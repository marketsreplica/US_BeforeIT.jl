# Census inventory release-profile mechanics v1

Status: **permanently nonadmitting `CANNOT_RUN`; present-day schema
diagnostics only**.

This isolated, standard-library-only package implements a real OOXML parser
for the five Census inventory workbook profiles frozen in
`prospective_2026q3_contract_v2.toml`. It does not download a workbook, store a
raw body, authenticate Census, establish provider provenance or custody,
qualify a prospective capture, or authorize any model, scoring, promotion, or
production use.

The checked-in JSON is a small, self-hashed structure derivative. Its current
workbook observations were made on 2026-08-08 from five caller-supplied local
bodies. Those observations are neither future-layout promises nor evidence
that the bodies came from Census. A later planned capture must supply five new
external bodies plus a self-hashed local binding, and even a successful parse
remains nonadmitting.

## Frozen five-profile plan

The module and JSON bind the full selector strings byte-for-byte to the frozen
v2 contract. The required topology is exactly:

| Profile | Event and window (UTC) | Mutable URL |
| --- | --- | --- |
| M3 2026-08 full, Table 6 stages | `census_m3_2026_08_full`; 2026-10-02 14:00--14:15 | `https://www.census.gov/manufacturing/m3/prel/table6p.xlsx` |
| MWTS 2026-08 adjusted inventory and ratio | `census_mwts_2026_08`; 2026-10-08 14:00--14:15 | `https://www.census.gov/wholesale/xls/mwts/timeseries1.xlsx` |
| MWTS 2026-08 not-adjusted inventory and ratio | `census_mwts_2026_08`; 2026-10-08 14:00--14:15 | `https://www.census.gov/wholesale/xls/mwts/timeseries2.xlsx` |
| MRTS 2026-08 inventory and ratio | `census_mrts_inventory_2026_08`; 2026-10-15 14:00--14:15 | `https://www.census.gov/retail/mrtsinv/www/mrtsinv92-present.xlsx` |
| M3 2026-09 advance total | `census_m3_2026_09_advance`; 2026-10-27 12:30--12:45 | `https://www.census.gov/manufacturing/m3/adv/tabletm.xlsx` |

The URLs are mutable locations, not content identities. Source verification is
always on: observed-current mode requires the five frozen diagnostic SHA/size
pins below, while planned-local mode requires the exact URL, event window,
HTTP status, content type, raw SHA, and byte count in the self-hashed local
binding. There is no verification-disable parameter. Caller assertions and
local hashes do not authenticate transport, provider, time, origin, or custody.
Result records therefore distinguish three facts: the declared URL matches the
frozen contract, planned caller URL fields passed their local validation, and
the local body matched its hash/size pin. Body-to-URL provenance and provider
provenance remain explicitly false in both modes.

## Present-day diagnostic observations

The external bodies are deliberately not checked in:

| Workbook | Observed reference | SHA-256 | Bytes |
| --- | --- | --- | ---: |
| M3 `table6p.xlsx` | 2026-06 full report | `f4b6be3579da9efea2d9065ddfc1d5178f032f9a8a9a342504ee818741718904` | 35,835 |
| MWTS `timeseries1.xlsx` | 2026-06 | `4bcb167e1ff904dbccfc00de14e4bf0d4a0a4d77f3d74c46c8f28a6333f8a44d` | 182,382 |
| MWTS `timeseries2.xlsx` | 2026-06 | `232a178c7363cd64b5fd4eec54cc471316ef1af87842b9f9f2b28e69ca47fc20` | 192,478 |
| MRTS `mrtsinv92-present.xlsx` | 2026-05 | `b8cd273c22cb1cf88bcf2ea5cde31d6524a418c089c9f47dd3c8e2cef752c122` | 245,266 |
| M3 `tabletm.xlsx` | 2026-06 advance report | `492388f139b73e4a6495e071d11912d80acef1ab9352e157e383b48a08f3be44` | 20,001 |

These are local fixity facts for the supplied bytes only. They are not
publisher signatures, download receipts, future content pins, or origin
evidence.

## Exact parsing surface

The package validates ZIP signatures, CRCs, member count and size bounds,
compression ratios, safe case-unique member paths, regular-file path identity,
content types, a closed internal relationship graph, reachability of every
substantive part, and exact workbook-to-worksheet bindings. Every XML package
part, including properties, themes, relationships, and content types, is
identified from its resolved OPC MIME type rather than its filename suffix and
must be strict BOM-free UTF-8 before parsing. Every allowed relationship type
also requires its exact expected target MIME type, and every relationship part
requires the exact OPC relationships MIME rather than a suffix-only inference.
DTDs, entity declarations, non-declaration processing instructions, and
forbidden control characters fail closed. The parser also forbids external
relationships, macros and embedded objects, formulas, errors, inline strings,
unsupported cell types,
duplicate/out-of-order cells, cells outside declared dimensions, unreferenced
shared strings, and non-finite JSON. Numeric policy uses manual ASCII lexical
predicates; no persistent regular expression or mutable collection carries
policy state.

