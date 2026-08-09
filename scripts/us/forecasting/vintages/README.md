# U.S. source-release registry

`USSourceReleaseRegistry.jl` is a fail-closed WS-1A primitive for a
retrospective forecast information set. It registers source-release retrieval
events, selects only releases available at an exact UTC origin, and evaluates
whether all source, target, and structural blocks required by an origin are
present.

The registry intentionally separates three times:

- `release_timestamp_utc` is the source's official publication time.
- `availability_timestamp_utc` is the earliest evidenced time the exact
  content was accessible.
- `retrieved_at_utc` records each archive retrieval event. It is provenance and
  is not allowed to stand in for unknown source availability.

Every timestamp is mandatory RFC3339 UTC at second precision. Date-only,
minute-only, fractional, timezone-free, or inferred intraday timestamps are
rejected. Real-time intervals are half-open. A release is eligible exactly
when both its release and availability timestamps are no later than the origin
and its interval starts no later than the origin. For each required reference
interval, the latest covering release wins; only then is its exclusive
`realtime_end_utc` checked. This permits an immutable open release to coexist
with a later appended revision, while preventing fallback to an older release
after the newer release expires. The interval starts at evidenced
availability, so no future valid-to timestamp must be invented.

Each retrieval has its own `retrieval_event_id`. An identical-content refetch
is retained as a separate event only if its retrieval ID and provenance are
distinct; its release metadata and raw SHA256 must remain identical. Conflicting
content for one release event, duplicate retrieval provenance, and tied
release events that make an as-of choice ambiguous are rejected.

`evaluate_completeness` checks exact metadata and reference coverage for every
declared block, plus inventory completion, explicit origin admission,
requirements approval, and evidence-artifact verification. Mechanical block
coverage is reported separately as `candidate_complete`. The integrated
cross-registry evidence resolver is deliberately
`NOT_IMPLEMENTED_FAIL_CLOSED`, and requirements are deliberately
`DRAFT_UNAPPROVED`; consequently this version cannot emit `READY`, even for a
schema-complete synthetic fixture. The separate local evidence-bundle
integrity checker does not resolve source-release/origin bytes or authenticate
approval identities, so it does not change this status. This prevents
syntactic hashes or invented locators from becoming forecast evidence.

Evaluation identity uses a canonical origin-evidence manifest, not the
append-growing warehouse-head hash. A later release or identical-content
refetch therefore cannot change an earlier origin hash. The full inventory
hash remains available separately for warehouse auditing.

`build_cannot_run_record` emits a deterministically hashed, explicit
`CANNOT_RUN` record with block-level reason codes. The three-argument
`validate_cannot_run_record` recomputes that record against the supplied
inventory and requirements; use it when verifying provenance, since the
one-argument form validates only the self-contained record schema and digest.

The declarative field contract is in
`source_release_inventory.schema.toml`. `current_inventory.toml` is deliberately
empty: it records zero admissible origins. Its audit facts point to the
workspace finding that only 2026-08-02 and 2026-08-04 retrieval directories
were observed, while the ignored local files lack a validated historical
release sequence with exact availability evidence. Those files are not listed
as distributable artifacts and their directory names are not treated as
official vintages.

## Historical backfill and prospective capture

`historical_backfill_plan.toml` and `USHistoricalBackfillPlan.jl` define a
separate, plan-only acquisition contract. They do not install releases or
change `current_inventory.toml`: the guarded inventory remains at zero release
events and zero admissible origins.

The contract records:

- zero certified strict retrospective origins;
- `2026-07-31T14:00:00Z` as a
  `reconstructed_after_origin` diagnostic with status `CANNOT_RUN`;
- `2026-10-30T14:00:00Z` as the planned first prospective cutoff, still
  uncaptured, unadmitted, not `READY`, and not accuracy-evaluation evidence;
- reconstructed pilots for 2026Q2, 2021Q2, and 2020Q1, a 2008Q3 archive-gap
  probe, and a prospective 2026Q3 pilot;
- exact official BEA HMI7 and BLS target-backfill routes, Z.1 format eras, the
  incomplete historical first-state EFFR route and its 2016-03-01 method
  break, and unresolved structural routes for HMI8, HMI11, QCEW, SUSB, CPS,
  and USDA inputs; and
