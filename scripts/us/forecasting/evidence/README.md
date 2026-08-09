# U.S. local artifact-bundle integrity verifier

This directory implements the fail-closed artifact boundary that the Tier-1
target coverage inventory intentionally leaves unresolved. It does not change
that inventory, promote an origin, or declare the forecasting system ready.
It can check the local bytes, structure, and internal bindings of a future
evidence bundle. It does not establish that those bytes are valid forecasting
evidence. The checked-in bundle records that the required evidence is
currently unavailable.

Files:

- `USEvidenceVerifier.jl` validates and resolves an evidence bundle.
- `artifact_evidence.schema.toml` is the declarative schema and trust policy.
- `unavailable_evidence.toml` is the honest checked-in absence record.
- `test_evidence_verifier.jl` builds synthetic artifacts in temporary
  directories and exercises positive and adversarial cases.

The implementation uses only Julia standard libraries: `Dates`, `SHA`, and
`TOML`.

## Verification boundary

A complete candidate must contain exactly:

- 24 truth-manifest references: all eight protocol Tier-1 targets crossed
  with `first_release`, `near_mature`, and `mature`;
- eight operator-manifest references, each using the exact operator ID frozen
  in `../protocol.toml`; and
- at least 40 origin IDs in the set intersection across all 24 truth
  manifests.

An origin can enter that intersection only when its observation row binds the
common-information contract:

```text
product_id       = quarterly_unconditional
origin_rule_id   = quarterly-after-advance.v1-draft
information_track = common_information
protocol_eligible = true
origin_evidence_sha256 = <64 lowercase hexadecimal characters>
```

Every observation is uniquely keyed by `(origin_id, reference_key)`.
Repeated rows with the same key are rejected. If an origin appears more than
once or in more than one truth manifest, its UTC timestamp, eligibility flag,
and upstream origin-evidence hash must agree everywhere. This prevents the
intersection from treating different information sets as the same origin.
Across the complete bundle, distinct eligible origin IDs must also have
distinct UTC timestamps and distinct origin-evidence hashes. Forty labels
that alias one timestamp or one hash therefore cannot satisfy the minimum.

The verifier does not infer protocol eligibility from a directory name or a
retrieval date. `protocol_eligible = true` is accepted only inside a
hash-verified truth manifest with the exact frozen protocol/product/rule/track
fields and a bound upstream origin-evidence SHA-256. The upstream origin
artifact remains outside this isolated verifier's path scope; its digest is a
required cross-manifest identity binding, not a claim that those bytes were
resolved here.

## Truth artifact format

Each available truth manifest must declare:

```text
truth_artifact_format = beforeit-us-truth-values-tsv.v1
```

The referenced artifact must be nonempty valid UTF-8 with LF line endings,
one final LF, and this exact tab-separated header:

```text
target_id	truth_layer_id	origin_id	reference_key	value
```

Every following line must contain exactly five tab-separated fields. Target
and truth-layer IDs must match the manifest reference, `reference_key` must
use `YYYY-Q[1-4]`, and `value` must be a finite canonical decimal number.
Rows must be sorted and unique by `(origin_id, reference_key)`. Their key set
and row count must exactly match the manifest's observation array and declared
`observation_count`. The artifact's raw-byte SHA-256 binds the values as well
as the row identities.

## Byte and path policy

Available references must use normalized relative paths. Absolute paths,
`..`, dot components, empty components, backslash separators, files outside
the bundle directory, and symbolic-link traversal are rejected. The root
manifest itself must not be a symbolic link. For every truth manifest,
operator manifest, truth artifact, operator artifact, validation artifact,
validation receipt, and signoff receipt, the verifier:

1. resolves a regular file beneath the evidence bundle directory;
2. reads the file once;
3. compares those raw bytes with the declared lowercase SHA-256; and
4. parses those same bytes when the file is a TOML manifest or receipt.

