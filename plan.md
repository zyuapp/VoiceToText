# Whisper Dictation for macOS - Implementation Plan

## Overview
This plan breaks down the development of the Whisper Dictation app into 8 distinct phases. Each phase builds on the previous one and includes specific testing criteria you can manually verify. Since you're new to Swift and macOS development, each phase includes detailed guidance on what to expect and how to verify success.

---

## Prerequisites Setup

### What You'll Need
- **Xcode 15+** installed from Mac App Store
- **Command Line Tools** (install via `xcode-select --install`)
- **Apple Developer Account** (free tier is fine for local development)
- **Homebrew** for installing Whisper.cpp dependencies

### Initial Repository Structure
```
voice-to-text/
├── WhisperDictation/           # Xcode project folder
├── PRD.md                       # Product requirements (already exists)
├── plan.md                      # This file
└── README.md                    # User-facing documentation
```

---

## Phase 1: Basic macOS Menu Bar App Foundation
**Goal:** Create a functioning macOS app that shows a menu bar icon and basic menu.

### Tasks
1. **Create Xcode Project**
   - Create new macOS App project in Xcode
   - Bundle identifier: `com.yourname.WhisperDictation`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum deployment: macOS 13.0

2. **Configure as Menu Bar App**
   - Remove default window (modify App struct)
   - Add `LSUIElement` key to Info.plist (hides dock icon)
   - Create menu bar icon using `NSStatusBar`
   - Add basic menu with "Quit" option

3. **Add App Icon**
   - Create simple microphone icon for menu bar
   - Set up asset catalog

### Deliverables
- ✅ Xcode project structure created
- ✅ App runs and shows icon in menu bar
- ✅ No window appears (only menu bar icon)
- ✅ Clicking icon shows menu with "Quit" option

### Testing Plan
**How to Test:**
1. Open project in Xcode
2. Click Run (Cmd+R)
3. Look for icon in top menu bar (right side)
4. Click icon - should see dropdown menu
5. Click "Quit" - app should close
6. Check that no window opens when app launches
7. Check that app doesn't appear in Dock

**Success Criteria:**
- [ ] App builds without errors
- [ ] Menu bar icon appears and is clickable
- [ ] Menu appears with working Quit option
- [ ] No dock icon visible
- [ ] No window opens on launch

---

## Phase 2: Microphone Access & Audio Recording
**Goal:** Record audio from microphone and save as WAV file.

### Tasks
1. **Request Microphone Permission**
   - Add `NSMicrophoneUsageDescription` to Info.plist
   - Implement permission request flow
   - Handle permission granted/denied states

2. **Implement Audio Recorder**
   - Create `AudioRecorder` class using `AVFoundation`
   - Configure for 16kHz mono WAV format
   - Save recordings to temporary directory
   - Add start/stop recording methods

3. **Add Menu Testing Controls**
   - Add "Test Recording" menu item
   - Records for 5 seconds automatically
   - Shows system notification when done
   - Prints file path to console

### Deliverables
- ✅ Microphone permission dialog appears on first run
- ✅ Can record audio to WAV file
- ✅ Files saved in correct format (16kHz, mono, WAV)
- ✅ Test menu item works

### Testing Plan
**How to Test:**
1. Run app - should see microphone permission dialog
2. Grant permission
3. Click menu bar icon → "Test Recording"
4. Speak into microphone for 5 seconds
5. Check notification appears saying recording saved
6. Open Console.app and filter for "WhisperDictation"
7. Find logged file path (e.g., `/tmp/recording_12345.wav`)
8. Open file in QuickTime Player - should hear your recording
9. Right-click file → Get Info - verify 16kHz, mono format

**Success Criteria:**
- [ ] Permission dialog appears with your custom message
- [ ] Recording starts when clicking "Test Recording"
- [ ] Can hear recorded audio in QuickTime
- [ ] File format matches specs (16kHz, mono)
- [ ] File path logged to console
- [ ] No crashes or audio distortion

**Common Issues & Fixes:**
- If no permission dialog: Check Info.plist has `NSMicrophoneUsageDescription`
- If no audio: Check System Settings → Privacy → Microphone
- If wrong format: Verify AVAudioRecorder settings

---

## Phase 3: Global Hotkey Listener
**Goal:** Detect when user holds/releases a global hotkey (e.g., Right Command).

### Tasks
1. **Implement Hotkey Detection**
   - Use Carbon Event Manager or CGEvent tap
   - Listen for Right Command key (default)
   - Handle key down and key up events
   - Work even when app is in background

