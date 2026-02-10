# loom-go

A Loom-like screen recorder for macOS built with Hammerspoon. Records screen, webcam, and audio with instant shareable URLs via Google Cloud Storage.

## Features

- 🚀 **Instant URLs**: Get a shareable link the moment you stop recording (HTML placeholder while processing)
- 📹 **Screen Recording**: Capture your screen with cursor and clicks
- 📷 **Webcam Recording**: Optional circular webcam overlay (Loom-style)
- 🎙️ **Crystal Clear Audio**: Distortion-free audio using macOS Core Audio (sox)
- 🎯 **Perfect Sync**: Audio and video perfectly synchronized every time
- 🎬 **Composite Video**: Automatic final video with webcam overlay
- 🗂️ **Raw Files**: Get separate screen.mp4, webcam.mp4, and audio_raw.wav for editing
- ⭕ **Circular Webcam**: Beautiful circular crop (or rectangular if you prefer)
- 📍 **Webcam Positioning**: Bottom-right, bottom-left, top-right, or top-left
- 📏 **Webcam Sizing**: Adjust size from 15% to 30% of screen width
- 🎚️ **Audio Gain Control**: Adjust microphone volume (30% to 150%)
- ☁️ **Auto-upload to GCS**: Automatically upload to your Google Cloud Storage bucket
- 🔗 **Public URLs**: Shareable links anyone can access (no login required)
- 🎛️ **Menu Bar Interface**: All settings accessible from menu bar
- ⌨️ **Keyboard Shortcut**: `Cmd+Option+S` to start/stop recording
- 📺 **Multi-display Support**: Select any screen to record
- 🎥 **Camera Selection**: Choose from available webcams or disable
- 🎤 **Audio Device Selection**: Pick your preferred microphone

## Why This Exists

Unlike Loom or other screen recorders, **loom-go** gives you:
- **Instant sharing**: URL in clipboard immediately (HTML placeholder while processing)
- **Perfect audio**: No distortion or crackling (uses Core Audio, not FFmpeg AVFoundation)
- **Perfect sync**: Audio/video always in sync (automatic offset trimming)
- **Composite + Raw Files**: Get the polished video PLUS separate screen, webcam, and audio files
- **Full Customization**: Position and size your webcam overlay exactly how you want
- **Your own storage**: Upload to your Google Cloud Storage bucket
- **No subscription**: Use your own cloud storage, pay only for what you use
- **Full control**: Customize everything - audio gain, positioning, upload behavior
- **Privacy**: Your data stays on your machine and your cloud storage

## Quick Start

### 1. Install Dependencies

```bash
# Install Hammerspoon
brew install --cask hammerspoon

# Install FFmpeg (for video recording)
brew install ffmpeg

# Install sox (for audio recording - critical for quality!)
brew install sox

# Install Google Cloud SDK (for uploads)
brew install --cask google-cloud-sdk
```

### 2. Set Up loom-go

```bash
cd ~/Code
git clone <repository-url> loom-go
```

Add to `~/.hammerspoon/init.lua`:
```lua
dofile(os.getenv("HOME") .. "/Code/loom-go/init.lua")
```

Reload Hammerspoon: Menu bar → Hammerspoon → Reload Config

### 3. Grant Permissions

1. **System Settings → Privacy & Security → Screen Recording** → Enable Hammerspoon
2. **System Settings → Privacy & Security → Camera** → Enable Hammerspoon  
3. **System Settings → Privacy & Security → Microphone** → Enable Hammerspoon

### 4. Configure GCS (Optional but Recommended)

```bash
# Create bucket
gsutil mb -l us-central1 gs://your-recordings

# Make bucket public for easy sharing
gsutil iam ch allUsers:objectViewer gs://your-recordings
```

In menu bar: 📹 → "☁️ GCS Bucket" → Enter `your-recordings`

## Usage

### Recording

**Start:** Press `Cmd+Option+S` or click 📹 → "⏺️ Start Recording"  
**Stop:** Press `Cmd+Option+S` again or click 📹 → "⏹️ Stop Recording"

You'll get:
1. **⏺️ Recording started** alert
2. **⏹️ Processing... URL in clipboard** - instant shareable link (shows HTML loading page)
3. **✅ Video uploaded!** - real video has replaced the placeholder

### Device Selection

**Screen:** 📹 → "📺 Screen" → Pick your display  
**Camera:** 📹 → "📷 Camera" → Pick webcam or "No Camera"  
**Microphone:** 📹 → "🎤 Audio" → Pick your mic  
**Audio Gain:** 📹 → "🎚️ Audio Gain" → 30% to 150% (default: 50%)

### Webcam Settings

**Position:** 📹 → "📐 Webcam Position" → Bottom-right, bottom-left, top-right, top-left  
**Size:** 📹 → "📏 Webcam Size" → Small (15%), Medium (20%), Large (25%), Extra Large (30%)  
**Circle Crop:** 📹 → "⭕ Crop Webcam to Circle" → Toggle circular vs rectangular

### Quick URL Feature