Whitespace changes therefore invalidate a referenced manifest or receipt
unless its parent manifest is deliberately updated to the new raw-byte hash.
The root evidence manifest has a separate deterministic semantic identity:
sorted typed canonicalization excluding only
`artifact.content_sha256`.

## Operator receipts

Each available operator manifest resolves four byte artifacts:

1. the operator implementation artifact;
2. its validation artifact;
3. an independent-validation approval receipt; and
4. a research-lead signoff receipt.

The validation receipt binds the target ID, operator ID, protocol identity,
evidence class, operator bytes, and validation bytes. The signoff receipt
binds all of those fields plus the raw SHA-256 of the validation receipt.
Validator and signatory IDs must differ, signoff cannot predate validation,
and receipt paths, hashes, and IDs must be unique across operators. Within
each operator bundle, implementation, validation, validation-receipt, and
signoff-receipt paths and byte hashes must also be pairwise distinct. A
receipt that is merely present but does not carry all of these bindings is
rejected.

The operator implementation artifact and validation artifact must each be
nonempty. Their paths and byte hashes must remain distinct from each other and
from both receipts.

## Failure semantics

Malformed, ambiguous, escaped, stale, tampered, mismatched, or self-approved
evidence raises `EvidenceError`. Honest absence is represented by
`status = "unavailable"` together with `manifest_path = "unavailable"` and
`manifest_sha256 = "unavailable"`. It validates as an audit record but
`verify_evidence` returns:

```text
status = NOT_VERIFIED
common_origin_count = 0
available truth manifests = 0/24
available operator manifests = 0/8
blockers = 33
```

A structurally complete bundle can only reach local integrity status. The
result fields deliberately separate that state from evidentiary verification:

```text
verification_scope = local_bundle_integrity_only
integrity_verified = true
verified = false
promotion_eligible = false
```

`require_integrity_verified` accepts a bundle only after all local byte,
structure, binding, intersection, and injectivity checks pass.
`require_verified_evidence` remains fail-closed for every bundle accepted by
this implementation. Status labels such as `VERIFIED_TEST_FIXTURE`,
`BUNDLE_INTEGRITY_VERIFIED_AUDIT`, and `BUNDLE_INTEGRITY_VERIFIED` describe
only local bundle integrity; they do not override `verified = false`.

Even an integrity-complete retrospective bundle retains blockers because this
verifier does not:

- resolve upstream origin-evidence bytes against source-release and origin
  registries;
- verify origin-by-horizon reference quarters or the release semantics of
  `first_release`, `near_mature`, and `mature`; or
- externally authenticate validator and signatory identities in receipts.

A non-retrospective evidence class has an additional blocker. Synthetic
fixtures and repository audits therefore cannot be promotion evidence.
Forecast-model promotion remains a separate, higher-level decision. The
checked-in manifest cannot reach local integrity verification or promotion
and has semantic SHA-256:

```text
01fa10389150bc8c905ef502f583510649745b3bb38bea9b263975fb6662dc3f
```

## Run

From the repository root:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/evidence/test_evidence_verifier.jl
```

The suite is hermetic: its complete 40-origin bundle is explicitly labeled
`synthetic_test_only`, exists only in a temporary directory, and is deleted
after the test. Its success proves only local integrity. The suite includes
negative cases for root schemas and root symlinks, IDs, strict truth TSV
content, manifest/artifact key agreement, unique keys, origin intersection,
eligible-origin timestamp/hash aliases, path escape, nested symlinks, invalid
UTF-8/TOML, byte tampering, empty operator/validation artifacts, artifact
bindings, receipt decisions, receipt roles, separation of duties, timestamp
order, and global receipt uniqueness.

Inspect the checked-in absence result:

```sh
julia --startup-file=no --project=scripts/us -e '
include("scripts/us/forecasting/evidence/USEvidenceVerifier.jl")
using .USEvidenceVerifier
display(verify_evidence())
'
```
