# AnswerSearch

An answer engine for your Mac menu bar. Ask a question, get one concise, sourced answer (not a
chat thread), with a single related follow-up. Open source under Apache 2.0.

- **Your keys, your providers.** Bring an Anthropic (Claude) or OpenAI API key. Web search runs on
  the provider's side, with source links shown under the answer.
- **Answer Modes.** *Local AI* (Apple's on-device model, for simple self-contained questions, with
  automatic fallback), *Fast AI*, *Web Quick*, *Web Deep*.
- **Private by design.** No server, no telemetry, no history on disk. Keys live in the macOS
  Keychain. See [PRIVACY.md](PRIVACY.md).
- **Global shortcut** (default Control + Option + Space) and launch at login.

It is built on the [LocalLM Lab SDK](https://github.com/ancientcomputing/locallm) (2.3.0-GA): the SDK
provides the model layer: hosted providers with web search and citations, and Apple's on-device
model.
The SDK binaries come from the
[v2.3.0-GA release](https://github.com/ancientcomputing/locallm/releases/tag/v2.3.0-GA); for
everything about LocalLM Lab, see [thisbrain.ai/locallm](https://thisbrain.ai/locallm).

## Mac App Store

A Mac App Store version of AnswerSearch is available here: https://apps.apple.com/app/answersearch/id6797641255

The App Store version is a separate, closed-source codebase and is not built from this repository.
This repository is an open-source rewrite on the LocalLM Lab SDK, so features and behavior may
differ between the two.

## Requirements

- Apple Silicon Mac, macOS 26+ and Xcode 26+ (Swift 6) to build.
- Claude/OpenAI answers need **macOS 27** (an SDK requirement). On macOS 26 only Local AI works
  (needs Apple Intelligence enabled).

## Build and run

```sh
git clone https://github.com/ancientcomputing/answersearch-oss.git
cd answersearch-oss
scripts/build_app.sh
open dist/AnswerSearch.app
```

### Xcode

Open `AnswerSearch.xcodeproj` and press Run (scheme **AnswerSearch**). It uses ad-hoc signing,
no sandbox, and resolves the SDK through the root `Package.swift`. To distribute, set your team and
signing identity on the target. (Opening `Package.swift` directly also works for building and
testing.)

On first launch, pick a provider and paste your API key. The first build downloads and
checksum-verifies the SDK binaries from GitHub Releases. `swift test` runs the unit tests.
`LOCALLM_SDK_VERSION` selects another SDK release listed in `Package.swift`.

The script ad-hoc signs the app. To sign with your own identity:
`APP_IDENTITY="Developer ID Application: Name (TEAMID)" scripts/build_app.sh`. Change the bundle
identifier in `Resources/Info.plist` if you distribute your own build.

## How it works

`AnswerEngine` builds a provider-neutral request from the selected mode, decides local vs. hosted,
and labels the result. Hosted answers go through the SDK's `RemoteModelProvider`
(`.anthropic` / `.openAIResponses` presets, `SessionOptions(webSearch:)`, `session.citations`).
Local AI is a two-step flow over `SystemModelProvider`: a guided-generation triage call that
defers anything not clearly safe (current events, facts needing sources), then a short answer.
Follow-ups carry only the one previous question and answer.


## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE). The name and icon are trademarks
of ThisBrainAI LLC; please use your own for redistributed forks.
