#!/usr/bin/env python3
"""Prepare 4x2 chroma-key animation sheets for the Douhua desktop pet.

The script performs one deterministic local raster pass:

1. split each input sheet into eight equal row-major cells;
2. remove the #ff00ff matte and suppress magenta spill at alpha edges;
3. compute one scale and one horizontal registration for the whole clip;
4. place every frame on a 480x440 transparent canvas at baseline y=424;
5. write sequential PNGs plus a validated, deterministic manifest.

Examples:
  PrepareAnimationSheets.py --clip walk=/path/walk_4x2.png
  PrepareAnimationSheets.py --clip walk=/path/walk.png --clip loaf=/path/loaf.png
  PrepareAnimationSheets.py                 # discover tmp/imagegen/*sheet*.png
  PrepareAnimationSheets.py --validate-only
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable, Sequence

from PIL import Image, ImageFilter


SCRIPT_VERSION = 1
ALGORITHM = "soft-magenta-key-and-edge-local-linear-despill-v1"
SHEET_COLUMNS = 4
SHEET_ROWS = 2
FRAME_COUNT = SHEET_COLUMNS * SHEET_ROWS
CANVAS_WIDTH = 480
CANVAS_HEIGHT = 440
MINIMUM_MARGIN = 16
TARGET_BASELINE = 424  # PNG coordinates measured down from the top edge.
GLOBAL_DISPLAY_SCALE = 0.90
ALPHA_THRESHOLD = 2
MAGENTA_RESIDUE_TOLERANCE = 24
DEFAULT_KEY = (255, 0, 255)
KNOWN_CLIPS = ("walk", "observe", "loaf")
LOOP_CLIP_FOR_STATE = {
    "walking": "walk_loop",
    "observing": "observe_idle",
    "loafing": "loaf_breathe",
    "sleeping": "sleep_breathe",
}
CLIP_ENDPOINT_STATES = {
    "observe_to_walk": ("observing", "walking"),
    "walk_to_observe": ("walking", "observing"),
    "observe_to_loaf": ("observing", "loafing"),
    "loaf_to_observe": ("loafing", "observing"),
    "loaf_to_sleep": ("loafing", "sleeping"),
    "sleep_to_loaf": ("sleeping", "loafing"),
    "pet_observe": ("observing", "observing"),
    "pet_loaf": ("loafing", "loafing"),
    "pet_sleep": ("sleeping", "sleeping"),
}


class PipelineError(RuntimeError):
    """A deterministic input or validation failure."""


def flattened_data(image: Image.Image) -> Iterable[Any]:
    """Use Pillow's forward-compatible flattened pixel iterator."""
    getter = getattr(image, "get_flattened_data", None)
    if getter is not None:
        return getter()
    return image.getdata()


@dataclass(frozen=True)
class Bounds:
    left: int
    top: int
    right: int
    bottom: int

    @property
    def width(self) -> int:
        return self.right - self.left

    @property
    def height(self) -> int:
        return self.bottom - self.top

    @property
    def area(self) -> int:
        return self.width * self.height

    def as_list(self) -> list[int]:
        return [self.left, self.top, self.right, self.bottom]


@dataclass
class PreparedCell:
    index: int
    row: int
    column: int
    image: Image.Image
    bounds: Bounds
    cleanup: dict[str, Any]


def smoothstep(value: float) -> float:
    value = min(1.0, max(0.0, value))
    return value * value * (3.0 - 2.0 * value)


def srgb_to_linear(value: float) -> float:
    if value <= 0.04045:
        return value / 12.92
    return ((value + 0.055) / 1.055) ** 2.4


def linear_to_srgb(value: float) -> float:
    if value <= 0.0031308:
        return value * 12.92
    return 1.055 * value ** (1.0 / 2.4) - 0.055


def chroma_similarity(
    color: tuple[float, float, float],
    key: tuple[float, float, float],
) -> float:
    color_mean = sum(color) / 3.0
    key_mean = sum(key) / 3.0
    color_chroma = tuple(channel - color_mean for channel in color)
    key_chroma = tuple(channel - key_mean for channel in key)
    denominator = sum(channel * channel for channel in color_chroma) * sum(
        channel * channel for channel in key_chroma
    )
    if denominator <= 1e-12:
        return -1.0
    return sum(a * b for a, b in zip(color_chroma, key_chroma)) / math.sqrt(denominator)


def chroma_saturation(color: tuple[float, float, float]) -> float:
    maximum = max(color)
    if maximum <= 0.0:
        return 0.0
    return (maximum - min(color)) / maximum


def parse_hex_color(value: str) -> tuple[int, int, int]:
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", value):
        raise PipelineError(f"invalid chroma key {value!r}; expected #RRGGBB")
    return tuple(int(value[index : index + 2], 16) for index in (1, 3, 5))  # type: ignore[return-value]


def color_hex(color: tuple[int, int, int]) -> str:
    return "#" + "".join(f"{channel:02X}" for channel in color)


