module USCommonOriginWindowDecision

using SHA
using TOML

export ALLOWED_CONCLUSIONS,
    ARTIFACT_PROVENANCE_STATES,
    BLOCKER_STATES,
    CANONICALIZATION,
    CONTRACT_ID,
    DEFAULT_DECISION_PATH,
    EXPECTED_CONTENT_SHA256,
    HOLDOUT_INTEGRITY_STATES,
    IRREGULARITY_STATES,
    RESERVE_CLASSES,
    SCHEMA_VERSION,
    SOURCE_ROLES,
    TERMS_STATES,
    TRACK_IDS,
    USCommonOriginWindowError,
    computed_content_sha256,
    decision_artifact,
    load_decision,
    validate_decision

const DEFAULT_DECISION_PATH =
    joinpath(@__DIR__, "common_origin_window_decision.toml")
const SCHEMA_VERSION =
    "beforeit-us-common-origin-window-decision.v1"
const CONTRACT_ID =
    "us-common-origin-window-offline-decision-2026-08-07.v1"
const CANONICALIZATION =
    "sorted_typed_length_aware_v1_excluding_artifact_content_sha256"
const EXPECTED_CONTENT_SHA256 =
    "a28913ce7516ded9af034e6aa800d0cb29b1d528519fb79745c9c8744e994e82"

const INVENTORY_SHA256 =
    "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
const OBSERVED_DATE = "2026-08-07"

const TRACK_IDS = (
    "STRICT_FIRST_PUBLIC_BYTES",
    "OFFICIAL_ARCHIVE_RECONSTRUCTION",
    "CURRENT_REVISED_PROXY",
    "MIXED_CONCEPT_AND_PROVENANCE_SENSITIVITY",
)
const ALLOWED_CONCLUSIONS = (
    "NO_EMPIRICAL_CONCLUSION",
    "RESEARCH_ONLY_AFTER_ALL_GATES_PASS",
    "DESCRIPTIVE_REVISED_DATA_DIAGNOSTIC_ONLY",
    "SENSITIVITY_ONLY_WITH_EXPLICIT_STRATIFICATION",
)
const BLOCKER_STATES = (
    "SOURCE_COVERAGE_NOT_PROVEN",
    "TERMS_AUTHORIZATION_NOT_PROVEN",
    "ARTIFACT_CAPTURE_INCOMPLETE",
    "TRUTH_MATURITY_NOT_PROVEN",
    "ZERO_ORIGINS_ADMITTED",
    "FIRST_PUBLIC_BYTES_NOT_VERIFIED",
    "ALFRED_GOVERNANCE_BLOCKED",
    "CURRENT_STATE_NOT_VINTAGE",
    "PRE_2016_CONCEPT_BREAK",
    "MIXED_PROVENANCE_REQUIRES_STRATIFICATION",
    "IRREGULAR_RELEASES_REQUIRE_ADJUDICATION",
    "PROMOTION_COVERAGE_ZERO_OF_EIGHT",
)
const ARTIFACT_PROVENANCE_STATES = (
    "FIRST_PUBLIC_BYTES_VERIFIED",
    "OFFICIAL_ARCHIVE_RECONSTRUCTION",
    "REISSUED_CORRECTED",
    "UNKNOWN_FIRST_STATE",
    "MISSING_ROUTE",
    "SKIPPED_NOT_PUBLISHED",
    "SKIPPED_NOT_PUBLISHED_NON_PANEL_MONTH",
    "DATE_LEVEL_VINTAGE",
    "CURRENT_STATE_WITH_REVISION_FLAG_NOT_VINTAGE",
    "OCR_NOT_AUTHORITATIVE",
)
const SOURCE_ROLES = (
    "PRIMARY_VALUE_SOURCE",
    "PRIMARY_ARTIFACT_EVIDENCE",
    "CROSSCHECK_ONLY",
    "NOT_USED",
    "QUARANTINED",
)
const TERMS_STATES = (
    "TERMS_AUTHORIZATION_NOT_PROVEN",
    "TERMS_LOCAL_GOVERNANCE_BLOCKED_PENDING_REVIEW",
)
const RESERVE_CLASSES = (
    "NOT_A_RESERVE",
    "ADJACENT_2026Q2_EVALUATION_RESERVE",
)
const HOLDOUT_INTEGRITY_STATES = (
    "NOT_APPLICABLE",
    "UNVERIFIED",
)
const CONCEPT_STATES = (
    "EARLIEST_COMPLETE_GDP_AND_PERSONAL_INCOME_RELEASE",
    "EMPLOYMENT_SITUATION_QUARTER_END_RELEASE",
    "POST_2016_FR2420_VOLUME_WEIGHTED_MEDIAN",
    "CONCEPT_BREAK",
    "MIXED_PRE_AND_POST_2016_CONCEPT",
    "NOT_APPLICABLE",
)
const ARTIFACT_CAPTURE_STATES = (
    "ROUTE_EXISTS_NOT_CAPTURED",
    "CURRENT_RESPONSE_NOT_VINTAGE",
)
const TRUTH_MATURITY_STATES = ("TRUTH_MATURITY_NOT_PROVEN",)
const ORIGIN_ADMISSION_STATES = ("ZERO_ORIGINS_ADMITTED",)
const COVERAGE_STATES = (
    "FROZEN_METADATA_WINDOW_NOT_SOURCE_COMPLETE",
    "ROUTE_LEVEL_CANDIDATE_NOT_SOURCE_COMPLETE",
    "CURRENT_STATE_CROSSCHECK_ONLY",
)
const IRREGULARITY_STATES = (
    "INITIAL_REPLACES_ADVANCE_AND_SECOND",
    "REISSUED_CORRECTED",
    "DELAYED_BY_FEDERAL_LAPSE",
    "SKIPPED_NOT_PUBLISHED_NON_PANEL_MONTH",
)
const PANEL_RELATIONS = (
    "INSIDE_FROZEN_SOURCE_WINDOW",
    "INSIDE_ROUTE_LEVEL_WINDOW_OUTSIDE_FIXED_40",
    "OUTSIDE_FROZEN_SOURCE_WINDOW",
    "NON_PANEL_MONTH",
)

