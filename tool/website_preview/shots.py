"""把 website_shots_test 拍的畫面轉成網站用的檔案。

    python -I tool/website_preview/shots.py [名稱 ...]

- `<暫存>/night-reader-screens/web/<名稱>.png` → `website/proto/shots/<名稱>.webp`
  （手機縮成 2/3、寬 786；平板縮成寬 1000）
- `<暫存>/night-reader-screens/web-clips/<名稱>/f0000.png…` →
  `website/proto/clips/<名稱>.mp4`（30 fps、H.264、寬 786）與
  `website/proto/shots/<名稱>.webp`（最後一格，當短片載入前的封面）

沒給名稱就全部轉。要有 ffmpeg 與 Pillow。
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SRC = Path(tempfile.gettempdir()) / "night-reader-screens"
SHOTS = ROOT / "website" / "proto" / "shots"
CLIPS = ROOT / "website" / "proto" / "clips"


def width_for(image: Image.Image) -> int:
    # 手機 1179 寬縮成 786；平板 1600 寬縮成 1000。
    return 786 if image.width < 1400 else 1000


def save_webp(png: Path, out: Path) -> None:
    image = Image.open(png).convert("RGB")
    w = width_for(image)
    h = round(image.height * w / image.width)
    image.resize((w, h), Image.LANCZOS).save(out, "WEBP", quality=82, method=6)
    print(f"{out.relative_to(ROOT)}  {out.stat().st_size // 1024} KB")


def save_clip(folder: Path) -> None:
    frames = sorted(folder.glob("f*.png"))
    if not frames:
        return
    out = CLIPS / f"{folder.name}.mp4"
    subprocess.run(
        [
            "ffmpeg", "-y", "-loglevel", "error", "-framerate", "30",
            "-i", str(folder / "f%04d.png"),
            "-vf", "scale=786:-2:flags=lanczos", "-c:v", "libx264",
            "-pix_fmt", "yuv420p", "-crf", "24", "-preset", "slow",
            "-movflags", "+faststart", str(out),
        ],
        check=True,
    )
    print(f"{out.relative_to(ROOT)}  {out.stat().st_size // 1024} KB  {len(frames)} 格")
    save_webp(frames[-1], SHOTS / f"{folder.name}.webp")


def main(names: list[str]) -> None:
    SHOTS.mkdir(parents=True, exist_ok=True)
    CLIPS.mkdir(parents=True, exist_ok=True)
    for png in sorted((SRC / "web").glob("*.png")):
        if not names or png.stem in names:
            save_webp(png, SHOTS / f"{png.stem}.webp")
    clips = SRC / "web-clips"
    if clips.exists():
        for folder in sorted(p for p in clips.iterdir() if p.is_dir()):
            if not names or folder.name in names:
                save_clip(folder)


if __name__ == "__main__":
    os.chdir(ROOT)
    main(sys.argv[1:])
