module USEFFRObservedStateContractV3

using Dates
using JSON
using SHA
using TOML

export CapturedReport,
    DecisionBinding,
    MORNING_WINDOW_ENDPOINT_OBSERVATION,
    OBSERVED_EFFR_TRANSITION,
    ObservedStateContractError,
    POST_REVISION_WINDOW_ENDPOINT_OBSERVATION,
    adjudicate_morning_observation,
    adjudicate_transition,
    decision_document,
    load_protocol,
    observation_document,
    protocol_semantic_sha256,
    validate_decision_document,
    validate_endpoint_observation,
    validate_protocol,
    validate_protocol_document,
    validate_report

const SCHEMA_VERSION = "beforeit-us-effr-observed-state-contract.v3"
const CONTRACT_VERSION = "3.0.0"
const MORNING_WINDOW_ENDPOINT_OBSERVATION =
    "MORNING_WINDOW_ENDPOINT_OBSERVATION"
const POST_REVISION_WINDOW_ENDPOINT_OBSERVATION =
    "POST_REVISION_WINDOW_ENDPOINT_OBSERVATION"
const OBSERVED_EFFR_TRANSITION = "OBSERVED_EFFR_TRANSITION"
const V2_SCHEMA_VERSION =
    "beforeit-us-effr-one-effective-date-capture-receipt.v2"
const V2_ABSENT_STATUS =
    "NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT"
const ESTIMAND_STATUS = "PENDING"
const ESTIMAND_CANDIDATES = (
    "STRICT_FIRST_PUBLIC_BYTES",
    "PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE",
)
const DATA_ENDPOINT =
    "https://markets.newyorkfed.org/api/rates/all/search.json"
const FINAL_HOST = "markets.newyorkfed.org"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const ID_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:-]*$"
const HEADER_NAME_PATTERN = r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$"
const JSON_NUMBER_PATTERN =
    r"^-?(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$"
const JSON_INTEGER_PATTERN = r"^-?(0|[1-9][0-9]*)$"
const MAX_JSON_BODY_BYTES = 1_048_576
const MAX_JSON_NESTING_DEPTH = 64
const MAX_JSON_NUMBER_BYTES = 96
const MAX_JSON_MANTISSA_DIGITS = 40
const MAX_JSON_ABS_EXPONENT = 20
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sss"
const ALLOWED_REVISION_TOKENS = ("", "r")
const SUPPORTED_TYPES =
    ("EFFR", "OBFR", "TGCR", "BGCR", "SOFR", "SOFRAI")
const SUPPORTED_FOOTNOTE_IDS = (1, 2, 3)
const FOOTNOTE_CLASS = Dict(
    1 => "REDUCED_VOLUME",
    2 => "BROKER_CONTINGENCY",
    3 => "PRIOR_DAY_REPUBLICATION",
)
const RATE_FIELDS = (
    "percentRate",
    "percentPercentile1",
    "percentPercentile25",
    "percentPercentile75",
    "percentPercentile99",
    "targetRateFrom",
    "targetRateTo",
)
const ORDINARY_RATE_FIELDS = (
    "percentRate",
    "percentPercentile1",
    "percentPercentile25",
    "percentPercentile75",
    "percentPercentile99",
)
const AVERAGE_RATE_FIELDS =
    ("average30day", "average90day", "average180day", "index")
const CAMPAIGN_CONTROL_FILE_SHA256 =
    "83db9b24f88e7ad48ba21726f7905b2ba7a00638e681ff40d8fdcf0c728edd02"
const CAMPAIGN_SCHEDULE_FILE_SHA256 =
    "ddbc7a089a636d09f97e68e67da7f534ecca6c88d6b7dbc8bf78080ce7400e25"
const CAMPAIGN_SCHEDULE_CONTENT_SHA256 =
    "fb984becfc5608922cd4acffd7e3e3bdf997022935f816acad221ec32dcd0383"
const PROSPECTIVE_CONTRACT_FILE_SHA256 =
    "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
const PROSPECTIVE_CONTRACT_CONTENT_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const V2_CONTRACT_SOURCE_SHA256 =
    "6c4ee3ff95b92daf34899db64dbff7fc920eb33e5bc4bf17a6adf99bf3b3f651"
const AUGUST7_MANIFEST_FILE_SHA256 =
    "f801b5539a550857a4ca6c69e0f16ad1c7645ab83e3c87407a0c99aeed4db6d1"
const AUGUST7_MANIFEST_SEMANTIC_SHA256 =
    "9a865a8b60f06b0da33be4f48e40266d986d633d250715c55c69fb113d130885"
const AUGUST7_RATE_RAW_SHA256 =
    "5977e0aafae9f34d348ad69166afce47c223b6147312654155855e0450315341"
const AUGUST7_VOLUME_RAW_SHA256 =
    "13f146b7f27a724f28a63343fed40c1cdb3c447eec1a5663d5b1b5f192febc61"
const API_DOCUMENTATION_SHA256 =
    "c1ab76a0e006e7f16c5ba4660716f2ade0f8a76e58dbbe7124d73a9fbf98cd2c"
const OPENAPI_SHA256 =
    "5dbb331d86b91bfc115be9b5fe9c46735833a4f7280d33e4327e8acf7ad30d2b"
const TERMS_SHA256 =
    "a2904b4679f340f17330c845f481399398f7aeb1fabae5ca14781f15ed3d776b"
const HOLIDAY_SHA256 =
    "2d4c37577b6e439136ef15ccf1d56869133e1342a292310417f190d24e239b17"
const PROTOCOL_PATH = joinpath(@__DIR__, "observed_state_contract_v3.toml")
const CAMPAIGN_CONTROL_PATH =
    normpath(joinpath(@__DIR__, "..", "campaign", "USEFFRCampaignControl.jl"))
const CAMPAIGN_SCHEDULE_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "campaign",
        "effr_2026q3_campaign_schedule.toml",
    ),
)
const PROSPECTIVE_CONTRACT_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "prospective",
        "prospective_2026q3_contract_v2.toml",
    ),
)
const V2_CONTRACT_SOURCE_PATH = normpath(
    joinpath(@__DIR__, "..", "capture_contract", "USEFFRCaptureContract.jl"),
)
const ALWAYS_FALSE_GATES = (
    "accuracy_evaluation_allowed",
    "empirical_forecast_allowed",
    "external_timestamp_authenticated",
    "full_campaign_complete",
    "network_exchange_count_externally_witnessed",
    "operator_authorization_externally_authenticated",
    "origin_admissible",
    "other_required_profiles_complete",
    "production_use_allowed",
    "production_scoring_allowed",
    "profile_completion_authorized",
    "promotion_eligible",
    "publisher_provenance_authenticated",
    "raw_durably_stored_external",
    "readiness",
    "source_inventory_mutation_allowed",
    "transport_provenance_authenticated",
)
const BASE_BLOCKERS = (
    "CURRENT_OPENAPI_CURRENT_STATE_DEFINITION_ABSENT",
    "CAPTURED_WIRE_CURRENT_STATE_ABSENT",
    "CURRENT_STATE_EVER_OFFICIAL_NOT_ESTABLISHED",
    "CURRENT_STATE_FALSE_DERIVATION_FORBIDDEN",
    "RATE_VOLUME_REQUESTS_SEQUENTIAL_NOT_ATOMIC",
    "EXTERNAL_TIMESTAMP_NOT_AUTHENTICATED",
    "TRANSPORT_PROVENANCE_NOT_AUTHENTICATED",
    "PUBLISHER_PROVENANCE_NOT_AUTHENTICATED",
    "NETWORK_EXCHANGE_COUNT_NOT_INDEPENDENTLY_WITNESSED",
    "OPERATOR_AUTHORIZATION_NOT_EXTERNALLY_AUTHENTICATED",
    "DURABLE_EXTERNAL_STORAGE_NOT_ESTABLISHED",
    "FULL_CAMPAIGN_NOT_COMPLETE",
    "OTHER_REQUIRED_PROFILES_NOT_COMPLETE",
    "ESTIMAND_SELECTION_PENDING",
    "ORIGIN_ADMISSION_FORBIDDEN",
    "SCORING_FORBIDDEN",
    "PROMOTION_FORBIDDEN",
)
const OUTCOME_CLAIMS = Dict(
    "MORNING_WINDOW_ENDPOINT_OBSERVATION_RECORDED" =>
        "STATE_OBSERVED_BY_RECORDED_RATE_AND_VOLUME_COMPLETION_TIMES",
    "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE" =>
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE",
    "MARKED_SAME_DAY_REVISION_OBSERVED" =>
        "MARKED_SAME_DAY_REVISION_OBSERVED",
    "QUARANTINED_MORNING_ALREADY_MARKED_REVISED" =>
        "MORNING_ENDPOINT_NOT_CLASSIFIED_AS_FIRST_PUBLICATION",
    "QUARANTINED_UNMARKED_EFFR_TRANSITION" =>
        "SELECTED_EFFR_SEMANTICS_CHANGED_WITHOUT_RAW_R_TOKEN",
    "QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT" =>
        "RAW_R_TOKEN_LACKS_STRICTLY_GREATER_THAN_ONE_BASIS_POINT_RATE_CHANGE",
    "QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION" =>
        "FULL_RESPONSE_CHANGED_WITHOUT_SELECTED_EFFR_TRANSITION",
)

struct ObservedStateContractError <: Exception
    code::String
    location::String
    message::String
end

Base.showerror(io::IO, error::ObservedStateContractError) = print(
    io,
    error.code,
    " at ",
    error.location,
    ": ",
    error.message,
)

fail(code, location, message) =
    throw(ObservedStateContractError(code, location, message))

struct ExactJSONNumber
    lexeme::String
    value::Rational{BigInt}
end

Base.@kwdef struct CapturedReport
    report_type::String
    body::Vector{UInt8}
    canonical_query::String
    requested_url::String
    final_url::String
    http_status::Int
    redirect_count::Int
    response_headers::Vector{Pair{String, String}}
    request_started_at_utc::DateTime
    response_body_completed_at_utc::DateTime
    response_metadata_observed_at_utc::DateTime
end

Base.@kwdef struct DecisionBinding
    decision_id::String
    created_at_utc::DateTime
    predecessor_observation_sha256::String
    predecessor_decision_sha256::String
    superseded_contract_schema_version::String = V2_SCHEMA_VERSION
    superseded_capture_manifest_sha256::String
    superseded_receipt_status::String = V2_ABSENT_STATUS
    supersession_mode::String =
        "APPEND_ONLY_OFFLINE_READJUDICATION_NO_MUTATION_NO_BACKDATING"
    timestamp_evidence_status::String = "NOT_PROVIDED"
    timestamp_token_sha256::String = "NONE"
end

struct ParsedReport
    report_type::String
    raw_sha256::String
    raw_byte_count::Int
    http_status::Int
    redirect_count::Int
    response_headers::Tuple
    response_headers_sha256::String
    selected_json_pointer::String
    selected_row_sha256::String
    selected_value_sha256::String
    selected_fields::Tuple
    revision_token::String
    footnote_token::String
    footnote_class::String
    request_started_at_utc::DateTime
    response_body_completed_at_utc::DateTime
    response_metadata_observed_at_utc::DateTime
    canonical_query::String
    requested_url::String
    final_url::String
end

struct EndpointObservation
    schema_version::String
    observation_class::String
    publication_date::Date
    effective_date::Date
    rate::ParsedReport
    volume::ParsedReport
    rate_completion_claim::String
    volume_completion_claim::String
    pair_as_of_utc::DateTime
    requests_sequential_not_atomic::Bool
    observation_sha256::String
end

sha256_hex(bytes) = bytes2hex(sha256(bytes))

function _expect_dict(value, location)
    value isa AbstractDict ||
        fail("TYPE_MISMATCH", location, "must be a table/object")
    all(key -> key isa AbstractString, keys(value)) ||
        fail("TYPE_MISMATCH", location, "all keys must be strings")
    return value
end

function _closed_keys(value, expected, location)
    table = _expect_dict(value, location)
    actual = Set(String.(keys(table)))
    wanted = Set(String.(expected))
    actual == wanted || fail(
        "CLOSED_SCHEMA_VIOLATION",
        location,
        "expected keys $(sort!(collect(wanted))), got $(sort!(collect(actual)))",
    )
    return table
end

function _expect_string(value, location; allow_empty = false)
    value isa String ||
        fail("TYPE_MISMATCH", location, "must be a String")
    value == strip(value) ||
        fail("NONCANONICAL_STRING", location, "has surrounding whitespace")
    (allow_empty || !isempty(value)) ||
        fail("MISSING_TOKEN", location, "must not be empty")
    return value
end

