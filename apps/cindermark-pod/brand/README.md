# Brand assets

The logo in the app and on every delivery receipt was rebuilt from
`source-logo-photo.jpg` - a camera photo of the logo on a screen, which is the
best source we had.

`extract-logo.py` does the rebuilding, and it is worth keeping rather than just
the PNGs it produced: if the artwork changes, re-run it instead of hand-editing
an image.

```sh
pip install pillow numpy scipy
python3 brand/extract-logo.py brand/source-logo-photo.jpg ios/CindermarkPOD/Assets.xcassets
```

It writes `LogoPrimary`, `LogoDocument`, `LogoMark`, `LogoWordmark` and the app
icon straight into the asset catalog.

## What it does, and why it is not just a crop

A photo of a screen carries a backlight gradient, the screen's pixel weave, JPEG
noise and a soft drop shadow. Cropping it would put all of that on every
receipt. So the photo is used only to recover the shape and the two inks, and
the artwork is rebuilt from them: illumination divided out, inks measured from
shape interiors away from the blended edges, a hard mask cleaned of speckle,
every pixel repainted as one flat ink, then downsampled with premultiplied
alpha - the resampling is what produces the smooth edges.

Two details in there are easy to get wrong:

- **The road's white dashes** read as paper, so they punch holes in the shape
  and have to be filled back in. But letter counters - the enclosed middle of a
  D or an A - are holes too, and must stay transparent. Each hole is judged on
  the *ink* that touches it: dashes come out 62–100% road blue, counters 0%.
- **Premultiplied alpha** on the downsample. Resampling straight RGBA pulls the
  colour of transparent pixels into the edge and fringes it.

## Colours

Measured from the artwork, and the values the whole app is built on:

| | Hex | Used for |
|---|---|---|
| Navy | `#364564` | The C letterform. Body ink, headings, PDF text. |
| Road blue | `#3D6FB0` | The road through the C. Accent, buttons, section headings. |

Both clear WCAG AA on white (9.6:1 and 5.1:1), so the road blue is used at full
strength rather than darkened for text.

`BrandAlert` (`#B3261E`) is deliberately **not** a brand colour. Exceptions on a
receipt - short, damaged, refused, a missing location, a failed send - have to
read as exceptions, and brand blue would make them look like another heading.

## If you find the original

Use it. Export `LogoPrimary` (stacked lockup), `LogoDocument` (horizontal
lockup, for the PDF header band), `LogoMark` (the C alone) and `LogoWordmark`
(the type alone) from the vector file into the same image sets, and this script
stops being needed. Vector-derived artwork will be sharper than anything
recoverable from a photograph, and the two ink values above are approximations
of the real brand colours - if you have the actual specification, put those
values in `Branding/BrandColor.swift` and in the constants at the top of
`extract-logo.py`.
