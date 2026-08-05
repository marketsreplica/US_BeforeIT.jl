# BeforeIT Prototype Contract — API, data, and design rules

Shared reference for all visual prototypes under `apps/web/prototypes/`.
Every prototype is a self-contained static folder (`index.html` + assets) served
by the Julia backend at `http://127.0.0.1:8080/prototypes/<folder>/`.
**Always call the API with absolute paths (`/api/...`).**

## The model in one paragraph

BeforeIT is an agent-based macroeconomic model (Poledna et al.) with
dataset-specific national calibrations. One simulated step = one quarter. The
current Austrian calibration has 62 NACE/FIGARO sectors; the U.S. calibration
has 68 BEA Summary I-O sectors. Firm and household counts come from the selected
artifact rather than a fixed UI assumption. Every run also contains **1
commercial bank**, **1 central bank**, **1 government**, and **1
rest-of-the-world** (RoW) agent. Firms hire
workers, take bank loans, produce with Leontief technology, set prices/quantities from
expectations; households earn wages/dividends/benefits, pay taxes, consume and invest;
the central bank sets the policy rate by a Taylor rule; government taxes, spends, and
issues debt; RoW trades imports/exports. Markets clear by search-and-matching.

## HTTP API (all JSON)

### GET /api/datasets
List of datasets. Key fields per item: `id`, `label`, `period` (e.g. "2026-Q1"),
`scenarios` (subset of ["baseline","upside","downside","unconditional"]),
`default_scenario`, `default_horizon`, `description`.
Dataset ids: `US2026Q1` (default), `US2024Q4`, `AUSTRIA2026Q1` (the only
dataset with conditional scenarios), `AUSTRIA2024Q4`, `AUSTRIA2010Q1`,
`ITALY2010Q1`, and `STEADY_STATE2010Q1`.

### GET /api/knobs?dataset_id=AUSTRIA2026Q1
The editable parameters. Array of
`{group: "parameters"|"initial_conditions", key, label, unit, min, max, default}`.
Live defaults (AUSTRIA2026Q1):

| group | key | default | range | meaning |
|---|---|---|---|---|
| param | tau_INC | 0.212 | 0–0.8 | income tax rate |
| param | tau_FIRM | 0.1625 | 0–0.8 | corporate tax rate |
| param | tau_VAT | 0.1391 | 0–0.8 | VAT rate |
| param | tau_SIF | 0.2059 | 0–0.8 | employer social insurance |
| param | tau_SIW | 0.19 | 0–0.8 | employee social insurance |
| param | tau_EXPORT | 0.0 | 0–0.8 | export tax |
| param | tau_CF | 0.0653 | 0–0.8 | capital formation tax |
| param | tau_G | 0.0092 | 0–0.8 | tax on gov consumption |
| param | psi | 0.8447 | 0–1 | household consumption share of income |
| param | psi_H | 0.0877 | 0–1 | household housing-investment share |
| param | theta_UB | 0.3511 | 0–1 | unemployment benefit replacement rate |
| param | theta_DIV | 1.4096 | 0–1 | dividend payout ratio (NOTE: default > max; only send if user changes it) |
| param | mu | -0.0005 | 0–0.2 | bank risk premium (NOTE: default < min; same caveat) |
| param | zeta | 0.03 | 0–1 | bank capital requirement |
| param | zeta_LTV | 0.6 | 0–1 | loan-to-value cap (mortgages) |
| param | zeta_b | 0.5 | 0–1 | loan-to-capital for new/insolvent firms ("ease of restarting business") |
| param | theta | 0.05 | 1e-6–1 | loan repayment (installment) rate |
| param | rho | 0.9443 | 0–0.999 | central-bank rate smoothing |
| param | r_star | 0.0004 | ±0.05 | CB neutral real rate (quarterly) |
| param | pi_star | 0.005 | -0.02–0.05 | CB inflation target (quarterly) |
| param | xi_pi | 1.075 | 0–5 | Taylor-rule inflation weight |
| param | xi_gamma | 0.1656 | 0–5 | Taylor-rule growth weight |
| param | r_G | 0.005 | 0–0.1 | quarterly government debt rate |
| init | r_bar | 0.0205 | -0.05–0.2 | initial policy rate (ANNUALIZED in UI units) |
| init | sb_other | 0.8854 | 0–100 | other social benefits (per household, per quarter) |
| init | sb_inact | 4.6627 | 0–100 | benefits per inactive household |
| init | w_UB | 6.5964 | 0–100 | unemployment benefit wage |
| init | omega | 0.85 | 1e-6–1 | initial capacity utilization |

Overrides are sent in **UI units** (the server transforms r_bar annual→quarterly itself).
Constraint enforced server-side: `psi + psi_H <= 1`. Sending a value outside [min,max]
→ HTTP 400. Only send keys the user actually changed.

