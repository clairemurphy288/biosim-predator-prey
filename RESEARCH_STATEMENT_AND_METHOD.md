# Research Problem Statement and Methodology

## Problem Statement

Classical predator-prey theory predicts coupled oscillations where prey abundance increases first, predator abundance follows with delay, prey then declines under predation pressure, and predator abundance later declines due to reduced food availability. The core research problem in this project is:

**Can predator-prey dynamics emerge in a neuroevolutionary agent-based simulation without hard-coding ecological strategy, and under what environmental and ecological parameter settings are these dynamics most likely to appear?**

This project treats emergence as the central scientific target: agents begin with random genomes and adapt only through selection across generations. The goal is not to force oscillations, but to test whether they appear robustly from predator-prey interaction plus evolutionary pressure.


## Formal Research Question

**To what extent does a two-species neuroevolution simulation produce statistically detectable predator-prey dynamics (oscillation, phase lag, and coevolutionary fitness gain), and how are these outcomes modulated by environment geometry, species speed asymmetry, initial predator fraction, and predator starvation pressure?**


## Hypotheses

1. **OSC1 (Oscillation):** The detrended prey survivor series exhibits a negative autocorrelation peak at positive lag, consistent with cyclic dynamics.
2. **OSC2 (Phase lag):** Cross-correlation between detrended predator and prey survivor series peaks at positive lag (prey leads predator), with significance under permutation testing.
3. **RED-QUEEN (Coevolution):** Predator and prey mean fitness both increase across generations (positive trend slopes), indicating joint adaptation.


## Experimental Design

### Independent variables (experiment matrix)

1. **Environment:** `challenge`
2. **Population balance ("size"):** `predatorFraction`
3. **Relative speed:** `predatorActionPeriod`, `preyActionPeriod`
4. **Predator mortality pressure:** `predatorStarvationSteps` (with `predatorStarvationGrace`)

### Secondary control variables

- `predatorRatioMode`, `predatorRatioFloor`, `predatorRatioCeil`, `predatorRatioGain`
- `predatorMinCapturesToReproduce`, `predatorCaptureNorm`
- `preyTopFractionToReproduce`

### Controls and treatments

- **Control:** `predatorPreyEnabled=false` (single-species baseline)
- **Treatment:** `predatorPreyEnabled=true` (predator-prey coevolution active)


## Simulation Procedure

For each run:

1. Initialize a population with random genomes.
2. Simulate `stepsPerGeneration` timesteps.
3. Apply survival and reproduction criteria at generation end:
   - Predator survival/reproduction depends on captures.
   - Prey survival/reproduction depends on challenge success (plus evasion pressure).
4. Spawn next generation with mutation.
5. Repeat for `maxGenerations`.
6. Log per-generation metrics to `Output/Logs/epoch-log.txt`.


## Analysis Pipeline

Run with `tools/analyse.py`, which computes:

- **OSC1:** autocorrelation on detrended prey survivor series
- **OSC2:** cross-correlation on detrended predator/prey survivor series + circular-shift permutation null
- **RED-QUEEN:** linear trend slopes for predator and prey mean fitness
- **Qualitative evidence:** population traces and sensor usage trends

Outputs:

- `Output/analysis.png`
- `Output/analysis_panels/*.png` (optional split figures)
- `Output/analysis_report.md` (prediction verdict table)


## Interpretation Notes

- With fixed total population, oscillation is primarily observed in species-specific survivor trajectories and/or predator fraction over generations, not in absolute total population size.
- If `predatorRatioMode=0` (fixed ratio), results are interpreted as oscillation in coevolutionary performance rather than full ecological ratio feedback.
- If `predatorRatioMode=1`, predator/prey composition can change generation-to-generation, giving stronger ecological population-dynamics interpretation.


## Suggested Reporting Language

This study evaluates whether predator-prey dynamics can emerge from evolutionary adaptation in a neural agent population. Evidence is assessed using predefined statistical criteria for oscillation and lag structure, complemented by qualitative inspection of evolved network sensor usage and population trajectories.
