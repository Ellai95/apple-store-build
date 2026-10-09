import Foundation

@main struct NewsDismissalSmoke {
    static func main() {
        let suite = "AppleStore.NewsDismissalTest." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["whatsapp-26.40.10"], forKey: "AppleStore.seenNews")
        precondition(StoreNewsDismissals.load(defaults: defaults).isEmpty)
        let closed = StoreNewsDismissals.dismiss("whatsapp-26.40.10", defaults: defaults)
        precondition(closed == ["whatsapp-26.40.10"])
        let reopened = UserDefaults(suiteName: suite)!
        precondition(StoreNewsDismissals.load(defaults: reopened) == closed)
        precondition(!closed.contains("whatsapp-26.41.10"))
        precondition(StoreNewsDismissals.dismiss("whatsapp-26.40.10", defaults: defaults) == closed)
        precondition(StoreNewsDismissals.dismiss("", defaults: defaults) == closed)
        for index in 0..<105 { StoreNewsDismissals.dismiss("news-" + String(index), defaults: defaults) }
        let latest = StoreNewsDismissals.load(defaults: defaults)
        precondition(latest.count == 100 && latest.last == "news-104")
        precondition(!latest.contains("news-0"))
        print("PASS: banner closure persists, modal history remains separate, new IDs appear, duplicate closes are harmless.")
    }
}
