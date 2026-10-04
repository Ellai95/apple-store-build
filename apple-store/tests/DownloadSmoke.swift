import Foundation

private final class ProgressProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int64 = 0
    func record(_ bytes: Int64) { lock.lock(); count = max(count, bytes); lock.unlock() }
    var bytes: Int64 { lock.lock(); defer { lock.unlock() }; return count }
}

@main struct DownloadSmoke {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = CommandLine.arguments[1]
        func transfer(_ path: String, cancel: Bool = false, preCancel: Bool = false) async throws -> Int64 {
            let probe = ProgressProbe()
            let downloader = StoreDownloader(firstByteTimeout: 2, stallTimeout: 4, allowedSchemes: ["http"], changed: { _, bytes in probe.record(bytes) })
            let output = root.appendingPathComponent(UUID().uuidString + ".ipa")
            if preCancel { downloader.cancel() }
            let task = Task { try await downloader.download(from: URL(string: base + path)!, to: output) }
            if cancel { try await Task.sleep(nanoseconds: 150_000_000); task.cancel() }
            do {
                let file = try await task.value
                precondition(FileManager.default.fileExists(atPath: file.path), "Download file vanished")
                let data = try Data(contentsOf: file)
                precondition(data.starts(with: [0x50, 0x4b, 0x03, 0x04]), "Wrong contents")
                return probe.bytes
            } catch {
                precondition(!FileManager.default.fileExists(atPath: output.path), "Failed download left a file")
                throw error
            }
        }
        for path in ["/ipa", "/redirect", "/unknown-length"] {
            let bytes = try await transfer(path)
            precondition(bytes > 0, "No progress for " + path)
            print("PASS download, file lifetime and progress: " + path)
        }
        for (path, expected) in [("/denied", "HTTP 403"), ("/html", "не IPA"), ("/stall", "TIMEOUT")] {
            do { _ = try await transfer(path); fatalError("Expected failure: " + path) }
            catch { precondition(error.localizedDescription.contains(expected), error.localizedDescription); print("PASS error: " + path) }
        }
        for early in [false, true] {
            do { _ = try await transfer("/stall", cancel: !early, preCancel: early); fatalError("Expected cancellation") }
            catch is CancellationError { print("PASS cancellation before/during transfer: \(early)") }
        }
        // A failed/cancelled transfer must not poison the next attempt.
        _ = try await transfer("/ipa")
        print("PASS fresh retry; all downloader tests passed")
    }
}