- distinct `exact_intraday_route_only`, `mixed_event_level`, `date_only`,
  `no_time`, and `historical_first_state_unverified` states. Only event-level
  exact UTC evidence can eventually qualify; route descriptions, retrieval
  times, date-only metadata, and no-time metadata cannot.

FRED and ALFRED are excluded from the byte warehouse pending written
clearance. RTDSM is a value cross-check only and cannot establish intraday
availability. Every listed acquisition stage remains `PLANNED_NOT_STARTED`.

## Common-window decision boundary

`common_window/` freezes the arithmetic and governance distinction that the
three current 40-quarter source windows do not form a 40-quarter common
panel. Their shared range is only 2016Q2--2021Q2 (21 quarter labels), and
strict admitted overlap remains zero.

The offline contract separately records a 41-quarter post-break EFFR
route-level range, the fixed 2016Q2--2026Q1 40-quarter research candidate,
and 2026Q2 as an adjacent evaluation reserve whose holdout integrity is
unverified. Because 2026Q2 was public before the 2026-08-07 freeze, it is not
prospective; the earliest genuinely prospective quarter is 2026Q3. The
contract does not claim that BEA/BLS routes, truth maturity, ALFRED
governance, bytes, or historical availability are complete.
Strict first-public, official-reconstruction, current-revised, and mixed
concept/provenance tracks remain typed and non-interchangeable. Shutdown,
reissue, concept-break, and non-panel-month cases are explicit; none becomes
generic `Used`, `Other`, zero, or an admitted origin.

## EFFR one-effective-date capture boundary

`effr/capture_contract/` defines the offline receipt and rate-volume pairing
boundary for one post-2016 EFFR effective date. It distinguishes the New York
Fed's approximately 09:00 first state, approximately 14:30 same-day revision,
later correction, ALFRED date-level state, and current API state. First and
same-day candidates are bound to validated New York publication windows;
current API evidence can never be relabeled as historical first-public bytes.

The contract requires an out-of-band receipt digest, exact OpenAPI and
governance context, fresh decision-consistent terms metadata, append-only
revision lineage, and ordered percentile/target fields before a rate-volume
pair can be returned. Pending/rejected terms, schema conflicts, unsupported
blanks, ambiguous `Used`/`Other` labels, or mismatched capture contexts fail
closed. It contains no downloader or raw-byte loader and keeps every origin,
empirical, promotion, scoring, and readiness gate false.

`effr/prospective_acquisition/` is the separate, minimal 2026-08-07 day-zero
runner. It preserves the full all-rates responses before selecting exactly one
raw `type="EFFR"` row, captures and hashes the official OpenAPI YAML, terms,
and holiday-schedule bytes, and validates any generated rate-volume pair
against the offline contract. An unchanged 14:30 check is stored as a
byte-equality record and never relabeled as a revision. Local copies and
self-generated pins remain nonadmitting integrity evidence, not durable
storage or out-of-band authentication. See its README for the exact 13:00Z
and 18:30Z commands and the unattended-scheduling warning.
Because the currently observed raw API row omits `currentState`, the runner
does not invent `false`: it installs a typed, successful raw capture with
`ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT` and emits no one-date
receipt or pair.

## Draft prospective acquisition/requirements successor

`prospective/` adds a separate v2-draft governance surface for the planned
2026Q3 capture. It models a conservative availability upper bound proven by a
pre-origin receipt, keeps verifier implementation separate from requirements
approval, pins event-specific fixed and recurring capture windows, and requires
durable retention through the mature-truth horizon.

This is not a v1 migration or admission mutation. The checked-in v2 draft has
no captured artifacts, an unimplemented verifier, unapproved requirements,
zero authorized inventory writes, and an origin that remains
`PLANNED_NOT_CAPTURED_NOT_ADMITTED`. See `prospective/README.md` for the exact
evidence boundary and hermetic test.

## Accepted fail-closed prospective composition boundary

