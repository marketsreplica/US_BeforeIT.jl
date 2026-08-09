# Classification maps present-day physical profile v1

This isolated Python-stdlib package verifies the physical OOXML layout of six
exact, externally held classification workbook bodies. It emits a deterministic,
self-hashed derivative to standard output. Its permanent status is `CANNOT_RUN`:
zero of the six prospective logical profiles are physically qualified, and every
origin, model, forecast, truth, scoring, promotion, and production gate remains
false.

The derivative is layout evidence only. A matching byte count and SHA-256 prove
local fixity against the pins below; they do not authenticate a provider, URL,
transport, custody chain, or publication origin. The workbooks remain outside
the repository. No temporary audit filename is represented as an official
publisher filename.

## Exact profile scope

The six prospective profile identifiers are preserved exactly:

1. `bea_summary_codes`
2. `bea_industry_commodity_naics_concordance`
3. `beforeit_bea71_model_bridge`
4. `naics_2017`
5. `naics_2017_to_2022`
6. `naics_2022`

The accepted offline logical-profile pins are:

- module: `f5890e959dc80c8fdda1507d73dba3658d4fa5720daaa3adc7cfb8e64732cfb1`
- profile bytes: `abef7ace9ecc5799a0f09c060a3ee6371e45330b2d6dbac21a09c3b6f97598f8`
- profile semantic hash: `1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992`
- tests: `4237ec1aba9dfd89d0d63c1995c3c20aa557bed3f42e275bf1eeb20764763dff`

The repository-local `scripts/us/bea71.toml` receipt is also checked at 8,146
bytes and SHA-256
`2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f`.
That receipt is repository-authored fixity evidence, not official BEA origin
evidence.

## External diagnostic bodies

| Diagnostic object | Official planned filename | Local audit transport label | Bytes | SHA-256 |
|---|---|---:|---:|---|
| 2024 Summary Use | `IOUse_After_Redefinitions_PRO_Summary.xlsx` | same | 1,163,798 | `9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7` |
| 2024 Summary Make | `IOMake_After_Redefinitions_PRO_Summary.xlsx` | same | 598,989 | `073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6` |
| BEA concordance | `BEA-Industry-and-Commodity-Codes-and-NAICS-Concordance.xlsx` | `bea.xlsx` | 61,081 | `6e25267ff60ccedc0808c14153b0cdeb566a7f5e9097536c70c2b9694ef5ff47` |
| NAICS 2017 structure | `2017_NAICS_Structure.xlsx` | `naics2017.xlsx` | 95,610 | `662b5a2bdff10938997acd7f59f84331527d6f06ff24d5533331581a00a94aad` |
| 2017-to-2022 concordance | `2017_to_2022_NAICS.xlsx` | `conc.xlsx` | 59,656 | `4662cc7ed9e7f3fb8a968e9504a7d06e448f5b65a349996a5627439df193eb30` |
| NAICS 2022 structure | `2022_NAICS_Structure.xlsx` | `naics2022.xlsx` | 88,218 | `217c9e0d4d74e7517bc288f5f308b73aa0de5ee787976a6dd222412be28ada22` |

The profile intentionally contains no source URL. Only the supplied body bytes,
their hashes, and physical package evidence are bound.

## Physical findings and incompatibility

The 2024 Use and Make workbooks each expose 71 ordinary industry pairs and 73
commodity pairs. Their 71 ordinary code/title pairs agree exactly between Use
and Make. The physical special-account order, however, is `Used, Other`; the
accepted logical profile requires `Other, Used`.

The published titles also differ at the physical projections:

- Use `Used`: `Scrap, used and secondhand goods`
- Use `Other`: `Noncomparable imports and rest-of-the-world adjustment [1]`
- Make `Used`: `Scrap, used and secondhand goods /1/`
- Make `Other`: `Noncomparable imports and rest-of-the-world adjustment /2/`

The parser preserves those cells, styles, coordinates, shared-string indexes,
and exact text. It does not reorder them to fit the logical contract. The result
therefore sets `logical_profile_compatible=false` and
`successor_requirement=VERSIONED_LOGICAL_SUCCESSOR_REQUIRED`.

The BEA concordance is one sheet, `A1:N510`, with 499 data rows at 6:504. Its
five hierarchy columns are Sector, Summary, U. Summary, Detail, and GO Detail.
It has no explicit per-row Industry-versus-Commodity axis, so this parser does
not invent one. The four terminal rows remain ordered `Used`, `Used`, `Other`,
`Other`; these are BEA commodity accounts and are never treated as NAICS codes.

The parser also preserves two easy-to-lose BEA details:

- `N5:N504` contains 500 explicit style-8 shared-string cells whose raw value is
  index `1152`; the final shared string decodes to the empty string. A separate
  artifact renderer displayed these cells misleadingly as the number `1152`.
- BEA Summary titles for codes `481`, `482`, and `485` have respectively two,
  one, and one trailing spaces. The 2024 Use/Make titles do not. Code order is
  equal; ordinary title bytes are not fully equal across these sources.

NAICS 2017 contains 2,196 semantic rows and 19 explicit separator rows. NAICS
2022 contains 2,125 semantic rows and 19 separators. Range codes such as
`31-33`, `44-45`, and `48-49` stay strings. The 2017-to-2022 concordance is
strictly directional, contains 1,150 unique ordered pairs, 1,057 source codes,
and 1,012 target codes. Its row cardinalities are 928 one-to-one, 5 one-to-many,
120 many-to-one, and 97 many-to-many. Reversing the concordance in place is
forbidden.

