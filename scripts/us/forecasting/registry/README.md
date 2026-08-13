# U.S. forecast registry kernel

`USForecastRegistry.jl` is the WS-3A append-only registry primitive. Schema v3
retains the two explicit v2 modes without making a historical timestamp
pretend to be the time at which a replay was actually run:

- `prospective`: outcomes must be released strictly after the forecast seal;
- `retrospective_replay`: already-released outcomes are committed outside the
  forecast process, withheld until the forecasts are sealed, and admitted only
  through a commitment-opening reveal receipt.

Both modes keep hash-chained forecast, truth, and score ledgers. The forecast
seal pins the registry header, record count, terminal chain hash, and exact
forecast-ledger bytes. After sealing, every forecast write is refused.
Forecast payloads use an exact schema with no outcome, loss, error, or score
fields. Failed model runs remain visible as zero-draw failure records and
cannot receive a score.

V3 is intentionally schema-breaking for registry headers and forecast
payloads: every forecast now binds its authenticated origin-data sample and
receipt. Truth and score payloads remain v2. Preserve existing v1 and v2
archives as immutable evidence rather than rewriting their timestamps,
payloads, or hashes.

## Timestamp semantics

Economic information time and actual execution time are separate fields:

| Stage | Information/vintage time | Actual execution time |
| --- | --- | --- |
| registry | `knowledge_cutoff_utc` | `execution_created_at_utc` |
| forecast | `origin_timestamp_utc` | `execution_registered_at_utc` |
| seal | — | `execution_sealed_at_utc` |
| truth reveal | `release_timestamp_utc` in the manifest | `execution_revealed_at_utc` |
| truth append | `release_timestamp_utc` | `execution_appended_at_utc` |
| scoring | — | `execution_evaluated_at_utc` |

The registry requires the forecast origin to equal the registry knowledge
cutoff and checks this monotone execution order:

```text
knowledge cutoff <= registry creation <= forecast registration <= seal
                                                        < replay reveal
                                                        <= truth append
                                                        <= score evaluation
```

Truth append also cannot predate its public release. Prospective truth release
must remain strictly later than the actual seal, preserving the v1 prospective
anti-leakage rule. Retrospective truth must have been released no later than
actual registry creation; a not-yet-released outcome belongs in a prospective
registry.

All timestamps are RFC3339 UTC at second precision. The `execution_*` names are
deliberate: callers must record the real run times and must never substitute a
historical origin or release date. The local kernel checks ordering and hash
bindings, but cannot prove that the host clock or caller is honest. Promotion
requires a trusted clock or an external timestamped immutable-object/version
record.

## Retrospective quarantine protocol

The replay protocol is split across processes or access-control domains:

1. Before creating the registry, a quarantine stage serializes the exact TOML
   truth manifest, generates a random 256-bit nonce, and computes
   `truth_quarantine_commitment(manifest_path, nonce)`.
2. Registry creation receives only that salted commitment. The forecasting
   process receives neither the manifest nor the nonce.
3. The forecasting process registers forecasts using vintage-correct inputs
   and seals the forecast ledger.
4. A second-stage truth process calls `reveal_retrospective_truth!` with the
   original manifest bytes, nonce, and actual reveal time.
5. Reveal verifies the commitment, experiment, protocol, knowledge cutoff,
   historical release eligibility, target coverage, forecast seal, chain hash,
   and exact forecast-file hash. It then copies the exact manifest bytes into
   the registry and writes a self-hashed reveal receipt binding all of those
   artifacts.
6. `append_truth!` accepts only exact committed records, apart from their
   actual append timestamp. Scoring is blocked until every committed truth
   record has been appended.

The manifest has this topology:

```toml
[artifact]
schema_version = "beforeit-us-retrospective-truth-quarantine.v1"
experiment_id = "..."
protocol_sha256 = "..."
knowledge_cutoff_utc = "2010-01-29T13:30:00Z"
truth_record_count = 1

[[truth_records]]
truth_id = "truth.real-gdp-growth.2010q2.first"
truth_key = "real-gdp-growth.2010q2"
release_timestamp_utc = "2010-07-30T12:30:00Z"
target_id = "real-gdp-growth"
target_operator_version = "nipa-real-gdp-growth.v1"
transformation_version = "annualized-log-growth.v1"
target_period_start = "2010-04-01"
target_period_end = "2010-06-30"
truth_vintage = "first_release"
value = 2.1
source_artifact_sha256 = "..."
```

The commitment is domain-separated SHA-256 over the manifest byte hash and
nonce. A nonce is required because economic truth values often have a tiny
guessable domain. The internal
`truth_quarantine_manifest.toml` and `truth_reveal_receipt.toml` must both be
absent before reveal and both present afterward; partial reveal state is
invalid. Every manifest target must match a sealed forecast target, and every
sealed forecast target must be covered.

The registry cannot enforce process isolation by itself. Keeping the manifest
and nonce outside the forecast process before sealing requires separate
credentials, a sealed job stage, or equivalent operating controls. A
commitment made by a process that can also read its opening does not establish
an honest replay.

## Other enforced invariants

- one experiment and protocol hash per registry;
- exact origin-manifest, model-manifest, model-card, and seed-namespace hashes;
- required nonzero `origin_data_sample_sha256` and
  `origin_data_receipt_sha256` on every successful or failed forecast record;
- unique semantic forecast, truth-vintage, and score keys;
- target, operator, transformation, period, and truth-key agreement at scoring;
- forecast sealing before any truth or score;
- complete record-hash chains and sealed forecast byte integrity;
- reveal-manifest and reveal-receipt tamper detection.

`derive_seed_record` deterministically namespaces each RNG path by master seed,
experiment, origin-manifest hash, model, path number, and purpose. It returns
both the non-negative Julia seed and namespace SHA-256 without touching the
process-global RNG.

Run the hermetic fixture with:

```shell
julia --project=scripts/us --startup-file=no \
  scripts/us/forecasting/registry/test_registry.jl
```

This is a single-writer local kernel, not a transactional database. The hash
chain detects record alteration and the forecast seal detects forecast
truncation or extension. Detecting suffix truncation of the still-open
truth/score ledgers requires an externally retained checkpoint or immutable
object store. Registry correctness does not establish source-vintage
correctness, stage isolation, or forecast skill.
