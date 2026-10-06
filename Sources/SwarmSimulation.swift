//
//  SwarmSimulation.swift
//  Swarm screensaver for macOS
//
//  A reimplementation of the classic X11 "swarm" screensaver by Jeff
//  Butterworth: a wasp wanders the screen while a swarm of bees chases it,
//  each insect dragging a short trail behind it.
//
//  The motion rules follow the original:
//    * the wasp accelerates in a random direction every frame, is speed
//      limited per axis, and bounces off an invisible fence set in from the
//      edges of the screen,
//    * every bee accelerates towards the wasp by a fixed amount whatever the
//      distance, is speed limited per axis, and is never repelled, so it
//      always overshoots and ends up orbiting,
//    * bees bounce off the boundary of the world, so the swarm can swing out
//      past the wasp's fence without any of it leaving the display.
//
//  With Depth turned up the same rules run in three dimensions and the world
//  turns slowly about its vertical axis. 

import Foundation
import CoreGraphics

// A point in world space. `z` is zero in flat mode.
struct Point3 {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var z: CGFloat = 0
}

// One insect. Positions are in points, velocities in points per frame.
struct Agent {
    var x: CGFloat = 0
    var y: CGFloat = 0
    var z: CGFloat = 0
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var vz: CGFloat = 0

    var position: Point3 { Point3(x: x, y: y, z: z) }
}

// Where the world is seen from, and how to get from world space to the screen.
struct Camera {
    var centre: CGPoint
    var focal: CGFloat
    var angle: CGFloat
    var flat: Bool

    // The turn is the same for every point in a frame, so its sine and cosine
    // are worked out once here rather than per trail point. Doing it inside
    // project() takes four times the drawing time.
    private let c: CGFloat
    private let s: CGFloat

    init(centre: CGPoint, focal: CGFloat, angle: CGFloat, flat: Bool) {
        self.centre = centre
        self.focal = focal
        self.angle = angle
        self.flat = flat
        self.c = flat ? 1 : cos(angle)
        self.s = flat ? 0 : sin(angle)
    }

    // Just the turned depth, for sorting. Skips the divide and the point.
    func depth(of p: Point3) -> CGFloat {
        flat ? 0 : -(p.x - centre.x) * s + p.z * c
    }

    // The screen point, the perspective scale there, and the turned depth.
    // The renderer bands that depth for fog, line width and draw order.
    func project(_ p: Point3) -> (point: CGPoint, scale: CGFloat, depth: CGFloat) {
        guard !flat else { return (CGPoint(x: p.x, y: p.y), 1, 0) }
        let ox = p.x - centre.x
        let oy = p.y - centre.y
        let rx = ox * c + p.z * s
        let rz = -ox * s + p.z * c
        // The spheroid's radius is always smaller than the focal length, so
        // the divisor cannot reach zero. The floor is belt and braces.
        let k = focal / max(focal * 0.05, focal + rz)
        return (CGPoint(x: centre.x + rx * k, y: centre.y + oy * k), k, rz)
    }
}

// The state of one swarm, independent of how it gets drawn.
final class SwarmSimulation {

    // Motion constants, in points per frame at 60 frames a second on a 1280
    // point wide screen. `scale` below stretches them to whatever screen we
    // run on.
    private enum Reference {
        static let beeAcceleration: CGFloat = 0.77
        static let beeMaxSpeed: CGFloat = 10.0
        static let waspAcceleration: CGFloat = 2.0
        static let waspMaxSpeed: CGFloat = 6.0
        static let border: CGFloat = 150.0
        static let turn: CGFloat = 6.0
        static let pace: CGFloat = 0.60
        static let width: CGFloat = 1280.0
    }

    private(set) var size: CGSize
    private(set) var beeCount: Int
    private(set) var trailLength: Int

    // How fast the swarm lives, as a multiple of the chosen pace, so 1.0 is
    // the default and the slider runs either side of it. 
    var speedScale: CGFloat = 1.0

