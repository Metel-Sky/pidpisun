#!/usr/bin/env python3
"""CLI for Підписун: DOCX→PDF conversion and PNG stamps on PDF."""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def _configure_stdio() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, OSError):
            pass


def _emit_ok(out: Path) -> None:
    json.dump({"ok": True, "out": str(out)}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def _fail(message: str, code: int = 1) -> None:
    json.dump({"ok": False, "error": message}, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _find_soffice() -> str | None:
    found = shutil.which("soffice") or shutil.which("libreoffice")
    if found:
        return found
    candidates = [
        Path("/Applications/LibreOffice.app/Contents/MacOS/soffice"),
        Path(r"C:\Program Files\LibreOffice\program\soffice.exe"),
        Path(r"C:\Program Files (x86)\LibreOffice\program\soffice.exe"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return None


def convert_docx(input_path: Path, output_path: Path) -> None:
    if not input_path.is_file():
        _fail(f"Файл не знайдено: {input_path}")
    if input_path.suffix.lower() != ".docx":
        _fail("Конвертація підтримує лише файли .docx")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    errors: list[str] = []

    try:
        from docx2pdf import convert as docx2pdf_convert

        docx2pdf_convert(str(input_path), str(output_path))
        if output_path.is_file():
            return
        errors.append("docx2pdf не створив PDF")
    except Exception as exc:  # noqa: BLE001 — surface Word/COM failures to the user
        errors.append(f"docx2pdf / Microsoft Word: {exc}")

    soffice = _find_soffice()
    if soffice:
        try:
            subprocess.run(
                [
                    soffice,
                    "--headless",
                    "--norestore",
                    "--convert-to",
                    "pdf",
                    "--outdir",
                    str(output_path.parent),
                    str(input_path),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            produced = output_path.parent / f"{input_path.stem}.pdf"
            if produced.is_file() and produced.resolve() != output_path.resolve():
                if output_path.exists():
                    output_path.unlink()
                produced.replace(output_path)
            if output_path.is_file():
                return
            errors.append("LibreOffice не створив PDF")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"LibreOffice: {exc}")
    else:
        errors.append("LibreOffice не знайдено")

    _fail(
        "Не вдалося конвертувати DOCX. Встановіть Microsoft Word або LibreOffice. "
        + " ".join(errors)
    )


def _parse_stamp_color(value):
    if value is None or value == "":
        return None
    if isinstance(value, int):
        return ((value >> 16) & 255, (value >> 8) & 255, value & 255)
    text = str(value).strip()
    if text.startswith("#"):
        text = text[1:]
    if len(text) == 8:
        text = text[2:]
    if len(text) != 6:
        return None
    try:
        return (int(text[0:2], 16), int(text[2:4], 16), int(text[4:6], 16))
    except ValueError:
        return None


def _pixmap_with_opacity(pymupdf, png: Path, opacity: float, color=None):
    pix = pymupdf.Pixmap(str(png))
    if pix.colorspace is not None and pix.colorspace.n != 3:
        pix = pymupdf.Pixmap(pymupdf.csRGB, pix)
    rgb = _parse_stamp_color(color)
    factor = min(1.0, max(0.05, opacity))
    needs_alpha = rgb is not None or factor < 0.999
    if needs_alpha and pix.alpha == 0:
        pix = pymupdf.Pixmap(pix, 1)
    if rgb is None and factor >= 0.999:
        return _premultiply_rgba(pix)
    samples = pix.samples_mv
    stride = pix.n
    for i in range(0, len(samples), stride):
        if rgb is not None and stride >= 3:
            samples[i] = rgb[0]
            samples[i + 1] = rgb[1]
            samples[i + 2] = rgb[2]
        if factor < 0.999:
            samples[i + stride - 1] = int(samples[i + stride - 1] * factor)
    return _premultiply_rgba(pix)


def _premultiply_rgba(pix):
    """Premultiply RGB by alpha before insert_image.

    MuPDF un-premultiplies when embedding RGBA; if a channel is brighter than
    alpha (common for blue ink at partial opacity), that overflows and blue
    becomes green in the saved PDF.
    """
    if pix.alpha == 0:
        return pix
    samples = pix.samples_mv
    stride = pix.n
    for i in range(0, len(samples), stride):
        alpha = samples[i + stride - 1]
        if alpha == 0:
            samples[i] = 0
            samples[i + 1] = 0
            samples[i + 2] = 0
        elif alpha < 255:
            samples[i] = samples[i] * alpha // 255
            samples[i + 1] = samples[i + 1] * alpha // 255
            samples[i + 2] = samples[i + 2] * alpha // 255
    return pix


def _aabb_rotated(pymupdf, rect, ccw_degrees: float):
    mat = pymupdf.Matrix(ccw_degrees)
    center = pymupdf.Point((rect.x0 + rect.x1) / 2.0, (rect.y0 + rect.y1) / 2.0)
    xs = []
    ys = []
    for point in (rect.tl, rect.tr, rect.bl, rect.br):
        rotated = pymupdf.Point(point.x - center.x, point.y - center.y) * mat
        xs.append(rotated.x + center.x)
        ys.append(rotated.y + center.y)
    return pymupdf.Rect(min(xs), min(ys), max(xs), max(ys))


def _insert_stamp(page, pymupdf, rect, pixmap, rotate_cw: float) -> None:
    if abs(rotate_cw) <= 0.05:
        page.insert_image(rect, pixmap=pixmap, overlay=True, keep_proportion=False)
        return

    # insert_image() in this PyMuPDF only accepts a Rect, not a rotated Quad.
    src = pymupdf.open()
    try:
        src_page = src.new_page(
            width=max(1.0, float(rect.width)),
            height=max(1.0, float(rect.height)),
        )
        src_page.insert_image(
            src_page.rect,
            pixmap=pixmap,
            overlay=True,
            keep_proportion=False,
        )
        bbox = _aabb_rotated(pymupdf, rect, -rotate_cw)
        if bbox.is_empty or bbox.is_infinite:
            bbox = rect
        page.show_pdf_page(
            bbox,
            src,
            0,
            overlay=True,
            keep_proportion=True,
            rotate=-rotate_cw,
        )
    finally:
        src.close()


def stamp_pdf(input_path: Path, output_path: Path, stamps_path: Path) -> None:
    if not input_path.is_file():
        _fail(f"PDF не знайдено: {input_path}")
    if not stamps_path.is_file():
        _fail(f"Файл штампів не знайдено: {stamps_path}")

    try:
        import pymupdf
    except ImportError:
        _fail("Не встановлено pymupdf. Виконайте: pip install -r engine/requirements.txt")

    try:
        stamps = json.loads(stamps_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        _fail(f"Некоректний JSON штампів: {exc}")

    if not isinstance(stamps, list):
        _fail("stamps.json має бути списком об'єктів")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    doc = pymupdf.open(input_path)
    try:
        for index, item in enumerate(stamps):
            if not isinstance(item, dict):
                _fail(f"Штамп #{index} має бути об'єктом")
            try:
                page_index = int(item["page"])
                x = float(item["x"])
                y = float(item["y"])
                width = float(item["width"])
                height = float(item["height"])
                png = Path(str(item["png"]))
                opacity = float(item.get("opacity", 1.0))
                color = item.get("color")
                rotate = float(item.get("rotate", 0.0))
            except (KeyError, TypeError, ValueError) as exc:
                _fail(f"Штамп #{index}: некоректні поля ({exc})")
            if not png.is_file():
                _fail(f"PNG не знайдено: {png}")
            if page_index < 0 or page_index >= doc.page_count:
                _fail(f"Сторінка {page_index + 1} не існує (усього {doc.page_count})")
            page = doc[page_index]
            rect = pymupdf.Rect(x, y, x + width, y + height)
            pixmap = _pixmap_with_opacity(pymupdf, png, opacity, color)
            _insert_stamp(page, pymupdf, rect, pixmap, rotate)
        if output_path.resolve() == input_path.resolve():
            _fail("Вихідний файл не може збігатися з оригіналом")
        doc.save(output_path, garbage=4, deflate=True)
    finally:
        doc.close()

    if not output_path.is_file():
        _fail("Не вдалося зберегти PDF")


def main() -> None:
    _configure_stdio()
    parser = argparse.ArgumentParser(description="Підписун PDF engine")
    sub = parser.add_subparsers(dest="command", required=True)

    convert_parser = sub.add_parser("convert", help="DOCX → PDF")
    convert_parser.add_argument("--in", dest="input_path", required=True)
    convert_parser.add_argument("--out", dest="output_path", required=True)

    stamp_parser = sub.add_parser("stamp", help="Накласти PNG на PDF")
    stamp_parser.add_argument("--in", dest="input_path", required=True)
    stamp_parser.add_argument("--out", dest="output_path", required=True)
    stamp_parser.add_argument("--stamps", dest="stamps_path", required=True)

    args = parser.parse_args()
    try:
        if args.command == "convert":
            output = Path(args.output_path)
            convert_docx(Path(args.input_path), output)
            _emit_ok(output)
        elif args.command == "stamp":
            output = Path(args.output_path)
            stamp_pdf(Path(args.input_path), output, Path(args.stamps_path))
            _emit_ok(output)
        else:
            _fail(f"Невідома команда: {args.command}")
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        _fail(str(exc))


if __name__ == "__main__":
    main()
