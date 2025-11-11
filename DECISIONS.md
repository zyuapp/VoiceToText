# Implementation Decisions

Decisions made during PRD clarification to guide v1 implementation.

---

## 1. Maximum Recording Duration and Timeout

**Decision:**
- Hard cap: 60 seconds per capture
- Auto-stop trigger: 1.5 seconds of continuous silence
- Whichever comes first
- Immediate transcription after stop

---

## 2. Default Hotkey on First Launch

**Decision:**
- **Default:** Hold Right Command (⌘) to record
- User-configurable in Preferences
- Hotkey held = recording active, release = stop and transcribe

---

## 3. Whisper.cpp Integration

**Decision:**
- **v1:** CLI subprocess approach
  - Simpler implementation
  - Stable and well-tested
  - Easy to ship and debug
- **v2 (future):** Explore in-process library integration to reduce latency

---

## 4. Error Feedback Mechanism

**Decision:**
- **Primary:** Non-blocking macOS notification
  - Brief error message
  - "View logs" action button
- **Visual:** Menu bar icon pulses red on failure
- **No modal alerts** (non-intrusive)

---

## 5. Clipboard Overwrite Behavior

**Decision:**
- **Default mode:** Overwrite clipboard + auto-paste (⌘V)
- **Preferences toggles:**
  - "Copy only (no paste)" - just updates clipboard
  - "Do not overwrite clipboard" - paste directly without clipboard modification

---

## 6. Model Download Source and Fallback

**Decision:**
- **Primary source:** Official ggml-org whisper.cpp model via repo's download script
- **Fallback:** Mirrored model on Hugging Face
- **Verification:** SHA256 checksum before use
- **Failure handling:**
  - If both sources fail: prompt user to retry or select local model file
  - No bundled model in initial `.app` (download on first launch)

---

## Additional Clarifications

### Audio Management
- Temporary WAV files stored in app's temp directory
- 16 kHz mono format
- Cleanup: Delete immediately after successful transcription
- On error: Keep for debugging (include path in error notification)

### Menu Bar States
- **Idle:** Standard microphone icon
- **Recording:** Animated pulsing icon
- **Transcribing:** Spinner/progress indicator
- **Error:** Red pulse, returns to idle after 3 seconds

### Permissions
- Request on first launch with clear explanation
- If denied: Show instructions in notification with System Preferences deep link

### Performance Target
- 1× real-time for audio ≤10 seconds
- Best effort for 10-60 second audio (expect 1-2× real-time on M1/M2)

---

**Date:** 2025-11-10
**Version:** v1 implementation scope
