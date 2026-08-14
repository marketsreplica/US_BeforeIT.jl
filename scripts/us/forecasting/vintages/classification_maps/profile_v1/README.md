# Offline classification-map profile v1

This directory is an isolated, standard-library-only parser and object-set
contract for the six `classification_maps` profiles. Its permanent status is
`CANNOT_RUN`. It proves only synthetic parser mechanics plus exact fixity and
schema replay of the repository-local `scripts/us/bea71.toml` mapping.

It does **not** contain an official workbook body, a current-origin capture, a
provider-layout witness, or an admission receipt. Consequently all six
profiles remain physically unqualified, every origin/model/forecast/scoring
gate remains false, and the only allowed claim ceiling is:

`OFFLINE_SYNTHETIC_PARSER_AND_LOCAL_FIXITY_RECEIPT_ONLY_NO_OFFICIAL_BODY_OR_CURRENT_ORIGIN`

## Closed six-profile set

| Profile | Object geometry | Offline contract |
|---|---|---|
| `bea_summary_codes` | shared projection over the 2024 producer-price summary-use and summary-make objects | require the exact known 71-industry axis, 71 ordinary commodity codes plus `Other` and `Used`, and byte-for-byte-equivalent parsed use/make axis rows |
| `bea_industry_commodity_naics_concordance` | one planned official BEA workbook | preserve ordered BEA-axis/code/title to NAICS-code/title pairs and derive direction-aware cardinalities |
| `beforeit_bea71_model_bridge` | one exact repository-local TOML object | hash and strictly replay the complete project-authored model, retail, QCEW, SUSB, fixed-asset, and special-construction schema without calling it official |
| `naics_2017` | one planned official Census workbook | preserve the ordered hierarchy, level, code/range, title, note, and explicit blank fields |
| `naics_2017_to_2022` | one planned official Census workbook | preserve only the registered 2017-to-2022 direction and derive one-to-one, one-to-many, many-to-one, or many-to-many cardinality from the complete ordered pairs |
| `naics_2022` | one planned official Census workbook | preserve the ordered hierarchy, level, code/range, title, note, and explicit blank fields |

The catalog therefore has seven logical objects: six planned official
workbooks and one repository-local TOML mapping. The first profile projects
two existing shared-parent objects instead of inventing a seventh official
classification workbook. Its parent bindings are the accepted
after-redefinitions profile
`57c71a1d9a1a8f4ecad7fbc4dbc284590792aa3b2966388bf138397dc0e10d11`
and member hashes:

- summary producer-use:
  `9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7`;
- summary producer-make:
  `073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6`.

Those are nonprospective parent identities, not replayed bytes or proof of a
current-origin capture in this candidate.

## Input boundary and fixture non-attribution

`validate_object_set` accepts exactly six ordered `Pair`s for the planned
official workbook objects. Every value must have exactly four fields:

- `fixture_kind = "SYNTHETIC_OOXML_PARTS"`;
- `fixture_origin = "SYNTHETIC_NO_URL_ATTRIBUTION"`;
- the exact OOXML media type; and
- an ordered three-part byte vector containing synthetic `workbook.xml`,
  workbook relationships, and one worksheet.

The fixture wrapper cannot contain `url`, `requested_url`, `effective_url`, or
another extra member. Result manifests explicitly set both
`planned_locator_attributed_to_fixture=false` and
`official_body_claimed=false`. The profile records future planned locators,
but no supplied synthetic byte is ever attributed to one of them.

The synthetic XML is deliberately a closed parser fixture, not a claim about
the physical layout of any official workbook. It requires one worksheet named
`ClassificationMap`, inline strings, explicit cells for blanks, consecutive
row/cell coordinates, and exact synthetic headers. Production work still
requires the complete official ZIP/OOXML bytes, all members and relationships,
actual sheet/layout discovery, current-origin receipts, and independently
accepted leaf verification.

The local bridge is different: `validate_object_set` reads the one frozen
repository path itself, verifies its source pin, parses its exact TOML bytes,
and emits a local fixity receipt. There is no public parameter that can supply
replacement bridge bytes or disable source verification.

Every pinned local source is resolved without symbolic path components or hard
links, opened as a regular single-link file, and read twice through the same
handle. The reader compares path and handle device/inode identity, mode, link
count, size, modification/change timestamps, exact bytes, and SHA-256 before
and after the replay read, then resolves and checks the path again. These checks
detect observable local replacement or concurrent mutation; they are not an OS
security boundary against a malicious same-user process able to race and undo
changes between observations. This offline candidate therefore makes no
race-free custody, authentication, or adversarial-host claim.

## Preserved semantics

The parsers return every selected source field instead of reducing a mapping
to a dictionary:

- physical row ordinal and exact source order;
- BEA or NAICS source and target codes as strings, including `31-33` and
  `44-45` range codes;
- source and target titles;
- notes, including explicit empty strings;
- registered direction; and
- source-target and target-source counts plus the derived cardinality class.

Reversing column headers does not construct an inverse. A future inverse must
be a separately named derivation from the accepted complete forward mapping.
The BEA cardinality calculation keeps Industry and Commodity mappings in
separate namespaces, so a NAICS target appearing on both axes is not silently
treated as a cross-axis many-to-one relation.

