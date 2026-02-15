@preconcurrency import AVFoundation
import Foundation

final class DeepgramStreamer: @unchecked Sendable {
    private let apiKey: String
    private let onStatus: (String) -> Void
    private let onWords: ([DeepgramWord]) -> Void
    private let onUtterance: (String) -> Void
    private let onLevel: (Float) -> Void

    private let audioEngine = AVAudioEngine()
    private let audioQueue = DispatchQueue(label: "autoprompter.audio.queue")
    private var webSocketTask: URLSessionWebSocketTask?
    private var keepAliveTimer: Timer?
    private var sampleRate: Int = 44100

    init(
        apiKey: String,
        onStatus: @escaping (String) -> Void,
        onWords: @escaping ([DeepgramWord]) -> Void,
        onUtterance: @escaping (String) -> Void,
        onLevel: @escaping (Float) -> Void
    ) {
        self.apiKey = apiKey
        self.onStatus = onStatus
        self.onWords = onWords
        self.onUtterance = onUtterance
        self.onLevel = onLevel
    }

    func start() {
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = Int(format.sampleRate)

        guard let url = buildURL(sampleRate: sampleRate) else {
            onStatus("Invalid Deepgram URL")
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        webSocketTask = task
        task.resume()
        onStatus("Listening…")

        receiveLoop()
        startKeepAlive()
        startAudioCapture(with: format)
    }

    func stop() {
        stopAudioCapture()
        keepAliveTimer?.invalidate()
        keepAliveTimer = nil
        sendControlMessage(type: "CloseStream")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    private func startAudioCapture(with format: AVAudioFormat) {
        let input = audioEngine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.audioQueue.async { [weak self] in
                self?.sendAudioBuffer(buffer, format: format)
            }
        }
        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            onStatus("Audio error: \(error.localizedDescription)")
        }
    }

    private func stopAudioCapture() {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
    }

    private func sendAudioBuffer(_ buffer: AVAudioPCMBuffer, format: AVAudioFormat) {
        guard let channelData = buffer.floatChannelData else { return }
        let channelCount = Int(format.channelCount)
        let frames = Int(buffer.frameLength)

        // Compute RMS level for the mic indicator.
        var sumSquares: Float = 0
        let ptr = channelData[0]
        for i in 0..<frames { sumSquares += ptr[i] * ptr[i] }
        let rms = sqrt(sumSquares / max(Float(frames), 1))
        onLevel(rms)

        var pcmData = Data(count: frames * MemoryLayout<Int16>.size)
        pcmData.withUnsafeMutableBytes { rawBuffer in
            let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
            guard let int16Ptr = int16Buffer.baseAddress else { return }
            for frame in 0..<frames {
                let sample = channelData[0][frame]
                let clamped = max(-1.0, min(1.0, sample))
                int16Ptr[frame] = Int16(clamped * Float(Int16.max))
            }
        }

        if channelCount > 1 {
            // If multiple channels exist, we currently just take the first channel.
        }

        webSocketTask?.send(.data(pcmData)) { [weak self] error in
            if let error {
                self?.onStatus("Stream error: \(error.localizedDescription)")
            }
        }
    }

    private func receiveLoop() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                self.handleMessage(text)
            case .success(.data(let data)):
                if let text = String(data: data, encoding: .utf8) {
                    self.handleMessage(text)
                }
            case .failure(let error):
                self.onStatus("Connection error: \(error.localizedDescription)")
            @unknown default:
                break
            }
            self.receiveLoop()
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if let response = try? JSONDecoder().decode(DeepgramResponse.self, from: data),
           let alt = response.channel?.alternatives.first {
            // Always forward word-level data for rate tracking.
            if let words = alt.words, !words.isEmpty {
                onWords(words)
            }
            // Forward full transcript for semantic matching on final results.
            if response.isFinal == true,
               let transcript = alt.transcript,
               !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                onUtterance(transcript)
            }
        }
    }

    private func startKeepAlive() {
        keepAliveTimer?.invalidate()
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.sendControlMessage(type: "KeepAlive")
        }
    }

    private func sendControlMessage(type: String) {
        let payload = ["type": type]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(json)) { _ in }
    }

    private func buildURL(sampleRate: Int) -> URL? {
        var components = URLComponents(string: "wss://api.deepgram.com/v1/listen")
        components?.queryItems = [
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: "\(sampleRate)"),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "endpointing", value: "200"),
            URLQueryItem(name: "utterance_end_ms", value: "1000")
        ]
        return components?.url
    }
}

struct DeepgramResponse: Decodable {
    struct Channel: Decodable {
        let alternatives: [Alternative]
    }
    struct Alternative: Decodable {
        let transcript: String?
        let words: [DeepgramWord]?
    }
    let channel: Channel?
    let isFinal: Bool?

    enum CodingKeys: String, CodingKey {
        case channel
        case isFinal = "is_final"
    }
}

struct DeepgramWord: Decodable {
    let word: String
    let start: Double
    let end: Double
}

// RecognizedWord not needed — AutoPrompter uses DeepgramWord directly.