Every input path must be an absolute, canonically spelled, single-link regular
file with no symbolic-link component. Reads pin device, inode, size, and
modification time before and after the read. The five workbooks must be distinct
files and distinct byte bodies. Results carry a canonical content hash, but
validation always reparses the exact external bodies and type-exactly compares
the rebuilt result. Rehashing or restamping a modified result cannot replace
replay.

The selected workbook mechanics are:

- M3 full requires the exact 15-sheet topology, `Table 6` title/unit/header,
  source note, three stage blocks, and the same 24-industry axis in each block.
  Stage values are exact nonnegative integers for SA and NSA. `total` is
  explicitly labelled as a derived exact sum of the three published stage
  cells; it is not misrepresented as a published Table 6 cell.

- M3 advance requires the sole `Total mfg` sheet, Table 2 title/unit/header,
  all 14 published rows, row 54 as total manufacturing, and the month-bound
  source note. The current workbook does not explicitly establish stock timing
  or price-adjustment semantics, so `selector_metadata_complete` is false.

- MRTS requires sheets `2026` through `1992` in exact order and the exact 2026
  title, month axis, four blocks, and nine-row NAICS/label universes. Inventory
  cells are exact integers; ratios are canonical exact decimal strings. The
  notes establish end-of-month stock, SA/NSA meaning, current-dollar units, and
  no price adjustment. The frozen US selector is retained, but US geography is
  not literal workbook text and is reported as not explicit.

- Each MWTS profile requires its exact sheet topology and the selected
  `Inventories` and `Inventories to Sales Ratios` sheets. It binds titles,
  units, preliminary/revised markers, the 22-column NAICS/description universe,
  and every monthly row back through 1992-01. Inventories are exact integers,
  ratios are canonical decimal strings, and historical `NA` is a typed source
  state rather than zero. Current adjusted notes explicitly support the
  adjustment and no-price-change semantics. The current not-adjusted workbook
  does not explicitly state the no-price-change semantic, so its selector
  metadata remains incomplete. US geography is also not literal workbook text.

None of these mechanics elevates the result above
`PRESENT_DAY_SCHEMA_DIAGNOSTIC_NONADMITTING`. Every origin, provider-
provenance, transport, custody, policy, qualified-dispatch, model-input,
forecast, truth, scoring, accuracy, promotion, production, and readiness gate
is hard false at both bundle and record level.

## Offline use

Run the hermetic/adversarial suite from the worktree root:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest -v \
  scripts/us/forecasting/vintages/census_inventory/release_profile_v1/\
test_census_inventory_release_profile_v1.py
```

From an unrelated directory, invoke the test file directly by absolute path;
this avoids `unittest` treating the dotted worktree ancestor as a module name:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -B \
  /absolute/worktree/scripts/us/forecasting/vintages/census_inventory/\
release_profile_v1/test_census_inventory_release_profile_v1.py
```

The suite creates only temporary synthetic fixtures and tampered copies. If
the caller-supplied diagnostic directory exists, it also reparses the five
external present-day bodies and checks representative published and derived
values plus exact replay.

Observed-current CLI output is canonical JSON on standard output only:

```sh
python3 -B /absolute/worktree/scripts/us/forecasting/vintages/\
census_inventory/release_profile_v1/census_inventory_release_profile_v1.py \
  --mode observed-current \
  --m3-full /absolute/path/m3_table6p.xlsx \
  --mwts-adjusted /absolute/path/mwts_adjusted.xlsx \
  --mwts-not-adjusted /absolute/path/mwts_not_adjusted.xlsx \
  --mrts /absolute/path/mrts_inventory.xlsx \
  --m3-advance /absolute/path/m3_tabletm.xlsx
```

Planned-local mode uses the same five absolute workbook arguments plus
`--mode planned-local-binding --binding /absolute/path/binding.json`. The
binding must contain exactly five ordered records with the frozen profile,
requirement, event, reference period, timestamps, and URLs; exact HTTP 200 and
XLSX content type; an effective URL equal to the frozen URL; raw SHA and byte
count; a retrieval timestamp inside the 15-minute window; and the literal
non-authenticating claim defined by the module. It remains caller-supplied
metadata, not a capture implementation or receipt.

## Frozen replacement candidate

| Artifact | SHA-256 |
| --- | --- |
| module | `8633647b13b3e795b3d09f1e6503b00b381753c788e12cb5d5e1428b62841788` |
| profile physical | `b0a422598a4a59856268c63c8f6f707865dd093f6953db5d2253a6570200c463` |
| profile semantic | `abf4cb63dd4bfc7ce53d052bc58f66a5e2fbf21eaab10d5a5d19a8fb0b5e00c7` |
| tests | `0229618cdb3631387001a43d07cea5d3a4b8693d8b80df94b5397e406aa477fe` |

These identities designate a replacement candidate submitted for independent
read-only audit. They are not self-acceptance, qualification, or permission to
write raw data, receipts, inventory, forecast artifacts, scores, or production
state.
