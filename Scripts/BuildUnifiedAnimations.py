#!/usr/bin/env python3
"""Build the temporally unified v4 Douhua animation package.

Each source sheet contains a complete 24-frame action drawn as one coherent
character.  No runtime crossfade and no optical-flow frames are used.
"""

from __future__ import annotations

import hashlib
import json
import math
import shutil
import sys
import tempfile
from collections import deque
from pathlib import Path
from typing import Any

from PIL import Image

import PrepareAnimationSheets as prep


ROOT = Path(__file__).resolve().parent.parent
SOURCE_ROOT = ROOT / "Docs/Art/AnimationSource/v4-unified"
OUTPUT_ROOT = ROOT / "Sources/DouhuaPet/Resources/Animations/Douhua/v4-unified"
BUILD_ROOT = ROOT / ".build"
SHEET_COLUMNS = 6
SHEET_ROWS = 4
FRAME_COUNT = 24

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

LOOPS = {"walk_loop", "observe_idle", "loaf_breathe", "sleep_breathe"}
TOTAL_DURATIONS = {
    "walk_loop": 0.96,
    "observe_idle": 3.0,
    "loaf_breathe": 4.0,
    "sleep_breathe": 5.0,
    "pet_observe": 0.90,
    "pet_loaf": 0.90,
    "pet_sleep": 1.05,
    "observe_to_walk": 0.72,
    "walk_to_observe": 0.84,
    "observe_to_loaf": 1.20,
    "loaf_to_observe": 1.05,
    "loaf_to_sleep": 1.30,
    "sleep_to_loaf": 1.15,
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


class BuildError(RuntimeError):
    pass


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_path(clip: str) -> Path:
    return SOURCE_ROOT / f"{clip}_24.png"


def frame_path(root: Path, clip: str, index: int) -> Path:
    return root / clip / f"douhua_v4_{clip}_{index:03d}.png"


def remove_small_components(image: Image.Image, minimum_area: int = 500) -> Image.Image:
    """Remove generated labels/specks while retaining cat, tail and fur islands."""
    rgba = image.convert("RGBA")
    width, height = rgba.size
    alpha = list(rgba.getchannel("A").getdata())
    visible = [value >= prep.ALPHA_THRESHOLD for value in alpha]
    visited = bytearray(width * height)
    components: list[list[int]] = []
    for start, is_visible in enumerate(visible):
        if not is_visible or visited[start]:
            continue
        visited[start] = 1
        queue: deque[int] = deque([start])
        component: list[int] = []
        while queue:
            index = queue.popleft()
            component.append(index)
            x, y = index % width, index // width
            for neighbor in (
                index - 1 if x > 0 else -1,
                index + 1 if x + 1 < width else -1,
                index - width if y > 0 else -1,
                index + width if y + 1 < height else -1,
            ):
                if neighbor >= 0 and visible[neighbor] and not visited[neighbor]:
                    visited[neighbor] = 1
                    queue.append(neighbor)
        components.append(component)
    if not components:
        raise BuildError("chroma-keyed cell contains no foreground")
    largest = max(len(component) for component in components)
    threshold = max(minimum_area, round(largest * 0.01))
    keep = bytearray(width * height)
    for component in components:
        if len(component) >= threshold:
            for index in component:
                keep[index] = 1
    pixels = list(rgba.getdata())
    rgba.putdata([pixel if keep[index] else (0, 0, 0, 0) for index, pixel in enumerate(pixels)])
    return rgba


def split_and_prepare(clip: str, output: Path) -> dict[str, Any]:
    path = source_path(clip)
    if not path.is_file():
        raise BuildError(f"missing v4 source sheet: {path}")
    with Image.open(path) as opened:
        sheet = opened.convert("RGBA")

    y_lines = prep.grid_separators(sheet, parts=SHEET_ROWS, axis="y")
    row_x_lines = [
        prep.grid_separators(
            sheet.crop((0, y_lines[row], sheet.width, y_lines[row + 1])),
            parts=SHEET_COLUMNS,
            axis="x",
        )
        for row in range(SHEET_ROWS)
    ]
    rects = [
        (
            row_x_lines[row][column],
            y_lines[row],
            row_x_lines[row][column + 1],
            y_lines[row + 1],
        )
        for row in range(SHEET_ROWS)
        for column in range(SHEET_COLUMNS)
    ]
    cell_width = max(right - left for left, _, right, _ in rects)
    cell_height = max(bottom - top for _, top, _, bottom in rects)
    cells: list[prep.PreparedCell] = []
    for index, rect in enumerate(rects):
        raw = sheet.crop(rect)
        padded = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
        padded.alpha_composite(
            raw,
            ((cell_width - raw.width) // 2, (cell_height - raw.height) // 2),
        )
        prepared = prep.prepare_cell(
            padded,
            index=index,
            chroma_key=prep.DEFAULT_KEY,
            near_distance=8.0,
            far_distance=190.0,
            edge_radius=5,
        )
        prepared.image = remove_small_components(prepared.image)
        bounds = prep.alpha_bounds(prepared.image)
        if bounds is None:
            raise BuildError(f"{clip} frame {index}: empty after component cleanup")
        prepared.bounds = bounds
        cells.append(prepared)

    scale, anchor_x, relative_lefts, dimensions = prep.determine_shared_geometry(
        cells,
        cell_width=cell_width,
    )
    scale *= prep.GLOBAL_DISPLAY_SCALE
    output_clip = output / clip
    output_clip.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, Any]] = []
    for cell, relative_left, dimensions_at_full in zip(cells, relative_lefts, dimensions):
        crop = cell.image.crop(tuple(cell.bounds.as_list()))
        width = max(1, round(dimensions_at_full[0] * prep.GLOBAL_DISPLAY_SCALE))
        height = max(1, round(dimensions_at_full[1] * prep.GLOBAL_DISPLAY_SCALE))
        resized = prep.premultiplied_resize(crop, (width, height))
        resized, _ = prep.suppress_edge_spill(
            resized,
            chroma_key=prep.DEFAULT_KEY,
            edge_radius=3,
            strength=1.0,
            spill_tolerance=0.15,
        )
        # Keep the generated sheet's common source-slot registration.  It is
        # more temporally stable than recentering each cat by its changing fur.
        x = round(anchor_x + relative_left * prep.GLOBAL_DISPLAY_SCALE)
        x = min(max(x, prep.MINIMUM_MARGIN), prep.CANVAS_WIDTH - prep.MINIMUM_MARGIN - width)
        y = prep.TARGET_BASELINE - height
        canvas = Image.new("RGBA", (prep.CANVAS_WIDTH, prep.CANVAS_HEIGHT), (0, 0, 0, 0))
        canvas.alpha_composite(resized, (x, y))
        destination = frame_path(output, clip, cell.index)
        prep.atomic_save_png(canvas, destination)
        bounds = prep.alpha_bounds(canvas)
        if bounds is None:
            raise BuildError(f"empty frame: {destination}")
        records.append(
            {
                "index": cell.index,
                "file": destination.name,
                "sha256": sha256(destination),
                "alphaBounds": bounds.as_list(),
                "visiblePixels": prep.visible_pixel_count(canvas),
            }
        )
    return {
        "id": clip,
        "source": path.relative_to(ROOT).as_posix(),
        "sourceSha256": sha256(path),
        "sheetSize": [sheet.width, sheet.height],
        "grid": [SHEET_COLUMNS, SHEET_ROWS],
        "sharedScale": round(scale, 8),
        "frames": records,
    }


