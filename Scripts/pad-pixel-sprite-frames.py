#!/usr/bin/env python3
"""Pad existing transparent sprite frames without rescaling their character pixels."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--input-prefix", required=True)
    parser.add_argument("--output-prefix", required=True)
    parser.add_argument("--count", type=int, default=8)
    parser.add_argument("--width", type=int, default=200)
    parser.add_argument("--height", type=int, default=120)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index in range(args.count):
        source = args.input_dir / f"{args.input_prefix}_{index:02d}.png"
        image = Image.open(source).convert("RGBA")
        if image.width > args.width or image.height > args.height:
            raise RuntimeError(f"{source} is larger than target canvas")
        frame = Image.new("RGBA", (args.width, args.height), (0, 0, 0, 0))
        frame.alpha_composite(
            image,
            ((args.width - image.width) // 2, args.height - image.height),
        )
        frame.save(
            args.output_dir / f"{args.output_prefix}_{index:02d}.png",
            optimize=True,
        )
    print(f"Padded {args.count} frames to {args.width}x{args.height} without rescaling")


if __name__ == "__main__":
    main()
