import Foundation
@main struct DiagnosticsSmoke {
    static func main() {
        let secret = "password=secret p12 private.mobileprovision https://example.com/install?token=private /Users/private"
        let timeout = NSError(domain:NSURLErrorDomain,code:NSURLErrorTimedOut,userInfo:[NSLocalizedDescriptionKey:secret,NSUnderlyingErrorKey:NSError(domain:"private",code:1)])
        let d=StoreDiagnostic.classify(timeout,stage:"downloading")
        precondition(d.category == "network.timeout")
        let report=d.report(version:"4.8",build:470,ios:"18.0",bytes:100)
        for marker in ["secret","private","https://","/Users/"] { precondition(!report.contains(marker)) }
        let disk=StoreDiagnostic.classify(NSError(domain:NSCocoaErrorDomain,code:NSFileWriteOutOfSpaceError),stage:"packaging")
        precondition(disk.category == "storage.full")
        let unknown=StoreDiagnostic.classify(NSError(domain:secret,code:9,userInfo:[NSLocalizedDescriptionKey:"unknown failure"]),stage:secret)
        precondition(unknown.domain == "Application")
        precondition(!unknown.report(version:secret,build:470,ios:secret,bytes:-100).contains(secret))
        for stage in ["importing","signing","confirming"] {
            let e=StoreDiagnostic.classify(NSError(domain:"App",code:1),stage:stage)
            precondition(!e.action.isEmpty && !e.reason.isEmpty)
        }
        print("PASS: network/storage/import/sign/install diagnostics and strict report privacy whitelist.")
    }
}