def bake_endpoints(output: Path, clip: str) -> None:
    loops = ENDPOINT_LOOPS.get(clip)
    if loops is None:
        return
    shutil.copy2(frame_path(output, loops[0], 0), frame_path(output, clip, 0))
    shutil.copy2(frame_path(output, loops[1], 0), frame_path(output, clip, FRAME_COUNT - 1))


def validate_frame(path: Path) -> tuple[float, float, float]:
    with Image.open(path) as opened:
        image = opened.convert("RGBA")
    if image.size != (prep.CANVAS_WIDTH, prep.CANVAS_HEIGHT):
        raise BuildError(f"wrong canvas: {path}")
    bounds = prep.alpha_bounds(image)
    if bounds is None or abs(bounds.bottom - prep.TARGET_BASELINE) > 2:
        raise BuildError(f"invalid baseline: {path}")
    if any(image.getpixel(point)[3] >= prep.ALPHA_THRESHOLD for point in [(0, 0), (479, 0), (0, 439), (479, 439)]):
        raise BuildError(f"non-transparent corner: {path}")
    luminances = []
    for red, green, blue, alpha in image.getdata():
        if alpha > 220:
            value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            if 42 <= value <= 210:
                luminances.append(value)
    luminance = sum(luminances) / max(1, len(luminances))
    metric = math.sqrt(bounds.width * bounds.height)
    center = (bounds.left + bounds.right) / 2
    return luminance, metric, center


