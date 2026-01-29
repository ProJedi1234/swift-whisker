# Whisker

[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux-blue)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![SPM Compatible](https://img.shields.io/badge/SPM-Compatible-brightgreen)](https://swift.org/package-manager/)

A declarative Swift framework for building terminal user interfaces, inspired by SwiftUI.

Write TUIs with the same patterns you already know — `VStack`, `@State`, `@Binding`, `ViewBuilder` — but targeting the terminal instead of a window.

```swift
import Whisker

let app = Application {
    VStack {
        Text("Hello, terminal!").bold().foregroundColor(.cyan)
        Text("Built with Whisker.")
    }
}

try app.run()
```

## Features

- **SwiftUI-like API** — `VStack`, `HStack`, `ZStack`, `Text`, `ForEach`, `Group`, `Spacer`, and more
- **Reactive state** — `@State`, `@Binding`, and `@Environment` property wrappers
- **Interactive controls** — `TextField`, `SecureField`, `Button` with focus management
- **Layout engine** — Flexbox-inspired layout with alignment, spacing, and frames
- **Styling** — Colors (ANSI, 256, TrueColor), bold, italic, underline, strikethrough
- **Focus navigation** — Tab, Shift+Tab, and arrow key support out of the box
- **Two render modes** — Fullscreen (alternate buffer) or inline (lives in scrollback)
- **Cross-platform** — macOS and Linux
- **Testable** — Built-in `TestBackend` for unit testing views without a real terminal

## Getting Started

### Requirements

- Swift 5.9+
- macOS 13+ or Linux

### Installation

Add Whisker to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ProJedi1234/swift-whisker.git", from: "0.1.0")
]
```

Then add it as a dependency to your target:

```swift
.target(name: "MyApp", dependencies: ["Whisker"])
```

### Quick Start

```swift
import Whisker

let app = Application {
    VStack(alignment: .leading, spacing: 1) {
        Text("Welcome").bold().foregroundColor(.green)
        Text("Press Ctrl+C to exit.")
    }
}

try app.run()
```

## Example: Form with Validation

This is a real working example — an inline form with text fields, a password field, and submit validation:

```swift
import Whisker

final class FormState {
    var name = ""
    var email = ""
    var password = ""
    var message = ""
    var messageColor: Color = .white
}

let state = FormState()

let app = Application(mode: .inline) {
    VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.yellow)
            Text("Name? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            TextField("Enter your name",
                      get: { state.name },
                      set: { state.name = $0 })
        }
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.green)
            Text("Email? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            TextField("you@example.com",
                      get: { state.email },
                      set: { state.email = $0 })
        }
        HStack(spacing: 0) {
            Text("? ").foregroundColor(.magenta)
            Text("Password? ").bold()
            Text("› ").foregroundColor(.brightBlack)
            SecureField("Create a password",
                        text: Binding(
                            get: { state.password },
                            set: { state.password = $0 }))
        }
        HStack(spacing: 0) {
            Text("  ")
            Button("Submit") {
                if state.name.isEmpty {
                    state.message = "  ✗ Name is required"
                    state.messageColor = .red
                } else if !state.email.contains("@") {
                    state.message = "  ✗ Valid email required"
                    state.messageColor = .red
                } else {
                    state.message = "  ✓ Welcome, \(state.name)!"
                    state.messageColor = .green
                }
            }
            Text(state.message).foregroundColor(state.messageColor)
        }
    }
}

try app.run()
```

## Architecture

Whisker uses a three-level tree system, similar to how SwiftUI and React work internally:

```
View Tree          Node Tree           Render Buffer
(declarative)      (persistent)        (output)
┌──────────┐      ┌──────────┐       ┌──────────────┐
│  VStack   │ ──▶ │   Node   │ ──▶  │ RenderCommand│
│  ├ Text   │      │  ├ Node  │       │ (position,   │
│  └ Button │      │  └ Node  │       │  cell)       │
└──────────┘      └──────────┘       └──────────────┘
 Recreated on      Persists state     Flat list of
 every update      across renders     draw commands
```

1. **View tree** — Lightweight value types describing the UI. Cheap to recreate.
2. **Node tree** — Persistent class-based tree. Stores `@State`, tracks focus, manages layout.
3. **Render buffer** — Flat list of characters + positions. Diffed against the previous frame.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full deep-dive.

## Available Views

| View | Description |
|------|-------------|
| `Text` | Styled text with colors, bold, italic, underline |
| `VStack` | Vertical layout with alignment and spacing |
| `HStack` | Horizontal layout with alignment and spacing |
| `ZStack` | Overlapping layout |
| `Spacer` | Flexible space |
| `Divider` | Horizontal separator |
| `Group` | Transparent grouping |
| `ForEach` | Dynamic list of views |
| `TextField` | Single-line text input |
| `SecureField` | Masked password input |
| `Button` | Pressable control with label and action |

## Roadmap

Whisker is at **v0.1.0**. The core architecture is in place. Here's what's next:

- **Phase 2** — Picker, Toggle, Slider, ScrollView, TabView, NavigationStack
- **Phase 3** — Tables, Markdown rendering, mouse support, themes
- **Phase 4** — Swift Argument Parser integration, `@Observable` support, `.task {}` modifier

See [ROADMAP.md](ROADMAP.md) for the full plan.

## Running the Examples

```bash
git clone https://github.com/ProJedi1234/swift-whisker.git
cd swift-whisker
swift run Examples
```

## Running Tests

```bash
swift test
```

## How It Compares

| | Whisker | [SwiftTUI](https://github.com/rensbreur/SwiftTUI) | [Ink (JS)](https://github.com/vadimdemedes/ink) | [Ratatui (Rust)](https://github.com/ratatui/ratatui) |
|---|---|---|---|---|
| Language | Swift | Swift | JavaScript | Rust |
| API style | Declarative (SwiftUI) | Declarative (SwiftUI) | Declarative (React) | Immediate mode |
| State management | @State, @Binding | @State | React hooks | Manual |
| Layout | Flexbox-inspired | Custom | Yoga (Flexbox) | Constraint-based |
| Async | Swift concurrency | Combine | Node.js event loop | tokio |
| Test backend | Yes | No | Yes | Yes |
| Status | Early (v0.1) | Maintained | Mature | Mature |

## License

[MIT](LICENSE)
