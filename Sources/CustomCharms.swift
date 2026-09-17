import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Charms made from your own pictures, kept in Application Support as a PNG
/// and a small JSON file each.
final class CustomCharms {
    static let shared = CustomCharms()

    struct Metadata: Codable {
        var name: String
        var artWidth: Double
        var artHeight: Double
        var bodyTop: Double
        var halfWidth: Double
        var added: Date
    }

    private(set) var charms: [Charm] = []
    let folder: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("Hanging Charm/Charms", isDirectory: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        charms = files.filter { $0.pathExtension == "json" }
            .compactMap { url -> (Date, Charm)? in
                let image = url.deletingPathExtension().appendingPathExtension("png")
                guard let data = try? Data(contentsOf: url),
                      let meta = try? decoder.decode(Metadata.self, from: data),
                      FileManager.default.fileExists(atPath: image.path) else { return nil }
                let charm = Charm(id: "custom-" + url.deletingPathExtension().lastPathComponent, name: meta.name,
                                  region: "Your picture", artHeight: meta.artHeight, beadTop: 0.5, bodyTop: meta.bodyTop,
                                  halfWidth: meta.halfWidth, scale: 1, artWidth: meta.artWidth, imageURL: image)
                return (meta.added, charm)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    /// Makes a charm from a picture and saves it, returning its id. Subject
    /// detection takes a moment, so call this off the main thread.
    static func make(from source: URL, in folder: URL, existingNames: [String]) throws -> String {
        var (png, meta) = try CharmMaker.make(from: source)
        let base = meta.name
        var number = 2
        while existingNames.contains(meta.name) {
            meta.name = "\(base) \(number)"
            number += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = UUID().uuidString
        try png.write(to: folder.appendingPathComponent(file + ".png"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        try encoder.encode(meta).write(to: folder.appendingPathComponent(file + ".json"))
        return "custom-" + file
    }

    func remove(_ charm: Charm) {
        guard let image = charm.imageURL else { return }
        try? FileManager.default.removeItem(at: image)
        try? FileManager.default.removeItem(at: image.deletingPathExtension().appendingPathExtension("json"))
        reload()
    }
}

/// Turns a picture into a hanging charm: the main subject is lifted out of
/// its background, given a white sticker edge, and strung from the top of
/// its head on a cord with three beads, like the built-in charms.
enum CharmMaker {
    enum Failure: LocalizedError {
        case unreadable
        var errorDescription: String? { "The file couldn’t be opened as a picture." }
    }

    private struct Bitmap {
        let image: CGImage
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    private static let unit: CGFloat = 4             // pixels per art unit, like the built-in artwork
    private static let stringLength: CGFloat = 34    // cord and beads above the picture, in art units
    private static let gold = [CGColor(srgbRed: 1, green: 0.9, blue: 0.55, alpha: 1),
                               CGColor(srgbRed: 0.91, green: 0.68, blue: 0.18, alpha: 1),
                               CGColor(srgbRed: 0.58, green: 0.38, blue: 0.04, alpha: 1)]
    private static let red = [CGColor(srgbRed: 1, green: 0.49, blue: 0.41, alpha: 1),
                              CGColor(srgbRed: 0.82, green: 0.14, blue: 0.11, alpha: 1),
                              CGColor(srgbRed: 0.41, green: 0.02, blue: 0.04, alpha: 1)]

    static func make(from url: URL) throws -> (Data, CustomCharms.Metadata) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let picture = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 1400,
              ] as CFDictionary)
        else { throw Failure.unreadable }

        let subject = liftSubject(from: picture) ?? framed(picture)
        let fit = min(84 * unit / CGFloat(subject.width), 112 * unit / CGFloat(subject.height))
        let width = max(1, Int((CGFloat(subject.width) * fit).rounded()))
        let height = max(1, Int((CGFloat(subject.height) * fit).rounded()))
        guard let body = sticker(subject, width: width, height: height, edge: 2.4 * unit) else { throw Failure.unreadable }

        // Hang it from the top of the subject, wherever that is across the picture.
        let (topRow, attachX) = topAttachPoint(body)
        let bodyTop = stringLength * unit
        let half = max(attachX, CGFloat(body.width) - attachX) + 6 * unit
        let canvasWidth = Int(ceil(max(half * 2, 120 * unit)))
        let canvasHeight = Int(ceil(bodyTop + CGFloat(body.height) + 4 * unit))
        guard let ctx = bitmap(canvasWidth, canvasHeight) else { throw Failure.unreadable }
        ctx.interpolationQuality = .high
        let h = CGFloat(canvasHeight), cx = CGFloat(canvasWidth) / 2
        func up(_ y: CGFloat) -> CGFloat { h - y }

        let ringY = bodyTop + CGFloat(topRow) - 1.6 * unit
        ctx.setLineCap(.round)
        for (color, lineWidth) in [(CGColor(srgbRed: 0.37, green: 0.26, blue: 0.12, alpha: 1), 2 * unit),
                                   (CGColor(srgbRed: 0.63, green: 0.48, blue: 0.27, alpha: 1), 1.2 * unit)] {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(lineWidth)
            ctx.move(to: CGPoint(x: cx, y: up(0)))
            ctx.addLine(to: CGPoint(x: cx, y: up(ringY - 2.6 * unit)))
            ctx.strokePath()
        }
        ctx.draw(body.image, in: CGRect(x: cx - attachX, y: up(bodyTop) - CGFloat(body.height),
                                        width: CGFloat(body.width), height: CGFloat(body.height)))
        ctx.setStrokeColor(gold[1])
        ctx.setLineWidth(1.3 * unit)
        ctx.strokeEllipse(in: CGRect(x: cx - 2.6 * unit, y: up(ringY) - 2.6 * unit, width: 5.2 * unit, height: 5.2 * unit))
        drawBead(ctx, at: CGPoint(x: cx, y: up(4.5 * unit)), radius: 3.5 * unit, colors: gold)
        drawBead(ctx, at: CGPoint(x: cx, y: up(14.5 * unit)), radius: 6 * unit, colors: red)
        drawBead(ctx, at: CGPoint(x: cx, y: up(23.5 * unit)), radius: 3.5 * unit, colors: gold)

        guard let image = ctx.makeImage(), let png = pngData(image) else { throw Failure.unreadable }
        let meta = CustomCharms.Metadata(
            name: name(for: url), artWidth: Double(canvasWidth) / Double(unit), artHeight: Double(canvasHeight) / Double(unit),
            bodyTop: Double((bodyTop + CGFloat(topRow)) / unit), halfWidth: Double(CGFloat(body.width) / 2 / unit), added: Date())
        return (png, meta)
    }

    /// The largest foreground subject with its background removed, or nil if none is found.
    private static func liftSubject(from picture: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: picture, options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }

        // Keep only the biggest subject, so people and things in the background stay out.
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask)?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask), rowBytes = CVPixelBufferGetBytesPerRow(mask)
        var areas = [Int: Int]()
        for y in 0..<height {
            for x in 0..<width where base[y * rowBytes + x] > 0 { areas[Int(base[y * rowBytes + x]), default: 0] += 1 }
        }
        guard let biggest = areas.max(by: { $0.value < $1.value })?.key,
              let lifted = try? observation.generateMaskedImage(ofInstances: IndexSet(integer: biggest), from: handler,
                                                                croppedToInstancesExtent: true) else { return nil }
        let image = CIImage(cvPixelBuffer: lifted)
        return CIContext().createCGImage(image, from: image.extent)
    }

