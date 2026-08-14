module USBLSCPSProspectiveCaptureSetV1

using SHA
using TOML

export CaptureSetError,
    PROFILE_PATH,
    canonical_post_bodies,
    parse_json_strict,
    parse_tsv_strict,
    profile_semantic_sha256,
    validate_capture_set,
    validate_compiled_result,
    validate_profile

const PROFILE_PATH = joinpath(@__DIR__, "bls_cps_prospective_capture_set_v1.toml")
const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."))
const PROFILE_SCHEMA = "beforeit-us-bls-cps-prospective-capture-set.v1"
const CANONICALIZATION = "sorted-typed-length-aware-excluding-artifact-content-sha256.v1"
const EXPECTED_CONTRACT_ID =
    "bls-cps-final-structural-pre-origin-offline-candidate.audit-repaired.v2"
const EXPECTED_PROFILE_PHYSICAL_SHA256 =
    "426c312ba290a11ae117c595e16936c189a64fc4aaa3e0a5273b13aecb92d33a"
const EXPECTED_PROFILE_SEMANTIC_SHA256 =
    "68e8d7a1a366c9409e4a29f83dfa90864fbcb0024fcbd91aa53cc16dcbd04e8b"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const MONTH_PERIODS = ["M" * lpad(string(month), 2, '0') for month in 1:12]
const PERIOD_NAMES = Dict(
    "M01" => "January",
    "M02" => "February",
    "M03" => "March",
    "M04" => "April",
    "M05" => "May",
    "M06" => "June",
    "M07" => "July",
    "M08" => "August",
    "M09" => "September",
    "M10" => "October",
    "M11" => "November",
    "M12" => "December",
    "M13" => "Annual",
)
const SERIES_HEADER = [
    "series_id",
    "series_title",
    "seasonal_code",
    "periodicity_code",
    "tdat_code",
    "lfst_code",
    "ages_code",
    "begin_year",
    "begin_period",
    "end_year",
    "end_period",
]
const LOOKUP_SPECS = Dict(
    "catalog_ln_footnote" => ("footnote_code", "footnote_text"),
    "catalog_ln_seasonal" => ("seasonal_code", "seasonal_text"),
    "catalog_ln_periodicity" => ("periodicity_code", "periodicity_text"),
    "catalog_ln_lfst" => ("lfst_code", "lfst_text"),
    "catalog_ln_ages" => ("ages_code", "ages_text"),
    "catalog_ln_tdat" => ("tdat_code", "tdat_text"),
)
const EXPECTED_PROHIBITED_ACTIONS = [
    "NETWORK_REQUEST",
    "FILESYSTEM_WRITE",
    "RAW_CAPTURE",
    "ORIGIN_ADMISSION",
    "SOURCE_INVENTORY_MUTATION",
    "FORECAST_EXECUTION",
    "TRUTH_ACCESS",
    "SCORING",
    "CLAIM_FIRST_PUBLIC_HISTORY",
    "CLAIM_PUBLISHER_AUTHENTICATION",
    "CLAIM_INJECTED_BYTES_CAME_FROM_PLANNED_URL",
    "MANIFEST_PROJECTION_AS_PROVIDER_RAW_OBJECT",
]
const EXPECTED_LIMITS = Dict{String, Any}(
    "max_json_bytes" => 8_388_608,
    "max_json_depth" => 64,
    "max_json_nodes" => 250_000,
    "max_json_string_bytes" => 1_048_576,
    "max_ln_series_bytes" => 33_554_432,
    "max_lookup_tsv_bytes" => 8_388_608,
    "max_tsv_lines" => 500_000,
    "max_tsv_columns" => 64,
    "max_tsv_field_bytes" => 1_048_576,
    "max_text_lines" => 100_000,
    "ln_series_ceiling_rationale" =>
        "32_MiB_is_more_than_twice_independent_audit_reference_size_15288538_bytes",
)
const EXPECTED_SOURCE_PINS = [
    ("prospective_v2_module", "scripts/us/forecasting/vintages/prospective/USProspectiveAcquisitionContractV2.jl", "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379"),
    ("prospective_v2_contract", "scripts/us/forecasting/vintages/prospective/prospective_2026q3_contract_v2.toml", "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"),
    ("common_origin_v3_module", "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/USCommonOriginAcquisitionV3.jl", "b82c6ab5c2830b8f23ec92971ed3930790f60fd3d09e0beaf4c98a66938cdf57"),
    ("common_origin_v3_policy", "scripts/us/forecasting/vintages/prospective/common_origin_acquisition_v3/common_origin_acquisition_v3_policy.toml", "1cdd7834e76fb414761c41470319dfeded97f5dd5e9f0cf420893717d5f2d8ce"),
    ("accepted_snapshot_envelope_module", "scripts/us/forecasting/vintages/bea_industry/prospective_snapshot_envelope_v1/USProspectiveSnapshotEnvelopeV1.jl", "cb8fffd626c019fa6ce65a32664a46d1ecd87d3337f72ea378900d2d4f05b165"),
    ("accepted_snapshot_envelope_tests", "scripts/us/forecasting/vintages/bea_industry/prospective_snapshot_envelope_v1/test_prospective_snapshot_envelope_v1.jl", "ae36445f9b7af77fa8a93a945bab2109382c881e2942c71c78f9252a29470d1e"),
    ("sources_toml", "scripts/us/sources.toml", "41b2bf73b92fb0cf9d9e02ae836beb91d07cd6a3bd20ecf668882350c86f23c9"),
    ("us_pipeline", "scripts/us/USPipeline.jl", "ce4d8138a1c07fdc9509d7560f307f226dc314eb0a4394270ef1e1014b9ca14d"),
    ("project_toml", "scripts/us/Project.toml", "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"),
    ("manifest_toml", "scripts/us/Manifest.toml", "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"),
    ("current_inventory", "scripts/us/forecasting/vintages/current_inventory.toml", "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"),
]

struct CaptureSetError <: Exception
    code::Symbol
    detail::String
end

Base.showerror(io::IO, error::CaptureSetError) =
    print(io, String(error.code), ": ", error.detail)

_fail(code::Symbol, detail) = throw(CaptureSetError(code, string(detail)))

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        keys_sorted = sort!(collect(String.(keys(value))))
        write(io, "D", string(length(keys_sorted)), ":")
        for key in keys_sorted
            _canonical_write(io, key)
            _canonical_write(io, value[key])
        end
    elseif value isa AbstractVector
        write(io, "A", string(length(value)), ":")
        for element in value
            _canonical_write(io, element)
        end
    elseif value isa Bool
        write(io, value ? "B1" : "B0")
    elseif value isa Integer
        representation = string(value)
        write(io, "I", string(ncodeunits(representation)), ":", representation)
    elseif value isa AbstractFloat
        representation = repr(value)
        write(io, "F", string(ncodeunits(representation)), ":", representation)
    elseif value isa AbstractString
        write(io, "S", string(ncodeunits(value)), ":", value)
    elseif value === nothing
        write(io, "N")
    else
        _fail(:unsupported_canonical_type, typeof(value))
    end
    return io
