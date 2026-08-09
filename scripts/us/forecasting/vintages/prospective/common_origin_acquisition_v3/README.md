# Common-origin acquisition v3 composition verifier

This isolated directory is a read-only composition layer for the planned
2026Q3 prospective U.S. forecasting origin. It does not capture data, execute a
leaf verifier, admit an origin, run or construct a model, load truth, score a
forecast, mutate inventory, use the network, or write evidence. There is no v3
evidence parent under `data/`.

The exact v3 policy and verifier are permanently `CANNOT_RUN`. Their current
status, maximum status, and claim ceiling remain `CANNOT_RUN` under every
input, including a structurally complete input carrying a
`PROSPECTIVE_NONSYNTHETIC` label. `READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED` is
only a design target for a separately versioned successor with pinned trust
anchors and authenticated signature and timestamp validators. It is not a
reachable v3 status.

All 21 dispatch entries are exact and `qualified=false`; they cover the exact
107 prospective-v2 profiles. V3 has no qualified-dispatch or qualified-leaf
execution branch. An accepted leaf identity is never invented from an
unavailable verifier.

## Files

- `USCommonOriginAcquisitionV3.jl` is the standard-library-only verifier. Its
  public API is `load_policy`, `load_parent`, `verify_parent`,
  `validate_result`, and `canonical_sha256`.
- `common_origin_acquisition_v3_policy.toml` freezes the legacy baseline,
  schema and source identities, closed dispatch table, permanent claim ceiling,
  EFFR overlay blockers, retention geometry, and resource ceilings.
- `common_origin_parent_v3.schema.toml` closes the exact ordered 107-row parent
  composition.
- `prospective_profile_verification_receipt_v1.schema.toml` closes each leaf
  receipt and its supporting metadata.
- `retention_custody_v2.schema.toml` closes the acyclic ordered-child custody
  covenant.
- `test_common_origin_acquisition_v3.jl` creates temporary fixtures only. It
  creates no empirical parent and changes no source inventory.

## Baseline and dispatch identity

The verifier reopens and rehashes the exact accepted prospective-v2 module,
contract, tests, and README. It reconstructs a sorted 107-row projection of
requirement ID, profile ID, selector, capture ID, and completion date.

The design audit published SHA-256
`9fa271ea0bc646c8f3789084d8c61e04e2b31c4c5e4eeb6b551a217499ac75fb`
without preserving its serialization. V3 retains that value only as an opaque
audit fingerprint. It does not pretend to rederive it. V3 separately derives
the documented typed-length canonical projection SHA-256
`bff32b3b46270818e0e7d487173c1676df7d286c1d6846c16a2977d1bff20299`.
Exact row comparison and the 21 exact four-part dispatch keys enforce the
21/107 bijection.

Each dispatch key is `(receipt_schema_version, requirement_id, source_id,
evidence_role)`. There are no wildcards, prefixes, function paths, dynamic
callbacks, or executable verifier names in evidence. Every entry fixes its
claim schema, independent-validation schema, exact allowed profiles, media
types, artifact roles, and exhaustive blockers.

## What verification proves

For every parent row, v3 rederives and verifies:

1. exact legacy requirement/profile, active profile, dispatch, physical leaf
   receipt, and explicit EFFR supersession sentinel in canonical order;
2. exact legacy/active selectors, source/capture binding, closed catalog set,
   rank-one selection, and selected candidate locator equal to the release and
   release-notice locator;
3. capture start/completion/availability, with reference-period end no later
   than the calendar date of receipt completion;
4. catalog completion no earlier than capture completion, resolution no earlier
   than catalog completion, and all evidence strictly before origin;
5. raw paths, bytes, hashes, sizes, permitted media/roles, release-notice
   bytes, and every referenced metadata receipt;
6. exactly two replicas per raw artifact, with global replica/object/path/
   attestation uniqueness, distinct raw/replica inodes, and distinct domains,
   backends, objects, and domain-attestation bytes within each pair;
7. an external timestamp whose subject and token bytes are exact and whose
   declared time follows capture, catalog, resolution, and every replica-domain
   attestation;
8. distinct owner and validator identities, paths, hashes, roles, decisions,
   and approvals no earlier than the complete child-evidence time;
9. custody approvals after every leaf, followed by parent approvals after both
   the complete child set and custody; and
10. all downstream scientific and production gates hard-false.

Every numeric rank, count, horizon, lag, and ordinal control must be a TOML
integer; Julia equality aliases such as `true == 1` and `1.0 == 1` are
rejected.

`validate_result` is not a standalone self-hash checker. It requires an
explicit `evidence_root`, safely reopens the result's exact parent, reruns the
complete verification, and compares the complete replayed result. A fabricated
107-row result, missing parent, stale result, removed action-count scope, or
coordinated result restamp cannot pass by recomputing its own hash.

The result's zero action counts are scoped only to the
`COMMON_ORIGIN_ACQUISITION_V3_VERIFIER_INVOCATION_ONLY`. They are not claims
about the caller process or surrounding system.

## Trust boundary and permanent ceiling

V3 checks exact bytes, declared subjects, chronology, distinct metadata
identities, and local fixity. Its `EXTERNAL_SIGNATURE_REFERENCE_V1` strings and
hashed timestamp tokens are not cryptographically authenticated, and the
`PROSPECTIVE_NONSYNTHETIC` evidence class is not a non-self-asserted trust root.
Consequently, a coordinated self-restamp of the entire metadata closure may be
structurally consistent, but it remains `CANNOT_RUN` with the
`current_v3_authenticated_trust_roots_absent` blocker.

