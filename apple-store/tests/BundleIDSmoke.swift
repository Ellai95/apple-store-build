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
        precondition(StoreBundleID.error("ru.ipa95.applestore", own: "ru.ipa95.applestore") != nil)
        precondition(StoreBundleID.error("net.whatsapp.WhatsApp1") == nil)
        precondition(StoreBundleID.error("net.whatsapp.WhatsApp2") == nil)
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
        print("PASS: Bundle ID syntax, original IPA XML/binary extraction; existing ID accepted for updates")
    }
}
