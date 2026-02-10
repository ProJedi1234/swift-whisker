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

    var body: some View {
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
                        }
                    }
                    Text(message).foregroundColor(messageColor)
                }
            } else if phase == 1 {
                HStack(spacing: 0) {
                    Text("  ")
                    ActivityIndicator().foregroundColor(.cyan)
                    Text(" Signing up...").foregroundColor(.cyan)
                }
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    phase = 2
                }
            } else if phase == 2 {
                HStack(spacing: 0) {
                    Text("  ✓ Signed up!").foregroundColor(.green)
                }
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    phase = 3
                }
            } else {
                HStack(spacing: 0) {
                    Text("  ✓ Welcome, \(name)! (\(plans.indices.contains(planIndex) ? plans[planIndex] : plans[0]))")
                        .foregroundColor(.green)
                }
                .task {
                    try? await Task.sleep(for: .seconds(1))
                    Application.shared?.quit()
                }
            }
        }
    }
}

let app = Application(mode: .inline) {
    FormView()
}

try app.run()
