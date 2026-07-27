import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingOverlayModel: ObservableObject {
    @Published var isPresented = false
    @Published var isExpanded = false
    @Published var audioLevel = 0.0
    @Published var targetAppIcon: NSImage
    @Published var targetAppName = "Current app"

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
    private var previewStartTime = Date()

    func show(
        targetApplication: NSRunningApplication?,
        levelProvider: @escaping () -> Double
    ) {
        preparePresentation(targetApplication: targetApplication)
        startLevelUpdates(levelProvider: levelProvider)
        animateIn()
    }

    func showPreview(targetApplication: NSRunningApplication?) {
        previewStartTime = Date()
        preparePresentation(targetApplication: targetApplication)
        startLevelUpdates { [weak self] in
            self?.simulatedAudioLevel() ?? 0.35
        }
        animateIn()
    }

    func hide() {
        stopLevelUpdates()

        withAnimation(.smooth(duration: 0.2)) {
            model.isExpanded = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            guard let self else { return }

            withAnimation(.easeOut(duration: 0.16)) {
                self.model.isPresented = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }
}

@MainActor
private extension RecordingOverlayController {
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
        model.audioLevel = 0
        model.isPresented = false
        model.isExpanded = false

        positionPanel()
        panel.orderFrontRegardless()
    }

    func animateIn() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                self.model.isPresented = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }

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

    func startLevelUpdates(levelProvider: @escaping () -> Double) {
        stopLevelUpdates()

        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let nextLevel = min(max(levelProvider(), 0), 1)
                let smoothing = nextLevel > self.model.audioLevel ? 0.11 : 0.055
                self.model.audioLevel += (nextLevel - self.model.audioLevel) * smoothing

                if nextLevel == 0, self.model.audioLevel < 0.008 {
                    self.model.audioLevel = 0
                }
            }
        }
    }

    func stopLevelUpdates() {
        levelTimer?.invalidate()
        levelTimer = nil
    }

    func simulatedAudioLevel() -> Double {
        let elapsed = Date().timeIntervalSince(previewStartTime)
        let cyclePosition = elapsed.truncatingRemainder(dividingBy: 5)

        guard cyclePosition > 1.5 else { return 0 }

        let slowPulse = (sin(elapsed * 2.1) + 1) * 0.16
        let voicePulse = abs(sin(elapsed * 6.7)) * 0.34
        let detail = abs(sin(elapsed * 13.1)) * 0.13
        return min(0.22 + slowPulse + voicePulse + detail, 0.9)
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

            FlowingWaveform(level: model.audioLevel)
                .frame(width: 126, height: 28)

            Divider()
                .frame(height: 24)
                .overlay(.primary.opacity(0.2))

            HStack(spacing: 5) {
                Text("ESC")
                    .font(.system(size: 10.5, weight: .semibold, design: .default))
                    .offset(x: 1, y: -0.75)
                    .frame(width: 34, height: 22, alignment: .center)
                    .foregroundStyle(.primary)
                    .background(.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.primary.opacity(0.18), lineWidth: 0.75)
                    }

                Text("to cancel")
                    .font(.system(size: 11, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .padding(.leading, 10)
        .padding(.trailing, 13)
    }
}

private struct FlowingWaveform: View {
    let level: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let path = waveformPath(
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )

                context.stroke(
                    path,
                    with: .color(.primary.opacity(0.94)),
                    style: StrokeStyle(
                        lineWidth: 2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .drawingGroup()
        .accessibilityHidden(true)
    }

    private func waveformPath(size: CGSize, time: TimeInterval) -> Path {
        var path = Path()
        let centerY = size.height / 2
        let visibleLevel = max((level - 0.04) / 0.96, 0)

        guard visibleLevel > 0 else {
            path.move(to: CGPoint(x: 0, y: centerY))
            path.addLine(to: CGPoint(x: size.width, y: centerY))
            return path
        }

        let pointCount = max(Int(size.width / 2), 2)
        let energy = CGFloat(pow(visibleLevel, 0.58))
        let amplitude = energy * size.height * 0.48
        let motion = time * 7.6

        for index in 0...pointCount {
            let progress = CGFloat(index) / CGFloat(pointCount)
            let x = progress * size.width
            let envelope = sin(progress * .pi)
            let primary = sin(progress * 32 + motion)
            let detail = sin(progress * 67 - motion * 0.72) * (0.2 + energy * 0.12)
            let y = centerY + (primary + detail) * amplitude * envelope
            let point = CGPoint(x: x, y: y)

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        return path
    }
}