    // The setting, converted to real time.
    private var timeScale: CGFloat { speedScale * Reference.pace }

    // Ratio between the apparent size of the nearest and furthest points of
    // the world. 1 means no depth at all, and runs a 2d swarm like the original.
    var depth: CGFloat = 1.0 {
        didSet {
            guard (depth <= 1.001) != (oldValue <= 1.001) else { return }
            reset()
        }
    }

    // Multiplier on the bees' pull towards the wasp. Orbit radius equals
    // speed squared over acceleration, so raising this tightens the swarm.
    var gravity: CGFloat = 1.0

    var isFlat: Bool { depth <= 1.001 }

    private(set) var wasp = Agent()
    private(set) var bees: [Agent] = []

    // How far the world has turned, and how fast it is turning. The rate
    // wanders slowly so the view never settles into a recognisable loop.
    private(set) var angle: CGFloat = 0
    private var turnRate: CGFloat = 0

    // Ring buffer of past positions, `trailLength` slots per insect.
    // Slot 0 of every insect is the wasp's, bee `b` starts at `(b + 1) * trailLength`.
    private(set) var trail: [Point3] = []
    // Index of the newest slot in each ring.
    private(set) var head: Int = 0
    // How many slots hold real data yet, so a fresh swarm does not draw a
    // bundle of lines back to the origin.
    private(set) var filled: Int = 0

    private var scale: CGFloat {
        max(0.45, min(size.width, size.height * 1.6) / Reference.width)
    }

    // The wasp's fence, inset from every edge. Capped at a quarter of the
    // short side so it cannot swallow the whole view in a System Settings
    // thumbnail, where the scaled border would otherwise overlap itself.
    private var border: CGFloat {
        min(Reference.border * scale, min(size.width, size.height) * 0.25)
    }

    // 3D geometry

    // The swarm lives inside a spheroid: radius `r` in x and z, half height
    // `b` in y. A spheroid whose polar axis is the axis of rotation looks the
    // same from every angle, so unlike a box it has no flat face to read as a
    // pane of glass when a wall of bees bounces off it.
    //
    // Its radius is fixed at half the screen, so the swarm fills the frame at
    // any Depth setting, and the focal length does the work instead.
    private var spheroid: (r: CGFloat, b: CGFloat) {
        (size.width / 2, size.height / 2)
    }

    // Chosen to give the requested near to far size ratio across the
    // spheroid: with a half depth of `r`, a ratio of `d` needs a focal length
    // of `r (d + 1) / (d - 1)`.
    private var focal: CGFloat {
        let d = max(1.01, depth)
        return spheroid.r * (d + 1) / (d - 1)
    }

    var camera: Camera {
        Camera(centre: CGPoint(x: size.width / 2, y: size.height / 2),
               focal: focal, angle: angle, flat: isFlat)
    }

    // Half the depth of the world, which is what the renderer bands over.
    var depthRange: CGFloat { isFlat ? 1 : spheroid.r }

    init(size: CGSize, beeCount: Int, trailLength: Int) {
        self.size = CGSize(width: max(size.width, 32), height: max(size.height, 32))
        self.beeCount = max(1, beeCount)
        self.trailLength = max(2, trailLength)
        reset()
    }

    // Set up

    // Throws the swarm away and starts a new one at a random spot.
    func reset() {
        let s = scale
        angle = CGFloat.random(in: 0..<(2 * .pi))
        turnRate = turnStep

        if isFlat {
            let b = border
            wasp = Agent(x: CGFloat.random(in: b...(size.width - b)),
                         y: CGFloat.random(in: b...(size.height - b)),
                         z: 0,
                         vx: CGFloat.random(in: -1...1) * Reference.waspMaxSpeed * s,
                         vy: CGFloat.random(in: -1...1) * Reference.waspMaxSpeed * s,
                         vz: 0)
            bees = (0..<beeCount).map { _ in
                Agent(x: CGFloat.random(in: 0...size.width),
                      y: CGFloat.random(in: 0...size.height),
                      z: 0,
                      vx: CGFloat.random(in: -1...1) * Reference.beeMaxSpeed * s,
                      vy: CGFloat.random(in: -1...1) * Reference.beeMaxSpeed * s,
                      vz: 0)
            }
        } else {
            let (fenceR, fenceB) = waspFence
            wasp = spawn(inR: fenceR, b: fenceB, speed: Reference.waspMaxSpeed * s)
            let (r, b) = spheroid
            bees = (0..<beeCount).map { _ in
                spawn(inR: r, b: b, speed: Reference.beeMaxSpeed * s)
            }
        }

        trail = Array(repeating: Point3(), count: (beeCount + 1) * trailLength)
        head = 0
        filled = 0
        recordPositions()
    }

