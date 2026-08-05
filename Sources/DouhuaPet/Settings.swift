import Foundation

enum PetSizePreset: String, CaseIterable, Sendable {
    case small
    case medium
    case large
}

enum PetActivityPreset: String, CaseIterable, Sendable {
    case quiet
    case standard
    case active
}

/// A small UserDefaults-backed store for preferences that should survive relaunches.
///
/// Values are read from the injected defaults instance on demand, so multiple store
/// instances using the same suite always observe the latest persisted state.
final class PetSettingsStore {
    enum StorageKey: String, CaseIterable {
        case quiet = "douhua.settings.quiet"
        case hidden = "douhua.settings.hidden"
        case paused = "douhua.settings.paused"
        case size = "douhua.settings.size"
        case activity = "douhua.settings.activity"
        case normalizedX = "douhua.position.normalizedX"
        case normalizedY = "douhua.position.normalizedY"
        case screenIdentifier = "douhua.position.screenIdentifier"
    }

    static let defaultSize: PetSizePreset = .medium
    static let defaultActivity: PetActivityPreset = .quiet
    static let defaultNormalizedX = 0.5
    static let defaultNormalizedY = 0.5

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var quiet: Bool {
        get { storedBool(for: .quiet, defaultValue: false) }
        set { defaults.set(newValue, forKey: StorageKey.quiet.rawValue) }
    }

    var hidden: Bool {
        get { storedBool(for: .hidden, defaultValue: false) }
        set { defaults.set(newValue, forKey: StorageKey.hidden.rawValue) }
    }

    var paused: Bool {
        get { storedBool(for: .paused, defaultValue: false) }
        set { defaults.set(newValue, forKey: StorageKey.paused.rawValue) }
    }

    var size: PetSizePreset {
        get {
            guard
                let rawValue = defaults.object(forKey: StorageKey.size.rawValue) as? String,
                let preset = PetSizePreset(rawValue: rawValue)
            else {
                return Self.defaultSize
            }
            return preset
        }
        set { defaults.set(newValue.rawValue, forKey: StorageKey.size.rawValue) }
    }

    var activity: PetActivityPreset {
        get {
            guard
                let rawValue = defaults.object(forKey: StorageKey.activity.rawValue) as? String,
                let preset = PetActivityPreset(rawValue: rawValue)
            else {
                return Self.defaultActivity
            }
            return preset
        }
        set { defaults.set(newValue.rawValue, forKey: StorageKey.activity.rawValue) }
    }

    var normalizedX: Double {
        get { storedCoordinate(for: .normalizedX, defaultValue: Self.defaultNormalizedX) }
        set {
            defaults.set(
                Self.clampedCoordinate(newValue, defaultValue: Self.defaultNormalizedX),
                forKey: StorageKey.normalizedX.rawValue
            )
        }
    }

    var normalizedY: Double {
        get { storedCoordinate(for: .normalizedY, defaultValue: Self.defaultNormalizedY) }
        set {
            defaults.set(
                Self.clampedCoordinate(newValue, defaultValue: Self.defaultNormalizedY),
                forKey: StorageKey.normalizedY.rawValue
            )
        }
    }

    /// Nil means that no restorable screen has been recorded yet.
    var screenIdentifier: String? {
        get {
            guard let value = defaults.object(forKey: StorageKey.screenIdentifier.rawValue) as? String else {
                return nil
            }
            return Self.sanitizedScreenIdentifier(value)
        }
        set {
            guard let value = newValue.flatMap(Self.sanitizedScreenIdentifier) else {
                defaults.removeObject(forKey: StorageKey.screenIdentifier.rawValue)
                return
            }
            defaults.set(value, forKey: StorageKey.screenIdentifier.rawValue)
        }
    }

    func savePosition(normalizedX: Double, normalizedY: Double, screenIdentifier: String?) {
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.screenIdentifier = screenIdentifier
    }

    func reset() {
        for key in StorageKey.allCases {
            defaults.removeObject(forKey: key.rawValue)
        }
    }

    private func storedBool(for key: StorageKey, defaultValue: Bool) -> Bool {
        guard let value = defaults.object(forKey: key.rawValue) else {
            return defaultValue
        }
        return (value as? NSNumber)?.boolValue ?? defaultValue
    }

    private func storedCoordinate(for key: StorageKey, defaultValue: Double) -> Double {
        guard let value = defaults.object(forKey: key.rawValue) as? NSNumber else {
            return defaultValue
        }
        return Self.clampedCoordinate(value.doubleValue, defaultValue: defaultValue)
    }

    private static func clampedCoordinate(_ value: Double, defaultValue: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, 0), 1)
    }

    private static func sanitizedScreenIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
