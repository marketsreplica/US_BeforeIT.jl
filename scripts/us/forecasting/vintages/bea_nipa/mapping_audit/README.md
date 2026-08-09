# BEA NIPA HMI7 mapping audit

This directory records a read-only scientific audit of concept drift in
official BEA HMI7 NIPA workbooks. It is deliberately separate from source
acquisition and the release inventory.

The audit is non-admitting:

- provenance is `ephemeral_research_audit_only`;
- no downloaded workbook bytes are persisted;
- historical byte availability is not verified;
- no origin is admitted; and
- no record is READY.

`bea_nipa_mapping_audit.toml` contains 40 official workbook locators and
SHA-256 observations, 20 release records, eight exact mapping profiles,
40 per-target mappings, seven demonstrated adjacent-release breaks, and nine
evidence gaps. Its checked-in byte hash is
`424e34febc2054a055f8f9495a94f08fd93d8229d035b0a349b0446f0e7c2b5f`.

## Exact-release rule

A profile is only a compact description of mappings observed in specifically
listed release IDs. `profile_for_release` rejects:

- an unknown release;
- a partially inspected boundary release; and
- any attempt to infer a profile from a date, quarter, archive label, or
  neighboring release.

The field `ephemeral_audit_profile_assignment_eligible` means only that all
five mappings were inspected for that exact ephemeral research observation.
It does not imply acquisition eligibility, verified historical availability,
origin admission, promotion eligibility, or READY status.

Every future release must independently validate workbook hash, section,
sheet, table title, quarterly frequency, unit and base year, published line,
physical row, series code, and reference-period columns.

## Files

- `bea_nipa_mapping_audit.toml`: the machine-readable audit.
- `BEANIPAMappingAudit.jl`: strict byte and semantic validator.
- `test_mapping_audit.jl`: hermetic positive and adversarial tests.

The validator pins the complete TOML byte stream by SHA-256 in addition to
checking exact keys, counts, identifiers, cross-references, statuses, target
coverage, profile membership, adjacent-break evidence, URL forms, retrieval
timestamps, and workbook hashes.

## Test

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/mapping_audit/test_mapping_audit.jl
```

The test does not use the network and does not mutate the inventory, plan,
work log, or any acquisition state.