### GET /api/datasets/schema?dataset_id=… and /api/datasets/value?dataset_id=…&group=…&key=…
Full parameter/initial-condition listing and raw values (scalars, vectors[62], matrices).
Useful vectors (group=parameters unless noted): `I_s` firms per sector (total 652,
range 1–60), `alpha_s` labor productivity/sector, `w_s` wages/sector,
`b_HH_g` household consumption basket shares by sector, `c_G_g` government purchase
shares, `c_E_g` export shares, `c_I_g` import shares, `tau_Y_s`/`tau_K_s` sector taxes;
(group=initial_conditions): `N_s` employees per sector (total 4,180).

### GET /api/scenarios?dataset_id=AUSTRIA2026Q1&scenario=baseline
Yearly assumption rows for conditional scenarios: real_gdp_growth, hicp_inflation,
government_consumption_growth, exports_growth, imports_growth, etc. (fractions/yr).

### GET /api/runs
List of past runs, newest first: `{run_id, dataset_id, scenario, created_at,
state: "queued"|"running"|"done"|"error", progress: 0..1, message,
override_count, shock_type, cashflows_available, cashflow_quarters,
display_name, parent_run_id, experiment_id, experiment_role, trace,
capabilities}`.
`override_count` is the total number of parameter and initial-condition overrides
stored on the run; `shock_type` is `"none"` or the submitted shock type.
Use an existing completed, traced run when possible so a network view does not
wait for a new simulation. Do not assume a fixed number of runs on disk.

### GET /api/runs/{run_id}/spec
Returns the normalized run provenance:
`{run_id, name, description, parent_run_id, experiment_id, experiment_role,
dataset_id, scenario, created_at, sim, overrides, shock, trace, provenance}`.
The values in `overrides` are converted back to **UI units**, including annualized
`initial_conditions.r_bar`, so they can be passed directly to prototype controls
and resubmitted through `POST /api/runs`.

### POST /api/runs  → {run_id}
```json
{
  "dataset_id": "AUSTRIA2026Q1",
  "scenario": "baseline",            // or upside|downside|unconditional
  "sim": {"T": 12, "n_sims": 4, "base_seed": 1234},
  "overrides": {
    "parameters": {"tau_VAT": 0.17},          // UI units, changed keys only
    "initial_conditions": {"r_bar": 0.03}
  },
  "shock": {"type": "none"},
  "trace": {"profile": "standard", "realization_indices": [1]}
}
```
Shock variants: `{"type":"interest_rate","annual_rate":0.02,"final_time":4}` (adds to
policy rate through quarter final_time), `{"type":"productivity","multiplier":1.05}`,
`{"type":"consumption","multiplier":1.1,"final_time":4}`, and
`{"type":"sector_productivity","sector":27,"multiplier":1.05}`.
Limits: conditional scenarios `T ≤ 23`; unconditional `T ≤ 80`; `n_sims ≤ 64`.
**For interactive runs default to T=12, n_sims=4** (a 23-quarter 16-sim run takes
minutes; 12×4 is far faster). Poll:

### GET /api/runs/{run_id}/status → {state, progress 0..1, message, started_at, finished_at}
Poll every ~1.5 s while queued/running.

### GET /api/runs/{run_id}/summary  (only when state == "done")
```
periods: ["2026-Q1", ...]            // T+1 labels, index 0 = initial quarter
t: [1..T+1]
real_gdp, real_household_consumption, real_government_consumption,
real_fixed_capitalformation, real_exports, real_imports, wages,
euribor_q, euribor_annual, gdp_deflator:   {mean: [T+1], std: [T+1]}
real_sector_gva: {mean: [T+1][G], std: [T+1][G]}     // per-sector real GVA
n_sims, T, dataset_id, scenario, run_id, dataset_metadata, forecast_start_period
```
Magnitudes (AUSTRIA2026Q1): real_gdp ≈ 130,000 (millions €/quarter ≈ model units),
consumption ≈ 72,000, gov ≈ 29,000, exports ≈ 63,000, imports ≈ 70,000, wages ≈ 57,000.
`std` may contain nulls — guard. euribor_q is quarterly rate (~0.005).
Currency, flow/stock units, and sector classification come from dataset
metadata. U.S. runs use USD and BEA Summary I-O identities; Austrian runs use
EUR and NACE/FIGARO.

### GET /api/runs/{run_id}/cashflows

Without query parameters this returns the trace manifest: `quarter-ledger.v2`
and normalized API versions, available quarters and periods, representative
realization and seed, run provenance, firm/sector directories, capability
flags, and exact run-wide `scale_domains`.

Quarter `0` is the calibrated, pre-restructuring opening stock snapshot. It has
`initial_period_has_flows=false` and no transaction or equation-flow edges.
Quarter `1` and later are settled simulated quarters.

