# 2. Local AI

Source: `Sources/AnswerSearchKit/AppleLocalAnswerer.swift`.
SDK guide: [§6a](https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md#6a-the-model-layer-local-models-routing-sessions),
[Running a turn](https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md#running-a-turn-and-when-to-use-languagemodelsession).

Local AI answers a question on the Mac with Apple's on-device model (`SystemModelProvider`),
but only when it is clearly safe. Everything else is deferred to the online provider (page 3).

## Availability

```swift
lab.models.availability(for: .system)   // .available / .unavailable(kind:detail:) / ...
```

The SDK reports why the model is unavailable (`.ineligibleHardware`, `.notEnabled`,
`.modelNotReady`, ...). `AppleLocalAnswerer.availability(from:)` maps these to the status shown in
Settings. This works on macOS 26 and 27.

## Step 1: triage with guided generation

```swift
lab.models.route("local", to: .system)
let triageSession = try lab.makeSession(route: "local", includeMCPTools: false)
let triage = try await triageSession.languageModelSession
    .respond(to: prompts.triage, generating: LocalTriage.self).content
```

### The instructions the model is given

Source: `Sources/AnswerSearchKit/LocalPrompts.swift`. The triage call is told it is **not**
answering, only deciding whether a local answer is allowed. The instructions and the question are
combined into one prompt, which reads more reliably with the on-device model than separate session
instructions. The key instructions:

- **Default to defer.** Answer locally only if all four hold: the question is self-contained (or
  made so by the previous Q&A); it can be answered from the prompt, previous context,
  deterministic calculation, user-supplied text, or stable general knowledge in an allowed
  category; it needs no freshness, verification, sources, personal data, professional judgment,
  tools or web access; and the model is highly confident. If any condition is false or unclear,
  defer.
- **Pick exactly one category.** The local-safe categories are exhaustive: `arithmetic`,
  `unit_conversion`, `stable_school_science`, `simple_definition`, `simple_explanation`,
  `user_text_transformation`. Anything that does not clearly fit is `not_local_safe`. Product facts,
  specs, news, weather, prices, schedules and source-dependent claims are `not_local_safe` unless
  the prompt supplies the information.
- **Flag external info.** `requires_external_info` is "yes" if a good answer depends on facts
  outside the prompt and the allowed stable knowledge.
- **Flag current info.** `requires_current_info` is "yes" if the wording asks for or may need
  recency: latest, today, price, schedule, version, status, and so on. Misspellings and paraphrases
  ("lateset") count.
- **Extra caution for science and explanations.** Defer if the answer depends on recent
  discoveries, exact source wording, measurement conditions, location, date, disputed facts,
  health, legal or professional judgment.
- **Follow-ups.** If the previous answer came from the online provider or used web search, defer
  unless the follow-up stands alone as a local-safe task.
- **Output discipline.** Say "answer" only with "high" confidence; keep `reason` a short code
  with no computed values or answer text.

The prompt also carries request context: locale, local and UTC time, location, and the previous
Q&A with its provenance for related questions. The instructions note these help interpret wording
and decide whether to defer; they do **not** make current facts answerable locally.

`LocalTriage` is a `@Generable` struct (decision, confidence, category, whether it needs external
or current information), so the result is typed, not free text to parse.

Guided generation is the one case where the code uses `session.languageModelSession`: **the SDK has
no turn method for it.** Normal turns use `session.respond`.
(See "When the escape hatch is the right call" in the guide.)

## The defer rule

```swift
guard decision.allowsLocalAnswer else { return .deferred(reason: decision.reason) }
```

`allowsLocalAnswer` is true only if the decision is "answer", confidence is "high", it needs no
external or current information, and the category is local-safe (arithmetic, unit conversion,
stable school science, simple definitions or explanations, transforming user-supplied text).
Missing or unrecognized values resolve to "defer". Defaulting to the cautious answer is deliberate.

## Step 2: answer

```swift
let answerSession = try lab.makeSession(route: "local", includeMCPTools: false)
let text = try await answerSession.respond(to: prompts.answer)
```

A fresh session answers the triaged question with plain `respond`. Its instructions say the
question was already triaged as safe, to answer directly from the prompt and previous context only,
in the user's language, with no citations, links, current claims or external facts. An empty answer also defers
instead of showing nothing.
