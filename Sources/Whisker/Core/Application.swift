import Foundation

/// How the application renders to the terminal
public enum RenderMode {
    /// Takes over the full screen using the alternate buffer
    case fullscreen
    /// Renders in-place in the normal scrollback (like bun create, clack, Ink)
    case inline
}

/// The main application that runs the terminal UI
public final class Application {
    /// Shared instance for state updates
    public static var shared: Application?

    /// The terminal backend
    let backend: TerminalBackend

    /// Root node of the view tree
    var rootNode: Node?

    /// Currently focused node
    var focusedNode: Node?

    /// Index of the focused node among all focusable nodes (survives rebuilds)
    var focusedIndex: Int = 0

    /// Whether an update is scheduled
    var updateScheduled = false

    /// Whether the app is running
    var isRunning = false

    /// The root view builder
    let rootViewBuilder: () -> any View

    /// How many lines the previous inline render occupied
    var lastRenderedLineCount: Int = 0

    /// The content row where the cursor was left after focus positioning
    var lastCursorContentRow: Int = 0

    /// Whether the first inline render has occurred
    var isFirstInlineRender: Bool = true

    // MARK: - Initialization

    public init<V: View>(mode: RenderMode = .fullscreen, backend: TerminalBackend = ANSIBackend(), @ViewBuilder rootView: @escaping () -> V) {
        self.backend = backend
        self.backend.renderMode = mode
        self.rootViewBuilder = rootView
        Application.shared = self
    }

    // MARK: - Running

    /// Start the application
    public func run() throws {
        try backend.setup()
        defer {
            // In inline mode, move cursor to bottom of content before teardown
            if backend.renderMode == .inline && lastRenderedLineCount > 0 {
                let rowsDown = (lastRenderedLineCount - 1) - lastCursorContentRow
                if rowsDown > 0 {
                    backend.writeRaw("\u{1b}[\(rowsDown)B")
                }
                backend.flush()
            }
            backend.teardown()
            Application.shared = nil
        }

        isRunning = true

        // Initial build
        rebuild()

        // Initial render
        render()

        // Main loop
        runLoop()
    }

