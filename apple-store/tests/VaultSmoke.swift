import Foundation

@main struct VaultSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let resource = root.appendingPathComponent("Feather/Resources/StoreData.bin")
        StoreVault.testResourceURL = resource
        let data = try Data(contentsOf: resource)
        let input = try Data(contentsOf: root.appendingPathComponent("SOURCE_RESOURCES.json"))
        guard try StoreVault.openResource(data) == input else { fatalError("Resource mismatch") }
        let original = try StoreCatalogDocument.decode(Data(contentsOf: root.appendingPathComponent("build-report/plain-catalog.json")))
        guard let catalog = StoreVault.catalogData() else { fatalError("Missing catalog") }
        let decoded = try StoreCatalogDocument.decode(catalog)
        guard decoded.apps.map(\.id) == original.apps.map(\.id), decoded.apps.map(\.ipaUrl) == original.apps.map(\.ipaUrl) else { fatalError("Catalog changed") }
        guard StoreVault.url("catalog").path == "/apple-store/catalog.json",
              StoreVault.url("catalog").host == "pub-d11175355ab34b9299fb0a916702bce7.r2.dev",
              StoreLinks.support.absoluteString == "https://t.me/ellai95",
              StoreContacts.fallback.whatsapp == "https://wa.me/79667202220",
              StoreVault.text("AppleStoreLicense").contains("GNU GENERAL PUBLIC LICENSE") else { fatalError("Resource contents missing") }
        let cache = try StoreVault.sealCache(catalog)
        guard try StoreVault.openCache(cache) == catalog else { fatalError("Cache round trip failed") }
        let another = try StoreVault.sealCache(catalog)
        guard cache != another else { fatalError("Cache nonce reused") }
        var damaged = data; damaged[damaged.count / 2] ^= 1
        do { _ = try StoreVault.openResource(damaged); fatalError("Tampered resources accepted") } catch { }
        do { _ = try StoreVault.openCache(data); fatalError("Resource accepted as cache") } catch { }
        do { _ = try StoreVault.openResource(Data()); fatalError("Empty resource accepted") } catch { }
        print("PASS: resources, original IPA URLs, contacts, cache, random nonces and tamper rejection.")
    }
}
