import Foundation
import XCTest

@testable import Whisker

/// Where `ANSIBackend` puts its bytes.
///
/// The routing is the point of these tests, not the escape sequences: a program whose
/// stdout is a contract (`result=$(tool ...)`) has to be able to render somewhere else,
/// and a regression here is silent — the frames still appear on a terminal where both
/// descriptors are the same device.
final class ANSIBackendTests: XCTestCase {
    private func drain(_ pipe: Pipe) -> String {
        String(decoding: pipe.fileHandleForReading.availableData, as: UTF8.self)
    }

    func testWritesToTheSuppliedHandle() throws {
        let pipe = Pipe()
        let backend = ANSIBackend(output: pipe.fileHandleForWriting)

        backend.writeRaw("hello")
        backend.flush()

        XCTAssertEqual(drain(pipe), "hello")
    }

    func testRenderCommandsGoToTheSuppliedHandle() throws {
        let pipe = Pipe()
        let backend = ANSIBackend(output: pipe.fileHandleForWriting)

        backend.write([
            RenderCommand(position: Position(x: 0, y: 0), cell: Cell(char: "h", style: .default))
        ])
        backend.flush()

        XCTAssertTrue(drain(pipe).hasSuffix("h"))
    }

    func testFlushIsANoOpWhenNothingIsBuffered() throws {
        let pipe = Pipe()
        let backend = ANSIBackend(output: pipe.fileHandleForWriting)

        backend.writeRaw("first")
        backend.flush()
        XCTAssertEqual(drain(pipe), "first")

        // A second flush must not repeat the buffer it already emptied.
        backend.flush()
        backend.writeRaw("second")
        backend.flush()
        XCTAssertEqual(drain(pipe), "second")
    }
}
