"""Sample the preferences window's background thumbnail and inline material preview.

Used by settings_thumbnail_native.ts (set-modals: the thumbnail was blank because the
wallpaper texture lived in the main window's own texture table). The fixture is the
20 px yellow / blue checker of h_appearance_capture.ts.
argv: screenshot.png window_w window_h thumbnail_rect_json preview_rect_json
Prints JSON: {thumbnail: {checker_ratio}, preview: {spread}}.
"""
import json
import sys

from PIL import Image

CHECKER = [(242, 192, 65), (71, 129, 232)]


def pixels(image, rect, scale_x, scale_y, inset):
    x0, y0 = round((rect["x"] + inset) * scale_x), round((rect["y"] + inset) * scale_y)
    x1, y1 = round((rect["x"] + rect["w"] - inset) * scale_x), round((rect["y"] + rect["h"] - inset) * scale_y)
    for y in range(y0, y1):
        for x in range(x0, x1):
            yield image.getpixel((x, y))


with Image.open(sys.argv[1]) as screenshot:
    image = screenshot.convert("RGB")
    scale_x, scale_y = image.width / float(sys.argv[2]), image.height / float(sys.argv[3])
    thumbnail = list(pixels(image, json.loads(sys.argv[4]), scale_x, scale_y, 3))
    near = sum(1 for p in thumbnail if min(max(abs(p[i] - c[i]) for i in range(3)) for c in CHECKER) <= 40)
    preview = list(pixels(image, json.loads(sys.argv[5]), scale_x, scale_y, 4))
    luminance = [0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in preview]
    mean = sum(luminance) / max(1, len(luminance))
    spread = (sum((v - mean) ** 2 for v in luminance) / max(1, len(luminance))) ** 0.5
    print(json.dumps({"thumbnail": {"pixels": len(thumbnail), "checker_ratio": near / max(1, len(thumbnail))}, "preview": {"pixels": len(preview), "spread": spread}}))
