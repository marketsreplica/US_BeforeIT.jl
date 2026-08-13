# Census structural present-day physical profile v1

This directory contains a standard-library-only parser and a self-hashed
physical-layout profile for six files observed on 2026-08-08:

- the five 2023 AIES inventory ZIPs (`AIES00INV`, `AIES31INV`, `AIES42INV`,
  `AIES44INV`, and `AIES51INV`); and
- the full 2022 SUSB state-by-six-digit-NAICS text file.

Its permanent maximum is `CANNOT_RUN` with role
`PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_NONADMITTING`. It does not authenticate
Census, establish that the local bytes came from the declared URLs, prove
transport or custody, qualify a parser for a later capture, admit model input,
or authorize forecasting, truth access, scoring, promotion, production, or an
inventory mutation.

The downloaded bodies and raw response headers are intentionally external to
the repository. The profile stores only small hashes, sizes, structural facts,
and semantic derivatives. Present-day bytes are not evidence of future layout
compatibility.

## Binding to the accepted logical contract

The parser requires all four frozen artifacts in the independently accepted
`../profile_v1/` directory:

| Artifact | SHA-256 |
| --- | --- |
| `USCensusStructuralProfileV1.jl` | `e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68` |
| `census_structural_profile_v1.toml` | `512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157` |
| `test_census_structural_profile_v1.jl` | `ef2089d3fb47400947111f8b8a743999c42c0092b547d70e8be7c9708447cd55` |
| accepted README | `4a734c3fe7239dc686b9fe0de53075ec5a4d0c3b96d31298c2be3d8d45a980e5` |

The accepted profile semantic hash is
`c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491`.
The physical profile semantic hash is
`50cc87614dfbfc63ddc58342b24ea8d20a2b6d6364fd804f51e86ea3ac155a8f`;
its physical SHA-256 is
`556fb4319ddc05779bb785588b32df60704ff4a276f8a133b58cef59710b9673`.

The present bytes map to the accepted field topology, but they do not satisfy
the accepted row constraints. The parser therefore emits
`logical_field_topology_mapped=true` and
`logical_constraint_compatibility=false`. It never passes these provider bytes
to the accepted module's synthetic-fixture API. A separately versioned logical
contract successor is mandatory before any qualification.

## Exact present-day source diagnostics

These are local fixity observations, not origin claims:

| File | Bytes | Body SHA-256 | Raw-header bytes | Raw-header SHA-256 |
| --- | ---: | --- | ---: | --- |
| `AIES00INV.zip` | 28,470 | `d141f6b6f932335b404557d3007766f75d6d110bfa065b533e2b74a0a277664b` | 1,231 | `44c4fd09e97cffeb6fd6653181c33a0a6e9435b75fb8ea46babcf592704612e1` |
| `AIES31INV.zip` | 18,902 | `6d2fc3faf1a7e69f9c6fb882233a94f871e5b2e39626963a9c14a3b5228fd3dd` | 1,232 | `8b0c79b9cdb5eb11c5ff8e81e7bd9e30cbb1254c73f13e86fdd0dd1c2678ae65` |
| `AIES42INV.zip` | 2,830 | `ad2345d73371f99765d21939e9806be8f14eea71238384877783e5c256406013` | 1,230 | `4bf0980bc5c9554ff5e16c22667ad760f4b2c0c367a2febb3dff38db615d03b2` |
| `AIES44INV.zip` | 4,081 | `07965c9360d6a918c7f8214e45d14d3da8170c84b394d090c701e3a6c78d7d52` | 1,231 | `9370168caa9479a6d65c55f755539ac13b4168015a6900c86d66f2f51f3abb36` |
| `AIES51INV.zip` | 1,674 | `33aec64ddc61cc1bb59622c3b87bed96b4e27553453ebe8ef3df47829dc7d774` | 1,231 | `d97dbb926c54deabad9e3dc1a185e78476f56bc8b9d51065ba10edc8d1287f74` |
| `us_state_6digitnaics_2022.txt` | 56,000,447 | `6f7b2f2b14cbad9dbfeb31d3bfc9f729368a0e971727de4eda88c9f83f77a513` | 1,192 | `6a67f504eb580e668e58ad2179ab68e54e0dca83f6844a19e5facc0452200092` |

The raw headers reported HTTP/2 200, `application/zip` for AIES and
`text/plain` for SUSB, with Content-Length equal to the local body size. Those
header bytes include transient intermediary fields. Their exact hashes are
preserved, but their semantics are explicitly unauthenticated.

The parser accepts one canonical absolute source directory containing exactly
the six basenames above and their six adjacent `.headers` files—no extras. It
does not accept caller hashes, alternate profiles, URL overrides, future
bindings, or a source-verification switch.

## Physical layouts

Every AIES archive has exactly three ordered, case-exact members: `.dat`,
`_FIELDS.txt`, and `_README.txt`. All entries use Deflate method 8, flags
`0x0808`, DOS creator system 0, no attributes/extra/comment, and their frozen
CRC, compressed size, uncompressed size, timestamp, and member SHA-256. The
parser does not extract them. It rejects prefixes, suffixes, ZIP64, encryption,
unsafe/colliding names, topology drift, CRC failure, and expansion outside the
closed ceilings.

All 15 inner AIES members are ASCII, BOM-free, NUL-free, LF-only, and
terminal-LF. DAT is unquoted pipe-delimited. Its first field has exactly one
leading `#`; the companion FIELDS order must equal the normalized DAT header.
Observed DAT row counts are 1,279, 648, 45, 72, and 8. `GEO_LABEL` corresponds
to logical `NAME`; `GEOTYPE` and, where present, `ST` are retained physically
but omitted from the logical topology. Raw fields, case, flags, signs, blanks,
and order are never normalized.

