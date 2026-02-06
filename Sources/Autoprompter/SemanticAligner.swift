import Foundation
import NaturalLanguage

/// Segments a script into sentences, computes on-device sentence embeddings
/// via NLEmbedding, and matches spoken utterances to the closest script segment.
final class SemanticAligner {

    struct Segment {
        let index: Int
        let text: String
        let range: NSRange          // range in the original script string
        let lineIndex: Int          // which visual line this segment starts on
        let embedding: [Double]?
    }

    private(set) var segments: [Segment] = []
    private var currentSegmentIndex: Int = 0
    private let embedding: NLEmbedding?

    /// Similarity threshold below which we don't advance (0–1 scale, higher = more similar).
    private let advanceThreshold: Double = 0.45

    /// How many segments ahead we look for a match.
    private let lookahead: Int = 6

    init() {
        self.embedding = NLEmbedding.sentenceEmbedding(for: .english)
    }

    // MARK: - Setup

    func prepare(script: String, lineRanges: [NSRange]) {
        segments.removeAll()
        currentSegmentIndex = 0

        let nsScript = script as NSString
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = script

        var segmentList: [(text: String, range: NSRange)] = []
        tagger.enumerateTags(
            in: script.startIndex..<script.endIndex,
            unit: .sentence,
            scheme: .tokenType
        ) { _, tokenRange in
            let nsRange = NSRange(tokenRange, in: script)
            let text = nsScript.substring(with: nsRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                segmentList.append((text: text, range: nsRange))
            }
            return true
        }

        // If the tagger produced nothing (short script), treat the whole thing as one segment.
        if segmentList.isEmpty && !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segmentList.append((
                text: script.trimmingCharacters(in: .whitespacesAndNewlines),
                range: NSRange(location: 0, length: nsScript.length)
            ))
        }

        segments = segmentList.enumerated().map { index, seg in
            let lineIndex = lineIndexFor(location: seg.range.location, in: lineRanges)
            let emb = computeEmbedding(for: seg.text)
            return Segment(
                index: index,
                text: seg.text,
                range: seg.range,
                lineIndex: lineIndex,
                embedding: emb
            )
        }
    }

    // MARK: - Matching

    struct MatchResult {
        let segmentIndex: Int
        let lineIndex: Int
        let range: NSRange
        let similarity: Double
    }

    /// Try to match the given utterance to a script segment.
    /// Returns the best match if above threshold, nil otherwise.
    func match(utterance: String) -> MatchResult? {
        guard !segments.isEmpty else { return nil }
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let uttEmb = computeEmbedding(for: trimmed) else { return nil }

        let start = max(0, currentSegmentIndex - 1) // allow slight backward correction
        let end = min(segments.count - 1, currentSegmentIndex + lookahead)
        guard start <= end else { return nil }

        var bestIndex = -1
        var bestSimilarity = -Double.infinity

        for i in start...end {
            guard let segEmb = segments[i].embedding else { continue }
            let sim = cosineSimilarity(uttEmb, segEmb)
            // Apply a small forward bias: prefer segments at or ahead of current position.
            let biased = (i >= currentSegmentIndex) ? sim + 0.02 : sim
            if biased > bestSimilarity {
                bestSimilarity = biased
                bestIndex = i
            }
        }

        guard bestIndex >= 0, bestSimilarity >= advanceThreshold else { return nil }

        // Only advance forward (or stay); never jump back more than 1.
        if bestIndex >= currentSegmentIndex - 1 {
            currentSegmentIndex = bestIndex
        }

        let seg = segments[bestIndex]
        return MatchResult(
            segmentIndex: bestIndex,
            lineIndex: seg.lineIndex,
            range: seg.range,
            similarity: bestSimilarity
        )
    }

    /// Advance by one segment (used as gentle rate-based fallback).
    func advanceOneSegment() -> MatchResult? {
        let next = currentSegmentIndex + 1
        guard next < segments.count else { return nil }
        currentSegmentIndex = next
        let seg = segments[next]
        return MatchResult(
            segmentIndex: next,
            lineIndex: seg.lineIndex,
            range: seg.range,
            similarity: 1.0
        )
    }

    func reset() {
        currentSegmentIndex = 0
    }

    var progress: Double {
        guard segments.count > 1 else { return 0 }
        return Double(currentSegmentIndex) / Double(segments.count - 1)
    }

    // MARK: - Embedding helpers

    private func computeEmbedding(for text: String) -> [Double]? {
        embedding?.vector(for: text)
    }

    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private func lineIndexFor(location: Int, in lineRanges: [NSRange]) -> Int {
        for (i, range) in lineRanges.enumerated() {
            if location < range.location + range.length {
                return i
            }
        }
        return max(0, lineRanges.count - 1)
    }
}
