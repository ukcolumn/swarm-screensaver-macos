//
//  SwarmRenderer.swift
//  Turns simulation state into strokes on a CGContext.
//


import Foundation
import CoreGraphics

final class SwarmRenderer {

    var colourScheme: ColourScheme = .classic
    var fadeTrails: Bool = true

    // Number of opacity steps used along a fading trail.
    private static let fadeBands = 8
    // Number of depth slices used for fog, line width and draw order.
    private static let depthBands = 12

    // Slowly rotating hue, used by the classic and rainbow colour schemes.
    private var cycle: CGFloat = CGFloat.random(in: 0..<1)

    private struct RGB: Equatable {
        var r: CGFloat
        var g: CGFloat
        var b: CGFloat
    }

    // Segment end points waiting to be stroked, one bucket per depth band per
    // fade band. Bucket [0] is the furthest slice.
    private var buckets: [[[CGPoint]]] = Array(
        repeating: Array(repeating: [], count: SwarmRenderer.fadeBands),
        count: SwarmRenderer.depthBands)

    // Bee indices sorted furthest first, reused between frames.
    private var order: [Int] = []

    private var camera = Camera(centre: .zero, focal: 1, angle: 0, flat: true)
    private var depthRange: CGFloat = 1
    private var lineWidth: CGFloat = 1

    // The slice of depth the bands are spread over. 
    private var bandCentre: CGFloat = 0
    private var bandHalfSpan: CGFloat = 1

    func advanceColourCycle() {
        cycle += 0.0002
        if cycle >= 1 { cycle -= 1 }
    }

    func draw(_ swarm: SwarmSimulation, in context: CGContext, bounds: CGRect) {
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(bounds)

        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setShouldAntialias(true)

        camera = swarm.camera
        depthRange = max(swarm.depthRange, 0.0001)

        // Furthest bee first, so that where bees differ in colour the near ones
        // draw over the far ones. Within one colour it makes no difference.
        sortBeesByDepth(swarm)

        lineWidth = 1.0
        var pending: RGB?
        for bee in order {
            let beeColour = colour(forBee: bee, of: swarm.beeCount)
            if let previous = pending, previous != beeColour {
                flush(colour: previous, in: context)
            }
            pending = beeColour
            collectTrail(of: bee + 1, from: swarm)
        }
        if let previous = pending {
            flush(colour: previous, in: context)
        }

        // The wasp goes on top, drawn a bit heavier so it stays visible
        // inside the swarm, and exempt from the fog so distance cannot lose it.
        lineWidth = 1.8
        collectTrail(of: 0, from: swarm)
        flush(colour: waspColour(), in: context, fog: false)
    }

    private func sortBeesByDepth(_ swarm: SwarmSimulation) {
        if order.count != swarm.beeCount {
            order = Array(0..<swarm.beeCount)
        }
        guard !camera.flat else { return }
        let depths = swarm.bees.map { camera.depth(of: $0.position) }
        order.sort { depths[$0] > depths[$1] }
        updateBandRange(sortedDepths: order.map { depths[$0] })
    }

    private func updateBandRange(sortedDepths: [CGFloat]) {
        guard sortedDepths.count > 4 else { return }
        // The list arrives furthest first, so the tenth element is a far one.
        let far = sortedDepths[sortedDepths.count / 10]
        let near = sortedDepths[sortedDepths.count * 9 / 10]
        bandCentre = sortedDepths[sortedDepths.count / 2]
        let target = min(max(1.25 * (far - near) / 2, depthRange * 0.02), depthRange)
        bandHalfSpan += (target - bandHalfSpan) * 0.05
    }

