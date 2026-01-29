/// Type-safe keys for node storage
enum NodeStorageKey {
    static let keyHandler = NodeKey<(KeyEvent) -> Void>("_keyHandler")
    static let getText = NodeKey<() -> String>("_getText")
    static let setText = NodeKey<(String) -> Void>("_setText")
    static let placeholder = NodeKey<String>("_placeholder")
    static let cursorPosition = NodeKey<Int>("_cursorPosition")
    static let isSecure = NodeKey<Bool>("_isSecure")
    static let action = NodeKey<() -> Void>("_action")
    static let label = NodeKey<String>("_label")
    static let placeChildren = NodeKey<(Rect) -> Void>("_placeChildren")
}

struct NodeKey<Value> {
    let key: String
    init(_ key: String) { self.key = key }
}

extension Node {
    subscript<T>(key: NodeKey<T>) -> T? {
        get { stateStorage[key.key] as? T }
        set { stateStorage[key.key] = newValue }
    }
}

extension NodeKey {
    static var keyHandler: NodeKey<(KeyEvent) -> Void> { NodeStorageKey.keyHandler }
    static var getText: NodeKey<() -> String> { NodeStorageKey.getText }
    static var setText: NodeKey<(String) -> Void> { NodeStorageKey.setText }
    static var placeholder: NodeKey<String> { NodeStorageKey.placeholder }
    static var cursorPosition: NodeKey<Int> { NodeStorageKey.cursorPosition }
    static var isSecure: NodeKey<Bool> { NodeStorageKey.isSecure }
    static var action: NodeKey<() -> Void> { NodeStorageKey.action }
    static var label: NodeKey<String> { NodeStorageKey.label }
    static var placeChildren: NodeKey<(Rect) -> Void> { NodeStorageKey.placeChildren }
}
