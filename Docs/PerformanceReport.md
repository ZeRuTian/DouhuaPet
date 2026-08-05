# DouhuaPet 0.5.1 verification report

Date: 2026-07-13

Machine: Apple Silicon, macOS 26.5.2, Swift 6.3.3 Command Line Tools

## Renderer and asset verification

- Primary renderer is `AVQueuePlayer + AVPlayerLooper + SKVideoNode`; the SpriteKit scene does not change visual PNG textures while live-video mode is available.
- Runtime video is HEVC with alpha, 480×440, 30 FPS, 10.133 seconds, 304 continuous source samples, approximately 1.29 MB.
- FFmpeg decoded the installed MOV from start to end with no errors.
- Alpha survived the HEVC round trip; decoded frames retain fully transparent background pixels and antialiased foreground edges.
- Vision segmentation was inspected at multiple source times. The clip-wide fixed crop preserves position and scale and avoids per-frame tracking jitter.
- A second Vision translation-registration pass now cancels handheld motion against a fixed foreground reference. Across 304 frames, alpha-centroid horizontal range fell from 34.93 px to 6.44 px and vertical range from 19.18 px to 3.29 px while head and tail articulation remained visible.
- A six-frame seam strip covering the last 0.33 seconds and first 0.33 seconds was inspected. The cat remains at the same scale and location, with no black/white frame or identity replacement.
- Fourteen one-second desktop captures across more than one complete loop confirmed real head, eye, ear, breathing, and tail changes in the installed transparent window.
- The retired v2/v3/v4 sequences are under `Docs/Art/AnimationSource/archive/` and are not copied into the app.
- The app now checks for the semantic-bone `douhua_rigged.usdz` contract before video startup. Missing or invalid 3D assets fail closed to the stabilized video; no partial model is presented.

## Build and logic verification

- `Scripts/test-logic.sh`: 72/72 executable checks passed.
- `swift build -Xswiftc -warnings-as-errors`: passed.
- `swift test`: application and XCTest targets compiled and linked successfully. This Command Line Tools-only environment still has no runnable `xctest` host.
- Release application build, ad-hoc signing, strict signature verification, and ZIP packaging: passed.
- Installed `Info.plist`: version 0.5.1, build 8.

## Runtime samples

Short local samples, not a substitute for Instruments or a long soak test:

- Installed app became visible within the normal launch sample window.
- Continuous 30 FPS live-video sample after 15 seconds: approximately 4.5% CPU.
- Resident memory after 15 seconds: approximately 57 MB RSS.
- Installed app: approximately 1.6 MB.
- ZIP archive: approximately 1.4 MB.
- Runtime resource count: one MOV plus one PNG alpha hit mask; the hit mask is not rendered.

These samples meet the 0.5 PRD targets of under 8% continuous-playback CPU, under 150 MB RSS, and under 10 MB installed size. The former under-2% quiet CPU target applied to low-rate PNG animation and is no longer the correct budget for continuous hardware video decoding.

## Privacy/package checks

- The application bundle contains no original JPG, JPEG, MP4, or unprocessed owner video.
- The MOV is a silent, background-free, fixed-crop derivative containing only Douhua's foreground.
- The application performs no network work and requests no Accessibility, Input Monitoring, Screen Recording, camera, or microphone permission.

## Still requiring the matching environment

- Full Xcode XCTest/UI Test execution.
- Instruments Energy Log, Time Profiler, Allocations, and Leaks.
- Dual-display hot-plug, cross-scale, Stage Manager, and full-screen Space matrix.
- Two-hour MVP soak and eight-hour release-candidate soak.
- New fixed-camera walking footage before any realistic patrol implementation.
