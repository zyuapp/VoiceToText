import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayModel: ObservableObject {
    @Published var isPresented = false
    @Published var isExpanded = false
    @Published var targetAppIcon: NSImage
    @Published var targetAppName = "Current app"

    /// Level samples live outside `@Published` so 60 Hz metering never invalidates the
    /// pill's layout; the visualizer reads the track from its own timeline instead.
    let levelTrack = RecordingLevelTrack()

    init() {
        targetAppIcon = NSImage(
            systemSymbolName: "app.fill",
            accessibilityDescription: "Current app"
        ) ?? NSImage()
    }

    func updateTargetApplication(_ application: NSRunningApplication?) {
        targetAppName = application?.localizedName ?? "Current app"

        if let icon = application?.icon {
            targetAppIcon = icon
        }
    }
}

@MainActor
final class RecordingOverlayController {
    private let model = RecordingOverlayModel()
    private lazy var panel = createPanel()
    private var levelTimer: Timer?
    private var lastSampleTime: TimeInterval?
    private var previewStartTime = Date.timeIntervalSinceReferenceDate
    private var presentationGeneration = 0

    func show(
        targetApplication: NSRunningApplication?,
        levelProvider: @escaping (TimeInterval) -> Double
    ) {
        presentationGeneration += 1
        preparePresentation(targetApplication: targetApplication)
        startLevelUpdates(levelProvider: levelProvider)
        animateIn()
    }

    func showPreview(targetApplication: NSRunningApplication?) {
        presentationGeneration += 1
        previewStartTime = Date.timeIntervalSinceReferenceDate
        preparePresentation(targetApplication: targetApplication)
        startLevelUpdates { [weak self] _ in
            self?.simulatedAudioLevel() ?? 0
        }
        animateIn()
    }

    func hide() {
        presentationGeneration += 1
        let generation = presentationGeneration
        stopLevelUpdates()

        withAnimation(.smooth(duration: 0.2)) {
            model.isExpanded = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }

            withAnimation(.easeOut(duration: 0.16)) {
                self.model.isPresented = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }
            self.panel.orderOut(nil)
            self.model.levelTrack.clear()
        }
    }
}

@MainActor
private extension RecordingOverlayController {
    static let sampleInterval = 1.0 / 60.0
    static let maximumDeltaTime = 0.25

    func createPanel() -> NSPanel {
        let panel = RecordingOverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 370, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.contentView = NSHostingView(rootView: RecordingOverlayRootView(model: model))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.level = .statusBar

        return panel
    }

    func preparePresentation(targetApplication: NSRunningApplication?) {
        model.updateTargetApplication(targetApplication)
        model.levelTrack.clear()
        model.isPresented = false
        model.isExpanded = false

        positionPanel()
        panel.orderFrontRegardless()
    }

    func animateIn() {
        let generation = presentationGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentationGeneration == generation else { return }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                self.model.isPresented = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.presentationGeneration == generation else { return }

                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    self.model.isExpanded = true
                }
            }
        }
    }

    func positionPanel() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        } ?? NSScreen.main

        guard let screen else { return }

        let panelSize = panel.frame.size
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - panelSize.width / 2,
            y: frame.minY + 22
        )

        panel.setFrameOrigin(origin)
    }

    /// Runs in `.common` mode so menu tracking and window drags cannot stall metering.
    func startLevelUpdates(levelProvider: @escaping (TimeInterval) -> Double) {
        stopLevelUpdates()

        lastSampleTime = nil

        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleLevel(using: levelProvider)
            }
        }

        RunLoop.main.add(timer, forMode: .common)
        levelTimer = timer
    }

    func sampleLevel(using levelProvider: (TimeInterval) -> Double) {
        let now = Date.timeIntervalSinceReferenceDate
        let elapsed = lastSampleTime.map { now - $0 } ?? Self.sampleInterval
        lastSampleTime = now

        // Wall clock can jump backwards, which would drive the filters with a negative step.
        let deltaTime = min(max(elapsed, 0), Self.maximumDeltaTime)
        let level = min(max(levelProvider(deltaTime), 0), 1)
        model.levelTrack.append(level: level, at: now)
    }

    func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    /// Phrases of stressed syllables separated by pauses, so previews exercise the same
    /// dynamics real speech does.
    func simulatedAudioLevel() -> Double {
        let elapsed = Date.timeIntervalSinceReferenceDate - previewStartTime
        let phrasePosition = elapsed.truncatingRemainder(dividingBy: 4.2)

        guard phrasePosition > 0.35, phrasePosition < 3.4 else { return 0 }

        let syllable = pow(abs(sin(elapsed * 7.4)), 1.6)
        let stress = 0.55 + 0.45 * abs(sin(elapsed * 1.9))
        let grain = 0.85 + 0.15 * sin(elapsed * 23)
        return min(syllable * stress * grain * 1.3, 1)
    }
}

private final class RecordingOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct RecordingOverlayRootView: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        ZStack {
            Color.clear

            if model.isPresented {
                overlayContent
                    .transition(.scale(scale: 0.78).combined(with: .opacity))
            }
        }
        .frame(width: 370, height: 92)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording into \(model.targetAppName)")
        .accessibilityHint("Press Escape to cancel")
    }

    @ViewBuilder
    private var overlayContent: some View {
        if #available(macOS 26.0, *) {
            LiquidGlassRecordingOverlay(model: model)
        } else {
            LegacyRecordingOverlay(model: model)
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassRecordingOverlay: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        if model.isExpanded {
            RecordingPill(model: model)
                .frame(width: 300, height: 54)
                .glassEffect(.regular, in: Capsule())
                .glassEffectTransition(.materialize)
                .transition(
                    .scale(scale: 0.82, anchor: .center)
                        .combined(with: .opacity)
                )
        }
    }
}

private struct LegacyRecordingOverlay: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        if model.isExpanded {
            RecordingPill(model: model)
                .frame(width: 300, height: 54)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.28), lineWidth: 0.75)
                }
                .transition(.scale(scale: 0.82).combined(with: .opacity))
        }
    }
}

private struct TargetAppIcon: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        Image(nsImage: model.targetAppIcon)
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 36)
            .accessibilityLabel(model.targetAppName)
    }
}

private struct RecordingPill: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        HStack(spacing: 11) {
            TargetAppIcon(model: model)

            RecordingVisualizer(track: model.levelTrack)

            Divider()
                .frame(height: 24)
                .overlay(.primary.opacity(0.2))

            CancelHint()
        }
        .padding(.leading, 10)
        .padding(.trailing, 13)
    }
}

private struct CancelHint: View {
    var body: some View {
        HStack(spacing: 5) {
            Text("ESC")
                .font(.system(size: 10.5, weight: .semibold))
                .offset(x: 1, y: -0.75)
                .frame(width: 34, height: 22)
                .foregroundStyle(.primary)
                .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.primary.opacity(0.18), lineWidth: 0.75)
                }

            Text("to cancel")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}
