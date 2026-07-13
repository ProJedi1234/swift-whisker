import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

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
    /// Cleared when stdin reaches EOF (e.g. redirected input hangs up) so the run loop
    /// stops polling a descriptor that would otherwise wake `poll()` forever. See
    /// `waitForActivity`.
    private var stdinOpen = true
    /// Number of animated views (e.g. `ActivityIndicator`) in the current tree.
    /// When non-zero, the run loop keeps scheduling redraws.
    var animationTickCount = 0
    let rootViewBuilder: () -> any View

    /// Lock for synchronizing @State mutations from async contexts (e.g. .task closures)
    /// against the single-threaded rebuild pass. Uncontended in the common synchronous case.
    let stateLock = NSLock()

    private let viewBuilder = NodeViewBuilder()
    let inlineRenderer = InlineRenderer()

    public init<V: View>(mode: RenderMode = .fullscreen, backend: TerminalBackend = ANSIBackend(), @ViewBuilder rootView: @escaping () -> V) {
        self.backend = backend
        self.backend.renderMode = mode
        self.rootViewBuilder = rootView
        Application.shared = self
    }

    public func run() throws {
        let signalCoordinator: SignalCoordinator
        do {
            signalCoordinator = try SignalCoordinator()
        } catch {
            Application.shared = nil
            throw error
        }
        var pendingError: Error?

        do {
            try backend.setup()
            isRunning = true
            rebuild()
            render()
            try runLoop(signalCoordinator: signalCoordinator)
        } catch {
            pendingError = error
        }

        isRunning = false
        rootNode?.cancelTasksRecursively()

        do {
            try cleanupTerminal()
        } catch {
            if pendingError == nil { pendingError = error }
        }

        do {
            try signalCoordinator.uninstall()
        } catch {
            if pendingError == nil { pendingError = error }
        }

        Application.shared = nil
        if let pendingError { throw pendingError }
    }

    public func scheduleUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
    }

    /// Stop the application and cancel any in-flight `.task` work.
    public func quit() {
        isRunning = false
        rootNode?.cancelTasksRecursively()
    }

    private func runLoop(signalCoordinator: SignalCoordinator) throws {
        while isRunning {
            for signalNumber in try signalCoordinator.drain() {
                try handleSignal(signalNumber, coordinator: signalCoordinator)
            }
            guard isRunning else { break }

            // Park until a keystroke arrives or a signal fires, instead of spinning at a
            // fixed 60fps. Both the terminal and the signal self-pipe wake poll() the
            // instant they have data, so this is where the loop spends its idle time.
            let stdinReady = try waitForActivity(signalReadFD: signalCoordinator.readFileDescriptor)

            if stdinReady, let event = try readInput() {
                handleEvent(event)
            }

            if updateScheduled {
                updateScheduled = false
                rebuild()
                render()
            }

            // Keep updating while animated views are present
            if animationTickCount > 0 {
                updateScheduled = true
            }
        }
    }

    /// Blocks until stdin or the signal self-pipe becomes readable, or the timeout elapses.
    /// Returns `true` when stdin has bytes waiting.
    ///
    /// Input and signals wake `poll()` immediately regardless of the timeout — the timeout
    /// only bounds how long we sleep waiting for work that carries *no* file-descriptor
    /// event: animation frames, and `@State` updates scheduled from async `.task` closures
    /// on another thread (those flip `updateScheduled` without touching any fd).
    private func waitForActivity(signalReadFD: Int32) throws -> Bool {
        // A negative fd makes poll() ignore that slot (revents cleared), so once stdin
        // hangs up we stop watching it without disturbing the fixed array layout that the
        // revents checks below rely on.
        var fds = [
            pollfd(fd: stdinOpen ? STDIN_FILENO : -1, events: Int16(POLLIN), revents: 0),
            pollfd(fd: signalReadFD, events: Int16(POLLIN), revents: 0)
        ]

        // The timeout only bounds work that carries no fd event: animation frames need a
        // ~60fps cadence; an idle screen sleeps longer, capped so cross-thread @State
        // updates from `.task` still surface. Animation drives redraws by setting
        // `updateScheduled`, so it must be checked on its own — keying the timeout off
        // `updateScheduled` would collapse the frame interval to zero and busy-spin.
        let timeoutMilliseconds: Int32
        if animationTickCount > 0 {
            timeoutMilliseconds = 16
        } else {
            timeoutMilliseconds = 50
        }

        let ready = poll(&fds, nfds_t(fds.count), timeoutMilliseconds)
        if ready == -1 {
            if errno == EINTR { return false }
            throw TerminalSystemError(operation: "poll terminal input", code: errno)
        }

        // POLLERR/POLLNVAL stay asserted on every poll(), so a broken descriptor would
        // spin the loop at full speed. Treat either as unrecoverable rather than looping.
        let errorFlags = Int16(POLLERR) | Int16(POLLNVAL)
        if (fds[1].revents & errorFlags) != 0 {
            throw TerminalSystemError(operation: "poll signal pipe", code: EIO)
        }
        if (fds[0].revents & errorFlags) != 0 {
            throw TerminalSystemError(operation: "poll terminal input", code: EIO)
        }

        // POLLHUP means stdin's source closed (e.g. redirected input reached EOF). It also
        // stays asserted, so once any buffered input (POLLIN) is drained, stop watching
        // stdin; signals and the timeout keep the loop alive.
        let stdinReadable = (fds[0].revents & Int16(POLLIN)) != 0
        if !stdinReadable && (fds[0].revents & Int16(POLLHUP)) != 0 {
            stdinOpen = false
        }
        return stdinReadable
    }

    private func readInput() throws -> TerminalEvent? {
        var buffer = [UInt8](repeating: 0, count: 16)

        let flags = fcntl(STDIN_FILENO, F_GETFL)
        guard flags != -1 else {
            throw TerminalSystemError(operation: "fcntl(F_GETFL)", code: errno)
        }
        guard fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw TerminalSystemError(operation: "fcntl(F_SETFL, O_NONBLOCK)", code: errno)
        }

        let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)
        let readError = errno
        guard fcntl(STDIN_FILENO, F_SETFL, flags) != -1 else {
            throw TerminalSystemError(operation: "fcntl(F_SETFL, restore)", code: errno)
        }

        if bytesRead == -1 {
            if readError == EAGAIN || readError == EWOULDBLOCK || readError == EINTR {
                return nil
            }
            throw TerminalSystemError(operation: "read terminal input", code: readError)
        }
        guard bytesRead > 0 else { return nil }

        return parseInput(Array(buffer.prefix(bytesRead)))
    }

    private func parseInput(_ bytes: [UInt8]) -> TerminalEvent? {
        guard !bytes.isEmpty else { return nil }
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

    func rebuild() {
        animationTickCount = 0
        let view = rootViewBuilder()
        let oldRoot = rootNode
        rootNode = viewBuilder.buildNode(from: view, existing: oldRoot)

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

    func render() {
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
