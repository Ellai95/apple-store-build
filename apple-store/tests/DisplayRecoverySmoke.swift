import Foundation

@main struct DisplayRecoverySmoke {
    static func main() {
        let suite = "AppStorePlus.DisplayRecoveryTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("saved-certificate", forKey: "AppleStore.activeCertificate")
        defaults.set("glass", forKey: "AppleStore.selectedTheme")
        defaults.set(120, forKey: "AppleStore.plus.frameRate")
        StoreDisplayRecovery.beginLaunch(defaults: defaults)
        precondition(defaults.string(forKey: "AppleStore.selectedTheme") == "classic")
        precondition(defaults.integer(forKey: "AppleStore.plus.frameRate") == 0)
        precondition(defaults.string(forKey: "AppleStore.activeCertificate") == "saved-certificate")
        StoreDisplayRecovery.markReady(defaults: defaults)
        defaults.set("glass", forKey: "AppleStore.selectedTheme")
        defaults.set(120, forKey: "AppleStore.plus.frameRate")
        StoreDisplayRecovery.beginLaunch(defaults: defaults)
        precondition(defaults.string(forKey: "AppleStore.selectedTheme") == "glass")
        precondition(defaults.integer(forKey: "AppleStore.plus.frameRate") == 120)
        // No markReady: the previous launch did not finish its display setup.
        StoreDisplayRecovery.beginLaunch(defaults: defaults)
        precondition(defaults.string(forKey: "AppleStore.selectedTheme") == "classic")
        precondition(defaults.integer(forKey: "AppleStore.plus.frameRate") == 0)
        precondition(defaults.string(forKey: "AppleStore.activeCertificate") == "saved-certificate")
        print("PASS: display migration, healthy-launch preservation, interrupted-launch recovery; certificate selection retained.")
    }
}
