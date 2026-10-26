# App icon: space gradient, lit ringed planet, glowing tower beacon, mothership silhouette.
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
N = 1024; OUT = '/workspace/galaxy-td/project/art/icon/'
yy, xx = np.mgrid[0:N, 0:N] / N
def background():
    d = np.sqrt((xx - 0.35)**2 + (yy - 0.3)**2)
    c1 = np.array([120, 50, 190]); c2 = np.array([10, 14, 45]); c3 = np.array([4, 4, 16])
    t = np.clip(d / 0.9, 0, 1)[..., None]
    rgb = np.where(t < 0.5, c1 + (c2 - c1) * (t / 0.5), c2 + (c3 - c2) * ((t - 0.5) / 0.5))
    neb = np.exp(-((xx - 0.75)**2 / 0.02 + (yy - 0.75)**2 / 0.05))[..., None] * np.array([30, 80, 160])[None, None, :]
    img = Image.fromarray(np.clip(rgb + neb, 0, 255).astype('uint8')).convert('RGBA')
    d = ImageDraw.Draw(img); r = np.random.default_rng(3)
    for _ in range(160):
        x, y = r.integers(0, N, 2); s = r.choice([1, 1, 2, 3]); b = int(r.integers(150, 255))
        d.ellipse((x - s, y - s, x + s, y + s), fill=(b, b, 255))
    return img
def foreground(scale=1.0):
    L = Image.new('RGBA', (N, N))
    # planet
    cx, cy, R = 600, 640, 300
    p = np.zeros((N, N, 4))
    dx = (xx * N - cx) / R; dy = (yy * N - cy) / R; r2 = dx**2 + dy**2; inside = r2 < 1
    z = np.sqrt(np.clip(1 - r2, 0, 1))
    light = np.clip(-0.6 * dx - 0.5 * dy + 0.62 * z, 0, 1)
    band = 0.5 + 0.5 * np.sin(dy * 9 + 0.6 * np.sin(dx * 4))
    base = np.stack([60 + 150 * band, 110 + 90 * band, 220 + 30 * band], -1)
    col = base * (0.12 + light[..., None]) + np.array([120, 180, 255]) * ((1 - z)**3)[..., None] * 0.8
    p[..., :3] = col; p[..., 3] = inside * 255
    planet = Image.fromarray(np.clip(p, 0, 255).astype('uint8'))
    glow = Image.new('RGBA', (N, N)); ImageDraw.Draw(glow).ellipse((cx - R - 40, cy - R - 40, cx + R + 40, cy + R + 40), fill=(90, 160, 255, 150))
    L = Image.alpha_composite(L, glow.filter(ImageFilter.GaussianBlur(40)))
    # ring back
    ring = Image.new('RGBA', (N, N)); rd = ImageDraw.Draw(ring)
    for w, a in [(30, 200), (12, 255)]:
        rd.ellipse((cx - 470, cy - 120, cx + 470, cy + 120), outline=(255, 200, 120, a), width=w)
    ring = ring.rotate(18, center=(cx, cy), resample=Image.BICUBIC)
    L = Image.alpha_composite(L, ring)
    L = Image.alpha_composite(L, planet)
    front = np.array(ring); front[:cy + 0, :, 3] = 0  # ring front half over the planet
    L = Image.alpha_composite(L, Image.fromarray(front))
    # tower beacon on the planet limb
    tx, ty = 800, 430
    bg = Image.new('RGBA', (N, N)); bd = ImageDraw.Draw(bg); bd.ellipse((tx - 90, ty - 120, tx + 90, ty + 60), fill=(255, 210, 90, 200))
    L = Image.alpha_composite(L, bg.filter(ImageFilter.GaussianBlur(35)))
    d = ImageDraw.Draw(L)
    d.polygon([(tx - 34, ty + 50), (tx - 18, ty - 50), (tx + 18, ty - 50), (tx + 34, ty + 50)], fill=(70, 80, 105), outline=(200, 220, 255), width=4)
    d.ellipse((tx - 26, ty - 86, tx + 26, ty - 34), fill=(255, 230, 140), outline=(255, 255, 255), width=4)
    d.line((tx, ty - 60, tx + 60, ty - 110), fill=(255, 240, 200), width=10)
    # mothership, diagonal, top-left to centre
    ms = Image.open('/workspace/galaxy-td/project/art/ships/mothership.png').convert('RGBA')
    ms = ms.resize((620, int(620 * ms.height / ms.width)), Image.LANCZOS).rotate(28, expand=True, resample=Image.BICUBIC)
    sh = Image.new('RGBA', ms.size, (120, 190, 255, 0)); a = ms.split()[3]
    halo = Image.new('RGBA', ms.size, (110, 180, 255, 255)); halo.putalpha(a.filter(ImageFilter.GaussianBlur(14)).point(lambda v: v * 0.8))
    pos = (40, 60)
    L.alpha_composite(halo, pos); L.alpha_composite(ms, pos)
    # engine glow
    eg = Image.new('RGBA', (N, N)); ImageDraw.Draw(eg).ellipse((40, 360, 150, 470), fill=(140, 210, 255, 200))
    L = Image.alpha_composite(L, eg.filter(ImageFilter.GaussianBlur(28)))
    if scale != 1.0:
        S = int(N * scale); small = L.resize((S, S), Image.LANCZOS); L = Image.new('RGBA', (N, N)); L.alpha_composite(small, ((N - S) // 2, (N - S) // 2))
    return L
bg = background(); fg = foreground()
full = Image.alpha_composite(bg, fg)
mask = Image.new('L', (N, N)); ImageDraw.Draw(mask).rounded_rectangle((0, 0, N - 1, N - 1), 180, fill=255)
full.save(OUT + 'icon_1024.png')
full.resize((256, 256), Image.LANCZOS).save('/workspace/galaxy-td/project/icon.png')
full.resize((192, 192), Image.LANCZOS).save(OUT + 'icon_192.png')
foreground(0.62).resize((432, 432), Image.LANCZOS).save(OUT + 'adaptive_fg_432.png')
bg.resize((432, 432), Image.LANCZOS).save(OUT + 'adaptive_bg_432.png')
# preview sheet
sheet = Image.new('RGBA', (1600, 620), (24, 26, 34, 255)); x = 20
for s in [512, 192, 96, 48]:
    im = full.resize((s, s), Image.LANCZOS); m = mask.resize((s, s)); sheet.paste(im, (x, 40), m); x += s + 40
ad = Image.alpha_composite(bg, foreground(0.62)).resize((300, 300), Image.LANCZOS)
cm = Image.new('L', (300, 300)); ImageDraw.Draw(cm).ellipse((0, 0, 299, 299), fill=255); sheet.paste(ad, (x, 40), cm)
sheet.save('/workspace/galaxy-td/screens/icon.png'); print('ok')
