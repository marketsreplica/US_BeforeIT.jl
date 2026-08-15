# `beforeit_abm_us_v2` — commodity-balance reconciliation + random-walk-with-drift expectations

Branch `claude/abm-v2`, based on `a55d9ed`. Every number below comes from the CSVs written by
the runs named in each section; nothing is quoted from memory or from a different tree.

**Information labels that must travel with every number in this file.**
`information_track = revised_mixed_vintage_diagnostic`, `origin_admissible = false`,
`promotion_eligible = false`, `real_time = false`, `mixed_vintage_structural_year = 2024`,
`h1_opening_row_transient = true`, `monte_carlo_paths = 500`, `scale = 1e-5`.

---

## 1. What v2 changes

Two changes, both in the calibration artifact rather than in behavioural parameters.

### 1.1 The opening commodity balance now clears

The shipped U.S. calibration's opening commodity balance does not clear. Per commodity, modelled
uses differ from supply (domestic industry output plus measured BEA T262 imports) by **−70.6 % to
+47.6 %**: 42 of 68 commodities over-demanded, 34 with `|gap| > 10 %`, 8 with `|gap| > 25 %`.
Because every firm's capacity envelope is frozen at `K_i·κ_i = Y_i/0.85` and investment is
replacement-only (`K_end/K_1 = 1.0000` measured), the over-demanded sectors sit permanently against
their ceiling and the under-demanded ones sit permanently idle. `min()` is one-sided, so the idle
capacity never compensates. Measured consequence in v1: **12.5 % of gross output is produced under
a binding capacity ceiling every quarter**, exports fill only 87 %, and real growth is pinned near
zero.

`scripts/us/calibration/reconcile_commodity_balance.jl` applies a biproportional (RAS /
minimum-I-divergence) adjustment to the **use side only**, at the flow level, then re-derives every
coefficient from the balanced flows and writes them back in the raw pre-valuation-bridge basis so
that the *unmodified* library pipeline reproduces the balanced flows exactly.

* Row controls: `industry_output + imports`. **`use_explicit_trade` stays `true`** — no measured
  BEA import level is discarded.
* Column controls: the 68 industry intermediate budgets and the four final-demand budgets.
* Zeros preserved; converged in 543 iterations; column budgets move by `< 1e-13`; the artifact
  re-derives to `max |uses_g/supply_g − 1| = 1.0e-13`.
* `use_commodity_balance_inventory` set to `false`: with the balance clearing there is no signed
  discrepancy to promote into `S_s`, and the reference specification opens with `S_i(0) = 0`. This
  also removes the artifact ↔ `scripts/us/USPipeline.jl:3441` contradiction.

**The one accounting choice, stated explicitly.** Uses exceed supply by **1.0104 %** in aggregate.
That residual decomposes exactly (to `5.6e-9`) into

| term | value (US$m) | meaning |
|---|---:|---|
| expenditure GDP − production GDP | 442 933 | the artifact's own statistical discrepancy, 1.57 % of GDP |
| capital consumption − non-dwelling GFCF | 88 223 | net non-dwelling fixed investment is negative in the artifact |
| **total** | **531 156** | = `sum(uses) − sum(supply)` |

RAS needs `sum(rows) == sum(cols)`, so one control must move. v2 anchors on the **production**
account: the four final-demand aggregates C, G, I and X — and `capital_consumption` and
`gross_capitalformation_dwellings`, which together set the investment budget — are scaled by

```
lambda = (supply − intermediates) / (C + G + I + X) = 0.983460
```

`lambda` is fixed by the accounting identity alone and was **not** chosen with reference to any
forecast error. It is recorded in every manifest as `reconciliation_lambda` together with
`reconciliation_lambda_semantics`. The alternative closure (hold every measured budget and let a
uniform 1.01 % excess-demand wedge survive) was built and measured too; it overshoots, because a
uniform 1 % excess demand is itself a growth impulse. See §6.

### 1.2 Growth expectations are a random walk with drift

`gamma_e` came from an AR(1) with constant fitted to the **log level** of gross output. That
estimator is mis-specified for an I(1)-with-drift series: with the small-sample downward bias on
`alpha` it delivers `g·[1 − (1−alpha)·T/2]`, measured at **32–63 %** of the in-sample trend at every
origin from 1998 to 2026. v2 pins `alpha = 1` and takes the drift as the average past log growth —
the correctly specified estimator for the same series, using past data only.

The change is gated behind a new `expectation_rw_drift` model property, registered only when the
calibration artifact carries the marker. **Default `false`, so Austria and Italy are bit-identical**
(gate G3 below). Exactly one Normal variate is consumed on either branch, so matched-seed
comparisons stay aligned.

---

## 2. Regression gates

