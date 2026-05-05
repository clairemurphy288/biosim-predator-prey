#!/usr/bin/env python3
"""
analyse.py  –  analysis and plotting pipeline for biosim4 predator-prey runs.

Produces a single figure with 4 subplots:
  1. Predator & prey fitness over generations
  2. Survivor counts (predator / prey) over generations
  3. Opponent-sensor usage rate (PrD in predator nets, PyD in prey nets)
  4. Genetic diversity over generations

Usage:
    python tools/analyse.py [--log Output/Logs/epoch-log.txt]
                            [--nets Output/Images]
                            [--out  Output/analysis.png]
                            [--smooth 5]
"""

import argparse
import os
import re
import sys
from pathlib import Path
from collections import defaultdict

import matplotlib
matplotlib.use('Agg')          # no display needed
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np

# ── CLI ───────────────────────────────────────────────────────────────────────
parser = argparse.ArgumentParser(description='biosim4 predator-prey analysis')
parser.add_argument('--log',    default='Output/Logs/epoch-log.txt',
                    help='Path to epoch-log.txt')
parser.add_argument('--nets',   default='Output/Images',
                    help='Directory containing gen-*-pred/prey-id-*.txt files')
parser.add_argument('--out',    default='Output/analysis.png',
                    help='Output image path')
parser.add_argument('--smooth', type=int, default=5,
                    help='Rolling-average window size (0 = off)')
args = parser.parse_args()

# ── Helpers ───────────────────────────────────────────────────────────────────
def smooth(y, w):
    if w < 2 or len(y) < w:
        return np.array(y, dtype=float)
    kernel = np.ones(w) / w
    return np.convolve(y, kernel, mode='same')

def fmt_ax(ax, ylabel, title):
    ax.set_ylabel(ylabel, fontsize=10)
    ax.set_title(title, fontsize=11, fontweight='bold')
    ax.grid(True, alpha=0.3)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)

# ── 1. Parse epoch log ────────────────────────────────────────────────────────
log_path = Path(args.log)
if not log_path.is_file():
    sys.exit(f'ERROR: log file not found: {log_path}')

gen, survivors, diversity, genome_len, murders = [], [], [], [], []
pred_survivors, prey_survivors = [], []
pred_fitness, prey_fitness = [], []

with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        gen.append(int(parts[0]))
        survivors.append(int(parts[1]))
        diversity.append(float(parts[2]))
        genome_len.append(float(parts[3]))
        murders.append(int(parts[4]))
        # Extended columns added by our patched analysis.cpp
        if len(parts) >= 9:
            pred_survivors.append(int(parts[5]))
            prey_survivors.append(int(parts[6]))
            pred_fitness.append(float(parts[7]))
            prey_fitness.append(float(parts[8]))
        else:
            pred_survivors.append(None)
            prey_survivors.append(None)
            pred_fitness.append(None)
            prey_fitness.append(None)

gen = np.array(gen)
has_fitness = any(v is not None for v in pred_fitness)

# ── 2. Scan saved NN edge-list files for sensor usage ─────────────────────────
# Filename pattern: gen-<G>-pred-id-<ID>.txt  /  gen-<G>-prey-id-<ID>.txt
nets_dir = Path(args.nets)
PRED_SENSOR = 'PrD'   # predator nets should evolve to use prey-distance
PREY_SENSOR = 'PyD'   # prey nets should evolve to use predator-distance

pat = re.compile(r'^gen-(\d+)-(pred|prey)-id-\d+\.txt$')

pred_usage = defaultdict(lambda: [0, 0])   # gen -> [count_with_sensor, total]
prey_usage = defaultdict(lambda: [0, 0])

for fpath in nets_dir.glob('*.txt'):
    m = pat.match(fpath.name)
    if not m:
        continue
    g_num   = int(m.group(1))
    kind    = m.group(2)       # 'pred' or 'prey'
    text    = fpath.read_text()
    nodes   = {tok for line in text.splitlines()
                    for tok in line.split()[:2] if tok}

    if kind == 'pred':
        pred_usage[g_num][1] += 1
        if PRED_SENSOR in nodes:
            pred_usage[g_num][0] += 1
    else:
        prey_usage[g_num][1] += 1
        if PREY_SENSOR in nodes:
            prey_usage[g_num][0] += 1

def usage_series(usage_dict, all_gens):
    rates = []
    for g in all_gens:
        d = usage_dict.get(g)
        if d and d[1] > 0:
            rates.append(d[0] / d[1])
        else:
            rates.append(np.nan)
    return np.array(rates)

pred_sensor_rate = usage_series(pred_usage, gen)
prey_sensor_rate = usage_series(prey_usage, gen)
has_sensor_data  = not np.all(np.isnan(pred_sensor_rate))

# ── 3. Plot ───────────────────────────────────────────────────────────────────
W = args.smooth
MARKER_KW  = dict(marker='o', ms=3, markevery=1)   # small dot on every point
PRED_COLOR = '#cf222e'
PREY_COLOR = '#2ea04b'

nrows = 2 + (1 if has_fitness else 0) + (1 if has_sensor_data else 0)
fig, axes = plt.subplots(nrows, 1, figsize=(13, 4.2 * nrows), sharex=True)
fig.suptitle('biosim4 Predator–Prey Run Analysis', fontsize=14, fontweight='bold', y=1.01)
ax_iter = iter(axes if nrows > 1 else [axes])

