import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: TeleprompterViewModel

    var body: some View {
        VStack(spacing: 12) {
            header
            ZStack(alignment: .topLeading) {
                TeleprompterTextView(
                    text: $viewModel.scriptText,
                    highlightRange: $viewModel.highlightRange,
                    isEditable: !viewModel.isRunning,
                    fontSize: viewModel.fontSize,
                    scrollAnimationDuration: viewModel.scrollAnimationDuration
                )
                if viewModel.scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Paste your script here…")
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: $viewModel.showKeyPanel) {
            APIKeyPanel(
                apiKey: $viewModel.apiKeyInput,
                onSave: viewModel.saveAPIKey,
                onPaste: viewModel.pasteAPIKey,
                onClose: viewModel.dismissKeyPanel
            )
        }
        .onAppear {
            viewModel.loadAPIKeyIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.isRunning ? viewModel.stop() : viewModel.start()
            } label: {
                Text(viewModel.isRunning ? "Stop" : "Start")
                    .frame(width: 60)
            }
            .keyboardShortcut(.space, modifiers: [])

            Text(viewModel.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if viewModel.isRunning {
                MicBars(level: viewModel.micLevel)
            }

            if viewModel.speechRateWPM > 0 {
                Text(String(format: "%.0f wpm", viewModel.speechRateWPM))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Inline translucency slider
            HStack(spacing: 4) {
                Image(systemName: "eye")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $viewModel.windowOpacity, in: 0.15...1)
                    .frame(width: 64)
            }

            Button("API Key") {
                viewModel.showKeyPanel = true
            }
        }
    }
}

// MARK: - Mic bars

struct MicBars: View {
    let level: Float

    /// Map raw RMS (typically 0–0.3) to 0–1 for display.
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
        .frame(height: 16)
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Each bar has a different sensitivity so they fluctuate at different levels.
        let thresholds: [CGFloat] = [0.05, 0.2, 0.45]
        let minH: CGFloat = 3
        let maxH: CGFloat = 16
        let effective = max(0, normalized - thresholds[index]) / (1 - thresholds[index])
        return minH + effective * (maxH - minH)
    }
}


struct APIKeyPanel: View {
    @Binding var apiKey: String
    let onSave: () -> Void
    let onPaste: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Deepgram API Key")
                .font(.headline)
            TextField("Paste your key…", text: $apiKey)
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
        .frame(width: 420)
    }
}
