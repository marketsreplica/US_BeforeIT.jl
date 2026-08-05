# Economy Complexity Explorer

The Explorer is the production, run-centric network view served at
`/explorer/`. It connects economy, sector, firm, receipt, edge-history, and
paired-run comparison states without reconstructing a second economy in the
browser. The saved run and its trace are the authority for identities, values,
evidence, hierarchy, and available capabilities.

This document describes the implemented contract. It is intentionally narrower
than the full roadmap in
[`../ECONOMY_COMPLEXITY_EXPLORER_IMPLEMENTATION_PLAN.md`](../ECONOMY_COMPLEXITY_EXPLORER_IMPLEMENTATION_PLAN.md).

## Opening the Explorer

Start the web server from the repository root:

```bash
julia --project=apps/web apps/web/src/server.jl
```

Then open `http://127.0.0.1:8080/explorer/`. The Explorer selects a completed,
traced run if the URL does not name one. Aggregate-only historical runs remain
valid for summary charts but cannot acquire a synthetic network.

The URL is the shareable Explorer state:

```text
/explorer/
  ?run=<uuid>&q=<quarter>&altitude=economy|sectors|firms
  &focus=<actor-id>&selected=<edge-or-node-id>&parent=<rollup-edge-id>
  &layers=<comma-separated-layers>&direction=money|product
  &coverage=0.50..1.00&view=map|table
  &compare=<uuid>&question=<question-id>
```

Run, quarter, semantic altitude, focus, selected evidence, drill-down parent,
layers, direction, coverage, view, question, and comparison survive reload and
browser history. Invalid or unavailable identities are removed visibly rather
than silently replaced with a different actor.

## Quarter-ledger v2

New Standard-profile runs persist one exact representative realization using:

- on-disk schema `quarter-ledger.v2`;
- normalized API schema `explorer-edges.v2`; and
- one immutable artifact per quarter plus a run manifest.

Quarter `0` is an explicit calibrated, pre-restructuring stock snapshot. It
shares the timeline and actor directories with later quarters, has
`initial_period_has_flows=false`, and contains no transaction or equation-flow
edges. Quarters `1..T` are settled simulated quarters. Timeline motion moves
between recorded quarter totals; it is not transaction timing or interpolation
within a quarter.

Each normalized relationship has one primary measure. Its important fields are:

| Field | Meaning |
|---|---|
| `id` | Stable semantic relationship ID used for history and joins |
| `canonical_source`, `canonical_target` | Stable role-pair orientation |
| `signed_value` | Value relative to the canonical orientation |
| `source`, `target`, `amount` | Recorded display direction and non-negative magnitude |
| `layer`, `market`, `purpose` | Economic classification |
| `measure_kind`, `units`, `cash_recognition` | Compatibility and accounting meaning |
| `evidence_basis`, `aggregation`, `valuation_basis`, `timing` | What supports the claim |
| `realization_scope`, `realization_index` | Representative/ensemble scope |
| `rollup_id`, `component_id`, `parent_ids`, `summation_role` | Hierarchy and reconciliation |
| derived domain key | `level|layer|measure_kind|units|cash_recognition` indexes the manifest scale |

A realized cash payment and a capacity-counterfactual match are separate edges.
Stocks, stock changes, cash, quantities, and counterfactual values are not
co-summable. Potential capacity response is explicitly non-cash and does not
claim to be true unmet demand.

The server may adapt `quarter-ledger.v1` into the normalized response structure,
but it does not invent final-demand destinations, components, opening state,
stable signed direction, or valuation evidence that v1 did not retain.
Capabilities tell the client which journeys are available.

## Query, coverage, and export

Manifest:

```text
GET /api/runs/{run_id}/cashflows
```

Normalized quarter query:

```text
GET /api/runs/{run_id}/cashflows
  ?quarter=&level=macro|sector|firm
  &focus=&parent_id=&edge_id=&layers=&recognition=&direction=
  &min_amount=&coverage=&page_size=&cursor=&include_potential=
```

The server:

