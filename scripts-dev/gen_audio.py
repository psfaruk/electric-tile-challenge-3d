#!/usr/bin/env python3
"""Synthesize all original sound effects + music loops for Electric Tile
Challenge 3D. numpy + stdlib wave writer. Deterministic. Run from repo root:
    python3 scripts-dev/gen_audio.py
"""
import os
import struct
import wave

import numpy as np

SR = 44100
rng = np.random.default_rng(42)

OUT_SFX = "assets/audio/sfx"
OUT_MUS = "assets/audio/music"
os.makedirs(OUT_SFX, exist_ok=True)
os.makedirs(OUT_MUS, exist_ok=True)


def write_wav(path, samples, normalize_to=0.85):
    x = np.asarray(samples, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * normalize_to
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767.0).astype("<i2").tobytes()
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data)
    print(f"  wrote {path}  {len(x)/SR:.2f}s  {len(data)} bytes")


def t(n):
    return np.arange(int(round(n * SR))) / SR


def sine(freq, dur, phase=0.0):
    return np.sin(2 * np.pi * freq * t(dur) + phase)


def sweep(f0, f1, dur):
    tt = t(dur)
    freq = np.linspace(f0, f1, tt.size)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR)


def saw(freq, dur):
    tt = t(dur)
    return 2.0 * ((freq * tt) % 1.0) - 1.0


def square(freq, dur):
    return np.sign(sine(freq, dur)) * 0.6


def noise(dur):
    return rng.uniform(-1.0, 1.0, int(round(dur * SR)))


