import AppKit
import AVFoundation
import SynesthesiaData
import UniformTypeIdentifiers

@MainActor
private final class ColorShowView: NSView {
    var sample: ColorSample? {
        didSet {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()

        guard let sample, let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let shortestSide = min(bounds.width, bounds.height)
        let dotRadius = max(38, min(68, shortestSide * 0.09))

        if let tertiary = sample.tertiary {
            drawTertiary(tertiary, center: center, dotRadius: dotRadius, context: context)
        }

        if let secondary = sample.secondary {
            drawSecondary(secondary, center: center, dotRadius: dotRadius, context: context)
        }

        if let primary = sample.primary {
            let primaryColor = color(from: primary)
            let dot = NSBezierPath(
                ovalIn: NSRect(
                    x: center.x - dotRadius,
                    y: center.y - dotRadius,
                    width: dotRadius * 2,
                    height: dotRadius * 2
                )
            )
            context.saveGState()
            context.setShadow(offset: .zero, blur: 18, color: primaryColor.withAlphaComponent(0.55).cgColor)
            primaryColor.setFill()
            dot.fill()
            context.restoreGState()
        }
    }

    private func drawSecondary(
        _ value: ColorValue,
        center: CGPoint,
        dotRadius: CGFloat,
        context: CGContext
    ) {
        let secondary = color(from: value)
        let colors = [
            secondary.withAlphaComponent(0.9).cgColor,
            secondary.withAlphaComponent(0.45).cgColor,
            secondary.withAlphaComponent(0).cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 0.45, 1]
        ) else { return }

        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: dotRadius * 0.75,
            endCenter: center,
            endRadius: dotRadius * 3.2,
            options: []
        )
    }

    private func drawTertiary(
        _ value: ColorValue,
        center: CGPoint,
        dotRadius: CGFloat,
        context: CGContext
    ) {
        let tertiary = color(from: value)
        let colors = [
            tertiary.withAlphaComponent(0).cgColor,
            tertiary.withAlphaComponent(0.12).cgColor,
            tertiary.withAlphaComponent(0.9).cgColor
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors,
            locations: [0, 0.58, 1]
        ) else { return }

        let outerRadius = hypot(bounds.width, bounds.height) / 2
        context.drawRadialGradient(
            gradient,
            startCenter: center,
            startRadius: dotRadius * 2,
            endCenter: center,
            endRadius: outerRadius,
            options: [.drawsAfterEndLocation]
        )
    }

    private func color(from value: ColorValue) -> NSColor {
        NSColor(
            srgbRed: value.red,
            green: value.green,
            blue: value.blue,
            alpha: 1
        )
    }
}

@MainActor
private final class ColorShowViewController: NSViewController {
    private let audioLabel = NSTextField(labelWithString: "No audio selected")
    private let dataLabel = NSTextField(labelWithString: "No color data selected")
    private let statusLabel = NSTextField(labelWithString: "Choose matching audio and color data files")
    private let timeLabel = NSTextField(labelWithString: "0:00.0 / 0:00.0")
    private let playButton = NSButton(title: "Play", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let progressSlider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let colorShowView = ColorShowView()

    private var audioPlayer: AVAudioPlayer?
    private var audioURL: URL?
    private var dataset: Dataset?
    private var timer: Timer?
    private var isPairReady = false
    private var displayedSampleTime: Double?

    override func loadView() {
        view = NSView()
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
        audioLabel.lineBreakMode = .byTruncatingMiddle
        dataLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.textColor = .secondaryLabelColor
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        playButton.target = self
        playButton.action = #selector(togglePlayback)
        playButton.isEnabled = false

        stopButton.target = self
        stopButton.action = #selector(stopPlayback)
        stopButton.isEnabled = false

        progressSlider.target = self
        progressSlider.action = #selector(seek)
        progressSlider.isContinuous = true
        progressSlider.isEnabled = false
    }

    private func buildLayout() {
        let audioButton = NSButton(title: "Choose Audio…", target: self, action: #selector(chooseAudio))
        let dataButton = NSButton(title: "Choose Color Data…", target: self, action: #selector(chooseData))

        let fileControls = NSStackView(views: [audioButton, audioLabel, dataButton, dataLabel])
        fileControls.orientation = .horizontal
        fileControls.alignment = .centerY
        fileControls.spacing = 10

        let playbackControls = NSStackView(views: [playButton, stopButton, timeLabel, statusLabel])
        playbackControls.orientation = .horizontal
        playbackControls.alignment = .centerY
        playbackControls.spacing = 10

        let controls = NSStackView(views: [fileControls, progressSlider, playbackControls])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 10
        controls.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        controls.translatesAutoresizingMaskIntoConstraints = false

        colorShowView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        view.addSubview(colorShowView)

        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.topAnchor.constraint(equalTo: view.topAnchor),

            audioLabel.widthAnchor.constraint(equalToConstant: 220),
            dataLabel.widthAnchor.constraint(equalToConstant: 220),
            progressSlider.widthAnchor.constraint(equalTo: controls.widthAnchor, constant: -32),
            timeLabel.widthAnchor.constraint(equalToConstant: 120),

            colorShowView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            colorShowView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            colorShowView.topAnchor.constraint(equalTo: controls.bottomAnchor),
            colorShowView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePlayback()
            }
        }
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
            audioPlayer?.stop()
            audioPlayer = player
            audioURL = url
            audioLabel.stringValue = url.lastPathComponent
            validatePair()
        } catch {
            showAlert(title: "Could not open audio", message: error.localizedDescription)
        }
    }

