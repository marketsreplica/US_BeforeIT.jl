# First-pass ABM vs. statistical benchmarks — stage-2 revised-data diagnostic

Run 2026-08-10 from commit `a55d9ed`. All numbers below come from the CSVs in this
directory and its sibling `..._burnin`, `..._burnin4` and `..._outlook` directories.

## What this is, and what it is not

The BeforeIT U.S. agent-based model is free-run at **all 61 benchmark origins**
(panel indices 40–100, 2010Q2–2025Q2), 12 quarters each, and scored on exactly the
cells the ten statistical benchmark models are scored on.

| Label | Value |
|---|---|
| `information_track` | `revised_mixed_vintage_diagnostic` |
| `real_time` | **false** |
| `origin_admissible` | **false** |
| `promotion_eligible` | **false** |
| `mixed_vintage_structural_year` | **2024** |
| `abm_forecast_included` | true |
| `h1_opening_row_transient` | **true** |
| `monte_carlo_paths` | 500 (headline), 128 (burn-in variants) |
| `mc_standard_error_reported` | true |
| failures / failed paths | **0 / 0** (61/61 origins, 30 500/30 500 paths) |

This is a **revised-data, mixed-vintage research diagnostic**. It is not a real-time
forecast, not an admitted forecast origin, and not promotion evidence. Historical
origins are reached by making the artifact's single (2024) annual structural row
addressable at earlier dates, so the 68-sector input-output structure, firm and
employee counts, tax rates and population are 2024 values at every origin. Quarterly
initial conditions do have full history.

Reproduce with:

```bash
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_revised_comparison 500 headline
```

Both ABM columns come from the **same** simulated paths: operators are applied
pathwise and only then reduced, to the ensemble **mean** (`beforeit_abm_us_v1_mean`)
and the ensemble **median** (`beforeit_abm_us_v1_median`). The mean is the
RMSE-consistent point forecast; the median is the MAE-consistent one.

Common observation counts are **61 / 60 / 58 / 54 / 50** at h = 1/2/4/8/12 on the
all-available track — identical to the statistical models' own counts, so every
comparison below is on matched cells. Both ABM columns scored `COMPLETE_MATCHED`.

## 1. Headline result — target pair {`real_gdp`, `gdp_deflator`}

Weighted macro-average of cellwise RMSE ratios to the `beforeit_var_p1_constant`
anchor, horizon weights 0.30/0.25/0.20/0.15/0.10, equal target weights.

**All-available track**

| rank | model | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---:|---:|
| 1 | `naive_historical_mean` | 0.8789 | 0.8381 |
| **2** | **`beforeit_abm_us_v1_median`** | **0.9034** | **1.1303** |
| **3** | **`beforeit_abm_us_v1_mean`** | **0.9048** | **1.1370** |
| 4 | `bvar_mniw_v1_p1_constant_*` | 0.9080 | 0.8957 |
| 5 | `univariate_ar_p1_constant` | 0.9179 | 0.8877 |
| 6 | `univariate_ar_bic_p1-8_constant` | 0.9286 | 0.9011 |
| 7 | `univariate_ar_p4_constant` | 0.9387 | 0.9227 |
| 8 | `beforeit_var_p1_constant` (anchor) | 1.0000 | 1.0000 |
| 9 | `naive_no_change` | 1.0748 | 1.1214 |
| 10 | `naive_drift` | 1.1058 | 1.1563 |
| 11 | `beforeit_var_p2_constant` | 2.1207 | 1.4961 |
| 12 | `beforeit_var_p3_constant` | 5.3127 | 2.6721 |

**Balanced-h12 track** (50 origins with a complete 12-quarter future)

| rank | model | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---:|---:|
| 1 | `naive_historical_mean` | 0.8843 | 0.8462 |
| **2** | **`beforeit_abm_us_v1_median`** | **0.8929** | **1.0977** |
| **3** | **`beforeit_abm_us_v1_mean`** | **0.8938** | **1.1022** |
| 4 | `bvar_mniw_v1_p1_constant_*` | 0.9090 | 0.8932 |
| 5 | `univariate_ar_p1_constant` | 0.9185 | 0.8901 |
| 6 | `univariate_ar_bic_p1-8_constant` | 0.9304 | 0.9080 |
| 7 | `univariate_ar_p4_constant` | 0.9416 | 0.9333 |
| 8 | `beforeit_var_p1_constant` (anchor) | 1.0000 | 1.0000 |
| 9 | `naive_no_change` | 1.0715 | 1.1246 |
| 10 | `naive_drift` | 1.1026 | 1.1597 |
| 11 | `beforeit_var_p2_constant` | 2.1223 | 1.4974 |
| 12 | `beforeit_var_p3_constant` | 5.3191 | 2.6852 |

