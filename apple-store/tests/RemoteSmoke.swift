import Foundation
import CryptoKit

// Foundation-only fixtures let macOS CI exercise the exact shipping decoder.
enum StoreVault {
    static func link(_ key: String) -> String { "https://t.me/example" }
    static func url(_ key: String) -> URL { URL(string: link(key))! }
}
@main struct RemoteSmoke {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let doc = try StoreRemoteDocument.decode(data)
        let plan = doc.purchase.tariffs[2]
        let url = doc.purchase.url(for: plan)!
        let message = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
        precondition(url.host == "t.me" && url.path == "/ellai95")
        precondition(message.contains("2000") && message.contains("90 дней") && !message.contains("{price}"))
        let initial = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        func reject(_ mutate: (inout [String: Any]) -> Void) throws {
            var value = initial; mutate(&value)
            let bytes = try JSONSerialization.data(withJSONObject: value)
            do { _ = try StoreRemoteDocument.decode(bytes); fatalError("Invalid configuration accepted") }
            catch StoreRemoteDocument.Invalid.document { }
        }
        try reject { $0["schemaVersion"] = 2 }
        try reject { var p = $0["purchase"] as! [String: Any]; p["recipient"] = "https://evil.invalid/ellai95"; $0["purchase"] = p }
        try reject { var p = $0["layout"] as! [String: Any]; p["tabs"] = ["catalog"]; $0["layout"] = p }
        try reject { var p = $0["appearance"] as! [String: Any]; p["accent"] = "red"; $0["appearance"] = p }
        try reject { var p = $0["update"] as! [String: Any]; p["enabled"] = true; $0["update"] = p }
        let news = StoreRemoteDocument.News(id: "test", enabled: true, title: "Test", text: "", button: "", action: "none", url: nil, modal: true, minBuild: 400, maxBuild: 410, startsAt: nil, endsAt: nil)
        precondition(!news.active(build: 399) && news.active(build: 400) && !news.active(build: 411))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("release fixture".utf8)
        let file = directory.appendingPathComponent("Application.ipa")
        try bytes.write(to: file)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let release = StoreRemoteDocument.Update(enabled: true, version: "4.1", build: 401, ipaURL: "https://example.com/app.ipa", sha256: digest, bundleID: "ru.ipa95.applestore", sizeBytes: Int64(bytes.count), minimumIOS: "15.0", notes: [])
        precondition(release.newer(than: 400) && !release.newer(than: 401))
        try StoreUpdateVerifier.archive(file, release: release)
        let plist: [String: Any] = ["CFBundleIdentifier": release.bundleID, "CFBundleDisplayName": "Apple Store", "CFBundleShortVersionString": "4.1", "CFBundleVersion": "401"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: directory.appendingPathComponent("Info.plist"))
        try StoreUpdateVerifier.identity(directory, release: release, own: release.bundleID, build: 400)
        do { try StoreUpdateVerifier.identity(directory, release: release, own: "other.app", build: 400); fatalError("Wrong identity accepted") } catch StoreUpdateVerifier.Failure.identity { }
        try Data("corrupt fixture".utf8).write(to: file)
        do { try StoreUpdateVerifier.archive(file, release: release); fatalError("Corrupt update accepted") } catch StoreUpdateVerifier.Failure.file { }
        print("PASS: remote schema, recipient, template, layout, colors, targeting, release version/hash/identity.")
    }
}
