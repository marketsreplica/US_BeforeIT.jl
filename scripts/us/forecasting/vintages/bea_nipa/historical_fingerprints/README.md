# Historical BEA HMI7 semantic fingerprints

This directory contains a dependency-free, fail-closed OOXML parser for two
exact BEA HMI7 workbook pairs:

- 2019Q4 advance, archive directory `13075`
- 2021Q2 advance/annual update, archive directory `13091`

Each release is atomic: Section 1 and Section 2 must both match their pinned
byte counts and SHA-256 identities before one content-addressed JSON
fingerprint is emitted. The fingerprint binds the raw pair hash used by the
adjacent capture contract, parser bytes, mapping and release profiles, exact
sheet counts and sheet manifests, workbook headers, row labels, quarterly
period axes, cell styles, every parsed target observation, and the expected
terminal cells and values.

The five mappings are:

| Target | Sheet | Published line / physical row | Series | Units |
|---|---|---:|---|---|
| Nominal GDP | `T10105-Q` | 1 / 9 | `A191RC` | Millions of dollars, SAAR |
| Real GDP | `T10106-Q` | 1 / 9 | `A191RX` | Millions of chained 2012 dollars, SAAR |
| GDP deflator | `T10109-Q` | 1 / 9 | `A191RD` | 2012=100 |
| PCE price index | `T20304-Q` | 1 / 9 | `DPCERG` | 2012=100 |
| Core PCE price index | `T20304-Q` | 25 / 34 | `DPCCRG` | 2012=100 |

All five histories must be numeric from 1997Q1 through the release endpoint.
Earlier source missing markers are preserved in the fingerprint. Formulas,
error cells, missing values in the complete window, unexpected number
formats, period or mapping drift, ZIP traversal and aliases, partial pairs,
and raw-byte drift are rejected.

## Evidence boundary

Every artifact and parsed record is labeled
`PRESENT_DAY_ARCHIVE_BYTES_PARSED_NONADMITTING`. Present-day parsing cannot
prove the archive's historical first state, the bytes available at the
release event, or information available at a forecast origin. These gates
are therefore hard-coded to `false` at artifact, release, workbook, and
target level:

- `historical_first_state_verified`
- `historical_availability_verified`
- `origin_admissible`
- `empirical_execution_allowed`
- `inventory_mutation_authorized`
- `production_authorized`
- `ready`

The 2021Q2 fingerprint explicitly records that the release includes the 2021
annual update and revised history. It must not be treated as a standard
within-definition vintage.

The checked-in JSON files are small semantic fingerprints. Raw workbooks
remain outside Git, and this parser never modifies the vintage inventory.

## Focused tests

Tests use generated standard-library OOXML fixtures and adversarial
mutations; they make no network requests:

```sh
python3 \
  scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/test_fingerprint_historical_releases.py
```

## Reproduce a fingerprint

Use absolute, normalized, canonical paths. For 2019Q4:

```sh
python3 \
  scripts/us/forecasting/vintages/bea_nipa/historical_fingerprints/fingerprint_historical_releases.py \
  --release-id r2019q4_advance_hmi7_monthly_snapshot \
  --raw-root /absolute/path/to/raw/pair \
  --section-1 /absolute/path/to/raw/pair/section-1.xlsx \
  --section-2 /absolute/path/to/raw/pair/section-2.xlsx \
  --output-dir /absolute/path/to/historical_fingerprints/fingerprints
```

For 2021Q2, use release ID
`r2021q2_advance_annual_update_hmi7_monthly_snapshot` and its corresponding
pinned Section 1 and Section 2 files.
