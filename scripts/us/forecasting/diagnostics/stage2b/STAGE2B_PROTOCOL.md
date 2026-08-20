# Stage-2b frozen protocol (workstreams 2b-1 … 2b-6)

**Frozen: 2026-08-17, before any Stage-2b scored table was produced or
examined.** This document fixes the scored field, the model repairs, every
calibration rule, and the success bar for the Stage-2b decisive experiment
(plan status addendum 2026-08-16). Where the plan and this protocol disagree,
the plan governs.

## Experimental frame (unchanged from the plan)

Same 61 revised-panel origins (2010Q2–2025Q2), h = 1..12 simulated and
h ∈ {1, 2, 4, 8, 12} scored, 500 paths per origin, identical common cells,
three tracks (all-available, balanced-h12, pandemic-masked), current
revised-vintage truth, labeled mixed-vintage throughout; no promotion or
real-time claim. Anchor: VAR(1) with constant. Weighted ratios are
macro-averages of matched cellwise ratios with horizon weights
{1: 0.30, 2: 0.25, 4: 0.20, 8: 0.15, 12: 0.10}.

## Scored columns

| Column | Source |
|---|---|
| naive ×3, AR ×3, VAR ×3, Minnesota BVAR | frozen statistical family (registry) |
| `dsge_small_nk` (+ `_median`) | validated An–Schorfheide-type gensys mechanics, posterior-mode re-estimated at every origin on the panel columns [real_gdp, gdp_deflator, effr] |
| `dsge_sw07` (+ `_median`) | Smets–Wouters 2007, posterior-mode re-estimated at every origin on seven observables (1966Q1 → origin), fixed-provenance FRED retrieval spliced to the frozen panel |
| `beforeit_abm_us_v1` (mean, median) | frozen v1, regenerated under the extended source tree |
| `beforeit_abm_us_v2` (mean, median) | frozen v2, regenerated under the extended source tree |
| `beforeit_abm_us_v3` (mean, median) | v2 calibration + the balanced-growth repair below |

The semi-structural comparator cannot produce GDP-deflator forecasts
natively; it is reported in its existing core-4 comparison and excluded from
the headline-pair field (a structural coverage fact, recorded, not a choice
made after seeing scores).

Bit-identity gate: the regenerated v1 and v2 ensemble caches must reproduce
the committed caches byte-for-byte (identity fields aside); this is the proof
that the v3 source-tree extension moved no frozen number.

## The v3 repair (2b-2 + 2b-3), frozen

Three flag-gated mechanisms, all default-off, all injected per origin by the
sealed kernel policy (`V3_VARIANT_MECHANISMS`):

1. **Trend labour growth** (`trend_growth_rate`, mechanism `:trend_growth`):
   `alpha_bar_i` and `w_bar_i` grow by `(1+g)` at the start of every simulated
   quarter. `g` = trailing-40-quarter mean, ending at the origin quarter, of
   observed quarterly labour-productivity growth `dln(GDPC1/CE16OV)` plus
   observed labour-force growth `dln(CLF16OV)` (fixture
   `trend_growth_series.csv`, SHA-pinned; demographics and immigration enter
   through the labour-force term). Unit labour cost `w/alpha` is invariant by
   construction.
2. **Capacity-efficiency growth** (`trend_capacity_efficiency`, mechanism
   `:capacity_efficiency`): `kappa_i` and `delta_i` grow by the same `(1+g)`,
   so productive capacity `K_i * kappa_i` tracks trend while the replacement
   share `delta/kappa` (CFC/output) is exactly stable and **no demand flow is
   injected**. Book capital is constant; `net I = ΔK` holds trivially in book
   units; trend capacity growth is carried by the efficiency factor calibrated
   to the same observed `g`.
3. **Expectations** stay the v2 random-walk-with-drift; the `headline_v3_ar1`
   ablation forces the legacy log-level AR(1) (paper form).

