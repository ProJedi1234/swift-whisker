import CWhiskerTestSupport
import Foundation
import XCTest

@testable import Whisker

#if os(Linux)
import Glibc
#else
import Darwin
#endif

final class TerminalLifecycleTests: XCTestCase {
    private struct Fixture {
        let pid: pid_t
        let controller: Int32
        let terminal: Int32
    }

    private var fixtureExecutable: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/WhiskerLifecycleFixture")
            .path
    }

    func testPartialSetupFailureStillAttemptsTeardown() {
        let backend = FailingSetupBackend()
        let app = Application(backend: backend) { EmptyView() }

        XCTAssertThrowsError(try app.run())
        XCTAssertEqual(backend.setupCount, 1)
        XCTAssertEqual(backend.teardownCount, 1)
    }

    func testANSIBackendTeardownIsIdempotent() throws {
        let fixture = try spawn(mode: "double-teardown")
        defer { forceCleanup(fixture) }

        let output = try readUntil("double-teardown-complete", from: fixture.controller)
        XCTAssertEqual(output.components(separatedBy: "\u{1b}[?2004h").count - 1, 1)
        XCTAssertEqual(output.components(separatedBy: "\u{1b}[?2004l").count - 1, 1)
        XCTAssertEqual(output.components(separatedBy: "\u{1b}[?25h").count - 1, 1)
        XCTAssertEqual(output.components(separatedBy: "\u{1b}[?1049l").count - 1, 1)
        try assertCookedMode(fixture.controller)
    }

    func testTerminatingSignalsRetainConventionalProcessStatus() throws {
        for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: fixtureExecutable)
            process.arguments = ["mock"]
            try process.run()
            usleep(100_000)
            XCTAssertEqual(kill(process.processIdentifier, signalNumber), 0)
            process.waitUntilExit()

            XCTAssertEqual(process.terminationReason, .uncaughtSignal)
            XCTAssertEqual(process.terminationStatus, signalNumber)
        }
    }

    func testTerminatingSignalRestoresFullscreenTerminal() throws {
        let fixture = try spawn(mode: "fullscreen")
        defer { forceCleanup(fixture) }

        var output = try readUntil("\u{1b}[?1049h", from: fixture.controller)
        XCTAssertEqual(kill(fixture.pid, SIGTERM), 0)
        output += try readUntil("\u{1b}[?1049l", from: fixture.controller)

        XCTAssertTrue(output.contains("\u{1b}[?25h"))
        XCTAssertTrue(output.contains("\u{1b}[?2004l"))
        XCTAssertTrue(output.contains("\u{1b}[0m"))
        try assertCookedMode(fixture.controller)
    }

    func testInlineSignalCleanupDoesNotUseAlternateScreen() throws {
        let fixture = try spawn(mode: "inline")
        defer { forceCleanup(fixture) }

        var output = try readUntil("\u{1b}[?25l", from: fixture.controller)
        XCTAssertEqual(kill(fixture.pid, SIGTERM), 0)
        output += try readUntil("\u{1b}[?25h", from: fixture.controller)

        XCTAssertFalse(output.contains("\u{1b}[?1049h"))
        XCTAssertFalse(output.contains("\u{1b}[?1049l"))
        XCTAssertTrue(output.contains("\u{1b}[?25h"))
        try assertCookedMode(fixture.controller)
    }

    func testSuspendRestoresThenResumeReentersConfiguredMode() throws {
        let fixture = try spawn(mode: "fullscreen")
        defer { forceCleanup(fixture) }

        var output = try readUntil("\u{1b}[?1049h", from: fixture.controller)
        XCTAssertEqual(kill(fixture.pid, SIGTSTP), 0)
        output += try readUntil("\u{1b}[?1049l", from: fixture.controller)

        XCTAssertTrue(output.contains("\u{1b}[?1049l"))
        try assertCookedMode(fixture.controller)

        XCTAssertEqual(kill(fixture.pid, SIGCONT), 0)
        let resumedOutput = try readUntil("\u{1b}[?2004h", from: fixture.controller)
        XCTAssertTrue(resumedOutput.contains("\u{1b}[?1049h"))
        XCTAssertTrue(resumedOutput.contains("\u{1b}[?2004h"))
        XCTAssertTrue(resumedOutput.contains("\u{1b}[?25l"))
        try assertRawModeWithSignals(fixture.controller)

        XCTAssertEqual(kill(fixture.pid, SIGTERM), 0)
        _ = try readUntil("\u{1b}[?1049l", from: fixture.controller)
        try assertCookedMode(fixture.controller)
    }

    func testSuccessiveKeystrokesRemainReadableAfterInputPause() throws {
        let fixture = try spawn(mode: "input")
        defer { forceCleanup(fixture) }

        _ = try readUntil("\u{1b}[?25h", from: fixture.controller)
        try writeInput("a", to: fixture.controller)
        _ = try readUntil("a", from: fixture.controller)

        // Exceed the terminal's VTIME interval. The following key must still be read;
        // a zero-byte raw-mode read during this pause is not EOF.
        usleep(200_000)
        try writeInput("b", to: fixture.controller)
        let output = try readUntil("ab", from: fixture.controller)

        XCTAssertTrue(output.contains("ab"))
    }

    private func spawn(mode: String) throws -> Fixture {
        var pid: pid_t = 0
        var controller: Int32 = -1
        var terminal: Int32 = -1
        let result = fixtureExecutable.withCString { executable in
            mode.withCString { modePointer in
                whisker_test_spawn_pty(executable, modePointer, &pid, &controller, &terminal)
            }
        }
        guard result == 0 else {
            throw TerminalSystemError(operation: "spawn PTY fixture", code: result)
        }
        return Fixture(pid: pid, controller: controller, terminal: terminal)
    }

    private func forceCleanup(_ fixture: Fixture) {
        _ = kill(fixture.pid, SIGKILL)
        _ = whisker_test_wait_for_signal_exit(fixture.pid, SIGKILL)
        close(fixture.controller)
        close(fixture.terminal)
    }

    private func readUntil(_ marker: String, from descriptor: Int32, timeout: TimeInterval = 3) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var output = ""
        while Date() < deadline {
            output += readAvailable(from: descriptor)
            if output.contains(marker) { return output }
            usleep(10_000)
        }
        XCTFail("Timed out waiting for terminal output marker \(String(reflecting: marker)); output: \(String(reflecting: output))")
        return output
    }

    private func readAvailable(from descriptor: Int32) -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer.prefix(count))
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func writeInput(_ input: String, to descriptor: Int32) throws {
        let bytes = Array(input.utf8)
        let written = bytes.withUnsafeBytes { rawBuffer in
            write(descriptor, rawBuffer.baseAddress, rawBuffer.count)
        }
        guard written == bytes.count else {
            throw TerminalSystemError(operation: "write PTY input", code: errno)
        }
    }

    private func assertCookedMode(_ descriptor: Int32, file: StaticString = #filePath, line: UInt = #line) throws {
        let deadline = Date().addingTimeInterval(1)
        var attributes = termios()
        repeat {
            guard tcgetattr(descriptor, &attributes) == 0 else {
                throw TerminalSystemError(operation: "inspect cooked terminal mode", code: errno)
            }
            if attributes.c_lflag & tcflag_t(ICANON) != 0,
               attributes.c_lflag & tcflag_t(ECHO) != 0 {
                return
            }
            usleep(10_000)
        } while Date() < deadline

        XCTAssertNotEqual(attributes.c_lflag & tcflag_t(ICANON), 0, file: file, line: line)
        XCTAssertNotEqual(attributes.c_lflag & tcflag_t(ECHO), 0, file: file, line: line)
    }

    private func assertRawModeWithSignals(_ descriptor: Int32, file: StaticString = #filePath, line: UInt = #line) throws {
        var attributes = termios()
        guard tcgetattr(descriptor, &attributes) == 0 else {
            throw TerminalSystemError(operation: "inspect raw terminal mode", code: errno)
        }
        XCTAssertEqual(attributes.c_lflag & tcflag_t(ICANON), 0, file: file, line: line)
        XCTAssertNotEqual(attributes.c_lflag & tcflag_t(ISIG), 0, file: file, line: line)
    }
}

private final class FailingSetupBackend: TerminalBackend, @unchecked Sendable {
    enum ExpectedError: Error { case setup }

    var renderMode: RenderMode = .fullscreen
    var size = Size(width: 80, height: 24)
    var setupCount = 0
    var teardownCount = 0

    func write(_ commands: [RenderCommand]) {}
    func writeRaw(_ string: String) {}
    func flush() {}
    func moveCursor(to position: Position) {}
    func setCursorVisible(_ visible: Bool) {}
    func clearScreen() {}
    func clearLines(_ count: Int) {}

    func setup() throws {
        setupCount += 1
        throw ExpectedError.setup
    }

    func teardown() throws {
        teardownCount += 1
    }
}
