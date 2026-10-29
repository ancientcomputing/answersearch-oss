# Contributing

Issues and pull requests are welcome.

```sh
swift build          # first build downloads the LocalLM Lab SDK binaries
swift test           # engine logic runs against stub backends; no API key needed
scripts/build_app.sh # produces dist/AnswerSearch.app
```

Layout: `Sources/AnswerSearchKit` is the engine (settings, prompts, routing, SDK-backed
providers, text clean-up) and has no UI; `Sources/AnswerSearch` is the menu-bar app and SwiftUI
views. Put new product logic in the Kit so it can be unit-tested. By contributing you agree your
work is licensed under Apache 2.0.
