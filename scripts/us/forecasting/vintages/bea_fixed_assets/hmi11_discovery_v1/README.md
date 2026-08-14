# BEA Fixed Assets HMI11 discovery mechanics v1

Status: **permanently nonadmitting `CANNOT_RUN`; discovery mechanics only**.

The first candidate was independently rejected. Its module
`7da6084e16b563fecdd0fef3cda81548aafc4d307ee674f39e2690b8e7f8a136`,
profile physical
`271c9768b395caac3e64a72fb86328e9627510833f6c244f4946fc563e3658cf`,
profile semantic
`5e4770c2b38eaf4552290e48b2f37575939650956d02a9672f89aa72dd0b65e3`,
test `5eaf16b144599299fddbb964a4c933208291fcfa69b4fb57fd6cbfdd464c6ced`,
and README
`bad0aa1ecdb62157cb88b52c14d1affbe153d2100432f3f2b01bf4876ed41495`
hashes are historical rejected identities only. They must not be used as
accepted pins or integration evidence.

The first repaired candidate was also independently rejected. Its module
`d61e2a50be40a635521f012e45a020b9e4b6103caf68767e2c7cd36f62e5b82a`,
profile physical
`bda22cb4f50b967ad1464dbd015f21cf4640942acb0407faf99ef55829d84c73`,
profile semantic
`8c1c02d2e5744df6fe2d8d1c23d1dec453b31353134dd7550a507b143cadbdc5`,
test `483aca32609352474797dfada880af264e77d231e094921855483a0c657878d7`,
and README
`92a756d589e8fc6aed97d594fd4a437abfb5abcfe74398e705baf3f4edb28c82`
hashes are also historical rejected identities only. That candidate exposed a
public `verify_sources=false` keyword that could skip every dependency read
and hash while producing an otherwise indistinguishable plan. This candidate
removes that bypass rather than treating the old hashes as valid evidence.

This isolated artifact defines a strict offline parser and a closed eight-profile
selector contract for future BEA Fixed Assets HMI11 metadata discovery. It has
no HTTP client, downloader, workbook parser, capture writer, receipt writer,
inventory mutation, model execution, or scoring path. A successor artifact is
required for every status above `CANNOT_RUN`.

The implementation reads its checked-in TOML profile and pinned local control
files. It can parse caller-supplied in-memory HMI11 metadata response envelopes,
but contains no live requester and reads no BEA workbook, ZIP, TXT, API, or raw
artifact file. All response bodies in the tests are synthetic byte vectors.

## Files

- `USBEAFixedAssetsHMI11DiscoveryV1.jl`: standard-library-only strict JSON,
  HMI11 release selection, path/ID round-trip, case-sensitive file catalog,
  response-envelope lineage, safe official URL derivation, profile validation,
  nonadmitting plan builder, and full plan-replay validator.
- `bea_fixed_assets_hmi11_discovery_profile_v1.toml`: self-hashed closed
  profile, selector mappings, dependency bindings, unresolved claims, and false
  gates.
- `test_bea_fixed_assets_hmi11_discovery_v1.jl`: hermetic synthetic and
  adversarial tests.

The module imports only `Dates`, `SHA`, and `TOML`. The test adds only `Test`.

The exported acceptance surface is limited to `build_discovery_plan`,
`validate_discovery_plan`, `load_profile`, `validate_profile_document`, and the
typed error. URL helpers and result constructors are not exported. Inner
constructors are not an acceptance path: every supplied release is reparsed,
and every supplied result must pass full replay.

Every exported operational profile loader, profile validator, plan builder,
and plan-replay validator mandatorily reads and verifies the complete pinned
source-binding closure. No exported method has a `verify_sources`, injected
verifier, or equivalent bypass keyword. The internal declaration-only binding
checker is separately named, returns no plan, and cannot produce an
interchangeable `DiscoveryPlan`.

## Exact metadata sequence

The module constructs, but never requests, this official route sequence. Each
caller-supplied response must be wrapped in a closed envelope containing only:

- `sequence_index`;
- `response_role`;
- derived `requested_uri`;
- `final_effective_uri`, required by this v1 to equal the derived request URI;
- exact `body::Vector{UInt8}` and reconstructed `body_sha256`;
- `prior_response_body_sha256`;
- `selected_release_internal_path`; and
- `directory_id`.

