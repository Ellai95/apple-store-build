import Foundation

@main struct CatalogMergeSmoke {
    static func main() throws {
        let raw = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let doc = try StoreCatalogDocument.decode(raw)
        var newApps = doc.apps.filter { $0.bundledSupplement == true }
        let legacy = doc.apps.filter { $0.bundledSupplement != true }
        precondition(legacy.count >= 202)
        if newApps.isEmpty {
            var fixture = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy[0])) as! [String: Any]
            fixture["id"] = "merge-fixture-addition"
            fixture["bundleIdentifier"] = "com.example.merge.fixture"
            fixture["bundledSupplement"] = true
            fixture.removeValue(forKey: "appleMetadata")
            newApps = [try JSONDecoder().decode(StoreApp.self, from: JSONSerialization.data(withJSONObject: fixture))]
        }
        let bundled = legacy + newApps
        let merged = StoreCatalogDocument.merging(remote: legacy, bundled: bundled)
        precondition(merged.count == bundled.count, "Old online catalog removed bundled additions")
        precondition(Set(merged.map(\.id)).count == merged.count)
        let removed = legacy.dropFirst()
        let afterRemoval = StoreCatalogDocument.merging(remote: Array(removed), bundled: bundled)
        precondition(!afterRemoval.contains { $0.id == legacy[0].id }, "Removed legacy app was resurrected")

        var remoteNew = try JSONSerialization.jsonObject(with: JSONEncoder().encode(newApps[0])) as! [String: Any]
        remoteNew["id"] = "remote-same-bundle"
        remoteNew["version"] = "99.0"
        let incoming = try JSONDecoder().decode(StoreApp.self, from: JSONSerialization.data(withJSONObject: remoteNew))
        let sameBundle = StoreCatalogDocument.merging(remote: legacy + [incoming], bundled: bundled)
        precondition(sameBundle.count == bundled.count, "Same bundle duplicated under a different ID")
        precondition(!sameBundle.contains { $0.id == newApps[0].id })
        precondition(sameBundle.first { $0.id == incoming.id }?.version == "99.0", "Remote update was replaced")
        precondition(StoreCatalogDocument.merging(remote: doc.apps, bundled: doc.apps).count == doc.apps.count)
        print("PASS: bundled additions survive remote refresh; no duplicate bundles; removals and newer remote versions respected.")
    }
}
