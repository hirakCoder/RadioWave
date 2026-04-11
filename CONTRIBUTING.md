# Contributing to RadioWave

Thanks for your interest in contributing! RadioWave is a small project and contributions of all kinds are welcome.

## Getting Started

1. Fork the repo
2. Clone your fork
3. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
4. Generate the Xcode project: `xcodegen generate`
5. Open `RadioWave.xcodeproj` and build (Cmd+R)

## Project Structure

- **Audio/** — AVAudioEngine pipeline, procedural synthesis, event chimes
- **Core/** — State management, hook server, session detection
- **Views/** — SwiftUI popover, waveform visualization, settings

## Ways to Contribute

### New Sound Variants
Each state (thinking, tool use, generating) supports multiple sound variants in `SignalSynthesizer.swift`. Adding a new variant is a great first contribution:
1. Add a new `fillThinking___()` method
2. Increment the variant count in the dispatch `switch`
3. Test it in demo mode

### Bug Fixes
If something sounds wrong or the UI behaves unexpectedly, open an issue or submit a PR.

### New Hook Events
Claude Code exposes many hook events we don't handle yet (`SubagentStart`, `SubagentStop`, `PreCompact`, etc.). Adding support for these is straightforward in `AppDelegate.swift`.

## Code Style

- Follow existing patterns — no external dependencies, all audio is procedural
- Use `nonisolated(unsafe)` for render-thread shared state (not locks)
- Keep sounds musical and pleasant, not harsh or annoying
- Test with demo mode before submitting

## Pull Requests

1. Create a branch from `main`
2. Make your changes
3. Test that it builds and sounds right
4. Open a PR with a brief description

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