end

function _semantic_document(document::AbstractDict)
    copy = deepcopy(document)
    artifact = get(copy, "artifact", nothing)
    artifact isa AbstractDict || _fail(:profile_artifact_missing, "artifact table is required")
    pop!(artifact, "content_sha256", nothing)
    return copy
end

function _canonical_sha256(document::AbstractDict; exclude_artifact_hash::Bool = false)
    io = IOBuffer()
    _canonical_write(io, exclude_artifact_hash ? _semantic_document(document) : document)
    return bytes2hex(sha256(take!(io)))
end

profile_semantic_sha256(profile::AbstractDict) =
    _canonical_sha256(profile; exclude_artifact_hash = true)

function _expect_exact_keys(value, expected, code::Symbol)
    value isa AbstractDict || _fail(code, "expected object")
    actual = Set(String.(keys(value)))
    target = Set(String.(expected))
    actual == target || _fail(code, "expected $(sort!(collect(target))); got $(sort!(collect(actual)))")
    return value
end

function _exact_int(value, code::Symbol)
    typeof(value) === Int || _fail(code, "expected Int, got $(typeof(value))")
    return value
end

function _exact_bool(value, expected::Bool, code::Symbol)
    value isa Bool && value === expected || _fail(code, "expected $expected")
    return value
end

function _canonical_body(series_ids, start_year::Int, end_year::Int)
    quoted = join(("\"" * id * "\"" for id in series_ids), ",")
    return "{\"seriesid\":[" * quoted * "],\"startyear\":\"" *
        string(start_year) * "\",\"endyear\":\"" * string(end_year) * "\"}"
end

function canonical_post_bodies(profile::AbstractDict = validate_profile())
    return [String(chunk["body"]) for chunk in profile["chunks"]]
end

