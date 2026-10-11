import Foundation

enum StoreVault {
    static func link(_ key: String) -> String { "https://t.me/example" }
    static func url(_ key: String) -> URL { URL(string: link(key))! }
}
@main struct AdvertisingSmoke {
    static func main() throws {
        let old = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let legacy = try StoreRemoteDocument.decode(old)
        precondition(legacy.advertisements == nil)
        let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        var ads = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        ads["enabled"] = true
        var campaign = (ads["campaigns"] as! [[String: Any]])[0]
        campaign["enabled"] = true
        ads["campaigns"] = [campaign]
        func decode(_ value: [String: Any]) throws -> StoreAdvertisingDocument {
            let result = try JSONDecoder().decode(StoreAdvertisingDocument.self, from: JSONSerialization.data(withJSONObject: value))
            try result.validate(); return result
        }
        let doc = try decode(ads)
        var config = try JSONSerialization.jsonObject(with: old) as! [String: Any]
        config["advertisements"] = ads
        let migrated = try StoreRemoteDocument.decode(JSONSerialization.data(withJSONObject: config))
        precondition(migrated.advertisements?.campaigns.count == 1)
        let code = String(repeating: "A", count: 32), other = String(repeating: "B", count: 32)
        let now = ISO8601DateFormatter().date(from: "2026-10-11T20:00:00Z")!
        var policy = StoreAdvertisingPolicy()
        precondition(policy.candidate(document: doc, build: 459, code: code, now: now, seen: []) == nil)
        let c = policy.candidate(document: doc, build: 460, code: code, now: now, seen: [])!
        policy.shown(c, at: now)
        precondition(policy.candidate(document: doc, build: 460, code: code, now: now.addingTimeInterval(301), seen: []) == nil)
        policy.newEntry()
        precondition(policy.candidate(document: doc, build: 460, code: code, now: now.addingTimeInterval(301), seen: []) != nil)
        campaign["mode"] = "interval"; ads["campaigns"] = [campaign]
        let interval = try decode(ads); var repeatPolicy = StoreAdvertisingPolicy()
        repeatPolicy.shown(interval.campaigns[0], at: now)
        precondition(repeatPolicy.candidate(document: interval, build: 460, code: code, now: now.addingTimeInterval(299), seen: []) == nil)
        precondition(repeatPolicy.candidate(document: interval, build: 460, code: code, now: now.addingTimeInterval(300), seen: []) != nil)
        campaign["mode"] = "once"; ads["campaigns"] = [campaign]
        let once = try decode(ads); let fresh = StoreAdvertisingPolicy()
        precondition(fresh.candidate(document: once, build: 460, code: code, now: now, seen: [campaign["id"] as! String]) == nil)
        ads["grants"] = [["code":code,"expiresAt":"2026-11-11T20:00:00Z"]]
        let exempt = try decode(ads)
        precondition(fresh.candidate(document: exempt, build: 460, code: code, now: now, seen: []) == nil)
        precondition(fresh.candidate(document: exempt, build: 460, code: other, now: now, seen: []) != nil)
        precondition(exempt.adFreeUntil(code: code, now: now.addingTimeInterval(40*86400)) == nil)
        ads["enabled"] = false
        let stopped = try decode(ads)
        precondition(fresh.candidate(document: stopped, build: 460, code: other, now: now, seen: []) == nil)
        func reject(_ mutation: (inout [String: Any]) -> Void) throws {
            var bad = ads; mutation(&bad)
            do { _ = try decode(bad); fatalError("Unsafe advertising configuration accepted") }
            catch StoreRemoteDocument.Invalid.document { }
        }
        try reject { var rows = $0["campaigns"] as! [[String:Any]]; rows[0]["intervalSeconds"] = 1; $0["campaigns"] = rows }
        try reject { var rows = $0["campaigns"] as! [[String:Any]]; rows[0]["imageURL"] = "http://example.com/a.png"; $0["campaigns"] = rows }
        try reject { var rows = $0["campaigns"] as! [[String:Any]]; rows[0]["buttons"] = [["id":"bad","title":"Bad","url":"javascript:alert(1)"]]; $0["campaigns"] = rows }
        try reject { $0["purchaseEnabled"] = true }
        try reject { $0["grants"] = [["code":"short","expiresAt":"never"]] }
        print("PASS: old configuration compatibility, targeting, entry/interval/once, individual grant and expiry, kill switch, unsafe payload rejection.")
    }
}
