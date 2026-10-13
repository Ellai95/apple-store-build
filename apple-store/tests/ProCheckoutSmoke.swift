import Foundation
enum StoreVault {
    static func link(_ key:String)->String { "https://t.me/ellai95" }
    static func url(_ key:String)->URL { URL(string:link(key))! }
}
@main struct ProCheckoutSmoke {
    static func main() throws {
        var root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
        root["personalization"]=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
        let doc=try StoreRemoteDocument.decode(JSONSerialization.data(withJSONObject:root)).personalization!
        let offer=StoreProPurchase.annualOffer(doc.pro)
        precondition(offer.price == 300 && offer.days == 365 && StoreProPurchase.paymentReady(doc.pro))
        precondition(doc.pro.payment?.ready == true && doc.pro.payment?.displayCard.count == 19)
        let device=String(repeating:"A",count:32), other=String(repeating:"B",count:32)
        var checkout=StoreProCheckoutState()
        precondition(!checkout.declaredPaid(paymentReady:true))
        checkout.showPayment();precondition(!checkout.declaredPaid(paymentReady:false))
        precondition(checkout.declaredPaid(paymentReady:true) && checkout.step == .receipt)
        precondition(!doc.pro.allows("premiumThemes",code:device))
        let message=StoreProPurchase.receiptMessage(code:device,offer:offer)
        let tg=StoreProPurchase.contactURL(base:"https://t.me/ellai95",message:message,whatsapp:false)!
        let wa=StoreProPurchase.contactURL(base:"https://wa.me/79667202220",message:message,whatsapp:true)!
        precondition(URLComponents(url:tg,resolvingAgainstBaseURL:false)!.queryItems![0].value! == message)
        precondition(URLComponents(url:wa,resolvingAgainstBaseURL:false)!.queryItems![0].value! == message)
        precondition(StoreProPurchase.contactURL(base:"javascript:alert(1)",message:message,whatsapp:false) == nil)
        let release=StoreProExtras.Release(id:"test",catalogID:"whatsapp",name:"WhatsApp+",version:"next",ipaURL:"https://example.com/beta.ipa",notes:"Preview",sizeBytes:1000,allowedCodes:[device],expiresAt:nil)
        precondition(release.visible(code:device) && !release.visible(code:other))
        precondition(release.app(base:nil).kind == "early")
        precondition(StoreProDownloadPolicy.canEnqueue(active:4,pro:true,duplicate:false))
        precondition(!StoreProDownloadPolicy.canEnqueue(active:5,pro:true,duplicate:false))
        precondition(!StoreProDownloadPolicy.canEnqueue(active:0,pro:false,duplicate:false))
        precondition(!StoreProDownloadPolicy.canEnqueue(active:0,pro:true,duplicate:true))
        print("PASS: 300/365 checkout, bank/SBP layout, contact links, no grant from payment click, targeted early audience, five-slot cap.")
    }
}