| # | gate | threshold | result |
|---|---|---|---|
| G1 | matched-grid completeness | 61 origins, common observation counts 61/60/58/54/50, no `INCOMPLETE_MATCHED_GRID_NOT_RANKED` | **PASS** — 61/61 origins, counts `[61, 60, 58, 54, 50]` all-available, `[50, 50, 50, 50, 50]` balanced, `[53, 52, 50, 46, 42]` pandemic-masked; every ABM column `COMPLETE_MATCHED` |
| G2 | no non-finite output | 0 | **PASS** — 0 non-finite cells in 3 660 + 3 660 + 120 ensemble rows; `paths_used = 500` at every origin; `paths_failed = 0`; `failures.csv` empty |
| G3 | Austria/Italy unchanged with the flag off | bit-identical | **PASS** — `AUSTRIA2010Q1`, 3 seeds × {real_gdp, nominal_gdp, euribor}, SHA-256 of the raw `Float64` vectors identical between a pristine `a55d9ed` checkout and the patched worktree |
| G4 | v1 column reproduces the pre-patch v1 run | bit-identical | **PASS** — all **3 660** cached v1 ensemble cells identical (`max |diff| = 0`) to the concurrent agent's unpatched 500-path v1 run, and the weighted scores match to every printed digit (0.9048 / 0.9034 mean / median) |
| G5 | GDP-deflator inflation stays ~2 % | no regression vs v1 | **PASS** — v2 mean 2.019 pp (p5 1.663, p95 2.687) against v1 2.024 pp over the same 671 scored cells; per-horizon v2 bias −0.19 / −0.29 / −0.42 / −0.53 / −0.62 pp vs v1 −0.19 / −0.29 / −0.40 / −0.53 / −0.61 pp. The reconciliation is a quantity intervention and leaves pricing untouched — at h = 1 the two columns are bit-identical |
| G6 | commodity balance clears in the shipped artifact | `max |uses/supply − 1| < 1e-6` | **PASS** — 1.0e-13 after re-derivation through the unmodified pipeline; RAS column budgets moved < 1e-13 |
| G7 | package test suite | green | **PARTIAL — pre-existing failure.** 815 pass, 1 fail. The single failure is `Format (Runic.jl)`, which walks the whole repository and already failed at `a55d9ed` on ten `scripts/` files untouched by this work. Every file authored or edited here is Runic-clean. Tracked separately |
| G8 | unemployment | report, do not gate | **REPORTED, FAILING ON MERIT** — see §6.2. `unemployment_rate` stays out of every weighted score |

---

## 3. Headline standings

**What "14 columns" means.** The field is 14 *forecast columns*, not 14 independent
models: ten benchmark models (VAR, BVAR, AR variants and naive rules) plus four ABM
ensemble columns — mean and median, for each of two runs (v1 and v2). The two ABM
runs share a seed stream and differ only in the calibration artifact, so the four
ABM columns are not independent of one another. Ranks below are positions among
these 14 scored columns.

**Headline pair {real_gdp, gdp_deflator} — `all-available`**

| rank | model | status | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---|---:|---:|
| 1 | **beforeit_abm_us_v2_mean** | COMPLETE_MATCHED | 0.8295 | 0.8135 |
| 2 | **beforeit_abm_us_v2_median** | COMPLETE_MATCHED | 0.8301 | 0.8154 |
| 3 | naive_historical_mean | COMPLETE_MATCHED | 0.8789 | 0.8381 |
| 4 | _beforeit_abm_us_v1_median_ | COMPLETE_MATCHED | 0.9034 | 1.1303 |
| 5 | _beforeit_abm_us_v1_mean_ | COMPLETE_MATCHED | 0.9048 | 1.1370 |
| 6 | bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale | COMPLETE_MATCHED | 0.9080 | 0.8957 |
| 7 | univariate_ar_p1_constant | COMPLETE_MATCHED | 0.9179 | 0.8877 |
| 8 | univariate_ar_bic_p1-2-3-4-5-6-7-8_constant | COMPLETE_MATCHED | 0.9286 | 0.9011 |
| 9 | univariate_ar_p4_constant | COMPLETE_MATCHED | 0.9387 | 0.9227 |
| 10 | beforeit_var_p1_constant | COMPLETE_MATCHED | 1.0000 | 1.0000 |
| 11 | naive_no_change | COMPLETE_MATCHED | 1.0748 | 1.1214 |
| 12 | naive_drift | COMPLETE_MATCHED | 1.1058 | 1.1563 |
| 13 | beforeit_var_p2_constant | COMPLETE_MATCHED | 2.1207 | 1.4961 |
| 14 | beforeit_var_p3_constant | COMPLETE_MATCHED | 5.3127 | 2.6721 |

**Headline pair {real_gdp, gdp_deflator} — `balanced h=12`**

| rank | model | status | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---|---:|---:|
| 1 | **beforeit_abm_us_v2_mean** | COMPLETE_MATCHED | 0.8292 | 0.8104 |
| 2 | **beforeit_abm_us_v2_median** | COMPLETE_MATCHED | 0.8297 | 0.8121 |
| 3 | naive_historical_mean | COMPLETE_MATCHED | 0.8843 | 0.8462 |
| 4 | _beforeit_abm_us_v1_median_ | COMPLETE_MATCHED | 0.8929 | 1.0977 |
| 5 | _beforeit_abm_us_v1_mean_ | COMPLETE_MATCHED | 0.8938 | 1.1022 |
| 6 | bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale | COMPLETE_MATCHED | 0.9090 | 0.8932 |
| 7 | univariate_ar_p1_constant | COMPLETE_MATCHED | 0.9185 | 0.8901 |
| 8 | univariate_ar_bic_p1-2-3-4-5-6-7-8_constant | COMPLETE_MATCHED | 0.9304 | 0.9080 |
| 9 | univariate_ar_p4_constant | COMPLETE_MATCHED | 0.9416 | 0.9333 |
| 10 | beforeit_var_p1_constant | COMPLETE_MATCHED | 1.0000 | 1.0000 |
| 11 | naive_no_change | COMPLETE_MATCHED | 1.0715 | 1.1246 |
| 12 | naive_drift | COMPLETE_MATCHED | 1.1026 | 1.1597 |
| 13 | beforeit_var_p2_constant | COMPLETE_MATCHED | 2.1223 | 1.4974 |
| 14 | beforeit_var_p3_constant | COMPLETE_MATCHED | 5.3191 | 2.6852 |

