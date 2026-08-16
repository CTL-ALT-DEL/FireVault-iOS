//
//  FireVaultTripSummaryAIService.swift
//  FireVault
//
//  Private, on-device refinement of an already factual Trip Log summary.
//

import Foundation
import FoundationModels

enum FireVaultTripSummaryAIUnavailableReason: Sendable {
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unknown
}

enum FireVaultTripSummaryAIAvailability: Sendable {
    case available
    case unavailable(FireVaultTripSummaryAIUnavailableReason)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

enum FireVaultTripSummaryAIError: LocalizedError, Sendable {
    case unavailable(FireVaultTripSummaryAIUnavailableReason)
    case invalidSource
    case invalidResponse
    case generationFailed

    var errorDescription: String? {
        switch self {
        case .unavailable(.deviceNotEligible):
            "This device does not support the on-device Trip Log summary model."
        case .unavailable(.appleIntelligenceNotEnabled):
            "Apple Intelligence must be enabled to refine the Trip Log summary."
        case .unavailable(.modelNotReady):
            "The on-device Trip Log summary model is not ready yet."
        case .unavailable(.unknown):
            "The on-device Trip Log summary model is unavailable."
        case .invalidSource:
            "The factual Trip Log summary was empty or too large to refine."
        case .invalidResponse:
            "The refined Trip Log summary did not pass FireVault's factual validation."
        case .generationFailed:
            "FireVault could not refine the Trip Log summary on this device."
        }
    }
}

/// A narrow protocol so report generation can inject the production service or
/// a deterministic test double. The caller remains responsible for persisting
/// the successful result and for invoking this service only when no saved AI
/// paragraph exists for the completed trip.
protocol FireVaultTripSummaryAIProviding: Sendable {
    var availability: FireVaultTripSummaryAIAvailability { get }

    func refine(factualParagraph: String) async throws -> String
}

/// Uses Apple's on-device Foundation Models framework for one constrained
/// rewrite. It never receives raw route points and it never asks the model to
/// infer new trip facts; the deterministic summary remains the source of truth.
@available(iOS 26.0, *)
struct FireVaultTripSummaryAIService: FireVaultTripSummaryAIProviding, Sendable {
    static let shared = FireVaultTripSummaryAIService()

    private static let maximumSourceCharacters = 6_000
    private static let maximumResponseCharacters = 2_400

    var availability: FireVaultTripSummaryAIAvailability {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(Self.mapUnavailableReason(reason))
        }
    }

    func refine(factualParagraph: String) async throws -> String {
        let source = Self.sanitizedParagraph(factualParagraph)
        guard source.count >= 40, source.count <= Self.maximumSourceCharacters else {
            throw FireVaultTripSummaryAIError.invalidSource
        }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw FireVaultTripSummaryAIError.unavailable(Self.mapUnavailableReason(reason))
        }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You are FireVault's Trip Log copy editor. Rewrite only the factual paragraph supplied by the app into one polished, concise paragraph for a professional field-service report.

            The supplied paragraph is the complete and authoritative record. Keep it short, natural, and easy to read. Preserve every start and end location, time, stop count, distance, duration, speed, and elevation exactly. Do not name, describe, or categorize individual stops. Do not infer, estimate, calculate, add, remove, merge, or correct facts. Do not add commentary, recommendations, headings, bullets, Markdown, or an introduction. Return only the rewritten paragraph. If wording cannot be improved without changing a fact, return the source paragraph unchanged.

            Keep each value attached to its original subject. Preserve the factual phrases "started at ... at ...", "ended at ... at ...", "covered ... in ...", "averaging ... mph", "trip included ... recorded stops", and the ordered elevation range. Never exchange values between these phrases.
            """
        )
        let prompt = """
        Rewrite the authoritative Trip Log paragraph below. Keep all numerals and named places exactly as supplied, and return exactly one paragraph.

