import Foundation
import FoundationModels
import LocalLMLabSDKCore

@Generable
private struct LocalTriage {
    @Guide(.anyOf(["answer", "defer"]))
    var decision: String

    @Guide(.anyOf(["high", "medium", "low"]))
    var confidence: String?

    @Guide(.anyOf([
        "arithmetic",
        "unit_conversion",
        "stable_school_science",
        "simple_definition",
        "simple_explanation",
        "user_text_transformation",
        "not_local_safe",
    ]))
    var category: String?

    @Guide(.anyOf(["yes", "no"]))
    var requiresExternalInfo: String?

    @Guide(.anyOf(["yes", "no"]))
    var requiresCurrentInfo: String?

    var reason: String?
}

/// Local AI: Apple's on-device model, reached through the LocalLM Lab SDK's `SystemModelProvider`.
///
/// Answering is deliberately conservative: a first "triage" call decides whether the question is
/// a stable, self-contained task (arithmetic, unit conversion, simple definitions, ...). Anything
/// else is deferred, and the caller falls back to the configured provider.
@MainActor
public final class AppleLocalAnswerer: LocalAnswering {
    private let lab: LocalLMLab
    private static let route: RouteName = "local"

    public init(lab: LocalLMLab) {
        self.lab = lab
    }

    public var availability: LocalAIAvailability {
        Self.availability(from: lab.models.availability(for: .system))
    }

    static func availability(from availability: ModelAvailability) -> LocalAIAvailability {
        switch availability {
        case .available:
            return LocalAIAvailability(supported: true, reason: "available", detail: "Apple's on-device model is available.")
        case .unavailable(let kind, let detail):
            switch kind {
            case .ineligibleHardware:
                return LocalAIAvailability(
                    supported: false, reason: "unsupported_hardware",
                    detail: "This Mac is not eligible for Apple Intelligence."
                )
            case .notEnabled:
                return LocalAIAvailability(
                    supported: false, reason: "capability_missing",
                    detail: "Apple Intelligence is not enabled for this user."
                )
            case .modelNotReady:
                return LocalAIAvailability(
                    supported: false, reason: "model_not_ready",
                    detail: "Apple's on-device model is present but not ready yet."
                )
            default:
                return LocalAIAvailability(supported: false, reason: "api_unavailable", detail: detail)
            }
        default:
            return LocalAIAvailability(
                supported: false, reason: "api_unavailable",
                detail: "Apple's on-device model is unavailable."
            )
        }
    }

    public func answer(_ request: AnswerRequest) async throws -> LocalOutcome {
        guard availability.supported else { return .deferred(reason: "local_model_unavailable") }
        lab.models.route(Self.route, to: .system)

        let prompts = LocalPrompts(request: request)

        let triageSession = try lab.makeSession(route: Self.route, includeMCPTools: false)
        let triage = try await triageSession.languageModelSession
            .respond(to: prompts.triage, generating: LocalTriage.self).content
        let decision = LocalPrompts.normalizedTriage(
            decision: triage.decision, confidence: triage.confidence, category: triage.category,
            requiresExternal: triage.requiresExternalInfo, requiresCurrent: triage.requiresCurrentInfo,
            reason: triage.reason
        )
        guard decision.allowsLocalAnswer else {
            return .deferred(reason: decision.reason)
        }

        let answerSession = try lab.makeSession(route: Self.route, includeMCPTools: false)
        let text = try await answerSession.respond(to: prompts.answer)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .deferred(reason: "empty_local_answer") : .answer(text)
    }
}
