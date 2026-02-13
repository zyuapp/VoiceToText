# VoiceToText

> Built with [Claude Code](https://claude.ai/code) - AI-assisted development from concept to completion. 🤖

A lightweight, privacy-first macOS menu bar app for offline voice dictation. Hold Command, speak, and your words appear at your cursor.

## Features

- **Completely Offline** - All transcription happens locally, no internet required
- **System-Wide** - Works in any application where you can type
- **Simple Hotkey** - Hold Command to record, release to transcribe and paste
- **Cancel Anytime** - Press Escape while holding to cancel recording
- **Privacy First** - No cloud services, no telemetry, no data collection
- **Accurate** - Powered by OpenAI's Whisper large-v3-turbo model
- **Native macOS** - Built with Swift, optimized for Apple Silicon

## Requirements

- macOS 13.0 or later
- Apple Silicon (M1/M2/M3) recommended
- Microphone access permission

## Installation

### Download Pre-built App

Install with Homebrew Cask:

```bash
brew install --cask zyuapp/tap/voice-to-text
```

Or download the latest zip from the GitHub Releases page and move `VoiceToText.app` to `/Applications`.

Note: builds are currently unsigned and not notarized, so macOS may show a security warning on first launch.

### Build from Source

```bash
# Clone and setup
git clone https://github.com/yourusername/VoiceToText.git
cd VoiceToText
./setup-whisper.sh

# Build
xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug clean build

# Find built app
ls -la ~/Library/Developer/Xcode/DerivedData/VoiceToText-*/Build/Products/Debug/VoiceToText.app
```

## Usage

1. **First Launch** - Grant microphone permission when prompted, download Whisper model from menu
2. **Record** - Hold Command key (⌘) and speak
3. **Transcribe** - Release Command to stop and auto-paste
4. **Cancel** - Press Escape while holding to abort

## Tech Stack

- **SwiftUI + AppKit** - Menu bar app with NSApplicationDelegateAdaptor
- **AVFoundation** - Native audio recording (16kHz mono WAV)
- **Whisper.cpp** - Local transcription with Metal acceleration
- **Sandboxed** - Minimal permissions, secure by design

## Development

See [CLAUDE.md](CLAUDE.md) for architecture details and development guidelines.

## Release Process

Tag and push a version to trigger the release workflow:

```bash
git tag v1.1
git push origin v1.1
```

The workflow builds a Release app, creates a zip asset, publishes it to GitHub Releases, and can update `zyuapp/homebrew-tap` automatically when `HOMEBREW_TAP_TOKEN` is configured in repository secrets.

## Acknowledgments

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper
- [OpenAI Whisper](https://github.com/openai/whisper) - Robust speech recognition model
