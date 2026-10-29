# SDK annotations

Walkthroughs of the places where AnswerSearch calls the
[LocalLM Lab SDK](https://thisbrain.ai/locallm) (2.3.0-GA). Each page excerpts the real code,
explains each SDK call and why it is there, and links to the matching section of the
[SDK guide](https://github.com/ancientcomputing/locallm/blob/2.3.0-GA/docs/sdk-guide.md). The same notes are inline in the source files.

| Page | Covers | Source |
|---|---|---|
| [1. Hosted provider answers](01-hosted-provider.md) | `RemoteModelProvider`, routes, sessions, web search, events, citations | `SDKProviderAnswerer.swift` |
| [2. Local AI](02-local-ai.md) | on-device availability, triage by guided generation, answering | `AppleLocalAnswerer.swift` |
| [3. Local to online hand-off](03-local-to-online.md) | when and how Local AI defers to the online provider | `AnswerEngine.swift` |

Start with page 1 if you want to add a hosted model to your own app, or page 2 for on-device use.
