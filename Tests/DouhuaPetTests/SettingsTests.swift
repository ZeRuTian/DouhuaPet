#if canImport(XCTest)
import Foundation
import XCTest
@testable import DouhuaPet

final class SettingsTests: XCTestCase {
    func testDefaultsAreSafeAndMatchTheProductDefaults() {
        withStore { store, _ in
            XCTAssertFalse(store.quiet)
            XCTAssertFalse(store.hidden)
            XCTAssertFalse(store.paused)
            XCTAssertEqual(store.size, .medium)
            XCTAssertEqual(store.activity, .quiet)
            XCTAssertEqual(store.normalizedX, 0.5)
            XCTAssertEqual(store.normalizedY, 0.5)
            XCTAssertNil(store.screenIdentifier)
        }
    }

    func testValuesPersistAcrossStoreInstances() {
        withStore { store, defaults in
            store.quiet = true
            store.hidden = true
            store.paused = true
            store.size = .large
            store.activity = .active
            store.savePosition(normalizedX: 0.2, normalizedY: 0.8, screenIdentifier: "display-2")

            let restored = PetSettingsStore(defaults: defaults)
            XCTAssertTrue(restored.quiet)
            XCTAssertTrue(restored.hidden)
            XCTAssertTrue(restored.paused)
            XCTAssertEqual(restored.size, .large)
            XCTAssertEqual(restored.activity, .active)
            XCTAssertEqual(restored.normalizedX, 0.2)
            XCTAssertEqual(restored.normalizedY, 0.8)
            XCTAssertEqual(restored.screenIdentifier, "display-2")
        }
    }

    func testCoordinatesAreClampedAndNonFiniteValuesUseDefaults() {
        withStore { store, _ in
            store.normalizedX = -2
            store.normalizedY = 4
            XCTAssertEqual(store.normalizedX, 0)
            XCTAssertEqual(store.normalizedY, 1)

            store.normalizedX = .nan
            store.normalizedY = .infinity
            XCTAssertEqual(store.normalizedX, PetSettingsStore.defaultNormalizedX)
            XCTAssertEqual(store.normalizedY, PetSettingsStore.defaultNormalizedY)
        }
    }

    func testCorruptPersistedValuesFallBackOrClampSafely() {
        withStore { store, defaults in
            defaults.set("yes", forKey: PetSettingsStore.StorageKey.quiet.rawValue)
            defaults.set("giant", forKey: PetSettingsStore.StorageKey.size.rawValue)
            defaults.set("restless", forKey: PetSettingsStore.StorageKey.activity.rawValue)
            defaults.set(-0.25, forKey: PetSettingsStore.StorageKey.normalizedX.rawValue)
            defaults.set(1.25, forKey: PetSettingsStore.StorageKey.normalizedY.rawValue)
            defaults.set(42, forKey: PetSettingsStore.StorageKey.screenIdentifier.rawValue)

            XCTAssertFalse(store.quiet)
            XCTAssertEqual(store.size, .medium)
            XCTAssertEqual(store.activity, .quiet)
            XCTAssertEqual(store.normalizedX, 0)
            XCTAssertEqual(store.normalizedY, 1)
            XCTAssertNil(store.screenIdentifier)
        }
    }

    func testBlankScreenIdentifierIsTreatedAsMissing() {
        withStore { store, defaults in
            store.screenIdentifier = "  display-main \n"
            XCTAssertEqual(store.screenIdentifier, "display-main")

            store.screenIdentifier = " \t "
            XCTAssertNil(store.screenIdentifier)
            XCTAssertNil(defaults.object(forKey: PetSettingsStore.StorageKey.screenIdentifier.rawValue))
        }
    }

    func testResetRemovesEveryStoredValue() {
        withStore { store, defaults in
            store.quiet = true
            store.hidden = true
            store.paused = true
            store.size = .small
            store.activity = .standard
            store.savePosition(normalizedX: 0.1, normalizedY: 0.9, screenIdentifier: "display-main")

            store.reset()

            XCTAssertFalse(store.quiet)
            XCTAssertFalse(store.hidden)
            XCTAssertFalse(store.paused)
            XCTAssertEqual(store.size, .medium)
            XCTAssertEqual(store.activity, .quiet)
            XCTAssertEqual(store.normalizedX, 0.5)
            XCTAssertEqual(store.normalizedY, 0.5)
            XCTAssertNil(store.screenIdentifier)
            for key in PetSettingsStore.StorageKey.allCases {
                XCTAssertNil(defaults.object(forKey: key.rawValue))
            }
        }
    }

    private func withStore(_ body: (PetSettingsStore, UserDefaults) -> Void) {
        let suiteName = "DouhuaPet.SettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(PetSettingsStore(defaults: defaults), defaults)
    }
}
#endif
