"""Builds assets/wordmark.svg: the dev-null.sh header wordmark with its text as paths.

Mirrors the site's header markup: the logo at 1.1em, a 0.5rem gap, then "/dev/null"
in Geist Bold at 1.75rem with -0.03em tracking, the middle slash an accent outline
of 0.035em. Run with: uv run --with fonttools --with brotli --with uharfbuzz tools/build_wordmark.py
"""

import io
import pathlib
import urllib.request

import uharfbuzz as hb
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

FONT_URL = "https://dev-null.sh/build/assets/geist-700-normal-CFi8mLqe.woff2"
TEXT = "/dev/null"
OUTLINED = 4  # index of the middle slash
FONT_SIZE_PX = 28  # 1.75rem
GAP = 8 / FONT_SIZE_PX  # 0.5rem
ICON = 1.1
TRACKING = -0.03
STROKE = 0.035

INK_PATH = "M2 42h10L26 6H16Z"
ACCENT_PATH = "M17.81 43.5h13.22L46.19 4.5H32.97ZM22.19 40.5l12.84-33h6.78l-12.84 33Z"

request = urllib.request.Request(FONT_URL, headers={"User-Agent": "Mozilla/5.0"})
font = TTFont(io.BytesIO(urllib.request.urlopen(request).read()))
font.flavor = None
ttf = io.BytesIO()
font.save(ttf)
upem = font["head"].unitsPerEm
glyphs = font.getGlyphSet()
order = font.getGlyphOrder()

blob = hb.Blob(ttf.getvalue())
shaper = hb.Font(hb.Face(blob))
buf = hb.Buffer()
buf.add_str(TEXT)
buf.guess_segment_properties()
hb.shape(shaper, buf)

# Everything is in em; y grows downward and 0 is the centre line both items align on.
hhea = font["hhea"]
baseline = (hhea.ascent + hhea.descent) / 2 / upem
pen_x = ICON + GAP
paths, bounds = [], [0.0, -ICON / 2, ICON, ICON / 2]
for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
    name = order[info.codepoint]
    s = 1 / upem
    transform = (s, 0, 0, -s, pen_x + pos.x_offset * s, baseline - pos.y_offset * s)
    svg = SVGPathPen(glyphs)
    glyphs[name].draw(TransformPen(svg, transform))
    box = BoundsPen(glyphs)
    glyphs[name].draw(TransformPen(box, transform))
    if box.bounds:
        pad = STROKE / 2 if info.cluster == OUTLINED else 0
        x0, y0, x1, y1 = box.bounds
        bounds = [min(bounds[0], x0 - pad), min(bounds[1], y0 - pad), max(bounds[2], x1 + pad), max(bounds[3], y1 + pad)]
    paths.append((info.cluster == OUTLINED, svg.getCommands()))
    pen_x += pos.x_advance * s + TRACKING

k = ICON / 45
x0, y0, x1, y1 = bounds
text = "\n".join(
    f'  <path fill="none" stroke="{{accent}}" stroke-width="{STROKE}" d="{d}"/>'
    if outlined
    else f'  <path fill="{{ink}}" d="{d}"/>'
    for outlined, d in paths
)
svg = f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:.4f} {y0:.4f} {x1 - x0:.4f} {y1 - y0:.4f}">
  <g transform="translate(0 {-ICON / 2}) scale({k}) translate(-1.6 -1.5)">
    <path fill="{{ink}}" d="{INK_PATH}"/>
    <path fill="{{accent}}" fill-rule="evenodd" d="{ACCENT_PATH}"/>
  </g>
{text}
</svg>
"""
out = pathlib.Path(__file__).resolve().parent.parent / "assets" / "wordmark.svg"
out.write_text(svg)
print(out, f"{x1 - x0:.3f}x{y1 - y0:.3f}em")
