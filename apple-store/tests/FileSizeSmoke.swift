import Foundation
@main struct FileSizeSmoke {
    static func main() {
        func response(_ status: Int, _ headers: [String: String]) -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "https://example.com/app.ipa")!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        }
        precondition(StoreSizeProbe.byteCount(response(200, ["Content-Length": "123456789"])) == 123456789)
        precondition(StoreSizeProbe.byteCount(response(206, ["Content-Length": "1", "Content-Range": "bytes 0-0/123456789"])) == 123456789)
        precondition(StoreSizeProbe.byteCount(response(403, ["Content-Length": "1234"])) == nil)
        precondition(StoreSizeProbe.byteCount(response(200, ["Content-Length": "1234", "Content-Type": "text/html"])) == nil)
        precondition(StoreSizeProbe.byteCount(response(200, ["Content-Length": "0"])) == nil)
        precondition(StoreSizeProbe.byteCount(response(206, ["Content-Length": "1", "Content-Range": "bytes 0-0/*"])) == nil)
        print("PASS real byte counts, partial content total, and rejection of errors/unknown lengths")
    }
}
