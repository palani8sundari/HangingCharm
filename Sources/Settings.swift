import Foundation
import CoreGraphics

enum CordLength: String, CaseIterable {
    case short, medium, long
    var points: Double { switch self { case .short: 90; case .medium: 150; case .long: 240 } }
    var title: String { switch self { case .short: "Short"; case .medium: "Medium"; case .long: "Long" } }
}

enum CharmSize: String, CaseIterable {
    case small, medium, large
    var factor: CGFloat { switch self { case .small: 0.78; case .medium: 1; case .large: 1.3 } }
    var title: String { switch self { case .small: "Small"; case .medium: "Medium"; case .large: "Large" } }
}

enum Swing: String, CaseIterable {
    case calm, natural, lively
    /// Exponential decay of angular velocity, per second.
    var damping: Double { switch self { case .calm: 1.3; case .natural: 0.7; case .lively: 0.3 } }
    var title: String { switch self { case .calm: "Calm"; case .natural: "Natural"; case .lively: "Lively" } }
}

enum HangPoint: String {
    case menuBarIcon, custom
}

/// Everything the menu can change, kept in UserDefaults.
final class Settings {
    enum Change { case visibility, charm, cord, size, swing, placement }

    static let shared = Settings()
    var onChange: ((Change) -> Void)?
    private let store = UserDefaults.standard

    var isVisible: Bool {
        get { store.object(forKey: "visible") as? Bool ?? true }
        set { store.set(newValue, forKey: "visible"); onChange?(.visibility) }
    }
    var charmID: String {
        get { store.string(forKey: "charm") ?? Charm.all[0].id }
        set { store.set(newValue, forKey: "charm"); onChange?(.charm) }
    }
    var cordLength: CordLength {
        get { CordLength(rawValue: store.string(forKey: "cordLength") ?? "") ?? .medium }
        set { store.set(newValue.rawValue, forKey: "cordLength"); onChange?(.cord) }
    }
    var size: CharmSize {
        get { CharmSize(rawValue: store.string(forKey: "size") ?? "") ?? .medium }
        set { store.set(newValue.rawValue, forKey: "size"); onChange?(.size) }
    }
    var swing: Swing {
        get { Swing(rawValue: store.string(forKey: "swing") ?? "") ?? .natural }
        set { store.set(newValue.rawValue, forKey: "swing"); onChange?(.swing) }
    }
    var hangPoint: HangPoint {
        get { HangPoint(rawValue: store.string(forKey: "hangPoint") ?? "") ?? .menuBarIcon }
        set { store.set(newValue.rawValue, forKey: "hangPoint"); onChange?(.placement) }
    }
    /// Where the hook was last dropped with ⌥-drag, measured from the right edge of the display.
    var customOffsetFromRight: Double? {
        get { store.object(forKey: "customOffsetFromRight") as? Double }
        set { store.set(newValue, forKey: "customOffsetFromRight") }
    }
    var followsPointerAcrossDisplays: Bool {
        get { store.object(forKey: "followsPointer") as? Bool ?? true }
        set { store.set(newValue, forKey: "followsPointer"); onChange?(.placement) }
    }
    var breeze: Bool {
        get { store.object(forKey: "breeze") as? Bool ?? true }
        set { store.set(newValue, forKey: "breeze") }
    }
}
