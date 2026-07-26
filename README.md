# JustSpeak

> Built with [Claude Code](https://claude.ai/code) - AI-assisted development from concept to completion. 🤖

A lightweight macOS menu bar app for offline voice dictation, with optional cloud LLM post-processing. Hold Right Command, speak, and your words appear at your cursor.

## Features

- **Offline Transcription** - Core speech-to-text runs locally with Parakeet on sherpa-onnx
- **System-Wide** - Works in any application where you can type
- **Simple Hotkey** - Hold Right Command to record, release to transcribe and paste
- **Cancel Anytime** - Press Escape while holding to cancel recording
- **Optional LLM Cleanup** - Route transcribed text to an OpenAI-compatible endpoint before paste
- **Privacy Control** - Keep everything local or opt in to cloud post-processing
- **Accurate** - Powered by NVIDIA's Parakeet TDT 0.6B v2 model
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
./setup-parakeet.sh

# Build
xcodebuild -project JustSpeak.xcodeproj -scheme JustSpeak -configuration Debug clean build

# Find built app
ls -la ~/Library/Developer/Xcode/DerivedData/JustSpeak-*/Build/Products/Debug/JustSpeak.app
```

## Usage

1. **First Launch** - Grant microphone permission and wait for the Parakeet model download
2. **Record** - Hold the Right Command key (⌘) and speak
3. **Optional LLM Setup** - Open app menu > Settings... and add Base URL, Model, and API key
4. **Transcribe** - Release Command to stop and auto-paste
5. **Cancel** - Press Escape while holding to abort

## Tech Stack

- **SwiftUI + AppKit** - Menu bar app with NSApplicationDelegateAdaptor
- **AVFoundation** - Native audio recording (16kHz mono WAV)
- **sherpa-onnx** - Local Parakeet inference through ONNX Runtime
- **Native Integration** - Uses macOS microphone and accessibility APIs directly

## Development

See [CLAUDE.md](CLAUDE.md) for architecture details and development guidelines.
Third-party attributions and license texts are bundled with the app under
[`JustSpeak/ThirdPartyLicenses`](JustSpeak/ThirdPartyLicenses).

## Acknowledgments

- [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) - On-device speech recognition runtime
- [NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) - English speech recognition model