function _validate_profile_document_unit(profile::AbstractDict)
    _expect_exact_keys(
        profile,
        [
            "prohibited_actions", "artifact", "scope", "origin", "release", "routes",
            "limits", "coverage", "catalog_contract", "profiles", "chunks",
            "catalog_objects", "source_pins", "gates",
        ],
        :profile_top_level_shape,
    )
    artifact = _expect_exact_keys(
        profile["artifact"],
        ["schema_version", "contract_id", "status", "canonicalization", "content_sha256"],
        :profile_artifact_shape,
    )
    artifact["schema_version"] == PROFILE_SCHEMA || _fail(:profile_schema, artifact["schema_version"])
    artifact["contract_id"] == EXPECTED_CONTRACT_ID || _fail(:profile_contract_id, artifact["contract_id"])
    artifact["status"] == "CANNOT_RUN" || _fail(:profile_status, artifact["status"])
    artifact["canonicalization"] == CANONICALIZATION || _fail(:profile_canonicalization, artifact["canonicalization"])
    occursin(HASH_PATTERN, artifact["content_sha256"]) || _fail(:profile_semantic_hash_format, artifact["content_sha256"])
    semantic_hash = profile_semantic_sha256(profile)
    semantic_hash == artifact["content_sha256"] || _fail(:profile_semantic_hash, "semantic self-hash mismatch")
    if EXPECTED_PROFILE_SEMANTIC_SHA256 != "TO_BE_FROZEN"
        semantic_hash == EXPECTED_PROFILE_SEMANTIC_SHA256 || _fail(:profile_frozen_semantic_hash, "coordinated restamp rejected")
    end
    profile["prohibited_actions"] == EXPECTED_PROHIBITED_ACTIONS || _fail(:prohibited_actions, "exact action list drift")

    scope = profile["scope"]
    scope["requirement_id"] == "bls_cps_structural" || _fail(:requirement_id, scope["requirement_id"])
    scope["source_id"] == "bls_cps_structural_controls" || _fail(:source_id, scope["source_id"])
    scope["capture_id"] == "final_structural_pre_origin" || _fail(:capture_id, scope["capture_id"])
    for key in ("offline_validation_only", "synthetic_input_only")
        _exact_bool(scope[key], true, :scope_boundary)
    end
    for key in (
            "current_v3_integration", "catalog_provider_layout_evidenced",
            "catalog_projection_operational", "injected_bytes_are_provider_url_bytes",
            "full_provider_object_completeness_proven", "actual_bls_bytes_claimed",
            "availability_claimed", "atomicity_claimed", "first_public_history_claimed",
            "publisher_authentication_claimed",
        )
        _exact_bool(scope[key], false, :scope_claim_ceiling)
    end
    scope["catalog_evidence_status"] == "MISSING_FUTURE_PROSPECTIVE_FULL_CATALOG_CAPTURE_REQUIRED" || _fail(:catalog_evidence_status, scope["catalog_evidence_status"])
    scope["current_v3_gap"] == "v3_has_no_set_valued_raw_object_media_or_catalog_trust_branch" || _fail(:v3_gap, scope["current_v3_gap"])
    for key in ("network_action_count", "filesystem_write_action_count", "current_qualified_count")
        _exact_int(scope[key], :scope_action_count) == 0 || _fail(:scope_action_count, key)
    end
    _exact_int(scope["profile_count"], :profile_count) == 6 || _fail(:profile_count, scope["profile_count"])
    _exact_int(scope["chunk_count"], :chunk_count) == 8 || _fail(:chunk_count, scope["chunk_count"])
    _exact_int(scope["catalog_object_count"], :catalog_count) == 8 || _fail(:catalog_count, scope["catalog_object_count"])
    _exact_int(scope["object_count"], :object_count) == 16 || _fail(:object_count, scope["object_count"])

    origin = profile["origin"]
    origin["capture_not_before_utc"] == "2026-10-29T13:30:00Z" || _fail(:capture_window, "not-before drift")
    origin["capture_deadline_utc"] == "2026-10-30T13:45:00Z" || _fail(:capture_window, "deadline drift")
    origin["origin_timestamp_utc"] == "2026-10-30T14:00:00Z" || _fail(:origin, "origin drift")
    _exact_bool(origin["completion_must_be_strictly_before_origin"], true, :origin_rule)

    release = profile["release"]
    release["scheduled_release_timestamp_utc"] == "2026-10-02T12:30:00Z" || _fail(:release_schedule, "schedule drift")
    _exact_int(release["public_api_documented_lag_days"], :api_lag) == 1 || _fail(:api_lag, "must be one day")
    _exact_bool(release["release_event_separate_from_final_capture_window"], true, :release_separation)
    _exact_bool(release["single_release_time_api_capture_sufficient"], false, :release_separation)

    routes = profile["routes"]
    routes["planned_api_url"] == "https://api.bls.gov/publicAPI/v2/timeseries/data/" || _fail(:api_route, routes["planned_api_url"])
    routes["planned_catalog_base_url"] == "https://download.bls.gov/pub/time.series/ln/" || _fail(:catalog_route, routes["planned_catalog_base_url"])
    routes["api_method"] == "POST" || _fail(:api_method, routes["api_method"])
    routes["api_media_type"] == "application/json" || _fail(:api_media_type, routes["api_media_type"])
    routes["catalog_media_type"] == "text/plain" || _fail(:catalog_media_type, routes["catalog_media_type"])
    routes["injected_object_url_provenance"] == "UNAUTHENTICATED_NOT_CLAIMED" || _fail(:url_provenance, routes["injected_object_url_provenance"])
    _exact_bool(routes["api_registration_key_present"], false, :registration_key)

    profiles = profile["profiles"]
    length(profiles) == 6 || _fail(:profile_count, length(profiles))
    expected_profile_ids = ["cps_employed", "cps_inactive", "cps_labor_force", "cps_population", "cps_unemployed", "cps_unemployment_rate"]
    expected_series_ids = ["LNU02000000", "LNU05000000", "LNU01000000", "LNU00000000", "LNU03000000", "LNS14000000"]
    [entry["profile_id"] for entry in profiles] == expected_profile_ids || _fail(:profile_order, "profile order drift")
    [entry["series_id"] for entry in profiles] == expected_series_ids || _fail(:series_order, "series order drift")
    for (index, entry) in enumerate(profiles)
        entry["selector"] == (
            index == 6 ?
                "BLS:CPS:SeriesID=LNS14000000:Frequency=M:SA=true:history_as_known_at_receipt_through=2026-09:seasonal_factor_vintage_as_known_at_receipt=true:historical_first_states_not_claimed=true" :
                "BLS:CPS:SeriesID=$(entry["series_id"]):Frequency=M:NSA=true:history_as_known_at_receipt_through=2026-09:historical_first_states_not_claimed=true"
        ) || _fail(:selector, entry["profile_id"])
        entry["frequency_text"] == "Monthly" || _fail(:frequency, entry["profile_id"])
        expected_seasonal = index == 6 ? "Seasonally Adjusted" : "Not Seasonally Adjusted"
        entry["seasonal_text"] == expected_seasonal || _fail(:seasonal_class, entry["profile_id"])
        expected_unit = index == 6 ? "Percent" : "Number in thousands"
        entry["unit_text"] == expected_unit || _fail(:unit_class, entry["profile_id"])
        expected_begin_year = index == 2 ? 1975 : 1948
        _exact_int(entry["expected_begin_year"], :begin_year) == expected_begin_year || _fail(:begin_year, entry["profile_id"])
        entry["expected_begin_period"] == "M01" || _fail(:begin_period, entry["profile_id"])
    end

    chunks = profile["chunks"]
    expected_ranges = [(1948, 1957), (1958, 1967), (1968, 1977), (1978, 1987), (1988, 1997), (1998, 2007), (2008, 2017), (2018, 2026)]
    length(chunks) == 8 || _fail(:chunk_count, length(chunks))
    for (chunk, (start_year, end_year)) in zip(chunks, expected_ranges)
        _exact_int(chunk["start_year"], :chunk_year) == start_year || _fail(:chunk_range, chunk["object_id"])
        _exact_int(chunk["end_year"], :chunk_year) == end_year || _fail(:chunk_range, chunk["object_id"])
        chunk["object_id"] == "api_$(start_year)_$(end_year)" || _fail(:chunk_id, chunk["object_id"])
        chunk["body"] == _canonical_body(expected_series_ids, start_year, end_year) || _fail(:canonical_post_body, chunk["object_id"])
        occursin("registrationkey", lowercase(chunk["body"])) && _fail(:registration_key, chunk["object_id"])
    end

    catalogs = profile["catalog_objects"]
    expected_catalogs = [
        ("catalog_ln_series", "ln.series", "series_tsv"),
        ("catalog_ln_footnote", "ln.footnote", "lookup_tsv"),
        ("catalog_ln_seasonal", "ln.seasonal", "lookup_tsv"),
        ("catalog_ln_periodicity", "ln.periodicity", "lookup_tsv"),
        ("catalog_ln_lfst", "ln.lfst", "lookup_tsv"),
        ("catalog_ln_ages", "ln.ages", "lookup_tsv"),
        ("catalog_ln_tdat", "ln.tdat", "lookup_tsv"),
        ("catalog_ln_txt", "ln.txt", "bounded_text"),
    ]
    [(entry["object_id"], entry["filename"], entry["kind"]) for entry in catalogs] == expected_catalogs || _fail(:catalog_order, "catalog object order drift")

    profile["limits"] == EXPECTED_LIMITS || _fail(:resource_ceilings, "exact ceilings or rationale drift")
    _exact_int(profile["limits"]["max_ln_series_bytes"], :ln_series_ceiling) > 15_288_538 || _fail(:ln_series_ceiling, "must exceed audited reference size")
    coverage = profile["coverage"]
    _exact_int(coverage["required_terminal_year"], :terminal_year) == 2026 || _fail(:terminal_year, coverage["required_terminal_year"])
    coverage["required_terminal_period"] == "M09" || _fail(:terminal_period, coverage["required_terminal_period"])
    coverage["annual_period"] == "M13" || _fail(:annual_period, coverage["annual_period"])
    coverage["annual_period_policy"] == "REJECT_NOT_REQUIRED_FOR_MONTHLY_PROJECTIONS" || _fail(:annual_period_policy, coverage["annual_period_policy"])
    _exact_bool(coverage["annual_period_kept_separate"], false, :annual_period)
    _exact_bool(coverage["october_2025_missing_required"], true, :october_missing)
    _exact_bool(coverage["no_gap_no_overlap_required"], true, :coverage_rule)

    catalog_contract = profile["catalog_contract"]
    _exact_bool(catalog_contract["future_full_catalog_capture_required"], true, :catalog_contract)
    _exact_bool(catalog_contract["synthetic_fixture_header_is_provider_schema_claim"], false, :catalog_contract)
    _exact_bool(catalog_contract["full_raw_objects_must_be_hashed_before_projection"], true, :catalog_contract)
    _exact_bool(catalog_contract["projection_receipt_self_hash_required"], true, :catalog_contract)
    _exact_bool(catalog_contract["projection_receipt_binds_full_header"], true, :catalog_contract)
    _exact_bool(catalog_contract["projection_receipt_binds_full_raw_hashes"], true, :catalog_contract)
    _exact_bool(catalog_contract["projection_receipt_binds_physical_row_ordinals"], true, :catalog_contract)
    _exact_bool(catalog_contract["irrelevant_rows_must_be_retained_in_full_raw_hash"], true, :catalog_contract)
    _exact_bool(catalog_contract["seven_row_projection_may_be_manifested_as_raw"], false, :catalog_contract)
    catalog_contract["provider_layout_evidence_status"] == "MISSING_NOT_LOCALLY_EVIDENCED" || _fail(:catalog_contract, "provider layout may not be claimed")
    catalog_contract["projection_receipt_schema"] == "beforeit-us-bls-cps-catalog-projection-receipt.v1" || _fail(:catalog_contract, "projection receipt schema drift")
    catalog_contract["synthetic_series_required_columns"] == SERIES_HEADER || _fail(:catalog_contract, "synthetic required columns drift")

    gates = profile["gates"]
    Set(String.(keys(gates))) == Set(
        [
            "origin_admissible", "qualified_leaf", "current_v3_integration",
            "raw_capture_complete", "source_inventory_mutation_allowed",
            "forecast_execution_allowed", "truth_access_allowed", "scoring_allowed",
            "promotion_allowed",
        ]
    ) || _fail(:gates, "gate key drift")
    all(value isa Bool && value === false for value in values(gates)) || _fail(:gates, "every gate must remain false")
    pins = profile["source_pins"]
    actual_pins = [(pin["binding_id"], pin["path"], pin["sha256"]) for pin in pins]
    actual_pins == EXPECTED_SOURCE_PINS || _fail(:source_pins, "exact ordered source pins drift")
    length(unique(first.(actual_pins))) == length(actual_pins) || _fail(:source_pin_duplicate_id, "duplicate binding id")
    length(unique(getindex.(actual_pins, 2))) == length(actual_pins) || _fail(:source_pin_duplicate_path, "duplicate path")
    return nothing
