#!/usr/bin/env python3
"""Remove the generated far-side leg layer from Douhua's tiny walk frames."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


# At 160x120 these polygons cover only the darker, far-side leg. The near-side
# fore/hind legs remain intact. Keeping the correction after normalization makes
# it deterministic even if the original generated sheet has uneven cell sizes.
WALK_LEG_RECTS: dict[int, tuple[int, int, int, int]] = {
    4: (76, 88, 109, 112),
    5: (88, 88, 116, 112),
    6: (80, 88, 105, 112),
    7: (78, 88, 103, 112),
}

# Register the four locomotion drawings against the same head/torso landmark.
# The generated cells were planted on one baseline but wandered horizontally by
# as much as 12 source pixels, which looked like camera shake once the panel also
# moved. These offsets preserve a transparent margin on both sides.
WALK_X_OFFSETS: dict[int, int] = {
    4: -3,
    5: -3,
    6: 9,
    7: 14,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--input-prefix", default="douhua_pixel_v4")
    parser.add_argument("--output-prefix", default="douhua_pixel_v4_clean")
    return parser.parse_args()


def keep_largest_alpha_component(image: Image.Image) -> None:
    pixels = image.load()
    width, height = image.size
    visible = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if pixels[x, y][3] >= 24
    }
    components: list[set[tuple[int, int]]] = []

    while visible:
        seed = visible.pop()
        component = {seed}
        stack = [seed]
        while stack:
            x, y = stack.pop()
            for next_y in range(max(0, y - 1), min(height, y + 2)):
                for next_x in range(max(0, x - 1), min(width, x + 2)):
                    neighbor = (next_x, next_y)
                    if neighbor in visible:
                        visible.remove(neighbor)
                        component.add(neighbor)
                        stack.append(neighbor)
        components.append(component)

    if not components:
        return
    largest = max(components, key=len)
    for component in components:
        if component is largest:
            continue
        for x, y in component:
            pixels[x, y] = (0, 0, 0, 0)


def translate_x(image: Image.Image, offset: int) -> Image.Image:
    registered = Image.new("RGBA", image.size, (0, 0, 0, 0))
    registered.alpha_composite(image, (offset, 0))
    return registered


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for index in range(8):
        source = args.input_dir / f"{args.input_prefix}_{index:02d}.png"
        image = Image.open(source).convert("RGBA")
        if index in WALK_LEG_RECTS:
            left, top, right, bottom = WALK_LEG_RECTS[index]
            pixels = image.load()
            for y in range(top, bottom):
                for x in range(left, right):
                    if pixels[x, y][3] >= 24:
                        pixels[x, y] = (0, 0, 0, 0)
        keep_largest_alpha_component(image)
        if index in WALK_X_OFFSETS:
            image = translate_x(image, WALK_X_OFFSETS[index])
        destination = args.output_dir / f"{args.output_prefix}_{index:02d}.png"
        image.save(destination, optimize=True)

    print(f"Wrote 8 no-overlap frames to {args.output_dir}")


if __name__ == "__main__":
    main()
