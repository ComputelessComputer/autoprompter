# Autoprompter

An intelligent teleprompter for macOS that automatically tracks your speech and highlights the current line as you speak — even if you paraphrase.

## How it works

1. Paste your script into the editor
2. Hit **Start** — the app begins listening via your microphone
3. Speech is streamed to [Deepgram](https://deepgram.com) for real-time transcription
4. Recognized utterances are semantically matched against your script using on-device sentence embeddings (Apple NaturalLanguage framework)
5. The current line is highlighted and the view auto-scrolls at your speaking pace

Because alignment is **semantic** (not word-by-word), the prompter keeps up even when you ad-lib, rephrase, or skip ahead.

## Features

- **Semantic alignment** — uses NLEmbedding to match meaning, not exact words
- **Line-based highlighting** with smooth auto-scroll
- **Always-on-top** floating window
- **Translucent glass panel** with adjustable opacity
- **Mic level indicator** (three red bars)
- **Speech rate display** (words per minute)
- **Best-effort screen capture protection** (`window.sharingType = .none`)
- **Deepgram API key** stored in Keychain

## Requirements

- macOS 15+
- Xcode 16+ / Swift 6.1
- A [Deepgram API key](https://console.deepgram.com) (free tier available)

## Run

```sh
swift run
```

Or open in Xcode:

```sh
open Package.swift
# Then ⌘R
```

On first launch, you'll be prompted to paste your Deepgram API key.

## Project structure

```
Sources/Autoprompter/
├── AutoprompterApp.swift       # App entry point, window setup, translucent glass
├── ContentView.swift           # Main UI: header, script editor, controls
├── TeleprompterViewModel.swift # State management, speech handling, alignment
├── TeleprompterTextView.swift  # NSTextView wrapper with highlight + auto-scroll
├── SemanticAligner.swift       # Sentence segmentation + NLEmbedding matching
├── DeepgramStreamer.swift      # WebSocket streaming STT + audio capture
├── WordTokenizer.swift         # Text tokenization and fuzzy matching utilities
└── KeychainStore.swift         # Simple Keychain read/write for API key
```

## Notes

- Microphone permission is requested at runtime. When running via `swift run`, the permission prompt is tied to Terminal (or your terminal emulator), not the app itself. For a standalone `.app` with its own permission, build via Xcode.
- Screen capture hiding uses `window.sharingType = .none`, which blocks legacy `CGWindowListCreateImage` capture but **not** ScreenCaptureKit on macOS 15+. There is no public API to fully prevent screen capture.

## License

MIT
