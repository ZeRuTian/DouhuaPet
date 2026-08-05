# DouhuaPet 0.5.1 release checklist

## Completed

- [x] PNG frame-sequence renderer retired as the primary visual path.
- [x] One uninterrupted real-Douhua source shot selected for stable camera, full-body visibility, and natural micro-motion.
- [x] macOS Vision foreground segmentation validated on the full selected clip.
- [x] Fixed clip-wide crop and scale used; no per-frame recentering or whole-cat breathing transform.
- [x] 304 continuous samples encoded as 480×440, 30 FPS HEVC with alpha.
- [x] Audio and original background removed from the derived runtime asset.
- [x] AVQueuePlayer, AVPlayerLooper, and SKVideoNode integrated as the primary renderer.
- [x] Video timebase pauses during drag, app pause, hide, and lifecycle suspension.
- [x] Resting cat no longer slides horizontally when no valid walking footage exists.
- [x] Retired v2/v3/v4 animation frames and legacy static poses removed from the runtime bundle.
- [x] Loop endpoint selected by minimum later-pose difference; seam decoded and inspected on both sides.
- [x] Installed transparent desktop window inspected across more than one complete loop.
- [x] Runtime bundle contains one visual MOV and one non-rendered PNG hit mask.
- [x] 72/72 executable logic checks passed.
- [x] Swift warnings-as-errors build and XCTest-target compilation passed.
- [x] HEVC asset decodes without FFmpeg errors.
- [x] Release app built, packaged, ad-hoc signed, and strict signature verified.
- [x] Installed app is approximately 1.6 MB; ZIP is approximately 1.4 MB.
- [x] Short live sample is approximately 57 MB RSS and 4.5% CPU.
- [x] Foreground registration removes handheld translation while retaining local cat motion.
- [x] SceneKit semantic feline-rig runtime and USDZ validator compile and safely fall back when the production model is absent.
- [x] Installed version is 0.5.1 build 8.

## Before public distribution

- [ ] Obtain an unobstructed fixed-camera walking shot before restoring patrol movement.
- [ ] Capture compatible continuous stand, lie-down, sleep, wake, and petted shots before adding state switching.
- [ ] Run full XCTest and UI tests with complete Xcode.
- [ ] Run Instruments Energy, Time Profiler, Allocations, and Leaks.
- [ ] Complete dual-display, Stage Manager, and full-screen Space matrix.
- [ ] Complete two-hour MVP soak and eight-hour release soak.
- [ ] Decide Developer ID signing, notarization, and privacy statement.
