"""Draws Flaco's icon: a vacuum fluorescent display as if photographed, phosphor on near-black glass with no
labels or frame. A 6-band analyzer of thin dashed columns, peaks held above. Drawn at 2048, saved at 1024.

usage: python3 Tools/icon.py Flaco/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png [amber|cyan]
Needs Pillow.
"""
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2048
K = S / 1024

SPECTRUM = {"amber": (255, 186, 74), "cyan": (110, 240, 236)}[sys.argv[2] if len(sys.argv) > 2 else "amber"]
OVER = (255, 64, 52)
GHOST = (22, 22, 21)


def u(v):
    return int(round(v * K))


def clear():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def screen(base, light, radius, strength):
    blurred = light.filter(ImageFilter.GaussianBlur(radius)) if radius else light
    r, g, b, a = blurred.split()
    a = a.point(lambda v: min(255, int(v * strength)))
    glow = Image.new("RGB", (S, S), (0, 0, 0))
    glow.paste(Image.merge("RGB", (r, g, b)), mask=a)
    return Image.merge("RGBA", (*ImageChops.screen(base.convert("RGB"), glow).split(), base.split()[3]))


def hot(colour, t):
    """Phosphor is whiter at its brightest."""
    return tuple(int(c + (255 - c) * t) for c in colour)


def main(out):
    # The glass: near black, a little warmer at the top where room light falls on it.
    base = Image.linear_gradient("L").resize((S, S))
    img = Image.merge("RGBA", (
        base.point(lambda v: int(16 - v * 0.045)),
        base.point(lambda v: int(15 - v * 0.045)),
        base.point(lambda v: int(15 - v * 0.040)),
        Image.new("L", (S, S), 255)))

    ghost = ImageDraw.Draw(img)
    lit_img = clear()
    lit = ImageDraw.Draw(lit_img)

    # Everything sits in a square with the same margin on all four sides: the side marks on its left and
    # right edges, the top dash row on its top edge, the scale dots on its bottom edge.
    margin = 150
    box_l, box_r, box_t, box_b = u(margin), u(1024 - margin), u(margin), u(1024 - margin)
    mark, mark_gap, dot, dot_gap = u(7), u(20), u(8), u(26)

    # The analyzer: each band two thin columns of dashes, with the peak held above.
    bands = 6
    levels = [0.60, 0.90, 0.76, 0.84, 0.54, 0.36]
    peaks = [0.72, 1.00, 0.88, 0.95, 0.67, 0.49]
    left, right = box_l + mark + mark_gap, box_r - mark - mark_gap
    col_gap, band_gap = u(9), u(30)
    col_w = ((right - left) - (bands - 1) * band_gap - bands * col_gap) / (2 * bands)
    band_w = 2 * col_w + col_gap
    top, bottom = box_t, box_b - dot - dot_gap
    rows, dash_h = 32, u(12.5)
    pitch = (bottom - top - dash_h) / (rows - 1)
    for b in range(bands):
        on = round(levels[b] * rows)
        peak = min(rows - 1, round(peaks[b] * rows))
        for c in range(2):
            x = left + b * (band_w + band_gap) + c * (col_w + col_gap)
            # The second column of a band sits a dash or so lower, as real displays flicker.
            reach = on - (1 if c == 1 and b % 2 == 0 else 0)
            for r in range(rows):
                y1 = bottom - r * pitch
                rect = (int(x), int(y1 - dash_h), int(x + col_w), int(y1))
                ghost.rectangle(rect, fill=GHOST + (255,))
                if r < reach:
                    lit.rectangle(rect, fill=hot(SPECTRUM, 0.15 * r / rows) + (255,))
                elif r == peak:
                    lit.rectangle(rect, fill=hot(SPECTRUM, 0.25) + (255,))

    # Scale dots along the bottom edge, between and beside the bands, and marks down both sides.
    for b in range(bands + 1):
        cx = left - band_gap / 2 + b * (band_w + band_gap) if 0 < b < bands else (left if b == 0 else right)
        lit.ellipse((cx - dot / 2, box_b - dot, cx + dot / 2, box_b), fill=SPECTRUM + (210,))
    for side in (box_l, box_r - mark):
        for r in range(0, rows, 4):
            y = bottom - r * pitch - dash_h / 2
            colour = OVER if r == rows - rows % 4 - 4 else SPECTRUM
            lit.ellipse((side, y - mark / 2, side + mark, y + mark / 2), fill=colour + (170,))

    # Phosphor: crisp, a tight halo, and only a faint wide bloom.
    lit_img = lit_img.filter(ImageFilter.GaussianBlur(u(0.6)))
    img = screen(img, lit_img, u(38), 0.45)
    img = screen(img, lit_img, u(10), 1.1)
    img = screen(img, lit_img, u(2.5), 0.9)
    img = screen(img, lit_img, 0, 1.0)
    core = lit_img.filter(ImageFilter.MinFilter(5))
    r, g, b, a = core.split()
    img = screen(img, Image.merge("RGBA", (r, g, b, a.point(lambda v: v // 3))), u(1), 1)

    # The control mesh, seen only where it's lit.
    mesh = clear()
    md = ImageDraw.Draw(mesh)
    for gx in range(0, S, u(3.4)):
        md.line([(gx, 0), (gx, S)], fill=(0, 0, 0, 46))
    for gy in range(0, S, u(3.4)):
        md.line([(0, gy), (S, gy)], fill=(0, 0, 0, 46))
    reach = lit_img.split()[3].point(lambda v: 255 if v > 40 else 0)
    img.alpha_composite(Image.composite(mesh, clear(), reach))

    # Filament wires: hair-thin, dark against the glow, catching a little light elsewhere.
    wires = clear()
    wd = ImageDraw.Draw(wires)
    for i in range(6):
        y = u(150) + i * u(148)
        wd.line([(0, y), (S, y + u(3))], fill=(0, 0, 0, 150), width=u(1.4))
        wd.line([(0, y - u(1.6)), (S, y + u(1.4))], fill=(255, 236, 214, 30), width=u(1))
    img.alpha_composite(wires)

    # The front glass reflects the glow faintly, a little above where it is.
    echo = lit_img.filter(ImageFilter.GaussianBlur(u(6)))
    r, g, b, a = echo.split()
    echo = Image.merge("RGBA", (r, g, b, a.point(lambda v: v // 9)))
    shifted = clear()
    shifted.paste(echo, (u(6), -u(14)), echo)
    img = screen(img, shifted, 0, 1)

    # Room light on the glass: a broad soft smear, brighter toward the upper left.
    smear = Image.new("L", (S, S), 0)
    sd = ImageDraw.Draw(smear)
    sd.polygon([(-u(100), u(120)), (u(560), -u(60)), (u(760), u(40)), (u(40), u(420))], fill=38)
    sd.ellipse((u(600), u(470), u(1180), u(610)), fill=10)
    smear = smear.filter(ImageFilter.GaussianBlur(u(70)))
    img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), (230, 236, 255)).split(), smear)))

    # Corners fall off, and a little grain, as in a photograph.
    vignette = Image.radial_gradient("L").resize((S, S)).point(lambda v: int(min(255, max(0, (v - 110) * 1.1))))
    img.alpha_composite(Image.merge("RGBA", (*Image.new("RGB", (S, S), (0, 0, 0)).split(), vignette.point(lambda v: v // 2))))
    noise = Image.effect_noise((S // 2, S // 2), 40).resize((S, S))
    grain = Image.merge("RGBA", (noise, noise, noise, Image.new("L", (S, S), 9)))
    img.alpha_composite(grain)

    img.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(out)


main(sys.argv[1])
