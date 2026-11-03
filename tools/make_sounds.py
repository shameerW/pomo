"""Synthesise Pomo's phase sounds (additive synthesis, no samples): a deep gong for the end of a
focus block and a Tibetan singing bowl for the start of the next one."""
import sys, wave
import numpy as np

SR = 44100

def render(partials, seconds, strike, attack, out, gain_db=-3.0, seed=7):
    rng = np.random.default_rng(seed)
    t = np.arange(int(SR * seconds)) / SR
    chans = []
    for side in (-1, 1):  # tiny per-channel detune → natural stereo width
        sig = np.zeros_like(t)
        for f, amp, decay, beat, glide in partials:
            f_side = f + side * beat / 2
            # Gongs bend slightly flat after the strike; integrate frequency to get phase.
            inst = f_side * (1 + glide * np.exp(-t / 0.35))
            phase = 2 * np.pi * np.cumsum(inst) / SR + rng.uniform(0, 2 * np.pi)
            sig += amp * np.exp(-t / decay) * np.sin(phase)
        # Mallet strike: short low-passed noise burst.
        n = rng.standard_normal(len(t)) * np.exp(-t / strike[0]) * strike[1]
        k = int(SR / strike[2]); n = np.convolve(n, np.ones(k) / k, mode="same")
        sig += n
        env = np.minimum(1, t / attack)
        fade = np.clip((seconds - t) / 0.6, 0, 1)
        chans.append(sig * env * fade)
    x = np.stack(chans, axis=1)
    x *= 10 ** (gain_db / 20) / np.max(np.abs(x))
    with wave.open(out, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())

# (freq Hz, amplitude, decay s, stereo beat Hz, pitch glide)
gong = [
    (98.0, 1.00, 4.5, 0.35, 0.020), (149.0, 0.55, 3.6, 0.50, 0.015), (199.5, 0.42, 3.0, 0.60, 0.010),
    (243.0, 0.30, 2.4, 0.80, 0.008), (304.0, 0.22, 1.9, 1.00, 0.005), (412.0, 0.14, 1.4, 1.30, 0.0),
    (529.0, 0.09, 1.0, 1.60, 0.0), (733.0, 0.05, 0.7, 2.00, 0.0),
]
bowl = [
    (262.0, 1.00, 6.5, 0.90, 0.0), (723.0, 0.45, 4.0, 1.40, 0.0), (1414.0, 0.20, 2.4, 2.10, 0.0),
    (2330.0, 0.07, 1.4, 2.80, 0.0), (131.0, 0.12, 5.0, 0.30, 0.0),
]
out = sys.argv[1] if len(sys.argv) > 1 else "."
render(gong, 7.0, strike=(0.03, 0.35, 900), attack=0.004, out=f"{out}/Gong.wav")
render(bowl, 9.0, strike=(0.012, 0.10, 3000), attack=0.012, out=f"{out}/Bowl.wav", gain_db=-5.0)
print("ok")
