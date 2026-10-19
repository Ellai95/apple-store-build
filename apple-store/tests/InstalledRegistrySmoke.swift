import Foundation
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
protocol ObservableObject: AnyObject {}
struct StoreApp { let id:String; let version:String; let bundleIdentifier:String?; var kind="mod" }
enum StoreSystemApps {
    static var values: [String:(Bool?,String?,Date?)] = [:]
    static var opened: String?
    static func info(_ id:String) -> (Bool?,String?,Date?) { values[id] ?? (nil,nil,nil) }
    static func open(_ id:String) -> Bool { opened=id;return values[id]?.0 == true }
}
@main struct InstalledRegistrySmoke {
    @MainActor static func wait(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds:10_000_000)
        }
        preconditionFailure("Asynchronous installed-app probe did not complete")
    }
    @MainActor static func main() async {
        UserDefaults.standard.removeObject(forKey:"AppleStore.catalogInstallationRecords.v1")
        let manager=StoreInstalledApps.shared
        let original=Date(timeIntervalSince1970:100), replacement=Date(timeIntervalSince1970:200)
        let app=StoreApp(id:"wa",version:"2.0",bundleIdentifier:"catalog.id")
        StoreSystemApps.values["signed.actual.id"]=(true,"1.0",original)
        let probe=StoreApp(id:"probe",version:"1.0",bundleIdentifier:"signed.actual.id")
        await wait { manager.action(probe) == .open }
        manager.remember(app,bundleID:"signed.actual.id",version:"2.0")
        // Signing/preparing a new version must not turn the old installed version into a successful update.
        precondition(manager.action(app) == .update)
        StoreSystemApps.values["signed.actual.id"]=(true,"2.0",replacement);manager.refresh(force:true)
        await wait { manager.action(app) == .open }
        StoreSystemApps.values["signed.actual.id"]=(nil,nil,nil);manager.refresh(force:true)
        try? await Task.sleep(nanoseconds:300_000_000)
        precondition(manager.action(app).downloaded)
        let persisted = try! JSONDecoder().decode([String:StoreInstalledRecord].self,from:UserDefaults.standard.data(forKey:"AppleStore.catalogInstallationRecords.v1")!)
        precondition(persisted[app.id]?.confirmedInstalled == true)
        StoreSystemApps.values["signed.actual.id"]=(true,"2.0",replacement);manager.refresh(force:true)
        try? await Task.sleep(nanoseconds:300_000_000)
        manager.open(app);precondition(StoreSystemApps.opened == "signed.actual.id")
        let next=StoreApp(id:"wa",version:"3.0",bundleIdentifier:"catalog.id")
        precondition(manager.action(next) == .update)
        StoreSystemApps.values["signed.actual.id"]=(false,nil,nil);manager.refresh(force:true)
        await wait { manager.action(next) == .install }
        StoreSystemApps.values["signed.actual.id"]=(nil,nil,nil);manager.refresh(force:true)
        await wait { manager.action(next) == .verify }
        let mod=StoreApp(id:"mod",version:"13.0 + TGExtra 1.8.0",bundleIdentifier:"mod.id")
        StoreSystemApps.values["mod.id"]=(true,"13.0",original)
        await wait { manager.action(mod).downloaded }
        manager.remember(mod,bundleID:"mod.id",version:"13.0")
        precondition(manager.action(mod) == .update)
        StoreSystemApps.values["mod.id"]=(true,"13.0",replacement);manager.refresh(force:true)
        await wait { manager.action(mod) == .open }
        print("PASS: actual registry waits for system confirmation, retains old version after failed update, detects uninstall/unknown, opens actual signed ID and handles same-version mod replacement.")
    }
}