const ROOT_KEYS = (
    "artifact",
    "decision",
    "gates",
    "prospective_boundary",
    "source_windows",
    "intersections",
    "effr_window_roles",
    "tracks",
    "source_routes",
    "irregularities",
    "citations",
)
const ARTIFACT_KEYS =
    ("schema_version", "canonicalization", "content_sha256")
const DECISION_KEYS = (
    "contract_id",
    "observed_date",
    "decision_class",
    "inventory_sha256",
    "admitted_origin_count",
    "promotion_passed",
    "promotion_total",
    "strict_all_three_intersection_count",
    "metadata_only",
    "network_access_allowed",
    "raw_bytes_stored",
    "source_inventory_mutation_authorized",
    "empirical_results_stored",
    "production_claim_allowed",
)
const GATE_KEYS = (
    "source_coverage_proven",
    "terms_authorization_complete",
    "artifact_capture_complete",
    "truth_maturity_proven",
    "origin_admission_complete",
    "strict_intersection_admissible",
    "empirical_execution_allowed",
    "promotion_eligible",
    "production_scoring_allowed",
    "ready",
)
const PROSPECTIVE_BOUNDARY_KEYS = (
    "freeze_date",
    "public_and_inspected_through_quarter",
    "earliest_genuinely_prospective_quarter",
    "adjacent_reserve_id",
    "adjacent_reserve_holdout_integrity",
    "adjacent_reserve_is_prospective",
    "prospective_reserve_registered",
    "origin_admitted",
    "empirical_execution_allowed",
)
const WINDOW_KEYS = (
    "sequence",
    "window_id",
    "source_id",
    "first_quarter",
    "last_quarter",
    "quarter_count",
    "coverage_state",
    "artifact_provenance_state",
    "concept_state",
    "terms_state",
    "artifact_capture_state",
    "truth_maturity_state",
    "origin_admission_state",
    "source_coverage_proven",
    "terms_authorization_complete",
    "artifact_capture_complete",
    "truth_maturity_proven",
    "origin_admission_complete",
)
const INTERSECTION_KEYS = (
    "sequence",
    "intersection_id",
    "member_window_ids",
    "first_quarter",
    "last_quarter",
    "quarter_count",
    "strict_admitted_origin_count",
    "strict_admissible",
)
const EFFR_ROLE_KEYS = (
    "sequence",
    "role_id",
    "first_quarter",
    "last_quarter",
    "quarter_count",
    "status",
    "included_in_fixed_40",
    "reserve_class",
    "holdout_integrity",
    "public_at_freeze",
    "prospective_at_freeze",
    "origin_admitted",
    "empirical_execution_allowed",
)
const TRACK_KEYS = (
    "sequence",
    "track_id",
    "allowed_conclusion",
    "blockers",
    "source_coverage_proven",
    "terms_authorization_complete",
    "artifact_capture_complete",
    "truth_maturity_proven",
    "origin_admission_complete",
    "empirical_execution_allowed",
    "production_eligible",
)
const SOURCE_ROUTE_KEYS = (
    "sequence",
    "route_id",
    "agency",
    "artifact_provenance_state",
    "source_role",
    "concept_state",
    "terms_state",
    "coverage_state",
    "artifact_capture_state",
    "truth_maturity_state",
    "origin_admission_state",
    "allowed_use",
    "source_coverage_proven",
    "terms_authorization_complete",
    "artifact_capture_complete",
    "truth_maturity_proven",
    "origin_admission_complete",
)
const IRREGULARITY_KEYS = (
    "sequence",
    "period",
    "agency",
    "irregularity_state",
    "panel_relation",
    "treatment",
    "evidence_citation_id",
    "admitted",
)
const CITATION_KEYS = (
    "sequence",
    "citation_id",
    "citation_class",
    "title",
    "url",
    "supports",
)

const EXPECTED_WINDOWS = (
    (
        window_id = "BEA_HMI7_RELEASE_METADATA_40",
        source_id = "BEA_HMI7_OFFICIAL_ARCHIVE",
        first_quarter = "2011Q3",
        last_quarter = "2021Q2",
        quarter_count = 40,
        coverage_state = "FROZEN_METADATA_WINDOW_NOT_SOURCE_COMPLETE",
        artifact_provenance_state = "UNKNOWN_FIRST_STATE",
        concept_state =
            "EARLIEST_COMPLETE_GDP_AND_PERSONAL_INCOME_RELEASE",
        terms_state = "TERMS_AUTHORIZATION_NOT_PROVEN",
        artifact_capture_state = "ROUTE_EXISTS_NOT_CAPTURED",
    ),
    (
        window_id = "BLS_QUARTER_END_ARCHIVE_METADATA_40",
        source_id = "BLS_EMPLOYMENT_OFFICIAL_ARCHIVE",
        first_quarter = "2015Q1",
        last_quarter = "2024Q4",
        quarter_count = 40,
        coverage_state = "FROZEN_METADATA_WINDOW_NOT_SOURCE_COMPLETE",
        artifact_provenance_state =
            "OFFICIAL_ARCHIVE_RECONSTRUCTION",
        concept_state = "EMPLOYMENT_SITUATION_QUARTER_END_RELEASE",
        terms_state = "TERMS_AUTHORIZATION_NOT_PROVEN",
        artifact_capture_state = "ROUTE_EXISTS_NOT_CAPTURED",
    ),
    (
        window_id = "EFFR_CLEAN_POST_BREAK_CANDIDATE_40",
        source_id = "ALFRED_EFFR_DATE_LEVEL_VINTAGE",
        first_quarter = "2016Q2",
        last_quarter = "2026Q1",
        quarter_count = 40,
        coverage_state = "FROZEN_METADATA_WINDOW_NOT_SOURCE_COMPLETE",
        artifact_provenance_state = "DATE_LEVEL_VINTAGE",
        concept_state = "POST_2016_FR2420_VOLUME_WEIGHTED_MEDIAN",
        terms_state =
            "TERMS_LOCAL_GOVERNANCE_BLOCKED_PENDING_REVIEW",
        artifact_capture_state = "ROUTE_EXISTS_NOT_CAPTURED",
    ),
)

