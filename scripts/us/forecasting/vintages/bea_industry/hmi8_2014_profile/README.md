# BEA HMI8 January-2014 present-day archive profile

Status: **frozen nonadmitting candidate; independent audit required**.

This isolated, standard-library-only Python profile validates the current BEA
HMI8 archive entry labelled `Comprehensive_January-23-2014`. It fingerprints
the discovery metadata, both outer ZIPs, two annual summary workbooks, and the
2007 benchmark-detail make/use pair. It does not modify the later-era parsers,
the source inventory, raw data, any forecast origin, or an ABM state.

The scientific classification is deliberately narrow:

- `byte_observation_mode = PRESENT_DAY_ARCHIVE_RETRIEVAL`;
- `information_set_construction_mode = UNKNOWN_INFORMATION_SET`;
- January 23, 2014 is supported only at date precision, so the profile uses a
  conservative New York end-of-day availability ceiling;
- the two archive responses currently advertise March 2015 HTTP
  `Last-Modified` timestamps;
- both detail workbooks were modified on February 14, 2014 and their ReadMe
  records a post-release real-estate aggregation on that date;
- every origin, model-input, forecast, score, accuracy, and promotion gate is
  false.

Consequently, a successful parse proves the content of the bytes retrieved in
2026. It does not prove that those exact bytes were served on January 23, 2014,
that they were the first public state, or when within that day they became
available.

## Pinned inputs

| Input | Bytes | SHA-256 |
|---|---:|---|
| `hmi8-root.json` | 40,651 | `3ec9431c62fa419595f6acbe485c683adb1ebba67924862f5677271eb8d51a1e` |
| `url-path-id.json` | 70 | `6156a2acaa650ed89472b50604ded7ac8540bc1a34809887edf6dde833751d9a` |
| `get-path.json` | 192 | `9e32cb466447d4f8492131acfbbe6b61ef8df154d9160bde171e97fc84b6230c` |
| `release-files.json` | 4,203 | `ac2bdf3c8ee61473d45f3880158b00a30d38ec67cca42d6f4ee1c53853beafa7` |
| `AllTablesIO.zip` | 15,397,981 | `c98eff9b134e66429d12a740d72306e08de3bd29703aa6ea56310262a7879330` |
| `AllTables.zip` | 537,569 | `08209ee802eec3773a49f7cac7a0b82e6b0f86bf6176028b2a19ff4d27f0a409` |
| summary make workbook | 618,395 | `67735472f7ed832df3603fbf234b7a8404e4fe8e70884c3f112426e32637e750` |
| summary producer-price use workbook | 767,039 | `3313ccd997d995d2f9354148587d1358e914d30ca6cad550ed2a45842696af62` |
| detail make workbook | 499,255 | `b3cf4d96ab651c3d9c6f4a1f1e340cc77e40a2995a060a5588393b092a7c7669` |
| detail producer-price use workbook | 728,138 | `52f5b354a9647ef01fc68f3c1c82a7cb194f03f55ec6a16ace48752ae34f49e5` |

The parser requires the four extracted workbooks to be byte-identical to the
corresponding members of `AllTablesIO.zip`; merely presenting files with the
right names is insufficient.

## Closed parser contract

The parser checks all of the following before emitting an artifact:

- direct regular-file identity, byte count, SHA-256, and single-link status;
- duplicate-member, case-alias, traversal, encryption, symbolic-link, size,
  compression, decompression, and CRC rules for both outer ZIPs and all four
  OOXML packages;
- the exact outer member sequences (30 OOXML workbooks and five legacy XLS
  files), plus a content hash for every member;
- OOXML content types and every internal/external relationship, with internal
  target resolution and an exact allowlist for the four BEA hyperlinks;
- exact sheet order, sheet IDs, relationship targets, dimensions, annual
  `1997` through `2012` coverage, shared-string counts/indices/rich-text
  grammar, style bounds and number formats, core properties, and ReadMe text;
- the exact 69-code summary ordinary axis, explicit `Used`/`Other` rows and
  columns, terminal totals, final-use codes, value-added rows, and an exact
  integer-or-blank lexical grammar (`0|-?[1-9][0-9]*`);
- arbitrary-precision integer conversion, without commas, decimal points,
  exponents, leading zeroes, whitespace, plus signs, locale digits, Unicode
  minus signs, or analyst-generated aliases;