**Headline pair {real_gdp, gdp_deflator} — `pandemic-masked`**

| rank | model | status | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---|---:|---:|
| 1 | **beforeit_abm_us_v2_mean** | COMPLETE_MATCHED | 0.7960 | 0.7920 |
| 2 | **beforeit_abm_us_v2_median** | COMPLETE_MATCHED | 0.7991 | 0.7950 |
| 3 | univariate_ar_p1_constant | COMPLETE_MATCHED | 0.8480 | 0.8295 |
| 4 | bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale | COMPLETE_MATCHED | 0.8518 | 0.8664 |
| 5 | univariate_ar_bic_p1-2-3-4-5-6-7-8_constant | COMPLETE_MATCHED | 0.8699 | 0.8520 |
| 6 | naive_historical_mean | COMPLETE_MATCHED | 0.8806 | 0.8194 |
| 7 | univariate_ar_p4_constant | COMPLETE_MATCHED | 0.8885 | 0.8636 |
| 8 | beforeit_var_p1_constant | COMPLETE_MATCHED | 1.0000 | 1.0000 |
| 9 | naive_no_change | COMPLETE_MATCHED | 1.2577 | 1.1978 |
| 10 | _beforeit_abm_us_v1_median_ | COMPLETE_MATCHED | 1.2641 | 1.4352 |
| 11 | _beforeit_abm_us_v1_mean_ | COMPLETE_MATCHED | 1.2723 | 1.4484 |
| 12 | naive_drift | COMPLETE_MATCHED | 1.3252 | 1.2550 |
| 13 | beforeit_var_p2_constant | COMPLETE_MATCHED | 3.7218 | 1.8412 |
| 14 | beforeit_var_p3_constant | COMPLETE_MATCHED | 11.8057 | 4.0167 |

**Secondary pair {nominal_gdp, effective_federal_funds_rate} — `all-available`**

| rank | model | status | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---|---:|---:|
| 1 | **beforeit_abm_us_v2_mean** | COMPLETE_MATCHED | 0.7156 | 0.7174 |
| 2 | **beforeit_abm_us_v2_median** | COMPLETE_MATCHED | 0.7162 | 0.7152 |
| 3 | univariate_ar_bic_p1-2-3-4-5-6-7-8_constant | COMPLETE_MATCHED | 0.7796 | 0.8164 |
| 4 | _beforeit_abm_us_v1_median_ | COMPLETE_MATCHED | 0.7810 | 0.9620 |
| 5 | _beforeit_abm_us_v1_mean_ | COMPLETE_MATCHED | 0.7824 | 0.9705 |
| 6 | univariate_ar_p4_constant | COMPLETE_MATCHED | 0.7912 | 0.8326 |
| 7 | bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale | COMPLETE_MATCHED | 0.8093 | 0.8639 |
| 8 | univariate_ar_p1_constant | COMPLETE_MATCHED | 0.8307 | 0.7953 |
| 9 | naive_no_change | COMPLETE_MATCHED | 0.9050 | 0.8840 |
| 10 | naive_drift | COMPLETE_MATCHED | 0.9632 | 1.0233 |
| 11 | beforeit_var_p1_constant | COMPLETE_MATCHED | 1.0000 | 1.0000 |
| 12 | naive_historical_mean | COMPLETE_MATCHED | 1.2590 | 1.7103 |
| 13 | beforeit_var_p2_constant | COMPLETE_MATCHED | 1.5804 | 1.2456 |
| 14 | beforeit_var_p3_constant | COMPLETE_MATCHED | 3.5431 | 1.9897 |

**Secondary pair {nominal_gdp, effective_federal_funds_rate} — `balanced h=12`**

| rank | model | status | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---|---:|---:|
| 1 | **beforeit_abm_us_v2_mean** | COMPLETE_MATCHED | 0.7032 | 0.6940 |
| 2 | **beforeit_abm_us_v2_median** | COMPLETE_MATCHED | 0.7040 | 0.6912 |
| 3 | _beforeit_abm_us_v1_median_ | COMPLETE_MATCHED | 0.7603 | 0.9047 |
| 4 | _beforeit_abm_us_v1_mean_ | COMPLETE_MATCHED | 0.7611 | 0.9119 |
| 5 | univariate_ar_bic_p1-2-3-4-5-6-7-8_constant | COMPLETE_MATCHED | 0.7702 | 0.7976 |
| 6 | univariate_ar_p4_constant | COMPLETE_MATCHED | 0.7872 | 0.8293 |
| 7 | bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale | COMPLETE_MATCHED | 0.7995 | 0.8435 |
| 8 | univariate_ar_p1_constant | COMPLETE_MATCHED | 0.8125 | 0.7610 |
| 9 | naive_no_change | COMPLETE_MATCHED | 0.8938 | 0.8601 |
| 10 | naive_drift | COMPLETE_MATCHED | 0.9530 | 1.0084 |
| 11 | beforeit_var_p1_constant | COMPLETE_MATCHED | 1.0000 | 1.0000 |
| 12 | naive_historical_mean | COMPLETE_MATCHED | 1.0782 | 1.4450 |
| 13 | beforeit_var_p2_constant | COMPLETE_MATCHED | 1.5717 | 1.2247 |
| 14 | beforeit_var_p3_constant | COMPLETE_MATCHED | 3.5336 | 1.9671 |

**Secondary pair {nominal_gdp, effective_federal_funds_rate} — `pandemic-masked`**