end

function _verify_source_pins!(profile::AbstractDict)
    for pin in profile["source_pins"]
        occursin(HASH_PATTERN, pin["sha256"]) || _fail(:source_pin_hash, pin["binding_id"])
        path = joinpath(REPOSITORY_ROOT, pin["path"])
        isfile(path) || _fail(:source_pin_missing, pin["path"])
        islink(path) && _fail(:source_pin_symlink, pin["path"])
        stat(path).nlink == 1 || _fail(:source_pin_hardlink, pin["path"])
        bytes2hex(sha256(read(path))) == pin["sha256"] || _fail(:source_pin_mismatch, pin["binding_id"])
    end
    return nothing
end

function _validate_profile_with_source_verifier(path::AbstractString, source_verifier::Function)
    normpath(abspath(path)) == PROFILE_PATH || _fail(:profile_path, "only the adjacent checked-in profile path is accepted")
    islink(path) && _fail(:profile_path, "profile symlink rejected")
    profile = TOML.parsefile(path)
    if EXPECTED_PROFILE_PHYSICAL_SHA256 != "TO_BE_FROZEN"
        bytes2hex(sha256(read(path))) == EXPECTED_PROFILE_PHYSICAL_SHA256 || _fail(:profile_physical_hash, "checked-in profile bytes changed")
    end
    _validate_profile_document_unit(profile)
    source_verifier(profile)
    return profile
end

validate_profile(path::AbstractString = PROFILE_PATH) =
    _validate_profile_with_source_verifier(path, _verify_source_pins!)

mutable struct JSONState
    bytes::Vector{UInt8}
    position::Int
    depth::Int
    nodes::Int
    max_depth::Int
    max_nodes::Int
    max_string_bytes::Int
end

function _json_fail(detail)
    return _fail(:json_invalid, detail)
end

function _skip_ws!(state::JSONState)
    while state.position <= length(state.bytes) && state.bytes[state.position] in (0x20, 0x09, 0x0a, 0x0d)
        state.position += 1
    end
    return
end

function _hex_value(byte::UInt8)
    0x30 <= byte <= 0x39 && return Int(byte - 0x30)
    0x41 <= byte <= 0x46 && return Int(byte - 0x41 + 10)
    0x61 <= byte <= 0x66 && return Int(byte - 0x61 + 10)
    return _json_fail("invalid unicode escape")
end

function _unicode_escape!(state::JSONState)
    state.position + 3 <= length(state.bytes) || _json_fail("truncated unicode escape")
    value = 0
    for _ in 1:4
        value = 16 * value + _hex_value(state.bytes[state.position])
        state.position += 1
    end
    if 0xd800 <= value <= 0xdbff
        state.position + 5 <= length(state.bytes) || _json_fail("truncated surrogate pair")
        state.bytes[state.position] == 0x5c && state.bytes[state.position + 1] == 0x75 || _json_fail("missing low surrogate")
        state.position += 2
        low = 0
        for _ in 1:4
            low = 16 * low + _hex_value(state.bytes[state.position])
            state.position += 1
        end
        0xdc00 <= low <= 0xdfff || _json_fail("invalid low surrogate")
        return 0x00010000 + ((value - 0xd800) << 10) + low - 0xdc00
    elseif 0xdc00 <= value <= 0xdfff
        _json_fail("unpaired low surrogate")
    end
    return value
end

function _parse_string!(state::JSONState)
    state.bytes[state.position] == 0x22 || _json_fail("expected string")
    state.position += 1
    io = IOBuffer()
    while state.position <= length(state.bytes)
        byte = state.bytes[state.position]
        state.position += 1
        if byte == 0x22
            data = take!(io)
            length(data) <= state.max_string_bytes || _fail(:json_string_limit, length(data))
            isvalid(String, data) || _fail(:json_invalid_utf8, "invalid UTF-8 in decoded string")
            return String(data)
        elseif byte == 0x5c
            state.position <= length(state.bytes) || _json_fail("truncated escape")
            escaped = state.bytes[state.position]
            state.position += 1
            if escaped == 0x75
                write(io, Char(_unicode_escape!(state)))
            else
                mapping = Dict(0x22 => 0x22, 0x5c => 0x5c, 0x2f => 0x2f, 0x62 => 0x08, 0x66 => 0x0c, 0x6e => 0x0a, 0x72 => 0x0d, 0x74 => 0x09)
                haskey(mapping, escaped) || _json_fail("invalid escape")
                write(io, mapping[escaped])
            end
        elseif byte < 0x20
            _json_fail("unescaped control character")
        else
            write(io, byte)
        end
    end
    return _json_fail("unterminated string")
end

function _parse_number!(state::JSONState)
    start = state.position
    bytes = state.bytes
    state.position <= length(bytes) && bytes[state.position] == 0x2d && (state.position += 1)
    state.position <= length(bytes) || _json_fail("truncated number")
    if bytes[state.position] == 0x30
        state.position += 1
        state.position <= length(bytes) && 0x30 <= bytes[state.position] <= 0x39 && _json_fail("leading zero")
    elseif 0x31 <= bytes[state.position] <= 0x39
        while state.position <= length(bytes) && 0x30 <= bytes[state.position] <= 0x39
            state.position += 1
        end
    else
        _json_fail("invalid number")
    end
    floating = false
    if state.position <= length(bytes) && bytes[state.position] == 0x2e
        floating = true
        state.position += 1
        state.position <= length(bytes) && 0x30 <= bytes[state.position] <= 0x39 || _json_fail("invalid fraction")
        while state.position <= length(bytes) && 0x30 <= bytes[state.position] <= 0x39
            state.position += 1
        end
    end
    if state.position <= length(bytes) && bytes[state.position] in (0x65, 0x45)
        floating = true
        state.position += 1
        state.position <= length(bytes) && bytes[state.position] in (0x2b, 0x2d) && (state.position += 1)
        state.position <= length(bytes) && 0x30 <= bytes[state.position] <= 0x39 || _json_fail("invalid exponent")
        while state.position <= length(bytes) && 0x30 <= bytes[state.position] <= 0x39
            state.position += 1
        end
    end
    token = String(bytes[start:(state.position - 1)])
    if floating
        value = tryparse(Float64, token)
        value !== nothing && isfinite(value) || _json_fail("unrepresentable number")
        return value
    end
    value = tryparse(Int, token)
    value === nothing && _json_fail("integer outside Int range")
    return value
