# Whisker Architecture

## Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              User Code                                       │
│                                                                             │
│   struct MyApp: View {                                                      │
│       @State var count = 0                                                  │
│       var body: some View {                                                 │
│           VStack {                                                          │
│               Text("Count: \(count)")                                       │
│               Button("+") { count += 1 }                                    │
│           }                                                                 │
│       }                                                                     │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           View Tree (Declarative)                           │
│                                                                             │
│   Views are lightweight value types that describe UI.                       │
│   They're recreated on every state change - cheap to make.                  │
│                                                                             │
│   protocol View {                                                           │
│       associatedtype Body: View                                             │
│       @ViewBuilder var body: Body { get }                                   │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                          ┌─────────┴─────────┐
                          │   Reconciliation  │
                          │   (Diffing)       │
                          └─────────┬─────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           Node Tree (Runtime)                               │
│                                                                             │
│   Nodes are the persistent runtime representation.                          │
│   They store state, handle layout, and manage lifecycle.                    │
│                                                                             │
│   class Node {                                                              │
│       var viewType: Any.Type          // Type of the originating view       │
│       var stateStorage: [String: Any] // @State values live here            │
│       var environment: EnvironmentValues                                    │
│       var children: [Node]            // Child nodes                        │
│       var frame: Rect                 // Computed layout frame              │
│       var render: ((Rect, inout RenderBuffer) -> Void)?                     │
│       var layout: ((ProposedSize, [Node]) -> (Size, [...]))?                │
│       var needsRebuild: Bool          // Dirty flag                         │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                          ┌─────────┴─────────┐
                          │     Layout        │
                          │   (Flexbox-ish)   │
                          └─────────┬─────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Render Tree (Drawing)                              │
│                                                                             │
│   Flat list of drawing commands. No hierarchy, just "put cell X at Y".      │
│   Diffed against previous frame to minimize terminal writes.                │
│                                                                             │
│   struct RenderCommand {                                                    │
│       let position: Position                                                │
│       let cell: Cell                                                        │
│   }                                                                         │
│                                                                             │
│   struct Cell: Equatable {                                                  │
│       var char: Character                                                   │
│       var style: Style          // fg, bg, bold, etc.                       │
│   }                                                                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                          ┌─────────┴─────────┐
                          │      Diff         │
                          │   (old vs new)    │
                          └─────────┬─────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        Terminal Backend (I/O)                               │
│                                                                             │
│   Abstract interface to the terminal. Multiple implementations.             │
│                                                                             │
│   protocol TerminalBackend: AnyObject, Sendable {                           │
│       var size: Size { get }                                                │
│       func write(_ commands: [RenderCommand])                               │
│       func flush()                                                          │
│       func setup() throws                                                   │
│       func teardown()                                                       │
│   }                                                                         │
│                                                                             │
│   Implementations:                                                          │
│   - ANSIBackend: Raw escape sequences (default)                             │
│   - TestBackend: In-memory for unit tests                                   │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. View Protocol

```swift
public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

// Primitive views have Body = Never (can't access .body)
extension Text: View {
    typealias Body = Never
}

// Primitives are handled by NodeViewBuilder which sets
// render and layout closures directly on the Node.
```

### 2. Node (Runtime Identity)

```swift
final class Node {
    weak var parent: Node?
    var children: [Node] = []
    var viewType: Any.Type

    var stateStorage: [String: Any] = [:]
    var environment: EnvironmentValues = EnvironmentValues()
    var frame: Rect = .zero
    var needsRebuild: Bool = true

    var isFocusable: Bool = false
    var isFocused: Bool = false

    // Closures set by NodeViewBuilder during tree construction
    var render: ((Rect, inout RenderBuffer) -> Void)?
    var layout: ((ProposedSize, [Node]) -> (Size, [(Node, Rect)]))?
}
```

### 3. Layout System

Inspired by Flexbox but simplified for terminal constraints (integer sizes, no sub-cell positioning).

```swift
struct ProposedSize {
    var width: SizeConstraint   // .exactly(n), .atMost(n), .unconstrained
    var height: SizeConstraint
}

struct Size {
    var width: Int
    var height: Int
}

protocol Layout {
    func sizeThatFits(
        proposal: ProposedSize,
        children: [LayoutChild]
    ) -> Size

    func placeChildren(
        in bounds: Rect,
        children: [LayoutChild]
    )
}

struct LayoutChild {
    let node: Node
    var size: Size = .zero
    var position: Position = .zero
    func sizeThatFits(_ proposal: ProposedSize) -> Size
}
```

**Built-in layouts:**

```swift
// VStack: children stacked vertically
struct VStackLayout: Layout {
    var alignment: HorizontalAlignment
    var spacing: Int
}

// HStack: children stacked horizontally
struct HStackLayout: Layout {
    var alignment: VerticalAlignment
    var spacing: Int
}

// ZStack: children overlaid
struct ZStackLayout: Layout {
    var alignment: Alignment
}

```

### 4. Rendering Pipeline

```swift
final class Renderer {
    var previousFrame: [Position: Cell] = [:]
    let backend: TerminalBackend

    func render(rootNode: Node) {
        // 1. Collect all render commands from the tree
        var commands: [RenderCommand] = []
        collectCommands(from: rootNode, into: &commands)

        // 2. Diff against previous frame
        var changes: [RenderCommand] = []
        var currentFrame: [Position: Cell] = [:]

        for cmd in commands {
            currentFrame[cmd.position] = cmd.cell
            if previousFrame[cmd.position] != cmd.cell {
                changes.append(cmd)
            }
        }

        // 3. Find cells that need clearing (were in previous, not in current)
        for (pos, _) in previousFrame where currentFrame[pos] == nil {
            changes.append(RenderCommand(position: pos, cell: Cell(char: " ")))
        }

        previousFrame = currentFrame

        // 4. Write to terminal (backend handles escape sequences)
        backend.write(changes)
        backend.flush()
    }
}
```

### 5. Terminal Backend

```swift
protocol TerminalBackend: AnyObject, Sendable {
    var renderMode: RenderMode { get set }
    var size: Size { get }

    func write(_ commands: [RenderCommand])
    func writeRaw(_ string: String)
    func flush()
    func setup() throws
    func teardown()
    func moveCursor(to position: Position)
    func setCursorVisible(_ visible: Bool)
    func clearScreen()
    func clearLines(_ count: Int)
}

enum TerminalEvent: Sendable {
    case key(KeyEvent)
    case resize(Size)
    case mouse(MouseEvent)
}
```

**ANSI Implementation:**

```swift
final class ANSIBackend: TerminalBackend {
    private var originalTermios: termios?
    private var outputBuffer = Data()

    var size: Size {
        var ws = winsize()
        _ = ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws)
        return Size(width: Int(ws.ws_col), height: Int(ws.ws_row))
    }

    func write(_ commands: [RenderCommand]) {
        // Sort by position for optimal cursor movement
        let sorted = commands.sorted { ($0.position.y, $0.position.x) < ($1.position.y, $1.position.x) }

        var currentPos: Position?
        var currentStyle: Style?

        for cmd in sorted {
            // Move cursor if needed
            if currentPos != cmd.position {
                outputBuffer.append(escapeSequence(.moveTo(cmd.position)))
            }

            // Update style if needed
            if currentStyle != cmd.cell.style {
                outputBuffer.append(escapeSequence(.style(cmd.cell.style)))
                currentStyle = cmd.cell.style
            }

            // Write character
            outputBuffer.append(cmd.cell.char.utf8)
            currentPos = Position(x: cmd.position.x + 1, y: cmd.position.y)
        }
    }

    func flush() {
        FileHandle.standardOutput.write(outputBuffer)
        outputBuffer.removeAll(keepingCapacity: true)
    }
}
```

### 6. State Management

```swift
@propertyWrapper
public struct State<Value: Equatable>: DynamicProperty {
    private let key: String
    private let initialValue: Value

    public init(wrappedValue: Value, _ key: String = #function) {
        self.initialValue = wrappedValue
        self.key = key
    }

    public var wrappedValue: Value {
        get {
            guard let node = NodeContext.current else {
                return initialValue
            }
            return node.stateStorage[key] as? Value ?? initialValue
        }
        nonmutating set {
            guard let node = NodeContext.current else { return }
            node.stateStorage[key] = newValue
            node.needsRebuild = true
            Application.shared?.scheduleUpdate()
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}
```

### 7. Application Lifecycle

```swift
public final class Application {
    public static var shared: Application?
    let backend: TerminalBackend
    var rootNode: Node?
    let rootViewBuilder: () -> any View

    public init<V: View>(mode: RenderMode = .fullscreen, backend: TerminalBackend = ANSIBackend(),
                         @ViewBuilder rootView: @escaping () -> V) { ... }

    public func run() throws {
        try backend.setup()
        defer { backend.teardown() }

        isRunning = true
        rebuild()
        render()

        // Synchronous ~60fps run loop
        while isRunning {
            if let event = readInput() {  // Non-blocking stdin via fcntl
                handleEvent(event)
            }
            if updateScheduled {
                updateScheduled = false
                rebuild()
                render()
            }
            Thread.sleep(forTimeInterval: 0.016)
        }
    }
}
```

---

## Directory Structure

```
Sources/
├── Whisker/
│   ├── Core/
│   │   ├── View.swift              # View protocol, ViewBuilder, TupleView, ConditionalView
│   │   ├── Node.swift              # Runtime node tree
│   │   ├── Application.swift       # Main run loop, RenderMode
│   │   ├── ViewBuilder.swift       # NodeViewBuilder (view → node conversion)
│   │   ├── Environment.swift       # EnvironmentValues, EnvironmentKey
│   │   ├── NodeStorage.swift       # Type-safe node storage keys
│   │   ├── FocusManager.swift      # Focus traversal logic
│   │   ├── InlineRenderer.swift    # Inline render mode
│   │   └── InputParser.swift       # Terminal input byte parsing
│   │
│   ├── State/
│   │   └── State.swift             # @State, Binding, @Environment, NodeContext
│   │
│   ├── Layout/
│   │   ├── Layout.swift            # Layout protocol, VStack/HStack/ZStackLayout
│   │   ├── ProposedSize.swift      # ProposedSize, SizeConstraint
│   │   └── Geometry.swift          # Position, Size, Rect, EdgeInsets
│   │
│   ├── Views/
│   │   ├── Primitives/
│   │   │   ├── Text.swift
│   │   │   ├── Spacer.swift        # Spacer and Divider
│   │   │   └── EmptyView.swift
│   │   │
│   │   ├── Containers/
│   │   │   ├── Stacks.swift        # VStack, HStack, ZStack, Group, alignment types
│   │   │   └── ForEach.swift
│   │   │
│   │   └── Controls/
│   │       ├── Button.swift        # Button and Toggle
│   │       └── TextField.swift     # TextField and SecureField
│   │
│   ├── Rendering/
│   │   ├── RenderBuffer.swift      # RenderBuffer (draw commands)
│   │   ├── Cell.swift              # Cell, Style, Attributes
│   │   └── Color.swift             # Color enum + ANSI sequences
│   │
│   ├── Backend/
│   │   ├── TerminalBackend.swift   # Protocol + event types
│   │   ├── ANSIBackend.swift       # ANSI escape sequences
│   │   └── TestBackend.swift       # In-memory backend for tests
│   │
│   └── Whisker.swift               # Module version
│
├── Examples/
│   └── main.swift                  # Interactive form demo
│
└── Tests/
    └── WhiskerTests/
        └── WhiskerTests.swift
```

---

## Key Differences from SwiftTUI

| Aspect | SwiftTUI | Whisker |
|--------|----------|---------------------|
| Tree structure | View → Node → Control → Layer | View → Node → RenderCommands |
| Layout | Ad-hoc per control | Flexbox-inspired, uniform |
| State | Combine (macOS only) | Swift native, @State with Equatable |
| Terminal I/O | Direct ANSI writes | Abstracted backend |
| Testing | Minimal | First-class TestBackend |
| Focus | Basic | Full system with @FocusState |
| Async | DispatchQueue | async/await native |

---

## Testing Strategy

```swift
// TestBackend captures rendered cells for assertions
func testTextRendering() {
    let backend = TestBackend(size: Size(width: 80, height: 24))
    // Write render commands, then inspect:
    XCTAssertEqual(backend.text(atLine: 0), "Hello")
    XCTAssertEqual(backend.allText(), "...")
    let cell = backend.cell(at: Position(x: 0, y: 0))
}

// State is stored in Node.stateStorage keyed by #function
func testStateChanges() {
    let node = Node(viewType: MyView.self)
    NodeContext.current = node
    // @State var count = 0 stores as node.stateStorage["count"]
    // Setting wrappedValue calls Application.shared?.scheduleUpdate()
}
```

---

## Performance Considerations

1. **Minimize allocations** - Reuse buffers, avoid creating strings in hot paths
2. **Batch terminal writes** - Buffer commands, flush once per frame
3. **Smart diffing** - Only send changed cells to terminal
4. **Lazy layout** - Only recalculate affected subtrees
5. **Virtualization** - For long lists, only render visible rows

Target: <16ms frame time for typical UIs (60fps capable, though terminals rarely need it)