| rank | model | status | weighted RMSE ratio | weighted MAE ratio |
|---:|---|---|---:|---:|
| 1 | univariate_ar_p4_constant | COMPLETE_MATCHED | 0.7188 | 0.7823 |
| 2 | **beforeit_abm_us_v2_mean** | COMPLETE_MATCHED | 0.7393 | 0.7349 |
| 3 | **beforeit_abm_us_v2_median** | COMPLETE_MATCHED | 0.7411 | 0.7322 |
| 4 | univariate_ar_bic_p1-2-3-4-5-6-7-8_constant | COMPLETE_MATCHED | 0.7714 | 0.8046 |
| 5 | bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale | COMPLETE_MATCHED | 0.7942 | 0.8562 |
| 6 | univariate_ar_p1_constant | COMPLETE_MATCHED | 0.8664 | 0.7951 |
| 7 | beforeit_var_p1_constant | COMPLETE_MATCHED | 1.0000 | 1.0000 |
| 8 | naive_no_change | COMPLETE_MATCHED | 1.0431 | 0.9485 |
| 9 | _beforeit_abm_us_v1_median_ | COMPLETE_MATCHED | 1.1168 | 1.2539 |
| 10 | _beforeit_abm_us_v1_mean_ | COMPLETE_MATCHED | 1.1239 | 1.2681 |
| 11 | naive_drift | COMPLETE_MATCHED | 1.1478 | 1.1442 |
| 12 | naive_historical_mean | COMPLETE_MATCHED | 1.6657 | 2.0835 |
| 13 | beforeit_var_p2_constant | COMPLETE_MATCHED | 2.7783 | 1.5536 |
| 14 | beforeit_var_p3_constant | COMPLETE_MATCHED | 8.2034 | 2.9806 |

---

## 4. Per-cell detail, v1 → v2 delta and bias by horizon

**Per-cell RMSE ratio vs `beforeit_var_p1_constant` and rank among all scored models — `all-available`**

| target | h | n | v1 RMSE | v2 RMSE | v1 ratio | v2 ratio | v1 rank | v2 rank | ratio delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | 6.2592 | 6.0879 | 0.6887 | 0.6698 | 4/14 | 1/14 | -0.0188 |
| `real_gdp` | 2 | 60 | 9.5104 | 6.1001 | 1.2939 | 0.8299 | 12/14 | 1/14 | -0.4640 |
| `real_gdp` | 4 | 58 | 6.8762 | 6.2235 | 1.0825 | 0.9797 | 8/14 | 3/14 | -0.1027 |
| `real_gdp` | 8 | 54 | 6.7381 | 6.4418 | 0.8576 | 0.8199 | 8/14 | 3/14 | -0.0377 |
| `real_gdp` | 12 | 50 | 6.9637 | 6.6510 | 1.0347 | 0.9883 | 10/14 | 3/14 | -0.0465 |
| `gdp_deflator` | 1 | 61 | 1.4288 | 1.4288 | 0.7938 | 0.7938 | 6/14 | 5/14 | -0.0000 |
| `gdp_deflator` | 2 | 60 | 1.6486 | 1.6544 | 0.7713 | 0.7740 | 5/14 | 8/14 | +0.0027 |
| `gdp_deflator` | 4 | 58 | 1.9398 | 1.9512 | 0.8223 | 0.8272 | 2/14 | 6/14 | +0.0048 |
| `gdp_deflator` | 8 | 54 | 2.0391 | 2.0448 | 0.9751 | 0.9779 | 4/14 | 5/14 | +0.0027 |
| `gdp_deflator` | 12 | 50 | 2.1093 | 2.1080 | 0.8917 | 0.8911 | 5/14 | 4/14 | -0.0006 |
| `nominal_gdp` | 1 | 61 | 7.0266 | 6.8395 | 0.6740 | 0.6561 | 4/14 | 1/14 | -0.0179 |
| `nominal_gdp` | 2 | 60 | 10.1803 | 6.7821 | 1.1678 | 0.7780 | 12/14 | 1/14 | -0.3898 |
| `nominal_gdp` | 4 | 58 | 7.7626 | 7.0431 | 1.0510 | 0.9536 | 7/14 | 3/14 | -0.0974 |
| `nominal_gdp` | 8 | 54 | 7.7071 | 7.3312 | 0.8819 | 0.8389 | 7/14 | 5/14 | -0.0430 |
| `nominal_gdp` | 12 | 50 | 7.9643 | 7.5800 | 1.0282 | 0.9786 | 10/14 | 4/14 | -0.0496 |
| `effective_federal_funds_rate` | 1 | 61 | 0.3734 | 0.3734 | 0.5626 | 0.5626 | 7/14 | 6/14 | +0.0000 |
| `effective_federal_funds_rate` | 2 | 60 | 0.6921 | 0.6921 | 0.5559 | 0.5558 | 5/14 | 4/14 | -0.0000 |
| `effective_federal_funds_rate` | 4 | 58 | 1.2188 | 1.2196 | 0.5881 | 0.5885 | 3/14 | 4/14 | +0.0004 |
| `effective_federal_funds_rate` | 8 | 54 | 1.8935 | 1.8944 | 0.7958 | 0.7962 | 1/14 | 2/14 | +0.0004 |
| `effective_federal_funds_rate` | 12 | 50 | 2.1670 | 2.1646 | 0.8060 | 0.8052 | 3/14 | 2/14 | -0.0009 |

**Bias by horizon (`mean_error` = forecast − truth, pp) — `all-available`**

