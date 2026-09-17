import AppKit
import QuartzCore

/// Draws the hook, the cord and the charm.
///
/// Geometry is worked out in "model" coordinates, y pointing down from the
/// top of the view like the physics, and flipped only where it touches
/// Core Animation.
final class CharmView: NSView {
    /// From the top of the hook plate to the bottom of the eye the cord is tied to.
    static let pivotDrop: CGFloat = 13

    weak var controller: CharmController?
    var pivot = CGPoint.zero { didSet { if pivot != oldValue { layoutHook() } } }
    var charm = Charm.all[0] { didSet { if charm != oldValue { loadArtwork() } } }
    var sizeFactor: CGFloat = 1
    var charmOpacity: Float = 1

    private(set) var bob = CGPoint.zero
    private(set) var axis = CGPoint(x: 0, y: 1)
    private var ropePoints: [CGPoint] = []

    private let root = CALayer()
    private let hookPlate = CAShapeLayer()
    private let hookEye = CAShapeLayer()
    private let cord = CAShapeLayer()
    private let cordCore = CAShapeLayer()
    private let fibre = CAShapeLayer()
    private let charmLayer = CALayer()
    private var artSize = CGSize.zero

    // The same three layers as the cord drawn into the charm art: a dark edge, a warm core, and fibres.
    private static let cordEdge = CGColor(srgbRed: 0.37, green: 0.26, blue: 0.12, alpha: 1)
    private static let cordWarm = CGColor(srgbRed: 0.63, green: 0.48, blue: 0.27, alpha: 1)
    private static let fibreGold = CGColor(srgbRed: 0.89, green: 0.75, blue: 0.49, alpha: 0.5)
    private static let brass = CGColor(srgbRed: 0.85, green: 0.67, blue: 0.34, alpha: 1)
    private static let brassShade = CGColor(srgbRed: 0.52, green: 0.37, blue: 0.14, alpha: 1)

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = root            // layer-hosting, so AppKit leaves the tree to us
        wantsLayer = true

        cord.fillColor = nil
        cord.strokeColor = Self.cordEdge
        cord.lineWidth = 2
        cord.lineCap = .round
        cord.lineJoin = .round
        cord.shadowColor = CGColor.black
        cord.shadowOpacity = 0.24
        cord.shadowRadius = 1.3
        cord.shadowOffset = CGSize(width: 1.2, height: -2.2)

        cordCore.fillColor = nil
        cordCore.strokeColor = Self.cordWarm
        cordCore.lineWidth = 1.2
        cordCore.lineCap = .round
        cordCore.lineJoin = .round

        // Uneven light dashes along the cord read as twisted fibres.
        fibre.fillColor = nil
        fibre.strokeColor = Self.fibreGold
        fibre.lineWidth = 0.8
        fibre.lineDashPattern = [2.2, 6, 1.4, 9]

        hookPlate.fillColor = Self.brass
        hookPlate.strokeColor = Self.brassShade
        hookPlate.lineWidth = 0.6

        hookEye.fillColor = nil
        hookEye.strokeColor = Self.brass
        hookEye.lineWidth = 1.8
        hookEye.shadowColor = CGColor.black
        hookEye.shadowOpacity = 0.25
        hookEye.shadowRadius = 1
        hookEye.shadowOffset = CGSize(width: 0.6, height: -1.2)

        charmLayer.anchorPoint = CGPoint(x: 0.5, y: 1)   // top centre, where it is tied on
        charmLayer.contentsGravity = .resize
        charmLayer.minificationFilter = .trilinear
        charmLayer.shadowColor = CGColor.black
        charmLayer.shadowOpacity = 0.3
        charmLayer.shadowRadius = 5
        charmLayer.shadowOffset = CGSize(width: 2, height: -5)

        for sublayer in [cord, cordCore, fibre, hookEye, hookPlate, charmLayer] as [CALayer] {
            root.addSublayer(sublayer)
        }
        loadArtwork()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [root, cord, cordCore, fibre, hookEye, hookPlate, charmLayer] as [CALayer] {
            sublayer.contentsScale = scale
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutHook()
    }

