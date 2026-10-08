import AppKit
import AVFoundation
import SynesthesiaData
import UniformTypeIdentifiers

private let samplingRate = 10.0

@MainActor
private final class ColorFieldView: NSView {
    var onColorChange: ((NSColor) -> Void)?
    var isSelectionEnabled = true {
        didSet {
            alphaValue = isSelectionEnabled ? 1 : 0.3
        }
    }

    private var selectedHue = 0.0
    private var selectedLightness = 0.5

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let step = 3.0
        var x = 0.0
        while x < bounds.width {
            var y = 0.0
            while y < bounds.height {
                color(at: NSPoint(x: x, y: y)).setFill()
                NSRect(x: x, y: y, width: step + 0.5, height: step + 0.5).fill()
                y += step
            }
            x += step
        }

        let marker = NSRect(
            x: selectedHue * bounds.width - 6,
            y: selectedLightness * bounds.height - 6,
            width: 12,
            height: 12
        )
        NSColor.white.setStroke()
        let markerPath = NSBezierPath(ovalIn: marker)
        markerPath.lineWidth = 3
        markerPath.stroke()
        NSColor.black.setStroke()
        markerPath.lineWidth = 1
        markerPath.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        updateSelection(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateSelection(with: event)
    }

    private func updateSelection(with event: NSEvent) {
        guard isSelectionEnabled else { return }

        let point = convert(event.locationInWindow, from: nil)
        selectedHue = min(max(point.x / max(bounds.width, 1), 0), 1)
        selectedLightness = min(max(point.y / max(bounds.height, 1), 0), 1)
        onColorChange?(color(hue: selectedHue, lightness: selectedLightness))
        needsDisplay = true
    }

    private func color(at point: NSPoint) -> NSColor {
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let hue = min(max(point.x / width, 0), 1)
        let lightness = min(max(point.y / height, 0), 1)
        return color(hue: hue, lightness: lightness)
    }

    private func color(hue: Double, lightness: Double) -> NSColor {
        let brightness = lightness <= 0.5 ? lightness * 2 : 1
        let saturation = lightness <= 0.5 ? 1 : 2 * (1 - lightness)
        return NSColor(
            calibratedHue: hue,
            saturation: saturation,
            brightness: brightness,
            alpha: 1
        )
    }
}

@MainActor
private final class CollectorViewController: NSViewController {
    private let fileLabel = NSTextField(labelWithString: "No audio selected")
    private let timeLabel = NSTextField(labelWithString: "0:00.0 / 0:00.0")
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let recordButton = NSButton(title: "Start Recording", target: nil, action: nil)
    private let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let sampleLabel = NSTextField(labelWithString: "Not recording")
    private let primaryColorLabel = NSTextField(labelWithString: "#FF0000")
    private let primaryColorSwatch = NSBox()
    private let primaryColorField = ColorFieldView()
    private let primaryNullButton = NSButton(
        checkboxWithTitle: "No primary color",
        target: nil,
        action: nil
    )
    private let secondaryColorLabel = NSTextField(labelWithString: "None")
    private let secondaryColorSwatch = NSBox()
    private let secondaryColorField = ColorFieldView()
    private let secondaryNullButton = NSButton(
        checkboxWithTitle: "No secondary color",
        target: nil,
        action: nil
    )
    private let tertiaryColorLabel = NSTextField(labelWithString: "None")
    private let tertiaryColorSwatch = NSBox()
    private let tertiaryColorField = ColorFieldView()
    private let tertiaryNullButton = NSButton(
        checkboxWithTitle: "No tertiary color",
        target: nil,
        action: nil
    )