SUSB is strict Windows-1252, not UTF-8. Byte `0x92` occurs exactly 1,324 times.
It is BOM/NUL/CR-free, LF-only, terminal-LF, and canonical minimal-quote CSV.
The parser reproduces and hashes that CSV serialization. It has exactly 14
physical columns and 570,105 rows. Physical `EMPLFL_R` is absent; the
provisional topology records an explicit absent-column insertion rather than
claiming the provider supplied an empty column.

The physical-to-logical SUSB size map is exact and label-bound:

```text
01→01  02→02  03→03  26→04  33→05
34→06  35→07  37→08  36→09
```

No missing size row is synthesized or zero-filled. All rows remain in the
full retained table; the `STATE=00`, logical-size-`01` projection is separately
hashed and explicitly nonadmitted.

## First-class logical incompatibilities

The physical lexemes and provider placement are distinguished from the
accepted contract's semantics. Provider flag meanings are not inferred from
local bytes.

| AIES source | Incompatible rows | Preserved reasons |
| --- | ---: | --- |
| AIES00 | 242 / 1,279 | 20 `NAICS_F=805` rows; 402 CV-flag occurrences outside the accepted CV vocabulary |
| AIES31 | 302 / 648 | 74 value-flag `v/w` occurrences; 402 CV-flag `D/N/S/Z` occurrences; 46 negative CV rows |
| AIES42 | 34 / 45 | 5 `NAICS_F=805` rows; one value-flag `v`; 71 incompatible CV-flag occurrences |
| AIES44 | 57 / 72 | 38 value-flag `v/w` occurrences; 22 incompatible CV-flag occurrences; 14 empty accepted dimensions across 13 rows |
| AIES51 | 2 / 8 | three value-flag `v` occurrences across two rows |

The output binds a deterministic first row/key/field/raw-lexeme exemplar and
both occurrence and affected-row counts for each mismatch. It does not discard
`805`, reclassify `v/w`, erase uppercase CV flags, take absolute values, or fill
aggregate dimensions. AIES31 reserve value/CV signs are preserved. AIES51
component addition is not imposed: only 2 of 8 observed rows sum exactly.

SUSB contains 86,416 `(STATE,NAICS)` groups and 74 membership patterns. Only
29,151 groups contain all nine logical size rows; 57,265 do not. The parser
records this as a contract incompatibility. Size-row counts are:

```text
01=86416 02=71753 03=56896 04=51982 05=78138
06=54427 07=38267 08=83011 09=49215
```

All observed SUSB measure flags are `G`, `H`, or `J`; no blank, `S`, or `D`
occurs. Wherever all operands exist, raw integer arithmetic satisfies the
three overlap identities. Under the accepted semantics, FIRM and ESTB are
eligible for exact identity claims, while EMPL, PAYR, and RCPT remain
unverifiable noise-flag states even though their raw arithmetic matches.
FIRM is never summed across NAICS. Its exact ceiling remains
`PROHIBITED_MULTI_INDUSTRY_ENTERPRISE_DOUBLE_COUNT_RISK`, and its model role
remains
`INDUSTRY_FIRM_PRESENCES_PROXY_ONLY_PENDING_VALIDATED_ALLOCATION_OR_DEDUPLICATION_ONTOLOGY`.

All sector-detail AIES total-inventory fields, raw flags, CVs, and CV flags
match AIES00 exactly: 648/648 manufacturing, 45/45 wholesale, 72/72 retail,
and 8/8 information rows.

## Local safety and replay

The source directory must be private, canonical, nonsymlinked, and owned by
the current user. Every leaf must be a distinct, single-link, non-group/world-
writable regular file. Reads use directory-relative `O_NOFOLLOW`, byte caps,
pre/post `fstat`, entry-identity checks, and a stable directory snapshot.
These controls reduce path/link/race ambiguity; they do not establish custody
against the local user, operating system, or storage stack.

Row and key hashes use schema-tagged, field-name-and-value byte-length framing.
Order, full projected-row membership, and key membership are hashed separately.
The SUSB national code-01 projection is linked separately to the full result.
Every source derivative and the cross-AIES derivative is frozen in the
self-hashed profile. Result validation first requires that the supplied bytes
already equal the one exact canonical JSON serialization, then rebuilds all six
sources and compares canonical bytes exactly. Leading/trailing whitespace,
CRLF, alternate key order/spacing, duplicate keys, output restamping, and
semantic replay decoys fail closed.

## Running

From the repository root:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 \
  scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/census_structural_present_day_physical_profile_v1.py \
  --source-directory /private/tmp/census-structural-physical-audit.dZRm93
```

Run the adversarial suite from both the repository root and an unrelated
working directory:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 \
  scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/test_census_structural_present_day_physical_profile_v1.py

cd /private/tmp
PYTHONDONTWRITEBYTECODE=1 python3 \
  /absolute/path/to/test_census_structural_present_day_physical_profile_v1.py
```

The tests cover self/dependency pins, immutable-state poisoning, exact integer
typing, duplicate/nonfinite JSON, source/body/header mutation and mix-match,
result replay/restamping, provenance-claim restamping, extra/missing/relative/
alias/symlink/hardlink/FIFO paths, ZIP prefix/suffix/duplicate topology, AIES
physical mismatches, SUSB Windows-1252/header/size-map/duplicate decoys, overlap
identities, projection separation, and all-false gates.

Passing tests do not self-accept this profile. A fresh independent read-only
audit of the final frozen bytes is required.