    /// When there is no clear subject, hang the whole picture as a rounded card.
    private static func framed(_ picture: CGImage) -> CGImage {
        let border = max(8, min(picture.width, picture.height) / 28)
        let width = picture.width + border * 2, height = picture.height + border * 2
        guard let ctx = bitmap(width, height) else { return picture }
        let radius = CGFloat(min(picture.width, picture.height)) * 0.06
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                           cornerWidth: radius + CGFloat(border), cornerHeight: radius + CGFloat(border), transform: nil))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillPath()
        let inner = CGRect(x: border, y: border, width: picture.width, height: picture.height)
        ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.clip()
        ctx.draw(picture, in: inner)
        return ctx.makeImage() ?? picture
    }

    /// The subject scaled to size with a white edge around its outline.
    private static func sticker(_ subject: CGImage, width: Int, height: Int, edge: CGFloat) -> Bitmap? {
        let pad = Int(ceil(edge)) + 2
        let canvasWidth = width + pad * 2, canvasHeight = height + pad * 2
        let full = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
        let placed = CGRect(x: pad, y: pad, width: width, height: height)
        guard let shape = bitmap(canvasWidth, canvasHeight) else { return nil }
        shape.interpolationQuality = .high
        shape.draw(subject, in: placed)
        shape.setBlendMode(.sourceIn)
        shape.setFillColor(CGColor(gray: 1, alpha: 1))
        shape.fill(full)
        guard let silhouette = shape.makeImage(), let ctx = bitmap(canvasWidth, canvasHeight) else { return nil }
        ctx.interpolationQuality = .high
        for radius in [edge, edge * 0.5] {
            for step in 0..<24 {
                let angle = Double(step) / 24 * 2 * .pi
                ctx.draw(silhouette, in: full.offsetBy(dx: cos(angle) * radius, dy: sin(angle) * radius))
            }
        }
        ctx.draw(subject, in: placed)
        guard let image = ctx.makeImage(), let data = ctx.data else { return nil }
        let pixels = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: canvasWidth * canvasHeight * 4))
        return Bitmap(image: image, pixels: pixels, width: canvasWidth, height: canvasHeight)
    }

    /// The first solid row from the top, and the middle of the solid pixels
    /// just below it, so a stray hair doesn't decide where the hook goes.
    private static func topAttachPoint(_ b: Bitmap) -> (row: Int, x: CGFloat) {
        func solid(_ x: Int, _ y: Int) -> Bool { b.pixels[(y * b.width + x) * 4 + 3] > 160 }
        for row in 0..<b.height where (0..<b.width).contains(where: { solid($0, row) }) {
            var sum = 0, count = 0
            for y in row..<min(b.height, row + Int(unit * 4)) {
                for x in 0..<b.width where solid(x, y) {
                    sum += x
                    count += 1
                }
            }
            return (row, CGFloat(sum) / CGFloat(max(count, 1)))
        }
        return (0, CGFloat(b.width) / 2)
    }

    private static func drawBead(_ ctx: CGContext, at center: CGPoint, radius r: CGFloat, colors: [CGColor]) {
        let circle = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -0.8 * unit), blur: 1.4 * unit, color: CGColor(gray: 0, alpha: 0.28))
        ctx.setFillColor(colors[2])
        ctx.fillEllipse(in: circle)
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addEllipse(in: circle)
        ctx.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 0.55, 1]) {
            let light = CGPoint(x: center.x - 0.13 * r, y: center.y + 0.2 * r)
            ctx.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: light, endRadius: r * 1.5,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.restoreGState()
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: center.x - 0.61 * r, y: center.y + 0.26 * r, width: 0.54 * r, height: 0.4 * r))
    }

    private static func name(for url: URL) -> String {
        let base = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let generic = ["image", "img", "photo", "picture", "download", "screenshot", "screen shot", "untitled", "whatsapp"]
        if base.isEmpty || base.allSatisfy(\.isNumber) || generic.contains(where: { base.lowercased().hasPrefix($0) }) {
            return "My Picture"
        }
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    private static func bitmap(_ width: Int, _ height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