- the exact 388-by-388 detailed axes, special codes `S00401`, `S00402`,
  `S00300`, and `S00900`, the federal detail witness, and the single combined
  real-estate code `531000`;
- make/use accounting checks using the published integer cells. Published
  rounding residuals are bounded and retained; the parser never rebalances
  the source tables.

Three workbooks are formula-free. The detail-use workbook has one exact,
fail-closed historical exception: `2007!OP337:OP344` are style `11`, type `e`,
cached `#REF!` cells whose formulas are bound row-by-row to
`#REF!-SUM(Cr:OAr,OCr:OMr)`. Column `OP` has no logical header and lies beyond
the declared evidence boundary `ON/T007`; those cells are excluded from the
data matrix. The calc-chain must name the same eight cells. Any other formula,
error, token, style, coordinate, or cache value fails.

## Mapping result

The annual summary axis contains 69 ordinary industries. Mapping it to the
later project axis requires both:

```text
531 -> HS + ORE
GFG -> GFGD + GFGN
```

The detail tables support the federal defense/nondefense witness through
`S00500` and `S00600`. They contain only `531000` for real estate, so they
cannot identify the historical `HS`/`ORE` split. The exact crosswalk also
confirms `Used = S00401 + S00402` and
`Other = S00300 + S00900`; both component pairs reconcile exactly to their
2007 summary outputs. None of those equalities authorizes a behavioral
producer, a later-share allocation, or an ABM state.

## Frozen candidate hashes

| Object | SHA-256 |
|---|---|
| profile contract | `8d2555d0b2bd449253c27bf3da562b4dbe2011a3c64f1689f560471c69f5c8df` |
| summary-make structure | `8bc6bc60552f512c3fc9cbfcbc5a4c60b057a5f03671f695745858f7d22408ed` |
| summary-use structure | `8e1d6d5dd6ba78db249e9ce31118a1aa5524ba7f7c5f04fb2ee3fb7661cd8229` |
| detail-make structure | `e3210bc9aa2c19adf8dbe23085f6c512b97fe23dbd1d6c79b6499a71d7a0bf6d` |
| detail-use structure | `3843b0356c918bf9a42cdd95878026569f66ffb349326116aa14a0adc2553183` |
| semantic artifact (before its self-hash field) | `79e96950772bbd172f26ef7a53f096862cd0d87f0cc4de1f244fd336d164508a` |
| canonical emitted artifact file | `5ed02e8f5b0959430d42bcb9df65641f628370c00ce20435cc39e43618775f9a` |

The self-hash is a local fixity check, not authenticated historical provenance.

## Run and test

From the repository root:

```sh
python3 scripts/us/forecasting/vintages/bea_industry/hmi8_2014_profile/fingerprint_hmi8_2014.py \
  --capture-dir /tmp/bea-hmi8-20140123.NDC4Vc \
  --workbook-dir /tmp/bea-hmi8-sheet-inspect.yjRVD3

python3 -m unittest \
  scripts/us/forecasting/vintages/bea_industry/hmi8_2014_profile/test_fingerprint_hmi8_2014.py -v
```

The tests cover exact inputs, root and unrelated working directories, hash and
hard-link drift, JSON duplicate names after escape decoding, ZIP duplicates,
case aliases, traversal and CRC corruption, relationship traversal/duplicates,
shared-string indices, cell types, style indices, formulas/errors, the closed
integer grammar, row/code/axis/history mutations, accounting bounds, and all
false gates. Set `BEA_HMI8_2014_CAPTURE_DIR` and
`BEA_HMI8_2014_WORKBOOK_DIR` to audit the same exact inputs elsewhere; pure
synthetic adversarial tests still run when the temporary exact inputs are not
present.

## Official source context

- [BEA HMI8 archive metadata](https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=8&getFiles=false&getDirs=true)
- [BEA 2007 benchmark input-output release, December 18, 2013](https://www.bea.gov/news/2013/2007-benchmark-input-output-account)
- [BEA Survey of Current Business, February 2014](https://apps.bea.gov/scb/issues/2014/scb-2014-february.pdf)

These sources support release identity and interpretation. They do not turn a
present-day archive download into contemporaneously observed historical bytes.