The ABM places **2nd of 12 on RMSE and 8th of 12 on MAE**. The mean/median split is
small (0.9048 vs 0.9034 RMSE; 1.1370 vs 1.1303 MAE): using the loss-consistent
median narrows the MAE gap but does not close it. The RMSE/MAE divergence is a real
property, not a functional-choice artifact — the ABM avoids catastrophic misses
better than it gets typical quarters right.

## 2. Per target and horizon (all-available track)

Rank is among the ten statistical models plus the stated ABM column (x/11).

**ABM ensemble mean**

| target | h | n | ABM RMSE | VAR(1) RMSE | best statistical RMSE | ABM/VAR(1) | rank | ABM bias |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | 6.2592 | 9.0886 | 6.1084 | 0.6887 | **2/11** | -1.32 |
| `real_gdp` | 2 | 60 | 9.5104 | 7.3500 | 6.1355 | 1.2939 | 9/11 | **-7.28** |
| `real_gdp` | 4 | 58 | 6.8762 | 6.3524 | 6.2003 | 1.0825 | 5/11 | -2.94 |
| `real_gdp` | 8 | 54 | 6.7381 | 7.8571 | 6.4203 | 0.8576 | 5/11 | -2.15 |
| `real_gdp` | 12 | 50 | 6.9637 | 6.7300 | 6.6472 | 1.0347 | 7/11 | -2.02 |
| `gdp_deflator` | 1 | 61 | 1.4288 | 1.7999 | 1.4119 | 0.7938 | 3/11 | -0.19 |
| `gdp_deflator` | 2 | 60 | 1.6486 | 2.1374 | 1.5829 | 0.7713 | 5/11 | -0.29 |
| `gdp_deflator` | 4 | 58 | 1.9398 | 2.3589 | 1.9408 | 0.8223 | **1/11** | -0.40 |
| `gdp_deflator` | 8 | 54 | 2.0391 | 2.0911 | 2.0248 | 0.9751 | 3/11 | -0.53 |
| `gdp_deflator` | 12 | 50 | 2.1093 | 2.3655 | 2.1014 | 0.8917 | 3/11 | -0.61 |
| `nominal_gdp` | 1 | 61 | 7.0266 | 10.4245 | 6.8856 | 0.6740 | **2/11** | -1.51 |
| `nominal_gdp` | 2 | 60 | 10.1803 | 8.7177 | 6.9267 | 1.1678 | 9/11 | -7.57 |
| `nominal_gdp` | 4 | 58 | 7.7626 | 7.3856 | 7.0417 | 1.0510 | 4/11 | -3.34 |
| `nominal_gdp` | 8 | 54 | 7.7071 | 8.7388 | 7.2875 | 0.8819 | 4/11 | -2.67 |
| `nominal_gdp` | 12 | 50 | 7.9643 | 7.7455 | 7.5484 | 1.0282 | 7/11 | -2.63 |
| `unemployment_rate` | 1 | 61 | 2.8578 | 2.1029 | 1.3231 | 1.3590 | 10/11 | -1.97 |
| `unemployment_rate` | 2 | 60 | 2.2001 | 3.3082 | 1.6595 | 0.6650 | 6/11 | -0.86 |
| `unemployment_rate` | 4 | 58 | 1.9697 | 4.1676 | 1.9849 | 0.4726 | 1/11 | -0.06 |
| `unemployment_rate` | 8 | 54 | 1.9205 | 2.2418 | 2.0863 | 0.8567 | 1/11 | +0.19 |
| `unemployment_rate` | 12 | 50 | 1.8143 | 3.8982 | 2.1209 | 0.4654 | 1/11 | +0.08 |
| `effective_federal_funds_rate` | 1 | 61 | 0.3734 | 0.6638 | 0.2720 | 0.5626 | 4/11 | -0.04 |
| `effective_federal_funds_rate` | 2 | 60 | 0.6921 | 1.2451 | 0.5632 | 0.5559 | 3/11 | -0.09 |
| `effective_federal_funds_rate` | 4 | 58 | 1.2188 | 2.0724 | 1.1273 | 0.5881 | 3/11 | -0.20 |
| `effective_federal_funds_rate` | 8 | 54 | 1.8935 | 2.3793 | 1.9670 | 0.7958 | **1/11** | -0.50 |
| `effective_federal_funds_rate` | 12 | 50 | 2.1670 | 2.6884 | 2.0989 | 0.8060 | 2/11 | -0.79 |

