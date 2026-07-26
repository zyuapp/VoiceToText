# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native macOS menu bar app for offline voice dictation powered by Parakeet on sherpa-onnx. Users hold a hotkey to record audio, which is transcribed locally and auto-pasted at the cursor.

## Setup and Build Commands

```bash
# Install sherpa-onnx static libraries (required before first app build)
./setup-parakeet.sh

# Build the app with a dynamically selected local signing identity
make build

# Install a release build
make install

# Open downloaded model directory
open ~/Library/Application\ Support/just-speak/Models/
```

If build errors mention missing sherpa-onnx or ONNX Runtime symbols, run `./setup-parakeet.sh` again.

## Runtime Paths

- Parakeet model path: `~/Library/Application Support/just-speak/Models/parakeet/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/`
- Recordings are written to `FileManager.default.temporaryDirectory` as `recording_<timestamp>.wav`
- Temporary recordings are deleted after transcription or cancellation

## Architecture

**Menu Bar App Pattern:**
- SwiftUI `App` with `NSApplicationDelegateAdaptor`
- `AppDelegate` owns all core services and manages lifecycle
- No visible window - menu bar icon only via `NSStatusBar`
- Hidden from dock via `INFOPLIST_KEY_LSUIElement = YES`

**Core Components:**
- `AppDelegate` (`JustSpeakApp.swift`): status menu, notifications, record/transcribe/paste flow orchestration
- `HotkeyManager` (`HotkeyManager.swift`): global event tap for Right Command down/up and Escape cancel
- `AudioRecorder` (`AudioRecorder.swift`): `AVAudioRecorder` wrapper plus CoreAudio input-device selection
- `TranscriptionService` (`TranscriptionService.swift`): model lifecycle and async transcription entry point
- `ModelDownloader` (`ModelDownloader.swift`): verified first-run model download and installation
- `ParakeetWrapper` (`ParakeetWrapper.swift`): audio loading and Swift interface to Parakeet
- `ParakeetBridge` (`ParakeetBridge.mm`): sherpa-onnx C API configuration and inference
- `ClipboardManager` (`ClipboardManager.swift`): copy result and synthesize Command+V paste

**Function Size Constraint:**
Keep functions small and single-purpose. Break large functions into multiple focused helper methods.

## Critical Requirements

**Audio Format (Non-negotiable):**
Must be **16kHz mono WAV** for Parakeet compatibility:
```swift
AVSampleRateKey: 16000.0
AVNumberOfChannelsKey: 1
AVFormatIDKey: kAudioFormatLinearPCM
```

**Hotkey Behavior:**
- Record trigger is currently Right Command only (`targetKeyCode = 54`)
- Release stops recording; Escape while held cancels recording

**Permissions:**
- Microphone usage string comes from `INFOPLIST_KEY_NSMicrophoneUsageDescription` in `project.pbxproj`
- Accessibility permission is required for global key capture and synthetic paste events

**App Sandbox:**
- App sandbox is currently disabled (`ENABLE_APP_SANDBOX = NO` and `com.apple.security.app-sandbox = false`)
- Do not assume sandbox container paths for temporary recordings

**macOS-Specific:**
- No `AVAudioSession` (iOS only) - `AVAudioRecorder` works directly on macOS
- Menu built with `NSMenu`/`NSMenuItem` (AppKit), not SwiftUI

## Non-Obvious Gotchas

- First launch downloads the Parakeet archive (~460 MB). App is not transcription-ready until download, verification, extraction, and `TranscriptionService.initialize()` complete.
- `JustSpeakApp.handleHotkeyUp()` warns when duration is over 60s, but does not trim audio yet. If you change duration UX, keep behavior and messaging aligned.
- `Parakeet.xcconfig` links static libs from `sherpa-onnx/lib`; if that folder is removed, run `./setup-parakeet.sh` again.