`prospective/common_origin_acquisition_v3/` is the independently accepted
read-only composition verifier for the exact v2 topology. It rederives the
closed 21-requirement/107-profile baseline and safely reconstructs a complete
parent, leaf, raw/replica, catalog/resolution, timestamp, approval, and custody
closure without executing leaf source, loading a model or truth, using the
network, or writing evidence. Its exact status, maximum status, and claim
ceiling are permanently `CANNOT_RUN`; all 21 dispatches remain unqualified.
`READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED` is reachable only in a separately
versioned successor with pinned trust anchors and authenticated signature and
timestamp validators. Local self-hashes, local clock labels, opaque signature
references, and self-authored nonsynthetic labels are not provenance.

`prospective/common_origin_acquisition_v4/` is the independently accepted
synthetic object-catalog and trust-schema prototype. It represents shared and
set-valued sources directly: the synthetic fixed-assets example maps eight
profiles to three XLSX objects, while six CPS profiles reference one ordered
three-object JSON history. Requested/final URI, method, request payload,
ordinal, provider object, replicas, profile projections, byte ceilings, and
the entire parent closure are canonically bound. Its validation-policy state
is immutable under ordinary Julia mutation, returned containers are fresh,
and the exact mutation/restamp attacks are regression-tested. It is still
permanently `CANNOT_RUN`: all evidence is synthetic, no production trust
anchor, key, signature, RFC 3161 response, qualified leaf verifier, complete
107-profile closure, EFFR supersession, physical replica, external custody,
or closed Julia/JLL runtime exists. It does not load OpenSSL or expose a
network, model, truth, scoring, or inventory-write path.

`effr/prospective_endpoint_profile_v1/` is the accepted fail-closed EFFR
endpoint-profile contract. It records the 58-morning/57-later/115-slot/57-pair
restart geometry and the missing August 7 later observation, but remains
`CANNOT_RUN`: all three legacy-profile supersession decisions are unfrozen,
the daily-history start and 2016 methodology-break treatment are unapproved,
and the short 2026Q3 campaign is not a model training history.

The first reusable source acquisition mechanism is split between
`bea_industry/prospective_snapshot_envelope_v1/` and
`bea_industry/after_redefinitions_2025_adapter_v1/`. The envelope provides an
explicit injected-fetcher boundary, dual pre-request clock gates, exactly-once
journaling/recovery, validated two-copy local preservation, and nonretrying
quarantine. The adapter closes exactly the six BEA industry-valuation profiles
assigned to the August campaign and excludes the other 27 structural profiles.
No new prospective bundle exists, so its status is
`CANNOT_RUN_NO_NEW_PROSPECTIVE_BUNDLE`; the prior archive remains
nonprospective diagnostic material. Neither component qualifies a v3 dispatch
or changes the zero-origin inventory.

`bea_fixed_assets/hmi11_discovery_v1/` is the independently accepted offline
HMI11 discovery-mechanics validator. It closes the four-response directory,
path-to-ID, ID-to-path and file-catalog lineage; selects the latest canonical
release at a cutoff; preserves exact filename case; derives only exact-child
workbook URLs; and maps the eight fixed-assets profiles across Sections 3, 5
and 7 in a 3/3/2 pattern. Public build and replay always verify the pinned
control-file closure. It remains permanently `CANNOT_RUN`: no live response or
workbook was acquired, the future 2026 release/member identities and workbook
contents are unknown, and qualification remains 0/8.

`bls_cps/prospective_capture_set_v1/` is the independently accepted offline
capture-set/parser mechanics contract for the six CPS structural profiles. It
freezes eight ordered ten-year API requests, eight catalog-object roles,
strict duplicate-safe JSON/TSV/text parsing, explicit UTF-8 validation,
full-object-to-six-series projection receipts, exact monthly coverage,
October-2025 typed missing values, and source-pin/result replay. Its exact
status remains `CANNOT_RUN`: the official provider catalog layout and complete
raw-object provenance have not been prospectively captured, the fixtures are
synthetic and are not attributed to the planned URLs, projection operationality
is false, and qualification remains 0/6. It contains no downloader or writer
and does not alter v3 or the inventory.