The `unemployment_rate` rows are **not scored** anywhere in this report — see §7.

**ABM ensemble median** — differences from the mean are third-decimal on RMSE. The
only rank change on the headline pair is `real_gdp` h=8 (5/11 → 3/11, RMSE 6.7381 →
6.7132). Full table in `relative_scores.csv`.

## 3. Secondary targets {`nominal_gdp`, `effective_federal_funds_rate`}

| rank | model | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---:|---:|
| 1 | `univariate_ar_bic_p1-8_constant` | 0.7796 | 0.8164 |
| **2** | **`beforeit_abm_us_v1_median`** | **0.7810** | **0.9620** |
| **3** | **`beforeit_abm_us_v1_mean`** | **0.7824** | **0.9705** |
| 4 | `univariate_ar_p4_constant` | 0.7912 | 0.8326 |
| 5 | `bvar_mniw_v1_p1_constant_*` | 0.8093 | 0.8639 |
| 6 | `univariate_ar_p1_constant` | 0.8307 | 0.7953 |
| 7 | `naive_no_change` | 0.9050 | 0.8840 |
| 8 | `naive_drift` | 0.9632 | 1.0233 |
| 9 | `beforeit_var_p1_constant` (anchor) | 1.0000 | 1.0000 |
| 10 | `naive_historical_mean` | 1.2590 | 1.7103 |
| 11 | `beforeit_var_p2_constant` | 1.5804 | 1.2456 |
| 12 | `beforeit_var_p3_constant` | 3.5431 | 1.9897 |

`nominal_gdp` is the exact sum of the two headline targets and carries no independent
information. The policy rate is the ABM's strongest target (ratios 0.56–0.81, ranks
4/3/3/1/2), but `model.data.euribor` is the model's own internal Taylor-rule rate and
is explicitly **not an approved EFFR bridge**; treat that column as indicative only.

## 4. Pandemic-masked partition — the ABM's result does not survive it

Cells whose **target** period falls in 2020Q1–2021Q4 are dropped. This is the
project's frozen `PT_ACUTE` window (a target-date cut, not an origin-date cut); the
masked track is `PT_PRE` + `PT_POST`. Counts fall to 53/52/50/46/42.

| rank | model | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---:|---:|
| 1 | `univariate_ar_p1_constant` | 0.8480 | 0.8295 |
| 2 | `bvar_mniw_v1_p1_constant_*` | 0.8518 | 0.8664 |
| 3 | `univariate_ar_bic_p1-8_constant` | 0.8699 | 0.8520 |
| 4 | `naive_historical_mean` | 0.8806 | 0.8194 |
| 5 | `univariate_ar_p4_constant` | 0.8885 | 0.8636 |
| 6 | `beforeit_var_p1_constant` (anchor) | 1.0000 | 1.0000 |
| 7 | `naive_no_change` | 1.2577 | 1.1978 |
| **8** | **`beforeit_abm_us_v1_median`** | **1.2641** | **1.4352** |
| **9** | **`beforeit_abm_us_v1_mean`** | **1.2723** | **1.4484** |
| 10 | `naive_drift` | 1.3252 | 1.2550 |
| 11 | `beforeit_var_p2_constant` | 3.7218 | 1.8412 |
| 12 | `beforeit_var_p3_constant` | 11.8057 | 4.0167 |

**This is the single most important caveat in the report.** The ABM goes from 2nd to
9th (mean) / 8th (median), and from beating the anchor to losing to it by 27%. Its
headline standing is substantially earned on the pandemic quarters, where every
statistical model fails badly and the ABM's very wide predictive spread and downward
bias happen to be less wrong. On the ordinary-times sample the ABM is beaten by every
non-degenerate statistical model. The semi-structural comparison saw the same kind of
demotion under this cut, so the pattern is not ABM-specific — but it is not a small
effect and no headline claim should be quoted without it.

## 5. Burn-in sensitivity — the opening transient is real, and burn-in does not fix it

Row 1 of `model.data` is written on a different measurement basis from rows 2+
(real GDP is set equal to nominal GDP, so the deflator is exactly 1.0). The prescribed
sensitivity builds the model one quarter before the origin, steps once, and treats
that row as the origin. I also ran a four-quarter version to test whether the
disturbance decays. Both at 128 paths.

