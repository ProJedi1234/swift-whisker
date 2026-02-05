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
                        let planName = plans.indices.contains(planIndex)
                            ? plans[planIndex] : plans[0]
                        message = "  ✓ Welcome, \(name)! (\(planName))"
                        messageColor = .green
                        Application.shared?.quit()
                    }
                }
                Text(message).foregroundColor(messageColor)
            }
        }
    }
}

let app = Application(mode: .inline) {
    FormView()
}

try app.run()