    @objc private func chooseData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            dataset = try decoder.decode(Dataset.self, from: Data(contentsOf: url))
            dataLabel.stringValue = url.lastPathComponent
            validatePair()
        } catch {
            dataset = nil
            dataLabel.stringValue = "No color data selected"
            validatePair()
            showAlert(title: "Could not open color data", message: error.localizedDescription)
        }
    }

    private func validatePair() {
        audioPlayer?.pause()
        playButton.title = "Play"
        isPairReady = false
        playButton.isEnabled = false
        stopButton.isEnabled = false
        progressSlider.isEnabled = false
        progressSlider.doubleValue = 0
        colorShowView.sample = nil
        displayedSampleTime = nil

        guard let player = audioPlayer, let audioURL, let dataset else {
            setStatus("Choose matching audio and color data files", color: .secondaryLabelColor)
            return
        }
        guard dataset.formatVersion >= 4 else {
            setStatus("Color data must use format version 4 or later", color: .systemRed)
            return
        }
        guard dataset.audio.fileName == audioURL.lastPathComponent else {
            setStatus("Color data expects \(dataset.audio.fileName)", color: .systemRed)
            return
        }
        guard abs(dataset.audio.durationSeconds - player.duration) <= 0.5 else {
            setStatus("Audio duration does not match the color data", color: .systemRed)
            return
        }
        guard !dataset.samples.isEmpty else {
            setStatus("Color data contains no samples", color: .systemRed)
            return
        }

        isPairReady = true
        playButton.isEnabled = true
        stopButton.isEnabled = true
        progressSlider.isEnabled = true
        setStatus("Ready", color: .systemGreen)
        updatePlayback()
    }

    @objc private func togglePlayback() {
        guard isPairReady, let player = audioPlayer else { return }

        if player.isPlaying {
            player.pause()
        } else {
            if player.currentTime >= player.duration {
                player.currentTime = 0
            }
            player.play()
        }
        updatePlayback()
    }

    @objc private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        updatePlayback()
    }

    @objc private func seek() {
        guard isPairReady, let player = audioPlayer else { return }
        player.currentTime = progressSlider.doubleValue * player.duration
        displayedSampleTime = nil
        updatePlayback()
    }

    private func updatePlayback() {
        guard isPairReady, let player = audioPlayer, let dataset else { return }

        playButton.title = player.isPlaying ? "Pause" : "Play"
        progressSlider.doubleValue = player.duration > 0 ? player.currentTime / player.duration : 0
        timeLabel.stringValue = "\(formatTime(player.currentTime)) / \(formatTime(player.duration))"
        let currentSample = sample(at: player.currentTime, in: dataset)
        guard currentSample?.timeSeconds != displayedSampleTime else { return }
        displayedSampleTime = currentSample?.timeSeconds
        colorShowView.sample = currentSample
    }

    private func sample(at time: TimeInterval, in dataset: Dataset) -> ColorSample? {
        let samples = dataset.samples
        var lowerBound = 0
        var upperBound = samples.count

        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if samples[middle].timeSeconds <= time {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let index = lowerBound - 1
        guard index >= 0 else { return nil }
        let sample = samples[index]
        let maximumGap = max(0.2, 2 / dataset.sampling.rateHz)
        return time - sample.timeSeconds <= maximumGap ? sample : nil
    }

    private func setStatus(_ text: String, color: NSColor) {
        statusLabel.stringValue = text
        statusLabel.textColor = color
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let safeSeconds = max(seconds, 0)
        let minutes = Int(safeSeconds) / 60
        let remainingSeconds = safeSeconds.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%04.1f", minutes, remainingSeconds)
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
        let controller = ColorShowViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "Color Show"
        window.setContentSize(NSSize(width: 1_000, height: 700))
        window.minSize = NSSize(width: 760, height: 520)
        window.collectionBehavior = [.fullScreenPrimary]
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