def validate_clip(output: Path, clip: str) -> dict[str, Any]:
    paths = [frame_path(output, clip, index) for index in range(FRAME_COUNT)]
    samples = [validate_frame(path) for path in paths]
    pairs = list(zip(range(FRAME_COUNT), range(1, FRAME_COUNT)))
    if clip in LOOPS:
        pairs.append((FRAME_COUNT - 1, 0))
    luma_step = max(abs(samples[b][0] - samples[a][0]) for a, b in pairs)
    scale_ratio = max(max(samples[a][1], samples[b][1]) / min(samples[a][1], samples[b][1]) for a, b in pairs)
    center_step = max(abs(samples[b][2] - samples[a][2]) for a, b in pairs)
    if luma_step > 18:
        raise BuildError(f"{clip}: exposure discontinuity {luma_step:.2f}")
    # A stand/loaf or loaf/sleep transition legitimately changes the alpha
    # bounding-box metric as limbs fold and the contact patch widens.
    scale_limit = 1.35 if "_to_" in clip else 1.16
    if scale_ratio > scale_limit:
        raise BuildError(f"{clip}: silhouette scale discontinuity {scale_ratio:.3f}")
    duration = TOTAL_DURATIONS[clip] / FRAME_COUNT
    return {
        "id": clip,
        "loops": clip in LOOPS,
        "frameCount": FRAME_COUNT,
        "files": [path.name for path in paths],
        "durations": [round(duration, 6)] * FRAME_COUNT,
        "sha256": [sha256(path) for path in paths],
        "continuity": {
            "maximumAdjacentFurLuminanceStep": round(luma_step, 4),
            "maximumAdjacentScaleMetricRatio": round(scale_ratio, 6),
            "maximumAdjacentCenterStepPixels": round(center_step, 4),
        },
    }


def validate_endpoints(output: Path) -> None:
    for clip, loops in ENDPOINT_LOOPS.items():
        if not (output / clip).is_dir():
            continue
        if sha256(frame_path(output, clip, 0)) != sha256(frame_path(output, loops[0], 0)):
            raise BuildError(f"{clip}: source endpoint mismatch")
        if sha256(frame_path(output, clip, FRAME_COUNT - 1)) != sha256(frame_path(output, loops[1], 0)):
            raise BuildError(f"{clip}: destination endpoint mismatch")


def selected_clips() -> list[str]:
    available = [clip for clip in CLIP_ORDER if source_path(clip).is_file()]
    if not available:
        raise BuildError(f"no v4 sheets found in {SOURCE_ROOT}")
    return available


def validate_existing() -> None:
    manifest_path = OUTPUT_ROOT / "animation-manifest-v4.json"
    if not manifest_path.is_file():
        raise BuildError(f"missing manifest: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (
        manifest.get("schemaVersion") != 4
        or manifest.get("renderer") != "single-opaque-frame"
        or manifest.get("usesRuntimeCrossfade") is not False
        or manifest.get("usesOpticalFlowFrames") is not False
    ):
        raise BuildError("v4 manifest renderer contract is invalid")
    records = manifest.get("clips", [])
    if [record.get("id") for record in records] != CLIP_ORDER:
        raise BuildError("v4 manifest is incomplete or out of order")
    for stored in records:
        checked = validate_clip(OUTPUT_ROOT, stored["id"])
        if checked["files"] != stored["files"] or checked["sha256"] != stored["sha256"]:
            raise BuildError(f"{stored['id']}: files differ from manifest")
    validate_endpoints(OUTPUT_ROOT)
    print(f"Validated {len(records)} clips / {len(records) * FRAME_COUNT} unified frames")


def main() -> None:
    if sys.argv[1:] == ["--validate-only"]:
        validate_existing()
        return
    if sys.argv[1:]:
        raise BuildError("usage: BuildUnifiedAnimations.py [--validate-only]")
    clips = selected_clips()
    BUILD_ROOT.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="douhua-v4-", dir=BUILD_ROOT) as temporary:
        staging = Path(temporary) / "v4-unified"
        sources = [split_and_prepare(clip, staging) for clip in clips]
        for clip in clips:
            bake_endpoints(staging, clip)
        records = [validate_clip(staging, clip) for clip in clips]
        validate_endpoints(staging)
        manifest = {
            "schemaVersion": 4,
            "renderer": "single-opaque-frame",
            "temporalDesign": "unified-character-24-frame-actions",
            "usesRuntimeCrossfade": False,
            "usesOpticalFlowFrames": False,
            "canvas": [prep.CANVAS_WIDTH, prep.CANVAS_HEIGHT],
            "targetBaseline": prep.TARGET_BASELINE,
            "clips": records,
            "sources": sources,
            "validation": {
                "ok": True,
                "clipCount": len(records),
                "frameCount": len(records) * FRAME_COUNT,
                "completePackage": len(records) == len(CLIP_ORDER),
            },
        }
        (staging / "animation-manifest-v4.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        if OUTPUT_ROOT.exists():
            shutil.rmtree(OUTPUT_ROOT)
        shutil.copytree(staging, OUTPUT_ROOT)
    print(f"Built {len(clips)} clips / {len(clips) * FRAME_COUNT} frames: {OUTPUT_ROOT}")


if __name__ == "__main__":
    try:
        main()
    except BuildError as error:
        print(f"BuildUnifiedAnimations failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
