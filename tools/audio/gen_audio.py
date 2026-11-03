#!/usr/bin/env python3
"""Canadian Winter -- procedural audio generator.

Renders every sound effect, ambience loop and music track used by the game into
``assets/audio/<name>.wav`` (16-bit PCM, mono, 22050 Hz). Nothing is sampled or
downloaded: every sound is synthesized here from noise, oscillators, filters and
envelopes (granular crunch, modal impacts, stick-slip friction, pulse-train
engines, formant voices, wavetable pads, convolution reverb ...).

The output is deterministic: every sound gets its own RNG seeded from a fixed
global seed + the sound's name, so reruns reproduce identical files.

Usage (from the project root):
    python3 tools/audio/gen_audio.py              # render everything
    python3 tools/audio/gen_audio.py step_ music  # only names containing a filter

Seamless loops
--------------
The game loops the *whole* file (sample 0 .. last sample), so every loop is built
to be exactly periodic over its length:
  * noise colouring / filtering is done in the frequency domain over the loop
    length ("circular" filtering == the periodic steady state of the filter);
  * oscillators use an integer number of cycles per loop (``qf``);
  * events (grains, engine pulses, notes, crackles) are placed on a circular
    timeline, so tails (and reverb tails) that run past the end wrap onto the
    head of the file;
  * slow modulations (``pmod``) only contain integer-cycle frequency bins.
``make_loop_seamless`` (an equal-power tail-into-head crossfade) handles the one
layer rendered with a non-periodic time-varying filter (blizzard moan).
"""
from __future__ import annotations

import sys
import time
import zlib
from pathlib import Path

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 22050
NYQ = SR / 2.0
TWO_PI = 2.0 * np.pi
SEED = 1867  # fixed global seed (Confederation year)
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "audio"

ONESHOT_PEAK_DB = -3.0   # one-shots are peak-normalized to this
LOOP_PEAK_CAP_DB = -1.5  # loops are RMS-normalized but never peak above this

_freqz_sos = getattr(signal, "freqz_sos", None) or signal.sosfreqz


# =============================================================================
# Helper library: basics
# =============================================================================

def ns(sec: float) -> int:
    """Duration in seconds -> sample count (>= 1)."""
    return max(1, int(round(sec * SR)))


def at(sec: float) -> int:
    """Time position in seconds -> sample index (may be negative; used with place())."""
    return int(round(sec * SR))


def tvec(n: int) -> np.ndarray:
    return np.arange(n) / SR


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def dbfs(v: float) -> float:
    return 20.0 * np.log10(max(float(v), 1e-12))


def peak(x) -> float:
    return float(np.max(np.abs(x))) if len(x) else 0.0


def rms(x) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.0


def nrm(x, to: float = 1.0):
    """Scale to a given peak."""
    p = peak(x)
    return x * (to / p) if p > 0 else x


def nrms(x, to: float = 1.0):
    """Scale to a given RMS."""
    r = rms(x)
    return x * (to / r) if r > 0 else x


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def qf(f: float, n: int) -> float:
    """Quantize a frequency so an integer number of cycles fits into n samples (periodic loops)."""
    T = n / SR
    return max(1, round(f * T)) / T


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng([SEED, zlib.crc32(name.encode())])


# =============================================================================
# Envelopes
# =============================================================================

def env_pts(n: int, pts) -> np.ndarray:
    """Piecewise-linear envelope through (time_s, value) points."""
    tt = np.array([p[0] for p in pts], float)
    vv = np.array([p[1] for p in pts], float)
    return np.interp(tvec(n), tt, vv)


def kf(n: int, pts) -> np.ndarray:
    """Keyframe track with scalar or tuple values -> array (dims, n). Points are sorted, ties nudged."""
    pts = sorted(pts, key=lambda p: p[0])
    tt, vv, last = [], [], -1.0
    for t, v in pts:
        t = max(float(t), last + 1e-5)
        tt.append(t)
        vv.append(np.atleast_1d(np.asarray(v, float)))
        last = t
    vv = np.array(vv)
    tg = tvec(n)
    return np.stack([np.interp(tg, tt, vv[:, j]) for j in range(vv.shape[1])])


def hit(n: int, t0: float, rise: float, tau: float) -> np.ndarray:
    """Impact envelope: zero before t0, exponential rise (time-constant rise), exponential decay tau.
    Normalized to peak 1."""
    t = tvec(n) - t0
    e = np.zeros(n)
    m = t >= 0
    tt = t[m]
    e[m] = (1.0 - np.exp(-tt / max(rise, 1e-5))) * np.exp(-tt / tau)
    pk = e.max() if len(e) else 0.0
    return e / pk if pk > 0 else e


def note_env(n: int, attack: float, hold: float, release: float) -> np.ndarray:
    """Raised-cosine attack, flat hold, raised-cosine release (smooth, click free)."""
    t = tvec(n)
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    r = np.clip((t - attack - hold) / max(release, 1e-4), 0.0, 1.0)
    return np.sin(0.5 * np.pi * a) ** 2 * np.cos(0.5 * np.pi * r) ** 2


