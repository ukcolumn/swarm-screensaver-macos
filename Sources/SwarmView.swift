//
//  SwarmView.swift
//  The ScreenSaverView that macOS loads.
//

import AppKit
import ScreenSaver

@objc(SwarmView)
final class SwarmView: ScreenSaverView {

    private var settings: SwarmSettings
    private let simulation: SwarmSimulation
    private let renderer = SwarmRenderer()
    private var sheetController: SwarmConfigureSheetController?

    // Thumbnails in System Settings are tiny, so thin the swarm out there.
    private var effectiveBeeCount: Int {
        isPreview ? min(settings.beeCount, 45) : settings.beeCount
    }

    override init?(frame: NSRect, isPreview: Bool) {
        let loaded = SwarmSettings.load()
        settings = loaded
        simulation = SwarmSimulation(size: frame.size,
                                     beeCount: isPreview ? min(loaded.beeCount, 45) : loaded.beeCount,
                                     trailLength: loaded.trailLength)
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 60.0
        applySettings()
    }

    required init?(coder: NSCoder) {
        settings = SwarmSettings.load()
        simulation = SwarmSimulation(size: .zero,
                                     beeCount: settings.beeCount,
                                     trailLength: settings.trailLength)
        super.init(coder: coder)
        animationTimeInterval = 1.0 / 60.0
        applySettings()
    }

    override var isOpaque: Bool { true }

    private func applySettings() {
        simulation.speedScale = CGFloat(settings.speed)
        simulation.depth = CGFloat(settings.depth)
        simulation.gravity = CGFloat(settings.gravity)
        renderer.colourScheme = settings.colourScheme
        renderer.fadeTrails = settings.fadeTrails
        simulation.reconfigure(size: bounds.size,
                               beeCount: effectiveBeeCount,
                               trailLength: settings.trailLength)
    }

    // Animation

    override func startAnimation() {
        settings = SwarmSettings.load()
        applySettings()
        simulation.reset()
        super.startAnimation()
    }

    override func stopAnimation() {
        super.stopAnimation()
    }

    override func animateOneFrame() {
        simulation.reconfigure(size: bounds.size,
                               beeCount: effectiveBeeCount,
                               trailLength: settings.trailLength)
        simulation.step()
        renderer.advanceColourCycle()
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(simulation, in: context, bounds: bounds)
    }

    // Preferences

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        let controller = SwarmConfigureSheetController { [weak self] updated in
            guard let self else { return }
            self.settings = updated
            self.applySettings()
            self.simulation.reset()
        }
        sheetController = controller
        return controller.window
    }
}
