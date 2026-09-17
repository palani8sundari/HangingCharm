import Foundation
import simd

typealias Vec = SIMD2<Double>

/// The charm as a weight on an elastic cord.
///
/// The knot is a point mass hanging from the hook (the origin, y down) on a
/// spring that can pull but not push: pull it and the cord stretches, let go
/// and it springs back, overshoots with the cord gone slack, and drops back
/// onto it again.
final class CordPhysics {
    let gravity = 2450.0            // pt/s²
    var length = 150.0              // hook to knot while hanging still
    var airDrag = 0.7               // per second
    let ceiling = 12.0              // how close to the hook the charm can rise
    let maxPull = 340.0             // how far past its length the cord can be pulled

    /// Bouncing runs at three times the swing frequency, clear of the 2:1
    /// ratio where an elastic pendulum starts trading energy chaotically.
    var stiffness: Double { 9 * gravity / length }
    /// Unstretched cord; its own weight stretches it the rest of the way.
    var naturalLength: Double { length - gravity / stiffness }
    var swingFrequency: Double { (gravity / length).squareRoot() }
    private var cordDamping: Double { 2 * 0.16 * stiffness.squareRoot() }

    private(set) var position = Vec(0, 150)
    private(set) var velocity = Vec(0, 0)
    private(set) var charmAngle = 0.0
    private var charmSpin = 0.0

    /// How much cord is paid out: 1 is all of it, near 0 is wound up to the hook.
    private(set) var reel = 1.0
    private var reelVelocity = 0.0
    var reelTarget = 1.0

    enum Grip { case none, charm(offset: Vec), cord(fraction: Double) }
    private(set) var grip = Grip.none
    /// Where the hand is, relative to the hook.
    var pointer = Vec(0, 0)
    private(set) var cordGripPoint: Vec?

    var isHeld: Bool { if case .none = grip { return false } else { return true } }

    var cordGrip: (fraction: Double, point: Vec)? {
        if case .cord(let u) = grip, let point = cordGripPoint { return (u, point) }
        return nil
    }

    func reset(reeledIn: Bool) {
        reel = reeledIn ? 0.04 : 1
        reelTarget = reel
        reelVelocity = 0
        position = reeledIn ? Vec(.random(in: -4...4), ceiling + 8) : Vec(0, length)
        velocity = .zero
        charmAngle = 0
        charmSpin = 0
        grip = .none
        cordGripPoint = nil
    }

    // MARK: Hands

    func grabCharm(at point: Vec) {
        pointer = point
        grip = .charm(offset: position - point)
    }

    func grabCord(fraction: Double, at point: Vec) {
        pointer = point
        cordGripPoint = point
        grip = .cord(fraction: clamp(fraction, 0.1, 0.92))
    }

    func release() {
        grip = .none
        cordGripPoint = nil
        limitEnergy()
    }

    /// A sideways push that adds to the motion already there. Once it is
    /// swinging, pushes go with the swing, so repeated flicks build.
    func flick() {
        let tangent = swingTangent
        let along = simd_dot(velocity, tangent)
        let direction: Double = abs(along) > 0.2 * swingFrequency * length ? (along > 0 ? 1 : -1) : (Bool.random() ? 1 : -1)
        velocity += tangent * direction * swingFrequency * length * Double.random(in: 0.42...0.6)
        limitEnergy()
    }

    func nudge(strength: Double) {
        velocity += swingTangent * (Bool.random() ? 1 : -1) * swingFrequency * length * strength
    }

    /// The hook moved sideways: the charm stays where it was and swings after it.
    func hookMoved(dx: Double) {
        position.x -= dx
        pointer.x -= dx
        cordGripPoint?.x -= dx
    }

    private var swingTangent: Vec {
        let d = simd_length(position)
        guard d > 1 else { return Vec(1, 0) }
        return Vec(position.y, -position.x) / d
    }

    // MARK: Stepping

    func step(_ h: Double) {
        reelVelocity += ((reelTarget - reel) * 160 - reelVelocity * 25) * h
        reel = clamp(reel + reelVelocity * h, 0.03, 1.2)

        switch grip {
        case .charm(let offset):
            // Follow the hand closely, but as a mass, so letting go throws it.
            let target = reachable(pointer + offset, within: length + maxPull)
            let k = 2200.0
            velocity += ((target - position) * k - velocity * 2 * k.squareRoot()) * h
            position += velocity * h
        case .cord(let u):
            // The hand pins the cord; the charm hangs from that point on what is left of it.
            let held = reachable(pointer, within: naturalLength * reel * u + maxPull)
            cordGripPoint = held
            fall(h, from: held, naturalLength: naturalLength * reel * (1 - u), stiffness: stiffness / (1 - u))
        case .none:
            fall(h, from: .zero, naturalLength: naturalLength * reel, stiffness: stiffness)
        }

        // On a taut cord the charm lines up with it, lagging into a swing and
        // overshooting out of it. On a slack cord nothing turns it, so it coasts.
        let anchor = cordGripPoint ?? .zero
        let hanging = position - anchor
        let hangLength: Double
        if case .cord(let u) = grip { hangLength = naturalLength * reel * (1 - u) } else { hangLength = naturalLength * reel }
        if simd_length(hanging) > hangLength * 0.98 {
            let spin = isHeld ? 0 : (hanging.y * velocity.x - hanging.x * velocity.y) / max(simd_length_squared(hanging), 100)
            let target = atan2(hanging.x, hanging.y) + spin * 0.05
            charmSpin += ((target - charmAngle).remainder(dividingBy: 2 * .pi) * 190 - charmSpin * 17) * h
        } else {
            charmSpin *= exp(-4 * h)
        }
        charmAngle = (charmAngle + charmSpin * h).remainder(dividingBy: 2 * .pi)
    }

