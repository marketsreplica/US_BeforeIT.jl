# BeforeIT Web UI (local)

This local dashboard runs `BeforeIT` simulations and visualizes calibrated inputs
and outputs. It exposes:

- the U.S. 2026 Q1 nowcast and 2024 Q4 structural calibration;
- Austria 2024 Q4 structural data;
- the Austria 2026 Q1 nowcast;
- Austrian baseline, upside, and downside paths from 2026 Q2 through 2031 Q4;
  and
- the original 2010 Austria, Italy, and steady-state datasets.

## Run

From the repo root:

```bash
julia --project=apps/web -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=apps/web apps/web/src/server.jl
```

Then open `http://127.0.0.1:8080`.

The production Economy Complexity Explorer is served at
`http://127.0.0.1:8080/explorer/`. It opens completed runs that contain a
compatible trace and keeps the selected run, quarter, altitude, actor,
relationship, layers, direction, coverage target, table/map view, question, and
comparison run in the URL.

The visual digital-twin prototypes are served by the same Julia process at
`http://127.0.0.1:8080/prototypes/`:

- **Flow Atlas** — animated agent and sector topology;
- **The Machine** — input-to-mechanism Sankey plus a 15-phase quarter walkthrough;
- **Econopolis** — a policy-card city time-lapse; and
- **Twin Lab** — synchronized baseline/treatment comparison; and
- **Cash Flow Canvas** — an infinite 2D map backed by exact quarterly
  buyer-to-seller transaction traces.

## Economy Complexity Explorer

The Explorer is the supported connected-network view. Its economy, sector,
firm, receipt, history, and comparison states are projections of the same saved
run rather than separate reconstructed dashboards. New Standard-profile runs
persist a `quarter-ledger.v2` trace for one explicitly identified
representative realization:

- quarter `0` is the calibrated, pre-restructuring opening stock snapshot and
  intentionally has no flow edges;
- simulated quarters contain normalized edges with stable semantic IDs,
  canonical signed direction, display direction, purpose, units, evidence,
  timing, recognition, realization scope, rollup/component links, and an exact
  compatible-measure scale-domain identity;
- economy → sector → firm drill-down uses recorded `parent_ids` and
  `rollup_id`; parent and child sets are not displayed as summable peers;
- server coverage is computed after filtering the complete edge table,
  separately for every compatible measure domain; the client separately
  reports active-view filtering and canvas level-of-detail omission; and
- exports contain all server-matching relationships, not only the relationships
  drawn on the canvas.

The paired experiment builder persists an experiment object and launches a
matched treatment from a saved baseline. Comparison joins both complete edge
tables before filtering or coverage selection. It uses paired-treatment
language only when provenance and capability checks pass; otherwise the result
is explicitly descriptive. Provenance includes the worker's Julia version,
thread count, architecture, kernel, and word size, all of which must agree
exactly across a pair. A relationship whose signed direction reverses is
shown as two rows—removal of the old direction and addition of the new
direction—rather than as one misleading arrow. Edge-level deltas are recorded
differences, not proof that the intervention caused that individual edge.

See [`explorer/README.md`](explorer/README.md) for the UI, query, evidence,
comparison, performance, and capability contracts. The cross-prototype API
contract remains in [`prototypes/CONTRACT.md`](prototypes/CONTRACT.md).

## Notes

- The current UI default is the U.S. 2026 Q1 nowcast. Its first simulated
  quarter is 2026 Q2.
- U.S. structural and nowcast datasets currently expose unconditional
  stochastic projections. A 23-quarter run from the nowcast ends in 2031 Q4.
- U.S. traces use BEA Summary I-O sector identities and millions of U.S.
  dollars; Austrian and other euro-area datasets retain NACE/FIGARO identities
  and euro units.
- The official-data U.S. baseline can imply household dissaving, so its
  calibrated consumption-plus-housing propensity is preserved even when it is
  above one. Manual edits to either propensity still enforce a combined value
  no greater than one.
- Conditional paths can run for up to 23 quarters, ending in 2031 Q4.
- Conditional baseline, upside, and downside assumptions are currently
  available only for the Austria 2026 Q1 nowcast.
- Select **Unconditional model** to run stochastic projections for as many as
  80 quarters.
- Scenario paths condition government consumption, exports, and imports. GDP,
  inflation, and other reported series remain simulation outputs.
- Runs are persisted under `apps/web/runs/` (gitignored).
- First-class experiment records are persisted under `apps/web/experiments/`
  (gitignored).
- The server spawns a separate Julia process per run for isolation/responsiveness.
- New runs retain an exact transaction trace for one explicitly labelled
  representative realization. Institution flows come directly from model
  equations; firm links come from the goods-matching engine.
- Historical runs created before the trace was added remain aggregate-only and
  are labelled unavailable instead of receiving synthetic firm relationships.
- `quarter-ledger.v1` traces are adapted to the normalized response shape, but
  evidence that was never captured remains absent behind capability flags.
- Potential demand beyond current supply is retained separately and never
  counted as cash. It is a capacity counterfactual, not measured true unmet
  demand.
- Older prototype views that reconstruct flows from summary series continue to
  label those widths as derived estimates.
- The calibrated number of firms is fixed during a run. The `zeta_b` control
  changes refinancing for insolvent firms; it does not create additional firms.
- Deep mechanism logs, phase traces, checkpoints, multiple traced
  realizations, branch-from-quarter, and firm-identity causal comparisons remain
  capability-gated. The current RNG policy reseeds Julia's default RNG per
  realization but does not provide mechanism-specific, stream-stable common
  random numbers after treatment paths diverge. Compatibility requires the same
  serial/parallel stepping mode; tested same-mode parallel no-op traces matched
  aggregates exactly and individual edge values within the declared comparison
  tolerance.
