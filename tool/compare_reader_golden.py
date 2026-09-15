"""Compare bounded C6 screenshot checkpoints with a deterministic tolerance.

This host-side utility intentionally uses Pillow instead of adding an image
runtime dependency to the Flutter app.  It compares fixed-resolution PNGs,
counts per-channel differences above the calibrated tolerance, and writes a
diff only for a failed checkpoint.  ``--probe-micro-shift`` is an explicit
negative proof: it shifts the in-memory actual image by one pixel without
modifying the supplied artifact.
"""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path

from PIL import Image


def compare_one(expected: Path, actual: Path, diff_dir: Path, channel_tolerance: int,
                max_bad_ratio: float, probe_micro_shift: bool) -> dict:
    expected_image = Image.open(expected).convert("RGBA")
    actual_image = Image.open(actual).convert("RGBA")
    if probe_micro_shift:
        shifted = Image.new("RGBA", actual_image.size, (255, 255, 255, 255))
        shifted.paste(actual_image, (1, 0))
        actual_image = shifted

    result = {
        "checkpoint": expected.name,
        "expected": str(expected),
        "actual": str(actual),
        "width": expected_image.width,
        "height": expected_image.height,
        "channelTolerance": channel_tolerance,
        "maxBadRatio": max_bad_ratio,
    }
    if expected_image.size != actual_image.size:
        result.update({"status": "failed", "reason": "dimension-mismatch"})
        return result

    expected_pixels = list(expected_image.getdata())
    actual_pixels = list(actual_image.getdata())
    bad_pixels = 0
    total_abs = 0
    diff_pixels = []
    for left, right in zip(expected_pixels, actual_pixels):
        distance = [abs(a - b) for a, b in zip(left, right)]
        total_abs += sum(distance)
        bad = any(value > channel_tolerance for value in distance)
        bad_pixels += int(bad)
        diff_pixels.append((255, 0, 0, 255) if bad else (0, 0, 0, 0))
    pixel_count = len(expected_pixels)
    bad_ratio = bad_pixels / pixel_count if pixel_count else 1.0
    mean_abs = total_abs / (pixel_count * 4) if pixel_count else 255.0
    passed = bad_ratio <= max_bad_ratio
    result.update({
        "status": "passed" if passed else "failed",
        "badPixels": bad_pixels,
        "badPixelRatio": bad_ratio,
        "meanAbsoluteChannelDifference": mean_abs,
    })
    if not passed:
        diff_dir.mkdir(parents=True, exist_ok=True)
        diff = Image.new("RGBA", expected_image.size)
        diff.putdata(diff_pixels)
        diff_path = diff_dir / f"{expected.stem}.diff.png"
        diff.save(diff_path)
        result["diff"] = str(diff_path)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--channel-tolerance", type=int, default=8)
    parser.add_argument("--max-bad-ratio", type=float, default=0.001)
    parser.add_argument("--probe-micro-shift", action="store_true")
    args = parser.parse_args()
    if args.channel_tolerance < 0 or args.max_bad_ratio < 0:
        parser.error("tolerance values must be non-negative")
    expected_files = {path.name: path for path in args.expected.glob("*.png")}
    actual_files = {path.name: path for path in args.actual.glob("*.png")}
    names = sorted(set(expected_files) | set(actual_files))
    results = []
    diff_dir = args.report.parent / f"{args.report.stem}-diff"
    for name in names:
        if name not in expected_files or name not in actual_files:
            results.append({"checkpoint": name, "status": "failed", "reason": "missing-file"})
            continue
        results.append(compare_one(
            expected_files[name], actual_files[name], diff_dir,
            args.channel_tolerance, args.max_bad_ratio, args.probe_micro_shift,
        ))
    summary = {
        "schemaVersion": 1,
        "status": "passed" if results and all(item["status"] == "passed" for item in results) else "failed",
        "expectedDir": str(args.expected),
        "actualDir": str(args.actual),
        "checkpointCount": len(results),
        "channelTolerance": args.channel_tolerance,
        "maxBadRatio": args.max_bad_ratio,
        "probeMicroShift": args.probe_micro_shift,
        "results": results,
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, separators=(",", ":")))
    return 0 if summary["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
