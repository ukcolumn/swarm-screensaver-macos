//
//  SwarmConfigureSheet.swift
//  The Options sheet.
//

import AppKit

final class SwarmConfigureSheetController: NSObject {

    let window: NSWindow
    private var settings: SwarmSettings
    private let onSave: (SwarmSettings) -> Void

    private let beeSlider = NSSlider()
    private let beeValue = NSTextField(labelWithString: "")
    private let trailSlider = NSSlider()
    private let trailValue = NSTextField(labelWithString: "")
    private let speedSlider = NSSlider()
    private let speedValue = NSTextField(labelWithString: "")
    private let depthSlider = NSSlider()
    private let depthValue = NSTextField(labelWithString: "")
    private let gravitySlider = NSSlider()
    private let gravityValue = NSTextField(labelWithString: "")
    private let schemePopUp = NSPopUpButton()
    private let fadeCheckbox = NSButton(checkboxWithTitle: "Fade the trails out", target: nil, action: nil)

    init(onSave: @escaping (SwarmSettings) -> Void) {
        self.settings = SwarmSettings.load()
        self.onSave = onSave
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 392),
                          styleMask: [.titled],
                          backing: .buffered,
                          defer: false)
        super.init()
        window.title = "Swarm Options"
        buildContents()
        loadValues()
    }

    // Layout

    private func buildContents() {
        guard let content = window.contentView else { return }
        var y: CGFloat = 340

        let heading = NSTextField(labelWithString: "Swarm")
        heading.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        heading.frame = NSRect(x: 20, y: y, width: 420, height: 20)
        content.addSubview(heading)
        y -= 20

        let blurb = NSTextField(labelWithString: "A wasp wanders the screen and the bees give chase. Depth turns it 3D.")
        blurb.font = NSFont.systemFont(ofSize: 11)
        blurb.textColor = .secondaryLabelColor
        blurb.frame = NSRect(x: 20, y: y, width: 420, height: 16)
        content.addSubview(blurb)
        y -= 38

        addSlider(beeSlider, label: "Bees:", value: beeValue,
                  min: Double(SwarmSettings.beeCountRange.lowerBound),
                  max: Double(SwarmSettings.beeCountRange.upperBound),
                  action: #selector(beeCountChanged(_:)), in: content, y: &y)

        addSlider(trailSlider, label: "Trail length:", value: trailValue,
                  min: Double(SwarmSettings.trailLengthRange.lowerBound),
                  max: Double(SwarmSettings.trailLengthRange.upperBound),
                  action: #selector(trailChanged(_:)), in: content, y: &y)

        addSlider(speedSlider, label: "Speed:", value: speedValue,
                  min: log(SwarmSettings.speedRange.lowerBound),
                  max: log(SwarmSettings.speedRange.upperBound),
                  action: #selector(speedChanged(_:)), in: content, y: &y)

        addSlider(depthSlider, label: "Depth:", value: depthValue,
                  min: SwarmSettings.depthRange.lowerBound,
                  max: SwarmSettings.depthRange.upperBound,
                  action: #selector(depthChanged(_:)), in: content, y: &y)

        addSlider(gravitySlider, label: "Gravity:", value: gravityValue,
                  min: log(SwarmSettings.gravityRange.lowerBound),
                  max: log(SwarmSettings.gravityRange.upperBound),
                  action: #selector(gravityChanged(_:)), in: content, y: &y)

        let schemeLabel = NSTextField(labelWithString: "Colours:")
        schemeLabel.alignment = .right
        schemeLabel.frame = NSRect(x: 20, y: y + 3, width: 90, height: 18)
        content.addSubview(schemeLabel)
        schemePopUp.frame = NSRect(x: 118, y: y - 2, width: 170, height: 26)
        schemePopUp.addItems(withTitles: ColourScheme.allCases.map { $0.title })
        content.addSubview(schemePopUp)
        y -= 36

        fadeCheckbox.frame = NSRect(x: 116, y: y, width: 300, height: 20)
        content.addSubview(fadeCheckbox)

        let defaultsButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults(_:)))
        defaultsButton.bezelStyle = .rounded
        defaultsButton.frame = NSRect(x: 16, y: 16, width: 150, height: 30)
        content.addSubview(defaultsButton)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.frame = NSRect(x: 268, y: 16, width: 80, height: 30)
        content.addSubview(cancelButton)

        let okButton = NSButton(title: "OK", target: self, action: #selector(save(_:)))
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"
        okButton.frame = NSRect(x: 356, y: 16, width: 88, height: 30)
        content.addSubview(okButton)
    }

    private func addSlider(_ slider: NSSlider,
                           label: String,
                           value: NSTextField,
                           min minValue: Double,
                           max maxValue: Double,
                           action: Selector,
                           in content: NSView,
                           y: inout CGFloat) {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.frame = NSRect(x: 20, y: y, width: 90, height: 18)
        content.addSubview(title)

        slider.minValue = minValue
        slider.maxValue = maxValue
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.frame = NSRect(x: 118, y: y - 3, width: 260, height: 22)
        content.addSubview(slider)

        value.alignment = .left
        value.frame = NSRect(x: 388, y: y, width: 60, height: 18)
        content.addSubview(value)

        y -= 36
    }

    // Values

    private func loadValues() {
        beeSlider.doubleValue = Double(settings.beeCount)
        trailSlider.doubleValue = Double(settings.trailLength)
        // Speed and Gravity are multipliers, so their sliders work in logs.
        // Both ranges are symmetric about 1.0, which puts the default in the
        // middle of the travel and makes a step left cost what a step right
        // gains.
        speedSlider.doubleValue = log(settings.speed)
        depthSlider.doubleValue = settings.depth
        gravitySlider.doubleValue = log(settings.gravity)
        schemePopUp.selectItem(at: ColourScheme.allCases.firstIndex(of: settings.colourScheme) ?? 0)
        fadeCheckbox.state = settings.fadeTrails ? .on : .off
        updateLabels()
    }

    private func updateLabels() {
        beeValue.stringValue = "\(settings.beeCount)"
        trailValue.stringValue = "\(settings.trailLength)"
        speedValue.stringValue = String(format: "%.2f\u{00d7}", settings.speed)
        depthValue.stringValue = settings.depth <= 1.001
            ? "flat"
            : String(format: "%.1f\u{00d7}", settings.depth)
        gravityValue.stringValue = String(format: "%.2f\u{00d7}", settings.gravity)
    }

    @objc private func beeCountChanged(_ sender: NSSlider) {
        settings.beeCount = Int(sender.doubleValue.rounded())
        updateLabels()
    }

    @objc private func trailChanged(_ sender: NSSlider) {
        settings.trailLength = Int(sender.doubleValue.rounded())
        updateLabels()
    }

    @objc private func speedChanged(_ sender: NSSlider) {
        settings.speed = SwarmConfigureSheetController.snap(exp(sender.doubleValue))
        updateLabels()
    }

    @objc private func depthChanged(_ sender: NSSlider) {
        settings.depth = (sender.doubleValue * 10).rounded() / 10
        updateLabels()
    }

    @objc private func gravityChanged(_ sender: NSSlider) {
        settings.gravity = SwarmConfigureSheetController.snap(exp(sender.doubleValue))
        updateLabels()
    }

    private static func snap(_ value: Double) -> Double {
        abs(value - 1) < 0.02 ? 1.0 : (value * 100).rounded() / 100
    }

    @objc private func restoreDefaults(_ sender: Any) {
        settings = SwarmSettings.defaultSettings
        loadValues()
    }

    // Closing

    @objc private func save(_ sender: Any) {
        settings.colourScheme = ColourScheme.allCases[schemePopUp.indexOfSelectedItem]
        settings.fadeTrails = fadeCheckbox.state == .on
        settings.save()
        onSave(settings)
        dismiss()
    }

    @objc private func cancel(_ sender: Any) {
        dismiss()
    }

    private func dismiss() {
        if let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            NSApp.stopModal()
        }
        window.orderOut(nil)
    }
}
