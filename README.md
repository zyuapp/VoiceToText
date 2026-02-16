# JustSpeak

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
brew install --cask zyuapp/tap/just-speak
```

Or download the latest zip from the GitHub Releases page and move `JustSpeak.app` to `/Applications`.

Note: builds are currently unsigned and not notarized, so macOS may show a security warning on first launch. If that happens, open System Settings > Privacy & Security, scroll to Security, click Open Anyway for JustSpeak, then confirm Open.

### Build from Source

```bash
# Clone and setup
git clone https://github.com/zyuapp/just-speak.git
cd just-speak
./setup-whisper.sh

# Build
xcodebuild -project JustSpeak.xcodeproj -scheme JustSpeak -configuration Debug clean build

# Find built app
ls -la ~/Library/Developer/Xcode/DerivedData/JustSpeak-*/Build/Products/Debug/JustSpeak.app
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

## Acknowledgments

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper
- [OpenAI Whisper](https://github.com/openai/whisper) - Robust speech recognition model
