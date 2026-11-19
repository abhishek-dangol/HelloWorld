import CoreImage
import Foundation

/// Gives a finished photo the brightness and colour of the picture that was on screen when the
/// shutter was pressed, while keeping the photo's own fine detail (option D, 2026-11-19).
///
/// The screen picture is small (about 2 MP) but is exactly what the user saw; the real photo is
/// sharp but the iPhone develops it its own way (brighter or darker from shot to shot). Both
/// are shrunk to a small grid, lined up, and compared:
/// 1. one dark-to-light curve for the whole photo makes its spread of tones the screen's;
/// 2. a smooth map of gains, one per small area and colour, fixes what is left (a brighter
///    face, a warmer corner). Being smooth, it changes brightness and colour only, not detail.
/// When the two pictures do not line up (the phone moved a lot), only step 1 is used.
enum ScreenTransfer {
    /// Grid width; the height follows the photo's shape
    private static let gridWidth = 72
    /// How smooth the gain map is, in grid cells
    private static let gainBlur: Float = 1.6
    /// The most a gain map may change an area, either way
    private static let gainLimit: ClosedRange<Float> = 0.55...1.8
    /// Below this the two pictures are not the same view, and the gain map is skipped
    private static let minimumMatch: Float = 0.8

    struct Grid {
        let width: Int, height: Int
        /// Linear light, RGB per cell
        var r: [Float], g: [Float], b: [Float]

        func luma(_ i: Int) -> Float { 0.2126 * r[i] + 0.7152 * g[i] + 0.0722 * b[i] }
    }

    /// What was done, for the test log
    struct Report {
        var match: Float = 0, scale: Float = 1, shiftX: Float = 0, shiftY: Float = 0
        var usedGainMap = false
    }

    static func matched(_ photo: CIImage, to screen: CIImage, context: CIContext) -> CIImage {
        matchedWithReport(photo, to: screen, context: context).image
    }

    static func matchedWithReport(_ photo: CIImage, to screen: CIImage, context: CIContext) -> (image: CIImage, report: Report) {
        var report = Report()
        let extent = photo.extent
        guard !extent.isInfinite, extent.width > 8, extent.height > 8,
              !screen.extent.isInfinite, screen.extent.width > 8 else { return (photo, report) }
        let width = gridWidth
        let height = max(8, Int((CGFloat(width) * extent.height / extent.width).rounded()))
        // The screen grid is read a little larger than the photo's, so the photo's view can be
        // found inside it even when the two views differ slightly in size
        let margin: Float = 1.2
        let screenWidth = Int((Float(width) * margin).rounded()), screenHeight = Int((Float(height) * margin).rounded())
        guard let photoGrid = grid(of: photo, width: width, height: height, context: context),
              let screenGrid = grid(of: screen, width: screenWidth, height: screenHeight, context: context) else {
            return (photo, report)
        }

        // Line the screen picture up on the photo: the scale and shift where their light and
        // dark patterns agree best (brightness differences do not matter to this score)
        let (aligned, score, scale, shiftX, shiftY) = align(screenGrid, onto: photoGrid, margin: margin)
        report.match = score; report.scale = scale; report.shiftX = shiftX; report.shiftY = shiftY

        // 1. One curve for the whole photo (on screen-style values, 0-1)
        let table = toneTable(from: photoGrid, to: aligned)
        var result = photo
        if let curves = curveFilter(table) {
            curves.setValue(photo, forKey: kCIInputImageKey)
            result = curves.outputImage?.cropped(to: extent) ?? photo
        }

        // 2. The smooth gain map, only when the views clearly line up
        guard score >= minimumMatch else { return (result, report) }
        var curved = photoGrid
        for i in 0..<curved.r.count {
            curved.r[i] = throughTable(curved.r[i], table)
            curved.g[i] = throughTable(curved.g[i], table)
            curved.b[i] = throughTable(curved.b[i], table)
        }
        let blurredScreen = blurred(aligned), blurredPhoto = blurred(curved)
        var gains = [Float](repeating: 1, count: width * height * 4)
        let floor: Float = 0.004
        for i in 0..<width * height {
            gains[i * 4] = clampGain((blurredScreen.r[i] + floor) / (blurredPhoto.r[i] + floor))
            gains[i * 4 + 1] = clampGain((blurredScreen.g[i] + floor) / (blurredPhoto.g[i] + floor))
            gains[i * 4 + 2] = clampGain((blurredScreen.b[i] + floor) / (blurredPhoto.b[i] + floor))
            gains[i * 4 + 3] = 1
        }
        // Both the grid and a bitmap image list the top row first (checked on photo pairs)
        let data = gains.withUnsafeBufferPointer { Data(buffer: $0) }
        let gainImage = CIImage(bitmapData: data, bytesPerRow: width * 16,
                                size: CGSize(width: width, height: height), format: .RGBAf, colorSpace: nil)
            .samplingLinear()
            .clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
        guard let multiply = CIFilter(name: "CIMultiplyCompositing") else { return (result, report) }
        multiply.setValue(gainImage, forKey: kCIInputImageKey)
        multiply.setValue(result, forKey: kCIInputBackgroundImageKey)
        report.usedGainMap = true
        return (multiply.outputImage?.cropped(to: extent) ?? result, report)
    }