| target | h | n | v1 bias | v2 bias | v1 RMSE | v2 RMSE | v1 MASE | v2 MASE |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | -1.317 | -0.025 | 6.259 | 6.088 | 1.259 | 1.043 |
| `real_gdp` | 2 | 60 | -7.277 | -0.096 | 9.510 | 6.100 | 3.361 | 1.099 |
| `real_gdp` | 4 | 58 | -2.938 | -0.143 | 6.876 | 6.224 | 1.819 | 1.137 |
| `real_gdp` | 8 | 54 | -2.146 | -0.119 | 6.738 | 6.442 | 1.629 | 1.221 |
| `real_gdp` | 12 | 50 | -2.017 | -0.202 | 6.964 | 6.651 | 1.656 | 1.259 |
| `gdp_deflator` | 1 | 61 | -0.192 | -0.192 | 1.429 | 1.429 | 1.430 | 1.430 |
| `gdp_deflator` | 2 | 60 | -0.293 | -0.292 | 1.649 | 1.654 | 1.444 | 1.440 |
| `gdp_deflator` | 4 | 58 | -0.400 | -0.421 | 1.940 | 1.951 | 1.641 | 1.639 |
| `gdp_deflator` | 8 | 54 | -0.525 | -0.528 | 2.039 | 2.045 | 1.762 | 1.775 |
| `gdp_deflator` | 12 | 50 | -0.608 | -0.615 | 2.109 | 2.108 | 1.898 | 1.897 |
| `nominal_gdp` | 1 | 61 | -1.509 | -0.217 | 7.027 | 6.839 | 1.326 | 1.170 |
| `nominal_gdp` | 2 | 60 | -7.569 | -0.388 | 10.180 | 6.782 | 3.403 | 1.246 |
| `nominal_gdp` | 4 | 58 | -3.338 | -0.563 | 7.763 | 7.043 | 1.949 | 1.347 |
| `nominal_gdp` | 8 | 54 | -2.672 | -0.647 | 7.707 | 7.331 | 1.886 | 1.548 |
| `nominal_gdp` | 12 | 50 | -2.625 | -0.816 | 7.964 | 7.580 | 1.989 | 1.637 |
| `unemployment_rate` | 1 | 61 | -1.967 | -2.091 | 2.858 | 2.947 | 7.666 | 8.077 |
| `unemployment_rate` | 2 | 60 | -0.858 | -2.383 | 2.200 | 3.128 | 5.997 | 9.258 |
| `unemployment_rate` | 4 | 58 | -0.063 | -3.118 | 1.970 | 3.693 | 5.903 | 12.177 |
| `unemployment_rate` | 8 | 54 | +0.187 | -4.386 | 1.921 | 4.807 | 5.713 | 17.276 |
| `unemployment_rate` | 12 | 50 | +0.077 | -4.731 | 1.814 | 5.051 | 5.247 | 18.754 |

---

## 5. Density calibration — empirical interval coverage

**Empirical interval coverage of the v2 ensemble** (nominal 90 / 80 / 50 %)

| target | h | n | 5–95 % | 10–90 % | 25–75 % |
|---|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | 0.951 | 0.918 | 0.705 |
| `real_gdp` | 2 | 60 | 0.950 | 0.900 | 0.683 |
| `real_gdp` | 4 | 58 | 0.948 | 0.914 | 0.707 |
| `real_gdp` | 8 | 54 | 0.889 | 0.870 | 0.667 |
| `real_gdp` | 12 | 50 | 0.900 | 0.860 | 0.720 |
| `gdp_deflator` | 1 | 61 | 0.738 | 0.656 | 0.295 |
| `gdp_deflator` | 2 | 60 | 0.750 | 0.717 | 0.600 |
| `gdp_deflator` | 4 | 58 | 0.759 | 0.741 | 0.500 |
| `gdp_deflator` | 8 | 54 | 0.722 | 0.722 | 0.500 |
| `gdp_deflator` | 12 | 50 | 0.700 | 0.680 | 0.460 |
| `nominal_gdp` | 1 | 61 | 0.934 | 0.852 | 0.639 |
| `nominal_gdp` | 2 | 60 | 0.933 | 0.867 | 0.667 |
| `nominal_gdp` | 4 | 58 | 0.897 | 0.845 | 0.638 |
| `nominal_gdp` | 8 | 54 | 0.852 | 0.778 | 0.593 |
| `nominal_gdp` | 12 | 50 | 0.820 | 0.800 | 0.480 |
| `unemployment_rate` | 1 | 61 | 0.295 | 0.197 | 0.148 |
| `unemployment_rate` | 2 | 60 | 0.317 | 0.200 | 0.133 |
| `unemployment_rate` | 4 | 58 | 0.276 | 0.155 | 0.052 |
| `unemployment_rate` | 8 | 54 | 0.148 | 0.056 | 0.000 |
| `unemployment_rate` | 12 | 50 | 0.000 | 0.000 | 0.000 |
| `effective_federal_funds_rate` | 1 | 61 | 0.754 | 0.689 | 0.557 |
| `effective_federal_funds_rate` | 2 | 60 | 0.683 | 0.617 | 0.367 |
| `effective_federal_funds_rate` | 4 | 58 | 0.517 | 0.414 | 0.086 |
| `effective_federal_funds_rate` | 8 | 54 | 0.333 | 0.241 | 0.130 |
| `effective_federal_funds_rate` | 12 | 50 | 0.200 | 0.160 | 0.060 |
| `real_gdp` **all h** | — | 283 | **0.929** | **0.894** | **0.696** |
| `gdp_deflator` **all h** | — | 283 | **0.735** | **0.703** | **0.470** |
| `nominal_gdp` **all h** | — | 283 | **0.890** | **0.830** | **0.608** |
| `unemployment_rate` **all h** | — | 283 | **0.216** | **0.127** | **0.071** |
| `effective_federal_funds_rate` **all h** | — | 283 | **0.512** | **0.438** | **0.251** |

