import Foundation
import QuickSnapCore

enum ShortcutAction: Int, CaseIterable {
    case copy, paste, capture

    var title: String {
        switch self {
        case .copy: return "复制"
        case .paste: return "粘贴"
        case .capture: return "截图"
        }
    }

    func preferenceKey(for mode: ShortcutMode) -> String {
        switch self {
        case .copy: return mode == .chord ? "chordBinding" : "shortcutBinding"
        case .paste: return mode == .chord ? "pasteChordBinding" : "pasteDoublePressBinding"
        case .capture: return mode == .chord ? "captureChordBinding" : "captureDoublePressBinding"
        }
    }

    func defaultBinding(for mode: ShortcutMode) -> ShortcutBinding {
        let controlOption: UInt64 = (1 << 18) | (1 << 19)
        switch self {
        case .copy: return mode == .doublePress ? .mouse(2) : .key(35, controlOption) // P
        case .paste: return .key(9, controlOption) // V
        case .capture: return .key(1, controlOption) // S
        }
    }
}

struct ShortcutSettings {
    var defaults: UserDefaults = .standard

    func bindings(for mode: ShortcutMode) -> [ShortcutAction: ShortcutBinding] {
        var bindings: [ShortcutAction: ShortcutBinding] = [:]
        for action in ShortcutAction.allCases {
            bindings[action] = savedBinding(for: action, mode: mode)
        }
        let defaultChords = ShortcutAction.allCases.map { $0.defaultBinding(for: .chord) }
        for action in ShortcutAction.allCases where bindings[action] == nil {
            let choices = [action.defaultBinding(for: mode)] + defaultChords
            bindings[action] = choices.first { !bindings.values.contains($0) }
        }
        return bindings
    }

    func save(_ binding: ShortcutBinding, for action: ShortcutAction, mode: ShortcutMode) -> Bool {
        guard mode.accepts(binding) else { return false }
        var bindings = bindings(for: mode)
        bindings[action] = binding
        // Save the other resolved defaults too, so editing one row doesn't move another.
        for (action, value) in bindings {
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: action.preferenceKey(for: mode))
            }
        }
        return true
    }

    private func savedBinding(for action: ShortcutAction, mode: ShortcutMode) -> ShortcutBinding? {
        if let data = defaults.data(forKey: action.preferenceKey(for: mode)),
           let binding = try? JSONDecoder().decode(ShortcutBinding.self, from: data), mode.accepts(binding) {
            return binding
        }
        if action == .copy, mode == .doublePress, let legacy = defaults.object(forKey: "triggerButton") as? Int {
            let binding = ShortcutBinding.mouse(Int64(legacy))
            if mode.accepts(binding) { return binding }
        }
        return nil
    }
}
