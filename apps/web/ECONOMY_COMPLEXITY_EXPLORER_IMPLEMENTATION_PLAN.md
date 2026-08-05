# Economy Complexity Explorer

## Integrated product and implementation plan

Status: implementation handoff  
Date: 2026-08-01  
Scope: BeforeIT web application, visual prototypes, trace API, and required model instrumentation  
Source proposal: [Economy Complexity Explorer — Design Proposal, revision 2](https://claude.ai/code/artifact/312f5d4a-fd8c-4e15-a5d1-bcd016a25d21)

## Product context and design philosophy

### Why this product exists

The ambition is to create the **ultimate economy complexity explorer**: an educational, demonstrative, and analytically credible interface through which a person can learn how an economy works as a network of interacting agents.

The agent-based model already represents an economy from the bottom up. Firms buy, sell, hire, borrow, invest, pay taxes, and respond to changing conditions. Households, government, the commercial bank, the central bank, and the rest of the world participate in connected monetary and real flows. Those local interactions aggregate into sector performance and ultimately into employment, prices, output, public finances, credit conditions, and other macroeconomic outcomes.

The UI should make that emergence visible and understandable. Its purpose is not merely to display a large graph or another set of macroeconomic charts. It should let a user investigate:

- which actors participate in an economic outcome;
- how money, products and services, income, taxes, credit, and financial positions move among them;
- how an individual firm is embedded in suppliers, customers, institutions, and its sector;
- how firm-level behavior aggregates into sector and macro outcomes;
- how dependencies, concentration, feedback, bottlenecks, unused capacity, heterogeneity, and network structure shape the system;
- how the same economy evolves through time and changes under a policy or parameter intervention.

The product should turn the simulation from a black box that produces indicators into an inspectable economic world.

### The experience we want to create

A user should be able to begin with a comprehensible object—a firm, sector, institution, macro flow, or curated question—and progressively reveal the surrounding economy.

For example, a user might:

1. isolate a synthetic agriculture, manufacturing, construction, retail, or services firm;
2. see what it buys and sells and which household cohorts, government payment categories, bank relationships, and foreign buyers connect to it;
3. expand to its named sector and understand the sector’s suppliers, customers, institutional payments, and structural dependencies;
4. reconcile those firm and sector relationships upward into the corresponding macro accounts;
5. move through quarters to see relationships appear, disappear, strengthen, or weaken;
6. return to the main application, change an initial condition, model parameter, or supported policy intervention, and run a new simulation;
7. compare the saved baseline and intervention, then drill into the network mechanisms associated with their different outcomes.

The interaction should work in both directions:

```text
Firm transactions → sector structure → macro outcome
Macro outcome → contributing sectors → firms and relationships
```

This two-way movement is central to the product. The user should not lose their selected actor, question, evidence, or accounting context when moving between scales.

### What the UI must help users understand

The Explorer should teach several ideas from complexity economics through direct interaction:

- **Emergence** — macro outcomes arise from many heterogeneous local interactions.
- **Interdependence** — firms and institutions depend on networks of suppliers, customers, workers, finance, government, and foreign trade.
- **Aggregation** — firm transactions become sector totals and macro accounts under explicit accounting rules.
- **Feedback** — changes in demand, production, employment, credit, prices, and balance sheets can reinforce or dampen one another over time.
- **Propagation** — a localized intervention or disruption can alter connected sectors and eventually system-level outcomes.
- **Heterogeneity** — firms and household roles experience the same economy differently.
- **Path dependence and contingency** — outcomes depend on prior state, network position, matching, and simulated randomness.
- **Structure versus realization** — input-output exposure, potential supply response, recorded transactions, and simulated counterfactual outcomes are different economic objects.

These concepts should be learned by exploring real model records and reconciliations, not by adding decorative complexity terminology.

### Core UX principles

1. **Questions before controls.** Curated questions such as “Where did government purchases go?” or “Who supplies construction?” teach users what the instrument can answer. Advanced controls remain available after the question establishes context.
2. **Progressive disclosure.** Open with a legible ego network or macro circuit, then let users reveal peers, counterparties, additional layers, and finally the whole economy. Complexity should unfold rather than arrive as an unexplained hairball.
3. **One economy across scales.** Economy, sector, firm, receipt, history, and comparison views are projections of the same saved run and selection—not disconnected dashboards.
4. **Preserve context.** Selection, quarter, filters, evidence, scale, and comparison state survive drill-down, roll-up, playback, and deep linking.
5. **Names make the economy meaningful.** Prefer dataset-scoped sector codes and names and clearly synthetic firm labels over anonymous sector numbers and unexplained IDs.
6. **Include the full institutional circuit.** Households, government, the commercial bank, central bank, and rest of world should connect wherever the model records an applicable relationship. Services must be visible as named sectors even where the model uses a generic clearing mechanism.
7. **Make large networks queryable.** Filtering by actor, sector, economic layer, direction, evidence, amount, government spending, credit, principal, interest, and other categories is a primary interaction—not an afterthought.
8. **Reconcile, do not merely illustrate.** Users should be able to climb from a receipt or relationship to its firm, sector, and correct macro account and see why totals agree.
9. **Show change without inventing mechanism.** Time and comparison views should reveal recorded changes while distinguishing interpolation, chronology, structural exposure, and simulated counterfactual evidence.
10. **Be honest about the model.** Every visible relationship should communicate what was recorded, calculated, aggregated, derived, representative, or unavailable. The interface must never gain visual drama by claiming more precision or causality than the simulation captured.
11. **Keep the whole economy as a destination.** The complete firm economy should remain reachable and visually impressive through level of detail, bundling, filtering, and stable layout—without requiring every raw edge to be drawn simultaneously.
12. **Design for explanation and discovery.** Receipts, accounting proofs, definitions, question states, and guided stories should help a learner form and test an explanation while always allowing a return to free exploration.

### Run-centric product context

The Explorer is part of the simulation workflow, not an isolated prototype:

```text
Configure → run → save → explore → explain → modify → rerun → compare
```

Runs created in the main application should retain their specifications, outputs, history, provenance, and available trace capabilities. A user should be able to open a completed run in the Explorer, inspect any supported quarter, return to its inputs, create a revised run, and compare outcomes without losing the relationship between the two experiments.

Old runs must remain useful at the level of evidence they contain. The UI should explain unavailable detail rather than reconstructing fictional transactions.

### Desired user outcome

After using the Explorer, a member of the primary audience should be able to explain, in their own words:

- what a selected firm or sector did during a quarter;
- which actors and economic layers connected to it;
- how its relationships contributed to a sector and macro account;
- how the surrounding network evolved;
- what changed between a baseline and supported intervention;
- which parts of that explanation are exact, equation-derived, aggregated, non-cash, representative, ensemble-based, or unavailable.

The intended emotional outcome is a productive sense of discovery: the economy initially appears complex, but the interface gives the user enough structure, evidence, and continuity to make that complexity intelligible.

### Decision filter for implementation

When product, visual, or engineering tradeoffs arise, prefer the option that most improves a user’s ability to answer:

> **Who interacted, what moved, why is it represented this way, how does it aggregate, how did it change, and what evidence supports that explanation?**

Features that do not improve exploration, experimentation, learning, reconciliation, or evidentiary honesty should not displace the core work required to make the economy understandable.

## 1. Executive decision

Build one run-centric Economy Complexity Explorer around three jobs:

1. **Explore** — move from economy to sector to firm to counterparty while preserving selection and accounting context.
2. **Experiment** — compare a baseline and intervention with paired seeds and inspect the network differences.
3. **Learn** — use receipts, reconciliations, explanations, and guided stories whose claims are backed by the data available in that run.

The saved run is the spine. Macro, sector, firm, comparison, and educational views are different projections of the same run rather than separate products with separate state.

The core interaction is an emergence ladder:

```text
Economy → sector group → sector → firm → counterparty → receipt
    ↑                                                  ↓
    └──────────── reconcile into macro accounts ──────┘
```

The implementation should be incremental:

- stabilize and complete the existing Ledger first;
- introduce a shared Explorer shell only after its economic graph is trustworthy;
- migrate useful visual grammar from Machine and Twin Lab rather than merging all five prototypes wholesale;
- preserve existing prototypes as reference implementations until the Explorer reaches parity.

The coherent public beta is:

> One trustworthy saved run, one connected actor graph, three navigable aggregation levels, and four canonical questions.

The flagship v1 adds one paired policy experiment without changing the Explorer’s state or evidence model.

## 2. Reconciliation of the contested points

The two reviews are substantially aligned. The following decisions resolve the remaining differences.

| Topic | Final decision | Implementation consequence |
|---|---|---|
| Data layers versus stories | Complete the minimum story-capable graph before authoring any story that depends on it. | Institution edges, household cohorts, final-demand aggregates, and tax/benefit components precede government-spending and receipt-to-macro stories. Credit, labour, insolvency, and phase stories wait for their loggers. |
| Animation honesty | Inter-quarter tweening and amount-proportional particles are allowed. Invented within-quarter sequencing is not. | Motion between recorded quarter states carries the note “Motion represents the quarter’s recorded total, not transaction timing.” A phase scrubber appears only for runs with phase-log capability. |
| Ego network versus whole economy | Open on an ego network, but retain the whole economy as a deliberate level-of-detail destination. | All firms may be visible at the widest firm altitude, while edges are bundled or aggregated by sector pair. The product keeps the whole-economy revelation without drawing every raw edge at once. |
| Counts and value coverage | Derive all values from the selected run and active query. | The server returns total, matching, and returned counts and amounts. The UI never hardcodes audit snapshots such as a particular relationship count or value percentage. |
| Blank Sector canvas | Treat this as a camera/layout defect, but do not assume the root cause. | `selectRun` and mode changes already call `loadQuarter({fit: true})`, which already invokes `fitView()`. Instrument viewport size, device-pixel ratio, scene bounds, and camera state; add a regression test before changing the camera code. |
| Rapid mode/quarter race | Treat the observed race as untriaged rather than attributing it to the existing token guard. | `requestToken` already prevents stale fetches from applying their payload. Reproduce the failure around playback, category state, camera state, and post-fetch rendering before choosing the fix. |
| Cost of final-demand tracing | Consider the existing model hook a major head start, not a one-line feature. | Enabling `:final_demand` is one worker change, but the collector currently rejects non-business markets. Aggregation keys, serialization, API materialization, coverage calculations, capability flags, storage budgets, and tests are required. |
| Final-demand purpose | Label only the purpose the model can identify at the seller match. | Household consumption and housing investment are currently combined before seller matching, and business materials and capital goods are also combined. Until purpose is logged earlier, use “household final demand” and “business inputs”; do not manufacture a finer split. |
| Current “potential demand” edges | Rename them “capacity-counterfactual match” or “potential supply response.” | They represent a second-pass match against unused productive capacity, not a general observation that demand failed to find a seller. They remain non-cash, dashed, and separate from any future true unmet-demand measure. |
| “Follow a euro” | Keep only as a clearly derived notional allocation. | Money is fungible and the model does not track currency tokens. Call it “Notional €1 decomposition” or “Follow related payment paths,” and label proportional allocations as derived. |
| “Transaction to GDP” | Reframe as “Receipt to macro account.” | Government and foreign receipts can reconcile to recorded macro components. A household receipt maps only to combined household final demand until consumption versus housing investment is instrumented. An intermediate purchase maps to turnover/input use, not a one-for-one GDP contribution. |
| Shock causality | A paired-seed treatment difference supports a controlled simulation contrast, not unique edge-by-edge causal attribution. | The difference network displays counterfactual deltas. Random-draw consumption can diverge after treatment; stronger path-level common-random-number claims require mechanism/agent/time-specific RNG streams. |
| Ensemble edge persistence | Start at the sector level. | The same firm ID can represent a differently initialized synthetic firm under another seed. Firm-edge persistence requires clones of one initialized economy with dynamic randomness separated from initialization randomness. |
| Checkpoints | Treat branch-from-quarter as versioned simulation infrastructure, not raw object serialization. | A checkpoint must include model state, simulation time, RNG state, dataset and model digests, schema version, and deterministic replay tests. |

## 3. Product principles and semantic guardrails

These rules are release requirements, not optional design polish.

### 3.1 Every visual claim carries evidence

The useful user-facing badges remain, but the API should model their dimensions orthogonally because they can coexist.

An edge can be both an exact transaction aggregate and part of one representative realization. Store:

- **basis** — transaction event, stock change, model equation, derived allocation, or simulated metric;
- **scope** — representative realization, selected realization, or ensemble statistic;
- **aggregation** — none, exact sum, cohort-to-sector, sector-to-macro, or named derived method;
- **timing** — opening snapshot, quarterly window, closing snapshot, or logged phase;
- **units** — stock, amount per quarter, quantity, rate, count, or dimensionless influence;
- **recognition** — realized cash, stock/non-cash, capacity counterfactual, or illustrative;
- **scenario status** — baseline, treatment, paired delta, unpaired difference, or exposure exercise;
- **valuation basis** — the price/tax basis needed for reconciliation.

The UI combines these fields into concise badges such as:

- Exact transactions · summed by buyer class · realization 1
- Exact stock change · quarter
- Model-equation aggregate · realization 1
- Derived allocation · expenditure basket
- Ensemble median · 16 realizations

### 3.2 Never conflate different economic objects

- Money direction and product/service direction are opposite for purchases.
- Outstanding deposits and loans are stocks, not quarterly payments.
- Net stock changes are not gross transactions.
- Capacity-counterfactual matches encode a possible supply response, not cash or observed unmet demand.
- A network association is not a causal path.
- The representative transaction network is not the ensemble mean.
- A purpose that was combined before matching cannot be recovered exactly after the fact.

### 3.3 Synthetic identities remain explicit

- Use dataset-scoped sector codes and names.
- Use labels such as `C24 · Basic metals · Firm 003`.
- Mark firms and household cohorts as synthetic/representative.
- Do not invent legal company names, locations, or real household identities.
- Explain that the commercial-bank institution is distinct from financial-services sector firms.

### 3.4 Whole-economy views use level of detail

The complete economy remains available, but visual density changes with altitude:

- far view — sector-pair bundles and communities;
- middle view — selected sectors and top-value firm relationships;
- near view — individual firms, counterparties, and receipts;
- table/export — all relationships matching the query.

### 3.5 Counts, scales, and layouts remain comparable

- Display returned count and returned value as shares of the matching total.
- Use run-wide or paired-run-wide scale domains per layer.
- Preserve actor positions across quarters and compatible comparisons.
- Changing a filter must not silently change the thickness denominator.
- Changing scale must not discard the current selection.

## 4. Current system and constraints

### 4.1 Existing product assets

| Surface | Reusable strength | Limitation to avoid carrying forward |
|---|---|---|
| Flow Atlas | Connected institutions, sector groups, KPI orientation | Derived rather than exact flows; no firm level |
| Machine | Macro circuit, controls, phase pedagogy | Separate state and mostly aggregate mechanism view |
| Econopolis | Friendly policy cards and playful onboarding | Metaphorical geography and limited analytical depth |
| Twin Lab | Paired-run comparison and impact framing | Comparison is isolated from network drill-down |
| Ledger | Exact bilateral business transactions, firm focus, accounting diagnostics | Numeric sectors, disconnected institutions below Macro, one firm-level market |

The Explorer should reuse these strengths through adapters and extracted modules. It should not reproduce five independent run pickers, timelines, and state models.

### 4.2 Model/API coverage

| Layer | Model state or hook | Current API | Required work |
|---|---|---|---|
| Business products/services | Exact bilateral matching, realized events, and capacity-counterfactual matches | Exact representative trace | Clarify combined input purpose; extend coverage, receipts, and LOD |
| Final demand | Existing retail transaction hook with buyer classes | Disabled and discarded | Enable, aggregate during collection, materialize |
| Wages/dividends/taxes | Per-firm state and component equations | Macro composites | Emit firm and sector allocations with correct evidence |
| Credit | Desired/granted credit, loans, interest per firm | Macro aggregate | Emit state-derived edges first; add event logger later |
| Labour | Employer IDs, vacancies, hires and separations in model | Not exposed | Add event logger and compact transition aggregates |
| Benefits/households | Active, inactive, firm-owner, and bank-owner household state | One aggregate household node | Add cohort nodes and class-specific flows |
| Insolvency | Restructuring and bank financing occur | Aggregate restart financing | Add firm event log |
| Structure/pressure | Input-output matrix and several model pressure fields | Dataset endpoints and optional capacity-counterfactual relationships | Normalize as structural, pressure, and counterfactual layers |
| History | Aggregate paths plus one traced realization | Mean/std plus cash-flow trace | Add quantiles, selectable trace realization, then sector persistence |
| Branching | Initial run specification only | Rerun from initial state | Versioned checkpoints and branch endpoint |

### 4.3 Genuine model limitations

These are not visualization bugs:

- one representative commercial bank means no interbank market, bank competition, deposit migration, or bank-network contagion;
- service sectors exist, but use the generic product-clearing mechanism rather than service-specific non-storability or contract behavior;
- simulated firms are scaled synthetic agents, not real enterprises;
- household consumption and housing investment, and business materials and capital inputs, are combined before seller matching in the current mechanism;
- old aggregate-only runs cannot be reconstructed into exact transaction networks;
- only one realization is currently traced;
- firm IDs are not comparable across independently initialized ensemble realizations without a stricter initialization/RNG protocol;
- full agent states and RNG state are not checkpointed.

Features that cross these boundaries require separate model RFCs, not UI wording that implies they already exist.

## 5. Target product architecture

### 5.1 The run is the shared addressable object

Extend the normalized run specification additively:

```json
{
  "name": "Rate hike · baseline comparison",
  "description": "Optional human note",
  "parent_run_id": null,
  "experiment_id": null,
  "experiment_role": null,
  "trace": {
    "profile": "standard",
    "realization_indices": [1],
    "phase_detail": "none",
    "checkpoints": false
  }
}
```

Older specifications remain valid. Missing fields receive defaults.

Every run advertises capabilities rather than forcing the client to infer them:

```json
{
  "business_transactions": "exact_representative",
  "final_demand": "cohort_sector_aggregate",
  "credit": "state_derived",
  "labor": "unavailable",
  "phase_trace": false,
  "checkpoints": false,
  "traced_realizations": [1]
}
```

### 5.2 Shared Explorer state

The canonical URL state is:

```text
/explorer/
  ?run=<uuid>
  &q=3
  &altitude=firm
  &focus=firm:42
  &layers=products,credit
  &direction=money
  &coverage=0.85
  &view=map
  &compare=<uuid>
```

Required properties:

- copying and reopening the URL restores the same meaningful state;
- unsupported state is removed with an explicit explanation;
- run, quarter, selection, filters, and comparison survive altitude changes;
- historical runs retain macro access even when detailed trace capability is absent.

### 5.3 Discrete semantic zoom first

Ship stable semantic altitudes before attempting continuous scroll-wheel metamorphosis:

1. Economy/institutions
2. Sector groups
3. Named sectors
4. Firms
5. Counterparties/receipts

Macro, Sectors, and Firms remain visible jump controls and accessible fallbacks. Smooth zoom can later trigger altitude changes, but correctness must not depend on a gesture.

### 5.4 Visual grammar by altitude

| Altitude | Primary grammar | Alternate |
|---|---|---|
| Economy | Monetary circuit/Sankey | Network map |
| Sector groups/sectors | Supply-use matrix or bundled network | Chord/map |
| Firms | Ego-network canvas | Ranked relationship table |
| Counterparty/receipt | Inspector and accounting strip | Edge history |
| Compare | Delta network with shared scale | Side-by-side/table |

Do not implement all three grammars at every altitude in the first release.

### 5.5 Production Explorer structure

Stabilization work remains in `apps/web/prototypes/ledger/`. The production Explorer should graduate into its own modular surface rather than importing sibling prototypes:

```text
apps/web/explorer/
  index.html
  style.css
  api.js
  state.js
  url-state.js
  metadata.js
  shell.js
  views/
    economy.js
    sectors.js
    firms.js
    compare.js
  render/
    canvas.js
    sankey.js
    matrix.js
    layout.js
  panels/
    inspector.js
    receipt.js
    reconciliation.js
    questions.js
    table.js
```

Add a safe `/explorer/` static route in `apps/web/src/BeforeITWeb.jl`. Keep `/prototypes/*` available during migration and visual parity testing.

### 5.6 Layer and filter model

Layers represent different economic objects and never become one ambiguous edge soup:

- realized products and services;
- capacity-counterfactual supply response;
- wages, benefits, and dividends;
- fiscal payments;
- credit grants, principal, and interest;
- financial stocks and stock changes;
- foreign transactions;
- later labour, credit-rationing, insolvency, and structural-exposure overlays.

Orthogonal filters cover actor class, named sector, relationship category, money versus product direction, realized versus counterfactual status, evidence basis, amount/value coverage, and text search. A filter chip displays the selected-quarter amount and denominator, supports solo/remove, and is serialized in the URL.

The server applies economic predicates before truncation and returns totals for the full, matching, and returned sets. The UI applies only presentation predicates locally. This makes questions such as “government purchases,” “principal and interest,” and “who supplies construction?” reproducible saved states rather than bespoke screens.

### 5.7 Entry-state matrix

| Entry | Initial state |
|---|---|
| Standalone `/explorer/` with no URL state | Newest compatible traced run, latest completed quarter, deterministic firm ego, one-time orientation |
| `Explore network` from a completed main-app run | That run and latest completed quarter at Economy altitude, with the run outcome summarized |
| Aggregate-only historical run | Economy altitude with network capabilities explained as unavailable |
| Valid deep link | Restore the encoded run, quarter, altitude, focus, layers, filters, and comparison exactly; no automatic reselection |
| Cleared selection | Preserve the current layout and show a suggested question without silently selecting a new entity |

## 6. Data and API plan

### 6.1 Canonical dataset metadata

Add:

```text
GET /api/datasets/{dataset_id}/sector-metadata
```

Return:

```json
{
  "dataset_id": "AUSTRIA2026Q1",
  "classification": "NACE/FIGARO",
  "version": "...",
  "sectors": [
    {
      "index": 1,
      "code": "A01",
      "label": "Crop and animal production",
      "short_label": "Agriculture",
      "group_id": "PRIMARY",
      "group_label": "Primary",
      "group_order": 1,
      "group_color": "#..."
    }
  ]
}
```

Migration:

1. Establish `apps/web/metadata/sectors/NACE62.json` as the canonical web metadata asset and serve the endpoint from it.
2. Update Ledger and the Explorer to use it.
3. Add sector codes to new run artifacts and exports.
4. Keep prototype-local copies until every prototype is migrated.
5. Remove duplicates only in a separate cleanup change.

### 6.2 Quarter-ledger v2

Do not silently reinterpret `quarter-ledger.v1`. Introduce additive v2 fields, keep v1 readers working, and provide a client adapter for historical traced runs.

Normalize all graph relationships into an Explorer edge model:

```json
{
  "id": "final-demand:government:sector:27",
  "source": "government",
  "target": "sector:27",
  "layer": "money_flow",
  "market": "final_demand",
  "purpose": "government_purchase",
  "measure_kind": "cash_transaction",
  "cash_recognition": "realized",
  "amount": 1280.5,
  "quantity": 0.0,
  "match_count": 163,
  "units": "million_eur_per_quarter",
  "direction_semantics": "buyer_to_seller",
  "evidence_basis": "transaction_event",
  "realization_scope": "representative",
  "realization_index": 1,
  "aggregation": "government_buyers_to_sector",
  "valuation_basis": "declared_macro_basis",
  "rollup_id": "macro:government-purchases",
  "component_id": "government-purchase",
  "parent_ids": ["macro:government-purchases"]
}
```

Existing `flows`, `relationships`, and `sector_relationships` may remain during migration while an additive normalized `edges` array is introduced. New consumers should use one adapter-normalized edge interface.

Each normalized v2 edge carries one primary economic measure. A realized cash relationship and its capacity-counterfactual match are separate edge records with separate IDs, layers, recognition, evidence, units, coverage, and scale domains; do not carry `amount` and `potential_amount` as co-summable fields on one normalized edge.

For relationships that can reverse direction, keep a stable role-pair ID and canonical endpoints. Store a signed value relative to those endpoints, then derive display source/target from the sign. Do not preserve one ID while silently swapping its canonical source/target across quarters; histories and diffs operate on the stable key and signed value.

Track two separate versions:

- `trace_schema_version` — the on-disk artifact, such as `quarter-ledger.v1` or `quarter-ledger.v2`;
- `api_schema_version` — the normalized response contract served to clients.

The server may adapt v1 structure into the current response shape, but missing evidence remains absent behind capability flags. Clients accept the legacy numeric Boolean representation for one transition window while new responses emit real JSON Booleans.

### 6.3 Coverage contract

For each returned relationship set and layer, return:

```json
{
  "count_total": 0,
  "count_matching": 0,
  "count_returned": 0,
  "amount_total": 0.0,
  "amount_matching": 0.0,
  "amount_returned": 0.0
}
```

The server must compute omitted-edge value because the client cannot recover it from a truncated response.

Coverage is computed within one compatible measure/layer from non-negative display magnitudes (normally absolute signed value); it never nets opposite directions or mixes cash flows, stocks, quantities, and counterfactual values into one denominator.

Query contract:

```text
GET /api/runs/{id}/cashflows
  ?quarter=&level=&focus=&layers=&recognition=&direction=
  &min_amount=&coverage=&page_size=&cursor=

GET /api/runs/{id}/cashflows/export
  ?quarter=&level=&focus=&layers=&recognition=&direction=
  &min_amount=&format=csv|jsonl
```

The server applies filters to the complete edge set, sorts deterministically by descending absolute value then stable edge ID, and only then applies a requested value-coverage target and page size. An opaque cursor binds to the manifest/query digest so it cannot be reused against another run, quarter, or filter. Export returns every matching relationship plus the evidence/schema metadata needed to interpret it; it is not limited to the visual top-N.

The manifest additionally carries stable scale domains by layer:

```json
{
  "scale_domains": {
    "products": {"min": 0.0, "max": 0.0, "mapping": "sqrt"},
    "credit": {"min": 0.0, "max": 0.0, "mapping": "sqrt"}
  }
}
```

Paired comparison uses a domain shared by both runs.

New workers compute scale domains once for the complete run. For a legacy traced run, either materialize a versioned lazy sidecar or show an explicit current-quarter legacy-scale badge; never imply cross-quarter comparability when the domain is unavailable.

### 6.4 Components and rollups

Composite and component edges must never appear as simultaneously summable peers. Return nested components or mark them with `rollup_id`/`component_id`, and let the client display either the closed parent or its expanded children.

The payer-specific government-revenue decomposition contains ten lines, even though the aggregate government accounting has nine categories because social contributions split by payer:

1. employer social contribution;
2. worker social contribution;
3. labour income tax;
4. VAT;
5. household capital-formation tax;
6. capital-income tax;
7. corporate tax;
8. product tax;
9. production tax;
10. export tax.

Benefits expand into inactive, unemployment, and other benefits. Every child set must reconcile to its parent; unavailable historical detail remains capability-gated.

### 6.5 Trace profiles and data-volume policy

| Profile | Default content | Intended use |
|---|---|---|
| Summary | Aggregate histories only | Fast ensembles and old-style charts |
| Standard | Exact business trace plus online buyer-class → seller-firm final-demand aggregates, with sector rollups; sector/firm state-derived institution edges | Default Explorer run and firm/customer journeys |
| Deep | Selected realization with finer goods/stage detail, event receipts, and later labour/credit/phase detail | Mechanism autopsy |
| Ensemble network | Compact traces for a small selected set of realizations | Edge persistence and rare-world comparison |
| Checkpoint | Versioned state and RNG snapshots | Branch-from-quarter |

Default final-demand collection aggregates during logging:

- use an online key containing buyer kind, seller kind, seller sector or firm, good, and transaction stage;
- household class → seller firm and sector, labeled “household final demand” until consumption versus housing-investment purpose is instrumented before matching;
- government buyers → seller firm and sector;
- foreign buyers → seller firm and sector;
- for a focused firm, buyer class → that firm;
- individual household IDs are not stored by default.

“Explode market hub” must use captured realized buyer-to-seller aggregates. Planned or structural baskets such as household/government expenditure shares are not substitutes for realized destinations.

Set and test payload and storage budgets before enabling a profile in production. A suggested Standard-profile gate is at most 15% traced-realization runtime overhead, with storage proportional to buyer classes × active sellers/sector rollups rather than household IDs × firms.

### 6.6 Opening-state access

New traced runs should persist an explicit quarter-zero snapshot:

- calibrated/pre-restructuring stock state;
- no transaction edges;
- clear `timing` and `initial_period_has_flows=false`;
- accessible from the same timeline as an “Opening” state.

Also add the already-captured central-bank equity and bank reserve position to the public stock payload.

### 6.7 JSON type correctness

Fix boolean serialization before v2 fixtures are created. In Julia, `Bool <: Real`; `_sanitize_for_json` currently handles `Real` before `Bool`, so quarter-payload booleans can become `0.0` or `1.0`. Add an explicit Boolean branch and contract tests.

### 6.8 Experiment and comparison contract

Create a first-class experiment object:

```text
POST /api/experiments
GET  /api/experiments/{id}
GET  /api/compare/cashflows?run_a=…&run_b=…&quarter=…&level=…&layers=…
```

The experiment stores its normalized base specification, intervention diff, seed schedule, pairing strategy, run IDs, roles, and compatibility evidence. Run create/list/spec APIs round-trip optional names and experiment linkage; historical runs receive a generated display label without rewriting their specifications.

The comparison endpoint:

- validates exact non-intervention base-spec and initial-state digests, dataset/classification/calibration, model/code/schema versions, horizon/period, step/RNG policy, seed schedule, traced realization, aggregation/valuation basis, and required capabilities;
- joins complete edge tables by stable semantic ID before applying limits;
- treats a missing edge as zero;
- returns added, removed, increased, and decreased edges plus count/value coverage;
- makes identical run A/B produce an exact zero diff within the declared numeric contract;
- labels unpaired or capability-mismatched comparisons descriptive rather than causal;
- refuses paired-treatment language when one run differs outside the declared intervention or when trace profiles cannot support the requested level.

### 6.9 Ensemble summaries, events, phases, and distributions

R3b can derive macro/sector quantiles and stored individual aggregate paths from existing `results.jld2` without mechanism instrumentation:

```text
GET /api/runs/{id}/ensemble-summary?metrics=&quantiles=
GET /api/runs/{id}/paths?metrics=&realizations=
```

Add these only with their R4 capabilities and sidecars:

```text
GET /api/runs/{id}/events?quarter=&type=
GET /api/runs/{id}/phases?quarter=
GET /api/runs/{id}/distributions?quarter=
```

Prefer versioned worker sidecars for event and distribution artifacts so historical JLD2 results remain readable. A guided story declares its required capabilities and cannot start when any are absent.

## 7. Delivery plan

The estimates below are relative effort bands (M = medium, L = large, XL = program-scale), not calendar commitments. Re-estimate after the Foundation and Connected Graph spikes.

| Release | Relative effort | Depends on | Product outcome |
|---|---:|---|---|
| R0 · Truthful foundation | M | Current Ledger and deterministic fixture | Correct names, evidence, coverage, scales, types, and defect fixes |
| R1 · Connected graph | L | R0 contracts | Institutions, components, and final-demand destinations connect to sectors/firms |
| R2 · One Explorer | L | R1 minimum graph | Shared run shell, emergence ladder, receipts, playback, and deep links |
| R3a · Flagship paired experiment | M | R2 plus paired provenance | One sector-level shock, delta network, and synchronized macro result |
| R3b · Statistical/complexity depth | L | R3a | Firm-level comparison protocol, quantiles/paths, and interpretable measures |
| R4 · Deep mechanism logs | XL | R1 truth contract; can develop beside R2/R3 | Credit, labour, restructuring, phase, distribution, and story evidence |
| R5 · Checkpoints/research | XL | R3b and R4 replay guarantees | Quarter-boundary branching, sweeps, and advanced experiments |

```mermaid
flowchart LR
    F["R0 · Truthful foundation"] --> G["R1 · Connected economic graph"]
    G --> E["R2 · One Explorer"]
    E --> L["R3a · Paired sector experiment"]
    L --> D["R3b · Statistical & complexity depth"]
    G --> M["R4 · Deep mechanism logs"]
    L --> M
    D --> C["R5 · Checkpoints & research"]
    M --> C
```

### R0 — Truthful foundation

Goal: make the current Ledger correct, named, comparable, and testable before increasing its scope.

#### R0.1 Establish correctness and stress fixtures

Files:

- `apps/web/test/runtests.jl`
- `apps/web/prototypes/ledger/main.js`
- new browser regression fixture/harness under `apps/web/test/`

Work:

- designate a small deterministic trace-capable run as the correctness fixture;
- designate a maximum-supported Standard-profile run as the LOD, payload, and memory stress fixture;
- capture expected diagnostics, counts, values, scene bounds, and labels;
- test 1280×800 at device-pixel ratio 1 and 2;
- add a browser smoke test for initial run, each altitude, focus, filtering, and playback;
- record numeric compressed/uncompressed payload, worker peak-memory, browser-heap, and cold/warm input-to-painted-frame budgets before R1 sign-off.

Acceptance:

- returned relationships greater than zero never produce an unexplained empty ready-state;
- the test can distinguish no data, zero matches, and lost camera;
- correctness claims use the small fixture and scale/performance claims use the stress fixture;
- all subsequent phases extend both fixtures.

#### R0.2 Clear the verified defect log

Work:

- instrument and fix camera framing on load and altitude changes;
- recompute status counts and amount totals from the active visible query;
- reproduce and fix rapid quarter/mode/playback inconsistency;
- populate firm search independently of whether the current payload contains firm detail;
- expose central-bank stocks and bank position;
- expose the opening stock state;
- round-trip optional run names through create/list/spec;
- preserve Boolean JSON types.

Acceptance:

- 20 rapid quarter/altitude changes end on the final requested state;
- fiscal-only filtering updates canvas, table, status, and screen-reader summary atomically;
- manual Fit is a recovery action, not a requirement for first render;
- opening state shows stocks and no transaction arrows.

#### R0.3 Make every identity meaningful

Work:

- add dataset-scoped sector metadata;
- replace numeric primary labels with code, short name, and synthetic firm ordinal;
- rename “Goods clearing” to “Products & services market”;
- disambiguate commercial-bank institution from financial-services firms;
- remove hardcoded Austria, 62-sector, and 652-firm UI assumptions;
- correct the household-role count.

Acceptance:

- every sector in the fixture has a code and name;
- every firm search result includes sector identity;
- non-Austrian and different-size datasets do not require frontend code changes.

#### R0.4 Make the ledger honest about evidence and omission

Work:

- add orthogonal evidence, scope, aggregation, timing, and units fields;
- add count and amount coverage;
- compute run-wide scale domains;
- establish minimal distinct styles for cash flows, stocks/stock changes, and non-cash evidence.

Release gate:

> No edge may ship without direction semantics, units, economic layer, evidence, timing, and recognition metadata; accounting edges also declare a valuation basis.

Additional acceptance:

- historical v1 traces remain readable and advertise unavailable detail instead of receiving fabricated fields;
- the foundation milestone closes without requiring receipts, component expansion, or every optional overlay.

### R1 — Connected economic graph

Goal: answer the original missing-actor questions and make the minimum graph needed for the first educational journeys.

#### R1.1 Retain final demand at useful aggregation levels

Files:

- `src/markets/search_and_matching.jl`
- `src/one_step.jl`
- `apps/web/src/BeforeITWeb.jl`
- `apps/web/src/cashflows.jl`
- `test/markets/search_and_matching.jl`
- `apps/web/test/runtests.jl`

Work:

- enable `:final_demand` for traced realizations;
- extend the collector beyond `business_goods`;
- aggregate household, government, and foreign buyer events online by buyer kind, seller kind, seller sector/firm, good, and stage;
- preserve only observed purpose labels; use “household final demand” until consumption versus housing investment is instrumented before matching;
- keep realized amounts, quantities, and counts separate from capacity-counterfactual amounts;
- add capability and observability metadata;
- drive hub expansion from captured realized destinations rather than planned expenditure-share vectors;
- reconcile the aggregates to their corresponding macro equations.

Acceptance:

- government recipient-sector totals reconcile to government purchases under the declared valuation/tax basis and ledger tolerance;
- household-class totals reconcile to recorded household final demand under the declared valuation/tax basis and tolerance;
- foreign-buyer totals reconcile to exports under the declared valuation/tax basis and tolerance;
- capacity-counterfactual values never enter cash totals;
- logger-on and logger-off runs with the same seed/configuration produce identical model results;
- traced-realization overhead is at most the agreed budget, provisionally 15%;
- storage grows with buyer classes × active sellers/sector rollups for Standard traces, not household IDs × firms;
- serial and parallel collectors produce accounting-equivalent aggregates.

#### R1.2 Emit sector institution relationships

Work:

- aggregate only sector-attributable relationships: firm wages/employer charges, firm/product/production/corporate taxes, dividends, new credit, opening-state-based principal/interest settlement, firm deposits/stock changes, and seller-attributed final demand;
- keep household deposits and government benefits on household-cohort ↔ bank/government relationships rather than forcing them through a sector;
- retain whether each relationship is transaction-event exact, model-equation exact, stock change, or derived allocation;
- mark principal and interest as opening-state-dependent settlement flows and never infer them from closing loan deltas;
- do not attribute VAT, household capital-formation tax, exports, or government destinations to seller sectors without the required retail records;
- connect household cohorts, government, commercial bank, central bank, and world wherever nonzero activity exists.

Acceptance:

- no applicable institution remains an unexplained orphan in Sector altitude;
- sector children plus explicit bank/non-sector institutional children reconcile to the macro parent; no bank residual is allocated artificially across sectors;
- financial-services sector firms and the bank institution remain distinct.

#### R1.3 Emit focused-firm institution relationships

Work:

- expose per-firm wages, taxes, dividends, credit granted, outstanding debt, principal, interest, deposits, and relevant final-demand aggregates;
- distinguish quarterly flows from closing stocks;
- preserve exact business counterparties;
- include explanation text for equation/state-derived rather than event-logged values;
- keep unavailable seller-attributed fiscal/final-demand components disabled until their source records exist.

Acceptance:

- a selected active firm shows suppliers/customers plus applicable household, government, bank, and world relationships;
- inspector totals reconcile to the parent sector where the model equations permit;
- state-derived credit and wage edges do not claim event-log provenance.

#### R1.4 Introduce household cohorts

Initial cohorts:

- active worker households;
- inactive households;
- firm-owner households;
- bank-owner household.

Individual household nodes and income deciles are deferred.

Acceptance:

- cohort agent counts sum to the documented household-role count;
- wages, benefits, dividends, consumption, taxes, interest, and deposits route to the correct cohorts;
- no cohort is presented as a real demographic microdata record.

#### R1.5 Complete fiscal/benefit and counterfactual layers

Work:

- expose tax and benefit components already computed before aggregation;
- implement rollup/component rendering without double summation;
- request and display capacity-counterfactual matches as a separate dashed, non-cash layer;
- keep true unmet-demand measures distinct and capability-gated.

Acceptance:

- expanded tax and benefit children reconcile to their closed parents;
- parent and component edges cannot be double-summed;
- capacity-counterfactual values never enter cash or accounting totals;
- a historical run without component/counterfactual capability stays usable and explains the omission.

#### R1.6 Ship the first question shelf

Questions:

- Where did government purchases go?
- Who supplies this sector?
- What does this firm pay households, government, and the bank?
- Where did the model identify a potential supply response from unused capacity?

Each question is a saved Explorer state, not custom one-off logic.

Release gate:

> Any active selected firm can show its production counterparties and applicable institutional relationships with reconciled totals and explicit evidence.

### R2 — One Explorer

Goal: connect levels, runs, and questions without a big-bang rewrite of every prototype.

#### R2.0 Prove one vertical slice

Before adding another visual grammar, port one complete Ledger slice—run load, quarter load, firm ego, edge inspector, filter, coverage, and URL restore—into the shared API/state/render modules.

Acceptance:

- corrected Ledger and Explorer render the same nodes, edges, evidence, coverage, and selection for the fixture;
- shared logic is imported rather than copied;
- prototype compatibility remains intact.

#### R2.1 Build the shared shell

Work:

- add the `/explorer/` route and modular surface;
- add run, quarter, altitude, trace capability, compare, and status controls;
- link every completed main-app run to `Explore network`;
- add `Clone`, `Compare`, and `Open parameters` actions;
- preserve macro access for aggregate-only historical runs.

#### R2.2 Implement URL state and deep links

Acceptance:

- reload restores run, quarter, altitude, focus, layers, filters, threshold, view, and comparison;
- invalid IDs or unavailable capabilities produce explicit states;
- links from Machine-style macro views and Twin-style comparisons open the corresponding Explorer state.

#### R2.3 Implement the emergence ladder

Work:

- breadcrumbs and sticky selection;
- parent/child aggregation links on nodes and edges;
- decompose macro flow → sectors → firms → receipts;
- reconcile receipts → firm → sector → macro account;
- use turnover/GVA language for intermediate transactions and expenditure/GDP language only where final-demand purpose is identified;
- reconcile unsplit household receipts to combined household final demand rather than inventing a C-versus-housing-investment allocation.

Acceptance:

- users can reverse direction without losing the selected economic object;
- child sums reconcile to parent values within documented tolerance;
- no intermediate purchase is double-counted as direct GDP.

#### R2.4 Implement the correct default and full-economy destination

Work:

- choose the first firm deterministically and explain the choice, such as largest employer in the selected quarter;
- open on a one-hop ego network;
- reveal sector peers, then all firms, through explicit expansion;
- show all firm nodes at whole-economy altitude with sector bundles/LOD edges;
- keep all matching raw links available in table/export/focus queries.

#### R2.5 Add receipt, accounting, and history interactions

Work:

- edge receipt with counterparties, purpose, good, quantity, amount, count, evidence, and aggregation path;
- global accounting proof using current diagnostics;
- node stock-flow reconciliation after R1 edge coverage is complete;
- edge history sparkline using stable edge IDs;
- category chips with visible-quarter amounts and solo action;
- global accounting diagnostics drawer;
- paginated accessible relationship table equivalent to the current visual query.

#### R2.6 Add truthful playback

Work:

- prefetch adjacent/all small quarter payloads;
- cache immutable quarter responses;
- tween widths and positions between verified states;
- use amount-proportional particles only as quarterly-flow encoding;
- honor reduced-motion preferences;
- mark shock dates.

Release gate:

> A copied Explorer URL restores the same run, quarter, selection, filters, altitude, and comparison state, and the user can climb from one receipt to its correct macro account.

### R3 — Policy and complexity laboratory

Goal: ship one defensible counterfactual first, then add statistical and firm-level research depth without making every capability a flagship dependency.

#### R3a — Flagship paired sector experiment

##### R3a.1 Expose existing shocks

Initial UI:

- interest-rate shock;
- aggregate productivity shock;
- consumption shock;
- magnitude and only the duration fields already supported by each backend shock;
- fixed first-simulated-quarter onset, stated explicitly.

The current API does not expose arbitrary start times: interest and consumption accept an end time, while productivity applies at `t == 1`. Do not render a generic timing control until a `start_time`/schedule contract, continuation semantics, and deterministic tests exist.

Before exposure, verify each shock’s units, bounds, reversibility, persistence, provenance, and paired-seed behavior. The current shock hook precedes later government-expenditure and rest-of-world price formation, so naive government-spending or import-price mutations can be overwritten; those interventions require persistent wedges or correctly placed hooks.

Add only one new shock in this release: sector-targeted productivity, after the same tests pass.

##### R3a.2 Make experiments first-class

Work:

- create or reuse a baseline with the same dataset, scenario, horizon, ensemble size, and base seed;
- store `experiment_id`, role, and parent linkage;
- reject incompatible runs from paired treatment-comparison mode;
- synchronize quarter, altitude, sector selection, and scales between runs.

##### R3a.3 Implement the sector delta network

Work:

- use stable actor and edge IDs;
- join full edge sets before truncation;
- display added, removed, increased, and decreased relationships;
- report count and value coverage for the returned diff;
- distinguish representative-realization deltas from ensemble outcome deltas;
- show the shock quarter and run-spec difference;
- label unpaired comparisons descriptive rather than causal.

R3a release gate:

> A paired sector-level shock produces a zero no-op delta, reconciles its sector and macro differences, and never requires firm identity, quantiles, or complexity metrics to tell the flagship story.

#### R3b — Statistical and firm-level depth

##### R3b.1 Expose ensemble distributions

Work:

- serve quantiles and optional individual macro paths from `results.jld2`;
- pair the statistical fan with the selected exact trace;
- allow a later run to specify which realization receives deep tracing;
- clone the same initialized economy for comparisons that claim firm-level identity;
- record whether initialization and dynamic randomness use separate streams.

##### R3b.2 Add a minimal, interpretable metrics panel

Initial metrics:

- weighted inflow/outflow strength;
- supplier/customer concentration;
- import dependence;
- leverage and liquidity;
- potential-supply-response, labour-gap, and credit-gap pressure as distinct measures where available.

A true unmet-demand measure is a separate future retention/instrumentation item. Do not relabel the current capacity-counterfactual layer to fill that gap.

Do not compute a Leontief inverse directly from the column-normalized `a_sg`: it is generally singular in that form. Derive and verify a technical-coefficient matrix, approximately `A[g,s] = a_sg[g,s] / beta_s`, then test orientation and spectral radius. Label the result static structural exposure, not realized causal impact. Defer community detection and a composite systemic-importance score until their components and interpretation are reviewed.

Every static network perturbation or reweighting is labeled **Exposure exercise**. Only a rerun through the economic model with a declared intervention is labeled **Simulated counterfactual**.

R3b release gate:

> Every firm-level or statistical comparison states its initialization/RNG policy and realization/ensemble scope; quantiles and metrics pass direct deterministic fixtures before appearing in the product.

### R4 — Deep mechanism logs and evidence-gated narratives

Goal: retain the within-quarter evidence needed for credit, labour, insolvency, distributional, and ordered mechanism stories while keeping chronology separate from causal identification.

#### R4.1 Credit-decision logger

Record:

- desired amount;
- granted amount;
- rationed/refused amount;
- firm and bank;
- applicable constraints and rate.

#### R4.2 Financial-settlement instrumentation

Record principal and interest separately from the earlier credit decision:

- opening debt basis;
- one mechanically booked principal installment from opening loans;
- interest amount and rate basis;
- the resulting deposit/overdraft consequence rather than an invented missed-payment event;
- firm/bank accounting references;
- settlement phase and quarter.

Closing loan deltas remain stocks/stock changes, not substitutes for gross settlement flows.

#### R4.3 Labour logger

Record compact events/aggregates for:

- vacancy;
- eligible-unemployed random match and hire;
- employer-initiated firing/separation;
- employer sector and worker cohort;
- post-match firm-set wage snapshot and employment transition.

Do not describe these records as applications or wage bargaining; the current model implements neither mechanism.

Individual worker identities remain optional/deep-trace only.

#### R4.4 Insolvency restructuring and recapitalization events

Record:

- firm;
- pre-event equity/debt;
- write-down or financing;
- bank-equity effect;
- restart state.

Mechanism-logging acceptance:

- credit grants sum to the model’s granted-credit total and rationing reconciles desired minus granted credit;
- hires and separations reconcile opening and closing employer assignments, firm employment, and aggregate employment;
- insolvency events fire only under the model’s insolvency predicate and reconcile firm/bank balance effects;
- event and phase loggers do not draw randomness or mutate model state;
- enabling or disabling logging leaves economic results unchanged for an identical seed and configuration.

#### R4.5 Phase logger

Map the existing user-facing 15 phases to the actual ordered operations in `src/one_step.jl`.

The hook should retain selected projections and events rather than serializing the entire model at every sub-step.

Acceptance:

- phase IDs are stable and documented;
- displayed ordering matches executed ordering;
- selected variable-specific deltas across logged boundaries reconcile to settled-quarter changes;
- phase order is presented as chronology, not by itself as causal identification;
- a run without phase capability never displays within-quarter phase/mechanism controls.

#### R4.6 Distributions and multiple realizations

Add:

- household income/wealth distributions over explicitly listed simulated role classes;
- firm size, growth, profitability, and leverage distributions;
- trace selection for a small number of realizations;
- sector-edge persistence across independently initialized realizations;
- firm-edge persistence only for runs cloned from the same initialized economy with initialization and dynamic randomness separated.

Every household distribution publishes included role classes, agent/sample weights, realization scope, units, and treatment of the single bank-owner role. Until a defensible population weighting exists, label results “distribution over simulated agents/roles,” not population inequality.

#### R4.7 Story engine

A story is a sequence of deep-link states plus:

- a claim;
- required capabilities;
- evidence references;
- fallback/disabled explanation;
- interaction prompt;
- exit to free exploration.

Stories become available independently as their data gates pass.

Release gate:

> No within-quarter mechanism narrative is enabled unless every narrated transition is backed by a logged phase or event, and the wording distinguishes recorded chronology from causal identification.

### R5 — Checkpoints, sweeps, and research extensions

Goal: support branch-from-quarter and advanced research workflows after the core product is stable.

#### R5.1 Checkpoint format

Do not rely on opaque raw Julia serialization as the public contract.

Include:

- checkpoint schema version;
- model and application version/digest;
- code revision and parameter digest;
- dataset ID and calibration digest;
- simulation time and exact phase boundary;
- concrete model/scenario type and state;
- complete mutable agent, aggregate, model-property, accumulator, and continuation-history state;
- RNG state and threading/reproducibility metadata;
- intervention schedule plus active shock/lifecycle state;
- parent run and quarter;
- trace configuration.

Release gate:

- canonical checkpoint replay runs with `parallel=false` and reproduces discrete events, edge identities, and model state exactly or under the project’s explicitly declared numeric rule;
- parallel replay is not promised until deterministic task/agent/time-specific RNG-stream infrastructure exists;
- incompatible model/checkpoint versions fail clearly;
- checkpoint loading never silently substitutes a dataset or parameter set.

#### R5.2 Branch endpoint and UI

Allow:

1. select a checkpoint taken after quarter settlement and before the next quarter’s insolvency pass;
2. clone state and run provenance;
3. change only whitelisted policy/shock inputs valid at that boundary;
4. continue under a new run ID;
5. compare parent and branch.

Unsupported or initialization-only changes fail closed rather than being silently applied mid-run.

Current run-start shock handlers are not automatically valid at a checkpoint boundary: several assume the original timeline begins at `t=1`. R5 must introduce an explicit continuation-relative intervention lifecycle before exposing them for branching.

#### R5.3 Advanced experiments

Candidates:

- rare-world replay;
- parameter sweeps and phase diagrams;
- keystone-firm exposure and a defined capacity-disable intervention;
- Zipf/Gibrat panels;
- Beveridge curve from labour transitions;
- validated influence and criticality analysis.

Parameter sweeps require a bounded job queue, concurrency policy, cancellation semantics, progress, aggregation, and experiment persistence; worker isolation alone does not make them an orchestration-only feature.

#### R5.4 Separate model RFCs

Keep outside the Explorer implementation plan until explicitly approved:

- multiple commercial banks and interbank markets;
- service-specific production/clearing;
- firm entry/exit, raw array deletion, and bankruptcy-cascade mechanisms;
- persistent fiscal or import-price wedges not already represented by a validated hook;
- materially richer household/firm heterogeneity;
- real-company or geographic microdata.

## 8. Signature experiences and their data gates

| Experience | Earliest release | Required evidence | Honesty rule |
|---|---|---|---|
| One firm at a time | R1/R2 | Firm business and institution edges | Explain deterministic firm selection and synthetic identity |
| Government spending x-ray | R1/R2 | Exact final-demand government aggregates | Related wages/taxes are separate flows, not the same identifiable euros |
| The books close | R0 global; R2 node-level | Diagnostics, stocks, classified inflows/outflows | Use the run’s tolerance and show residuals |
| Receipt to macro account | R2 | Stable aggregation links and macro identities | Intermediate purchases map to turnover/input use/GVA; unsplit household receipts map to combined household final demand |
| Shock propagation cinema | R3a | Paired seeds, stable sector IDs, sector diff network | Start at sector level; firm autopsy is R3b and individual paths are not uniquely identified |
| Firm-quarter story | R4 | Credit, labour, insolvency-restructuring, and phase events | Enable only chapters supported by run capabilities |
| Butterfly/rare-world autopsy | R4/R5 | Individual paths and selectable realization trace | Distinguish stochastic contingency from parameter treatment |
| Notional €1 decomposition | R4/R5 | Explicit allocation rule | Label as derived; do not imply token tracking |
| Phase diagram | R5 | Sweep runner and ensembles | Report uncertainty and compute budget |

Public beta should prioritize the first four. Flagship launch adds Shock Propagation Cinema. The remainder are capability-gated follow-ons.

## 9. Canonical user journeys

### 9.1 First visit

1. Load the newest compatible trace-capable run.
2. Open a named, deterministically selected firm ego network.
3. Explain money direction, quarter, evidence, and coverage.
4. Show what the firm buys, sells, pays, and finances.
5. Expand to sector and reconcile upward.
6. Reveal the full firm economy through sector bundles.

Success: a representative user identifies a top supplier, customer class, and institutional dependency within 90 seconds.

### 9.2 Government-spending question

1. Choose “Where did government purchases go?”
2. Focus government and government-purchase relationships.
3. Show exact total, coverage, recipient sectors, and evidence.
4. Drill to representative recipient firms.
5. Move through quarters; after R3a, compare a paired policy run.
6. Keep related wage, tax, and consumption flows separated by timing and evidence.

Success: recipient-sector totals reconcile to government purchases within ledger tolerance.

### 9.3 Receipt-to-macro journey

1. Select an edge and open its receipt.
2. Classify it as final demand, intermediate input, financial flow, income flow, or stock change.
3. Aggregate to firm and sector.
4. Reconcile to the correct macro account.
5. Reverse the ladder without losing context.

Success: no intermediate transaction is double-counted or described as direct GDP.

### 9.4 Accounting-proof journey

1. Choose “Do the books close?”
2. Open the global accounting diagnostics for the selected quarter.
3. Expand an identity into its classified terms and highlight the corresponding relationships.
4. At a supported node, reconcile opening stock + classified inflows − outflows = closing stock.
5. Show the numeric tolerance and any unexplained residual rather than hiding it.

Success: every advertised identity closes within the run’s declared tolerance, or the view explicitly identifies the failing residual.

### 9.5 Policy experiment

1. Pin the current run as baseline.
2. Select a supported shock, magnitude, and available duration; onset remains fixed to the first simulated quarter until scheduling capability exists.
3. Create/reuse the paired baseline and treatment with identical seeds.
4. Keep progress and specifications visible.
5. Open comparison at the shock quarter.
6. Synchronize delta network, macro outcomes, and evidence.
7. Drill into the first material sector divergence; enable firm autopsy only when R3b identity requirements hold.

Success: incompatible or unpaired runs cannot silently enter paired treatment-comparison mode.

## 10. Required UX states

| State | Behavior |
|---|---|
| Boot/loading | Name the current operation: loading runs, metadata, manifest, or quarter |
| No traced runs | Explain trace capability and offer a trace-capable simulation |
| Aggregate-only historical run | Preserve macro results and explain unavailable network detail |
| Ready/unselected | After explicit selection clearing, preserve the auto-framed scene and offer a suggested question |
| Entity selected | Persistent inspector, breadcrumb, inflow/outflow totals |
| Edge selected | Receipt, evidence, units, history, and aggregation path |
| Partial network | Count and value coverage plus threshold/coverage control |
| Zero filter matches | Preserve layout, explain zero, offer clear filter |
| Lost camera | Automatic recovery plus “Return to network” |
| Compare incompatible | Name the mismatch and offer a matched rerun |
| Experiment running | Baseline/treatment specs and progress; cancel only after backend support exists |
| Accounting warning | Keep the view usable and foreground the failing identity/tolerance |
| Capability missing | Disable only the dependent feature and name the required capability |
| Reduced motion | No particles, autoplay, or large animated reflow |
| API/error | Preserve the last valid scene when safe; show retry and exact failure scope |

## 11. Cross-cutting release requirements

### 11.1 Correctness

- 100% of sectors use dataset-scoped code and name.
- Commercial bank and financial-services firms are unambiguous.
- Every visible edge has direction, units, layer, timing, evidence, recognition, and any applicable valuation basis.
- Counts and value coverage match server totals exactly.
- Returned nonzero relationships never result in an unexplained blank ready view.
- Edge width is comparable across quarter and filter changes.
- Institution edges reconcile at macro, sector, and focused-firm levels where supported.
- Capacity-counterfactual values never enter cash totals or appear as observed unmet demand.
- Representative traces and ensemble statistics are never visually conflated.
- Boolean payload fields remain Boolean.
- Enabling any logger leaves model results unchanged for the same seed and configuration.

### 11.2 Performance

Measure correctness on the small deterministic fixture and scale on the maximum-supported Standard-profile stress fixture at 1280×800 on a documented reference machine. Record cold-cache navigation-to-painted-frame separately from warm-cache interaction-to-painted-frame.

- meaningful first view: at most 2 seconds P75 locally;
- cached quarter/altitude response: at most 150 ms;
- uncached quarter payload: at most 1 second P95 locally;
- pan/zoom input latency: at most 50 ms;
- ego and full-economy LOD animation: at least 55 FPS P95;
- no main-thread interaction task over 100 ms;
- 20 rapid state changes settle on the final request;
- full-economy mode shows all firm nodes through LOD without drawing all raw edges;
- compressed/uncompressed quarter payload, worker peak RSS, and browser-heap limits are numeric release budgets set from the R0 stress baseline rather than left implicit;
- quarter responses are cached and adjacent quarters prefetched;
- Standard final-demand tracing stays within the agreed runtime/storage budget, provisionally 15% overhead and buyer-class×active-seller/sector-rollup storage;
- requestAnimationFrame dirty rendering and a spatial index replace full synchronous redraw/hit testing where profiling confirms the need.

WebGL is a profiling-driven option, not a prerequisite.

### 11.3 Accessibility

Target WCAG 2.2 AA for the four public-beta journeys; apply the same gate to the policy journey before flagship v1.

- keyboard access for runs, questions, filters, selection, altitude, timeline, and comparison;
- filtered actor outline and paginated relationship table equivalent to the canvas;
- screen-reader summaries of quarter, selection, totals, evidence, and coverage;
- evidence and layers encoded with text/shape/line style as well as color;
- 4.5:1 text and 3:1 graphical contrast targets;
- reduced-motion mode;
- predictable focus restoration;
- 44×44 touch-target guidance;
- zero critical or serious automated accessibility violations;
- manual completion of the four public-beta journeys with VoiceOver/Safari and one documented secondary screen-reader/browser combination, verifying parity for filters, counts, selection, receipts, evidence, and coverage.

### 11.4 Reproducibility

- a deep link restores state in every automated fixture;
- paired experiments require matching dataset, horizon, ensemble, and seeds;
- firm-level paired comparisons additionally require the same initialized economy and disclose RNG-stream policy;
- run and checkpoint artifacts include schema/model/dataset version information;
- old runs are never backfilled with fabricated transaction detail;
- unsupported capabilities produce explicit states.

### 11.5 Comprehension

Primary audience: economics-curious upper-level students and policy/economic analysts who can read standard charts but do not know this model’s internals. Model developers and expert economists are a secondary validation audience.

Before public beta, run a scripted moderated study with at least 10 primary-audience participants, including both student and policy/analysis profiles. At least 80% should complete each task without facilitator help under a prewritten success rubric:

- identify a selected firm’s largest supplier and principal institutional relationship;
- identify the sector receiving the most government purchases;
- identify separately an edge’s evidence basis, realization/ensemble scope, and realized/non-cash status;
- return from firm to macro while preserving context;

For flagship v1, add the task “distinguish a baseline from its paired intervention.” Separately, at least three model/economics experts review accounting language, evidence labels, and the limits of causal interpretation.

## 12. Testing strategy

### 12.1 Julia/API tests

Extend `apps/web/test/runtests.jl` to cover:

- dataset-scoped sector metadata;
- v1/v2 compatibility;
- Boolean JSON preservation;
- count and amount coverage;
- deterministic filtering, coverage selection, cursor binding, and complete export;
- stable signed direction for reversible relationships;
- component/rollup non-double-counting and reconciliation;
- opening and central-bank stocks;
- final-demand capabilities and aggregation;
- macro ↔ sector ↔ firm reconciliation;
- capacity-counterfactual exclusion from cash and observed unmet-demand labels;
- logger-on/off determinism;
- trace profiles and old-run capability fallbacks;
- exact paired-run compatibility digests, structured rejection, and no-op delta;
- per-shock supported-control round trips;
- ensemble-summary/path endpoints distinct from agent-distribution endpoints;
- household-distribution class/weight provenance;
- canonical serial checkpoint continuation.

Extend core tests to cover:

- buyer-class final-demand logging;
- credit events;
- booked principal/interest settlement and overdraft consequences;
- labour transitions;
- insolvency events;
- phase-hook ordering;
- serial RNG/checkpoint replay, with parallel replay capability gated separately.

### 12.2 Frontend tests

Add a browser regression suite against the local Julia server:

- initial run and every altitude frame correctly at DPR 1 and 2;
- filters update scene/table/status/accessibility summary atomically;
- camera recovery;
- 20 rapid state changes;
- firm search before visiting Firm altitude;
- deep-link round trip;
- focus preservation across quarter/altitude;
- aggregate-only and missing-capability states;
- paired comparison compatibility;
- reduced motion;
- keyboard-only canonical journeys.

Extract camera-fit, coverage, URL-state, evidence-label, and accounting-classification logic into pure modules with unit tests.

### 12.3 Economic invariants

Automated release checks:

- sector children plus explicit non-sector institutional children reconcile to parent edges within declared tolerance;
- government final-demand aggregates reconcile to purchases;
- household final-demand aggregates reconcile to the model’s combined household-final-demand definition unless purpose instrumentation is present;
- foreign final-demand aggregates reconcile to exports;
- stock changes reconcile to classified flows where the contract claims they do;
- no capacity-counterfactual amount is included in cash;
- instrumentation enabled/disabled with an identical seed produces identical economic results;
- no-op paired experiment produces zero delta within tolerance;
- intermediate receipts never enter expenditure GDP as final demand.

## 13. Rollout and migration

1. Patch and test current Ledger in R0/R1.
2. Add v2 fields and adapters without breaking v1 traced runs.
3. Build `/explorer/` behind an explicit route/feature entry.
4. Migrate Machine-style macro circuit, Ledger sector/firm views, and Twin comparison patterns one at a time.
5. Add `Explore network` to the main run history after URL-state stability.
6. Keep prototype gallery and old Ledger available through public beta.
7. Retire redundant views only after feature parity, accessibility, and saved deep-link migration are verified.

Historical policy:

- aggregate-only runs remain valid for macro exploration;
- v1 traced runs use the compatibility adapter;
- v2-only controls are capability-gated;
- no historical network is synthesized from aggregates.

## 14. Scope explicitly deferred

Defer until the core journeys meet their release gates:

- individual household nodes by default;
- all raw firm edges drawn simultaneously;
- continuous animated metamorphosis between every altitude;
- three visualization grammars at every altitude;
- a large shock library;
- unvalidated community/centrality catalogs;
- black-box systemic-importance scores;
- full guided curriculum;
- branch-from-quarter;
- rare-world network replay;
- keystone-firm surgery;
- phase diagrams and large parameter sweeps;
- US metadata generalization beyond keeping the contract dataset-scoped;
- AI-generated question answering;
- multiple banks, service-specific behavior, or real-firm identities.

## 15. Implementation ownership map

| Area | Primary files |
|---|---|
| Run API, specifications, capabilities, static route | `apps/web/src/BeforeITWeb.jl` |
| Ledger schema, nodes, flows, coverage, snapshots | `apps/web/src/cashflows.jl` |
| Existing Ledger stabilization | `apps/web/prototypes/ledger/main.js`, `style.css`, `index.html` |
| Production Explorer | new `apps/web/explorer/` modules |
| Final-demand hooks | `src/markets/search_and_matching.jl`, `src/one_step.jl` |
| Credit and labour loggers | `src/markets/search_and_matching_credit.jl`, `src/markets/search_and_matching_labour.jl` |
| Insolvency events | `src/agent_actions/bank.jl` |
| Phase logging | `src/one_step.jl` |
| Aggregate distributions | `src/utils/data.jl`, collection paths |
| Shocks | `src/shocks/shocks.jl`, run normalization in `BeforeITWeb.jl` |
| API tests | `apps/web/test/runtests.jl` |
| Core market tests | `test/markets/` and new focused testsets |
| Documentation | `apps/web/README.md`, `apps/web/prototypes/CONTRACT.md`, API docs |

## 16. Definition of public-beta completion

Public beta is complete when:

1. the current Ledger defect log is closed with automated regressions;
2. all sectors and firms have honest, dataset-scoped identities;
3. households, government, bank, central bank, and world connect at every applicable altitude;
4. final-demand aggregates make government and household destinations inspectable;
5. every edge states layer, direction, units, evidence, timing, recognition, and coverage;
6. the Explorer restores its complete state from a URL;
7. the one-firm, government-spending, accounting-proof, and receipt-to-macro journeys pass correctness, accessibility, and user-comprehension gates;
8. the whole economy is available through a stable LOD view rather than a mandatory raw hairball;
9. old runs fail gracefully by capability rather than receiving invented detail;
10. correctness passes on the deterministic fixture, and performance/accessibility budgets pass on the appropriate correctness and stress fixtures.

Flagship launch additionally requires one paired policy experiment and the Shock Propagation Cinema release gate.

## 17. North star

A user starts with one synthetic warehousing firm and can answer:

- what it bought and sold;
- which household cohorts, government payment categories, commercial-bank relationships, and foreign buyer classes it touched;
- what evidence supports every visible relationship;
- how those relationships aggregate into its sector and the macro accounts;
- how the same network changed under a paired policy intervention;
- what is exact, aggregated, derived, representative, or ensemble-based.

Every state is reproducible from a URL, every total reconciles within a declared tolerance, and no animation claims more temporal or causal knowledge than the model recorded.
