import Foundation

/// How the application renders to the terminal
public enum RenderMode {
    /// Takes over the full screen using the alternate buffer
    case fullscreen
    /// Renders in-place in the normal scrollback (like bun create, clack, Ink)
    case inline
}

public final class Application {
    public static var shared: Application?

    let backend: TerminalBackend
    var rootNode: Node?
    var focusedNode: Node?
    var focusedIndex: Int = 0
    var updateScheduled = false
    var isRunning = false
    let rootViewBuilder: () -> any View

    private let viewBuilder = NodeViewBuilder()
    private let inlineRenderer = InlineRenderer()

    public init<V: View>(mode: RenderMode = .fullscreen, backend: TerminalBackend = ANSIBackend(), @ViewBuilder rootView: @escaping () -> V) {
        self.backend = backend
        self.backend.renderMode = mode
        self.rootViewBuilder = rootView
        Application.shared = self
    }

    public func run() throws {
        try backend.setup()
        defer {
            if backend.renderMode == .inline && inlineRenderer.lastRenderedLineCount > 0 {
                let rowsDown = (inlineRenderer.lastRenderedLineCount - 1) - inlineRenderer.lastCursorContentRow
                if rowsDown > 0 {
                    backend.writeRaw("\u{1b}[\(rowsDown)B")
                }
                backend.flush()
            }
            backend.teardown()
            Application.shared = nil
        }

        isRunning = true
        rebuild()
        render()
        runLoop()
    }

    public func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
    }

    public func quit() {
        isRunning = false
    }

    private func runLoop() {
        while isRunning {
            if let event = readInput() {
                handleEvent(event)
            }

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
        var buffer = [UInt8](repeating: 0, count: 16)

        let flags = fcntl(STDIN_FILENO, F_GETFL)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(STDIN_FILENO, F_SETFL, flags) }

        let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)
        guard bytesRead > 0 else { return nil }

        return parseInput(Array(buffer.prefix(bytesRead)))
    }

    private func parseInput(_ bytes: [UInt8]) -> TerminalEvent? {
        guard !bytes.isEmpty else { return nil }
        if bytes.count == 1, bytes[0] == 3 {
            isRunning = false
            return nil
        }
        return InputParser.parse(bytes)
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
            break // TODO: Implement mouse event handling
        }
    }

    private func handleKey(_ event: KeyEvent) {
        if event.key == .tab || event.key == .up || event.key == .down {
            if event.key == .up || (event.key == .tab && event.modifiers.contains(.shift)) {
                FocusManager.moveFocusPrevious(root: rootNode, focusedIndex: &focusedIndex, focusedNode: &focusedNode)
            } else {
                FocusManager.moveFocusNext(root: rootNode, focusedIndex: &focusedIndex, focusedNode: &focusedNode)
            }
            render()
            return
        }

        if let focused = focusedNode {
            deliverKeyToNode(focused, event: event)
            render()
        }
    }

    private func deliverKeyToNode(_ node: Node, event: KeyEvent) {
        if let handler = node[.keyHandler] {
            handler(event)
        }
    }

    private func rebuild() {
        let view = rootViewBuilder()
        rootNode = viewBuilder.buildNode(from: view)

        let terminalSize = backend.size
        if let root = rootNode {
            switch backend.renderMode {
            case .fullscreen:
                layout(root, in: Rect(origin: .zero, size: terminalSize))
            case .inline:
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

        FocusManager.restoreFocus(root: rootNode, focusedIndex: &focusedIndex, focusedNode: &focusedNode)
    }

    private func layout(_ node: Node, in bounds: Rect) {
        node.frame = bounds

        if let placeChildren = node[.placeChildren] {
            placeChildren(bounds)
            for child in node.children {
                layout(child, in: child.frame)
            }
        } else {
            for child in node.children {
                layout(child, in: bounds)
            }
        }
    }

    private func render() {
        guard let root = rootNode else { return }

        var buffer = RenderBuffer()
        renderNode(root, into: &buffer)

        switch backend.renderMode {
        case .fullscreen:
            renderFullscreen(buffer)
        case .inline:
            inlineRenderer.render(buffer, backend: backend, focusedNode: focusedNode)
        }
    }

    private func renderFullscreen(_ buffer: RenderBuffer) {
        backend.clearScreen()
        backend.write(buffer.commands)
        positionCursorAtFocus()

        backend.flush()
    }

    private func positionCursorAtFocus() {
        if let focused = focusedNode,
           focused[.getText] != nil {
            let cursorX = focused.frame.x + (focused[.cursorPosition] ?? 0)
            backend.moveCursor(to: Position(x: cursorX, y: focused.frame.y))
            backend.setCursorVisible(true)
        } else {
            backend.setCursorVisible(false)
        }
    }

    private func renderNode(_ node: Node, into buffer: inout RenderBuffer) {
        if let renderFn = node.render {
            renderFn(node.frame, &buffer)
        }

        for child in node.children {
            renderNode(child, into: &buffer)
        }
    }
}
