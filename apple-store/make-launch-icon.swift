// Build-time launch asset masking. Keep the original artwork and app icon unchanged.
import AppKit
import Foundation
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: input),
      let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot create launch asset") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
NSColor.clear.setFill(); rect.fill(using: .copy)
NSBezierPath(roundedRect: rect, xRadius: 235, yRadius: 235).addClip()
image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: output, options: .atomic)
for point in [(0, 0), (1023, 0), (0, 1023), (1023, 1023)] {
    precondition(bitmap.colorAt(x: point.0, y: point.1)!.alphaComponent == 0, "Corner is not transparent")
}
precondition(bitmap.colorAt(x: 512, y: 512)!.alphaComponent > 0.99)
print("PASS: launch icon uses original artwork, rounded corners and transparent exterior")