**Empirical interval coverage of the v1 ensemble** (nominal 90 / 80 / 50 %)

| target | h | n | 5–95 % | 10–90 % | 25–75 % |
|---|---:|---:|---:|---:|---:|
| `real_gdp` | 1 | 61 | 0.918 | 0.852 | 0.574 |
| `real_gdp` | 2 | 60 | 0.083 | 0.067 | 0.017 |
| `real_gdp` | 4 | 58 | 0.724 | 0.569 | 0.224 |
| `real_gdp` | 8 | 54 | 0.796 | 0.722 | 0.389 |
| `real_gdp` | 12 | 50 | 0.780 | 0.720 | 0.300 |
| `gdp_deflator` | 1 | 61 | 0.738 | 0.656 | 0.295 |
| `gdp_deflator` | 2 | 60 | 0.750 | 0.717 | 0.550 |
| `gdp_deflator` | 4 | 58 | 0.759 | 0.741 | 0.431 |
| `gdp_deflator` | 8 | 54 | 0.741 | 0.722 | 0.500 |
| `gdp_deflator` | 12 | 50 | 0.720 | 0.680 | 0.480 |
| `nominal_gdp` | 1 | 61 | 0.918 | 0.820 | 0.557 |
| `nominal_gdp` | 2 | 60 | 0.183 | 0.033 | 0.017 |
| `nominal_gdp` | 4 | 58 | 0.741 | 0.569 | 0.310 |
| `nominal_gdp` | 8 | 54 | 0.778 | 0.704 | 0.370 |
| `nominal_gdp` | 12 | 50 | 0.700 | 0.640 | 0.420 |
| `unemployment_rate` | 1 | 61 | 0.344 | 0.246 | 0.131 |
| `unemployment_rate` | 2 | 60 | 0.550 | 0.483 | 0.217 |
| `unemployment_rate` | 4 | 58 | 0.569 | 0.345 | 0.138 |
| `unemployment_rate` | 8 | 54 | 0.537 | 0.352 | 0.185 |
| `unemployment_rate` | 12 | 50 | 0.560 | 0.460 | 0.220 |
| `effective_federal_funds_rate` | 1 | 61 | 0.754 | 0.689 | 0.557 |
| `effective_federal_funds_rate` | 2 | 60 | 0.667 | 0.583 | 0.350 |
| `effective_federal_funds_rate` | 4 | 58 | 0.517 | 0.431 | 0.103 |
| `effective_federal_funds_rate` | 8 | 54 | 0.352 | 0.241 | 0.130 |
| `effective_federal_funds_rate` | 12 | 50 | 0.180 | 0.140 | 0.040 |
| `real_gdp` **all h** | — | 283 | **0.654** | **0.580** | **0.300** |
| `gdp_deflator` **all h** | — | 283 | **0.742** | **0.703** | **0.449** |
| `nominal_gdp` **all h** | — | 283 | **0.661** | **0.548** | **0.332** |
| `unemployment_rate` **all h** | — | 283 | **0.509** | **0.375** | **0.177** |
| `effective_federal_funds_rate` **all h** | — | 283 | **0.509** | **0.431** | **0.247** |

Read-out. **v2's real-GDP density is well calibrated**: 0.929 of realized values inside the
nominal-90 % band and 0.894 inside the nominal-80 %, against v1's 0.654 and 0.580 — v1's intervals
missed because the point forecast was biased down by ~2 pp, not because they were too narrow. The
50 % band is too wide for both (0.696 v2, 0.300 v1), i.e. v2 now over-covers the centre. The
deflator is unchanged and under-covered at every level (0.735 / 0.703 / 0.470 v2 against 0.742 /
0.703 / 0.449 v1): the ensemble's inflation spread is genuinely too narrow, and that is untouched
by this work. `effective_federal_funds_rate` under-covers badly and increasingly with the horizon
(0.754 at h = 1 down to 0.200 at h = 12) in both versions — the Taylor-rule path is far too tight.
`unemployment_rate` coverage falls from 0.509 to 0.216 and reaches exactly 0.000 at h = 12, which
is the §6.2 defect showing up in the density as well as the mean.

---

## 6. Known open defects that limit what v2 means

These are measured, not speculative, and must be quoted alongside any v2 number.

### 6.1 The growth is a capacity-headroom refill, not a growth mechanism

`K_end/K_1 = 1.0000` in every variant: capital never accumulates, because
`I_d_i = δ_i/κ_i·min(Q_s_i, K_i·κ_i)` and `K' = K − δ/κ·Y + I` make investment purely
replacement. All of v2's extra growth therefore comes from draining the fixed 17.6 % opening
capacity headroom. Measured over 24 quarters at 2016Q4 (24 paths, annualised by year):

| variant | y1 | y2 | y3 | y4 | y5 | y6 | utilisation y1 → y6 | K24/K0 |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| v1 baseline | −1.62 | −0.04 | 0.59 | 0.45 | 1.19 | 1.36 | 0.845 → 0.865 | 1.0003 |
| reconciled, budgets held (rejected) | 3.33 | 3.60 | 3.53 | 2.71 | 1.39 | **0.33** | 0.867 → **0.986** | 1.0000 |
| **v2 (`lambda` closure)** | 1.17 | 1.06 | 1.56 | 1.47 | 2.86 | 3.33 | 0.856 → 0.943 | 1.0000 |

Inside the 12-quarter scoring window this is a genuine improvement. Beyond roughly eight to ten
years v2 must stall, because it has consumed 0.087 of its 0.144 headroom in six. A
capacity-expansion term in desired investment — calibrated against the accounting identity
`net I = ΔK`, never against forecast RMSE — is the prerequisite for any multi-year use.