The four roles are fixed in this order:
`ROOT_DIRECTORY_CATALOG`, `PATH_TO_DIRECTORY_ID`,
`DIRECTORY_ID_TO_PATH`, and `RELEASE_FILE_CATALOG`. The root begins at
`GENESIS`; each later envelope must name the preceding body's hash. The path
and ID fields transition from `NOT_APPLICABLE` to exact values derived from
prior bodies. Response-body hashes may not be reused across roles.

1. Root directory catalog:

   `https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=11&getFiles=false&getDirs=true`

   Exact response fields:

   - `MainName::String`, required to equal `Fixed Asset`
   - `FolderPattern::String`, required to equal
     `FA\dataYear\vintage_NewReleaseDate`
   - `FileArray::Array{String}`

2. Exact path to decimal directory ID:

   `https://apps.bea.gov/histdata/core/data/UrlPath_getID/?UrlPath=<percent-encoded-path>`

   Exact response shape: an array of length one whose record has only `Notes`,
   `Theid`, `Thepath`, and `DescriptionLong`. `Notes`, `Thepath`, and
   `DescriptionLong` must be JSON null. `Theid` must be a positive canonical
   decimal string without a leading zero.

3. Directory ID back to exact path:

   `https://apps.bea.gov/histdata/core/data/getPath/<decimal-ID>`

   Exact response shape: an array of length one with the same four fields.
   `Notes`, `Theid`, and `DescriptionLong` must be JSON null. `Thepath` must
   equal the selected release path byte-for-byte.

4. Exact release file catalog:

   `https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=11&thePath=<percent-encoded-path>&getFiles=true&getDirs=false`

   Exact response fields:

   - `MainName::String`, required to equal `Fixed Asset`
   - `Filearray3::Array{String}`

5. Direct locators are derived only for exact one-level children of the
   selected release. The fixed internal HistData prefix is removed, every path
   component is percent-encoded, and the result is rooted at
   `https://apps.bea.gov/HistData/`.

The requested/final URI, role, order, body hash, path, and ID bindings are
structural checks over caller-supplied bytes and labels. They do not
authenticate the transport labels, prove that BEA returned the body, establish
that a workbook existed, or show that any bytes were available at an origin.
Path equality in the reverse body alone is explicitly insufficient.

## Release grammar and selection

The parser accepts only exact HMI11 paths beneath:

`/Inetpub/wwwroot/website/website/HistData/Files/Releases/FA`

A canonical release has exactly two dynamic path components:

`<four-digit-data-year>\AnnualUpdate_<full-month>-<canonical-day>-<four-digit-year>`

The embedded date must be a valid calendar date and round-trip to the same
canonical spelling. Year-only entries, notes directories, `_notes` labels,
`UND` trees, and special/non-annual labels are excluded. Empty, dot, slash,
control-character, duplicate, and casefold-colliding paths fail closed.

Selection requires an explicit `Date` cutoff. The result is the unique latest
canonical release-label date no later than that cutoff. A tie at the latest
eligible date and a future-only catalog both fail.

An archive label date is not an official intraday availability timestamp.

`ReleaseDirectory` values are never trusted by their field values. Every
boundary reparses `internal_path` under the frozen HMI11 root, folder pattern,
four-digit year grammar, two-component release grammar, and annual-update date
grammar, then strictly compares all five stored fields. An outside path, HMI7
`GDP_and_PI` path, or field-forged otherwise canonical 2098 path fails.

## Workbook catalog boundary

The file parser requires exactly one main XLSX workbook for each of Sections
3, 5, and 7. Identification is case-insensitive solely for recognizing the
closed `Section<section>All_xls.xlsx` filename grammar; the exact observed
filename and locator preserve original case. It rejects:

- casefold-colliding child filenames;
- duplicate, missing, or extra main sections;
- `.xls` in place of `.xlsx`;
- traversal, empty, or noncanonical segments;
- an exact child belonging to any other release; and
- nested children other than excluded notes/`UND` trees.

