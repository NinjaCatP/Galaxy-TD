# Procedural original planet textures (equirectangular, horizontally tileable), icons and nebula.
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
W, H = 256, 128
lon = np.linspace(0, 2*np.pi, W, endpoint=False)[None, :]
lat = np.linspace(0, np.pi, H)[:, None]
def noise(seed, terms=70, maxf=14, decay=1.1):
    r = np.random.default_rng(seed); out = np.zeros((H, W))
    for _ in range(terms):
        n = r.integers(1, maxf); m = r.uniform(0.5, maxf); a = 1.0 / n**decay
        out += a*np.sin(n*lon + r.uniform(0, 6.28)) * np.sin(m*lat + r.uniform(0, 6.28))
    out = (out - out.min()) / (out.max() - out.min()); return out
def ramp(v, stops):
    xs = [s[0] for s in stops]; cs = np.array([s[1] for s in stops], float)
    return np.stack([np.interp(v, xs, cs[:, i]) for i in range(3)], -1)
def save(name, rgb, a=None):
    img = np.clip(rgb, 0, 255).astype('uint8')
    if a is not None: img = np.dstack([img, (np.clip(a, 0, 1)*255).astype('uint8')])
    Image.fromarray(img).save(f"planets/{name}.png")
n = noise(1); d = noise(2, maxf=30)
rocky = ramp(0.7*n+0.3*d, [(0, (70, 60, 55)), (0.5, (130, 115, 100)), (1, (190, 175, 155))])
r = np.random.default_rng(3)
im = Image.fromarray(rocky.astype('uint8')); dr = ImageDraw.Draw(im, 'RGBA')
for _ in range(60):
    x, y, s = r.integers(0, W), r.integers(15, H-15), r.integers(2, 9)
    dr.ellipse((x-s, y-s, x+s, y+s), fill=(50, 42, 38, 110)); dr.arc((x-s, y-s, x+s, y+s), 200, 340, fill=(210, 200, 185, 140))
im.save("planets/rocky.png")
h = noise(4, decay=1.0); land = h > 0.55
terran = np.where(land[..., None], ramp(h, [(0.55, (70, 140, 60)), (0.75, (120, 110, 70)), (1, (200, 200, 190))]), ramp(h, [(0, (10, 30, 90)), (0.55, (40, 110, 190))]))
pole = (np.abs(lat - np.pi/2) > 1.25)[..., None] * np.ones((1, W, 1)); terran = np.where(pole > 0, [235, 245, 250], terran)
save("terran", terran)
bands = np.sin(lat*14 + 2.5*noise(5, maxf=6)) * 0.5 + 0.5
save("gas", ramp(0.8*bands + 0.2*noise(6), [(0, (150, 90, 50)), (0.4, (215, 170, 110)), (0.7, (240, 220, 180)), (1, (180, 110, 70))]))
i = noise(7); cracks = np.abs(noise(8, maxf=25) - 0.5) < 0.02
ice = ramp(i, [(0, (150, 190, 220)), (1, (240, 250, 255))]); ice[cracks] = [90, 140, 190]; save("ice", ice)
l = noise(9); lc = np.abs(noise(10, maxf=20) - 0.5) < 0.04
lava = ramp(l, [(0, (25, 15, 15)), (1, (80, 40, 30))]); lava[lc] = [255, 140, 30]; lava[np.abs(noise(11, maxf=12)-0.5) < 0.015] = [255, 220, 90]
img = Image.fromarray(lava.astype('uint8')).filter(ImageFilter.GaussianBlur(0.7)); img.save("planets/lava.png")
c = noise(12, maxf=18); save("clouds", np.full((H, W, 3), 255.0), np.clip((c - 0.5) * 2.5, 0, 0.9))
# nebula background
NW, NH = 780, 360
x = np.linspace(0, 1, NW)[None, :]; y = np.linspace(0, 1, NH)[:, None]; r = np.random.default_rng(20); neb = np.zeros((NH, NW, 3))
for col in [(90, 40, 140), (30, 70, 150), (150, 40, 90)]:
    f = np.zeros((NH, NW))
    for _ in range(40):
        f += np.sin(x*r.uniform(2, 12)*np.pi + r.uniform(0, 6)) * np.sin(y*r.uniform(2, 10)*np.pi + r.uniform(0, 6)) / r.uniform(2, 6)
    f = np.clip((f - f.mean()) / f.std() * 0.5, 0, 1)**2
    neb += f[..., None]*np.array(col)
neb = neb*0.6 + 6
img = Image.fromarray(np.clip(neb, 0, 255).astype('uint8')).resize((1560, 720), Image.BICUBIC)
dr = ImageDraw.Draw(img)
for _ in range(500):
    px, py = r.integers(0, 1560), r.integers(0, 720); b = int(r.integers(120, 255)); s = r.choice([0, 0, 0, 1])
    dr.ellipse((px-s, py-s, px+s, py+s), fill=(b, b, b))
img.save("nebula.jpg", quality=85)
# icons 48x48
def icon(name, fn):
    im = Image.new('RGBA', (48, 48)); fn(ImageDraw.Draw(im)); im.save(f"icons/{name}.png")
icon("factory", lambda d: (d.rectangle((6, 22, 42, 42), fill=(240, 200, 80)), d.polygon([(6, 22), (16, 12), (16, 22), (26, 12), (26, 22), (36, 12), (36, 22)], fill=(240, 200, 80)), d.rectangle((34, 4, 40, 18), fill=(200, 160, 60)), [d.rectangle((10+i*10, 28, 16+i*10, 34), fill=(90, 70, 30)) for i in range(3)]))
icon("shield", lambda d: (d.polygon([(24, 4), (42, 10), (40, 28), (24, 44), (8, 28), (6, 10)], fill=(90, 180, 255)), d.polygon([(24, 10), (36, 14), (34, 27), (24, 38)], fill=(170, 220, 255))))
icon("back", lambda d: (d.polygon([(6, 24), (22, 8), (22, 18), (42, 18), (42, 30), (22, 30), (22, 40)], fill=(220, 220, 230))))
icon("ship", lambda d: (d.polygon([(44, 24), (8, 8), (16, 24), (8, 40)], fill=(130, 200, 255)), d.ellipse((4, 20, 12, 28), fill=(255, 210, 120))))
icon("tower", lambda d: (d.regular_polygon((24, 28, 16), 8, fill=(110, 115, 125)), d.rectangle((22, 4, 26, 26), fill=(60, 60, 60)), d.ellipse((16, 20, 32, 36), fill=(255, 215, 100))))
print("ok")
