import Foundation
import Whisker

// ============================================================================
// Form Demo - Using the Whisker framework with @State
// ============================================================================
//
// This demo shows how to build a simple inline-prompt form using a custom
// View struct with @State properties. No manual ANSI codes or class-based
// state workarounds needed.

let plans = [
    "Guppy", "Orbit", "Nimbus", "Lichen", "Quartz", "Bramble", "Vortex",
    "Papaya", "Saffron", "Kestrel", "Juniper", "Tinsel", "Harbor", "Yonder",
    "Marble", "Cinder", "Puddle", "Sprocket", "Velvet", "Chroma", "Tangle",
    "Mosaic", "Cobalt", "Topaz", "Quasar", "Ramble", "Fable", "Driftwood",
    "Starlight", "Hammock", "Telemetry", "Windmill", "Whirligig", "Sundial",
    "Thunderclap", "Peppercorn", "Kaleidoscope", "Foghorn", "Huckleberry"
]

struct FormView: View {
    @State var name = ""
    @State var email = ""
    @State var password = ""
    @State var confirmPassword = ""
    @State var planIndex = 0
    @State var message = ""
    @State var messageColor: Color = .white
    @State var phase: Int = 0
    @State var submittedAt: Double = 0

    /// Check elapsed time and advance through submission phases.
    ///
    /// This is the key to time-based transitions in a declarative framework:
    /// instead of callbacks ("after 2s, do X"), we ask "given the current
    /// time, what phase should we be in?" every time the view rebuilds.
    ///
    /// - Phase 1 rebuilds continuously (~60fps) because ActivityIndicator
    ///   keeps the animation tick alive.
    /// - Phases 2 and 3 have no spinner, so we use scheduleUpdate(after:)
    ///   as an alarm clock to trigger the next rebuild.
    private func advancePhaseIfNeeded() {
        guard submittedAt > 0 else { return }
        let elapsed = Date().timeIntervalSinceReferenceDate - submittedAt

        if phase == 1 && elapsed >= 2.0 {
            phase = 2
            Application.shared?.scheduleUpdate(after: 1.0)
        } else if phase == 2 && elapsed >= 3.0 {
            phase = 3
            Application.shared?.scheduleUpdate(after: 1.0)
        } else if phase == 3 && elapsed >= 4.0 {
            Application.shared?.quit()
        }
    }

    var body: some View {
        // Advance phase based on elapsed time before rendering.
        // This call has side effects (@State mutations) but returns Void,
        // so we use a let binding to keep the result builder happy.
        let _ = advancePhaseIfNeeded()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("? ").foregroundColor(.yellow)
                Text("Name? ").bold()
                Text("› ").foregroundColor(.brightBlack)
                TextField("Enter your full name", text: $name)
            }
            HStack(spacing: 0) {
                Text("? ").foregroundColor(.green)
                Text("Email? ").bold()
                Text("› ").foregroundColor(.brightBlack)
                TextField("you@example.com", text: $email)
            }
            HStack(spacing: 0) {
                Text("? ").foregroundColor(.magenta)
                Text("Password? ").bold()
                Text("› ").foregroundColor(.brightBlack)
                SecureField("Create a password", text: $password)
            }
            HStack(spacing: 0) {
                Text("? ").foregroundColor(.cyan)
                Text("Confirm? ").bold()
                Text("› ").foregroundColor(.brightBlack)
                SecureField("Confirm your password", text: $confirmPassword)
            }
            HStack(spacing: 0) {
                Text("? ").foregroundColor(.brightBlue)
                Text("Plan? ").bold()
                Text("› ").foregroundColor(.brightBlack)
                SegmentedControl(
                    plans,
                    selection: $planIndex,
                    overflow: .wrap
                )
                .foregroundColor(.brightCyan)
            }
            if phase == 0 {
                HStack(spacing: 0) {
                    Text("  ")
                    Button("Submit") {
                        if name.isEmpty {
                            message = "  ✗ Name is required"
                            messageColor = .red
                        } else if email.isEmpty || !email.contains("@") {
                            message = "  ✗ Valid email is required"
                            messageColor = .red
                        } else if password.count < 4 {
                            message = "  ✗ Password must be at least 4 characters"
                            messageColor = .red
                        } else if password != confirmPassword {
                            message = "  ✗ Passwords do not match"
                            messageColor = .red
                        } else {
                            phase = 1
                            submittedAt = Date().timeIntervalSinceReferenceDate
                        }
                    }
                    Text(message).foregroundColor(messageColor)
                }
            } else if phase == 1 {
                // Phase 1: Loading spinner (lasts 2 seconds)
                //
                // The ActivityIndicator keeps the run loop ticking at ~60fps,
                // so this body runs every frame. Each frame we check: has 2s
                // passed? If not, do nothing — just keep showing the spinner.
                // If yes, advance to phase 2 and schedule a wake-up for 1s
                // later (since there will be no spinner to keep ticks alive).
                HStack(spacing: 0) {
                    Text("  ")
                    ActivityIndicator().foregroundColor(.cyan)
                    Text(" Signing up...").foregroundColor(.cyan)
                }
            } else if phase == 2 {
                // Phase 2: Success checkmark (lasts 1 second)
                //
                // We got here because scheduleUpdate(after:) woke us up.
                // Show the checkmark, and schedule another wake-up for the
                // final phase.
                HStack(spacing: 0) {
                    Text("  ✓ Signed up!").foregroundColor(.green)
                }
            } else {
                // Phase 3: Full welcome message (lasts 1 second, then quit)
                HStack(spacing: 0) {
                    Text("  ✓ Welcome, \(name)! (\(plans.indices.contains(planIndex) ? plans[planIndex] : plans[0]))")
                        .foregroundColor(.green)
                }
            }
        }
    }
}

let app = Application(mode: .inline) {
    FormView()
}

try app.run()