### 6.2 Unemployment collapses once goods rationing stops

Measured at four origins, 64 matched-seed paths, end-of-horizon unemployment rate:

| variant | 2012Q4 | 2016Q4 | 2022Q4 | 2024Q4 |
|---|---:|---:|---:|---:|
| v1 baseline | 4.73 | 4.97 | 5.28 | 5.08 |
| reconciled, budgets held | 0.00 | 0.00 | 0.06 | 0.01 |
| **v2** | 0.90 | 0.95 | 1.11 | 0.76 |
| **v2 + rw-drift** | 0.12 | 0.18 | 0.50 | 0.49 |

This is not credible and it is a direct consequence of the fix: with the goods market no longer
rationing, the labour block over-heats. `unemployment_rate` is emitted and diagnosed but is
**excluded from every weighted score** — already the policy in v1 for an independent reason (the
initial unemployed stock is a length-one annual array frozen at 2024, so every historical origin
opens at the 2024 labour market). The labour block needs its own review before unemployment is
scored for either version.

### 6.3 Everything v1 was already caveated for still applies

Mixed-vintage structural year 2024 at every historical origin; `h = 1` sits on the opening-row
measurement basis (`real ≡ nominal`, deflator ≡ 1.0) and carries the largest horizon weight;
`effective_federal_funds_rate` is the model's internal Taylor rule, not an approved EFFR bridge.

---

## 6b. Current outlook (unscored, out of sample)

Origins 2025Q4 and 2026Q1, 500 paths, the reconciled artifact. These origins lie beyond the end of
the revised panel, so there is no realized truth and nothing here is scored. Full percentile grid in
`output/us_forecasting/abm_v2_comparison_outlook/current_outlook.csv`.

**Outlook, origin 2025Q4, `real_gdp`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q1 | +2.193 | +1.965 | 4.649 | -5.358 | -0.914 | +5.332 | +9.882 |
| 2 | 2026Q2 | +2.010 | +1.876 | 4.896 | -6.119 | -1.281 | +5.357 | +10.224 |
| 3 | 2026Q3 | +2.013 | +1.885 | 4.829 | -5.615 | -0.958 | +5.321 | +10.523 |
| 4 | 2026Q4 | +2.229 | +2.426 | 4.726 | -5.716 | -0.747 | +5.243 | +9.400 |
| 8 | 2027Q4 | +2.367 | +2.238 | 5.072 | -5.897 | -1.062 | +5.721 | +10.404 |
| 12 | 2028Q4 | +2.044 | +2.322 | 4.775 | -5.912 | -1.110 | +5.259 | +9.757 |

**Outlook, origin 2025Q4, `gdp_deflator`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q1 | +3.211 | +3.188 | 1.133 | +1.252 | +2.388 | +3.983 | +5.009 |
| 2 | 2026Q2 | +2.962 | +2.920 | 1.357 | +0.829 | +2.035 | +3.964 | +5.095 |
| 3 | 2026Q3 | +2.626 | +2.655 | 1.433 | +0.273 | +1.604 | +3.489 | +5.005 |
| 4 | 2026Q4 | +2.399 | +2.419 | 1.518 | -0.204 | +1.388 | +3.363 | +4.889 |
| 8 | 2027Q4 | +2.283 | +2.271 | 1.617 | -0.247 | +1.196 | +3.293 | +4.833 |
| 12 | 2028Q4 | +2.245 | +2.198 | 1.606 | -0.296 | +1.189 | +3.339 | +4.952 |

**Outlook, origin 2025Q4, `unemployment_rate`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q1 | +3.434 | +3.669 | 0.665 | +2.081 | +3.231 | +3.724 | +4.217 |
| 2 | 2026Q2 | +3.083 | +3.395 | 1.063 | +0.928 | +2.574 | +3.724 | +4.491 |
| 3 | 2026Q3 | +2.717 | +3.039 | 1.242 | +0.107 | +1.862 | +3.669 | +4.107 |
| 4 | 2026Q4 | +2.324 | +2.519 | 1.405 | +0.000 | +1.260 | +3.560 | +4.272 |
| 8 | 2027Q4 | +1.086 | +0.383 | 1.372 | +0.000 | +0.000 | +1.930 | +3.727 |
| 12 | 2028Q4 | +0.392 | +0.000 | 0.922 | +0.000 | +0.000 | +0.000 | +2.579 |

**Outlook, origin 2025Q4, `effective_federal_funds_rate`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q1 | +3.862 | +3.861 | 0.128 | +3.658 | +3.775 | +3.941 | +4.077 |
| 2 | 2026Q2 | +3.817 | +3.824 | 0.189 | +3.501 | +3.688 | +3.952 | +4.135 |
| 3 | 2026Q3 | +3.772 | +3.766 | 0.230 | +3.381 | +3.620 | +3.923 | +4.123 |
| 4 | 2026Q4 | +3.717 | +3.719 | 0.257 | +3.321 | +3.541 | +3.897 | +4.153 |
| 8 | 2027Q4 | +3.514 | +3.516 | 0.354 | +2.935 | +3.293 | +3.766 | +4.071 |
| 12 | 2028Q4 | +3.322 | +3.322 | 0.425 | +2.587 | +3.062 | +3.594 | +3.980 |

