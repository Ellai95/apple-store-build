import Foundation
enum StoreVault {
    static func link(_ key:String)->String { "https://t.me/ellai95" }
    static func url(_ key:String)->URL { URL(string:link(key))! }
}
@main struct ServicesSmoke {
    static func main() throws {
        let services = StoreServicesDocument.standard
        try services.validate()
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--defaults" {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
            try encoder.encode(services).write(to:URL(fileURLWithPath:CommandLine.arguments[2])); return
        }
        precondition(services.products.count == 5)
        let ps = services.products.first { $0.id == "playstation" }!
        precondition(ps.platforms == ["PS4","PS5"])
        precondition(ps.plans.compactMap(\.price) == [2500,4500,5500,6500])
        precondition(ps.plans.last!.previousPrice == 8000)
        let steam = services.products.first { $0.id == "steam" }!
        precondition(steam.plans[0].price == 2000 && steam.plans[0].period == "Навсегда")
        let gpt = services.products.first { $0.id == "chatgpt" }!
        precondition(gpt.plans.compactMap(\.price) == [1200,2500])
        let text = StoreServicesDocument.orderMessage(product:ps,plan:ps.plans.last!)
        precondition(text.contains("6500 ₽") && text.contains("1 год") && text.contains("EA Play + Deluxe"))
        for pair in [("https://t.me/ellai95",false),("https://wa.me/79667202220",true)] {
            let url = StoreServicesDocument.contactURL(base:pair.0,message:text,whatsapp:pair.1)!
            precondition(URLComponents(url:url,resolvingAgainstBaseURL:false)!.queryItems!.first!.value == text)
        }
        precondition(StoreServicesDocument.contactURL(base:"javascript:alert(1)",message:text,whatsapp:false) == nil)
        precondition(StoreServicesDocument.contactURL(base:"https://example.com",message:text,whatsapp:true) == nil)
        var json = try JSONSerialization.jsonObject(with:JSONEncoder().encode(services)) as! [String:Any]
        var products = json["products"] as! [[String:Any]]
        products.append(products[0]);json["products"] = products
        let invalid = try JSONDecoder().decode(StoreServicesDocument.self,from:JSONSerialization.data(withJSONObject:json))
        do { try invalid.validate(); preconditionFailure("Duplicate product accepted") } catch {}
        if CommandLine.arguments.count > 1 {
            let doc = try StoreRemoteDocument.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
            try doc.personalization?.services?.validate()
        }
        print("PASS: service prices, periods, sale price, platforms, order contacts and invalid-data validation.")
    }
}
