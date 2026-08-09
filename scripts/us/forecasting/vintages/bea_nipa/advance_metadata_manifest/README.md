# BEA HMI7 40-release metadata contract

This directory seals the official BEA HMI7 metadata inventory for the 40
consecutive earliest-complete quarterly releases from 2011Q3 through 2021Q2.
It is an offline metadata contract, not a workbook capture and not evidence
that the current HMI7 workbook bytes were available at historical forecast
origins.

The manifest binds:

- the exact HMI7 root-metadata and BEA release-sitemap URL, byte-count, and
  SHA-256 observations made on 2026-08-07;
- all 40 reference quarters, archive paths with original case, directory IDs,
  archive labels and folder dates;
- official BEA embargo timestamps in `America/New_York` and UTC, release
  numbers, canonical news pages, and full-release PDF locators;
- the direct-child Section 1 and Section 2 filenames;
- 24 legacy `.xls` pairs through 2017Q2 and 16 `.xlsx` pairs beginning in
  2017Q3;
- annual/comprehensive revision or update classifications, shutdown
  irregularities, and all 15 archive-folder/event-date mismatches.

The path for 2014Q3 deliberately contains lowercase `q3`. The 2018Q4 row is
the shutdown-related `Initial` estimate that BEA states replaced the cancelled
Advance and Second estimates. Neither exception may be normalized away.

## Files

- `bea_hmi7_advance_manifest_2011q3_2021q2.toml` is the sealed inventory.
- `BEAHMI7AdvanceMetadataManifest.jl` parses and validates the inventory
  without network access.
- `test_bea_hmi7_advance_metadata_manifest.jl` exercises the contract and
  adversarial drift cases.

The manifest self-hash uses sorted, typed, length-aware canonicalization,
excluding only `artifact.content_sha256`. Array order is significant. The
validator also pins the expected canonical digest in code, so changing a row
and recomputing the manifest's self-hash cannot silently redefine the
contract. Successful validation returns only immutable named tuples and
tuples; it never returns or aliases the mutable parsed TOML dictionary under
the trusted digest.

All historical-workbook-availability, strict-origin, empirical execution,
promotion, production-scoring, and readiness gates are false. The validator
rejects any attempt to enable one of them.

## Hermetic validation

Run:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/advance_metadata_manifest/test_bea_hmi7_advance_metadata_manifest.jl
```

The test and validator read only local files. They do not import `Downloads`
or `HTTP`, open BEA URLs, acquire workbook or PDF bytes, or mutate a source
release inventory. Because the two observed anchor bodies are deliberately
not stored, hermetic tests validate their sealed hash assertions rather than
recomputing those hashes from retained bodies; live reproduction is a
separate audit.

The separately governed `../advance_capture/` boundary consumes this exact
compiled-pin artifact to derive and seal one present-day Section 1/Section 2
pair at a time. It does not change any historical-availability or admission
gate in this metadata contract.

## Source boundary

The two metadata anchors are:

- [BEA HMI7 root metadata](https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=7&getFiles=false&getDirs=true)
- [BEA release sitemap](https://www.bea.gov/releases/sitemap.xml)

Each release row contains its official news page and PDF locator. Those
locators support release-event identity and timing. They do not prove the
historical publication time or first state of the archived Excel bytes.
