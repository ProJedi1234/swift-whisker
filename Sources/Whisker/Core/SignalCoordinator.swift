#if os(macOS) || os(Linux)
import CWhiskerSignals
#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// Routes signals through a self-pipe so lifecycle work stays on the application thread.
///
/// The underlying C module keeps process-global state (one pipe, one saved-disposition
/// table), so only one coordinator may be installed at a time. Constructing a second
/// while one is live fails fast: `whisker_signals_install` returns `EBUSY`, surfaced here
/// as a thrown `TerminalSystemError`. This matches Whisker's single-`Application.shared`
/// model — a process runs one terminal UI at a time.
final class SignalCoordinator {
    let readFileDescriptor: Int32
    private var isInstalled = true

    init() throws {
        var descriptor: Int32 = -1
        let result = whisker_signals_install(&descriptor)
        guard result == 0 else {
            throw TerminalSystemError(operation: "install signal handlers", code: result)
        }
        readFileDescriptor = descriptor
    }

    deinit {
        if isInstalled {
            _ = whisker_signals_uninstall()
        }
    }

    func drain() throws -> [Int32] {
        var signals = [Int32](repeating: 0, count: 4)
        var count = 0
        let result = whisker_signals_drain(&signals, signals.count, &count)
        guard result == 0 else {
            throw TerminalSystemError(operation: "read signal pipe", code: result)
        }
        return Array(signals.prefix(count))
    }

    func reraise(_ signalNumber: Int32) -> Never {
        whisker_signals_reraise(signalNumber)
    }

    func uninstall() throws {
        guard isInstalled else { return }
        let result = whisker_signals_uninstall()
        isInstalled = false
        guard result == 0 else {
            throw TerminalSystemError(operation: "restore signal handlers", code: result)
        }
    }
}
#endif
