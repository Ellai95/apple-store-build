import Foundation

@main struct BundleIDSmoke {
    static func main() throws {
        for id in ["com.example.copy", "ru.ipa95.copy.whatsapp", "com.Example-2.app"] {
            precondition(StoreBundleID.error(id) == nil)
        }
        for id in ["", "   ", "com", "com..copy", ".com.app", "com.app.", "com.приложение", "com.app_*", "com app.copy", "com.app\ncopy", String(repeating: "a", count: 201)+".app"] {
            precondition(StoreBundleID.error(id) != nil, id)
        }
        precondition(StoreBundleID.cleaned(" com.example.app \n") == "com.example.app")
        precondition(StoreBundleID.error("com.example.app", original: "com.example.app") != nil)
        precondition(StoreBundleID.error("COM.example.app", original: "com.example.app") != nil)
        precondition(StoreBundleID.error("ru.ipa95.applestore", own: "ru.ipa95.applestore") != nil)
        precondition(StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.*"))
        precondition(StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.com.example.*"))
        precondition(!StoreBundleID.permits("com.examplex.app", applicationIdentifier: "TEAM123456.com.example.*"))
        precondition(!StoreBundleID.permits("com.example.app.copy", applicationIdentifier: "TEAM123456.com.example.app"))
        precondition(StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.com.example.app"))
        precondition(!StoreBundleID.permits("com.example.app", applicationIdentifier: "invalid"))
        precondition(!StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.com.*.app"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plist = dir.appendingPathComponent("Info.plist")
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "net.example.actualIPA", "CFBundleName": "Unrelated name"], format: format, options: 0)
            try data.write(to: plist)
            let actual = try StoreBundleID.original(in: dir)
            precondition(actual == "net.example.actualIPA")
        }
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "No identifier"], format: .binary, options: 0).write(to: plist)
        var rejected = false
        do { _ = try StoreBundleID.original(in: dir) } catch { rejected = true }
        precondition(rejected)
        precondition(StoreBundleID.permittedPattern(" TEAM123456.com.example.* \n") == "com.example.*")
        precondition(StoreBundleID.permits("com.example.app.copy", applicationIdentifier: "TEAM123456.com.example.*"))
        precondition(!StoreBundleID.permits("ru.ipa95.copy.catalog-whatsapp", applicationIdentifier: "TEAM123456.com.example.*"))
        print("PASS: Bundle ID syntax, same-ID guard, original IPA XML/binary extraction, explicit/wildcard profile matching")
    }
}