2. **Connect to Recording**
   - Start recording on key down
   - Stop recording on key up
   - Add visual feedback (change menu bar icon)

3. **Add Accessibility Permission**
   - Add Accessibility permission request
   - Guide user through System Settings if denied

### Deliverables
- ✅ Global hotkey detection working
- ✅ Recording starts on key down
- ✅ Recording stops on key up
- ✅ Menu bar icon changes during recording
- ✅ Works when app is not focused

**Implementation Status: COMPLETED**

### Testing Plan
**How to Test:**
1. Run app
2. Grant Accessibility permission when prompted (System Settings → Privacy & Security → Accessibility)
3. Focus any app (e.g., TextEdit, Notes, Browser)
4. Hold Right Command key
5. Watch menu bar icon - should change (e.g., red dot or different icon)
6. Speak while holding key
7. Release key
8. Icon should return to normal
9. Check console for recording file path

**Manual Test Scenarios:**
- Test in different apps (TextEdit, Notes, Terminal, Browser)
- Test with app completely in background
- Test rapid press/release (should handle gracefully)
- Test holding for very short time (< 0.5 sec)
- Test holding for long time (> 30 sec)

**Success Criteria:**
- [ ] Hotkey works in any app
- [ ] Visual feedback is clear and immediate
- [ ] Recording starts/stops correctly
- [ ] No lag or UI freeze
- [ ] Works when app is in background
- [ ] Console shows recording saved after key release

**Common Issues & Fixes:**
- Hotkey not working: Check Accessibility permission in System Settings
- App crashes: Ensure event tap is properly initialized
- No visual feedback: Check menu bar icon update code

---

## Phase 4: Whisper.cpp Integration
**Goal:** Transcribe recorded WAV files to text using Whisper.cpp.

### Tasks
1. **Build Whisper.cpp**
   - Clone whisper.cpp repository
   - Build with Metal backend for Apple Silicon
   - Create Swift wrapper/bridge
   - Bundle binary in app

2. **Model Management**
   - Implement model downloader
   - Download `ggml-large-v3-turbo.bin` on first launch
   - Store in Application Support directory
   - Show progress in menu bar

3. **Transcription Engine**
   - Create `TranscriptionService` class
   - Pass WAV file to Whisper.cpp
   - Parse output text
   - Handle errors gracefully

4. **Testing Interface**
   - Add "Transcribe Test File" menu item
   - Uses pre-recorded audio
   - Shows result in notification and console

### Deliverables
- ✅ Whisper.cpp binary built and bundled
- ✅ Model downloads on first launch
- ✅ Can transcribe WAV to text
- ✅ Performance meets target (1× real-time)

### Testing Plan
**How to Test:**

**Part 1: Model Download**
1. Delete any existing model files
2. Run app
3. Should see menu bar indication of download
4. Check `~/Library/Application Support/WhisperDictation/`
5. Verify `ggml-large-v3-turbo.bin` exists (~1.6GB)

**Part 2: Transcription Test**
1. Create test recording: "The quick brown fox jumps over the lazy dog"
2. Click menu → "Transcribe Test File"
3. Wait for processing
4. Check console for transcribed text
5. Verify text is accurate
6. Note transcription time

**Part 3: Performance Test**
Record and transcribe various lengths:
- 5 seconds of speech
- 10 seconds of speech
- 30 seconds of speech

For each, verify:
- Transcription time ≤ recording length (1× real-time)
- Accuracy is good
- No crashes or memory issues

**Success Criteria:**
- [ ] Model downloads successfully on first launch
- [ ] Model file is correct size (~1.6GB)
- [ ] Transcription produces readable text
- [ ] Accuracy is acceptable (>90% for clear speech)
- [ ] Performance: 10 sec audio transcribed in ≤10 sec
- [ ] No memory leaks or crashes
- [ ] Works offline (test with WiFi off)

**Common Issues & Fixes:**
- Download fails: Check network, check disk space (need ~2GB free)
- Transcription slow: Verify Metal backend is being used, not CPU
- Poor accuracy: Check audio quality (should be 16kHz mono)
- Crashes: Check Whisper.cpp build flags match architecture

---

## Phase 5: Clipboard & Auto-Paste Integration
**Goal:** Copy transcribed text to clipboard and automatically paste it.

### Tasks
1. **Clipboard Management**
   - Use `NSPasteboard` to copy text
   - Preserve previous clipboard content (optional)
   - Handle empty transcriptions

2. **Auto-Paste Implementation**
   - Simulate Cmd+V using CGEvent
   - Small delay to ensure clipboard is updated
   - Handle cases where paste fails