    // MARK: - Grids

    static func grid(of image: CIImage, width: Int, height: Int, context: CIContext) -> Grid? {
        let e = image.extent
        guard let linear = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        // Shrink in two steps so every pixel counts (one big step skips pixels)
        var small = image.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        let firstScale = min(1, CGFloat(width * 8) / e.width)
        if firstScale < 1 {
            small = small.applyingFilter("CILanczosScaleTransform",
                                         parameters: [kCIInputScaleKey: firstScale, kCIInputAspectRatioKey: 1.0])
        }
        let se = small.extent
        small = small.clampedToExtent()
            .applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: max(1, se.width / CGFloat(width) / 2)])
            .transformed(by: CGAffineTransform(scaleX: CGFloat(width) / se.width, y: CGFloat(height) / se.height))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        var pixels = [Float](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            context.render(small, toBitmap: $0.baseAddress!, rowBytes: width * 16,
                           bounds: CGRect(x: 0, y: 0, width: width, height: height),
                           format: .RGBAf, colorSpace: linear)
        }
        var grid = Grid(width: width, height: height, r: [], g: [], b: [])
        grid.r.reserveCapacity(width * height)
        // render writes the top row first
        for i in 0..<width * height {
            grid.r.append(max(pixels[i * 4], 0))
            grid.g.append(max(pixels[i * 4 + 1], 0))
            grid.b.append(max(pixels[i * 4 + 2], 0))
        }
        return grid
    }

    private static func sample(_ grid: Grid, x: Float, y: Float) -> (Float, Float, Float) {
        let fx = min(max(x, 0), Float(grid.width - 1)), fy = min(max(y, 0), Float(grid.height - 1))
        let x0 = Int(fx), y0 = Int(fy)
        let x1 = min(x0 + 1, grid.width - 1), y1 = min(y0 + 1, grid.height - 1)
        let tx = fx - Float(x0), ty = fy - Float(y0)
        func at(_ c: [Float]) -> Float {
            let top = c[y0 * grid.width + x0] * (1 - tx) + c[y0 * grid.width + x1] * tx
            let bottom = c[y1 * grid.width + x0] * (1 - tx) + c[y1 * grid.width + x1] * tx
            return top * (1 - ty) + bottom * ty
        }
        return (at(grid.r), at(grid.g), at(grid.b))
    }

    /// The screen grid resampled onto the photo grid at the best scale and shift, with how well
    /// they agree (1 = the same pattern of light and dark)
    private static func align(_ screen: Grid, onto photo: Grid, margin: Float)
        -> (Grid, Float, Float, Float, Float) {
        let w = photo.width, h = photo.height
        // Compared on screen-style values, so dark areas count as much as they look
        let photoLevels = (0..<w * h).map { encode(photo.luma($0)) }
        func resampled(scale: Float, shiftX: Float, shiftY: Float) -> Grid {
            var out = Grid(width: w, height: h, r: [], g: [], b: [])
            out.r.reserveCapacity(w * h); out.g.reserveCapacity(w * h); out.b.reserveCapacity(w * h)
            let cx = Float(screen.width - 1) / 2, cy = Float(screen.height - 1) / 2
            let px = Float(w - 1) / 2, py = Float(h - 1) / 2
            for y in 0..<h {
                for x in 0..<w {
                    let sx = cx + (Float(x) - px) * margin * scale + shiftX
                    let sy = cy + (Float(y) - py) * margin * scale + shiftY
                    let (r, g, b) = sample(screen, x: sx, y: sy)
                    out.r.append(r); out.g.append(g); out.b.append(b)
                }
            }
            return out
        }
        func score(_ g: Grid) -> Float {
            // Correlation of the two, ignoring an outer border where views differ most
            var sa: Float = 0, sb: Float = 0, saa: Float = 0, sbb: Float = 0, sab: Float = 0, n: Float = 0
            for y in 2..<(h - 2) {
                for x in 2..<(w - 2) {
                    let i = y * w + x
                    let a = photoLevels[i], b = encode(g.luma(i))
                    sa += a; sb += b; saa += a * a; sbb += b * b; sab += a * b; n += 1
                }
            }
            let cov = sab / n - sa / n * sb / n
            let va = saa / n - sa * sa / (n * n), vb = sbb / n - sb * sb / (n * n)
            guard va > 1e-6, vb > 1e-6 else { return 0 }
            return cov / (va * vb).squareRoot()
        }
        // Coarse search, then a fine one around the best
        var best = (score: -Float.infinity, scale: Float(1), sx: Float(0), sy: Float(0))
        for scale in stride(from: Float(0.84), through: 1.16, by: 0.02) {
            for sx in stride(from: Float(-4), through: 4, by: 1) {
                for sy in stride(from: Float(-4), through: 4, by: 1) {
                    let s = score(resampled(scale: scale, shiftX: sx, shiftY: sy))
                    if s > best.score { best = (s, scale, sx, sy) }
                }
            }
        }
        let coarse = best
        for scale in stride(from: coarse.scale - 0.02, through: coarse.scale + 0.02, by: 0.005) {
            for sx in stride(from: coarse.sx - 1, through: coarse.sx + 1, by: 0.25) {
                for sy in stride(from: coarse.sy - 1, through: coarse.sy + 1, by: 0.25) {
                    let s = score(resampled(scale: scale, shiftX: sx, shiftY: sy))
                    if s > best.score { best = (s, scale, sx, sy) }
                }
            }
        }
        return (resampled(scale: best.scale, shiftX: best.sx, shiftY: best.sy), best.score, best.scale, best.sx, best.sy)
    }

    // MARK: - The whole-photo curve

    private static let steps = 64

    /// 64 steps from black to white, on screen-style values: the photo's tones mapped onto the
    /// screen's, share by share (the darkest tenth onto the darkest tenth, and so on)
    private static func toneTable(from photo: Grid, to screen: Grid) -> [Float] {
        let a = (0..<photo.r.count).map { encode(photo.luma($0)) }.sorted()
        let b = (0..<screen.r.count).map { encode(screen.luma($0)) }.sorted()
        func level(_ s: [Float], _ share: Float) -> Float { s[min(s.count - 1, Int(share * Float(s.count - 1) + 0.5))] }
        var points: [(x: Float, y: Float)] = [(0, 0)]
        for k in 1..<50 {
            let share = Float(k) / 50
            let x = level(a, share), y = level(b, share)
            guard x - points[points.count - 1].x >= 0.01, x <= 0.99 else { continue }
            points.append((x, max(y, points[points.count - 1].y)))
        }
        // White stays white unless the screen's brightest areas are clearly darker
        let top = max(level(b, 0.995), points[points.count - 1].y)
        points.append((1, min(1, max(top, points[points.count - 1].y))))
        var table = [Float](repeating: 0, count: steps)
        for i in 0..<steps {
            let x = Float(i) / Float(steps - 1)
            var j = 1
            while j < points.count - 1 && points[j].x < x { j += 1 }
            let p0 = points[j - 1], p1 = points[j]
            let t = p1.x > p0.x ? (x - p0.x) / (p1.x - p0.x) : 0
            table[i] = p0.y + (p1.y - p0.y) * min(max(t, 0), 1)
        }
        // Smooth it, keeping the ends, so the photo gets no bands
        for _ in 0..<2 {
            var smooth = table
            for i in 1..<(steps - 1) { smooth[i] = (table[i - 1] + 2 * table[i] + table[i + 1]) / 4 }
            table = smooth
        }
        return table
    }

    private static func curveFilter(_ table: [Float]) -> CIFilter? {
        guard let filter = CIFilter(name: "CIColorCurves"),
              let screenSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgb = [Float]()
        for value in table { rgb.append(contentsOf: [value, value, value]) }
        filter.setValue(rgb.withUnsafeBufferPointer { Data(buffer: $0) }, forKey: "inputCurvesData")
        filter.setValue(CIVector(x: 0, y: 1), forKey: "inputCurvesDomain")
        filter.setValue(screenSpace, forKey: "inputColorSpace")
        return filter
    }

    /// A linear value through the table (which works on screen-style values)
    private static func throughTable(_ linear: Float, _ table: [Float]) -> Float {
        let x = min(max(encode(linear), 0), 1) * Float(table.count - 1)
        let i = min(Int(x), table.count - 2)
        let t = x - Float(i)
        return decode(table[i] * (1 - t) + table[i + 1] * t)
    }

    // MARK: - Helpers

    private static func clampGain(_ g: Float) -> Float { min(max(g, gainLimit.lowerBound), gainLimit.upperBound) }

    private static func encode(_ v: Float) -> Float {
        let c = min(max(v, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055
    }

    private static func decode(_ v: Float) -> Float {
        let c = min(max(v, 0), 1)
        return c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4)
    }

    private static func blurred(_ grid: Grid) -> Grid {
        let radius = Int((gainBlur * 3).rounded(.up))
        let weights = (-radius...radius).map { expf(-Float($0 * $0) / (2 * gainBlur * gainBlur)) }
        func pass(_ c: [Float], horizontal: Bool) -> [Float] {
            var out = c
            for y in 0..<grid.height {
                for x in 0..<grid.width {
                    var sum: Float = 0, total: Float = 0
                    for k in -radius...radius {
                        let xx = horizontal ? x + k : x, yy = horizontal ? y : y + k
                        guard xx >= 0, xx < grid.width, yy >= 0, yy < grid.height else { continue }
                        let w = weights[k + radius]
                        sum += c[yy * grid.width + xx] * w; total += w
                    }
                    out[y * grid.width + x] = sum / total
                }
            }
            return out
        }
        func both(_ c: [Float]) -> [Float] { pass(pass(c, horizontal: true), horizontal: false) }
        return Grid(width: grid.width, height: grid.height, r: both(grid.r), g: both(grid.g), b: both(grid.b))
    }
}