function _expect_bool(value, expected, location)
    value isa Bool || fail("TYPE_MISMATCH", location, "must be Bool")
    value === expected ||
        fail("TRUST_ELEVATION_FORBIDDEN", location, "must remain $expected")
    return value
end

function _expect_int(value, location; minimum = nothing)
    value isa Int && !(value isa Bool) ||
        fail("TYPE_MISMATCH", location, "must be Int and not Bool")
    minimum !== nothing && value < minimum &&
        fail("RANGE_VIOLATION", location, "must be at least $minimum")
    return value
end

function _expect_hash(value, location; allow_none = false)
    text = _expect_string(value, location)
    allow_none && text == "NONE" && return text
    occursin(HASH_PATTERN, text) ||
        fail("INVALID_SHA256", location, "must be lowercase SHA-256")
    return text
end

function _expect_id(value, location)
    text = _expect_string(value, location)
    occursin(ID_PATTERN, text) ||
        fail("INVALID_IDENTIFIER", location, "is outside the closed syntax")
    return text
end

function _expect_exact_json_number(value, location; nonnegative = false)
    value isa ExactJSONNumber ||
        fail("TYPE_MISMATCH", location, "must be an RFC 8259 JSON number")
    nonnegative && value.value < 0 // 1 &&
        fail("RANGE_VIOLATION", location, "must be nonnegative")
    return value
end

function _canonical(value)
    if value isa AbstractDict
        keys_sorted = sort!(String.(collect(keys(value))))
        length(keys_sorted) == length(unique(keys_sorted)) ||
            fail("DUPLICATE_KEY", "canonicalization", "duplicate table key")
        payload = join(
            (
                "K$(ncodeunits(key)):$key" * _canonical(value[key]) for
                    key in keys_sorted
            ),
        )
        return "D$(length(keys_sorted)):$payload"
    elseif value isa NamedTuple
        return _canonical(Dict(String(key) => item for (key, item) in pairs(value)))
    elseif value isa Pair
        return "P" * _canonical(first(value)) * _canonical(last(value))
    elseif value isa Tuple || value isa AbstractVector
        return "A$(length(value)):" * join(_canonical(item) for item in value)
    elseif value isa String
        return "S$(ncodeunits(value)):$value"
    elseif value isa Bool
        return value ? "B1" : "B0"
    elseif value isa Integer
        return "I$(value)"
    elseif value isa AbstractFloat
        isfinite(value) ||
            fail("NONFINITE_VALUE", "canonicalization", "float must be finite")
        return "F$(bitstring(Float64(value)))"
    elseif value isa DateTime
        return "T$(Dates.format(value, TIMESTAMP_FORMAT))Z"
    elseif value isa Date
        return "E$(string(value))"
    elseif value === nothing
        return "N"
    end
    return fail(
        "UNSUPPORTED_CANONICAL_TYPE",
        "canonicalization",
        "unsupported type $(typeof(value))",
    )
end

semantic_sha256(value) = sha256_hex(codeunits(_canonical(value)))

function protocol_semantic_sha256(document)
    copy_document = deepcopy(_expect_dict(document, "protocol"))
    artifact = _expect_dict(get(copy_document, "artifact", nothing), "artifact")
    haskey(artifact, "content_sha256") ||
        fail("MISSING_FIELD", "artifact", "content_sha256 is required")
    delete!(artifact, "content_sha256")
    return semantic_sha256(copy_document)
end

function _decision_semantic_sha256(document)
    copy_document = deepcopy(_expect_dict(document, "decision"))
    artifact = _expect_dict(get(copy_document, "artifact", nothing), "artifact")
    haskey(artifact, "decision_sha256") ||
        fail("MISSING_FIELD", "artifact", "decision_sha256 is required")
    delete!(artifact, "decision_sha256")
    return semantic_sha256(copy_document)
end

function _file_sha256(path, location)
    isfile(path) ||
        fail("SOURCE_BINDING_MISSING", location, "missing file $path")
    islink(path) &&
        fail("SOURCE_BINDING_SYMLINK", location, "refuses symbolic link $path")
    try
        return sha256_hex(read(path))
    catch error
        error isa ObservedStateContractError && rethrow()
        fail("SOURCE_BINDING_READ_FAILED", location, sprint(showerror, error))
    end
end

function _validate_local_source_bindings()
    bindings = (
        (
            CAMPAIGN_CONTROL_PATH,
            CAMPAIGN_CONTROL_FILE_SHA256,
            "campaign control",
        ),
        (
            CAMPAIGN_SCHEDULE_PATH,
            CAMPAIGN_SCHEDULE_FILE_SHA256,
            "campaign schedule",
        ),
        (
            PROSPECTIVE_CONTRACT_PATH,
            PROSPECTIVE_CONTRACT_FILE_SHA256,
            "prospective v2 contract",
        ),
        (
            V2_CONTRACT_SOURCE_PATH,
            V2_CONTRACT_SOURCE_SHA256,
            "one-date v2 source",
        ),
    )
    for (path, expected, label) in bindings
        _file_sha256(path, label) == expected ||
            fail("SOURCE_BINDING_CHANGED", label, "SHA-256 does not match")
    end
    return true
end

function load_protocol(path = PROTOCOL_PATH)
    isfile(path) ||
        fail("PROTOCOL_MISSING", "protocol", "missing file $path")
    islink(path) &&
        fail("PROTOCOL_SYMLINK", "protocol", "refuses symbolic link $path")
    document = try
        TOML.parsefile(path)
    catch error
        fail("PROTOCOL_PARSE_FAILED", "protocol", sprint(showerror, error))
    end
    return validate_protocol_document(document)
end

function _validate_exact_array(value, expected, location)
    value isa AbstractVector ||
        fail("TYPE_MISMATCH", location, "must be an array")
    length(value) == length(expected) ||
        fail("CLOSED_SCHEMA_VIOLATION", location, "array length differs")
    for index in eachindex(expected)
        typeof(value[index]) === typeof(expected[index]) ||
            fail("TYPE_MISMATCH", "$location[$index]", "type differs")
        isequal(value[index], expected[index]) ||
            fail("CLOSED_SCHEMA_VIOLATION", "$location[$index]", "value differs")
    end
    return value
end

