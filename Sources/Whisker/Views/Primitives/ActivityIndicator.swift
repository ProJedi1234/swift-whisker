import Foundation

/// An animated spinner that cycles through Braille dot characters.
/// Commonly used to indicate loading or in-progress operations.
///
/// The spinner animates automatically when in the view tree.
/// It picks up foreground color from the environment.
///
///     HStack {
///         ActivityIndicator()
///         Text(" Loading...")
///     }
public struct ActivityIndicator: View {
    public typealias Body = Never

    static let frames: [Character] = [
        "\u{280B}", // ⠋
        "\u{2819}", // ⠙
        "\u{2839}", // ⠹
        "\u{2838}", // ⠸
        "\u{283C}", // ⠼
        "\u{2834}", // ⠴
        "\u{2826}", // ⠦
        "\u{2827}", // ⠧
        "\u{2807}", // ⠇
        "\u{280F}", // ⠏
    ]

    let fps: Double

    /// Create an activity indicator.
    /// - Parameter fps: Animation speed in frames per second (default: 10)
    public init(fps: Double = 10) {
        self.fps = fps
    }

    public var body: Never {
        fatalError("ActivityIndicator has no body")
    }

    /// Compute the current frame index from wall-clock time
    func currentFrameIndex() -> Int {
        let time = Date().timeIntervalSinceReferenceDate
        return Int(time * fps) % Self.frames.count
    }
}