1. starts with the complete decoded quarter edge table;
2. applies level, focus/parent/edge, layer, recognition, direction, minimum,
   and counterfactual filters;
3. sorts by descending absolute value and stable ID;
4. applies the requested value target separately inside each exact compatible
   domain;
5. applies cursor pagination.

Coverage reports `count_total`, `count_matching`, `count_returned`,
`amount_total`, `amount_matching`, `amount_returned`, omitted amount, and
fractions for each domain. Opposite signs are compared by display magnitude;
incompatible measures are never netted into one denominator.

There are two deliberately separate omission concepts:

- **server coverage** describes the complete semantic query, coverage target,
  and returned page; and
- **active-view coverage** is recalculated after client-side domain/view
  adaptation and discloses server-returned relationships suppressed from that
  active model view.

Canvas LOD is a third, presentation-only count: a bounded scene can draw fewer
relationships than the active model. The canvas summary discloses that separate
omission. The relationship table continues to expose all relationships in the
returned response. Full export is:

```text
GET /api/runs/{run_id}/cashflows/export
  ?quarter=&level=&focus=&parent_id=&edge_id=&layers=&recognition=
  &direction=&min_amount=&include_potential=&format=csv|jsonl
```

Export re-applies semantic filters to the complete table; it is not constrained
by canvas LOD, coverage, or page size.

## Hierarchy, receipts, and evidence

Macro, sector, and firm edges are linked by recorded `parent_ids` and
`rollup_id`. Selecting a relationship opens its receipt/evidence inspector.
Drill-down queries the exact parent ID; reconcile upward selects the recorded
rollup. Components and their closed parent are alternative views, not peers
that may be added together.

Government revenue uses one closed fiscal parent and payer-specific component
children. Benefits, finance, products/final demand, and other supported
institution relationships follow the same parent/child rule. Reconciliation
uses the artifact's declared tolerance and diagnostic basis. A capability flag
remains false where the model did not capture the required evidence.

Edge history requests the same stable edge ID across recorded quarters. A
missing edge in a quarter is displayed as zero; quarter `0` remains an opening
stock state rather than an implied zero-transaction event.

## Scale domains

Line width is stable only inside an exact compatible domain:

```text
level | layer | measure_kind | units | cash_recognition
```

The run worker scans complete quarter tables and writes run-wide square-root
domain maxima to the manifest. A regular v2 response need not repeat that key
on every edge: the client derives its exact `scaleDomainId` from the five
compatibility fields and looks it up in the manifest. It does not collapse all
product, cash, stock, and counterfactual widths into a layer-wide maximum. This
keeps compatible widths comparable across quarters while preventing a large
macro edge from flattening firm-scale edges in another domain.

Comparison returns a `shared_scale_domains` map. Each maximum is the greater of
the two exact run-wide maxima, so A, B, and delta context use one paired-run-wide
reference. If a legacy domain is absent, the response marks stability honestly
instead of implying cross-quarter comparability.

## First-class experiments and comparison

Endpoints:

```text
GET  /api/experiments
POST /api/experiments
GET  /api/experiments/{experiment_id}
GET  /api/compare/cashflows?run_a=...&run_b=...&quarter=...
```

To reuse a completed baseline:

```json
{
  "name": "Sector productivity experiment",
  "baseline_run_id": "<uuid>",
  "intervention_diff": {
    "shock": {
      "type": "sector_productivity",
      "sector": 27,
      "multiplier": 0.95
    }
  }
}
```

Use `base_spec` instead of `baseline_run_id` to create both runs from a new
normalized specification; providing both is an error. An intervention may
change only `shock` and editable `overrides`, so it cannot silently alter the
horizon, ensemble, seed schedule, scenario, or trace policy.

The in-Explorer builder reuses the selected run as baseline and launches one
matched treatment. The exposed interventions are interest-rate, aggregate
productivity, household-consumption, and sector-productivity changes whose
normalization and lifecycle are implemented by the run API. The intervention
begins at the first simulated quarter; duration is shown only for shock types
whose handler supports it.

