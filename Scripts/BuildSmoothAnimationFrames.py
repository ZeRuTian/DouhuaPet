#!/usr/bin/env python3
"""Build Douhua v3's single-image, high-frame-rate animation package.

The v2 runtime cross-faded two complete photographs.  Different fur edges and
exposure made that look like flashing.  This builder moves interpolation
offline: large body motions use generated biomechanical midpoint poses, small
motions use optical-flow in-betweens, and the app displays exactly one finished
RGBA frame at any instant.
"""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from statistics import median

from PIL import Image, ImageEnhance


ROOT = Path(__file__).resolve().parent.parent
V2_ROOT = ROOT / "Sources/DouhuaPet/Resources/Animations/Douhua/v2"
OUTPUT_ROOT = ROOT / "Sources/DouhuaPet/Resources/Animations/Douhua/v3-smooth"
MIDPOINT_ROOT = ROOT / "Docs/Art/AnimationSource/v3-inbetweens"
PREPARE_SCRIPT = ROOT / "Scripts/PrepareAnimationSheets.py"
CANVAS_SIZE = (480, 440)
BASELINE = 424
ALPHA_THRESHOLD = 2
MINIMUM_MARGIN = 12

LOOPS = {"walk_loop", "observe_idle", "loaf_breathe", "sleep_breathe"}
MIDPOINT_CLIPS = {
    "walk_loop",
    "observe_to_walk",
    "walk_to_observe",
    "observe_to_loaf",
    "loaf_to_observe",
    "loaf_to_sleep",
    "sleep_to_loaf",
    "pet_observe",
    "pet_loaf",
    "pet_sleep",
}
ENDPOINT_LOOPS = {
    "pet_observe": ("observe_idle", "observe_idle"),
    "pet_loaf": ("loaf_breathe", "loaf_breathe"),
    "pet_sleep": ("sleep_breathe", "sleep_breathe"),
    "observe_to_walk": ("observe_idle", "walk_loop"),
    "walk_to_observe": ("walk_loop", "observe_idle"),
    "observe_to_loaf": ("observe_idle", "loaf_breathe"),
    "loaf_to_observe": ("loaf_breathe", "observe_idle"),
    "loaf_to_sleep": ("loaf_breathe", "sleep_breathe"),
    "sleep_to_loaf": ("sleep_breathe", "loaf_breathe"),
}
CLIP_ORDER = [
    "walk_loop",
    "observe_idle",
    "loaf_breathe",
    "sleep_breathe",
    "pet_observe",
    "pet_loaf",
    "pet_sleep",
    "observe_to_walk",
    "walk_to_observe",
    "observe_to_loaf",
    "loaf_to_observe",
    "loaf_to_sleep",
    "sleep_to_loaf",
]

SOURCE_DURATIONS = {
    "observe_idle": [1.8, 0.11, 0.11, 0.11, 0.72, 0.11, 0.11, 2.2],
    "walk_loop": [0.095] * 8,
    "observe_to_walk": [0.12, 0.105, 0.095, 0.085, 0.08, 0.075, 0.065, 0.06],
    "walk_to_observe": [0.065, 0.075, 0.08, 0.085, 0.095, 0.11, 0.13, 0.15],
    "loaf_breathe": [0.30] * 8,
    "sleep_breathe": [0.35] * 8,
    "pet_observe": [0.11] * 8,
    "pet_loaf": [0.11] * 8,
    "pet_sleep": [0.125] * 8,
    "observe_to_loaf": [0.13, 0.12, 0.11, 0.10, 0.10, 0.11, 0.13, 0.17],
    "loaf_to_observe": [0.16, 0.13, 0.11, 0.10, 0.09, 0.09, 0.10, 0.13],
    "loaf_to_sleep": [0.18, 0.16, 0.14, 0.13, 0.13, 0.14, 0.17, 0.22],
    "sleep_to_loaf": [0.18, 0.15, 0.13, 0.11, 0.10, 0.10, 0.12, 0.16],
}


class BuildError(RuntimeError):
    pass


