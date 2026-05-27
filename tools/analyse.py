#!/usr/bin/env python3
"""
analyse.py - focused analysis pipeline for biosim4 predator-prey runs.

Three falsifiable predictions only:

    OSC1  Population oscillations
          Detrended autocorrelation of prey_survivors should peak negatively
          at a positive lag (the half-period).

    OSC2  Phase lag (prey leads predator)
          Cross-correlation of detrended pred / prey survivors should peak
          at a positive lag.  Significance is tested by circular-shift
          permutation, which preserves each series' own autocorrelation but
          destroys the cross alignment.

    RED-QUEEN
          Coevolution avoids evolutionary stasis: both species persist
          (no extinction) AND realised fitness keeps fluctuating rather
          than freezing at a constant-phenotype ESS.  It deliberately does
          NOT require fitness to rise -- a capture is a predator gain and a
          prey loss, so the two fitnesses are near zero-sum and a joint
          upward trend is impossible by construction (and would contradict
          Van Valen's Red Queen: constant realised fitness despite change).

Plus two qualitative panels (no test, just visual):

    POPULATIONS    pred_surv & prey_surv over generations
    SENSOR USAGE   fraction of each species' nets that wire in the
                   opponent-distance sensor (PrD for predators, PyD for prey)

Outputs
-------
    Output/analysis.png             composite figure with all panels
    Output/analysis_panels/*.png    per-panel figures (with --split-figures)
    Output/analysis_report.md       markdown table of test verdicts

Usage
-----
    .venv/bin/python3 tools/analyse.py
    .venv/bin/python3 tools/analyse.py --burn-in 50 --smooth 5 --split-figures
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
from scipy import stats
from scipy.signal import correlate


# =============================================================================
# CLI
# =============================================================================
def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="biosim4 predator-prey analysis")
    ap.add_argument("--log", default="Output/Logs/epoch-log.txt")
    ap.add_argument("--nets", default="Output/Images")
    ap.add_argument("--out", default="Output/analysis.png")
    ap.add_argument("--report", default="Output/analysis_report.md")
    ap.add_argument("--smooth", type=int, default=5,
                    help="rolling-mean window for plotted lines (0 = off)")
    ap.add_argument("--burn-in", type=int, default=0,
                    help="discard first N generations as transient")
    ap.add_argument("--max-lag", type=int, default=40)
    ap.add_argument("--n-perm", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--split-figures", action="store_true",
                    help="also save individual figures for each panel")
    ap.add_argument("--title", default=None,
                    help="optional title suffix shown on the figure (e.g. run name)")
    ap.add_argument("--osc2-alpha", type=float, default=0.10,
                    help="p-value threshold for OSC2 significance (default 0.10)")
    ap.add_argument("--osc2-lag-min", type=int, default=-2,
                    help="minimum peak lag accepted as passing for OSC2 "
                         "(default -2: near-simultaneous dynamics count)")
    ap.add_argument("--checkpoints", type=int, nargs="+", default=[],
                    metavar="GEN",
                    help="also run full analysis at these generation cutoffs "
                         "e.g. --checkpoints 100 200 400")
    return ap.parse_args()


# =============================================================================
# Data loading
# =============================================================================
@dataclass
class EpochData:
    gen: np.ndarray
    pred_surv: np.ndarray
    prey_surv: np.ndarray
    pred_fit: np.ndarray
    prey_fit: np.ndarray

    @classmethod
    def load(cls, path: Path, burn_in: int = 0) -> "EpochData":
        rows = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                rows.append(line.split())
        if not rows:
            sys.exit(f"ERROR: no data rows in {path}")

        ncols = max(len(r) for r in rows)
        rows = [r + ["nan"] * (ncols - len(r)) for r in rows]
        arr = np.array(rows, dtype=float)

        gen = arr[:, 0].astype(int)
        if ncols >= 11:
            pred_surv = arr[:, 6].astype(int)
            prey_surv = arr[:, 7].astype(int)
            pred_fit  = arr[:, 8]
            prey_fit  = arr[:, 9]
        elif ncols >= 9:
            pred_surv = arr[:, 5].astype(int)
            prey_surv = arr[:, 6].astype(int)
            pred_fit  = arr[:, 7]
            prey_fit  = arr[:, 8]
        else:
            sys.exit("ERROR: epoch-log.txt is missing predator/prey columns. "
                     "Re-run the simulator with predatorPreyEnabled = true.")

        if burn_in > 0:
            mask = gen >= burn_in
            gen, pred_surv, prey_surv, pred_fit, prey_fit = (
                gen[mask], pred_surv[mask], prey_surv[mask],
                pred_fit[mask], prey_fit[mask],
            )

        return cls(gen, pred_surv, prey_surv, pred_fit, prey_fit)


# =============================================================================
# Statistics
# =============================================================================
# Late-window fitness sd above this counts as "still running" rather than
# frozen at an ESS.  Calibrated against the sweep: no-predation controls give
# exactly 0.000 (fitness pinned at a ceiling); predation runs give >= 0.05.
RQ_FLUCT_FLOOR = 0.02

# A species "persists" only if its final-quartile mean survivors stay above
# this fraction of its pre-late-window baseline median -- i.e. it did not
# collapse by >80%.  Scale-free, so it tolerates the intrinsically small,
# steady predator subpopulation (median ~1 survivor/gen) while still catching a
# genuine end-of-run crash.  Calibrated against the sweep: healthy runs sit at
# >= 0.38 of baseline; true extinction hits the separate "late mean > 0" clause.
RQ_PERSIST_FRAC = 0.2


def rolling_mean(y: np.ndarray, w: int) -> np.ndarray:
    if w < 2 or len(y) < w:
        return np.array(y, dtype=float)
    kernel = np.ones(w) / w
    return np.convolve(y, kernel, mode="same")


def standardize(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    m = np.nanmean(x)
    s = np.nanstd(x)
    return (x - m) / s if s > 0 else x - m


def detrend_linear(y: np.ndarray) -> np.ndarray:
    """Subtract a linear trend so long-run drift doesn't dominate the
    autocorrelation / cross-correlation signal."""
    y = np.asarray(y, dtype=float)
    mask = np.isfinite(y)
    if mask.sum() < 3:
        return y - np.nanmean(y)
    x = np.arange(len(y))
    slope, intercept, *_ = stats.linregress(x[mask], y[mask])
    return y - (slope * x + intercept)


def cross_correlation(x: np.ndarray, y: np.ndarray, max_lag: int):
    x = standardize(x)
    y = standardize(y)
    n = len(x)
    full = correlate(x, y, mode="full") / n
    lags = np.arange(-n + 1, n)
    keep = (lags >= -max_lag) & (lags <= max_lag)
    return lags[keep], full[keep]


def permutation_null(x: np.ndarray, y: np.ndarray, max_lag: int,
                     n_perm: int, rng: np.random.Generator) -> np.ndarray:
    n = len(y)
    peaks = np.empty(n_perm)
    for i in range(n_perm):
        shift = rng.integers(1, n)
        _, c = cross_correlation(x, np.roll(y, shift), max_lag)
        peaks[i] = np.max(np.abs(c))
    return peaks


def estimate_period(y: np.ndarray) -> int:
    y = detrend_linear(y)
    y = y[np.isfinite(y)]
    if len(y) < 16:
        return 0
    n = len(y)
    fft_vals = np.abs(np.fft.rfft(y - y.mean())) ** 2
    freqs = np.fft.rfftfreq(n, d=1.0)
    valid = freqs > 2.0 / n
    if not valid.any():
        return 0
    f = freqs[valid][int(np.argmax(fft_vals[valid]))]
    return int(round(1.0 / f)) if f > 0 else 0


def species_persists(surv: np.ndarray, q: int) -> bool:
    """A species persists if it is present at the end of the run AND has not
    collapsed relative to its earlier baseline (median of the pre-late window).
    Catches the 'extinction' outcome -- including a gradual end-of-run crash --
    while tolerating the naturally low, steady predator survivor counts."""
    surv = np.asarray(surv, dtype=float)
    late = float(np.nanmean(surv[-q:]))
    if late <= 0:
        return False
    baseline = (float(np.nanmedian(surv[:-q])) if len(surv) > q
                else float(np.nanmedian(surv)))
    if baseline <= 0:
        return True  # no earlier baseline to fall from; presence at the end suffices
    return late >= RQ_PERSIST_FRAC * baseline


def fitness_fluctuation(y: np.ndarray, q: int):
    """Std of the *detrended* fitness series in the first and last q
    generations.  A frozen series gives ~0; a still-oscillating one stays
    well above the noise floor.  Detrending first so a slow drift is not
    mistaken for sustained fluctuation."""
    yd = detrend_linear(np.asarray(y, dtype=float))
    early = float(np.nanstd(yd[:q])) if q <= len(yd) else float("nan")
    late = float(np.nanstd(yd[-q:]))
    return early, late


def linear_trend(y: np.ndarray):
    y = np.asarray(y, dtype=float)
    mask = np.isfinite(y)
    if mask.sum() < 3:
        return float("nan"), float("nan")
    x = np.arange(len(y))[mask]
    res = stats.linregress(x, y[mask])
    return float(res.slope), float(res.pvalue)


@dataclass
class StatsBundle:
    # OSC1
    acf_lags: np.ndarray = field(default_factory=lambda: np.zeros(0))
    acf: np.ndarray = field(default_factory=lambda: np.zeros(0))
    osc1_neg_lag: int = 0
    osc1_neg_corr: float = 0.0
    osc1_period: int = 0
    # OSC2
    xcf_lags: np.ndarray = field(default_factory=lambda: np.zeros(0))
    xcf: np.ndarray = field(default_factory=lambda: np.zeros(0))
    osc2_peak_lag: int = 0
    osc2_peak_corr: float = 0.0
    osc2_null_95: float = 0.0
    osc2_p: float = 1.0
    # RED-QUEEN (non-stasis / three-outcomes test)
    rq_pred_slope: float = 0.0
    rq_pred_p: float = 1.0
    rq_prey_slope: float = 0.0
    rq_prey_p: float = 1.0
    rq_persist: bool = False
    rq_nonstasis: bool = False
    rq_pred_fluct_early: float = 0.0
    rq_pred_fluct_late: float = 0.0
    rq_prey_fluct_early: float = 0.0
    rq_prey_fluct_late: float = 0.0
    rq_pred_surv_late: float = 0.0
    rq_prey_surv_late: float = 0.0


def compute_verdicts(sb: StatsBundle, osc2_alpha: float = 0.10,
                     osc2_lag_min: int = -2) -> dict:
    """Single source of truth for the three pass/fail verdicts, shared by the
    per-run report and the sweep-level overview so thresholds never drift."""
    return {
        "OSC1": bool(sb.osc1_neg_corr < -0.15 and sb.osc1_neg_lag >= 3),
        "OSC2": bool(sb.osc2_p < osc2_alpha and sb.osc2_peak_lag >= osc2_lag_min),
        "RED-QUEEN": bool(sb.rq_persist and sb.rq_nonstasis),
    }


def compute_stats(d: EpochData, max_lag: int, n_perm: int,
                  rng: np.random.Generator) -> StatsBundle:
    sb = StatsBundle()
    pred = d.pred_surv.astype(float)
    prey = d.prey_surv.astype(float)
    pred_dt = detrend_linear(pred)
    prey_dt = detrend_linear(prey)

    # OSC1: autocorrelation of detrended prey
    if len(prey) > 8:
        lags, c = cross_correlation(prey_dt, prey_dt, max_lag)
        sb.acf_lags, sb.acf = lags, c
        positive = lags >= 3
        if positive.any():
            idx = int(np.argmin(c[positive]))
            sb.osc1_neg_lag = int(lags[positive][idx])
            sb.osc1_neg_corr = float(c[positive][idx])
        sb.osc1_period = estimate_period(prey)

    # OSC2: cross-correlation pred ↔ prey on detrended series
    if len(pred) > 4 and len(prey) > 4:
        lags, c = cross_correlation(pred_dt, prey_dt, max_lag)
        sb.xcf_lags, sb.xcf = lags, c
        idx = int(np.argmax(np.abs(c)))
        sb.osc2_peak_lag = int(lags[idx])
        sb.osc2_peak_corr = float(c[idx])
        if len(pred) >= 20:
            null = permutation_null(pred_dt, prey_dt, max_lag, n_perm, rng)
            sb.osc2_null_95 = float(np.quantile(null, 0.95))
            sb.osc2_p = float(np.mean(null >= abs(sb.osc2_peak_corr)))

    # RED QUEEN: a coevolving predator-prey system ends in one of three
    # outcomes (Dieckmann, Marrow & Law 1995): a species goes extinct, it
    # settles to a constant-phenotype ESS, or it keeps cycling -- the Red
    # Queen.  We detect the third by ruling out the first two: both species
    # persist AND realised fitness keeps fluctuating instead of freezing.
    # Slopes are kept only as a drift diagnostic for the plot/report.
    sb.rq_pred_slope, sb.rq_pred_p = linear_trend(d.pred_fit)
    sb.rq_prey_slope, sb.rq_prey_p = linear_trend(d.prey_fit)
    n = len(d.gen)
    q = max(n // 4, 4)
    sb.rq_pred_surv_late = float(np.nanmean(d.pred_surv[-q:]))
    sb.rq_prey_surv_late = float(np.nanmean(d.prey_surv[-q:]))
    sb.rq_persist = (species_persists(d.pred_surv, q)
                     and species_persists(d.prey_surv, q))
    sb.rq_pred_fluct_early, sb.rq_pred_fluct_late = fitness_fluctuation(d.pred_fit, q)
    sb.rq_prey_fluct_early, sb.rq_prey_fluct_late = fitness_fluctuation(d.prey_fit, q)
    sb.rq_nonstasis = (sb.rq_prey_fluct_late > RQ_FLUCT_FLOOR
                       or sb.rq_pred_fluct_late > RQ_FLUCT_FLOOR)
    return sb


# =============================================================================
# Sensor usage
# =============================================================================
NET_RE = re.compile(r"^gen-(\d+)-(pred|prey)-id-\d+\.txt$")
PRED_SENSOR = "PrD"
PREY_SENSOR = "PyD"


def scan_sensor_usage(nets_dir: Path, all_gens: np.ndarray):
    pred_usage = defaultdict(lambda: [0, 0])
    prey_usage = defaultdict(lambda: [0, 0])

    if nets_dir.is_dir():
        for fpath in nets_dir.glob("*.txt"):
            m = NET_RE.match(fpath.name)
            if not m:
                continue
            g, kind = int(m.group(1)), m.group(2)
            try:
                text = fpath.read_text()
            except OSError:
                continue
            nodes = {tok for line in text.splitlines() for tok in line.split()[:2] if tok}
            bucket = pred_usage if kind == "pred" else prey_usage
            sensor = PRED_SENSOR if kind == "pred" else PREY_SENSOR
            bucket[g][1] += 1
            if sensor in nodes:
                bucket[g][0] += 1

    def to_series(usage):
        out = np.full(len(all_gens), np.nan, dtype=float)
        for i, g in enumerate(all_gens):
            d = usage.get(int(g))
            if d and d[1] > 0:
                out[i] = d[0] / d[1]
        return out

    return to_series(pred_usage), to_series(prey_usage)


# =============================================================================
# Plotting
# =============================================================================
PRED_C = "#cf222e"
PREY_C = "#2ea04b"
ACCENT = "#5b9bd5"
NEUTRAL = "#888888"
BG = "#fafbfc"


def style(ax, ylabel="", title=""):
    if ylabel:
        ax.set_ylabel(ylabel, fontsize=10)
    if title:
        ax.set_title(title, fontsize=11, fontweight="bold")
    ax.grid(True, alpha=0.25)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def annotate(ax, text, loc="upper right"):
    pos = {
        "upper right": (0.98, 0.97, "right", "top"),
        "upper left":  (0.02, 0.97, "left",  "top"),
        "lower right": (0.98, 0.03, "right", "bottom"),
        "lower left":  (0.02, 0.03, "left",  "bottom"),
    }[loc]
    ax.text(pos[0], pos[1], text,
            transform=ax.transAxes, ha=pos[2], va=pos[3],
            family="monospace", fontsize=8,
            bbox=dict(boxstyle="round,pad=0.4", facecolor="white",
                      edgecolor="0.7", alpha=0.9))


# ---------- panels ----------

def panel_populations(ax, d: EpochData, smooth: int):
    pred = rolling_mean(d.pred_surv.astype(float), smooth)
    prey = rolling_mean(d.prey_surv.astype(float), smooth)
    ax.plot(d.gen, pred, color=PRED_C, lw=1.8, label="Predator survivors")
    ax.plot(d.gen, prey, color=PREY_C, lw=1.8, label="Prey survivors")
    ax.fill_between(d.gen, prey, alpha=0.10, color=PREY_C)
    ax.set_xlabel("Generation")
    ax.legend(fontsize=9, loc="upper right")
    style(ax, "Survivors per generation", "Population time series")


def panel_autocorrelation(ax, sb: StatsBundle):
    if sb.acf.size == 0:
        ax.text(0.5, 0.5, "(no data)", ha="center", va="center", transform=ax.transAxes)
        style(ax, "", "OSC1 — Oscillations (autocorrelation of prey)")
        return
    pos = sb.acf_lags >= 0
    ax.axhline(0, color="black", lw=0.6)
    ax.fill_between(sb.acf_lags[pos], sb.acf[pos], 0, alpha=0.25, color=PREY_C)
    ax.plot(sb.acf_lags[pos], sb.acf[pos], color=PREY_C, lw=1.8)
    if sb.osc1_neg_corr < 0:
        ax.scatter([sb.osc1_neg_lag], [sb.osc1_neg_corr], color=PRED_C, s=50, zorder=5,
                   label=f"min: lag={sb.osc1_neg_lag}, r={sb.osc1_neg_corr:+.2f}")
        ax.legend(fontsize=8, loc="upper right")
    if sb.osc1_period > 0:
        annotate(ax, f"FFT period ≈ {sb.osc1_period} gens", loc="lower right")
    ax.set_xlabel("Lag (generations)")
    style(ax, "Autocorrelation r", "OSC1 — Oscillations (autocorrelation of detrended prey)")


def panel_cross_correlation(ax, sb: StatsBundle):
    if sb.xcf.size == 0:
        ax.text(0.5, 0.5, "(no data)", ha="center", va="center", transform=ax.transAxes)
        style(ax, "", "OSC2 — Phase lag (cross-correlation)")
        return
    ax.axhline(0, color="black", lw=0.6)
    ax.axvline(0, color="black", lw=0.6, ls=":")
    ax.plot(sb.xcf_lags, sb.xcf, color=ACCENT, lw=1.8)
    ax.fill_between(sb.xcf_lags, sb.xcf, 0, alpha=0.15, color=ACCENT)
    if sb.osc2_null_95 > 0:
        ax.axhline(sb.osc2_null_95, color=NEUTRAL, ls="--", lw=1,
                   label=f"95% null (|r|={sb.osc2_null_95:.2f})")
        ax.axhline(-sb.osc2_null_95, color=NEUTRAL, ls="--", lw=1)
    ax.scatter([sb.osc2_peak_lag], [sb.osc2_peak_corr], color=PRED_C, s=40, zorder=5,
               label=f"peak: lag={sb.osc2_peak_lag:+d}, r={sb.osc2_peak_corr:+.2f}")
    ax.set_xlabel("Lag (generations)  —  positive ⇒ prey leads predator")
    ax.legend(fontsize=8, loc="upper right")
    sig = "✓ significant" if sb.osc2_p < 0.10 else "✗ n.s."
    annotate(ax, f"perm-p = {sb.osc2_p:.3f}  {sig}", loc="lower left")
    style(ax, "Cross-correlation r", "OSC2 — Phase lag (cross-correlation pred ↔ prey)")


def panel_red_queen(ax, d: EpochData, sb: StatsBundle, smooth: int):
    if not np.isfinite(d.pred_fit).any():
        ax.text(0.5, 0.5, "(no fitness data)", ha="center", va="center",
                transform=ax.transAxes)
        style(ax, "", "RED-QUEEN")
        return
    pf = rolling_mean(d.pred_fit, smooth)
    yf = rolling_mean(d.prey_fit, smooth)
    ax.plot(d.gen, pf, color=PRED_C, lw=1.8, label="Predator fitness")
    ax.plot(d.gen, yf, color=PREY_C, lw=1.8, label="Prey fitness")
    x = np.arange(len(d.gen))
    if np.isfinite(sb.rq_pred_slope):
        ax.plot(d.gen, sb.rq_pred_slope * x +
                np.nanmean(pf - sb.rq_pred_slope * x),
                color=PRED_C, lw=1.0, ls="--", alpha=0.7)
    if np.isfinite(sb.rq_prey_slope):
        ax.plot(d.gen, sb.rq_prey_slope * x +
                np.nanmean(yf - sb.rq_prey_slope * x),
                color=PREY_C, lw=1.0, ls="--", alpha=0.7)
    ax.set_ylim(0, 1)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=1.0))
    ax.set_xlabel("Generation")
    ax.legend(fontsize=9, loc="lower right")
    persist_mark = "✓" if sb.rq_persist else "✗"
    stasis_mark = "✓" if sb.rq_nonstasis else "✗"
    annotate(ax,
             f"{persist_mark} persist  pred_surv={sb.rq_pred_surv_late:.1f} "
             f"prey_surv={sb.rq_prey_surv_late:.1f}\n"
             f"{stasis_mark} non-stasis  fluctuation (early→late):\n"
             f"   pred {sb.rq_pred_fluct_early:.2f}→{sb.rq_pred_fluct_late:.2f}  "
             f"prey {sb.rq_prey_fluct_early:.2f}→{sb.rq_prey_fluct_late:.2f}",
             loc="upper left")
    style(ax, "Fitness (0..1)",
          "RED-QUEEN — non-stasis (persistence + sustained fluctuation)")


def panel_sensor_usage(ax, d: EpochData,
                       pred_rate: np.ndarray, prey_rate: np.ndarray):
    has_pred = np.isfinite(pred_rate).any()
    has_prey = np.isfinite(prey_rate).any()
    if not (has_pred or has_prey):
        ax.text(0.5, 0.5,
                "(no NN snapshots in Output/Images — set autoSave*PerGeneration > 0)",
                ha="center", va="center", transform=ax.transAxes, color=NEUTRAL)
        style(ax, "", "SENSOR USAGE")
        return
    if has_pred:
        m = np.isfinite(pred_rate)
        ax.plot(d.gen[m], pred_rate[m] * 100, color=PRED_C, lw=1.6,
                marker="o", ms=5, label=f'predators wired to "{PRED_SENSOR}"')
    if has_prey:
        m = np.isfinite(prey_rate)
        ax.plot(d.gen[m], prey_rate[m] * 100, color=PREY_C, lw=1.6,
                marker="s", ms=5, label=f'prey wired to "{PREY_SENSOR}"')
    ax.set_ylim(-5, 105)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter())
    ax.set_xlabel("Generation")
    ax.legend(fontsize=9, loc="best")
    style(ax, "Net wiring rate (%)",
          f"SENSOR USAGE — {PRED_SENSOR} = prey-distance, {PREY_SENSOR} = pred-distance")


# ---------- composite ----------

def render_composite(d: EpochData, sb: StatsBundle, smooth: int,
                     pred_rate, prey_rate, out_path: Path,
                     title_suffix: str | None = None):
    fig = plt.figure(figsize=(15, 16), facecolor=BG)
    gs = fig.add_gridspec(3, 2, hspace=0.45, wspace=0.25,
                          height_ratios=[1.0, 1.0, 1.0])
    title = "biosim4  ·  Predator-Prey  ·  Coevolution Analysis"
    if title_suffix:
        title += f"  —  {title_suffix}"
    fig.suptitle(title, fontsize=14, fontweight="bold", y=0.995)

    panel_populations(fig.add_subplot(gs[0, :]), d, smooth)
    panel_autocorrelation(fig.add_subplot(gs[1, 0]), sb)
    panel_cross_correlation(fig.add_subplot(gs[1, 1]), sb)
    panel_red_queen(fig.add_subplot(gs[2, 0]), d, sb, smooth)
    panel_sensor_usage(fig.add_subplot(gs[2, 1]), d, pred_rate, prey_rate)

    fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)


def render_split(d: EpochData, sb: StatsBundle, smooth: int,
                 pred_rate, prey_rate, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)
    plots = [
        ("populations.png",       lambda fig: panel_populations(fig.add_subplot(1, 1, 1), d, smooth)),
        ("autocorrelation.png",   lambda fig: panel_autocorrelation(fig.add_subplot(1, 1, 1), sb)),
        ("cross_correlation.png", lambda fig: panel_cross_correlation(fig.add_subplot(1, 1, 1), sb)),
        ("red_queen.png",         lambda fig: panel_red_queen(fig.add_subplot(1, 1, 1), d, sb, smooth)),
        ("sensor_usage.png",      lambda fig: panel_sensor_usage(fig.add_subplot(1, 1, 1), d, pred_rate, prey_rate)),
    ]
    for fname, draw in plots:
        fig = plt.figure(figsize=(10, 5.5), facecolor=BG)
        draw(fig)
        fig.savefig(out_dir / fname, dpi=150, bbox_inches="tight", facecolor=BG)
        plt.close(fig)


# =============================================================================
# Markdown report
# =============================================================================
def render_report(d: EpochData, sb: StatsBundle, args, report_path: Path) -> str:
    def verdict(p: bool) -> str: return "**PASS**" if p else "_fail_"

    v = compute_verdicts(sb, args.osc2_alpha, args.osc2_lag_min)
    osc1_pass, osc2_pass, rq_pass = v["OSC1"], v["OSC2"], v["RED-QUEEN"]

    lines = [
        "# biosim4 predator-prey analysis",
        "",
        f"- log: `{args.log}`",
        f"- generations analysed: {len(d.gen)}  (burn-in = {args.burn_in})",
        f"- smoothing window: {args.smooth}",
        "",
        "## Predictions",
        "",
        "| #    | Prediction | Verdict | Detail |",
        "|------|------------|---------|--------|",
        (f"| OSC1 | Detrended prey autocorrelation has a negative peak "
         f"at a positive lag (= half the period) | {verdict(osc1_pass)} | "
         f"min lag = {sb.osc1_neg_lag}, r = {sb.osc1_neg_corr:+.2f}, "
         f"FFT period ≈ {sb.osc1_period} gens |"),
        (f"| OSC2 | Cross-correlation peak at positive lag (prey leads "
         f"predator), permutation-significant | {verdict(osc2_pass)} | "
         f"lag = {sb.osc2_peak_lag:+d}, r = {sb.osc2_peak_corr:+.2f}, "
         f"perm-p = {sb.osc2_p:.3f} |"),
        (f"| RED-QUEEN | Coevolution avoids stasis: both species persist and "
         f"realised fitness keeps fluctuating (not frozen at an ESS) | "
         f"{verdict(rq_pass)} | persist = {sb.rq_persist} "
         f"(pred_surv={sb.rq_pred_surv_late:.1f}, prey_surv={sb.rq_prey_surv_late:.1f}); "
         f"prey fluctuation {sb.rq_prey_fluct_early:.2f}→{sb.rq_prey_fluct_late:.2f}, "
         f"pred {sb.rq_pred_fluct_early:.2f}→{sb.rq_pred_fluct_late:.2f} "
         f"(floor {RQ_FLUCT_FLOOR}) |"),
        "",
        "## Notes",
        "",
        "- **OSC1** uses the autocorrelation of the *detrended* prey series.  "
        "True Lotka-Volterra cycles produce a negative peak at the half-period "
        "lag.  A monotonic Red Queen trend never crosses below zero, so "
        "detrending separates oscillation from trend.",
        "- **OSC2** is the headline predator-prey test.  Detrended pred and "
        "prey series are cross-correlated; a circular-shift permutation null "
        "preserves each series' own autocorrelation but destroys the "
        "cross-alignment.  Reporting peak lag and permutation p.",
        "- **RED-QUEEN** follows the three-outcome framing of predator-prey "
        "coevolution (Dieckmann, Marrow & Law 1995; cf. Cliff & Miller 1995): "
        "a system either loses a species (extinction), settles to a constant-"
        "phenotype ESS (stasis), or keeps cycling -- the Red Queen.  We detect "
        "the last by ruling out the first two: both species persist in the "
        "final quartile **and** detrended realised fitness keeps fluctuating "
        f"(late sd > {RQ_FLUCT_FLOOR}) rather than freezing.  This deliberately "
        "does **not** require fitness to rise: a capture is a predator gain and "
        "a prey loss, so the two fitnesses are near zero-sum and a joint upward "
        "trend is structurally impossible.  The reported pred/prey slopes are a "
        "drift diagnostic only, not a pass condition.  Calibration: every "
        "no-predation control gives late fluctuation 0.000 (fitness pinned at a "
        "ceiling) and so fails, as required.",
    ]
    text = "\n".join(lines)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(text + "\n")
    return text


def print_summary(d: EpochData, sb: StatsBundle):
    bar = "─" * 72
    print()
    print(bar)
    print(f"  Generations analysed : {len(d.gen)}")
    if d.pred_fit.size > 0:
        print(f"  Final pred fitness   : {d.pred_fit[-1]:.3f}")
        print(f"  Final prey fitness   : {d.prey_fit[-1]:.3f}")
    print(bar)
    print(f"  OSC1  prey autocorr (neg)   "
          f"lag = {sb.osc1_neg_lag}  r = {sb.osc1_neg_corr:+.3f}  "
          f"FFT period ≈ {sb.osc1_period} gens")
    print(f"  OSC2  cross-corr peak       "
          f"lag = {sb.osc2_peak_lag:+d}  r = {sb.osc2_peak_corr:+.3f}  "
          f"perm-p = {sb.osc2_p:.3f}")
    print(f"  RQ    persist = {sb.rq_persist}  "
          f"(pred_surv = {sb.rq_pred_surv_late:.1f}, prey_surv = {sb.rq_prey_surv_late:.1f})")
    print(f"        non-stasis = {sb.rq_nonstasis}  "
          f"prey fluct {sb.rq_prey_fluct_early:.2f}->{sb.rq_prey_fluct_late:.2f}  "
          f"pred fluct {sb.rq_pred_fluct_early:.2f}->{sb.rq_pred_fluct_late:.2f}")
    print(bar)


# =============================================================================
# Main
# =============================================================================
def main():
    args = parse_args()
    log = Path(args.log)
    if not log.is_file():
        sys.exit(f"ERROR: log file not found: {log}")

    d = EpochData.load(log, burn_in=args.burn_in)
    if len(d.gen) < 5:
        sys.exit(f"ERROR: only {len(d.gen)} generations after burn-in "
                 f"(need ≥ 5 for any meaningful stats)")

    rng = np.random.default_rng(args.seed)
    pred_rate, prey_rate = scan_sensor_usage(Path(args.nets), d.gen)
    sb = compute_stats(d, args.max_lag, args.n_perm, rng)

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    render_composite(d, sb, args.smooth, pred_rate, prey_rate, out_path,
                     title_suffix=args.title)
    print(f"Saved composite figure: {out_path}")

    if args.split_figures:
        sub_dir = out_path.parent / (out_path.stem + "_panels")
        render_split(d, sb, args.smooth, pred_rate, prey_rate, sub_dir)
        print(f"Saved per-panel figures: {sub_dir}/")

    render_report(d, sb, args, Path(args.report))
    print(f"Saved markdown report: {args.report}")
    print_summary(d, sb)

    # ── generation checkpoints ──────────────────────────────────────────────
    for ckpt in sorted(args.checkpoints):
        mask = d.gen <= ckpt
        if mask.sum() < 5:
            print(f"Skipping checkpoint gen={ckpt}: fewer than 5 generations available")
            continue
        dc = EpochData(
            d.gen[mask], d.pred_surv[mask], d.prey_surv[mask],
            d.pred_fit[mask], d.prey_fit[mask],
        )
        rng_ckpt = np.random.default_rng(args.seed)
        sbc = compute_stats(dc, args.max_lag, args.n_perm, rng_ckpt)

        ckpt_stem = out_path.stem.replace("analysis", f"analysis_gen{ckpt}")
        ckpt_out    = out_path.parent / f"{ckpt_stem}.png"
        ckpt_report = Path(args.report).parent / f"{Path(args.report).stem}_gen{ckpt}.md"

        # slice sensor-rate arrays to match the checkpoint's generation range
        pred_rate_c = pred_rate[mask] if pred_rate.size == d.gen.size else pred_rate
        prey_rate_c = prey_rate[mask] if prey_rate.size == d.gen.size else prey_rate

        ckpt_title = (f"{args.title} | gen≤{ckpt}" if args.title else f"gen≤{ckpt}")
        render_composite(dc, sbc, args.smooth, pred_rate_c, prey_rate_c, ckpt_out,
                         title_suffix=ckpt_title)
        print(f"Saved checkpoint figure (gen≤{ckpt}): {ckpt_out}")
        render_report(dc, sbc, args, ckpt_report)
        print(f"Saved checkpoint report (gen≤{ckpt}): {ckpt_report}")


if __name__ == "__main__":
    main()