**Rejected candidates (design-stage, retained as reproducible ablations):**
the capacity-gap accelerator (`nu = 0.0625`) and the BGP net-investment flow
(`g·K` demand injection). Both were rejected on matched-seed *simulation
diagnostics only* — utilization/unemployment stability and internal growth
rates — before any forecast error against panel truth was computed for any v3
candidate. The pilot evidence (4 origins × 64 paths, matched seeds) is part
of the evidence report. No forecast error entered any design decision
(calibration firewall).

Design-stage stability pilots used: unemployment trajectory boundedness,
internal real-growth magnitude, dispersion growth. These are
simulation-internal properties, not scores.

## Unemployment enters the scorecard

New scored target set `labour_unemployment_rate = ["unemployment_rate"]`
(weight 1.0 within the set, same horizon weights). The 2b-2 gate statistic is
the ratio of mean ensemble dispersion to the dispersion of realized values
across matched cells per horizon, reported per track, plus the standard
score tables. The headline and secondary target-set definitions are
unchanged.

DSGE columns cover unemployment through a labeled auxiliary Okun bridge
(per-origin OLS of the quarterly change in the unemployment rate on
annualized real GDP growth, iterated over predictive growth paths with
residual noise). This is outside both DSGE cores and is labeled as such in
every table that quotes it.

## Density scores

CRPS (exact ensemble form) and central-interval coverage (50/80/90%) are
computed from the persisted 500-path draws for every ABM and DSGE column, on
the same matched cells as the point scores, per track. The preregistered
density bar compares the v3 ABM against the best density-capable challenger
per target set (the DSGE columns; the statistical family is point-only in
the frozen registry and is not retrofitted with densities for this exercise).

## Inference (2b-5)

For every column pair (column vs. anchor) and (v3 vs. best non-ABM column):
HLN-corrected Diebold–Mariano per (track, target, horizon) on matched loss
differentials (squared loss). Romano–Wolf step-down within each (track,
target set) family across columns, and Hansen–Lunde–Nason MCS (T_max,
stationary bootstrap, block length 4, 2000 replications, alpha 0.10) over
the weighted headline-pair cell losses per track. Every superiority sentence
in the report must carry the DM result and its horizon scope.

## Success bar (restated verbatim from the plan, frozen 2026-08-16)

The repaired ABM is superior if its weighted headline-pair RMSE ratio beats
the best non-ABM column, including both DSGE columns, in at least two of the
three tracks with DM significance reported per horizon, and its density
scores (CRPS, 90% coverage) are no worse than the best challenger's. If the
ABM instead wins only on densities, tails, unemployment, or sector detail,
that specialized value is the claim published; a negative result is published
with the same tables.

## 2b-4 structural-vintage robustness

Two additional annual structures (2017 and 2012 reference years) built from
the same BEA summary supply–use ingestion path as the 2024 structure,
carried through the identical reconciliation, and re-scored on matched cells
for {v2, v3} and the DSGE columns (which do not depend on the structure and
therefore serve as invariance controls). If ingestion of a pre-2017 vintage
proves infeasible inside Stage 2b, the 2017-only comparison is reported and
the gap named.

## Information-set disclosures (fixed)

- Panel: `quarterly_panel.csv`, sha256 `f7bb26a4…851bbe`, truth and
  estimation for all columns; revised-vintage; mixed-vintage structure at
  historical origins for the ABM columns.
- SW07 estimation uses pre-2000Q3 history and four observables the panel
  does not carry, from a FRED retrieval frozen 2026-08-17 (SHA-pinned).
  This information-set asymmetry favors the DSGE challenger and is
  disclosed wherever SW07 results are quoted.
- DSGE predictive densities carry filtered-state and future-shock
  uncertainty at the posterior mode; no parameter uncertainty. Disclosed.
- ABM v3 calibration adds two observed-series fixtures (trend growth); no
  other calibration input changes relative to v2.