function validate_protocol_document(document; verify_sources = true)
    protocol = _closed_keys(
        document,
        (
            "artifact",
            "citations",
            "current_state_disposition",
            "estimand",
            "gates",
            "observations",
            "parser",
            "policy",
            "source_bindings",
            "transition_matrix",
        ),
        "protocol",
    )
    artifact = _closed_keys(
        protocol["artifact"],
        (
            "canonicalization",
            "content_sha256",
            "contract_id",
            "contract_version",
            "incompatible_with",
            "schema_version",
            "status",
        ),
        "artifact",
    )
    _expect_string(artifact["schema_version"], "artifact.schema_version") ==
        SCHEMA_VERSION ||
        fail("WRONG_SCHEMA_VERSION", "artifact.schema_version", "must be v3")
    _expect_string(artifact["contract_id"], "artifact.contract_id") ==
        "beforeit-us-effr-observed-state-offline-adjudication.v3" ||
        fail("WRONG_CONTRACT_ID", "artifact.contract_id", "must remain exact")
    _expect_string(artifact["contract_version"], "artifact.contract_version") ==
        CONTRACT_VERSION ||
        fail("WRONG_CONTRACT_VERSION", "artifact.contract_version", "must be 3.0.0")
    _expect_string(artifact["incompatible_with"], "artifact.incompatible_with") ==
        V2_SCHEMA_VERSION ||
        fail("COMPATIBILITY_ERROR", "artifact.incompatible_with", "must name v2")
    _expect_string(artifact["status"], "artifact.status") ==
        "CANDIDATE_OFFLINE_NONADMITTING" ||
        fail("TRUST_ELEVATION_FORBIDDEN", "artifact.status", "must remain candidate")
    _expect_string(artifact["canonicalization"], "artifact.canonicalization") ==
        "sorted_typed_length_aware_excluding_artifact_content_sha256.v1" ||
        fail("CANONICALIZATION_CHANGED", "artifact.canonicalization", "unsupported")
    embedded = _expect_hash(artifact["content_sha256"], "artifact.content_sha256")
    reproduced = protocol_semantic_sha256(protocol)
    embedded == reproduced ||
        fail("PROTOCOL_DIGEST_MISMATCH", "artifact.content_sha256", "does not reproduce")

    disposition = _closed_keys(
        protocol["current_state_disposition"],
        (
            "authoritative_evidence_ever_official",
            "captured_wire_presence",
            "current_openapi_definition",
            "raw_false_derivation_allowed",
            "synthetic_current_state_allowed",
        ),
        "current_state_disposition",
    )
    dispositions = (
        "current_openapi_definition" => "ABSENT",
        "captured_wire_presence" => "ABSENT",
        "authoritative_evidence_ever_official" => "NOT_ESTABLISHED",
    )
    for (key, expected) in dispositions
        _expect_string(disposition[key], "current_state_disposition.$key") ==
            expected ||
            fail("CURRENT_STATE_DISPOSITION_CHANGED", "current_state_disposition.$key", "must be $expected")
    end
    _expect_bool(
        disposition["raw_false_derivation_allowed"],
        false,
        "current_state_disposition.raw_false_derivation_allowed",
    )
    _expect_bool(
        disposition["synthetic_current_state_allowed"],
        false,
        "current_state_disposition.synthetic_current_state_allowed",
    )

    observations = _closed_keys(
        protocol["observations"],
        (
            "morning_class",
            "morning_window_end_utc",
            "morning_window_start_utc",
            "pair_atomic",
            "post_revision_class",
            "post_revision_window_end_utc",
            "post_revision_window_start_utc",
            "transition_class",
        ),
        "observations",
    )
    expected_observation_strings = (
        "morning_class" => MORNING_WINDOW_ENDPOINT_OBSERVATION,
        "post_revision_class" => POST_REVISION_WINDOW_ENDPOINT_OBSERVATION,
        "transition_class" => OBSERVED_EFFR_TRANSITION,
        "morning_window_start_utc" => "13:00:00Z",
        "morning_window_end_utc" => "13:15:00Z",
        "post_revision_window_start_utc" => "18:30:00Z",
        "post_revision_window_end_utc" => "18:45:00Z",
    )
    for (key, expected) in expected_observation_strings
        _expect_string(observations[key], "observations.$key") == expected ||
            fail("OBSERVATION_PROFILE_CHANGED", "observations.$key", "must be $expected")
    end
    _expect_bool(observations["pair_atomic"], false, "observations.pair_atomic")

    parser = _closed_keys(
        protocol["parser"],
        (
            "allowed_revision_tokens",
            "duplicate_members_rejected_before_materialization",
            "effr_type_literal",
            "envelope_keys",
            "exact_numeric_lexemes_preserved",
            "footnote_alias_allowed",
            "footnote_field",
            "footnote_ids",
            "max_json_abs_exponent",
            "max_json_body_bytes",
            "max_json_mantissa_digits",
            "max_json_nesting_depth",
            "max_json_number_bytes",
            "percent_alias_allowed",
            "rate_required_fields",
            "unknown_fields_allowed",
            "volume_required_fields",
        ),
        "parser",
    )
    _validate_exact_array(
        parser["allowed_revision_tokens"],
        collect(ALLOWED_REVISION_TOKENS),
        "parser.allowed_revision_tokens",
    )
    _validate_exact_array(parser["envelope_keys"], ["refRates"], "parser.envelope_keys")
    _validate_exact_array(parser["footnote_ids"], [1, 2, 3], "parser.footnote_ids")
    _expect_string(parser["footnote_field"], "parser.footnote_field") ==
        "footnoteId" ||
        fail("PARSER_PROFILE_CHANGED", "parser.footnote_field", "must be footnoteId")
    _expect_bool(
        parser["footnote_alias_allowed"],
        false,
        "parser.footnote_alias_allowed",
    )
    _expect_bool(
        parser["exact_numeric_lexemes_preserved"],
        true,
        "parser.exact_numeric_lexemes_preserved",
    )
    _expect_int(
        parser["max_json_body_bytes"],
        "parser.max_json_body_bytes";
        minimum = 1,
    ) == MAX_JSON_BODY_BYTES ||
        fail("PARSER_PROFILE_CHANGED", "parser.max_json_body_bytes", "unsupported")
    _expect_int(
        parser["max_json_nesting_depth"],
        "parser.max_json_nesting_depth";
        minimum = 1,
    ) == MAX_JSON_NESTING_DEPTH ||
        fail("PARSER_PROFILE_CHANGED", "parser.max_json_nesting_depth", "unsupported")
    _expect_int(
        parser["max_json_number_bytes"],
        "parser.max_json_number_bytes";
        minimum = 1,
    ) == MAX_JSON_NUMBER_BYTES ||
        fail("PARSER_PROFILE_CHANGED", "parser.max_json_number_bytes", "unsupported")
    _expect_int(
        parser["max_json_mantissa_digits"],
        "parser.max_json_mantissa_digits";
        minimum = 1,
    ) == MAX_JSON_MANTISSA_DIGITS ||
        fail("PARSER_PROFILE_CHANGED", "parser.max_json_mantissa_digits", "unsupported")
    _expect_int(
        parser["max_json_abs_exponent"],
        "parser.max_json_abs_exponent";
        minimum = 0,
    ) == MAX_JSON_ABS_EXPONENT ||
        fail("PARSER_PROFILE_CHANGED", "parser.max_json_abs_exponent", "unsupported")
    _validate_exact_array(
        parser["rate_required_fields"],
        [
            "effectiveDate",
            "type",
            RATE_FIELDS...,
            "revisionIndicator",
        ],
        "parser.rate_required_fields",
    )
    _validate_exact_array(
        parser["volume_required_fields"],
        [
            "effectiveDate",
            "type",
            "volumeInBillions",
            "revisionIndicator",
        ],
        "parser.volume_required_fields",
    )
    _expect_string(parser["effr_type_literal"], "parser.effr_type_literal") ==
        "EFFR" ||
        fail("PARSER_PROFILE_CHANGED", "parser.effr_type_literal", "must be EFFR")
    _expect_bool(
        parser["duplicate_members_rejected_before_materialization"],
        true,
        "parser.duplicate_members_rejected_before_materialization",
    )
    _expect_bool(parser["percent_alias_allowed"], false, "parser.percent_alias_allowed")
    _expect_bool(parser["unknown_fields_allowed"], false, "parser.unknown_fields_allowed")

    policy = _closed_keys(
        protocol["policy"],
        (
            "footnote_required_for_marked_revision",
            "footnote_pair_rule",
            "marked_revision_token",
            "rate_change_threshold_basis_points",
            "strictly_greater_than_threshold",
            "unchanged_claim",
        ),
        "policy",
    )
    _expect_string(policy["marked_revision_token"], "policy.marked_revision_token") ==
        "r" ||
        fail("POLICY_CHANGED", "policy.marked_revision_token", "must be r")
    _expect_int(
        policy["rate_change_threshold_basis_points"],
        "policy.rate_change_threshold_basis_points";
        minimum = 1,
    ) == 1 ||
        fail("POLICY_CHANGED", "policy.rate_change_threshold_basis_points", "must be 1")
    _expect_bool(
        policy["strictly_greater_than_threshold"],
        true,
        "policy.strictly_greater_than_threshold",
    )
    _expect_bool(
        policy["footnote_required_for_marked_revision"],
        false,
        "policy.footnote_required_for_marked_revision",
    )
    _expect_string(policy["footnote_pair_rule"], "policy.footnote_pair_rule") ==
        "EXACT_FOOTNOTE_ID_INTEGER_OR_ABSENCE_MATCH_OR_QUARANTINE" ||
        fail("POLICY_CHANGED", "policy.footnote_pair_rule", "unsupported")
    _expect_string(policy["unchanged_claim"], "policy.unchanged_claim") ==
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE" ||
        fail("CLAIM_CEILING_CHANGED", "policy.unchanged_claim", "unsupported")

    estimand = _closed_keys(
        protocol["estimand"],
        ("candidate_estimands", "owner_validator_decision", "status"),
        "estimand",
    )
    _expect_string(estimand["status"], "estimand.status") == ESTIMAND_STATUS ||
        fail("ESTIMAND_PRESELECTION_FORBIDDEN", "estimand.status", "must be PENDING")
    _expect_string(
        estimand["owner_validator_decision"],
        "estimand.owner_validator_decision",
    ) == "REQUIRED_BEFORE_ORIGIN_ADMISSION" ||
        fail("ESTIMAND_PRESELECTION_FORBIDDEN", "estimand.owner_validator_decision", "must remain required")
    _validate_exact_array(
        estimand["candidate_estimands"],
        collect(ESTIMAND_CANDIDATES),
        "estimand.candidate_estimands",
    )

    gates = _closed_keys(protocol["gates"], ALWAYS_FALSE_GATES, "gates")
    for gate in ALWAYS_FALSE_GATES
        _expect_bool(gates[gate], false, "gates.$gate")
    end

    sources = _closed_keys(
        protocol["source_bindings"],
        (
            "api_documentation_current_state_occurrences",
            "api_documentation_sha256",
            "api_documentation_url",
            "august7_manifest_file_sha256",
            "august7_manifest_semantic_sha256",
            "august7_rate_raw_sha256",
            "august7_volume_raw_sha256",
            "campaign_control_file_sha256",
            "campaign_schedule_content_sha256",
            "campaign_schedule_file_sha256",
            "effr_page_url",
            "holiday_sha256",
            "holiday_url",
            "openapi_current_state_occurrences",
            "openapi_effr_record_schema_path",
            "openapi_footnote_id_schema_members",
            "openapi_revision_indicator_occurrences",
            "openapi_sha256",
            "openapi_standalone_footnote_schema_members",
            "openapi_url",
            "prospective_contract_content_sha256",
            "prospective_contract_file_sha256",
            "revision_policy_url",
            "terms_sha256",
            "terms_url",
            "v2_contract_source_sha256",
        ),
        "source_bindings",
    )
    expected_hashes = (
        "api_documentation_sha256" => API_DOCUMENTATION_SHA256,
        "august7_manifest_file_sha256" => AUGUST7_MANIFEST_FILE_SHA256,
        "august7_manifest_semantic_sha256" => AUGUST7_MANIFEST_SEMANTIC_SHA256,
        "august7_rate_raw_sha256" => AUGUST7_RATE_RAW_SHA256,
        "august7_volume_raw_sha256" => AUGUST7_VOLUME_RAW_SHA256,
        "campaign_control_file_sha256" => CAMPAIGN_CONTROL_FILE_SHA256,
        "campaign_schedule_content_sha256" => CAMPAIGN_SCHEDULE_CONTENT_SHA256,
        "campaign_schedule_file_sha256" => CAMPAIGN_SCHEDULE_FILE_SHA256,
        "holiday_sha256" => HOLIDAY_SHA256,
        "openapi_sha256" => OPENAPI_SHA256,
        "prospective_contract_content_sha256" => PROSPECTIVE_CONTRACT_CONTENT_SHA256,
        "prospective_contract_file_sha256" => PROSPECTIVE_CONTRACT_FILE_SHA256,
        "terms_sha256" => TERMS_SHA256,
        "v2_contract_source_sha256" => V2_CONTRACT_SOURCE_SHA256,
    )
    for (key, expected) in expected_hashes
        _expect_hash(sources[key], "source_bindings.$key") == expected ||
            fail("SOURCE_PIN_CHANGED", "source_bindings.$key", "must match reviewed bytes")
    end
    expected_urls = (
        "api_documentation_url" =>
            "https://markets.newyorkfed.org/static/docs/markets-api.html",
        "effr_page_url" =>
            "https://www.newyorkfed.org/markets/reference-rates/effr",
        "holiday_url" =>
            "https://www.newyorkfed.org/aboutthefed/holiday_schedule",
        "openapi_url" =>
            "https://markets.newyorkfed.org/static/docs/markets-api.yml",
        "revision_policy_url" =>
            "https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates",
        "terms_url" => "https://www.newyorkfed.org/privacy/termsofuse",
    )
    for (key, expected) in expected_urls
        _expect_string(sources[key], "source_bindings.$key") == expected ||
            fail("SOURCE_URL_CHANGED", "source_bindings.$key", "must remain exact")
    end
    _expect_int(
        sources["api_documentation_current_state_occurrences"],
        "source_bindings.api_documentation_current_state_occurrences";
        minimum = 0,
    ) == 0 ||
        fail("SOURCE_ASSERTION_CHANGED", "source_bindings.api_documentation_current_state_occurrences", "must be zero")
    _expect_int(
        sources["openapi_current_state_occurrences"],
        "source_bindings.openapi_current_state_occurrences";
        minimum = 0,
    ) == 0 ||
        fail("SOURCE_ASSERTION_CHANGED", "source_bindings.openapi_current_state_occurrences", "must be zero")
    _expect_int(
        sources["openapi_revision_indicator_occurrences"],
        "source_bindings.openapi_revision_indicator_occurrences";
        minimum = 0,
    ) == 6 ||
        fail("SOURCE_ASSERTION_CHANGED", "source_bindings.openapi_revision_indicator_occurrences", "must be six")
    _expect_int(
        sources["openapi_footnote_id_schema_members"],
        "source_bindings.openapi_footnote_id_schema_members";
        minimum = 0,
    ) == 5 ||
        fail("SOURCE_ASSERTION_CHANGED", "source_bindings.openapi_footnote_id_schema_members", "must be five")
    _expect_int(
        sources["openapi_standalone_footnote_schema_members"],
        "source_bindings.openapi_standalone_footnote_schema_members";
        minimum = 0,
    ) == 0 ||
        fail("SOURCE_ASSERTION_CHANGED", "source_bindings.openapi_standalone_footnote_schema_members", "must be zero")
    _expect_string(
        sources["openapi_effr_record_schema_path"],
        "source_bindings.openapi_effr_record_schema_path",
    ) == "#/components/schemas/effr-record" ||
        fail("SOURCE_ASSERTION_CHANGED", "source_bindings.openapi_effr_record_schema_path", "must remain exact")

    matrix = protocol["transition_matrix"]
    matrix isa AbstractVector ||
        fail("TYPE_MISMATCH", "transition_matrix", "must be an array of tables")
    expected_decisions = (
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE",
        "MARKED_SAME_DAY_REVISION_OBSERVED",
        "QUARANTINED_MORNING_ALREADY_MARKED_REVISED",
        "QUARANTINED_UNMARKED_EFFR_TRANSITION",
        "QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT",
        "QUARANTINED_RATE_VOLUME_PAIR_MISMATCH",
        "QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION",
        "QUARANTINED_SUCCESSOR_PROFILE_REQUIRED",
    )
    expected_evidence = (
        "both empty tokens; selected EFFR semantics and full bodies identical",
        "morning empty; later coherent r pair; exact published decimal-lexeme rate change strictly greater than one basis point; optional contingency footnoteId absent or the same exact JSON integer",
        "morning endpoint already carries r",
        "later empty token but selected EFFR semantics change",
        "later r without a published rate change strictly greater than one basis point",
        "rate and volume tokens, exact footnoteId integers or absence, dates, types, or capture roles differ",
        "selected EFFR semantics identical but full response bytes differ",
        "missing or unknown token, alias, new field, duplicate member, currentState, or unknown category",
    )
    length(matrix) == length(expected_decisions) ||
        fail("TRANSITION_MATRIX_CHANGED", "transition_matrix", "must contain eight rows")
    for (index, expected) in enumerate(expected_decisions)
        row = _closed_keys(
            matrix[index],
            ("decision", "evidence", "sequence"),
            "transition_matrix[$index]",
        )
        _expect_int(row["sequence"], "transition_matrix[$index].sequence") ==
            index ||
            fail("TRANSITION_MATRIX_CHANGED", "transition_matrix[$index].sequence", "must be $index")
        _expect_string(row["decision"], "transition_matrix[$index].decision") ==
            expected ||
            fail("TRANSITION_MATRIX_CHANGED", "transition_matrix[$index].decision", "must be $expected")
        _expect_string(row["evidence"], "transition_matrix[$index].evidence") ==
            expected_evidence[index] ||
            fail("TRANSITION_MATRIX_CHANGED", "transition_matrix[$index].evidence", "must remain exact")
    end

    citations = protocol["citations"]
    citations isa AbstractVector ||
        fail("TYPE_MISMATCH", "citations", "must be an array of tables")
    length(citations) == 10 ||
        fail("CITATION_SET_CHANGED", "citations", "must contain ten entries")
    expected_citations = (
        (
            id = "NYFED_EFFR",
            url = "https://www.newyorkfed.org/markets/reference-rates/effr",
            scope = "remote assertion for EFFR meaning and raw r revision marker; footnoteId is a separate contingency annotation; not local publisher authentication",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "NYFED_REVISION_POLICY",
            url = "https://www.newyorkfed.org/markets/reference-rates/additional-information-about-reference-rates",
            scope = "remote assertion for approximately 09:00 and 14:30 ET publication policy and greater-than-one-basis-point revision threshold",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "NYFED_MARKETS_API",
            url = "https://markets.newyorkfed.org/static/docs/markets-api.html",
            scope = "pinned local documentation snapshot plus direct authoritative URL",
            status = "PINNED_LOCAL_SNAPSHOT",
        ),
        (
            id = "OPENAPI_3_0_SCHEMA",
            url = "https://spec.openapis.org/oas/v3.0.0.html#schema",
            scope = "absence of required does not create a mandatory closed response member",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "JSON_SCHEMA_2020_12_REQUIRED",
            url = "https://json-schema.org/draft/2020-12/json-schema-validation#name-required",
            scope = "required-member semantics",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "RFC_8259_JSON",
            url = "https://www.rfc-editor.org/rfc/rfc8259.html",
            scope = "interoperability hazard of non-unique JSON object names",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "RFC_9110_DATE",
            url = "https://www.rfc-editor.org/rfc/rfc9110.html#name-date",
            scope = "HTTP Date is message metadata and not a trusted publication timestamp",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "RFC_3161_TIMESTAMP",
            url = "https://www.rfc-editor.org/rfc/rfc3161.html",
            scope = "a trusted timestamp can bind digest existence but cannot alone authenticate publisher provenance",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "SEMVER_2_0_0",
            url = "https://semver.org/spec/v2.0.0.html",
            scope = "major version marks the deliberately incompatible v2-to-v3 semantics",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
        (
            id = "REAL_TIME_DATA_CROUSHORE_STARK",
            url = "https://doi.org/10.1016/S0304-4076(01)00072-0",
            scope = "dated information-set motivation; does not authenticate local EFFR captures",
            status = "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED",
        ),
    )
    for (index, expected) in enumerate(expected_citations)
        citation = _closed_keys(
            citations[index],
            ("id", "local_authentication_status", "scope", "url"),
            "citations[$index]",
        )
        _expect_string(citation["id"], "citations[$index].id") == expected.id ||
            fail("CITATION_SET_CHANGED", "citations[$index].id", "must be $(expected.id)")
        _expect_string(citation["url"], "citations[$index].url") == expected.url ||
            fail("CITATION_SET_CHANGED", "citations[$index].url", "must remain exact")
        _expect_string(
            citation["local_authentication_status"],
            "citations[$index].local_authentication_status",
        ) == expected.status ||
            fail("CITATION_SET_CHANGED", "citations[$index].local_authentication_status", "must remain exact")
        _expect_string(citation["scope"], "citations[$index].scope") == expected.scope ||
            fail("CITATION_SET_CHANGED", "citations[$index].scope", "must remain exact")
    end

    verify_sources && _validate_local_source_bindings()
    return deepcopy(protocol)
end

validate_protocol() = load_protocol(PROTOCOL_PATH)

_json_whitespace(byte) =
    byte in (UInt8(' '), UInt8('\t'), UInt8('\n'), UInt8('\r'))

function _skip_json_whitespace(bytes, index)
    cursor = index
    while cursor <= length(bytes) && _json_whitespace(bytes[cursor])
        cursor += 1
    end
    return cursor
end

function _scan_json_string(bytes, index, location)
    index <= length(bytes) && bytes[index] == UInt8('"') ||
        fail("INVALID_JSON", location, "expected a JSON string")
    cursor = index + 1
    while cursor <= length(bytes)
        byte = bytes[cursor]
        if byte == UInt8('"')
            return cursor + 1
        elseif byte == UInt8('\\')
            cursor += 1
            cursor <= length(bytes) ||
                fail("INVALID_JSON", location, "unterminated JSON escape")
            escape = bytes[cursor]
            if escape == UInt8('u')
                cursor + 4 <= length(bytes) ||
                    fail("INVALID_JSON", location, "truncated JSON unicode escape")
                for offset in 1:4
                    isxdigit(Char(bytes[cursor + offset])) ||
                        fail("INVALID_JSON", location, "invalid JSON unicode escape")
                end
                cursor += 5
                continue
            end
            escape in UInt8.(['"', '\\', '/', 'b', 'f', 'n', 'r', 't']) ||
                fail("INVALID_JSON", location, "invalid JSON escape")
        elseif byte < 0x20
            fail("INVALID_JSON", location, "unescaped JSON control character")
        end
        cursor += 1
    end
    return fail("INVALID_JSON", location, "unterminated JSON string")
end

function _decoded_json_string(bytes, first_index, next_index, location)
    token = String(copy(bytes[first_index:(next_index - 1)]))
    isvalid(token) ||
        fail("INVALID_JSON_UTF8", location, "string token is not valid UTF-8")
    decoded = try
        JSON.parse(token)
    catch
        fail("INVALID_JSON", location, "invalid JSON member-name string")
    end
    decoded isa AbstractString ||
        fail("INVALID_JSON", location, "member name did not decode to a string")
    isvalid(decoded) ||
        fail("INVALID_JSON_UNICODE", location, "string contains an unpaired surrogate")
    return String(decoded)
end

function _bounded_json_exponent(exponent_text, location)
    exponent_text === nothing && return 0
    negative = startswith(exponent_text, "-")
    has_sign = negative || startswith(exponent_text, "+")
    unsigned = has_sign ?
        String(SubString(exponent_text, 2)) : exponent_text
    first_nonzero = findfirst(character -> character != '0', unsigned)
    significant = first_nonzero === nothing ?
        "0" : String(SubString(unsigned, first_nonzero))
    limit_text = string(MAX_JSON_ABS_EXPONENT)
    if ncodeunits(significant) > ncodeunits(limit_text) ||
            (
            ncodeunits(significant) == ncodeunits(limit_text) &&
                significant > limit_text
        )
        fail(
            "NUMBER_EXPONENT_LIMIT_EXCEEDED",
            location,
            "absolute exponent exceeds $MAX_JSON_ABS_EXPONENT",
        )
    end
    magnitude = parse(Int, significant)
    return negative ? -magnitude : magnitude
end

function _exact_json_number(lexeme, location)
    ncodeunits(lexeme) <= MAX_JSON_NUMBER_BYTES ||
        fail(
        "NUMBER_TOKEN_LIMIT_EXCEEDED",
        location,
        "numeric token exceeds $MAX_JSON_NUMBER_BYTES bytes",
    )
    matched = match(JSON_NUMBER_PATTERN, lexeme)
    matched === nothing &&
        fail("INVALID_JSON_NUMBER", location, "outside the RFC 8259 grammar")
    integer_text, fraction_text, exponent_text = matched.captures
    fraction = something(fraction_text, "")
    mantissa_digits = ncodeunits(integer_text) + ncodeunits(fraction)
    mantissa_digits <= MAX_JSON_MANTISSA_DIGITS ||
        fail(
        "NUMBER_PRECISION_LIMIT_EXCEEDED",
        location,
        "mantissa exceeds $MAX_JSON_MANTISSA_DIGITS digits",
    )
    exponent = _bounded_json_exponent(exponent_text, location)
    numerator_value = parse(BigInt, integer_text * fraction)
    startswith(lexeme, "-") && (numerator_value = -numerator_value)
    scale = ncodeunits(fraction) - exponent
    value = scale >= 0 ?
        numerator_value // big(10)^scale :
        (numerator_value * big(10)^(-scale)) // big(1)
    return ExactJSONNumber(lexeme, value)
end

function _primitive_token(bytes, index, location)
    cursor = index
    while cursor <= length(bytes) &&
            !(bytes[cursor] in UInt8.([',', '}', ']'])) &&
            !_json_whitespace(bytes[cursor])
        cursor += 1
    end
    cursor > index ||
        fail("INVALID_JSON", location, "missing JSON primitive")
    token = String(copy(bytes[index:(cursor - 1)]))
    if token == "true"
        return (true, cursor)
    elseif token == "false"
        return (false, cursor)
    elseif token == "null"
        return (nothing, cursor)
    end
    return (_exact_json_number(token, location), cursor)
end

function _parse_json_value(bytes, index, location, depth)
    depth <= MAX_JSON_NESTING_DEPTH ||
        fail(
        "JSON_NESTING_LIMIT_EXCEEDED",
        location,
        "nesting exceeds $MAX_JSON_NESTING_DEPTH",
    )
    cursor = _skip_json_whitespace(bytes, index)
    cursor <= length(bytes) ||
        fail("INVALID_JSON", location, "missing JSON value")
    byte = bytes[cursor]
    if byte == UInt8('{')
        cursor = _skip_json_whitespace(bytes, cursor + 1)
        values = Dict{String, Any}()
        if cursor <= length(bytes) && bytes[cursor] == UInt8('}')
            return (values, cursor + 1)
        end
        while true
            member_start = cursor
            member_next = _scan_json_string(bytes, member_start, location)
            member = _decoded_json_string(
                bytes,
                member_start,
                member_next,
                location,
            )
            haskey(values, member) && fail(
                "DUPLICATE_JSON_MEMBER",
                location,
                "duplicate member after escape decoding: $member",
            )
            cursor = _skip_json_whitespace(bytes, member_next)
            cursor <= length(bytes) && bytes[cursor] == UInt8(':') ||
                fail("INVALID_JSON", location, "missing member separator")
            value, cursor = _parse_json_value(
                bytes,
                cursor + 1,
                "$location.$member",
                depth + 1,
            )
            values[member] = value
            cursor = _skip_json_whitespace(bytes, cursor)
            cursor <= length(bytes) ||
                fail("INVALID_JSON", location, "unterminated object")
            if bytes[cursor] == UInt8('}')
                return (values, cursor + 1)
            end
            bytes[cursor] == UInt8(',') ||
                fail("INVALID_JSON", location, "invalid object separator")
            cursor = _skip_json_whitespace(bytes, cursor + 1)
        end
    elseif byte == UInt8('[')
        cursor = _skip_json_whitespace(bytes, cursor + 1)
        values = Any[]
        if cursor <= length(bytes) && bytes[cursor] == UInt8(']')
            return (values, cursor + 1)
        end
        index_in_array = 1
        while true
            value, cursor = _parse_json_value(
                bytes,
                cursor,
                "$location[$index_in_array]",
                depth + 1,
            )
            push!(values, value)
            cursor = _skip_json_whitespace(bytes, cursor)
            cursor <= length(bytes) ||
                fail("INVALID_JSON", location, "unterminated array")
            if bytes[cursor] == UInt8(']')
                return (values, cursor + 1)
            end
            bytes[cursor] == UInt8(',') ||
                fail("INVALID_JSON", location, "invalid array separator")
            cursor = _skip_json_whitespace(bytes, cursor + 1)
            index_in_array += 1
        end
    elseif byte == UInt8('"')
        next_cursor = _scan_json_string(bytes, cursor, location)
        return (
            _decoded_json_string(bytes, cursor, next_cursor, location),
            next_cursor,
        )
    end
    return _primitive_token(bytes, cursor, location)
end

function _parse_exact_json(body, location)
    length(body) <= MAX_JSON_BODY_BYTES ||
        fail(
        "JSON_BODY_LIMIT_EXCEEDED",
        location,
        "body exceeds $MAX_JSON_BODY_BYTES bytes",
    )
    isvalid(String(copy(body))) ||
        fail("INVALID_JSON_UTF8", location, "body is not valid UTF-8")
    bytes = Vector{UInt8}(body)
    value, cursor = _parse_json_value(bytes, 1, location, 0)
    _skip_json_whitespace(bytes, cursor) == length(bytes) + 1 ||
        fail("INVALID_JSON", location, "trailing bytes after JSON value")
    return value
end

function _footnote(row, location)
    if !haskey(row, "footnoteId")
        return ("NONE", "NONE")
    end
    value = row["footnoteId"]
    value isa ExactJSONNumber ||
        fail(
        "FOOTNOTE_ID_TYPE_MISMATCH",
        "$location.footnoteId",
        "must be an exact JSON integer",
    )
    occursin(JSON_INTEGER_PATTERN, value.lexeme) ||
        fail(
        "FOOTNOTE_ID_TYPE_MISMATCH",
        "$location.footnoteId",
        "decimal and exponent forms are not integers in this profile",
    )
    identifier_big = numerator(value.value)
    denominator(value.value) == 1 ||
        fail("FOOTNOTE_ID_TYPE_MISMATCH", "$location.footnoteId", "must be integral")
    identifier_big in BigInt.(SUPPORTED_FOOTNOTE_IDS) ||
        fail("UNKNOWN_FOOTNOTE_TOKEN", "$location.footnoteId", "unsupported identifier")
    identifier = Int(identifier_big)
    return (string(identifier), FOOTNOTE_CLASS[identifier])
end

function _required_row_fields(report_type, row_type)
    common = ("effectiveDate", "type")
    suffix = ("revisionIndicator",)
    if report_type == "rate"
        fields = if row_type == "EFFR"
            RATE_FIELDS
        elseif row_type == "SOFRAI"
            AVERAGE_RATE_FIELDS
        else
            ORDINARY_RATE_FIELDS
        end
        return (common..., fields..., suffix...)
    end
    fields = row_type == "SOFRAI" ? () : ("volumeInBillions",)
    return (common..., fields..., suffix...)
end

function _validate_row(row_value, report_type, effective_date, location)
    row = _expect_dict(row_value, location)
    haskey(row, "currentState") && fail(
        "SCHEMA_DRIFT_CURRENT_STATE_PRESENT",
        "$location.currentState",
        "v3 forbids deriving or accepting currentState",
    )
    haskey(row, "type") ||
        fail("MISSING_FIELD", location, "missing type")
    row_type = _expect_string(row["type"], "$location.type")
    row_type in SUPPORTED_TYPES ||
        fail("UNKNOWN_ROW_TYPE", "$location.type", "unsupported raw type")
    required = _required_row_fields(report_type, row_type)
    optional = ("footnoteId",)
    actual = Set(String.(keys(row)))
    required_set = Set(required)
    optional_set = Set(optional)
    missing = sort!(collect(setdiff(required_set, actual)))
    unknown = sort!(collect(setdiff(actual, union(required_set, optional_set))))
    isempty(missing) ||
        fail("MISSING_FIELD", location, "missing fields: $(join(missing, ", "))")
    isempty(unknown) ||
        fail("SCHEMA_DRIFT_UNKNOWN_FIELD", location, "unknown fields: $(join(unknown, ", "))")
    effective = _expect_string(row["effectiveDate"], "$location.effectiveDate")
    effective == string(effective_date) ||
        fail("EFFECTIVE_DATE_MISMATCH", "$location.effectiveDate", "must match authorized date")
    revision = _expect_string(
        row["revisionIndicator"],
        "$location.revisionIndicator";
        allow_empty = true,
    )
    revision in ALLOWED_REVISION_TOKENS ||
        fail("UNKNOWN_REVISION_TOKEN", "$location.revisionIndicator", "only empty and r are supported")
    footnote_token, footnote_class = _footnote(row, location)
    for field in setdiff(required, ("effectiveDate", "type", "revisionIndicator"))
        _expect_exact_json_number(
            row[field],
            "$location.$field";
            nonnegative = field == "volumeInBillions",
        )
    end
    if report_type == "rate" && row_type == "EFFR"
        p1 = row["percentPercentile1"].value
        p25 = row["percentPercentile25"].value
        rate = row["percentRate"].value
        p75 = row["percentPercentile75"].value
        p99 = row["percentPercentile99"].value
        p1 <= p25 <= rate <= p75 <= p99 ||
            fail("RATE_ORDERING_VIOLATION", location, "percentiles and EFFR are incoherent")
        row["targetRateFrom"].value <= row["targetRateTo"].value ||
            fail("TARGET_RANGE_VIOLATION", location, "target bounds are reversed")
    end
    return (;
        row,
        row_type,
        revision,
        footnote_token,
        footnote_class,
        required,
    )
end

function _typed_selected_field(field, value, location)
    name = String(field)
    if value isa ExactJSONNumber
        kind = name == "footnoteId" ? "JSON_INTEGER" : "JSON_NUMBER"
        return (name, kind, value.lexeme)
    elseif value isa String
        return (name, "JSON_STRING", value)
    end
    return fail(
        "INTERNAL_SELECTED_FIELD_TYPE",
        "$location.$name",
        "unsupported selected value type $(typeof(value))",
    )
end

function _semantic_selected_field(field, value, location)
    name = String(field)
    if value isa ExactJSONNumber
        kind = name == "footnoteId" ? "JSON_INTEGER" : "JSON_NUMBER"
        return (
            name,
            kind,
            string(numerator(value.value)),
            string(denominator(value.value)),
        )
    elseif value isa String
        return (name, "JSON_STRING", value)
    end
    return fail(
        "INTERNAL_SELECTED_FIELD_TYPE",
        "$location.$name",
        "unsupported selected value type $(typeof(value))",
    )
end

function _parse_body(body, report_type, effective_date)
    length(body) <= MAX_JSON_BODY_BYTES ||
        fail(
        "JSON_BODY_LIMIT_EXCEEDED",
        "$report_type response",
        "body exceeds $MAX_JSON_BODY_BYTES bytes",
    )
    before = copy(body)
    parsed = _parse_exact_json(before, "$report_type response")
    envelope = _closed_keys(parsed, ("refRates",), "$report_type response")
    rows = envelope["refRates"]
    rows isa AbstractVector ||
        fail("TYPE_MISMATCH", "$report_type response.refRates", "must be an array")
    !isempty(rows) ||
        fail("MISSING_EFFR_ROW", "$report_type response.refRates", "must not be empty")
    selected = nothing
    for (index, raw_row) in enumerate(rows)
        validated = _validate_row(
            raw_row,
            report_type,
            effective_date,
            "$report_type response.refRates[$index]",
        )
        if validated.row_type == "EFFR"
            selected === nothing ||
                fail("DUPLICATE_EFFR_ROW", "$report_type response.refRates", "must contain exactly one EFFR row")
            selected = (index, validated)
        end
    end
    selected === nothing &&
        fail("MISSING_EFFR_ROW", "$report_type response.refRates", "must contain exactly one EFFR row")
    body == before ||
        fail("RAW_BODY_MUTATED", "$report_type response", "parser changed caller bytes")
    index, validated = selected
    row = validated.row
    field_names = sort!(collect(keys(row)))
    selected_fields = Tuple(
        _typed_selected_field(
                field,
                row[field],
                "$report_type response.refRates[$index]",
            ) for field in field_names
    )
    semantic_fields = Tuple(
        _semantic_selected_field(
                field,
                row[field],
                "$report_type response.refRates[$index]",
            ) for field in field_names
    )
    value_fields = Tuple(
        item for item in semantic_fields if
            first(item) ∉ ("revisionIndicator", "footnoteId")
    )
    return (
        raw_sha256 = sha256_hex(before),
        raw_byte_count = length(before),
        selected_json_pointer = "/refRates/$(index - 1)",
        selected_row_sha256 = semantic_sha256(semantic_fields),
        selected_value_sha256 = semantic_sha256(value_fields),
        selected_fields,
        revision_token = validated.revision,
        footnote_token = validated.footnote_token,
        footnote_class = validated.footnote_class,
    )
end

function _validate_headers(headers, report_type)
    isempty(headers) &&
        fail("MISSING_RESPONSE_HEADERS", "$report_type headers", "must not be empty")
    seen = Set{String}()
    canonical_headers = Pair{String, String}[]
    values = Dict{String, String}()
    for (index, pair) in enumerate(headers)
        name = first(pair)
        value = last(pair)
        name == strip(name) && occursin(HEADER_NAME_PATTERN, name) ||
            fail("INVALID_HEADER_NAME", "$report_type headers[$index]", "invalid raw field name")
        any(character -> Int(character) < 0x20 || Int(character) == 0x7f, name) &&
            fail("INVALID_HEADER_NAME", "$report_type headers[$index]", "contains control character")
        value == strip(value) ||
            fail("INVALID_HEADER_VALUE", "$report_type headers[$index]", "surrounding whitespace")
        any(character -> Int(character) < 0x20 || Int(character) == 0x7f, value) &&
            fail("INVALID_HEADER_VALUE", "$report_type headers[$index]", "contains control character")
        normalized = lowercase(name)
        normalized in seen &&
            fail("DUPLICATE_RESPONSE_HEADER", "$report_type headers", "duplicate $normalized")
        push!(seen, normalized)
        values[normalized] = value
        push!(canonical_headers, name => value)
    end
    haskey(values, "content-type") ||
        fail("MISSING_CONTENT_TYPE", "$report_type headers", "content-type is required")
    values["content-type"] in ("application/json", "application/json;charset=utf-8") ||
        fail("MEDIA_TYPE_MISMATCH", "$report_type headers.content-type", "unsupported exact media type")
    get(values, "content-encoding", "identity") == "identity" ||
        fail("CONTENT_ENCODING_MISMATCH", "$report_type headers.content-encoding", "must be identity")
    return semantic_sha256(Tuple(canonical_headers))
end

function _campaign_day(publication_date)
    schedule = try
        TOML.parsefile(CAMPAIGN_SCHEDULE_PATH)
    catch error
        fail("SCHEDULE_PARSE_FAILED", "campaign schedule", sprint(showerror, error))
    end
    schedule["artifact"]["content_sha256"] ==
        CAMPAIGN_SCHEDULE_CONTENT_SHA256 ||
        fail("SCHEDULE_BINDING_CHANGED", "campaign schedule", "semantic pin differs")
    matches = [
        day for day in schedule["days"] if
            get(day, "publication_date", nothing) == string(publication_date)
    ]
    length(matches) == 1 ||
        fail("UNAUTHORIZED_PUBLICATION_DATE", "publication_date", "not in pinned schedule")
    return only(matches)
end

function _window(publication_date, observation_class)
    day = _campaign_day(publication_date)
    midnight = DateTime(publication_date)
    if observation_class == MORNING_WINDOW_ENDPOINT_OBSERVATION
        return (midnight + Hour(13), midnight + Hour(13) + Minute(15), day)
    elseif observation_class == POST_REVISION_WINDOW_ENDPOINT_OBSERVATION
        get(day, "revision_check_required", false) === true ||
            fail("UNAUTHORIZED_REVISION_WINDOW", "publication_date", "schedule has no pre-origin revision slot")
        return (midnight + Hour(18) + Minute(30), midnight + Hour(18) + Minute(45), day)
    end
    return fail("UNKNOWN_OBSERVATION_CLASS", "observation_class", "unsupported class")
end

function validate_report(
        capture::CapturedReport,
        publication_date::Date,
        effective_date::Date,
        observation_class::String,
    )
    capture.report_type in ("rate", "volume") ||
        fail("UNKNOWN_REPORT_TYPE", "capture.report_type", "must be rate or volume")
    start_window, end_window, day = _window(publication_date, observation_class)
    get(day, "effective_date", nothing) == string(effective_date) ||
        fail("EFFECTIVE_DATE_MISMATCH", "effective_date", "does not match pinned schedule")
    query =
        "endDate=$(effective_date)&startDate=$(effective_date)&type=$(capture.report_type)"
    capture.canonical_query == query ||
        fail("QUERY_MISMATCH", "capture.canonical_query", "must be exact one-date query")
    expected_url = "$DATA_ENDPOINT?$query"
    capture.requested_url == expected_url ||
        fail("REQUEST_URL_MISMATCH", "capture.requested_url", "must be exact")
    capture.final_url == expected_url ||
        fail("FINAL_URL_OR_REDIRECT_MISMATCH", "capture.final_url", "must equal request")
    startswith(capture.final_url, "https://$FINAL_HOST/") ||
        fail("FINAL_HOST_MISMATCH", "capture.final_url", "must remain on pinned host")
    capture.http_status isa Int && !(capture.http_status isa Bool) ||
        fail("TYPE_MISMATCH", "capture.http_status", "must be Int")
    capture.http_status == 200 ||
        fail("HTTP_STATUS_MISMATCH", "capture.http_status", "must be 200")
    capture.redirect_count isa Int && !(capture.redirect_count isa Bool) ||
        fail("TYPE_MISMATCH", "capture.redirect_count", "must be Int")
    capture.redirect_count == 0 ||
        fail("REDIRECT_FORBIDDEN", "capture.redirect_count", "must be zero")
    start_window <= capture.request_started_at_utc <
        capture.response_body_completed_at_utc <=
        capture.response_metadata_observed_at_utc <= end_window ||
        fail("CAPTURE_WINDOW_VIOLATION", "capture timestamps", "must be ordered inside the exact window")
    header_sha256 = _validate_headers(capture.response_headers, capture.report_type)
    parsed = _parse_body(capture.body, capture.report_type, effective_date)
    return ParsedReport(
        capture.report_type,
        parsed.raw_sha256,
        parsed.raw_byte_count,
        capture.http_status,
        capture.redirect_count,
        Tuple(copy(capture.response_headers)),
        header_sha256,
        parsed.selected_json_pointer,
        parsed.selected_row_sha256,
        parsed.selected_value_sha256,
        parsed.selected_fields,
        parsed.revision_token,
        parsed.footnote_token,
        parsed.footnote_class,
        capture.request_started_at_utc,
        capture.response_body_completed_at_utc,
        capture.response_metadata_observed_at_utc,
        capture.canonical_query,
        capture.requested_url,
        capture.final_url,
    )
end

function _field_record(report::ParsedReport, name)
    matches = [item for item in report.selected_fields if first(item) == name]
    length(matches) == 1 ||
        fail("INTERNAL_FIELD_LOOKUP_FAILED", report.report_type, "missing $name")
    return only(matches)
end

_field(report::ParsedReport, name) = last(_field_record(report, name))

function _numeric_lexeme(report::ParsedReport, name)
    record = _field_record(report, name)
    record[2] == "JSON_NUMBER" ||
        fail("INTERNAL_FIELD_TYPE_MISMATCH", report.report_type, "$name is not JSON_NUMBER")
    return record[3]
end

function _numeric_rational(report::ParsedReport, name)
    lexeme = _numeric_lexeme(report, name)
    return _exact_json_number(
        lexeme,
        "$(report.report_type).selected_fields.$name",
    ).value
end

function _observation_payload(
        observation_class,
        publication_date,
        effective_date,
        rate,
        volume,
    )
    return Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "observation_class" => observation_class,
        "publication_date" => string(publication_date),
        "effective_date" => string(effective_date),
        "rate" => Dict{String, Any}(
            "raw_sha256" => rate.raw_sha256,
            "raw_byte_count" => rate.raw_byte_count,
            "http_status" => rate.http_status,
            "redirect_count" => rate.redirect_count,
            "response_headers" => collect(rate.response_headers),
            "response_headers_sha256" => rate.response_headers_sha256,
            "selected_json_pointer" => rate.selected_json_pointer,
            "selected_row_sha256" => rate.selected_row_sha256,
            "selected_value_sha256" => rate.selected_value_sha256,
            "selected_fields" => collect(rate.selected_fields),
            "revision_token" => rate.revision_token,
            "footnote_token" => rate.footnote_token,
            "footnote_class" => rate.footnote_class,
            "request_started_at_utc" => rate.request_started_at_utc,
            "response_body_completed_at_utc" =>
                rate.response_body_completed_at_utc,
            "response_metadata_observed_at_utc" =>
                rate.response_metadata_observed_at_utc,
            "canonical_query" => rate.canonical_query,
            "requested_url" => rate.requested_url,
            "final_url" => rate.final_url,
        ),
        "volume" => Dict{String, Any}(
            "raw_sha256" => volume.raw_sha256,
            "raw_byte_count" => volume.raw_byte_count,
            "http_status" => volume.http_status,
            "redirect_count" => volume.redirect_count,
            "response_headers" => collect(volume.response_headers),
            "response_headers_sha256" => volume.response_headers_sha256,
            "selected_json_pointer" => volume.selected_json_pointer,
            "selected_row_sha256" => volume.selected_row_sha256,
            "selected_value_sha256" => volume.selected_value_sha256,
            "selected_fields" => collect(volume.selected_fields),
            "revision_token" => volume.revision_token,
            "footnote_token" => volume.footnote_token,
            "footnote_class" => volume.footnote_class,
            "request_started_at_utc" => volume.request_started_at_utc,
            "response_body_completed_at_utc" =>
                volume.response_body_completed_at_utc,
            "response_metadata_observed_at_utc" =>
                volume.response_metadata_observed_at_utc,
            "canonical_query" => volume.canonical_query,
            "requested_url" => volume.requested_url,
            "final_url" => volume.final_url,
        ),
        "rate_completion_claim" =>
            "RATE_ENDPOINT_STATE_OBSERVED_BY_RECORDED_BODY_COMPLETION_TIME",
        "volume_completion_claim" =>
            "VOLUME_ENDPOINT_STATE_OBSERVED_BY_RECORDED_BODY_COMPLETION_TIME",
        "pair_as_of_utc" => volume.response_body_completed_at_utc,
        "requests_sequential_not_atomic" => true,
    )
