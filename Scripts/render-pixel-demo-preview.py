#!/usr/bin/env python3
"""Render a compact GIF that mirrors the pixel demo's animation timing."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("frames_dir", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--prefix", default="douhua_pixel")
    parser.add_argument("--display-scale", type=int, default=2)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    sprites = []
    for index in range(8):
        sprite = Image.open(
            args.frames_dir / f"{args.prefix}_{index:02d}.png"
        ).convert("RGBA")
        sprite = sprite.resize(
            (
                sprite.width * args.display_scale,
                sprite.height * args.display_scale,
            ),
            Image.Resampling.NEAREST,
        )
        sprites.append(sprite)

    fps = 20
    seconds = 6
    output_frames: list[Image.Image] = []
    for frame_number in range(fps * seconds):
        time = frame_number / fps
        canvas = Image.new("RGB", (960, 320), (238, 233, 222))
        draw = ImageDraw.Draw(canvas)
        draw.rectangle((0, 294, 960, 319), fill=(224, 216, 201))

        if time < 2:
            x = 72
            sprite_index = 6
        elif time < 5:
            progress = (time - 2) / 3
            eased = progress * progress * (3 - 2 * progress)
            x = round(72 + eased * 500)
            sprite_index = 4 + int((time - 2) / 0.115) % 4
        else:
            x = 572
            sprite_index = 6

        sprite = sprites[sprite_index]
        sprite_y = 294 - 112 * args.display_scale
        canvas.paste(sprite, (x, sprite_y), sprite)
        output_frames.append(canvas)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output_frames[0].save(
        args.output,
        save_all=True,
        append_images=output_frames[1:],
        duration=round(1000 / fps),
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"Rendered {len(output_frames)} preview frames to {args.output}")


if __name__ == "__main__":
    main()