const EXPECTED_INTERSECTIONS = (
    (
        intersection_id = "BEA_X_BLS",
        member_window_ids = (
            "BEA_HMI7_RELEASE_METADATA_40",
            "BLS_QUARTER_END_ARCHIVE_METADATA_40",
        ),
        first_quarter = "2015Q1",
        last_quarter = "2021Q2",
        quarter_count = 26,
    ),
    (
        intersection_id = "BEA_X_EFFR",
        member_window_ids = (
            "BEA_HMI7_RELEASE_METADATA_40",
            "EFFR_CLEAN_POST_BREAK_CANDIDATE_40",
        ),
        first_quarter = "2016Q2",
        last_quarter = "2021Q2",
        quarter_count = 21,
    ),
    (
        intersection_id = "BLS_X_EFFR",
        member_window_ids = (
            "BLS_QUARTER_END_ARCHIVE_METADATA_40",
            "EFFR_CLEAN_POST_BREAK_CANDIDATE_40",
        ),
        first_quarter = "2016Q2",
        last_quarter = "2024Q4",
        quarter_count = 35,
    ),
    (
        intersection_id = "BEA_X_BLS_X_EFFR",
        member_window_ids = (
            "BEA_HMI7_RELEASE_METADATA_40",
            "BLS_QUARTER_END_ARCHIVE_METADATA_40",
            "EFFR_CLEAN_POST_BREAK_CANDIDATE_40",
        ),
        first_quarter = "2016Q2",
        last_quarter = "2021Q2",
        quarter_count = 21,
    ),
)

const EXPECTED_EFFR_ROLES = (
    (
        role_id = "ROUTE_LEVEL_CANDIDATE_41",
        first_quarter = "2016Q2",
        last_quarter = "2026Q2",
        quarter_count = 41,
        status = "ROUTE_LEVEL_CANDIDATE_NOT_SOURCE_COMPLETE",
        included_in_fixed_40 = false,
        reserve_class = "NOT_A_RESERVE",
        holdout_integrity = "NOT_APPLICABLE",
        public_at_freeze = true,
        prospective_at_freeze = false,
    ),
    (
        role_id = "FROZEN_FIXED_40_RESEARCH_CANDIDATE",
        first_quarter = "2016Q2",
        last_quarter = "2026Q1",
        quarter_count = 40,
        status = "FROZEN_RESEARCH_CANDIDATE_NOT_ADMITTED",
        included_in_fixed_40 = true,
        reserve_class = "NOT_A_RESERVE",
        holdout_integrity = "NOT_APPLICABLE",
        public_at_freeze = true,
        prospective_at_freeze = false,
    ),
    (
        role_id = "ADJACENT_2026Q2_EVALUATION_RESERVE",
        first_quarter = "2026Q2",
        last_quarter = "2026Q2",
        quarter_count = 1,
        status = "PUBLIC_AT_FREEZE_NOT_PROSPECTIVE",
        included_in_fixed_40 = false,
        reserve_class = "ADJACENT_2026Q2_EVALUATION_RESERVE",
        holdout_integrity = "UNVERIFIED",
        public_at_freeze = true,
        prospective_at_freeze = false,
    ),
)

const EXPECTED_TRACKS = (
    (
        track_id = "STRICT_FIRST_PUBLIC_BYTES",
        allowed_conclusion = "NO_EMPIRICAL_CONCLUSION",
        blockers = (
            "SOURCE_COVERAGE_NOT_PROVEN",
            "TERMS_AUTHORIZATION_NOT_PROVEN",
            "ARTIFACT_CAPTURE_INCOMPLETE",
            "TRUTH_MATURITY_NOT_PROVEN",
            "ZERO_ORIGINS_ADMITTED",
            "FIRST_PUBLIC_BYTES_NOT_VERIFIED",
            "IRREGULAR_RELEASES_REQUIRE_ADJUDICATION",
            "PROMOTION_COVERAGE_ZERO_OF_EIGHT",
        ),
    ),
    (
        track_id = "OFFICIAL_ARCHIVE_RECONSTRUCTION",
        allowed_conclusion = "RESEARCH_ONLY_AFTER_ALL_GATES_PASS",
        blockers = (
            "SOURCE_COVERAGE_NOT_PROVEN",
            "TERMS_AUTHORIZATION_NOT_PROVEN",
            "ARTIFACT_CAPTURE_INCOMPLETE",
            "TRUTH_MATURITY_NOT_PROVEN",
            "ZERO_ORIGINS_ADMITTED",
            "ALFRED_GOVERNANCE_BLOCKED",
            "IRREGULAR_RELEASES_REQUIRE_ADJUDICATION",
            "PROMOTION_COVERAGE_ZERO_OF_EIGHT",
        ),
    ),
    (
        track_id = "CURRENT_REVISED_PROXY",
        allowed_conclusion = "DESCRIPTIVE_REVISED_DATA_DIAGNOSTIC_ONLY",
        blockers = (
            "CURRENT_STATE_NOT_VINTAGE",
            "ZERO_ORIGINS_ADMITTED",
            "PROMOTION_COVERAGE_ZERO_OF_EIGHT",
        ),
    ),
    (
        track_id = "MIXED_CONCEPT_AND_PROVENANCE_SENSITIVITY",
        allowed_conclusion =
            "SENSITIVITY_ONLY_WITH_EXPLICIT_STRATIFICATION",
        blockers = (
            "PRE_2016_CONCEPT_BREAK",
            "MIXED_PROVENANCE_REQUIRES_STRATIFICATION",
            "TERMS_AUTHORIZATION_NOT_PROVEN",
            "ARTIFACT_CAPTURE_INCOMPLETE",
            "TRUTH_MATURITY_NOT_PROVEN",
            "ZERO_ORIGINS_ADMITTED",
            "PROMOTION_COVERAGE_ZERO_OF_EIGHT",
        ),
    ),
)

