import AppKit
import Foundation

let source = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let image = NSImage(contentsOf: source) else { fatalError("Cannot read icon image") }
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  let transform = NSAffineTransform()
  transform.scale(by: CGFloat(size) / 1024)
  transform.concat()
  let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
  NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200).addClip()
  let crop = NSRect(
    x: image.size.width * 0.14, y: image.size.height * 0.14, width: image.size.width * 0.72,
    height: image.size.height * 0.72)
  image.draw(in: rect, from: crop, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  try bitmap.representation(using: .png, properties: [:])!.write(
    to: destination.appendingPathComponent("app_icon_\(size).png"))
}