A successor must pin trusted keys/anchors and accepted validators. Relevant
primary standards describe the missing boundary: [NIST FIPS 186-5](https://csrc.nist.gov/pubs/fips/186-5/final)
defines digital signatures for signatory authentication and modification
detection; [NIST SP 800-57 Part 1 Revision 5](https://csrc.nist.gov/pubs/sp/800/57/pt1/r5/final)
addresses key-management and trust-anchor procedures; and
[RFC 3161](https://www.rfc-editor.org/info/rfc3161/) defines signed TSA
request/response semantics. V3 does not claim conformance to those standards
and does not substitute home-grown cryptography.

## Filesystem and resource boundary

Paths must be relative to an explicit absolute evidence root. Empty, dot,
parent, absolute, backslash, symbolic-link, non-regular, and hard-linked paths
are rejected. The verifier checks every evidence-root ancestor for stable
identity and no symlink, keeps a full state snapshot for the evidence root and
internal path components, and checks every regular evidence file before and
after reading. Unrelated sibling changes in a shared ancestor do not cause a
false race failure; root or ancestor replacement does.

These pathname checks are not a kernel-atomic defense against a malicious
same-user process. The result therefore records
`same_user_path_race_resistance_attested=false`.

The policy freezes pre-read and pre-materialization limits: 16 MiB metadata
files and timestamp tokens, 512 MiB per raw/replica file, 1 GiB raw and 2 GiB
replica bytes per profile, 64 GiB raw and 128 GiB replica bytes per parent, 32
raw artifacts, 64 replicas, 256 catalog candidates, 4,096 vector/table items,
1 MiB strings, 512-byte identifiers, and bounded relative paths/components.
Declared and stat sizes are rejected before file allocation where possible;
aggregate addition is overflow-safe.

## EFFR supersession ceiling

The independently accepted endpoint-profile v1 module, tests, TOML, and README
are exact source bindings, but that profile remains read-only `CANNOT_RUN`
metadata. The three legacy EFFR rows require separately frozen supersession
decisions and currently carry only `UNAVAILABLE_NOT_FROZEN`.

The overlay requires a justified daily-history start, at least 60 common
information quarters beginning with the 2000Q3 core geometry, and explicit
treatment of the New York Fed methodology boundary at 2016-03-01. The 84-date
July--October candidate is not sufficient model-input training history. Restart
geometry is exactly 58 morning observations, 57 later observations, 115 total
slots, and 57 complete pairs. The missing August 7 later observation cannot be
borrowed. First-public, raw `currentState`, final-daily-state, and no-later-
revision claims remain false.

## Retention

The maximum h12 forecast from a 2026Q3 origin targets 2029Q3, ending
2029-09-30T23:59:59Z. Adding 60 months gives the mathematical minimum
2034-09-30T23:59:59Z. Deletion additionally requires later completion,
external timestamping, durable replication, and independent audit of the last
required mature-truth receipt. V3 verifies this covenant without opening future
truth.

The custody subject is acyclic: it binds the exact evidence class, origin,
baseline, and ordered parent-row closure. Each row's physical leaf hash
transitively binds raw, replica, catalog, resolution, release, timestamp,
approval, and retention identities. Reusing custody after changing any child
physical identity is rejected.

## Verification

The formatted audit candidate freezes these identities:

- module physical SHA-256
  `9654eb61b92b2655391b00952ed4cbee0e9fa58224339f1fb0440c51570e719e`;
- policy physical/semantic SHA-256
  `0deff5e3e6c950b5682bba96fcefa1fa2304bbbadae6227a940376dc7699bd3e` /
  `a69392029c2221ab5f490311c02d09a667e71982c486a1612100c1d6dcd96d13`;
- parent-schema physical/semantic SHA-256
  `cf4060554a6c53de079d728c2a2ac179309e9a7b888edc3bfa0a931ced5442a2` /
  `a140f2c730102ab882f606c2780d1214f0db691f4f921b5e9c1a140cfaf520ce`;
- leaf-schema physical/semantic SHA-256
  `6bcd6f26efba67bb92053dabdc20c08f6b36d9c3569a92a5e980c5117265a4cd` /
  `702ffcf060fd9bfb3530e3f9dee5936304351ab58ee386b53455662c3f069fe8`;
- custody-schema physical/semantic SHA-256
  `94eb2a1bdbd1346b4918d63bdf1befcf506a8b6d39c6eeaa1b50e87eb2c79598` /
  `2c6d6840a3396d5ced8e4e20b3bf0c5cc1fce68fdb927b796258fbf7a72382c3`;
  and
- test-suite physical SHA-256
  `e3ee90a943e26fd6ce5db37644035c4dff3edfdb1f364921ea1353e782cded53`.

The policy self-hash excludes only its own `artifact.content_sha256`; each
schema uses the same documented exclusion. The test suite independently pins
the module and policy physical bytes, while the policy pins all three schema
identities and every upstream source binding.

From the repository root:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/test_common_origin_acquisition_v3.jl
```

The 223-test suite also runs under `--check-bounds=yes --depwarn=error` and from an
unrelated working directory. It covers bijection/order/narrowing, EFFR
geometry, unknown types, inert candidate `.jl` bytes, reference/catalog/
resolution/replica/timestamp/approval chronology, strict integer types,
restamps, stale result replay, custody reuse, coordinated closure restamps,
resource exhaustion declarations, path traversal, symlinks, hard links,
root/ancestor races, global replica identity, retention, and verifier-scoped
hard-zero action counts.

The generated `PROSPECTIVE_NONSYNTHETIC`-shape fixture demonstrates only
structural traversal. Its label is self-authored test metadata, not empirical
provenance, and it never establishes origin readiness.