end

function validate_endpoint_observation(
        rate_capture::CapturedReport,
        volume_capture::CapturedReport;
        observation_class::String,
        publication_date::Date,
        effective_date::Date,
    )
    validate_protocol()
    rate_capture.report_type == "rate" ||
        fail("RATE_VOLUME_PAIR_MISMATCH", "rate_capture.report_type", "must be rate")
    volume_capture.report_type == "volume" ||
        fail("RATE_VOLUME_PAIR_MISMATCH", "volume_capture.report_type", "must be volume")
    rate = validate_report(
        rate_capture,
        publication_date,
        effective_date,
        observation_class,
    )
    volume = validate_report(
        volume_capture,
        publication_date,
        effective_date,
        observation_class,
    )
    rate.response_metadata_observed_at_utc <
        volume.request_started_at_utc ||
        fail(
        "RATE_VOLUME_NOT_SEQUENTIAL",
        "capture timestamps",
        "volume must start strictly after rate metadata observation",
    )
    rate.request_started_at_utc != volume.request_started_at_utc &&
        rate.response_body_completed_at_utc !=
        volume.response_body_completed_at_utc ||
        fail("RATE_VOLUME_TIMES_NOT_DISTINCT", "capture timestamps", "must be retained separately")
    rate.raw_sha256 != volume.raw_sha256 ||
        fail("RATE_VOLUME_RAW_HASH_COLLISION", "capture bodies", "must be retained separately")
    rate.revision_token == volume.revision_token ||
        fail("RATE_VOLUME_PAIR_MISMATCH", "revisionIndicator", "tokens differ")
    rate.footnote_token == volume.footnote_token ||
        fail("RATE_VOLUME_PAIR_MISMATCH", "footnote", "tokens differ")
    payload = _observation_payload(
        observation_class,
        publication_date,
        effective_date,
        rate,
        volume,
    )
    digest = semantic_sha256(payload)
    return EndpointObservation(
        SCHEMA_VERSION,
        observation_class,
        publication_date,
        effective_date,
        rate,
        volume,
        payload["rate_completion_claim"],
        payload["volume_completion_claim"],
        volume.response_body_completed_at_utc,
        true,
        digest,
    )
