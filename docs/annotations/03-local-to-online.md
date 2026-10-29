# 3. Local to online hand-off

Source: `Sources/AnswerSearchKit/AnswerEngine.swift` (`search`, `tryLocal`, `localRoute`).
This is product logic, not SDK calls, but it decides when the SDK's two paths (pages 1 and 2) run.

## When Local AI is tried

Only in **Local AI mode**, when the user opted in (Settings), the Mac supports it, the question
does not ask for links or sources, and it is not a double-check. A follow-up stays local only if
the previous answer came from Local AI.

## What happens next

```swift
if route.useLocal {
    if let result = await tryLocal(request, ...) { return result }   // answered on this Mac
    request = request.providerFast                                    // otherwise fall through
}
// ... online provider answers
```

`tryLocal` returns nil when the model deferred, errored or produced an empty answer. The same
question then goes to the configured provider with **Fast AI** behavior: `providerFast` sets a short
token budget, no web search and no link request.

Local AI mode that is not usable (not opted in, or not available) also becomes Fast AI.

## After the answer

The result is labeled by who answered ("Answered by AI on this Mac" or "Answered by Claude").
Local answers show no sources. A local answer offers **Double-check with Claude**, which sends the
previous question and answer to the provider (still Fast AI, no web search). Only that one
previous question and answer are kept for follow-ups.