const EXPECTED_ROUTE_IDS = (
    "BEA_HMI7_OFFICIAL_ARCHIVE",
    "BLS_EMPLOYMENT_OFFICIAL_ARCHIVE",
    "ALFRED_EFFR_DATE_LEVEL_VINTAGE",
    "NYFED_EFFR_CURRENT_API",
    "BOARD_H15_CURRENT_SERIES",
    "BOARD_H15_PRE_2016_ISSUE_ARCHIVE",
)

const EXPECTED_IRREGULARITIES = (
    (
        period = "2018Q4",
        agency = "BEA",
        irregularity_state = "INITIAL_REPLACES_ADVANCE_AND_SECOND",
        panel_relation = "INSIDE_FROZEN_SOURCE_WINDOW",
        evidence_citation_id = "bea_hmi7_archive",
    ),
    (
        period = "2019Q4",
        agency = "BLS",
        irregularity_state = "REISSUED_CORRECTED",
        panel_relation = "INSIDE_FROZEN_SOURCE_WINDOW",
        evidence_citation_id = "bls_december_2019_release",
    ),
    (
        period = "2025Q3",
        agency = "BLS",
        irregularity_state = "DELAYED_BY_FEDERAL_LAPSE",
        panel_relation = "OUTSIDE_FROZEN_SOURCE_WINDOW",
        evidence_citation_id = "bls_september_2025_release",
    ),
    (
        period = "2025Q3",
        agency = "BEA",
        irregularity_state = "INITIAL_REPLACES_ADVANCE_AND_SECOND",
        panel_relation = "OUTSIDE_FROZEN_SOURCE_WINDOW",
        evidence_citation_id = "bea_2025q3_initial",
    ),
    (
        period = "2025-10",
        agency = "BLS",
        irregularity_state =
            "SKIPPED_NOT_PUBLISHED_NON_PANEL_MONTH",
        panel_relation = "NON_PANEL_MONTH",
        evidence_citation_id = "bls_2025_shutdown_method",
    ),
)

const EXPECTED_CITATION_URLS = (
    "bea_hmi7_archive" =>
        "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/?HistMainId=7&getFiles=false&getDirs=true",
    "bls_archive" =>
        "https://www.bls.gov/bls/news-release/empsit.htm",
    "bls_december_2019_release" =>
        "https://www.bls.gov/news.release/archives/empsit_01102020.htm",
    "bls_2025_shutdown_method" =>
        "https://www.bls.gov/cps/methods/2025-federal-government-shutdown-impact-cps.htm",
    "bls_september_2025_release" =>
        "https://www.bls.gov/news.release/archives/empsit_11202025.htm",
    "bea_2025q3_initial" =>
        "https://www.bea.gov/news/2025/gross-domestic-product-3rd-quarter-2025-initial-estimate-and-corporate-profits",
    "bea_2025_schedule_explanation" =>
        "https://www.bea.gov/news/blog/2025-12-10/economic-release-schedule-updates",
    "nyfed_effr" =>
        "https://www.newyorkfed.org/markets/reference-rates/effr",
    "nyfed_effr_methodology" =>
        "https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates",
    "board_h15" =>
        "https://www.federalreserve.gov/releases/h15/",
    "fraser_h15" =>
        "https://fraser.stlouisfed.org/title/h15-selected-interest-rates-86",
    "fred_terms" => "https://fred.stlouisfed.org/legal/terms/",
    "fred_api_terms" =>
        "https://fred.stlouisfed.org/docs/api/terms_of_use.html",
    "croushore_stark_2001" =>
        "https://doi.org/10.1016/S0304-4076(01)00072-0",
    "koenig_dolmas_piger_2003" =>
        "https://doi.org/10.1162/003465303322369768",
    "fett_2015" => "https://doi.org/10.21916/mlr.2015.12",
)

const HASH_PATTERN = r"^[0-9a-f]{64}$"
const QUARTER_PATTERN = r"^[0-9]{4}Q[1-4]$"
const MONTH_PATTERN = r"^[0-9]{4}-(0[1-9]|1[0-2])$"

struct USCommonOriginWindowError <: Exception
    message::String
end

Base.showerror(io::IO, error::USCommonOriginWindowError) =
    print(io, error.message)

