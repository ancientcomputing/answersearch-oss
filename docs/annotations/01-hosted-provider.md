# 1. Hosted provider answers

Source: `Sources/AnswerSearchKit/SDKProviderAnswerer.swift`.
SDK guide: [§6b Online providers](https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md#6b-online-providers--gpt-claude-online-openrouter-locallmlabsdkremote),
[§6a Sessions](https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md#6a-the-model-layer-local-models-routing-sessions).

One search with Claude or OpenAI is: **config -> register -> route -> session -> respond -> read results.**

## One shared `LocalLMLab`

`AppState` creates a single `LocalLMLab` with Apple's on-device provider. The hosted provider is
added per turn (below).

```swift
let lab = LocalLMLab(configuration: .init(providers: [SystemModelProvider()]))
```

## 1. Build a `RemoteProviderConfig`

```swift
switch provider {
case .anthropic: config = .anthropic(apiKey: apiKey, models: models)
case .openai:    config = .openAIResponses(apiKey: apiKey, models: models)
}
config.capabilities.insert(.webSearch)
```

- Presets fill in the dialect, base URL and auth shape. **The SDK ships no model ids**, so the
  id comes from Settings.
- Anthropic uses the Messages API; OpenAI uses the Responses API.
- `capabilities.insert(.webSearch)` says the provider *can* search. Whether a given turn does is
  decided per turn by `SessionOptions.webSearch` (step 4).

## 2. Validate and register

```swift
let remote = try RemoteModelProvider(config)   // validates: HTTPS base URL, credential syntax
lab.models.replace(remote)
```

`RemoteModelProvider.init` always validates the config. `replace` swaps the provider in place and
is called **before every turn**, so a changed API key or model applies immediately without
rebuilding `LocalLMLab`.

## 3. Route

```swift
lab.models.route("answer", to: modelID)
```

A route is a name the app owns. Sessions ask for the route, never a hard-coded model.

## 4. Make a session

```swift
var options = SessionOptions(
    webSearch: request.useWebSearch,
    webSearchMaxUses: request.useWebSearch ? request.webSearchMaxUses : nil,
    maxOutputTokens: request.maxOutputTokens
)
if request.useWebSearch { options.userLocation = ... }   // localizes search results

let session = try lab.makeSession(
    route: "answer",
    instructions: Prompts.system(for: request),
    includeMCPTools: false,
    options: options
)
```

- The **provider runs the web search itself**; no MCP server is needed.
- `instructions` become the system prompt. The user's question goes in the turn (step 5).
- `includeMCPTools: false`: AnswerSearch configures no MCP servers and wants a plain answer turn.

## 5. Respond, and watch for searches

```swift
let events = Task { @MainActor in
    for await event in session.events {
        if case .serverToolCall(let activity) = event,
           case .webSearch(let queries, let hits) = activity.kind { ... }
    }
}
let text = try await session.respond(to: Prompts.user(for: request))
```

`session.events` reports provider-run web searches as they happen, which is how the UI shows
"Searching the web..." before the answer arrives. Errors arrive as `LocalLMLabError`.

## 6. Read the sources

```swift
var sources = session.citations.map { Source(title: $0.title, url: $0.url, citedText: $0.citedText) }
```

`session.citations` is filled in by `respond`. Show them: a web-search answer without visible
sources reads as unverifiable. If the provider cited nothing, the app falls back to the pages
the search returned.

## The macOS 27 gate

`RemoteModelProvider` is `@available(macOS 27, *)`, while the package's floor is macOS 26. The
hosted path therefore sits behind `#available(macOS 27, *)`, and on macOS 26 only Local AI works.
See [§1a](https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md#1a-targeting-macos-26-and-macos-27-from-one-build).
