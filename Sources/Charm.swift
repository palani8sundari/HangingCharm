import AppKit
import ImageIO

/// One charm. Built-in artwork lives in Resources/Charms, and charms made from
/// your own pictures in Application Support; both are 4x PNGs drawn with the
/// cord's end at the top centre. Sizes are in art units, where one unit is one
/// point at Medium size.
struct Charm: Equatable {
    let id: String
    let name: String
    let region: String
    let artHeight: CGFloat
    let beadTop: CGFloat      // where the app's cord meets the cord drawn into the art
    let bodyTop: CGFloat      // where the charm itself starts, below its beads
    let halfWidth: CGFloat    // for grabbing
    let scale: CGFloat
    var artWidth: CGFloat = 120
    var imageURL: URL? = nil

    var isCustom: Bool { imageURL != nil }

    static var all: [Charm] { builtIn + CustomCharms.shared.charms }

    static let builtIn: [Charm] = [
        Charm(id: "nazar", name: "Nazar Boncuğu", region: "Turkey and the Mediterranean",
              artHeight: 106, beadTop: 0.5, bodyTop: 38, halfWidth: 33, scale: 1.0),
        Charm(id: "hamsa", name: "Hamsa", region: "Middle East and North Africa",
              artHeight: 142, beadTop: 0.5, bodyTop: 38, halfWidth: 40, scale: 0.86),
        Charm(id: "nimbu", name: "Nimbu-Mirchi", region: "India",
              artHeight: 90, beadTop: 0.5, bodyTop: 2, halfWidth: 33, scale: 1.0),
        Charm(id: "ghanta", name: "Ghanta", region: "India",
              artHeight: 118, beadTop: 0.5, bodyTop: 38, halfWidth: 38, scale: 0.9),
        Charm(id: "bommai", name: "Drishti Bommai", region: "South India",
              artHeight: 164, beadTop: 0.5, bodyTop: 36, halfWidth: 46, scale: 0.7),
        Charm(id: "panchang", name: "Panchang Jie", region: "China",
              artHeight: 148, beadTop: 0.5, bodyTop: 34, halfWidth: 34, scale: 0.95),
        Charm(id: "daruma", name: "Daruma", region: "Japan",
              artHeight: 116, beadTop: 0.5, bodyTop: 38, halfWidth: 40, scale: 0.86),
    ]

    static func with(id: String) -> Charm { all.first { $0.id == id } ?? all[0] }

    static func == (lhs: Charm, rhs: Charm) -> Bool { lhs.id == rhs.id }

    var artwork: CGImage? { ArtworkCache.shared.image(for: self) }

    /// The charm body, without its cord, fitted into a square for menus.
    func menuImage(side: CGFloat = 26) -> NSImage? {
        guard let art = artwork else { return nil }
        let pixelsPerUnit = CGFloat(art.height) / artHeight
        let width = isCustom ? artWidth : (halfWidth + 4) * 2
        let crop = CGRect(x: (artWidth - width) / 2 * pixelsPerUnit, y: bodyTop * pixelsPerUnit,
                          width: width * pixelsPerUnit, height: (artHeight - bodyTop) * pixelsPerUnit).integral
        guard let body = art.cropping(to: crop) else { return nil }
        let aspect = crop.width / crop.height
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            var fit = rect
            if aspect > 1 { fit.size.height = rect.width / aspect } else { fit.size.width = rect.height * aspect }
            fit.origin = CGPoint(x: rect.midX - fit.width / 2, y: rect.midY - fit.height / 2)
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.interpolationQuality = .high
            context.draw(body, in: fit)
            return true
        }
    }
}

private final class ArtworkCache {
    static let shared = ArtworkCache()
    private var images: [String: CGImage] = [:]

    func image(for charm: Charm) -> CGImage? {
        if let cached = images[charm.id] { return cached }
        guard let url = charm.imageURL ?? Bundle.main.url(forResource: charm.id, withExtension: "png", subdirectory: "Charms"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        images[charm.id] = image
        return image
    }
}
