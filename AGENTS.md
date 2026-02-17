---
alwaysApply: true
---

## Commit Discipline

- Commit after every discrete action. Each meaningful change (e.g. adding a feature, fixing a bug, refactoring, updating docs, adding a test) must be committed individually before moving on.
- Use concise, imperative commit messages (e.g. `add speech recognition fallback`, `fix overlay positioning on notch displays`).
- Do not batch unrelated changes into a single commit.
- If a task involves multiple steps, commit after each step — not all at the end.

## Releases

- When asked to create a release: bump the version and build number in the Xcode project, commit, push, then create the release with `gh release create`.
- Releases must be published immediately — do not use `--draft`.
- Include release notes with concise, descriptive bullet points explaining what changed. Each bullet should describe the user-facing change, not implementation details.

## Comments

- By default, avoid writing comments at all.
- If you write one, it should be about "Why", not "What".

## General

- Avoid creating unnecessary types, protocols, or extensions if they are not shared. Prefer inlining when something is only used in one place.
- Keep commits small and reviewable.

## Swift

- Run `xcodebuild -project AutoPrompter/AutoPrompter.xcodeproj -scheme AutoPrompter -configuration Debug build -quiet` periodically while making changes to catch errors early — don't wait until the end.
- Fix all warnings before committing.
- Prefer `let` over `var` unless mutation is required.
- Use Swift concurrency (`async`/`await`, `@MainActor`) over completion handlers or Combine when possible.
- Prefer value types (`struct`, `enum`) over reference types (`class`) unless identity semantics are needed.
- Keep SwiftUI views small. Extract subviews when a body getter exceeds ~40 lines.
- Avoid force-unwrapping (`!`) and force-casting (`as!`) outside of tests and previews.
