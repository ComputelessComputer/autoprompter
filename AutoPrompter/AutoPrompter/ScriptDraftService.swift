//
//  ScriptDraftService.swift
//  AutoPrompter
//

import AVFoundation
import Foundation
import Speech

/// Manages "free run" draft sessions: transcribe speech, then optionally refine with AI.
@Observable
final class ScriptDraftService {
    var rawTranscript: String = ""
    var refinedText: String = ""
    var isRecording: Bool = false
    var isRefining: Bool = false
    var audioLevels: [CGFloat] = Array(repeating: 0, count: 30)
    var error: String?

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var deepgramStreamer: DeepgramStreamer?

    /// Accumulated transcript segments from Deepgram (each utterance appended).
    private var deepgramSegments: [String] = []

    // MARK: - Recording

    func startRecording() {
        rawTranscript = ""
        refinedText = ""
        error = nil
        deepgramSegments = []

        let settings = NotchSettings.shared
        if settings.speechBackend == .deepgram {
            let apiKey = settings.deepgramAPIKey
            guard !apiKey.isEmpty else {
                error = "Deepgram API key not set. Open Settings → Guidance to add your key."
                return
            }
            startDeepgramRecording(apiKey: apiKey)
        } else {
            startAppleRecording()
        }
    }

    func stopRecording() {
        isRecording = false

        // Clean up Deepgram
        deepgramStreamer?.stop()
        deepgramStreamer = nil

        // Clean up Apple speech
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Apple Speech Backend

    private func startAppleRecording() {
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .denied, .restricted:
            error = "Microphone access denied. Open System Settings → Privacy & Security → Microphone."
            return
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.requestSpeechAuthAndBegin()
                    } else {
                        self?.error = "Microphone access denied."
                    }
                }
            }
            return
        case .authorized:
            break
        @unknown default:
            break
        }

        requestSpeechAuthAndBegin()
    }

    private func requestSpeechAuthAndBegin() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.beginAppleRecognition()
                default:
                    self?.error = "Speech recognition not authorized."
                }
            }
        }
    }

    private func beginAppleRecognition() {
        audioEngine = AVAudioEngine()

        // Set selected microphone if configured
        let micUID = NotchSettings.shared.selectedMicUID
        if !micUID.isEmpty, let deviceID = AudioInputDevice.deviceID(forUID: micUID) {
            let inputUnit = audioEngine.inputNode.audioUnit
            if let audioUnit = inputUnit {
                var devID = deviceID
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &devID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                AudioUnitUninitialize(audioUnit)
                AudioUnitInitialize(audioUnit)
            }
        }

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: NotchSettings.shared.speechLocale))
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer not available"
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            error = "Audio input unavailable"
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let spoken = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    self.rawTranscript = spoken
                }
            }
            if error != nil, self.isRecording {
                // Apple speech has a ~60s limit; restart to keep going
                DispatchQueue.main.async {
                    self.restartAppleRecognition()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            self.error = "Audio engine failed: \(error.localizedDescription)"
        }
    }

    /// Apple speech recognition has a ~60-second session limit.
    /// When it ends, snapshot the current transcript and start a new session,
    /// prepending the snapshot so the user sees continuous text.
    private var accumulatedAppleTranscript: String = ""

    private func restartAppleRecognition() {
        guard isRecording else { return }

        // Snapshot what we have so far
        if !rawTranscript.isEmpty {
            accumulatedAppleTranscript = rawTranscript
        }

        // Clean up current session
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)

        // Start fresh
        audioEngine = AVAudioEngine()

        let micUID = NotchSettings.shared.selectedMicUID
        if !micUID.isEmpty, let deviceID = AudioInputDevice.deviceID(forUID: micUID) {
            let inputUnit = audioEngine.inputNode.audioUnit
            if let audioUnit = inputUnit {
                var devID = deviceID
                AudioUnitSetProperty(
                    audioUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &devID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                AudioUnitUninitialize(audioUnit)
                AudioUnitInitialize(audioUnit)
            }
        }

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: NotchSettings.shared.speechLocale))
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            recognitionRequest.append(buffer)
            self?.updateAudioLevel(buffer: buffer)
        }

        let prefix = accumulatedAppleTranscript
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let newPart = result.bestTranscription.formattedString
                DispatchQueue.main.async {
                    if prefix.isEmpty {
                        self.rawTranscript = newPart
                    } else {
                        self.rawTranscript = prefix + " " + newPart
                    }
                }
            }
            if error != nil, self.isRecording {
                DispatchQueue.main.async {
                    self.restartAppleRecognition()
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            // Silently fail the restart; user still has accumulated text
        }
    }

    // MARK: - Deepgram Backend

    private func startDeepgramRecording(apiKey: String) {
        let streamer = DeepgramStreamer(
            apiKey: apiKey,
            onStatus: { [weak self] status in
                DispatchQueue.main.async {
                    if status.contains("error") || status.contains("Error") {
                        self?.error = status
                    }
                }
            },
            onWords: { _ in },
            onUtterance: { [weak self] utterance in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    self.deepgramSegments.append(trimmed)
                    self.rawTranscript = self.deepgramSegments.joined(separator: " ")
                }
            },
            onLevel: { [weak self] level in
                DispatchQueue.main.async {
                    guard let self else { return }
                    let scaled = CGFloat(min(level * 5, 1.0))
                    self.audioLevels.append(scaled)
                    if self.audioLevels.count > 30 {
                        self.audioLevels.removeFirst()
                    }
                }
            }
        )
        deepgramStreamer = streamer
        streamer.start()
        isRecording = true
    }

    // MARK: - Audio Levels

    private func updateAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(max(frameLength, 1)))
        let level = CGFloat(min(rms * 5, 1.0))

        DispatchQueue.main.async { [weak self] in
            self?.audioLevels.append(level)
            if (self?.audioLevels.count ?? 0) > 30 {
                self?.audioLevels.removeFirst()
            }
        }
    }

    // MARK: - AI Refinement

    func refine() {
        let transcript = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            error = "Nothing to refine — transcript is empty."
            return
        }

        let settings = NotchSettings.shared
        let apiKey = settings.openaiAPIKey
        guard !apiKey.isEmpty else {
            error = "OpenAI API key not set. Open Settings → Guidance to add your key."
            return
        }

        isRefining = true
        refinedText = ""
        error = nil

        let model = settings.refinementModel
        let prompt = """
        You are a professional script editor for a teleprompter app. The user spoke freely and the following is a raw speech-to-text transcript. Please refine it into a polished, teleprompter-ready script.

        Rules:
        - Remove filler words (um, uh, like, you know, so, basically, actually, right)
        - Fix grammar and add proper punctuation
        - Break into natural paragraphs (one idea per paragraph)
        - Improve clarity and flow while preserving the speaker's original meaning, tone, and style
        - Keep it conversational and natural — this will be read aloud from a teleprompter
        - Do NOT add content the speaker didn't say; only clean up what's there
        - Output ONLY the refined script, nothing else

        Raw transcript:
        \"\"\"\(transcript)\"\"\"
        """

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.3
        ]

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            isRefining = false
            error = "Failed to build API request."
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 60

        URLSession.shared.dataTask(with: request) { [weak self] data, _, reqError in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isRefining = false

                if let reqError {
                    self.error = "API error: \(reqError.localizedDescription)"
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let message = choices.first?["message"] as? [String: Any],
                      let content = message["content"] as? String else {
                    // Check for API error message
                    if let data,
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let apiError = json["error"] as? [String: Any],
                       let errorMessage = apiError["message"] as? String {
                        self.error = "API error: \(errorMessage)"
                    } else {
                        self.error = "Failed to parse API response."
                    }
                    return
                }

                self.refinedText = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.resume()
    }
}
