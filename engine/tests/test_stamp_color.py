"""Regression: blue ink must stay blue when opacity < 1."""
import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

import pymupdf

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / "main.py"
PNG = (
    ROOT.parent
    / "build/macos/Build/Products/Debug/PNG/Gemini_Generated_Image_6rxigp6rxigp6rxi.png"
)


def test_blue_stays_blue_at_partial_opacity():
    if PNG.exists():
        png = PNG
    else:
        png = Path(tempfile.mkdtemp()) / "s.png"
        pix = pymupdf.Pixmap(pymupdf.csRGB, pymupdf.IRect(0, 0, 64, 64), 1)
        samples = pix.samples_mv
        for i in range(0, len(samples), 4):
            samples[i] = samples[i + 1] = samples[i + 2] = 0
            samples[i + 3] = 255
        pix.save(png)

    tmp = Path(tempfile.mkdtemp())
    doc = pymupdf.open()
    doc.new_page(width=200, height=200)
    pdf_in = tmp / "in.pdf"
    doc.save(pdf_in)
    doc.close()

    stamps = tmp / "stamps.json"
    stamps.write_text(
        json.dumps(
            [
                {
                    "page": 0,
                    "x": 10,
                    "y": 10,
                    "width": 160,
                    "height": 160,
                    "png": str(png),
                    "opacity": 0.69,
                    "color": "#1565C0",
                    "rotate": 0,
                }
            ]
        ),
        encoding="utf-8",
    )
    out = tmp / "out.pdf"
    result = subprocess.run(
        [
            sys.executable,
            str(MAIN),
            "stamp",
            "--in",
            str(pdf_in),
            "--out",
            str(out),
            "--stamps",
            str(stamps),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    assert "ok" in result.stdout

    saved = pymupdf.open(out)
    assert saved[0].get_images(), "stamp image missing from PDF"
    rendered = saved[0].get_pixmap()
    counts = Counter(
        rendered.pixel(x, y)
        for y in range(rendered.height)
        for x in range(rendered.width)
        if rendered.pixel(x, y) != (255, 255, 255)
    )
    assert counts, "stamp not visible on page"
    top, _ = counts.most_common(1)[0]
    # Blue must dominate green (the previous overflow bug).
    assert top[2] > top[1], top
    saved.close()


if __name__ == "__main__":
    test_blue_stays_blue_at_partial_opacity()
    print("ok")