def grid_separators(image: Image.Image, *, parts: int, axis: str) -> list[int]:
    """Locate chroma valleys near the nominal generated-sheet grid lines.

    Image generation often places a paw or tail a few pixels across the exact
    mathematical quarter boundary while leaving a clear magenta gutter next
    to it.  Cutting at the lowest-foreground valley preserves the complete
    subject without guessing per-frame bounding boxes.
    """
    rgba = image.convert("RGBA")
    dimension = rgba.width if axis == "x" else rgba.height
    cross_dimension = rgba.height if axis == "x" else rgba.width
    nominal_cell = dimension / parts
    search_radius = max(4, int(nominal_cell * 0.20))
    sample_step = max(1, cross_dimension // 256)

    separators = [0]
    for part in range(1, parts):
        expected = int(round(part * nominal_cell))
        lower = max(separators[-1] + 1, expected - search_radius)
        upper = min(dimension - 1, expected + search_radius)
        candidates: list[tuple[int, int, int]] = []
        for coordinate in range(lower, upper + 1):
            foreground = 0
            for cross in range(0, cross_dimension, sample_step):
                x, y = (coordinate, cross) if axis == "x" else (cross, coordinate)
                red, green, blue, alpha = rgba.getpixel((x, y))
                dominance = (min(red, blue) - green) / 255.0
                if alpha > 0 and dominance < 0.28:
                    foreground += 1
            candidates.append((foreground, abs(coordinate - expected), coordinate))
        separators.append(min(candidates)[2])
    separators.append(dimension)
    return separators


def alpha_bounds(image: Image.Image) -> Bounds | None:
    alpha = image.getchannel("A")
    mask = alpha.point([0 if value < ALPHA_THRESHOLD else 255 for value in range(256)])
    box = mask.getbbox()
    if box is None:
        return None
    return Bounds(*box)


def visible_pixel_count(image: Image.Image) -> int:
    histogram = image.getchannel("A").histogram()
    return sum(histogram[ALPHA_THRESHOLD:])


def magenta_residue_stats(image: Image.Image) -> tuple[int, int]:
    count = 0
    maximum_excess = 0
    for red, green, blue, alpha in flattened_data(image):
        if alpha < ALPHA_THRESHOLD:
            continue
        excess = min(red, blue) - green
        maximum_excess = max(maximum_excess, excess)
        if excess > MAGENTA_RESIDUE_TOLERANCE:
            count += 1
    return count, max(0, maximum_excess)


def edge_band(alpha: Image.Image, radius: int) -> list[bool]:
    visible = [value > 0 for value in flattened_data(alpha)]
    transparent = Image.new("L", alpha.size)
    transparent.putdata([0 if value else 255 for value in visible])
    expanded = transparent.filter(ImageFilter.MaxFilter(radius * 2 + 1))
    return [
        is_visible and nearby > 0
        for is_visible, nearby in zip(visible, flattened_data(expanded))
    ]


def soft_magenta_key(
    image: Image.Image,
    *,
    chroma_key: tuple[int, int, int],
    near_distance: float,
    far_distance: float,
) -> tuple[Image.Image, dict[str, int]]:
    if near_distance < 0.0 or far_distance <= near_distance:
        raise PipelineError("key distances must satisfy 0 <= near < far")

    rgba = image.convert("RGBA")
    keyed_pixels = 0
    transparent_pixels = 0
    output: list[tuple[int, int, int, int]] = []

    for red, green, blue, source_alpha in flattened_data(rgba):
        if source_alpha == 0:
            output.append((0, 0, 0, 0))
            transparent_pixels += 1
            continue

        distance = math.sqrt(
            (red - chroma_key[0]) ** 2
            + (green - chroma_key[1]) ** 2
            + (blue - chroma_key[2]) ** 2
        )
        distance_matte = smoothstep((distance - near_distance) / (far_distance - near_distance))

        # A magenta key has both red and blue above green. This second matte
        # handles antialiased key/subject mixtures more accurately than RGB
        # distance alone, while leaving golden fur, green eyes and a pink nose.
        magenta_dominance = max(0.0, (min(red, blue) - green) / 255.0)
        # Generated "solid" chroma sheets contain a broad pink gradient
        # (roughly R/B 220...255 and G 0...50), not literal #ff00ff.  Treat
        # strongly magenta pixels as fully background while retaining the
        # warm pinks of ears and nose, whose green channel is much closer to
        # red/blue.  The smooth interval keeps a feathered antialiased edge.
        dominance_matte = 1.0 - smoothstep((magenta_dominance - 0.08) / 0.42)
        matte = min(distance_matte, dominance_matte)
        output_alpha = int(round(source_alpha * matte))
        if output_alpha < ALPHA_THRESHOLD:
            output.append((0, 0, 0, 0))
            transparent_pixels += 1
        else:
            output.append((red, green, blue, output_alpha))
        if output_alpha < source_alpha:
            keyed_pixels += 1

    keyed = Image.new("RGBA", rgba.size)
    keyed.putdata(output)
    return keyed, {
        "keyedPixels": keyed_pixels,
        "transparentPixels": transparent_pixels,
    }


def suppress_edge_spill(
    image: Image.Image,
    *,
    chroma_key: tuple[int, int, int],
    edge_radius: int,
    strength: float,
    spill_tolerance: float,
) -> tuple[Image.Image, dict[str, int | float | bool]]:
    if edge_radius < 1:
        raise PipelineError("edge radius must be at least 1")
    if not 0.0 <= strength <= 1.0:
        raise PipelineError("despill strength must be between 0 and 1")

    rgba = image.convert("RGBA")
    width, height = rgba.size
    source = list(flattened_data(rgba))
    boundary = edge_band(rgba.getchannel("A"), edge_radius)
    colors_linear = [
        tuple(srgb_to_linear(channel / 255.0) for channel in pixel[:3]) for pixel in source
    ]
    key_linear = tuple(srgb_to_linear(channel / 255.0) for channel in chroma_key)
    similarity_threshold = 1.0 - min(spill_tolerance, 1.0)

    pending = [
        pixel[3] > 0
        and is_boundary
        and (
            pixel[3] < 250
            or (
                chroma_saturation(color) >= 0.1
                and chroma_similarity(color, key_linear) >= similarity_threshold
            )
        )
        for pixel, color, is_boundary in zip(source, colors_linear, boundary)
    ]
    filled = [pixel[3] > 0 and not is_pending for pixel, is_pending in zip(source, pending)]
    output = source.copy()
    changed = [False] * len(source)

    # Extend clean interior RGB outward through the alpha boundary in linear
    # light. Alpha itself is never changed by this despill stage.
    for _ in range(edge_radius * 2 + 1):
        updates: list[tuple[int, tuple[float, float, float]]] = []
        for index, is_pending in enumerate(pending):
            if not is_pending:
                continue
            x = index % width
            y = index // width
            references: list[tuple[float, float, float]] = []
            for neighbor_y in range(max(0, y - 1), min(height, y + 2)):
                for neighbor_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = neighbor_y * width + neighbor_x
                    if neighbor != index and filled[neighbor]:
                        references.append(colors_linear[neighbor])
            if not references:
                continue

            reference = tuple(
                sum(color[channel] for color in references) / len(references)
                for channel in range(3)
            )
            observed = colors_linear[index]
            cleaned = tuple(
                channel + (reference_channel - channel) * strength
                for channel, reference_channel in zip(observed, reference)
            )
            updates.append((index, cleaned))

        if not updates:
            break
        for index, cleaned in updates:
            colors_linear[index] = cleaned
            filled[index] = True
            pending[index] = False
            cleaned_pixel = (
                *(
                    round(linear_to_srgb(min(1.0, max(0.0, channel))) * 255.0)
                    for channel in cleaned
                ),
                source[index][3],
            )
            output[index] = cleaned_pixel
            changed[index] = cleaned_pixel != source[index]

    # Any isolated translucent pixel without a clean neighbor is neutralized;
    # this is still part of the same edge-local pass and preserves alpha.
    for index, is_pending in enumerate(pending):
        if not is_pending:
            continue
        observed = colors_linear[index]
        luminance = sum(observed) / 3.0
        cleaned = tuple(channel + (luminance - channel) * strength for channel in observed)
        cleaned_pixel = (
            *(
                round(linear_to_srgb(min(1.0, max(0.0, channel))) * 255.0)
                for channel in cleaned
            ),
            source[index][3],
        )
        output[index] = cleaned_pixel
        changed[index] = cleaned_pixel != source[index]

    forced_neutral = 0
    for index, (red, green, blue, alpha) in enumerate(output):
        if alpha == 0:
            output[index] = (0, 0, 0, 0)
            continue
        excess = min(red, blue) - green
        if excess > MAGENTA_RESIDUE_TOLERANCE:
            output[index] = (
                red,
                min(255, min(red, blue) - MAGENTA_RESIDUE_TOLERANCE),
                blue,
                alpha,
            )
            changed[index] = True
            forced_neutral += 1

    cleaned_image = Image.new("RGBA", rgba.size)
    cleaned_image.putdata(output)
    return cleaned_image, {
        "despilledPixels": sum(changed),
        "forcedNeutralPixels": forced_neutral,
        "alphaPreservedByDespill": True,
        "edgeRadius": edge_radius,
        "strength": strength,
        "spillTolerance": spill_tolerance,
    }


def prepare_cell(
    cell: Image.Image,
    *,
    index: int,
    chroma_key: tuple[int, int, int],
    near_distance: float,
    far_distance: float,
    edge_radius: int,
) -> PreparedCell:
    keyed, key_report = soft_magenta_key(
        cell,
        chroma_key=chroma_key,
        near_distance=near_distance,
        far_distance=far_distance,
    )
    cleaned, despill_report = suppress_edge_spill(
        keyed,
        chroma_key=chroma_key,
        edge_radius=edge_radius,
        strength=1.0,
        spill_tolerance=0.15,
    )
    bounds = alpha_bounds(cleaned)
    if bounds is None:
        raise PipelineError(f"frame {index:02d} is empty after chroma removal")
    if bounds.left <= 0 or bounds.top <= 0 or bounds.right >= cell.width or bounds.bottom >= cell.height:
        alpha = cleaned.getchannel("A")
        edge_contacts = {
            "left": sum(alpha.getpixel((0, y)) >= ALPHA_THRESHOLD for y in range(cell.height)),
            "right": sum(
                alpha.getpixel((cell.width - 1, y)) >= ALPHA_THRESHOLD
                for y in range(cell.height)
            ),
            "top": sum(alpha.getpixel((x, 0)) >= ALPHA_THRESHOLD for x in range(cell.width)),
            "bottom": sum(
                alpha.getpixel((x, cell.height - 1)) >= ALPHA_THRESHOLD
                for x in range(cell.width)
            ),
        }
        # A generated whisker or tail hair can cross the mathematically chosen
        # gutter by only a handful of pixels.  Preserve it and add transparent
        # output padding; reject broad contact, which indicates a truly clipped
        # body (notably the first rejected petted sheet).
        contact_limit = max(12, int(min(cell.size) * 0.03))
        if max(edge_contacts.values()) > contact_limit:
            raise PipelineError(
                f"frame {index:02d} touches a cell edge after keying; source sheet is clipped "
                f"(bounds={bounds.as_list()}, contacts={edge_contacts}, "
                f"cell={cell.width}x{cell.height})"
            )
    corner_alpha = [
        cleaned.getpixel((0, 0))[3],
        cleaned.getpixel((cell.width - 1, 0))[3],
        cleaned.getpixel((0, cell.height - 1))[3],
        cleaned.getpixel((cell.width - 1, cell.height - 1))[3],
    ]
    if any(value >= ALPHA_THRESHOLD for value in corner_alpha):
        raise PipelineError(f"frame {index:02d} retained opaque chroma at a cell corner")

    residue, maximum_excess = magenta_residue_stats(cleaned)
    cleanup: dict[str, Any] = {
        "algorithm": ALGORITHM,
        **key_report,
        **despill_report,
        "magentaResiduePixels": residue,
        "maxVisibleMagentaExcess": maximum_excess,
    }
    return PreparedCell(
        index=index,
        row=index // SHEET_COLUMNS,
        column=index % SHEET_COLUMNS,
        image=cleaned,
        bounds=bounds,
        cleanup=cleanup,
    )


def premultiplied_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    # Pillow's RGBa mode stores premultiplied alpha and avoids dark/key-colored
    # fringes when Lanczos samples across transparent pixels.
    return image.convert("RGBa").resize(size, Image.Resampling.LANCZOS).convert("RGBA")


def atomic_save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    image.save(temporary, format="PNG", compress_level=9, optimize=False)
    os.replace(temporary, path)


def atomic_write_json(data: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp")
    temporary.write_text(
        json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    os.replace(temporary, path)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def display_path(path: Path, project_root: Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def determine_shared_geometry(
    cells: Sequence[PreparedCell],
    *,
    cell_width: int,
) -> tuple[float, int, list[int], list[tuple[int, int]]]:
    center = cell_width / 2.0
    minimum_relative_left = min(cell.bounds.left - center for cell in cells)
    maximum_relative_right = max(cell.bounds.right - center for cell in cells)
    horizontal_span = maximum_relative_right - minimum_relative_left
    maximum_height = max(cell.bounds.height for cell in cells)
    usable_width = CANVAS_WIDTH - MINIMUM_MARGIN * 2
    usable_height = CANVAS_HEIGHT - MINIMUM_MARGIN * 2
    scale = min(usable_width / horizontal_span, usable_height / maximum_height)
    if not math.isfinite(scale) or scale <= 0.0:
        raise PipelineError("could not determine a positive shared clip scale")

    # Rounding of the final integer rectangles can consume one extra pixel. If
    # needed, reduce the scale by a tiny deterministic amount until every frame
    # admits one shared source-slot horizontal anchor.
    for _ in range(32):
        widths = [max(1, int(math.floor(cell.bounds.width * scale))) for cell in cells]
        relative_lefts = [int(round((cell.bounds.left - center) * scale)) for cell in cells]
        lower_anchor = max(
            MINIMUM_MARGIN - relative_left
            for relative_left in relative_lefts
        )
        upper_anchor = min(
            CANVAS_WIDTH - MINIMUM_MARGIN - relative_left - width
            for relative_left, width in zip(relative_lefts, widths)
        )
        if lower_anchor <= upper_anchor:
            anchor = min(max(CANVAS_WIDTH // 2, lower_anchor), upper_anchor)
            dimensions = [
                (
                    width,
                    max(1, int(math.floor(cell.bounds.height * scale))),
                )
                for cell, width in zip(cells, widths)
            ]
            return scale, anchor, relative_lefts, dimensions
        scale *= 0.999

    raise PipelineError("shared horizontal registration cannot fit within the safe area")


def process_clip(
    *,
    name: str,
    source_path: Path,
    output_root: Path,
    project_root: Path,
    chroma_key: tuple[int, int, int],
    near_distance: float,
    far_distance: float,
    edge_radius: int,
) -> dict[str, Any]:
    if not source_path.is_file():
        raise PipelineError(f"missing input sheet for {name}: {source_path}")
    with Image.open(source_path) as opened:
        sheet = opened.convert("RGBA")
    y_lines = grid_separators(sheet, parts=SHEET_ROWS, axis="y")
    row_x_lines = [
        grid_separators(
            sheet.crop((0, y_lines[row], sheet.width, y_lines[row + 1])),
            parts=SHEET_COLUMNS,
            axis="x",
        )
        for row in range(SHEET_ROWS)
    ]
    source_rects = [
        (
            row_x_lines[row][column],
            y_lines[row],
            row_x_lines[row][column + 1],
            y_lines[row + 1],
        )
        for row in range(SHEET_ROWS)
        for column in range(SHEET_COLUMNS)
    ]
    cell_width = max(right - left for left, _, right, _ in source_rects)
    cell_height = max(bottom - top for _, top, _, bottom in source_rects)

    cells: list[PreparedCell] = []
    for index in range(FRAME_COUNT):
        row = index // SHEET_COLUMNS
        column = index % SHEET_COLUMNS
        source_rect = source_rects[index]
        source_cell = sheet.crop(source_rect)
        padded_cell = Image.new("RGBA", (cell_width, cell_height), (0, 0, 0, 0))
        padded_cell.paste(
            source_cell,
            ((cell_width - source_cell.width) // 2, (cell_height - source_cell.height) // 2),
        )
        cells.append(
            prepare_cell(
                padded_cell,
                index=index,
                chroma_key=chroma_key,
                near_distance=near_distance,
                far_distance=far_distance,
                edge_radius=edge_radius,
            )
        )

    scale, anchor_x, relative_lefts, dimensions = determine_shared_geometry(
        cells,
        cell_width=cell_width,
    )
    clip_directory = output_root / name
    frame_records: list[dict[str, Any]] = []

    for cell, relative_left, (scaled_width, scaled_height) in zip(
        cells,
        relative_lefts,
        dimensions,
    ):
        crop = cell.image.crop(tuple(cell.bounds.as_list()))
        resized = premultiplied_resize(crop, (scaled_width, scaled_height))
        # Lanczos can reintroduce a few key-coloured RGB samples into the new
        # fractional-alpha boundary.  Run the same edge-local despill once
        # more at output resolution so the runtime texture is halo-free.
        resized, _ = suppress_edge_spill(
            resized,
            chroma_key=chroma_key,
            edge_radius=max(2, edge_radius // 2),
            strength=1.0,
            spill_tolerance=0.15,
        )
        destination_x = anchor_x + relative_left
        destination_y = TARGET_BASELINE - scaled_height
        if (
            destination_x < MINIMUM_MARGIN
            or destination_x + scaled_width > CANVAS_WIDTH - MINIMUM_MARGIN
            or destination_y < MINIMUM_MARGIN
            or destination_y + scaled_height > CANVAS_HEIGHT - MINIMUM_MARGIN
        ):
            raise PipelineError(
                f"computed destination for {name} frame {cell.index:02d} violates safe margins"
            )

        canvas = Image.new("RGBA", (CANVAS_WIDTH, CANVAS_HEIGHT), (0, 0, 0, 0))
        canvas.paste(resized, (destination_x, destination_y))
        frame_path = clip_directory / f"douhua_{name}_{cell.index:02d}.png"
        atomic_save_png(canvas, frame_path)

        output_bounds = alpha_bounds(canvas)
        if output_bounds is None:
            raise PipelineError(f"generated {name} frame {cell.index:02d} is empty")
        residue_count, maximum_excess = magenta_residue_stats(canvas)
        frame_records.append(
            {
                "index": cell.index,
                "file": frame_path.relative_to(output_root).as_posix(),
                "sha256": sha256_file(frame_path),
                "sourceCell": [
                    source_rects[cell.index][0],
                    source_rects[cell.index][1],
                    source_rects[cell.index][2] - source_rects[cell.index][0],
                    source_rects[cell.index][3] - source_rects[cell.index][1],
                ],
                "sourceAlphaBounds": cell.bounds.as_list(),
                "destination": [destination_x, destination_y, scaled_width, scaled_height],
                "outputAlphaBounds": output_bounds.as_list(),
                "visiblePixels": visible_pixel_count(canvas),
                "magentaResiduePixels": residue_count,
                "maxVisibleMagentaExcess": maximum_excess,
                "cleanup": cell.cleanup,
            }
        )

    return {
        "name": name,
        "source": display_path(source_path, project_root),
        "sourceSha256": sha256_file(source_path),
        "sheetSize": [sheet.width, sheet.height],
        "cellSize": [cell_width, cell_height],
        "gridLines": {"xByRow": row_x_lines, "y": y_lines},
        "frameCount": FRAME_COUNT,
        "sharedScale": round(scale, 8),
        "sharedSourceSlotAnchorX": anchor_x,
        "frames": frame_records,
    }


def normalize_cross_clip_anchors(
    clip_records: list[dict[str, Any]],
    output_root: Path,
) -> None:
    """Correct generated per-sheet scale drift against stable pose anchors.

    The correction is baked into each transition/reaction frame around a fixed
    bottom-center root.  Endpoint scale and center are measured from the source
    and destination stable loops, then eased across the eight-frame motion.  It
    removes apparent grow/shrink caused by independently generated sheets; it is
    not a runtime breathing or squash effect.
    """
    by_name = {record["name"]: record for record in clip_records}
    required = set(LOOP_CLIP_FOR_STATE.values()) | set(CLIP_ENDPOINT_STATES)
    if not required.issubset(by_name):
        return

    def image_for(record: dict[str, Any], index: int) -> Image.Image:
        path = output_root / record["frames"][index]["file"]
        with Image.open(path) as opened:
            return opened.convert("RGBA")

    def geometry(image: Image.Image) -> tuple[Bounds, float, float]:
        bounds = alpha_bounds(image)
        if bounds is None:
            raise PipelineError("cross-clip normalization encountered an empty frame")
        metric = math.sqrt(float(bounds.area))
        center_x = (bounds.left + bounds.right) / 2.0
        return bounds, metric, center_x

    for clip_name, (source_state, target_state) in CLIP_ENDPOINT_STATES.items():
        record = by_name[clip_name]
        source_record = by_name[LOOP_CLIP_FOR_STATE[source_state]]
        target_record = by_name[LOOP_CLIP_FOR_STATE[target_state]]
        _, source_metric, source_center = geometry(image_for(source_record, 0))
        _, target_metric, target_center = geometry(image_for(target_record, 0))
        _, first_metric, _ = geometry(image_for(record, 0))
        _, last_metric, _ = geometry(image_for(record, FRAME_COUNT - 1))
        source_scale = source_metric / first_metric
        target_scale = target_metric / last_metric

        applied_scales: list[float] = []
        for index, frame_record in enumerate(record["frames"]):
            frame_path = output_root / frame_record["file"]
            with Image.open(frame_path) as opened:
                image = opened.convert("RGBA")
            bounds = alpha_bounds(image)
            if bounds is None:
                raise PipelineError(f"{clip_name} frame {index:02d} is empty before normalization")
            crop = image.crop(tuple(bounds.as_list()))
            progress = smoothstep(index / (FRAME_COUNT - 1))
            requested_scale = source_scale + (target_scale - source_scale) * progress
            fit_scale = min(
                (CANVAS_WIDTH - MINIMUM_MARGIN * 2) / crop.width,
                (CANVAS_HEIGHT - MINIMUM_MARGIN * 2) / crop.height,
            )
            scale = min(requested_scale, fit_scale)
            width = max(1, int(round(crop.width * scale)))
            height = max(1, int(round(crop.height * scale)))
            resized = premultiplied_resize(crop, (width, height))
            resized, _ = suppress_edge_spill(
                resized,
                chroma_key=DEFAULT_KEY,
                edge_radius=3,
                strength=1.0,
                spill_tolerance=0.15,
            )
            expected_center = source_center + (target_center - source_center) * progress
            x = int(round(expected_center - width / 2.0))
            x = min(max(x, MINIMUM_MARGIN), CANVAS_WIDTH - MINIMUM_MARGIN - width)
            y = TARGET_BASELINE - height
            canvas = Image.new("RGBA", (CANVAS_WIDTH, CANVAS_HEIGHT), (0, 0, 0, 0))
            canvas.paste(resized, (x, y))
            atomic_save_png(canvas, frame_path)

            output_bounds = alpha_bounds(canvas)
            if output_bounds is None:
                raise PipelineError(f"{clip_name} frame {index:02d} became empty")
            residue, maximum_excess = magenta_residue_stats(canvas)
            frame_record["sha256"] = sha256_file(frame_path)
            frame_record["outputAlphaBounds"] = output_bounds.as_list()
            frame_record["visiblePixels"] = visible_pixel_count(canvas)
            frame_record["magentaResiduePixels"] = residue
            frame_record["maxVisibleMagentaExcess"] = maximum_excess
            frame_record["crossClipDestination"] = [x, y, width, height]
            applied_scales.append(round(scale, 8))

        record["crossClipNormalization"] = {
            "sourceState": source_state,
            "targetState": target_state,
            "sourceEndpointScale": round(source_scale, 8),
            "targetEndpointScale": round(target_scale, 8),
            "appliedScales": applied_scales,
            "root": [CANVAS_WIDTH // 2, TARGET_BASELINE],
            "easing": "smoothstep",
        }


def apply_global_display_scale(
    clip_records: list[dict[str, Any]],
    output_root: Path,
    scale: float = GLOBAL_DISPLAY_SCALE,
) -> None:
    """Reserve cross-clip normalization headroom without changing anchors."""
    if not 0.0 < scale <= 1.0:
        raise PipelineError("global display scale must be in (0, 1]")
    for record in clip_records:
        for frame_record in record["frames"]:
            frame_path = output_root / frame_record["file"]
            with Image.open(frame_path) as opened:
                image = opened.convert("RGBA")
            bounds = alpha_bounds(image)
            if bounds is None:
                raise PipelineError(f"{frame_path} is empty before global scaling")
            crop = image.crop(tuple(bounds.as_list()))
            width = max(1, int(round(crop.width * scale)))
            height = max(1, int(round(crop.height * scale)))
            resized = premultiplied_resize(crop, (width, height))
            resized, _ = suppress_edge_spill(
                resized,
                chroma_key=DEFAULT_KEY,
                edge_radius=3,
                strength=1.0,
                spill_tolerance=0.15,
            )
            center_x = (bounds.left + bounds.right) / 2.0
            x = int(round(center_x - width / 2.0))
            x = min(max(x, MINIMUM_MARGIN), CANVAS_WIDTH - MINIMUM_MARGIN - width)
            y = TARGET_BASELINE - height
            canvas = Image.new("RGBA", (CANVAS_WIDTH, CANVAS_HEIGHT), (0, 0, 0, 0))
            canvas.paste(resized, (x, y))
            atomic_save_png(canvas, frame_path)
            output_bounds = alpha_bounds(canvas)
            if output_bounds is None:
                raise PipelineError(f"{frame_path} became empty after global scaling")
            residue, maximum_excess = magenta_residue_stats(canvas)
            frame_record["sha256"] = sha256_file(frame_path)
            frame_record["outputAlphaBounds"] = output_bounds.as_list()
            frame_record["visiblePixels"] = visible_pixel_count(canvas)
            frame_record["magentaResiduePixels"] = residue
            frame_record["maxVisibleMagentaExcess"] = maximum_excess
            frame_record["globalScaleDestination"] = [x, y, width, height]
        record["globalDisplayScale"] = scale


def validate_frame(path: Path) -> dict[str, Any]:
    with Image.open(path) as opened:
        if opened.mode != "RGBA":
            raise PipelineError(f"{path} is {opened.mode}, expected RGBA")
        image = opened.copy()
    if image.size != (CANVAS_WIDTH, CANVAS_HEIGHT):
        raise PipelineError(f"{path} is {image.width}x{image.height}, expected 480x440")

    corners = [
        image.getpixel((0, 0))[3],
        image.getpixel((CANVAS_WIDTH - 1, 0))[3],
        image.getpixel((0, CANVAS_HEIGHT - 1))[3],
        image.getpixel((CANVAS_WIDTH - 1, CANVAS_HEIGHT - 1))[3],
    ]
    if any(value >= ALPHA_THRESHOLD for value in corners):
        raise PipelineError(f"{path} failed transparent-corner validation")

    bounds = alpha_bounds(image)
    if bounds is None:
        raise PipelineError(f"{path} is empty")
    margins = {
        "left": bounds.left,
        "right": CANVAS_WIDTH - bounds.right,
        "top": bounds.top,
        "bottom": CANVAS_HEIGHT - bounds.bottom,
    }
    if min(margins.values()) < MINIMUM_MARGIN:
        raise PipelineError(f"{path} violates the {MINIMUM_MARGIN}px safe area: {margins}")
    if abs(bounds.bottom - TARGET_BASELINE) > 2:
        raise PipelineError(
            f"{path} baseline is {bounds.bottom}, expected about {TARGET_BASELINE}"
        )

    visible = visible_pixel_count(image)
    if visible < 1_000 or bounds.width < 48 or bounds.height < 48:
        raise PipelineError(
            f"{path} has insufficient subject coverage: bounds={bounds.width}x{bounds.height}, "
            f"visible={visible}"
        )
    residue, maximum_excess = magenta_residue_stats(image)
    if residue:
        raise PipelineError(
            f"{path} retains {residue} visible magenta-like pixels "
            f"(max excess {maximum_excess})"
        )

    return {
        "bounds": bounds.as_list(),
        "margins": margins,
        "baseline": bounds.bottom,
        "visiblePixels": visible,
        "magentaResiduePixels": residue,
        "maxVisibleMagentaExcess": maximum_excess,
    }


def safe_manifest_frame_path(output_root: Path, relative_path: str) -> Path:
    candidate = (output_root / relative_path).resolve()
    try:
        candidate.relative_to(output_root.resolve())
    except ValueError as error:
        raise PipelineError(f"manifest frame escapes output root: {relative_path}") from error
    return candidate


def validate_manifest_data(manifest: dict[str, Any], output_root: Path) -> dict[str, Any]:
    if manifest.get("schemaVersion") != 1:
        raise PipelineError("manifest schemaVersion must be 1")
    clips = manifest.get("clips")
    if not isinstance(clips, list) or not clips:
        raise PipelineError("manifest must contain at least one clip")

    validated_frames = 0
    clip_summaries: list[dict[str, Any]] = []
    for clip in clips:
        name = clip.get("name")
        frames = clip.get("frames")
        if not isinstance(name, str) or not isinstance(frames, list):
            raise PipelineError("manifest clip has invalid name or frames")
        if clip.get("frameCount") != FRAME_COUNT or len(frames) != FRAME_COUNT:
            raise PipelineError(f"clip {name} must contain exactly eight frames")
        if [frame.get("index") for frame in frames] != list(range(FRAME_COUNT)):
            raise PipelineError(f"clip {name} frame indices are not sequential 0...7")
        if not isinstance(clip.get("sharedScale"), (float, int)) or clip["sharedScale"] <= 0:
            raise PipelineError(f"clip {name} has invalid sharedScale")

        baselines: list[int] = []
        minimum_margin = CANVAS_WIDTH
        for frame in frames:
            path = safe_manifest_frame_path(output_root, frame["file"])
            if not path.is_file():
                raise PipelineError(f"manifest frame is missing: {path}")
            digest = sha256_file(path)
            if digest != frame.get("sha256"):
                raise PipelineError(f"SHA-256 mismatch for {path}")
            result = validate_frame(path)
            baselines.append(result["baseline"])
            minimum_margin = min(minimum_margin, *result["margins"].values())
            validated_frames += 1
        clip_summaries.append(
            {
                "name": name,
                "frames": FRAME_COUNT,
                "baselines": sorted(set(baselines)),
                "minimumMargin": minimum_margin,
                "magentaResiduePixels": 0,
            }
        )

    cross_clip_errors: list[float] = []
    by_name = {clip["name"]: clip for clip in clips}
    required = set(LOOP_CLIP_FOR_STATE.values()) | set(CLIP_ENDPOINT_STATES)
    if required.issubset(by_name):
        def frame_metric(clip_name: str, index: int) -> float:
            frame = by_name[clip_name]["frames"][index]
            path = safe_manifest_frame_path(output_root, frame["file"])
            with Image.open(path) as opened:
                bounds = alpha_bounds(opened.convert("RGBA"))
            if bounds is None:
                raise PipelineError(f"cross-clip validation found empty {clip_name} frame {index}")
            return math.sqrt(float(bounds.area))

        for clip_name, (source_state, target_state) in CLIP_ENDPOINT_STATES.items():
            source_loop = LOOP_CLIP_FOR_STATE[source_state]
            target_loop = LOOP_CLIP_FOR_STATE[target_state]
            source_error = abs(
                frame_metric(clip_name, 0) / frame_metric(source_loop, 0) - 1.0
            )
            target_error = abs(
                frame_metric(clip_name, FRAME_COUNT - 1)
                / frame_metric(target_loop, 0)
                - 1.0
            )
            cross_clip_errors.extend([source_error, target_error])
        if max(cross_clip_errors) > 0.005:
            raise PipelineError(
                "cross-clip endpoint scale error exceeds 0.5%: "
                f"{max(cross_clip_errors) * 100:.3f}%"
            )

    return {
        "ok": True,
        "validatedClips": len(clips),
        "validatedFrames": validated_frames,
        "dimensions": [CANVAS_WIDTH, CANVAS_HEIGHT],
        "mode": "RGBA",
        "transparentCorners": True,
        "clipSharedScale": True,
        "targetBaseline": TARGET_BASELINE,
        "minimumMargin": MINIMUM_MARGIN,
        "magentaResiduePixels": 0,
        "crossClipEndpointScaleMaxErrorPercent": round(
            max(cross_clip_errors, default=0.0) * 100,
            4,
        ),
        "clips": clip_summaries,
    }


def parse_clip_arguments(values: Iterable[str]) -> dict[str, Path]:
    clips: dict[str, Path] = {}
    for value in values:
        if "=" not in value:
            raise PipelineError(f"invalid --clip {value!r}; expected NAME=/absolute/path.png")
        name, raw_path = value.split("=", 1)
        name = name.strip().lower()
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name):
            raise PipelineError(f"invalid clip name {name!r}")
        if name in clips:
            raise PipelineError(f"duplicate clip name {name!r}")
        clips[name] = Path(raw_path).expanduser().resolve()
    return clips


def discover_clips(project_root: Path) -> dict[str, Path]:
    search_roots = [
        project_root / "tmp" / "imagegen",
        project_root / "tmp" / "animations",
        project_root / ".build" / "imagegen",
    ]
    all_pngs: list[Path] = []
    for search_root in search_roots:
        if search_root.is_dir():
            all_pngs.extend(sorted(search_root.rglob("*.png")))

    discovered: dict[str, Path] = {}
    markers = ("4x2", "sheet", "strip", "animation", "frames")
    for name in KNOWN_CLIPS:
        candidates = [
            path
            for path in all_pngs
            if name in path.stem.lower()
            and any(marker in path.stem.lower() for marker in markers)
            and "alpha" not in path.stem.lower()
        ]
        if len(candidates) > 1:
            paths = "\n  ".join(str(path) for path in candidates)
            raise PipelineError(
                f"multiple {name} sheets discovered; select one with --clip {name}=PATH:\n  {paths}"
            )
        if candidates:
            discovered[name] = candidates[0].resolve()
    return discovered


def project_root_from_script() -> Path:
    return Path(__file__).resolve().parent.parent


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--clip",
        action="append",
        default=[],
        metavar="NAME=PATH",
        help="repeatable clip name and 4x2 chroma-key sheet path",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        help="default: Sources/DouhuaPet/Resources/Animations/v1.0-realistic",
    )
    parser.add_argument("--chroma-key", default=color_hex(DEFAULT_KEY))
    parser.add_argument("--key-near-distance", type=float, default=8.0)
    parser.add_argument("--key-far-distance", type=float, default=190.0)
    parser.add_argument("--edge-radius", type=int, default=5)
    parser.add_argument(
        "--validate-only",
        action="store_true",
        help="validate the existing output manifest and frames without processing sheets",
    )
    return parser


def run(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    project_root = project_root_from_script()
    output_root = (
        args.output_root.expanduser().resolve()
        if args.output_root
        else project_root
        / "Sources"
        / "DouhuaPet"
        / "Resources"
        / "Animations"
        / "v1.0-realistic"
    )
    manifest_path = output_root / "animation-manifest-v2.json"

    if args.validate_only:
        if not manifest_path.is_file():
            raise PipelineError(f"missing manifest: {manifest_path}")
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        result = validate_manifest_data(manifest, output_root)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    clips = parse_clip_arguments(args.clip)
    if not clips:
        clips = discover_clips(project_root)
    if not clips:
        raise PipelineError(
            "no 4x2 animation sheets found; pass one or more "
            "--clip NAME=/absolute/path.png arguments or place named sheets in tmp/imagegen"
        )

    chroma_key = parse_hex_color(args.chroma_key)
    clip_records = [
        process_clip(
            name=name,
            source_path=source_path,
            output_root=output_root,
            project_root=project_root,
            chroma_key=chroma_key,
            near_distance=args.key_near_distance,
            far_distance=args.key_far_distance,
            edge_radius=args.edge_radius,
        )
        for name, source_path in sorted(clips.items())
    ]
    apply_global_display_scale(clip_records, output_root)
    normalize_cross_clip_anchors(clip_records, output_root)
    manifest: dict[str, Any] = {
        "schemaVersion": 1,
        "generator": "Scripts/PrepareAnimationSheets.py",
        "generatorVersion": SCRIPT_VERSION,
        "algorithm": ALGORITHM,
        "sourceLayout": {
            "columns": SHEET_COLUMNS,
            "rows": SHEET_ROWS,
            "frameOrder": "row-major",
        },
        "output": {
            "canvas": [CANVAS_WIDTH, CANVAS_HEIGHT],
            "mode": "RGBA",
            "minimumMargin": MINIMUM_MARGIN,
            "targetBaseline": TARGET_BASELINE,
            "globalDisplayScale": GLOBAL_DISPLAY_SCALE,
            "alphaThreshold": ALPHA_THRESHOLD,
        },
        "chroma": {
            "key": color_hex(chroma_key),
            "keyNearDistance": args.key_near_distance,
            "keyFarDistance": args.key_far_distance,
            "edgeRadius": args.edge_radius,
            "magentaResidueTolerance": MAGENTA_RESIDUE_TOLERANCE,
        },
        "clips": clip_records,
    }
    manifest["validation"] = validate_manifest_data(manifest, output_root)
    atomic_write_json(manifest, manifest_path)

    print(
        f"Prepared {len(clip_records)} clip(s), {len(clip_records) * FRAME_COUNT} frames: "
        f"{output_root}"
    )
    for clip in clip_records:
        summary = next(
            item for item in manifest["validation"]["clips"] if item["name"] == clip["name"]
        )
        print(
            f"  {clip['name']}: 8 x 480x440 RGBA, sharedScale={clip['sharedScale']:.5f}, "
            f"baseline={summary['baselines']}, minMargin={summary['minimumMargin']}, "
            "magentaResidue=0"
        )
    print(f"Manifest: {manifest_path}")
    return 0


def main() -> None:
    try:
        raise SystemExit(run())
    except PipelineError as error:
        print(f"PrepareAnimationSheets failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
