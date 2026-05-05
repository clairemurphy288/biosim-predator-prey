# biosim4 predator-prey analysis

- log: `Output/Logs/epoch-log.txt`
- generations analysed: 29  (burn-in = 0)
- smoothing window: 5

## Predictions

| #    | Prediction | Verdict | Detail |
|------|------------|---------|--------|
| OSC1 | Detrended prey autocorrelation has a negative peak at a positive lag (= half the period) | **PASS** | min lag = 8, r = -0.34, FFT period ≈ 6 gens |
| OSC2 | Cross-correlation peak at positive lag (prey leads predator), permutation-significant | **PASS** | lag = +3, r = +0.46, perm-p = 0.029 |
| RED-QUEEN | Both fitness slopes positive (joint improvement) | _fail_ | pred slope = +6.12e-03/gen (p=0.000); prey slope = -3.48e-03/gen (p=0.044) |

## Notes

- **OSC1** uses the autocorrelation of the *detrended* prey series.  True Lotka-Volterra cycles produce a negative peak at the half-period lag.  A monotonic Red Queen trend never crosses below zero, so detrending separates oscillation from trend.
- **OSC2** is the headline predator-prey test.  Detrended pred and prey series are cross-correlated; a circular-shift permutation null preserves each series' own autocorrelation but destroys the cross-alignment.  Reporting peak lag and permutation p.
- **RED-QUEEN** is a linear regression of mean fitness vs generation for each species.  Both slopes positive **and** small p-values means both species are genuinely improving over time.
