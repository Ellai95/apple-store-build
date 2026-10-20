import Foundation
@main struct InstalledSmoke {
    static func main() throws {
        #if APPSTORE_PLUS
        precondition(StoreInstalledPresence.resolve(proxy: false, state: false, workspace: true, placeholder: false) == true)
        precondition(StoreInstalledPresence.resolve(proxy: true, state: true, workspace: true, placeholder: true) == false)
        precondition(StoreInstalledPresence.resolve(proxy: nil, state: nil, workspace: nil, placeholder: nil) == nil)
        precondition(StoreInstalledPresence.resolve(proxy: false, state: nil, workspace: false, placeholder: nil) == false)
        #endif
        precondition(StoreInstalledVersions.action(installed:false,pending:false,currentVersion:"",catalogVersion:"1") == .install)
        precondition(StoreInstalledVersions.action(installed:nil,pending:true,currentVersion:"1",catalogVersion:"2") == .verify)
        precondition(StoreInstalledVersions.action(installed:true,pending:false,currentVersion:"26.40.10",catalogVersion:"26.40.10") == .open)
        precondition(StoreInstalledVersions.action(installed:true,pending:true,currentVersion:"26.40.10",catalogVersion:"26.41.2") == .update)
        precondition(StoreInstalledVersions.action(installed:true,pending:false,currentVersion:"v26.41.2",catalogVersion:"26.40.10") == .open)
        precondition(!StoreInstalledVersions.newer("1.0",than:"1.0.0"))
        precondition(StoreInstalledVersions.newer("13.0 + TGExtra 1.8.0",than:"13.0 + TGExtra 1.7.9"))
        precondition(StoreInstalledAction.open.downloaded)
        precondition(StoreInstalledAction.update.downloaded)
        precondition(!StoreInstalledAction.install.downloaded && !StoreInstalledAction.verify.downloaded)
        precondition(StoreInstalledAction.open.title == "Загружено")
        let record=StoreInstalledRecord(catalogID:"wa",bundleID:"custom.actual.id",version:"26.40.10",catalogVersion:"26.40.10")
        let decoded=try JSONDecoder().decode(StoreInstalledRecord.self,from:JSONEncoder().encode(record))
        precondition(decoded.bundleID == "custom.actual.id" && decoded.catalogVersion == record.catalogVersion)
        print("PASS: installed/open/update/unknown states, numeric mod versions, downgrade protection and persisted actual bundle identity.")
    }
}
