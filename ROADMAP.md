# Whisker Framework Roadmap

> A modern Swift framework for building terminal user interfaces, inspired by SwiftUI.

## Vision

Be the "Ink.js for Swift" — the obvious choice when Swift developers need to build terminal applications. Prioritize developer experience, correctness, and real-world utility over feature count.

---

## How to read this roadmap

Work is grouped by **milestone** — a thematic destination we're moving toward ("are we there yet"), **not** a dated release. Versions/releases are a separate concern we'll layer on later if the project ever needs them; milestones carry no dates and no version numbers on purpose.

Each open item is tagged `Area · Priority · Source`:

- **Area** — `Robustness` · `Layout` · `Components` · `State` · `Rendering` · `Backend` · `Distribution` · `Docs` · `Testing` · `DX`
- **Priority** — `P0-blocker` (gates real use) · `P1-high` · `P2-medium` · `P3-low`
- **Source** — where the item came from: `audit` (surfaced by the readiness audit), `roadmap` (original plan), `both`

Items become GitHub issues **when we pick them up**, not before — this doc is the staging ground so the tracker doesn't fill with stale tickets. Items that already have an issue link to it (e.g. `→ #10`). Milestones map 1:1 to the GitHub Project milestones of the same name.

---

## Milestone: Production Safety

**Goal:** The framework can't corrupt a user's terminal. This is the gate to *any* real-world use — surfaced almost entirely by the readiness audit and not previously tracked. Nothing below is "polish"; these are correctness blockers.

- [ ] **Terminal restoration on signal (SIGINT/SIGTERM/SIGHUP)** — `Robustness · P0-blocker · audit`
  Cleanup currently lives only in a `defer` block (`Application.swift:41-51`) that a signal bypasses entirely, so pressing **Ctrl-C** leaves the terminal in raw mode, cursor hidden, on the alternate screen buffer — requiring a blind `reset`. Install `sigaction` handlers that run the same teardown path, then re-raise.
  **Acceptance criteria:**
  - Handlers installed for `SIGINT`, `SIGTERM`, and `SIGHUP`; each runs the full teardown path (exit raw mode, show cursor, leave alt-screen) before the process dies.
  - Default behavior re-raises the signal with the default disposition after cleanup, so the exit code is conventional (`130` for SIGINT) and `app && next-step` shell chaining behaves correctly. No swallowing signals into a clean `exit(0)`.
  - Opt-in interception hook (e.g. `onInterrupt`) lets an app veto/handle Ctrl-C (e.g. "unsaved changes — quit anyway?") instead of dying unconditionally; default when unset is the re-raise behavior above.
  - `SIGTSTP` (Ctrl-Z) restores the terminal on suspend and re-arms raw mode + alt-screen on `SIGCONT` resume.
  - **Invariant (non-negotiable, all paths):** the terminal is always left usable — cooked mode, cursor visible, main screen buffer — even if teardown itself partially fails.
- [ ] **Check terminal-lifecycle syscall return values** — `Robustness · P0-blocker · audit`
  `tcsetattr` returns are ignored (`ANSIBackend.swift:69,97`) and `fcntl(F_GETFL)` is unchecked (`Application.swift:95-96`), so even normal-path restoration can silently fail. Surface errors instead of swallowing them.
- [ ] **Scope or remove the `Application.shared` global singleton** — `Robustness · P1-high · audit`
  `Application.shared` (`Application.swift:12`) prevents nesting, complicates testing, and isn't concurrency-safe. Replace with an instance handle threaded through context.
- [ ] **Make `@State` survive `run()` returning** — `State · P1-high · audit`
  `@State` storage becomes inaccessible after the app exits, forcing an external result class (see `Examples/main.swift:82`). Either expose post-run state reads or ship a documented result-extraction pattern. Critical for the embedded config-TUI use case.
- [ ] **Fix Linux support claim** — `Distribution · P1-high · audit`
  `Package.swift` declares only `.macOS(.v13)`, but this roadmap previously marked Linux as done. Either add the Linux platform + CI validation, or stop claiming it. (Corrected below in *Shipped* — Linux is **not** currently shipped.)
