# Revised core-three equilibrium comparison candidate

This isolated diagnostic compares one fixed-parameter small New Keynesian
(NK) equilibrium model with the accepted AR(1), VAR(1), and fixed-prior MNIW
BVAR(1) mechanics on one identical revised-data core-three panel. It is a
descriptive, retrospective experiment. It is not an honest real-time
backtest, an authenticated-origin result, an ABM comparison, or evidence that
any model is suitable for production forecasting.

The maximum status is:

```text
REVISED_CORE3_EQUILIBRIUM_COMPARISON_DESCRIPTIVE_NONADMITTING
```

The design disclosure is deliberately irreversible:

```text
model_selection_timing=RETROSPECTIVE_HINDSIGHT_EVALUATION_DESIGN_EXPOSED
```

All origin-admission, scoring-eligibility, empirical-accuracy,
forecast-suitability, confirmation, registration, promotion, and production
gates remain false. “Scoring” below means that mathematical scores were
calculated, not that the source passed the repository's eligibility gate.
The result encodes that distinction in separate fields:
`mathematical_scores_computed=true` and
`repository_scoring_eligible=false`.

## Frozen experiment

- Target order: real-GDP growth, PCE inflation, effective federal funds rate.
- Revised panel: 101 quarters, 2000Q3–2025Q3, with the exact four source and
  derived hashes enforced by the accepted core-three loader.
- Origins: rows 60:89, 2015Q2–2022Q3, exactly 30 balanced origins.
- Each model is fit or filtered from the same copied prefix through its origin.
- Each model-origin is run once to a joint 12-quarter horizon with exactly 500
  coherent predictive paths. Horizons 1, 2, 4, 8, and 12 are extracted from
  that run without restarting it.
- The small NK parameters are fixed before scoring. They are neither estimated
  nor tuned. Its density includes filtered-state and future structural-shock
  uncertainty, but no parameter uncertainty; measurement error is exactly
  zero.
- AR(1) density paths contain target-independent plug-in Gaussian innovations.
  VAR(1) paths contain joint plug-in Gaussian innovations. Neither contains
  coefficient or covariance uncertainty. BVAR paths contain MNIW coefficient,
  covariance, and joint future-innovation uncertainty.
- MASE uses a quarterly seasonal-naive lag-4 denominator calculated separately
  for every origin and target from its training prefix only.
- Point error is `actual - forecast`; a positive mean error denotes
  underprediction.
- Joint-score centers and scales are the origin-target training mean and
  corrected standard deviation. Variogram order is 0.5 with equal
  off-diagonal weights.
- CRPS is the accepted equal-weight empirical-distribution `M^2` definition.
  It is not the fair finite-ensemble `U`-statistic correction.
- Central 50%, 80%, and 95% intervals feed coverage, width, and WIS.
- Paired point-loss differences are small-NK challenger minus comparator;
  negative values favor small NK. HLN-DM is computed only for balanced common
  cells with `horizon < n` and nondegenerate HAC variance. A failure or
  inapplicable short regime is retained visibly rather than dropped.

The regime masks were frozen before the canonical score run:

| Regime | Boundary | Counts at h=1,2,4,8,12 |
|---|---|---|
| `FULL` | all target quarters | 30, 30, 30, 30, 30 |
| `PRE_PANDEMIC` | through 2019Q4 | 18, 17, 15, 11, 7 |
| `PANDEMIC_ACUTE` | 2020Q1–2021Q4 | 8, 8, 8, 8, 8 |
| `POST_ACUTE` | from 2022Q1 | 4, 5, 7, 11, 15 |

## Prefix API and phase-two score-attachment barriers

The claim ceiling is important: `load_canonical_training_prefixes()` first
loads and materializes the entire 101-quarter revised core-three panel in the
same Julia process. Only then does it copy each training prefix and future
period labels. Consequently, future target bytes have already existed in the
forecast process. This is **not** process-level future-byte absence, runtime
isolation, capability security, or an independently executable real-time
forecast environment.

The narrower software property is that each model executor receives an owned
prefix-only object: its model API has no future-target field, panel reference,
future-value view, score callback, or sibling-origin collection. The executor
receives a deep copy, and the stored training matrix does not alias the full
panel. Before dispatch, every `TrainingPrefix`—including a caller-supplied,
noncanonical object with a locally recomputed hash—is compared bit for bit and
axis for axis with one freshly loaded and fully validated exact pinned panel.
The same source rebinding is unconditional in archive validation with either
`replay=true` or `replay=false`. It runs once, content-hashes each forecast,
and, when replay is requested, compares the complete replay-derived attempt
payload, including diagnostics, upstream identity, and all success or failure
evidence. These checks establish a prefix-API barrier only; they do not erase
or isolate the full panel previously materialized by the builder.