end

function _parse_value!(state::JSONState)
    state.nodes += 1
    state.nodes <= state.max_nodes || _fail(:json_node_limit, state.nodes)
    _skip_ws!(state)
    state.position <= length(state.bytes) || _json_fail("unexpected end")
    byte = state.bytes[state.position]
    if byte == 0x22
        return _parse_string!(state)
    elseif byte == 0x7b
        state.depth += 1
        state.depth <= state.max_depth || _fail(:json_depth_limit, state.depth)
        state.position += 1
        object = Dict{String, Any}()
        _skip_ws!(state)
        if state.position <= length(state.bytes) && state.bytes[state.position] == 0x7d
            state.position += 1
            state.depth -= 1
            return object
        end
        while true
            _skip_ws!(state)
            state.position <= length(state.bytes) && state.bytes[state.position] == 0x22 || _json_fail("object key must be string")
            key = _parse_string!(state)
            haskey(object, key) && _fail(:json_duplicate_member, key)
            _skip_ws!(state)
            state.position <= length(state.bytes) && state.bytes[state.position] == 0x3a || _json_fail("missing colon")
            state.position += 1
            object[key] = _parse_value!(state)
            _skip_ws!(state)
            state.position <= length(state.bytes) || _json_fail("unterminated object")
            delimiter = state.bytes[state.position]
            state.position += 1
            delimiter == 0x7d && break
            delimiter == 0x2c || _json_fail("object delimiter")
        end
        state.depth -= 1
        return object
    elseif byte == 0x5b
        state.depth += 1
        state.depth <= state.max_depth || _fail(:json_depth_limit, state.depth)
        state.position += 1
        array = Any[]
        _skip_ws!(state)
        if state.position <= length(state.bytes) && state.bytes[state.position] == 0x5d
            state.position += 1
            state.depth -= 1
            return array
        end
        while true
            push!(array, _parse_value!(state))
            _skip_ws!(state)
            state.position <= length(state.bytes) || _json_fail("unterminated array")
            delimiter = state.bytes[state.position]
            state.position += 1
            delimiter == 0x5d && break
            delimiter == 0x2c || _json_fail("array delimiter")
        end
        state.depth -= 1
        return array
    elseif byte == 0x74 && state.position + 3 <= length(state.bytes) && state.bytes[state.position:(state.position + 3)] == codeunits("true")
        state.position += 4
        return true
    elseif byte == 0x66 && state.position + 4 <= length(state.bytes) && state.bytes[state.position:(state.position + 4)] == codeunits("false")
        state.position += 5
        return false
    elseif byte == 0x6e && state.position + 3 <= length(state.bytes) && state.bytes[state.position:(state.position + 3)] == codeunits("null")
        state.position += 4
        return nothing
    elseif byte == 0x2d || 0x30 <= byte <= 0x39
        return _parse_number!(state)
    end
    return _json_fail("unexpected token")
end

function parse_json_strict(bytes::AbstractVector{UInt8}; max_bytes::Int = 8_388_608, max_depth::Int = 64, max_nodes::Int = 250_000, max_string_bytes::Int = 1_048_576)
    length(bytes) <= max_bytes || _fail(:json_size_limit, length(bytes))
    isvalid(String, bytes) || _fail(:json_invalid_utf8, "input is not valid UTF-8")
    state = JSONState(Vector{UInt8}(bytes), 1, 0, 0, max_depth, max_nodes, max_string_bytes)
    value = _parse_value!(state)
    _skip_ws!(state)
    state.position == length(state.bytes) + 1 || _json_fail("trailing bytes")
    return value
end

function parse_tsv_strict(bytes::AbstractVector{UInt8}; max_bytes::Int = 16_777_216, max_lines::Int = 500_000, max_columns::Int = 64, max_field_bytes::Int = 1_048_576)
    length(bytes) <= max_bytes || _fail(:tsv_size_limit, length(bytes))
    any(byte -> byte in (0x00, 0x0d), bytes) && _fail(:tsv_malformed, "NUL and CR are forbidden")
    isvalid(String, bytes) || _fail(:tsv_invalid_utf8, "input is not valid UTF-8")
    text = String(Vector{UInt8}(bytes))
    lines = split(text, '\n'; keepempty = true)
    !isempty(lines) && isempty(last(lines)) && pop!(lines)
    isempty(lines) && _fail(:tsv_malformed, "empty TSV")
    length(lines) <= max_lines || _fail(:tsv_line_limit, length(lines))
    rows = Vector{Vector{String}}()
    for line in lines
        isempty(line) && _fail(:tsv_malformed, "blank line")
        fields = String.(split(line, '\t'; keepempty = true))
        length(fields) <= max_columns || _fail(:tsv_column_limit, length(fields))
        any(field -> ncodeunits(field) > max_field_bytes, fields) && _fail(:tsv_field_limit, "field too large")
        push!(rows, fields)
    end
    width = length(first(rows))
    width > 0 || _fail(:tsv_malformed, "zero-width TSV")
    all(length(row) == width for row in rows) || _fail(:tsv_malformed, "ragged TSV")
    length(unique(first(rows))) == width || _fail(:tsv_duplicate_header, "duplicate header")
    return rows
end

function _bounded_text(bytes, limits)
    length(bytes) <= limits["max_lookup_tsv_bytes"] || _fail(:text_size_limit, length(bytes))
    any(byte -> byte in (0x00, 0x0d), bytes) && _fail(:text_malformed, "NUL and CR are forbidden")
    isvalid(String, bytes) || _fail(:text_invalid_utf8, "input is not valid UTF-8")
    text = String(Vector{UInt8}(bytes))
    isempty(strip(text)) && _fail(:text_malformed, "empty text")
    length(split(text, '\n'; keepempty = true)) <= limits["max_text_lines"] || _fail(:text_line_limit, "too many lines")
    return text
end

function _parse_lookup(object_id, bytes, limits)
    code_header, text_header = LOOKUP_SPECS[object_id]
    rows = parse_tsv_strict(
        bytes;
        max_bytes = limits["max_lookup_tsv_bytes"],
        max_lines = limits["max_tsv_lines"],
        max_columns = limits["max_tsv_columns"],
        max_field_bytes = limits["max_tsv_field_bytes"],
    )
    header = first(rows)
    code_positions = findall(==(code_header), header)
    text_positions = findall(==(text_header), header)
    length(code_positions) == 1 && length(text_positions) == 1 || _fail(:catalog_header, object_id)
    code_index = only(code_positions)
    text_index = only(text_positions)
    lookup = Dict{String, String}()
    ordinals = Dict{String, Int}()
    for (index, row) in enumerate(rows[2:end])
        ordinal = index + 1
        code = row[code_index]
        text = row[text_index]
        isempty(code) && _fail(:catalog_blank_field, object_id)
        isempty(text) && _fail(:catalog_blank_field, object_id)
        haskey(lookup, code) && _fail(:catalog_duplicate_code, "$(object_id):$(code)")
        lookup[code] = text
        ordinals[code] = ordinal
    end
    isempty(lookup) && _fail(:catalog_empty, object_id)
    return (lookup = lookup, ordinals = ordinals, header = header, row_count = length(rows) - 1)