`Other` and `Used` are accepted only at the end of the BEA commodity axis with
`account_kind = "BEA_SPECIAL_ACCOUNT_NON_NAICS"`. Either exact token in a BEA
concordance NAICS field, a Census structure code, a Census concordance code,
or a QCEW/SUSB bridge-code list fails as
`special_account_as_naics`. The word “Used” remains legal inside a title; the
rule is semantic-field-specific rather than a lexical ban.

## Repository bridge receipt and order witness

The local bridge remains exactly:

- path: `scripts/us/bea71.toml`;
- bytes: 8,146;
- SHA-256:
  `2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f`;
- model code count: 68; and
- sector-table count: 68.

The two code lists have the same unique set but not the same physical order.
`model.codes` places `4A0` at position 36, while the `[[sector]]` array places
it at position 28; positions 28 through 36 therefore differ. The parser
preserves both exact orders and emits
`sector_order_differs_from_model_codes=true` with difference positions
`28:36`. It does not normalize, sort, or conceal the distinction. This is
project-authored mapping evidence, not an official BEA/Census concordance and
not a prospective evidence receipt.

## Fail-closed checks

The profile is self-hashed with typed, length-aware canonicalization after
removing only `artifact.content_sha256`. The module also freezes the physical
and semantic profile hashes. Every call verifies eight exact repository source
pins; no `verify_sources=false` overload or keyword exists.

The object-set and replay checks reject, among other attacks:

- missing, extra, duplicated, or reordered objects and OOXML parts;
- extra fixture members that could attach a URL;
- non-byte part payloads and byte/row/column/cell caps;
- malformed UTF-8, BOMs, invalid XML 1.0 scalars (including literal or
  referenced U+FFFE), raw `]]>` character data, declarations, DTDs, unsupported
  entities, processing instructions, duplicate attributes, path-traversing
  relationships, multiple roots, unclosed tags, formulas/rich text, wrong cell
  types, duplicate or reordered coordinates, implicit blanks, and row-width
  drift;
- unknown/reordered headers, non-ASCII or malformed code grammars, integer
  type confusion, Boolean-as-integer values, duplicate codes/rows, conflicting
  titles, gaps in ordinals, and wrong NAICS levels;
- reversed BEA or Census concordance headers;
- coordinated use/make axis changes;
- `Other` or `Used` in a NAICS-bearing field;
- TOML duplicate keys, unknown/missing bridge tables or members, changed model
  or sector code order, duplicated auxiliary codes, and invalid fixed-asset
  line types; and
- self-rehashed compiled results with cleared blockers, `READY`, a true gate,
  synthetic URL attribution, fabricated qualification, or a reversed
  direction; and
- canonicalization-collision type substitutions, including `Int` to `Int128`,
  vector to tuple, changed vector element type, Boolean/float-for-integer, and
  narrower integer attacks.

`validate_compiled_result` recomputes the complete result from the supplied
ordered synthetic objects and the exact local source. It performs recursive
type-exact replay before any digest validation, so canonical byte equivalence
cannot hide a Julia container or scalar type change. A result self-hash alone
is insufficient. Returned arrays and dictionaries are fresh, so caller
mutation cannot change later validation policy or results.

## Permanent blockers

Every successful synthetic replay returns all of these blockers:

1. missing official 2024 BEA summary-use body;
2. missing official 2024 BEA summary-make body;
3. missing official BEA industry/commodity-NAICS concordance body;
4. missing official NAICS 2017 structure body;
5. missing official 2017-to-2022 NAICS concordance body;
6. missing official NAICS 2022 structure body;
7. unverified provider physical layouts;
8. missing current-origin receipts;
9. missing publisher authentication;
10. missing prospective receipt for the repository-local bridge; and
11. no accepted classification-map leaf integration with common-origin v4.

Thus the result remains 0/6 physically qualified even when all synthetic
parser tests pass. It authorizes no request, raw capture, inventory update,
origin admission, model mapping, forecast, truth access, scoring, or
production action.

## Verification

Run the strict suite from the repository root:

```bash
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/classification_maps/profile_v1/test_classification_maps_profile_v1.jl
```

Run the same suite from an unrelated working directory with absolute paths:

```bash
cd /private/tmp
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/path/to/scripts/us \
  /absolute/path/to/scripts/us/forecasting/vintages/classification_maps/profile_v1/test_classification_maps_profile_v1.jl
```

Both runs pass 172/172 assertions. Runic 1.7.0 `--check` passes both Julia
files. The frozen candidate identities are:

| Artifact | SHA-256 |
|---|---|
| `USClassificationMapsProfileV1.jl` | `4248d329618cb1397e983f0df60d6e9047e5dbf6d4ec4786487cabc63fe5c2a0` |
| `classification_maps_profile_v1.toml` physical bytes | `9bc1934a66adc19d981b89adf81a2d5f3e8c61ba268c6267fcc968eead2423e2` |
| profile canonical semantic identity | `1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992` |
| `test_classification_maps_profile_v1.jl` | `5abc564866bb420c2cff851a68090cebb1d83388f99783a6cb45a96441c11ab2` |

These are local fixity assertions for an authored candidate. Independent
audit is still required before even the narrow offline-mechanics candidate is
accepted; no production trust or physical-source qualification can be
inferred from them.
