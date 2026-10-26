# Procedural capital-ship (mothership) texture, pointing right. Rendered at 2x then downsampled.
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
S = 2; W, H = 1024*S, 440*S
cy = H//2
r = np.random.default_rng(42)
img = Image.new('RGBA', (W, H)); d = ImageDraw.Draw(img)
def P(pts): return [(x*S, cy + y*S) for x, y in pts]
def sym(pts): return pts + [(x, -y) for x, y in reversed(pts)]
# layer 1: outer hull
outer = sym([(1000, 0), (860, -40), (700, -70), (560, -120), (420, -130), (300, -175), (170, -180), (120, -140), (60, -135), (30, -90)])
d.polygon(P(outer), fill=(58, 66, 82)); d.line(P(outer + [outer[0]]), fill=(120, 150, 190), width=3*S)
# layer 2: armour band
mid = sym([(960, 0), (840, -26), (680, -50), (540, -90), (400, -100), (280, -140), (160, -140), (90, -100), (50, -70)])
d.polygon(P(mid), fill=(78, 88, 108))
# plating rects
mask = Image.new('L', (W, H)); ImageDraw.Draw(mask).polygon(P(mid), fill=255)
plates = Image.new('RGBA', (W, H)); pd = ImageDraw.Draw(plates)
for _ in range(900):
    x = r.integers(40, 980); y = r.integers(-150, 150); w = r.integers(12, 60); h = r.integers(6, 28)
    g = int(r.integers(70, 120)); pd.rectangle((x*S, cy+y*S, (x+w)*S, cy+(y+h)*S), fill=(g, g+8, g+24), outline=(40, 46, 58), width=S)
pa = np.array(plates); pa[..., 3] = np.minimum(pa[..., 3], np.array(mask)); img = Image.alpha_composite(img, Image.fromarray(pa))
d = ImageDraw.Draw(img)
# spine / superstructure
spine = sym([(880, 0), (760, -14), (420, -22), (300, -40), (150, -40), (110, -20)])
d.polygon(P(spine), fill=(105, 116, 138)); d.line(P(spine + [spine[0]]), fill=(160, 185, 220), width=2*S)
for x in range(140, 860, 24): d.line(P([(x, -20), (x, 20)]), fill=(70, 78, 96), width=S)
# bridge tower
d.polygon(P([(300, -40), (330, -78), (420, -78), (440, -40)]), fill=(92, 102, 122))
d.rectangle(P([(338, -70), (412, -60)]), fill=(150, 230, 255))
# panel lines across hull
for x in range(80, 960, 46): d.line(P([(x, -150), (x, 150)]), fill=(44, 50, 64, 150), width=S)
d.line(P([(60, -60), (900, -20)]), fill=(44, 50, 64), width=S); d.line(P([(60, 60), (900, 20)]), fill=(44, 50, 64), width=S)
# window strips
for row in (-95, -70, 70, 95):
    for x in range(180, 560, 9):
        if r.random() < 0.75: d.rectangle(P([(x, row), (x+4, row+3)]), fill=(255, 225, 150))
# turrets
for x, y in [(240, -120), (380, -105), (520, -85), (240, 120), (380, 105), (520, 85), (650, -55), (650, 55)]:
    d.ellipse(P([(x-16, y-16), (x+16, y+16)]), fill=(70, 78, 94), outline=(150, 175, 210), width=2*S)
    d.ellipse(P([(x-8, y-8), (x+8, y+8)]), fill=(110, 120, 140))
    d.line(P([(x, y), (x+34, y + (-6 if y < 0 else 6))]), fill=(140, 150, 170), width=5*S)
# antennas
for x, y, L in [(360, -78, -60), (395, -78, -40), (200, -175, -30), (200, 175, 30)]:
    d.line(P([(x, y), (x, y+L)]), fill=(170, 180, 200), width=2*S); d.ellipse(P([(x-3, y+L-3), (x+3, y+L+3)]), fill=(255, 90, 90))
# engine blocks (nozzles; flames are drawn live in-game)
for y in (-120, -60, 0, 60, 120):
    d.rectangle(P([(0, y-22), (70, y+22)]), fill=(64, 70, 86), outline=(130, 150, 180), width=2*S)
    d.ellipse(P([(-6, y-18), (22, y+18)]), fill=(20, 30, 50)); d.ellipse(P([(0, y-12), (16, y+12)]), fill=(120, 200, 255))
# hangar bay
d.rectangle(P([(760, -10), (900, 10)]), fill=(30, 36, 48)); d.rectangle(P([(770, -4), (890, 4)]), fill=(90, 170, 255))
hull_a = Image.new('L', (W, H)); ImageDraw.Draw(hull_a).polygon(P(outer), fill=255); hull_a = hull_a.filter(ImageFilter.MaxFilter(9))
fa = np.array(img); fa[..., 3] = np.where(np.array(hull_a) > 0, fa[..., 3], 0); fa[..., 3] = np.maximum(fa[..., 3], 0); img = Image.fromarray(fa)
# re-add parts outside hull (engines, antennas) are inside dilated mask or redrawn:
d = ImageDraw.Draw(img)
for x, y, L in [(200, -175, -30), (200, 175, 30)]:
    d.line(P([(x, y), (x, y+L)]), fill=(170, 180, 200), width=2*S); d.ellipse(P([(x-3, y+L-3), (x+3, y+L+3)]), fill=(255, 90, 90))
for y in (-120, -60, 0, 60, 120):
    d.rectangle(P([(0, y-22), (70, y+22)]), fill=(64, 70, 86), outline=(130, 150, 180), width=2*S)
    d.ellipse(P([(-6, y-18), (22, y+18)]), fill=(20, 30, 50)); d.ellipse(P([(0, y-12), (16, y+12)]), fill=(120, 200, 255))
img = img.resize((W//S, H//S), Image.LANCZOS)
# subtle shading top-lit
a = np.array(img).astype(float); yy = np.linspace(1.15, 0.75, a.shape[0])[:, None]
a[..., :3] *= yy[..., None]; img = Image.fromarray(np.clip(a, 0, 255).astype('uint8'))
img.save('/workspace/galaxy-td/project/art/ships/mothership.png')
# soft glow sprite for engines/aura
g = np.zeros((128, 128)); yy, xx = np.mgrid[-1:1:128j, -1:1:128j]; g = np.clip(1 - np.sqrt(xx**2+yy**2), 0, 1)**2
Image.fromarray(np.dstack([np.full((128, 128, 3), 255), (g*255)]).astype('uint8')).save('/workspace/galaxy-td/project/art/ships/glow.png')
print(img.size)