end

function _catalog_metadata(profile, objects)
    limits = profile["limits"]
    rows = parse_tsv_strict(
        objects["catalog_ln_series"];
        max_bytes = limits["max_ln_series_bytes"], max_lines = limits["max_tsv_lines"],
        max_columns = limits["max_tsv_columns"], max_field_bytes = limits["max_tsv_field_bytes"]
    )
    header = first(rows)
    column_indices = Dict{String, Int}()
    for required in SERIES_HEADER
        positions = findall(==(required), header)
        length(positions) == 1 || _fail(:catalog_header, "catalog_ln_series missing or duplicate $(required)")
        column_indices[required] = only(positions)
    end
    length(rows) > 7 || _fail(:catalog_full_object_required, "a seven-row selected projection cannot stand in for full raw ln.series")
    lookups = Dict(id => _parse_lookup(id, objects[id], limits) for id in keys(LOOKUP_SPECS))
    footnote = lookups["catalog_ln_footnote"].lookup
    coverage = profile["coverage"]
    get(footnote, coverage["october_2025_missing_footnote_code"], nothing) == coverage["october_2025_missing_footnote_text"] || _fail(:footnote_catalog_drift, "October 2025 footnote")
    _bounded_text(objects["catalog_ln_txt"], limits)

    metadata = Dict{String, Dict{String, Any}}()
    expected_ids = [entry["series_id"] for entry in profile["profiles"]]
    selected_rows = Dict{String, Tuple{Int, Vector{String}}}()
    seen_series_ids = Set{String}()
    for (index, row) in enumerate(rows[2:end])
        ordinal = index + 1
        series_id = row[column_indices["series_id"]]
        isempty(series_id) && _fail(:catalog_blank_field, "catalog_ln_series series_id")
        series_id in seen_series_ids && _fail(:catalog_duplicate_series, series_id)
        push!(seen_series_ids, series_id)
        series_id in expected_ids || continue
        selected_rows[series_id] = (ordinal, row)
    end
    Set(keys(selected_rows)) == Set(expected_ids) || _fail(:catalog_series_count, "exact six selected series required")
    length(rows) - 1 - length(selected_rows) > 0 || _fail(:catalog_irrelevant_rows, "full-object candidate must retain irrelevant rows")

    selected_receipt_rows = Vector{Dict{String, Any}}()
    for expected in profile["profiles"]
        ordinal, row = selected_rows[expected["series_id"]]
        record = Dict(required => row[column_indices[required]] for required in SERIES_HEADER)
        begin_year = tryparse(Int, record["begin_year"])
        end_year = tryparse(Int, record["end_year"])
        begin_year !== nothing && end_year !== nothing || _fail(:catalog_year, record["series_id"])
        begin_year == expected["expected_begin_year"] || _fail(:catalog_begin_drift, record["series_id"])
        record["begin_period"] == expected["expected_begin_period"] || _fail(:catalog_begin_drift, record["series_id"])
        end_year == coverage["required_terminal_year"] && record["end_period"] == coverage["required_terminal_period"] || _fail(:catalog_terminal_drift, record["series_id"])
        record["series_title"] == expected["series_title"] || _fail(:catalog_title_drift, record["series_id"])
        get(lookups["catalog_ln_seasonal"].lookup, record["seasonal_code"], nothing) == expected["seasonal_text"] || _fail(:catalog_seasonal_drift, record["series_id"])
        get(lookups["catalog_ln_periodicity"].lookup, record["periodicity_code"], nothing) == expected["frequency_text"] || _fail(:catalog_frequency_drift, record["series_id"])
        get(lookups["catalog_ln_tdat"].lookup, record["tdat_code"], nothing) == expected["unit_text"] || _fail(:catalog_unit_drift, record["series_id"])
        get(lookups["catalog_ln_lfst"].lookup, record["lfst_code"], nothing) == expected["labor_force_status_text"] || _fail(:catalog_lfst_drift, record["series_id"])
        get(lookups["catalog_ln_ages"].lookup, record["ages_code"], nothing) == expected["ages_text"] || _fail(:catalog_ages_drift, record["series_id"])
        metadata[record["series_id"]] = Dict(
            "begin_year" => begin_year,
            "begin_period" => record["begin_period"],
            "end_year" => end_year,
            "end_period" => record["end_period"],
            "series_title" => record["series_title"],
            "seasonal_text" => expected["seasonal_text"],
            "unit_text" => expected["unit_text"],
            "frequency_text" => expected["frequency_text"],
            "physical_row_ordinal" => ordinal,
        )
        lookup_bindings = Dict{String, Any}()
        for (lookup_id, field) in (
                ("catalog_ln_seasonal", "seasonal_code"),
                ("catalog_ln_periodicity", "periodicity_code"),
                ("catalog_ln_tdat", "tdat_code"),
                ("catalog_ln_lfst", "lfst_code"),
                ("catalog_ln_ages", "ages_code"),
            )
            code = record[field]
            lookup_bindings[lookup_id] = Dict(
                "code" => code,
                "physical_row_ordinal" => lookups[lookup_id].ordinals[code],
            )
        end
        push!(
            selected_receipt_rows, Dict(
                "profile_id" => expected["profile_id"],
                "series_id" => record["series_id"],
                "physical_row_ordinal" => ordinal,
                "decoded_tab_row_sha256" => bytes2hex(sha256(codeunits(join(row, '\t')))),
                "selected_fields" => record,
                "lookup_bindings" => lookup_bindings,
            )
        )
    end

    catalog_ids = [entry["object_id"] for entry in profile["catalog_objects"]]
    raw_bindings = [
        Dict(
                "catalog_ordinal" => ordinal,
                "object_set_ordinal" => ordinal + 8,
                "object_id" => object_id,
                "full_raw_sha256" => bytes2hex(sha256(objects[object_id])),
                "full_raw_byte_count" => length(objects[object_id]),
            ) for (ordinal, object_id) in enumerate(catalog_ids)
    ]
    receipt = Dict{String, Any}(
        "artifact" => Dict(
            "schema_version" => profile["catalog_contract"]["projection_receipt_schema"],
            "content_sha256" => repeat("0", 64),
            "status" => "CANNOT_RUN_UNVERIFIED_PROVIDER_LAYOUT",
        ),
        "provider_layout_evidenced" => false,
        "operational" => false,
        "full_provider_object_completeness_proven" => false,
        "raw_catalog_bindings" => raw_bindings,
        "ln_series_full_header" => header,
        "ln_series_decoded_header_sha256" => bytes2hex(sha256(codeunits(join(header, '\t')))),
        "ln_series_physical_data_row_count" => length(rows) - 1,
        "ln_series_irrelevant_row_count" => length(rows) - 1 - length(selected_rows),
        "lookup_full_headers" => Dict(id => lookups[id].header for id in sort!(collect(keys(lookups)))),
        "october_2025_missing_footnote_binding" => Dict(
            "object_id" => "catalog_ln_footnote",
            "code" => coverage["october_2025_missing_footnote_code"],
            "text" => coverage["october_2025_missing_footnote_text"],
            "physical_row_ordinal" => lookups["catalog_ln_footnote"].ordinals[coverage["october_2025_missing_footnote_code"]],
        ),
        "selected_series_rows" => selected_receipt_rows,
    )
    receipt["artifact"]["content_sha256"] = _canonical_sha256(receipt; exclude_artifact_hash = true)
    return metadata, receipt