        <authoritative_trip_log>
        \(source)
        </authoritative_trip_log>
        """

        do {
            // Greedy sampling with zero temperature makes repeat invocations as
            // stable as the framework permits. The report layer persists the
            // first accepted result and does not invoke the model on export.
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(
                    sampling: .greedy,
                    temperature: 0,
                    maximumResponseTokens: 384
                )
            )
            let candidate = Self.sanitizedParagraph(response.content)
            guard Self.validatesFactualRewrite(candidate, source: source) else {
                throw FireVaultTripSummaryAIError.invalidResponse
            }
            return candidate
        } catch let error as FireVaultTripSummaryAIError {
            throw error
        } catch {
            throw FireVaultTripSummaryAIError.generationFailed
        }
    }

    private static func mapUnavailableReason(
        _ reason: SystemLanguageModel.Availability.UnavailableReason
    ) -> FireVaultTripSummaryAIUnavailableReason {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        @unknown default:
            return .unknown
        }
    }

    private static func sanitizedParagraph(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if result.count >= 2,
           let first = result.first,
           let last = result.last,
           (first == "\"" && last == "\"") || (first == "“" && last == "”") {
            result.removeFirst()
            result.removeLast()
        }

        return result
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Internal by design: unit tests can exercise the same acceptance gate as
    /// the production model path without exposing validation as app API.
    static func validatesFactualRewrite(_ candidate: String, source: String) -> Bool {
        isValidRewrite(
            sanitizedParagraph(candidate),
            of: sanitizedParagraph(source)
        )
    }

    private static func isValidRewrite(_ candidate: String, of source: String) -> Bool {
        guard candidate.count >= 40,
              candidate.count <= maximumResponseCharacters,
              candidate.count <= source.count + max(240, source.count / 3),
              !containsPresentationMarkup(candidate),
              numericFacts(in: candidate) == numericFacts(in: source),
              namedTerms(in: source).isSubset(of: namedTerms(in: candidate)),
              namedTerms(in: candidate).subtracting(namedTerms(in: source))
                .subtracting(permittedNamedTerms).isEmpty,
              preservesRequiredConcepts(candidate: candidate, source: source),
              preservesBoundFacts(candidate: candidate, source: source) else {
            return false
        }
        return true
    }

    /// Compares label-bound values rather than only comparing the paragraph's
    /// aggregate number bag. This prevents a fluent rewrite from moving an
    /// otherwise valid number from start to end, speed to elevation, or the
    /// stop count.
    private static func preservesBoundFacts(candidate: String, source: String) -> Bool {
        guard let sourceFacts = boundFacts(in: source),
              let candidateFacts = boundFacts(in: candidate) else {
            return false
        }
        return sourceFacts == candidateFacts
    }

    private static func boundFacts(in text: String) -> [String: String]? {
        guard let start = endpointBinding(label: "started", in: text),
              let end = endpointBinding(label: "ended", in: text),
              let travel = travelBinding(in: text),
              let elevation = elevationBinding(in: text) else {
            return nil
        }

        var facts: [String: String] = [
            "start.location": start.location,
            "start.time": start.time,
            "end.location": end.location,
            "end.time": end.time,
            "travel.distance": travel.distance,
            "travel.duration": travel.duration,
            "travel.speed": travel.speed,
            "elevation": elevation
        ]

        if let totalStops = capture(
            #"\btrip\s+included\s+(\d+)\s+recorded\s+stops?\b"#,
            in: text
        )?.first {
            facts["stops.total"] = normalizedNumber(totalStops)
        } else if text.localizedCaseInsensitiveContains("No stops were recorded") {
            facts["stops.total"] = "0:none"
        } else {
            return nil
        }
        return facts
    }

    private static func endpointBinding(
        label: String,
        in text: String
    ) -> (location: String, time: String)? {
        let boundary = label == "started"
            ? #"(?=\s*,?\s*and\s+ended\b)"#
            : #"(?=\s*[.!?]|$)"#
        let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: label)
            + #"\s+at\s+(.+?)\s+at\s+(\d{1,2}:\d{2}(?:\s*(?:AM|PM))?)"#
            + boundary
        guard let values = capture(pattern, in: text), values.count == 2 else { return nil }
        return (
            normalizedFactText(values[0]),
            normalizedFactText(values[1])
        )
    }

    private static func travelBinding(
        in text: String
    ) -> (distance: String, duration: String, speed: String)? {
        let pattern = #"\bcovered\s+(.+?)\s+in\s+(.+?)(?=,\s+averaging|\.\s+Average\s+speed)"#
        guard let values = capture(pattern, in: text), values.count == 2 else { return nil }

        let speed: String
        if let speedValue = capture(
            #"\baveraging\s+([+-]?\d+(?:[.,]\d+)?)\s+mph\b"#,
            in: text
        )?.first {
            speed = normalizedNumber(speedValue) + " mph"
        } else if text.localizedCaseInsensitiveContains(
            "average speed was unavailable"
        ) {
            speed = "unavailable"
        } else {
            return nil
        }

        return (
            normalizedFactText(values[0]),
            normalizedFactText(values[1]),
            speed
        )
    }

    private static func elevationBinding(in text: String) -> String? {
        if let range = capture(
            #"\belevation\s+ranged\s+from\s+about\s+([+-]?[\d,]+(?:\.\d+)?)\s+to\s+([+-]?[\d,]+(?:\.\d+)?)\s+feet\b"#,
            in: text
        ), range.count == 2 {
            return "range:\(normalizedNumber(range[0])):\(normalizedNumber(range[1]))"
        }
        if let value = capture(
            #"\belevation\s+stayed\s+near\s+([+-]?[\d,]+(?:\.\d+)?)\s+feet\b"#,
            in: text
        )?.first {
            return "near:\(normalizedNumber(value))"
        }
        if text.localizedCaseInsensitiveContains(
            "Elevation data was unavailable"
        ) {
            return "unavailable"
        }
        return nil
    }

    private static func capture(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range),
              match.numberOfRanges > 1 else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let valueRange = Range(match.range(at: index), in: text) else { return nil }
            return String(text[valueRange])
        }
    }

    private static func normalizedFactText(_ value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            .lowercased()
    }

    private static func normalizedNumber(_ value: String) -> String {
        value
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }

    private static func numericFacts(in text: String) -> [String: Int] {
        let pattern = #"[+-]?\d+(?:[,:.]\d+)*(?:°)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [:] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var counts: [String: Int] = [:]
        for match in expression.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let token = text[matchRange]
                .replacingOccurrences(of: ",", with: "")
                .lowercased()
            counts[token, default: 0] += 1
        }
        return counts
    }

    private static func namedTerms(in text: String) -> Set<String> {
        let pattern = #"\b[A-Z][A-Za-z0-9&'-]{2,}\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(expression.matches(in: text, range: fullRange).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else { return nil }
            let prefix = text[..<matchRange.lowerBound]
            let previous = prefix.last(where: { !$0.isWhitespace })
            if previous == nil || previous == "." || previous == "!" || previous == "?" {
                // Sentence-opening capitalization is grammar, not evidence of
                // a named place or category.
                return nil
            }
            return text[matchRange].lowercased()
        })
    }

    private static func containsPresentationMarkup(_ text: String) -> Bool {
        text.contains("# ")
            || text.contains("##")
            || text.contains("**")
            || text.contains("```")
            || text.contains("\n-")
            || text.contains("\n•")
    }

    private static func preservesRequiredConcepts(candidate: String, source: String) -> Bool {
        let sourceText = source.lowercased()
        let candidateText = candidate.lowercased()
        let concepts: [(source: [String], accepted: [String])] = [
            (["started", "start"], ["started", "starts", "start", "began", "beginning"]),
            (["ended", "end"], ["ended", "ends", "end", "finished", "concluded"]),
            (["stop"], ["stop"]),
            (["average travel speed", "average speed"], ["average travel speed", "average speed"]),
            (["elevation"], ["elevation"])
        ]
        return concepts.allSatisfy { concept in
            let isRequired = concept.source.contains { sourceText.contains($0) }
            return !isRequired || concept.accepted.contains { candidateText.contains($0) }
        }
    }

    private static let permittedNamedTerms: Set<String> = [
        "firevault", "log", "route", "trip"
    ]
}