end

function observation_document(observation::EndpointObservation)
    payload = _observation_payload(
        observation.observation_class,
        observation.publication_date,
        observation.effective_date,
        observation.rate,
        observation.volume,
    )
    payload["observation_sha256"] = observation.observation_sha256
    semantic_sha256(
        Dict(key => value for (key, value) in payload if key != "observation_sha256"),
    ) == observation.observation_sha256 ||
        fail("OBSERVATION_DIGEST_MISMATCH", "observation", "internal digest differs")
    return deepcopy(payload)
end

function _validate_binding(
        binding::DecisionBinding,
        morning::EndpointObservation;
        latest_observed_at,
    )
    _expect_id(binding.decision_id, "binding.decision_id")
    binding.created_at_utc >= latest_observed_at ||
        fail("BACKDATING_FORBIDDEN", "binding.created_at_utc", "predates observed evidence")
    _expect_hash(
        binding.predecessor_observation_sha256,
        "binding.predecessor_observation_sha256",
    ) == morning.observation_sha256 ||
        fail("PREDECESSOR_MISMATCH", "binding.predecessor_observation_sha256", "must bind morning observation")
    _expect_hash(binding.predecessor_decision_sha256, "binding.predecessor_decision_sha256")
    binding.superseded_contract_schema_version == V2_SCHEMA_VERSION ||
        fail("SUPERSESSION_MISMATCH", "binding.superseded_contract_schema_version", "must name incompatible v2")
    _expect_hash(
        binding.superseded_capture_manifest_sha256,
        "binding.superseded_capture_manifest_sha256",
    )
    binding.superseded_receipt_status == V2_ABSENT_STATUS ||
        fail("SUPERSESSION_MISMATCH", "binding.superseded_receipt_status", "must preserve absent-field nonreceipt")
    binding.supersession_mode ==
        "APPEND_ONLY_OFFLINE_READJUDICATION_NO_MUTATION_NO_BACKDATING" ||
        fail("MUTATION_OR_BACKDATING_FORBIDDEN", "binding.supersession_mode", "must remain append-only")
    binding.timestamp_evidence_status in (
        "NOT_PROVIDED",
        "CALLER_ASSERTED_RFC3161_TOKEN_NOT_CRYPTOGRAPHICALLY_VERIFIED",
    ) ||
        fail("UNKNOWN_TIMESTAMP_STATUS", "binding.timestamp_evidence_status", "unsupported")
    if binding.timestamp_evidence_status == "NOT_PROVIDED"
        binding.timestamp_token_sha256 == "NONE" ||
            fail("TIMESTAMP_BINDING_MISMATCH", "binding.timestamp_token_sha256", "must be NONE")
    else
        _expect_hash(binding.timestamp_token_sha256, "binding.timestamp_token_sha256")
    end
    return nothing
