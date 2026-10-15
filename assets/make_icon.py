# Draws the PhoneConnect icon and writes PNG, macOS .icns and Windows .ico.
# Run: python3 make_icon.py   (needs Pillow: pip install pillow)
from PIL import Image, ImageDraw, ImageFilter
S = 1024
SS = 4  # supersample for smooth edges
W = S * SS

def sc(v): return int(v * SS)

# --- background: macOS-style rounded square with a vertical gradient ---
grad = Image.new("RGBA", (W, W))
top, bot = (52, 211, 153), (14, 116, 144)   # green -> deep teal
gd = ImageDraw.Draw(grad)
for y in range(W):
    t = y / (W - 1)
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,)
    gd.line([(0, y), (W, y)], fill=c)

mask = Image.new("L", (W, W), 0)
md = ImageDraw.Draw(mask)
inset = sc(100)                 # Apple icon grid: 824px body inside 1024 canvas
md.rounded_rectangle([inset, inset, W - inset, W - inset], radius=sc(185), fill=255)

icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
# soft drop shadow
shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle([inset, inset + sc(12), W - inset, W - inset + sc(12)], radius=sc(185), fill=(0, 0, 0, 90))
shadow = shadow.filter(ImageFilter.GaussianBlur(sc(14)))
icon.alpha_composite(shadow)
icon.paste(grad, (0, 0), mask)

d = ImageDraw.Draw(icon)

# --- laptop/Mac screen behind (simple monitor shape) ---
mon = [sc(205), sc(300), sc(745), sc(640)]
ml = Image.new("RGBA", (W, W), (0, 0, 0, 0))
mdr = ImageDraw.Draw(ml)
mdr.rounded_rectangle(mon, radius=sc(34), fill=(255, 255, 255, 235))
mdr.rounded_rectangle([mon[0]+sc(22), mon[1]+sc(22), mon[2]-sc(22), mon[3]-sc(22)], radius=sc(16), fill=(14, 116, 144, 255))
mdr.rounded_rectangle([sc(430), sc(640), sc(520), sc(700)], radius=sc(6), fill=(255, 255, 255, 235))
mdr.rounded_rectangle([sc(370), sc(695), sc(580), sc(725)], radius=sc(15), fill=(255, 255, 255, 235))
icon.alpha_composite(ml)
d = ImageDraw.Draw(icon)

# --- phone in front ---
ph = [sc(560), sc(330), sc(800), sc(790)]
# phone shadow
ps = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(ps).rounded_rectangle([ph[0]+sc(6), ph[1]+sc(14), ph[2]+sc(6), ph[3]+sc(14)], radius=sc(48), fill=(0, 0, 0, 110))
icon.alpha_composite(ps.filter(ImageFilter.GaussianBlur(sc(16))))
d = ImageDraw.Draw(icon)
d.rounded_rectangle(ph, radius=sc(48), fill=(255, 255, 255, 255))
scr = [ph[0]+sc(18), ph[1]+sc(18), ph[2]-sc(18), ph[3]-sc(18)]
d.rounded_rectangle(scr, radius=sc(32), fill=(17, 94, 89, 255))
# camera hole
cx = (ph[0] + ph[2]) // 2
d.ellipse([cx - sc(9), scr[1] + sc(14), cx + sc(9), scr[1] + sc(32)], fill=(255, 255, 255, 200))
# call glyph: classic handset, drawn upright then rotated
hl = Image.new("RGBA", (W, W), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hx, hy = cx, sc(560)
g = (52, 211, 153, 255)
r = sc(70)
hd.arc([hx - r, hy - r, hx + r, hy + r], start=200, end=340, fill=g, width=sc(34))
hd.rounded_rectangle([hx - r - sc(14), hy - sc(40), hx - r + sc(40), hy + sc(22)], radius=sc(16), fill=g)
hd.rounded_rectangle([hx + r - sc(40), hy - sc(40), hx + r + sc(14), hy + sc(22)], radius=sc(16), fill=g)
hl = hl.rotate(-135, center=(hx, hy - sc(10)), resample=Image.BICUBIC)
icon.alpha_composite(hl)
d = ImageDraw.Draw(icon)

# --- mouse cursor overlapping phone (control from the Mac) ---
cur = [(sc(470), sc(500)), (sc(470), sc(700)), (sc(518), sc(655)), (sc(552), sc(728)),
       (sc(585), sc(713)), (sc(551), sc(642)), (sc(612), sc(638))]
d.polygon(cur, fill=(255, 255, 255, 255), outline=(15, 60, 70, 255), width=sc(10))

icon = icon.resize((S, S), Image.LANCZOS)
icon.save("PhoneConnect.png")
icon.save("PhoneConnect.ico", sizes=[(16,16),(24,24),(32,32),(48,48),(64,64),(128,128),(256,256)])
icon.save("PhoneConnect.icns", sizes=[(16,16),(32,32),(64,64),(128,128),(256,256),(512,512),(1024,1024)])
print("done")
