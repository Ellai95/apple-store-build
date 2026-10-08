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
        let profileData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let profile = try JSONSerialization.jsonObject(with: profileData) as! [String: Any]
        var announcementFixture = initial
        announcementFixture["news"] = [profile["announcement"]!]
        let targeted = try StoreRemoteDocument.decode(JSONSerialization.data(withJSONObject: announcementFixture))
        precondition(targeted.news.count == 1)
        precondition(targeted.news[0].active(build: 400))
        precondition(!targeted.news[0].active(build: 420))
        precondition(targeted.news[0].modal && targeted.news[0].action == "update")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("release fixture".utf8)
        let file = directory.appendingPathComponent("Application.ipa")
        try bytes.write(to: file)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let release = StoreRemoteDocument.Update(enabled: true, version: "4.2", build: 420, ipaURL: "https://example.com/app.ipa", sha256: digest, bundleID: "ru.ipa95.applestore", sizeBytes: Int64(bytes.count), minimumIOS: "15.0", notes: [])
        precondition(release.newer(than: 400) && !release.newer(than: 420))
        try StoreUpdateVerifier.archive(file, release: release)
        let plist: [String: Any] = ["CFBundleIdentifier": release.bundleID, "CFBundleDisplayName": "Apple Store", "CFBundleShortVersionString": "4.2", "CFBundleVersion": "420"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: directory.appendingPathComponent("Info.plist"))
        try StoreUpdateVerifier.sourceIdentity(directory, release: release, build: 400)
        try StoreUpdateVerifier.signedIdentity(directory, release: release, installedID: release.bundleID, build: 400)
        let renamedID = "ru.ipa95.applestore.bot-assigned-123"
        precondition(StoreUpdateVerifier.validInstalledID(renamedID))
        precondition(!StoreUpdateVerifier.validInstalledID("bad id/../"))
        // The original download is valid; it must be renamed to the installed ID before handoff.
        do { try StoreUpdateVerifier.signedIdentity(directory, release: release, installedID: renamedID, build: 400); fatalError("Duplicate install would be allowed") } catch StoreUpdateVerifier.Failure.identity { }
        var renamed = plist
        renamed["CFBundleIdentifier"] = renamedID
        func writePlist(_ value: [String: Any]) throws {
            try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0).write(to: directory.appendingPathComponent("Info.plist"))
        }
        try writePlist(renamed)
        try StoreUpdateVerifier.signedIdentity(directory, release: release, installedID: renamedID, build: 400)
        do { try StoreUpdateVerifier.sourceIdentity(directory, release: release, build: 400); fatalError("Modified original download accepted") } catch StoreUpdateVerifier.Failure.identity { }
        do { try StoreUpdateVerifier.signedIdentity(directory, release: release, installedID: "different.app", build: 400); fatalError("Wrong signed ID accepted") } catch StoreUpdateVerifier.Failure.identity { }
        do { try StoreUpdateVerifier.signedIdentity(directory, release: release, installedID: renamedID, build: 420); fatalError("Same build accepted as an update") } catch StoreUpdateVerifier.Failure.identity { }
        renamed["CFBundleVersion"] = "421"
        try writePlist(renamed)
        do { try StoreUpdateVerifier.signedIdentity(directory, release: release, installedID: renamedID, build: 400); fatalError("Wrong build accepted") } catch StoreUpdateVerifier.Failure.identity { }
        try Data("corrupt fixture".utf8).write(to: file)
        do { try StoreUpdateVerifier.archive(file, release: release); fatalError("Corrupt update accepted") } catch StoreUpdateVerifier.Failure.file { }
        print("PASS: remote schema, recipient, template, layout, colors, targeting, release version/hash/identity.")
    }
}