end

function _footnotes(value, coverage)
    value isa AbstractVector || _fail(:footnotes_shape, "footnotes must be an array")
    output = Vector{Dict{String, String}}()
    for footnote in value
        _expect_exact_keys(footnote, ["code", "text"], :footnote_shape)
        footnote["code"] isa String && footnote["text"] isa String || _fail(:footnote_type, "code and text must be strings")
        push!(output, Dict("code" => footnote["code"], "text" => footnote["text"]))
    end
    return output
end

function _record_key(year::Int, period::String)
    return string(year) * "-" * period
end

function _validate_chunk!(profile, chunk, bytes, monthly)
    limits = profile["limits"]
    root = parse_json_strict(
        bytes;
        max_bytes = limits["max_json_bytes"], max_depth = limits["max_json_depth"],
        max_nodes = limits["max_json_nodes"], max_string_bytes = limits["max_json_string_bytes"]
    )
    _expect_exact_keys(root, ["status", "responseTime", "message", "Results"], :api_root_shape)
    root["status"] == "REQUEST_SUCCEEDED" || _fail(:api_status, chunk["object_id"])
    _exact_int(root["responseTime"], :api_response_time)
    root["message"] isa AbstractVector && isempty(root["message"]) || _fail(:api_message, chunk["object_id"])
    results = _expect_exact_keys(root["Results"], ["series"], :api_results_shape)
    series = results["series"]
    series isa AbstractVector || _fail(:api_series_shape, chunk["object_id"])
    length(series) == 6 || _fail(:api_series_count, chunk["object_id"])
    expected_ids = [entry["series_id"] for entry in profile["profiles"]]
    actual_ids = String[]
    for entry in series
        _expect_exact_keys(entry, ["seriesID", "data"], :api_series_object_shape)
        entry["seriesID"] isa String || _fail(:api_series_id_type, chunk["object_id"])
        push!(actual_ids, entry["seriesID"])
    end
    actual_ids == expected_ids || _fail(:api_series_order, chunk["object_id"])
    length(unique(actual_ids)) == 6 || _fail(:api_duplicate_series, chunk["object_id"])

    coverage = profile["coverage"]
    for entry in series
        series_id = entry["seriesID"]
        data = entry["data"]
        data isa AbstractVector || _fail(:api_data_shape, series_id)
        last_sort_key = nothing
        for record in data
            keys_allowed = Set(["year", "period", "periodName", "value", "footnotes", "latest"])
            record isa AbstractDict || _fail(:api_record_shape, series_id)
            actual_keys = Set(String.(keys(record)))
            Set(["year", "period", "periodName", "value", "footnotes"]) ⊆ actual_keys || _fail(:api_record_shape, series_id)
            actual_keys ⊆ keys_allowed || _fail(:api_record_shape, series_id)
            haskey(record, "latest") && !(record["latest"] in ("true", "false")) && _fail(:api_latest, series_id)
            record["year"] isa String && occursin(r"^\d{4}$", record["year"]) || _fail(:api_year_grammar, series_id)
            year = parse(Int, record["year"])
            chunk["start_year"] <= year <= chunk["end_year"] || _fail(:api_wrong_chunk, _record_key(year, record["period"]))
            period = record["period"]
            period isa String && (period in MONTH_PERIODS || period == "M13") || _fail(:api_period_grammar, series_id)
            period == "M13" && _fail(:api_m13_forbidden, "M13 is outside the six monthly projections")
            record["periodName"] == PERIOD_NAMES[period] || _fail(:api_period_name, _record_key(year, period))
            value = record["value"]
            value isa String || _fail(:api_value_type, _record_key(year, period))
            value == coverage["explicit_missing_token"] || occursin(r"^-?(?:0|[1-9]\d*)(?:\.\d+)?$", value) || _fail(:api_value_grammar, _record_key(year, period))
            footnotes = _footnotes(record["footnotes"], coverage)
            sort_key = (year, parse(Int, period[2:3]))
            last_sort_key === nothing || sort_key < last_sort_key || _fail(:api_period_order, "$(series_id):$(_record_key(year, period))")
            last_sort_key = sort_key
            key = _record_key(year, period)
            haskey(monthly[series_id], key) && _fail(:api_duplicate_period, "$(series_id):$(key)")
            monthly[series_id][key] = Dict("year" => year, "period" => period, "value" => value, "footnotes" => footnotes)
        end
    end
    return nothing
end

function _expected_month_keys(begin_year::Int, end_year::Int, end_period::String)
    output = String[]
    terminal_month = parse(Int, end_period[2:3])
    for year in begin_year:end_year
        last_month = year == end_year ? terminal_month : 12
        for month in 1:last_month
            push!(output, _record_key(year, "M" * lpad(string(month), 2, '0')))
        end
    end
    return output
end

function _manifest(profile, objects)
    output = Vector{Dict{String, Any}}()
    ordinal = 0
    for chunk in profile["chunks"]
        ordinal += 1
        bytes = objects[chunk["object_id"]]
        push!(
            output, Dict(
                "ordinal" => ordinal,
                "object_id" => chunk["object_id"],
                "role" => "INJECTED_API_CHUNK_RESPONSE_CANDIDATE",
                "planned_url" => profile["routes"]["planned_api_url"],
                "planned_url_bytes_claimed" => false,
                "evidence_class" => "INJECTED_UNAUTHENTICATED_BYTES",
                "media_type" => profile["routes"]["api_media_type"],
                "request_body" => chunk["body"],
                "request_body_sha256" => bytes2hex(sha256(codeunits(chunk["body"]))),
                "raw_sha256" => bytes2hex(sha256(bytes)),
                "byte_count" => length(bytes),
            )
        )
    end
    for catalog in profile["catalog_objects"]
        ordinal += 1
        bytes = objects[catalog["object_id"]]
        push!(
            output, Dict(
                "ordinal" => ordinal,
                "object_id" => catalog["object_id"],
                "role" => "INJECTED_FULL_CATALOG_OR_LOOKUP_CANDIDATE",
                "planned_url" => profile["routes"]["planned_catalog_base_url"] * catalog["filename"],
                "planned_url_bytes_claimed" => false,
                "full_provider_object_completeness_proven" => false,
                "evidence_class" => "INJECTED_UNAUTHENTICATED_BYTES",
                "media_type" => profile["routes"]["catalog_media_type"],
                "raw_sha256" => bytes2hex(sha256(bytes)),
                "byte_count" => length(bytes),
            )
        )
    end
    return output