The normalized query is:

```text
GET /api/runs/{run_id}/cashflows
  ?quarter=&level=macro|sector|firm
  &focus=&parent_id=&edge_id=&layers=&recognition=&direction=
  &min_amount=&coverage=&page_size=&cursor=&include_potential=
```

The response contains normalized `edges`, nodes/directories, stocks,
diagnostics, rollups, the applied query, an opaque `next_cursor`, and coverage
separated by compatible measure domain. A v2 edge carries:

```text
id, canonical_source, canonical_target, signed_value,
source, target, amount, layer, market, purpose, measure_kind,
cash_recognition, units, direction_semantics, evidence_basis,
realization_scope, realization_index, aggregation, valuation_basis,
timing, rollup_id, component_id, parent_ids, summation_role,
explanation
```

`id` is the stable semantic key. For reversible relationships,
`canonical_source`/`canonical_target` stay fixed and `signed_value` is relative
to them; `source`/`target` are display endpoints derived from its sign. Ordinary
money edges display payer/buyer → recipient/seller. Stocks and non-cash
counterfactuals have different measure and recognition fields and must not be
summed with cash.

The exact coverage/width-domain key is derived as
`level|layer|measure_kind|units|cash_recognition`. It indexes the manifest's
run-wide `scale_domains`. The regular v2 client derives `measureDomainId` and
`scaleDomainId` from those edge fields; comparison rows additionally return
`measure_domain_id` explicitly.

Filtering is performed against the complete quarter edge set. Results are
sorted by descending absolute value and stable ID, then value-coverage selection
is applied independently within each exact compatible domain, then pagination.
The cursor is bound to the run/schema/quarter/query digest and cannot be reused
for a different state. `parent_id` returns the recorded children of a rollup
edge; those children reconcile to their parent within the artifact's declared
tolerance.

The transitional `detail`, `limit`, `sector_limit`, and `firm_id` parameters
remain for v1 consumers. New clients should use `level`, `focus`, and
`page_size`. A v1 trace is adapted into the v2 response shape, but unsupported
evidence remains absent and is declared by capabilities. An aggregate-only
historical run returns 404 instead of a fabricated network.

### GET /api/runs/{run_id}/cashflows/export

```text
GET /api/runs/{run_id}/cashflows/export
  ?quarter=&level=&focus=&parent_id=&edge_id=&layers=&recognition=
  &direction=&min_amount=&include_potential=&format=csv|jsonl
```

Export applies the semantic filters to the complete edge table and does not
apply canvas LOD, coverage truncation, or page size.

### GET /api/datasets/{dataset_id}/sector-metadata

Returns dataset-scoped sector identity and grouping metadata. Each sector has
an index, code, label, short label, group identity/order/color, classification,
and version. The legacy `/sector-metadata.json` asset remains available for
self-contained prototypes, but new clients should use the dataset endpoint.

### Experiments and comparison

```text
GET  /api/experiments
POST /api/experiments
GET  /api/experiments/{experiment_id}
GET  /api/compare/cashflows
  ?run_a=&run_b=&quarter=&level=&layers=&focus=&direction=&recognition=
  &coverage=&limit=&min_amount=&min_delta=&include_unchanged=
  &include_potential=&experiment_id=
```

An experiment persists the normalized baseline specification, declared
intervention diff, seed schedule and pairing strategy, baseline/treatment run
IDs and roles, realized diff, and compatibility evidence. Creation may reuse a
completed baseline run or create the baseline from `base_spec`; it launches the
matched treatment as a normal persisted run.

Comparison performs a full outer join of the two complete edge tables by stable
semantic ID before level/layer/focus filtering, coverage selection, or the
return limit. Missing edges are zero. It returns per-domain coverage,
`shared_scale_domains` formed from the exact run-wide maxima of A and B, and
`added`, `removed`, `increased`, `decreased`, or optional `unchanged` rows.

Side magnitudes are non-negative in each row's displayed direction. The
canonical numeric delta is `signed_value_B - signed_value_A`. If the canonical
sign reverses, the API emits two uniquely identified rows under one semantic
relationship: removal of A's recorded direction and addition of B's recorded
direction. Never collapse those two rows into one arrow.

`compatibility.paired` is fail-closed. Paired-treatment wording requires a
declared first-class experiment; matching non-intervention specs, seeds,
realization, schemas, capabilities, producer/model/trace source digests,
dataset/calibration/initialized-state digests, and RNG policy; and no
out-of-contract difference. The recorded worker Julia version, thread count,
architecture, kernel, and word size must also match exactly. Serial and
parallel stepping modes must match;
same-mode no-op equality is evaluated under the response's declared numeric
tolerance. Missing or mismatched evidence yields a descriptive run difference.
The current default-RNG policy is not stream-stable after
treatment-dependent draw consumption diverges, so firm-level causal pairing is
not claimed. Even an eligible sector comparison reports recorded simulated
differences, not edge-level causal attribution.

