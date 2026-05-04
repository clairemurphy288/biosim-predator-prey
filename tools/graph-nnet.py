#!/usr/bin/python3
"""
graph-nnet.py  –  render a biosim4 neural-net edge list as an SVG.

Usage:
    python graph-nnet.py -i <edge_list.txt> -o <output.svg>

Edge-list format (one connection per line):
    SOURCE  SINK  WEIGHT
where SOURCE/SINK are short node names (e.g. PyD, N2, Klf).
"""

import igraph
import argparse
import sys
import os

# ── Full human-readable label lookup ─────────────────────────────────────────
SENSOR_LABELS = {
    'Lx':  'Loc X',      'Ly':  'Loc Y',
    'EDx': 'Edge Dist X','EDy': 'Edge Dist Y', 'ED': 'Edge Dist',
    'Bfd': 'Barrier Fwd','Blr': 'Barrier L/R',
    'Gen': 'Genetic Sim','LMx': 'Last Move X',  'LMy': 'Last Move Y',
    'LPf': 'LongProbe Pop','LPb': 'LongProbe Bar',
    'Pop': 'Population', 'Pfd': 'Pop Fwd',      'Plr': 'Pop L/R',
    'Osc': 'Oscillator', 'Age': 'Age',           'Rnd': 'Random',
    'Sg':  'Signal',     'Sfd': 'Signal Fwd',   'Slr': 'Signal L/R',
    'PrX': 'Pred Dir X', 'PrY': 'Pred Dir Y',   'PrD': 'Pred Dist',
    'PyX': 'Prey Dir X', 'PyY': 'Prey Dir Y',   'PyD': 'Prey Dist',
}

ACTION_LABELS = {
    'MvX': 'Move X',     'MvY': 'Move Y',
    'MvE': 'Move East',  'MvW': 'Move West',
    'MvN': 'Move North', 'MvS': 'Move South',
    'Mfd': 'Move Fwd',   'MvL': 'Move Left',
    'MvR': 'Move Right', 'MRL': 'Move R/L',
    'Mrv': 'Move Rev',   'Mrn': 'Move Rand',
    'OSC': 'Set Osc',    'LPD': 'Set LProbe',
    'Res': 'Set Resp',   'SG':  'Emit Signal',
    'Klf': 'Kill Fwd',
}

SENSOR_NAMES = set(SENSOR_LABELS.keys())
ACTION_NAMES = set(ACTION_LABELS.keys())

# ── Colour palette ────────────────────────────────────────────────────────────
# Sensor  = steel blue   Action = salmon red   Neuron = light grey
COLOR_SENSOR = '#5b9bd5'
COLOR_ACTION = '#ed7d6a'
COLOR_NEURON = '#c8c8c8'
COLOR_EDGE_POS = '#2ea04b'   # positive weight  → green
COLOR_EDGE_NEG = '#cf222e'   # negative weight  → red
COLOR_EDGE_ZRO = '#888888'   # zero             → grey
FONT_COLOR = '#ffffff'        # white text on coloured nodes

# ── Parse arguments ───────────────────────────────────────────────────────────
parser = argparse.ArgumentParser()
parser.add_argument('-i', default='tools/net.txt',  help='input edge-list file')
parser.add_argument('-o', default='tools/net.svg',  help='output SVG file')
args = parser.parse_args()

if not os.path.isfile(args.i):
    sys.exit(f'ERROR: input file not found: {args.i}')

# ── Load graph ────────────────────────────────────────────────────────────────
g = igraph.Graph.Read_Ncol(args.i, names=True, weights=True, directed=True)

if len(g.vs) == 0:
    sys.exit(f'ERROR: no nodes found in {args.i}')

# ── Style nodes ──────────────────────────────────────────────────────────────
for v in g.vs:
    name = v['name']
    if name in SENSOR_NAMES:
        v['color']      = COLOR_SENSOR
        v['label']      = SENSOR_LABELS[name]
        v['label_size'] = 11
        v['size']       = 50
        v['shape']      = 'circle'
    elif name in ACTION_NAMES:
        v['color']      = COLOR_ACTION
        v['label']      = ACTION_LABELS[name]
        v['label_size'] = 11
        v['size']       = 50
        v['shape']      = 'circle'
    else:
        # Internal neuron: N0, N1, …
        v['color']      = COLOR_NEURON
        v['label']      = name
        v['label_size'] = 13
        v['size']       = 42
        v['shape']      = 'circle'
    v['label_color'] = '#222222'
    v['frame_color'] = '#444444'
    v['frame_width'] = 1.5

# ── Style edges ───────────────────────────────────────────────────────────────
max_w = max((abs(e['weight']) for e in g.es), default=1) or 1
for e in g.es:
    w = e['weight']
    if w > 0:
        e['color'] = COLOR_EDGE_POS
    elif w < 0:
        e['color'] = COLOR_EDGE_NEG
    else:
        e['color'] = COLOR_EDGE_ZRO
    # line width scaled to 0.8–5.0
    e['width'] = 0.8 + 4.2 * (abs(w) / max_w)
    e['arrow_size'] = 1.0

# ── Canvas size ───────────────────────────────────────────────────────────────
n = len(g.vs)
if n <= 8:
    bbox, layout = (500, 500), 'fruchterman_reingold'
elif n <= 16:
    bbox, layout = (700, 700), 'fruchterman_reingold'
elif n <= 30:
    bbox, layout = (900, 900), 'fruchterman_reingold'
else:
    bbox, layout = (1200, 1200), 'fruchterman_reingold'

# ── Plot ──────────────────────────────────────────────────────────────────────
igraph.plot(
    g,
    args.o,
    layout=layout,
    bbox=bbox,
    margin=80,
    edge_curved=0.2,
    vertex_label=g.vs['label'],
    vertex_label_size=g.vs['label_size'],
    vertex_label_dist=0,
    vertex_label_color=g.vs['label_color'],
    vertex_color=g.vs['color'],
    vertex_frame_color=g.vs['frame_color'],
    vertex_frame_width=g.vs['frame_width'],
    vertex_size=g.vs['size'],
    edge_color=g.es['color'],
    edge_width=g.es['width'],
    edge_arrow_size=g.es['arrow_size'],
)
print(f'Saved: {args.o}  ({n} nodes, {len(g.es)} edges)')
