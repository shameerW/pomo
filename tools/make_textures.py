"""Procedural material textures for Pomo's table and hourglass frame (no photos, no downloads).
Woods: fractal-noise turbulence → growth rings + along-grain streaks + pores, per-species palette.
Stones: slate (layered cleavage streaks) and marble (ridged-noise veins)."""
import sys, zlib, struct
import numpy as np

W, H = 1400, 360


def upsample(a, w, h):
    ys = np.linspace(0, a.shape[0] - 1, h); xs = np.linspace(0, a.shape[1] - 1, w)
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, a.shape[0] - 1); x1 = np.minimum(x0 + 1, a.shape[1] - 1)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    top = a[y0][:, x0] * (1 - fx) + a[y0][:, x1] * fx
    bot = a[y1][:, x0] * (1 - fx) + a[y1][:, x1] * fx
    return top * (1 - fy) + bot * fy


def fbm(rng, octaves, bw, bh, gain=0.5):
    out = np.zeros((H, W)); amp = 1.0; tot = 0
    for o in range(octaves):
        g = rng.uniform(-1, 1, (bh * 2 ** o + 2, bw * 2 ** o + 2))
        out += amp * upsample(g, W, H); tot += amp; amp *= gain
    return out / tot


def wood(seed, light, dark, rings=16, ring_sharp=7, contrast=0.55, pores=0.3):
    rng = np.random.default_rng(seed)
    y = np.linspace(0, 1, H)[:, None]; x = np.linspace(0, 1, W)[None, :]
    turb = fbm(rng, 5, 3, 2)
    r1 = np.sin(2 * np.pi * (y * rings + turb * 2.6 + 0.25 * np.sin(x * 3.1)))
    r2 = np.sin(2 * np.pi * (y * rings * 2.6 + turb * 5.0 + fbm(rng, 3, 4, 3) * 0.6))
    late = ((r1 * 0.5 + 0.5) ** ring_sharp) * 0.8 + ((r2 * 0.5 + 0.5) ** 9) * 0.35
    fine = fbm(rng, 4, 2, 70)
    pore = (upsample(rng.uniform(0, 1, (H // 2, 40)), W, H) > 0.93) * 0.5
    figure = fbm(rng, 3, 5, 2) * 0.5 + 0.5
    t = np.clip(contrast * late + 0.22 * (fine * 0.5 + 0.5) + 0.22 * (1 - figure) + pores * pore, 0, 1)[..., None]
    img = np.array(light) * (1 - t) + np.array(dark) * t
    return np.clip(img * (0.94 + 0.12 * figure[..., None]), 0, 1)


def slate(seed):
    rng = np.random.default_rng(seed)
    layers = fbm(rng, 5, 2, 40)                  # cleavage planes run along the slab
    speck = rng.uniform(0, 1, (H, W)) ** 12 * 0.25
    cloud = fbm(rng, 4, 6, 3) * 0.5 + 0.5
    base = np.array([0.30, 0.32, 0.34])
    img = base * (0.82 + 0.18 * cloud[..., None]) + layers[..., None] * 0.045 + speck[..., None]
    return np.clip(img, 0, 1)


def marble(seed):
    rng = np.random.default_rng(seed)
    y = np.linspace(0, 1, H)[:, None]; x = np.linspace(0, 1, W)[None, :]
    turb = fbm(rng, 6, 4, 3)
    vein = 1 - np.abs(np.sin(2 * np.pi * (x * 2.2 + y * 1.3 + turb * 2.4)))   # ridged noise → thin veins
    vein = vein ** 18
    fine = (1 - np.abs(np.sin(2 * np.pi * (x * 6 + turb * 5)))) ** 40 * 0.5
    cloud = fbm(rng, 4, 5, 3) * 0.5 + 0.5
    base = np.array([0.95, 0.94, 0.91]) * (0.95 + 0.05 * cloud[..., None])
    veins = np.clip(vein + fine, 0, 1)[..., None]
    return np.clip(base * (1 - veins * 0.55) + np.array([0.45, 0.45, 0.47]) * veins * 0.55, 0, 1)


def write_png(path, rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + (rgb[r] * 255).astype(np.uint8).tobytes() for r in range(h))
    ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                            + ch(b"IDAT", zlib.compress(raw, 9)) + ch(b"IEND", b""))


out = sys.argv[1]
textures = {
    "walnut":   wood(11, [0.62, 0.41, 0.23], [0.27, 0.15, 0.07]),
    "oak":      wood(23, [0.87, 0.72, 0.50], [0.63, 0.46, 0.27], rings=11, ring_sharp=5, contrast=0.45, pores=0.4),
    "ebony":    wood(37, [0.25, 0.20, 0.17], [0.06, 0.05, 0.04], rings=20, ring_sharp=9, contrast=0.5, pores=0.15),
    "mahogany": wood(41, [0.64, 0.28, 0.16], [0.32, 0.11, 0.06], rings=14, ring_sharp=6, contrast=0.5),
    "slate":    slate(53),
    "marble":   marble(61),
}
for name, img in textures.items():
    write_png(f"{out}/Texture-{name}.png", img)
    print(name)