## Derived money flows (recipe)

This recipe is retained only for legacy prototypes that consume aggregate
summaries. The Explorer and Cash Flow Canvas must prefer a traced normalized
ledger. If a prototype uses the recipe below, every agent-to-agent flow is a
**derived estimate** and must be labelled "derived" in the UI. Per quarter t,
with `defl = gdp_deflator.mean[t]` and knob defaults (or the run's overrides if
you track them):

- nominal GDP: `real_gdp[t] * defl`
- Households → Firms (consumption): `C = real_household_consumption[t] * defl`
- Government → Firms (purchases): `G = real_government_consumption[t] * defl`
- RoW → Firms (exports): `X = real_exports[t] * defl`
- Firms → RoW (imports): `M = real_imports[t] * defl`
- Firms → Firms (investment): `I = real_fixed_capitalformation[t] * defl`
- Firms → Households (wages): `W = wages[t]` (nominal)
- Households → Government (VAT): `tau_VAT * C`
- Households → Government (income tax): `tau_INC * W`
- Firms+Workers → Government (social insurance): `(tau_SIF + tau_SIW) * W`
- Firms → Government (corporate tax, rough): `tau_FIRM * max(0, nominalGDP − W)`
- Government → Households (benefits, rough): `(sb_inact*4130 + sb_other*9215) * defl / 100 * 100` → just `(4.6627*4130 + 0.8854*9215) * defl ≈ 27,400 * defl`
- Bank ↔ everyone (policy rate backdrop): `euribor_annual[t]` as ambient indicator
- Sector split of any Firms flow: distribute by `real_sector_gva.mean[t][s] / Σ_s`
  or by basket vectors (`b_HH_g` for consumption, `c_G_g` for gov, `c_E_g` exports).

## The 15 phases of one simulated quarter (from src/one_step.jl)

1. Insolvent firms are restructured/financed
2. Agents form growth + inflation expectations
3. Central bank sets policy rate (Taylor rule)
4. (Optional shock applied)
5. Bank sets loan rate (policy rate + risk premium mu)
6. Firms decide prices, output, hiring, investment, loan demand
7. Credit market: firms ↔ bank search & matching
8. Labour market: firms ↔ households search & matching
9. Production (Leontief), wage updates
10. Government sets social benefits; households set consumption/investment budgets (psi, psi_H)
11. Government expenditure budget; RoW sets import/export budgets
12. Goods market: all buyers ↔ all sellers search & matching (biggest compute step)
13. Price indices update → inflation
14. Profits, dividends (theta_DIV), taxes collected (tau_*)
15. Balance sheets settle: deposits, loans, equity, government debt, GDP recorded

## Design rules

- Each prototype lives entirely in its own folder; no imports from siblings; no build
  step; vanilla ES modules or plain scripts. CDN libraries allowed (the existing app
  already uses cdn.plot.ly): d3@7 `https://cdn.jsdelivr.net/npm/d3@7`, d3-sankey
  `https://cdn.jsdelivr.net/npm/d3-sankey@0.12.3`, plotly
  `https://cdn.plot.ly/plotly-2.30.0.min.js`. Prefer hand-rolled canvas/SVG where
  reasonable — fewer moving parts.
- Must render something meaningful within ~2 s of load using **existing runs**
  (GET /api/runs → pick newest done run, or clearly prompt if none).
- Dark, game-like aesthetic is welcome; keep text legible (WCAG-ish contrast),
  system-ui/monospace font stacks fine. Design for a 1280×800 viewport minimum;
  degrade gracefully.
- Handle API failure states visibly (backend down → banner, not blank canvas).
- No external network calls other than the listed CDNs and /api.
- Educational framing matters: this is a teaching instrument for how an agent-based
  economy works. Label derived/estimated data honestly.
- Never combine coverage or line-width scales across incompatible domains. The
  exact domain includes level, layer, measure kind, units, and recognition.
  Run views use manifest-wide domains; comparison uses a paired-run-wide maximum.
- Distinguish server coverage, active-view filtering, and canvas LOD.
  Server total/matching fields describe the complete query while returned
  fields describe the page; the canvas may draw fewer relationships for
  readability and must disclose that omission while leaving the table/export
  available.
- Do not present phase chronology as event timestamps. The current trace stores
  quarter settlement and model-equation/event evidence, not a phase log.
- `deep`, `ensemble_network`, and `checkpoint` trace profiles, phase detail,
  checkpoints, true unmet demand, and firm-identity causal comparison are
  capability-gated. Do not synthesize them from available aggregates.
