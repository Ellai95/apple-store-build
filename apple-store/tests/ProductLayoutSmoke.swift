import Foundation

@main struct ProductLayoutSmoke {
    static func main() {
        let samples = [CGSize(width: 1320, height: 2868), CGSize(width: 392, height: 696),
                       CGSize(width: 1920, height: 1080), CGSize(width: 1080, height: 1080)]
        for source in samples {
            for available in [CGFloat(240), CGFloat(280), CGFloat(353), CGFloat(720)] {
                let result = StoreProductScreenshotGeometry.fitted(source, availableWidth: available)
                precondition(result.width > 0 && result.height > 0)
                precondition(result.width <= available + 0.001 && result.height <= 500.001)
                precondition(abs(result.width / result.height - source.width / source.height) < 0.0001, "Screenshot was stretched or cropped")
            }
        }
        let landscape = StoreProductScreenshotGeometry.fitted(samples[2], availableWidth: 353)
        precondition(abs(landscape.width - 353) < 0.001 && landscape.height < 200)
        let invalid = StoreProductScreenshotGeometry.fitted(CGSize(width: 0, height: 0), availableWidth: 200)
        precondition(invalid.width <= 200 && invalid.height <= 500)
        print("PASS: all product image orientations keep their own aspect ratio and fit the available width.")
    }
}