    /// Schedule an update on the next run loop iteration
    public func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
    }

    /// Stop the application and exit the run loop
    public func quit() {
        isRunning = false
    }

    // MARK: - Private

    private func runLoop() {
        // Use a simple synchronous input loop
        while isRunning {
            // Check for input (non-blocking would be better but this works)
            if let event = readInput() {
                handleEvent(event)
            }

            // Process updates if scheduled
            if updateScheduled {
                updateScheduled = false
                rebuild()
                render()
            }

            // Small sleep to avoid busy-waiting
            Thread.sleep(forTimeInterval: 0.016) // ~60fps
        }
    }

    private func readInput() -> TerminalEvent? {
        // Simple blocking read with timeout
        var buffer = [UInt8](repeating: 0, count: 16)

        // Set up non-blocking read
        let flags = fcntl(STDIN_FILENO, F_GETFL)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }

        let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)
        guard bytesRead > 0 else { return nil }

        return parseInput(Array(buffer.prefix(bytesRead)))
    }

    private func parseInput(_ bytes: [UInt8]) -> TerminalEvent? {
        guard !bytes.isEmpty else { return nil }

        if bytes.count == 1 {
            let byte = bytes[0]
            switch byte {
            case 3: // Ctrl+C
                isRunning = false
                return nil
            case 9: return .key(KeyEvent(key: .tab))
            case 13: return .key(KeyEvent(key: .enter))
            case 27: return .key(KeyEvent(key: .escape))
            case 127: return .key(KeyEvent(key: .backspace))
            case 32...126:
                return .key(KeyEvent(key: .char(Character(UnicodeScalar(byte)))))
            default:
                return nil
            }
        }

        // Escape sequences
        if bytes[0] == 27 && bytes.count >= 3 && bytes[1] == 91 {
            switch bytes[2] {
            case 65: return .key(KeyEvent(key: .up))
            case 66: return .key(KeyEvent(key: .down))
            case 67: return .key(KeyEvent(key: .right))
            case 68: return .key(KeyEvent(key: .left))
            case 90: return .key(KeyEvent(key: .tab, modifiers: .shift)) // Shift+Tab
            default: break
            }
        }

        return nil
    }

    private func handleEvent(_ event: TerminalEvent) {
        switch event {
        case .key(let keyEvent):
            handleKey(keyEvent)
        case .resize(let size):
            // Relayout and rerender
            if let root = rootNode {
                layout(root, in: Rect(origin: .zero, size: size))
            }
            render()
        case .mouse:
            break // Not implemented yet
        }
    }

    private func handleKey(_ event: KeyEvent) {
        // Tab / arrow key navigation
        if event.key == .tab || event.key == .up || event.key == .down {
            if event.key == .up || (event.key == .tab && event.modifiers.contains(.shift)) {
                moveFocusPrevious()
            } else {
                moveFocusNext()
            }
            render()
            return
        }

        // Pass to focused node
        if let focused = focusedNode {
            deliverKeyToNode(focused, event: event)
            render()
        }
    }

    private func deliverKeyToNode(_ node: Node, event: KeyEvent) {
        // Nodes can have key handlers attached
        if let handler = node.stateStorage["_keyHandler"] as? (KeyEvent) -> Void {
            handler(event)
        }
    }

    private func moveFocusNext() {
        let focusables = allFocusableNodes()
        guard !focusables.isEmpty else { return }

        focusedNode?.isFocused = false
        focusedIndex = (focusedIndex + 1) % focusables.count
        focusedNode = focusables[focusedIndex]
        focusedNode?.isFocused = true
    }

    private func moveFocusPrevious() {
        let focusables = allFocusableNodes()
        guard !focusables.isEmpty else { return }

        focusedNode?.isFocused = false
        focusedIndex = (focusedIndex - 1 + focusables.count) % focusables.count
        focusedNode = focusables[focusedIndex]
        focusedNode?.isFocused = true
    }

    // MARK: - Building

    private func rebuild() {
        let view = rootViewBuilder()
        rootNode = buildNode(from: view)

        // Layout
        let terminalSize = backend.size
        if let root = rootNode {
            switch backend.renderMode {
            case .fullscreen:
                layout(root, in: Rect(origin: .zero, size: terminalSize))
            case .inline:
                // Use terminal width but let height be determined by content
                let proposal = ProposedSize(
                    width: .exactly(terminalSize.width),
                    height: .unconstrained
                )
                let contentSize: Size
                if let layoutFn = root.layout {
                    let (size, _) = layoutFn(proposal, root.children)
                    contentSize = size
                } else {
                    contentSize = Size(width: terminalSize.width, height: 1)
                }
                layout(root, in: Rect(origin: .zero, size: Size(width: terminalSize.width, height: contentSize.height)))
            }
        }

        // Restore focus to the same index position after rebuild
        restoreFocus()
    }

    /// Collect all focusable nodes in tree order
    private func allFocusableNodes() -> [Node] {
        guard let root = rootNode else { return [] }
        var result: [Node] = []
        root.traverse { node in
            if node.isFocusable {
                result.append(node)
            }
        }
        return result
    }

    /// Restore focus to the node at focusedIndex
    private func restoreFocus() {
        let focusables = allFocusableNodes()
        guard !focusables.isEmpty else {
            focusedNode = nil
            return
        }
        let index = min(focusedIndex, focusables.count - 1)
        focusedNode = focusables[index]
        focusedNode?.isFocused = true
    }

    private func buildNode(from view: any View) -> Node {
        let node = Node(viewType: type(of: view))

        // Set up node context for @State access
        let previousNode = NodeContext.current
        NodeContext.current = node
        defer { NodeContext.current = previousNode }

        // Build based on view type using protocol checks for generics
        if let text = view as? Text {
            buildTextNode(node, text: text)
        } else if let vstack = view as? any _VStackProtocol {
            buildVStackNode(node, content: vstack._content, alignment: vstack._alignment, spacing: vstack._spacing)
        } else if let hstack = view as? any _HStackProtocol {
            buildHStackNode(node, content: hstack._content, alignment: hstack._alignment, spacing: hstack._spacing)
        } else if let textField = view as? TextField {
            buildTextFieldNode(node, textField: textField)
        } else if let secureField = view as? SecureField {
            buildSecureFieldNode(node, secureField: secureField)
        } else if let button = view as? Button {
            buildButtonNode(node, button: button)
        } else if let tupleView = view as? any _TupleViewProtocol {
            // TupleView: extract children and add them directly
            let children = extractViews(from: tupleView._tupleValue)
            for childView in children {
                node.addChild(buildNode(from: childView))
            }
            // Default vertical layout for bare TupleViews
            let layoutEngine = VStackLayout(alignment: .leading, spacing: 0)
            node.stateStorage["_placeChildren"] = { [weak node] (bounds: Rect) in
                guard let node = node else { return }
                let children = node.children.map { LayoutChild(node: $0) }
                layoutEngine.placeChildren(in: bounds, children: children)
            }
            node.layout = { [weak node] proposal, _ in
                guard let node = node else { return (.zero, []) }
                let children = node.children.map { LayoutChild(node: $0) }
                return (layoutEngine.sizeThatFits(proposal: proposal, children: children), [])
            }
        } else {
            // Custom view or unknown: try to get body and recurse
            buildCompositeNode(node, view: view)
        }

        return node
    }

    private func buildTextNode(_ node: Node, text: Text) {
        node.render = { [text] frame, buffer in
            let style = text.style
            let content = text.content
            for (i, char) in content.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: text.content.count)
            let height = proposal.height.resolve(with: 1)
            return (Size(width: width, height: height), [])
        }
    }

    private func buildVStackNode(_ node: Node, content: Any, alignment: HorizontalAlignment, spacing: Int) {
        let children = extractViews(from: content)
        for childView in children {
            node.addChild(buildNode(from: childView))
        }

        let layoutEngine = VStackLayout(alignment: alignment, spacing: spacing)

        node.stateStorage["_placeChildren"] = { [weak node] (bounds: Rect) in
            guard let node = node else { return }
            let children = node.children.map { LayoutChild(node: $0) }
            layoutEngine.placeChildren(in: bounds, children: children)
        }

        node.layout = { [weak node] proposal, _ in
            guard let node = node else { return (.zero, []) }
            let children = node.children.map { LayoutChild(node: $0) }
            return (layoutEngine.sizeThatFits(proposal: proposal, children: children), [])
        }
    }

    private func buildHStackNode(_ node: Node, content: Any, alignment: VerticalAlignment, spacing: Int) {
        let children = extractViews(from: content)
        for childView in children {
            node.addChild(buildNode(from: childView))
        }

        let layoutEngine = HStackLayout(alignment: alignment, spacing: spacing)

        node.stateStorage["_placeChildren"] = { [weak node] (bounds: Rect) in
            guard let node = node else { return }
            let children = node.children.map { LayoutChild(node: $0) }
            layoutEngine.placeChildren(in: bounds, children: children)
        }

        node.layout = { [weak node] proposal, _ in
            guard let node = node else { return (.zero, []) }
            let children = node.children.map { LayoutChild(node: $0) }
            return (layoutEngine.sizeThatFits(proposal: proposal, children: children), [])
        }
    }

    private func buildTextFieldNode(_ node: Node, textField: TextField) {
        node.isFocusable = true

        // Store the binding getter/setter in node for access during key handling
        node.stateStorage["_getText"] = textField.getText
        node.stateStorage["_setText"] = textField.setText
        node.stateStorage["_placeholder"] = textField.placeholder
        node.stateStorage["_cursorPosition"] = textField.getText().count

        // Key handler
        node.stateStorage["_keyHandler"] = { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            guard let getText = node.stateStorage["_getText"] as? () -> String,
                  let setText = node.stateStorage["_setText"] as? (String) -> Void else { return }

            var text = getText()
            var cursor = node.stateStorage["_cursorPosition"] as? Int ?? text.count

            switch event.key {
            case .char(let c):
                let index = text.index(text.startIndex, offsetBy: min(cursor, text.count))
                text.insert(c, at: index)
                cursor += 1
            case .backspace:
                if cursor > 0 && !text.isEmpty {
                    let index = text.index(text.startIndex, offsetBy: cursor - 1)
                    text.remove(at: index)
                    cursor -= 1
                }
            case .delete:
                if cursor < text.count {
                    let index = text.index(text.startIndex, offsetBy: cursor)
                    text.remove(at: index)
                }
            case .left:
                cursor = max(0, cursor - 1)
            case .right:
                cursor = min(text.count, cursor + 1)
            case .home:
                cursor = 0
            case .end:
                cursor = text.count
            default:
                break
            }

            setText(text)
            node.stateStorage["_cursorPosition"] = cursor
            Application.shared?.scheduleUpdate()
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let getText = node.stateStorage["_getText"] as? () -> String
            let placeholder = node.stateStorage["_placeholder"] as? String ?? ""
            let text = getText?() ?? ""

            let displayText = text.isEmpty ? placeholder : text
            let style: Style = text.isEmpty
                ? Style(foreground: .brightBlack)
                : .default

            // Draw text content
            for (i, char) in displayText.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { [weak node] proposal, _ in
            guard let node = node else { return (.zero, []) }
            let getText = node.stateStorage["_getText"] as? () -> String
            let placeholder = node.stateStorage["_placeholder"] as? String ?? ""
            let text = getText?() ?? ""
            let displayText = text.isEmpty ? placeholder : text
            let width = proposal.width.resolve(with: displayText.count)
            return (Size(width: width, height: 1), [])
        }
    }

    private func buildSecureFieldNode(_ node: Node, secureField: SecureField) {
        // SecureField is just like TextField but masks the display
        node.isFocusable = true
        node.stateStorage["_getText"] = secureField.getText
        node.stateStorage["_setText"] = secureField.setText
        node.stateStorage["_placeholder"] = secureField.placeholder
        node.stateStorage["_cursorPosition"] = secureField.getText().count
        node.stateStorage["_isSecure"] = true

        // Reuse TextField key handler
        node.stateStorage["_keyHandler"] = { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            guard let getText = node.stateStorage["_getText"] as? () -> String,
                  let setText = node.stateStorage["_setText"] as? (String) -> Void else { return }

            var text = getText()
            var cursor = node.stateStorage["_cursorPosition"] as? Int ?? text.count

            switch event.key {
            case .char(let c):
                let index = text.index(text.startIndex, offsetBy: min(cursor, text.count))
                text.insert(c, at: index)
                cursor += 1
            case .backspace:
                if cursor > 0 && !text.isEmpty {
                    let index = text.index(text.startIndex, offsetBy: cursor - 1)
                    text.remove(at: index)
                    cursor -= 1
                }
            case .left:
                cursor = max(0, cursor - 1)
            case .right:
                cursor = min(text.count, cursor + 1)
            default:
                break
            }

            setText(text)
            node.stateStorage["_cursorPosition"] = cursor
            Application.shared?.scheduleUpdate()
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let getText = node.stateStorage["_getText"] as? () -> String
            let placeholder = node.stateStorage["_placeholder"] as? String ?? ""
            let text = getText?() ?? ""
            let masked = String(repeating: "\u{2022}", count: text.count)
            let displayText = text.isEmpty ? placeholder : masked
            let style: Style = text.isEmpty
                ? Style(foreground: .brightBlack)
                : .default

            for (i, char) in displayText.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let width = proposal.width.resolve(with: 20)
            return (Size(width: width, height: 1), [])
        }
    }

    private func buildButtonNode(_ node: Node, button: Button) {
        node.isFocusable = true
        node.stateStorage["_action"] = button.action
        node.stateStorage["_label"] = button.label

        node.stateStorage["_keyHandler"] = { [weak node] (event: KeyEvent) in
            guard let node = node else { return }
            if event.key == .enter || event.key == .char(" ") {
                if let action = node.stateStorage["_action"] as? () -> Void {
                    action()
                }
            }
        }

        node.render = { [weak node] frame, buffer in
            guard let node = node else { return }
            let label = node.stateStorage["_label"] as? String ?? "Button"

            let style: Style = node.isFocused
                ? Style(foreground: .black, background: .white, attributes: [.bold])
                : Style(foreground: .white)

            let text = "[ \(label) ]"
            for (i, char) in text.prefix(frame.width).enumerated() {
                buffer.draw(char, at: Position(x: frame.x + i, y: frame.y), style: style)
            }
        }

        node.layout = { proposal, _ in
            let label = button.label
            let width = proposal.width.resolve(with: label.count + 4) // "[ label ]"
            return (Size(width: width, height: 1), [])
        }
    }

    private func buildCompositeNode(_ node: Node, view: any View) {
        // Use Mirror to access body
        let mirror = Mirror(reflecting: view)

        // Check if it's a tuple view (from ViewBuilder)
        if let value = mirror.children.first?.value {
            if let tupleView = value as? any View {
                let childNode = buildNode(from: tupleView)
                node.addChild(childNode)
            } else {
                // It's a tuple of views
                let views = extractViews(from: value)
                for childView in views {
                    let childNode = buildNode(from: childView)
                    node.addChild(childNode)
                }
            }
        }

        // Layout passes through to children
        node.layout = { [weak node] proposal, _ in
            guard let node = node, let firstChild = node.children.first else {
                return (.zero, [])
            }
            let childLayout = LayoutChild(node: firstChild)
            let size = childLayout.sizeThatFits(proposal)
            return (size, [])
        }
    }

    private func extractViews(from value: Any) -> [any View] {
        // If it's a TupleView, unwrap to get the inner tuple
        if let tupleView = value as? any _TupleViewProtocol {
            return extractViews(from: tupleView._tupleValue)
        }

        // Mirror the value to extract child views
        var views: [any View] = []
        let mirror = Mirror(reflecting: value)

        for child in mirror.children {
            if let view = child.value as? any View {
                views.append(view)
            }
        }

        // If no children found via mirror, try direct cast
        if views.isEmpty {
            if let view = value as? any View {
                views.append(view)
            }
        }

        return views
    }

    // MARK: - Layout

    private func layout(_ node: Node, in bounds: Rect) {
        node.frame = bounds

        // If this node has a layout engine (VStack/HStack/ZStack), use it to place children
        if let placeChildren = node.stateStorage["_placeChildren"] as? (Rect) -> Void {
            placeChildren(bounds)
            // Recurse into children whose frames were set by the layout engine
            for child in node.children {
                layout(child, in: child.frame)
            }
        } else {
            // Default: pass bounds through to children (composite/passthrough nodes)
            for child in node.children {
                layout(child, in: bounds)
            }
        }
    }

    // MARK: - Rendering

    private func render() {
        guard let root = rootNode else { return }

        var buffer = RenderBuffer()

        // Render tree into buffer
        renderNode(root, into: &buffer)

        switch backend.renderMode {
        case .fullscreen:
            renderFullscreen(buffer)
        case .inline:
            renderInline(buffer)
        }
    }

    private func renderFullscreen(_ buffer: RenderBuffer) {
        // Clear screen
        backend.clearScreen()

        // Write to terminal
        backend.write(buffer.commands)

        // Position the real cursor at the focused text field
        positionCursorAtFocus()

        backend.flush()
    }

    private func renderInline(_ buffer: RenderBuffer) {
        // Determine content height from buffer
        let contentHeight: Int
        if buffer.commands.isEmpty {
            contentHeight = 0
        } else {
            contentHeight = (buffer.commands.map { $0.position.y }.max() ?? 0) + 1
        }

        // If not the first render, move cursor back up to overwrite previous output
        // Use lastCursorContentRow (where cursor actually is) instead of lastRenderedLineCount
        if !isFirstInlineRender {
            backend.clearLines(lastCursorContentRow)
        }
        isFirstInlineRender = false

        // Build line strings from render commands
        for row in 0..<contentHeight {
            let rowCommands = buffer.commands
                .filter { $0.position.y == row }
                .sorted { $0.position.x < $1.position.x }

            var line = ""
            var currentStyle: Style?

            // Fill in characters at their positions
            var col = 0
            for cmd in rowCommands {
                // Pad with spaces to reach this command's position
                if cmd.position.x > col {
                    if currentStyle != nil {
                        line += ANSI.reset
                        currentStyle = nil
                    }
                    line += String(repeating: " ", count: cmd.position.x - col)
                    col = cmd.position.x
                }

                // Apply style if changed
                if currentStyle == nil || currentStyle! != cmd.cell.style {
                    line += ANSI.style(cmd.cell.style)
                    currentStyle = cmd.cell.style
                }

                line += String(cmd.cell.char)
                col += 1
            }

            // Reset style and erase to end of line
            line += ANSI.reset
            line += "\u{1b}[K" // erase to end of line

            backend.writeRaw(line)
            if row < contentHeight - 1 {
                backend.writeRaw("\r\n")
            }
        }

        lastRenderedLineCount = contentHeight

        // Position the real cursor at the focused text field
        // In inline mode we need to move the cursor relatively
        if let focused = focusedNode,
           focused.stateStorage["_getText"] != nil {
            let getText = focused.stateStorage["_getText"] as? () -> String
            let text = getText?() ?? ""
            let cursorX = focused.frame.x + text.count
            let cursorY = focused.frame.y
            // Move cursor from end of content (last row) to focused row
            let rowsUp = (contentHeight - 1) - cursorY
            if rowsUp > 0 {
                backend.writeRaw("\u{1b}[\(rowsUp)A")
            }
            backend.writeRaw("\r")
            if cursorX > 0 {
                backend.writeRaw("\u{1b}[\(cursorX)C")
            }
            backend.setCursorVisible(true)
            lastCursorContentRow = cursorY
        } else {
            backend.setCursorVisible(false)
            lastCursorContentRow = contentHeight - 1
        }

        backend.flush()
    }

    private func positionCursorAtFocus() {
        if let focused = focusedNode,
           focused.stateStorage["_getText"] != nil {
            let getText = focused.stateStorage["_getText"] as? () -> String
            let text = getText?() ?? ""
            let cursorX = focused.frame.x + text.count
            backend.moveCursor(to: Position(x: cursorX, y: focused.frame.y))
            backend.setCursorVisible(true)
        } else {
            backend.setCursorVisible(false)
        }
    }

    private func renderNode(_ node: Node, into buffer: inout RenderBuffer) {
        // Render this node
        if let renderFn = node.render {
            renderFn(node.frame, &buffer)
        }

        // Render children
        for child in node.children {
            renderNode(child, into: &buffer)
        }
    }
}