    // A random point inside a spheroid, by rejection. The spheroid fills a
    // good half of its bounding box, so this lands first or second try.
    private func spawn(inR r: CGFloat, b: CGFloat, speed: CGFloat) -> Agent {
        var x: CGFloat = 0, y: CGFloat = 0, z: CGFloat = 0
        repeat {
            x = CGFloat.random(in: -r...r)
            y = CGFloat.random(in: -b...b)
            z = CGFloat.random(in: -r...r)
        } while (x * x + z * z) / (r * r) + (y * y) / (b * b) > 1
        return Agent(x: size.width / 2 + x,
                     y: size.height / 2 + y,
                     z: z,
                     vx: CGFloat.random(in: -1...1) * speed,
                     vy: CGFloat.random(in: -1...1) * speed,
                     vz: CGFloat.random(in: -1...1) * speed)
    }

    // Rebuilds the swarm when the preferences or the screen size change.
    func reconfigure(size: CGSize, beeCount: Int, trailLength: Int) {
        let newSize = CGSize(width: max(size.width, 32), height: max(size.height, 32))
        let changed = newSize != self.size
            || beeCount != self.beeCount
            || trailLength != self.trailLength
        guard changed else { return }
        self.size = newSize
        self.beeCount = max(1, beeCount)
        self.trailLength = max(2, trailLength)
        reset()
    }

    // Motion

    private var turnStep: CGFloat {
        Reference.turn * .pi / 180 / 60
    }

    func step() {
        let velocity = scale * timeScale
        let acceleration = scale * timeScale * timeScale
        if !isFlat { turnWorld() }
        moveWasp(velocity: velocity, acceleration: acceleration)
        moveBees(velocity: velocity, acceleration: acceleration)
        advanceTrail()
    }

    private func turnWorld() {
        let step = turnStep * timeScale
        turnRate += CGFloat.random(in: -1...1) * step * 0.02
        turnRate = min(max(turnRate, -step * 1.6), step * 1.6)
        angle += turnRate
        if angle > 2 * .pi { angle -= 2 * .pi }
        if angle < 0 { angle += 2 * .pi }
    }

    // The spheroid the wasp is fenced inside.
    private var waspFence: (r: CGFloat, b: CGFloat) {
        let (r, b) = spheroid
        let inset = border
        return (max(r * 0.35, r - inset), max(b * 0.35, b - inset))
    }

    private func moveWasp(velocity: CGFloat, acceleration: CGFloat) {
        let acc = Reference.waspAcceleration * acceleration
        let limit = Reference.waspMaxSpeed * velocity

        // Random path, per axis, exactly like the original screensaver. 
        wasp.vx += CGFloat.random(in: -acc...acc)
        wasp.vy += CGFloat.random(in: -acc...acc)
        if !isFlat { wasp.vz += CGFloat.random(in: -acc...acc) }

        wasp.vx = min(max(wasp.vx, -limit), limit)
        wasp.vy = min(max(wasp.vy, -limit), limit)
        wasp.vz = min(max(wasp.vz, -limit), limit)

        wasp.x += wasp.vx
        wasp.y += wasp.vy
        wasp.z += wasp.vz

        if isFlat {
            // Bounce off the fence, not off the screen edge. 
            let b = border
            if wasp.x < b || wasp.x > size.width - b {
                wasp.vx = -wasp.vx
                wasp.x += wasp.vx * 2
            }
            if wasp.y < b || wasp.y > size.height - b {
                wasp.vy = -wasp.vy
                wasp.y += wasp.vy * 2
            }
        } else {
            let (r, b) = waspFence
            reflect(&wasp, r: r, b: b)
        }
    }

