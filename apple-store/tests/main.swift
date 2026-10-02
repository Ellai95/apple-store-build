import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}
let path = CommandLine.arguments[1]
let data = try Data(contentsOf: URL(fileURLWithPath: path))
let doc = try StoreCatalogDocument.decode(data)
expect(doc.apps.count >= 201, "Catalog lost entries")
let original = try JSONSerialization.jsonObject(with: data) as! [String: Any]
func rejects(_ mutate: (inout [String: Any]) -> Void, _ name: String) {
    var bad = original; mutate(&bad)
    do { _ = try StoreCatalogDocument.decode(JSONSerialization.data(withJSONObject: bad)); fatalError("Accepted invalid catalog: " + name) }
    catch { print("PASS reject " + name) }
}
rejects({ $0["schemaVersion"] = 999 }, "unsupported schema")
rejects({ $0["apps"] = [] }, "empty catalog")
rejects({ d in var a = d["apps"] as! [[String: Any]]; a.append(a[0]); d["apps"] = a }, "duplicate ids")
rejects({ d in var a = d["apps"] as! [[String: Any]]; a[0]["ipaUrl"] = "http://example.com/test.ipa"; d["apps"] = a }, "insecure IPA URL")
rejects({ d in var a = d["apps"] as! [[String: Any]]; a[0]["screenshots"] = ["file:///etc/passwd"]; d["apps"] = a }, "unsafe image URL")
rejects({ d in var a = d["apps"] as! [[String: Any]]; a[0]["rating"] = ["value": 9, "count": 1]; d["apps"] = a }, "invalid rating")
rejects({ d in var a = d["apps"] as! [[String: Any]]; a[0]["id"] = "../escape"; d["apps"] = a }, "invalid identity")
let whatsapp = doc.apps.first { $0.id == "whatsapp" }!
expect(whatsapp.matches(" ВАТСАП "), "Russian search alias failed")
expect(whatsapp.version == "26.38.10", "Existing WhatsApp version replaced")
expect(whatsapp.ipaUrl.contains("r2.dev"), "Existing IPA source replaced")
expect(!whatsapp.modFeatures.isEmpty, "Mod features lost")
let contact = doc.contacts.whatsappURL!
expect(contact.absoluteString == "https://wa.me/79667202220", "Incorrect contact")
let draft = StoreLinks.request("Тест & игра +", contact: contact)
let query = URLComponents(url: draft, resolvingAgainstBaseURL: false)!.queryItems!
expect(query.first { $0.name == "text" }!.value == "Здравствуйте! Добавьте, пожалуйста, Тест & игра +.", "Draft text escaped incorrectly")
expect(StoreCatalogDocument.secureURL("https://user:secret@example.com/file") == nil, "Credential URL accepted")
let encoded = try JSONEncoder().encode(doc)
let decoded = try StoreCatalogDocument.decode(encoded)
expect(decoded.apps.count == doc.apps.count && decoded.revision == doc.revision, "Cache serialization failed")
print("PASS catalog decoding, rejection cases, search, preservation, contacts and cache round-trip")
