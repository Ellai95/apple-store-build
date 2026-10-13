import Foundation
enum StoreVault {
    static func link(_ key: String) -> String { "https://t.me/ellai95" }
    static func url(_ key: String) -> URL { URL(string:link(key))! }
}
@main struct PersonalizationSmoke {
    static func main() throws {
        let legacy = try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
        let old = try StoreRemoteDocument.decode(legacy)
        precondition(old.personalization == nil)
        let preview = StorePersonalizationDocument.preview
        try preview.validate()
        precondition(preview.themes.count == 6 && preview.themes.contains { $0.style == "custom" })
        precondition(!preview.pro.testing && !preview.pro.purchaseEnabled)
        let code = String(repeating:"A",count:32); let other = String(repeating:"B",count:32)
        precondition(!preview.pro.allows("premiumThemes",code:code))
        let now = Date(timeIntervalSince1970:1_800_000_000)
        let activationHash = String(repeating:"c",count:64)
        let expiry = ISO8601DateFormatter().string(from:now.addingTimeInterval(30*86400))
        let pro = StorePersonalizationDocument.Pro(enabled:true,testing:false,purchaseEnabled:false,offers:[],paymentDetails:"",recipient:"https://t.me/ellai95",grants:[.init(code:code,expiresAt:expiry,features:["premiumThemes","noAds"],activationHash:activationHash)],features:["premiumThemes":true,"customWallpaper":true,"noAds":true])
        precondition(pro.allows("premiumThemes",code:code,activatedHash:activationHash,now:now))
        precondition(!pro.allows("premiumThemes",code:code,now:now))
        precondition(!pro.allows("premiumThemes",code:code,activatedHash:String(repeating:"d",count:64),now:now))
        precondition(StoreProActivation.normalized("PRO-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AAAA") == String(repeating:"A",count:32))
        precondition(StoreProActivation.normalized("wrong") == nil)
        precondition(!pro.allows("premiumThemes",code:other,activatedHash:activationHash,now:now))
        precondition(!pro.allows("customWallpaper",code:code,activatedHash:activationHash,now:now))
        precondition(!pro.allows("noAds",code:code,activatedHash:activationHash,now:now.addingTimeInterval(31*86400)))
        var root = try JSONSerialization.jsonObject(with:legacy) as! [String:Any]
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        var obj = try JSONSerialization.jsonObject(with:encoder.encode(preview)) as! [String:Any]
        root["personalization"] = obj
        let decoded = try StoreRemoteDocument.decode(JSONSerialization.data(withJSONObject:root))
        precondition(decoded.personalization?.themes.count == 6)
        func reject(_ mutate:(inout [String:Any])->Void) throws {
            var value = obj; mutate(&value); var document = root; document["personalization"] = value
            do { _ = try StoreRemoteDocument.decode(JSONSerialization.data(withJSONObject:document)); fatalError("Unsafe theme accepted") } catch { }
        }
        try reject { value in var list=value["themes"] as! [[String:Any]]; list[0]["accent"]="red";value["themes"]=list }
        try reject { value in var list=value["themes"] as! [[String:Any]];list[1]["imageURL"]="http://example.com/image.png";value["themes"]=list }
        try reject { value in var p=value["pro"] as! [String:Any];p["features"]=["signWithoutCertificate":true];value["pro"]=p }
        try reject { value in var p=value["pro"] as! [String:Any];p["purchaseEnabled"]=true;value["pro"]=p }
        let fixed = StoreWallpaperPreferences(dimming:10,blur:-1,surfaceOpacity:0.1,accent:"bad").validated()
        precondition(fixed.dimming == 0.8 && fixed.blur == 0 && fixed.surfaceOpacity == 0.85 && fixed.accent == "#1964F5")
        // A production template never carries preview access or invented prices.
        var p=obj["pro"] as! [String:Any];p["testing"]=false;obj["pro"]=p
        let production = try JSONDecoder().decode(StorePersonalizationDocument.self,from:JSONSerialization.data(withJSONObject:obj))
        try production.validate()
        if CommandLine.arguments.count > 2 { try JSONSerialization.data(withJSONObject:obj,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:CommandLine.arguments[2])) }
        print("PASS: legacy config, 6 themes, per-code Pro/expiry/feature gates, image/colors validation, safe preview/production split.")
    }
}