end

function validate_capture_set(objects::AbstractDict; profile_path::AbstractString = PROFILE_PATH)
    profile = validate_profile(profile_path)
    expected_ids = vcat([chunk["object_id"] for chunk in profile["chunks"]], [catalog["object_id"] for catalog in profile["catalog_objects"]])
    length(objects) == 16 || _fail(:object_set_cardinality, "exactly 16 objects required")
    all(typeof(key) === String for key in keys(objects)) || _fail(:object_key_type, "every object key must be a concrete String")
    Set(keys(objects)) == Set(expected_ids) || _fail(:object_set, "exact 8+8 object membership required")
    all(typeof(objects[id]) === Vector{UInt8} for id in expected_ids) || _fail(:object_bytes_type, "all objects must be concrete Vector{UInt8}")

    metadata, projection_receipt = _catalog_metadata(profile, objects)
    series_ids = [entry["series_id"] for entry in profile["profiles"]]
    monthly = Dict(id => Dict{String, Dict{String, Any}}() for id in series_ids)
    for chunk in profile["chunks"]
        _validate_chunk!(profile, chunk, objects[chunk["object_id"]], monthly)
    end

    projections = Vector{Dict{String, Any}}()
    coverage = profile["coverage"]
    for expected in profile["profiles"]
        id = expected["series_id"]
        meta = metadata[id]
        required = _expected_month_keys(meta["begin_year"], meta["end_year"], meta["end_period"])
        Set(keys(monthly[id])) == Set(required) || _fail(:monthly_coverage, "$(id): expected $(length(required)), got $(length(monthly[id]))")
        october = monthly[id][coverage["october_2025_period"]]
        october["value"] == coverage["explicit_missing_token"] || _fail(:october_2025_not_missing, id)
        october["footnotes"] == [Dict("code" => coverage["october_2025_missing_footnote_code"], "text" => coverage["october_2025_missing_footnote_text"])] || _fail(:october_2025_footnote, id)
        missing_count = count(record -> record["value"] == coverage["explicit_missing_token"], values(monthly[id]))
        projection = Dict{String, Any}(
            "profile_id" => expected["profile_id"],
            "series_id" => id,
            "selector" => expected["selector"],
            "provider_begin" => _record_key(meta["begin_year"], meta["begin_period"]),
            "provider_end" => _record_key(meta["end_year"], meta["end_period"]),
            "seasonal_text" => meta["seasonal_text"],
            "unit_text" => meta["unit_text"],
            "frequency_text" => meta["frequency_text"],
            "catalog_series_physical_row_ordinal" => meta["physical_row_ordinal"],
            "catalog_projection_receipt_sha256" => projection_receipt["artifact"]["content_sha256"],
            "monthly_observation_count" => length(monthly[id]),
            "explicit_missing_count" => missing_count,
            "annual_m13_count" => 0,
            "annual_m13_policy" => "REJECT_NOT_REQUIRED_FOR_MONTHLY_PROJECTIONS",
            "accounting_identity_role" => "DIAGNOSTIC_ONLY_NOT_A_VALIDATION_GATE",
            "monthly_projection_sha256" => _canonical_sha256(Dict(key => monthly[id][key] for key in sort!(collect(keys(monthly[id]))))),
        )
        push!(projections, projection)
    end

    result = Dict{String, Any}(
        "artifact" => Dict(
            "schema_version" => "beforeit-us-bls-cps-offline-validation-result.audit-repaired.v2",
            "content_sha256" => repeat("0", 64),
            "status" => "CANNOT_RUN",
            "claim_ceiling" => "SYNTHETIC_OFFLINE_VALIDATION_ONLY_NO_CAPTURE_OR_AVAILABILITY_CLAIM",
        ),
        "profile_physical_sha256" => bytes2hex(sha256(read(profile_path))),
        "profile_semantic_sha256" => profile["artifact"]["content_sha256"],
        "capture_id" => "final_structural_pre_origin",
        "object_order" => expected_ids,
        "object_set_manifest" => _manifest(profile, objects),
        "catalog_projection_receipt" => projection_receipt,
        "profile_projections" => projections,
        "validation" => Dict(
            "object_count" => 16,
            "api_chunk_count" => 8,
            "catalog_object_count" => 8,
            "profile_projection_count" => 6,
            "network_action_count" => 0,
            "filesystem_write_action_count" => 0,
            "actual_bls_bytes_claimed" => false,
            "availability_claimed" => false,
            "atomicity_claimed" => false,
            "first_public_history_claimed" => false,
            "publisher_authentication_claimed" => false,
            "injected_bytes_are_planned_url_bytes" => false,
            "full_provider_catalog_completeness_proven" => false,
            "provider_catalog_layout_evidenced" => false,
            "catalog_projection_operational" => false,
            "current_v3_integration" => false,
            "v3_gap" => "NO_SET_VALUED_RAW_OBJECT_MEDIA_OR_CATALOG_TRUST_BRANCH",
        ),
        "gates" => deepcopy(profile["gates"]),
    )
    result["artifact"]["content_sha256"] = _canonical_sha256(result; exclude_artifact_hash = true)
    return result
end

function validate_compiled_result(result::AbstractDict, objects::AbstractDict; profile_path::AbstractString = PROFILE_PATH)
    expected = validate_capture_set(objects; profile_path)
    result == expected || _fail(:result_replay_mismatch, "result must exactly replay from profile and object bytes")
    _canonical_sha256(result; exclude_artifact_hash = true) == result["artifact"]["content_sha256"] || _fail(:result_semantic_hash, "result self-hash mismatch")
    receipt = result["catalog_projection_receipt"]
    _canonical_sha256(receipt; exclude_artifact_hash = true) == receipt["artifact"]["content_sha256"] || _fail(:projection_receipt_semantic_hash, "projection receipt self-hash mismatch")
    result["artifact"]["status"] == "CANNOT_RUN" || _fail(:result_status, result["artifact"]["status"])
    [entry["ordinal"] for entry in result["object_set_manifest"]] == collect(1:16) || _fail(:result_object_order, "manifest ordinals drift")
    result["object_order"] == [entry["object_id"] for entry in result["object_set_manifest"]] || _fail(:result_object_order, "order vector and manifest disagree")
    all(entry["planned_url_bytes_claimed"] === false for entry in result["object_set_manifest"]) || _fail(:result_url_provenance, "injected bytes cannot be attributed to planned URLs")
    all(value isa Bool && value === false for value in values(result["gates"])) || _fail(:result_gates, "all gates must remain false")
    return result
end

end