def alpha_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value >= ALPHA_THRESHOLD else 0)
    bounds = mask.getbbox()
    if bounds is None:
        raise BuildError("empty animation frame")
    return bounds


def frame_path(root: Path, clip: str, index: int) -> Path:
    return root / clip / f"douhua_{clip}_{index:02d}.png"


def load_rgba(path: Path) -> Image.Image:
    if not path.is_file():
        raise BuildError(f"missing frame: {path}")
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    if image.size != CANVAS_SIZE:
        raise BuildError(f"unexpected frame dimensions for {path}: {image.size}")
    return image


def premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Resize without pulling transparent RGB into Douhua's fur edge."""
    rgba = image.convert("RGBA")
    pixels = list(rgba.getdata())
    premultiplied = Image.new("RGBA", rgba.size)
    premultiplied.putdata(
        [
            (
                round(red * alpha / 255),
                round(green * alpha / 255),
                round(blue * alpha / 255),
                alpha,
            )
            for red, green, blue, alpha in pixels
        ]
    )
    resized = premultiplied.resize(size, Image.Resampling.LANCZOS)
    output = []
    for red, green, blue, alpha in resized.getdata():
        if alpha < ALPHA_THRESHOLD:
            output.append((0, 0, 0, 0))
        else:
            scale = 255 / alpha
            output.append(
                (
                    min(255, round(red * scale)),
                    min(255, round(green * scale)),
                    min(255, round(blue * scale)),
                    alpha,
                )
            )
    result = Image.new("RGBA", size)
    result.putdata(output)
    return result


def fur_luminance(image: Image.Image) -> float:
    """Median mid-tone luminance, excluding white chest and transparent edge."""
    samples: list[float] = []
    for red, green, blue, alpha in image.getdata():
        if alpha < 220:
            continue
        luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if 42 <= luminance <= 205:
            samples.append(luminance)
    return float(median(samples)) if samples else 128.0


def normalize_midpoint(midpoint: Image.Image, before: Image.Image, after: Image.Image) -> Image.Image:
    mid_bounds = alpha_bounds(midpoint)
    before_bounds = alpha_bounds(before)
    after_bounds = alpha_bounds(after)
    crop = midpoint.crop(mid_bounds)

    def metric(bounds: tuple[int, int, int, int]) -> float:
        return math.sqrt((bounds[2] - bounds[0]) * (bounds[3] - bounds[1]))

    target_metric = (metric(before_bounds) + metric(after_bounds)) / 2
    scale = target_metric / metric(mid_bounds)
    scale = min(
        scale,
        (CANVAS_SIZE[0] - 2 * MINIMUM_MARGIN) / crop.width,
        (CANVAS_SIZE[1] - 2 * MINIMUM_MARGIN) / crop.height,
    )
    width = max(1, round(crop.width * scale))
    height = max(1, round(crop.height * scale))
    resized = premultiplied_resize(crop, (width, height))

    target_luminance = (fur_luminance(before) + fur_luminance(after)) / 2
    gain = min(1.12, max(0.88, target_luminance / max(fur_luminance(resized), 1)))
    alpha = resized.getchannel("A")
    resized = ImageEnhance.Brightness(resized.convert("RGB")).enhance(gain).convert("RGBA")
    resized.putalpha(alpha)

    before_center = (before_bounds[0] + before_bounds[2]) / 2
    after_center = (after_bounds[0] + after_bounds[2]) / 2
    center_x = (before_center + after_center) / 2
    x = round(center_x - width / 2)
    x = min(max(x, MINIMUM_MARGIN), CANVAS_SIZE[0] - MINIMUM_MARGIN - width)
    y = BASELINE - height
    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(resized, (x, y))
    return canvas


def prepare_midpoints(work_root: Path) -> Path:
    output = work_root / "prepared-midpoints"
    command = [sys.executable, str(PREPARE_SCRIPT), "--output-root", str(output)]
    for clip in sorted(MIDPOINT_CLIPS):
        sheet = MIDPOINT_ROOT / f"{clip}_midpoints.png"
        if not sheet.is_file():
            raise BuildError(f"missing midpoint sheet: {sheet}")
        command.extend(["--clip", f"{clip}={sheet}"])
    subprocess.run(command, check=True, cwd=ROOT)
    return output