end

function _gates()
    return Dict{String, Any}(gate => false for gate in ALWAYS_FALSE_GATES)
end

function _binding_document(binding)
    return Dict{String, Any}(
        "decision_id" => binding.decision_id,
        "created_at_utc" => binding.created_at_utc,
        "predecessor_observation_sha256" =>
            binding.predecessor_observation_sha256,
        "predecessor_decision_sha256" =>
            binding.predecessor_decision_sha256,
        "superseded_contract_schema_version" =>
            binding.superseded_contract_schema_version,
        "superseded_capture_manifest_sha256" =>
            binding.superseded_capture_manifest_sha256,
        "superseded_receipt_status" => binding.superseded_receipt_status,
        "supersession_mode" => binding.supersession_mode,
        "timestamp_evidence_status" => binding.timestamp_evidence_status,
        "timestamp_token_sha256" => binding.timestamp_token_sha256,
    )
end

function _decision_document(
        binding,
        morning,
        later,
        decision_class,
        outcome,
        claim,
        blockers,
    )
    morning_rate_lexeme = _numeric_lexeme(morning.rate, "percentRate")
    later_rate_lexeme =
        later === nothing ? "NOT_APPLICABLE" :
        _numeric_lexeme(later.rate, "percentRate")
    basis_points = later === nothing ? nothing :
        _rate_change_basis_points_rational(morning, later)
    selected_rows_identical = later === nothing ? "NOT_APPLICABLE" :
        morning.rate.selected_row_sha256 == later.rate.selected_row_sha256 &&
        morning.volume.selected_row_sha256 == later.volume.selected_row_sha256
    full_bodies_identical = later === nothing ? "NOT_APPLICABLE" :
        morning.rate.raw_sha256 == later.rate.raw_sha256 &&
        morning.volume.raw_sha256 == later.volume.raw_sha256
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => SCHEMA_VERSION,
            "contract_version" => CONTRACT_VERSION,
            "decision_sha256" => repeat("0", 64),
            "canonicalization" =>
                "sorted_typed_length_aware_excluding_artifact_decision_sha256.v1",
            "status" => "OFFLINE_DECISION_NONADMITTING",
        ),
        "binding" => _binding_document(binding),
        "current_state_disposition" => Dict{String, Any}(
            "current_openapi_definition" => "ABSENT",
            "captured_wire_presence" => "ABSENT",
            "authoritative_evidence_ever_official" => "NOT_ESTABLISHED",
            "raw_false_derivation_allowed" => false,
            "synthetic_current_state_added" => false,
        ),
        "decision" => Dict{String, Any}(
            "decision_class" => decision_class,
            "outcome" => outcome,
            "claim" => claim,
            "publication_date" => string(morning.publication_date),
            "effective_date" => string(morning.effective_date),
            "morning_observation_sha256" => morning.observation_sha256,
            "later_observation_sha256" =>
                later === nothing ? "NOT_APPLICABLE" : later.observation_sha256,
            "morning_pair_as_of_utc" => morning.pair_as_of_utc,
            "later_pair_as_of_utc" =>
                later === nothing ? "NOT_APPLICABLE" : later.pair_as_of_utc,
            "latest_evidence_observed_at_utc" =>
                later === nothing ?
                morning.volume.response_metadata_observed_at_utc :
                later.volume.response_metadata_observed_at_utc,
            "morning_percent_rate_lexeme" => morning_rate_lexeme,
            "later_percent_rate_lexeme" => later_rate_lexeme,
            "rate_change_basis_points_numerator" =>
                basis_points === nothing ?
                "NOT_APPLICABLE" : string(numerator(basis_points)),
            "rate_change_basis_points_denominator" =>
                basis_points === nothing ?
                "NOT_APPLICABLE" : string(denominator(basis_points)),
            "morning_revision_token" => morning.rate.revision_token,
            "later_revision_token" =>
                later === nothing ?
                "NOT_APPLICABLE" : later.rate.revision_token,
            "selected_effr_rows_identical" => selected_rows_identical,
            "full_response_bodies_identical" => full_bodies_identical,
            "rate_volume_requests_atomic" => false,
            "final_state_for_day_claimed" => false,
            "no_later_revision_claimed" => false,
        ),
        "estimand" => Dict{String, Any}(
            "status" => ESTIMAND_STATUS,
            "candidate_estimands" => collect(ESTIMAND_CANDIDATES),
            "selected_estimand" => "NONE",
            "owner_validator_decision_required" => true,
        ),
        "evidence_layers" => Dict{String, Any}(
            "local_integrity_validated" => true,
            "publication_endpoint_state_observed" => true,
            "transport_provenance_authenticated" => false,
            "publisher_provenance_authenticated" => false,
            "external_timestamp_authenticated" => false,
            "profile_complete" => false,
            "origin_admitted" => false,
        ),
        "gates" => _gates(),
        "blockers" => sort!(unique(collect(blockers))),
    )
    document["artifact"]["decision_sha256"] =
        _decision_semantic_sha256(document)
    return document
