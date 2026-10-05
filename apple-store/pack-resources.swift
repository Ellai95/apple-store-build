// Runs on the macOS build runner, before Xcode. No third-party packages.
import Foundation
import CryptoKit

guard CommandLine.arguments.count == 3 else {
    fatalError("Usage: swift pack-resources.swift SOURCE CUSTOMIZATION")
}
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let customization = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let resources = root.appendingPathComponent("Feather/Resources")
let report = root.appendingPathComponent("build-report")
let catalogURL = resources.appendingPathComponent("AppleStoreCatalog.json")
let catalogData = try Data(contentsOf: catalogURL)
let catalog = try JSONSerialization.jsonObject(with: catalogData)
let links = try JSONSerialization.jsonObject(with: Data(contentsOf: customization.appendingPathComponent("resource-links.json")))
var texts: [String: String] = [:]
for name in ["AppleStoreLicense", "AppleStoreNotices"] {
    texts[name] = try String(contentsOf: resources.appendingPathComponent(name + ".txt"), encoding: .utf8)
}
let plain = try JSONSerialization.data(withJSONObject: ["catalog": catalog, "links": links, "texts": texts], options: [.sortedKeys])
let key = SymmetricKey(size: .bits256)
let keyBytes = key.withUnsafeBytes { Array($0) }
let mask = SymmetricKey(size: .bits256).withUnsafeBytes { Array($0) }
let masked = zip(keyBytes, mask).map { $0.0 ^ $0.1 }
let box = try AES.GCM.seal(plain, using: key, authenticating: Data("store.resources.v1".utf8))
guard let sealed = box.combined else { fatalError("Missing encrypted resource") }
guard try AES.GCM.open(AES.GCM.SealedBox(combined: sealed), using: key, authenticating: Data("store.resources.v1".utf8)) == plain else {
    fatalError("Resource round trip failed")
}
let swiftFile = root.appendingPathComponent("Feather/AppleStore/StoreVault.swift")
var swift = try String(contentsOf: swiftFile, encoding: .utf8)
guard swift.contains("/*KEY_A*/"), swift.contains("/*KEY_B*/") else { fatalError("Prepare a clean source tree before packing") }
swift = swift.replacingOccurrences(of: "/*KEY_A*/", with: mask.map { String($0) }.joined(separator: ","))
             .replacingOccurrences(of: "/*KEY_B*/", with: masked.map { String($0) }.joined(separator: ","))
try sealed.write(to: resources.appendingPathComponent("StoreData.bin"), options: .atomic)
try swift.write(to: swiftFile, atomically: true, encoding: .utf8)
// Keep editable originals outside the application target, in corresponding source.
try plain.write(to: root.appendingPathComponent("SOURCE_RESOURCES.json"), options: .atomic)
try catalogData.write(to: report.appendingPathComponent("plain-catalog.json"), options: .atomic)
try FileManager.default.removeItem(at: catalogURL)
for name in texts.keys { try FileManager.default.removeItem(at: resources.appendingPathComponent(name + ".txt")) }
print("PASS: encrypted bundled catalog, links and notices; source originals retained outside app target.")
