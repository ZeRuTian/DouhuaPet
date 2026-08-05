#!/usr/bin/env python3
"""Split, normalize, and align the generated Douhua pixel sprite sheet."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path

from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--width", type=int, default=192)
    parser.add_argument("--height", type=int, default=144)
    parser.add_argument("--ground", type=int, default=136)
    parser.add_argument("--prefix", default="douhua_pixel")
    parser.add_argument(
        "--scale-multiplier",
        type=float,
        default=1.0,
        help="apply a final shared scale adjustment without changing registration",
    )
    parser.add_argument(
        "--fixed-scale",
        type=float,
        help="use an identity-calibrated source-to-runtime scale instead of fitting the longest pose",
    )
    parser.add_argument(
        "--horizontal-padding",
        type=int,
        default=8,
        help="total transparent horizontal padding reserved before scaling",
    )
    parser.add_argument(
        "--component-split",
        action="store_true",
        help="extract the eight largest complete subjects instead of hard 4x2 cuts",
    )
    parser.add_argument(
        "--fill-alpha-holes",
        type=int,
        default=0,
        metavar="MAX_PIXELS",
        help="fill fully enclosed transparent components up to this size",
    )
    return parser.parse_args()


def split_cells(sheet: Image.Image) -> list[Image.Image]:
    cells: list[Image.Image] = []
    for row in range(2):
        y0 = round(row * sheet.height / 2)
        y1 = round((row + 1) * sheet.height / 2)
        for column in range(4):
            x0 = round(column * sheet.width / 4)
            x1 = round((column + 1) * sheet.width / 4)
            cells.append(sheet.crop((x0, y0, x1, y1)))
    return cells


def subject_component_boxes(sheet: Image.Image) -> list[tuple[int, int, int, int]]:
    alpha = sheet.getchannel("A")
    width, height = sheet.size
    visible = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if alpha.getpixel((x, y)) >= 12
    }
    components: list[tuple[int, tuple[int, int, int, int]]] = []

    while visible:
        seed = visible.pop()
        stack = [seed]
        count = 0
        minimum_x = maximum_x = seed[0]
        minimum_y = maximum_y = seed[1]
        while stack:
            x, y = stack.pop()
            count += 1
            minimum_x = min(minimum_x, x)
            maximum_x = max(maximum_x, x)
            minimum_y = min(minimum_y, y)
            maximum_y = max(maximum_y, y)
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = (next_x, next_y)
                    if neighbor in visible:
                        visible.remove(neighbor)
                        stack.append(neighbor)
        components.append(
            (count, (minimum_x, minimum_y, maximum_x + 1, maximum_y + 1))
        )

    subjects = [box for _, box in sorted(components, reverse=True)[:8]]
    if len(subjects) != 8 or any(
        (right - left) * (bottom - top) < 10_000
        for left, top, right, bottom in subjects
    ):
        raise RuntimeError("could not identify eight complete sprite subjects")

    subjects.sort(key=lambda box: ((box[1] + box[3]) * 0.5, (box[0] + box[2]) * 0.5))
    top_row = sorted(subjects[:4], key=lambda box: (box[0] + box[2]) * 0.5)
    bottom_row = sorted(subjects[4:], key=lambda box: (box[0] + box[2]) * 0.5)
    return top_row + bottom_row


def split_subject_components(sheet: Image.Image) -> list[Image.Image]:
    cells: list[Image.Image] = []
    for left, top, right, bottom in subject_component_boxes(sheet):
        margin = 4
        crop = (
            max(0, left - margin),
            max(0, top - margin),
            min(sheet.width, right + margin),
            min(sheet.height, bottom + margin),
        )
        cells.append(sheet.crop(crop))
    return cells


def visible_bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value >= 24 else 0).getbbox()
    if bbox is None:
        raise RuntimeError("Sprite cell is empty")
    return bbox


def fill_small_alpha_holes(image: Image.Image, maximum_size: int) -> Image.Image:
    if maximum_size <= 0:
        return image

    result = image.copy()
    pixels = result.load()
    width, height = result.size
    transparent = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if pixels[x, y][3] == 0
    }

    while transparent:
        seed = transparent.pop()
        component = {seed}
        stack = [seed]
        touches_edge = seed[0] in (0, width - 1) or seed[1] in (0, height - 1)
        boundary_colors: list[tuple[int, int, int]] = []

        while stack:
            x, y = stack.pop()
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = (next_x, next_y)
                    if neighbor in transparent:
                        transparent.remove(neighbor)
                        component.add(neighbor)
                        stack.append(neighbor)
                        touches_edge = touches_edge or next_x in (0, width - 1) or next_y in (0, height - 1)
                    elif neighbor not in component and pixels[next_x, next_y][3] > 0:
                        boundary_colors.append(pixels[next_x, next_y][:3])

        if not touches_edge and len(component) <= maximum_size and boundary_colors:
            red, green, blue = Counter(boundary_colors).most_common(1)[0][0]
            for x, y in component:
                pixels[x, y] = (red, green, blue, 255)

    return result


def main() -> None:
    args = parse_args()
    sheet = Image.open(args.input).convert("RGBA")
    cells = split_subject_components(sheet) if args.component_split else split_cells(sheet)
    boxes = [visible_bbox(cell) for cell in cells]

    largest_width = max(right - left for left, _, right, _ in boxes)
    largest_height = max(bottom - top for _, top, _, bottom in boxes)
    fitted_scale = min(
        (args.width - args.horizontal_padding) / largest_width,
        (args.height - 12) / largest_height,
    )
    scale = (args.fixed_scale if args.fixed_scale is not None else fitted_scale) * args.scale_multiplier
    if scale <= 0:
        raise RuntimeError("sprite scale must be positive")
    if largest_width * scale > args.width or largest_height * scale > args.height:
        raise RuntimeError(
            "fixed sprite scale exceeds the target canvas; enlarge the transparent canvas "
            "instead of shrinking the character identity"
        )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index, (cell, box) in enumerate(zip(cells, boxes)):
        left, top, right, bottom = box
        sprite = cell.crop(box)
        scaled_size = (
            max(1, round(sprite.width * scale)),
            max(1, round(sprite.height * scale)),
        )
        sprite = sprite.resize(scaled_size, Image.Resampling.NEAREST)

        # Preserve the generated sheet's per-cell horizontal registration while
        # planting every frame on one shared ground line. This prevents the
        # camera-shake effect caused by independently trimmed sprite frames.
        cell_center_from_left = cell.width * 0.5 - left
        destination_x = round(args.width * 0.5 - cell_center_from_left * scale)
        destination_y = args.ground - sprite.height

        frame = Image.new("RGBA", (args.width, args.height), (0, 0, 0, 0))
        frame.alpha_composite(sprite, (destination_x, destination_y))
        frame = fill_small_alpha_holes(frame, args.fill_alpha_holes)
        frame.save(args.output_dir / f"{args.prefix}_{index:02d}.png", optimize=True)

    print(
        f"Prepared {len(cells)} frames at {args.width}x{args.height}; "
        f"shared scale={scale:.4f}; ground={args.ground}"
    )


if __name__ == "__main__":
    main()