**Effect on the ABM mean column, all-available track**

| target | h | headline RMSE | 1q burn-in | 4q burn-in | headline bias | 1q bias | 4q bias |
|---|---:|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 6.2592 | 9.4889 | 6.6260 | -1.32 | -7.29 | -2.72 |
| `real_gdp` | 2 | 9.5104 | 7.5995 | 6.5522 | **-7.28** | -4.57 | **-2.37** |
| `real_gdp` | 4 | 6.8762 | 6.7998 | 6.5242 | -2.94 | -2.74 | -2.16 |
| `real_gdp` | 8 | 6.7381 | 6.7543 | 6.7025 | -2.15 | -2.11 | -2.00 |
| `real_gdp` | 12 | 6.9637 | 6.9235 | 6.7966 | -2.02 | -1.93 | -1.58 |
| `gdp_deflator` | 1 | 1.4288 | 1.6423 | 1.9293 | -0.19 | -0.27 | -0.45 |
| `gdp_deflator` | 2 | 1.6486 | 1.8254 | 1.9701 | -0.29 | -0.36 | -0.49 |
| `gdp_deflator` | 4 | 1.9398 | 1.9661 | 1.9808 | -0.40 | -0.43 | -0.52 |
| `gdp_deflator` | 8 | 2.0391 | 2.0493 | 2.0306 | -0.53 | -0.55 | -0.59 |
| `gdp_deflator` | 12 | 2.1093 | 2.1152 | 2.1187 | -0.61 | -0.63 | -0.65 |

Weighted RMSE ratio on the headline pair, all-available track:

| variant | ABM mean | ABM median | rank of the mean column |
|---|---:|---:|---:|
| headline (no burn-in, 500 paths) | **0.9048** | 0.9034 | 3/12 |
| one-quarter burn-in (128 paths) | 0.9540 | 0.9502 | 7/12 |
| four-quarter burn-in (128 paths) | 0.9156 | 0.9152 | 4/12 |

**Both burn-ins make the headline worse.** The one-quarter burn-in does not remove the
transient, it *relocates* it: `real_gdp` h=1 RMSE jumps 6.26 → 9.49 and its bias goes
-1.32 → -7.29, i.e. exactly the h=2 pathology moved to h=1, which carries the larger
horizon weight (0.30 vs 0.25). The four-quarter burn-in genuinely does drain it — h=2
real-GDP bias falls from -7.28 to -2.37, in line with the other horizons — but it
costs four quarters of initialization information and degrades the deflator at short
horizons (h=1 RMSE 1.43 → 1.93), so the net weighted ratio still worsens.