`classification_maps/profile_v1/` is the independently accepted offline
synthetic-parser and local-fixity contract for the six classification-map
profiles. It preserves mapping direction and cardinality, exact blanks and
orders, the distinct `model.codes` and `[[sector]]` orderings in
`scripts/us/bea71.toml`, and terminal BEA `Other`/`Used` special accounts that
must never be treated as NAICS codes. Exact-type result replay and XML 1.0
character-data attacks are closed. It remains permanently `CANNOT_RUN`: the
official workbook bodies, provider layouts, current-origin receipts, and
official-to-model approvals are absent, so qualification remains 0/6 and all
downstream gates are false.

`classification_maps/present_day_physical_profile_v1/` is the independently
accepted standard-library physical-layout diagnostic for six exact external
classification workbooks. It replays the Use/Make ordinary and special axes,
BEA hierarchy/empty-shared-string/defined-name surfaces, both NAICS structures,
and the directional 2017-to-2022 concordance while preserving exact spaces,
styled blanks, trailing title whitespace, mapping cardinality, and special
account order. It proves that present workbooks do not satisfy the logical-v1
shared-axis/order projection. Local body hashes are not body-to-URL/provider
provenance; no workbook is stored here. Status remains `CANNOT_RUN`,
qualification remains 0/6, and every origin/model/scoring/promotion/production
gate is false.

`census_structural/profile_v1/` is the independently accepted, permanently
nonadmitting logical-schema contract for five AIES inventory profiles and one
SUSB structural profile. It requires the complete documented AIES row keys,
dimensions, values, flags, CVs and CV flags; retains all overlapping SUSB
size-code rows; derives code 01 separately; and forbids treating industry
`FIRM` presences as an additive enterprise count. Exact concrete TOML/result
types and immutable numeric policy are replay-checked. It resolves 6/6 logical
schemas but 0/6 physical layouts: no provider ZIP/TXT body, physical schema,
prospective receipt, or origin evidence is present, so status is `CANNOT_RUN`
and every downstream gate remains false.

`census_structural/present_day_physical_profile_v1/` is the independently
accepted standard-library physical-layout diagnostic for the exact five AIES
ZIPs and full SUSB text body observed on 2026-08-08. It preserves raw AIES
flag/value/CV pairings, signed lexemes and structural flags; decodes SUSB as
Windows-1252; binds the provider's nonconsecutive size-code vocabulary; and
keeps the full SUSB universe separate from its national code-01 projection.
It proves that the present bodies map to the logical field topology but violate
the logical-v1 row constraints. The external bodies are not stored here, and
local hash/size fixity is explicitly separate from body-to-URL/provider
provenance. Its role is
`PRESENT_DAY_PHYSICAL_LAYOUT_DIAGNOSTIC_NONADMITTING`, status remains
`CANNOT_RUN`, qualification remains 0/6, and all origin/model/scoring/
promotion/production gates are false.

`census_inventory/release_profile_v1/` is the independently accepted
present-day OOXML mechanics profile for the five scheduled M3, MWTS, and MRTS
inventory workbooks. It reparses five exact external diagnostic bodies,
validates their complete package/relationship/content-type and selected
sheet/axis/value surfaces, and distinguishes published cells from derived M3
stage totals. XML safety is driven by resolved MIME, not filename suffix, and
relationship parts and targets require exact content types. Its current
June/May bodies are not the planned August/September captures and are neither
retained raw evidence nor authenticated body-to-URL provenance. Status remains
`CANNOT_RUN`, qualification remains 0/5, and every origin/model/scoring/
promotion/production gate is false.

`usda_nass/farms_land_in_farms_profile_v1/` is the independently accepted
present-day PDF-table mechanics profile for the NASS `Farms and Land in Farms
2025 Summary`. It binds one exact external PDF body, the complete 2018--2025
national table, and all 32 positional cells; two pypdf versions independently
reproduce the same checked-in derivative and the 2024 value of 1,880,000. The
raw body is not retained in the repository, no prospective origin or custody
is established, and the farm-to-model-firm mapping remains
`DUBIOUS_NOT_APPROVED`. Its status is
`PRESENT_DAY_PDF_TABLE_PARSED_NONADMITTING`; qualification remains 0/1 and all
origin, model-input, scoring, promotion, and production gates remain false.

Run the hermetic tests with:

