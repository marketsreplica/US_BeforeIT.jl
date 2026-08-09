# Closed BEA HMI7 2017-era OOXML profile

This directory parses one exact, quarantined present-day BEA archive capture:
the Section 1 and Section 2 pair for the 2017Q3 advance estimate (metadata
sequence 25). It is a separate parser/profile because these October 2017
workbooks store the five target histories as shared strings under Excel's
`General` style. The accepted 2019/2021 parser requires numeric OOXML cells
and remains unchanged.

## Exact input boundary

The public entry point accepts only this bundle identity:

```text
bundle/receipt semantic SHA-256  1ed6435ae6be6a2a9e629bab2d0b3f3112117926cf3d365fac3e0dc1ef8b312d
receipt file SHA-256             56f99f2a5630226d94ce45cd111d5990c61b35069c9ed65bce2e0509af2b0d71
raw pair SHA-256                 e46bf665a69799c3f98cd2dff29263fe30b8b616163f5f97281a0fc82b720ee9
Section 1 SHA-256                b6461337a1438e36a232d7b1a86fe3bf75df5c190f8b7900ad732c4fe56e03d5
Section 2 SHA-256                4cb8c738fdc1785a701be314ec2809e3e74628ea5b6aae6c1ccb783af286b1b0
```

It rejects any extra, missing, aliased, symbolic-linked, or hard-linked file.
It rehashes the receipt and both raw objects before parsing and again after
parsing. The raw bytes are never written or modified.

The parser validates ZIP paths, member aliases, size limits, CRCs, content
types, every package relationship, the ordered 114/39-sheet manifests, the
two exact `General` styles, shared-string counts and semantic manifests,
critical worksheet dimensions, formula absence, physical rows, table and
series identities, units/base, and the complete 1947Q1--2017Q3 quarter axis.

## Closed lexical and missingness rules

- Nominal and real GDP are positive integer SAAR levels with exact ASCII
  thousands grouping, for example `19,495,476`. Ungrouped numbers, misplaced
  commas, signs, whitespace, exponent notation, locale punctuation, leading
  zeroes, and Unicode digit aliases fail.
- GDP-deflator, PCE-price, and core-PCE-price observations are positive ASCII
  decimals with exactly three fractional digits, for example `113.630`.
  Signs, whitespace, exponents, non-finite values, commas, leading zeroes,
  locale forms, and Unicode digit aliases fail.
- Core PCE has an axis-complete but source-missing interval from 1947Q1
  through 1958Q4. Exactly 48 cells (`D34:AY34`) must contain the literal
  `.....` and are emitted as `SOURCE_MISSING` with no canonical number.
  Numeric observations must start at 1959Q1 and remain gap-free. Blank,
  `NA`, or any alternate dot token fails.

Numeric values are emitted as arbitrary-precision coefficient and scale
strings, so no binary floating-point or consumer JSON-number limit is part of
the identity. Q2-to-Q3 annualized changes are calculated with integer powers
and an exact reduced rational:

```text
100 * ((current_level / previous_level)^4 - 1)
```

The semantic checks reproduce the release-page current-dollar GDP level
(`$19,495.5` billion) and the rounded statements for real GDP (`3.0`
percent), the PCE price index (`1.5` percent), and core PCE prices (`1.3`
percent). Those comparisons are explicitly non-origin checks.

## Temporal limitation

The [BEA release page](https://www.bea.gov/news/2017/gross-domestic-product-3rd-quarter-2017-advance-estimate)
identifies the release event as 2017-10-27 at 08:30 EDT. The exact capture was
made on 2026-08-07 UTC. More decisively, Section 2 embeds `File created Oct 29
2017  1:23PM`, and its captured HTTP `Last-Modified` is `Tue, 31 Oct 2017
15:29:36 GMT`. The present archive object therefore cannot establish the
Section 2 bytes available at the historical forecast origin.

Every artifact, capture, release, workbook, target, and semantic-check scope
keeps historical-availability, origin, target, truth, model-input, forecast,
scoring, promotion, inventory-mutation, production, and readiness gates
false. This component reconstructs archive content; it creates no admitted
origin, truth record, forecast, score, or accuracy claim.

## Run and test

Use absolute paths. The output is canonical, content-addressed JSON and is
byte-identical from an unrelated working directory.

```bash
python3 scripts/us/forecasting/vintages/bea_nipa/era_2017_profile/fingerprint_2017q3_advance.py \
  --bundle "$PWD/data/us/raw/forecasting/bea_hmi7/advance/receipt-sha256-1ed6435ae6be6a2a9e629bab2d0b3f3112117926cf3d365fac3e0dc1ef8b312d" \
  --output-dir /private/tmp/bea-hmi7-era-2017-output

python3 \
  scripts/us/forecasting/vintages/bea_nipa/era_2017_profile/test_fingerprint_2017q3_advance.py
```

The test suite uses the preserved read-only bundle and temporary copies. It
includes cell-type, style, comma, decimal, shared-string-index, formula,
duplicate-ZIP, unsafe-path, relationship-traversal, physical-row, series-code,
quarter-axis, incomplete-history, missing-token, raw-hash, receipt, symlink,
hard-link, extra-file, and unrelated-working-directory cases. It makes no
network request and never writes under `data/us/raw`.
