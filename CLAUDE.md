# CinematiCam - Cinematic Camera for TikTok Creators

---

## ⚠️ STOP AND READ THIS FIRST ⚠️

### THE #1 RULE: ONE FEATURE AT A TIME

**This project uses incremental development. You must follow these rules:**

1. **ONLY implement ONE small feature per response**
2. **NEVER combine multiple features into one implementation**
3. **NEVER write more than ~100 lines of new code at once**
4. **ALWAYS wait for user to test and confirm before moving on**
5. **ALWAYS end your response with "Test this and let me know if it works"**

---

### What Counts as ONE Feature

✅ **Correct (small, testable):**
- Request camera permission and show alert if denied
- Add a button that prints to console when tapped
- Display camera preview on screen (no buttons, just the preview)
- Create a single filter that warms the image

❌ **Wrong (too much at once):**
- Set up camera with preview, buttons, and recording
- Add all 5 filters with the carousel UI
- Implement depth capture with bokeh effect and blur slider
- Create the entire settings screen

---

### Required Response Format

Every response MUST follow this format:

```
**Implementing:** [one specific feature]

**Files I'll touch:**
- [filename] (create/modify)

**What this does:** [1-2 sentences]

[code changes]

**How to test:** [specific steps]

**Expected result:** [what user should see]

Test this and let me know if it works.
```

---

### When User Reports a Bug

1. Ask ONE clarifying question if needed
2. Identify the likely cause
3. Make the SMALLEST fix possible
4. Do NOT add other improvements while fixing
5. Ask user to test the fix

---

### Forbidden Behaviors

🚫 "While I'm at it, I'll also..."
🚫 "I've implemented X, Y, and Z..."
🚫 "Here's the complete [feature]..."
🚫 "I've added some improvements..."
🚫 "I also noticed [unrelated thing] so I fixed it..."
🚫 Adding TODO comments for future features
🚫 Creating files that aren't immediately needed
🚫 Refactoring working code without being asked

---

## Project Overview

**CinematiCam** solves a critical gap in the market for TikTok and short-form video creators.

---

### The Problem: Two Broken Workflows

Creators today are forced to choose between two broken options:

**Option 1: iPhone Native Camera App**
- ✅ Has Cinematic Mode with beautiful bokeh (background blur)
- ✅ Professional depth-of-field effect that makes you stand out
- ❌ **NO start/stop recording** — if you pause and resume, it creates SEPARATE video files
- ❌ **NO filters** — no TikTok-style color effects
- ❌ Painful workflow: Record clip 1 → Stop → Record clip 2 → Stop → Record clip 3 → Now you have 3 separate files → Open iMovie/CapCut → Import all clips → Stitch together → Export → Finally upload to TikTok
- ❌ This workflow takes 10+ extra minutes per video

**Option 2: TikTok Native Camera**
- ✅ Has start/stop recording that creates ONE continuous clip
- ✅ Has real-time filters and effects creators love
- ✅ Seamless workflow: Record → Pause → Record more → Stop → Post
- ❌ **NO cinematic mode / NO bokeh / NO portrait video**
- ❌ **NO depth-based background blur whatsoever**
- ❌ Videos look flat and amateur compared to iPhone Cinematic Mode
- ❌ You blend in with everyone else instead of standing out

**The Gap:** 
There is currently NO app that combines:
1. iPhone's cinematic bokeh/depth blur recording
2. TikTok's start/stop recording (single continuous clip)
3. TikTok-style real-time filters

Creators must choose: professional-looking bokeh with painful workflow OR easy workflow with flat, non-cinematic video.

---

### The Solution: CinematiCam

**CinematiCam is the ONLY app that combines the best of both worlds.**

| Feature | iPhone Camera | TikTok Camera | CinematiCam |
|---------|---------------|---------------|-------------|
| Cinematic bokeh (depth blur) | ✅ Yes | ❌ No | ✅ Yes |
| Start/stop → ONE clip | ❌ No (creates multiple files) | ✅ Yes | ✅ Yes |
| Real-time filters | ❌ No | ✅ Yes | ✅ Yes |
| 9:16 vertical optimized | ❌ No | ✅ Yes | ✅ Yes |
| Saves to camera roll | ✅ Yes | ❌ No (stuck in TikTok) | ✅ Yes |

**CinematiCam Workflow:**
1. Open app → See yourself with live bokeh effect (background blurred)
2. Swipe to choose a filter (Warm, Cool, Vintage, etc.)
3. Tap record → Perform → Tap to pause → Tap to resume → Tap to stop
4. **ONE video file** with bokeh + filter baked in, saved to camera roll
5. Upload directly to TikTok/Instagram/YouTube