end

function adjudicate_morning_observation(
        morning::EndpointObservation,
        binding::DecisionBinding,
    )
    morning.observation_class == MORNING_WINDOW_ENDPOINT_OBSERVATION ||
        fail("OBSERVATION_CLASS_MISMATCH", "morning", "must be morning endpoint")
    _validate_binding(
        binding,
        morning;
        latest_observed_at = morning.volume.response_metadata_observed_at_utc,
    )
    blockers = (
        BASE_BLOCKERS...,
        "NO_POST_REVISION_WINDOW_OBSERVATION_LINKED",
        morning.rate.revision_token == "r" ?
            "MORNING_ENDPOINT_ALREADY_MARKED_REVISED_NOT_FIRST_STATE" :
            "FIRST_PUBLIC_BYTES_NOT_ESTABLISHED",
    )
    document = _decision_document(
        binding,
        morning,
        nothing,
        MORNING_WINDOW_ENDPOINT_OBSERVATION,
        "MORNING_WINDOW_ENDPOINT_OBSERVATION_RECORDED",
        "STATE_OBSERVED_BY_RECORDED_RATE_AND_VOLUME_COMPLETION_TIMES",
        blockers,
    )
    return validate_decision_document(
        document,
        document["artifact"]["decision_sha256"],
    )
end

function _rate_change_rational(morning, later)
    old_rate = _numeric_rational(morning.rate, "percentRate")
    new_rate = _numeric_rational(later.rate, "percentRate")
    return abs(new_rate - old_rate)
end

_rate_change_basis_points_rational(morning, later) =
    100 * _rate_change_rational(morning, later)

function _transition_outcome_from_facts(
        morning_token,
        later_token,
        selected_rows_identical,
        full_bodies_identical,
        rate_change_basis_points,
    )
    if morning_token == "r"
        return (
            "QUARANTINED_MORNING_ALREADY_MARKED_REVISED",
            "MORNING_ENDPOINT_NOT_CLASSIFIED_AS_FIRST_PUBLICATION",
            ("MORNING_ENDPOINT_ALREADY_MARKED_REVISED_NOT_FIRST_STATE",),
        )
    end
    if later_token == ""
        if selected_rows_identical && full_bodies_identical
            return (
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE",
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE",
                ("FIRST_PUBLIC_BYTES_NOT_ESTABLISHED",),
            )
        elseif !selected_rows_identical
            return (
                "QUARANTINED_UNMARKED_EFFR_TRANSITION",
                "SELECTED_EFFR_SEMANTICS_CHANGED_WITHOUT_RAW_R_TOKEN",
                ("UNMARKED_EFFR_TRANSITION",),
            )
        end
        return (
            "QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION",
            "FULL_RESPONSE_CHANGED_WITHOUT_SELECTED_EFFR_TRANSITION",
            ("NON_EFFR_OR_SERIALIZATION_CHANGE_REQUIRES_FROZEN_RULE",),
        )
    end
    rate_change_basis_points > big(1) // big(1) ||
        return (
        "QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT",
        "RAW_R_TOKEN_LACKS_STRICTLY_GREATER_THAN_ONE_BASIS_POINT_RATE_CHANGE",
        ("MARKED_REVISION_POLICY_INCONSISTENT",),
    )
    return (
        "MARKED_SAME_DAY_REVISION_OBSERVED",
        "MARKED_SAME_DAY_REVISION_OBSERVED",
        ("LATER_OR_EXTRAORDINARY_CORRECTION_NOT_RULED_OUT",),
    )
end

function _transition_outcome(morning, later)
    selected_rows_identical =
        morning.rate.selected_row_sha256 == later.rate.selected_row_sha256 &&
        morning.volume.selected_row_sha256 ==
        later.volume.selected_row_sha256
    full_bodies_identical =
        morning.rate.raw_sha256 == later.rate.raw_sha256 &&
        morning.volume.raw_sha256 == later.volume.raw_sha256
    return _transition_outcome_from_facts(
        morning.rate.revision_token,
        later.rate.revision_token,
        selected_rows_identical,
        full_bodies_identical,
        _rate_change_basis_points_rational(morning, later),
    )
end

function adjudicate_transition(
        morning::EndpointObservation,
        later::EndpointObservation,
        binding::DecisionBinding,
    )
    morning.observation_class == MORNING_WINDOW_ENDPOINT_OBSERVATION ||
        fail("OBSERVATION_CLASS_MISMATCH", "morning", "must be morning endpoint")
    later.observation_class == POST_REVISION_WINDOW_ENDPOINT_OBSERVATION ||
        fail("OBSERVATION_CLASS_MISMATCH", "later", "must be post-revision endpoint")
    morning.publication_date == later.publication_date ||
        fail("TRANSITION_DATE_MISMATCH", "publication_date", "observations differ")
    morning.effective_date == later.effective_date ||
        fail("TRANSITION_DATE_MISMATCH", "effective_date", "observations differ")
    morning.volume.response_metadata_observed_at_utc <
        later.rate.request_started_at_utc ||
        fail("TRANSITION_TIME_ORDER_VIOLATION", "observations", "later capture must follow morning")
    _validate_binding(
        binding,
        morning;
        latest_observed_at = later.volume.response_metadata_observed_at_utc,
    )
    outcome, claim, transition_blockers =
        _transition_outcome(morning, later)
    blockers = (BASE_BLOCKERS..., transition_blockers...)
    document = _decision_document(
        binding,
        morning,
        later,
        OBSERVED_EFFR_TRANSITION,
        outcome,
        claim,
        blockers,
    )
    return validate_decision_document(
        document,
        document["artifact"]["decision_sha256"],
    )
end

decision_document(document::AbstractDict) = deepcopy(document)

