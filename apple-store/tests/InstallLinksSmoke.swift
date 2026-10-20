import Foundation
@main struct InstallLinksSmoke {
    static func main() {
        let name = "A&B + Тест #1 / 100%"
        let service = URL(string: "https://example.invalid/genPlist")!
        let payload = URL(string: "http://127.0.0.1:4567/operation.ipa")!
        let manifest = StoreInstallationLinks.externalManifest(service: service, bundleID: "test.bundle",
                                                              name: name, version: "2.0+1", payload: payload)!
        let values = Dictionary(uniqueKeysWithValues: URLComponents(url: manifest, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
        precondition(values["name"] == name && values["version"] == "2.0+1")
        precondition(values["fetchurl"] == payload.absoluteString && values.count == 4)
        precondition(!URLComponents(url: manifest, resolvingAgainstBaseURL: false)!.percentEncodedQuery!.contains("+"))
        precondition(StoreInstallationLinks.install(manifest: manifest.absoluteString).hasPrefix("itms-services://?"))
        let link = URLComponents(string: StoreInstallationLinks.install(manifest: manifest.absoluteString))!
        precondition(link.scheme == "itms-services")
        precondition(link.queryItems?.first(where: { $0.name == "url" })?.value == manifest.absoluteString)
        precondition(StoreInstallationLinks.install(manifest: "file:///private/data") == "")
        precondition(StoreInstallationLinks.externalManifest(service: payload, bundleID: "x", name: name, version: "1", payload: payload) == nil)
        let transfers = StorePayloadTransfers()
        precondition(!transfers.isCompleteAndIdle())
        precondition(transfers.begin())
        precondition(!transfers.isCompleteAndIdle())
        precondition(transfers.finish(success: true, bytes: 0...99, total: 100))
        precondition(transfers.isCompleteAndIdle())
        precondition(transfers.begin(), "A readiness check must not prevent iOS from retrying the same IPA")
        precondition(!transfers.isCompleteAndIdle())
        precondition(transfers.finish(success: true, bytes: 0...99, total: 100))
        precondition(transfers.closeAfterCompleteTransfer())
        precondition(!transfers.begin(), "Only explicit retirement closes the server")
        print("PASS: nested installation URLs preserve delimiters, Unicode and the payload URL; reject unsupported schemes; readiness checks preserve retries")
    }
}