def write_key_sequence(clip: str, midpoint_root: Path, destination: Path) -> tuple[int, int]:
    originals = [load_rgba(frame_path(V2_ROOT, clip, index)) for index in range(8)]
    destination.mkdir(parents=True, exist_ok=True)

    if clip in MIDPOINT_CLIPS:
        midpoints = [
            normalize_midpoint(
                load_rgba(frame_path(midpoint_root, clip, index)),
                originals[index],
                originals[(index + 1) % 8],
            )
            for index in range(8)
        ]
        keys: list[Image.Image] = []
        for index, original in enumerate(originals):
            keys.append(original)
            if clip in LOOPS or index < 7:
                keys.append(midpoints[index])
        source_fps, factor = 15, 1
    else:
        keys = originals
        source_fps = 10
        factor = 3 if clip == "observe_idle" else 6

    for index, image in enumerate(keys):
        image.save(destination / f"key_{index:03d}.png", optimize=True)

    if clip in MIDPOINT_CLIPS:
        output_count = len(keys)
    elif clip in LOOPS:
        # Optical flow needs future samples. They are context only and are not
        # emitted, so the loop still ends immediately before the first pose.
        keys[0].save(destination / f"key_{len(keys):03d}.png", optimize=True)
        keys[1].save(destination / f"key_{len(keys) + 1:03d}.png", optimize=True)
        output_count = len(keys) * factor
    else:
        keys[-1].save(destination / f"key_{len(keys):03d}.png", optimize=True)
        keys[-1].save(destination / f"key_{len(keys) + 1:03d}.png", optimize=True)
        output_count = (len(keys) - 1) * factor + 1
    return source_fps, output_count


def interpolate(clip: str, key_root: Path, destination: Path, source_fps: int, output_count: int) -> None:
    if clip in MIDPOINT_CLIPS:
        destination.mkdir(parents=True, exist_ok=True)
        for index in range(output_count):
            shutil.copy2(
                key_root / f"key_{index:03d}.png",
                destination / f"douhua_v3_{clip}_{index:03d}.png",
            )
        return
    output_fps = source_fps * (2 if clip in MIDPOINT_CLIPS else (3 if clip == "observe_idle" else 6))
    destination.mkdir(parents=True, exist_ok=True)
    command = [
        "ffmpeg",
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-framerate",
        str(source_fps),
        "-start_number",
        "0",
        "-i",
        str(key_root / "key_%03d.png"),
        "-vf",
        (
            f"minterpolate=fps={output_fps}:mi_mode=mci:mc_mode=obmc:"
            "me_mode=bilat:vsbmc=0"
        ),
        "-frames:v",
        str(output_count),
        "-c:v",
        "png",
        "-pix_fmt",
        "rgba",
        "-start_number",
        "0",
        str(destination / f"douhua_v3_{clip}_%03d.png"),
    ]
    subprocess.run(command, check=True, cwd=ROOT)
    for path in sorted(destination.glob("*.png")):
        stabilize_interpolated_frame(path)


def stabilize_interpolated_frame(path: Path) -> None:
    """Remove optical-flow wisps and keep every frame on one ground plane."""
    image = load_rgba(path)
    cleaned = []
    for red, green, blue, alpha in image.getdata():
        if alpha < 10:
            cleaned.append((0, 0, 0, 0))
        else:
            cleaned.append((red, green, blue, alpha))
    image.putdata(cleaned)
    bounds = alpha_bounds(image)
    crop = image.crop(bounds)
    x = bounds[0]
    y = BASELINE - crop.height
    if y < MINIMUM_MARGIN:
        fit = (BASELINE - MINIMUM_MARGIN) / crop.height
        crop = premultiplied_resize(
            crop,
            (max(1, round(crop.width * fit)), max(1, round(crop.height * fit))),
        )
        x = round((bounds[0] + bounds[2]) / 2 - crop.width / 2)
        y = BASELINE - crop.height
    x = min(max(x, MINIMUM_MARGIN), CANVAS_SIZE[0] - MINIMUM_MARGIN - crop.width)
    canvas = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(crop, (x, y))
    canvas.save(path, optimize=True)