- [ ] **Allow redirectable I/O** — `Backend · P2-medium · audit`
  I/O is hardwired to `STDIN_FILENO`/`STDOUT_FILENO`; can't be redirected for testing or piping. Parameterize the backend's file descriptors.
- [ ] **Stabilize `@State` identity keys** — `State · P2-medium · audit`
  State keys are `file:line`-based, so refactoring can silently drop state. Investigate a more stable keying scheme.

---

## Milestone: Core Foundation

**Goal:** Finish the MVP layer — the everyday SwiftUI modifiers and focus primitives that structured layouts depend on.

- [ ] **`.frame(width:height:)` + min/max variants** — `Layout · P1-high · both`
  No frame modifier exists (`Environment.swift` only does color/bold). Prerequisite for structured panels.
- [ ] **`.padding()`** — `Layout · P1-high · both`
  Removes most Spacer-hacking; most-cited DX gap in the audit.
- [ ] **`.border()` + box-drawing infrastructure** — `Layout · P2-medium · both`
  Reusable box-drawing layer also unblocks tables, panels, themes later.
- [ ] **`.hidden()`** — `Layout · P3-low · roadmap`
- [ ] **`@FocusState`** — `State · P2-medium · roadmap`
  Programmatic focus control.
- [ ] **ESC-byte buffering in `InputParser`** — `Backend · P2-medium · roadmap`
  Lone ESC is ambiguous with ANSI sequence starts; may misparse over high-latency SSH. Fix: timeout-based buffering (~50ms) before emitting `.escape`.
- [ ] **Improve core test coverage** — `Testing · P1-high · both` → #3
  FocusManager, InlineRenderer, InputParser, layout engine. Roadmap targets 80%+ on core.
- [ ] **Docstrings across public + internal API** — `Docs · P1-high · both` → #2
  Currently ~3.57%; CodeRabbit CI requires 80%.

---

## Milestone: Interactive Components

**Goal:** Build real forms, menus, and wizards. The bread-and-butter of CLI tools.

- [ ] **`Picker` — vertical list selection** — `Components · P1-high · both` → #10
  Most critical missing component for setup wizards; includes scrollable viewport for long lists.
- [ ] **`ScrollView` with keyboard scrolling** — `Layout · P1-high · both` *(audit-promoted from a later phase)*
  Needs scroll-offset tracking in `Layout.swift` + viewport clip. The hard ceiling on app size today.
- [ ] **`ProgressView` — determinate progress** — `Components · P2-medium · roadmap` → #11
- [ ] **`Shell` helper for `.task` closures** — `DX · P2-medium · roadmap` → #12
- [ ] **`ActivityIndicator` unit tests** — `Testing · P2-medium · roadmap` → #13
- [ ] **`Alert` / `ConfirmationDialog` — modal dialogs** — `Components · P2-medium · roadmap`
- [ ] **`.focusable()` / `.onKeyPress()` modifiers** — `State · P2-medium · roadmap`
- [ ] **`TextEditor` — multi-line input** — `Components · P3-low · roadmap`
- [ ] **`MultiPicker` — multiple selection** — `Components · P3-low · roadmap`
- [ ] **`Slider` — numeric range** — `Components · P3-low · roadmap`
- [ ] **`TabView` / `NavigationStack`** — `Components · P3-low · roadmap`

---

## Milestone: Rich Content & Polish

**Goal:** Beautiful, robust output — wrapping, international text, tables, themes.

- [ ] **Text wrapping + truncation** — `Rendering · P1-high · both` *(audit-promoted)*
  `Text.swift` hard-clips with `prefix(frame.width)`; long labels/messages clip silently. Add word-wrap + `.lineLimit`/`.truncationMode`.
- [ ] **Unicode / CJK width handling** — `Rendering · P1-high · both` *(audit-promoted)*
  `ViewBuilder.swift` uses `text.count`, so emoji/CJK misaligns every layout.
- [ ] **`Table` — headers, sorting, column sizing** — `Components · P2-medium · roadmap`
- [ ] **`List` — styled lists with selection** — `Components · P2-medium · roadmap`
- [ ] **Customizable themes** — `DX · P2-medium · roadmap`
  Controls currently render hardcoded chrome (`[ Label ]`, `[x]`) that can't be restyled.