**Time saved:** What used to take 10+ minutes of post-production now takes 0 minutes.

---

### Core Features (MVP)

1. **Real-time cinematic bokeh** — Background blur using iPhone's depth camera, just like iPhone's Cinematic Mode
2. **Start/stop recording** — Pause and resume recording, outputs ONE continuous video file (not multiple clips)
3. **TikTok-style filters** — Real-time color filters applied during recording (Warm, Cool, Vintage, B&W, Vivid, etc.)
4. **9:16 vertical video** — Optimized for TikTok, Reels, Shorts
5. **Save to camera roll** — One tap export, ready to upload anywhere

---

### Target Users

- TikTok content creators who want professional-looking video without complex editing
- Instagram Reels creators
- YouTube Shorts creators  
- UGC (User Generated Content) creators
- Anyone frustrated by the current broken workflows

### Why They'll Pay

- Creators already invest in ring lights ($30-100), microphones ($50-200), and editing apps ($10-100/year)
- Cinematic bokeh makes content look dramatically more professional
- Time saved on every video = more content created = faster growth
- Standing out visually = more views, more followers, more income
- One-time $9.99-$14.99 pays for itself after saving time on just 2-3 videos

---

## Tech Stack

| Component | Technology |
|-----------|------------|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Camera Preview | UIKit (UIViewRepresentable) |
| Camera | AVFoundation |
| Depth | AVDepthData |
| Filters | Core Image (CIFilter) |
| Video Recording | AVAssetWriter |
| Min iOS | 16.0 |

---

## Step-by-Step Build Order

Build in this EXACT order. Each step = one feature.

### Phase 1: Camera Basics

| Step | Feature | Verification |
|------|---------|--------------|
| 1 | Create empty Xcode project, launches without crash | App shows blank screen |
| 2 | Add camera permission to Info.plist | No visible change yet |
| 3 | Create PermissionsManager, request camera on launch | Permission dialog appears |
| 4 | Handle permission denied (show alert) | Denying shows "Enable in Settings" alert |
| 5 | Create CameraManager with AVCaptureSession setup | Console: "Session configured" |
| 6 | Start capture session running | Console: "Session running" |
| 7 | Create CameraPreviewView (UIViewRepresentable) | Camera feed visible on screen |
| 8 | Make preview fill screen (9:16 or full bleed) | No black bars, fills screen |
| 9 | Add flip camera button (icon only, no function) | Button visible in corner |
| 10 | Flip button switches front/back camera | Tapping switches camera |
| 11 | Add flash toggle button (icon only) | Button visible |
| 12 | Flash button toggles torch | Torch turns on/off |
| 13 | Add haptic feedback to buttons | Feel haptic on tap |

### Phase 2: Depth Capture

| Step | Feature | Verification |
|------|---------|--------------|
| 14 | Switch to builtInDualWideCamera | Console: "Using dual camera" |
| 15 | Add AVCaptureDepthDataOutput | Console: "Depth output added" |
| 16 | Set up output synchronizer | Console: "Synchronizer ready" |
| 17 | Receive depth data, log to console | Console: "Depth frame received" (repeating) |

### Phase 3: Bokeh Effect

| Step | Feature | Verification |
|------|---------|--------------|
| 20 | Create DepthMaskGenerator class | Console: "Mask generated" |
| 21 | Create BokehRenderer with basic blur | Background appears blurry |
| 22 | Apply bokeh to live preview | Live preview has depth blur |
| 23 | Add blur intensity slider UI | Slider visible on screen |
| 24 | Connect slider to blur amount | Moving slider changes blur |
| 25 | Add tap-to-focus gesture | Tapping changes focus plane |
| 26 | Smooth depth edge transitions | Blur edges look natural |

### Phase 4: Recording

| Step | Feature | Verification |
|------|---------|--------------|
| 27 | Create VideoRecorder class shell | Console: "Recorder initialized" |
| 28 | Configure AVAssetWriter for video | Console: "Writer configured" |
| 29 | Add record button UI (not functional) | Red button visible |
| 30 | Record button toggles state visually | Button changes appearance |
| 31 | Start/stop actually writes video file | File created in temp directory |
| 32 | Verify video file is playable | Can open file in Finder, plays |
| 33 | Record processed frames (with bokeh) | Recorded video has blur effect |
| 34 | Add microphone permission request | Mic permission dialog appears |
| 35 | Add audio input to capture session | Console: "Audio input added" |
| 36 | Write audio to video file | Recorded video has sound |
| 37 | Add recording timer display | Timer shows during recording |
| 38 | Add red dot recording indicator | Red dot pulses while recording |

