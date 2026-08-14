# BEA after-redefinitions 2025 prospective adapter v1

This adapter binds the six `bea_industry_valuation_structural` profiles assigned
by prospective contract v2 to `slow_structural_pre_origin`. It uses the archived
September 25, 2025 annual-release artifact at this exact immutable locator:

```text
https://apps.bea.gov/HistData/Files/Releases/Industry/2025/GDP_by_Industry/Q2/Annual_September-25-2025/MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip
```

The expected archive is exactly 8,326,144 bytes with SHA-256
`c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da`.
The adapter pins the prospective-v2 physical and semantic identities, the
current source inventory, `scripts/us` Project/Manifest, the reusable envelope,
and four existing repository evidence records. It refuses any binding drift.

The policy review is frozen to 2026-08-08 and binds the exact BEA linking,
FAQ 145, Input-Output, and open-data URLs. No policy-page response bytes were
captured by this adapter, so it records no page-content hashes and makes no
same-day legal-authorization claim. Direct archive policy is not generalized to
BEA API access, nor are API registration/terms generalized back to this direct
file. Required wording is `Source: U.S. Bureau of Economic Analysis`; no BEA
endorsement is claimed.

## Six profiles and selectors

The closed profile contains only:

1. the exact after-redefinitions release ZIP;
2. 2024 producer-price use from
   `IOUse_After_Redefinitions_PRO_Summary.xlsx`;
3. 2024 producer-price make from
   `IOMake_After_Redefinitions_PRO_Summary.xlsx`;
4. the full 2024 imports-by-user matrix from
   `ImportMatrices_After_Redefinitions_Summary.xlsx`;
5. the resolved 2017 purchaser-price benchmark use workbook
   `IOUse_After_Redefinitions_PUR_Summary.xlsx`; and
6. the resolved 2017 producer-price benchmark use sheet in the producer use
   workbook.

The profile records the full 12-member outer ZIP directory and CRC metadata. For
the four selected workbooks it also pins exact workbook SHA-256/byte counts,
outer CRC-32, `xl/workbook.xml` SHA-256/byte count/CRC-32, and source-order sheet
inventories. `selector_receipt` reconstructs all six records from the exact raw
archive identity and parsed directory. `validate_extracted_evidence` additionally
rehashes independently supplied workbook bytes, recomputes their outer CRCs, and
checks the nested OOXML sheet evidence.

The six profiles are August 6–31, 2026 completion-eligible only if a new
prospective bundle is actually acquired and validates. The other 27 profiles in
the slow structural campaign remain excluded and cannot be relabeled by this
adapter.

## Current status and execution boundary

Status remains `CANNOT_RUN_NO_NEW_PROSPECTIVE_BUNDLE`. The preserved August 6
archive used for offline identity verification came from an earlier mutable-URL,
nonprospective accounting diagnostic. It is not silently converted into a new
capture or origin artifact.

`capture_after_redefinitions_with_fetcher` delegates to the pure snapshot
envelope. Its default is a zero-request, zero-write dry run. Live use requires
all of the following in one explicit call:

- `execute_live=true`;
- an injected direct HTTPS transport that returns the envelope's closed
  `FetchResponse` type;
- a typed clock source (the default samples the local UTC host clock), with a
  passing window check both before transaction mutation and again after the
  durable journal immediately before callback invocation;
- a BEA terms-review date equal to the UTC request-start date and an actor
  assertion; and
- optionally, an evidence provider that independently extracts the four
  workbooks and their `xl/workbook.xml` bytes, plus an external timestamp
  provider/verifier.

There is no built-in network transport, no redirect/proxy/netrc/cookie fallback,
and no retry after an uncertain request. This implementation has made no live
request and has written nothing under `data/us/raw`.

If a typed response arrives but its body hash, headers, six-profile selector, or
timestamp evidence fails, the reusable envelope preserves two durable copies in
a separate nonadmitting quarantine. `validate_capture_quarantine` reconstructs
that artifact. It cannot create a completion receipt, selector/profile evidence,
or an origin claim, and the transaction remains permanently no-retry.

Even after a valid capture, all origin admission, source-inventory mutation,
model-state, empirical forecasting, accuracy evaluation, promotion, production,
and scoring gates remain false. The two local replicas are one fault domain;
transport and local attestations are unauthenticated; and absent external
timestamp evidence remains explicitly false.

## Verification

From the repository root:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_industry/after_redefinitions_2025_adapter_v1/test_bea_after_redefinitions_2025_adapter_v1.jl
```

The accepted local run passes 144 assertions. It checks exact source and
prospective mappings, 20 profile-tamper classes (including Float/Bool aliases for
counts, byte sizes, compression methods, and request-header sequence),
zero-effect dry behavior, all 12
outer ZIP entries, all six selectors, and an independent four-workbook
CRC/SHA-256/OOXML audit against the preserved exact archive. It also proves
zero callback calls at both adapter clock gates and routes the exact archive
through one offline injected six-profile bundle plus one nonadmitting invalid
media-type quarantine. Coordinated self-rehash mutations of the top-level
selector count and nested profile evidence count are rejected. Neither test
opens a socket or leaves its temporary root.

Frozen implementation identities for this version are:

- adapter module: `11be31c23033593c140d056093b82752ffe151d185ec88f27261e4e476dc4018`
- adapter normalized module: `9bd6b1e249d010ceecd8a9deac5b17b7541ce58838642b3decbb8ef688babe31`
- profile contract: `57c71a1d9a1a8f4ecad7fbc4dbc284590792aa3b2966388bf138397dc0e10d11`
- derived capture policy: `ef97acfcbd31fca34e2466e9199c06aa26f43dc67f80fda04386186db1075212`
- tests: `d334a3bfdaf68ea6940a52edb4ed4428fb27c0dc9887d3703082ccf2434c9024`
- reusable envelope: `cb8fffd626c019fa6ce65a32664a46d1ecd87d3337f72ea378900d2d4f05b165`
