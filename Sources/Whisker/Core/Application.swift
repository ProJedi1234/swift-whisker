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
    private var inputParser: InputParser
    private let inputClock = ContinuousClock()
    /// Number of animated views (e.g. `ActivityIndicator`) in the current tree.
    /// When non-zero, the run loop keeps scheduling redraws.
    var animationTickCount = 0
    let rootViewBuilder: () -> any View

    /// Lock for synchronizing @State mutations from async contexts (e.g. .task closures)
    /// against the single-threaded rebuild pass. Uncontended in the common synchronous case.
    let stateLock = NSLock()

    private let viewBuilder = NodeViewBuilder()
    let inlineRenderer = InlineRenderer()

    public init<V: View>(
        mode: RenderMode = .fullscreen,
        backend: TerminalBackend = ANSIBackend(),
        escapeTimeout: Duration = .milliseconds(50),
        @ViewBuilder rootView: @escaping () -> V
    ) {
        self.backend = backend
        self.inputParser = InputParser(escapeTimeout: escapeTimeout)
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
            var needsRender = false

            for signalNumber in try signalCoordinator.drain() {
                try handleSignal(signalNumber, coordinator: signalCoordinator)
            }
            guard isRunning else { break }

            // Park until a keystroke arrives or a signal fires, instead of spinning at a
            // fixed 60fps. Both the terminal and the signal self-pipe wake poll() the
            // instant they have data, so this is where the loop spends its idle time.
            let stdinWasOpen = stdinOpen
            let stdinReady = try waitForActivity(
                signalReadFD: signalCoordinator.readFileDescriptor,
                inputDeadline: inputParser.nextDeadline
            )

            if stdinReady {
                needsRender = handleEvents(try readInput()) || needsRender
            } else if stdinWasOpen && !stdinOpen {
                needsRender = handleEvents(inputParser.finish()) || needsRender
            }
            needsRender = handleEvents(inputParser.flushExpired(at: inputClock.now)) || needsRender

            if updateScheduled {
                updateScheduled = false
                rebuild()
                render()
                needsRender = false
            } else if needsRender {
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
    private func waitForActivity(
        signalReadFD: Int32,
        inputDeadline: ContinuousClock.Instant?
    ) throws -> Bool {
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
        var timeoutMilliseconds: Int32
        if animationTickCount > 0 {
            timeoutMilliseconds = 16
        } else {
            timeoutMilliseconds = 50
        }
        if let inputDeadline {
            timeoutMilliseconds = min(
                timeoutMilliseconds,
                millisecondsUntil(inputDeadline, from: inputClock.now)
            )
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

    /// Cap stdin reads per run-loop cycle so a flooded pipe cannot starve layout/render.
    /// Leftover bytes remain buffered by the OS and are drained on subsequent cycles.
    private static let maxInputBytesPerCycle = 65_536

    private func readInput() throws -> [TerminalEvent] {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var events: [TerminalEvent] = []

        let flags = fcntl(STDIN_FILENO, F_GETFL)
        guard flags != -1 else {
            throw TerminalSystemError(operation: "fcntl(F_GETFL)", code: errno)
        }
        guard fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw TerminalSystemError(operation: "fcntl(F_SETFL, O_NONBLOCK)", code: errno)
        }

        var pendingError: Error?
        var bytesProcessed = 0
        while bytesProcessed < Self.maxInputBytesPerCycle {
            let bytesRead = read(STDIN_FILENO, &buffer, buffer.count)
            let readError = errno

            if bytesRead > 0 {
                bytesProcessed += bytesRead
                events.append(contentsOf: inputParser.feed(
                    Array(buffer.prefix(bytesRead)),
                    at: inputClock.now
                ))
                continue
            }

            if bytesRead == 0 {
                // In noncanonical mode VMIN is zero, so an empty read means there are no
                // more bytes available right now. POLLHUP, handled by waitForActivity,
                // is the authoritative EOF signal.
                break
            }

            if readError == EAGAIN || readError == EWOULDBLOCK || readError == EINTR {
                break
            }
            pendingError = TerminalSystemError(operation: "read terminal input", code: readError)
            break
        }

        guard fcntl(STDIN_FILENO, F_SETFL, flags) != -1 else {
            throw TerminalSystemError(operation: "fcntl(F_SETFL, restore)", code: errno)
        }
        if let pendingError { throw pendingError }
        return events
    }

    private func handleEvents(_ events: [TerminalEvent]) -> Bool {
        events.reduce(false) { handled, event in
            handleEvent(event) || handled
        }
    }

    private func handleEvent(_ event: TerminalEvent) -> Bool {
        switch event {
        case .key(let keyEvent):
            return handleKey(keyEvent)
        case .text(let text):
            return handleText(text, isPaste: false)
        case .paste(let text):
            return handleText(text, isPaste: true)
        case .resize(let size):
            // Relayout and rerender
            if let root = rootNode {
                layout(root, in: Rect(origin: .zero, size: size))
            }
            return true
        case .mouse:
            return false // TODO: Implement mouse event handling
        }
    }

    func handleKey(_ event: KeyEvent) -> Bool {
        switch event.key {
        case .tab, .up, .down:
            // Offer the key to the focused node first; only an unconsumed key
            // falls back to focus traversal.
            if dispatchKey(event, startingAt: focusedNode) { return true }
            if event.key == .up || (event.key == .tab && event.modifiers.contains(.shift)) {
                FocusManager.moveFocusPrevious(root: rootNode, focusedIndex: &focusedIndex, focusedNode: &focusedNode)
            } else {
                FocusManager.moveFocusNext(root: rootNode, focusedIndex: &focusedIndex, focusedNode: &focusedNode)
            }
            return true
        case .escape:
            // An unconsumed escape is dropped.
            return dispatchKey(event, startingAt: focusedNode)
        default:
            guard let focused = focusedNode else { return false }
            _ = dispatchKey(event, startingAt: focused)
            return true
        }
    }

    private func handleText(_ text: String, isPaste: Bool) -> Bool {
        guard let focused = focusedNode else { return false }
        if isPaste, let pasteHandler = focused[.pasteInputHandler] {
            pasteHandler(text)
        } else if let handler = focused[.textInputHandler] {
            handler(text)
        } else {
            for character in text {
                _ = dispatchKey(KeyEvent(key: .char(character)), startingAt: focused)
            }
        }
        return true
    }

    /// Offer a key event to `node`'s handler, bubbling up through ancestors
    /// until one consumes it. Bubbling is what lets a `.onKeyPress` wrapper
    /// receive keys on behalf of a focused `.focusable()` view or a focused
    /// descendant control. Returns `true` when some handler consumed the key.
    private func dispatchKey(_ event: KeyEvent, startingAt node: Node?) -> Bool {
        var current = node
        while let candidate = current {
            if let handler = candidate[.keyHandler], handler(event) {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    private func millisecondsUntil(
        _ deadline: ContinuousClock.Instant,
        from now: ContinuousClock.Instant
    ) -> Int32 {
        let duration = now.duration(to: deadline)
        if duration <= .zero { return 0 }
        let components = duration.components
        let millisecondsFromSeconds = components.seconds.multipliedReportingOverflow(by: 1_000)
        if millisecondsFromSeconds.overflow { return Int32.max }
        let fractionalMilliseconds = (components.attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
        let total = millisecondsFromSeconds.partialValue + fractionalMilliseconds
        return Int32(clamping: total)
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
            let cursorX = focused.frame.x + textInputCursorColumn(for: focused)
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
