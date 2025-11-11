# Product Requirements Document (PRD)

## Project
Whisper Dictation for macOS  
Version 1.0

---

## Overview
A lightweight macOS background app that enables system-wide voice dictation powered by Whisper.cpp.  
When the user holds a configurable hotkey, the app records audio, transcribes it locally using Whisper,  
and pastes the recognized text at the active cursor location.  
Runs entirely offline and packaged as a single drag-and-drop `.app`.

---

## Goals
- Enable fast, offline, accurate dictation anywhere on macOS.  
- Zero setup: one `.app`, minimal permissions.  
- Instant hotkey trigger and seamless paste.  
- Privacy-first: no network or cloud services.

---

## Core User Flow
1. User installs the app by dragging it to Applications.  
2. On first run, the app requests Microphone and Accessibility access.  
3. User holds the configured hotkey (e.g., Right Command).  
4. The app records voice until the key is released.  
5. Whisper.cpp transcribes the audio to text.  
6. The transcribed text is copied to the clipboard and auto-pasted.

---

## Functional Requirements
- Global hotkey listener (configurable).  
- Continuous microphone recording while the key is held.  
- Temporary audio file written as WAV (16 kHz mono).  
- Whisper.cpp CLI or library integration using bundled model (`ggml-large-v3-turbo.bin`).  
- Clipboard update and programmatic Cmd+V paste.  
- Menu bar icon for settings (hotkey, model, language, startup).  
- Local storage for preferences.

---

## Technical Requirements
- macOS 13+ (Apple Silicon optimized).  
- Swift + AVFoundation for audio capture.  
- Whisper.cpp binary (Metal or Core ML backend).  
- Bundle model in `Contents/Resources` or download on first launch.  
- Permissions: `NSMicrophoneUsageDescription`, Accessibility access.  
- Signed and notarized `.app`.

---

## Out of Scope
- Cloud transcription.
- Multi-language auto-detection (manual language selection only).
- UI text editor or rich text formatting.

---

## Design Decisions

### Development Stack
Swift for native macOS performance and clean system integration (hotkeys, mic, pasteboard). Not using Electron/Tauri.

### Model Strategy
- **v1**: `large-v3-turbo` for best accuracy
- **Future**: Allow users to switch to smaller models for speed

### Performance Target
1× real-time or better. Example: 10 seconds of audio transcribed in ≤10 seconds on M1/M2.

### Language Support
- **v1**: English-only
- **Future**: Multi-language optional

### Visual Feedback
Minimal: animated menu bar icon during recording/processing. No pop-ups.

### Model Distribution
Download on first launch to keep initial `.app` under ~200 MB.

### Distribution Channel
Direct download for now. App Store can be revisited once sandbox and code-signing workflows are proven.

### Timeline
- Functional prototype: 2–3 weeks
- Polished release: ~6 weeks