The selected release is reparsed and all of its fields are compared before
`Filearray3` is inspected. The official locator helper additionally requires an
exact single child of that replayed release. It cannot convert an arbitrary
HistData path, an HMI7 path, or an outside path.

No workbook is opened. A recognized workbook name does not verify sheets,
tables, rows, units, cells, archive bytes, or a content hash.

## Closed v2 profile mapping

The profile exactly reproduces the eight selectors from
`prospective_2026q3_contract_v2.toml` and groups them 3/3/2:

| Section | Profile | Table | Candidate sheet | Required line string |
| --- | --- | --- | --- | --- |
| 3 | `faat301esi_net_stock` | `FAAt301ESI` | `FAAt301ESI-A` | ESI set |
| 3 | `faat304esi_depreciation` | `FAAt304ESI` | `FAAt304ESI-A` | ESI set |
| 3 | `faat307esi_investment` | `FAAt307ESI` | `FAAt307ESI-A` | ESI set |
| 5 | `faat501_residential_net_stock` | `FAAt501` | `FAAt501-A` | `11,12` |
| 5 | `faat504_residential_depreciation` | `FAAt504` | `FAAt504-A` | `11,12` |
| 5 | `faat507_residential_investment` | `FAAt507` | `FAAt507-A` | `11,12` |
| 7 | `faat701_government_net_stock` | `FAAt701` | `FAAt701-A` | `1,21,22,55,79` |
| 7 | `faat703_government_depreciation` | `FAAt703` | `FAAt703-A` | `1,21,22,55,79` |

The ESI set is:

`1,3,4,6,7,8,9,13,16,17,18,19,20,21,22,23,24,25,26,30,33,34,35,36,37,38,39,40,43,49,50,51,52,53,54,55,56,58,59,60,61,63,64,68,69,72,74,75,77,78,79,80,82,83,84,86,87,88,89,91,92,94,95,96`

Every full selector string and its SHA-256 is frozen in the TOML profile. The
candidate sheet names are mappings to test after source-byte acquisition; they
are not claims that a discovered workbook contains those sheets. For every
profile, `sheet_verified`, `contents_verified`, `units_verified`, and
`bytes_verified` remain false, and `raw_sha256` remains `UNRESOLVED`.

## Strict JSON and profile controls

The JSON parser is implemented without `JSON.jl`. It rejects duplicate object
member names after escape decoding at every nesting level, including surrogate
pairs and escaped-name aliases. It also rejects unknown response fields,
invalid UTF-8, unpaired surrogates, controls, invalid number grammar, trailing
bytes, wrong types, and excess body, depth, string, number, array, or object
sizes.

JSON numbers remain `ExactJSONNumber` lexical values; they cannot alias strings
or integers required by the metadata schemas. TOML integer controls explicitly
reject `Bool` and floating-point aliases.

The profile self-hash excludes only `artifact.content_sha256`. The module also
pins the profile's exact physical and semantic identities and validates every
closed field. Recomputing the self-hash after changing a status, gate, source
binding, profile, table, line string, selector, or candidate sheet cannot make
the changed document valid.

The profile additionally freezes that source-binding verification is mandatory
for operational build and replay and that a public bypass keyword is
forbidden. Tests inspect every exported operational method's keyword
declaration, prove a legacy `verify_sources=false` call raises `MethodError`,
and use an additive internal failure probe to prove both public build and
public replay traverse the mandatory verifier. The probe cannot suppress the
subsequent dependency reads; it can only make verification fail earlier in a
synthetic regression.

## Full result replay

`build_discovery_plan` accepts exactly four envelopes plus an explicit cutoff.
`validate_discovery_plan` reloads the pinned profile, reparses all four exact
bodies, rederives every request URI and lineage transition, selects and replays
the release, reparses the workbook catalog, rebuilds all eight profile
mappings, and then strictly compares every field of the supplied plan and all
nested response bindings, workbooks, profile mappings, and gates.

Both operations first verify every physical source pin and every applicable
semantic source pin. This mandatory step is part of operational replay and
cannot be disabled by a caller.

A locally constructed `DiscoveryPlan`, including one labeled `READY` with true
admission gates, is rejected unless it equals the complete replay. The only
true structural flag is `metadata_response_lineage_replayed`; it is not a
transport-authentication, publisher-provenance, capture, availability, or
admission claim. Every model, source-byte, admission, truth, scoring, accuracy,
promotion, and production gate remains false.

