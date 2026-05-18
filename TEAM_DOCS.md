# biosim4 — Team Documentation

*Predator-Prey Neuroevolution · Bia, Yannic, Claire*

---

## Table of Contents

1. [Quickstart](#quickstart)
2. [Windows Setup](#windows-setup)
3. [Project Directory Structure](#project-directory-structure)
4. [Project Overview](#1-project-overview)
5. [Installation](#2-installation)
6. [Stochasticity & Reproducibility](#3-stochasticity--reproducibility)
7. [Running a Single Simulation](#4-running-a-single-simulation)
8. [Running the Parameter Sweep](#5-running-the-parameter-sweep)
9. [Cleaning Up Outputs](#6-cleaning-up-outputs)
10. [biosim4.ini Variable Reference](#7-biosim4ini-variable-reference)
11. [Evolutionary Algorithm Explained](#8-evolutionary-algorithm-explained)
12. [Kill Mechanics](#9-kill-mechanics)
13. [Video Recording](#10-video-recording)
14. [Neural Network Snapshots](#11-neural-network-snapshots)
15. [Statistical Analysis](#12-statistical-analysis)
16. [Interpreting the Analysis Panels](#13-interpreting-the-analysis-panels)
17. [Experiment Matrix Summary](#14-experiment-matrix-summary)

---

## The Two Files You Will Edit

Almost everything you need to do for your experiments touches exactly two files:

### `biosim4.ini` — simulation parameters

This is the main config file. It controls the world size, population, challenge type, predator/prey behaviour, mutation rate, starvation pressure, and output paths. **You do not need to touch the C++ source code.** Every experimental variable is exposed as a parameter here.

When running a sweep, the sweep script automatically copies this file and overrides the relevant parameters per-run — so treat `biosim4.ini` as the **default baseline** that all experiments start from.

Key things to check before running:
- `maxGenerations` — set to `400` for full experiment runs
- `deterministic = true` and `RNGSeed = 1` — correct for reproducibility
- `predatorPreyEnabled = true` — must be on for all treatment runs

### `tools/run_sweep.sh` — experiment matrix

This script defines every condition to sweep across, runs the simulator for each condition × seed combination, and saves all results to `Output/Sweep/`. The **EXPERIMENT MATRIX** block at the top is the only part you need to edit:

```bash
MAX_GENERATIONS=400     # how long each run goes
SEEDS=(1 2 3)           # replication seeds
HEADLESS=true           # true = no window (recommended for sweeps)
SAVE_NETS=true          # capture neural network snapshots
NETS_STRIDE=10          # one snapshot every N generations
BURN_IN=50              # skip first N generations in statistical tests

# Your experiment arrays, e.g.:
B1_CHALLENGES=(20 0 5 11)
C1_STARVATION=(0 60 120 220 400)
```

Everything below that block is infrastructure — you do not need to edit it.

---

## Quickstart

Everything you need to go from a fresh clone to a running experiment.

### 1. Install dependencies

**macOS**
```bash
brew install cmake sfml tgui cereal
```

**Ubuntu / Debian**
```bash
sudo apt install build-essential cmake libsfml-dev
# TGUI (must be 1.1.x): https://tgui.eu/tutorials/latest-stable/linux/
# cereal (header-only):  https://uscilab.github.io/cereal/index.html
#   → download and copy include/ to /usr/local/include/
```

**Windows** — see [Windows Setup](#windows-setup) below.

> TGUI must be version **1.1.x** — other versions are not compatible. See full install details in [Section 2](#2-installation).

### 2. Build

```bash
make -j4
# Binary: bin/Release/biosim4
```

### 3. Python environment

```bash
python3 -m venv .venv
source .venv/bin/activate          # macOS / Linux
# .venv\Scripts\activate           # Windows (Command Prompt)
pip install -r requirements.txt
```

### 4. Test a single run (headless, ~2 min)

```bash
./bin/Release/biosim4 biosim4.ini --headless
# Output → Output/Logs/epoch-log.txt
```

### 5. Run your experiment group

```bash
# Edit tools/run_sweep.sh → set MAX_GENERATIONS, SEEDS, HEADLESS, BURN_IN, SAVE_NETS
# Then:
RUN_GROUPS="B1 B2 B3"  ./tools/run_sweep.sh   # Bia
RUN_GROUPS="Y1 Y2 Y3"  ./tools/run_sweep.sh   # Yannic
RUN_GROUPS="C1 C2 C3"  ./tools/run_sweep.sh   # Claire
```

### 6. Find your results

```
Output/Sweep/run_<timestamp>/<YourName>/<GroupDir>/<run_label>/seed_N/
  logs/epoch-log.txt          ← population dynamics (main data)
  analysis/analysis.png       ← statistical panels
  analysis/analysis_report.md ← pass/fail summary
  run.ini                     ← exact parameters used
```

### 7. Clean up between runs

```bash
./tools/clean.sh             # wipes Output/ and tmp/ generated files
./tools/clean.sh --dry-run   # preview first
```

### Key knobs at a glance

| What | Variable in `biosim4.ini` | Typical values |
|------|--------------------------|----------------|
| Environment type | `challenge` | `20` (open), `0` (circle), `5` (corner), `11` (wall) |
| Predator fraction | `predatorFraction` | `0.25`, `0.50`, `0.75` |
| Speed asymmetry | `predatorActionPeriod` / `preyActionPeriod` | `1`, `2`, `3` |
| Starvation pressure | `predatorStarvationSteps` | `0` (off), `60`, `120`, `220` |
| Mutation rate | `pointMutationRate` | `0.0001`, `0.001`, `0.01` |
| RNG seed | `RNGSeed` | `1`, `2`, `3` |
| Generations | `maxGenerations` | `400` for sweep runs |
| Burn-in (analysis) | `BURN_IN` in `run_sweep.sh` | `50` (skip first 50 gens) |

---

## Windows Setup

Building on Windows requires a few extra steps. The recommended path is **MSYS2 + MinGW-w64**, which gives you a Linux-style shell and GCC toolchain.

### Step 1 — Install MSYS2

Download and run the installer from https://www.msys2.org/. Once installed, open the **MSYS2 MinGW 64-bit** shell (not the plain MSYS2 shell).

### Step 2 — Install build tools and dependencies

```bash
pacman -Syu   # update package database first, then re-open the shell

pacman -S \
  mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-cmake \
  mingw-w64-x86_64-make \
  mingw-w64-x86_64-sfml \
  mingw-w64-x86_64-tgui \
  mingw-w64-x86_64-cereal \
  git
```

> If `tgui` is not available at version 1.1.x in pacman, download the binary from https://tgui.eu/tutorials/latest-stable/ and point CMake to it manually.

### Step 3 — Build

From the **MSYS2 MinGW 64-bit** shell, `cd` into the project root and run:

```bash
make -j4
# Binary: bin/Release/biosim4.exe
```

### Step 4 — Python

Install Python from https://python.org (tick "Add Python to PATH" during install), then from Command Prompt or PowerShell:

```cmd
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

### Step 5 — Run

```cmd
bin\Release\biosim4.exe biosim4.ini --headless
```

For the sweep script, use the MSYS2 shell (it provides `bash`):

```bash
RUN_GROUPS="B1 B2 B3" ./tools/run_sweep.sh
```

### Windows notes

- The SFML window (non-headless mode) requires the SFML `.dll` files to be on your PATH or in the same folder as the binary. MSYS2's pacman install handles this automatically.
- Video saving (`.avi`) requires `ffmpeg` on PATH: `pacman -S mingw-w64-x86_64-ffmpeg`
- If you see a missing DLL error on launch, run: `pacman -S mingw-w64-x86_64-gcc-libs`

---

## Project Directory Structure

```
biosim4/
├── biosim4.ini              ← main config file (edit experiment parameters here)
├── requirements.txt         ← Python dependencies for analyse.py
├── Makefile                 ← build system
├── src/                     ← C++ simulator source code
│   ├── main.cpp             ← entry point
│   ├── simulator.cpp        ← main simulation loop
│   ├── ai/                  ← neural network, genome, evolution logic
│   ├── userio/              ← SFML window, video writer, headless mode
│   ├── survivalCriteria/    ← challenge definitions (circle, corner, wall, etc.)
│   └── params.cpp/.h        ← all biosim4.ini parameters parsed here
├── bin/Release/biosim4      ← compiled binary (after make)
├── tools/
│   ├── run_sweep.sh         ← main sweep script — edit experiment matrix here
│   ├── analyse.py           ← generates analysis.png and analysis_report.md
│   ├── clean.sh             ← wipes all generated output
│   └── TEAM_DOCS.md         ← this file
├── Output/
│   ├── Sweep/               ← all sweep run results (gitignored)
│   │   └── run_<timestamp>/ ← one folder per sweep invocation
│   ├── Logs/                ← epoch-log.txt from single runs (gitignored)
│   ├── Videos/              ← .avi video frames from single runs (gitignored)
│   ├── Images/              ← misc image output (gitignored)
│   ├── Saves/               ← auto-saved simulation state (gitignored)
│   └── analysis_panels/     ← standalone panel images (gitignored)
├── tmp/
│   └── sweep/               ← per-run .ini copies used during sweep (auto-cleaned, gitignored)
├── tests/                   ← unit tests
└── Resources/               ← fonts and UI assets for SFML window
```

> **Note:** Everything under `Output/` and `tmp/` is gitignored — results stay local. Commit only source code and `biosim4.ini`.

---

## 1. Project Overview

biosim4 is a 2D grid-based neuroevolution simulator where predators and prey evolve neural network-driven behaviours across generations. Each agent's genome encodes a small neural network. Agents that survive (prey) or capture prey (predators) are more likely to reproduce. Over many generations, both populations adapt to each other — a classic co-evolutionary arms race.

**The research question:** Can we observe Lotka-Volterra-style population oscillations (prey leads predator in anti-phase cycles) and Red Queen co-evolutionary dynamics as we vary key ecological parameters?

**The three experiments:**

| Researcher | Variable | Groups |
|------------|----------|--------|
| Bia | Environment (challenge type), mutation rate, predator fraction | B1 – B3 |
| Yannic | Action speed asymmetry (predator vs prey period), environment | Y1 – Y3 |
| Claire | Starvation pressure, regeneration mode | C1 – C4 |

---

## 2. Installation

### Prerequisites

| Dependency | Version | Notes |
|------------|---------|-------|
| C++ compiler | GCC 11+ or Clang 14+ | Must support C++20 |
| CMake | 3.16+ | Or use `make` directly |
| SFML | 2.5.x | Windowed mode only |
| TGUI | 1.1.x | UI widgets — must match SFML version |
| cereal | 1.3.x | C++ serialisation library |
| Python | 3.10+ | For `analyse.py` |

### Step-by-step (macOS)

```bash
# 1. Install system dependencies
brew install cmake sfml tgui cereal

# 2. Clone / enter the project
cd biosim4/

# 3. Build
make -j4
# Binary lands at: bin/Release/biosim4

# 4. Python environment
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Step-by-step (Linux / Ubuntu)

```bash
sudo apt install build-essential cmake libsfml-dev
# TGUI: https://tgui.eu/tutorials/latest-stable/linux/
# cereal: https://uscilab.github.io/cereal/index.html — copy include/ into /usr/local/include/

make -j4
```

### Quick verification

```bash
./bin/Release/biosim4 biosim4.ini --headless   # should run and exit cleanly
```

---

## 3. Stochasticity & Reproducibility

The simulator's random number generator is fully controllable.

```ini
deterministic = true   # use a seeded RNG (not wall-clock time)
RNGSeed       = 1      # integer seed — change to 1, 2, or 3 for replication
numThreads    = 1      # MUST stay at 1 — multiple threads break determinism
```

**What this means for you:**

- With the same `RNGSeed`, every run of the same `.ini` file produces identical output.
- We use **seeds 1, 2, and 3** for every experiment condition. This gives three independent replicates so we can estimate variance without running a huge number of trials.
- `numThreads = 1` is enforced — do not change it, or results become non-deterministic.

The sweep script automatically sets `RNGSeed` to 1, 2, 3 for each condition.

---

## 4. Running a Single Simulation

### Headless (no window — fastest, safe for long runs)

```bash
./bin/Release/biosim4 biosim4.ini --headless
```

Output goes to `Output/Logs/epoch-log.txt` and `Output/Videos/` (if `saveVideo = true`).

### Windowed (with SFML UI)

```bash
./bin/Release/biosim4 biosim4.ini
```

Opens a window. You can pause/unpause with the UI and watch evolution in real time.

### Supplying a custom ini

Copy `biosim4.ini` to a new file, edit your parameters, then pass it:

```bash
./bin/Release/biosim4 my_experiment.ini --headless
```

### Running analysis manually after a run

```bash
source .venv/bin/activate
python3 tools/analyse.py \
    --log     Output/Logs/epoch-log.txt \
    --nets    Output/Videos \
    --out     Output/analysis.png \
    --report  Output/analysis_report.md \
    --burn-in 50 \
    --split-figures
```

---

## 5. Running the Parameter Sweep

The sweep script runs all experiment groups (B1-B3, Y1-Y3, C1-C4), each with 3 seeds, and organises results into a timestamped archive.

### Before you run

```bash
make -j4                    # make sure the binary is built
source .venv/bin/activate   # activate Python environment
```

### Commands

```bash
# Preview what would run — no files created
./tools/run_sweep.sh --dry-run

# Run everything (takes a long time — consider running overnight)
./tools/run_sweep.sh

# Run only your own experiments
RUN_GROUPS="B1 B2 B3"   ./tools/run_sweep.sh    # Bia only
RUN_GROUPS="Y1 Y2 Y3"   ./tools/run_sweep.sh    # Yannic only
RUN_GROUPS="C1 C2 C3"   ./tools/run_sweep.sh    # Claire only

# Run any combination
RUN_GROUPS="B1 Y1 C1"   ./tools/run_sweep.sh
```

### What gets created

```
Output/Sweep/run_20260517_142300/
  Bia/
    B1_environment/
      ch20_open/
        seed_1/
          logs/epoch-log.txt        ← population dynamics
          images/                   ← video frames + neural net .txt files
          analysis/analysis.png     ← all statistical panels
          analysis/analysis_report.md
          run.ini                   ← exact parameters used
          simulator.stdout          ← simulator console output
        seed_2/  ...
        seed_3/  ...
      ch00_circle/  ...
  Yannic/  ...
  Claire/  ...
  sweep_summary.md

Output/Sweep/sweep_20260517_142300.zip   ← everything zipped for sharing
```

### Editing sweep parameters

Open `tools/run_sweep.sh` and edit the **EXPERIMENT MATRIX** block at the top:

```bash
MAX_GENERATIONS=400
SEEDS=(1 2 3)
HEADLESS=true          # true = no window, false = SFML window
SAVE_VIDEO=false       # true = save .avi frames — works with or without HEADLESS
SAVE_NETS=true         # capture neural net snapshots
NETS_STRIDE=10         # one snapshot every N generations
BURN_IN=50             # skip first N generations in statistical tests
```

---

## 6. Cleaning Up Outputs

```bash
./tools/clean.sh --dry-run   # see what would be deleted
./tools/clean.sh             # actually delete it
```

This removes:
- `Output/Sweep/`, `Output/Videos/`, `Output/Images/`, `Output/Logs/`, `Output/Saves/`
- `Output/Profiling/`, `Output/analysis_panels/`
- `Output/analysis.png`, `Output/analysis_report.md`
- `sweep_*.zip` files
- `tmp/sweep/` temp files

**Source code, `biosim4.ini`, and tools are never touched.**

---

## 7. biosim4.ini Variable Reference

### Section A — Experiment knobs (the ones you change)

#### Master toggle

| Variable | Values | Effect |
|----------|--------|--------|
| `predatorPreyEnabled` | `true` / `false` | `true` = two-species coevolution; `false` = single-species baseline (all prey, no predators) |

---

#### 1. Environment — `challenge`

Controls what prey must do to survive. Predators are always selected by kills.

| Value | Name | Description |
|-------|------|-------------|
| `20` | open | No spatial constraint — classical Lotka-Volterra setup |
| `0` | circle | Prey must stay inside a central circle |
| `5` | corner | Prey must reach a corner within 1/4 radius |
| `11` | wall | Prey must press against any wall |
| `1` | right half | Stay in right half of arena |
| `4` | center weighted | Stay near centre |

Sweep recommendation: `20, 0, 5, 11`

---

#### 2. Population balance — `predatorFraction`

| Variable | Range | Effect |
|----------|-------|--------|
| `predatorFraction` | 0.0 – 1.0 | Fraction of population that are predators at start |
| `predatorRatioMode` | `0` or `1` | `0` = fraction is re-applied every generation (fixed); `1` = fraction evolves by relative fitness |
| `predatorRatioFloor` | 0.0 – 1.0 | Minimum predator fraction in mode 1 |
| `predatorRatioCeil` | 0.0 – 1.0 | Maximum predator fraction in mode 1 |
| `predatorRatioGain` | > 0 | Sensitivity of ratio update to fitness imbalance |

**Tip:** Mode `0` is simpler — predators never go extinct or dominate. Use mode `0` for controlled experiments. Mode `1` allows oscillations but can destabilise early.

---

#### 3. Speed asymmetry — `predatorActionPeriod` / `preyActionPeriod`

| Variable | Range | Effect |
|----------|-------|--------|
| `predatorActionPeriod` | integer ≥ 1 | Predator acts every Nth step |
| `preyActionPeriod` | integer ≥ 1 | Prey acts every Nth step |

Lower number = acts more often = faster species.

- `predatorActionPeriod=1, preyActionPeriod=2` → predator 2× faster → predator advantage
- `predatorActionPeriod=2, preyActionPeriod=1` → prey 2× faster → prey advantage
- `predatorActionPeriod=1, preyActionPeriod=1` → balanced

Note: starvation and age timers still tick every step regardless of period.

---

#### 4. Starvation — `predatorStarvationSteps`

| Variable | Range | Effect |
|----------|-------|--------|
| `predatorStarvationSteps` | integer ≥ 0 | `0` = starvation disabled; `>0` = predator dies if no kill before deadline |
| `predatorStarvationGrace` | integer ≥ 0 | Steps at generation start before starvation begins |

This is the key ecological feedback term: fewer prey → fewer kills → more predator starvation → fewer predators → prey recovery. This negative feedback can produce Lotka-Volterra oscillations.

| Value | Effect |
|-------|--------|
| 0 | Starvation off — predators only die from age |
| 40–100 | Strong pressure, many predator deaths |
| 120–220 | Balanced pressure |
| 300–500 | Weak pressure |

---

#### 5. Secondary predator-prey parameters

| Variable | Default | Effect |
|----------|---------|--------|
| `predatorMinCapturesToReproduce` | `3` | Predator must make this many kills to reproduce |
| `predatorCaptureNorm` | `5` | Number of captures that maps to fitness = 1.0 |
| `predatorPreyPerceptionRadius` | `6.0` | Radius for species-detection sensors |
| `preyTopFractionToReproduce` | `0.7` | Top fraction of prey (by fitness) that can reproduce |

---

### Section B — Infrastructure (rarely changed)

| Variable | Default | Notes |
|----------|---------|-------|
| `numThreads` | `1` | **Do not change** — multiple threads break determinism |
| `sizeX` / `sizeY` | `128` | World grid dimensions |
| `population` | `500` | Total number of agents |
| `stepsPerGeneration` | `500` | Simulation steps per generation |
| `maxGenerations` | `200` | How many generations to run |
| `genomeInitialLengthMin/Max` | `14` | Genome length at initialisation |
| `genomeMaxLength` | `300` | Hard cap on genome growth |
| `maxNumberNeurons` | `3` | Maximum hidden neurons in neural net |
| `pointMutationRate` | `0.001` | Per-gene point mutation probability |
| `geneInsertionDeletionRate` | `0.0` | Rate of genome length changes (currently off) |
| `sexualReproduction` | `false` | Sexual vs asexual reproduction |
| `chooseParentsByFitness` | `true` | Fitness-proportional parent selection |
| `genomeComparisonMethod` | `0` | `0` = Jaro-Winkler (handles variable-length genomes) |

---

### Output / video variables

| Variable | Default | Effect |
|----------|---------|--------|
| `imageDir` | `Output/Videos` | Where video frames and net snapshots are written |
| `logDir` | `Output/Logs` | Where `epoch-log.txt` is written |
| `saveVideo` | `true` | Whether to save per-generation `.avi` files |
| `videoStride` | `1` | Save a video frame every Nth generation |
| `videoSaveFirstFrames` | `2` | Always save the first N frames regardless of stride |

---

### Neural net auto-save variables

| Variable | Default | Effect |
|----------|---------|--------|
| `autoSavePredatorNetsPerGeneration` | `1` | How many predator nets to snapshot per generation |
| `autoSavePreyNetsPerGeneration` | `1` | How many prey nets to snapshot per generation |
| `autoSaveNetStride` | `10` | Save a snapshot every N generations |
| `autoSaveNetEpochs` | `1000` | Stop saving after this many generations (`0` = disabled entirely) |

---

### RNG

| Variable | Default | Effect |
|----------|---------|--------|
| `deterministic` | `true` | Seed the RNG from `RNGSeed` |
| `RNGSeed` | `1` | Integer seed — use 1, 2, 3 for replication |

---

## 8. Evolutionary Algorithm Explained

### Genome and neural network

Each agent has a **genome** — a sequence of 24-bit genes. Each gene encodes one synapse: a (source, sink, weight) triplet. The genome is decoded into a **small neural network** at birth.

```
Sensor neurons → [0..maxNumberNeurons hidden neurons] → Action neurons
```

Sensors include: position, local population density, species proximity, oscillator signal, random noise.
Actions include: movement directions, kill attempt (`KILL_FORWARD`).

### Reproduction

At the end of each generation, agents are evaluated by fitness:

- **Prey fitness:** surviving at end of generation (+ meeting the challenge, e.g. reaching the circle)
- **Predator fitness:** number of successful kills (normalised by `predatorCaptureNorm`)

Eligible agents (top prey fraction, predators meeting `predatorMinCapturesToReproduce`) are randomly sampled as parents. Offspring inherit a **mutated copy** of the parent genome.

### Mutation

Point mutations randomly flip bits within genes at rate `pointMutationRate`. This can change synapse weights, sources, or sinks — subtly rewiring the neural network.

### Generation cycle

```
1. Spawn N agents (ratio: predatorFraction predators, rest prey)
2. Run stepsPerGeneration simulation steps
   - Each step: eligible agents execute their NN, move, attempt kills
   - Predators: starvation clock ticks; die if deadline reached without kill
3. End of generation: evaluate fitness
4. Select parents → produce offspring → mutate genomes
5. Repeat for next generation
```

---

## 9. Kill Mechanics

**Kills are not simple collision-based.** Several conditions must all be met:

1. **KILL_FORWARD neuron required.** A predator can only attempt a kill if its neural network has a `KILL_FORWARD` action neuron with activation **above 0.5**.
2. **Prey must be in the exact cell directly ahead.** The kill targets the single grid cell directly in front of the predator.
3. **Probabilistic.** Even if all conditions are met, the kill succeeds with probability proportional to activation strength above 0.5.
4. **Prey must be alive.**

**Implication:** Early generations often have zero kills because predators haven't evolved the `KILL_FORWARD` neuron yet. This bootstrap problem is why `predatorMinCapturesToReproduce` matters — a value of 3+ makes it harder for non-hunting predators to survive.

---

## 10. Video Recording

### Enabling video

```ini
saveVideo = true   # note: automatically disabled in --headless mode
```

### Controlling which generations are recorded

```ini
videoStride           = 1   # record every generation (higher = fewer recordings)
videoSaveFirstFrames  = 2   # always record the first 2 generations
```

### Playing a video

```bash
ffplay Output/Videos/gen-000010.avi
```

### Video in sweep runs

Set `SAVE_VIDEO=true` in `tools/run_sweep.sh`. Video works regardless of `HEADLESS` — the window is not needed for frame writing. Files appear in `seed_N/images/`.

---

## 11. Neural Network Snapshots

### Enabling

In `tools/run_sweep.sh`:

```bash
SAVE_NETS=true    # enable net snapshots
NETS_STRIDE=10    # one snapshot every 10 generations
```

### What is saved

For each saved generation, two `.txt` files are written:

```
gen-000010-pred-id-42.txt     ← predator network connections
gen-000010-prey-id-107.txt    ← prey network connections
```

Each file lists active synapses: source neuron, sink neuron, weight.

### How `analyse.py` uses these

Reads all `.txt` files and produces a **Sensor Usage** panel showing which input sensors predators vs prey rely on over the course of evolution.

---

## 12. Statistical Analysis

Three tests assess our research hypotheses. The burn-in period (controlled by `BURN_IN` in `run_sweep.sh`) skips early generations dominated by random/bootstrap behaviour before the tests run — this reduces noise and gives the tests a fairer signal to work with.

### OSC1 — Population oscillation (autocorrelation)

**Hypothesis:** Population cycles exist (prey leads, predator follows in anti-phase).

**Method:** Compute autocorrelation of predator population. Find dominant period. Check same period appears in prey with a phase offset.

**Passes if:** A significant periodic signal (p < 0.05) is detected in both populations with phase lag consistent with Lotka-Volterra dynamics.

**Interpret:** Failing OSC1 means populations are stable or collapsing, not oscillating. Expected when starvation is off or populations are too small.

---

### OSC2 — Phase lag cross-correlation

**Hypothesis:** Prey population leads predator population by a measurable lag.

**Method:** Compute cross-correlation of prey vs predator. The peak lag should be negative (prey leads).

**Passes if:** Cross-correlation peak falls at a lag consistent with prey leading predator (typically 5–20 generations).

**Note:** Use `predatorRatioMode=0` for baseline experiments — mode `1` actively damps oscillations by adjusting the ratio toward equilibrium.

---

### RED-QUEEN — Co-evolutionary arms race

**Hypothesis:** Both species continuously improve their fitness over time.

**Method:** Fit a linear trend to predator kills per generation and to prey survival rate per generation. Both should be significantly positive.

**Passes if:** Both predator and prey fitness show upward trends simultaneously.

**Interpret:** The hardest test to pass — prey fitness (survival) and predator fitness (kills) partially compete. Most visible in early learning phases or well-balanced conditions.

---

## 13. Interpreting the Analysis Panels

`analysis.png` contains multiple panels:

| Panel | What to look for |
|-------|-----------------|
| Population dynamics | Oscillating predator/prey counts out of phase = good sign |
| Fitness trends | Both lines rising over time = Red Queen |
| OSC1 (autocorrelation) | Clear regular peaks in ACF = oscillation detected |
| OSC2 (cross-correlation) | Peak at negative lag = prey leads predator |
| RED-QUEEN | Both linear fits sloping upward = passes |
| Sensor usage | Predators using prey-proximity sensors, prey using predator-proximity sensors |

`analysis_report.md` gives a plain-English pass/fail for each test.

---

## 14. Experiment Matrix Summary

### Bia — Environment experiments

| Group | Variable swept | Values | Fixed |
|-------|---------------|--------|-------|
| B1 | `challenge` | 20, 0, 5, 11 | default |
| B2 | `pointMutationRate` × `challenge` | rates: 0.0001, 0.001, 0.01; challenges: 20, 0 | default |
| B3 | `predatorFraction` × `challenge` | fractions: 0.25, 0.50, 0.75; challenges: 20, 0 | default |

### Yannic — Speed experiments

| Group | Variable swept | Values | Fixed |
|-------|---------------|--------|-------|
| Y1 | Full 3×3 grid of `predatorActionPeriod` × `preyActionPeriod` | periods: 1, 2, 3 each | challenge=20 |
| Y2 | Speed combo × `challenge` | 3 combos × challenges 20, 0 | default |
| Y3 | Speed combo × `pointMutationRate` | 3 combos × rates 0.0001, 0.001, 0.01 | challenge=20 |

Speed combos: `pred_fast (1,2)`, `balanced (1,1)`, `prey_fast (2,1)`

### Claire — Predator selection pressure experiments

All groups use `challenge=20` (open arena). C2–C4 hold starvation fixed at the best value from C1.

| Group | Variable swept | Values | Fixed |
|-------|---------------|--------|-------|
| C1 | `predatorStarvationSteps` | 0, 60, 120, 220, 400 | challenge=20 |
| C2 | `predatorMinCapturesToReproduce` | 0, 1, 2, 3, 5 | challenge=20, starvation from C1 |
| C3 | `maxNumberNeurons` | 2, 3, 5, 8 | challenge=20, starvation from C1 |
| C4 | `pointMutationRate` | 0.0001, 0.0005, 0.001, 0.005, 0.01 | challenge=20, starvation from C1 |

**Run order:** C1 first — the starvation value that produces the strongest oscillation becomes the fixed baseline for C2, C3, and C4. Update `C_FIXED_STARVATION` in `run_sweep.sh` before running those groups.

**Research questions:**
- C1: How tight does the starvation deadline need to be for Lotka-Volterra oscillations to emerge?
- C2: Does a stricter reproduction gate (requiring more kills) help or hinder predator evolution?
- C3: Does network capacity limit the emergence of hunting behaviour, or is 3 neurons sufficient?
- C4: What mutation rate gives the best co-evolutionary dynamics — too low = no exploration, too high = destroys functional nets?

### Total runs (all groups, 3 seeds each)

| Group | Conditions | Seeds | Runs |
|-------|-----------|-------|------|
| B1 | 4 | 3 | 12 |
| B2 | 6 | 3 | 18 |
| B3 | 6 | 3 | 18 |
| Y1 | 9 | 3 | 27 |
| Y2 | 6 | 3 | 18 |
| Y3 | 9 | 3 | 27 |
| C1 | 5 | 3 | 15 |
| C2 | 5 | 3 | 15 |
| C3 | 4 | 3 | 12 |
| C4 | 5 | 3 | 15 |
| CTRL1 | 4 | 3 | 12 |
| CTRL2 | 1 | 3 | 3 |
| **Total** | | | **207** |

---

*Last updated: May 2026. Questions → Claire.*
