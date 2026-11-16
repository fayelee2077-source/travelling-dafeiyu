# P1 ambient sounds, synthesised (no recordings, so nothing to license): rain, wind, crickets,
# bird chirps and a small splash. Writes WAV to a temp folder and converts to Ogg with ffmpeg.
#   python tools/p1_sounds.py
import math, os, random, struct, subprocess, tempfile, wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sounds")
os.makedirs(OUT, exist_ok=True)
SR = 22050
TMP = tempfile.mkdtemp(prefix="p1_sounds_")


def lowpass(x, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for v in x:
        y += a * (v - y)
        out.append(y)
    return out


def highpass(x, cutoff):
    low = lowpass(x, cutoff)
    return [a - b for a, b in zip(x, low)]


def normalize(x, peak):
    m = max(abs(v) for v in x) or 1.0
    return [v / m * peak for v in x]


def loop_seam(x, fade_s=1.0):
    """Crossfade the tail into the head so the sound loops without a click."""
    n = int(fade_s * SR)
    body = x[: len(x) - n]
    for i in range(n):
        t = i / n
        body[i] = body[i] * t + x[len(x) - n + i] * (1 - t)
    return body


def save(name, x):
    wav = os.path.join(TMP, name + ".wav")
    with wave.open(wav, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v)) * 32767)) for v in x))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "4",
                    os.path.join(OUT, name + ".ogg")], check=True)


def burst(buf, at, freq, decay, amp):
    """A short decaying sine ping (a raindrop, a drip)."""
    n = int(decay * 6 * SR)
    for i in range(n):
        j = at + i
        if j >= len(buf):
            break
        buf[j] += amp * math.exp(-i / (decay * SR)) * math.sin(2 * math.pi * freq * i / SR)


def swells(r, n, low, high, hz):
    """A slow random loudness curve between low and high (hz: how fast it wanders)."""
    return lowpass(lowpass([r.uniform(low, high) for _ in range(n)], hz), hz)


# Three kinds of rain the game mixes and changes between (11-16: one rain sound all the time is tiring),
# each longer than before so the repeat is harder to hear.
def rain(seconds=40):
    """Steady rain on leaves and ground (softer hiss than the first version)."""
    r = random.Random(1)
    n = seconds * SR
    hiss = highpass(lowpass([r.uniform(-1, 1) for _ in range(n)], 2200), 250)
    swell = swells(r, n, 0.3, 1.5, 0.25)
    x = [h * s * 0.4 for h, s in zip(hiss, swell)]
    for _ in range(seconds * 200):                      # patter on leaves and ground
        burst(x, r.randrange(n), r.uniform(1800, 4800), r.uniform(0.0015, 0.004), r.uniform(0.02, 0.08))
    for _ in range(seconds * 2):                        # heavier drips from the eaves
        burst(x, r.randrange(n), r.uniform(700, 1300), r.uniform(0.008, 0.02), r.uniform(0.08, 0.16))
    return normalize(loop_seam(x, 1.5), 0.6)


def rain_light(seconds=45):
    """A light shower: separate drops, almost no hiss, with near-quiet stretches."""
    r = random.Random(11)
    n = seconds * SR
    hiss = highpass(lowpass([r.uniform(-1, 1) for _ in range(n)], 1600), 300)
    swell = swells(r, n, 0.0, 1.3, 0.12)
    x = [h * max(s, 0.0) * 0.12 for h, s in zip(hiss, swell)]
    for _ in range(seconds * 70):
        at = r.randrange(n)
        burst(x, at, r.uniform(2000, 5000), r.uniform(0.002, 0.005), r.uniform(0.03, 0.1) * (0.3 + max(swell[at], 0.0)))
    for _ in range(seconds):
        burst(x, r.randrange(n), r.uniform(800, 1400), r.uniform(0.01, 0.025), r.uniform(0.06, 0.14))
    return normalize(loop_seam(x, 1.5), 0.5)


