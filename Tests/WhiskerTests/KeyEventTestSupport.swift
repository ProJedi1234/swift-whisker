import XCTest

@testable import Whisker

/// Shared fixtures for the key-routing and focus-ring suites.
class KeyEventTestCase: XCTestCase {

    /// Records the keys seen by a `.onKeyPress` handler and controls its return value.
    final class KeyRecorder {
        var keys: [Key] = []
        var result: KeyPressResult = .handled
    }

    struct ProbeView: View {
        var body: some View {
            Text("probe")
        }
    }

    func makeApp(
        backend: TestBackend = TestBackend(size: Size(width: 40, height: 10)),
        @ViewBuilder rootView: @escaping () -> some View
    ) -> Application {
        Application(mode: .fullscreen, backend: backend, rootView: rootView)
    }

    override func tearDown() {
        Application.shared = nil
        NodeContext.current = nil
        super.tearDown()
    }
}