def set_gen_xticks(ax):
    """Integer ticks every 1 generation up to 20, then every 5."""
    step = 1 if len(gen) <= 20 else 5
    ax.xaxis.set_major_locator(mticker.MultipleLocator(step))
    ax.xaxis.set_minor_locator(mticker.MultipleLocator(1))

# ── subplot: Fitness ──────────────────────────────────────────────────────────
if has_fitness:
    ax = next(ax_iter)
    pf = np.array([v if v is not None else np.nan for v in pred_fitness])
    yf = np.array([v if v is not None else np.nan for v in prey_fitness])
    ax.plot(gen, smooth(pf, W), color=PRED_COLOR, lw=1.8,
            label='Predator fitness (mean captures/norm)', **MARKER_KW)
    ax.plot(gen, smooth(yf, W), color=PREY_COLOR, lw=1.8,
            label='Prey fitness (mean age/stepsPerGen)', **MARKER_KW)
    ax.set_ylim(0, 1)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=1.0))
    ax.legend(fontsize=9)
    set_gen_xticks(ax)
    fmt_ax(ax, 'Fitness (normalised)', 'Predator & Prey Fitness Over Generations')

# ── subplot: Survivor counts ──────────────────────────────────────────────────
ax = next(ax_iter)
if has_fitness and any(v is not None for v in pred_survivors):
    ps = np.array([v if v is not None else np.nan for v in pred_survivors])
    ys = np.array([v if v is not None else np.nan for v in prey_survivors])
    ax.plot(gen, smooth(ps, W), color=PRED_COLOR, lw=1.8,
            label='Predator survivors', **MARKER_KW)
    ax.plot(gen, smooth(ys, W), color=PREY_COLOR, lw=1.8,
            label='Prey survivors', **MARKER_KW)
else:
    ax.plot(gen, smooth(survivors, W), color='steelblue', lw=1.8,
            label='Total survivors', **MARKER_KW)
ax.plot(gen, smooth(np.array(murders, dtype=float), W), color='#888888',
        lw=1.2, ls='--', label='Kills per gen')
ax.legend(fontsize=9)
set_gen_xticks(ax)
fmt_ax(ax, 'Count', 'Survivor & Kill Counts')

# ── subplot: Sensor usage ─────────────────────────────────────────────────────
if has_sensor_data:
    ax = next(ax_iter)
    # Only plot generations where we actually have .txt data (drop NaN gaps).
    pred_mask = np.isfinite(pred_sensor_rate)
    prey_mask = np.isfinite(prey_sensor_rate)
    sampled_gens = sorted(set(gen[pred_mask]) | set(gen[prey_mask]))
    note = f'(sampled every {sampled_gens[1]-sampled_gens[0]} gens)' \
           if len(sampled_gens) >= 2 else '(sparse samples)'
    if pred_mask.any():
        ax.plot(gen[pred_mask], pred_sensor_rate[pred_mask] * 100,
                color=PRED_COLOR, lw=1.8, marker='o', ms=6,
                label=f'Predators using "{PRED_SENSOR}" sensor {note}')
    if prey_mask.any():
        ax.plot(gen[prey_mask], prey_sensor_rate[prey_mask] * 100,
                color=PREY_COLOR, lw=1.8, marker='s', ms=6,
                label=f'Prey using "{PREY_SENSOR}" sensor {note}')
    ax.set_ylim(-5, 105)
    ax.yaxis.set_major_formatter(mticker.PercentFormatter())
    ax.set_xticks(sampled_gens)
    ax.legend(fontsize=9)
    fmt_ax(ax, 'Usage rate (%)',
           f'Opponent-Sensor Usage Rate  ({PRED_SENSOR}=prey-dist  /  {PREY_SENSOR}=pred-dist)')

# ── subplot: Genetic diversity ────────────────────────────────────────────────
ax = next(ax_iter)
div = np.array(diversity, dtype=float)
ax.plot(gen, smooth(div, W), color='#5b9bd5', lw=1.8,
        label='Genetic diversity', **MARKER_KW)
ax.fill_between(gen, smooth(div, W), alpha=0.12, color='#5b9bd5')
ax.set_ylim(0, 1)
ax.legend(fontsize=9)
ax.set_xlabel('Generation', fontsize=10)
set_gen_xticks(ax)
fmt_ax(ax, 'Diversity (0–1)', 'Genetic Diversity Over Generations')

# ── Save ──────────────────────────────────────────────────────────────────────
out_path = Path(args.out)
out_path.parent.mkdir(parents=True, exist_ok=True)
fig.tight_layout()
fig.savefig(out_path, dpi=150, bbox_inches='tight')
print(f'Saved analysis plot: {out_path}')

# ── Print summary table ───────────────────────────────────────────────────────
print()
print('── Summary ──────────────────────────────────────────────────────────')
print(f'  Generations logged : {len(gen)}')
print(f'  Final diversity    : {diversity[-1]:.3f}')
if has_fitness:
    print(f'  Final pred fitness : {pred_fitness[-1]:.3f}')
    print(f'  Final prey fitness : {prey_fitness[-1]:.3f}')
if has_sensor_data:
    last_pred = pred_sensor_rate[~np.isnan(pred_sensor_rate)]
    last_prey = prey_sensor_rate[~np.isnan(prey_sensor_rate)]
    if len(last_pred):
        print(f'  Last pred PrD rate : {last_pred[-1]*100:.1f}%')
    if len(last_prey):
        print(f'  Last prey PyD rate : {last_prey[-1]*100:.1f}%')
print('─────────────────────────────────────────────────────────────────────')