    private var audioPlayer: AVAudioPlayer?
    private var audioURL: URL?
    private var timer: Timer?
    private var samplesByFrame: [Int: ColorSample] = [:]
    private var primaryColor = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
    private var secondaryColor = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
    private var tertiaryColor = NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1)
    private var isRecording = false

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        configureControls()
        buildLayout()
        startTimer()
    }

    override func viewDidDisappear() {
        timer?.invalidate()
        timer = nil
        audioPlayer?.stop()
        super.viewDidDisappear()
    }

    private func configureControls() {
        fileLabel.lineBreakMode = .byTruncatingMiddle
        timeLabel.alignment = .center
        sampleLabel.textColor = .secondaryLabelColor
        primaryColorLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        secondaryColorLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        tertiaryColorLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)

        playButton.target = self
        playButton.action = #selector(togglePlayback)
        playButton.isEnabled = false

        stopButton.target = self
        stopButton.action = #selector(stopPlayback)
        stopButton.isEnabled = false

        recordButton.target = self
        recordButton.action = #selector(toggleRecording)
        recordButton.isEnabled = false

        progressSlider.target = self
        progressSlider.action = #selector(seek)
        progressSlider.isContinuous = true
        progressSlider.isEnabled = false

        configureColorControl(field: primaryColorField, swatch: primaryColorSwatch, color: primaryColor)
        primaryColorField.onColorChange = { [weak self] color in
            self?.primaryColor = color
            self?.primaryColorLabel.stringValue = Self.hexString(for: color)
            self?.primaryColorSwatch.fillColor = color
        }

        primaryNullButton.target = self
        primaryNullButton.action = #selector(togglePrimaryColor)
        primaryNullButton.state = .off
        updatePrimaryColorState()

        configureColorControl(field: secondaryColorField, swatch: secondaryColorSwatch, color: secondaryColor)
        secondaryColorField.onColorChange = { [weak self] color in
            self?.secondaryColor = color
            self?.secondaryColorLabel.stringValue = Self.hexString(for: color)
            self?.secondaryColorSwatch.fillColor = color
        }

        secondaryNullButton.target = self
        secondaryNullButton.action = #selector(toggleSecondaryColor)
        secondaryNullButton.state = .on
        updateSecondaryColorState()

        configureColorControl(field: tertiaryColorField, swatch: tertiaryColorSwatch, color: tertiaryColor)
        tertiaryColorField.onColorChange = { [weak self] color in
            self?.tertiaryColor = color
            self?.tertiaryColorLabel.stringValue = Self.hexString(for: color)
            self?.tertiaryColorSwatch.fillColor = color
        }

        tertiaryNullButton.target = self
        tertiaryNullButton.action = #selector(toggleTertiaryColor)
        tertiaryNullButton.state = .on
        updateTertiaryColorState()
    }

    private func buildLayout() {
        let chooseButton = NSButton(title: "Choose Audio…", target: self, action: #selector(chooseAudio))
        chooseButton.bezelStyle = .rounded

        let playbackButtons = NSStackView(views: [playButton, stopButton])
        playbackButtons.orientation = .horizontal
        playbackButtons.spacing = 8
        playbackButtons.distribution = .fillEqually

        let leftTitle = NSTextField(labelWithString: "Audio")
        leftTitle.font = .systemFont(ofSize: 20, weight: .semibold)

        let leftPanel = NSStackView(views: [
            leftTitle,
            chooseButton,
            fileLabel,
            progressSlider,
            timeLabel,
            playbackButtons,
            recordButton,
            sampleLabel
        ])
        leftPanel.orientation = .vertical
        leftPanel.alignment = .leading
        leftPanel.spacing = 12
        leftPanel.setCustomSpacing(24, after: fileLabel)
        leftPanel.translatesAutoresizingMaskIntoConstraints = false

        let rightTitle = NSTextField(labelWithString: "Colors")
        rightTitle.font = .systemFont(ofSize: 20, weight: .semibold)

        let primaryPanel = makeColorPanel(
            title: "Primary",
            field: primaryColorField,
            swatch: primaryColorSwatch,
            label: primaryColorLabel,
            nullButton: primaryNullButton
        )
        let secondaryPanel = makeColorPanel(
            title: "Secondary",
            field: secondaryColorField,
            swatch: secondaryColorSwatch,
            label: secondaryColorLabel,
            nullButton: secondaryNullButton
        )
        let tertiaryPanel = makeColorPanel(
            title: "Tertiary",
            field: tertiaryColorField,
            swatch: tertiaryColorSwatch,
            label: tertiaryColorLabel,
            nullButton: tertiaryNullButton
        )

        let colorPanels = NSStackView(views: [primaryPanel, secondaryPanel, tertiaryPanel])
        colorPanels.orientation = .horizontal
        colorPanels.alignment = .top
        colorPanels.distribution = .fillEqually
        colorPanels.spacing = 16

        let hint = NSTextField(labelWithString: "Move across the color fields while the music plays.")
        hint.textColor = .secondaryLabelColor

        let rightPanel = NSStackView(views: [rightTitle, colorPanels, hint])
        rightPanel.orientation = .vertical
        rightPanel.alignment = .leading
        rightPanel.spacing = 12
        rightPanel.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(leftPanel)
        view.addSubview(divider)
        view.addSubview(rightPanel)

        NSLayoutConstraint.activate([
            leftPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            leftPanel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            leftPanel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
            leftPanel.widthAnchor.constraint(equalToConstant: 280),

            divider.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: 24),
            divider.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            divider.widthAnchor.constraint(equalToConstant: 1),

            rightPanel.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 24),
            rightPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            rightPanel.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            rightPanel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),

            primaryColorField.widthAnchor.constraint(greaterThanOrEqualToConstant: 260),
            primaryColorField.heightAnchor.constraint(equalTo: primaryColorField.widthAnchor),
            secondaryColorField.widthAnchor.constraint(equalTo: primaryColorField.widthAnchor),
            secondaryColorField.heightAnchor.constraint(equalTo: secondaryColorField.widthAnchor),
            tertiaryColorField.widthAnchor.constraint(equalTo: primaryColorField.widthAnchor),
            tertiaryColorField.heightAnchor.constraint(equalTo: tertiaryColorField.widthAnchor),
            primaryColorSwatch.widthAnchor.constraint(equalToConstant: 28),
            primaryColorSwatch.heightAnchor.constraint(equalToConstant: 28),
            secondaryColorSwatch.widthAnchor.constraint(equalToConstant: 28),
            secondaryColorSwatch.heightAnchor.constraint(equalToConstant: 28),
            tertiaryColorSwatch.widthAnchor.constraint(equalToConstant: 28),
            tertiaryColorSwatch.heightAnchor.constraint(equalToConstant: 28),

            chooseButton.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),
            fileLabel.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),
            progressSlider.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),
            timeLabel.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),
            playbackButtons.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),
            recordButton.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),
            sampleLabel.widthAnchor.constraint(equalTo: leftPanel.widthAnchor)
        ])
    }

    private func makeColorPanel(
        title: String,
        field: ColorFieldView,
        swatch: NSBox,
        label: NSTextField,
        nullButton: NSButton? = nil
    ) -> NSStackView {
        let colorRow = NSStackView(views: [swatch, label])
        colorRow.orientation = .horizontal
        colorRow.alignment = .centerY
        colorRow.spacing = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)
        var views: [NSView] = [titleLabel, field, colorRow]
        if let nullButton {
            views.append(nullButton)
        }

        let panel = NSStackView(views: views)
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 8
        return panel
    }

    private func configureColorControl(field: ColorFieldView, swatch: NSBox, color: NSColor) {
        swatch.boxType = .custom
        swatch.borderWidth = 1
        swatch.borderColor = .separatorColor
        swatch.fillColor = color
        swatch.translatesAutoresizingMaskIntoConstraints = false

        field.wantsLayer = true
        field.layer?.cornerRadius = 8
        field.layer?.masksToBounds = true
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlaybackState()
            }
        }
    }

    private func updatePlaybackState() {
        guard let player = audioPlayer else { return }

        let duration = max(player.duration, 0)
        progressSlider.doubleValue = duration > 0 ? player.currentTime / duration : 0
        timeLabel.stringValue = "\(formatTime(player.currentTime)) / \(formatTime(duration))"
        playButton.title = player.isPlaying ? "Pause" : "Play"

        guard isRecording, player.isPlaying else { return }
        let frame = Int((player.currentTime * samplingRate).rounded(.down))
        samplesByFrame[frame] = makeSample(time: Double(frame) / samplingRate)
        sampleLabel.stringValue = "Recording • \(samplesByFrame.count) samples"
    }

    @objc private func chooseAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            audioPlayer = player
            audioURL = url
            fileLabel.stringValue = url.lastPathComponent
            playButton.isEnabled = true
            stopButton.isEnabled = true
            recordButton.isEnabled = true
            progressSlider.isEnabled = true
            samplesByFrame.removeAll()
            isRecording = false
            recordButton.title = "Start Recording"
            sampleLabel.stringValue = "Not recording"
            updatePlaybackState()
        } catch {
            showAlert(title: "Could not open audio", message: error.localizedDescription)
        }
    }

    @objc private func togglePlayback() {
        guard let player = audioPlayer else { return }

        if player.isPlaying {
            player.pause()
        } else {
            if player.currentTime >= player.duration {
                player.currentTime = 0
            }
            player.play()
        }
        updatePlaybackState()
    }

    @objc private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        updatePlaybackState()
    }

    @objc private func seek() {
        guard let player = audioPlayer else { return }
        player.currentTime = progressSlider.doubleValue * player.duration
        updatePlaybackState()
    }

    @objc private func toggleSecondaryColor() {
        updateSecondaryColorState()
    }

    @objc private func togglePrimaryColor() {
        updatePrimaryColorState()
    }

    private func updatePrimaryColorState() {
        updateOptionalColorState(
            button: primaryNullButton,
            field: primaryColorField,
            label: primaryColorLabel,
            swatch: primaryColorSwatch,
            color: primaryColor
        )
    }

    private func updateSecondaryColorState() {
        updateOptionalColorState(
            button: secondaryNullButton,
            field: secondaryColorField,
            label: secondaryColorLabel,
            swatch: secondaryColorSwatch,
            color: secondaryColor
        )
    }

    @objc private func toggleTertiaryColor() {
        updateTertiaryColorState()
    }

    private func updateTertiaryColorState() {
        updateOptionalColorState(
            button: tertiaryNullButton,
            field: tertiaryColorField,
            label: tertiaryColorLabel,
            swatch: tertiaryColorSwatch,
            color: tertiaryColor
        )
    }

    private func updateOptionalColorState(
        button: NSButton,
        field: ColorFieldView,
        label: NSTextField,
        swatch: NSBox,
        color: NSColor
    ) {
        let isNull = button.state == .on
        field.isSelectionEnabled = !isNull
        label.stringValue = isNull ? "None" : Self.hexString(for: color)
        swatch.fillColor = isNull ? .clear : color
    }

    @objc private func toggleRecording() {
        if isRecording {
            isRecording = false
            recordButton.title = "Start Recording"
            sampleLabel.stringValue = "\(samplesByFrame.count) samples ready"
            saveDataset()
            return
        }

        samplesByFrame.removeAll()
        isRecording = true
        recordButton.title = "Stop & Save"
        sampleLabel.stringValue = "Recording • 0 samples"
    }

    private func saveDataset() {
        guard let url = audioURL, let player = audioPlayer else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.directoryURL = url.deletingLastPathComponent()
        panel.nameFieldStringValue = "\(url.deletingPathExtension().lastPathComponent).colors.json"

        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let dataset = Dataset(
            formatVersion: 5,
            createdAt: Date(),
            audio: AudioReference(
                fileName: url.lastPathComponent,
                path: url.path,
                durationSeconds: rounded(player.duration)
            ),
            sampling: SamplingDescription(rateHz: samplingRate, colorSpace: "sRGB"),
            samples: samplesByFrame.values.sorted { $0.timeSeconds < $1.timeSeconds }
        )

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(dataset).write(to: destination, options: .atomic)
            sampleLabel.stringValue = "Saved \(samplesByFrame.count) samples"
        } catch {
            showAlert(title: "Could not save data", message: error.localizedDescription)
        }
    }

    private func makeSample(time: Double) -> ColorSample {
        return ColorSample(
            timeSeconds: rounded(time),
            primary: primaryNullButton.state == .on ? nil : makeColorValue(from: primaryColor),
            secondary: secondaryNullButton.state == .on ? nil : makeColorValue(from: secondaryColor),
            tertiary: tertiaryNullButton.state == .on ? nil : makeColorValue(from: tertiaryColor)
        )
    }

    private func makeColorValue(from selectedColor: NSColor) -> ColorValue {
        let color = selectedColor.usingColorSpace(.sRGB) ?? selectedColor
        return ColorValue(
            hex: Self.hexString(for: color),
            red: rounded(Double(color.redComponent)),
            green: rounded(Double(color.greenComponent)),
            blue: rounded(Double(color.blueComponent))
        )
    }

    private func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)
        let minutes = Int(safeSeconds) / 60
        let remainingSeconds = safeSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
    }

    private static func hexString(for color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(
            format: "#%02X%02X%02X",
            Int((rgb.redComponent * 255).rounded()),
            Int((rgb.greenComponent * 255).rounded()),
            Int((rgb.blueComponent * 255).rounded())
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = CollectorViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Synesthesia Data Collector"
        window.setContentSize(NSSize(width: 1_360, height: 560))
        window.minSize = NSSize(width: 1_190, height: 520)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