fail(location, message) =
    throw(USCommonOriginWindowError("$location: $message"))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_array(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    expected_set = Set(String.(expected))
    missing = sort!(collect(setdiff(expected_set, actual)))
    unknown = sort!(collect(setdiff(actual, expected_set)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return table
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    occursin('\0', text) && fail(location, "must not contain NUL")
    return text
end

function expect_bool(value, location)
    value isa Bool || fail(location, "must be a Boolean")
    return value
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    result = Int(value)
    result >= minimum || fail(location, "must be at least $minimum")
    return result
end

function expect_exact(value, expected, location)
    value == expected ||
        fail(location, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function expect_member(value, allowed, location)
    text = expect_string(value, location)
    text in ("Used", "Other", "USED", "OTHER") &&
        fail(location, "bare Used/Other labels are forbidden")
    text in allowed ||
        fail(location, "unsupported closed-enum value $(repr(text))")
    return text
end

function expect_false(value, location)
    expect_exact(expect_bool(value, location), false, location)
    return false
end

function _quarter_index(value, location)
    text = expect_string(value, location)
    occursin(QUARTER_PATTERN, text) ||
        fail(location, "must use canonical YYYYQn")
    year_number = parse(Int, text[1:4])
    quarter_number = parse(Int, text[end:end])
    return 4 * year_number + quarter_number - 1
end

function _quarter_label(index)
    year_number, remainder = divrem(index, 4)
    return "$(year_number)Q$(remainder + 1)"
end

function _quarter_count(first_quarter, last_quarter, location)
    first_index = _quarter_index(first_quarter, "$location.first_quarter")
    last_index = _quarter_index(last_quarter, "$location.last_quarter")
    last_index >= first_index ||
        fail(location, "last quarter must not precede first quarter")
    return last_index - first_index + 1
end

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        entries =
            sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "S", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "B1" : "B0")
    elseif value isa Integer
        print(io, "I", value, ";")
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) ||
            fail("canonicalization", "cannot encode a nonfinite number")
        print(io, "F", bitstring(number), ";")
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function _canonical_content_bytes(value)
    document = deepcopy(expect_table(value, "decision"))
    artifact = expect_table(
        get(document, "artifact", nothing),
        "decision.artifact",
    )
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, document)
    return take!(io)
end

"""
    computed_content_sha256(decision)

Compute the semantic digest without mutating or stamping the caller's data.
"""
computed_content_sha256(value) =
    bytes2hex(sha256(_canonical_content_bytes(value)))

function _freeze(value)
    if value isa AbstractDict
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        return (;
            (
                Symbol(String(key)) => _freeze(entry) for
                    (key, entry) in entries
            )...,
        )
    elseif value isa AbstractVector
        return Tuple(_freeze(entry) for entry in value)
    elseif value isa AbstractString
        return String(value)
    elseif value isa Bool
        return Bool(value)
    elseif value isa Integer
        return Int(value)
    elseif value isa AbstractFloat
        return Float64(value)
    end
    return fail("freeze", "unsupported value of type $(typeof(value))")
end

function _validate_artifact(root)
    artifact = expect_exact_keys(
        root["artifact"],
        ARTIFACT_KEYS,
        "decision.artifact",
    )
    expect_exact(
        artifact["schema_version"],
        SCHEMA_VERSION,
        "decision.artifact.schema_version",
    )
    expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "decision.artifact.canonicalization",
    )
    declared =
        expect_string(artifact["content_sha256"], "decision.artifact.content_sha256")
    occursin(HASH_PATTERN, declared) ||
        fail(
        "decision.artifact.content_sha256",
        "must be 64 lowercase hexadecimal characters",
    )
    computed = computed_content_sha256(root)
    declared == computed ||
        fail(
        "decision.artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    declared == EXPECTED_CONTENT_SHA256 ||
        fail(
        "decision.artifact.content_sha256",
        "does not match the compiled sealed-contract pin",
    )
    return declared
end

function _validate_decision_metadata(root)
    decision = expect_exact_keys(
        root["decision"],
        DECISION_KEYS,
        "decision.decision",
    )
    exact_values = (
        "contract_id" => CONTRACT_ID,
        "observed_date" => OBSERVED_DATE,
        "decision_class" =>
            "OFFLINE_COMMON_ORIGIN_WINDOW_GOVERNANCE",
        "inventory_sha256" => INVENTORY_SHA256,
        "admitted_origin_count" => 0,
        "promotion_passed" => 0,
        "promotion_total" => 8,
        "strict_all_three_intersection_count" => 0,
        "metadata_only" => true,
    )
    for (key, expected) in exact_values
        expect_exact(decision[key], expected, "decision.decision.$key")
    end
    for key in (
            "network_access_allowed",
            "raw_bytes_stored",
            "source_inventory_mutation_authorized",
            "empirical_results_stored",
            "production_claim_allowed",
        )
        expect_false(decision[key], "decision.decision.$key")
    end
    return decision
end

function _validate_gates(root)
    gates =
        expect_exact_keys(root["gates"], GATE_KEYS, "decision.gates")
    for key in GATE_KEYS
        expect_false(gates[key], "decision.gates.$key")
    end
    return gates
end

function _validate_prospective_boundary(root)
    location = "decision.prospective_boundary"
    boundary = expect_exact_keys(
        root["prospective_boundary"],
        PROSPECTIVE_BOUNDARY_KEYS,
        location,
    )
    exact_values = (
        "freeze_date" => OBSERVED_DATE,
        "public_and_inspected_through_quarter" => "2026Q2",
        "earliest_genuinely_prospective_quarter" => "2026Q3",
        "adjacent_reserve_id" =>
            "ADJACENT_2026Q2_EVALUATION_RESERVE",
    )
    for (key, expected) in exact_values
        expect_exact(boundary[key], expected, "$location.$key")
    end
    integrity = expect_member(
        boundary["adjacent_reserve_holdout_integrity"],
        HOLDOUT_INTEGRITY_STATES,
        "$location.adjacent_reserve_holdout_integrity",
    )
    expect_exact(
        integrity,
        "UNVERIFIED",
        "$location.adjacent_reserve_holdout_integrity",
    )
    expect_exact(
        _quarter_index(
            boundary["earliest_genuinely_prospective_quarter"],
            "$location.earliest_genuinely_prospective_quarter",
        ) -
            _quarter_index(
            boundary["public_and_inspected_through_quarter"],
            "$location.public_and_inspected_through_quarter",
        ),
        1,
        "$location prospective adjacency",
    )
    for key in (
            "adjacent_reserve_is_prospective",
            "prospective_reserve_registered",
            "origin_admitted",
            "empirical_execution_allowed",
        )
        expect_false(boundary[key], "$location.$key")
    end
    return boundary
end

function _validate_false_evidence_axes(row, location)
    for key in (
            "source_coverage_proven",
            "terms_authorization_complete",
            "artifact_capture_complete",
            "truth_maturity_proven",
            "origin_admission_complete",
        )
        expect_false(row[key], "$location.$key")
    end
    return nothing
end

function _validate_windows(root)
    records =
        expect_array(root["source_windows"], "decision.source_windows")
    length(records) == length(EXPECTED_WINDOWS) ||
        fail("decision.source_windows", "must contain exactly 3 windows")
    validated = NamedTuple[]
    for (sequence, (record, expected)) in
        enumerate(zip(records, EXPECTED_WINDOWS))
        location = "decision.source_windows[$sequence]"
        row = expect_exact_keys(record, WINDOW_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        for key in (
                :window_id,
                :source_id,
                :first_quarter,
                :last_quarter,
                :quarter_count,
            )
            expect_exact(
                row[String(key)],
                getproperty(expected, key),
                "$location.$(String(key))",
            )
        end
        arithmetic_count = _quarter_count(
            row["first_quarter"],
            row["last_quarter"],
            location,
        )
        expect_exact(
            expect_integer(
                row["quarter_count"],
                "$location.quarter_count";
                minimum = 1,
            ),
            arithmetic_count,
            "$location.quarter_count",
        )
        for (key, allowed) in (
                "coverage_state" => COVERAGE_STATES,
                "artifact_provenance_state" =>
                    ARTIFACT_PROVENANCE_STATES,
                "concept_state" => CONCEPT_STATES,
                "terms_state" => TERMS_STATES,
                "artifact_capture_state" => ARTIFACT_CAPTURE_STATES,
                "truth_maturity_state" => TRUTH_MATURITY_STATES,
                "origin_admission_state" => ORIGIN_ADMISSION_STATES,
            )
            expect_member(row[key], allowed, "$location.$key")
        end
        for key in (
                :coverage_state,
                :artifact_provenance_state,
                :concept_state,
                :terms_state,
                :artifact_capture_state,
            )
            expect_exact(
                row[String(key)],
                getproperty(expected, key),
                "$location.$(String(key))",
            )
        end
        expect_exact(
            row["truth_maturity_state"],
            "TRUTH_MATURITY_NOT_PROVEN",
            "$location.truth_maturity_state",
        )
        expect_exact(
            row["origin_admission_state"],
            "ZERO_ORIGINS_ADMITTED",
            "$location.origin_admission_state",
        )
        _validate_false_evidence_axes(row, location)
        push!(validated, _freeze(row))
    end
    return Tuple(validated)
end

function _reproduced_intersection(members, windows, location)
    by_id = Dict(window.window_id => window for window in windows)
    selected = NamedTuple[]
    for member in members
        haskey(by_id, member) ||
            fail(location, "references unknown source window $member")
        push!(selected, by_id[member])
    end
    first_index = maximum(
        _quarter_index(window.first_quarter, location) for window in selected
    )
    last_index = minimum(
        _quarter_index(window.last_quarter, location) for window in selected
    )
    last_index >= first_index ||
        fail(location, "source windows have an empty intersection")
    return (
        first_quarter = _quarter_label(first_index),
        last_quarter = _quarter_label(last_index),
        quarter_count = last_index - first_index + 1,
    )
end

function _validate_intersections(root, windows)
    records =
        expect_array(root["intersections"], "decision.intersections")
    length(records) == length(EXPECTED_INTERSECTIONS) ||
        fail(
        "decision.intersections",
        "must contain exactly 4 intersections",
    )
    validated = NamedTuple[]
    for (sequence, (record, expected)) in
        enumerate(zip(records, EXPECTED_INTERSECTIONS))
        location = "decision.intersections[$sequence]"
        row = expect_exact_keys(record, INTERSECTION_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        expect_exact(
            row["intersection_id"],
            expected.intersection_id,
            "$location.intersection_id",
        )
        members = Tuple(
            expect_string(member, "$location.member_window_ids") for
                member in expect_array(
                    row["member_window_ids"],
                    "$location.member_window_ids",
                )
        )
        expect_exact(
            members,
            expected.member_window_ids,
            "$location.member_window_ids",
        )
        reproduced = _reproduced_intersection(members, windows, location)
        for key in (:first_quarter, :last_quarter, :quarter_count)
            expect_exact(
                row[String(key)],
                getproperty(reproduced, key),
                "$location.$(String(key))",
            )
            expect_exact(
                row[String(key)],
                getproperty(expected, key),
                "$location.$(String(key))",
            )
        end
        expect_exact(
            expect_integer(
                row["strict_admitted_origin_count"],
                "$location.strict_admitted_origin_count";
                minimum = 0,
            ),
            0,
            "$location.strict_admitted_origin_count",
        )
        expect_false(row["strict_admissible"], "$location.strict_admissible")
        push!(validated, _freeze(row))
    end
    return Tuple(validated)
end

function _validate_effr_roles(root)
    records = expect_array(
        root["effr_window_roles"],
        "decision.effr_window_roles",
    )
    length(records) == length(EXPECTED_EFFR_ROLES) ||
        fail(
        "decision.effr_window_roles",
        "must contain exactly 3 role windows",
    )
    validated = NamedTuple[]
    for (sequence, (record, expected)) in
        enumerate(zip(records, EXPECTED_EFFR_ROLES))
        location = "decision.effr_window_roles[$sequence]"
        row = expect_exact_keys(record, EFFR_ROLE_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        for key in (
                :role_id,
                :first_quarter,
                :last_quarter,
                :quarter_count,
                :status,
                :included_in_fixed_40,
                :public_at_freeze,
                :prospective_at_freeze,
            )
            expect_exact(
                row[String(key)],
                getproperty(expected, key),
                "$location.$(String(key))",
            )
        end
        reserve_class = expect_member(
            row["reserve_class"],
            RESERVE_CLASSES,
            "$location.reserve_class",
        )
        holdout_integrity = expect_member(
            row["holdout_integrity"],
            HOLDOUT_INTEGRITY_STATES,
            "$location.holdout_integrity",
        )
        expect_exact(
            reserve_class,
            expected.reserve_class,
            "$location.reserve_class",
        )
        expect_exact(
            holdout_integrity,
            expected.holdout_integrity,
            "$location.holdout_integrity",
        )
        expect_exact(
            expect_bool(row["public_at_freeze"], "$location.public_at_freeze"),
            true,
            "$location.public_at_freeze",
        )
        expect_false(
            row["prospective_at_freeze"],
            "$location.prospective_at_freeze",
        )
        expect_exact(
            expect_integer(
                row["quarter_count"],
                "$location.quarter_count";
                minimum = 1,
            ),
            _quarter_count(
                row["first_quarter"],
                row["last_quarter"],
                location,
            ),
            "$location.quarter_count",
        )
        expect_false(row["origin_admitted"], "$location.origin_admitted")
        expect_false(
            row["empirical_execution_allowed"],
            "$location.empirical_execution_allowed",
        )
        push!(validated, _freeze(row))
    end
    route = validated[1]
    candidate = validated[2]
    adjacent_reserve = validated[3]
    expect_exact(
        _quarter_index(adjacent_reserve.first_quarter, "adjacent reserve") -
            _quarter_index(candidate.last_quarter, "candidate"),
        1,
        "decision.effr_window_roles adjacent-reserve adjacency",
    )
    expect_exact(
        route.quarter_count,
        candidate.quarter_count + adjacent_reserve.quarter_count,
        "decision.effr_window_roles route decomposition",
    )
    return Tuple(validated)
end

function _validate_tracks(root)
    records = expect_array(root["tracks"], "decision.tracks")
    length(records) == length(EXPECTED_TRACKS) ||
        fail("decision.tracks", "must contain exactly 4 tracks")
    validated = NamedTuple[]
    for (sequence, (record, expected)) in
        enumerate(zip(records, EXPECTED_TRACKS))
        location = "decision.tracks[$sequence]"
        row = expect_exact_keys(record, TRACK_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        track_id = expect_member(row["track_id"], TRACK_IDS, "$location.track_id")
        expect_exact(track_id, expected.track_id, "$location.track_id")
        conclusion = expect_member(
            row["allowed_conclusion"],
            ALLOWED_CONCLUSIONS,
            "$location.allowed_conclusion",
        )
        expect_exact(
            conclusion,
            expected.allowed_conclusion,
            "$location.allowed_conclusion",
        )
        blockers = Tuple(
            expect_member(
                    blocker,
                    BLOCKER_STATES,
                    "$location.blockers",
                ) for
                blocker in expect_array(row["blockers"], "$location.blockers")
        )
        length(blockers) == length(Set(blockers)) ||
            fail("$location.blockers", "must be unique")
        expect_exact(blockers, expected.blockers, "$location.blockers")
        _validate_false_evidence_axes(row, location)
        expect_false(
            row["empirical_execution_allowed"],
            "$location.empirical_execution_allowed",
        )
        expect_false(
            row["production_eligible"],
            "$location.production_eligible",
        )
        push!(validated, _freeze(row))
    end
    return Tuple(validated)
end

function _validate_source_routes(root)
    records =
        expect_array(root["source_routes"], "decision.source_routes")
    length(records) == length(EXPECTED_ROUTE_IDS) ||
        fail("decision.source_routes", "must contain exactly 6 routes")
    validated = NamedTuple[]
    for (sequence, (record, expected_id)) in
        enumerate(zip(records, EXPECTED_ROUTE_IDS))
        location = "decision.source_routes[$sequence]"
        row = expect_exact_keys(record, SOURCE_ROUTE_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        expect_exact(row["route_id"], expected_id, "$location.route_id")
        expect_string(row["agency"], "$location.agency")
        expect_member(
            row["artifact_provenance_state"],
            ARTIFACT_PROVENANCE_STATES,
            "$location.artifact_provenance_state",
        )
        expect_member(
            row["source_role"],
            SOURCE_ROLES,
            "$location.source_role",
        )
        expect_member(
            row["concept_state"],
            CONCEPT_STATES,
            "$location.concept_state",
        )
        expect_member(
            row["terms_state"],
            TERMS_STATES,
            "$location.terms_state",
        )
        expect_member(
            row["coverage_state"],
            COVERAGE_STATES,
            "$location.coverage_state",
        )
        expect_member(
            row["artifact_capture_state"],
            ARTIFACT_CAPTURE_STATES,
            "$location.artifact_capture_state",
        )
        expect_member(
            row["truth_maturity_state"],
            TRUTH_MATURITY_STATES,
            "$location.truth_maturity_state",
        )
        expect_member(
            row["origin_admission_state"],
            ORIGIN_ADMISSION_STATES,
            "$location.origin_admission_state",
        )
        expect_string(row["allowed_use"], "$location.allowed_use")
        _validate_false_evidence_axes(row, location)
        push!(validated, _freeze(row))
    end
    by_id = Dict(row.route_id => row for row in validated)
    expect_exact(
        by_id["ALFRED_EFFR_DATE_LEVEL_VINTAGE"].terms_state,
        "TERMS_LOCAL_GOVERNANCE_BLOCKED_PENDING_REVIEW",
        "decision.source_routes ALFRED terms",
    )
    for id in ("NYFED_EFFR_CURRENT_API", "BOARD_H15_CURRENT_SERIES")
        expect_exact(
            by_id[id].artifact_provenance_state,
            "CURRENT_STATE_WITH_REVISION_FLAG_NOT_VINTAGE",
            "decision.source_routes $id provenance",
        )
    end
    expect_exact(
        by_id["BOARD_H15_PRE_2016_ISSUE_ARCHIVE"].concept_state,
        "CONCEPT_BREAK",
        "decision.source_routes pre-2016 concept",
    )
    return Tuple(validated)
end

function _validate_irregularities(root, citation_ids)
    records =
        expect_array(root["irregularities"], "decision.irregularities")
    length(records) == length(EXPECTED_IRREGULARITIES) ||
        fail(
        "decision.irregularities",
        "must contain exactly 5 irregularities",
    )
    validated = NamedTuple[]
    for (sequence, (record, expected)) in
        enumerate(zip(records, EXPECTED_IRREGULARITIES))
        location = "decision.irregularities[$sequence]"
        row = expect_exact_keys(record, IRREGULARITY_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        period = expect_string(row["period"], "$location.period")
        occursin(QUARTER_PATTERN, period) ||
            occursin(MONTH_PATTERN, period) ||
            fail("$location.period", "must be canonical quarter or month")
        for key in (
                :period,
                :agency,
                :irregularity_state,
                :panel_relation,
                :evidence_citation_id,
            )
            expect_exact(
                row[String(key)],
                getproperty(expected, key),
                "$location.$(String(key))",
            )
        end
        expect_member(
            row["irregularity_state"],
            IRREGULARITY_STATES,
            "$location.irregularity_state",
        )
        expect_member(
            row["panel_relation"],
            PANEL_RELATIONS,
            "$location.panel_relation",
        )
        expect_string(row["treatment"], "$location.treatment")
        citation_id = expect_string(
            row["evidence_citation_id"],
            "$location.evidence_citation_id",
        )
        citation_id in citation_ids ||
            fail("$location.evidence_citation_id", "is not a known citation")
        expect_false(row["admitted"], "$location.admitted")
        push!(validated, _freeze(row))
    end
    return Tuple(validated)
end

function _validate_citations(root)
    records = expect_array(root["citations"], "decision.citations")
    length(records) == length(EXPECTED_CITATION_URLS) ||
        fail(
        "decision.citations",
        "must contain exactly $(length(EXPECTED_CITATION_URLS)) citations",
    )
    validated = NamedTuple[]
    for (sequence, (record, expected)) in
        enumerate(zip(records, EXPECTED_CITATION_URLS))
        location = "decision.citations[$sequence]"
        row = expect_exact_keys(record, CITATION_KEYS, location)
        expect_exact(
            expect_integer(row["sequence"], "$location.sequence"; minimum = 1),
            sequence,
            "$location.sequence",
        )
        expected_id, expected_url = expected
        expect_exact(row["citation_id"], expected_id, "$location.citation_id")
        citation_class =
            expect_string(row["citation_class"], "$location.citation_class")
        citation_class in ("OFFICIAL", "ACADEMIC") ||
            fail(
            "$location.citation_class",
            "must be OFFICIAL or ACADEMIC",
        )
        expect_string(row["title"], "$location.title")
        url = expect_string(row["url"], "$location.url")
        startswith(url, "https://") ||
            fail("$location.url", "must use HTTPS")
        expect_exact(url, expected_url, "$location.url")
        expect_string(row["supports"], "$location.supports")
        push!(validated, _freeze(row))
    end
    return Tuple(validated)
end

"""
    validate_decision(decision)

Validate the sealed offline decision. The compiled semantic digest is
mandatory. The return graph is immutable and never aliases parsed TOML.
"""
function validate_decision(value)
    root = expect_exact_keys(value, ROOT_KEYS, "decision")
    decision = _validate_decision_metadata(root)
    gates = _validate_gates(root)
    prospective_boundary = _validate_prospective_boundary(root)
    windows = _validate_windows(root)
    intersections = _validate_intersections(root, windows)
    effr_roles = _validate_effr_roles(root)
    tracks = _validate_tracks(root)
    source_routes = _validate_source_routes(root)
    citations = _validate_citations(root)
    citation_ids = Set(row.citation_id for row in citations)
    irregularities = _validate_irregularities(root, citation_ids)
    content_sha256 = _validate_artifact(root)
    return (;
        artifact = (
            schema_version = SCHEMA_VERSION,
            canonicalization = CANONICALIZATION,
            content_sha256 = String(content_sha256),
        ),
        decision = _freeze(decision),
        gates = _freeze(gates),
        prospective_boundary = _freeze(prospective_boundary),
        source_windows = windows,
        intersections,
        effr_window_roles = effr_roles,
        tracks,
        source_routes,
        irregularities,
        citations,
    )
end

function _read_decision(path)
    absolute = abspath(String(path))
    isfile(absolute) || fail("decision", "file does not exist: $absolute")
    islink(absolute) && fail("decision", "must not be a symbolic link")
    bytes = try
        read(absolute)
    catch error
        fail("decision", "could not read file: $(sprint(showerror, error))")
    end
    document = try
        TOML.parse(String(copy(bytes)))
    catch error
        fail("decision", "could not parse TOML: $(sprint(showerror, error))")
    end
    return (; absolute, bytes, document)
end

"""
    load_decision([path])

Read and validate one local TOML decision without network access.
"""
function load_decision(path::AbstractString = DEFAULT_DECISION_PATH)
    source = _read_decision(path)
    return validate_decision(source.document)
end

"""
    decision_artifact([path])

Return the immutable validated decision, canonical content, and file
identity. Raw manifest bytes and mutable parsed tables are never returned.
"""
function decision_artifact(path::AbstractString = DEFAULT_DECISION_PATH)
    source = _read_decision(path)
    validated = validate_decision(source.document)
    return (;
        path = source.absolute,
        artifact = validated.artifact,
        decision = validated.decision,
        gates = validated.gates,
        prospective_boundary = validated.prospective_boundary,
        source_windows = validated.source_windows,
        intersections = validated.intersections,
        effr_window_roles = validated.effr_window_roles,
        tracks = validated.tracks,
        source_routes = validated.source_routes,
        irregularities = validated.irregularities,
        citations = validated.citations,
        canonical_content =
            String(_canonical_content_bytes(source.document)),
        file_sha256 = bytes2hex(sha256(source.bytes)),
        file_byte_count = length(source.bytes),
    )
end

end
