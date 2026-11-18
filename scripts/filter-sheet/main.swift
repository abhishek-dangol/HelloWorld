// Draws every filter in FilterLibrary on the sample picture, as one labelled image.
// Build and run from the repo root:
//   swiftc -O -o /tmp/filter-sheet scripts/filter-sheet/main.swift CinematiCam/Filters/*.swift CinematiCam/Processing/FilterEngine.swift
//   /tmp/filter-sheet CinematiCam/Assets.xcassets/FilterSample.imageset/sample.png out.png [intensity 0-1] [tile width]
import AppKit
import CoreImage

let arguments = CommandLine.arguments
guard arguments.count >= 3, let source = CIImage(contentsOf: URL(fileURLWithPath: arguments[1])) else {
    print("usage: filter-sheet <sample.png> <out.png> [intensity] [tile width]")
    exit(1)
}
let intensity = arguments.count > 3 ? Double(arguments[3]) ?? 0.8 : 0.8
let columns = 3
let tileWidth = arguments.count > 4 ? CGFloat(Double(arguments[4]) ?? 380) : 380
let scale = tileWidth / source.extent.width
let sample = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let tileHeight = sample.extent.height.rounded()
let labelHeight: CGFloat = 54
let gap: CGFloat = 14
let filters = FilterLibrary.all
let rows = Int(ceil(Double(filters.count) / Double(columns)))
let width = CGFloat(columns) * (tileWidth + gap) + gap
let height = CGFloat(rows) * (tileHeight + labelHeight + gap) + gap

let context = CIContext()
let engine = FilterEngine()
engine.intensity = intensity
let bitmap = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
bitmap.setFillColor(NSColor(white: 0.07, alpha: 1).cgColor)
bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)

for (index, filter) in filters.enumerated() {
    engine.selectedFilter = filter
    let output = engine.applyFilter(to: sample)
    guard let tile = context.createCGImage(output, from: sample.extent) else { continue }
    let x = gap + CGFloat(index % columns) * (tileWidth + gap)
    let y = height - gap - tileHeight - CGFloat(index / columns) * (tileHeight + labelHeight + gap)
    bitmap.draw(tile, in: CGRect(x: x, y: y, width: tileWidth, height: tileHeight))
    let label = NSAttributedString(string: filter.name, attributes: [
        .font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: NSColor.white
    ])
    label.draw(at: CGPoint(x: x + 4, y: y - labelHeight + 10))
}

let image = NSBitmapImageRep(cgImage: bitmap.makeImage()!)
try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: arguments[2]))
print("wrote \(arguments[2]) with \(filters.count) filters at intensity \(intensity)")