def fade(x, fin: float = 0.001, fout: float = 0.01) -> np.ndarray:
    """Raised-cosine fade in / fade out (last sample becomes exactly 0)."""
    x = np.array(x, float, copy=True)
    a = min(ns(fin), len(x) // 2) if fin > 0 else 0
    b = min(ns(fout), len(x) // 2) if fout > 0 else 0
    if a > 1:
        x[:a] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(a) / a)
    if b > 1:
        x[-b:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(1, b + 1) / b)
    return x


def smooth(e, ms: float, circ: bool = False) -> np.ndarray:
    """Smooth an envelope with a (positive) Hann kernel of `ms` milliseconds."""
    L = max(3, ns(ms / 1000.0)) | 1
    k = np.hanning(L + 2)[1:-1]
    k /= k.sum()
    if circ:
        return np.roll(conv(np.asarray(e, float), k, circ=True), -(L // 2))
    return np.convolve(e, k, mode="same")


# =============================================================================
# Noise and modulation sources
# =============================================================================

def white(n: int, rng) -> np.ndarray:
    return rng.standard_normal(n)


def colored(n: int, rng, power: float, fmin: float = 20.0) -> np.ndarray:
    """1/f^power noise shaped in the frequency domain (periodic over n), std 1."""
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.maximum(np.fft.rfftfreq(n, 1.0 / SR), fmin)
    X *= f ** (-power / 2.0)
    X[0] = 0.0
    y = np.fft.irfft(X, n)
    return y / (y.std() + 1e-12)


def pink(n, rng, fmin=20.0):
    return colored(n, rng, 1.0, fmin)


def brown(n, rng, fmin=20.0):
    return colored(n, rng, 2.0, fmin)


def pmod(n: int, rng, fmax: float, fmin: float = 0.0, tilt: float = 0.0) -> np.ndarray:
    """Smooth random modulation curve (mean 0, std 1) containing only frequency bins in
    [fmin, fmax] that complete an integer number of cycles over n samples -> periodic."""
    f = np.fft.rfftfreq(n, 1.0 / SR)
    sel = (f > 0) & (f >= fmin) & (f <= fmax)
    if not sel.any():
        sel[1] = True
    k = int(sel.sum())
    X = np.zeros(len(f), complex)
    X[sel] = (rng.standard_normal(k) + 1j * rng.standard_normal(k)) * f[sel] ** (-tilt)
    y = np.fft.irfft(X, n)
    return y / (y.std() + 1e-12)


def nb_noise(n: int, rng, fc, bw: float) -> np.ndarray:
    """Narrow-band noise (whistles, howls) centred on a (time varying) frequency fc with
    bandwidth bw: complex baseband noise times a complex carrier. The carrier frequency is
    nudged so its total phase is a whole number of cycles -> periodic over n."""
    fc = np.array(np.broadcast_to(np.asarray(fc, float), (n,)))
    f = np.fft.fftfreq(n, 1.0 / SR)
    sel = np.abs(f) <= bw / 2.0
    k = int(sel.sum())
    X = np.zeros(n, complex)
    X[sel] = rng.standard_normal(k) + 1j * rng.standard_normal(k)
    base = np.fft.ifft(X)
    cyc = fc.sum() / SR
    fc = fc + (round(cyc) - cyc) * SR / n
    y = np.real(base * np.exp(1j * TWO_PI * np.cumsum(fc) / SR))
    return y / (y.std() + 1e-12)


# =============================================================================
# Filters (circ=True -> exact periodic/circular filtering for loops)
# =============================================================================

def _sos(btype: str, fc, order: int):
    if btype == "bandpass":
        lo, hi = fc
        lo = max(float(lo), 10.0)
        hi = min(float(hi), NYQ * 0.95)
        hi = max(hi, lo * 1.1)
        return signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.butter(order, min(max(float(fc), 5.0), NYQ * 0.95), btype=btype, fs=SR, output="sos")


def apply_sos(x, sos, circ: bool = False) -> np.ndarray:
    if circ:
        n = len(x)
        _, h = _freqz_sos(sos, worN=np.fft.rfftfreq(n, 1.0 / SR), fs=SR)
        return np.fft.irfft(np.fft.rfft(x) * h, n)
    return signal.sosfilt(sos, x)


def lp(x, fc, order=2, circ=False):
    return apply_sos(x, _sos("lowpass", fc, order), circ)


def hp(x, fc, order=2, circ=False):
    return apply_sos(x, _sos("highpass", fc, order), circ)


def bp(x, lo, hi, order=2, circ=False):
    return apply_sos(x, _sos("bandpass", (lo, hi), order), circ)


def peakf(x, f0, q, circ=False):
    """Resonant peak (constant-skirt bandpass) filter."""
    b, a = signal.iirpeak(min(float(f0), NYQ * 0.95), q, fs=SR)
    return apply_sos(x, signal.tf2sos(b, a), circ)


def soft_clip(x, drive_db: float = 6.0) -> np.ndarray:
    """Gentle tanh saturation that tames the few biggest peaks of grainy textures. Memoryless,
    so loops stay periodic; the output keeps the input's peak level."""
    p = peak(x)
    if p == 0:
        return x
    d = undb(drive_db)
    return np.tanh(x / p * d) / np.tanh(d) * p


def morph_lp(x, w, fcs, circ=False):
    """Lowpass whose cutoff glides between the values in `fcs` as w goes 0..1 (blend of fixed
    filters, vectorized and periodic)."""
    pos = np.clip(w, 0.0, 1.0) * (len(fcs) - 1)
    y = np.zeros(len(x))
    for i, fc in enumerate(fcs):
        wt = np.clip(1.0 - np.abs(pos - i), 0.0, 1.0)
        if wt.any():
            y += lp(x, fc, 2, circ) * wt
    return y


def svf(x, fc, q, mode: str = "bp") -> np.ndarray:
    """Time-varying state-variable filter (TPT/Zavalishin form, stable under modulation).
    mode 'bp' (unity peak gain) or 'lp'. fc and q may be arrays."""
    n = len(x)
    fc = np.clip(np.broadcast_to(np.asarray(fc, float), (n,)), 10.0, SR * 0.45)
    q = np.broadcast_to(np.asarray(q, float), (n,))
    g = np.tan(np.pi * fc / SR)
    k = 1.0 / q
    a1 = 1.0 / (1.0 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    xs, A1, A2, A3 = list(map(float, x)), a1.tolist(), a2.tolist(), a3.tolist()
    out = [0.0] * n
    ic1 = ic2 = 0.0
    want_lp = mode == "lp"
    for i in range(n):
        v3 = xs[i] - ic2
        v1 = A1[i] * ic1 + A2[i] * v3
        v2 = ic2 + A2[i] * ic1 + A3[i] * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        out[i] = v2 if want_lp else v1
    y = np.array(out)
    return y if want_lp else y * k


def reson_tv(x, F, BW) -> np.ndarray:
    """Klatt-style 2-pole resonator with per-sample frequency/bandwidth (unity gain at DC).
    Used in cascade for the formant voice."""
    C = -np.exp(-TWO_PI * BW / SR)
    B = 2.0 * np.exp(-np.pi * BW / SR) * np.cos(TWO_PI * F / SR)
    A = 1.0 - B - C
    xs, As, Bs, Cs = list(map(float, x)), A.tolist(), B.tolist(), C.tolist()
    y = [0.0] * len(xs)
    y1 = y2 = 0.0
    for i in range(len(xs)):
        v = As[i] * xs[i] + Bs[i] * y1 + Cs[i] * y2
        y[i] = v
        y2 = y1
        y1 = v
    return np.array(y)


# =============================================================================
# Events, impacts, convolution, reverb
# =============================================================================

def impulses(n: int, pos, amps, circ: bool = False) -> np.ndarray:
    """Impulse train with amplitude `amps` at sample positions `pos` (wrapped when circ)."""
    x = np.zeros(n)
    idx = np.round(np.asarray(pos, float)).astype(int)
    a = np.broadcast_to(np.asarray(amps, float), idx.shape)
    if circ:
        idx = idx % n
    else:
        keep = (idx >= 0) & (idx < n)
        idx, a = idx[keep], a[keep]
    np.add.at(x, idx, a)
    return x


def conv(x, k, circ: bool = False) -> np.ndarray:
    """Convolution truncated to len(x); circ=True -> circular convolution (loops)."""
    n = len(x)
    k = np.asarray(k, float)
    if circ:
        if len(k) > n:
            k = np.bincount(np.arange(len(k)) % n, weights=k, minlength=n)
        return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(k, n), n)
    return signal.fftconvolve(x, k)[:n]


def place(buf, seg, start, circ: bool = False):
    """Add `seg` into `buf` at sample `start` (wrapping around when circ)."""
    start = int(round(start))
    n = len(buf)
    seg = np.asarray(seg, float)
    if circ:
        i, s = 0, start % n
        while i < len(seg):
            take = min(n - s, len(seg) - i)
            buf[s:s + take] += seg[i:i + take]
            i += take
            s = 0
    else:
        a, b = max(0, start), min(n, start + len(seg))
        if b > a:
            buf[a:b] += seg[a - start:b - start]
    return buf


def modal(n: int, freqs, taus, amps, t0: float = 0.0) -> np.ndarray:
    """Sum of exponentially decaying sines starting at t0 (modal impact synthesis)."""
    t = tvec(n) - t0
    y = np.zeros(n)
    m = t >= 0
    tt = t[m]
    for f, tau, a in zip(freqs, taus, amps):
        if f < NYQ * 0.95:
            y[m] += a * np.exp(-tt / tau) * np.sin(TWO_PI * f * tt)
    return y


def taper(k, frac: float = 0.15) -> np.ndarray:
    """Fade out the last `frac` of a kernel so truncation never clicks."""
    k = np.array(k, float, copy=True)
    m = max(2, int(len(k) * frac))
    k[-m:] *= np.cos(0.5 * np.pi * np.arange(1, m + 1) / m) ** 2
    return k


def modal_k(freqs, taus, amps, dur=None) -> np.ndarray:
    """Modal impact as a stand-alone kernel."""
    return taper(modal(ns(dur if dur else 6.0 * max(taus)), freqs, taus, amps))


def make_ir(rng, rt60: float, length: float, predelay: float = 0.02,
            bright: float = 5000.0, dark: float = 1200.0) -> np.ndarray:
    """Reverb impulse response: exponentially decaying noise whose spectrum darkens over time.
    Normalized to unit energy (wet RMS ~ dry RMS for noise-like input)."""
    n = ns(length)
    t = tvec(n)
    a = lp(white(n, rng), bright, 2)
    b = lp(white(n, rng), dark, 2) * np.sqrt(bright / dark) * 0.6
    w = np.clip(t / (0.6 * rt60), 0.0, 1.0)
    ir = (a * (1.0 - w) + b * w) * np.exp(-6.9078 * t / rt60) * (1.0 - np.exp(-t / 0.008))
    ir = taper(np.concatenate([np.zeros(at(predelay)), ir]), 0.1)
    return ir / np.sqrt(np.sum(ir ** 2))


def make_loop_seamless(x, n: int, xfade: int) -> np.ndarray:
    """x was rendered past the loop length n (len(x) >= n + xfade). Equal-power crossfade the
    material after the loop point into the head, so x[n-1] -> x[0] continues naturally."""
    x = np.asarray(x, float)
    m = min(xfade, len(x) - n, n)
    y = x[:n].copy()
    if m > 0:
        th = np.linspace(0.0, 0.5 * np.pi, m)
        y[:m] = x[:m] * np.sin(th) + x[n:n + m] * np.cos(th)
    return y


# =============================================================================
# Snow: granular crunch (the heart of the game's audio)
# =============================================================================

# (low Hz, high Hz, relative grain count)
SNOW_BANDS = ((450, 1300, 0.9), (1100, 2600, 1.0), (2300, 4800, 0.75), (4200, 8000, 0.3))


def crunch(n: int, rng, dens, grains: int, bands=SNOW_BANDS, cracks: int = 0,
           crack_hz=(900.0, 4500.0), circ: bool = False, follow: float = 0.7,
           clump: float = 0.8, grain_cap: float = 4.0, crack_gain: float = 0.32) -> np.ndarray:
    """Granular compressed-snow crunch.

    dens    -- grain density over time (any non-negative curve, length n)
    grains  -- total number of tiny grains (ice-bond micro fractures)
    bands   -- each grain is band-limited to one band (count weight per band)
    cracks  -- number of larger, ringing ice cracks that give the crunch definition
    clump   -- random multiplicative density bursts (compaction events), 0 = smooth
    follow  -- how strongly grain amplitude follows the local density
    grain_cap / crack_gain -- bound on grain size, level of the cracks (lower both for dense,
               continuous textures such as rolling tires)
    """
    dens = np.maximum(np.asarray(dens, float), 0.0)
    if clump > 0:
        dens = dens * np.exp(clump * np.clip(pmod(n, rng, 160.0, 20.0), -2.5, 2.5))
    dens = dens + 1e-9 * (dens.max() + 1e-12)
    cdf = np.cumsum(dens)
    cdf /= cdf[-1]
    dmax = dens.max()
    out = np.zeros(n)
    wsum = sum(b[2] for b in bands)
    L = ns(0.0025)
    kt = np.arange(L)
    for lo, hi, w in bands:
        k = max(1, int(round(grains * w / wsum)))
        pos = np.clip(np.searchsorted(cdf, rng.random(k)), 0, n - 1)
        # heavy-ish tailed grain sizes (a few bigger fractures), bounded so no single grain dominates
        a = np.minimum(rng.pareto(3.0, k) + 0.35, grain_cap) * rng.choice((-1.0, 1.0), k) * (dens[pos] / dmax) ** follow
        crisp = rng.random(k) < 0.5
        kern = rng.standard_normal(L) * np.exp(-kt / (L * rng.uniform(0.12, 0.3)))
        kern /= np.sqrt(np.sum(kern ** 2))
        g = impulses(n, pos[crisp], a[crisp], circ) + conv(impulses(n, pos[~crisp], a[~crisp], circ), kern, circ)
        # equal energy per grain whatever the band width
        out += bp(g, lo, hi, 2, circ) / np.sqrt((hi - lo) / 1000.0)
    lo_c, hi_c = np.log(crack_hz[0]), np.log(crack_hz[1])
    for _ in range(cracks):
        p = int(np.clip(np.searchsorted(cdf, rng.random()), 0, n - 1))
        f = np.exp(rng.uniform(lo_c, hi_c))
        tau = rng.uniform(0.0006, 0.0028)
        Lc = ns(tau * 7.0)
        tc = tvec(Lc)
        seg = np.exp(-tc / tau) * (np.sin(TWO_PI * f * tc) + 0.45 * np.sin(TWO_PI * f * rng.uniform(1.6, 2.7) * tc))
        amp = min(rng.pareto(3.0) + 0.6, 2.5) * (dens[p] / dmax) ** (follow * 0.5) * crack_gain * rng.choice((-1.0, 1.0))
        place(out, taper(seg) * amp, p, circ)
    return out


# =============================================================================
# Mechanical helpers: friction, engines, clicks
# =============================================================================

def stick_slip(n, rng, rate, t_start, t_end, kernel, jitter=0.15, amp_jit=0.3, circ=False, amp_env=None):
    """Friction (stick-slip) excitation: an impulse train at instantaneous rate `rate` (Hz)
    between t_start and t_end, with timing/amplitude jitter, convolved with a resonant kernel.
    Produces creaks (slow) and scrapes (fast)."""
    rate = np.broadcast_to(np.asarray(rate, float), (n,))
    ph = np.cumsum(rate) / SR
    k = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    k = k[(k >= at(t_start)) & (k < min(n, at(t_end)))]
    if len(k) == 0:
        return np.zeros(n)
    pos = k + jitter * (SR / rate[k]) * rng.standard_normal(len(k))
    amps = np.maximum(1.0 + amp_jit * rng.standard_normal(len(k)), 0.05)
    if amp_env is not None:
        amps = amps * amp_env[k]
    return conv(impulses(n, pos, amps, circ), kernel, circ)


def plastic_kernel(rng, scale: float = 1.0, damp: float = 1.0) -> np.ndarray:
    """Resonances of a plastic shovel blade (damp > 1 -> shorter ring, less tonal)."""
    return modal_k([rng.uniform(600, 700) * scale, rng.uniform(1300, 1450) * scale, rng.uniform(2200, 2450) * scale,
                    rng.uniform(3300, 3700) * scale, 5200 * scale],
                   np.array([0.03, 0.02, 0.012, 0.008, 0.004]) / damp, [0.6, 0.8, 0.6, 0.4, 0.2], dur=0.08 / damp)


def exhaust_kernel(rng, dur, res, burst=(300, 1500), burst_tau=0.006, burst_amp=0.5,
                   pulse_tau=0.004, pulse_amp=1.0) -> np.ndarray:
    """One combustion/exhaust pulse: smooth pressure pulse + pipe/muffler resonances +
    a burst of combustion roughness noise."""
    L = ns(dur)
    t = tvec(L)
    k = pulse_amp * (t / pulse_tau) * np.exp(1.0 - t / pulse_tau)
    for f, tau, a in res:
        k += a * np.exp(-t / tau) * np.sin(TWO_PI * f * t)
    if burst_amp > 0:
        k += burst_amp * nrm(bp(white(L, rng), *burst)) * np.exp(-t / burst_tau)
    return taper(k, 0.25)


def firing_times(n, rng, fire_hz, pattern=(1.0,), timing=(0.0,), amp_jit=0.08, time_jit=0.01):
    """Engine firing events for a loop of n samples: a whole number of engine cycles
    (len(pattern) firings each) so the loop is periodic. pattern/timing give per-cylinder
    amplitude and timing offsets (fraction of the firing period) -> burble/lope."""
    L = len(pattern)
    cycles = max(1, int(round(fire_hz * n / SR / L)))
    count = cycles * L
    period = n / count
    i = np.arange(count)
    amps = np.asarray(pattern, float)[i % L] * (1.0 + amp_jit * rng.standard_normal(count))
    offs = np.asarray(timing, float)[i % len(timing)] + time_jit * rng.standard_normal(count)
    return (i + offs) * period, np.maximum(amps, 0.05), period


def engine_core(n, rng, pos, amps, kernel, hp_hz, drive, lp_hz):
    """Pulse train -> exhaust kernel -> DC removal -> soft saturation -> lowpass (all circular)."""
    ex = conv(impulses(n, pos, amps, True), kernel, True)
    ex = hp(ex, hp_hz, 2, True)
    ex = np.tanh(drive * nrm(ex))
    return lp(ex, lp_hz, 2, True)


def click(n, rng, t0, freqs=(2400.0, 3800.0, 5100.0), taus=(0.006, 0.004, 0.003), amps=(1.0, 0.6, 0.35), noise=0.5):
    """Small metallic/plastic click."""
    return modal(n, freqs, taus, amps, t0) + noise * hp(white(n, rng), 2000) * hit(n, t0, 0.0002, 0.0015)


# =============================================================================
# Music helpers
# =============================================================================

def saw_table(f0: float, fc: float, order: int = 2, size: int = 2048) -> np.ndarray:
    """Band-limited single-cycle sawtooth with a Butterworth-like lowpass at fc baked in."""
    nh = int(min(0.45 * SR / f0, size // 2 - 1))
    k = np.arange(1, nh + 1)
    amp = (1.0 / k) / np.sqrt(1.0 + (k * f0 / fc) ** (2 * order))
    spec = np.zeros(size // 2 + 1, complex)
    spec[k] = -1j * amp
    tab = np.fft.irfft(spec, size)
    return tab / np.abs(tab).max()


def tri_table(f0: float, size: int = 2048) -> np.ndarray:
    nh = int(min(0.45 * SR / f0, size // 2 - 1))
    k = np.arange(1, nh + 1, 2)
    spec = np.zeros(size // 2 + 1, complex)
    spec[k] = -1j * ((-1.0) ** ((k - 1) // 2)) / k ** 2
    tab = np.fft.irfft(spec, size)
    return tab / np.abs(tab).max()


def osc(table, freq, n: int, phase: float = 0.0) -> np.ndarray:
    """Wavetable oscillator (linear interpolation); freq scalar or per-sample array."""
    size = len(table)
    if np.isscalar(freq):
        ph = phase + np.arange(n) * (freq / SR)
    else:
        ph = phase + np.cumsum(freq) / SR
    ph = (ph % 1.0) * size
    i0 = ph.astype(np.int64)
    fr = ph - i0
    return table[i0 % size] * (1.0 - fr) + table[(i0 + 1) % size] * fr


def pad_note(rng, m, dur, attack=1.5, release=2.5, fc=1200.0, detune=8.0, voices=3, tri=0.4) -> np.ndarray:
    """Warm pad voice: detuned band-limited saws through a lowpass + a triangle layer."""
    f = midi_hz(m)
    L = ns(dur + release)
    tab = saw_table(f, fc)
    y = np.zeros(L)
    for v in range(voices):
        c = (v - (voices - 1) / 2.0) * (2.0 * detune / max(voices - 1, 1)) + rng.normal(0, 1.5)
        y += osc(tab, f * 2.0 ** (c / 1200.0), L, rng.random())
    y /= voices
    if tri > 0:
        y += tri * osc(tri_table(f), f, L, rng.random())
    return y * note_env(L, attack, max(dur - attack, 0.0), release)


BELL_PARTIALS = ((1.0, 1.0, 1.0), (2.0, 0.30, 0.55), (3.0, 0.07, 0.3), (4.2, 0.12, 0.22), (5.4, 0.05, 0.12), (6.8, 0.025, 0.07))
SOFT_BELL = ((1.0, 1.0, 1.0), (2.0, 0.18, 0.5), (3.0, 0.05, 0.3), (4.2, 0.04, 0.2))


def bell_note(rng, f, vel=0.7, length=2.6, decay=1.6, partials=BELL_PARTIALS) -> np.ndarray:
    """Celesta / music-box style note: sine + soft bell partials with faster decays above."""
    L = ns(length)
    t = tvec(L)
    y = np.zeros(L)
    for r, a, d in partials:
        fr = f * r * (1.0 + rng.normal(0, 0.0007))
        if fr < NYQ * 0.9:
            y += a * np.exp(-t / (decay * d)) * np.sin(TWO_PI * fr * t)
    y *= 1.0 - np.exp(-t / 0.0015)
    y += 0.03 * lp(white(L, rng), 3000) * np.exp(-t / 0.003)
    return fade(y, 0, min(0.08, length * 0.2)) * vel


def piano_note(rng, f, vel=0.6, length=4.5) -> np.ndarray:
    """Soft piano-like tone: slightly inharmonic partials, two detuned strings, two-stage decay."""
    L = ns(length)
    t = tvec(L)
    y = np.zeros(L)
    Bc = 0.0004
    for k in range(1, int(min(24, 0.42 * SR / f)) + 1):
        fk = k * f * np.sqrt(1.0 + Bc * k * k)
        if fk >= NYQ * 0.9:
            break
        a = (1.0 / k ** 1.1) * (0.35 + 0.65 * abs(np.sin(np.pi * k * 0.13))) * np.exp(-(k - 1) * (1.0 - vel) * 0.3)
        env = 0.55 * np.exp(-t / (0.35 / (1 + 0.2 * k))) + 0.45 * np.exp(-t / (3.2 / (1 + 0.25 * k)))
        for det in (-0.35, 0.35):
            y += 0.5 * a * env * np.sin(TWO_PI * fk * 2.0 ** (det / 1200.0) * t + rng.uniform(0, TWO_PI))
    y *= 1.0 - np.exp(-t / 0.002)
    y += 0.05 * vel * lp(white(L, rng), 1200) * np.exp(-t / 0.006)
    return fade(y, 0, 0.3) * vel


def bass_note(rng, f, dur, release=1.2) -> np.ndarray:
    L = ns(dur + release)
    t = tvec(L)
    y = np.sin(TWO_PI * f * t) + 0.25 * np.sin(TWO_PI * 2 * f * t) + 0.08 * np.sin(TWO_PI * 3 * f * t)
    return y * note_env(L, 0.25, max(dur - 0.25, 0.0), release) * (0.6 + 0.4 * np.exp(-t / 4.0))


def air_chord(rng, voicing, dur, attack, release) -> np.ndarray:
    """Breathy 'air' pad: noise with narrow spectral peaks at the chord's notes and harmonics."""
    L = ns(dur + release)
    X = np.fft.rfft(rng.standard_normal(L))
    f = np.fft.rfftfreq(L, 1.0 / SR)
    H = np.zeros(len(f))
    for m in voicing:
        for h, g in ((1, 1.0), (2, 0.5), (3, 0.22)):
            fc = midi_hz(m) * h
            bw = fc * 0.012 + 1.5
            H += g * np.exp(-0.5 * ((f - fc) / bw) ** 2)
    y = np.fft.irfft(X * H, L)
    y /= y.std() + 1e-12
    return y * note_env(L, attack, max(dur - attack, 0.0), release)


def lead_note(rng, f, dur, release=0.25) -> np.ndarray:
    """Soft bright synth lead for the radio jingle."""
    L = ns(dur + release)
    t = tvec(L)
    tab = saw_table(f, 2500, 2)
    y = 0.5 * osc(tab, f * 2 ** (-4 / 1200), L, rng.random()) + 0.5 * osc(tab, f * 2 ** (4 / 1200), L, rng.random())
    y += 0.6 * osc(tri_table(f), f, L)
    y += 0.4 * np.sin(TWO_PI * 2 * f * t) * np.exp(-t / 0.15)
    return y * note_env(L, 0.008, dur, release) * (0.75 + 0.25 * np.exp(-t / 0.2))


# =============================================================================
# Formant voice synthesis
# =============================================================================

VOWELS = {  # adult male formants F1..F4 (Hz)
    "i": (280, 2250, 2900, 3500), "I": (400, 1950, 2600, 3500), "e": (480, 2000, 2600, 3500),
    "E": (580, 1800, 2550, 3500), "ae": (660, 1700, 2400, 3500), "a": (720, 1150, 2450, 3500),
    "o": (520, 900, 2400, 3500), "U": (450, 1050, 2250, 3500), "u": (320, 900, 2300, 3500),
    "@": (520, 1400, 2450, 3500),
}
CONS_F = {
    "l": (360, 1000, 2650, 3500), "m": (270, 1050, 2250, 3400), "n": (270, 1500, 2450, 3400),
    "w": (300, 700, 2300, 3400), "b": (250, 850, 2300, 3400), "d": (280, 1700, 2600, 3500),
    "g": (280, 2000, 2400, 3500),
}


def formant_voice(rng, n, f0, F, BW, av, ah, af, tilt=1.0, jitter=0.006, shimmer=0.04,
                  breath=0.06, fric_band=(800, 6000), fric_gain=0.15) -> np.ndarray:
    """Source-filter voice. Glottal source = band-limited harmonic series (cosine phase, spectral
    tilt k^-tilt) following the f0 contour, with jitter/shimmer and pitch-synchronous breath;
    aspiration noise (ah) shares the formant path; both go through a cascade of 4 time-varying
    Klatt resonators (F, BW: arrays (4, n)). Frication/bursts (af) are added in parallel."""
    f0 = f0 * (1.0 + jitter * pmod(n, rng, 30.0, 3.0))
    ph = np.cumsum(f0) / SR
    src = np.zeros(n)
    for k in range(1, int(0.45 * SR / f0.max()) + 1):
        src += k ** (-tilt) * np.cos(TWO_PI * k * ph)
    src /= rms(src)
    src *= 1.0 + shimmer * pmod(n, rng, 40.0, 5.0)
    asp = white(n, rng)
    x = av * (src + breath * 3.0 * asp * (0.5 + 0.5 * np.cos(TWO_PI * ph))) + ah * asp
    y = x
    for j in range(4):
        y = reson_tv(y, F[j], BW[j])
    y = nrm(y)
    return y + fric_gain * nrm(bp(white(n, rng), *fric_band)) * af


# =============================================================================
# SOUNDS: snow & tools
# =============================================================================

def snd_step_snow(rng, v):
    """Soft crunchy footstep in fresh snow: heel + roll-to-toe crunch clusters."""
    n = ns(rng.uniform(0.24, 0.28))
    heel = rng.uniform(0.003, 0.009)
    toe = heel + rng.uniform(0.055, 0.095)
    dens = 0.75 * hit(n, heel, 0.003, rng.uniform(0.018, 0.032)) + \
        hit(n, toe, rng.uniform(0.008, 0.016), rng.uniform(0.035, 0.06))
    tilt = rng.uniform(-0.25, 0.25)
    bands = [(lo, hi, w * (1.0 + tilt * (i - 1.5) / 1.5)) for i, (lo, hi, w) in enumerate(SNOW_BANDS)]
    c = crunch(n, rng, dens, int(rng.integers(380, 560)), bands, cracks=int(rng.integers(12, 24)), crack_hz=(800, 4200))
    c = soft_clip(c, 4.0)  # bring the dense crunch up against its biggest grains
    body = bp(white(n, rng), 160, 850) * smooth(dens, 12)
    thump = lp(white(n, rng), 150, 2) * hit(n, heel, 0.002, 0.03)
    y = nrm(c) + nrm(body, 0.35) + nrm(thump, 0.4)
    return lp(y, 7500, 2)


def snd_step_deep(rng, v):
    """Foot sinking into deep snow: muffled low whumpf + longer, darker crunch + snow sliding in."""
    n = ns(rng.uniform(0.40, 0.45))
    t0 = rng.uniform(0.005, 0.015)
    t = tvec(n)
    whumpf = lp(white(n, rng), rng.uniform(200, 260), 2) * hit(n, t0, 0.018, rng.uniform(0.07, 0.1))
    f = 42.0 + 55.0 * np.exp(-np.maximum(t - t0, 0) / 0.05)
    sub = np.sin(TWO_PI * np.cumsum(f) / SR) * hit(n, t0, 0.012, 0.07)
    dens = hit(n, t0 + 0.015, 0.03, rng.uniform(0.09, 0.13)) + 0.5 * hit(n, t0 + rng.uniform(0.1, 0.15), 0.02, 0.07)
    bands = ((300, 900, 1.0), (700, 1700, 0.9), (1400, 3000, 0.5), (2600, 4500, 0.15))
    c = crunch(n, rng, dens, int(rng.integers(450, 600)), bands, cracks=int(rng.integers(8, 14)), crack_hz=(500, 2400))
    swish = bp(white(n, rng), 450, 2200) * smooth(env_pts(n, [(0, 0), (0.18, 0), (0.27, 1), (0.42, 0), (1, 0)]), 20)
    y = nrm(whumpf) + nrm(sub, 0.45) + nrm(c, 0.85) + nrm(swish, 0.18)
    return lp(y, 4500, 2)


def snd_step_hard(rng, v):
    """Boot on cleared pavement / floor: heel thud, sole slap, a little salt grit."""
    n = ns(0.16)
    h = rng.uniform(0.003, 0.006)
    s = h + rng.uniform(0.025, 0.045)
    heel = modal(n, [rng.uniform(95, 130), rng.uniform(170, 230), rng.uniform(310, 420), rng.uniform(900, 1300)],
                 [0.03, 0.02, 0.012, 0.004], [0.8, 0.6, 0.35, 0.25], t0=h)
    heel += 0.7 * lp(white(n, rng), 1800, 2) * hit(n, h, 0.0004, 0.006)
    sole = bp(white(n, rng), 1200, 5000) * hit(n, s, 0.0003, 0.004) + \
        modal(n, [rng.uniform(1400, 2200), rng.uniform(2800, 3600)], [0.006, 0.003], [0.4, 0.2], t0=s)
    grit = crunch(n, rng, hit(n, h, 0.002, 0.03) + 0.7 * hit(n, s, 0.002, 0.04), int(rng.integers(50, 90)),
                  ((2500, 6000, 1.0), (5000, 9500, 0.6)), cracks=4, crack_hz=(3000, 7000), clump=0.5)
    y = nrm(heel) + nrm(sole, 0.55) + nrm(grit, 0.35)
    return lp(y, 9000, 2)


def snd_hand_dig(rng):
    """Mittens scooping snow: muffled scrape with soft crunch."""
    n = ns(0.36)
    e = smooth(env_pts(n, [(0, 0), (0.03, 0.6), (0.1, 1.0), (0.22, 0.7), (0.33, 0.0), (1, 0)]), 15)
    rough = 0.6 + 0.4 * np.tanh(pmod(n, rng, 90, 15))
    scrape = bp(white(n, rng), 350, 2000) * e * rough
    c = crunch(n, rng, e ** 2 + 0.5 * hit(n, 0.02, 0.01, 0.06), 300,
               ((500, 1400, 1.0), (1100, 2600, 0.7), (2200, 3800, 0.25)), cracks=8, crack_hz=(700, 2500))
    thump = lp(white(n, rng), 220, 2) * hit(n, 0.012, 0.004, 0.03)
    y = nrm(scrape, 0.55) + nrm(c, 0.8) + nrm(thump, 0.3)
    return lp(y, 4000, 2)


def snd_hand_scoop(rng, v):
    """Polish pass: cupped mittens sweeping through powder — a soft, quick 'shhk' with a crunch
    as the snow packs into the hands (three variants)."""
    n = ns(rng.uniform(0.2, 0.26))
    e = smooth(env_pts(n, [(0, 0), (0.015, 0.7), (0.06, 1.0), (0.14, 0.6), (0.2, 0.0), (1, 0)]), 10)
    brush = bp(white(n, rng), 600 + 150 * v, 3200) * e * (0.6 + 0.4 * np.tanh(pmod(n, rng, 80, 10)))
    pack = crunch(n, rng, e ** 1.5, 380, ((500, 1300, 1.0), (1100, 2500, 0.8), (2200, 4200, 0.3)), cracks=6, crack_hz=(600, 2200))
    puff = lp(white(n, rng), 260, 2) * hit(n, 0.02, 0.006, 0.04)
    y = nrm(brush, 0.6) + nrm(pack, 0.85) + nrm(puff, 0.25)
    return lp(y, 4200, 2)


def snd_shovel_fill(rng, v):
    """Polish pass: a shovel blade slicing through the snow as the load fills (three variants)."""
    n = ns(rng.uniform(0.22, 0.28))
    se = smooth(env_pts(n, [(0, 0), (0.006, 1), (0.08, 0.7), (0.12, 0), (1, 0)]), 6)
    ss = stick_slip(n, rng, env_pts(n, [(0, 100 + 10 * v), (0.12, 140)]), 0.004, 0.12, plastic_kernel(rng, 1.0, 2.2), 0.3, 0.4)
    hiss = bp(white(n, rng), 1300, 6000) * (0.55 + 0.45 * np.tanh(1.5 * pmod(n, rng, 160, 30)))
    slice_ = (nrm(ss, 0.55) + nrm(hiss, 0.5)) * se
    dens = hit(n, 0.03, 0.02, 0.07)
    c = crunch(n, rng, dens, 520, SNOW_BANDS, cracks=14, crack_hz=(800, 3800))
    body = bp(white(n, rng), 180, 700) * smooth(dens, 12)
    y = slice_ + nrm(c, 0.9) + nrm(body, 0.25)
    return lp(y, 7500, 2)


def snd_hand_toss(rng):
    """Polish pass: an underhand toss of a double handful — light whoosh, then powder scattering."""
    n = ns(0.32)
    fc = env_pts(n, [(0, 380), (0.08, 1200), (0.18, 900), (0.32, 500)])
    wh = svf(white(n, rng), fc, 1.1)
    e = smooth(env_pts(n, [(0, 0), (0.05, 0.7), (0.09, 1.0), (0.17, 0.5), (0.3, 0.0), (1, 0)]), 18)
    parts = crunch(n, rng, e ** 2, 120, ((2200, 5500, 1.0), (4500, 8000, 0.4)), clump=1.0)
    return nrm(wh, 0.7) * e + nrm(parts, 0.3)


def snd_push_snow(rng):
    """LOOP (polish pass): flat palms shoving snow ahead — a soft, packing shuffle without blade
    scrape: low compression rumble plus a bed of fine crunch."""
    n = ns(2.0)
    C = True
    swell = 1.0 + 0.25 * pmod(n, rng, 4, 0.6)
    rumble = lp(white(n, rng), 260, 2, C) * (0.65 + 0.35 * np.tanh(pmod(n, rng, 7, 1)))
    shuffle = bp(white(n, rng), 500, 2200, 2, C) * (0.5 + 0.5 * np.tanh(1.4 * pmod(n, rng, 25, 4))) * swell
    g = crunch(n, rng, np.exp(0.7 * pmod(n, rng, 9, 0.5)), 2600, SNOW_BANDS[:3], cracks=14, circ=C, grain_cap=2.5,
               crack_gain=0.1)
    return soft_clip(nrms(rumble, 0.6) + nrms(shuffle, 0.4) + nrms(soft_clip(g, 8.0), 0.55), 4.0)


def snd_box_complete(rng):
    """Polish pass: a small, satisfying 'all clear' — a soft rising bell pair (C6 → G6) with a
    sparkle of tiny glints, like sunlight catching freshly bared pavement."""
    N = ns(1.6)
    y = np.zeros(N)
    place(y, bell_note(rng, midi_hz(84), 0.65, length=1.3, decay=0.9), at(0.0))
    place(y, bell_note(rng, midi_hz(91), 0.75, length=1.3, decay=1.0), at(0.11))
    place(y, bell_note(rng, midi_hz(96), 0.35, length=1.1, decay=0.8), at(0.2))
    glints = np.zeros(N)
    for _ in range(9):
        f = rng.uniform(4500, 8500)
        place(glints, modal_k([f, f * 1.51], [0.05, 0.03], [1.0, 0.4]) * rng.uniform(0.1, 0.25), at(rng.uniform(0.12, 0.6)))
    y = nrm(y) + nrm(glints, 0.18)
    y = y + 0.2 * signal.fftconvolve(y, make_ir(rng, 0.9, 1.0, 0.015, 7000, 2500))[:N]
    return fade(y, 0, 0.2)


def snd_shovel_scoop(rng):
    """Plastic blade scrapes along the ground, cuts into the snow, lifts a load."""
    n = ns(0.46)
    ss = stick_slip(n, rng, env_pts(n, [(0, 90), (0.15, 135)]), 0.004, 0.15, plastic_kernel(rng, 1.0, 2.0), 0.3, 0.4)
    hiss = bp(white(n, rng), 1200, 6500) * (0.55 + 0.45 * np.tanh(1.5 * pmod(n, rng, 160, 30)))
    se = smooth(env_pts(n, [(0, 0), (0.008, 1), (0.11, 0.85), (0.16, 0), (1, 0)]), 6)
    scrape = (nrm(ss, 0.7) + nrm(hiss, 0.5)) * se
    dens = hit(n, 0.09, 0.03, 0.09)
    c = crunch(n, rng, dens, 650, SNOW_BANDS, cracks=24, crack_hz=(800, 4000))
    body = bp(white(n, rng), 180, 800) * smooth(dens, 15)
    lift = lp(white(n, rng), 170, 2) * hit(n, 0.30, 0.02, 0.05)
    trickle = crunch(n, rng, hit(n, 0.31, 0.01, 0.06), 90, ((1500, 3500, 1.0), (3000, 7000, 0.6)), cracks=3)
    y = nrm(scrape, 0.65) + nrm(c) + nrm(body, 0.25) + nrm(lift, 0.3) + nrm(trickle, 0.25)
    return lp(y, 8000, 2)


def snd_shovel_scrape(rng):
    """Plastic shovel blade scraping pavement (starts/ends at silence, so it is click-free even
    if the engine loops it)."""
    n = ns(0.30)
    rate = env_pts(n, [(0, 95), (0.3, 120)]) * (1.0 + 0.08 * pmod(n, rng, 20, 3))
    ss = stick_slip(n, rng, rate, 0.003, 0.29, plastic_kernel(rng, 1.05, 2.5), 0.3, 0.4)
    hiss = bp(white(n, rng), 1500, 7000) * (0.55 + 0.45 * np.tanh(1.5 * pmod(n, rng, 160, 30)))
    grit = crunch(n, rng, np.ones(n), 120, ((2500, 6000, 1.0), (5000, 9500, 0.5)), cracks=5, crack_hz=(2500, 6000), clump=1.0)
    e = smooth(env_pts(n, [(0, 0), (0.012, 1), (0.2, 0.8), (0.28, 0), (1, 0)]), 6)
    y = (nrm(ss, 0.7) + nrm(hiss, 0.55) + nrm(grit, 0.3)) * e
    return lp(y, 8500, 2)


def snd_shovel_throw(rng):
    """Whoosh of a load of snow leaving the shovel (swept band-pass noise + flying particles)."""
    n = ns(0.36)
    fc = env_pts(n, [(0, 450), (0.10, 1700), (0.20, 1300), (0.36, 700)])
    wh = svf(white(n, rng), fc, 1.3)
    air = svf(white(n, rng), fc * 0.5, 0.7, "lp")
    e = smooth(env_pts(n, [(0, 0), (0.06, 0.6), (0.11, 1.0), (0.20, 0.55), (0.34, 0.0), (1, 0)]), 20)
    parts = crunch(n, rng, e ** 2, 170, ((2500, 6000, 1.0), (5000, 9000, 0.4)), clump=1.0)
    clump = lp(white(n, rng), 300, 2) * hit(n, 0.015, 0.008, 0.04)
    return (nrm(wh, 0.8) + nrm(air, 0.5)) * e + nrm(parts, 0.25) + nrm(clump, 0.2)


def snd_snow_land(rng, v):
    """Thrown clump landing: soft thud, impact crunch, scattering bits and a little puff."""
    n = ns(rng.uniform(0.40, 0.44))
    t0 = 0.004
    t = tvec(n)
    thud = lp(white(n, rng), rng.uniform(160, 230), 2) * hit(n, t0, 0.003, rng.uniform(0.035, 0.055))
    f = 48.0 + 40.0 * np.exp(-np.maximum(t - t0, 0) / 0.03)
    body = np.sin(TWO_PI * np.cumsum(f) / SR) * hit(n, t0, 0.002, 0.04)
    imp = crunch(n, rng, hit(n, t0, 0.002, rng.uniform(0.025, 0.04)), int(rng.integers(260, 360)),
                 ((400, 1100, 1.0), (900, 2400, 0.9), (2000, 4500, 0.5), (4000, 7000, 0.15)),
                 cracks=int(rng.integers(8, 14)), crack_hz=(700, 3500))
    scatter = crunch(n, rng, hit(n, t0 + 0.03, 0.03, rng.uniform(0.1, 0.16)), int(rng.integers(180, 260)),
                     ((1500, 3500, 0.8), (3000, 7000, 0.6)), cracks=5, crack_hz=(1500, 5000), clump=1.2)
    clumps = np.zeros(n)
    for _ in range(int(rng.integers(3, 7))):
        clumps += nrm(lp(white(n, rng), 400, 2) * hit(n, rng.uniform(0.05, 0.3), 0.002, 0.015), rng.uniform(0.08, 0.2))
    puff = bp(white(n, rng), 300, 1400) * hit(n, t0, 0.004, 0.06)
    y = nrm(thud) + nrm(body, 0.45) + nrm(imp, 0.8) + nrm(scatter, 0.5) + nrm(puff, 0.3) + clumps
    return lp(y, 6500, 2)


def snd_snow_land_big(rng):
    """A big load landing (sleigh dump / huge pile): heavy sub whumpf, several clumps, sliding hiss."""
    n = ns(0.82)
    t = tvec(n)
    t0 = 0.006
    whumpf = lp(white(n, rng), 130, 4) * hit(n, t0, 0.01, 0.13)
    f = 32.0 + 30.0 * np.exp(-np.maximum(t - t0, 0) / 0.06)
    sub = np.sin(TWO_PI * np.cumsum(f) / SR) * hit(n, t0, 0.006, 0.15)
    mid = bp(white(n, rng), 150, 600) * hit(n, t0, 0.005, 0.09)
    times = [t0] + list(t0 + np.sort(rng.uniform(0.025, 0.16, 4)))
    dens = 0.5 * hit(n, 0.05, 0.05, 0.25)
    clumps = np.zeros(n)
    for i, tc in enumerate(times):
        a = 1.0 if i == 0 else rng.uniform(0.3, 0.6)
        dens = dens + a * hit(n, tc, 0.003, 0.05)
        clumps += nrm(lp(white(n, rng), 220, 2) * hit(n, tc, 0.003, 0.04), a)
    c = crunch(n, rng, dens, 950, ((300, 900, 1.0), (700, 1900, 1.0), (1600, 3800, 0.7), (3500, 7000, 0.25)),
               cracks=30, crack_hz=(500, 3500))
    slide = bp(white(n, rng), 500, 3500) * hit(n, 0.04, 0.05, 0.25) * (0.6 + 0.4 * np.tanh(pmod(n, rng, 40, 5)))
    y = nrm(whumpf) + nrm(sub, 0.6) + nrm(mid, 0.4) + nrm(clumps, 0.5) + nrm(c, 0.65) + nrm(slide, 0.22)
    return lp(y, 6000, 2)


# ---- tool loops ---------------------------------------------------------------

def snd_push_scrape(rng):
    """LOOP: pusher blade on pavement: scraping hiss + blade chatter + rumble of snow rolling ahead."""
    n = ns(2.0)
    C = True
    rough = 0.55 + 0.45 * np.tanh(1.3 * pmod(n, rng, 140, 20))
    swell = 1.0 + 0.18 * pmod(n, rng, 3, 0.5)
    hiss = bp(white(n, rng), 900, 5500, 2, C) * rough * swell
    count = 170
    pos = (np.arange(count) + 0.25 * rng.standard_normal(count)) * n / count
    chatter = conv(impulses(n, pos, 0.6 + 0.4 * rng.random(count), C), plastic_kernel(rng, 0.85, 2.0), C)
    roll = lp(white(n, rng), 220, 2, C) * (0.7 + 0.3 * np.tanh(pmod(n, rng, 6, 1))) + \
        0.5 * nrms(bp(white(n, rng), 200, 700, 2, C)) * (0.6 + 0.4 * np.tanh(pmod(n, rng, 10, 2)))
    g = crunch(n, rng, np.exp(0.8 * pmod(n, rng, 8, 0.5)), 4000, SNOW_BANDS[:3], cracks=30, circ=C, grain_cap=2.5,
               crack_gain=0.12)
    return soft_clip(nrms(hiss, 0.55) + nrms(chatter, 0.25) + nrms(roll, 0.6) + nrms(soft_clip(g, 8.0), 0.45), 4.0)


def snd_plow_scrape(rng):
    """LOOP: steel plow edge grinding the road + heavy snow rolling off the moldboard."""
    n = ns(2.5)
    C = True
    grit = 0.5 + 0.5 * np.tanh(1.5 * pmod(n, rng, 220, 30))
    exc = white(n, rng) * grit
    metal = np.zeros(n)
    for f, q, g in ((380, 22, 0.8), (610, 26, 1.0), (1130, 30, 0.8), (1720, 34, 0.6), (2480, 36, 0.45), (3350, 40, 0.3)):
        metal += g * peakf(exc, f * rng.uniform(0.97, 1.03), q, C)
    grind = bp(white(n, rng), 600, 4000, 2, C) * grit
    rumble = lp(white(n, rng), 120, 2, C) * (0.75 + 0.25 * np.tanh(pmod(n, rng, 4, 0.4)))
    roll = bp(white(n, rng), 150, 600, 2, C) * (0.6 + 0.4 * np.tanh(pmod(n, rng, 5, 0.8)))
    g = crunch(n, rng, np.exp(0.7 * pmod(n, rng, 6, 0.4)), 4000, ((300, 900, 1.0), (700, 1900, 0.9), (1600, 3800, 0.5)),
               cracks=20, crack_hz=(500, 2500), circ=C, grain_cap=2.5, crack_gain=0.15)
    hits = np.zeros(n)
    for _ in range(12):  # grit / pebbles pinging off the blade
        seg = modal_k([rng.uniform(1800, 2600), rng.uniform(3200, 4200), rng.uniform(5000, 6000)], [0.03, 0.02, 0.012], [1.0, 0.6, 0.3])
        place(hits, seg * rng.uniform(0.3, 1.0), rng.integers(0, n), C)
    return soft_clip(nrms(metal, 0.5) + nrms(grind, 0.4) + nrms(rumble, 0.8) + nrms(roll, 0.55) + nrms(g, 0.35) +
                     nrms(hits, 0.12), 3.0)


def snd_electric_motor(rng):
    """LOOP: small electric snow shovel: DC motor whine (~215 Hz + harmonics), brush noise,
    paddle/auger chatter and snow grains."""
    n = ns(1.5)
    C = True
    t = tvec(n)
    f0, fm = qf(215.0, n), qf(3.3, n)
    ph = TWO_PI * f0 * t + (f0 * 0.004 / fm) * np.sin(TWO_PI * fm * t)
    amps = [1.0, 0.55, 0.42, 0.2, 0.25, 0.4, 0.1, 0.06, 0.05, 0.04, 0.03, 0.05]
    whine = sum(a * np.sin((k + 1) * ph + rng.uniform(0, TWO_PI)) for k, a in enumerate(amps))
    brush = bp(white(n, rng), 2500, 7000, 2, C) * (0.4 + 0.6 * np.abs(np.sin(ph)))
    paddle = qf(18.0, n)
    count = int(round(paddle * n / SR))
    pos = (np.arange(count) + 0.08 * rng.standard_normal(count)) * n / count
    pk = modal_k([rng.uniform(800, 950), rng.uniform(1900, 2200), rng.uniform(3000, 3300)], [0.006, 0.004, 0.003], [1.0, 0.6, 0.3])
    auger = conv(impulses(n, pos, 0.5 + 0.5 * rng.random(count), C), pk, C)
    grains = crunch(n, rng, 0.2 + np.sin(np.pi * paddle * t) ** 2, 2500, SNOW_BANDS[:3], cracks=10, circ=C, clump=0.5, grain_cap=2.5)
    gear = np.sin(TWO_PI * qf(640, n) * t) * (0.7 + 0.3 * np.sin(TWO_PI * paddle * t))
    return nrms(whine, 0.8) + nrms(brush, 0.18) + nrms(auger, 0.22) + nrms(grains, 0.2) + nrms(gear, 0.1)


def snd_blower_small(rng):
    """LOOP: single-stage 2-stroke snowblower (~52 Hz firing, raspy, slight 4-stroking)."""
    n = ns(2.0)
    C = True
    t = tvec(n)
    pos, amps, period = firing_times(n, rng, 52.0, (1.0, 0.82, 0.95, 0.7), (0.0, 0.02, -0.01, 0.03), 0.07, 0.012)
    k = exhaust_kernel(rng, 0.04, [(380, 0.008, 0.9), (820, 0.005, 0.6), (1600, 0.003, 0.35)],
                       burst=(1000, 4500), burst_tau=0.003, burst_amp=0.7, pulse_tau=0.0015)
    ex = engine_core(n, rng, pos, amps, k, 40, 2.5, 4500)
    imp = bp(white(n, rng), 500, 2500, 2, C) * (0.75 + 0.25 * np.sin(TWO_PI * qf(14, n) * t))
    hiss = bp(white(n, rng), 3000, 8000, 2, C)
    rk = modal_k([rng.uniform(1100, 1300), rng.uniform(2500, 2900)], [0.004, 0.003], [1.0, 0.6])
    ramps = rng.random(len(pos)) * (rng.random(len(pos)) < 0.4)
    rattle = conv(impulses(n, pos + 0.5 * period, ramps, C), rk, C)
    return nrms(ex) + nrms(imp, 0.25) + nrms(hiss, 0.06) + nrms(rattle, 0.1)


def snd_blower_large(rng):
    """LOOP: two-stage snowblower, bigger OHV single (30 Hz firing): deeper, rougher,
    impeller whoosh, auger rumble, valve tick, gearbox whine."""
    n = ns(2.0)
    C = True
    t = tvec(n)
    pos, amps, period = firing_times(n, rng, 30.0, (1.0,), (0.0,), 0.12, 0.02)
    k = exhaust_kernel(rng, 0.08, [(78, 0.025, 1.0), (175, 0.014, 0.6), (390, 0.007, 0.35)],
                       burst=(300, 1600), burst_tau=0.007, burst_amp=0.65, pulse_tau=0.004)
    ex = engine_core(n, rng, pos, amps, k, 28, 1.8, 3000)
    tk = modal_k([rng.uniform(2200, 2400), rng.uniform(3600, 3800), rng.uniform(5000, 5400)], [0.004, 0.003, 0.002], [1.0, 0.6, 0.3])
    ticks = conv(impulses(n, pos + 0.5 * period, 0.6 + 0.4 * rng.random(len(pos)), C), tk, C)
    imp = bp(white(n, rng), 350, 1800, 2, C) * (0.7 + 0.3 * np.sin(TWO_PI * qf(9, n) * t))
    aug = lp(white(n, rng), 150, 2, C) * (0.8 + 0.2 * np.sin(TWO_PI * qf(3, n) * t))
    gear = np.sin(TWO_PI * qf(760, n) * t + 0.3 * np.sin(TWO_PI * qf(9, n) * t))
    return nrms(ex) + nrms(imp, 0.3) + nrms(aug, 0.25) + nrms(gear, 0.06) + nrms(ticks, 0.12)


def snd_blower_discharge(rng):
    """LOOP: snow blasting out of the chute: bright whoosh with chunky pulses + sizzle."""
    n = ns(1.5)
    C = True
    m = np.exp(1.1 * pmod(n, rng, 14, 2))
    m /= m.max()
    w = white(n, rng)
    whoosh = (bp(w, 800, 7000, 2, C) + 0.6 * nrms(peakf(w, 2600, 1.5, C), rms(bp(w, 800, 7000, 2, C)))) * (0.45 + 0.55 * m)
    low = bp(white(n, rng), 150, 700, 2, C) * (0.6 + 0.4 * m)
    kerns = []
    for _ in range(3):
        L = ns(0.07)
        kerns.append(taper(bp(white(L, rng), 500, 3000) * hit(L, 0, 0.005, 0.03)))
    chunks = np.zeros(n)
    for _ in range(24):
        place(chunks, kerns[rng.integers(3)] * min(rng.pareto(3.0) + 0.4, 2.5), rng.integers(0, n), C)
    sizzle = crunch(n, rng, 0.3 + m, 7000, ((2500, 5000, 1.0), (4500, 9000, 0.7)), circ=C, clump=0.6, grain_cap=2.0)
    return soft_clip(nrms(whoosh, 0.8) + nrms(low, 0.4) + nrms(chunks, 0.45) + nrms(sizzle, 0.35), 4.0)


def snd_engine_truck(rng):
    """LOOP: pickup V8 idle. 8-firing cycle with uneven per-bank pulse amplitude/timing gives the
    cross-plane burble; neutral pitch so the game can pitch-scale it."""
    n = ns(2.0)
    C = True
    pattern = (1.0, 0.78, 0.95, 0.84, 1.08, 0.72, 0.9, 0.97)
    timing = (0.0, 0.05, -0.03, 0.04, 0.0, -0.05, 0.03, -0.02)
    pos, amps, _ = firing_times(n, rng, 44.0, pattern, timing, 0.05, 0.012)
    k = exhaust_kernel(rng, 0.07, [(68, 0.03, 1.0), (142, 0.018, 0.6), (310, 0.008, 0.3)],
                       burst=(250, 1400), burst_tau=0.006, burst_amp=0.5, pulse_tau=0.004)
    ex = engine_core(n, rng, pos, amps, k, 28, 1.6, 1600)
    lope = 1.0 + 0.04 * np.sin(TWO_PI * qf(1.0, n) * tvec(n))
    envf = smooth(np.abs(ex), 8, C)
    mech = bp(white(n, rng), 900, 3200, 2, C) * (0.3 + envf / envf.max())
    intake = bp(white(n, rng), 300, 900, 2, C)
    return nrms(ex) * lope + nrms(mech, 0.12) + nrms(intake, 0.06)


def snd_engine_diesel(rng):
    """LOOP: big diesel idle (6 cyl, 36 Hz firing): low exhaust thump + injection knock clatter."""
    n = ns(2.0)
    C = True
    pos, amps, period = firing_times(n, rng, 36.0, (1.0, 0.9, 1.05, 0.85, 0.97, 0.92), (0.0, 0.02, -0.02, 0.03, -0.01, 0.0), 0.06, 0.01)
    k = exhaust_kernel(rng, 0.08, [(52, 0.035, 1.0), (115, 0.02, 0.5), (240, 0.01, 0.25)],
                       burst=(200, 1000), burst_tau=0.008, burst_amp=0.45, pulse_tau=0.005)
    ex = engine_core(n, rng, pos, amps, k, 25, 1.4, 1200)
    # injection knock: 3 slightly different block-resonance kernels picked at random per firing
    knock = np.zeros(n)
    which = rng.integers(0, 3, len(pos))
    kamp = np.clip(1 + 0.3 * rng.standard_normal(len(pos)), 0.2, None)
    for j in range(3):
        s = rng.uniform(0.93, 1.07)
        kk = modal_k(np.array([1650, 2450, 3300, 4150, 5200]) * s * rng.uniform(0.97, 1.03, 5),
                     [0.005, 0.004, 0.0035, 0.003, 0.002], [1.0, 0.8, 0.6, 0.4, 0.25], dur=0.03)
        kk[:ns(0.002)] += 0.6 * hp(white(ns(0.002), rng), 1500) * np.exp(-np.arange(ns(0.002)) / ns(0.0005))
        sel = which == j
        knock += conv(impulses(n, pos[sel] + 0.08 * period, kamp[sel], C), kk, C)
    tk = modal_k([rng.uniform(3000, 3600), rng.uniform(4500, 5200)], [0.003, 0.002], [1.0, 0.5])
    tamps = rng.random(len(pos)) * (rng.random(len(pos)) < 0.7)
    ticks = conv(impulses(n, pos + 0.5 * period + 0.05 * period * rng.standard_normal(len(pos)), tamps, C), tk, C)
    envf = smooth(np.abs(ex), 8, C)
    clat = bp(white(n, rng), 600, 2500, 2, C) * (0.5 + envf / envf.max())
    y = nrms(ex) + nrms(knock, 0.5) + nrms(ticks, 0.12) + nrms(clat, 0.08)
    return lp(y, 6000, 2, C)


def snd_engine_small(rng):
    """LOOP: ATV single-cylinder idle putt (~14 Hz firing, irregular)."""
    n = ns(1.5)
    C = True
    t = tvec(n)
    pos, amps, period = firing_times(n, rng, 14.0, (1.0,), (0.0,), 0.15, 0.03)
    k = exhaust_kernel(rng, 0.09, [(85, 0.03, 1.0), (190, 0.02, 0.6), (420, 0.01, 0.35)],
                       burst=(400, 1800), burst_tau=0.008, burst_amp=0.6, pulse_tau=0.005)
    ex = engine_core(n, rng, pos, amps, k, 30, 1.5, 2500)
    tk = modal_k([rng.uniform(2500, 2800), rng.uniform(3800, 4100)], [0.003, 0.002], [1.0, 0.5])
    tpos = np.concatenate([pos + 0.3 * period, pos + 0.8 * period])
    ticks = conv(impulses(n, tpos, 0.5 + 0.5 * rng.random(len(tpos)), C), tk, C)
    whir = bp(white(n, rng), 600, 2500, 2, C) * (0.6 + 0.4 * np.sin(TWO_PI * qf(28, n) * t) ** 2)
    return nrms(ex) + nrms(ticks, 0.1) + nrms(whir, 0.1)


def snd_tires_snow(rng):
    """LOOP: tires rolling through packed snow: dense crunch modulated by tread + low rumble."""
    n = ns(2.0)
    C = True
    t = tvec(n)
    dens = (1.0 + 0.35 * np.sin(TWO_PI * qf(36, n) * t)) * np.exp(0.3 * pmod(n, rng, 3, 0.5))
    c = crunch(n, rng, dens, 9000, ((300, 900, 1.0), (800, 2200, 1.0), (1900, 4500, 0.6), (4000, 7000, 0.15)),
               cracks=50, crack_hz=(600, 3500), circ=C, clump=0.4, grain_cap=2.0, crack_gain=0.12, follow=0.4)
    c = soft_clip(c, 8.0)
    squish = bp(white(n, rng), 180, 650, 2, C) * smooth(dens, 20, C)
    rumble = lp(white(n, rng), 110, 2, C) * (0.8 + 0.2 * np.sin(TWO_PI * qf(2, n) * t))
    return nrms(c) + nrms(squish, 0.55) + nrms(rumble, 0.6)


def snd_engine_start(rng):
    """Solenoid clunk, starter cranking (rr-rr-rr), engine catching with a small flare, settles."""
    n = ns(1.25)
    t = tvec(n)
    sol = modal(n, [1150, 2600, 380], [0.012, 0.007, 0.03], [0.5, 0.3, 0.6], t0=0.01) + \
        0.5 * lp(white(n, rng), 2000) * hit(n, 0.01, 0.0005, 0.004)
    comp = 0.5 + 0.5 * np.cos(TWO_PI * 9.5 * t)  # compression strokes load the starter
    spin = 1.0 - np.exp(-np.maximum(t - 0.03, 0) / 0.05)
    sp = np.cumsum(150.0 * (1.0 - 0.2 * comp) * (0.3 + 0.7 * spin)) / SR
    starter = sum(a * np.sin(TWO_PI * (k + 1) * sp) for k, a in enumerate([1, 0.6, 0.5, 0.3, 0.25, 0.15, 0.1, 0.08]))
    starter = nrms(starter) + 0.5 * nrms(bp(white(n, rng), 1500, 5000))
    starter *= (0.5 + 0.5 * (1.0 - comp)) * smooth(env_pts(n, [(0, 0), (0.03, 0), (0.06, 1), (0.58, 1), (0.7, 0), (2, 0)]), 15)
    rate = env_pts(n, [(0, 12), (0.52, 12), (0.62, 20), (0.78, 75), (0.95, 55), (1.25, 46)])
    ph = np.cumsum(rate) / SR
    cross = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    cross = cross[t[cross] >= 0.52]
    pa = np.interp(t[cross], [0.52, 0.6, 0.8, 1.25], [0.3, 0.6, 1.2, 0.8]) * (1.0 + 0.15 * rng.standard_normal(len(cross)))
    k = exhaust_kernel(rng, 0.07, [(68, 0.03, 1.0), (142, 0.018, 0.6), (310, 0.008, 0.3)],
                       burst=(250, 1400), burst_tau=0.006, burst_amp=0.6, pulse_tau=0.004)
    ex = conv(impulses(n, cross + rng.normal(0, 2, len(cross)), np.maximum(pa, 0.05)), k)
    ex = np.tanh(1.5 * nrm(hp(ex, 28)))
    ex *= smooth(env_pts(n, [(0, 0), (0.5, 0), (0.55, 1), (0.95, 1), (1.22, 0), (2, 0)]), 30)
    y = nrm(sol, 0.4) + nrm(starter, 0.6) + nrm(ex, 1.0)
    return lp(y, 3500, 2)


def snd_horn(rng):
    """Truck horn: two detuned pulse-wave tones (~351/438 Hz) through horn resonances."""
    n = ns(0.62)
    t = tvec(n)

    def pulse_wave(fa, duty):
        ph = np.cumsum(fa) / SR
        y = np.zeros(n)
        for k in range(1, int(9000 / fa.max()) + 1):
            y += np.sin(np.pi * k * duty) / k * np.cos(TWO_PI * k * ph)
        return y

    bend = 1.0 - 0.025 * np.exp(-t / 0.025)
    tone = pulse_wave(351.5 * bend, 0.42) + 0.9 * pulse_wave(438.0 * bend, 0.38)
    tone = np.tanh(1.4 * nrm(tone))
    tone = 0.6 * tone + 0.8 * peakf(tone, 2100, 2.5) + 0.5 * peakf(tone, 900, 2.0)
    tone = lp(tone, 4000, 2)
    env = smooth(env_pts(n, [(0, 0), (0.012, 1), (0.53, 0.95), (0.6, 0), (1, 0)]), 4)
    return tone * env * (1.0 + 0.03 * np.sin(TWO_PI * 23 * t))


# =============================================================================
# SOUNDS: weather / ambience
# =============================================================================

def snd_wind_light(rng):
    """LOOP 10 s: gentle breeze, soft low-passed noise with slow swells that brighten slightly."""
    n = ns(10.0)
    C = True
    g = pmod(n, rng, 0.6, 0.05, tilt=0.8)
    gust = 0.5 + 0.5 * np.tanh(1.2 * g)
    bed = hp(morph_lp(pink(n, rng), gust, [250, 480, 850], C), 35, 2, C)
    air = bp(white(n, rng), 600, 2200, 2, C) * (0.15 + 0.85 * gust ** 1.5)
    whistle = nrms(nb_noise(n, rng, 720.0 * (1.0 + 0.1 * g), 16.0)) * np.clip(gust - 0.5, 0, None) ** 2
    return nrms(bed) * (0.45 + 0.55 * gust) + nrms(air, 0.12) + whistle * 1.0


def snd_wind_strong(rng):
    """LOOP 11 s: strong wind: fuller noise, gusts, whistle resonances sweeping with the gusts."""
    n = ns(11.0)
    C = True
    g = pmod(n, rng, 0.7, 0.04, tilt=0.7)
    gust = 0.5 + 0.5 * np.tanh(1.3 * g)
    g2 = np.roll(gust, ns(0.6))
    bed = morph_lp(pink(n, rng), gust, [350, 800, 1800], C) * (0.35 + 0.65 * gust)
    rumble = lp(white(n, rng), 120, 2, C) * (0.5 + 0.5 * g2)
    wob = pmod(n, rng, 4.0, 1.0)
    w1 = nrms(nb_noise(n, rng, 620.0 * (1.0 + 0.3 * (gust - 0.5) + 0.015 * wob), 25.0)) * gust ** 2.5
    w2 = nrms(nb_noise(n, rng, 980.0 * (1.0 + 0.22 * (g2 - 0.5) + 0.01 * wob), 18.0)) * g2 ** 3
    hiss = bp(white(n, rng), 2500, 7000, 2, C) * gust ** 2
    return nrms(bed) + nrms(rumble, 0.35) + 0.5 * w1 + 0.3 * w2 + nrms(hiss, 0.1)


def snd_blizzard(rng):
    """LOOP 12 s: violent storm: roaring wind with surges, buffeting, howling resonances,
    ice-particle hiss."""
    n = ns(12.0)
    C = True
    g = pmod(n, rng, 0.8, 0.04, tilt=0.6)
    gust = 0.5 + 0.5 * np.tanh(1.5 * g)
    surge = gust ** 1.6
    buffet = pmod(n, rng, 7.0, 1.2)
    roar = morph_lp(pink(n, rng), gust, [900, 1800, 3500], C) * (0.45 + 0.55 * surge) * (1.0 + 0.15 * buffet)
    low = lp(white(n, rng), 90, 2, C) * (0.5 + 0.5 * surge) * (1.0 + 0.35 * buffet)
    wob = pmod(n, rng, 5.0, 1.5)
    howl = np.zeros(n)
    for f0, bw, lag, depth, lvl, pw in ((380, 14, 0.4, 0.35, 0.9, 2.0), (560, 16, 1.1, 0.3, 0.7, 2.0),
                                        (880, 18, 1.9, 0.3, 0.5, 2.5), (1650, 10, 0.2, 0.15, 0.25, 4.0)):
        gl = np.roll(gust, ns(lag))
        fc = f0 * (1.0 + depth * (gl - 0.5) + 0.02 * wob)
        howl += lvl * nrms(nb_noise(n, rng, fc, bw)) * (0.2 + 0.8 * gl ** pw)
    # moaning resonance with a time-varying resonant filter; rendered past the loop end and
    # crossfaded tail-into-head for a seamless seam
    xf = ns(1.0)
    gx = np.concatenate([gust, gust[:xf]])
    moan = svf(white(n + xf, rng), 300.0 + 260.0 * gx, 9.0)
    moan = make_loop_seamless(moan, n, xf)
    hiss = bp(white(n, rng), 2500, 9000, 2, C) * (0.3 + 0.7 * surge)
    return nrms(roar) + nrms(low, 0.55) + howl + nrms(moan, 0.3) * (0.3 + 0.7 * gust) + nrms(hiss, 0.2)


def snd_fire_crackle(rng):
    """LOOP 10 s: cozy fireplace: soft flickering roar + crackle clusters + wood pops + sap hiss."""
    n = ns(10.0)
    C = True
    T = n / SR
    flick = 0.75 + 0.25 * np.tanh(pmod(n, rng, 4.0, 0.2))
    roar = (nrms(lp(brown(n, rng), 260, 2, C)) + 0.4 * nrms(bp(white(n, rng), 150, 500, 2, C))) * flick
    hiss = bp(white(n, rng), 2000, 6000, 2, C)
    pos = list(rng.uniform(0, n, int(5.0 * T)))
    for _ in range(int(1.2 * T)):
        p = rng.uniform(0, n)
        for _ in range(int(rng.integers(3, 11))):
            p += rng.exponential(0.018) * SR
            pos.append(p)
    pos = np.array(pos)
    amps = (rng.pareto(2.2, len(pos)) + 0.2) * rng.choice((-1.0, 1.0), len(pos))
    cls = rng.random(len(pos)) < 0.6
    L1, L2 = ns(0.0008), ns(0.003)
    k1 = white(L1, rng) * np.exp(-np.arange(L1) / (L1 / 4))
    k2 = white(L2, rng) * np.exp(-np.arange(L2) / (L2 / 5))
    crack = hp(conv(impulses(n, pos[cls], amps[cls], C), k1, C), 1000, 2, C) + \
        bp(conv(impulses(n, pos[~cls], amps[~cls], C), k2, C), 1200, 7000, 2, C)
    pops = np.zeros(n)
    for _ in range(int(0.35 * T)):
        seg = modal_k([rng.uniform(150, 300), rng.uniform(400, 700), rng.uniform(1200, 2000)],
                      [rng.uniform(0.02, 0.04), 0.015, 0.006], [1.0, 0.6, 0.4])
        Lc = ns(0.004)
        seg[:Lc] += 1.2 * hp(white(Lc, rng), 1500) * np.exp(-np.arange(Lc) / (Lc / 5))
        place(pops, seg * rng.uniform(0.5, 1.0), rng.uniform(0, n), C)
    sap = np.zeros(n)
    for _ in range(2):
        L = ns(rng.uniform(0.4, 1.0))
        place(sap, bp(white(L, rng), 3000, 5500) * np.sin(np.pi * np.arange(L) / L) ** 2 * rng.uniform(0.5, 1.0), rng.uniform(0, n), C)
    return nrms(roar, 0.5) + nrm(crack, 2.2) + nrm(pops, 2.6) + nrms(hiss, 0.04) + nrms(sap, 0.03)


def snd_furnace_hum(rng):
    """LOOP 10 s: quiet heating hum (60/120 Hz family) + blower airflow."""
    n = ns(10.0)
    C = True
    t = tvec(n)
    hum = sum(a * np.sin(TWO_PI * f * t + rng.uniform(0, TWO_PI))
              for f, a in ((60, 0.5), (120, 1.0), (180, 0.3), (240, 0.25), (360, 0.08)))
    hum *= 1.0 + 0.05 * pmod(n, rng, 0.5, 0.1)
    air = nrms(lp(white(n, rng), 900, 2, C)) + 0.6 * nrms(bp(white(n, rng), 150, 500, 2, C))
    air *= 1.0 + 0.08 * pmod(n, rng, 0.6, 0.1)
    return nrms(hum, 0.5) + nrms(air, 0.8)


def snd_room_tone(rng):
    """LOOP 10 s: very quiet indoor room tone."""
    n = ns(10.0)
    C = True
    t = tvec(n)
    tone = hp(lp(pink(n, rng), 700, 2, C), 30, 2, C)
    return nrms(tone) + nrms(np.sin(TWO_PI * 120 * t), 0.06)


def snd_shiver(rng):
    """LOOP 2 s: shaky breath (tremolo'd exhale/inhale) + chattering teeth bursts."""
    n = ns(2.0)
    C = True
    ex_env = smooth(env_pts(n, [(0, 0.0), (0.06, 0.0), (0.18, 0.9), (0.7, 0.75), (1.0, 0.35), (1.1, 0.0), (2.0, 0.0)]), 30, C)
    in_env = smooth(env_pts(n, [(0, 0), (1.2, 0), (1.32, 0.7), (1.7, 0.6), (1.85, 0), (2.0, 0)]), 30, C)
    w = white(n, rng)
    breath_ex = peakf(w, 700, 3, C) + 0.8 * peakf(w, 1200, 4, C) + 0.5 * peakf(w, 2500, 5, C) + 0.4 * bp(w, 400, 3000, 2, C)
    breath_in = bp(white(n, rng), 1200, 5000, 2, C)
    breath = nrms(breath_ex) * ex_env * (1.0 + 0.6 * np.tanh(1.5 * pmod(n, rng, 13, 6))) + \
        0.6 * nrms(breath_in) * in_env * (1.0 + 0.5 * np.tanh(1.5 * pmod(n, rng, 13, 6)))
    kerns = [modal_k([rng.uniform(2100, 2500), rng.uniform(3300, 3700), rng.uniform(4600, 5100), rng.uniform(6000, 6500),
                      rng.uniform(380, 460)], [0.003, 0.002, 0.0015, 0.001, 0.006], [1.0, 0.7, 0.45, 0.25, 0.35], dur=0.02)
             for _ in range(3)]
    teeth = np.zeros(n)
    for s0 in (0.08, 0.55, 1.05, 1.5):
        s = s0 + rng.uniform(-0.04, 0.04)
        rate = rng.uniform(11, 16)
        m = int(rng.integers(4, 9))
        for j in range(m):
            p = s + j / rate * (1.0 + rng.normal(0, 0.15))
            a = rng.uniform(0.4, 1.0) * np.sin(np.pi * (j + 0.5) / m) ** 0.5
            k = kerns[rng.integers(3)]
            place(teeth, k * a, at(p), C)
            if rng.random() < 0.5:  # rebound
                place(teeth, k * a * 0.35, at(p + rng.uniform(0.003, 0.006)), C)
    return nrms(breath, 0.28) + nrm(teeth, 1.6)


def heart_thump(rng, f_hi, f_lo, tau, length=0.3):
    n = ns(length)
    t = tvec(n)
    f = f_lo + (f_hi - f_lo) * np.exp(-t / 0.03)
    s = np.sin(TWO_PI * np.cumsum(f) / SR) * (1.0 - np.exp(-t / 0.006)) * np.exp(-t / tau)
    s += 0.35 * nrm(lp(white(n, rng), 120, 2)) * (1.0 - np.exp(-t / 0.004)) * np.exp(-t / (tau * 0.6))
    return fade(s, 0, 0.06)


def snd_heartbeat(rng):
    """LOOP 1.6 s: two lub-dub beats at 75 bpm."""
    n = ns(1.6)
    C = True
    y = np.zeros(n)
    for b, t0 in enumerate((0.03, 0.83)):
        g = 1.0 if b == 0 else 0.94
        place(y, g * heart_thump(rng, 78, 42, 0.06), at(t0), C)
        place(y, g * 0.7 * heart_thump(rng, 92, 55, 0.045), at(t0 + 0.29), C)
    y = np.tanh(1.8 * nrm(y)) / np.tanh(1.8)  # a few harmonics so it reads on small speakers
    return lp(y, 320, 2, C)


def snd_gust_whistle(rng):
    """One-shot gust: swelling roar with whistles that rise and fall with it."""
    n = ns(2.5)
    e = np.clip(smooth(env_pts(n, [(0, 0), (0.5, 0.35), (0.95, 0.85), (1.25, 1.0), (1.7, 0.55), (2.2, 0.15), (2.5, 0)]), 120), 0, None)
    wob = pmod(n, rng, 4, 0.5)
    roar = svf(pink(n, rng), 300.0 + 1100.0 * e, 0.7, "lp") * e
    wh1 = svf(white(n, rng), (600.0 + 550.0 * e) * (1.0 + 0.012 * wob), 30.0)
    wh2 = svf(white(n, rng), (900.0 + 700.0 * e) * (1.0 + 0.015 * wob), 40.0)
    hiss = bp(white(n, rng), 3000, 8000) * e ** 2
    return nrms(roar) + nrms(wh1, 0.5) * e ** 2 + nrms(wh2, 0.25) * e ** 3 + nrms(hiss, 0.15)


def snd_rattle(rng):
    """Window / sign rattling in a gust: fast irregular wooden and glass/metal ticks."""
    n = ns(0.8)
    rate = env_pts(n, [(0, 22), (0.3, 34), (0.6, 26), (0.8, 18)])
    ph = np.cumsum(rate) / SR
    cross = np.nonzero(np.diff(np.floor(ph)) > 0)[0] + 1
    ae = env_pts(n, [(0, 0.35), (0.12, 1.0), (0.45, 0.85), (0.78, 0.0), (1, 0)])
    wood = [modal_k([rng.uniform(310, 360), rng.uniform(690, 760), rng.uniform(1250, 1400), rng.uniform(2300, 2600)],
                    [0.012, 0.007, 0.004, 0.002], [1.0, 0.7, 0.4, 0.2]) for _ in range(3)]
    glass = [modal_k([rng.uniform(2000, 2300), rng.uniform(3200, 3500), rng.uniform(4500, 5000)],
                     [0.02, 0.012, 0.008], [1.0, 0.6, 0.35]) * 0.6 for _ in range(2)]
    y = np.zeros(n)
    for c in cross:
        if rng.random() < 0.15:
            continue
        p = c + rng.normal(0, 0.2) * SR / rate[c]
        a = ae[min(c, n - 1)] * rng.uniform(0.5, 1.0)
        k = wood[rng.integers(3)] if rng.random() < 0.65 else glass[rng.integers(2)]
        place(y, k * a, p)
    buzz = lp(white(n, rng), 200, 2) * ae
    return nrm(y) + nrm(buzz, 0.12)


# =============================================================================
# SOUNDS: UI / interaction
# =============================================================================

def snd_ui_click(rng):
    n = ns(0.065)
    y = modal(n, [1450, 2900, 480], [0.008, 0.003, 0.012], [1.0, 0.22, 0.45], t0=0.0008)
    y += 0.25 * hp(white(n, rng), 2500) * hit(n, 0.0008, 0.0002, 0.0012)
    return lp(y, 6000, 2)


def snd_ui_hover(rng):
    n = ns(0.03)
    return modal(n, [2400, 4100], [0.004, 0.0015], [1.0, 0.3], t0=0.0005)


def snd_ui_error(rng):
    """Soft low double buzz."""
    n = ns(0.26)
    y = np.zeros(n)
    for t0, f, d in ((0.004, 165.0, 0.085), (0.125, 150.0, 0.09)):
        L = ns(d)
        tt = tvec(L)
        # rounded square-ish tone (odd harmonics rolled off fast) with a hint of 2nd harmonic: soft buzz
        tone = sum((1.0 / k ** 1.6) * np.sin(TWO_PI * k * f * tt) for k in range(1, 16, 2)) + 0.25 * np.sin(TWO_PI * 2 * f * tt)
        place(y, lp(tone, 750, 2) * note_env(L, 0.008, d - 0.03, 0.022), at(t0))
    return y


def snd_ui_money(rng):
    """Cash register 'ka-ching': drawer clunk, bright E-major bell chord, coin shimmer."""
    n, N = ns(0.62), ns(1.0)
    ka = modal(N, [180, 420, 1100, 2600], [0.03, 0.02, 0.01, 0.005], [0.8, 0.7, 0.5, 0.3], t0=0.002) + \
        0.8 * bp(white(N, rng), 1000, 5000) * hit(N, 0.002, 0.0005, 0.004)
    ching = np.zeros(N)
    for i, m in enumerate((88, 92, 95)):  # E6 G#6 B6
        place(ching, bell_note(rng, midi_hz(m), 0.8 - 0.1 * i, length=0.9, decay=0.45), at(0.07 + 0.018 * i))
    coins = np.zeros(N)
    for _ in range(7):
        f = rng.uniform(3000, 6500)
        place(coins, modal_k([f, f * 1.47, f * 2.03], [0.03, 0.02, 0.012], [1.0, 0.5, 0.3]) * rng.uniform(0.15, 0.35), at(rng.uniform(0.08, 0.38)))
    y = nrm(ka, 0.55) + nrm(ching, 1.0) + nrm(coins, 0.3)
    y = y + 0.15 * signal.fftconvolve(y, make_ir(rng, 0.5, 0.6, 0.01, 6000, 2500))[:N]
    return fade(y[:n], 0, 0.08)


def snd_ui_notify(rng):
    """Gentle two-note chime (G5 -> C6)."""
    n, N = ns(0.42), ns(0.9)
    y = np.zeros(N)
    for m, when, vel in ((79, 0.0, 0.7), (84, 0.12, 0.8)):
        place(y, bell_note(rng, midi_hz(m), vel, 0.8, 0.35, SOFT_BELL), at(when + 0.002))
    y = y + 0.12 * signal.fftconvolve(y, make_ir(rng, 0.6, 0.7, 0.01, 6000, 2500))[:N]
    return fade(y[:n], 0, 0.1)


def snd_ui_alert(rng):
    """Attention chime: three descending notes, a bit brighter / more urgent."""
    n, N = ns(0.82), ns(1.2)
    y = np.zeros(N)
    alert = ((1.0, 1.0, 1.0), (2.0, 0.35, 0.6), (3.0, 0.2, 0.4), (4.0, 0.1, 0.3))
    for m, when in ((88, 0.0), (84, 0.17), (81, 0.34)):  # E6 C6 A5
        f = midi_hz(m)
        L = ns(0.16)
        tri = osc(tri_table(f), f, L) * note_env(L, 0.005, 0.09, 0.06) * 0.35
        place(y, bell_note(rng, f, 0.8, 0.9, 0.28, alert), at(when + 0.002))
        place(y, tri, at(when + 0.002))
    y = y + 0.12 * signal.fftconvolve(y, make_ir(rng, 0.6, 0.7, 0.01, 6000, 2500))[:N]
    return fade(y[:n], 0, 0.12)


def snd_pickup_item(rng):
    """Picking up a tool: plastic/metal clunk + handling rustle."""
    n = ns(0.3)
    clunk = modal(n, [rng.uniform(280, 340), rng.uniform(760, 860), rng.uniform(1450, 1600), rng.uniform(2600, 2900), 4100],
                  [0.04, 0.025, 0.015, 0.008, 0.004], [1.0, 0.7, 0.5, 0.3, 0.15], t0=0.008)
    clunk += 0.6 * nrm(lp(white(n, rng), 300, 2) * hit(n, 0.008, 0.002, 0.02))
    re = (hit(n, 0.0, 0.02, 0.08) + 0.6 * hit(n, 0.1, 0.015, 0.06)) * (0.5 + 0.5 * np.tanh(1.5 * pmod(n, rng, 120, 30)))
    rustle = bp(white(n, rng), 1800, 7000) * re
    return nrm(clunk) + nrm(rustle, 0.4)


def snd_paper(rng):
    """Paper rustle / unfolding a letter: crinkle grains, swish and a soft snap."""
    n = ns(0.52)
    dens = sum(a * hit(n, t0, 0.01, tau) for t0, a, tau in ((0.01, 1.0, 0.06), (0.14, 0.7, 0.05), (0.27, 1.0, 0.07), (0.38, 0.5, 0.05)))
    crinkle = crunch(n, rng, dens, 700, ((1800, 4000, 1.0), (3500, 8000, 1.0), (6000, 10000, 0.4)),
                     cracks=30, crack_hz=(2000, 6000), clump=1.2, follow=0.9)
    se = smooth(env_pts(n, [(0, 0), (0.05, 0.8), (0.2, 0.5), (0.3, 1.0), (0.45, 0.3), (0.52, 0)]), 20)
    swish = bp(white(n, rng), 900, 6000) * se * (0.5 + 0.5 * np.tanh(pmod(n, rng, 50, 10)))
    snap = hp(white(n, rng), 1200) * hit(n, 0.3, 0.001, 0.01) + modal(n, [700, 1500], [0.012, 0.006], [0.6, 0.3], t0=0.3)
    return nrm(crinkle, 0.8) + nrm(swish, 0.5) + nrm(snap, 0.4)


def snd_mailbox(rng):
    """Metal mailbox lid: hinge creak then a clank (with a small bounce)."""
    n = ns(0.62)
    metal = modal_k([rng.uniform(880, 950), rng.uniform(1750, 1900), rng.uniform(2700, 2900), 3900],
                    [0.02, 0.012, 0.008, 0.005], [1.0, 0.8, 0.5, 0.3])
    ae = smooth(env_pts(n, [(0, 0), (0.03, 0.7), (0.15, 1.0), (0.3, 0.8), (0.36, 0), (1, 0)]), 10)
    creak = stick_slip(n, rng, env_pts(n, [(0, 55), (0.1, 80), (0.25, 62), (0.34, 90)]), 0.01, 0.36, metal, 0.1, 0.35, amp_env=ae)
    clank = np.zeros(n)
    for t0, a in ((0.40, 1.0), (0.445, 0.3)):
        clank += a * modal(n, [430, 610, 1180, 2050, 3240, 4600], [0.18, 0.12, 0.1, 0.07, 0.05, 0.03], [1.0, 0.5, 0.7, 0.5, 0.35, 0.2], t0)
        clank += a * 0.6 * hp(white(n, rng), 1000) * hit(n, t0, 0.0003, 0.003)
        clank += a * 0.5 * nrm(lp(white(n, rng), 250, 2) * hit(n, t0, 0.002, 0.03))
    return nrm(creak, 0.45) + nrm(clank, 1.0)


def snd_door_open(rng):
    """Wooden door: latch unclick, then a creak whose pitch rises and falls."""
    n = ns(0.82)
    latch = np.zeros(n)
    for t0, a in ((0.008, 0.8), (0.055, 0.55)):
        latch += a * click(n, rng, t0, (rng.uniform(2300, 2600), rng.uniform(3700, 4000), rng.uniform(5000, 5400), rng.uniform(850, 950)),
                           (0.006, 0.004, 0.003, 0.01), (1.0, 0.6, 0.35, 0.4))
    rate = env_pts(n, [(0.14, 70), (0.3, 120), (0.5, 165), (0.65, 130), (0.8, 95)]) * (1.0 + 0.05 * pmod(n, rng, 12, 2))
    ae = smooth(env_pts(n, [(0, 0), (0.14, 0), (0.2, 0.6), (0.35, 1.0), (0.55, 0.8), (0.7, 0.9), (0.78, 0.0), (1, 0)]), 15) * \
        (0.75 + 0.25 * np.tanh(2.0 * pmod(n, rng, 20, 3)))
    wood = modal_k([rng.uniform(240, 280), rng.uniform(560, 620), rng.uniform(1050, 1150), rng.uniform(1800, 1950), rng.uniform(2800, 3000)],
                   [0.012, 0.008, 0.006, 0.004, 0.003], [0.8, 1.0, 0.7, 0.4, 0.2])
    creak = stick_slip(n, rng, rate, 0.14, 0.79, wood, 0.08, 0.3, amp_env=ae)
    air = lp(white(n, rng), 500, 2) * ae
    return nrm(latch, 0.7) + nrm(creak, 1.0) + nrm(air, 0.08)


def snd_door_close(rng):
    """Door thud + latch click + a little rattle."""
    n = ns(0.52)
    thud = nrm(lp(white(n, rng), 350, 2) * hit(n, 0.01, 0.002, 0.04)) + \
        nrm(modal(n, [rng.uniform(75, 90), rng.uniform(130, 150), rng.uniform(220, 250), 420], [0.08, 0.05, 0.035, 0.02], [1.0, 0.8, 0.5, 0.3], t0=0.01))
    latch = click(n, rng, 0.035, (2500, 3900, 5600), (0.008, 0.005, 0.003), (1.0, 0.6, 0.35))
    rat = click(n, rng, 0.075, (rng.uniform(1800, 2100), 3300), (0.004, 0.003), (1.0, 0.5), 0.3) + \
        0.6 * click(n, rng, 0.115, (rng.uniform(1600, 1900), 3000), (0.004, 0.003), (1.0, 0.5), 0.3)
    return nrm(thud) + nrm(latch, 0.5) + nrm(rat, 0.15)


def snd_keys_jingle(rng):
    """Bunch of keys: two shakes of bright inharmonic tinkles, a few settling."""
    n = ns(0.62)
    y = np.zeros(n)
    times = list(0.02 + np.sort(rng.uniform(0, 0.15, 14))) + list(0.25 + np.sort(rng.uniform(0, 0.13, 10))) + \
        list(rng.uniform(0.4, 0.52, 3))
    for t0 in times:
        f = rng.uniform(2800, 5200)
        taus = rng.uniform(0.015, 0.07) * np.array([1.0, 0.7, 0.5, 0.35])
        seg = modal_k([f, f * 1.52, f * (2.21 + rng.uniform(-0.05, 0.05)), f * 2.9], taus, [1.0, 0.6, 0.45, 0.3])
        Lc = ns(0.002)
        seg[:Lc] += 0.4 * hp(white(Lc, rng), 3000) * np.exp(-np.arange(Lc) / (Lc / 6))
        place(y, seg * rng.uniform(0.3, 1.0), at(t0))
    return lp(hp(y, 1500, 2), 10000, 2)


def snd_truck_locked(rng):
    """Door handle pulled against a lock: clunk-clunk."""
    n = ns(0.42)
    y = np.zeros(n)
    for t0, a in ((0.02, 1.0), (0.18 + rng.uniform(-0.015, 0.015), 0.85)):
        y += a * nrm(lp(white(n, rng), 280, 2) * hit(n, t0, 0.002, 0.025))
        y += a * modal(n, [rng.uniform(420, 480), rng.uniform(980, 1100), rng.uniform(1700, 1900)], [0.025, 0.015, 0.008], [0.8, 0.5, 0.25], t0)
        y += a * 0.3 * click(n, rng, t0 + 0.002, (2600, 4200), (0.002, 0.0015), (1.0, 0.5))
        y += a * 0.08 * modal(n, [3200], [0.03], [1.0], t0 + 0.004)
    return y


def snd_radio_jingle(rng):
    """Friendly station ident: C-E-G-C' with a soft synth lead, chord pad and a small room."""
    n, N = ns(1.55), ns(2.4)
    lead = np.zeros(N)
    for m, when, dur in ((72, 0.00, 0.14), (76, 0.15, 0.14), (79, 0.30, 0.14), (84, 0.45, 0.7)):
        place(lead, lead_note(rng, midi_hz(m), dur), at(when))
    chord = np.zeros(N)
    for m in (60, 64, 67):
        place(chord, pad_note(rng, m, 0.7, attack=0.06, release=0.4, fc=1500, detune=6), at(0.45))
    bass = np.zeros(N)
    place(bass, bass_note(rng, midi_hz(48), 0.5, 0.4), at(0.45))
    dry = nrm(lead) + nrm(chord, 0.45) + nrm(bass, 0.35)
    y = dry + 0.25 * signal.fftconvolve(dry, make_ir(rng, 0.9, 1.0, 0.015))[:N]
    return fade(y[:n], 0, 0.25)


def hum_tone(f_arr, amps):
    ph = np.cumsum(f_arr) / SR
    return sum(a * np.sin(TWO_PI * (k + 1) * ph) for k, a in enumerate(amps))


def relay_click(n, rng, t0, amp=1.0):
    return amp * (modal(n, [1800, 3100, 520], [0.006, 0.004, 0.012], [0.8, 0.5, 0.6], t0) +
                  0.6 * hp(white(n, rng), 1500) * hit(n, t0, 0.0003, 0.002))


def snd_power_off(rng):
    """Power cut: breaker click + electric pop, mains hum winding down."""
    n = ns(1.25)
    f = env_pts(n, [(0, 120), (0.3, 96), (0.8, 50), (1.25, 28)])
    hum = hum_tone(f, [1.0, 0.55, 0.35, 0.12, 0.15])
    buzz = lp(hum_tone(f, [0, 0, 0.3, 0, 0.2, 0, 0.15, 0, 0.1]), 2000) * hit(n, 0.01, 0.003, 0.12)
    env = smooth(env_pts(n, [(0, 0), (0.015, 1), (0.4, 0.6), (1.1, 0.1), (1.24, 0), (2, 0)]), 10)
    # transformer buzz partials keep the hum audible on small speakers as it drops
    hum = hum + 0.6 * lp(hum_tone(f, [0, 0.3, 0.25, 0.2, 0.15, 0.12, 0.1, 0.08, 0.06, 0.05]), 1500)
    pop = relay_click(n, rng, 0.005) + 0.6 * bp(white(n, rng), 300, 3000) * hit(n, 0.005, 0.0005, 0.01)
    return nrm(hum * env + 0.5 * buzz) + nrm(pop, 0.8) + 0.25 * relay_click(n, rng, 1.08)


def snd_power_on(rng):
    """Power restored: relay clack, hum spinning up to mains."""
    n = ns(1.0)
    f = env_pts(n, [(0.02, 35), (0.4, 90), (0.75, 118), (1.0, 120)])
    hum = hum_tone(f, [1.0, 0.55, 0.35, 0.12, 0.15])
    hum = hum + 0.6 * lp(hum_tone(f, [0, 0.3, 0.25, 0.2, 0.15, 0.12, 0.1, 0.08, 0.06, 0.05]), 1500)
    env = smooth(env_pts(n, [(0, 0), (0.02, 0), (0.25, 0.5), (0.6, 0.9), (0.85, 0.8), (0.99, 0), (2, 0)]), 10)
    return nrm(hum * env) + nrm(relay_click(n, rng, 0.008), 0.8)


def snd_death_sting(rng):
    """Somber, cold sting: low D-minor pad, sub boom, slowly falling celesta notes, icy air, reverb."""
    n, N = ns(4.0), ns(6.0)
    pad = np.zeros(N)
    for m in (38, 45, 50, 53, 57):
        place(pad, pad_note(rng, m, 2.6, 0.45, 1.6, 650, 9), 0)
    boom = lp(white(N, rng), 90, 2) * hit(N, 0.0, 0.02, 0.5)
    bells = np.zeros(N)
    for m, when, vel in ((81, 0.25, 0.7), (77, 0.85, 0.6), (74, 1.5, 0.5), (69, 2.25, 0.45)):  # A5 F5 D5 A4
        place(bells, bell_note(rng, midi_hz(m), vel, length=3.0, decay=1.8), at(when))
    ice = bp(white(N, rng), 5000, 9000) * smooth(env_pts(N, [(0, 0), (0.3, 1), (2.5, 0.4), (4, 0), (10, 0)]), 50)
    dry = nrms(pad, 0.8) + nrm(bells, 2.5) + nrm(boom, 1.5) + nrms(ice, 0.03)
    wet = signal.fftconvolve(dry, make_ir(rng, 3.5, 3.8, 0.03))[:N]
    y = (0.75 * dry + 0.6 * wet)[:n]
    return fade(y, 0, 0.8)


# =============================================================================
# SOUNDS: voices
# =============================================================================

def snd_help_call(rng):
    """'Hey! … Help!' shouted from across the street. Formant synthesis made more human (polish
    pass): a rough, breathy shouting source with natural pitch scoops and a little vibrato, a
    second voice layer slightly out of sync (real voices are never perfectly steady), more
    aspiration on the h's, then distance filtering, house reflections and reverb."""
    n = ns(1.6)
    E_hey, I_off, E_help, L_ = (640, 1850, 2550, 3500), (450, 2150, 2780, 3600), (660, 1760, 2550, 3500), (380, 1050, 2650, 3500)
    F = kf(n, [(0.0, E_hey), (0.18, E_hey), (0.36, I_off), (0.46, I_off), (0.62, E_help), (0.90, E_help), (0.98, L_), (1.6, L_)])
    bw_v, bw_h, bw_l = (110, 130, 190, 270), (230, 230, 320, 380), (140, 190, 270, 320)
    BW = kf(n, [(0.0, bw_h), (0.12, bw_v), (0.42, bw_v), (0.52, bw_h), (0.74, bw_v), (0.92, bw_v), (0.98, bw_l), (1.6, bw_l)])
    # Shouting contour: a quick upward scoop into each word, a fall at the end of "help".
    f0 = kf(n, [(0.0, 150), (0.12, 158), (0.17, 190), (0.25, 205), (0.36, 182), (0.46, 160), (0.56, 160), (0.64, 175),
                (0.72, 215), (0.84, 200), (0.95, 168), (1.08, 145), (1.6, 140)])[0]
    vib = 1.0 + 0.018 * np.sin(TWO_PI * 5.3 * tvec(n) + rng.uniform(0, 6.28)) * smooth(env_pts(n, [(0, 0), (0.2, 1), (1.6, 1)]), 40)
    f0 = f0 * vib
    av = kf(n, [(0.0, 0), (0.105, 0), (0.15, 1.0), (0.36, 1.0), (0.44, 0.5), (0.49, 0), (0.705, 0), (0.74, 1.0),
                (0.9, 0.95), (0.96, 0.55), (1.04, 0.45), (1.065, 0), (1.6, 0)])[0]
    ah = kf(n, [(0, 0), (0.03, 0), (0.05, 0.5), (0.11, 0.42), (0.16, 0.08), (0.40, 0.08), (0.47, 0.14), (0.52, 0),
                (0.63, 0), (0.65, 0.5), (0.71, 0.42), (0.75, 0.08), (1.04, 0.05), (1.08, 0), (1.6, 0)])[0]
    af = kf(n, [(0, 0), (1.135, 0), (1.14, 1.0), (1.152, 0.3), (1.2, 0.06), (1.24, 0), (1.6, 0)])[0]
    y1 = formant_voice(rng, n, f0, F, BW, av, ah, af, tilt=0.7, jitter=0.02, shimmer=0.1, breath=0.12,
                       fric_band=(700, 5000), fric_gain=0.12)
    # A second, slightly different take a few ms late (thickens the voice, removes the buzz).
    f0b = f0 * (1.0 + 0.012 * pmod(n, rng, 4.0, 0.5))
    y2 = formant_voice(rng, n, f0b, F, BW, av, ah, af, tilt=0.75, jitter=0.025, shimmer=0.12, breath=0.14,
                       fric_band=(700, 5000), fric_gain=0.1)
    y = nrm(y1) + 0.55 * np.roll(nrm(y2), at(0.009))
    y = soft_clip(y, 3.0)                     # a strained, shouted edge
    y = lp(hp(y, 160, 2), 3400, 2)            # distance: thin lows, air absorption of highs
    wet = signal.fftconvolve(y, make_ir(rng, 1.1, 1.2, 0.035, 2800, 800))[:n]
    taps = np.zeros(n)  # early reflections off nearby houses
    for d, g in ((0.023, 0.32), (0.047, 0.22), (0.083, 0.15), (0.121, 0.08)):
        place(taps, y * g, at(d))
    return fade(y + 0.3 * wet + lp(taps, 2000, 2), 0, 0.2)


def snd_neighbor_talk(rng, v):
    """Friendly older man murmuring gibberish syllables (Animal-Crossing style blips)."""
    n_syl = (4, 5, 6)[v - 1]
    base = rng.uniform(112, 126)
    cons = ["b", "d", "m", "n", "l", "h", "w", "g", ""]
    t = 0.025
    F_pts, AV, AH, AF, F0 = [], [(0.0, 0.0)], [(0.0, 0.0)], [(0.0, 0.0)], []
    prev = None
    stress = int(rng.integers(0, 2))
    for s in range(n_syl):
        c = cons[rng.integers(len(cons))]
        vk = rng.choice([k for k in VOWELS if k != prev])
        prev = vk
        V = VOWELS[vk]
        cd = {"": 0.012, "h": 0.045, "b": 0.045, "d": 0.04, "g": 0.045, "m": 0.05, "n": 0.045, "l": 0.045, "w": 0.045}[c]
        vd = rng.uniform(0.06, 0.1)
        p = base * (1.06 - 0.12 * s / max(n_syl - 1, 1)) * (1.12 if s == stress else 1.0)
        if v == 2 and s == n_syl - 1:
            p *= 1.12  # a little rising, question-like ending
        F0.append((t + cd + 0.5 * vd, p))
        if c == "":
            F_pts.append((t, V))
            AV += [(t, 0.0 if s == 0 else 0.35), (t + 0.02, 1.0)]
        elif c == "h":
            F_pts.append((t, V))
            AV += [(t, 0.0), (t + cd - 0.005, 0.0), (t + cd + 0.02, 1.0)]
            AH += [(t, 0.0), (t + 0.012, 0.3), (t + cd, 0.25), (t + cd + 0.02, 0.0)]
        elif c in ("b", "d", "g"):
            F_pts += [(t, CONS_F[c]), (t + cd, CONS_F[c])]
            AV += [(t, 0.6 if s else 0.0), (t + 0.012, 0.1), (t + cd - 0.004, 0.1), (t + cd + 0.012, 1.0)]
            AF += [(t + cd - 0.006, 0.0), (t + cd - 0.003, 0.5), (t + cd + 0.006, 0.05), (t + cd + 0.012, 0.0)]
        else:  # sonorants
            lvl = {"m": 0.45, "n": 0.45, "l": 0.6, "w": 0.75}[c]
            F_pts += [(t + 0.008, CONS_F[c]), (t + cd - 0.01, CONS_F[c])]
            AV += [(t, 0.6 if s else 0.0), (t + 0.012, lvl), (t + cd - 0.01, lvl), (t + cd + 0.015, 1.0)]
        F_pts += [(t + cd + 0.025, V), (t + cd + vd - 0.01, V)]
        AV.append((t + cd + vd - 0.015, 0.95))
        t += cd + vd
    AV.append((t + 0.035, 0.0))
    end = t + 0.1
    n = ns(end)
    F0 = [(0.0, F0[0][1] * 0.97)] + F0 + [(end, F0[-1][1] * 0.94)]
    F = kf(n, F_pts)
    BW = np.array([np.full(n, b) for b in (90, 110, 170, 260)], float)
    y = formant_voice(rng, n, kf(n, F0)[0], F, BW, kf(n, AV)[0], kf(n, AH)[0], kf(n, AF)[0], tilt=1.1,
                      jitter=0.012, shimmer=0.06, breath=0.1, fric_band=(900, 4000), fric_gain=0.05)
    y = lp(hp(y, 90, 2), 5000, 2)
    y = y + 0.12 * signal.fftconvolve(y, make_ir(rng, 0.3, 0.35, 0.008, 4000, 1500))[:n]
    return fade(y, 0.002, 0.05)


# =============================================================================
# SOUNDS: music (perfectly periodic: circular note placement + circular reverb)
# =============================================================================

def snd_music_calm(rng):
    """LOOP 60 s, D major, 64 bpm: warm pads Imaj7-vi7-IVmaj7-Vsus / Imaj9-iii7-IVmaj7-Vsus-V,
    soft bass, sparse celesta / music-box melody on the pentatonic scale, gentle reverb."""
    bpm = 64.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    L = ns(16 * bar)
    C = True
    chords = [  # (pad voicing MIDI, bass MIDI, bars)
        ([50, 57, 61, 66], 38, 2),  # Dmaj7
        ([47, 54, 57, 62], 35, 2),  # Bm7
        ([50, 55, 59, 66], 43, 2),  # Gmaj7
        ([52, 57, 62, 64], 45, 2),  # Asus4
        ([50, 54, 61, 64], 38, 2),  # Dmaj9
        ([54, 57, 61, 64], 42, 2),  # F#m7
        ([55, 59, 62, 66], 43, 2),  # Gmaj7
        ([52, 57, 62, 64], 45, 1),  # Asus4
        ([52, 57, 61, 64], 45, 1),  # A  -> resolves to Dmaj7 at the loop start
    ]
    pads, bass, bells = np.zeros(L), np.zeros(L), np.zeros(L)
    spans = []
    tp = 0.0
    for voicing, bm, nb in chords:
        dur = nb * bar
        for m in voicing:
            place(pads, pad_note(rng, m, dur + 0.35, attack=1.6, release=2.6, fc=1100), at(tp - 0.35), C)
        place(bass, bass_note(rng, midi_hz(bm), dur), at(tp), C)
        spans.append((tp, tp + dur, voicing))
        tp += dur
    scale = [69, 71, 74, 76, 78, 81, 83, 86]  # D major pentatonic A4..D6
    cells = [[0, 2], [0, 1.5, 3], [0, 3], [1, 2, 3], [0, 0.5, 2], [0], [2, 3], [0, 1, 1.5, 3]]
    weights = np.array([3, 3, 2, 2, 2, 1, 1, 1], float)
    end_cells = [[0], [0, 2], [0, 1.5]]
    idx = 3
    for b in range(16):
        bt = b * bar
        voicing = next(v for s, e, v in spans if s <= bt + 0.01 < e)
        pcs = {m % 12 for m in voicing}
        cell = end_cells[rng.integers(3)] if b % 4 == 3 else cells[rng.choice(len(cells), p=weights / weights.sum())]
        for on in cell:
            idx = int(np.clip(idx + rng.choice([-2, -1, -1, 0, 1, 1, 2]), 0, len(scale) - 1))
            if on in (0, 2):
                cands = [i for i, m in enumerate(scale) if m % 12 in pcs]
                if cands:
                    idx = min(cands, key=lambda i: abs(i - idx) + 0.01 * rng.random())
            when = bt + on * beat + rng.normal(0, 0.012)
            vel = rng.uniform(0.45, 0.75) * (1.1 if on == 0 else 1.0)
            place(bells, bell_note(rng, midi_hz(scale[idx]), vel), at(when), C)
            if on == 0 and idx >= 2 and rng.random() < 0.2:
                place(bells, bell_note(rng, midi_hz(scale[idx - 2]), vel * 0.45), at(when + 0.02), C)
        if rng.random() < 0.3:  # distant high sparkle
            m = 12 + scale[int(rng.integers(3, len(scale)))]
            place(bells, bell_note(rng, midi_hz(m), rng.uniform(0.12, 0.2), 2.0, 1.2), at(bt + rng.choice([0.5, 1.5, 2.5, 3.5]) * beat), C)
    d = at(1.5 * beat)
    bells = bells + 0.28 * np.roll(bells, d) + 0.1 * np.roll(bells, 2 * d)  # music-box echo (circular)
    pads, bass, bells = nrms(pads), nrms(bass, 0.3), nrm(bells, 3.0)
    wet = conv(0.55 * pads + 0.9 * bells + 0.1 * bass, make_ir(rng, 3.2, 3.5, 0.025), C)
    return hp(0.8 * pads + bass + 0.75 * bells + 0.55 * wet, 30, 2, C)


def snd_music_snow(rng):
    """LOOP ~68.6 s, E Dorian, 56 bpm: airy modal pads (Em9-Aadd9-Gmaj7-Bm7 / Em9-Dmaj9-F#m7-Asus2)
    with breathy 'air' chords and slow swells, sparse distant piano with echo, faint high sparkle."""
    bpm = 56.0
    beat = 60.0 / bpm
    bar = 4.0 * beat
    L = ns(16 * bar)
    C = True
    t = tvec(L)
    chords = [
        ([52, 55, 59, 62, 66], 40),  # Em9
        ([52, 57, 59, 61, 64], 45),  # Aadd9 (the Dorian IV)
        ([50, 55, 59, 62, 66], 43),  # Gmaj7
        ([50, 54, 57, 59, 64], 35),  # Bm7(11)
        ([52, 59, 62, 66, 71], 40),  # Em9 open
        ([50, 54, 57, 61, 64], 38),  # Dmaj9
        ([54, 57, 61, 64, 69], 42),  # F#m7
        ([52, 57, 59, 64, 71], 45),  # Asus2 -> back to Em9
    ]
    pads, air, bass = np.zeros(L), np.zeros(L), np.zeros(L)
    spans = []
    for i, (voicing, bm) in enumerate(chords):
        tp = i * 2 * bar
        dur = 2 * bar
        for m in voicing:
            place(pads, pad_note(rng, m, dur + 0.6, attack=2.6, release=3.5, fc=800, detune=11, tri=0.3), at(tp - 0.6), C)
        place(air, air_chord(rng, voicing, dur + 0.8, 3.0, 4.0), at(tp - 0.8), C)
        place(bass, bass_note(rng, midi_hz(bm), bar * 1.5, 2.0), at(tp), C)
        spans.append((tp, tp + dur, voicing))
    swell = 0.75 + 0.25 * np.sin(TWO_PI * qf(1.0 / (2 * bar), L) * t - 0.5 * np.pi)
    pads *= swell
    air *= np.roll(swell, at(bar * 0.5))
    piano = np.zeros(L)
    scale = [64, 67, 69, 71, 74, 76, 79, 81, 83]  # E G A B D (E4..B5)
    color = [66, 73, 78]  # F#, C# (Dorian colour)
    grid = np.arange(0, 4, 0.5)
    idx = 4
    for b in range(16):
        bt = b * bar
        voicing = next(v for s, e, v in spans if s <= bt + 0.01 < e)
        pcs = {m % 12 for m in voicing}
        if b % 2 == 0:  # low note at the chord change
            place(piano, piano_note(rng, midi_hz(voicing[0]), 0.35, 5.0), at(bt + rng.normal(0, 0.01)), C)
        k = int(rng.choice([1, 2, 2, 3])) if b % 4 != 3 else 1
        for on in np.sort(rng.choice(grid, k, replace=False)):
            if rng.random() < 0.12:
                m = int(rng.choice(color))
            else:
                idx = int(np.clip(idx + rng.choice([-2, -1, 0, 1, 2]), 0, len(scale) - 1))
                if on in (0.0, 2.0):
                    cands = [i for i, mm in enumerate(scale) if mm % 12 in pcs]
                    if cands:
                        idx = min(cands, key=lambda i: abs(i - idx) + 0.01 * rng.random())
                m = scale[idx]
            vel = rng.uniform(0.35, 0.6)
            place(piano, piano_note(rng, midi_hz(m), vel, 4.5), at(bt + on * beat + rng.normal(0, 0.015)), C)
            if rng.random() < 0.15:  # soft fifth below
                place(piano, piano_note(rng, midi_hz(m - 7), vel * 0.5, 4.0), at(bt + on * beat + 0.03), C)
    d = at(0.75 * beat)
    piano = piano + 0.35 * np.roll(piano, d) + 0.15 * np.roll(piano, 2 * d) + 0.06 * np.roll(piano, 3 * d)
    piano = lp(piano, 3200, 2, C)  # distant
    sparkle = np.zeros(L)
    for _ in range(10):
        m = 24 + scale[int(rng.integers(0, len(scale)))]
        place(sparkle, bell_note(rng, midi_hz(m), rng.uniform(0.05, 0.1), 2.0, 1.0, SOFT_BELL), rng.integers(0, L), C)
    pads, air, bass, piano = nrms(pads), nrms(air, 0.45), nrms(bass, 0.22), nrm(piano, 2.6)
    sparkle = nrm(sparkle, 0.6)
    wet = conv(0.6 * pads + 0.6 * air + piano + 0.8 * sparkle, make_ir(rng, 4.5, 5.0, 0.04), C)
    return hp(0.7 * pads + 0.5 * air + bass + 0.45 * piano + 0.3 * sparkle + 0.75 * wet, 30, 2, C)


# =============================================================================
# Registry
# =============================================================================

def oneshot(name, fn, peak_db=ONESHOT_PEAK_DB):
    return (name, fn, False, peak_db)


def loop(name, fn, rms_db):
    return (name, fn, True, rms_db)


SOUNDS = [
    # --- snow / tools -------------------------------------------------------
    # variant sets are loudness-matched (('loud', dB)) so no variant jumps out
    *[oneshot(f"step_snow_{i}", lambda r, i=i: snd_step_snow(r, i), ("loud", -16.0)) for i in range(1, 5)],
    *[oneshot(f"step_deep_{i}", lambda r, i=i: snd_step_deep(r, i), ("loud", -17.0)) for i in range(1, 4)],
    *[oneshot(f"step_hard_{i}", lambda r, i=i: snd_step_hard(r, i), ("loud", -17.0)) for i in range(1, 4)],
    oneshot("hand_dig", snd_hand_dig),
    *[oneshot(f"hand_scoop_{i}", lambda r, i=i: snd_hand_scoop(r, i), ("loud", -18.0)) for i in range(1, 4)],
    *[oneshot(f"shovel_fill_{i}", lambda r, i=i: snd_shovel_fill(r, i), ("loud", -17.0)) for i in range(1, 4)],
    oneshot("hand_toss", snd_hand_toss),
    loop("push_snow", snd_push_snow, -19.0),
    oneshot("box_complete", snd_box_complete, -5.0),
    oneshot("shovel_scoop", snd_shovel_scoop),
    oneshot("shovel_scrape", snd_shovel_scrape),
    oneshot("shovel_throw", snd_shovel_throw),
    oneshot("snow_land", lambda r: snd_snow_land(r, 0), ("loud", -16.5)),
    *[oneshot(f"snow_land_{i}", lambda r, i=i: snd_snow_land(r, i), ("loud", -16.5)) for i in range(1, 4)],
    oneshot("snow_land_big", snd_snow_land_big),
    loop("push_scrape", snd_push_scrape, -17.0),
    loop("plow_scrape", snd_plow_scrape, -17.0),
    loop("electric_motor", snd_electric_motor, -18.0),
    loop("blower_small", snd_blower_small, -17.0),
    loop("blower_large", snd_blower_large, -17.0),
    loop("blower_discharge", snd_blower_discharge, -18.0),
    loop("engine_truck", snd_engine_truck, -17.0),
    loop("engine_diesel", snd_engine_diesel, -17.0),
    loop("engine_small", snd_engine_small, -17.0),
    loop("tires_snow", snd_tires_snow, -18.0),
    oneshot("engine_start", snd_engine_start),
    oneshot("horn", snd_horn),
    # --- weather / ambience -------------------------------------------------
    loop("wind_light", snd_wind_light, -20.0),
    loop("wind_strong", snd_wind_strong, -18.0),
    loop("blizzard", snd_blizzard, -17.0),
    loop("fire_crackle", snd_fire_crackle, -20.0),
    loop("furnace_hum", snd_furnace_hum, -22.0),
    loop("room_tone", snd_room_tone, -28.0),
    loop("shiver", snd_shiver, -19.0),
    loop("heartbeat", snd_heartbeat, -16.0),
    oneshot("gust_whistle", snd_gust_whistle),
    oneshot("rattle", snd_rattle),
    # --- UI / interaction ---------------------------------------------------
    oneshot("ui_click", snd_ui_click),
    oneshot("ui_hover", snd_ui_hover, -16.0),
    # sustained tonal UI sounds sit a little lower so they match the clicks in loudness
    oneshot("ui_error", snd_ui_error, -6.0),
    oneshot("ui_money", snd_ui_money, -4.0),
    oneshot("ui_notify", snd_ui_notify, -5.0),
    oneshot("ui_alert", snd_ui_alert, -4.0),
    oneshot("pickup_item", snd_pickup_item),
    oneshot("paper", snd_paper),
    oneshot("mailbox", snd_mailbox),
    oneshot("door_open", snd_door_open),
    oneshot("door_close", snd_door_close),
    oneshot("keys_jingle", snd_keys_jingle),
    oneshot("truck_locked", snd_truck_locked),
    oneshot("radio_jingle", snd_radio_jingle),
    oneshot("power_off", snd_power_off),
    oneshot("power_on", snd_power_on),
    oneshot("death_sting", snd_death_sting),
    # --- voices -------------------------------------------------------------
    oneshot("help_call", snd_help_call),
    *[oneshot(f"neighbor_talk_{i}", lambda r, i=i: snd_neighbor_talk(r, i)) for i in range(1, 4)],
    # --- music --------------------------------------------------------------
    loop("music_calm", snd_music_calm, -20.0),
    loop("music_snow", snd_music_snow, -20.0),
]


# =============================================================================
# Output, normalization and verification
# =============================================================================

def active_loudness(x) -> float:
    """Loudness proxy for short transients: RMS (above 150 Hz) over the part of the sound that is
    within 10 dB of its loudest 10 ms. Used to level-match variants (footsteps, landings)."""
    h = hp(x, 150, 2)
    e = smooth(h * h, 10)
    m = e > 0.1 * e.max()
    return float(np.sqrt(e[m].mean()))


def ceiling(x, ceil_lin: float) -> np.ndarray:
    """Soft-knee peak limiter (memoryless): linear below half the ceiling, tanh knee above it."""
    p = peak(x)
    if p <= ceil_lin:
        return x
    k = 0.5 * ceil_lin
    a = np.abs(x)
    y = np.where(a <= k, a, k + (ceil_lin - k) * np.tanh((a - k) / (ceil_lin - k)))
    return np.sign(x) * y * (ceil_lin / max(y.max(), 1e-12))


def finalize(x, is_loop: bool, level) -> np.ndarray:
    """Loops: remove DC (keeps periodicity), RMS-normalize to `level` dB but never peak above
    LOOP_PEAK_CAP_DB. One-shots: DC-block, click-free fades, then either peak-normalize to `level`
    dBFS, or for level=('loud', dB) match the active loudness and soft-limit at ONESHOT_PEAK_DB."""
    x = np.nan_to_num(np.asarray(x, float))
    if is_loop:
        x = x - x.mean()
        g = min(undb(level) / max(rms(x), 1e-12), undb(LOOP_PEAK_CAP_DB) / max(peak(x), 1e-12))
        return x * g
    x = fade(hp(x, 20, 2), 0.0008, 0.012)
    if isinstance(level, tuple):
        x = x * (undb(level[1]) / max(active_loudness(x), 1e-12))
        return ceiling(x, undb(ONESHOT_PEAK_DB))
    return x * (undb(level) / max(peak(x), 1e-12))


def write_wav(path: Path, x: np.ndarray) -> None:
    q = np.clip(np.round(x * 32767.0), -32768, 32767).astype(np.int16)
    wavfile.write(str(path), SR, q)


def analyze(path: Path, is_loop: bool) -> dict:
    """Re-read the written file and check format, level, clipping, seams/edges."""
    sr, d = wavfile.read(str(path))
    x = d.astype(np.float64) / 32768.0
    res = {"dur": len(x) / sr, "peak": dbfs(peak(x)), "rms": dbfs(rms(x)), "seam": None, "issues": []}
    if sr != SR or d.dtype != np.int16 or d.ndim != 1:
        res["issues"].append("format")
    if res["rms"] < -60.0 or res["peak"] < -40.0:
        res["issues"].append("silent")
    if res["peak"] > -1.0:
        res["issues"].append("peak>-1dB")
    if is_loop:
        # 1) sample jump across the seam vs. the signal's own largest sample-to-sample steps
        jump = abs(x[0] - x[-1])
        ref = np.percentile(np.abs(np.diff(x)), 99.9) + 1e-9
        # 2) high-frequency click energy in a window centred on the seam vs. the same window
        #    size anywhere else in the (rotated) file
        r = np.roll(x, len(x) // 2)
        h = hp(r, 3000, 4) ** 2
        w = 64
        energies = np.add.reduceat(h, np.arange(0, len(h) - w, w))
        c = len(x) - len(x) // 2
        seam_e = h[c - w // 2:c + w // 2].sum()
        hf_ratio = seam_e / (np.percentile(energies, 99) + 1e-15)
        res["seam"] = (jump / ref, hf_ratio)
        if jump / ref > 1.0 or hf_ratio > 1.5:
            res["issues"].append("seam")
        # the game sets loop_end = int(get_length() * mix_rate); make sure that is the full file
        if int((len(x) / sr) * sr) != len(x):
            res["issues"].append("loop_end_rounding")
    else:
        if abs(x[0]) > 0.01 or abs(x[-1]) > 0.01:
            res["issues"].append("edge")
    return res


def main(argv) -> int:
    filters = argv[1:]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    t_all = time.time()
    rows = []
    for name, fn, is_loop, level in SOUNDS:
        if filters and not any(f in name for f in filters):
            continue
        t0 = time.time()
        x = finalize(fn(rng_for(name)), is_loop, level)
        path = OUT_DIR / f"{name}.wav"
        write_wav(path, x)
        res = analyze(path, is_loop)
        res.update(name=name, loop=is_loop, secs=time.time() - t0, size=path.stat().st_size)
        rows.append(res)
        print(f"  rendered {name:<18} {res['dur']:6.2f} s  ({res['secs']:.2f} s)", flush=True)

    print()
    print(f"{'name':<18} {'type':<5} {'dur s':>7} {'peak dBFS':>10} {'RMS dBFS':>9} {'seam jump/hf':>14}  status")
    print("-" * 78)
    bad = 0
    for r in rows:
        seam = f"{r['seam'][0]:.2f}/{r['seam'][1]:.2f}" if r["seam"] else "-"
        status = "OK" if not r["issues"] else "FAIL " + ",".join(r["issues"])
        bad += bool(r["issues"])
        print(f"{r['name']:<18} {'loop' if r['loop'] else 'shot':<5} {r['dur']:7.2f} {r['peak']:10.2f} {r['rms']:9.2f} {seam:>14}  {status}")
    total = sum(p.stat().st_size for p in OUT_DIR.glob("*.wav"))
    missing = [s[0] for s in SOUNDS if not (OUT_DIR / f"{s[0]}.wav").exists()]
    print("-" * 78)
    print(f"{len(rows)} files rendered in {time.time() - t_all:.1f} s; assets/audio total {total / 1e6:.2f} MB; "
          f"missing: {missing if missing else 'none'}; problems: {bad}")
    return 1 if (bad or missing) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
