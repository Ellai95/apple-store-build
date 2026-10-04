import Foundation
@main struct InstallDefaultsSmoke {
    static func main() {
        let suite = "AppleStore.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        StoreInstallationDefaults.apply(to: defaults)
        precondition(defaults.integer(forKey: "Feather.installationMethod") == 0)
        precondition(defaults.integer(forKey: "Feather.serverMethod") == 1)
        precondition(defaults.bool(forKey: "Feather.ipFix"))
        defaults.set(0, forKey: "Feather.serverMethod")
        defaults.set(false, forKey: "Feather.ipFix")
        StoreInstallationDefaults.apply(to: defaults)
        precondition(defaults.integer(forKey: "Feather.serverMethod") == 0)
        precondition(!defaults.bool(forKey: "Feather.ipFix"))
        defaults.removeObject(forKey: "AppleStore.installDefaultsV34")
        defaults.set(1, forKey: "Feather.installationMethod")
        StoreInstallationDefaults.apply(to: defaults)
        precondition(defaults.integer(forKey: "Feather.installationMethod") == 1)
        precondition(defaults.integer(forKey: "Feather.serverMethod") == 1)
        precondition(defaults.bool(forKey: "Feather.ipFix"))
        print("PASS fresh defaults, existing-user migration, preserved later choices and advanced method")
    }
}
