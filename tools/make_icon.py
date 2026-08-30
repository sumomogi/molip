#!/usr/bin/env python3
"""앱 아이콘 생성. 메뉴바 게이지와 같은 언어를 쓴다 — 세그먼트 막대."""
import subprocess, sys, shutil
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024
BG = (44, 44, 46, 255)        # 중성 차콜
FG = (245, 245, 247, 255)     # 오프화이트
SEGMENTS, FILLED = 5, 3       # 작은 크기에서도 셀 수 있게 5칸만

def render() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # 바탕 (macOS 아이콘 여백을 감안해 안쪽으로)
    inset, radius = 60, 230
    d.rounded_rectangle([inset, inset, S - inset, S - inset], radius=radius, fill=BG)

    # 게이지
    total_w, gap, bar_h = 600, 24, 200
    seg_w = (total_w - gap * (SEGMENTS - 1)) / SEGMENTS
    x0 = (S - total_w) / 2
    y0 = (S - bar_h) / 2

    for i in range(SEGMENTS):
        x = x0 + i * (seg_w + gap)
        color = FG if i < FILLED else FG[:3] + (56,)   # 빈 칸은 22%
        d.rounded_rectangle([x, y0, x + seg_w, y0 + bar_h], radius=24, fill=color)

    return img

def main(out_icns: Path):
    if not shutil.which("iconutil"):
        sys.exit("iconutil 없음")

    base = render()
    iconset = out_icns.parent / "AppIcon.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    iconset.mkdir(parents=True)

    for pt in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            px = pt * scale
            suffix = "" if scale == 1 else "@2x"
            base.resize((px, px), Image.LANCZOS).save(
                iconset / f"icon_{pt}x{pt}{suffix}.png"
            )

    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out_icns)], check=True)
    shutil.rmtree(iconset, ignore_errors=True)
    print(f"아이콘 생성: {out_icns} ({out_icns.stat().st_size} bytes)")

if __name__ == "__main__":
    main(Path(sys.argv[1]))