**Outlook, origin 2026Q1, `real_gdp`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q2 | +2.589 | +2.597 | 4.975 | -5.739 | -0.621 | +5.912 | +10.619 |
| 2 | 2026Q3 | +1.863 | +1.815 | 4.685 | -5.506 | -1.327 | +4.833 | +9.877 |
| 3 | 2026Q4 | +2.329 | +2.185 | 4.670 | -5.920 | -0.685 | +5.374 | +9.993 |
| 4 | 2027Q1 | +2.465 | +2.610 | 4.833 | -5.631 | -0.838 | +6.014 | +9.833 |
| 8 | 2028Q1 | +1.565 | +1.603 | 4.729 | -5.540 | -1.939 | +4.825 | +9.425 |
| 12 | 2029Q1 | +2.129 | +1.937 | 5.084 | -6.376 | -1.062 | +5.166 | +10.498 |

**Outlook, origin 2026Q1, `gdp_deflator`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q2 | +3.134 | +3.126 | 1.036 | +1.482 | +2.431 | +3.828 | +4.906 |
| 2 | 2026Q3 | +2.918 | +2.911 | 1.361 | +0.637 | +2.097 | +3.716 | +5.219 |
| 3 | 2026Q4 | +2.784 | +2.725 | 1.463 | +0.377 | +1.839 | +3.790 | +5.091 |
| 4 | 2027Q1 | +2.618 | +2.675 | 1.494 | +0.082 | +1.679 | +3.696 | +4.938 |
| 8 | 2028Q1 | +2.264 | +2.289 | 1.635 | -0.333 | +1.152 | +3.194 | +4.930 |
| 12 | 2029Q1 | +2.289 | +2.264 | 1.600 | -0.386 | +1.286 | +3.427 | +4.953 |

**Outlook, origin 2026Q1, `unemployment_rate`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q2 | +3.378 | +3.614 | 0.733 | +1.862 | +3.067 | +3.724 | +4.326 |
| 2 | 2026Q3 | +3.030 | +3.450 | 1.073 | +0.873 | +2.464 | +3.724 | +4.220 |
| 3 | 2026Q4 | +2.623 | +2.957 | 1.316 | +0.000 | +1.698 | +3.614 | +4.272 |
| 4 | 2027Q1 | +2.195 | +2.355 | 1.437 | +0.000 | +0.986 | +3.505 | +4.107 |
| 8 | 2028Q1 | +1.032 | +0.383 | 1.260 | +0.000 | +0.000 | +1.807 | +3.614 |
| 12 | 2029Q1 | +0.399 | +0.000 | 0.905 | +0.000 | +0.000 | +0.164 | +2.686 |

**Outlook, origin 2026Q1, `effective_federal_funds_rate`** (unscored, out of sample)

| h | target | mean | median | sd | 5 % | 25 % | 75 % | 95 % |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2026Q2 | +3.603 | +3.603 | 0.134 | +3.386 | +3.504 | +3.695 | +3.830 |
| 2 | 2026Q3 | +3.572 | +3.559 | 0.188 | +3.262 | +3.452 | +3.695 | +3.893 |
| 3 | 2026Q4 | +3.516 | +3.505 | 0.238 | +3.114 | +3.379 | +3.686 | +3.899 |
| 4 | 2027Q1 | +3.469 | +3.442 | 0.279 | +3.050 | +3.266 | +3.663 | +3.949 |
| 8 | 2028Q1 | +3.294 | +3.291 | 0.371 | +2.709 | +3.049 | +3.530 | +3.916 |
| 12 | 2029Q1 | +3.157 | +3.161 | 0.432 | +2.420 | +2.872 | +3.441 | +3.835 |

The unemployment column is shown only because the file contains it; it decays to zero by h = 8 and
is the §6.2 defect, not a forecast.

---

## 7. Reproduction

```bash
# 1. build the reconciled calibration artifact (one command, ~40 s)
julia --project=scripts/us scripts/us/calibration/reconcile_commodity_balance.jl \
  --mode=final_demand_scaled --expectations=rw_drift

# 2. v1 and v2 ensembles, 61 origins x 500 paths each
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v1_headline 500 headline
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2

# 3. joint scoring: both ABM columns on identical common cells
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2 \
  --also-score=output/us_forecasting/abm_v2_comparison/v1_headline

# 4. current outlook (unscored)
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison_outlook 500 outlook_v2

# 5. tables
julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/report_v2_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline \
  output/us_forecasting/abm_v2_comparison_outlook
```

Step 2 resumes from `abm_ensemble_summaries.csv`, so an interrupted run continues instead of
restarting, and step 3 is a re-score off the cache (~15 s) rather than a re-simulation.

---

## Reproducibility

The committed ensemble caches **are** the reproducibility artifact. Each run
directory carries `cache_identity.toml` recording the calibration artifact and its
sha256, the comparison and base-diagnostic code hashes, the panel hashes, the
requested path count, the variant, the seed-contract id and the Julia version. The
runner revalidates all of it before reusing a single cached row, and refuses by
field name on any mismatch.

Exact regeneration requires **Julia 1.10.3**. Seeds derive from `Base.hash` and are
drawn through the default global RNG; both are version-bound, so the same seed
produces a different path under a different Julia. A cross-version rerun is a new
experiment, not a reproduction of these numbers — and the identity check will say
so rather than silently reusing the cache. The U.S. hermetic validation job pins
1.10.3 for this reason.

Re-scoring a committed cache (seconds, no simulation):

```sh
JULIA_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 julia --project=scripts/us \
  scripts/us/forecasting/diagnostics/abm_revised_comparison/run_revised_data_abm_comparison.jl \
  output/us_forecasting/abm_v2_comparison/v2_headline 500 headline_v2 \
  --also-score=output/us_forecasting/abm_v2_comparison/v1_headline
```
