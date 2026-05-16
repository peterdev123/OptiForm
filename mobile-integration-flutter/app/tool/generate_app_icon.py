"""Fit the original OptiForm artwork into square launcher icons without stretching."""
from __future__ import annotations

from pathlib import Path

from PIL import Image

SIZE = 1024
BG = (13, 16, 32, 255)  # #0D1020 — matches adaptive_icon_background

# Original AI artwork (1536×1024). Kept in assets/icon/.
SOURCE = Path(__file__).resolve().parent.parent / "assets" / "icon" / "app_icon_source.png"


def _resolve_source() -> Path:
    if SOURCE.is_file():
        return SOURCE
    raise FileNotFoundError(
        f"Place the original artwork at {SOURCE}",
    )


def _fit_centered(img: Image.Image, canvas_size: int, background: tuple[int, ...]) -> Image.Image:
    """Scale to fit inside canvas; preserve aspect ratio (no compression/stretch)."""
    w, h = img.size
    scale = min(canvas_size / w, canvas_size / h)
    new_w = max(1, int(w * scale))
    new_h = max(1, int(h * scale))
    resized = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (canvas_size, canvas_size), background)
    x = (canvas_size - new_w) // 2
    y = (canvas_size - new_h) // 2
    canvas.paste(resized, (x, y), resized if resized.mode == "RGBA" else None)
    return canvas


def main() -> None:
    src_path = _resolve_source()
    out_dir = Path(__file__).resolve().parent.parent / "assets" / "icon"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Keep a copy in the repo.
    repo_source = out_dir / "app_icon_source.png"
    if src_path.resolve() != repo_source.resolve():
        Image.open(src_path).save(repo_source)

    original = Image.open(src_path).convert("RGBA")

    full = _fit_centered(original, SIZE, BG)
    full.save(out_dir / "app_icon.png", "PNG")

    # Foreground: same artwork, transparent padding (for Android adaptive).
    fg = _fit_centered(original, SIZE, (0, 0, 0, 0))
    fg.save(out_dir / "app_icon_foreground.png", "PNG")

    print(f"Source: {src_path} ({original.size[0]}x{original.size[1]})")
    print(f"Wrote square icons at {SIZE}x{SIZE} (aspect ratio preserved)")


if __name__ == "__main__":
    main()