An experiment record persists its normalized base specification, declared and
realized intervention diff, pairing/seed schedule, run IDs and roles, and
compatibility evidence. It does not mutate the baseline artifact.

Comparison joins the union of stable semantic IDs from both complete quarter
tables before applying semantic filters, minimum delta, coverage, or the return
limit. A relationship absent from one run is zero on that side. The result
classifies display-magnitude change as:

- `added`: zero in A, present in B;
- `removed`: present in A, zero in B;
- `increased`: same recorded direction and larger magnitude in B;
- `decreased`: same recorded direction and smaller magnitude in B; or
- `unchanged`: equal within the response's absolute/relative tolerance.

The canonical numeric delta remains
`canonical_signed_value_B - canonical_signed_value_A`. If the sign reverses,
one arrow cannot represent the change: the API emits a uniquely identified
`removed` row in A's recorded direction and an `added` row in B's recorded
direction. Both retain the original semantic relationship ID and a shared
reversal-group ID.

The UI renders added/increased relationships in mint and
removed/decreased relationships in coral; dash patterns distinguish
addition/removal from magnitude changes. Counts and value coverage remain
separate per compatible measure.

Compatibility is fail-closed. Paired-treatment language requires:

- a persisted experiment that declares the baseline and treatment roles;
- exact agreement outside its normalized intervention diff;
- matching dataset, classification/calibration, horizon/period, ensemble,
  seed schedule, traced realization, schema, aggregation/valuation, and
  required capabilities;
- the same serial/parallel stepping mode; same-mode no-op equality is evaluated
  under the comparison response's declared numeric tolerance;
- present and internally consistent producer/model/trace source digests,
  dataset/calibration/initial-state digests, and RNG policy in both specs and
  manifests;
- exact agreement on the worker Julia version, thread count, architecture,
  kernel, and word size recorded by both runs.

Missing or mismatched evidence produces a descriptive comparison. The current
policy reseeds Julia's implicit default RNG before each realization and can
match seed schedules, but mechanisms do not own independent streams.
Treatment-dependent draw consumption can therefore diverge after paths split.
Firm-level common-random-number identity and firm-edge causal attribution are
not claimed. Sector-level eligible comparisons are still simulated
counterfactual evidence at the paired-run level, not proof that the
intervention caused any single edge.

Selecting a supported firm, sector, production aggregate, household aggregate,
or household cohort also exposes an exact deposit/overdraft stock identity:
opening snapshot + recorded signed snapshot change = closing snapshot, with its
residual and tolerance. Cash-category chips beside it summarize only the
current returned query. They are explicitly not terms in that stock identity,
and partial coverage/focus/layer states are disclosed.

## Browser controls and accessibility surface

Pointer controls support pan, wheel zoom, selection, receipt inspection, and
semantic drill/roll-up. The stage buttons zoom, fit, and clear focus. The
timeline changes recorded quarters and can play them in sequence. Layer chips
support toggle, all, and solo; actor search accepts sector identity or synthetic
firm ID. The table is the non-canvas relationship view.

With the canvas focused:

| Key | Action |
|---|---|
| `N` / `Shift+N` | Cycle actors forward/backward |
| `R` / `Shift+R` | Cycle relationships forward/backward |
| `Enter` | Reopen the selected/hovered evidence |
| `F` | Fit the scene |
| Arrow keys | Pan (hold Shift for a larger step) |
| `+` / `-` | Zoom |
| `Escape` | Clear selection |

The canvas publishes `aria-keyshortcuts`, a changing accessible label, and a
live text summary of period, returned coverage, LOD omission, and comparison
meaning. A skip link targets the relationship table. Reduced-motion preference
disables animated playback effects.

Automated browser checks and keyboard interaction checks support engineering
validation, but the planned manual VoiceOver/Safari journey and a second
screen-reader/browser combination have not yet been completed. They remain
external release evidence, not an implemented-data claim.