    private func moveBees(velocity: CGFloat, acceleration: CGFloat) {
        let acc = Reference.beeAcceleration * gravity * acceleration
        let jitter = acc * 0.35
        let limit = Reference.beeMaxSpeed * velocity
        let flat = isFlat
        let (r, b) = spheroid

        for i in bees.indices {
            var bee = bees[i]

            // Constant pull towards the wasp, whatever the distance. This is
            // what makes the bees overshoot and swirl instead of settling.
            let dx = wasp.x - bee.x
            let dy = wasp.y - bee.y
            let dz = wasp.z - bee.z
            let distance = max(1.0, (dx * dx + dy * dy + dz * dz).squareRoot())
            bee.vx += acc * dx / distance + CGFloat.random(in: -jitter...jitter)
            bee.vy += acc * dy / distance + CGFloat.random(in: -jitter...jitter)
            if !flat { bee.vz += acc * dz / distance + CGFloat.random(in: -jitter...jitter) }

            bee.vx = min(max(bee.vx, -limit), limit)
            bee.vy = min(max(bee.vy, -limit), limit)
            bee.vz = min(max(bee.vz, -limit), limit)

            bee.x += bee.vx
            bee.y += bee.vy
            bee.z += bee.vz

            // The bees orbit wide enough to reach the
            // boundary even though the wasp never does.
            if flat {
                if bee.x < 0 || bee.x > size.width {
                    bee.vx = -bee.vx
                    bee.x += bee.vx * 2
                }
                if bee.y < 0 || bee.y > size.height {
                    bee.vy = -bee.vy
                    bee.y += bee.vy * 2
                }
            } else {
                reflect(&bee, r: r, b: b)
            }

            bees[i] = bee
        }
    }

    // Reflects an insect back inside the spheroid of radius `r` and half
    // height `b`, centred on the middle of the world.
    private func reflect(_ agent: inout Agent, r: CGFloat, b: CGFloat) {
        let ox = agent.x - size.width / 2
        let oy = agent.y - size.height / 2
        let oz = agent.z
        let outside = (ox * ox + oz * oz) / (r * r) + (oy * oy) / (b * b)
        guard outside > 1 else { return }

        let k = 1 / outside.squareRoot()
        let px = ox * k, py = oy * k, pz = oz * k
        agent.x = size.width / 2 + px
        agent.y = size.height / 2 + py
        agent.z = pz

        var nx = px / (r * r), ny = py / (b * b), nz = pz / (r * r)
        let length = (nx * nx + ny * ny + nz * nz).squareRoot()
        guard length > 0 else { return }
        nx /= length; ny /= length; nz /= length

        let along = 2 * (agent.vx * nx + agent.vy * ny + agent.vz * nz)
        agent.vx -= along * nx
        agent.vy -= along * ny
        agent.vz -= along * nz
    }

    // Trails

    private func advanceTrail() {
        head = (head + 1) % trailLength
        filled = min(filled + 1, trailLength)
        recordPositions()
    }

    private func recordPositions() {
        trail[head] = wasp.position
        for (i, bee) in bees.enumerated() {
            trail[(i + 1) * trailLength + head] = bee.position
        }
        filled = max(filled, 1)
    }

    // Index 0 is the wasp, 1... are the bees.
    func forEachTrailPoint(of insect: Int, _ body: (Point3, Int, Int) -> Void) {
        let base = insect * trailLength
        let count = filled
        guard count > 0 else { return }
        var slot = (head - count + 1 + trailLength * 2) % trailLength
        for step in 0..<count {
            body(trail[base + slot], step, count)
            slot = (slot + 1) % trailLength
        }
    }
}
