# Procedural, original audio for Galaxy TD (no third-party samples).
import numpy as np, wave, subprocess, os
SR = 22050
rng = np.random.default_rng(7)
def t(d): return np.arange(int(SR*d))/SR
def env(n, a=0.005, r=None):
    e = np.ones(n); ai = max(1,int(a*SR)); e[:ai] = np.linspace(0,1,ai)
    rr = n-ai if r is None else int(r*SR); e[-rr:] *= np.linspace(1,0,rr)**2; return e
def sweep(f0, f1, d, kind="sin"):
    tt = t(d); f = np.linspace(f0, f1, len(tt)); ph = 2*np.pi*np.cumsum(f)/SR
    return np.sin(ph) if kind=="sin" else (np.sign(np.sin(ph))*0.6 if kind=="sq" else 2*((ph/(2*np.pi))%1)-1)
def noise(d): return rng.uniform(-1,1,int(SR*d))
def lp(x, a=0.2):
    y = np.zeros_like(x); acc = 0.0
    for i,v in enumerate(x): acc += a*(v-acc); y[i] = acc
    return y
def save(name, x, vol=0.8, q=2):
    x = x/ (np.max(np.abs(x))+1e-9) * vol
    pcm = (x*32767).astype(np.int16)
    with wave.open(f"{name}.wav","wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",f"{name}.wav","-c:a","libvorbis","-q:a",str(q),f"../project/audio/{name}.ogg"],check=True)
def tone(f, d, kind="sin", r=None):
    x = sweep(f, f, d, kind); return x*env(len(x), r=r)

save("launch", sweep(300, 900, 0.25)*env(int(0.25*SR)) + 0.3*lp(noise(0.25),0.3)*env(int(0.25*SR)))
save("capture", np.concatenate([tone(523,0.09), tone(659,0.09), tone(784,0.18)]))
save("shot_gun", (lp(noise(0.08),0.5)+0.5*sweep(900,200,0.08,"sq"))*env(int(0.08*SR),0.001), 0.6)
save("shot_frost", sweep(1800,1200,0.18)*env(int(0.18*SR))*(1+0.5*np.sin(2*np.pi*40*t(0.18))), 0.5)
save("shot_missile", (sweep(200,60,0.35,"saw")*0.5+lp(noise(0.35),0.15))*env(int(0.35*SR),0.002), 0.7)
save("shot_laser", sweep(1400,700,0.12,"saw")*env(int(0.12*SR),0.001), 0.45)
save("death", sweep(500,80,0.2,"sq")*env(int(0.2*SR),0.001), 0.5)
save("core_hit", (sweep(120,40,0.4)+0.6*lp(noise(0.4),0.1))*env(int(0.4*SR),0.001))
save("win", np.concatenate([tone(523,0.12),tone(659,0.12),tone(784,0.12),tone(1047,0.45,r=0.4)]))
save("lose", np.concatenate([tone(392,0.2,"saw"),tone(330,0.2,"saw"),tone(262,0.6,"saw",r=0.5)]), 0.6)
save("tap", tone(1200,0.04)*0.8, 0.4)
save("upgrade", np.concatenate([sweep(400,1600,0.25)*env(int(0.25*SR)), tone(1600,0.2,r=0.18)]))
save("build", np.concatenate([tone(300,0.06,"sq"), tone(450,0.1,"sq")]), 0.5)

def music(name, bpm, chords, bars, lead=True, drums=False, pad_kind="sin"):
    beat = 60/bpm; bar = beat*4; out = np.zeros(int(SR*bar*bars))
    for b in range(bars):
        root = chords[b % len(chords)]; s = int(b*bar*SR); n = int(bar*SR); tt = np.arange(n)/SR
        pad = sum(np.sin(2*np.pi*root*m*tt + 0.3*np.sin(2*np.pi*0.3*tt)) for m in (1, 1.5, 2, 2.52))
        e = np.minimum(1, np.minimum(tt/0.6, (bar-tt)/0.6))
        out[s:s+n] += 0.18*pad*e
        for k in range(8 if drums else 4):
            ns = s + int(k*bar/(8 if drums else 4)*SR); d = beat*(0.5 if drums else 1)
            f = root/2 if (k % 2 == 0) else root*0.75
            x = sweep(f, f, d, "saw" if drums else "sin")*env(int(d*SR), r=d*0.8)
            out[ns:ns+len(x)] += (0.25 if drums else 0.3)*lp(x, 0.08)
        if drums:
            for k in range(4):
                ks = s + int(k*beat*SR); kk = sweep(120,40,0.15)*env(int(0.15*SR),0.001); out[ks:ks+len(kk)] += 0.6*kk
                hs = ks + int(beat*0.5*SR); hh = noise(0.04)*env(int(0.04*SR),0.001); out[hs:hs+len(hh)] += 0.12*hh
        if lead:
            scale = [1, 1.125, 1.25, 1.5, 1.6875, 2]
            for k in range(4):
                if rng.random() < 0.6:
                    f = root*2*scale[rng.integers(len(scale))]; d = beat*rng.choice([1, 2])
                    ns = s + int(k*beat*SR); x = sweep(f, f, d)*env(int(d*SR), 0.05, d*0.7)
                    out[ns:ns+len(x)] += 0.12*x
    save(name, out, 0.6, q=0)
music("music_galaxy", 70, [110, 87.3, 98, 82.4], 8)
music("music_battle", 132, [110, 110, 98, 116.5], 16, lead=False, drums=True)
