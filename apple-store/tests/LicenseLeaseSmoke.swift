import Foundation

@main struct LicenseLeaseSmoke {
    static func main() throws {
        func status(_ extra: [String: Any] = [:]) throws -> StoreSubscription {
            var data: [String: Any] = ["accountID":"one", "status":"active", "deviceID":"device",
                "connectedAt":"2026-10-19T00:00:00Z", "expiresAt":"2026-10-19T00:00:30Z",
                "certificateExpiresAt":"2027-10-19T00:00:00Z", "remainingDays":1,
                "licenseExpiresAt":"2026-10-19T00:00:30Z", "serverTime":"2026-10-19T00:00:00Z",
                "requiresLicense":true]
            extra.forEach { data[$0.key] = $0.value }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(StoreSubscription.self, from: JSONSerialization.data(withJSONObject: data))
        }
        let finite = try status()
        precondition(StoreLicenseLease.deadline(finite, requestStartedUptime:1000) == 1030)
        let lifetime = try status(["lifetime":true,"licenseExpiresAt":NSNull()])
        precondition(StoreLicenseLease.deadline(lifetime, requestStartedUptime:1000) == 1900)
        let legacy = try status(["requiresLicense":false])
        precondition(StoreLicenseLease.deadline(legacy, requestStartedUptime:1000) == 0)
        let missingExpiry = try status(["licenseExpiresAt":NSNull()])
        precondition(StoreLicenseLease.deadline(missingExpiry, requestStartedUptime:1000) == 1000)
        let expired = try status(["status":"expired"])
        precondition(StoreLicenseLease.deadline(expired, requestStartedUptime:1000) == 0)
        let certificate = try status(["lifetime":true,"certificateExpiresAt":"2026-10-19T00:00:10Z"])
        precondition(StoreLicenseLease.deadline(certificate, requestStartedUptime:1000) == 1010)
        print("PASS: server-relative monotonic access deadlines, lifetime, expired state, missing paid marker and certificate bounds.")
    }
}