The accepted autoregressive component normally revalidates a revised sample by
reopening the whole panel. This diagnostic instead passes it a synthetic
container holding the already rebound copied revised prefix. That container is
only an internal transport into the accepted mechanics. It is never treated as
a source claim or as a route around revised-source validation. The model
execution call does not itself reopen or receive the panel. That narrower fact
does not change the same-process builder limitation above.

After the forecast lock, phase two invokes the score-attachment callback. Any
`Core3RevisedPanel` returned by that callback is fully revalidated: its axes,
values, derived content hash, four source labels, and information track must
pass the pinned core-three validator and then equal a separately reopened exact
panel bit for bit before any truth is copied. Phase two also rebinds every
stored prefix and attaches target truth for mathematical score calculation.
Its counter records exactly one invocation of this **phase-two score-truth
attachment callback** after forecast validation. It does not count or deny the
phase-one builder's earlier full-panel load. A changed forecast, even when
coordinated local hashes are recomputed, fails before the callback. Two
permanent blockers encode this claim ceiling and cannot be removed by
restamping:

```text
FULL_REVISED_PANEL_MATERIALIZED_IN_FORECAST_PROCESS_BEFORE_PREFIX_EXTRACTION
PREFIX_ONLY_MODEL_API_IS_NOT_PROCESS_LEVEL_FUTURE_BYTE_ISOLATION
```

## Bootstrap and numerical ceiling

The canonical runner and focused test entrypoint load only the `SHA` and test
standard libraries before checking the comparison module. They require a
regular file, reject every symbolic-link path component and any hard-link count
other than one, verify stable metadata and byte length around the read, and
match the exact module SHA-256 before `Base.include` can run.

Inside the comparison module, only the `SHA` standard library is loaded before
the same class of preflight is applied to the small-NK source and fixture,
core-three source, scoring source, inference source, and the exact
`scripts/us/Project.toml` and `scripts/us/Manifest.toml`. The preflight also
requires `Base.active_project()` to be that exact project, requires the literal
`LOAD_PATH` stack `["@", "@v#.#", "@stdlib"]`, and requires the first resolved
load-path entry to be the active project. Dependency includes occur only in a
callback reached after all of those checks pass.

The only byte-tested numerical configuration is Julia 1.10.3 on Darwin
`aarch64`, machine `arm64-apple-darwin22.4.0`, CPU name `apple-m1`, 64-bit,
one Julia thread, LinearAlgebra vendor `lbt`, configuration
`LBTConfig([ILP64] libopenblas64_.dylib)`, and eight BLAS threads. Other
runtime, CPU, OS, BLAS, and thread configurations are unattested and cannot be
called canonical by this runner.

This is a strict configuration ceiling, not a full supply-chain attestation.
The Julia executable, standard-library files, system libraries, and BLAS
binary are not byte-pinned. Nor are depot contents, installed package source
trees, artifacts, compiled caches, or the resolved global-environment and
standard-library bytes independently attested. The pinned Project and Manifest
bytes and validated load-path order therefore provide local environment
fixity, not proof of all code bytes that Julia may load.

These hashes provide local fixity, not external provenance authentication:

```text
small-NK source:       2750a95581ba83bdac8578ccdc2cd290a265fa1968d74ddc3d10cfc56e26248a
small-NK fixture:      ec0a4a891e49e518ab5e08b98fdeda6b828f1b611600a3ddf4e198d0c70bc89e
small-NK fingerprint:  d45d4432c7e24bbe78e03c2953bd02cba52a89f942d45d9d6f11ad0fbc540e21
small-NK contract:     5d1bd37ec4977b49b385b11f51b1b7c56726b6f36bc8bf2c0937fc40f24f582a
core3 source:          e8444761c55e199ab475eddca31a06c058b8fb2566ce721b186654190746f1c0
score source:          1cd04371f6cc882094f0a7520b3cbbe7e0d9aee5072f144f0436bea294db51db
inference source:      2115a85b27879c72ad43db5f864d4a10389893b20f42a46a93b818a12fe89975
scripts/us Project:    72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c
scripts/us Manifest:   c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263
comparison module:     35fa2c699adee61bcb16d7eaf5b40a941122f851a5fcceb8e9e9e6f729025659
protocol:              380720dd2d4a5548f7680d2a7b29107ee95344afe86ff2190a29c77f28329bc1
forecast archive:      a1f9dce55a2910a80e7de0b5c1f32371ee3252f8bd7fc95f1f0999e60b8c0212
truth attachment:      9aa8614e1a92408f4fd92f751cc29cbf4a140970f1d72e8b122f8e057147d20d
canonical result:      cd0cb535dfa023dd7d75d50783c259c378c88ad3d1b03fa5abbaf192e9a705cd
```

## Descriptive result

Full-sample RMSE is shown below. The executable runner prints the exact
binary64 values for every full-sample point, density, joint, and paired HLN-DM
cell; the result identity also binds all regime-specific cells.

### Real-GDP growth RMSE

