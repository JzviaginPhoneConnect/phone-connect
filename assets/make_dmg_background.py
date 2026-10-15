# Draws the background of the macOS installer window (the .dmg):
# "drag PhoneConnect to Applications", with an arrow between the two icons and
# a reminder about the one-time security approval.
# Writes dmg-background.png (600x400) and dmg-background@2x.png (1200x800).
# Run: python3 make_dmg_background.py   (needs Pillow and the DejaVu Sans font)
#
# The icon positions here must match build/dmg-settings.py.
from PIL import Image, ImageDraw, ImageFont

W, H = 600, 400
APP_X, APPS_X, ICON_Y = 160, 440, 200      # icon centres, in window points
FONT_DIRS = ["/usr/share/fonts/truetype/dejavu/", "/Library/Fonts/", "/System/Library/Fonts/Supplemental/"]

def font(name, size):
    for d in FONT_DIRS:
        try:
            return ImageFont.truetype(d + name, size)
        except OSError:
            pass
    return ImageFont.load_default()

def draw(scale):
    s = lambda v: int(round(v * scale))
    img = Image.new("RGB", (s(W), s(H)))
    d = ImageDraw.Draw(img)

    # soft vertical gradient, in the icon's green/teal family but very light
    top, bot = (240, 250, 247), (222, 240, 238)
    for y in range(s(H)):
        t = y / (s(H) - 1)
        d.line([(0, y), (s(W), y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))

    ink = (20, 70, 75)
    muted = (70, 105, 110)
    title = font("DejaVuSans-Bold.ttf", s(22))
    body = font("DejaVuSans.ttf", s(13))
    small = font("DejaVuSans.ttf", s(12))

    def centred(text, y, f, fill):
        w = d.textlength(text, font=f)
        d.text(((s(W) - w) / 2, y), text, font=f, fill=fill)

    centred("Install PhoneConnect", s(34), title, ink)
    centred("Drag the app onto the Applications folder", s(68), body, muted)

    # arrow between the two icons
    x1, x2, y = s(APP_X + 70), s(APPS_X - 70), s(ICON_Y)
    green = (16, 150, 120)
    d.line([(x1, y), (x2 - s(14), y)], fill=green, width=s(6))
    d.polygon([(x2, y), (x2 - s(22), y - s(14)), (x2 - s(22), y + s(14))], fill=green)

    # one-time security step
    d.rounded_rectangle([s(40), s(300), s(W - 40), s(372)], radius=s(12), fill=(255, 255, 255), outline=(200, 225, 222), width=s(1))
    centred("First time you open it, macOS asks for approval:", s(312), small, ink)
    centred("System Settings → Privacy & Security → Open Anyway", s(334), font("DejaVuSans-Bold.ttf", s(12)), ink)
    centred("(only once — after that it opens normally)", s(353), small, muted)
    return img

draw(1).save("dmg-background.png", dpi=(72, 72))
draw(2).save("dmg-background@2x.png", dpi=(144, 144))
print("done")