## Pinned dependency closure

The profile freezes physical hashes for:

- the prospective-v2 module and contract, plus the contract semantic hash;
- the common-origin-v3 module and policy, plus the policy semantic hash;
- the common-origin parent, profile-receipt, and retention schemas, with each
  physical and semantic hash;
- `current_inventory.toml`, with physical and semantic hashes;
- `scripts/us/Project.toml` and `scripts/us/Manifest.toml`; and
- the local HMI7 discovery module and README used only as mechanics precedent,
  not as HMI11 authority.

The loader resolves these bindings relative to its source directory, so an
unrelated current working directory cannot redirect them.

All listed bindings are read and checked on every exported load, validation,
build, and replay path. A declaration-only helper exists solely as an internal
subroutine of the mandatory verifier; it returns no discovery plan.

Official remote references are recorded only as URLs with
`OFFICIAL_PAGE_ROUTE_PAGE_VISIBLE_UNPRESERVED` status and
`local_bytes_sha256 = "NOT_PRESERVED"`:

- [BEA Fixed Assets landing page](https://www.bea.gov/itable/fixed-assets)
- [BEA Fixed Assets downloadable-file catalog](https://apps.bea.gov/iTable/?categories=flatfiles&isuri=1&nipa_table_list=1&reqid=10&step=4)
- [BEA Historical Data archive](https://apps.bea.gov/histdata/)

## 2025 page-visible fact and claim ceiling

The profile records only that an official archive UI page visibly labeled
directory ID `14195` and `September-26-2025` when inspected. That fact is
explicitly `PAGE_VISIBLE_UNPRESERVED_NOT_SOURCE_EVIDENCE`; neither the page
response nor any source artifact was preserved here.

In particular, this artifact does **not** resolve or claim the exact
case-sensitive 2025 release-scoped Section 3/5/7 workbook names. The test names
and release directories are wholly synthetic and intentionally use distant
synthetic years. Current mutable filenames seen on another official page do
not establish historical HMI11 member casing.

The following remain unresolved and false:

- the future 2026 release directory, ID, date, and exact member case;
- response and workbook bytes, byte counts, hashes, and workbook contents;
- sheets, rows, numeric values, and units;
- official intraday availability and pre-origin completion;
- capture and durable custody;
- qualified leaf verification;
- approvals and authenticated publisher/transport trust; and
- admission, model input, forecast execution, truth, scoring, accuracy,
  promotion, and production gates.

Local self-hashes authenticate neither BEA nor transport provenance.

## Verification

From the repository root:

```sh
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_fixed_assets/hmi11_discovery_v1/test_bea_fixed_assets_hmi11_discovery_v1.jl
```

From an unrelated directory:

```sh
cd /private/tmp
julia --startup-file=no --depwarn=error --check-bounds=yes \
  --project=/absolute/repository/path/scripts/us \
  /absolute/repository/path/scripts/us/forecasting/vintages/bea_fixed_assets/hmi11_discovery_v1/test_bea_fixed_assets_hmi11_discovery_v1.jl
```

The root and unrelated-directory strict suites each pass 252 assertions, and
Runic 1.7.0 check/diff passes. The frozen replacement-candidate identities are:

- module physical SHA-256:
  `c3a506f844cb87d4662c04d4079e3e6c29947e13f5922a3777639bf28bd0ee6d`
- profile physical SHA-256:
  `9f03947315bdcb8ba602b664dd0015e03921d5a7867f02c66883d01590db5af4`
- profile semantic SHA-256:
  `96d0f93b4bf538b45fac44843f47dfd0e8aa8ca4a8e9125cfd3861e2de9e6921`
- tests physical SHA-256:
  `49634f0606a860be7bbaaca185575a6094ec9d12c9f7c797a32cc2dd0586aab6`

These are candidate pins pending a fresh independent audit. They are not an
integration, admission, origin, source-capture, or accuracy claim.

Independent review must recompute these identities, inspect the new-file-only
scope, rerun the tests from both working directories, and confirm that the
module contains no network, source-artifact-byte, write, admission, or model
execution path.
