# Structural as-of selector v1

Status: **candidate pending independent audit** for the narrow role
`PURE_DATA_STRUCTURAL_ASOF_SELECTOR_NONADMITTING`.

This directory closes one mechanical source of structural look-ahead without
changing calibration, the pinned v1 source-release registry, an origin
package, or any admission decision. The selector accepts caller-supplied
release evidence as pure dictionaries and requires exactly these six
components:

1. I/O or supply-use;
2. fixed assets;
3. firm counts;
4. QCEW or labor;
5. sector or financial accounts; and
6. classification maps.

## As-of rule

Every release has an observation-period start/end, exact second-precision UTC
release and evidenced-availability timestamps, raw SHA-256, source identifiers,
mapping version, classification system/version, and one of the registry's
closed `APPROVED`, `DUBIOUS`, or `REJECTED` quality statuses. The selector
rejects a release before its observation period ends and requires official
release no later than evidenced availability.

For `ORIGIN_ELIGIBLE_AS_OF`, a candidate is eligible only when all three facts
are no later than the forecast origin:

```text
observation_period_end conservative 23:59:59Z boundary <= origin_timestamp_utc
release_timestamp_utc <= origin_timestamp_utc
availability_timestamp_utc <= origin_timestamp_utc
```

For each component, the unique maximum
`(availability_timestamp_utc, release_timestamp_utc)` wins. Exact ties are
ambiguous and fail at the origin where they are latest. The winner must then
be `APPROVED`; a `DUBIOUS` or `REJECTED` winner fails closed without falling
back to an older approved release. Re-running the query at the exact
availability timestamp of a successor selects the successor, so a release is
carried only until the next eligible release, with an exclusive boundary.
Releases that are not yet eligible are excluded from the origin track's
considered-evidence hash; appending a later release, including one with a
closed non-approved quality status, therefore cannot rewrite an earlier
receipt. The hindsight track's considered-evidence hash covers every supplied
release because that track deliberately applies no origin cutoff.

Date-only observation ends are conservatively interpreted as `23:59:59Z`, so
an origin earlier on the same UTC date cannot use the completed-period row.
Component receipts retain the exact source, dataset, release, raw hash,
mapping, and classification identities. Structural age is the signed exact
second difference from that conservative observation-period boundary; the
signed UTC calendar-day difference is retained alongside it. Signed release
and availability ages are also emitted in exact seconds.

## Hindsight boundary

`RETROSPECTIVE_HINDSIGHT_SELECTED` deliberately chooses the latest supplied
release without the as-of filters. It is permanently marked:

```text
structural_information_set_eligible = false
pseudo_oos_structural_compatibility = FORBIDDEN
origin_admissible = false
promotion_eligible = false
accuracy_evidence = false
```

Post-origin release/availability and future observation periods are retained
as explicit blockers. A future-period structure can never be converted into
a pseudo-out-of-sample label by changing a receipt flag: validation rebuilds
the receipt from the supplied release evidence, so even a coordinated local
self-rehash fails.

## Registry composition and receipt limits

The module pins, source-loads, and reuses the v1
`USSourceReleaseRegistry.canonical_sha256` implementation. Its timestamp
precision, availability ordering, latest-release ordering, ambiguity, and
append-stability conventions are preserved. The pinned v1 module and schema
are read-only dependencies; neither is modified.

The returned in-memory receipt is self-hashed with the registry's canonical
encoding. `validate_receipt(receipt, releases)` is the evidence-bound check:
it validates the self-hash and independently rebuilds every selected field,
age, blocker, and gate from the supplied releases. A self-hash by itself is
not provenance or authentication.

This selector does not inspect release files, authenticate publishers, verify
locators, establish that the supplied timestamps are true, build a structural
model object, validate accounting concepts, load dynamic histories, access
truth, run a model, score, admit an origin, promote, or authorize production.
All receipts remain nonadmitting, including a mechanically complete
`ORIGIN_ELIGIBLE_AS_OF` receipt; that status is only compatible with later
pseudo-OOS work after every other origin and evidence gate passes.

## Verification

From the repository root:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/origins/structural_asof/test_structural_asof_selector.jl
```

From an unrelated directory:

```sh
cd /tmp
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/origins/structural_asof/test_structural_asof_selector.jl
```

The adversarial suite covers exact origin and availability boundaries,
post-origin catalog append invariance, input ordering, per-component ages and
version preservation, hindsight/future-period quarantine, missing/unknown
components, duplicate IDs, origin-local tied latest releases,
latest-then-quality selection without fallback, observation/release order,
strict timestamps/dates/hashes/quality, unknown or missing fields, self-hash
mutation, coordinated rehashing, evidence mutation, gate elevation, and the
pure-data/no-network/no-output boundary.
