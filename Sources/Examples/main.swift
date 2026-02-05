import Whisker

// ============================================================================
// Form Demo - Using the Whisker framework
// ============================================================================
//
// This demo shows how to build a simple inline-prompt form using the
// framework's VStack, HStack, Text, TextField, and Button views.
// No manual ANSI codes needed.

/// Holds form state (referenced by closures in the view tree)
final class FormState {
    var name = ""
    var email = ""
    var password = ""
    var confirmPassword = ""
    var planIndex = 0
    var message = ""
    var messageColor: Color = .white
}

let state = FormState()
let plans = [
    "Guppy", "Orbit", "Nimbus", "Lichen", "Quartz", "Bramble", "Vortex",
    "Papaya", "Saffron", "Kestrel", "Juniper", "Tinsel", "Harbor", "Yonder",
    "Marble", "Cinder", "Puddle", "Sprocket", "Velvet", "Chroma", "Tangle",
    "Mosaic", "Cobalt", "Topaz", "Quasar", "Ramble", "Fable", "Driftwood",
    "Starlight", "Hammock", "Telemetry", "Windmill", "Whirligig", "Sundial",
    "Thunderclap", "Peppercorn", "Kaleidoscope", "Foghorn", "Huckleberry",
]

let app = Application(mode: .inline) {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.yellow)
            Text("Name? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            TextField(
                "Enter your full name",
                get: { state.name },
                set: { state.name = $0 })
        }
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.green)
            Text("Email? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            TextField(
                "you@example.com",
                get: { state.email },
                set: { state.email = $0 })
        }
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.magenta)
            Text("Password? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            SecureField(
                "Create a password",
                text: Binding(
                    get: { state.password },
                    set: { state.password = $0 }))
        }
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.cyan)
            Text("Confirm? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            SecureField(
                "Confirm your password",
                text: Binding(
                    get: { state.confirmPassword },
                    set: { state.confirmPassword = $0 }))
        }
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.brightBlue)
            Text("Plan? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            SegmentedControl(
                plans,
                selection: Binding(
                    get: { state.planIndex },
                    set: { state.planIndex = $0 }
                ),
                overflow: .wrap
            )
            .foregroundColor(.brightCyan)
        }
        HStack(spacing: 0) {
            Text("  ")
            Button("Submit") {
                // Validate
                if state.name.isEmpty {
                    state.message = "  ✗ Name is required"
                    state.messageColor = .red
                } else if state.email.isEmpty || !state.email.contains("@") {
                    state.message = "  ✗ Valid email is required"
                    state.messageColor = .red
                } else if state.password.count < 4 {
                    state.message = "  ✗ Password must be at least 4 characters"
                    state.messageColor = .red
                } else if state.password != state.confirmPassword {
                    state.message = "  ✗ Passwords do not match"
                    state.messageColor = .red
                } else {
                    let planName =
                        plans.indices.contains(state.planIndex) ? plans[state.planIndex] : plans[0]
                    state.message = "  ✓ Welcome, \(state.name)! (\(planName))"
                    state.messageColor = .green
                    Application.shared?.scheduleUpdate()
                    Application.shared?.quit()
                    return
                }
                Application.shared?.scheduleUpdate()
            }
            Text(state.message).foregroundColor(state.messageColor)
        }
    }
}

try app.run()
