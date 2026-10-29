# Privacy

AnswerSearch has no server of its own and collects no analytics or telemetry.

- **Your questions** are sent directly from your Mac to the AI provider you choose (Anthropic or
  OpenAI), using your own API key. That provider's terms and privacy policy apply to them. With
  web search on, the provider may also receive the optional city/region/country/timezone from
  Settings. In **Local AI** mode, eligible questions are answered on-device by Apple's model and
  are not sent anywhere.
- **API keys** are stored in your macOS Keychain and sent only to the matching provider.
- **Settings** are stored in `~/Library/Application Support/AnswerSearch/config.json`.
  Answers and history are never written to disk; only the single previous question and answer
  are kept in memory to support one follow-up. "Delete local data" in Settings removes the
  settings file and keys.
- **Save as…** writes a text file only where you tell it to.
