# EFFR 2026Q3 offline campaign control

This directory is a hermetic, non-network control layer for the preregistered
2026Q3 EFFR campaign. It does not collect data. It freezes the exact
publication/effective-date calendar, authorizes only the dates and UTC windows
already present in the prospective-v2 contract, and checks offline coverage
across upstream-validated bundle manifests.

The control exists separately from the byte-pinned August 7 day-zero runner.
It does not modify or generalize that runner before its scheduled revision
check.

## Frozen calendar

`effr_2026q3_campaign_schedule.toml` contains 59 explicit publication days:

- first-state windows run from 2026-08-07 through 2026-10-30 at
  13:00:00–13:15:00Z;
- revision-check windows run through 2026-10-29 at
  18:30:00–18:45:00Z;
- Saturdays, Sundays, 2026-09-07, and 2026-10-12 are excluded; and
- each effective date is the immediately preceding authorized publication
  day, seeded by 2026-08-06 for the first row.

This yields 59 first-state slots, 58 revision-check slots, and 117 total
slots. Important discontinuities are explicit:

```text
publication 2026-09-08 -> effective 2026-09-04
publication 2026-10-13 -> effective 2026-10-09
publication 2026-10-30 -> effective 2026-10-29, no revision slot
```

The validator independently reconstructs the weekday/exclusion calendar and
the effective-date chain, then compares the controlling dates, times,
exclusions, source, requirement, evidence roles, and window lengths to
`prospective_2026q3_contract_v2.toml`. Any disagreement fails closed. The
schedule also pins both the contract's semantic digest and exact file digest.

## Authorization boundary

`capture_authorization` returns a typed `CaptureAuthorization` only for a
frozen date/phase pair. An optional observed UTC time must fall inside the
closed 15-minute window. The type carries fixed-false network execution, raw
write, inventory mutation, and origin-admission fields. It is a schedule
decision, not permission to perform a live request.

There is deliberately no live runner, scheduler, sleeper, downloader, raw
data writer, inventory writer, or profile-completion writer in this
directory.

## Offline manifest coverage

`validated_bundle_manifest` adapts the named tuple returned by an upstream
bundle validator. `evaluate_campaign` then checks:

- exact prospective-contract identities;
- publication date, effective date, phase, state class, and UTC window;
- exact one-date rate and volume queries;
- fixed-false empirical and inventory gates;
- unique slot, bundle-path, manifest, transaction, and manifest-hash
  identities; and
- every revision bundle's exact same-day first-state predecessor path and
  predecessor receipt hashes.

A frozen status/result matrix prevents independently plausible fields from
forming an impossible bundle:

- a first-state candidate is valid only in phase `first`, with raw
  `currentState=false` sourced as `RAW_FIELD_FALSE`, validated rate and volume
  receipts, no observed revision, and no predecessor;
- a revision candidate is valid only in phase `revision-check`, with the same
  raw-state provenance, validated revision receipts, an observed revision, and
  two real predecessor receipt hashes;
- a byte-identical no-revision result is valid only in phase
  `revision-check`, with no current receipts or receipt hashes and every
  revision flag false; and
- the incompatible status may occur in either phase but requires two absent,
  non-derived raw-state records and no current receipts or hashes.

The adapter does not itself read or authenticate raw bytes. Its
`ValidatedBundleManifest` designation is therefore an upstream caller
assertion; only results returned by a separately pinned byte-level validator
are intended as input. This layer detects cross-bundle schedule and lineage
failures, not forged in-memory validation results.

Coverage and receipt semantics are reported separately. Even a synthetic
117-slot receipt-complete fixture returns only
`LOCAL_RECEIPT_COVERAGE_CANDIDATE_NONADMITTING`. Profile completion,
inventory mutation, origin admission, scoring, promotion, and readiness are
hard false.

## Missing `currentState`

The checked-in one-date receipt contract requires raw
`currentState=false`, while the observed FRBNY response omits the field. This
control never infers or inserts `false`.

- The incompatibility status must retain both absent raw identity records,
  `ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED`, no receipts, and blocker
  `ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT`.
- A byte-identical same-day no-revision record may also contain the two absent
  raw identities; campaign control carries that absence forward as a receipt-
  semantics blocker even though no revision receipt is claimed.
- A first-state or revision receipt-candidate status with absent raw identities
  is rejected as an attempted derivation.

Thus complete raw-capture coverage can be reported while receipt semantics and
every admission gate remain blocked.

## Verification

Run from any working directory:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/vintages/effr/campaign/test_effr_campaign_control.jl
```

The tests are hermetic. They cover contract/calendar parity, weekends,
holidays, post-holiday effective dates, terminal revision exclusion, clock
boundaries, calendar and contract tampering, absent-field preservation,
fabricated or relabeled state, status/phase mismatch, false-state provenance,
receipt and revision-flag contradictions, typed phase rejection, wrong
effective dates and queries, opened gates, duplicate slots and identities,
orphaned or mismatched predecessors, full 117-slot coverage, and the permanent
nonadmission boundary.

## Remaining operational gates

This slice does not establish externally durable copies, an external
timestamp, retention through 2031, transport or host-clock attestation,
authenticated approval, a production recurring collector, a byte-level
cross-registry verifier, a complete-origin manifest, or any source-inventory
transition. It also does not claim that the two excluded dates are permanently
correct if the controlling contract is amended: any amendment requires a
separately reviewed, rehashed successor schedule rather than a runtime guess.