    private func fall(_ h: Double, from anchor: Vec, naturalLength l0: Double, stiffness k: Double) {
        var acceleration = Vec(0, gravity)
        let offset = position - anchor
        let distance = simd_length(offset)
        if distance > l0, distance > 0.001 {
            let direction = offset / distance
            let tension = k * (distance - l0) + cordDamping * simd_dot(velocity, direction)
            if tension > 0 { acceleration -= direction * tension }
        }
        velocity += acceleration * h
        velocity *= exp(-airDrag * h)
        position += velocity * h
        limitEnergy()
    }

    /// However hard it is pulled, the rebound tops out about a third of the
    /// way below the hook instead of slamming into the menu bar.
    private func limitEnergy() {
        if position.y < ceiling {
            position.y = ceiling
            if velocity.y < 0 { velocity.y *= -0.25 }
        }
        guard velocity.y < 0 else { return }
        let apex = max(ceiling, 0.35 * length * reel)
        let allowed = 2 * gravity * max(0, position.y - apex) + 200 * 200
        let speedSquared = simd_length_squared(velocity)
        if speedSquared > allowed { velocity *= (allowed / speedSquared).squareRoot() }
    }

    private func reachable(_ point: Vec, within reach: Double) -> Vec {
        var p = point
        p.y = max(p.y, ceiling)
        let d = simd_length(p)
        return d > reach ? p * (reach / d) : p
    }

    var isSettled: Bool {
        guard !isHeld else { return false }
        let rest = Vec(0, naturalLength * reel + gravity / stiffness)
        return simd_length(position - rest) < 0.6 && simd_length(velocity) < 3
            && abs(reel - reelTarget) < 0.003 && abs(reelVelocity) < 0.02
            && abs(charmSpin) < 0.03 && abs((charmAngle - atan2(position.x, position.y)).remainder(dividingBy: 2 * .pi)) < 0.006
    }
}

/// The cord as a light chain of links between the hook and the knot. It only
/// has to look right, so it follows the charm rather than pulling on it: taut
/// when stretched, draped and whipping when slack.
final class RopeChain {
    let links = 22
    private(set) var points: [Vec]
    private var previous: [Vec]
    /// How far past its natural length the cord is pulled (0 when slack).
    private(set) var strain = 0.0

    init() {
        points = Array(repeating: .zero, count: 23)
        previous = points
    }

    func reset(to end: Vec) {
        for i in 0...links { points[i] = end * (Double(i) / Double(links)) }
        previous = points
    }

    func hookMoved(dx: Double) {
        for i in 1...links {
            points[i].x -= dx
            previous[i].x -= dx
        }
    }

    func step(_ h: Double, to end: Vec, naturalLength: Double, grip: (fraction: Double, point: Vec)?, gravity: Double) {
        // A cord under tension barely sags; a slack one drapes with its full weight.
        let slack = clamp((naturalLength - simd_length(end)) / max(naturalLength, 1) * 4 + 0.12, 0.12, 1)
        let fall = Vec(0, gravity * slack) * h * h
        for i in 1..<links {
            let current = points[i]
            points[i] += (current - previous[i]) * 0.985 + fall
            previous[i] = current
        }

        let pin = grip.map { (index: clamp(Int(($0.fraction * Double(links)).rounded()), 1, links - 1), point: $0.point) }
        func restLength(_ from: Int, _ to: Int, _ a: Vec, _ b: Vec) -> Double {
            let count = Double(to - from)
            return max(naturalLength * count / Double(links), simd_distance(a, b)) / count
        }
        let upper = pin.map { restLength(0, $0.index, .zero, $0.point) } ?? restLength(0, links, .zero, end)
        let lower = pin.map { restLength($0.index, links, $0.point, end) } ?? upper
        strain = max(0, simd_length(end) / max(naturalLength, 1) - 1)

        func relax(_ i: Int) {
            let pinnedA = i == 0 || i == pin?.index
            let pinnedB = i + 1 == links || i + 1 == pin?.index
            let weightA = pinnedA ? 0.0 : 1.0, weightB = pinnedB ? 0.0 : 1.0
            guard weightA + weightB > 0 else { return }
            let delta = points[i + 1] - points[i]
            let distance = simd_length(delta)
            guard distance > 1e-6 else { return }
            let rest = pin.map { i >= $0.index ? lower : upper } ?? upper
            let correction = delta * ((distance - rest) / distance / (weightA + weightB))
            points[i] += correction * weightA
            points[i + 1] -= correction * weightB
        }
        // Sweep from both ends so tension reaches the middle of the cord quickly.
        for _ in 0..<6 {
            points[0] = .zero
            points[links] = end
            if let pin { points[pin.index] = pin.point }
            for i in 0..<links { relax(i) }
            for i in stride(from: links - 1, through: 0, by: -1) { relax(i) }
        }
        points[0] = .zero
        points[links] = end
        if let pin { points[pin.index] = pin.point }
    }
}

func clamp<T: Comparable>(_ value: T, _ low: T, _ high: T) -> T { min(max(value, low), high) }

extension SIMD2 where Scalar == Double {
    init(_ point: CGPoint) { self.init(Double(point.x), Double(point.y)) }
}

extension CGPoint {
    init(_ v: Vec) { self.init(x: v.x, y: v.y) }
}
