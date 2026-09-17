#!/usr/bin/env python3
"""Rebuild the CINDERMARK logo as clean flat-colour artwork from a photo of it.

    python3 brand/extract-logo.py brand/source-logo-photo.jpg \
        ios/CindermarkPOD/Assets.xcassets

The source we had to work from is a camera photo of a monitor. It carries a
backlight gradient, the screen's pixel weave, JPEG noise and a soft drop shadow.
Copying it into the app as-is would put all of that on every delivery receipt.

So the photograph is used only to recover two things - the shape, and the two
brand inks - and the artwork is rebuilt from them:

  1. Divide out the illumination, so paper is the same white everywhere.
  2. Measure the inks from confident shape interiors, well away from the
     antialiased edges where ink and paper are blended.
  3. Resolve a hard-edged mask, clean off camera speckle, and repaint every
     pixel as one flat ink.
  4. Downsample with premultiplied alpha. The resampling is what produces the
     smooth edges - antialiasing a clean shape, rather than inheriting the
     camera's soft, shadowed ones.

If the original vector artwork (SVG, PDF or AI) ever turns up, use that instead:
export LogoPrimary, LogoDocument, LogoMark and LogoWordmark from it and this
script becomes unnecessary.

Requires: pillow, numpy, scipy
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

# Measured from the photo in step 2 below. Override here if you have the real
# brand values - these are what the app and the PDF are built around.
NAVY = np.array([0x36, 0x45, 0x64], np.float32)   # the C letterform
ROAD = np.array([0x3D, 0x6F, 0xB0], np.float32)   # the road through it
WHITE = np.array([255.0, 255.0, 255.0], np.float32)


def flatten_illumination(rgb):
    """Divide out the backlight gradient and lens vignetting.

    The photo falls off about 15% from top to bottom, so no single threshold
    separates ink from paper across the whole frame. Fitting a quadratic to the
    light pixels models the lighting; dividing by it leaves flat white paper.
    """
    h, w, _ = rgb.shape
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    Y, X = ys / h, xs / w
    basis = lambda Y, X: np.stack([np.ones_like(Y), Y, X, Y * Y, X * X, Y * X], -1)
    light = rgb.mean(2) > np.percentile(rgb.mean(2), 60)
    A = basis(Y[light], X[light])
    field = np.zeros_like(rgb)
    for channel in range(3):
        coefficients, *_ = np.linalg.lstsq(A, rgb[..., channel][light], rcond=None)
        field[..., channel] = basis(Y, X) @ coefficients
    return np.clip(rgb / np.maximum(field, 1e-3) * 255.0, 0, 255)


def measure_inks(norm):
    """Report the two inks, for checking the constants above still hold."""
    solid = ndimage.binary_erosion(norm.mean(2) < 140, np.ones((7, 7)))
    px = norm[solid]
    blue_minus_red = px[:, 2] - px[:, 0]
    for name, sample in (("navy", px[blue_minus_red < 90]), ("road", px[blue_minus_red >= 90])):
        median = np.median(sample, 0)
        print(f"  measured {name}: #{''.join('%02X' % int(round(v)) for v in median)}  ({len(sample)} px)")


def build(norm):
    """Return flat colour and a hard mask covering the whole logo."""
    h, w, _ = norm.shape
    nlum = norm.mean(2)

    solid = ndimage.binary_erosion(nlum < 140, np.ones((5, 5)))
    blue_minus_red = norm[..., 2] - norm[..., 0]
    seed = np.zeros((h, w), np.uint8)
    seed[solid & (blue_minus_red < 90)] = 1
    seed[solid & (blue_minus_red >= 90)] = 2

    # Every pixel takes the label of the nearest confident interior, so an edge
    # pixel gets the colour of the shape it belongs to rather than the muddy
    # ink-and-paper blend the camera actually recorded there.
    _, (iy, ix) = ndimage.distance_transform_edt(seed == 0, return_indices=True)
    label = seed[iy, ix]

    # 190 sits well clear of both inks and of paper, and above the drop shadow.
    shape = nlum < 190
    disk = np.array([[0, 1, 1, 1, 0],
                     [1, 1, 1, 1, 1],
                     [1, 1, 1, 1, 1],
                     [1, 1, 1, 1, 1],
                     [0, 1, 1, 1, 0]], bool)
    shape = ndimage.binary_opening(ndimage.binary_closing(shape, disk), disk)

    parts, count = ndimage.label(shape)
    sizes = np.bincount(parts.ravel())
    keep = np.zeros(count + 1, bool)
    keep[1:] = sizes[1:] >= 200          # the blue tail below the C is ~1000 px
    print(f"  speckle components dropped: {int((sizes[1:] < 200).sum())}")
    shape = keep[parts]

    # The road's white dashes read as paper and punch holes in the shape. Refill
    # only the holes ringed by road: a letter counter (the middle of a D or an
    # A) is enclosed too and has to stay transparent.
    #
    # Judge each hole on the INK that touches it, not on every neighbouring
    # pixel. Where the road narrows near the C the ring spills onto bare paper,
    # and paper there is nearest to the navy seed - which makes the two end
    # dashes look like letter counters. Ink-only neighbours separate them
    # cleanly: every dash is 62-100% road ink, every counter is 0%.
    holes, hole_count = ndimage.label(~shape)
    edge = set(np.unique(np.concatenate([holes[0], holes[-1], holes[:, 0], holes[:, -1]])))
    filled = 0
    for index in range(1, hole_count + 1):
        if index in edge:
            continue
        hole = holes == index
        ring = ndimage.binary_dilation(hole, np.ones((9, 9))) & ~hole & shape
        neighbours = label[ring]
        if len(neighbours) and (neighbours == 2).mean() > 0.5:
            shape |= hole
            label[hole] = 3
            filled += 1
    print(f"  road dashes restored: {filled}")

    colour = np.zeros((h, w, 3), np.float32)
    colour[label == 1] = NAVY
    colour[label == 2] = ROAD
    colour[label == 3] = WHITE
    return colour, shape.astype(np.float32)


def bands(mask):
    """Find the mark, the wordmark, the tagline and the rule by their gaps."""
    rows = mask.sum(1) > 3
    found, start = [], None
    for y, on in enumerate(rows):
        if on and start is None:
            start = y
        elif not on and start is not None:
            if y - start > 8:
                found.append((start, y - 1))
            start = None
    if start is not None:
        found.append((start, len(rows) - 1))
    return found


def render(colour, mask, width):
    """Downsample with premultiplied alpha.

    Resampling straight RGBA instead would pull the colour of fully transparent
    pixels into the edge and fringe it.
    """
    height = round(colour.shape[0] * width / colour.shape[1])
    resize = lambda arr, mode: Image.fromarray(
        np.clip(arr, 0, 255).astype(np.uint8), mode).resize((width, height), Image.LANCZOS)
    small_rgb = np.asarray(resize(colour * mask[..., None], 'RGB')).astype(np.float32)
    small_a = np.asarray(resize(mask * 255.0, 'L')).astype(np.float32)
    coverage = np.maximum(small_a[..., None] / 255.0, 1e-3)
    straight = np.where(small_a[..., None] > 0.5, small_rgb / coverage, 0.0)
    return Image.fromarray(np.dstack([np.clip(straight, 0, 255), small_a]).astype(np.uint8), 'RGBA')


def write_imageset(catalog, name, filename, image):
    folder = catalog / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / filename)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print(f"  {name:14s} {image.width:5d} x {image.height:4d}")


def main(source, catalog):
    rgb = np.asarray(Image.open(source).convert('RGB')).astype(np.float32)
    print(f"source {source} {rgb.shape[1]}x{rgb.shape[0]}")
    norm = flatten_illumination(rgb)
    measure_inks(norm)
    colour, mask = build(norm)

    found = bands(mask > 0.5)
    if len(found) != 4:
        sys.exit(f"expected 4 bands (mark, wordmark, tagline, rule), found {len(found)}: {found}")
    (mark_y0, mark_y1), (words_y0, _), *_, (rule_y0, rule_y1) = found

    def crop(y0, y1, pad=8):
        rows = slice(max(0, y0 - pad), min(mask.shape[0], y1 + pad + 1))
        band = mask[rows]
        cols = np.where(band.any(0))[0]
        xs = slice(max(0, cols.min() - pad), min(mask.shape[1], cols.max() + pad + 1))
        return colour[rows, xs], band[:, xs]

    pieces = {
        'LogoMark': crop(mark_y0, mark_y1),
        'LogoWordmark': crop(words_y0, rule_y1),
        'LogoPrimary': crop(mark_y0, rule_y1),
    }
    # About 60% of native: ample resolution for every use here, and the
    # downsample is what buys the clean edge.
    images = {name: render(c, m, round(c.shape[1] * 0.62)) for name, (c, m) in pieces.items()}

    # A horizontal lockup for the PDF header band and toolbars. The stacked
    # logo is nearly square and would be illegibly small in a 38pt-tall strip.
    mark, words = images['LogoMark'], images['LogoWordmark']
    mark_h = 300
    m = mark.resize((round(mark.width * mark_h / mark.height), mark_h), Image.LANCZOS)
    t = words.resize((round(words.width * (mark_h * 0.84) / words.height), round(mark_h * 0.84)), Image.LANCZOS)
    gap = round(mark_h * 0.17)
    lockup = Image.new('RGBA', (m.width + gap + t.width, mark_h), (0, 0, 0, 0))
    lockup.alpha_composite(m, (0, 0))
    lockup.alpha_composite(t, (m.width + gap, (mark_h - t.height) // 2))
    images['LogoDocument'] = lockup

    catalog = Path(catalog)
    print("image sets:")
    for name, image in images.items():
        write_imageset(catalog, name, f"logo-{name[len('Logo'):].lower()}.png", image)

    # The app icon comes off the full-resolution mask: upscaling the finished
    # 455px mark back to 1024 would undo the clean edge. iOS icons cannot carry
    # transparency, so it sits on white, as the mark does on the letterhead.
    hires = render(*pieces['LogoMark'], 760)
    size, inset = 1024, 0.70
    icon = Image.new('RGBA', (size, size), (255, 255, 255, 255))
    scale = (size * inset) / max(hires.size)
    scaled = hires.resize((round(hires.width * scale), round(hires.height * scale)), Image.LANCZOS)
    icon.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    folder = catalog / "AppIcon.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    icon.convert('RGB').save(folder / "app-icon-1024.png")
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": "app-icon-1024.png", "idiom": "universal",
                    "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    print(f"  {'AppIcon':14s} {size:5d} x {size:4d}")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
