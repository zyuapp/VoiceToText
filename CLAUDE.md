# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native macOS menu bar app for offline voice dictation powered by Whisper.cpp. Users hold a hotkey to record audio, which is transcribed locally and auto-pasted at the cursor.

## Build Commands

```bash
# Build the app
xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug clean build

# Find built app
ls -la ~/Library/Developer/Xcode/DerivedData/VoiceToText-*/Build/Products/Debug/VoiceToText.app

# Open recordings directory (sandboxed container)
open ~/Library/Containers/com.zyu.VoiceToText/Data/tmp/
```

## Architecture

**Menu Bar App Pattern:**
- SwiftUI `App` with `NSApplicationDelegateAdaptor`
- `AppDelegate` owns all core services and manages lifecycle
- No visible window - menu bar icon only via `NSStatusBar`
- Hidden from dock via `INFOPLIST_KEY_LSUIElement = YES`

**Core Components:**
- `AppDelegate` (VoiceToTextApp.swift): Menu bar UI, notifications, coordinates recording
- `AudioRecorder` (AudioRecorder.swift): Wraps `AVAudioRecorder` for microphone capture

**Function Size Constraint:**
Keep functions small and single-purpose. Break large functions into multiple focused helper methods.

## Critical Requirements

**Audio Format (Non-negotiable):**
Must be **16kHz mono WAV** for Whisper.cpp compatibility:
```swift
AVSampleRateKey: 16000.0
AVNumberOfChannelsKey: 1
AVFormatIDKey: kAudioFormatLinearPCM
```

**Sandboxing:**
- Entitlements in `VoiceToText.entitlements`: `com.apple.security.device.audio-input`
- Microphone permission: `INFOPLIST_KEY_NSMicrophoneUsageDescription` in project.pbxproj
- Recordings save to sandboxed container: `~/Library/Containers/com.zyu.VoiceToText/Data/tmp/`

**macOS-Specific:**
- No `AVAudioSession` (iOS only) - `AVAudioRecorder` works directly on macOS
- Menu built with `NSMenu`/`NSMenuItem` (AppKit), not SwiftUI
