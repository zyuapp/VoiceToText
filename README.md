# VoiceToText

> **Generated with Claude** - This entire application was built through conversation with Claude Code. Every line of code, architectural decision, and feature implementation came from natural language prompts and AI-assisted development.

A lightweight, privacy-first macOS menu bar app for offline voice dictation powered by Whisper.cpp. Hold a hotkey, speak, and your words appear instantly at your cursor.

## Features

- **Completely Offline**: All transcription happens locally on your Mac - no internet required, no data leaves your device
- **System-Wide Dictation**: Works in any application where you can type
- **Simple Hotkey Interface**: Hold Command to record, release to transcribe and paste
- **Press Escape While Holding**: Cancel recording if you change your mind
- **Menu Bar Integration**: Unobtrusive menu bar icon with visual feedback during recording
- **Privacy First**: No cloud services, no telemetry, no data collection
- **Powered by Whisper**: Uses OpenAI's Whisper.cpp with the large-v3-turbo model for accurate transcription
- **Native macOS**: Built with Swift for optimal performance on Apple Silicon

## Requirements

- macOS 13.0 or later
- Apple Silicon (M1/M2/M3) recommended for best performance
- Microphone access permission

## Installation

### Option 1: Download Pre-built App (Coming Soon)
Download the latest release from the Releases page and drag to your Applications folder.

### Option 2: Build from Source

1. Clone this repository:
```bash
git clone https://github.com/yourusername/VoiceToText.git
cd VoiceToText
```

2. Run the setup script to build Whisper.cpp:
```bash
./setup-whisper.sh
```

3. Build the app:
```bash
xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug clean build
```

4. Find the built app:
```bash
ls -la ~/Library/Developer/Xcode/DerivedData/VoiceToText-*/Build/Products/Debug/VoiceToText.app
```

## Usage

1. **First Launch**: Grant microphone permission when prompted
2. **Start Recording**: Hold the Command key (⌘)
3. **Speak**: Your voice is being recorded while the key is held
4. **Stop & Transcribe**: Release the Command key
5. **Cancel**: Press Escape while holding Command to cancel recording
6. **Auto-Paste**: Transcribed text is automatically pasted at your cursor

### Menu Bar Options
- **Download Model**: First-time setup to download the Whisper model
- **Quit**: Exit the application

## How It Works

1. When you hold the Command key, the app starts recording audio from your microphone
2. Audio is captured in 16kHz mono WAV format (required for Whisper.cpp)
3. Upon release, the recording is saved to a temporary file
4. Whisper.cpp processes the audio file and generates transcription
5. The text is automatically copied to clipboard and pasted at your cursor location
6. Temporary audio files are stored in the sandboxed container: `~/Library/Containers/com.zyu.VoiceToText/Data/tmp/`

## Technical Details

### Architecture
- **SwiftUI + AppKit**: SwiftUI `App` with `NSApplicationDelegateAdaptor` for menu bar management
- **AppDelegate Pattern**: Core services owned and coordinated by `AppDelegate`
- **Audio Recording**: Native `AVAudioRecorder` with AVFoundation
- **Whisper Integration**: Calls Whisper.cpp CLI binary for transcription
- **No Window UI**: Menu bar icon only, hidden from Dock

### Audio Format
Audio must be **16kHz mono WAV** for Whisper.cpp compatibility:
- Sample Rate: 16,000 Hz
- Channels: 1 (mono)
- Format: Linear PCM

### Sandboxing
- Microphone access via `com.apple.security.device.audio-input` entitlement
- Recordings stored in sandboxed container for security
- Minimal permissions required

## Project Structure

```
VoiceToText/
├── VoiceToText/           # Swift source code
│   ├── VoiceToTextApp.swift      # App entry point & AppDelegate
│   ├── AudioRecorder.swift       # Audio recording service
│   └── Assets.xcassets           # App icon and resources
├── whisper.cpp/           # Whisper.cpp submodule
├── setup-whisper.sh       # Script to build Whisper.cpp
├── CLAUDE.md             # Claude Code guidance
├── prd.md                # Product requirements
└── plan.md               # Development plan
```

## Development

This project demonstrates AI-assisted development using Claude Code. The entire codebase was generated through conversational programming - from initial architecture to implementation details, bug fixes, and feature additions.

### Build Commands

```bash
# Clean build
xcodebuild -project VoiceToText.xcodeproj -scheme VoiceToText -configuration Debug clean build

# Find built app location
ls -la ~/Library/Developer/Xcode/DerivedData/VoiceToText-*/Build/Products/Debug/VoiceToText.app

# View recordings in sandboxed container
open ~/Library/Containers/com.zyu.VoiceToText/Data/tmp/
```

See [CLAUDE.md](CLAUDE.md) for detailed development guidelines and architectural patterns.

## Privacy & Security

- **100% Offline**: No network requests, no cloud services
- **Local Processing**: All transcription happens on your device
- **No Data Collection**: We don't collect, store, or transmit any of your voice data
- **Sandboxed**: App runs in a macOS sandbox with minimal permissions
- **Open Source**: Review the code yourself

## License

MIT License

Copyright (c) 2025

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgments

- [Whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper
- [OpenAI Whisper](https://github.com/openai/whisper) - Robust speech recognition model
- Built with [Claude Code](https://claude.ai/code) - AI-assisted development from concept to completion

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

**Built with Claude** - An example of what's possible with AI-assisted software development.