def lowpass(x, fc):
    """FFT-domain one-pole style filter."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(x.size, 1 / SR)
    gain = 1.0 / (1.0 + (freqs / max(1.0, fc)) ** 2)
    return np.fft.irfft(spec * gain, x.size)


def env(x, a=0.005, d=0.08, s=0.0, r=0.05):
    n = x.size
    aa = max(1, int(a * SR))
    dd = max(1, int(d * SR))
    rr = max(1, int(r * SR))
    e = np.ones(n)
    e[:aa] = np.linspace(0, 1, aa)
    if aa + dd < n and s <= 0.0:
        e[aa:aa + dd] = np.linspace(1, 0, dd)[..., : max(0, min(dd, n - aa))]
        e[aa + dd:] = 0.0
    else:
        if aa + dd < n:
            e[aa:aa + dd] = np.linspace(1, max(0.0, s), dd)
            e[aa + dd: n - rr] = s
            e[n - rr:] = np.linspace(s, 0, rr)
    tail = max(1, int(0.02 * SR))
    e[n - tail:] *= np.linspace(1, 0, tail)
    return x * e[:n]


def mix(*parts):
    n = max(p.size for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: p.size] += p
    return out


def delayed(x, sec):
    pad = np.zeros(int(round(sec * SR)))
    return np.concatenate([pad, x])


def gen_sfx():
    print("SFX:")
    write_wav(f"{OUT_SFX}/ui_click.wav", env(mix(env(sine(1900, 0.06), 0.001, 0.05), env(noise(0.05), 0.001, 0.012) * 0.5)))
    write_wav(f"{OUT_SFX}/ui_back.wav", env(sweep(620, 380, 0.11), 0.002, 0.1))
    st = mix(lowpass(noise(0.08), 900) * 0.9, env(sine(150, 0.07), 0.001, 0.06) * 0.8)
    write_wav(f"{OUT_SFX}/step.wav", env(st, 0.002, 0.07))
    write_wav(f"{OUT_SFX}/jump.wav", env(sweep(300, 640, 0.13), 0.004, 0.12))
    write_wav(f"{OUT_SFX}/land.wav", env(mix(sine(110, 0.09) * 0.9, env(lowpass(noise(0.09), 600) * 0.5, 0.001, 0.05)), 0.001, 0.09))
    write_wav(f"{OUT_SFX}/tile_show.wav", env(mix(sine(880, 0.2) * 0.6, sine(1760, 0.2) * 0.25), 0.01, 0.2, 0.0, 0.1))
    write_wav(f"{OUT_SFX}/tile_good.wav", env(mix(sine(1046.5, 0.15) * 0.7, sine(1318.5, 0.15) * 0.4, sine(2093, 0.15) * 0.15), 0.003, 0.14, 0.0, 0.06))
    write_wav(f"{OUT_SFX}/seq_note.wav", env(mix(sine(660, 0.18) * 0.8, sine(1320, 0.18) * 0.3), 0.004, 0.16, 0.0, 0.07))
    zap = sweep(2800, 90, 0.38) * 0.8 + lowpass(noise(0.38), 4000) * 0.55
    crackle = noise(0.38) * (rng.uniform(0, 1, int(0.38 * SR)) > 0.995)
    write_wav(f"{OUT_SFX}/zap.wav", env(mix(zap, crackle * 3.0), 0.001, 0.36, 0.0, 0.05), normalize_to=0.95)
    fail = mix(
        env(sine(392, 0.17), 0.005, 0.15),
        delayed(env(sine(311, 0.17), 0.005, 0.15), 0.19),
        delayed(env(mix(sine(247, 0.2), sine(123.5, 0.2) * 0.6), 0.005, 0.19), 0.38),
    )
    write_wav(f"{OUT_SFX}/fail.wav", fail)
    warn = np.concatenate([env(square(950, 0.09), 0.003, 0.08), np.zeros(int(0.07 * SR)), env(square(950, 0.09), 0.003, 0.08)])
    write_wav(f"{OUT_SFX}/warn.wav", warn * 0.8)
    write_wav(f"{OUT_SFX}/go.wav", env(mix(sweep(620, 990, 0.17), sine(1240, 0.17) * 0.2), 0.004, 0.16))
    write_wav(f"{OUT_SFX}/count.wav", env(sine(880, 0.09), 0.002, 0.08))
    write_wav(f"{OUT_SFX}/star.wav", env(mix(sine(1568, 0.22) * 0.7, sine(2093, 0.22) * 0.2), 0.003, 0.2, 0.0, 0.08))
    unlock = mix(env(sine(523.25, 0.09), 0.003, 0.08), delayed(env(sine(784, 0.09), 0.003, 0.08), 0.1), delayed(env(sine(1046.5, 0.14), 0.003, 0.13), 0.2))
    write_wav(f"{OUT_SFX}/unlock.wav", unlock)


def pad_chord(freqs, dur, detune=0.004, vol=0.14):
    out = np.zeros(int(round(dur * SR)))
    for f in freqs:
        out += lowpass(saw(f * (1 + detune), dur), 900) * vol
        out += lowpass(saw(f * (1 - detune), dur), 900) * vol
    return out


def pluck(f, dur, vol=0.2):
    return env(sine(f, dur) * 0.8 + sine(f * 2, dur) * 0.2 + noise(dur) * 0.02, 0.002, dur * 0.9)


def gen_music_menu():
    print("music_menu.wav")
    bpm = 95.0
    spb = 60.0 / bpm
    bars = 4
    beats_per_bar = 3  # waltz-ish relaxed loop
    total = int(round(bars * beats_per_bar * spb * SR))
    out = np.zeros(total)
    chords = [
        [220.0, 261.63, 329.63],   # Am
        [174.61, 220.0, 261.63],   # F
        [130.81, 164.81, 196.0],   # C
        [196.0, 246.94, 293.66],   # G
    ]
    bar_len = int(round(beats_per_bar * spb * SR))
    for b in range(bars):
        ch = chords[b]
        seg = np.zeros(total)
        seg[:bar_len] += pad_chord(ch, bar_len / SR, vol=0.10)
        bass = env(sine(ch[0] / 2.0, spb * 0.95), 0.01, spb * 0.8, 0.0, 0.1) * 0.30
        bass = np.pad(bass, (0, max(0, bar_len - bass.size)))
        seg[:bar_len] += bass[:bar_len]  # bass
        for beat in range(beats_per_bar):
            for sub in range(2):
                f = ch[(beat + sub) % 3] * 2.0
                p = pluck(f, 0.16, 0.16) * (1.0 if sub == 0 else 0.55)
                start = b * bar_len + int(round((beat + sub * 0.5) * spb * SR))
                end = min(total, start + p.size)
                seg[start:end] += p[: end - start]
            tick = lowpass(noise(0.03), 6000) * 0.05
            start = b * bar_len + int(round(beat * spb * SR))
            end = min(total, start + tick.size)
            seg[start:end] += tick[: end - start]
        start = b * bar_len
        end = min(total, start + seg.size)
        out[start:end] += seg[: end - start]
    out[: total] = lowpass(out, 2600) * 0.75 + out * 0.25
    write_wav(f"{OUT_MUS}/music_menu.wav", out, normalize_to=0.6)


def gen_music_game():
    print("music_game.wav")
    bpm = 128.0
    spb = 60.0 / bpm
    bars = 8
    total = int(round(bars * 4 * spb * SR))
    out = np.zeros(total)
    roots = [110.0, 110.0, 87.31, 98.0, 110.0, 130.81, 82.41, 98.0]  # A A F G A C E G
    bar_len = int(round(4 * spb * SR))
    for b in range(bars):
        root = roots[b]
        seg = np.zeros(bar_len)
        for eighth in range(8):
            tt = eighth * 0.5 * spb
            start = int(round(tt * SR))
            bass = env(sine(root, 0.22) + sine(root * 2, 0.22) * 0.3, 0.004, 0.2, 0.0, 0.04) * 0.5
            end = min(bar_len, start + bass.size)
            seg[start:end] += bass[: end - start]
            arp_f = root * 2 * [1.0, 1.5, 2.0, 2.9966 / 2.0 * 2][eighth % 4] / 2.0 * 2
            arp_f = root * 2.0 * (1.0 if eighth % 4 == 0 else (1.5 if eighth % 4 == 1 else (2.0 if eighth % 4 == 2 else 2.9973)))
            arp = pluck(arp_f, 0.14, 0.14) * (0.9 if eighth % 2 == 0 else 0.5)
            end = min(bar_len, start + arp.size)
            seg[start:end] += arp[: end - start]
        for beat in range(4):
            hat = lowpass(noise(0.025), 8000) * (0.05 if beat % 2 else 0.08)
            start = int(round(beat * spb * SR))
            end = min(bar_len, start + hat.size)
            seg[start:end] += hat[: end - start]
        start = b * bar_len
        end = min(total, start + seg.size)
        out[start:end] += seg[: end - start]
    if total > out.size:
        out = np.concatenate([out, np.zeros(total - out.size)])
    out = lowpass(out, 3200) * 0.6 + out * 0.4
    write_wav(f"{OUT_MUS}/music_game.wav", out, normalize_to=0.62)


if __name__ == "__main__":
    gen_sfx()
    gen_music_menu()
    gen_music_game()
    print("AUDIO: ALL GENERATED OK")
