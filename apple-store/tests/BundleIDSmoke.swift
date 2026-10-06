import Foundation

@main struct BundleIDSmoke {
    static func main() {
        for id in ["com.example.copy", "ru.ipa95.copy.whatsapp", "com.Example-2.app"] {
            precondition(StoreBundleID.error(id) == nil)
        }
        for id in ["", "   ", "com", "com..copy", ".com.app", "com.app.", "com.приложение", "com.app_*", "com app.copy", "com.app\ncopy", String(repeating: "a", count: 201)+".app"] {
            precondition(StoreBundleID.error(id) != nil, id)
        }
        precondition(StoreBundleID.cleaned(" com.example.app \n") == "com.example.app")
        precondition(StoreBundleID.error("com.example.app", original: "com.example.app") != nil)
        precondition(StoreBundleID.error("COM.example.app", original: "com.example.app") != nil)
        precondition(StoreBundleID.error("ru.ipa95.applestore", own: "ru.ipa95.applestore") != nil)
        precondition(StoreBundleID.suggested(original: "com.example.app", catalogID: "x") == "com.example.app.copy")
        precondition(StoreBundleID.error(StoreBundleID.suggested(original: nil, catalogID: "каталог:app-123")) == nil)
        precondition(StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.*"))
        precondition(StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.com.example.*"))
        precondition(!StoreBundleID.permits("com.examplex.app", applicationIdentifier: "TEAM123456.com.example.*"))
        precondition(!StoreBundleID.permits("com.example.app.copy", applicationIdentifier: "TEAM123456.com.example.app"))
        precondition(StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.com.example.app"))
        precondition(!StoreBundleID.permits("com.example.app", applicationIdentifier: "invalid"))
        precondition(!StoreBundleID.permits("com.example.app", applicationIdentifier: "TEAM123456.com.*.app"))
        print("PASS: Bundle ID syntax, same-ID guard, suggestions, explicit/wildcard profile matching")
    }
}
