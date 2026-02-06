import AVFoundation
import AppKit
import Foundation

@MainActor
final class TeleprompterViewModel: ObservableObject {
    @Published var scriptText: String = defaultScript
    @Published var isRunning: Bool = false
    @Published var statusText: String = "Idle"
    @Published var highlightRange: NSRange?
    @Published var showKeyPanel: Bool = false
    @Published var apiKeyInput: String = ""
    @Published var speechRateWPM: Double = 0
    @Published var scrollAnimationDuration: Double = 0.18
    @Published var windowOpacity: Double = 1.0
    @Published var micLevel: Float = 0
    @Published var isExpanded: Bool = false
    @Published var isHovering: Bool = false

    let fontSize: CGFloat = 22

    static let defaultScript = """
So, this is Hyprnote.

The problem we're solving is simple: meetings create a lot of information, and almost all of it gets lost.

You either try to take notes and miss the conversation, or you pay attention and forget what was said. Recording helps, but raw audio is basically unusable. Transcripts help, but they're noisy, long, and disconnected from how people actually work.

Hyprnote sits in the middle.

It listens to meetings locally on your device. No forced cloud. No sending your audio somewhere you don't control. Everything is file-based and stays with you.

While the meeting is happening, Hyprnote captures audio, detects speakers, and structures what's going on in real time. After the meeting, you don't get a giant wall of text. You get notes that actually resemble how humans think: summaries, decisions, action items, and context.

The important part is choice.

You can use whatever AI model you want. Local models, your own API key, or none at all. Hyprnote doesn't lock you into a black box. It's designed to work even when you're offline.

Under the hood, everything is just files. Markdown notes. Audio files. A folder structure you can understand. That means you can search them, version them, sync them however you want, or even open them in other tools.

This isn't an \"AI replaces your brain\" product.

It's an augmentation tool. It handles the mechanical parts of meetings so you can focus on thinking, listening, and deciding.

We built Hyprnote for people who care about ownership, privacy, and long-term leverage over their work.

If you believe your notes are part of your thinking, they should live with you. Not on someone else's server.
"""

    private let keychain = KeychainStore(service: "Autoprompter", account: "DeepgramAPIKey")
    private var lineRanges: [NSRange] = []
    private var currentLineIndex: Int = 0
    private var lastProcessedWordEnd: Double = 0
    private var recentWordTimes: [Double] = []
    private var streamer: DeepgramStreamer?
    private let aligner = SemanticAligner()
    private var utterancesSinceLastMatch: Int = 0

    func loadAPIKeyIfNeeded() {
        if let key = keychain.read(), !key.isEmpty {
            apiKeyInput = key
            showKeyPanel = false
        } else {
            showKeyPanel = true
        }
    }

    private func updateLineHighlight(forLine lineIndex: Int) {
        guard lineIndex >= 0, lineIndex < lineRanges.count else { return }
        if lineIndex != currentLineIndex || highlightRange == nil {
            currentLineIndex = lineIndex
            highlightRange = lineRanges[lineIndex]
        }
    }

    func pasteAPIKey() {
        if let pasted = NSPasteboard.general.string(forType: .string) {
            apiKeyInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func dismissKeyPanel() {
        showKeyPanel = false
    }

    func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = keychain.save(trimmed)
        showKeyPanel = false
    }

    func start() {
        guard let apiKey = keychain.read(), !apiKey.isEmpty else {
            showKeyPanel = true
            return
        }
        guard !scriptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusText = "Paste a script to start."
            return
        }

        Task {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                statusText = "Microphone access denied."
                return
            }
            beginStreaming(apiKey: apiKey)
        }
    }

    func stop() {
        isRunning = false
        statusText = "Stopped"
        streamer?.stop()
        streamer = nil
        speechRateWPM = 0
        micLevel = 0
        recentWordTimes.removeAll()
        lastProcessedWordEnd = 0
        utterancesSinceLastMatch = 0
        aligner.reset()
    }

    private func beginStreaming(apiKey: String) {
        prepareScript()
        isRunning = true
        statusText = "Connecting…"
        lastProcessedWordEnd = 0
        utterancesSinceLastMatch = 0

        streamer = DeepgramStreamer(
            apiKey: apiKey,
            onStatus: { [weak self] status in
                Task { @MainActor in self?.statusText = status }
            },
            onWords: { [weak self] words in
                Task { @MainActor in self?.handleRecognizedWords(words) }
            },
            onUtterance: { [weak self] utterance in
                Task { @MainActor in self?.handleUtterance(utterance) }
            },
            onLevel: { [weak self] level in
                Task { @MainActor in self?.micLevel = level }
            }
        )
        streamer?.start()
    }

    private func prepareScript() {
        lineRanges = WordTokenizer.lineRanges(in: scriptText)
        aligner.prepare(script: scriptText, lineRanges: lineRanges)
        currentLineIndex = 0
        highlightRange = lineRanges.first
    }

    private func handleRecognizedWords(_ words: [RecognizedWord]) {
        guard isRunning else { return }
        for word in words {
            if word.end <= lastProcessedWordEnd { continue }
            lastProcessedWordEnd = word.end
            updateSpeechRate(using: word.end)
        }
    }

    private func handleUtterance(_ utterance: String) {
        guard isRunning else { return }

        if let result = aligner.match(utterance: utterance) {
            updateLineHighlight(forLine: result.lineIndex)
            utterancesSinceLastMatch = 0
        } else {
            // No semantic match — gently advance after a few unmatched utterances
            // so the prompter doesn't get stuck.
            utterancesSinceLastMatch += 1
            if utterancesSinceLastMatch >= 3, let result = aligner.advanceOneSegment() {
                updateLineHighlight(forLine: result.lineIndex)
                utterancesSinceLastMatch = 0
            }
        }
    }

    private func updateSpeechRate(using timestamp: Double) {
        recentWordTimes.append(timestamp)
        if recentWordTimes.count > 20 {
            recentWordTimes.removeFirst(recentWordTimes.count - 20)
        }
        guard let first = recentWordTimes.first, let last = recentWordTimes.last, last > first else { return }
        let wpm = (Double(recentWordTimes.count - 1) / (last - first)) * 60
        speechRateWPM = wpm
        let clamped = max(0.08, min(0.28, 12.0 / max(wpm, 40)))
        scrollAnimationDuration = clamped
    }

}