    private func collectTrail(of insect: Int, from swarm: SwarmSimulation) {
        var previous: (point: CGPoint, scale: CGFloat, depth: CGFloat)?
        swarm.forEachTrailPoint(of: insect) { point, step, count in
            let projected = self.camera.project(point)
            defer { previous = projected }
            guard let start = previous else { return }

            let fade: Int
            if self.fadeTrails && count > 1 {
                let position = CGFloat(step) / CGFloat(count - 1)
                fade = min(SwarmRenderer.fadeBands - 1,
                           Int(position * CGFloat(SwarmRenderer.fadeBands)))
            } else {
                fade = SwarmRenderer.fadeBands - 1
            }

            let depth = self.band(for: (start.depth + projected.depth) / 2)
            self.buckets[depth][fade].append(start.point)
            self.buckets[depth][fade].append(projected.point)
        }
    }

    private func band(for depth: CGFloat) -> Int {
        guard !camera.flat else { return SwarmRenderer.depthBands - 1 }
        let span = max(bandHalfSpan, 0.0001)
        let nearness = 1 - (depth - bandCentre + span) / (2 * span)
        let index = Int(nearness * CGFloat(SwarmRenderer.depthBands))
        return min(SwarmRenderer.depthBands - 1, max(0, index))
    }

    private func flush(colour: RGB, in context: CGContext, fog: Bool = true) {
        for depth in buckets.indices {
            var used = false
            for fade in buckets[depth].indices where !buckets[depth][fade].isEmpty {
                if !used {
                    context.setLineWidth(width(forBand: depth))
                    used = true
                }
                let alpha = alpha(forFade: fade) * (fog ? fogAlpha(forBand: depth) : 1)
                context.setStrokeColor(red: colour.r, green: colour.g, blue: colour.b, alpha: alpha)
                context.strokeLineSegments(between: buckets[depth][fade])
                buckets[depth][fade].removeAll(keepingCapacity: true)
            }
        }
    }

    private func nearness(ofBand band: Int) -> CGFloat {
        (CGFloat(band) + 0.5) / CGFloat(SwarmRenderer.depthBands)
    }

    /// Distance dims an insect. 
    private func fogAlpha(forBand band: Int) -> CGFloat {
        guard !camera.flat else { return 1 }
        return 0.62 + 0.38 * nearness(ofBand: band)
    }

    /// Far insects are drawn thinner.
    private func width(forBand band: Int) -> CGFloat {
        guard !camera.flat else { return lineWidth }
        return lineWidth * (0.55 + 0.45 * nearness(ofBand: band))
    }

    /// The oldest end of a trail fades away, the newest end is solid.
    private func alpha(forFade band: Int) -> CGFloat {
        guard fadeTrails else { return 1 }
        let position = (CGFloat(band) + 0.5) / CGFloat(SwarmRenderer.fadeBands)
        return 0.12 + 0.88 * position * position
    }

    // Colours

    private func colour(forBee index: Int, of total: Int) -> RGB {
        switch colourScheme {
        case .classic:
            return hsb(hue: cycle, saturation: 0.85, brightness: 1.0)
        case .rainbow:
            let hue = (CGFloat(index) / CGFloat(max(total, 1)) + cycle).truncatingRemainder(dividingBy: 1)
            return hsb(hue: hue, saturation: 0.9, brightness: 1.0)
        case .honey:
            let hue = 0.09 + 0.04 * CGFloat(index % 7) / 7.0
            return hsb(hue: hue, saturation: 0.95, brightness: 1.0)
        case .monochrome:
            return RGB(r: 1, g: 1, b: 1)
        }
    }

    private func waspColour() -> RGB {
        RGB(r: 1, g: 1, b: 1)
    }

    private func hsb(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> RGB {
        guard saturation > 0 else { return RGB(r: brightness, g: brightness, b: brightness) }
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let sector = floor(h)
        let f = h - sector
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * f)
        let t = brightness * (1 - saturation * (1 - f))
        switch Int(sector) % 6 {
        case 0: return RGB(r: brightness, g: t, b: p)
        case 1: return RGB(r: q, g: brightness, b: p)
        case 2: return RGB(r: p, g: brightness, b: t)
        case 3: return RGB(r: p, g: q, b: brightness)
        case 4: return RGB(r: t, g: p, b: brightness)
        default: return RGB(r: brightness, g: p, b: q)
        }
    }
}
