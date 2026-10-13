// macOS SwiftUI render test for the actual StoreProgressRing source.
// Deliberately provides NO environment object, matching the formerly broken inset.
// Only the install model/style are lightweight fixtures: no download, signing or keys.
import SwiftUI
import AppKit

@MainActor final class StorePipeline: ObservableObject {
    enum Stage: String {
        case idle, downloading, importing, signing, packaging, confirming
        case transferring, handedOff, completed, failed
        var title: String { rawValue }
    }
    @Published var stage: Stage = .idle
    @Published var progress: Double?
    var busy: Bool { ![.idle, .failed, .completed, .handedOff].contains(stage) }
}

enum StoreStyle {
    static let blue = Color.blue
    static let gradient = LinearGradient(colors: [.blue, .cyan], startPoint: .top, endPoint: .bottom)
}

@main struct ProgressSmoke {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let model = StorePipeline()
        let cases: [(StorePipeline.Stage, Double?)] = [
            (.downloading, nil), (.downloading, 0), (.downloading, 0.45),
            (.importing, nil), (.signing, nil), (.packaging, 0.7),
            (.confirming, nil), (.transferring, 1), (.failed, nil),
            (.handedOff, nil), (.completed, 1)
        ]
        for (index, item) in cases.enumerated() {
            model.stage = item.0
            model.progress = item.1
            let view = StoreProgressRing(pipeline: model).frame(width: 64, height: 64)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("No rendered progress image: \(item.0)") }
            precondition(image.width == 128 && image.height == 128)
            guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                fatalError("Could not encode progress render")
            }
            try png.write(to: output.appendingPathComponent("progress-\(index)-\(item.0.rawValue).png"))
        }
        print("PASS: actual StoreProgressRing rendered in 11 install states without an environment object.")
    }
}
