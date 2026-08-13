# Historical BEA HMI7 present-day capture boundary

This directory implements an isolated, fail-closed capture contract for two
official BEA HMI7 National Accounts workbook pairs:

- 2019Q4 advance monthly-table snapshot, HMI7 directory `13075`
- 2021Q2 advance/annual-update monthly-table snapshot, HMI7 directory `13091`

Each identity binds the discovered archive directory ID and normalized path,
the exact Section 1 and Section 2 URLs, byte counts, SHA-256 digests, current
ETags, and current `Last-Modified` headers. A capture succeeds only when both
workbooks match. Each capture is installed below its stable pair hash and
receipt-specific self-hash, so repeated retrievals of unchanged bytes preserve
their distinct acquisition evidence. The pair and its receipt move together
through an exclusive atomic directory rename below the caller-supplied,
ignored `data/us/raw` root.

```text
bea_nipa/hmi7/historical/captures/
  pair-sha256-<raw-pair-digest>/
    receipt-self-sha256-<capture-receipt-digest>/
```

The live downloader requests identity encoding and fails during transfer when
either the advertised or observed body exceeds 25 MB. It rejects redirects,
wrong media types, byte counts, hashes, ETags, and `Last-Modified` values. The
server `Date` header must be a semantically valid IMF-fixdate within five
minutes of the locally observed request/return interval; that clock check is
present-day capture integrity, not historical-availability evidence.

## Evidence boundary

The economic news events are separate from these workbook snapshots:

- BEA release `20-04` was embargoed at `2020-01-30T13:30:00Z`; the HMI7
  directory and current workbook headers identify a January 31 monthly-table
  snapshot.
- BEA release `21-36` was embargoed at `2021-07-29T12:30:00Z`; the HMI7
  directory and current workbook headers identify a July 30 monthly-table
  snapshot. This release includes the 2021 annual update and revised history.

The next-day archive labels and current headers do not prove the bytes present
at the release event, the archive's historical first state, or what was
available to a forecaster at a historical origin. The receipt therefore binds
the exact present-day bytes while hard-coding all of these gates to `false`:

- `historical_first_state_verified`
- `historical_availability_verified`
- `origin_admissible`
- `empirical_execution_allowed`
- `inventory_mutation_authorized`
- `production_authorized`
- `ready`

The contract does not import workbook cells and never writes
`current_inventory.toml`.

## Terms boundary

Every live run requires a same-host-local-day review of BEA's
[FAQ 145 terms guidance](https://www.bea.gov/index.php/help/faq/145).
Receipts attribute the source to the U.S. Bureau of Economic Analysis. This
capture contract does not authorize BEA logo reuse or redistribution.

## Focused tests

Tests use only small synthetic OOXML-signature fixtures and an internal
deterministic seam; they make no network requests:

```sh
julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/historical/test_bea_hmi7_historical_capture.jl
```

## Opt-in live capture

Use an absolute, normalized, canonical raw root. The repository ignores
`data/us/raw/`.

```sh
julia --startup-file=no --check-bounds=yes --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/historical/capture_present_day.jl \
  --capture-id bea_hmi7_2019q4_advance_monthly_snapshot \
  --raw-root /absolute/path/to/data/us/raw \
  --terms-reviewed-local-date YYYY-MM-DD \
  --live
```

Repeat with
`bea_hmi7_2021q2_advance_annual_update_monthly_snapshot` for the pandemic/
annual-update diagnostic pair.