3. **End-to-End Test**
   - Add "Test Full Flow" menu item
   - Records → transcribes → copies → pastes
   - Use in real text editor

### Deliverables
- ✅ Text copied to clipboard
- ✅ Auto-paste works reliably
- ✅ Works in different applications

### Testing Plan
**How to Test:**

**Part 1: Clipboard Test**
1. Copy something to clipboard ("TEST TEXT")
2. Run transcription with audio "hello world"
3. Open TextEdit → paste (Cmd+V)
4. Should see "hello world"

**Part 2: Auto-Paste Test**
1. Open TextEdit, create new document
2. Click in document to position cursor
3. Use app's "Test Full Flow" menu item
4. Speak into mic: "This is a test"
5. After processing, text should appear in TextEdit

**Part 3: Multi-App Test**
Test auto-paste in:
- TextEdit
- Notes.app
- Safari (URL bar and text field)
- Terminal
- Slack/Discord (if installed)
- Any code editor

**Success Criteria:**
- [ ] Clipboard contains transcribed text
- [ ] Auto-paste works without manual Cmd+V
- [ ] Works in at least 5 different apps
- [ ] Cursor position respected
- [ ] No duplicate pastes
- [ ] Handles empty transcription gracefully

**Common Issues & Fixes:**
- Paste not working: Need Accessibility permission
- Text appears in wrong place: Timing issue, add small delay
- Clipboard not updating: Check NSPasteboard usage

---

## Phase 6: Complete End-to-End Flow
**Goal:** Full integration - hotkey triggers recording, transcription, and paste.

### Tasks
1. **Connect All Components**
   - Hotkey → AudioRecorder
   - AudioRecorder → TranscriptionService
   - TranscriptionService → Clipboard → Paste
   - Chain all async operations properly

2. **Visual Feedback**
   - Menu bar icon states:
     - Normal (idle)
     - Recording (holding hotkey)
     - Processing (transcribing)
     - Error (if something fails)
   - Optional: subtle animation

3. **Error Handling**
   - Recording too short (<0.5 sec) - ignore
   - Recording too long (>60 sec) - handle gracefully
   - Transcription fails - show notification
   - No audio detected - silent fail or notify

### Deliverables
- ✅ Complete flow works seamlessly
- ✅ Clear visual feedback at each stage
- ✅ Robust error handling

### Testing Plan
**How to Test:**

**Scenario 1: Happy Path**
1. Open TextEdit, position cursor
2. Hold Right Command key
3. Watch menu bar icon change to "recording" state
4. Speak: "Testing the voice dictation application"
5. Release key
6. Watch icon change to "processing" state
7. Text should appear in TextEdit
8. Verify text accuracy

**Scenario 2: Short Recording**
1. Position cursor in text field
2. Tap Right Command quickly (<0.5 sec)
3. Should either ignore or handle gracefully
4. No error notification

**Scenario 3: Long Recording**
1. Position cursor
2. Hold Right Command for 45 seconds
3. Speak continuously
4. Release
5. Should transcribe successfully
6. Verify full text appears

**Scenario 4: Background Noise**
1. Play music or have conversation nearby
2. Position cursor
3. Hold hotkey and speak clearly
4. Should transcribe your voice (may include noise)

**Scenario 5: Error Recovery**
1. Disconnect microphone (if using external)
2. Try to record
3. Should show error notification
4. Reconnect microphone
5. Try again - should work

**Scenario 6: Rapid Repeated Use**
1. Use dictation 5 times in a row quickly
2. Each should complete successfully
3. No memory buildup or slowdown

**Success Criteria:**
- [ ] Full flow completes in reasonable time
- [ ] Visual feedback is clear at each stage
- [ ] Text accuracy is good (>90% for clear speech)
- [ ] No crashes or hangs
- [ ] Handles errors gracefully
- [ ] Works consistently across multiple uses
- [ ] Audio files cleaned up (not filling disk)

**Performance Benchmarks:**
- 5 sec recording → text appears within 10 sec total
- 10 sec recording → text appears within 20 sec total
- No noticeable lag when starting recording

---

## Phase 7: Settings & User Configuration
**Goal:** Allow users to customize hotkey, language, and other preferences.

### Tasks
1. **Settings Storage**
   - Use `UserDefaults` for preferences
   - Store: hotkey, language, model choice, launch at startup

2. **Settings UI in Menu**
   - Add "Settings" menu item
   - Opens small window or panel
   - Hotkey recorder (click field, press key combination)
   - Language dropdown (English only for v1)
   - Model selection (large-v3-turbo only for v1)
   - "Launch at startup" checkbox

