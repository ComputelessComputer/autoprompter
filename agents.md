# Agents

## Commit Policy

Create a git commit after each discrete action (e.g. adding a feature, fixing a bug, refactoring, updating docs). Each commit should be atomic and self-contained.

Use concise, imperative commit messages (e.g. `Add speech rate slider`, `Fix overlay z-index on Sidecar`, `Refactor DeepgramStreamer error handling`).

Include the co-author line at the end of every commit message:

```
Co-Authored-By: Warp <agent@warp.dev>
```

## Project Overview

AutoPrompter is a macOS teleprompter app (SwiftUI, macOS 15+) that highlights your script in real-time as you speak. The Xcode project lives in `AutoPrompter/`.

Key source files in `AutoPrompter/AutoPrompter/`:

- `AutoPrompterApp.swift` — app entry point
- `AutoPrompterService.swift` — core teleprompter logic
- `ContentView.swift` / `SettingsView.swift` — main UI
- `SpeechRecognizer.swift` — on-device speech recognition
- `DeepgramStreamer.swift` — Deepgram speech-to-text integration
- `LLMResyncService.swift` — LLM-based resync logic
- `NotchOverlayController.swift` / `NotchSettings.swift` — Dynamic Island-style overlay
- `MarqueeTextView.swift` — scrolling text display
- `BrowserServer.swift` — local network browser overlay
- `ExternalDisplayController.swift` — Sidecar / external display support
- `PresentationNotesExtractor.swift` — PowerPoint notes import
- `KeychainStore.swift` — secure credential storage
- `UpdateChecker.swift` — update checking

## Code Style

- Follow existing Swift and SwiftUI conventions in the codebase.
- Keep files focused on a single responsibility.
- Prefer on-device / privacy-preserving approaches.
