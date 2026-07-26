#!/usr/bin/env python3
"""Recolour the Musify AI launcher/splash bitmaps.

There is no vector master for the app icon: every PNG under
``android/app/src/main/res`` was hand-edited when Musify Cloud forked from
upstream. Musify AI needs the same artwork in its own brand colour, so this
script shifts the hue/saturation/value of the chromatic pixels and leaves the
white line art (and the alpha channel) untouched.

Run it from the repository root::

    python3 tools/recolor_icons.py            # rewrite the bitmaps
    python3 tools/recolor_icons.py --check    # verify, change nothing

``--check`` is what CI/pre-commit should use: it fails if any target file still
contains the source colour, which is how a half-applied rebrand gets caught.
"""

from __future__ import annotations

import argparse
import colorsys
import sys
from pathlib import Path

from PIL import Image

# Musify Cloud teal -> Musify AI indigo.
#
# SOURCE_HEX is sampled from the artwork itself, not from
# @color/ic_launcher_background (#006A71). The launcher glyph is a gradient
# whose dominant tone is #0B8F85, and calibrating the saturation/value ratios
# against the much darker background colour would blow the whole gradient out
# to a washed-out sky blue. Mapping the dominant tone onto TARGET_HEX keeps the
# gradient's shape and lands the icon on the brand colour.
SOURCE_HEX = '#0B8F85'
TARGET_HEX = '#2F4FE0'

# Below this saturation a pixel is white/black/grey line art or antialiasing
# against it. Recolouring those would tint the glyph itself, not the brand fill.
ACHROMATIC_SATURATION = 0.15

# Relative to the repository root.
TARGETS = [
    # Legacy square launcher icon.
    *(f'android/app/src/main/res/mipmap-{d}/ic_launcher.png'
      for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')),
    # Adaptive + monochrome foreground.
    *(f'android/app/src/main/res/mipmap-{d}/ic_launcher_adaptive_fore.png'
      for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')),
    # Notification icon.
    *(f'android/app/src/main/res/drawable-{d}/ic_launcher_foreground.png'
      for d in ('mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')),
    # The in-app logo on the shareable listening recap card.
    'assets/icons/musify_icon.png',
]

# Deliberately NOT recoloured, having checked what they actually contain:
#   res/{drawable,drawable-v21,drawable-night,drawable-night-v21}/background.png
#     are 1x1 neutral splash fills (#F9FAFD / #151515), not brand colour.
#   mipmap-*/ic_launcher_adaptive_fore.png and drawable-*/ic_launcher_foreground.png
#     are pure white glyphs on alpha; the adaptive icon takes its colour from
#     @color/ic_launcher_background in res/values/colors.xml instead.
#   drawable-*/audio_service_*.png are upstream's monochrome media controls.


def hex_to_hsv(value: str) -> tuple[float, float, float]:
    value = value.lstrip('#')
    r, g, b = (int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return colorsys.rgb_to_hsv(r, g, b)


def build_mapper(source: str, target: str):
    src_h, src_s, src_v = hex_to_hsv(source)
    dst_h, dst_s, dst_v = hex_to_hsv(target)

    hue_shift = dst_h - src_h
    # Ratios rather than absolutes so shading and gradients survive.
    sat_ratio = dst_s / src_s if src_s else 1.0
    val_ratio = dst_v / src_v if src_v else 1.0

    def map_pixel(r: int, g: int, b: int) -> tuple[int, int, int]:
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s <= ACHROMATIC_SATURATION:
            return r, g, b
        h = (h + hue_shift) % 1.0
        s = min(1.0, s * sat_ratio)
        v = min(1.0, v * val_ratio)
        nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
        return round(nr * 255), round(ng * 255), round(nb * 255)

    return map_pixel


def is_source_colour(r: int, g: int, b: int) -> bool:
    """True when a pixel is close enough to the source hue to look unconverted."""
    h, s, _ = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if s <= ACHROMATIC_SATURATION:
        return False
    src_h = hex_to_hsv(SOURCE_HEX)[0]
    distance = abs(h - src_h)
    return min(distance, 1.0 - distance) < 0.08


def process(path: Path, *, check_only: bool) -> tuple[int, int]:
    """Returns (converted pixel count, leftover source-colour pixel count)."""
    with Image.open(path) as handle:
        image = handle.convert('RGBA')

    # Fully transparent pixels carry junk RGB (PNG encoders store whatever was
    # under the erased area), so they must be excluded from both the recolour
    # and the verification or they report false leftovers.
    pixels = list(image.getdata())

    if check_only:
        leftover = sum(1 for r, g, b, a in pixels
                       if a > 0 and is_source_colour(r, g, b))
        return 0, leftover

    mapper = build_mapper(SOURCE_HEX, TARGET_HEX)
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    converted = 0
    mapped = []
    for r, g, b, a in pixels:
        if a == 0:
            mapped.append((r, g, b, a))
            continue
        result = cache.get((r, g, b))
        if result is None:
            result = mapper(r, g, b)
            cache[(r, g, b)] = result
        if result != (r, g, b):
            converted += 1
        mapped.append((*result, a))

    # Only rewrite when something actually changed; a no-op re-encode would put
    # a meaningless binary diff in the commit.
    if converted:
        out = Image.new('RGBA', image.size)
        out.putdata(mapped)
        out.save(path)

    leftover = sum(1 for r, g, b, a in mapped
                   if a > 0 and is_source_colour(r, g, b))
    return converted, leftover


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true',
                        help='verify only; do not rewrite any file')
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    failures = []

    for relative in TARGETS:
        path = root / relative
        if not path.exists():
            print(f'MISSING  {relative}')
            failures.append(relative)
            continue

        converted, leftover = process(path, check_only=args.check)
        status = 'leftover' if leftover else 'ok'
        if leftover:
            failures.append(relative)
        if args.check:
            print(f'{status:9} {relative} ({leftover} source-colour px)')
        else:
            print(f'{status:9} {relative} ({converted} px recoloured)')

    if failures:
        print(f'\n{len(failures)} file(s) still carry the source colour.',
              file=sys.stderr)
        return 1

    print(f'\nAll {len(TARGETS)} bitmaps use {TARGET_HEX}.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
