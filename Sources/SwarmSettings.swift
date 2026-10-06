//
//  SwarmSettings.swift
//

import Foundation
import ScreenSaver
import AppKit

enum ColourScheme: String, CaseIterable {
    // One slowly cycling hue for the whole swarm, white wasp. Closest to the
    // original screensaver.
    case classic
    // Every bee keeps its own hue.
    case rainbow
    // Amber bees, white wasp.
    case honey
    // White on black, the way the original screensaver looked on a mono X terminal.
    case monochrome

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .rainbow: return "Rainbow"
        case .honey: return "Honey"
        case .monochrome: return "Monochrome"
        }
    }
}

struct SwarmSettings {

    static let moduleName = "ukcolumn.Swarm"

    private enum Key {
        static let beeCount = "BeeCount"
        static let trailLength = "TrailLength"
        static let speed = "SpeedV2"
        static let colourScheme = "ColourScheme"
        static let fadeTrails = "FadeTrails"
        static let depth = "Depth"
        static let gravity = "Gravity"
    }

    static let beeCountRange = 5...400
    static let trailLengthRange = 2...48
    // Symmetric about 1.0, so the slider's middle is the chosen pace.
    static let speedRange: ClosedRange<Double> = (1.0 / 3.0)...3.0
    // Ratio between the apparent size of the nearest and furthest points of
    // the world. 1 is the flat swarm; above that it runs in three dimensions
    // and the world turns slowly. Past about 3.5 the near insects sweep off
    // the sides faster than the extra depth is worth.
    static let depthRange: ClosedRange<Double> = 1.0...3.5
    // Multiplier on the bees' pull towards the wasp. 1.0 is the tuned value.
    static let gravityRange: ClosedRange<Double> = 0.4...2.5

    var beeCount: Int
    var trailLength: Int
    var speed: Double
    var colourScheme: ColourScheme
    var fadeTrails: Bool
    var depth: Double
    var gravity: Double

    static var defaultSettings: SwarmSettings {
        SwarmSettings(beeCount: 100,
                      trailLength: 14,
                      speed: 1.0,
                      colourScheme: .classic,
                      fadeTrails: true,
                      depth: 2.5,
                      gravity: 1.0)
    }

    static var store: ScreenSaverDefaults? {
        ScreenSaverDefaults(forModuleWithName: moduleName)
    }

    static func load() -> SwarmSettings {
        var settings = defaultSettings
        guard let defaults = store else { return settings }
        defaults.register(defaults: [
            Key.beeCount: settings.beeCount,
            Key.trailLength: settings.trailLength,
            Key.speed: settings.speed,
            Key.colourScheme: settings.colourScheme.rawValue,
            Key.fadeTrails: settings.fadeTrails,
            Key.depth: settings.depth,
            Key.gravity: settings.gravity
        ])
        settings.beeCount = clamp(defaults.integer(forKey: Key.beeCount), to: beeCountRange)
        settings.trailLength = clamp(defaults.integer(forKey: Key.trailLength), to: trailLengthRange)
        settings.speed = min(max(defaults.double(forKey: Key.speed), speedRange.lowerBound),
                             speedRange.upperBound)
        if let raw = defaults.string(forKey: Key.colourScheme),
           let scheme = ColourScheme(rawValue: raw) {
            settings.colourScheme = scheme
        }
        settings.fadeTrails = defaults.bool(forKey: Key.fadeTrails)
        settings.depth = min(max(defaults.double(forKey: Key.depth), depthRange.lowerBound),
                             depthRange.upperBound)
        settings.gravity = min(max(defaults.double(forKey: Key.gravity), gravityRange.lowerBound),
                               gravityRange.upperBound)
        return settings
    }

    func save() {
        guard let defaults = SwarmSettings.store else { return }
        defaults.set(beeCount, forKey: Key.beeCount)
        defaults.set(trailLength, forKey: Key.trailLength)
        defaults.set(speed, forKey: Key.speed)
        defaults.set(colourScheme.rawValue, forKey: Key.colourScheme)
        defaults.set(fadeTrails, forKey: Key.fadeTrails)
        defaults.set(depth, forKey: Key.depth)
        defaults.set(gravity, forKey: Key.gravity)
        defaults.synchronize()
    }

    private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
