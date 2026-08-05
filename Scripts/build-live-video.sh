#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SOURCE="../豆花照片视频/19dc70d8395691bfeb67796d932af201.mp4"
BUILD="$ROOT/.build/live-video-v5/rebuild"
OUTPUT="$ROOT/Sources/DouhuaPet/Resources/Animations/Douhua/v5-live"

rm -rf "$BUILD"
mkdir -p "$BUILD/frames" "$BUILD/stabilized-frames" "$OUTPUT"

# The 12-second extraction gives the seam search room. The final 304 frames
# end at the nearest later pose to frame zero, producing a clean 10.13 s loop.
xcrun swift Scripts/BuildLiveVideoAssets.swift "$SOURCE" "$BUILD/frames" 0 12 30
xcrun swift Scripts/StabilizeTransparentFrames.swift \
    "$BUILD/frames" \
    "$BUILD/stabilized-frames" \
    304
ffmpeg -y -hide_banner -loglevel error \
    -framerate 30 \
    -i "$BUILD/stabilized-frames/frame_%05d.png" \
    -frames:v 304 \
    -c:v hevc_videotoolbox \
    -alpha_quality 0.9 \
    -q:v 65 \
    -pix_fmt bgra \
    -tag:v hvc1 \
    "$OUTPUT/douhua_live_idle.mov"
cp "$BUILD/stabilized-frames/frame_00000.png" "$OUTPUT/douhua_live_hit.png"

ffmpeg -v error -i "$OUTPUT/douhua_live_idle.mov" -f null -
ffprobe -v error \
    -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate \
    -of compact=p=0 \
    "$OUTPUT/douhua_live_idle.mov"