3. **Hotkey Configuration**
   - Allow different key combinations
   - Common options: Right Cmd, Right Option, Fn, etc.
   - Validate hotkey doesn't conflict with system
   - Update listener when changed

4. **Launch at Startup**
   - Use SMLoginItemSetEnabled or ServiceManagement
   - Add/remove from login items
   - Test on clean macOS install

### Deliverables
- ✅ Settings UI functional
- ✅ Preferences persist across restarts
- ✅ Hotkey customization works
- ✅ Launch at startup works

### Testing Plan
**How to Test:**

**Part 1: Settings Persistence**
1. Open Settings
2. Change hotkey to Right Option
3. Close settings
4. Test new hotkey - should work
5. Quit app
6. Restart app
7. Test hotkey - should still be Right Option

**Part 2: Hotkey Change**
1. Open Settings
2. Click hotkey field
3. Press different combinations:
   - Right Command
   - Right Option
   - Fn key
   - Ctrl+Option
4. For each, verify it works
5. Try system hotkeys (e.g., Cmd+Space) - should warn

**Part 3: Launch at Startup**
1. Enable "Launch at startup" in Settings
2. Quit app
3. Restart Mac
4. Verify app launches automatically
5. Check menu bar icon appears
6. Disable "Launch at startup"
7. Restart Mac
8. Verify app does NOT launch

**Part 4: Settings Edge Cases**
- Close settings without saving
- Change multiple settings at once
- Use app immediately after changing hotkey
- Delete preferences file manually, restart app (should use defaults)

**Success Criteria:**
- [ ] All settings save correctly
- [ ] Settings persist after quit/restart
- [ ] Hotkey changes take effect immediately
- [ ] Launch at startup works on clean install
- [ ] Can disable launch at startup
- [ ] Default settings are sensible
- [ ] Settings UI is intuitive

---

## Phase 8: Code Signing, Notarization & Distribution
**Goal:** Create a distributable .app that works on any Mac.

### Tasks
1. **Code Signing**
   - Create Developer ID Application certificate
   - Enable Hardened Runtime
   - Sign app bundle and all embedded binaries
   - Sign Whisper.cpp binary

2. **Entitlements**
   - Add required entitlements:
     - Microphone access
     - Accessibility (for hotkey and paste)
     - Network (for model download only)
   - Configure Info.plist correctly

3. **Notarization**
   - Archive app for distribution
   - Submit to Apple notarization service
   - Staple notarization ticket
   - Handle common rejection reasons

4. **Distribution Package**
   - Create DMG or ZIP
   - Include brief README
   - Test on clean Mac (without Xcode)

### Deliverables
- ✅ Signed and notarized .app
- ✅ Distribution package (DMG or ZIP)
- ✅ Works on clean Mac install

### Testing Plan
**How to Test:**

**Part 1: Clean Install Simulation**
1. Build signed app
2. Copy to USB drive or AirDrop to another Mac
3. On different Mac (without Xcode):
   - Open app from Downloads
   - Should NOT see "unidentified developer" warning
   - Grant microphone and accessibility permissions
   - Test full flow
   - Check launch at startup

**Part 2: Notarization Verification**
1. Run in Terminal:
   ```bash
   spctl -a -v /Applications/WhisperDictation.app
   ```
2. Should see: "accepted"
3. Run:
   ```bash
   codesign -dv --verbose=4 /Applications/WhisperDictation.app
   ```
4. Verify signature details

**Part 3: First-Time User Experience**
1. Fresh Mac or new user account
2. Download and open app
3. Follow permission dialogs
4. Model should download
5. Test dictation works
6. Verify no technical errors

**Part 4: Security Checks**
- Open from quarantine (download from internet)
- Check Gatekeeper allows it
- Verify hardened runtime active
- Test all permissions granted properly

**Success Criteria:**
- [ ] App opens without "unidentified developer" warning
- [ ] All permissions request correctly
- [ ] Model downloads successfully
- [ ] Full flow works on clean Mac
- [ ] Notarization verified with `spctl`
- [ ] Code signature valid
- [ ] Works on both Intel and Apple Silicon (if supporting both)

---

## Development Environment Setup Guide

### For Someone New to Swift/macOS Development