- [ ] **`Tree` / `Grid`** — `Components · P3-low · roadmap`
- [ ] **`AttributedText` / Markdown subset / syntax highlighting** — `Rendering · P3-low · roadmap`
- [ ] **Mouse support (click, scroll)** — `Backend · P3-low · roadmap`
- [ ] **Braille patterns for pseudo-graphics** — `Rendering · P3-low · roadmap`
- [ ] **Clipboard integration** — `Backend · P3-low · roadmap`

---

## Milestone: Ecosystem & Integrations

**Goal:** Plays well with the Swift ecosystem; distributable.

- [ ] **Release / versioning + CI release automation** — `Distribution · P1-high · audit`
  No tags, no changelog, no release artifacts despite `Package.swift` referencing `from: 0.1.0`. Binary is arm64-only and dynamically linked.
- [ ] **Swift Argument Parser integration** — `DX · P2-medium · roadmap`
  Subcommand-with-interactive-UI pattern; `--no-interactive` flag.
- [ ] **`@Observable` macro support** — `State · P3-low · roadmap`
- [ ] **Windows support (Console API)** — `Backend · P3-low · roadmap`
- [ ] **Web target via WebAssembly** — `Backend · P3-low · roadmap` *(stretch)*
- [ ] **CocoaPods / Homebrew formula** — `Distribution · P3-low · roadmap`
- [ ] **Hot reload / debug overlay / profiler** — `DX · P3-low · roadmap`

---

## Shipped

Already landed (kept as a record of progress):

- **Architecture:** `TerminalBackend` protocol + ANSI implementation · `View` protocol · `@ViewBuilder` · Node tree · layout engine (VStack/HStack/ZStack) · ~60fps render loop · keyboard input system
- **Property wrappers:** `@State` · `@Binding` · `@Environment`
- **Views:** `Text` (bold/italic/underline/colors) · `VStack`/`HStack`/`ZStack` · `Spacer` · `Divider` · `EmptyView` · `Group` · `ForEach`
- **Controls:** `TextField` · `SecureField` · `Button` · `Toggle` · `SegmentedControl`
- **Modifiers:** `.foregroundColor()`/`.backgroundColor()` · `.bold()`/`.italic()`/`.underline()`/`.strikethrough()`
- **Rendering:** 256-color + TrueColor · dim/blink/reverse attributes
- **Lifecycle:** terminal resize handling · alternate screen buffer · raw/cooked mode control · `.task` modifier · `ActivityIndicator`
- **Testing:** `TestBackend` · README quick start

> ⚠️ **Correction:** Linux was previously marked shipped, but `Package.swift` declares only macOS. Linux support is tracked under *Production Safety* above, not shipped.

---

## Non-Goals (At Least Initially)

- **GUI rendering** — terminals only, not a general UI framework
- **iOS/watchOS/tvOS** — these have SwiftUI, no terminal
- **Pixel graphics** — we render characters, not pixels
- **Full VT100 compatibility** — target modern terminals (xterm-256color+)
- **Backwards compatibility** — will break APIs until 1.0

---

## Architecture Decisions

### Why not fork SwiftTUI?

SwiftTUI is a good proof of concept but has limitations:
1. Control/Node separation adds complexity without benefit
2. Layout system is ad-hoc, not based on an established algorithm
3. Combine dependency limits Linux support
4. Minimal test coverage
5. Single maintainer, limited activity

We'll learn from it but build fresh with:
- Simpler Node-based architecture (no separate Control tree)
- Flexbox-inspired layout (well-documented, predictable)
- Swift concurrency native (no Combine)
- Abstracted terminal backend (testable, portable)
- Tests from day one

### Core Principles

1. **SwiftUI-familiar API** — leverage existing knowledge
2. **Correctness over features** — better to have 10 solid components than 50 buggy ones
3. **Testability built-in** — every component should be unit-testable
4. **Documentation-driven** — if it's not documented, it doesn't exist
5. **Performance by default** — no premature optimization, but no obvious waste

---

## Getting Started (Contributors)

```bash
git clone https://github.com/ProJedi1234/swift-whisker.git
cd swift-whisker
swift build
swift test
swift run Examples
```

See CONTRIBUTING.md for development setup and guidelines.
