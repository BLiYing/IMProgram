#!/usr/bin/env python3
"""Generate the shared folded-document file icon family for iOS and im-web."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from xml.sax.saxutils import escape


TEXT_STYLE = (
    'fill="#fff" font-family="-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif" '
    'font-weight="800" text-anchor="middle"'
)


def text(label: str, size: int = 30, y: int = 82) -> str:
    return f'<text x="60" y="{y}" font-size="{size}" {TEXT_STYLE}>{escape(label)}</text>'


ICONS: dict[str, tuple[str, str, str]] = {
    "pdf": ("#ff6558", "#dc302c", text("PDF", 25)),
    "word": ("#4a82ff", "#164fd0", text("W", 43, 87)),
    "excel": ("#35c77e", "#07844d", text("X", 43, 87)),
    "powerpoint": ("#ff8254", "#d74928", text("PPT", 22)),
    "csv": (
        "#31cbc4", "#0a9197",
        '<g fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round">'
        '<rect x="34" y="48" width="52" height="45" rx="5"/>'
        '<path d="M34 63h52M34 78h52M51 48v45M69 48v45"/></g>',
    ),
    "pages": (
        "#ffb52b", "#ed8200",
        '<g fill="none" stroke="#fff" stroke-width="8" stroke-linecap="round">'
        '<path d="M39 87 76 50"/><path d="M35 94h52"/></g>',
    ),
    "numbers": (
        "#68dc55", "#22a630",
        '<g fill="#fff"><rect x="34" y="73" width="10" height="20" rx="3"/>'
        '<rect x="51" y="61" width="10" height="32" rx="3"/>'
        '<rect x="68" y="47" width="10" height="46" rx="3"/></g>'
        '<path d="M31 97h52" stroke="#fff" stroke-width="5" stroke-linecap="round"/>',
    ),
    "keynote": (
        "#a060f3", "#6332bf",
        '<g fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">'
        '<rect x="32" y="46" width="56" height="36" rx="4"/><path d="M60 82v15M48 97h24"/></g>',
    ),
    "text": (
        "#91a8bf", "#5c7187",
        '<g stroke="#fff" stroke-width="6" stroke-linecap="round"><path d="M34 51h52"/>'
        '<path d="M34 66h42"/><path d="M34 81h48"/><path d="M34 96h34"/></g>',
    ),
    "markdown": ("#637898", "#30445f", text("MD", 29)),
    "xml": (
        "#2bc9e2", "#087fb4",
        '<g fill="none" stroke="#fff" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="m45 55-14 14 14 14M75 55l14 14-14 14M67 48 53 91"/></g>',
    ),
    "json": ("#efbd3e", "#ce8700", text("{ }", 34)),
    "image": (
        "#ff6a62", "#df3e86",
        '<circle cx="42" cy="54" r="7" fill="#fff"/>'
        '<path d="m29 94 22-28 13 15 9-11 19 24z" fill="#fff" stroke="#fff" stroke-linejoin="round"/>',
    ),
    "video": ("#617fff", "#3148c9", '<path d="m48 47 34 23-34 23z" fill="#fff"/>'),
    "audio": (
        "#a869ee", "#6331ba",
        '<g stroke="#fff" stroke-width="6" stroke-linecap="round">'
        '<path d="M34 68v8M46 58v28M58 48v48M70 57v30M82 64v16"/></g>',
    ),
    "archive": (
        "#ffb42e", "#df7a00",
        '<g fill="#fff"><rect x="56" y="42" width="10" height="9" rx="2"/>'
        '<rect x="56" y="54" width="10" height="9" rx="2"/><rect x="56" y="66" width="10" height="9" rx="2"/>'
        '<rect x="53" y="78" width="16" height="18" rx="5"/></g>',
    ),
    "code": ("#3b8cff", "#0b4fc7", text("</>", 29)),
    "database": (
        "#c45fca", "#792681",
        '<g fill="none" stroke="#fff" stroke-width="6">'
        '<ellipse cx="60" cy="50" rx="25" ry="10"/><path d="M35 50v32c0 6 11 11 25 11s25-5 25-11V50"/>'
        '<path d="M35 66c0 6 11 11 25 11s25-5 25-11"/></g>',
    ),
    "font": ("#626a76", "#30353d", text("A", 46, 89)),
    "ebook": (
        "#30bdb0", "#087d75",
        '<g fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M29 49c12-5 22-3 31 5v40c-9-8-19-10-31-5zM91 49c-12-5-22-3-31 5v40c9-8 19-10 31-5z"/></g>',
    ),
    "package": (
        "#a67a56", "#66472f",
        '<g fill="none" stroke="#fff" stroke-width="6" stroke-linejoin="round">'
        '<path d="m34 58 26-14 26 14-26 15zM34 58v29l26 14 26-14V58M60 73v28"/></g>',
    ),
    "unknown": ("#a4acb7", "#666e79", text("?", 48, 90)),
}


BODY_PATH = "M27 6h48l31 31v70c0 9-7 15-15 15H27c-9 0-15-7-15-15V21c0-8 7-15 15-15z"
FOLD_PATH = "M75 6v20c0 7 5 12 12 12h19z"


def artwork(kind: str, gradient_id: str) -> str:
    _, _, symbol = ICONS[kind]
    return (
        f'<path d="{BODY_PATH}" fill="url(#{gradient_id})"/>'
        f'<path d="{BODY_PATH}" fill="none" stroke="#fff" stroke-opacity=".24" stroke-width="2"/>'
        f'<path d="{FOLD_PATH}" fill="#fff" fill-opacity=".34"/>'
        f'<path d="M77 8v18c0 6 4 10 10 10h17" fill="none" stroke="#fff" '
        f'stroke-opacity=".32" stroke-width="2"/>{symbol}'
    )


def gradient(kind: str, gradient_id: str) -> str:
    top, bottom, _ = ICONS[kind]
    return (
        f'<linearGradient id="{gradient_id}" x1="20" y1="8" x2="100" y2="122" '
        f'gradientUnits="userSpaceOnUse"><stop stop-color="{top}"/>'
        f'<stop offset="1" stop-color="{bottom}"/></linearGradient>'
    )


def individual_svg(kind: str) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 128">'
        f'<defs>{gradient(kind, "fileGradient")}</defs>{artwork(kind, "fileGradient")}</svg>\n'
    )


def write_ios_assets(assets_root: Path) -> None:
    group = assets_root / "FileTypeIcons"
    group.mkdir(parents=True, exist_ok=True)
    for kind in ICONS:
        image_set = group / f"FileType_{kind}.imageset"
        image_set.mkdir(parents=True, exist_ok=True)
        svg_name = f"FileType_{kind}.svg"
        (image_set / svg_name).write_text(individual_svg(kind), encoding="utf-8")
        contents = {
            "images": [{"filename": svg_name, "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True},
        }
        (image_set / "Contents.json").write_text(
            json.dumps(contents, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )


def write_web_assets(assets_root: Path) -> None:
    assets_root.mkdir(parents=True, exist_ok=True)
    for kind in ICONS:
        (assets_root / f"{kind}.svg").write_text(individual_svg(kind), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ios-assets", type=Path, default=Path("IMProgram/Assets.xcassets"))
    parser.add_argument("--web-assets", type=Path, default=Path("../im-web/public/file-types"))
    args = parser.parse_args()
    write_ios_assets(args.ios_assets)
    write_web_assets(args.web_assets)
    print(f"generated {len(ICONS)} file icons for iOS and Web")


if __name__ == "__main__":
    main()
