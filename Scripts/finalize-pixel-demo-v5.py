#!/usr/bin/env python3
"""Remove cell-boundary debris and register v5 without deleting any legs."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


# Registration was measured against the upper-body silhouette, excluding paws.
# All four anatomical legs remain untouched.
WALK_X_OFFSETS: dict[int, int] = {
    4: -2,
    5: 0,
    6: 0,
    7: 0,
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--input-prefix", default="douhua_pixel_v5")
    parser.add_argument("--output-prefix", default="douhua_pixel_v5_final")
    return parser.parse_args()


def keep_largest_alpha_component(image: Image.Image) -> None:
    pixels = image.load()
    width, height = image.size
    # Alpha 12 preserves the deliberate one-pixel joints while separating the
    # faint matte that can connect a neighboring cell fragment to the subject.
    visible = {
        (x, y)
        for y in range(height)
        for x in range(width)
        if pixels[x, y][3] >= 12
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
    for y in range(height):
        for x in range(width):
            if (x, y) not in largest:
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
        keep_largest_alpha_component(image)
        if index in WALK_X_OFFSETS:
            image = translate_x(image, WALK_X_OFFSETS[index])
        destination = args.output_dir / f"{args.output_prefix}_{index:02d}.png"
        image.save(destination, optimize=True)

    print(f"Wrote 8 four-leg registered frames to {args.output_dir}")


if __name__ == "__main__":
    main()