def rain_roof(seconds=40):
    """Rain on the roof and the porch: lower, rounder, with a slow rise and fall."""
    r = random.Random(21)
    n = seconds * SR
    hiss = highpass(lowpass([r.uniform(-1, 1) for _ in range(n)], 1100), 120)
    swell = swells(r, n, 0.4, 1.4, 0.18)
    x = [h * s * 0.5 for h, s in zip(hiss, swell)]
    for _ in range(seconds * 160):                      # drops on wood and tiles
        burst(x, r.randrange(n), r.uniform(450, 1300), r.uniform(0.003, 0.008), r.uniform(0.02, 0.07))
    return normalize(loop_seam(x, 1.5), 0.55)


def wind(seconds=21):
    r = random.Random(2)
    n = seconds * SR
    brown, b = [], 0.0
    for _ in range(n):
        b = b * 0.995 + r.uniform(-1, 1) * 0.05
        brown.append(b)
    gust = lowpass(lowpass([r.uniform(0.2, 1.6) for _ in range(n)], 0.15), 0.15)
    x = [v * g for v, g in zip(highpass(lowpass(brown, 700), 60), gust)]
    return normalize(loop_seam(x), 0.6)


def crickets(seconds=21):
    r = random.Random(3)
    n = seconds * SR
    x = [0.0] * n
    for pitch, gap, vol in ((4300, 0.55, 1.0), (4700, 0.8, 0.6), (3900, 0.7, 0.45)):
        t = r.uniform(0, gap)
        while t < seconds - 0.2:
            for p in range(r.choice((3, 4))):           # one chirp = 3-4 quick pulses
                start = int((t + p * 0.03) * SR)
                for i in range(int(0.014 * SR)):
                    env = math.sin(math.pi * i / (0.014 * SR))
                    if start + i < n:
                        x[start + i] += vol * env * math.sin(2 * math.pi * pitch * i / SR)
            t += gap * r.uniform(0.85, 1.2)
    x = [v * 0.25 + r.uniform(-1, 1) * 0.004 for v in x]
    return normalize(loop_seam(x, 0.5), 0.45)


def chirp(seed):
    r = random.Random(seed)
    x = [0.0] * int(1.2 * SR)
    t = 0.05
    kind = seed % 3
    for k in range(r.randint(2, 5)):
        dur = r.uniform(0.05, 0.09) if kind != 2 else r.uniform(0.12, 0.2)
        f0 = r.uniform(3000, 4200) if kind != 2 else r.uniform(2400, 3000)
        f1 = f0 * (r.uniform(1.2, 1.5) if kind == 0 else r.uniform(0.7, 0.85))
        start = int(t * SR)
        phase = 0.0
        for i in range(int(dur * SR)):
            u = i / (dur * SR)
            f = f0 + (f1 - f0) * u
            if kind == 1:
                f += math.sin(2 * math.pi * 38 * i / SR) * 300     # a little trill
            phase += 2 * math.pi * f / SR
            env = math.sin(math.pi * u) ** 1.5
            x[start + i] += env * (math.sin(phase) + 0.2 * math.sin(2 * phase))
        t += dur + r.uniform(0.03, 0.12)
        if t > 1.0:
            break
    return normalize(x, 0.5)


def splash():
    r = random.Random(9)
    n = int(0.5 * SR)
    noise = highpass(lowpass([r.uniform(-1, 1) for _ in range(n)], 3000), 600)
    x = [v * math.exp(-i / (0.06 * SR)) for i, v in enumerate(noise)]
    for k in range(4):                                  # a few bubbles
        burst(x, int(r.uniform(0.04, 0.2) * SR), r.uniform(500, 900), 0.02, 0.25)
    return normalize(x, 0.5)


save("rain", rain())
save("rain_light", rain_light())
save("rain_roof", rain_roof())
save("wind", wind())
save("crickets", crickets())
for i in range(4):
    save("bird_%d" % i, chirp(i))
save("splash", splash())
print("ok", OUT)
