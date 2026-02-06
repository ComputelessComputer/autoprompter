import SwiftUI

// MARK: - Notch shape

struct NotchShape: Shape {
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY),
            radius: r
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r),
            radius: r
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Main notch content view

struct NotchContentView: View {
    @ObservedObject var viewModel: TeleprompterViewModel
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    @State private var hoverTask: Task<Void, Never>?

    private var showContent: Bool {
        viewModel.isExpanded || viewModel.isRunning
    }

    private var showHeader: Bool {
        !viewModel.isRunning || viewModel.isHovering
    }

    private var cornerRadius: CGFloat {
        showContent ? 20 : 10
    }

    var body: some View {
        VStack(spacing: 0) {
            collapsedBar
                .frame(height: notchHeight)

            if showContent {
                contentArea
                    .opacity(viewModel.windowOpacity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .clipShape(NotchShape(cornerRadius: cornerRadius))
        .contentShape(NotchShape(cornerRadius: cornerRadius))
        .shadow(color: .black.opacity(showContent ? 0.5 : 0), radius: 12, y: 5)
        .onHover { handleHover($0) }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isExpanded)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isRunning)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isHovering)
        .onAppear {
            viewModel.loadAPIKeyIfNeeded()
        }
        .sheet(isPresented: $viewModel.showKeyPanel) {
            APIKeyPanel(
                apiKey: $viewModel.apiKeyInput,
                onSave: viewModel.saveAPIKey,
                onPaste: viewModel.pasteAPIKey,
                onClose: viewModel.dismissKeyPanel
            )
        }
    }

    // MARK: - Hover handling

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            viewModel.isHovering = true

            if !viewModel.isRunning && !viewModel.isExpanded {
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                    viewModel.isExpanded = true
                }
            }
        } else {
            hoverTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                viewModel.isHovering = false

                if !viewModel.isRunning && !viewModel.showKeyPanel {
                    viewModel.isExpanded = false
                }
            }
        }
    }

    // MARK: - Content area (adapts to running/hover state)

    private var contentArea: some View {
        VStack(spacing: 10) {
            if showHeader {
                header
                    .transition(.opacity)
            }
            ZStack(alignment: .topLeading) {
                TeleprompterTextView(
                    text: $viewModel.scriptText,
                    highlightRange: $viewModel.highlightRange,
                    isEditable: !viewModel.isRunning,
                    fontSize: viewModel.fontSize,
                    scrollAnimationDuration: viewModel.scrollAnimationDuration
                )
                if viewModel.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !viewModel.isRunning {
                    Text("Paste your script here\u{2026}")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 10)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, viewModel.isRunning && !viewModel.isHovering ? 8 : 12)
        .padding(.top, 4)
    }

    // MARK: - Collapsed bar (wings)

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if viewModel.isRunning {
                    MicBars(level: viewModel.micLevel)
                }
                Text(viewModel.statusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 10)

            Color.clear
                .frame(width: notchWidth)

            HStack(spacing: 6) {
                if viewModel.speechRateWPM > 0 {
                    Text(String(format: "%.0f wpm", viewModel.speechRateWPM))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                }
                Button {
                    viewModel.isExpanded.toggle()
                } label: {
                    Image(systemName: viewModel.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !viewModel.isExpanded {
                viewModel.isExpanded = true
            }
        }
    }

    // MARK: - Header controls

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                viewModel.isRunning ? viewModel.stop() : viewModel.start()
            } label: {
                Text(viewModel.isRunning ? "Stop" : "Start")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 50)
            }
            .keyboardShortcut(.space, modifiers: [])

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "eye")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.5))
                Slider(value: $viewModel.windowOpacity, in: 0.15...1)
                    .frame(width: 50)
            }

            Button {
                viewModel.showKeyPanel = true
            } label: {
                Image(systemName: "key")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)

            Button {
                viewModel.isExpanded = false
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Mic bars

struct MicBars: View {
    let level: Float

    private var normalized: CGFloat {
        let clamped = min(max(CGFloat(level) / 0.15, 0), 1)
        return clamped
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                let barHeight = barHeight(for: i)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.red)
                    .frame(width: 3, height: barHeight)
                    .animation(.easeOut(duration: 0.08), value: barHeight)
            }
        }
        .frame(height: 14)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let thresholds: [CGFloat] = [0.05, 0.2, 0.45]
        let minH: CGFloat = 3
        let maxH: CGFloat = 14
        let effective = max(0, normalized - thresholds[index]) / (1 - thresholds[index])
        return minH + effective * (maxH - minH)
    }
}

// MARK: - API Key panel

struct APIKeyPanel: View {
    @Binding var apiKey: String
    let onSave: () -> Void
    let onPaste: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deepgram API Key")
                .font(.headline)
            TextField("Paste your key\u{2026}", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Paste") { onPaste() }
                Spacer()
                Button("Cancel") { onClose() }
                Button("Save") { onSave() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