Conclusion for the next iteration: the transient is a several-quarter relaxation of
the opening state, not a one-row artifact, and burning it off by discarding
information is not a profitable trade. The fix belongs in the opening-state
construction, not in the scoring window. (The four-quarter variant is an addition
beyond the original brief; it is what turned "burn-in helps" into "burn-in cannot
help this way".)

## 6. Monte-Carlo precision at 500 paths

Mean across origins of `ensemble_sd / sqrt(n_paths)`, headline run.

| target | h | mean ensemble sd | mean MC s.e. | max MC s.e. | mean MC s.e. / RMSE |
|---|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 3.291 | 0.1472 | 0.2397 | 0.0235 |
| `real_gdp` | 2 | 2.811 | 0.1257 | 0.2071 | 0.0132 |
| `real_gdp` | 4 | 3.108 | 0.1390 | 0.2234 | 0.0202 |
| `real_gdp` | 8 | 3.016 | 0.1349 | 0.2314 | 0.0200 |
| `real_gdp` | 12 | 2.883 | 0.1289 | 0.2314 | 0.0185 |
| `gdp_deflator` | 1 | 0.860 | 0.0384 | 0.0531 | 0.0269 |
| `gdp_deflator` | 2 | 1.005 | 0.0450 | 0.0686 | 0.0273 |
| `gdp_deflator` | 4 | 1.070 | 0.0479 | 0.0846 | 0.0247 |
| `gdp_deflator` | 8 | 1.069 | 0.0478 | 0.0931 | 0.0234 |
| `gdp_deflator` | 12 | 1.035 | 0.0463 | 0.1025 | 0.0219 |
| `effective_federal_funds_rate` | 1–12 | 0.139–0.337 | 0.0062–0.0151 | ≤0.019 | 0.007–0.017 |
| `unemployment_rate` | 1–12 | 0.369–0.859 | 0.0165–0.0384 | ≤0.064 | 0.006–0.021 |

MC standard error is **0.7–2.7% of RMSE** everywhere. Removing it entirely would move
the weighted ratio by 0.0002. **500 paths is more than enough; Monte-Carlo noise is a
non-issue at this path count** (it was worth ~0.05 at the 16-path pilot). Full table
in `monte_carlo_errors.csv`.

## 7. Gap ranking — what to fix next, in order of measured value

Best statistical model on the headline pair is `naive_historical_mean` at 0.8789; the
ABM mean column is at 0.9048, a gap of **+0.0259**. Cell-by-cell decomposition
(weight × ratio difference):

| target | h | weight | ABM ratio | best-model ratio | contribution to gap |
|---|---:|---:|---:|---:|---:|
| `real_gdp` | 2 | 0.125 | 1.2939 | 0.8348 | **+0.0574** |
| `real_gdp` | 4 | 0.100 | 1.0825 | 0.9792 | +0.0103 |
| `real_gdp` | 8 | 0.075 | 0.8576 | 0.8171 | +0.0030 |
| `real_gdp` | 1 | 0.150 | 0.6887 | 0.6721 | +0.0025 |
| `real_gdp` | 12 | 0.050 | 1.0347 | 0.9899 | +0.0022 |
| `gdp_deflator` | 8 | 0.075 | 0.9751 | 0.9683 | +0.0005 |
| `gdp_deflator` | 12 | 0.050 | 0.8917 | 0.8887 | +0.0002 |
| `gdp_deflator` | 4 | 0.100 | 0.8223 | 0.8251 | -0.0003 |
| `gdp_deflator` | 2 | 0.125 | 0.7713 | 0.8832 | -0.0140 |
| `gdp_deflator` | 1 | 0.150 | 0.7938 | 1.0338 | **-0.0360** |

Counterfactual weighted RMSE ratios, ABM mean column, headline pair:

| counterfactual | weighted ratio | change |
|---|---:|---:|
| measured (500 paths) | 0.9048 | — |
| remove the systematic bias in every cell | **0.8202** | **-0.0846** |
| remove finite-path Monte-Carlo noise | 0.9045 | -0.0002 |
| substitute the one-quarter burn-in cells | 0.9540 | +0.0492 |
| substitute the four-quarter burn-in cells | 0.9156 | +0.0108 |

**Ranked deficiencies, by measured contribution:**

1. **Systematic under-forecast of real growth — worth ≈0.085, by far the largest
   lever.** The ABM's mean error is negative at every horizon of every target
   (`real_gdp` -1.32/-7.28/-2.94/-2.15/-2.02 pp). Removing bias alone would take the
   weighted ratio to 0.8202 and make the ABM the **best** model on this pair. This is
   the known shrinking-GDP drift and it is the whole story.
2. **The h=2 opening transient — worth ≈0.057 of the 0.026 net gap.** One cell,
   `real_gdp` h=2, contributes more than twice the entire deficit. It is a
   several-quarter relaxation of the opening state (§5), not a one-row artifact, and
   burn-in cannot remove it without paying more elsewhere. Fix the opening-state
   construction.
3. **Pandemic dependence — not a gap contributor but a validity threat (§4).** Masking
   2020Q1–2021Q4 moves the ABM from 2nd to 8th/9th. Any real improvement must show up
   on the masked partition too, or it is not an improvement.
4. **Persistent mid-horizon level error at h=4 — worth ≈0.010.** Distinct from the
   opening transient: h=4 bias (-2.94) is worse than h=8 (-2.15) and h=12 (-2.02),
   so the model overshoots downward before settling.
5. **Unemployment stock artifact — currently costs nothing because it is excluded
   (§8), but it blocks a fifth target.** Fetching historical annual CPS
   (`unemployed_census`, `employees`, `population`) would unlock it.
6. **Monte-Carlo noise — worth 0.0002. Solved. Do not spend more paths.**

The deflator needs no work: the ABM already beats the best statistical model at h=1
(-0.0360) and h=2 (-0.0140) and ties it at h=4.

## 8. Appendix — why `unemployment_rate` is excluded from every scored table

The ABM's h=1 unemployment forecast is **essentially constant across the whole
sample**: range 3.492–3.679 pp, standard deviation **0.049 pp**, against a realized
range of 3.533–13.0 pp and standard deviation 2.115 pp.

| origin | ABM h=1 forecast | actual |
|---|---:|---:|
| 2010Q2 | 3.664 | 9.467 |
| 2013Q2 | 3.679 | 7.233 |
| 2017Q4 | 3.641 | 4.033 |
| 2020Q2 | 3.636 | 8.800 |
| 2020Q4 | 3.564 | 6.233 |
| 2025Q2 | 3.564 | 4.333 |

The initial unemployed stock comes from `calibration["unemployed_census"]`, one of the
length-1 annual arrays frozen at 2024, so the model opens every historical origin at
the 2024 labour market regardless of the actual level. Its apparent wins at h=4/8/12
(ranks 1/11) are a constant sitting near the sample mean — note that
`naive_historical_mean` is the best statistical model in exactly those cells. **This
is an artifact, not skill**, and none of these numbers should be quoted as a result.

## 9. Current outlook — unscored, out of sample

Origins 2026Q1 and 2025Q4 lie beyond the end of the revised panel (2025Q3), so **no
realized truth exists and nothing here is scored**. 500 paths, full percentile fan in
`../abm_revised_comparison_outlook/current_outlook.csv`.

**Origin 2026Q1, next four quarters** (annualized percent):

| quarter | real GDP mean | median | p10 | p90 | deflator mean | median | p10 | p90 | EFFR mean |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2026Q2 | **+1.75** | +1.76 | -4.92 | +8.46 | **3.13** | 3.13 | 1.85 | 4.53 | 3.60 |
| 2026Q3 | **-4.92** | -4.74 | -9.92 | -0.18 | **2.91** | 3.01 | 1.23 | 4.48 | 3.57 |
| 2026Q4 | **-2.48** | -2.20 | -8.22 | +2.99 | **2.71** | 2.71 | 0.96 | 4.57 | 3.54 |
| 2027Q1 | **-0.30** | -0.13 | -5.92 | +5.49 | **2.64** | 2.72 | 0.77 | 4.62 | 3.50 |

Beyond h=4 real growth settles at roughly **0.0 to +0.3%** annualized through 2029Q1,
deflator inflation drifts down from 2.5% to **2.2–2.3%**, and the policy rate declines
steadily from 3.60% to **3.15%**. The 2025Q4 origin gives the same shape (h=1 +1.35,
h=2 -4.89, then ≈0).

**Read this with §5 in mind.** The h=2 dive to -4.92% is the opening transient, not a
forecast of a 2026Q3 recession — the same -5 to -7 pp h=2 artifact appears at all 61
historical origins. The flat ≈0% long-run growth is the documented shrinking-GDP
drift. The honest summary of what the model says about the future is: **inflation
converging to ≈2.2–2.3%, policy rate easing to ≈3.2%, and real growth that the model
cannot be trusted to level-calibrate.**

## 10. Caveat list

1. **Mixed vintage.** 2024 input-output structure, firm/employee counts, tax rates and
   population at every origin from 2010 on. Future information at historical origins.
   Benign for flow targets built from quarterly series; fatal for stock-initialized
   ones (§8).
2. **Not real time.** Revised-data panel; same caveat already applies to all ten
   statistical models. `origin_admissible = false`, `promotion_eligible = false`.
3. **The pandemic partition reverses the headline (§4).** 2nd → 8th/9th.
4. **h=1 and h=2 carry the opening-row transient (§5)**, and they carry the two largest
   horizon weights (0.30 and 0.25).
5. **The ABM under-forecasts real growth at every horizon (§7.1).** The competitive
   RMSE ratio partly reflects a weak VAR(1) anchor, not ABM accuracy.
6. **MAE is poor** (1.14 mean / 1.13 median vs 0.84 for the best statistical model)
   even with the loss-consistent median.
7. **`effective_federal_funds_rate` uses the model's internal Taylor-rule rate**, not
   an approved EFFR bridge.
8. **`unemployment_rate` is an artifact (§8)** and is excluded from all scored tables.
9. **`pce_price_index`, `core_pce_price_index` and `payroll_employment` are absent** —
   they need measurement bridges the model does not provide, so the ABM is compared on
   5 of the 8 registered targets and scored on 4.
10. **50 h=12 errors, ~4 non-overlapping spans.** No formal superiority test is
    performed and none is warranted at this sample size.
11. **Burn-in variants use 128 paths, not 500**, so their cells carry ~2x the
    Monte-Carlo noise of the headline — immaterial (§6) but stated.