    private func loadArtwork() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        charmLayer.contents = charm.artwork
        CATransaction.commit()
    }

    private func layoutHook() {
        let h = bounds.height
        let top = pivot.y - Self.pivotDrop
        let r: CGFloat = 3.1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hookPlate.path = CGPath(roundedRect: CGRect(x: pivot.x - 4, y: h - top - 1.6, width: 8, height: 2.6),
                                cornerWidth: 1.2, cornerHeight: 1.2, transform: nil)
        let eye = CGMutablePath()
        eye.move(to: CGPoint(x: pivot.x, y: h - top - 1.5))
        eye.addLine(to: CGPoint(x: pivot.x, y: h - (pivot.y - 2 * r)))
        eye.addEllipse(in: CGRect(x: pivot.x - r, y: h - pivot.y, width: 2 * r, height: 2 * r))
        hookEye.path = eye
        CATransaction.commit()
    }

    func render(_ physics: CordPhysics, rope: RopeChain) {
        let h = Double(bounds.height)
        let origin = Vec(pivot)
        func up(_ v: Vec) -> CGPoint { CGPoint(x: v.x, y: h - v.y) }

        let s = charm.scale * sizeFactor
        let knotPoint = origin + physics.position
        let r = physics.charmAngle
        bob = CGPoint(knotPoint)
        axis = CGPoint(x: sin(r), y: cos(r))
        let tail = knotPoint + Vec(sin(r), cos(r)) * Double(charm.beadTop * s)

        ropePoints = rope.points.map { CGPoint(origin + $0) }
        let points = rope.points.map { up(origin + $0) }
        let path = CGMutablePath()
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            // Catmull-Rom through the chain, so the cord curves instead of kinking.
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.addLine(to: up(tail))

        let size = CGSize(width: charm.artWidth * s, height: charm.artHeight * s)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cord.path = path
        cordCore.path = path
        fibre.path = path
        let thinning = 1 - 0.4 * CGFloat(clamp(rope.strain * 1.5, 0, 1))      // a pulled cord thins
        cord.lineWidth = 2 * thinning
        cordCore.lineWidth = 1.2 * thinning
        fibre.lineDashPhase = CGFloat(rope.strain * 14)
        if size != artSize {
            artSize = size
            charmLayer.bounds = CGRect(origin: .zero, size: size)
        }
        charmLayer.position = up(knotPoint)
        charmLayer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(r)))
        charmLayer.opacity = charmOpacity
        CATransaction.commit()
    }

    /// Whether a model-space point is on the charm, using a capsule along its hanging axis.
    func charmContains(_ q: CGPoint) -> Bool {
        guard charmOpacity > 0.5 else { return false }
        let s = charm.scale * sizeFactor
        let top = (charm.bodyTop + charm.halfWidth * 0.6) * s
        let bottom = max(top, (charm.artHeight - charm.halfWidth * 0.6) * s)
        let a = CGPoint(x: bob.x + axis.x * top, y: bob.y + axis.y * top)
        let b = CGPoint(x: bob.x + axis.x * bottom, y: bob.y + axis.y * bottom)
        return distance(from: q, toSegment: a, b) <= (charm.halfWidth + 6) * s
    }

    /// If a model-space point is on the cord, how far along it (0 at the hook, 1 at the knot).
    func cordFraction(at q: CGPoint) -> Double? {
        guard charmOpacity > 0.5, ropePoints.count > 1 else { return nil }
        var total: CGFloat = 0
        var nearest: (distance: CGFloat, along: CGFloat) = (.greatestFiniteMagnitude, 0)
        for i in 0..<(ropePoints.count - 1) {
            let a = ropePoints[i], b = ropePoints[i + 1]
            let length = hypot(b.x - a.x, b.y - a.y)
            let t = length < 0.001 ? 0 : clamp(((q.x - a.x) * (b.x - a.x) + (q.y - a.y) * (b.y - a.y)) / (length * length), 0, 1)
            let d = hypot(q.x - (a.x + (b.x - a.x) * t), q.y - (a.y + (b.y - a.y) * t))
            if d < nearest.distance { nearest = (d, total + length * t) }
            total += length
        }
        guard total > 20, nearest.distance <= 10 else { return nil }
        let fraction = Double(nearest.along / total)
        return fraction > 0.1 && fraction < 0.95 ? fraction : nil
    }

    func modelPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: bounds.height - p.y)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { controller?.pointerDown(event) }
    override func mouseDragged(with event: NSEvent) { controller?.pointerDragged(event) }
    override func mouseUp(with event: NSEvent) { controller?.pointerUp(event) }
    override func rightMouseDown(with event: NSEvent) { controller?.showContextMenu(for: event, in: self) }
}

private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
    let abx = b.x - a.x, aby = b.y - a.y
    let lengthSquared = abx * abx + aby * aby
    let t = lengthSquared == 0 ? 0 : clamp(((p.x - a.x) * abx + (p.y - a.y) * aby) / lengthSquared, 0, 1)
    return hypot(p.x - (a.x + abx * t), p.y - (a.y + aby * t))
}
