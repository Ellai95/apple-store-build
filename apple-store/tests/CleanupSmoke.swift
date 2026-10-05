import Foundation

@main struct CleanupSmoke {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func main() throws {
        let suite = "AppleStoreCleanupTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(StoreCleanup.enabled(defaults), "Fresh and existing users default to enabled")
        defaults.set(false, forKey: StoreCleanup.preference)
        check(!StoreCleanup.enabled(defaults), "Opt-out must survive subsequent access")
        defaults.set(true, forKey: StoreCleanup.preference)
        check(StoreCleanup.enabled(defaults), "Opt-in")

        let full = StorePayloadTransfers()
        check(!full.closeAfterCompleteTransfer(), "Never delivered")
        check(full.begin(), "Accept GET")
        check(!full.closeWhenIdle(), "Do not remove a streaming archive")
        check(!full.finish(success: false, bytes: 0...99, total: 100), "Failed body is not a full transfer")
        check(!full.closeAfterCompleteTransfer(), "Keep failed IPA")
        check(full.begin(), "Retry")
        check(full.finish(success: true, bytes: 0...99, total: 100), "Successful retry")
        check(full.closeAfterCompleteTransfer(), "Safe retirement")
        check(!full.begin(), "No new requests after retirement")

        let ranges = StorePayloadTransfers()
        check(ranges.begin() && ranges.begin(), "Concurrent reads")
        check(!ranges.finish(success: true, bytes: 50...99, total: 100), "Half the archive isn't enough")
        check(!ranges.closeAfterCompleteTransfer(), "Keep active IPA")
        check(ranges.finish(success: true, bytes: 0...49, total: 100), "Reassembled complete archive")
        check(ranges.begin(), "Retry remains possible during grace period")
        check(!ranges.closeAfterCompleteTransfer(), "Completed archive with active retry is protected")
        check(ranges.finish(success: true, bytes: 0...99, total: 100), "Retry delivered")
        check(ranges.closeAfterCompleteTransfer(), "No active streams left")

        let gaps = StorePayloadTransfers()
        check(gaps.begin(), "first")
        check(!gaps.finish(success: true, bytes: 0...39, total: 100), "Partial")
        check(gaps.begin(), "second")
        check(!gaps.finish(success: true, bytes: 50...99, total: 100), "Gap must not be considered complete")
        check(!gaps.closeAfterCompleteTransfer(), "Preserve incomplete archive")
        check(gaps.begin(), "third")
        check(gaps.finish(success: true, bytes: 30...60, total: 100), "Overlapping ranges fill gap")
        check(StorePayloadTransfers.bytes(range: nil, total: 100, isGET: false) == nil, "HEAD does not transfer an IPA")
        check(StorePayloadTransfers.bytes(range: nil, total: 100, isGET: true) == 0...99, "Full GET")
        check(StorePayloadTransfers.bytes(range: "bytes=50-", total: 100, isGET: true) == 50...99, "Open end")
        check(StorePayloadTransfers.bytes(range: "bytes=-20", total: 100, isGET: true) == 80...99, "Suffix")
        check(StorePayloadTransfers.bytes(range: "bytes=0-999", total: 100, isGET: true) == 0...99, "Clamp to file")
        for invalid in ["bytes=100-", "bytes=10-1", "bytes=a-b", "bytes=0-5,8-10", "bytes=-0"] {
            check(StorePayloadTransfers.bytes(range: invalid, total: 100, isGET: true) == nil, "Malformed/unsupported range")
        }

        let base = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupFixture-" + UUID().uuidString, isDirectory: true)
        let root = base.appendingPathComponent("tmp", isDirectory: true)
        let outside = base.appendingPathComponent("Files", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        func archive(_ parent: URL) throws -> URL {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let file = parent.appendingPathComponent("Archive.ipa")
            try Data([80,75,3,4]).write(to: file)
            return file
        }
        let completed = try archive(root.appendingPathComponent("FeatherInstall_" + UUID().uuidString))
        let failed = try archive(root.appendingPathComponent("FeatherInstall_" + UUID().uuidString))
        let original = try archive(outside.appendingPathComponent("FeatherInstall_" + UUID().uuidString))
        let certificate = root.appendingPathComponent("certificate.p12")
        try Data([1,2,3]).write(to: certificate)
        let journal = StoreCleanupJournal(defaults: defaults, root: root)
        journal.remember(completed)
        journal.remember(original) // Must be ignored even with a matching folder name.
        let link = root.appendingPathComponent("FeatherInstall_" + UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original.deletingLastPathComponent())
        journal.remember(link.appendingPathComponent("Archive.ipa"))
        check(!journal.remove(original), "Reject external path")
        check(!journal.remove(link.appendingPathComponent("Archive.ipa")), "Reject symlink escape")
        StoreCleanupJournal(defaults: defaults, root: root).recoverCompletedHandoffs()
        check(!FileManager.default.fileExists(atPath: completed.path), "Restart removes only completed handoff")
        check(FileManager.default.fileExists(atPath: failed.path), "Unfinished IPA remains")
        check(FileManager.default.fileExists(atPath: original.path), "Files original remains")
        check(FileManager.default.fileExists(atPath: certificate.path), "Certificate remains")
        journal.recoverCompletedHandoffs() // Idempotent.
        print("PASS: opt-out, interrupted/retried/full/ranged/overlapping transfers, active stream gate, restart cleanup, unrelated files and certificates.")
    }
}