**Step 1: Install Xcode**
1. Open Mac App Store
2. Search "Xcode"
3. Click "Get" (it's free, ~14GB download)
4. Wait for installation (can take 30-60 min)
5. Open Xcode, agree to license

**Step 2: Install Command Line Tools**
1. Open Terminal
2. Run: `xcode-select --install`
3. Click "Install" in dialog
4. Wait for completion

**Step 3: Install Homebrew**
1. Open Terminal
2. Visit https://brew.sh
3. Copy and paste install command
4. Follow prompts

**Step 4: Clone Whisper.cpp**
```bash
cd ~/Downloads
git clone https://github.com/ggerganov/whisper.cpp
cd whisper.cpp
make
```

**Step 5: Test Your Setup**
1. Open Xcode
2. Create new project (File → New → Project)
3. Choose macOS → App
4. Click Run (Cmd+R)
5. If window opens, setup is working!

---

## Learning Resources

### Essential Swift Concepts You'll Need
1. **Optionals** - handling values that might be nil
2. **Closures** - passing functions as parameters
3. **Async/Await** - handling asynchronous operations
4. **Classes vs Structs** - when to use which
5. **Property Observers** - reacting to value changes

### Essential macOS Concepts
1. **NSStatusBar** - menu bar API
2. **AVFoundation** - audio recording
3. **NSPasteboard** - clipboard access
4. **CGEvent** - simulating keyboard events
5. **UserDefaults** - saving preferences

### Recommended Learning Path
1. **Swift Basics** (1-2 days)
   - Apple's Swift Tour: https://docs.swift.org/swift-book/

2. **SwiftUI Basics** (1-2 days)
   - Apple's SwiftUI Tutorials

3. **macOS App Development** (2-3 days)
   - Focus on menu bar apps
   - Learn about app lifecycle

### When You're Stuck
1. Read error message carefully
2. Check Xcode's error suggestion (often helpful)
3. Search error on Stack Overflow
4. Check Apple Developer Documentation
5. Ask for help with specific error message

---

## Timeline Estimate

### Conservative Timeline (For Learning While Building)
- **Phase 1:** 2-3 days (includes learning Xcode basics)
- **Phase 2:** 3-4 days (learning AVFoundation)
- **Phase 3:** 4-5 days (hotkey system is tricky)
- **Phase 4:** 5-7 days (Whisper.cpp integration is complex)
- **Phase 5:** 2-3 days
- **Phase 6:** 3-4 days (integration and testing)
- **Phase 7:** 3-4 days
- **Phase 8:** 3-5 days (code signing can be tricky)

**Total: 25-39 days** (5-8 weeks)

### Optimistic Timeline (If Experienced)
- **Phase 1:** 1 day
- **Phase 2:** 1-2 days
- **Phase 3:** 2-3 days
- **Phase 4:** 3-5 days
- **Phase 5:** 1 day
- **Phase 6:** 2 days
- **Phase 7:** 2 days
- **Phase 8:** 2-3 days

**Total: 14-19 days** (3-4 weeks)

---

## Risk Mitigation

### High-Risk Areas
1. **Whisper.cpp Integration** - Most complex part
   - Mitigation: Test standalone first, before integration
   - Have fallback: Use command-line Whisper if library integration fails

2. **Global Hotkey Reliability** - Can be finicky
   - Mitigation: Research existing libraries (e.g., MASShortcut)
   - Start with Carbon, fallback to CGEvent tap

3. **Auto-Paste Not Working** - App-specific issues
   - Mitigation: Test extensively in many apps
   - Document any apps where it doesn't work

4. **Model Download Fails** - Network or size issues
   - Mitigation: Add retry logic
   - Allow manual model installation

5. **Code Signing/Notarization** - Tedious and error-prone
   - Mitigation: Start this early, don't wait until the end
   - Test frequently on different Macs

---

## Success Metrics

### Phase Completion Criteria
Each phase is considered complete when:
- All deliverables are met
- All testing criteria pass
- Code is committed to git
- No known critical bugs
- Ready to build next phase on top

### Final Release Criteria
- All 8 phases complete
- Full end-to-end testing on 3+ different apps
- Tested on clean Mac (non-developer machine)
- Performance meets targets (<2× real-time)
- No critical bugs
- Code signed and notarized
- Documentation complete

---

## Next Steps

1. **Review this plan** - Make sure you understand each phase
2. **Set up development environment** - Follow setup guide above
3. **Start Phase 1** - Create basic menu bar app
4. **Test each phase thoroughly** - Don't skip to next phase
5. **Ask questions early** - Don't get stuck for hours

Remember: This is an aggressive project for someone new to Swift/macOS. Be patient with yourself, test frequently, and don't hesitate to ask for help on specific issues.
