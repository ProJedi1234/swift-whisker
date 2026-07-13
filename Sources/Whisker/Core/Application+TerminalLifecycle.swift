import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

extension Application {
    func cleanupTerminal() throws {
        if backend.renderMode == .inline && inlineRenderer.lastRenderedLineCount > 0 {
            let rowsDown = (inlineRenderer.lastRenderedLineCount - 1) - inlineRenderer.lastCursorContentRow
            if rowsDown > 0 {
                backend.writeRaw("\u{1b}[\(rowsDown)B")
            }
            backend.flush()
        }
        try backend.teardown()
    }

    func handleSignal(_ signalNumber: Int32, coordinator: SignalCoordinator) throws {
        switch signalNumber {
        case SIGINT, SIGTERM, SIGHUP:
            do {
                try cleanupTerminal()
            } catch {
                reportLifecycleError(error)
            }

            coordinator.reraise(signalNumber)

        case SIGTSTP:
            var teardownError: Error?
            do {
                try cleanupTerminal()
            } catch {
                teardownError = error
                reportLifecycleError(error)
            }

            // Raise SIGSTOP rather than re-raising SIGTSTP: SIGTSTP is ignored for
            // orphaned process groups, but SIGSTOP always suspends. Because SIGSTOP is
            // uncatchable, our SIGTSTP handler stays installed across the stop/resume —
            // there is no disposition to reset beforehand or rearm afterward.
            guard kill(getpid(), SIGSTOP) == 0 else {
                throw TerminalSystemError(operation: "suspend process", code: errno)
            }

            // Execution continues here only after SIGCONT resumes the process.
            try backend.setup()
            inlineRenderer.reset()
            rebuild()
            render()

            if let teardownError { throw teardownError }

        default:
            break
        }
    }

    private func reportLifecycleError(_ error: Error) {
        let message = "Whisker terminal lifecycle error: \(error)\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
