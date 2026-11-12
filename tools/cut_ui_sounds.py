#!/usr/bin/env python3
"""Cut the menu sounds in sounds/ out of the take in models/, for 'Kardashev'.

The .wav files ARE committed — nobody needs ffmpeg to run or build the game. This only has to
run if the source take is replaced, and it prints what it found on the way so the claim the
game is built on can be checked rather than believed:

    tools/cut_ui_sounds.py

── What is in the take ──

freesound_community-menu-select-sound-100466.mp3 is 3.768 s of somebody using a menu. There are
seven hits in it and two sounds. Six of the hits are the same 523 Hz waveform and the seventh,
at 1.624 s, is another an octave below at 262 Hz.

The run below is what says so. It reports each run of sound with its four strongest partials and
its best-lag correlation against the first one: the repeats come back at 1.00, which is the same
waveform arriving at a different moment, and the low one at well under half that. (It prints six
runs rather than seven because the fourth and fifth overlap — the envelope dips but does not
reach silence between them — which the 180 ms length of that run gives away against ~100 ms for
every other.) The right channel carries the same hits a shade quieter, with nothing hidden in
it, so everything here is cut from the left.

That is why the game has two samples and not six:

    sounds/ui_move.wav     523 Hz — the one the take repeats, a menu being scrolled
    sounds/ui_select.wav   262 Hz — the one it lands on at the end, the thing chosen

ui_sound.gd makes a third role out of the second sample by pitching it down a fourth. There is
no third file because there was no third sound to cut one from.

── What is done to them ──

Normalised from the take's −26 dBFS peak up to −3, and given a 1 ms fade in and an 8 ms fade
out, so each one starts and ends on silence instead of on the click an abrupt cut leaves.
"""
import os
import subprocess
import sys
import wave

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "models", "freesound_community-menu-select-sound-100466.mp3")
OUT_DIR = os.path.join(ROOT, "sounds")

## Where each sample is cut from, in seconds. A little before the onset and a little after the
## decay, so the attack is whole and the fade has silence to work on.
CUTS = [
    ("ui_move.wav", 0.030, 0.152),      # the first hit, the one with a second of silence round it
    ("ui_select.wav", 1.619, 1.741),    # the last hit, the only one that is a different sound
]

PEAK_DBFS = -3.0
FADE_IN_MS = 1.0
FADE_OUT_MS = 8.0
## A hit is any run of 1 ms blocks above this, and runs closer together than the gap are one hit.
ONSET_DBFS = -70.0
GAP_MS = 8


def decode(path):
    """The take as (left channel, sample rate), via ffmpeg."""
    tmp = os.path.join(OUT_DIR, ".decoded.wav")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ar", "48000",
                    "-c:a", "pcm_s16le", tmp], check=True)
    with wave.open(tmp) as w:
        sr = w.getframerate()
        a = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768.0
    os.remove(tmp)
    return a[0::2], sr


def alike(ref, x):
    """Best-lag normalised correlation: 1.0 is the same waveform, whenever it starts.

    A plain dot product is no use here. These are ~500 Hz tones, so two copies of one that are
    half a period out of step correlate at −1 and a quarter period out at 0 — which says
    everything about where the window landed and nothing about what is in it.
    """
    a = ref / (np.linalg.norm(ref) + 1e-12)
    b = x / (np.linalg.norm(x) + 1e-12)
    return float(np.abs(np.correlate(a, b, "full")).max())


def partials(x, sr, n=4):
    """The n strongest, at least 40 Hz apart — enough to tell one blip from another."""
    sp = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    f = np.fft.rfftfreq(len(x), 1.0 / sr)
    out = []
    for i in np.argsort(sp)[::-1]:
        if all(abs(f[i] - u) > 40 for u in out):
            out.append(f[i])
        if len(out) == n:
            break
    return out


def report(ch, sr):
    """Print every hit in the take, and how alike it is to the first one."""
    blk = sr // 1000
    loud = np.abs(ch[:len(ch) // blk * blk]).reshape(-1, blk).max(axis=1) > 10 ** (ONSET_DBFS / 20)
    hits, i = [], 0
    while i < len(loud):
        if loud[i]:
            j = i
            while j < len(loud) and loud[j]:
                j += 1
            if j - i > 5:
                if hits and i - hits[-1][1] < GAP_MS:
                    hits[-1] = (hits[-1][0], j)
                else:
                    hits.append((i, j))
            i = j
        else:
            i += 1
    print("%d hits in %s" % (len(hits), os.path.basename(SRC)))
    ref = None
    for i, j in hits:
        x = ch[i * blk:j * blk]
        if ref is None:
            ref = x
        print("  %.3f - %.3f s  %3d ms  partials %s  alike as first %.2f" % (
            i / 1000.0, j / 1000.0, j - i,
            " ".join("%5.0f" % p for p in partials(x, sr)), alike(ref, x)))


def cut(ch, sr, name, t0, t1):
    x = ch[int(t0 * sr):int(t1 * sr)].copy()
    fi, fo = int(sr * FADE_IN_MS / 1000.0), int(sr * FADE_OUT_MS / 1000.0)
    x[:fi] *= np.linspace(0.0, 1.0, fi)
    x[-fo:] *= np.linspace(1.0, 0.0, fo)
    x *= (10 ** (PEAK_DBFS / 20.0)) / max(np.abs(x).max(), 1e-9)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "w") as o:
        o.setnchannels(1)
        o.setsampwidth(2)
        o.setframerate(sr)
        o.writeframes((np.clip(x, -1.0, 1.0) * 32767).astype("<i2").tobytes())
    print("  wrote %-16s %.3f - %.3f s  %5.1f ms  %s" % (
        name, t0, t1, (t1 - t0) * 1000.0, " ".join("%.0f Hz" % p for p in partials(x, sr, 2))))


def main():
    if not os.path.exists(SRC):
        sys.exit("no source take at %s" % SRC)
    os.makedirs(OUT_DIR, exist_ok=True)
    ch, sr = decode(SRC)
    report(ch, sr)
    print("cutting:")
    for name, t0, t1 in CUTS:
        cut(ch, sr, name, t0, t1)


if __name__ == "__main__":
    main()