The repeatable local browser harness is
`apps/web/test/explorer_browser_smoke.py`. Its verified Python 3.12 dependency
set is pinned in `apps/web/test/requirements-browser.txt`. On a new test
machine, install it and its browser once:

```sh
python3.12 -m pip install -r apps/web/test/requirements-browser.txt
python3.12 -m playwright install chromium
```

With the Julia server running and a completed Standard-trace baseline (plus an
optional paired treatment), run:

```sh
python3.12 apps/web/test/explorer_browser_smoke.py \
  --base-url http://127.0.0.1:8081 \
  --run BASELINE_RUN_ID \
  --compare TREATMENT_RUN_ID
```

It uses Python Playwright/Chromium and fails on page or console errors. It
checks desktop DPR 1 and 2, every altitude, firm search before drill-down,
focus preservation, deep-link reload, 20 rapid state changes, filtering,
camera recovery, keyboard evidence selection, mobile layout, reduced motion,
and paired-comparison disclosure. Screenshots default to
`/private/tmp/beforeit-explorer-acceptance` so test evidence does not become a
repository artifact. Pure coverage and table-copy checks run with
`node --test apps/web/explorer/**/*.test.mjs` in shells that expand `**`.

## Persistence, codec, caches, and measured stress

V2 edge arrays are JSON UTF-8 bytes compressed with gzip level 1 inside each
JLD2 quarter artifact (`json-utf8-gzip.v1`). The artifact metadata records
compressed and uncompressed byte sizes. Legacy column copies are dropped from
new compact artifacts after scale collection.

Server caches are LRU-bounded and invalidated by artifact path, byte size, and
modification time:

- decoded quarter artifacts: at most 4;
- comparison quarter indexes: at most 4;
- joined comparison pairs: at most 2;
- comparison filtered scopes: at most 6;
- validated cross-run identity pairs: at most 8; and
- browser immutable-response cache: at most 18 entries.

These are entry-count bounds sized for Standard-profile artifacts, not a claim
of a universal byte ceiling. New profiles need their own measured storage and
memory budgets before enablement.

Local stress evidence on a 54,966-edge Standard quarter:

| Operation | Compiled cold artifact/query | Warm cache |
|---|---:|---:|
| Quarter query on a new gzip artifact | 0.613 s | 0.146 s |
| Complete-table comparison | 1.63 s | 0.067 s |

“Compiled cold” means the relevant Julia methods had already undergone
one-time compilation but the artifact/query cache was cold. The numbers exclude
Julia startup and first-method compilation, are local engineering measurements
rather than a cross-machine P95, and do not establish browser paint time.

## Capability gates and deliberate deviations

This release implements the truthful foundation, connected graph, shared
Explorer, and the sector-level flagship experiment path. It deliberately
rejects unsupported trace requests rather than writing placeholders:

- **R3b statistical/firm depth:** no ensemble quantile/path endpoints,
  firm-level stream-stable pairing, or validated complexity-metric panel;
- **R4 mechanism evidence:** no credit-decision, labour, restructuring,
  settlement, phase, distribution, or narrative event logs;
- **R5 research/checkpoints:** no state/RNG checkpoint format,
  branch-from-quarter, sweep runner, rare-world replay, or phase diagram;
- no phase timestamps or phase-accurate playback;
- no checkpoint continuation lifecycle;
- no true unmet-demand measurement (capacity counterfactual is not a synonym);
- no individual household identity network by default.

The roadmap proposes Deep, Ensemble Network, and Checkpoint profiles, but the
run API currently accepts only Summary and Standard mechanics. The other
profile names, phase detail, and checkpoints are rejected by capability
validation.

The UI uses a bounded deterministic level-of-detail canvas rather than drawing
every returned edge at once. This is an intentional legibility/performance
deviation; omitted counts are disclosed and the table/export remains available.
Playback shows recorded quarter-to-quarter states, not invented intra-quarter
animation.

Manual assistive-technology evidence, the four public-beta journey sign-off,
and user-comprehension studies are still external release work. Their absence
does not change the data contract, but it means this implementation should not
be described as having completed those public-beta evidence gates.
