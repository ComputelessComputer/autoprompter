//
//  LLMResyncService.swift
//  AutoPrompter
//

import Foundation

final class LLMResyncService {
    static let shared = LLMResyncService()

    private var inFlight = false

    struct ResyncResult {
        let charOffset: Int
    }

    /// Ask GPT-4o-mini where in the script the speaker currently is.
    /// - Parameters:
    ///   - sourceText: The full source script (joined words).
    ///   - currentOffset: Current char offset the highlight is at.
    ///   - spokenText: Recent accumulated speech from the user.
    ///   - apiKey: OpenAI API key.
    ///   - completion: Called on main thread with the new char offset, or nil on failure.
    func resync(
        sourceText: String,
        currentOffset: Int,
        spokenText: String,
        apiKey: String,
        completion: @escaping (ResyncResult?) -> Void
    ) {
        guard !inFlight else {
            completion(nil)
            return
        }
        inFlight = true

        // Build a window of the script around the current position
        let lookBehind = 200
        let lookAhead = 800
        let windowStart = max(0, currentOffset - lookBehind)
        let windowEnd = min(sourceText.count, currentOffset + lookAhead)
        let startIdx = sourceText.index(sourceText.startIndex, offsetBy: windowStart)
        let endIdx = sourceText.index(sourceText.startIndex, offsetBy: windowEnd)
        let scriptWindow = String(sourceText[startIdx..<endIdx])

        // Trim spoken text to last ~500 chars
        let recentSpoken: String
        if spokenText.count > 500 {
            recentSpoken = String(spokenText.suffix(500))
        } else {
            recentSpoken = spokenText
        }

        let prompt = """
        You are a teleprompter sync assistant. A speaker is reading from a script but may paraphrase, skip words, or add extra details. Given the script excerpt and what they actually said, identify where in the script they currently are.

        Script excerpt:
        \"\"\"\(scriptWindow)\"\"\"

        What the speaker said recently (may be paraphrased):
        \"\"\"\(recentSpoken)\"\"\"

        Respond with ONLY a verbatim quote of 3-5 consecutive words from the script excerpt that represents the furthest point the speaker has reached. The words must appear exactly as written in the script. Output nothing else.
        """

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 50,
            "temperature": 0
        ]

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            inFlight = false
            DispatchQueue.main.async { completion(nil) }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            defer { self?.inFlight = false }

            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let phrase = content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !phrase.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Search for the phrase in the source text, starting slightly before the current offset
            let searchStart = max(0, currentOffset - lookBehind)
            let searchStartIdx = sourceText.index(sourceText.startIndex, offsetBy: searchStart)

            if let range = sourceText.range(of: phrase, options: [.caseInsensitive],
                                            range: searchStartIdx..<sourceText.endIndex) {
                let offset = sourceText.distance(from: sourceText.startIndex, to: range.upperBound)
                DispatchQueue.main.async { completion(ResyncResult(charOffset: offset)) }
                return
            }

            // Fallback: try matching just the last 3 words of the phrase
            let words = phrase.split(separator: " ")
            if words.count >= 3 {
                let shorter = words.suffix(3).joined(separator: " ")
                if let range = sourceText.range(of: shorter, options: [.caseInsensitive],
                                                range: searchStartIdx..<sourceText.endIndex) {
                    let offset = sourceText.distance(from: sourceText.startIndex, to: range.upperBound)
                    DispatchQueue.main.async { completion(ResyncResult(charOffset: offset)) }
                    return
                }
            }

            DispatchQueue.main.async { completion(nil) }
        }.resume()
    }
}