def expanded_durations(clip: str, output_count: int) -> list[float]:
    source = SOURCE_DURATIONS[clip]
    if clip in MIDPOINT_CLIPS:
        durations = [duration / 2 for duration in source for _ in range(2)]
        if clip not in LOOPS:
            durations = durations[: output_count - 1] + [source[-1]]
        return durations
    if clip == "observe_idle":
        durations: list[float] = []
        for duration in source:
            transition = min(duration * 0.88, 0.10)
            durations.extend([duration - transition, transition / 2, transition / 2])
        return durations
    return [duration / 6 for duration in source for _ in range(6)]


def bake_stable_endpoints(clip: str, staging: Path, destination: Path) -> None:
    endpoint_loops = ENDPOINT_LOOPS.get(clip)
    if endpoint_loops is None:
        return
    output_paths = sorted(destination.glob("*.png"))
    if not output_paths:
        raise BuildError(f"{clip}: no frames to anchor")
    source_anchor = sorted((staging / endpoint_loops[0]).glob("*.png"))[0]
    target_anchor = sorted((staging / endpoint_loops[1]).glob("*.png"))[0]
    shutil.copy2(source_anchor, output_paths[0])
    shutil.copy2(target_anchor, output_paths[-1])


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_clip(clip: str, root: Path, durations: list[float]) -> dict[str, object]:
    paths = sorted(root.glob("*.png"))
    if len(paths) != len(durations):
        raise BuildError(f"{clip}: {len(paths)} frames but {len(durations)} durations")
    luminances: list[float] = []
    areas: list[int] = []
    centers: list[float] = []
    files: list[str] = []
    hashes: list[str] = []
    for path in paths:
        image = load_rgba(path)
        if any(image.getpixel(point)[3] >= ALPHA_THRESHOLD for point in [(0, 0), (479, 0), (0, 439), (479, 439)]):
            raise BuildError(f"{path}: non-transparent corner")
        bounds = alpha_bounds(image)
        if abs(bounds[3] - BASELINE) > 3:
            raise BuildError(f"{path}: baseline {bounds[3]}, expected {BASELINE}")
        luminances.append(fur_luminance(image))
        areas.append((bounds[2] - bounds[0]) * (bounds[3] - bounds[1]))
        centers.append((bounds[0] + bounds[2]) / 2)
        files.append(path.name)
        hashes.append(sha256(path))

    pairs = list(zip(range(len(paths)), range(1, len(paths))))
    if clip in LOOPS:
        pairs.append((len(paths) - 1, 0))
    max_luminance_step = max(abs(luminances[b] - luminances[a]) for a, b in pairs)
    max_area_ratio = max(max(areas[a], areas[b]) / max(1, min(areas[a], areas[b])) for a, b in pairs)
    max_center_step = max(abs(centers[b] - centers[a]) for a, b in pairs)
    if max_luminance_step > 22:
        raise BuildError(f"{clip}: possible exposure flash, luma step {max_luminance_step:.2f}")
    # A real get-up/lie-down transition changes the silhouette area sharply
    # when a foreleg extends; loops and pet reactions should remain tighter.
    area_limit = 1.60 if "_to_" in clip else 1.32
    if max_area_ratio > area_limit:
        raise BuildError(f"{clip}: possible scale pop, area ratio {max_area_ratio:.3f}")
    return {
        "id": clip,
        "loops": clip in LOOPS,
        "frameCount": len(paths),
        "files": files,
        "durations": [round(value, 6) for value in durations],
        "sha256": hashes,
        "continuity": {
            "maximumAdjacentFurLuminanceStep": round(max_luminance_step, 4),
            "maximumAdjacentAlphaAreaRatio": round(max_area_ratio, 6),
            "maximumAdjacentCenterStepPixels": round(max_center_step, 4),
        },
    }


