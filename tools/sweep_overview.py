#!/usr/bin/env python3
"""
sweep_overview.py - roll a whole biosim4 sweep up into report-ready overviews.

Per-run figures (from analyse.py) answer "what happened in this run?".  This
tool answers "what happened across the sweep?" - aggregating every seed of
every condition into one figure (and one table) per experiment, so a reader can
see the behaviour of the whole experiment at a glance.

For each experiment (a directory whose children are condition folders, each
holding seed_<N> runs) it writes:

    <sweep>/overview/<Group>__<Experiment>.png
    <sweep>/overview/sweep_overview.md      (verdict tables for every experiment)

Each figure has four panels:

    A  VERDICT MATRIX      conditions x {OSC1, OSC2, RED-QUEEN}, shaded by the
                           fraction of seeds that pass.  The bird's-eye view.

    B  CROSS-CORRELATION   mean detrended predator<->prey survivor cross-
                           correlation per condition (band = seed spread).  The
                           shape (trough/peak, where it crosses zero) is the
                           Lotka-Volterra coupling signature.

    C  PHASE LAG           peak cross-correlation lag per condition, one point
                           per seed + mean.  Positive lag => prey leads predator
                           (prey booms, predators follow) - the classic lag.

    D  RED-QUEEN MARGIN    late-window prey-fitness fluctuation per condition vs
                           the stasis floor.  Shows how far each condition is
                           from freezing at an ESS (bars near the floor = nearly
                           static; tall bars = a live arms race).

Usage
-----
    .venv/bin/python3 tools/sweep_overview.py --sweep Output/Sweep/run_<ts>
    .venv/bin/python3 tools/sweep_overview.py --sweep Output/Sweep/run_<ts> --burn-in 50
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap

# Reuse the per-run machinery so the overview can never disagree with analyse.py
import analyse
from analyse import (
    EpochData, compute_stats, compute_verdicts, style, BG,
    PRED_C, PREY_C, ACCENT, NEUTRAL, RQ_FLUCT_FLOOR,
)

TESTS = ["OSC1", "OSC2", "RED-QUEEN"]
# red -> amber -> green for "fraction of seeds passing"
PASS_CMAP = LinearSegmentedColormap.from_list(
    "passfrac", ["#d1493f", "#e8c14b", "#2ea04b"])


# =============================================================================
# Discovery + per-run stats
# =============================================================================
@dataclass
class RunResult:
    condition: str
    seed: str
    verdicts: dict
    xcf_lags: np.ndarray
    xcf: np.ndarray
    peak_lag: int
    prey_fluct_late: float
    pred_surv_late: float
    prey_surv_late: float


def find_experiments(sweep: Path) -> dict[Path, list[Path]]:
    """Map experiment_dir -> [seed epoch-log paths].  An experiment dir is the
    grandparent of a seed_<N>/logs/epoch-log.txt path."""
    # path: <sweep>/<group>/<experiment>/<condition>/seed_<N>/logs/epoch-log.txt
    #   parents[1]=seed_<N>  [2]=condition  [3]=experiment  [4]=group
    experiments: dict[Path, list[Path]] = defaultdict(list)
    for log in sweep.rglob("seed_*/logs/epoch-log.txt"):
        experiments[log.parents[3]].append(log)
    return dict(sorted(experiments.items()))


def analyse_run(log: Path, args) -> RunResult | None:
    try:
        d = EpochData.load(log, burn_in=args.burn_in)
    except SystemExit:
        return None
    if len(d.gen) < 20:
        return None
    rng = np.random.default_rng(args.seed)
    sb = compute_stats(d, args.max_lag, args.n_perm, rng)
    seed_dir = log.parent.parent          # seed_<N>
    condition = seed_dir.parent.name      # condition folder
    return RunResult(
        condition=condition,
        seed=seed_dir.name.replace("seed_", ""),
        verdicts=compute_verdicts(sb, args.osc2_alpha),
        xcf_lags=sb.xcf_lags, xcf=sb.xcf,
        peak_lag=sb.osc2_peak_lag,
        prey_fluct_late=sb.rq_prey_fluct_late,
        pred_surv_late=sb.rq_pred_surv_late,
        prey_surv_late=sb.rq_prey_surv_late,
    )


# =============================================================================
# Panels
# =============================================================================
def panel_verdict_matrix(ax, conditions, by_condition):
    n_cond = len(conditions)
    frac = np.zeros((n_cond, len(TESTS)))
    counts = [[("", 0) for _ in TESTS] for _ in range(n_cond)]
    for i, cond in enumerate(conditions):
        runs = by_condition[cond]
        for j, t in enumerate(TESTS):
            k = sum(1 for r in runs if r.verdicts[t])
            frac[i, j] = k / len(runs) if runs else 0.0
            counts[i][j] = (f"{k}/{len(runs)}", len(runs))

    ax.imshow(frac, cmap=PASS_CMAP, vmin=0, vmax=1, aspect="auto")
    ax.set_xticks(range(len(TESTS)), TESTS, fontsize=9)
    ax.set_yticks(range(n_cond), conditions, fontsize=9)
    for i in range(n_cond):
        for j in range(len(TESTS)):
            txt, _ = counts[i][j]
            ax.text(j, i, txt, ha="center", va="center",
                    color="white", fontsize=9, fontweight="bold")
    ax.set_title("A  Verdict matrix  (seeds passing)", fontsize=11, fontweight="bold")
    ax.set_xticks(np.arange(-.5, len(TESTS), 1), minor=True)
    ax.set_yticks(np.arange(-.5, n_cond, 1), minor=True)
    ax.grid(which="minor", color="white", linewidth=2)
    ax.tick_params(which="minor", length=0)


def _condition_colors(conditions):
    cmap = plt.get_cmap("viridis", max(len(conditions), 2))
    return {c: cmap(i) for i, c in enumerate(conditions)}


def panel_cross_correlation(ax, conditions, by_condition, colors):
    ax.axhline(0, color="black", lw=0.6)
    ax.axvline(0, color="black", lw=0.6, ls=":")
    for cond in conditions:
        runs = [r for r in by_condition[cond] if r.xcf.size]
        if not runs:
            continue
        lags = runs[0].xcf_lags
        stack = np.vstack([r.xcf for r in runs if r.xcf.shape == lags.shape])
        if stack.size == 0:
            continue
        mean = stack.mean(0)
        ax.plot(lags, mean, lw=1.8, color=colors[cond], label=cond)
        if stack.shape[0] > 1:
            sd = stack.std(0)
            ax.fill_between(lags, mean - sd, mean + sd, color=colors[cond], alpha=0.12)
    ax.set_xlabel("Lag (generations)  —  positive ⇒ prey leads predator")
    ax.legend(fontsize=8, loc="upper right")
    style(ax, "Cross-correlation r",
          "B  Predator ↔ prey cross-correlation (mean ± sd over seeds)")


def panel_phase_lag(ax, conditions, by_condition, colors):
    ax.axvline(0, color="black", lw=0.8, ls=":")
    for i, cond in enumerate(conditions):
        lags = [r.peak_lag for r in by_condition[cond]]
        jitter = (np.random.default_rng(0).random(len(lags)) - 0.5) * 0.25
        ax.scatter(lags, np.full(len(lags), i) + jitter,
                   color=colors[cond], s=42, alpha=0.85, zorder=3)
        if lags:
            ax.scatter([np.mean(lags)], [i], marker="D", s=90,
                       edgecolor="black", facecolor=colors[cond], zorder=4)
    ax.set_yticks(range(len(conditions)), conditions, fontsize=9)
    ax.set_xlabel("Peak cross-correlation lag (generations)")
    ax.text(0.99, 0.02, "◆ = condition mean", transform=ax.transAxes,
            ha="right", va="bottom", fontsize=8, color=NEUTRAL)
    style(ax, "", "C  Phase lag  (positive ⇒ prey leads predator)")


def panel_rq_margin(ax, conditions, by_condition, colors):
    means, sds, xs = [], [], []
    for i, cond in enumerate(conditions):
        vals = [r.prey_fluct_late for r in by_condition[cond]]
        means.append(np.mean(vals) if vals else 0.0)
        sds.append(np.std(vals) if len(vals) > 1 else 0.0)
        xs.append(i)
    ax.bar(xs, means, yerr=sds, capsize=3,
           color=[colors[c] for c in conditions], alpha=0.55)
    # per-seed points so a single near-stasis seed is visible, not hidden in the mean
    rng = np.random.default_rng(0)
    for i, cond in enumerate(conditions):
        vals = [r.prey_fluct_late for r in by_condition[cond]]
        jitter = (rng.random(len(vals)) - 0.5) * 0.3
        ax.scatter(np.full(len(vals), i) + jitter, vals,
                   color="black", s=22, zorder=4, alpha=0.8)
    ax.axhline(RQ_FLUCT_FLOOR, color=PRED_C, ls="--", lw=1.4,
               label=f"stasis floor ({RQ_FLUCT_FLOOR})")
    ax.set_xticks(xs, conditions, fontsize=9, rotation=20, ha="right")
    ax.legend(fontsize=8, loc="upper right")
    style(ax, "Late prey-fitness fluctuation (sd)",
          "D  Red-Queen margin  (bars near floor ⇒ nearing stasis)")


# =============================================================================
# Per-experiment render
# =============================================================================
def render_experiment(experiment_dir: Path, logs: list[Path], sweep: Path,
                      out_dir: Path, args) -> tuple[str, list[RunResult]]:
    results = [r for r in (analyse_run(log, args) for log in logs) if r]
    if not results:
        return "", []

    by_condition: dict[str, list[RunResult]] = defaultdict(list)
    for r in results:
        by_condition[r.condition].append(r)
    conditions = sorted(by_condition)
    colors = _condition_colors(conditions)

    group = experiment_dir.parent.name
    exp = experiment_dir.name
    title = f"{group}  /  {exp}"

    fig = plt.figure(figsize=(15, 11), facecolor=BG)
    gs = fig.add_gridspec(2, 2, hspace=0.32, wspace=0.22)
    fig.suptitle(f"biosim4  ·  Sweep overview  —  {title}",
                 fontsize=14, fontweight="bold", y=0.98)
    panel_verdict_matrix(fig.add_subplot(gs[0, 0]), conditions, by_condition)
    panel_cross_correlation(fig.add_subplot(gs[0, 1]), conditions, by_condition, colors)
    panel_phase_lag(fig.add_subplot(gs[1, 0]), conditions, by_condition, colors)
    panel_rq_margin(fig.add_subplot(gs[1, 1]), conditions, by_condition, colors)

    out_path = out_dir / f"{group}__{exp}.png"
    fig.savefig(out_path, dpi=150, bbox_inches="tight", facecolor=BG)
    plt.close(fig)
    print(f"  {title:38s} → {out_path.name}  ({len(results)} runs, {len(conditions)} conditions)")
    return title, results


def experiment_table(title: str, results: list[RunResult]) -> str:
    by_condition: dict[str, list[RunResult]] = defaultdict(list)
    for r in results:
        by_condition[r.condition].append(r)
    lines = [f"### {title}", "",
             "| Condition | n | OSC1 | OSC2 | RED-QUEEN | mean lag | mean prey_surv |",
             "|-----------|---|------|------|-----------|----------|----------------|"]
    for cond in sorted(by_condition):
        runs = by_condition[cond]
        n = len(runs)
        cells = [f"{sum(1 for r in runs if r.verdicts[t])}/{n}" for t in TESTS]
        lag = np.mean([r.peak_lag for r in runs])
        prey = np.mean([r.prey_surv_late for r in runs])
        lines.append(f"| {cond} | {n} | {cells[0]} | {cells[1]} | {cells[2]} "
                     f"| {lag:+.1f} | {prey:.1f} |")
    lines.append("")
    return "\n".join(lines)


# =============================================================================
# Main
# =============================================================================
def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="biosim4 sweep-level overview")
    ap.add_argument("--sweep", required=True,
                    help="sweep root, e.g. Output/Sweep/run_<timestamp>")
    ap.add_argument("--burn-in", type=int, default=50)
    ap.add_argument("--max-lag", type=int, default=40)
    ap.add_argument("--n-perm", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--osc2-alpha", type=float, default=0.10)
    return ap.parse_args()


def main():
    args = parse_args()
    sweep = Path(args.sweep)
    if not sweep.is_dir():
        raise SystemExit(f"ERROR: sweep dir not found: {sweep}")

    experiments = find_experiments(sweep)
    if not experiments:
        raise SystemExit(f"ERROR: no seed_*/logs/epoch-log.txt found under {sweep}")

    out_dir = sweep / "overview"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Sweep: {sweep}\nFound {len(experiments)} experiment(s). Writing → {out_dir}/")

    tables = []
    for experiment_dir, logs in experiments.items():
        title, results = render_experiment(experiment_dir, logs, sweep, out_dir, args)
        if results:
            tables.append(experiment_table(title, results))

    md = out_dir / "sweep_overview.md"
    md.write_text("# Sweep overview\n\n"
                  f"- sweep: `{sweep}`\n"
                  f"- burn-in: {args.burn_in}\n\n"
                  "Cells show **seeds passing / total seeds**.  "
                  "Lag is the mean predator↔prey cross-correlation peak "
                  "(positive ⇒ prey leads predator).\n\n"
                  + "\n".join(tables) + "\n")
    print(f"Wrote summary: {md}")


if __name__ == "__main__":
    main()