```sh
julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/test_source_release_registry.jl

julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/test_historical_backfill_plan.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/prospective_acquisition/test_effr_day_zero_acquisition.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/common_window/test_common_origin_window_decision.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/effr/capture_contract/test_effr_capture_contract.jl

julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/prospective/test_prospective_acquisition_contract.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4 \
  scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v4/test_common_origin_acquisition_v4.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bls_cps/prospective_capture_set_v1/test_bls_cps_prospective_capture_set_v1.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/bea_fixed_assets/hmi11_discovery_v1/test_bea_fixed_assets_hmi11_discovery_v1.jl

julia --startup-file=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/classification_maps/profile_v1/test_classification_maps_profile_v1.jl

CLASSIFICATION_MAPS_PHYSICAL_AUDIT_DIR=/absolute/path/to/four-audit-workbooks \
  CLASSIFICATION_MAPS_SUMMARY_AUDIT_DIR=/absolute/path/to/summary-workbooks \
  PYTHONDONTWRITEBYTECODE=1 python3 -B \
  scripts/us/forecasting/vintages/classification_maps/present_day_physical_profile_v1/test_classification_maps_present_day_physical_profile_v1.py

julia --startup-file=no --compiled-modules=no --check-bounds=yes --depwarn=error \
  --project=scripts/us \
  scripts/us/forecasting/vintages/census_structural/profile_v1/test_census_structural_profile_v1.jl

CENSUS_STRUCTURAL_PHYSICAL_AUDIT_DIR=/private/tmp/census-structural-physical-audit.dZRm93 \
  PYTHONDONTWRITEBYTECODE=1 python3 -B \
  scripts/us/forecasting/vintages/census_structural/present_day_physical_profile_v1/test_census_structural_present_day_physical_profile_v1.py

PYTHONDONTWRITEBYTECODE=1 python3 -B -m unittest -v \
  scripts/us/forecasting/vintages/census_inventory/release_profile_v1/test_census_inventory_release_profile_v1.py

python3 \
  scripts/us/forecasting/vintages/usda_nass/farms_land_in_farms_profile_v1/test_usda_farms_land_in_farms_profile_v1.py

julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_schedule/test_bea_schedule_monitor.jl

julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/test_bea_nipa_discovery.jl

julia --startup-file=no --project=scripts/us \
  scripts/us/forecasting/vintages/bea_nipa/mapping_audit/test_mapping_audit.jl
```

## BEA schedule-monitor boundary

`bea_schedule/` strictly revalidates the planned October 29, 2026 8:30 a.m.
advance-GDP row on BEA's mutable official schedule. The scheduled workflow
preserves the exact fetched page and metadata as short-retention,
hash-addressed workflow artifacts and fails on a moved, missing, duplicated,
renamed, or structurally unrecognized event. This proves only what the
schedule page said when fetched; it is not release-byte, release-event,
origin-availability, admission, or `READY` evidence.

## BEA HMI7 discovery boundary

`bea_nipa/` implements only the locator-discovery portion of the first
acquisition stage. It parses official HMI7 directory metadata, reverse-checks
the selected archive directory ID and path, and catalogs every discovered
main section workbook separately from the five BEA Tier-1 target records.
Hermetic fixtures are normalized response subsets; the optional live probe
retrieves metadata only.

The checked-in mapping contract deliberately separates current protocol
selectors from both historical workbook sections and rows. A current
table/line number or section hint is not reused as a historical selector.
Each release workbook must independently verify its exact sheet, concept
label, series code, units, base year, line number, and reference-quarter
column after the workbook bytes have been preserved and hashed. Until then,
release bytes, historical section/row mappings, and availability evidence
remain unverified; no release event or origin is admitted.

`bea_nipa/mapping_audit/` records the separate ephemeral workbook-content
study as a byte-pinned, machine-readable research artifact. It covers 40
workbook locators, 20 exact inspected releases, eight demonstrated mapping
profiles, and seven adjacent-release breaks. The underlying workbook bytes
were not retained and historical availability was not established, so the
profiles apply only to the exact inspected research observations. Unknown,
partially inspected, neighboring, or date-inferred releases are rejected and
cannot enter acquisition or origin state.