| Model | h1 | h2 | h4 | h8 | h12 |
|---|---:|---:|---:|---:|---:|
| Fixed small NK | 59.226 | 46.875 | 30.590 | 15.131 | 10.157 |
| AR(1) | 12.736 | 10.259 | 9.846 | 8.884 | 8.764 |
| VAR(1) | 12.984 | 10.364 | 9.807 | 8.755 | 8.624 |
| MNIW BVAR(1) | 10.429 | 8.709 | 8.499 | 8.475 | 8.494 |

### PCE-inflation RMSE

| Model | h1 | h2 | h4 | h8 | h12 |
|---|---:|---:|---:|---:|---:|
| Fixed small NK | 1.817 | 2.161 | 2.229 | 2.250 | 2.251 |
| AR(1) | 1.715 | 2.118 | 2.293 | 2.354 | 2.350 |
| VAR(1) | 2.488 | 2.863 | 3.271 | 3.109 | 2.624 |
| MNIW BVAR(1) | 2.143 | 2.378 | 2.475 | 2.441 | 2.383 |

### Effective-federal-funds-rate RMSE

| Model | h1 | h2 | h4 | h8 | h12 |
|---|---:|---:|---:|---:|---:|
| Fixed small NK | 1.894 | 2.485 | 2.805 | 2.717 | 2.517 |
| AR(1) | 0.493 | 0.934 | 1.669 | 2.598 | 2.913 |
| VAR(1) | 0.681 | 1.277 | 2.214 | 3.331 | 4.023 |
| MNIW BVAR(1) | 0.519 | 0.951 | 1.638 | 2.498 | 2.839 |

The fixed small NK model has an extreme short-horizon real-GDP location error:
its h1 mean error is 58.407 percentage points and its 50%, 80%, and 95%
empirical intervals cover zero of the 30 h1 outcomes. That is direct evidence
that this fixed mechanics calibration is not an empirically usable GDP
forecast adapter on this panel. It must not be repaired by post-result tuning
under this protocol.

For inflation, the small NK RMSE is close to AR(1) and lower than the three
autoregressive comparators at several longer horizons. The full-sample paired
HLN-DM differentials against BVAR are negative at all five inflation horizons,
but none has a two-sided p-value below 0.05. For the policy rate, small NK is
substantially worse at short horizons and becomes competitive only at longer
horizons; its h12 RMSE is lowest, but the paired squared-loss differences
against AR, VAR, and BVAR are statistically uninformative in this 30-origin
sample. These are descriptive patterns, not model-superiority findings.

The GDP failure dominates the coherent joint scores. At h1 the small NK energy
score is 18.753, compared with 1.511 for BVAR. Even where a univariate metric
looks favorable, the experiment therefore does not support overall forecast
suitability. No causal interpretation is available, and overlapping-horizon
HLN-DM results in small regime slices are especially low-power.

## Reproduction and tests

The full 500-path result is intentionally separate from the fast test fixture;
the canonical entrypoint never lowers the path count:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/core3_equilibrium_comparison/run_canonical_comparison.jl
```

The focused suite explicitly labels its smaller path counts as noncanonical
mechanics fixtures. It tests comparison-module preinclude mismatch; dependency,
Project, and Manifest substitution with an inert include callback; symbolic and
hard-link rejection; active-project and load-path binding; ULP-altered but
locally restamped caller prefixes under both dispatch and `replay=false` archive
validation; no-alias copying; a ULP-altered callback truth panel retaining the
original hash labels; replay-restamped diagnostics and upstream identities;
phase-two score-attachment ordering; forecast changes after phase lock;
target reorder; permanent-blocker removal; regime boundaries and counts;
visible failures; Bool/nonfinite/type rejection; gate elevation; path-count
prefixes; and execution outside the repository working directory:

```bash
julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/diagnostics/core3_equilibrium_comparison/test_core3_equilibrium_comparison.jl
```

The authored refreeze ran that suite from both the repository root and an
unrelated `/private/tmp` working directory; each branch passed 118/118. The
canonical runner then ran once from each directory. Both complete stdout byte
streams had SHA-256
`5930876ee403098e73414870662edc4101ea782e96b7cf98953b40955ea86185`
and reproduced 240 point/density cells, 80 joint cells, and 360 paired-loss
cells. Runic 1.7.0 and scoped whitespace checks passed. These are authored
verification results, not the required independent re-audit.

The result remains blocked by final-revised mixed-vintage inputs, absent
historical release authentication, same-process full-panel materialization
before prefix extraction, the lack of process-level future-byte isolation,
prior exposure of the evaluation design, the lack of a common ABM origin,
fixed rather than estimated small-NK parameters, zero measurement error,
omitted small-NK parameter uncertainty, and the absence of a confirmatory
preregistered experiment. This repaired frozen candidate is not accepted; it
remains pending a fresh independent audit.
