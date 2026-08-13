# WS-0B paper/code crosswalk and model variants

This directory is the machine-readable baseline for the Part-I audit in
`US_FORECASTING_PLAN.md`. It is an audit and governance artifact, not evidence
that any model is a literal paper replication or an accurate forecaster.

The registry contains 40 required records:

- 3 apparent printed-paper typo candidates;
- all 19 numbered printed-equation/upstream differences;
- 3 additional implementation conventions called out in Part I;
- the vector-minimum and growth-rate wiring defects;
- 13 material U.S. fork additions, including both scenario timing boundaries.

Every record supplies paper and code evidence, classification, materiality,
resolution, status, rationale, test or pending-test evidence, an owner, an
independent validator, and a concrete treatment for each of four variants.
`unassigned` is intentional where independent review has not happened.

## Artifacts

- `crosswalk.toml` is the complete discrepancy and unresolved-question
  register. Its canonical content SHA-256 is
  `da097ef97ad6510dfed5234df7b14b4b48ad63d62a4f52f6829f70c0e2f6cde6`.
- `baseline_variants.toml` defines the change taxonomy, governance gate, and
  four baseline manifests. Its canonical content SHA-256 is
  `1fbdf6fcbeedc07fb9971b7e39c18852f74ace8fb07055b4f1ad2f43dcb29728`.
- The current unsigned approval payload SHA-256, which covers both substantive
  artifacts while excluding the attestation fields themselves, is
  `1a0936112e883d22603cad67f47a19eb2f9b66777ba895bc84dc96c6454e0ed7`.
- `USModelVariants.jl` validates schemas, exact required coverage, evidence
  prefixes, per-variant treatments, cross-artifact linkage, canonical hashes,
  allowed claims, and governance signatures.
- `test_variants.jl` is a hermetic suite covering completeness, current
  vector-minimum and growth-wiring corrections, tamper detection, parser
  failure, ambiguous treatments, blanket claims, and gate behavior.

Canonical hashes exclude only their own
`artifact.content_sha256` field. Dictionary key and TOML table order do not
change the digest; array order does.

## The four variants

| Variant | Meaning | Permitted claim |
|---|---|---|
| `printed_paper_reference` | The hashed 63-page SSRN preprint; reference-only and not executable | A source reference, not a runnable model |
| `upstream_compatible_6030f75` | Historical upstream-compatible behavior pinned to full commit `6030f7558a9956a99465a09e31c51f37df198c90` | Historical implementation behavior, not paper equivalence |
| `reviewed_us_port` | The reviewed U.S. configuration, including measured trade, valuation bridge, discrepancy-derived opening inventories, and the former embedded forecast-error correction layer | A reviewed but unvalidated U.S. port |
| `corrected_candidate` | Working-tree candidate with elementwise capacity minima, the base-model growth-rate guard, and the calibration firewall | A correctness candidate, not a validated forecaster |

The printed reference, historical checkout, U.S. configuration, and corrected
candidate must never share an unqualified label such as “the paper model.”
When treatments disagree, score them as separate variants.

## Validation and the open gate

Run the hermetic tests:

```sh
julia --startup-file=no --project=. \
  scripts/us/forecasting/variants/test_variants.jl
```

Inspect schema validity without treating it as approval:

```sh
julia --startup-file=no --project=. \
  scripts/us/forecasting/variants/USModelVariants.jl --schema-only
```

The current expected result is `schema_valid=true` and `gate=open`. Open work
is reported rather than averaged away:

- both artifacts remain `draft`;
- 27 entries have an `open_*` status;
- 34 entries retain 36 `pending:` test pointers;
- 25 entries have no implemented repository test yet;
- all 40 entry-level independent validators remain unassigned; and
- model-owner and independent-validator attestations are unsigned.

Running the validator without `--schema-only` is the promotion check. It exits
with status 2 while the gate is open:

```sh
julia --startup-file=no --project=. \
  scripts/us/forecasting/variants/USModelVariants.jl
```

This split is deliberate: a valid schema can be reviewed and versioned, but an
unfinished or unsigned artifact cannot pass the scientific gate. Closure
requires `approved` artifacts, zero open entries, zero pending test pointers,
at least one implemented repository test per entry, assigned owners and
independent entry validators, and distinct model-owner and
independent-validator attestations.

Attestation checksums are bound to the complete approval payload, approval
scope, actor role and name, and signing timestamp. Use
`expected_gate_attestation` to construct the checksum only after the
substantive artifacts and reviewer names are frozen. This checksum binding is
an audit control, not a substitute for organizational identity verification.

## Updating the registry

1. Add or change a fully specified crosswalk record. The validator rejects
   missing required IDs, unknown keys, absent evidence, missing variant
   treatments, and vague actions such as `inherit`, `same`, or `tbd`.
2. Compute the new crosswalk digest with
   `computed_artifact_sha256(TOML.parsefile(...))` and update
   `crosswalk.toml` plus `baseline_variants.toml.crosswalk_sha256`.
3. Compute and update the variant-manifest digest.
4. Run `test_variants.jl`, Runic on the Julia files, and both validator modes.
5. Resolve every `open_*` status and `pending:` pointer, assign independent
   entry validators, and change both artifact statuses to `approved`.
6. Obtain named model-owner and independent-validator attestations over the
   frozen approval payload before changing the gate to `closed`. Schema
   validation is never an approval.

This directory is intentionally standalone because WS-0B was restricted from
editing existing CI files. The command to add to the hermetic CI job is:

```sh
julia --startup-file=no --project=. \
  scripts/us/forecasting/variants/test_variants.jl
```

CI may also run the schema-only command above. A promotion job should run the
validator without `--schema-only`; it will remain red until the scientific
gate is genuinely closed.

Pending behavioral tests remain visible as `pending:` pointers. A documented
variant split is not a claim that two stochastic algorithms are
distribution-equivalent, and provenance checks are not economic validation.