The concordance contains 19 exact space-valued cells beyond column D, including
two spaces at `I238`, plus eight distinct styled blank cells at `F111:F113` and
`F1021:F1025`. Both physical classes are retained.

Across all six workbooks there are zero cell formulas and zero error cells. That
does not mean every formula-like package string is absent: the BEA workbook has
three stale defined names whose text is `#REF!` and one filter defined name that
contains `#REF!`. They are preserved as inert defined-name text and never
executed or silently relabeled as cell formulas.

## Parser boundary

The implementation uses only Python 3.11+ standard-library modules. It checks:

- canonical absolute paths, every path component, `O_NOFOLLOW` where available,
  regular-file type, a single hard link, and pre/post device, inode, size, mode,
  link count, mtime, and ctime;
- exact source size and SHA-256 with no public verification bypass;
- EOCD-at-EOF, single-disk non-ZIP64 topology, contiguous ordered local records,
  matching central/local names and metadata, no data descriptors, safe
  case-unique names, closed compression and size bounds, CRC/decompression, and
  exact observed alignment-padding extras;
- document-order ZIP member, CRC, compression, flag, size, attribute, payload,
  and local-extra metadata;
- BOM-free strict UTF-8 XML, XML 1.0 scalar validity, raw `]]>` rejection,
  DTD/entity/nondeclaration-PI rejection, and element/depth/attribute bounds;
- content-type-driven XML preflight even when an XML MIME part lacks an `.xml`
  suffix, exact relationship-part MIME, exact relationship-type-to-target-MIME,
  internal-only targets, reachability, and workbook relationship resolution;
- shared-string rich runs without trimming, explicit blank cells, cell order,
  coordinates, styles, raw numeric lexemes, formulas, errors, and dimensions;
- strict UTF-8 canonical JSON, duplicate member names after JSON decoding,
  nonfinite-number rejection, exact recursive JSON concrete types, self-hashes,
  and complete source replay for derivative validation.

The stable-read checks reduce pathname replacement races but do not authenticate
storage against a same-user adversary with concurrent write access. Python code
execution can also replace module globals or functions; reloading frozen bytes
is the recovery boundary. Local hashes and transport labels remain unauthenticated
fixity assertions.

The spreadsheet skill was followed for this task. In this candidate runtime,
two bundled workspace-dependency discovery attempts returned no runtime, so the
spreadsheet artifact tool could not be used as candidate evidence. Raw OOXML was
verified directly, and an independent read-only stdlib audit rederived the
critical counts and hashes. Any artifact rendering obtained elsewhere is
corroborative only and is not part of this candidate's evidence chain.

## Usage

The CLI writes one canonical JSON derivative to standard output and performs no
filesystem write:

```sh
python3 scripts/us/forecasting/vintages/classification_maps/present_day_physical_profile_v1/classification_maps_present_day_physical_profile_v1.py \
  --bea-summary-use /absolute/path/IOUse_After_Redefinitions_PRO_Summary.xlsx \
  --bea-summary-make /absolute/path/IOMake_After_Redefinitions_PRO_Summary.xlsx \
  --bea-concordance /absolute/path/bea.xlsx \
  --naics-2017 /absolute/path/naics2017.xlsx \
  --naics-concordance /absolute/path/conc.xlsx \
  --naics-2022 /absolute/path/naics2022.xlsx
```

`--validate-result /absolute/path/result.json` still requires all six source
arguments. Validation rebuilds the result from the exact workbooks and compares
every canonical byte; a self-rehashed result alone is insufficient.

Run the test suite from the repository root and an unrelated directory:

```sh
CLASSIFICATION_MAPS_PHYSICAL_AUDIT_DIR=/absolute/path/to/four-audit-workbooks \
CLASSIFICATION_MAPS_SUMMARY_AUDIT_DIR=/absolute/path/to/summary-workbooks \
PYTHONDONTWRITEBYTECODE=1 \
python3 scripts/us/forecasting/vintages/classification_maps/present_day_physical_profile_v1/test_classification_maps_present_day_physical_profile_v1.py

cd /private/tmp
CLASSIFICATION_MAPS_PHYSICAL_AUDIT_DIR=/absolute/path/to/four-audit-workbooks \
CLASSIFICATION_MAPS_SUMMARY_AUDIT_DIR=/absolute/path/to/summary-workbooks \
PYTHONDONTWRITEBYTECODE=1 \
python3 /absolute/path/to/scripts/us/forecasting/vintages/classification_maps/present_day_physical_profile_v1/test_classification_maps_present_day_physical_profile_v1.py
```

The exact-body integration tests skip only when the external workbooks are not
present; all synthetic adversarial tests remain runnable. No Julia source exists
in this isolated artifact, so Runic is not applicable.

For the six pinned audit bodies, the frozen generator module SHA-256 is
`f562825dd5985f889de89597103bc840f4fb27d362054a935951f85882f7bc7a`.
It emits 7,079,600 canonical bytes with physical SHA-256
`c39a22dcc2ffe6bd23a93185ddde082c3ee08b79c6ba6eda81fb7ccacc6f0d85`
and derivative content SHA-256
`54b79027ff55717910024b22693540f0aa20580b29dd6b52e9fb4c670600ee0c`.
The physical profile is
`57eefdcb3421a5f63ec8214b6c55feb0700fda4018340ea584863e55f89398fc`
with semantic SHA-256
`aad29e6493ab7d0d03e2da32b9be36ce1632ecce8bdf920c7bd3888454ac1147`.
These identities describe the candidate submitted for independent audit; they
are not an acceptance decision.
