#!/usr/bin/env python3
"""Render every packaged animation at normal and quarter speed for visual QA."""

from __future__ import annotations

import json
import shlex
import subprocess
import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def run(command: list[str]) -> None:
    subprocess.run(command, check=True, cwd=ROOT)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--animation-root",
        type=Path,
        default=ROOT / "Sources/DouhuaPet/Resources/Animations/Douhua/v3-smooth",
    )
    args = parser.parse_args()
    animation_root = args.animation_root.expanduser().resolve()
    manifests = sorted(animation_root.glob("animation-manifest-v*.json"))
    if len(manifests) != 1:
        raise SystemExit(f"expected one animation manifest in {animation_root}")
    manifest = json.loads(manifests[0].read_text(encoding="utf-8"))
    output_root = ROOT / ".build" / f"animation-review-{animation_root.name}"
    output_root.mkdir(parents=True, exist_ok=True)
    rendered: list[Path] = []
    for record in manifest["clips"]:
        clip = record["id"]
        sequence = output_root / f"{clip}.ffconcat"
        lines = ["ffconcat version 1.0"]
        for file, duration in zip(record["files"], record["durations"]):
            path = (animation_root / clip / file).resolve()
            lines.append(f"file {shlex.quote(str(path))}")
            lines.append(f"duration {duration:.6f}")
        last = (animation_root / clip / record["files"][-1]).resolve()
        lines.append(f"file {shlex.quote(str(last))}")
        sequence.write_text("\n".join(lines) + "\n", encoding="utf-8")

        output = output_root / f"{clip}.mp4"
        filter_graph = (
            "color=c=0xE8E8E8:s=480x440:r=60[bg];"
            "[0:v]format=rgba[fg];"
            "[bg][fg]overlay=shortest=1,fps=60[out]"
        )
        run(
            [
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-f", "concat", "-safe", "0", "-i", str(sequence),
                "-filter_complex", filter_graph, "-map", "[out]",
                "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", str(output),
            ]
        )
        rendered.append(output)

    concat = output_root / "all-clips.ffconcat"
    concat.write_text(
        "ffconcat version 1.0\n"
        + "\n".join(f"file {shlex.quote(str(path.resolve()))}" for path in rendered)
        + "\n",
        encoding="utf-8",
    )
    normal = output_root / "douhua-all-actions-1x.mp4"
    slow = output_root / "douhua-all-actions-0.25x.mp4"
    run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "concat", "-safe", "0", "-i", str(concat),
            "-c", "copy", str(normal),
        ]
    )
    run(
        [
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
            "-i", str(normal), "-vf", "setpts=4*PTS", "-an",
            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "16", str(slow),
        ]
    )
    print(normal)
    print(slow)


if __name__ == "__main__":
    main()