### Phase 5: Save to Camera Roll

| Step | Feature | Verification |
|------|---------|--------------|
| 39 | Add photo library permission to Info.plist | No visible change |
| 40 | Request photo library permission | Permission dialog appears |
| 41 | Save recorded video to camera roll | Video appears in Photos app |
| 42 | Show "Saved!" confirmation | Toast/alert appears after save |
| 43 | Add thumbnail preview after recording | Small thumbnail visible |
| 44 | Add delete button to discard video | Can delete without saving |
| 45 | Handle interruptions (background, calls) | Recording saves if interrupted |

### Phase 6: Filters

| Step | Feature | Verification |
|------|---------|--------------|
| 46 | Create Filter protocol | Code compiles |
| 47 | Create FilterEngine class | Code compiles |
| 48 | Create NaturalFilter (identity/passthrough) | Console: "Filter applied: Natural" |
| 49 | Create WarmFilter | Console: "Filter applied: Warm" |
| 50 | Apply filter to live preview | Preview shows warm tint |
| 51 | Create CoolFilter | Preview can show cool tint |
| 52 | Add filter carousel UI (text labels) | Row of filter names visible |
| 53 | Tapping filter name changes filter | Preview changes when tapped |
| 54 | Add haptic when filter changes | Feel haptic on selection |
| 55 | Create VintageFilter | Vintage look available |
| 56 | Create BWFilter (black & white) | B&W option available |
| 57 | Create VividFilter | Vivid option available |
| 58 | Add filter thumbnail previews | Carousel shows image previews |
| 59 | Persist selected filter (UserDefaults) | Filter remembered after restart |

### Phase 7: Effects in Recording

| Step | Feature | Verification |
|------|---------|--------------|
| 60 | Verify filter is recorded in video | Playback video has filter |
| 61 | Verify bokeh + filter combined | Both effects in recorded video |

### Phase 8: Polish

| Step | Feature | Verification |
|------|---------|--------------|
| 62 | Improve record button animation | Smooth state transition |
| 63 | Hide UI during recording | Controls fade out when recording |
| 64 | Add settings gear icon | Icon visible |
| 65 | Create empty settings sheet | Tapping gear opens sheet |
| 66 | Add video quality setting | Can choose 1080p/720p |
| 67 | Add grid overlay option | Grid toggles on/off |
| 68 | Add app icon | Icon shows on home screen |
| 69 | Final testing and bug fixes | Everything works |

---

## File Structure

```
CinematiCam/
├── CinematiCamApp.swift
├── ContentView.swift
├── Managers/
│   ├── CameraManager.swift
│   ├── PermissionsManager.swift
│   └── VideoRecorder.swift
├── Views/
│   ├── CameraView.swift
│   ├── CameraPreviewView.swift
│   ├── RecordButton.swift
│   ├── FilterCarousel.swift
│   └── SettingsView.swift
├── Processing/
│   ├── DepthProcessor.swift
│   ├── BokehRenderer.swift
│   └── FilterEngine.swift
├── Filters/
│   ├── Filter.swift (protocol)
│   ├── NaturalFilter.swift
│   ├── WarmFilter.swift
│   ├── CoolFilter.swift
│   ├── VintageFilter.swift
│   ├── BWFilter.swift
│   └── VividFilter.swift
└── Utilities/
    └── HapticFeedback.swift
```

---

## Technical Notes

### Camera Setup Order
1. Request permission
2. Create AVCaptureSession
3. Add video input
4. Add video output
5. Add depth output (if available)
6. Add audio input
7. Start session on background thread

### Frame Processing Pipeline
```
Raw Frame → Bokeh Blur → Color Filter → Display/Record
```

### Video Output Specs
- Resolution: 1080x1920 (9:16)
- Frame rate: 30 fps
- Video codec: H.264
- Audio codec: AAC
- Container: MOV

---

## Device Requirements

- **Must have**: Physical iPhone (no simulator)
- **Ideal**: iPhone 12+ (best depth quality)
- **Minimum**: iPhone X (limited depth)

---

## Remember

**Before every implementation, state:**
1. The ONE feature you're implementing
2. The file(s) you'll touch
3. How the user will test it

**After every implementation, say:**
"Test this and let me know if it works."

**NEVER proceed to the next feature until user confirms the current one works.**