def validate_existing_package() -> None:
    manifest_path = OUTPUT_ROOT / "animation-manifest-v3.json"
    if not manifest_path.is_file():
        raise BuildError(f"missing manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 3 or manifest.get("renderer") != "single-opaque-frame":
        raise BuildError("v3 manifest does not require the single-opaque-frame renderer")
    records = manifest.get("clips", [])
    if [record.get("id") for record in records] != CLIP_ORDER:
        raise BuildError("v3 manifest clip set or ordering is invalid")
    frame_count = 0
    for record in records:
        clip = record["id"]
        checked = validate_clip(clip, OUTPUT_ROOT / clip, record["durations"])
        if checked["files"] != record["files"] or checked["sha256"] != record["sha256"]:
            raise BuildError(f"{clip}: frame filenames or hashes differ from manifest")
        frame_count += int(checked["frameCount"])
    expected = manifest.get("validation", {}).get("frameCount")
    if frame_count != expected:
        raise BuildError(f"manifest reports {expected} frames; validated {frame_count}")
    validate_endpoint_anchors(OUTPUT_ROOT)
    print(f"Validated {len(records)} clips / {frame_count} single-image frames")


def validate_endpoint_anchors(root: Path) -> None:
    for clip, (source_loop, target_loop) in ENDPOINT_LOOPS.items():
        paths = sorted((root / clip).glob("*.png"))
        source = sorted((root / source_loop).glob("*.png"))[0]
        target = sorted((root / target_loop).glob("*.png"))[0]
        if not paths or sha256(paths[0]) != sha256(source) or sha256(paths[-1]) != sha256(target):
            raise BuildError(f"{clip}: stable endpoint anchor is not pixel-identical")


def main() -> None:
    if sys.argv[1:] == ["--validate-only"]:
        validate_existing_package()
        return
    if sys.argv[1:]:
        raise BuildError("usage: BuildSmoothAnimationFrames.py [--validate-only]")
    if shutil.which("ffmpeg") is None:
        raise BuildError("ffmpeg is required to build optical-flow in-betweens")
    build_root = ROOT / ".build"
    build_root.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="douhua-v3-", dir=build_root) as temporary:
        work_root = Path(temporary)
        midpoint_root = prepare_midpoints(work_root)
        staging = work_root / "v3-smooth"
        clip_records: list[dict[str, object]] = []
        for clip in CLIP_ORDER:
            keys = work_root / "keys" / clip
            source_fps, output_count = write_key_sequence(clip, midpoint_root, keys)
            destination = staging / clip
            interpolate(clip, keys, destination, source_fps, output_count)
            bake_stable_endpoints(clip, staging, destination)
            durations = expanded_durations(clip, output_count)
            clip_records.append(validate_clip(clip, destination, durations))
            print(f"{clip}: {output_count} single-image frames")

        validate_endpoint_anchors(staging)
        manifest = {
            "schemaVersion": 3,
            "renderer": "single-opaque-frame",
            "generator": "Scripts/BuildSmoothAnimationFrames.py",
            "source": "v2 keys plus generated biomechanical midpoints",
            "canvas": [CANVAS_SIZE[0], CANVAS_SIZE[1]],
            "targetBaseline": BASELINE,
            "clips": clip_records,
            "validation": {
                "ok": True,
                "clipCount": len(clip_records),
                "frameCount": sum(int(record["frameCount"]) for record in clip_records),
                "runtimeCrossfadeLayers": 0,
                "singleCompleteSpritePerFrame": True,
                "pixelIdenticalEndpointAnchors": True,
            },
        }
        (staging / "animation-manifest-v3.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if OUTPUT_ROOT.exists():
            shutil.rmtree(OUTPUT_ROOT)
        shutil.copytree(staging, OUTPUT_ROOT)

    print(
        f"Built {manifest['validation']['clipCount']} clips / "
        f"{manifest['validation']['frameCount']} frames at {OUTPUT_ROOT}"
    )


if __name__ == "__main__":
    try:
        main()
    except (BuildError, subprocess.CalledProcessError) as error:
        print(f"BuildSmoothAnimationFrames failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