When you stop recording, you **immediately** get a shareable URL:
- Opens an HTML page with a loading spinner and "Video processing..." message
- Page auto-refreshes every 5 seconds
- Once composite is ready, video replaces the placeholder automatically
- Share the link right away - viewers see the loading page, then the video appears!

### File Organization

Recordings saved to `~/Desktop/ScreenRecordings/`:

```
recording_2026-02-10_14-30-25/
├── screen.mp4         # Screen recording with synced audio
├── webcam.mp4         # Raw webcam video
├── audio_raw.wav      # Raw audio (for debugging)
└── composite.mp4      # Final video with webcam overlay ⭐
```

**composite.mp4** is your shareable video - screen + webcam overlay + audio, all perfectly synced.

## Technical Details

### Audio Quality

**Why sox instead of FFmpeg?**
- FFmpeg's AVFoundation audio has severe distortion/crackling issues on macOS
- sox uses macOS Core Audio API directly - crystal clear audio
- Loom and OBS also avoid FFmpeg's AVFoundation audio for this reason

### Audio/Video Sync

**Perfect sync every time:**
1. Screen video and audio recorded separately (FFmpeg + sox)
2. After recording stops, durations are compared
3. Whichever started earlier gets trimmed by the exact offset
4. Trimmed files muxed together - always in sync (within 50ms threshold)

### Instant URLs

**How "Quick URL" works:**
1. HTML placeholder uploaded to GCS immediately when recording starts (background, non-blocking)
2. URL copied to clipboard as soon as placeholder upload completes
3. Placeholder shows beautiful loading page with auto-refresh
4. Real composite video uploaded after creation and overwrites placeholder
5. No downtime - viewers see loading page, then video seamlessly appears

## Troubleshooting

### Audio Distortion
- **Solution**: Make sure sox is installed: `brew install sox`
- The script uses sox (not FFmpeg) specifically to avoid audio issues

### Out of Sync Audio/Video
- Should be automatic now with offset trimming
- Check Console logs (📹 → Console) for "Duration difference" value
- If consistently out of sync, report an issue with logs

### No Audio in Recording
- Check microphone permissions: System Settings → Privacy & Security → Microphone → Hammerspoon
- Verify sox is installed: `which rec` should return `/opt/homebrew/bin/rec`
- Check menu bar: 📹 → "🎤 Audio" should show your mic

### FFmpeg Not Found

```bash
which ffmpeg  # Should return /opt/homebrew/bin/ffmpeg
brew install ffmpeg
```

### No Cameras Detected

1. Grant camera permission: System Settings → Privacy & Security → Camera → Hammerspoon
2. Test in Photo Booth or FaceTime
3. Click 📹 → "🔄 Refresh Devices"

### Upload Fails

```bash
# Authenticate with Google Cloud
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Verify bucket exists
gsutil ls gs://your-bucket-name

# Test upload
echo "test" > test.txt
gsutil cp test.txt gs://your-bucket-name/
```

## Advanced Configuration

### Change Recording Location

Edit `init.lua`:
```lua
local recordingDirectory = os.getenv("HOME") .. "/Desktop/ScreenRecordings"
-- Change to your preferred location
```

### Adjust Video Quality

Edit FFmpeg args in `init.lua`:
```lua
"-crf", "23",           -- Lower = better quality (18 is high, 28 is low)
"-preset", "veryfast",  -- Options: ultrafast, veryfast, fast, medium, slow
```

### Disable Quick URL Feature

In menu bar: 📹 → "🚀 Quick URL" → Uncheck  
(URL will only be generated after composite is fully created and uploaded)

## Use Cases

- **Tutorials**: Record code walkthroughs with webcam commentary
- **Bug Reports**: Show issues with narration, share instant link with team
- **Code Reviews**: Record your review with annotations
- **Demos**: Present features to stakeholders with your face
- **Documentation**: Create video docs for internal tools

## Privacy & Security

- All recordings stored locally first
- GCS upload is optional and opt-in
- You control your own cloud storage
- Public URLs optional (you can keep bucket private)

⚠️ **Warning**: If bucket is public, anyone with URL can view recordings. Don't record sensitive info with public buckets.

## Requirements

- macOS 12.0+
- Hammerspoon
- FFmpeg (`brew install ffmpeg`)
- sox (`brew install sox`) - **Critical for audio quality!**
- Google Cloud SDK (`brew install --cask google-cloud-sdk`) - Optional, for uploads
- Permissions: Screen Recording, Camera, Microphone

## Beta Status

This is a **beta** version. Core functionality works well:
- ✅ Recording (screen + webcam + audio)
- ✅ Audio quality (no distortion)
- ✅ Audio/video sync
- ✅ Composite creation with circular webcam
- ✅ Instant URLs with HTML placeholder
- ✅ GCS upload with public URLs

Known limitations:
- Audio device selection menu shows devices but sox uses macOS default input (change in System Settings)
- Limited error recovery (check Console for errors)

## License

MIT License - Feel free to modify and use as needed.

## Credits

Built with [Hammerspoon](https://www.hammerspoon.org/), inspired by Loom and wispr-go.

---

**Questions?** Open an issue or submit a PR!
