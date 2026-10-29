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

A fresh session answers the triaged question with plain `respond`. An empty answer also defers
instead of showing nothing.