function validate_decision_document(document, expected_sha256)
    expected = _expect_hash(expected_sha256, "expected_sha256")
    decision = _closed_keys(
        document,
        (
            "artifact",
            "binding",
            "blockers",
            "current_state_disposition",
            "decision",
            "estimand",
            "evidence_layers",
            "gates",
        ),
        "decision",
    )
    artifact = _closed_keys(
        decision["artifact"],
        (
            "canonicalization",
            "contract_version",
            "decision_sha256",
            "schema_version",
            "status",
        ),
        "artifact",
    )
    _expect_string(artifact["schema_version"], "artifact.schema_version") ==
        SCHEMA_VERSION ||
        fail("WRONG_SCHEMA_VERSION", "artifact.schema_version", "must be v3")
    _expect_string(artifact["contract_version"], "artifact.contract_version") ==
        CONTRACT_VERSION ||
        fail("WRONG_CONTRACT_VERSION", "artifact.contract_version", "must be 3.0.0")
    _expect_string(artifact["status"], "artifact.status") ==
        "OFFLINE_DECISION_NONADMITTING" ||
        fail("TRUST_ELEVATION_FORBIDDEN", "artifact.status", "must remain nonadmitting")
    _expect_string(artifact["canonicalization"], "artifact.canonicalization") ==
        "sorted_typed_length_aware_excluding_artifact_decision_sha256.v1" ||
        fail("CANONICALIZATION_CHANGED", "artifact.canonicalization", "unsupported")
    embedded = _expect_hash(artifact["decision_sha256"], "artifact.decision_sha256")
    reproduced = _decision_semantic_sha256(decision)
    embedded == reproduced ||
        fail("DECISION_DIGEST_MISMATCH", "artifact.decision_sha256", "does not reproduce")
    embedded == expected ||
        fail("OUT_OF_BAND_PIN_MISMATCH", "expected_sha256", "does not match decision")

    disposition = _closed_keys(
        decision["current_state_disposition"],
        (
            "authoritative_evidence_ever_official",
            "captured_wire_presence",
            "current_openapi_definition",
            "raw_false_derivation_allowed",
            "synthetic_current_state_added",
        ),
        "current_state_disposition",
    )
    disposition["current_openapi_definition"] == "ABSENT" &&
        disposition["captured_wire_presence"] == "ABSENT" &&
        disposition["authoritative_evidence_ever_official"] ==
        "NOT_ESTABLISHED" ||
        fail("CURRENT_STATE_DISPOSITION_CHANGED", "current_state_disposition", "unsupported")
    _expect_bool(
        disposition["raw_false_derivation_allowed"],
        false,
        "current_state_disposition.raw_false_derivation_allowed",
    )
    _expect_bool(
        disposition["synthetic_current_state_added"],
        false,
        "current_state_disposition.synthetic_current_state_added",
    )

    estimand = _closed_keys(
        decision["estimand"],
        (
            "candidate_estimands",
            "owner_validator_decision_required",
            "selected_estimand",
            "status",
        ),
        "estimand",
    )
    estimand["status"] == ESTIMAND_STATUS &&
        estimand["selected_estimand"] == "NONE" ||
        fail("ESTIMAND_PRESELECTION_FORBIDDEN", "estimand", "must remain pending")
    _expect_bool(
        estimand["owner_validator_decision_required"],
        true,
        "estimand.owner_validator_decision_required",
    )
    _validate_exact_array(
        estimand["candidate_estimands"],
        collect(ESTIMAND_CANDIDATES),
        "estimand.candidate_estimands",
    )

    gates = _closed_keys(decision["gates"], ALWAYS_FALSE_GATES, "gates")
    for gate in ALWAYS_FALSE_GATES
        _expect_bool(gates[gate], false, "gates.$gate")
    end
    layers = _closed_keys(
        decision["evidence_layers"],
        (
            "external_timestamp_authenticated",
            "local_integrity_validated",
            "origin_admitted",
            "profile_complete",
            "publication_endpoint_state_observed",
            "publisher_provenance_authenticated",
            "transport_provenance_authenticated",
        ),
        "evidence_layers",
    )
    _expect_bool(layers["local_integrity_validated"], true, "evidence_layers.local_integrity_validated")
    _expect_bool(
        layers["publication_endpoint_state_observed"],
        true,
        "evidence_layers.publication_endpoint_state_observed",
    )
    for key in (
            "external_timestamp_authenticated",
            "origin_admitted",
            "profile_complete",
            "publisher_provenance_authenticated",
            "transport_provenance_authenticated",
        )
        _expect_bool(layers[key], false, "evidence_layers.$key")
    end
    core = _closed_keys(
        decision["decision"],
        (
            "claim",
            "decision_class",
            "effective_date",
            "final_state_for_day_claimed",
            "full_response_bodies_identical",
            "later_observation_sha256",
            "later_pair_as_of_utc",
            "latest_evidence_observed_at_utc",
            "later_percent_rate_lexeme",
            "later_revision_token",
            "morning_observation_sha256",
            "morning_pair_as_of_utc",
            "morning_percent_rate_lexeme",
            "morning_revision_token",
            "no_later_revision_claimed",
            "outcome",
            "publication_date",
            "rate_change_basis_points_denominator",
            "rate_change_basis_points_numerator",
            "rate_volume_requests_atomic",
            "selected_effr_rows_identical",
        ),
        "decision.decision",
    )
    decision_class = core["decision_class"]
    decision_class in (
        MORNING_WINDOW_ENDPOINT_OBSERVATION,
        OBSERVED_EFFR_TRANSITION,
    ) ||
        fail("UNKNOWN_DECISION_CLASS", "decision.decision_class", "unsupported")
    _expect_bool(
        core["rate_volume_requests_atomic"],
        false,
        "decision.rate_volume_requests_atomic",
    )
    _expect_bool(
        core["final_state_for_day_claimed"],
        false,
        "decision.final_state_for_day_claimed",
    )
    _expect_bool(
        core["no_later_revision_claimed"],
        false,
        "decision.no_later_revision_claimed",
    )
    morning_observation_sha256 = _expect_hash(
        core["morning_observation_sha256"],
        "decision.morning_observation_sha256",
    )
    morning_pair_as_of = core["morning_pair_as_of_utc"]
    morning_pair_as_of isa DateTime ||
        fail("TYPE_MISMATCH", "decision.morning_pair_as_of_utc", "must be DateTime")
    latest_evidence = core["latest_evidence_observed_at_utc"]
    latest_evidence isa DateTime ||
        fail("TYPE_MISMATCH", "decision.latest_evidence_observed_at_utc", "must be DateTime")
    later_hash = core["later_observation_sha256"]
    later_pair_as_of = core["later_pair_as_of_utc"]
    if decision_class == MORNING_WINDOW_ENDPOINT_OBSERVATION
        later_hash == "NOT_APPLICABLE" ||
            fail("DECISION_CLASS_MISMATCH", "decision.later_observation_sha256", "must be not applicable")
        later_pair_as_of == "NOT_APPLICABLE" ||
            fail("DECISION_CLASS_MISMATCH", "decision.later_pair_as_of_utc", "must be not applicable")
        latest_evidence >= morning_pair_as_of ||
            fail("DECISION_TIME_ORDER_VIOLATION", "decision.latest_evidence_observed_at_utc", "precedes pair")
    else
        _expect_hash(later_hash, "decision.later_observation_sha256") !=
            morning_observation_sha256 ||
            fail(
            "TRANSITION_OBSERVATION_COLLISION",
            "decision.later_observation_sha256",
            "must differ from the morning observation",
        )
        later_pair_as_of isa DateTime ||
            fail("TYPE_MISMATCH", "decision.later_pair_as_of_utc", "must be DateTime")
        morning_pair_as_of < later_pair_as_of <= latest_evidence ||
            fail("DECISION_TIME_ORDER_VIOLATION", "decision pair times", "must be strictly ordered")
    end
    publication_text = _expect_string(core["publication_date"], "decision.publication_date")
    effective_text = _expect_string(core["effective_date"], "decision.effective_date")
    publication = try
        Date(publication_text)
    catch
        fail("DATE_PARSE_FAILED", "decision.publication_date", "must be canonical YYYY-MM-DD")
    end
    effective = try
        Date(effective_text)
    catch
        fail("DATE_PARSE_FAILED", "decision.effective_date", "must be canonical YYYY-MM-DD")
    end
    string(publication) == publication_text &&
        string(effective) == effective_text ||
        fail("NONCANONICAL_DATE", "decision dates", "must be canonical")
    day = _campaign_day(publication)
    get(day, "effective_date", nothing) == effective_text ||
        fail("EFFECTIVE_DATE_MISMATCH", "decision.effective_date", "does not match pinned schedule")
    morning_window_start, morning_window_end, _ = _window(
        publication,
        MORNING_WINDOW_ENDPOINT_OBSERVATION,
    )
    morning_window_start < morning_pair_as_of <= morning_window_end ||
        fail(
        "DECISION_WINDOW_VIOLATION",
        "decision.morning_pair_as_of_utc",
        "must fall inside the pinned morning window",
    )
    if decision_class == MORNING_WINDOW_ENDPOINT_OBSERVATION
        morning_pair_as_of <= latest_evidence <= morning_window_end ||
            fail(
            "DECISION_WINDOW_VIOLATION",
            "decision.latest_evidence_observed_at_utc",
            "must remain inside the pinned morning window",
        )
    else
        later_window_start, later_window_end, _ = _window(
            publication,
            POST_REVISION_WINDOW_ENDPOINT_OBSERVATION,
        )
        later_window_start < later_pair_as_of <= latest_evidence <=
            later_window_end ||
            fail(
            "DECISION_WINDOW_VIOLATION",
            "decision later timestamps",
            "must remain inside the pinned post-revision window",
        )
    end
    outcome = _expect_string(core["outcome"], "decision.outcome")
    haskey(OUTCOME_CLAIMS, outcome) ||
        fail("UNKNOWN_DECISION_OUTCOME", "decision.outcome", "unsupported")
    claim = _expect_string(core["claim"], "decision.claim")
    claim == OUTCOME_CLAIMS[outcome] ||
        fail("CLAIM_CEILING_VIOLATION", "decision.claim", "does not match closed outcome")
    morning_rate_lexeme = _expect_string(
        core["morning_percent_rate_lexeme"],
        "decision.morning_percent_rate_lexeme",
    )
    morning_rate = _exact_json_number(
        morning_rate_lexeme,
        "decision.morning_percent_rate_lexeme",
    ).value
    morning_revision_token = _expect_string(
        core["morning_revision_token"],
        "decision.morning_revision_token";
        allow_empty = true,
    )
    morning_revision_token in ALLOWED_REVISION_TOKENS ||
        fail("UNKNOWN_REVISION_TOKEN", "decision.morning_revision_token", "unsupported")
    if decision_class == MORNING_WINDOW_ENDPOINT_OBSERVATION
        outcome == "MORNING_WINDOW_ENDPOINT_OBSERVATION_RECORDED" ||
            fail("DECISION_CLASS_MISMATCH", "decision.outcome", "morning class has wrong outcome")
        for field in (
                "later_percent_rate_lexeme",
                "later_revision_token",
                "rate_change_basis_points_numerator",
                "rate_change_basis_points_denominator",
                "selected_effr_rows_identical",
                "full_response_bodies_identical",
            )
            core[field] == "NOT_APPLICABLE" ||
                fail("DECISION_CLASS_MISMATCH", "decision.$field", "must be not applicable")
        end
        expected_specific_blockers = (
            "NO_POST_REVISION_WINDOW_OBSERVATION_LINKED",
            morning_revision_token == "r" ?
                "MORNING_ENDPOINT_ALREADY_MARKED_REVISED_NOT_FIRST_STATE" :
                "FIRST_PUBLIC_BYTES_NOT_ESTABLISHED",
        )
    else
        outcome != "MORNING_WINDOW_ENDPOINT_OBSERVATION_RECORDED" ||
            fail("DECISION_CLASS_MISMATCH", "decision.outcome", "transition has morning outcome")
        later_rate_lexeme = _expect_string(
            core["later_percent_rate_lexeme"],
            "decision.later_percent_rate_lexeme",
        )
        later_rate = _exact_json_number(
            later_rate_lexeme,
            "decision.later_percent_rate_lexeme",
        ).value
        rate_change = 100 * abs(later_rate - morning_rate)
        expected_numerator = string(numerator(rate_change))
        expected_denominator = string(denominator(rate_change))
        recorded_numerator = _expect_string(
            core["rate_change_basis_points_numerator"],
            "decision.rate_change_basis_points_numerator",
        )
        recorded_denominator = _expect_string(
            core["rate_change_basis_points_denominator"],
            "decision.rate_change_basis_points_denominator",
        )
        occursin(r"^(0|[1-9][0-9]*)$", recorded_numerator) ||
            fail(
            "NONCANONICAL_EXACT_RATIONAL",
            "decision.rate_change_basis_points_numerator",
            "must be a canonical nonnegative integer",
        )
        occursin(r"^[1-9][0-9]*$", recorded_denominator) ||
            fail(
            "NONCANONICAL_EXACT_RATIONAL",
            "decision.rate_change_basis_points_denominator",
            "must be a canonical positive integer",
        )
        recorded_numerator == expected_numerator &&
            recorded_denominator == expected_denominator ||
            fail(
            "EXACT_RATE_CHANGE_MISMATCH",
            "decision.rate_change_basis_points",
            "does not reproduce from the preserved decimal lexemes",
        )
        later_revision_token = _expect_string(
            core["later_revision_token"],
            "decision.later_revision_token";
            allow_empty = true,
        )
        later_revision_token in ALLOWED_REVISION_TOKENS ||
            fail("UNKNOWN_REVISION_TOKEN", "decision.later_revision_token", "unsupported")
        selected_rows_identical = core["selected_effr_rows_identical"]
        selected_rows_identical isa Bool ||
            fail("TYPE_MISMATCH", "decision.selected_effr_rows_identical", "must be Bool")
        full_bodies_identical = core["full_response_bodies_identical"]
        full_bodies_identical isa Bool ||
            fail("TYPE_MISMATCH", "decision.full_response_bodies_identical", "must be Bool")
        full_bodies_identical && !selected_rows_identical &&
            fail(
            "TRANSITION_FACT_INCONSISTENT",
            "decision transition equality facts",
            "identical full bodies require identical selected rows",
        )
        selected_rows_identical &&
            morning_revision_token != later_revision_token &&
            fail(
            "TRANSITION_FACT_INCONSISTENT",
            "decision.selected_effr_rows_identical",
            "identical selected rows require equal revision tokens",
        )
        selected_rows_identical && !iszero(rate_change) &&
            fail(
            "TRANSITION_FACT_INCONSISTENT",
            "decision.selected_effr_rows_identical",
            "identical numeric-canonical rows require zero rate change",
        )
        full_bodies_identical &&
            morning_rate_lexeme != later_rate_lexeme &&
            fail(
            "TRANSITION_FACT_INCONSISTENT",
            "decision.full_response_bodies_identical",
            "identical full bodies require identical raw rate lexemes",
        )
        expected_outcome, expected_claim, expected_specific_blockers =
            _transition_outcome_from_facts(
            morning_revision_token,
            later_revision_token,
            selected_rows_identical,
            full_bodies_identical,
            rate_change,
        )
        outcome == expected_outcome && claim == expected_claim ||
            fail(
            "DECISION_RECOMPUTATION_MISMATCH",
            "decision outcome",
            "exact transition replay produces $expected_outcome",
        )
    end
    blockers = decision["blockers"]
    blockers isa AbstractVector ||
        fail("TYPE_MISMATCH", "blockers", "must be an array")
    all(blocker -> blocker isa String, blockers) ||
        fail("TYPE_MISMATCH", "blockers", "all blockers must be strings")
    blockers == sort!(unique(copy(blockers))) ||
        fail("NONCANONICAL_BLOCKERS", "blockers", "must be sorted and unique")
    expected_blockers =
        sort!(unique([BASE_BLOCKERS..., expected_specific_blockers...]))
    blockers == expected_blockers ||
        fail("BLOCKER_RECOMPUTATION_MISMATCH", "blockers", "does not match exact decision replay")

    binding = _closed_keys(
        decision["binding"],
        (
            "created_at_utc",
            "decision_id",
            "predecessor_decision_sha256",
            "predecessor_observation_sha256",
            "superseded_capture_manifest_sha256",
            "superseded_contract_schema_version",
            "superseded_receipt_status",
            "supersession_mode",
            "timestamp_evidence_status",
            "timestamp_token_sha256",
        ),
        "binding",
    )
    _expect_id(binding["decision_id"], "binding.decision_id")
    binding["created_at_utc"] isa DateTime ||
        fail("TYPE_MISMATCH", "binding.created_at_utc", "must be DateTime")
    binding["created_at_utc"] >= latest_evidence ||
        fail("BACKDATING_FORBIDDEN", "binding.created_at_utc", "predates linked evidence")
    _expect_hash(binding["predecessor_decision_sha256"], "binding.predecessor_decision_sha256")
    _expect_hash(
        binding["predecessor_observation_sha256"],
        "binding.predecessor_observation_sha256",
    ) == core["morning_observation_sha256"] ||
        fail("PREDECESSOR_MISMATCH", "binding.predecessor_observation_sha256", "does not bind morning observation")
    _expect_hash(binding["superseded_capture_manifest_sha256"], "binding.superseded_capture_manifest_sha256")
    binding["superseded_contract_schema_version"] == V2_SCHEMA_VERSION ||
        fail("SUPERSESSION_MISMATCH", "binding.superseded_contract_schema_version", "must name v2")
    binding["superseded_receipt_status"] == V2_ABSENT_STATUS ||
        fail("SUPERSESSION_MISMATCH", "binding.superseded_receipt_status", "must preserve nonreceipt")
    binding["supersession_mode"] ==
        "APPEND_ONLY_OFFLINE_READJUDICATION_NO_MUTATION_NO_BACKDATING" ||
        fail("MUTATION_OR_BACKDATING_FORBIDDEN", "binding.supersession_mode", "must remain append-only")
    timestamp_status = binding["timestamp_evidence_status"]
    timestamp_status in (
        "NOT_PROVIDED",
        "CALLER_ASSERTED_RFC3161_TOKEN_NOT_CRYPTOGRAPHICALLY_VERIFIED",
    ) ||
        fail("UNKNOWN_TIMESTAMP_STATUS", "binding.timestamp_evidence_status", "unsupported")
    timestamp_token = _expect_string(
        binding["timestamp_token_sha256"],
        "binding.timestamp_token_sha256",
    )
    if timestamp_status == "NOT_PROVIDED"
        timestamp_token == "NONE" ||
            fail("TIMESTAMP_BINDING_MISMATCH", "binding.timestamp_token_sha256", "must be NONE")
    else
        occursin(HASH_PATTERN, timestamp_token) ||
            fail("TIMESTAMP_BINDING_MISMATCH", "binding.timestamp_token_sha256", "invalid")
    end
    return deepcopy(decision)
end

end
