module USPipeline

using CSV
using DataFrames
using Dates
using DuckDB
using HTTP
using JLD2
using JSON
using LinearAlgebra
using Random
using SHA
using Statistics
using TOML

import BeforeIT as Bit

const SCRIPT_DIR = @__DIR__
include(
    joinpath(
        SCRIPT_DIR,
        "accounting",
        "USSupplyMakeDiagnostics.jl",
    ),
)
using .USSupplyMakeDiagnostics
include(
    joinpath(
        SCRIPT_DIR,
        "accounting",
        "USSymmetricSupplyUse.jl",
    ),
)
using .USSymmetricSupplyUse
include(
    joinpath(
        SCRIPT_DIR,
        "accounting",
        "USRequirementsDiagnostics.jl",
    ),
)
using .USRequirementsDiagnostics

const REPO_ROOT = normpath(joinpath(SCRIPT_DIR, "..", ".."))
const DATA_ROOT = joinpath(REPO_ROOT, "data", "us")
const RAW_ROOT = joinpath(DATA_ROOT, "raw")
const CURATED_ROOT = joinpath(DATA_ROOT, "curated")
const VALIDATION_ROOT = joinpath(DATA_ROOT, "validation")
const BASELINE_ROOT = joinpath(DATA_ROOT, "baselines")
const CALIBRATION_ROOT = joinpath(DATA_ROOT, "calibration")
const REQUIREMENTS_FIXTURE_ROOT =
    joinpath(
    SCRIPT_DIR,
    "accounting",
    "fixtures",
    "bea_2024_requirements_approved",
)
const OFFICIAL_DIRECT_REQUIREMENTS_FIXTURE_ROOT =
    joinpath(
    SCRIPT_DIR,
    "accounting",
    "fixtures",
    "bea_2024_official_direct_requirements_approved",
)
const DATABASE_PATH = joinpath(DATA_ROOT, "db", "us_calibration.duckdb")
const SOURCE_FILE = joinpath(SCRIPT_DIR, "sources.toml")
const MAPPING_FILE = joinpath(SCRIPT_DIR, "bea71.toml")
const SOURCE_SPEC = TOML.parsefile(SOURCE_FILE)
const STRUCTURAL_YEAR = Int(SOURCE_SPEC["pipeline"]["structural_year"])
const DATA_TRUTH_VINTAGE =
    Date(String(SOURCE_SPEC["pipeline"]["data_truth_vintage"]))
const ECONOMIC_OUTLOOK_ACTUAL_START =
    Date(String(SOURCE_SPEC["pipeline"]["economic_outlook_actual_start"]))
const ECONOMIC_OUTLOOK_ACTUAL_END =
    Date(String(SOURCE_SPEC["pipeline"]["economic_outlook_actual_end"]))
const VALID_STATUSES = Set(["APPROVED", "DUBIOUS", "REJECTED", "MISSING"])
const RUN_SEED = 20260802
const OPENING_MACRO_CONTROL_SOURCE =
    "BEA_NIPA_T10105_CURRENT_DOLLAR_SAAR_DIVIDED_BY_4"
const OPENING_MACRO_CONTROL_TOLERANCE = 1.0
const MODEL_ACCOUNTING_TOLERANCE = 1.0e-6
const VALUATION_BRIDGE_SCIENTIFIC_STATUS =
    "REJECTED_NOT_CELL_IDENTIFIED"
const VALUATION_BRIDGE_RUNTIME_STATUS =
    "LEGACY_RESEARCH_PATH_STILL_APPLIED_PENDING_PRODUCER_PRICE_ADAPTER"

export collect!, build!, validate!, smoke!, run_all!, status!, main

mutable struct RunState
    env::Dict{String, String}
    acquisitions::DataFrame
    source_checks::DataFrame
    parameter_checks::DataFrame
    observations::DataFrame
    test_events::DataFrame
    tables::Dict{String, Any}
    artifacts::Dict{String, Any}
end

function RunState()
    return RunState(
        load_env(),
        DataFrame(
            source = String[],
            dataset = String[],
            request_id = String[],
            retrieved_at = DateTime[],
            http_status = Int[],
            raw_sha256 = String[],
            raw_path = String[],
            byte_count = Int[],
            content_type = String[],
            status = String[],
            detail = String[],
        ),
        DataFrame(
            source = String[],
            dataset = String[],
            check_id = String[],
            status = String[],
            observed = String[],
            expected = String[],
            detail = String[],
            checked_at = DateTime[],
        ),
        DataFrame(
            parameter = String[],
            source = String[],
            frequency = String[],
            unit = String[],
            shape = String[],
            status = String[],
            source_control_reconciles = String[],
            model_mapping_admissible = String[],
            check_id = String[],
            detail = String[],
            checked_at = DateTime[],
        ),
        DataFrame(
            source = String[],
            dataset = String[],
            series_id = String[],
            period = Date[],
            frequency = String[],
            unit = String[],
            value = Union{Missing, Float64}[],
            status = String[],
            raw_sha256 = String[],
            note = String[],
        ),
        DataFrame(
            stage = String[],
            test_id = String[],
            status = String[],
            elapsed_seconds = Float64[],
            detail = String[],
            checked_at = DateTime[],
        ),
        Dict{String, Any}(),
        Dict{String, Any}(),
    )
end

function load_env(path::String = joinpath(REPO_ROOT, ".env"))
    values = Dict{String, String}()
    isfile(path) || return values
    for raw_line in eachline(path)
        line = strip(raw_line)
        (isempty(line) || startswith(line, "#") || !occursin("=", line)) && continue
        key, value = split(line, "="; limit = 2)
        value = strip(value)
        if length(value) >= 2 &&
                (
                (startswith(value, "\"") && endswith(value, "\"")) ||
                    (startswith(value, "'") && endswith(value, "'"))
            )
            value = value[2:(end - 1)]
        end
        values[strip(key)] = value
    end
    return values
end

function require_key(state::RunState, key::String)
    value = get(state.env, key, "")
    isempty(value) && error("$key is not configured in $(joinpath(REPO_ROOT, ".env"))")
    return value
end

safe_slug(value) = begin
    slug = replace(lowercase(String(value)), r"[^a-z0-9._=-]+" => "-")
    strip(slug, '-')
end

sha256_bytes(bytes::Vector{UInt8}) = bytes2hex(SHA.sha256(bytes))

function redact_secrets(bytes::Vector{UInt8}, state::RunState)
    text = String(bytes)
    redactions = String[]
    for (name, secret) in state.env
        isempty(secret) && continue
        if occursin(secret, text)
            text = replace(text, secret => "[REDACTED:$name]")
            push!(redactions, name)
        end
    end
    return Vector{UInt8}(codeunits(text)), sort!(unique(redactions))
end

function archive_response!(
        state::RunState,
        source::String,
        dataset::String,
        request_id::String,
        response::HTTP.Response;
        extension::String,
        public_request::AbstractDict = Dict{String, Any}(),
        status::String = "APPROVED",
        detail::String = "",
    )
    sanitized, redactions = redact_secrets(Vector{UInt8}(response.body), state)
    digest = sha256_bytes(sanitized)
    vintage = string(DATA_TRUTH_VINTAGE)
    root = joinpath(
        RAW_ROOT,
        safe_slug(source),
        safe_slug(dataset),
        "vintage=$vintage",
        safe_slug(request_id),
    )
    mkpath(root)
    path = joinpath(root, "$digest.$extension")
    isfile(path) || open(path, "w") do io
        write(io, sanitized)
    end
    metadata_path = joinpath(root, "$digest.metadata.json")
    metadata = Dict(
        "source" => source,
        "dataset" => dataset,
        "request_id" => request_id,
        "retrieved_at" => string(now(UTC)),
        "http_status" => response.status,
        "content_type" => HTTP.header(response, "Content-Type", ""),
        "byte_count" => length(sanitized),
        "sha256" => digest,
        "request" => public_request,
        "secret_fields_redacted_from_response" => redactions,
    )
    isfile(metadata_path) || open(metadata_path, "w") do io
        JSON.print(io, metadata, 2)
    end
    push!(
        state.acquisitions,
        (
            source = source,
            dataset = dataset,
            request_id = request_id,
            retrieved_at = now(UTC),
            http_status = response.status,
            raw_sha256 = digest,
            raw_path = relpath(path, REPO_ROOT),
            byte_count = length(sanitized),
            content_type = HTTP.header(response, "Content-Type", ""),
            status = status,
            detail = isempty(redactions) ? detail :
                string(detail, isempty(detail) ? "" : " ", "API response credential echo redacted: ", join(redactions, ", ")),
        ),
    )
    return sanitized, digest, path
end

function http_get(url::String; query = Dict{String, String}())
    last_error = nothing
    for attempt in 1:3
        try
            response = HTTP.get(
                url;
                query = collect(pairs(query)),
                status_exception = false,
                readtimeout = 180,
                connect_timeout = 30,
                headers = ["User-Agent" => "BeforeIT-US-calibration/0.1"],
            )
            if response.status < 500
                return response
            end
            last_error = ErrorException("HTTP $(response.status)")
        catch error
            last_error = error
        end
        attempt < 3 && sleep(attempt)
    end
    throw(last_error)
end

function http_post_json(url::String, payload::Dict{String, Any})
    last_error = nothing
    body = JSON.json(payload)
    for attempt in 1:3
        try
            response = HTTP.post(
                url,
                ["Content-Type" => "application/json", "User-Agent" => "BeforeIT-US-calibration/0.1"],
                body;
                status_exception = false,
                readtimeout = 180,
                connect_timeout = 30,
            )
            if response.status < 500
                return response
            end
            last_error = ErrorException("HTTP $(response.status)")
        catch error
            last_error = error
        end
        attempt < 3 && sleep(attempt)
    end
    throw(last_error)
end

function record_source_check!(
        state::RunState,
        source::AbstractString,
        dataset::AbstractString,
        check_id::AbstractString,
        status::AbstractString;
        observed = "",
        expected = "",
        detail = "",
    )
    status in VALID_STATUSES || error("Invalid QA status $status")
    push!(
        state.source_checks,
        (
            source = String(source),
            dataset = String(dataset),
            check_id = String(check_id),
            status = String(status),
            observed = string(observed),
            expected = string(expected),
            detail = string(detail),
            checked_at = now(UTC),
        ),
    )
    return status
end

function record_parameter_check!(
        state::RunState,
        parameter::AbstractString,
        source::AbstractString,
        status::AbstractString;
        frequency = "",
        unit = "",
        shape = "",
        check_id = "availability",
        detail = "",
        source_control_reconciles = status,
        model_mapping_admissible = status,
    )
    status in VALID_STATUSES || error("Invalid QA status $status")
    source_control_reconciles in VALID_STATUSES ||
        error(
        "Invalid source-control QA status $source_control_reconciles",
    )
    model_mapping_admissible in VALID_STATUSES ||
        error(
        "Invalid model-mapping QA status $model_mapping_admissible",
    )
    combined_status = worst_status(
        [source_control_reconciles, model_mapping_admissible],
    )
    status == combined_status ||
        error(
        "Overall parameter status $status must equal the fail-closed " *
            "worst status $combined_status across source control and model mapping",
    )
    push!(
        state.parameter_checks,
        (
            parameter = String(parameter),
            source = String(source),
            frequency = string(frequency),
            unit = string(unit),
            shape = string(shape),
            status = String(status),
            source_control_reconciles =
                String(source_control_reconciles),
            model_mapping_admissible =
                String(model_mapping_admissible),
            check_id = check_id,
            detail = string(detail),
            checked_at = now(UTC),
        ),
    )
    return status
end

function with_test_event!(f::Function, state::RunState, stage::String, test_id::String)
    started = time()
    try
        result = f()
        push!(
            state.test_events,
            (
                stage = stage,
                test_id = test_id,
                status = "APPROVED",
                elapsed_seconds = time() - started,
                detail = "",
                checked_at = now(UTC),
            ),
        )
        return result
    catch error
        push!(
            state.test_events,
            (
                stage = stage,
                test_id = test_id,
                status = "REJECTED",
                elapsed_seconds = time() - started,
                detail = sprint(showerror, error),
                checked_at = now(UTC),
            ),
        )
        rethrow()
    end
end

function parse_bea_number(value)
    value === missing && return missing
    text = strip(String(value))
    text in ("", "--", "---", "NA", "(NA)", "(D)") && return missing
    negative = startswith(text, "(") && endswith(text, ")")
    text = replace(text, "," => "", "(" => "", ")" => "")
    parsed = tryparse(Float64, text)
    parsed === nothing && return missing
    return negative ? -parsed : parsed
end

function quarter_end(year_value::Integer, quarter::Integer)
    month_value = 3 * quarter
    return lastdayofmonth(Date(year_value, month_value, 1))
end

function parse_quarter(value::AbstractString)
    matched = match(r"^(\d{4})Q([1-4])$", value)
    matched === nothing && error("Invalid quarter $value")
    return quarter_end(parse(Int, matched.captures[1]), parse(Int, matched.captures[2]))
end

function quarter_of(date::Date)
    return quarter_end(year(date), cld(month(date), 3))
end

function bea_results(payload)
    root = payload["BEAAPI"]
    results = root["Results"]
    if results isa AbstractVector
        isempty(results) && error("BEA returned an empty Results array")
        result = results[1]
        haskey(result, "Error") && error("BEA API error: $(JSON.json(result["Error"]))")
        return result
    end
    haskey(results, "Error") && error("BEA API error: $(JSON.json(results["Error"]))")
    return results
end

function bea_request!(
        state::RunState,
        dataset::String,
        request_id::String,
        parameters::Dict{String, String},
    )
    secret = require_key(state, "BEA_API_KEY")
    query = Dict(
        "UserID" => secret,
        "method" => "GetData",
        "datasetname" => dataset,
        "ResultFormat" => "JSON",
    )
    merge!(query, parameters)
    public_request = Dict{String, Any}(
        "method" => "GetData",
        "datasetname" => dataset,
    )
    for (key, value) in parameters
        public_request[key] = value
    end
    response = http_get(SOURCE_SPEC["endpoints"]["bea"]; query = query)
    response.status == 200 || error("BEA $request_id returned HTTP $(response.status)")
    bytes, digest, path = archive_response!(
        state,
        "BEA",
        dataset,
        request_id,
        response;
        extension = "json",
        public_request = public_request,
    )
    payload = JSON.parse(String(bytes))
    result = bea_results(payload)
    haskey(result, "Data") || error("BEA $request_id response has no Data")
    rows = result["Data"]
    isempty(rows) && error("BEA $request_id returned no rows")
    record_source_check!(
        state,
        "BEA",
        dataset,
        "$request_id.http_schema",
        "APPROVED";
        observed = "$(response.status), $(length(rows)) rows",
        expected = "HTTP 200 and non-empty Data",
        detail = "Raw response: $(relpath(path, REPO_ROOT)); SHA-256 $digest",
    )
    return rows, digest
end

function ensure_directories!()
    for path in (RAW_ROOT, CURATED_ROOT, VALIDATION_ROOT, BASELINE_ROOT, CALIBRATION_ROOT, dirname(DATABASE_PATH))
        mkpath(path)
    end
    return
end

function push_observation!(
        state::RunState;
        source::String,
        dataset::String,
        series_id::String,
        period::Date,
        frequency::String,
        unit::String,
        value,
        status::String = "APPROVED",
        raw_sha256::String = "",
        note::String = "",
    )
    status in VALID_STATUSES || error("Invalid observation status $status")
    numeric = value === missing ? missing : Float64(value)
    return push!(
        state.observations,
        (
            source = source,
            dataset = dataset,
            series_id = series_id,
            period = period,
            frequency = frequency,
            unit = unit,
            value = numeric,
            status = status,
            raw_sha256 = raw_sha256,
            note = note,
        ),
    )
end

function collect_bea!(state::RunState)
    io_spec = SOURCE_SPEC["bea"]["input_output"]
    for table_id in (String(io_spec["use_table"]), String(io_spec["supply_table"]))
        rows, digest = bea_request!(
            state,
            "InputOutput",
            "table_$table_id-$(io_spec["year"])",
            Dict("TableID" => table_id, "Year" => String(io_spec["year"])),
        )
        state.tables["bea_io_$table_id"] = rows
        state.tables["bea_io_$(table_id)_sha"] = digest
    end

    nipa_spec = SOURCE_SPEC["bea"]["nipa"]
    for table_name in String.(nipa_spec["annual_tables"])
        rows, digest = bea_request!(
            state,
            "NIPA",
            "$table_name-A-$(nipa_spec["annual_year"])",
            Dict(
                "TableName" => table_name,
                "Frequency" => "A",
                "Year" => String(nipa_spec["annual_year"]),
            ),
        )
        state.tables["bea_nipa_$table_name"] = rows
        state.tables["bea_nipa_$(table_name)_sha"] = digest
    end
    for table_name in String.(nipa_spec["quarterly_tables"])
        rows, digest = bea_request!(
            state,
            "NIPA",
            "$table_name-Q-history",
            Dict(
                "TableName" => table_name,
                "Frequency" => "Q",
                "Year" => String(nipa_spec["quarterly_year"]),
            ),
        )
        state.tables["bea_nipa_$table_name"] = rows
        state.tables["bea_nipa_$(table_name)_sha"] = digest
    end

    fixed_spec = SOURCE_SPEC["bea"]["fixed_assets"]
    for table_name in String.(fixed_spec["tables"])
        rows, digest = bea_request!(
            state,
            "FixedAssets",
            "$table_name-$(fixed_spec["year"])",
            Dict("TableName" => table_name, "Year" => String(fixed_spec["year"])),
        )
        state.tables["bea_fixed_$table_name"] = rows
        state.tables["bea_fixed_$(table_name)_sha"] = digest
    end
    return state
end

function collect_fred!(state::RunState)
    api_key = require_key(state, "FRED_API_KEY")
    meta_rows = Dict{String, Any}()
    all_series = String[]
    for spec in values(SOURCE_SPEC["fred_series"])
        append!(all_series, String.(spec["series"]))
    end
    for series_id in sort!(unique(all_series))
        meta_query = Dict(
            "series_id" => series_id,
            "api_key" => api_key,
            "file_type" => "json",
        )
        meta_response = http_get(SOURCE_SPEC["endpoints"]["fred_series"]; query = meta_query)
        meta_response.status == 200 || error("FRED metadata $series_id returned HTTP $(meta_response.status)")
        meta_bytes, meta_sha, _ = archive_response!(
            state,
            "FRED",
            "series_metadata",
            series_id,
            meta_response;
            extension = "json",
            public_request = Dict("series_id" => series_id, "file_type" => "json"),
        )
        meta_payload = JSON.parse(String(meta_bytes))
        series_meta = only(meta_payload["seriess"])
        meta_rows[series_id] = series_meta

        observations_query = Dict(
            "series_id" => series_id,
            "api_key" => api_key,
            "file_type" => "json",
            "observation_start" => "1996-10-01",
        )
        response = http_get(
            SOURCE_SPEC["endpoints"]["fred_observations"];
            query = observations_query,
        )
        response.status == 200 || error("FRED observations $series_id returned HTTP $(response.status)")
        bytes, digest, _ = archive_response!(
            state,
            "FRED",
            "series_observations",
            series_id,
            response;
            extension = "json",
            public_request = Dict(
                "series_id" => series_id,
                "file_type" => "json",
                "observation_start" => "1996-10-01",
            ),
        )
        payload = JSON.parse(String(bytes))
        rows = payload["observations"]
        frequency = startswith(String(series_meta["frequency_short"]), "M") ? "M" : "Q"
        unit = String(series_meta["units"])
        for row in rows
            value = parse_bea_number(row["value"])
            push_observation!(
                state;
                source = "FRED",
                dataset = "series_observations",
                series_id = series_id,
                period = Date(String(row["date"])),
                frequency = frequency,
                unit = unit,
                value = value,
                status = value === missing ? "MISSING" : "APPROVED",
                raw_sha256 = digest,
                note = String(series_meta["title"]),
            )
        end
        record_source_check!(
            state,
            "FRED",
            series_id,
            "metadata_and_values",
            isempty(rows) ? "REJECTED" : "APPROVED";
            observed = "$(length(rows)) rows; $(series_meta["frequency"]); $(series_meta["units"])",
            expected = "Non-empty level/rate series with reviewed metadata",
            detail = String(series_meta["title"]),
        )
        record_source_check!(
            state,
            "FRED",
            series_id,
            "credential_not_persisted",
            occursin(api_key, String(meta_bytes)) || occursin(api_key, String(bytes)) ?
                "REJECTED" : "APPROVED";
            observed = "Sanitized raw response scan",
            expected = "API credential absent",
            detail = "The raw archive redacts any API response credential echo before persistence.",
        )
        state.tables["fred_$(series_id)_sha"] = digest
        state.tables["fred_$(series_id)_meta_sha"] = meta_sha
    end
    state.tables["fred_metadata"] = meta_rows
    return state
end

function bls_payload_success(payload)
    return get(payload, "status", "") == "REQUEST_SUCCEEDED" &&
        haskey(payload, "Results") &&
        haskey(payload["Results"], "series")
end

function bls_health!(state::RunState, series_id::String)
    api_key = get(state.env, "BLS_API_KEY", "")
    if isempty(api_key)
        record_source_check!(
            state,
            "BLS",
            "Public Data API",
            "registered_key",
            "MISSING";
            expected = "Configured registered key",
            detail = "Anonymous fallback will be tested and used.",
        )
        return false
    end
    response = http_post_json(
        SOURCE_SPEC["endpoints"]["bls"],
        Dict{String, Any}(
            "seriesid" => [series_id],
            "startyear" => "2024",
            "endyear" => "2024",
            "registrationkey" => api_key,
        ),
    )
    bytes, _, _ = archive_response!(
        state,
        "BLS",
        "Public Data API",
        "registered-key-health",
        response;
        extension = "json",
        public_request = Dict(
            "seriesid" => [series_id],
            "startyear" => "2024",
            "endyear" => "2024",
            "registrationkey" => "[REDACTED]",
        ),
        status = "DUBIOUS",
    )
    payload = JSON.parse(String(bytes))
    valid = response.status == 200 && bls_payload_success(payload)
    state.acquisitions.status[end] = valid ? "APPROVED" : "REJECTED"
    messages = join(String.(get(payload, "message", String[])), " ")
    record_source_check!(
        state,
        "BLS",
        "Public Data API",
        "registered_key",
        valid ? "APPROVED" : "REJECTED";
        observed = isempty(messages) ? get(payload, "status", "unknown") : messages,
        expected = "REQUEST_SUCCEEDED",
        detail = valid ? "Registered access works." :
            "Configured key was rejected; anonymous ten-year chunks are used and separately tested.",
    )
    return valid
end

function collect_bls!(state::RunState)
    series_by_name = Dict{String, String}(
        string(name) => String(series_id)
            for (name, series_id) in SOURCE_SPEC["bls_series"]
    )
    series_ids = sort!(collect(values(series_by_name)))
    registered_access = bls_health!(state, first(series_ids))
    api_key = get(state.env, "BLS_API_KEY", "")
    name_by_id = Dict(value => key for (key, value) in series_by_name)

    all_rows = Dict{String, Vector{Any}}(series_id => Any[] for series_id in series_ids)
    for (start_year, end_year) in ((1996, 2005), (2006, 2015), (2016, 2025), (2026, 2026))
        request = Dict{String, Any}(
            "seriesid" => series_ids,
            "startyear" => string(start_year),
            "endyear" => string(end_year),
        )
        registered_access && (request["registrationkey"] = api_key)
        access = registered_access ? "registered" : "anonymous"
        response = http_post_json(SOURCE_SPEC["endpoints"]["bls"], request)
        bytes, digest, _ = archive_response!(
            state,
            "BLS",
            "CPS",
            "$start_year-$end_year-$access",
            response;
            extension = "json",
            public_request = Dict(
                "seriesid" => series_ids,
                "startyear" => string(start_year),
                "endyear" => string(end_year),
                "access" => access,
                "registrationkey" =>
                    registered_access ? "[REDACTED]" : nothing,
            ),
        )
        payload = JSON.parse(String(bytes))
        success = response.status == 200 && bls_payload_success(payload)
        messages = join(String.(get(payload, "message", String[])), " ")
        record_source_check!(
            state,
            "BLS",
            "CPS",
            "$(access)_$start_year-$end_year",
            success ? "APPROVED" : "REJECTED";
            observed = isempty(messages) ? get(payload, "status", "unknown") : messages,
            expected = "REQUEST_SUCCEEDED",
            detail = "$(titlecase(access)) access chunk; raw SHA-256 $digest",
        )
        success || error("BLS $access chunk $start_year-$end_year failed: $messages")
        for series in payload["Results"]["series"]
            series_id = String(series["seriesID"])
            append!(all_rows[series_id], series["data"])
            for row in series["data"]
                period_code = String(row["period"])
                startswith(period_code, "M") || continue
                period_code == "M13" && continue
                month_value = parse(Int, period_code[2:3])
                month_value <= 12 || continue
                value = parse_bea_number(row["value"])
                push_observation!(
                    state;
                    source = "BLS",
                    dataset = "CPS",
                    series_id = series_id,
                    period = lastdayofmonth(Date(parse(Int, String(row["year"])), month_value, 1)),
                    frequency = "M",
                    unit = series_id == series_by_name["unemployment_rate"] ?
                        "Percent" : "Thousands of persons",
                    value = value,
                    status = value === missing ? "MISSING" : "APPROVED",
                    raw_sha256 = digest,
                    note = name_by_id[series_id],
                )
            end
        end
    end
    for series_id in series_ids
        rows = all_rows[series_id]
        record_source_check!(
            state,
            "BLS",
            "CPS",
            "$series_id.nonempty",
            isempty(rows) ? "REJECTED" : "APPROVED";
            observed = length(rows),
            expected = "> 0 monthly observations",
            detail = name_by_id[series_id],
        )
    end
    state.tables["bls_rows"] = all_rows
    return state
end

function download_public!(
        state::RunState,
        source::String,
        dataset::String,
        request_id::String,
        url::String,
        extension::String,
    )
    response = http_get(url)
    response.status == 200 || error("$source $dataset returned HTTP $(response.status)")
    bytes, digest, path = archive_response!(
        state,
        source,
        dataset,
        request_id,
        response;
        extension = extension,
        public_request = Dict("url" => url),
    )
    record_source_check!(
        state,
        source,
        dataset,
        "$request_id.download",
        isempty(bytes) ? "REJECTED" : "APPROVED";
        observed = "$(length(bytes)) bytes",
        expected = "HTTP 200, non-empty body",
        detail = "$(relpath(path, REPO_ROOT)); SHA-256 $digest",
    )
    return bytes, digest
end

function row_field(row, candidates::Vector{Symbol})
    names = propertynames(row)
    for candidate in candidates
        candidate in names && return getproperty(row, candidate)
        lowercase_candidate = Symbol(lowercase(String(candidate)))
        lowercase_candidate in names && return getproperty(row, lowercase_candidate)
    end
    error("None of $(join(candidates, ", ")) found in CSV columns $(join(names, ", "))")
end

function collect_qcew!(state::RunState)
    required = Set(
        [
            :own_code,
            :industry_code,
            :annual_avg_estabs,
            :annual_avg_emplvl,
            :total_annual_wages,
        ]
    )
    for source_year in (2022, 2024)
        bytes, digest = download_public!(
            state,
            "BLS",
            "QCEW",
            "$source_year-annual-US-area",
            SOURCE_SPEC["endpoints"]["qcew_$source_year"],
            "csv",
        )
        frame = CSV.read(IOBuffer(bytes), DataFrame; normalizenames = true)
        present = Set(Symbol.(names(frame)))
        schema_ok = required ⊆ present
        record_source_check!(
            state,
            "BLS",
            "QCEW",
            "$source_year.schema",
            schema_ok ? "APPROVED" : "REJECTED";
            observed = join(sort!(String.(collect(intersect(required, present)))), ", "),
            expected = join(sort!(String.(collect(required))), ", "),
            detail = "$(nrow(frame)) national annual rows",
        )
        schema_ok || error("QCEW $source_year schema does not contain required fields")
        state.tables["qcew_$source_year"] = frame
        state.tables["qcew_$(source_year)_sha"] = digest
    end
    state.tables["qcew"] = state.tables["qcew_2024"]
    state.tables["qcew_sha"] = state.tables["qcew_2024_sha"]
    return state
end

function collect_susb!(state::RunState)
    bytes, digest = download_public!(
        state,
        "Census",
        "SUSB",
        "2022-US-state-six-digit-NAICS",
        SOURCE_SPEC["endpoints"]["susb_2022"],
        "txt",
    )
    selected = NamedTuple[]
    rows = CSV.Rows(
        IOBuffer(bytes);
        normalizenames = true,
        types = String,
        reusebuffer = true,
    )
    inspected = 0
    for row in rows
        inspected += 1
        state_code = strip(String(row_field(row, [:STATE, :state])))
        size_code = strip(String(row_field(row, [:ENTRSIZE, :entrsize])))
        state_code == "00" || continue
        size_code == "01" || continue
        naics = strip(String(row_field(row, [:NAICS, :naics])))
        firms = parse_bea_number(row_field(row, [:FIRM, :firm]))
        establishments = parse_bea_number(row_field(row, [:ESTB, :estb]))
        employment = parse_bea_number(row_field(row, [:EMPL, :empl]))
        push!(
            selected,
            (
                naics = naics,
                firms = firms,
                establishments = establishments,
                employment = employment,
            ),
        )
    end
    frame = DataFrame(selected)
    schema_ok = all(name -> name in names(frame), ["naics", "firms", "establishments", "employment"])
    record_source_check!(
        state,
        "Census",
        "SUSB",
        "national_all_enterprises_schema",
        schema_ok && nrow(frame) > 0 ? "APPROVED" : "REJECTED";
        observed = "$(nrow(frame)) selected of $inspected rows",
        expected = "STATE=00, ENTRSIZE=01 rows with FIRM/ESTB/EMPL",
        detail = "Employer enterprises are used as the closest available firm concept.",
    )
    state.tables["susb"] = frame
    state.tables["susb_sha"] = digest
    return state
end

function collect_usda!(state::RunState)
    bytes, digest = download_public!(
        state,
        "USDA",
        "Farms and Land in Farms",
        "2025-summary-containing-2024",
        SOURCE_SPEC["endpoints"]["usda_2025_summary"],
        "pdf",
    )
    startswith(String(bytes[1:min(end, 4)]), "%PDF") || error("USDA download is not a PDF")
    manual = SOURCE_SPEC["manual"]["usda_farms"]
    state.tables["usda_farms"] = Float64(manual["value"])
    state.tables["usda_farms_sha"] = digest
    record_source_check!(
        state,
        "USDA",
        "Farms and Land in Farms",
        "manual_extraction",
        String(manual["status"]);
        observed = "$(manual["value"]) $(manual["unit"]) in $(manual["year"])",
        expected = "National published farm count",
        detail = String(manual["note"]),
    )
    return state
end

function collect!(state::RunState = RunState())
    today() == DATA_TRUTH_VINTAGE || error(
        "Live collection is pinned to truth vintage $(DATA_TRUTH_VINTAGE), " *
            "but the system date is $(today()). Advance data_truth_vintage " *
            "explicitly before fetching revised source data.",
    )
    ensure_directories!()
    with_test_event!(state, "collect", "bea") do
        collect_bea!(state)
    end
    with_test_event!(state, "collect", "fred") do
        collect_fred!(state)
    end
    with_test_event!(state, "collect", "bls_cps") do
        collect_bls!(state)
    end
    with_test_event!(state, "collect", "qcew") do
        collect_qcew!(state)
    end
    with_test_event!(state, "collect", "census_susb") do
        collect_susb!(state)
    end
    with_test_event!(state, "collect", "usda") do
        collect_usda!(state)
    end
    return state
end

function io_long(rows)
    frame = DataFrame(
        table_id = String[],
        year = Int[],
        row_code = String[],
        row_description = String[],
        column_code = String[],
        column_description = String[],
        value = Union{Missing, Float64}[],
    )
    for row in rows
        push!(
            frame,
            (
                table_id = String(row["TableID"]),
                year = parse(Int, String(row["Year"])),
                row_code = String(row["RowCode"]),
                row_description = String(row["RowDescr"]),
                column_code = String(row["ColCode"]),
                column_description = String(row["ColDescr"]),
                value = parse_bea_number(row["DataValue"]),
            ),
        )
    end
    return frame
end

function lookup_matrix(frame::DataFrame)
    values = Dict{Tuple{String, String}, Float64}()
    for row in eachrow(frame)
        row[7] === missing && continue
        values[(String(row[3]), String(row[5]))] = Float64(row[7])
    end
    return values
end

"""
    diagnostic_io_table(rows, table_id, source_sha256)

Construct the typed, sparse I-O representation used by the source-aware
supply/make diagnostics. Non-numeric BEA markers remain absent structural
cells; every numeric cell retains its published row and column economic basis.
"""
function diagnostic_io_table(rows, table_id, source_sha256)
    cells = USSupplyMakeDiagnostics.IOCell[]
    for row in rows
        value = parse_bea_number(row["DataValue"])
        ismissing(value) && continue
        push!(
            cells,
            USSupplyMakeDiagnostics.IOCell(
                row["TableID"],
                parse(Int, String(row["Year"])),
                row["RowCode"],
                get(row, "RowType", ""),
                row["ColCode"],
                get(row, "ColType", ""),
                value,
            ),
        )
    end
    table = USSupplyMakeDiagnostics.IOTable(
        cells;
        source_sha256 = source_sha256,
    )
    table.table_id == String(table_id) ||
        error(
        "Expected BEA I-O table $table_id; got $(table.table_id)",
    )
    return table
end

io_get(values, row_code::String, column_code::String) =
    get(values, (row_code, column_code), 0.0)

"""
    purchasers_to_basic_price_vector(supply_values, model_codes)

Build the legacy commodity-level `T013/T016` valuation quotient from BEA
Supply Table 262. `T013` is total product supply at basic prices and `T016`
is the corresponding supply at purchasers' prices. The model's aggregated
retail commodity `4A0` must combine the four detailed supply rows that feed
that model sector before the ratio is calculated.

The quotient is an arithmetic diagnostic, not a cell-identified valuation
allocator. The legacy research runtime still consumes it pending a
producer-price calibration adapter; current accounting evidence rejects that
application for promotion or forecast-origin admission.
"""
function purchasers_to_basic_price_vector(supply_values, model_codes)
    supply_rows(code) =
        code == "4A0" ? ("441", "445", "452", "4A0") : (code,)
    basic_price = Float64[
        sum(io_get(supply_values, row, "T013") for row in supply_rows(code))
            for code in model_codes
    ]
    purchasers_price = Float64[
        sum(io_get(supply_values, row, "T016") for row in supply_rows(code))
            for code in model_codes
    ]
    all(isfinite, basic_price) ||
        error("BEA T013 basic-price controls contain nonfinite values")
    all(isfinite, purchasers_price) ||
        error("BEA T016 purchasers-price controls contain nonfinite values")
    all(>(0), basic_price) ||
        error("BEA T013 basic-price controls must be strictly positive")
    zero_denominators = model_codes[purchasers_price .== 0]
    isempty(zero_denominators) ||
        error(
        "BEA T016 purchasers-price control is zero for model commodities " *
            join(zero_denominators, ", "),
    )
    all(>(0), purchasers_price) ||
        error("BEA T016 purchasers-price controls must be strictly positive")
    values = basic_price ./ purchasers_price
    all(isfinite, values) ||
        error("BEA purchasers-to-basic-price quotient contains nonfinite values")
    all(>(0), values) ||
        error("BEA purchasers-to-basic-price quotient must be strictly positive")
    return (;
        values,
        basic_price,
        purchasers_price,
        scientific_status = VALUATION_BRIDGE_SCIENTIFIC_STATUS,
        runtime_status = VALUATION_BRIDGE_RUNTIME_STATUS,
        cell_identified = false,
        diagnostic_only = true,
    )
end

"""
    nonnegative_import_vector(raw_values; control = sum(raw_values))

Convert BEA commodity imports (`MCIF + MADJ`) to model-ready nonnegative
levels while preserving their aggregate control. Negative commodity entries
are CIF/FOB valuation adjustments rather than negative physical imports: they
are floored at zero, then the positive entries are proportionally scaled back
to the supplied structural control (the signed `MCIF + MADJ` total by
default).
"""
function nonnegative_import_vector(raw_values; control = sum(raw_values))
    raw = Float64.(raw_values)
    all(isfinite, raw) || error("BEA import vector contains nonfinite values")
    raw_sum = sum(raw)
    raw_control = Float64(control)
    isfinite(raw_control) || error("BEA import aggregate control is nonfinite")
    raw_control >= 0 || error("BEA import aggregate control is negative")
    positive = max.(raw, 0.0)
    positive_control = sum(positive)
    if raw_control == 0
        return (
            values = zeros(length(raw)),
            raw_control = raw_control,
            raw_sum = raw_sum,
            positive_control = positive_control,
            scale = 0.0,
            negative_count = count(value -> value < 0, raw),
            negative_adjustment = sum(min.(raw, 0.0)),
        )
    end
    positive_control > 0 ||
        error("BEA import aggregate is positive but has no positive commodity entries")
    scale = raw_control / positive_control
    values = positive .* scale
    return (
        values = values,
        raw_control = raw_control,
        raw_sum = raw_sum,
        positive_control = positive_control,
        scale = scale,
        negative_count = count(value -> value < 0, raw),
        negative_adjustment = sum(min.(raw, 0.0)),
    )
end

function build_io!(state::RunState)
    use_frame = io_long(state.tables["bea_io_259"])
    supply_frame = io_long(state.tables["bea_io_262"])
    use_values = lookup_matrix(use_frame)
    supply_values = lookup_matrix(supply_frame)
    typed_use = diagnostic_io_table(
        state.tables["bea_io_259"],
        "259",
        state.tables["bea_io_259_sha"],
    )
    typed_supply = diagnostic_io_table(
        state.tables["bea_io_262"],
        "262",
        state.tables["bea_io_262_sha"],
    )
    typed_use.year == STRUCTURAL_YEAR ||
        error(
        "BEA Table 259 source year $(typed_use.year) does not match structural year $STRUCTURAL_YEAR",
    )
    typed_supply.year == STRUCTURAL_YEAR ||
        error(
        "BEA Table 262 source year $(typed_supply.year) does not match structural year $STRUCTURAL_YEAR",
    )
    supply_make_report =
        USSupplyMakeDiagnostics.diagnose_supply_make(
        typed_use,
        typed_supply;
        expected_supply_commodity_count = 73,
        expected_supply_industry_count = 71,
        expected_use_commodity_count = 70,
    )
    USSupplyMakeDiagnostics.controls_pass(supply_make_report) ||
        error(
        "Source-aware BEA supply/make controls exceed published rounding tolerances",
    )
    length(supply_make_report.residuals) == 755 ||
        error(
        "Source-aware BEA supply/make contract expected exactly 755 controls; found $(length(supply_make_report.residuals))",
    )
    symmetric_use_report =
        USSymmetricSupplyUse.build_industry_technology_system(
        supply_make_report,
    )
    USSymmetricSupplyUse.transformation_controls_pass(
        symmetric_use_report,
    ) ||
        error(
        "Industry-technology symmetric-use controls exceed declared tolerances",
    )
    length(symmetric_use_report.residuals) == 420 ||
        error(
        "Industry-technology symmetric-use contract expected exactly 420 controls; found $(length(symmetric_use_report.residuals))",
    )
    requirements_fixture =
        USRequirementsDiagnostics.load_requirements_fixture(
        REQUIREMENTS_FIXTURE_ROOT,
    )
    official_direct_requirements_fixture =
        USRequirementsDiagnostics.load_official_direct_requirements_fixture(
        OFFICIAL_DIRECT_REQUIREMENTS_FIXTURE_ROOT,
    )
    requirements_fixture.year == STRUCTURAL_YEAR ||
        error(
        "BEA Table 59 diagnostic year $(requirements_fixture.year) does not match structural year $STRUCTURAL_YEAR",
    )
    official_direct_requirements_fixture.year == STRUCTURAL_YEAR ||
        error(
        "BEA official-direct diagnostic year $(official_direct_requirements_fixture.year) does not match structural year $STRUCTURAL_YEAR",
    )
    requirements_report =
        USRequirementsDiagnostics.build_official_direct_requirements(
        requirements_fixture,
        official_direct_requirements_fixture,
    )
    USRequirementsDiagnostics.requirements_controls_pass(
        requirements_report,
    ) ||
        error("BEA official-direct requirements controls do not pass")
    length(requirements_report.residuals) == 221 ||
        error(
        "BEA official-direct requirements contract expected exactly 221 controls; found $(length(requirements_report.residuals))",
    )
    requirements_transaction_report =
        USRequirementsDiagnostics.build_requirements_transactions(
        requirements_report,
        supply_make_report,
    )
    USRequirementsDiagnostics.transaction_controls_pass(
        requirements_transaction_report,
    ) ||
        error("BEA official-direct transaction-aggregation controls do not pass")
    length(requirements_transaction_report.residuals) == 3 ||
        error(
        "BEA official-direct transaction contract expected exactly 3 controls; found $(length(requirements_transaction_report.residuals))",
    )
    requirements_comparison_report =
        USRequirementsDiagnostics.compare_structural_transactions(
        symmetric_use_report,
        requirements_transaction_report,
    )
    USRequirementsDiagnostics.comparison_controls_pass(
        requirements_comparison_report,
    ) ||
        error("BEA structural-transaction comparison controls do not pass")
    length(requirements_comparison_report.residuals) == 3 ||
        error(
        "BEA structural-transaction comparison expected exactly 3 controls; found $(length(requirements_comparison_report.residuals))",
    )
    special_rows = Set(
        [
            "Other",
            "Used",
            "T005",
            "T00OSUB",
            "T00OTOP",
            "T00SUB",
            "T00TOP",
            "T018",
            "V001",
            "V003",
            "VABAS",
            "VAPRO",
        ]
    )
    ordered_rows = unique(use_frame.row_code)
    model_codes = [code for code in ordered_rows if !(code in special_rows)]
    length(model_codes) == 68 || error("Expected 68 observed BEA commodity sectors; got $(length(model_codes))")
    source_industry_codes = reduce(
        vcat,
        [code == "4A0" ? ["441", "445", "452", "4A0"] : [code] for code in model_codes],
    )
    length(source_industry_codes) == 71 ||
        error("Expected 71 BEA industries before retail aggregation")
    column_sources(code) = code == "4A0" ? ["441", "445", "452", "4A0"] : [code]
    aggregate_column(row_code, model_code) =
        sum(io_get(use_values, row_code, source_code) for source_code in column_sources(model_code))

    observed = zeros(Float64, 68, 68)
    for (row_index, row_code) in enumerate(model_codes)
        for (column_index, model_code) in enumerate(model_codes)
            observed[row_index, column_index] = aggregate_column(row_code, model_code)
        end
    end
    intermediate_controls = [
        aggregate_column("T005", model_code) for model_code in model_codes
    ]
    observed_column_sums = vec(sum(observed; dims = 1))
    bridge_factor = intermediate_controls ./ observed_column_sums
    all(isfinite, bridge_factor) || error("Nonfinite I-O bridge factor")
    bridged = observed .* reshape(bridge_factor, 1, :)

    industry_vector(row_code) = [
        aggregate_column(row_code, model_code) for model_code in model_codes
    ]
    commodity_vector(column_code) = [
        io_get(use_values, row_code, column_code) for row_code in model_codes
    ]
    commodity_sum(column_codes) =
        reduce(+, [commodity_vector(column_code) for column_code in column_codes])
    compensation = industry_vector("V001")
    operating_surplus = industry_vector("V003")
    production_taxes =
        industry_vector("T00OTOP") - industry_vector("T00OSUB")
    reported_industry_product_taxes =
        industry_vector("T00TOP") - industry_vector("T00SUB")
    output_control = industry_vector("T018")
    Set(supply_make_report.commodity_output.codes) ==
        union(Set(model_codes), Set(["Other", "Used"])) ||
        error(
        "Source-aware commodity-output codes do not match the model core plus closure accounts",
    )
    Set(supply_make_report.industry_output.codes) == Set(model_codes) ||
        error(
        "Source-aware industry-output codes do not match the model industry axis",
    )
    domestic_commodity_output_basic_price = Float64[
        supply_make_report.commodity_output[code] for code in model_codes
    ]
    supply_industry_output_basic_price_t017 = Float64[
        supply_make_report.industry_output[code] for code in model_codes
    ]
    maximum(
        abs,
        supply_industry_output_basic_price_t017 - output_control,
    ) <= 2.0 ||
        error(
        "Table 262 T017 industry output does not reconcile to Table 259 T018",
    )
    # The calibration artifact labels its industry-output vector as Table 259
    # T018, so persist the actual T018 bytes under that field. Retain the
    # independently sourced Table 262 T017 vector under an explicit name for
    # the cross-table provenance check above.
    source_industry_output_basic_price = copy(output_control)
    closure_accounts = DataFrame(
        commodity_code = collect(
            USSupplyMakeDiagnostics.EXPLICIT_CLOSURE_CODES,
        ),
        domestic_output_basic_price_millions_usd = [
            supply_make_report.commodity_output[code]
                for code in
                USSupplyMakeDiagnostics.EXPLICIT_CLOSURE_CODES
        ],
        purchaser_supply_millions_usd = [
            supply_make_report.purchaser_supply[code]
                for code in
                USSupplyMakeDiagnostics.EXPLICIT_CLOSURE_CODES
        ],
        total_use_millions_usd = [
            supply_make_report.total_use[code]
                for code in
                USSupplyMakeDiagnostics.EXPLICIT_CLOSURE_CODES
        ],
        allocation_policy = fill(
            "explicit_unallocated_closure_account",
            length(USSupplyMakeDiagnostics.EXPLICIT_CLOSURE_CODES),
        ),
    )
    household_consumption = commodity_vector("F010")
    capital_columns = [
        "F02E",
        "F02N",
        "F02R",
        "F02S",
    ]
    government_columns = [
        "F06C",
        "F06E",
        "F06N",
        "F06S",
        "F07C",
        "F07E",
        "F07N",
        "F07S",
        "F10C",
        "F10E",
        "F10N",
        "F10S",
    ]
    fixed_capitalformation = commodity_sum(capital_columns)
    government_consumption = commodity_sum(government_columns)
    exports = commodity_vector("F040")
    purchasers_to_basic =
        purchasers_to_basic_price_vector(supply_values, model_codes)
    excluded_commodity_codes = ["Other", "Used"]
    official_import_control =
        io_get(supply_values, "T017", "MCIF") +
        io_get(supply_values, "T017", "MADJ")
    excluded_imports = sum(
        io_get(supply_values, commodity_code, "MCIF") +
            io_get(supply_values, commodity_code, "MADJ")
            for commodity_code in excluded_commodity_codes
    )
    model_import_control = official_import_control - excluded_imports
    raw_imports = [
        io_get(supply_values, commodity_code, "MCIF") +
            io_get(supply_values, commodity_code, "MADJ")
            for commodity_code in model_codes
    ]
    import_adjustment = nonnegative_import_vector(
        raw_imports;
        control = model_import_control,
    )
    imports = import_adjustment.values
    product_taxes = zeros(length(model_codes))
    taxes_products_household = 0.0
    taxes_products_capitalformation = 0.0
    taxes_products_government = 0.0
    taxes_products_dwellings = 0.0
    taxes_products_inventory = 0.0
    modeled_product_tax_control = 0.0
    for commodity_code in model_codes
        commodity_tax =
            io_get(supply_values, commodity_code, "TOP") +
            io_get(supply_values, commodity_code, "MDTY") +
            io_get(supply_values, commodity_code, "SUB")
        modeled_product_tax_control += commodity_tax
        intermediate_uses = [
            aggregate_column(commodity_code, industry_code)
                for industry_code in model_codes
        ]
        household_use = io_get(use_values, commodity_code, "F010")
        capital_uses = [
            io_get(use_values, commodity_code, column_code)
                for column_code in capital_columns
        ]
        government_uses = [
            io_get(use_values, commodity_code, column_code)
                for column_code in government_columns
        ]
        inventory_use = io_get(use_values, commodity_code, "F030")
        domestic_use =
            sum(intermediate_uses) + household_use + sum(capital_uses) +
            sum(government_uses) + inventory_use
        domestic_use <= 0 && continue
        product_taxes .+= commodity_tax .* intermediate_uses ./ domestic_use
        taxes_products_household +=
            commodity_tax * household_use / domestic_use
        taxes_products_capitalformation +=
            commodity_tax * sum(capital_uses) / domestic_use
        taxes_products_government +=
            commodity_tax * sum(government_uses) / domestic_use
        taxes_products_inventory +=
            commodity_tax * inventory_use / domestic_use
        dwellings_position = findfirst(==("F02R"), capital_columns)
        taxes_products_dwellings +=
            commodity_tax * capital_uses[dwellings_position] / domestic_use
    end
    gross_capitalformation_dwellings =
        sum(commodity_vector("F02R")) + taxes_products_dwellings
    total_product_tax_control = io_get(supply_values, "T017", "T015")
    allocation_total =
        sum(product_taxes) + taxes_products_household +
        taxes_products_capitalformation + taxes_products_government +
        taxes_products_inventory
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259/262",
        "product_tax_valuation_bridge",
        "DUBIOUS";
        observed = "modeled commodities \$$(modeled_product_tax_control)m ($(round(100 * modeled_product_tax_control / total_product_tax_control; digits = 2))% of T015); allocation error \$$(allocation_total - modeled_product_tax_control)m",
        expected = "Commodity product/import taxes allocated across domestic uses; exports remain zero-rated",
        detail = "Table 262 TOP+MDTY+SUB is allocated in proportion to Table 259 domestic intermediate/final uses. Other/Used commodities and inventories remain visible outside current model demand categories.",
    )

    model_output =
        vec(sum(bridged; dims = 1)) + compensation + operating_surplus + production_taxes
    identity_error = model_output - output_control
    max_identity_error = maximum(abs, identity_error)
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259",
        "observed_core_topology",
        size(observed) == (68, 68) ? "APPROVED" : "REJECTED";
        observed = "$(size(observed)); 71 industries aggregated to 68",
        expected = "68×68 after 441+445+452+4A0 → 4A0",
        detail = "No synthetic commodity split is introduced.",
    )
    gap = sum(intermediate_controls) - sum(observed)
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259",
        "intermediate_control_gap",
        abs(gap) <= 1.0 ? "APPROVED" : "DUBIOUS";
        observed = "Raw sparse core is $(round(100 * sum(observed) / sum(intermediate_controls); digits = 3))% of T005; gap \$$(round(gap; digits = 1))m",
        expected = "T005 industry controls",
        detail = "The model bridge scales each industry column to T005; raw observed and bridged matrices are both retained.",
    )
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259",
        "output_identity_after_bridge",
        max_identity_error <= 2.0 ? "APPROVED" : "REJECTED";
        observed = "maximum absolute industry error \$$(max_identity_error)m",
        expected = "≤ \$2m BEA rounding",
        detail = "T005 + V001 + V003 + T00OTOP − T00OSUB = T018",
    )

    record_source_check!(
        state,
        "BEA",
        "InputOutput 259/262",
        "source_aware_supply_make_controls",
        "APPROVED";
        observed = "$(length(supply_make_report.residuals)) controls within published rounding; raw make $(size(supply_make_report.raw_make)); aggregated make $(size(supply_make_report.aggregated_make)); raw use $(size(supply_make_report.raw_use)); aggregated use $(size(supply_make_report.aggregated_use))",
        expected = "755 unbalanced source controls; 73×71 and 70×68 make matrices; 70×71 and 70×68 use matrices",
        detail = "Commodity and industry axes are distinct Julia types. The only aggregation is code-keyed 441+445+452+4A0 → 4A0; Other and Used remain explicit; balancing_applied=false.",
    )
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259/262",
        "industry_technology_symmetric_use_diagnostic",
        "DUBIOUS";
        observed = "$(length(symmetric_use_report.residuals)) transformation controls pass; published-control total \$$(sum(symmetric_use_report.published_symmetric_use.values))m; rounding-normalized total \$$(sum(symmetric_use_report.rounding_normalized_symmetric_use.values))m; $(length(symmetric_use_report.negative_make_cells)) negative make, $(length(symmetric_use_report.negative_use_cells)) negative use, and $(length(symmetric_use_report.negative_symmetric_cells)) negative derived cells preserved",
        expected = "70×70 commodity-by-commodity industry-technology diagnostic with exact intermediate-use row conservation after explicit source-rounding normalization",
        detail = "Z = U*diag(g)^(-1)*V'. Both published-output and exact-make-sum denominators are retained. Use is purchasers' price, make is producer price, and output is basic price; no full valuation bridge, Other/Used allocation, clipping, balancing, or model-state reconciliation is claimed.",
    )
    largest_comparison_cell =
        requirements_comparison_report.maximum_absolute_difference_cell
    record_source_check!(
        state,
        "BEA",
        "InputOutput 59/direct/market-share/259/262",
        "official_direct_requirements_comparator",
        "DUBIOUS";
        observed = "$(length(requirements_report.residuals)) source and round-trip controls, $(length(requirements_transaction_report.residuals)) output-weighted aggregation invariants, and $(length(requirements_comparison_report.residuals)) comparison invariants pass; official B×D differs from I-inv(Table 59) by at most $(requirements_report.maximum_direct_agreement_error); official-direct, T007-scaled 70×70 transaction total \$$(sum(requirements_transaction_report.transactions.values))m; purchaser-price symmetric-use diagnostic exceeds it by \$$(requirements_comparison_report.signed_total_difference)m; L1 cell difference \$$(requirements_comparison_report.absolute_cell_difference)m; largest cell $(largest_comparison_cell.row_code)→$(largest_comparison_cell.column_code) is \$$(largest_comparison_cell.difference)m; cell correlation $(requirements_comparison_report.cell_correlation); $(length(requirements_report.substantive_negative_direct_cells)) direct coefficients are below -$(USRequirementsDiagnostics.SUBSTANTIVE_NEGATIVE_THRESHOLD)",
        expected = "separately published BEA transformation comparator; a nonzero basis/system-boundary gap remains explicit",
        detail = "The primary direct matrix is A = B×D from BEA's after-redefinitions direct-requirements and market-share workbooks; I-inv(Table 59) and inv(I-A) are retained as published-rounding round trips. Z = A*diag(q) uses Table 262 T007 before output-weighted retail aggregation. These products share the BEA input-output system, so the comparison is not independent statistical evidence and its raw-cell correlation is not an accuracy score. Both checked-in sources are current-vintage diagnostics, not origin eligible. No negative coefficient is clipped, and no valuation bridge, final-use ledger, Other/Used allocation, balancing, gate change, or model-state write is claimed.",
    )
    output_basis_difference =
        source_industry_output_basic_price -
        domestic_commodity_output_basic_price
    record_source_check!(
        state,
        "BEA",
        "InputOutput 262",
        "commodity_industry_output_basis_separation",
        "APPROVED";
        observed = "modeled T007 commodity output \$$(sum(domestic_commodity_output_basic_price))m; T018 industry output \$$(sum(source_industry_output_basic_price))m; signed difference \$$(sum(output_basis_difference))m; maximum absolute sector difference \$$(maximum(abs, output_basis_difference))m",
        expected = "separate, code-keyed 68-vectors; no positional substitution",
        detail = "T007 domestic commodity output is admitted only to commodity diagnostics. Table 259 T018 is retained as the industry control; the independently sourced Table 262 T017 vector is stored separately and must reconcile within published rounding.",
    )
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259/262",
        "explicit_other_used_closure_accounts",
        "APPROVED";
        observed = join(
            [
                "$(row.commodity_code): T007=$(row.domestic_output_basic_price_millions_usd), T016=$(row.purchaser_supply_millions_usd), T019=$(row.total_use_millions_usd)"
                    for row in eachrow(closure_accounts)
            ],
            "; ",
        ),
        expected = "Other and Used retained by name and not allocated into the 68 modeled commodities",
        detail = "Closure-account values remain outside the model core pending a separately governed mapping.",
    )

    supply_output = [
        sum(io_get(supply_values, "T017", source_code) for source_code in column_sources(code))
            for code in model_codes
    ]
    use_supply_output_error = maximum(abs, supply_output - output_control)
    use_total = [io_get(use_values, code, "T019") for code in model_codes]
    supply_total = [io_get(supply_values, code, "T016") for code in model_codes]
    use_supply_total_error = maximum(abs, use_total - supply_total)
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259/262",
        "cross_table_output_and_use",
        max(use_supply_output_error, use_supply_total_error) <= 2.0 ?
            "APPROVED" : "REJECTED";
        observed = "industry output max error \$$(use_supply_output_error)m; commodity total max error \$$(use_supply_total_error)m",
        expected = "≤ \$2m BEA rounding",
        detail = "Table 259 T018/T019 cross-checks Table 262 T017/T016.",
    )
    record_source_check!(
        state,
        "BEA",
        "InputOutput 262",
        "purchasers_to_basic_price_bridge",
        length(purchasers_to_basic.values) == 68 &&
            all(isfinite, purchasers_to_basic.values) &&
            all(>(0), purchasers_to_basic.values) ?
            "DUBIOUS" : "REJECTED";
        observed = "68 finite positive ratios; range $(extrema(purchasers_to_basic.values))",
        expected = "Arithmetic T013/T016 diagnostic by modeled commodity, with 441+445+452+4A0 aggregated before the 4A0 ratio",
        detail = "The quotient is not a use-cell margin/tax allocator. Scientific status $(purchasers_to_basic.scientific_status); runtime status $(purchasers_to_basic.runtime_status).",
    )

    official_export_control = io_get(use_values, "T005", "F040")
    excluded_exports = sum(
        io_get(use_values, commodity_code, "F040")
            for commodity_code in excluded_commodity_codes
    )
    export_control_error = sum(exports) + excluded_exports - official_export_control
    record_source_check!(
        state,
        "BEA",
        "InputOutput 259",
        "exports_structural_control",
        abs(export_control_error) <= 2.0 && all(exports .>= 0) ?
            "APPROVED" : "REJECTED";
        observed = "68-sector \$$(sum(exports))m + excluded Other/Used \$$(excluded_exports)m = \$$(sum(exports) + excluded_exports)m",
        expected = "T005/F040 \$$(official_export_control)m (error \$$(export_control_error)m)",
        detail = "The model retains the 68 observed commodities; noncomparable and used-goods exports remain outside the model vector but are included in this control reconciliation.",
    )

    import_control_error = sum(imports) + excluded_imports - official_import_control
    record_source_check!(
        state,
        "BEA",
        "InputOutput 262",
        "imports_structural_control",
        abs(import_control_error) <= 2.0 &&
            all(isfinite, imports) && all(imports .>= 0) ?
            "APPROVED" : "REJECTED";
        observed = "68-sector \$$(sum(imports))m + excluded Other/Used \$$(excluded_imports)m = \$$(sum(imports) + excluded_imports)m",
        expected = "T017/(MCIF+MADJ) \$$(official_import_control)m (error \$$(import_control_error)m)",
        detail = "$(import_adjustment.negative_count) negative commodity MCIF+MADJ entries (total \$$(import_adjustment.negative_adjustment)m) were floored at zero; positive entries were scaled by $(import_adjustment.scale) to preserve the T017 control net of Other/Used. The raw 68-row sum differed from that control by \$$(import_adjustment.raw_sum - import_adjustment.raw_control)m due to published rounding.",
    )

    cells = DataFrame(
        year = Int[],
        matrix_version = String[],
        commodity_code = String[],
        industry_code = String[],
        value_millions_usd = Float64[],
        status = String[],
        note = String[],
    )
    for (version, matrix, status, note) in (
            ("observed_aggregated", observed, "APPROVED", "Sparse absent cells materialized as zero; retail industries aggregated."),
            ("model_bridged", bridged, "DUBIOUS", "Each industry column scaled to the published T005 control."),
        )
        for (row_index, commodity_code) in enumerate(model_codes)
            for (column_index, industry_code) in enumerate(model_codes)
                push!(
                    cells,
                    (
                        year = STRUCTURAL_YEAR,
                        matrix_version = version,
                        commodity_code = commodity_code,
                        industry_code = industry_code,
                        value_millions_usd = matrix[row_index, column_index],
                        status = status,
                        note = note,
                    ),
                )
            end
        end
    end
    raw_cells = DataFrame(
        year = Int[],
        commodity_code = String[],
        industry_code = String[],
        value_millions_usd = Float64[],
    )
    for commodity_code in model_codes, industry_code in source_industry_codes
        push!(
            raw_cells,
            (
                year = STRUCTURAL_YEAR,
                commodity_code = commodity_code,
                industry_code = industry_code,
                value_millions_usd = io_get(use_values, commodity_code, industry_code),
            ),
        )
    end

    state.tables["model_codes"] = model_codes
    state.tables["bea259_long"] = use_frame
    state.tables["bea262_long"] = supply_frame
    state.tables["io_cells"] = cells
    state.tables["io_raw_68x71"] = raw_cells
    state.tables["io_observed"] = observed
    state.tables["io_bridged"] = bridged
    state.tables["io_bridge_factor"] = bridge_factor
    state.tables["io_output_control"] = output_control
    state.tables["supply_make_report"] = supply_make_report
    state.tables["symmetric_use_report"] = symmetric_use_report
    state.tables["requirements_report"] = requirements_report
    state.tables["requirements_transaction_report"] =
        requirements_transaction_report
    state.tables["requirements_comparison_report"] =
        requirements_comparison_report
    state.tables["domestic_commodity_output_basic_price"] =
        domestic_commodity_output_basic_price
    state.tables["source_industry_output_basic_price"] =
        source_industry_output_basic_price
    state.tables["supply_industry_output_basic_price_t017"] =
        supply_industry_output_basic_price_t017
    state.tables["commodity_output_codes"] = copy(model_codes)
    state.tables["industry_output_codes"] = copy(model_codes)
    state.tables["io_closure_accounts"] = closure_accounts
    state.tables["compensation_employees"] = compensation
    state.tables["operating_surplus"] = operating_surplus
    state.tables["taxes_production"] = production_taxes
    state.tables["taxes_products_observed"] = product_taxes
    state.tables["taxes_products_reported_industry"] =
        reported_industry_product_taxes
    state.tables["taxes_products_inventory"] = taxes_products_inventory
    state.tables["household_consumption"] = household_consumption
    state.tables["fixed_capitalformation"] = fixed_capitalformation
    state.tables["government_consumption"] = government_consumption
    state.tables["exports"] = exports
    state.tables["imports_raw_mcif_madj"] = raw_imports
    state.tables["imports"] = imports
    state.tables["purchasers_to_basic_price"] =
        purchasers_to_basic.values
    state.tables["valuation_bridge_scientific_status"] =
        purchasers_to_basic.scientific_status
    state.tables["valuation_bridge_runtime_status"] =
        purchasers_to_basic.runtime_status
    state.tables["taxes_products_household"] = taxes_products_household
    state.tables["taxes_products_capitalformation"] = taxes_products_capitalformation
    state.tables["taxes_products_government"] = taxes_products_government
    state.tables["gross_capitalformation_dwellings"] = gross_capitalformation_dwellings

    for (parameter, status, detail) in (
            ("intermediate_consumption", "DUBIOUS", "68×68 column-controlled model bridge; approved raw source retained."),
            ("household_consumption", "APPROVED", "Table 259 F010."),
            ("fixed_capitalformation", "APPROVED", "Table 259 private fixed-investment uses F02E+F02N+F02R+F02S, excluding inventories."),
            ("exports", "APPROVED", "Table 259 F040."),
            ("compensation_employees", "APPROVED", "Table 259 V001."),
            ("operating_surplus", "APPROVED", "Table 259 V003."),
            ("government_consumption", "APPROVED", "Table 259 federal and state/local consumption plus gross-investment uses F06*/F07*/F10*, matching broad NIPA government demand."),
            ("taxes_production", "APPROVED", "Table 259 T00OTOP−T00OSUB."),
            ("taxes_products", "DUBIOUS", "Table 262 commodity tax valuation bridge allocated to intermediate industries; current model intentionally sets it to zero."),
            ("taxes_products_household", "DUBIOUS", "Table 262 commodity tax valuation bridge allocated to F010."),
            ("taxes_products_capitalformation", "DUBIOUS", "Table 262 commodity tax valuation bridge allocated to fixed-investment uses."),
            ("taxes_products_government", "DUBIOUS", "Table 262 commodity tax valuation bridge allocated to government-consumption uses."),
            ("gross_capitalformation_dwellings", "DUBIOUS", "Table 259 F02R plus the Table 262 valuation-bridge product tax."),
        )
        record_parameter_check!(
            state,
            parameter,
            "BEA InputOutput 259",
            status;
            frequency = "A",
            unit = "millions USD",
            shape = parameter in (
                    "intermediate_consumption",
                ) ? "68×68×1" :
                parameter in (
                    "taxes_products_household",
                    "taxes_products_capitalformation",
                    "taxes_products_government",
                    "gross_capitalformation_dwellings",
                ) ? "1" : "68×1",
            check_id = "source_mapping",
            detail = detail,
        )
    end
    record_parameter_check!(
        state,
        "imports",
        "BEA InputOutput 262",
        "REJECTED";
        frequency = "A",
        unit = "millions USD",
        shape = "68×1",
        check_id = "source_mapping",
        source_control_reconciles = "APPROVED",
        model_mapping_admissible = "REJECTED",
        detail = "The raw signed Table 262 MCIF+MADJ rows and the T017 control are retained and reconcile after the documented control adjustment. The legacy nonnegative vector floors CIF/FOB adjustment entries and proportionally rescales positive rows; current accounting contracts leave the model import boundary unselected, so this construction is rejected as an admissible model mapping.",
    )
    record_parameter_check!(
        state,
        "purchasers_to_basic_price",
        "BEA InputOutput 262",
        "REJECTED";
        frequency = "A",
        unit = "basic-price supply / purchasers-price supply",
        shape = "68×1",
        check_id = "valuation_bridge",
        source_control_reconciles = "APPROVED",
        model_mapping_admissible = "REJECTED",
        detail = "The code-keyed T013/T016 arithmetic control is reproducible, including retail aggregation. It is rejected as a model mapping because no source use-cell margin/tax allocation identifies the proportional recipient rescale. The legacy research runtime still applies it pending a producer-price adapter.",
    )
    return state
end

function nipa_row(state::RunState, table_name::AbstractString, line_number::Int)
    name = String(table_name)
    key = "bea_nipa_$name"
    haskey(state.tables, key) || error("Missing BEA NIPA table $name")
    matches = [
        row for row in state.tables[key]
            if parse(Int, String(row["LineNumber"])) == line_number
    ]
    isempty(matches) && error("$name line $line_number is missing")
    return matches
end

function annual_nipa_value(state::RunState, reference::AbstractString)
    table_name, line_text = split(String(reference), ":"; limit = 2)
    matches = nipa_row(state, table_name, parse(Int, line_text))
    annual = [row for row in matches if String(row["TimePeriod"]) == string(STRUCTURAL_YEAR)]
    length(annual) == 1 ||
        error("$reference expected one $STRUCTURAL_YEAR observation; got $(length(annual))")
    value = parse_bea_number(only(annual)["DataValue"])
    value === missing && error("$reference has a missing value")
    return Float64(value), String(only(annual)["LineDescription"]), String(only(annual)["SeriesCode"])
end

function build_nipa!(state::RunState)
    lines = SOURCE_SPEC["nipa_lines"]
    extracted = Dict{String, Float64}()
    labels = Dict{String, String}()
    series_codes = Dict{String, String}()
    for (name, reference) in lines
        value, label, series_code = annual_nipa_value(state, String(reference))
        extracted[String(name)] = value
        labels[String(name)] = label
        series_codes[String(name)] = series_code
        table_name, _ = split(String(reference), ":"; limit = 2)
        push_observation!(
            state;
            source = "BEA",
            dataset = "NIPA",
            series_id = series_code,
            period = Date(STRUCTURAL_YEAR, 12, 31),
            frequency = "A",
            unit = "millions USD",
            value = value,
            raw_sha256 = state.tables["bea_nipa_$(table_name)_sha"],
            note = label,
        )
        record_source_check!(
            state,
            "BEA",
            table_name,
            "$name.line_mapping",
            isempty(label) ? "REJECTED" : "APPROVED";
            observed = "$(reference), $series_code, $label",
            expected = "Frozen line number with non-empty official label",
            detail = "2024 current-dollar annual level, UNIT_MULT=6.",
        )
    end

    values = Dict{String, Float64}(
        "property_income" => extracted["rental_income"] + extracted["personal_asset_income"],
        "mixed_income" => extracted["mixed_income"],
        "social_benefits" => extracted["social_benefits"],
        "unemployment_benefits" => extracted["unemployment_benefits"],
        "pension_benefits" => extracted["pension_benefits"],
        "corporate_tax" => extracted["corporate_tax"],
        "social_contributions" =>
            (extracted["compensation_employees"] - extracted["wages_total"]) +
            extracted["social_contributions_household"],
        "income_tax" => extracted["personal_current_taxes"] + extracted["corporate_tax"],
        "capital_taxes" =>
            extracted["federal_estate_gift_taxes"] +
            extracted["state_local_estate_gift_taxes"],
        "interest_government_debt" => extracted["government_interest"],
        "government_deficit" => -extracted["government_net_lending"],
        "firm_interest" =>
            extracted["firm_interest_corporate"] +
            extracted["firm_interest_noncorporate"],
        "wages_total" => extracted["wages_total"],
    )
    contributions_ok =
        values["social_contributions"] >=
        extracted["compensation_employees"] - extracted["wages_total"]
    record_source_check!(
        state,
        "BEA",
        "NIPA",
        "social_contribution_semantics",
        contributions_ok ? "APPROVED" : "REJECTED";
        observed = "total $(values["social_contributions"]); employer $(extracted["compensation_employees"] - extracted["wages_total"]); household $(extracted["social_contributions_household"])",
        expected = "total ≥ employer and residual household ≥ 0",
        detail = "Code-facing total matches the calibration's employer/household subtraction convention.",
    )
    values["government_deficit"] > 0 ||
        error("Government deficit sign convention must be positive for a deficit")
    state.tables["nipa_extracted"] = extracted
    state.tables["nipa_values"] = values
    state.tables["nipa_labels"] = labels

    parameter_sources = Dict(
        "property_income" => ("T20100:12+13", "DUBIOUS", "Rental-income boundary plus personal interest/dividends is explicit."),
        "mixed_income" => ("T20100:9", "APPROVED", "Proprietors' income."),
        "social_benefits" => ("T20100:17", "APPROVED", "Government social benefits to persons."),
        "unemployment_benefits" => ("T31200:7", "APPROVED", "Unemployment insurance benefits."),
        "pension_benefits" => ("T31200:5", "APPROVED", "Narrow Social Security definition."),
        "corporate_tax" => ("T30100:5", "APPROVED", "Taxes on corporate income."),
        "social_contributions" => ("T11000:2−3 + T30600:20", "APPROVED", "Employer plus employee/self-employed contributions."),
        "income_tax" => ("T30100:3+5", "APPROVED", "Personal plus corporate tax required by code."),
        "capital_taxes" => ("T51100:19+20", "APPROVED", "Federal and state/local estate and gift taxes."),
        "interest_government_debt" => ("T30100:27", "APPROVED", "Consolidated government interest paid."),
        "government_deficit" => ("−T30100:43", "APPROVED", "Positive-deficit convention."),
        "firm_interest" => ("T71100:7+8", "DUBIOUS", "Nonfinancial corporate plus noncorporate interest paid."),
    )
    for (parameter, (source, status, detail)) in parameter_sources
        record_parameter_check!(
            state,
            parameter,
            "BEA NIPA $source",
            status;
            frequency = "A",
            unit = "millions USD",
            shape = "1",
            check_id = "line_mapping",
            detail = detail,
        )
    end
    return state
end

function linked_level_backcast(
        observed_periods,
        observed_values,
        index_periods,
        index_values;
        start_period::Date,
    )
    length(observed_periods) == length(observed_values) ||
        error("Observed level periods and values do not align")
    length(index_periods) == length(index_values) ||
        error("Quantity-index periods and values do not align")
    length(unique(observed_periods)) == length(observed_periods) ||
        error("Observed level periods are not unique")
    length(unique(index_periods)) == length(index_periods) ||
        error("Quantity-index periods are not unique")
    all(isfinite, observed_values) && all(>(0), observed_values) ||
        error("Observed levels contain nonfinite or nonpositive values")
    all(isfinite, index_values) && all(>(0), index_values) ||
        error("Quantity indexes contain nonfinite or nonpositive values")

    observed = Dict(zip(Date.(observed_periods), Float64.(observed_values)))
    indexes = Dict(zip(Date.(index_periods), Float64.(index_values)))
    overlap = sort!(collect(intersect(Set(keys(observed)), Set(keys(indexes)))))
    length(overlap) >= 2 ||
        error("Level/index backcast requires at least two overlapping quarters")
    link_ratios = [observed[period] / indexes[period] for period in overlap]
    link_factor = median(link_ratios)
    overlap_relative_errors = [
        abs(link_factor * indexes[period] - observed[period]) /
            observed[period]
            for period in overlap
    ]
    max_relative_error = maximum(overlap_relative_errors)
    max_relative_error <= 5.0e-5 ||
        error(
        "Level/index overlap is not a stable link: maximum relative error $max_relative_error",
    )
    backcast_periods = sort!(
        [
            period for period in keys(indexes)
                if period >= start_period && !haskey(observed, period)
        ],
    )
    backcast_values =
        [link_factor * indexes[period] for period in backcast_periods]
    return (;
        periods = backcast_periods,
        values = backcast_values,
        link_factor,
        overlap_count = length(overlap),
        max_relative_error,
    )
end

function build_quarterly_nipa!(state::RunState)
    output = DataFrame(
        parameter = String[],
        period = Date[],
        value = Float64[],
        unit = String[],
        status = String[],
        source_series = String[],
    )
    for (parameter, reference) in SOURCE_SPEC["quarterly_nipa_lines"]
        table_name, line_text = split(String(reference), ":"; limit = 2)
        rows = nipa_row(state, table_name, parse(Int, line_text))
        rows = [row for row in rows if occursin("Q", String(row["TimePeriod"]))]
        for row in rows
            period = parse_quarter(String(row["TimePeriod"]))
            period < Date(1996, 12, 31) && continue
            value = parse_bea_number(row["DataValue"])
            value === missing && continue
            quarterly_value = Float64(value) / 4
            push!(
                output,
                (
                    parameter = String(parameter),
                    period = period,
                    value = quarterly_value,
                    unit = "millions USD per quarter",
                    status = "APPROVED",
                    source_series = String(row["SeriesCode"]),
                ),
            )
            push_observation!(
                state;
                source = "BEA",
                dataset = "NIPA",
                series_id = String(row["SeriesCode"]),
                period = period,
                frequency = "Q",
                unit = "millions USD per quarter",
                value = quarterly_value,
                raw_sha256 = state.tables["bea_nipa_$(table_name)_sha"],
                note = "Source SAAR divided by four; $(row["LineDescription"])",
            )
        end
        backcast_reference = get(
            SOURCE_SPEC["quarterly_nipa_backcasts"],
            String(parameter),
            nothing,
        )
        if backcast_reference !== nothing
            index_table, index_line_text =
                split(String(backcast_reference), ":"; limit = 2)
            index_rows = [
                row for row in
                    nipa_row(state, index_table, parse(Int, index_line_text))
                    if occursin("Q", String(row["TimePeriod"]))
            ]
            index_periods = Date[]
            index_values = Float64[]
            for row in index_rows
                value = parse_bea_number(row["DataValue"])
                value === missing && continue
                push!(index_periods, parse_quarter(String(row["TimePeriod"])))
                push!(index_values, Float64(value))
            end
            direct = output[output.parameter .== String(parameter), :]
            backcast = linked_level_backcast(
                direct.period,
                direct.value,
                index_periods,
                index_values;
                start_period = Date(1996, 12, 31),
            )
            index_series = unique(
                String(row["SeriesCode"]) for row in index_rows
            )
            length(index_series) == 1 ||
                error("$backcast_reference must resolve to one BEA series")
            direct_series = unique(direct.source_series)
            length(direct_series) == 1 ||
                error("$reference must resolve to one BEA series")
            linked_series =
                "$(only(index_series))→$(only(direct_series))"
            for (period, value) in zip(backcast.periods, backcast.values)
                push!(
                    output,
                    (
                        parameter = String(parameter),
                        period = period,
                        value = value,
                        unit = "millions USD per quarter",
                        status = "DUBIOUS",
                        source_series = linked_series,
                    ),
                )
                push_observation!(
                    state;
                    source = "BEA",
                    dataset = "NIPA linked quantity-index history",
                    series_id = linked_series,
                    period = period,
                    frequency = "Q",
                    unit = "millions USD per quarter",
                    value = value,
                    status = "DUBIOUS",
                    raw_sha256 =
                        state.tables["bea_nipa_$(index_table)_sha"],
                    note = "Official $index_table quantity index linked to $table_name chained-dollar levels over $(backcast.overlap_count) overlapping quarters.",
                )
            end
            record_source_check!(
                state,
                "BEA",
                "$index_table+$table_name",
                "$(parameter).quantity_index_backcast",
                isempty(backcast.periods) ? "REJECTED" : "APPROVED";
                observed = "$(length(backcast.periods)) linked quarters; factor $(backcast.link_factor); maximum overlap relative error $(backcast.max_relative_error)",
                expected = "Complete 1996Q4–2006Q4 history with a stable T10103/T10106 overlap link",
                detail = "Published T10106 chained-dollar levels are retained exactly from 2007Q1 onward. Earlier levels use the official T10103 quantity index and a robust median link over every published overlap quarter.",
            )
        end
        parameter_frame = output[output.parameter .== String(parameter), :]
        unique_ok = nrow(unique(parameter_frame, :period)) == nrow(parameter_frame)
        record_source_check!(
            state,
            "BEA",
            table_name,
            "$(parameter).quarterly_panel",
            unique_ok && nrow(parameter_frame) >= 118 ? "APPROVED" : "REJECTED";
            observed = "$(nrow(parameter_frame)) unique quarter rows, $(minimum(parameter_frame.period))–$(maximum(parameter_frame.period))",
            expected = "At least 118 unique quarters from 1996Q4",
            detail = "SAAR flow levels divided by four exactly once.",
        )
        record_parameter_check!(
            state,
            String(parameter),
            backcast_reference === nothing ?
                "BEA NIPA $reference" :
                "BEA NIPA $reference with $backcast_reference quantity-index history",
            backcast_reference === nothing ? "APPROVED" : "DUBIOUS";
            frequency = "Q",
            unit = "millions USD per quarter",
            shape = "$(nrow(parameter_frame))",
            check_id = "saar_conversion",
            detail = backcast_reference === nothing ?
                "Official quarterly SAAR flow divided by four; stock series are handled separately." :
                "Official quarterly SAAR levels divided by four where published; the pre-2007 history is linked from the official quantity index because T10106 exposes chained-dollar fixed-investment levels only from 2007Q1.",
        )
    end
    sort!(output, [:parameter, :period])
    state.tables["quarterly_nipa"] = output
    return state
end

function observation_map(state::RunState, series_id::String)
    selected = state.observations[
        (state.observations.source .== "FRED") .&
            (state.observations.series_id .== series_id) .&
            .!ismissing.(state.observations.value),
        :,
    ]
    return Dict(quarter_of(row.period) => Float64(row.value) for row in eachrow(selected))
end

function build_financial_quarterly!(state::RunState)
    output = DataFrame(
        parameter = String[],
        period = Date[],
        value = Float64[],
        unit = String[],
        status = String[],
        source_series = String[],
    )
    parameter_names = Dict(
        "household_cash" => "household_cash_quarterly",
        "firm_cash" => "firm_cash_quarterly",
        "firm_debt" => "firm_debt_quarterly",
        "government_debt" => "government_debt_quarterly",
        "bank_equity" => "bank_equity_quarterly",
    )
    for (registry_name, parameter) in parameter_names
        spec = SOURCE_SPEC["fred_series"][registry_name]
        series_ids = String.(spec["series"])
        maps = [observation_map(state, series_id) for series_id in series_ids]
        periods = sort!(collect(reduce(intersect, Set.(keys.(maps)))))
        operation = String(spec["operation"])
        for period in periods
            components = [mapping[period] for mapping in maps]
            value = if operation == "sum"
                sum(components)
            elseif operation == "difference"
                components[1] - components[2]
            elseif operation == "identity"
                only(components)
            else
                error("Unsupported FRED registry operation $operation")
            end
            push!(
                output,
                (
                    parameter = parameter,
                    period = period,
                    value = value,
                    unit = "millions USD",
                    status = "APPROVED",
                    source_series = join(series_ids, operation == "sum" ? "+" : operation == "difference" ? "−" : ""),
                ),
            )
        end
        metadata_ok = all(series_ids) do series_id
            metadata = state.tables["fred_metadata"][series_id]
            String(metadata["frequency_short"]) == "Q" &&
                String(metadata["seasonal_adjustment_short"]) == "NSA" &&
                occursin("Millions", String(metadata["units"])) &&
                occursin("Level", String(metadata["title"]))
        end
        parameter_frame = output[output.parameter .== parameter, :]
        complete = nrow(parameter_frame) == 118 &&
            minimum(parameter_frame.period) == Date(1996, 12, 31) &&
            maximum(parameter_frame.period) == Date(2026, 3, 31)
        record_source_check!(
            state,
            "FRED",
            join(series_ids, "+"),
            "$parameter.stock_metadata",
            metadata_ok && complete ? "APPROVED" : "REJECTED";
            observed = "$(nrow(parameter_frame)) quarters, $(minimum(parameter_frame.period))–$(maximum(parameter_frame.period)); NSA level",
            expected = "118 complete quarter-end NSA level observations in millions USD",
            detail = "End-of-period stocks are never divided by four.",
        )
        record_parameter_check!(
            state,
            parameter,
            "Federal Reserve Financial Accounts via FRED $(join(series_ids, operation == "difference" ? "−" : "+"))",
            metadata_ok && complete ? "APPROVED" : "REJECTED";
            frequency = "Q",
            unit = "millions USD",
            shape = "$(nrow(parameter_frame))",
            check_id = "stock_panel",
            detail = String(spec["concept"]),
        )
    end
    all(output.value .> 0) || error("A financial stock construction is non-positive")
    sort!(output, [:parameter, :period])
    state.tables["financial_quarterly"] = output
    return state
end

function bls_annual_value(state::RunState, series_id::String, source_year::Int)
    rows = state.tables["bls_rows"][series_id]
    matches = [
        row for row in rows
            if String(row["year"]) == string(source_year) &&
            String(row["period"]) == "M13"
    ]
    if length(matches) == 1
        value = parse_bea_number(only(matches)["value"])
        value === missing && error("BLS M13 $series_id $source_year is missing")
        return Float64(value)
    end
    monthly = Float64[]
    for row in rows
        String(row["year"]) == string(source_year) || continue
        period = String(row["period"])
        occursin(r"^M(0[1-9]|1[0-2])$", period) || continue
        value = parse_bea_number(row["value"])
        value === missing || push!(monthly, Float64(value))
    end
    length(monthly) == 12 ||
        error("Expected M13 or twelve complete BLS months for $series_id in $source_year")
    return mean(monthly)
end

function build_labor_controls!(state::RunState)
    series = Dict{String, String}(
        string(name) => String(value) for (name, value) in SOURCE_SPEC["bls_series"]
    )
    annual = Dict(
        "population" => 1000 * bls_annual_value(state, series["population"], STRUCTURAL_YEAR),
        "employees_total" => 1000 * bls_annual_value(state, series["employed"], STRUCTURAL_YEAR),
        "unemployed_census" => 1000 * bls_annual_value(state, series["unemployed"], STRUCTURAL_YEAR),
        "inactive_census" => 1000 * bls_annual_value(state, series["inactive"], STRUCTURAL_YEAR),
        "labor_force" => 1000 * bls_annual_value(state, series["labor_force"], STRUCTURAL_YEAR),
    )
    identity_error =
        annual["population"] -
        annual["employees_total"] -
        annual["unemployed_census"] -
        annual["inactive_census"]
    identity_ok = abs(identity_error) <= 10_000
    record_source_check!(
        state,
        "BLS",
        "CPS",
        "2024_annual_person_identity",
        identity_ok ? "APPROVED" : "REJECTED";
        observed = "population−employed−unemployed−inactive = $(identity_error) persons",
        expected = "within 10,000 persons (published-thousands rounding)",
        detail = "NSA M13 annual averages; people, not payroll jobs.",
    )
    for parameter in ("population", "unemployed_census", "inactive_census")
        record_parameter_check!(
            state,
            parameter,
            "BLS CPS NSA annual average",
            "APPROVED";
            frequency = "A",
            unit = "persons",
            shape = "1",
            check_id = "annual_person_control",
            detail = "2024 M13 when exposed, otherwise the mean of twelve complete official monthly NSA observations; converted from thousands to persons.",
        )
    end

    rate_id = series["unemployment_rate"]
    selected = state.observations[
        (state.observations.source .== "BLS") .&
            (state.observations.series_id .== rate_id) .&
            .!ismissing.(state.observations.value),
        [:period, :value, :status],
    ]
    selected.value = Float64.(selected.value)
    october = Date(2025, 10, 31)
    if !(october in selected.period)
        september_index = findfirst(==(Date(2025, 9, 30)), selected.period)
        november_index = findfirst(==(Date(2025, 11, 30)), selected.period)
        (september_index === nothing || november_index === nothing) &&
            error("Cannot construct explicit October 2025 CPS interpolation")
        imputed = (selected.value[september_index] + selected.value[november_index]) / 2
        push!(
            selected,
            (period = october, value = imputed, status = "DUBIOUS"),
        )
        push_observation!(
            state;
            source = "BLS",
            dataset = "CPS explicit model bridge",
            series_id = rate_id,
            period = october,
            frequency = "M",
            unit = "Percent",
            value = imputed,
            status = "DUBIOUS",
            note = "October 2025 CPS was not collected; explicit midpoint of September and November for model continuity.",
        )
        record_source_check!(
            state,
            "BLS",
            "CPS",
            "2025_october_shutdown_gap",
            "DUBIOUS";
            observed = "No official October 2025 CPS observation; imputed $imputed%",
            expected = "Explicit, visible bridge if a complete model panel is required",
            detail = "Midpoint of September and November. The source observation remains missing; no official 2025Q4 estimate is claimed.",
        )
    end
    selected.quarter = quarter_of.(selected.period)
    quarterly = combine(
        groupby(selected, :quarter),
        :value => mean => :value,
        :period => length => :month_count,
        :status => (values -> any(==("DUBIOUS"), values) ? "DUBIOUS" : "APPROVED") => :status,
    )
    quarterly = quarterly[quarterly.month_count .== 3, :]
    sort!(quarterly, :quarter)
    quarterly.value ./= 100
    state.tables["unemployment_quarterly"] = quarterly
    state.tables["labor_annual"] = annual
    record_parameter_check!(
        state,
        "unemployment_rate_quarterly",
        "BLS CPS LNS14000000",
        "DUBIOUS";
        frequency = "Q",
        unit = "fraction",
        shape = "$(nrow(quarterly))",
        check_id = "monthly_to_quarterly",
        detail = "Quarterly means of SA monthly rates; 2025Q4 includes the explicitly flagged October shutdown interpolation.",
    )
    return state
end

function build_policy_rate!(state::RunState)
    series_id = only(String.(SOURCE_SPEC["fred_series"]["policy_rate"]["series"]))
    selected = state.observations[
        (state.observations.source .== "FRED") .&
            (state.observations.series_id .== series_id) .&
            .!ismissing.(state.observations.value),
        [:period, :value],
    ]
    selected.value = Float64.(selected.value)
    selected.quarter = quarter_of.(selected.period)
    quarterly = combine(
        groupby(selected, :quarter),
        :value => mean => :value,
        :period => length => :month_count,
    )
    quarterly = quarterly[quarterly.month_count .== 3, :]
    quarterly.value ./= 100
    sort!(quarterly, :quarter)
    state.tables["policy_rate_quarterly"] = quarterly
    metadata = state.tables["fred_metadata"][series_id]
    metadata_ok =
        metadata["frequency_short"] == "M" &&
        metadata["units"] == "Percent"
    record_parameter_check!(
        state,
        "euribor",
        "FRED FEDFUNDS",
        metadata_ok ? "APPROVED" : "REJECTED";
        frequency = "Q",
        unit = "annual decimal rate",
        shape = "$(nrow(quarterly))",
        check_id = "semantic_adapter",
        detail = "Field name is retained at the model boundary; values are quarterly means of the effective federal funds rate divided by 100.",
    )
    return state
end

function build_nominal_wages!(state::RunState)
    series_id = only(String.(SOURCE_SPEC["fred_series"]["wages"]["series"]))
    selected = state.observations[
        (state.observations.source .== "FRED") .&
            (state.observations.series_id .== series_id) .&
            .!ismissing.(state.observations.value),
        [:period, :value],
    ]
    selected.value = Float64.(selected.value)
    selected.quarter = quarter_of.(selected.period)
    quarterly = combine(
        groupby(selected, :quarter),
        :value => mean => :value,
        :period => length => :month_count,
    )
    quarterly = quarterly[quarterly.month_count .== 3, :]
    quarterly.value .*= 1000 / 4
    sort!(quarterly, :quarter)
    all(isfinite, quarterly.value) && all(>(0), quarterly.value) ||
        error("Quarterly nominal wages contain nonfinite or nonpositive values")
    state.tables["nominal_wages_quarterly"] = quarterly

    metadata = state.tables["fred_metadata"][series_id]
    metadata_ok =
        String(metadata["frequency_short"]) == "M" &&
        String(metadata["units"]) == "Billions of Dollars" &&
        String(metadata["seasonal_adjustment_short"]) == "SAAR"
    complete =
        nrow(quarterly) >= 119 &&
        minimum(quarterly.quarter) == Date(1996, 12, 31) &&
        maximum(quarterly.quarter) >= ECONOMIC_OUTLOOK_ACTUAL_END
    record_source_check!(
        state,
        "FRED",
        series_id,
        "monthly_saar_to_quarterly_flow",
        metadata_ok && complete ? "APPROVED" : "REJECTED";
        observed = "$(nrow(quarterly)) complete quarters, $(minimum(quarterly.quarter))–$(maximum(quarterly.quarter)); monthly SAAR billions",
        expected = "At least 119 complete quarters from 1996Q4 through 2026Q2",
        detail = "Monthly SAAR levels are averaged within each calendar quarter, converted from billions to millions, then divided by four.",
    )
    record_parameter_check!(
        state,
        "nominal_wages_quarterly",
        "BEA Personal Income and Outlays via FRED $series_id",
        metadata_ok && complete ? "APPROVED" : "REJECTED";
        frequency = "Q",
        unit = "millions USD per quarter",
        shape = "$(nrow(quarterly))",
        check_id = "monthly_saar_conversion",
        detail = "Quarterly mean of three monthly SAAR wage-and-salary disbursement levels, multiplied by 1,000 and divided by four.",
    )
    return state
end

function build_quarterly_panel!(state::RunState)
    build_quarterly_nipa!(state)
    build_financial_quarterly!(state)
    build_labor_controls!(state)
    build_policy_rate!(state)
    build_nominal_wages!(state)
    nipa = state.tables["quarterly_nipa"]
    unemployment = state.tables["unemployment_quarterly"]
    rate = state.tables["policy_rate_quarterly"]
    wages = state.tables["nominal_wages_quarterly"]
    parameters = sort!(unique(nipa.parameter))
    period_sets = [Set(nipa[nipa.parameter .== parameter, :period]) for parameter in parameters]
    push!(period_sets, Set(unemployment.quarter))
    push!(period_sets, Set(rate.quarter))
    push!(period_sets, Set(wages.quarter))
    periods = sort!(collect(reduce(intersect, period_sets)))
    periods = [period for period in periods if period >= Date(1996, 12, 31)]
    panel = DataFrame(period = periods)
    for parameter in parameters
        mapping = Dict(
            row.period => row.value
                for row in eachrow(nipa[nipa.parameter .== parameter, :])
        )
        panel[!, Symbol(parameter)] = [mapping[period] for period in periods]
    end
    unemployment_map = Dict(row.quarter => row.value for row in eachrow(unemployment))
    rate_map = Dict(row.quarter => row.value for row in eachrow(rate))
    wages_map = Dict(row.quarter => row.value for row in eachrow(wages))
    panel.unemployment_rate_quarterly = [unemployment_map[period] for period in periods]
    panel.euribor = [rate_map[period] for period in periods]
    panel.nominal_wages_quarterly = [wages_map[period] for period in periods]
    panel.gdp_deflator_quarterly =
        panel.nominal_gdp_quarterly ./ panel.real_gdp_quarterly
    all(isfinite, panel.gdp_deflator_quarterly) &&
        all(>(0), panel.gdp_deflator_quarterly) ||
        error("GDP deflator ratio contains nonfinite or nonpositive values")
    state.tables["quarterly_panel"] = panel
    record_source_check!(
        state,
        "Curated",
        "quarterly_panel",
        "complete_intersection",
        nrow(panel) >= 119 &&
            minimum(panel.period) == Date(1996, 12, 31) ?
            "APPROVED" : "REJECTED";
        observed = "$(nrow(panel)) complete quarters, $(minimum(panel.period))–$(maximum(panel.period))",
        expected = "119 quarters from 1996Q4 through at least 2026Q2",
        detail = "BEA flows, FRED/BEA nominal wages, CPS unemployment and effective federal funds rate. The GDP deflator is nominal GDP divided by real GDP, matching the web output definition.",
    )
    record_parameter_check!(
        state,
        "gdp_deflator_quarterly",
        "Derived from BEA NIPA T10105:1 / T10106:1",
        "APPROVED";
        frequency = "Q",
        unit = "nominal-to-real GDP ratio",
        shape = "$(nrow(panel))",
        check_id = "derived_identity",
        detail = "Nominal GDP divided by real GDP without multiplying by 100, matching the web Economic outlook ratio.",
    )
    return state
end

function sql_identifier(name::String)
    occursin(r"^[a-z][a-z0-9_]*$", name) ||
        error("Unsafe SQL identifier $name")
    return name
end

function replace_table!(connection, name::String, frame::DataFrame)
    table_name = sql_identifier(name)
    registration = "incoming_$table_name"
    DuckDB.register_data_frame(connection, frame, registration)
    try
        DuckDB.DBInterface.execute(
            connection,
            "CREATE OR REPLACE TABLE $table_name AS SELECT * FROM $registration",
        )
    finally
        try
            DuckDB.unregister_data_frame(connection, registration)
        catch
            nothing
        end
    end
    return name
end

function persist_database!(state::RunState)
    ensure_directories!()
    database = DuckDB.DB(DATABASE_PATH)
    connection = DuckDB.DBInterface.connect(database)
    frames = Dict{String, DataFrame}(
        "acquisitions" => state.acquisitions,
        "source_checks" => state.source_checks,
        "parameter_checks" => state.parameter_checks,
        "observations" => state.observations,
        "test_events" => state.test_events,
    )
    optional_frames = Dict(
        "bea259_cells" => "bea259_long",
        "bea262_cells" => "bea262_long",
        "io_cells" => "io_cells",
        "io_raw_68x71" => "io_raw_68x71",
        "quarterly_nipa" => "quarterly_nipa",
        "financial_quarterly" => "financial_quarterly",
        "quarterly_panel" => "quarterly_panel",
        "unemployment_quarterly" => "unemployment_quarterly",
        "sector_annual" => "sector_annual",
        "calibration_quarterly" => "calibration_quarterly",
        "simulation_checks" => "simulation_checks",
    )
    for (table_name, state_key) in optional_frames
        haskey(state.tables, state_key) || continue
        value = state.tables[state_key]
        value isa DataFrame || continue
        frames[table_name] = value
    end
    snapshot_root = joinpath(CURATED_ROOT, "vintage=$(DATA_TRUTH_VINTAGE)")
    mkpath(snapshot_root)
    try
        for (table_name, frame) in frames
            replace_table!(connection, table_name, frame)
            parquet_path = joinpath(snapshot_root, "$table_name.parquet")
            escaped_path = replace(parquet_path, "'" => "''")
            DuckDB.DBInterface.execute(
                connection,
                "COPY $table_name TO '$escaped_path' (FORMAT PARQUET, COMPRESSION ZSTD)",
            )
        end
        DuckDB.DBInterface.execute(
            connection,
            """
            CREATE OR REPLACE VIEW qa_status_summary AS
            SELECT 'source' AS scope, status, count(*) AS checks
            FROM source_checks GROUP BY status
            UNION ALL
            SELECT 'parameter' AS scope, status, count(*) AS checks
            FROM parameter_checks GROUP BY status
            UNION ALL
            SELECT 'test' AS scope, status, count(*) AS checks
            FROM test_events GROUP BY status
            """,
        )
    finally
        close(connection)
        close(database)
    end
    return DATABASE_PATH
end

markdown_escape(value) = replace(
    replace(
        replace(string(value), "|" => "\\|"),
        "\n" => " ",
    ),
    "\r" => " ",
)

const STATUS_RANK = Dict(
    "APPROVED" => 1,
    "DUBIOUS" => 2,
    "MISSING" => 3,
    "REJECTED" => 4,
)

function worst_status(values)
    isempty(values) && return "MISSING"
    return argmax(status -> STATUS_RANK[status], String.(values))
end

function parameter_ledger(state::RunState)
    required = [
        "years_num",
        "quarters_num",
        "household_cash_quarterly",
        "property_income",
        "mixed_income",
        "firm_cash_quarterly",
        "firm_debt_quarterly",
        "firm_debt_consolidation_ratio_quarterly",
        "firm_interest",
        "government_debt_quarterly",
        "interest_government_debt",
        "social_benefits",
        "unemployment_benefits",
        "pension_benefits",
        "corporate_tax",
        "wages_by_sector",
        "social_contributions",
        "income_tax",
        "capital_taxes",
        "bank_equity_quarterly",
        "government_deficit",
        "firms",
        "employees",
        "population",
        "fixed_assets",
        "dwellings",
        "capital_consumption",
        "gross_capitalformation_dwellings",
        "unemployed_census",
        "inactive_census",
        "intermediate_consumption",
        "household_consumption",
        "fixed_capitalformation",
        "exports",
        "imports",
        "purchasers_to_basic_price",
        "compensation_employees",
        "operating_surplus",
        "government_consumption",
        "taxes_products_household",
        "taxes_products_capitalformation",
        "taxes_production",
        "taxes_products_government",
        "taxes_products",
        "nominal_gdp_quarterly",
        "real_gdp_quarterly",
        "real_household_consumption_quarterly",
        "real_fixed_capitalformation_quarterly",
        "nominal_wages_quarterly",
        "gdp_deflator_quarterly",
        "unemployment_rate_quarterly",
        "euribor",
        "real_government_consumption_quarterly",
        "real_exports_quarterly",
        "real_imports_quarterly",
        "ea.nominal_gdp_quarterly",
        "ea.real_gdp_quarterly",
    ]
    ledger = DataFrame(
        parameter = String[],
        status = String[],
        source_control_reconciles = String[],
        model_mapping_admissible = String[],
        sources = String[],
        frequency = String[],
        unit = String[],
        shape = String[],
        detail = String[],
    )
    for parameter in required
        matches = state.parameter_checks[state.parameter_checks.parameter .== parameter, :]
        if nrow(matches) == 0
            push!(
                ledger,
                (
                    parameter = parameter,
                    status = "MISSING",
                    source_control_reconciles = "MISSING",
                    model_mapping_admissible = "MISSING",
                    sources = "",
                    frequency = "",
                    unit = "",
                    shape = "",
                    detail = "No validated construction has been registered.",
                ),
            )
            continue
        end
        push!(
            ledger,
            (
                parameter = parameter,
                status = worst_status(matches.status),
                source_control_reconciles =
                    worst_status(matches.source_control_reconciles),
                model_mapping_admissible =
                    worst_status(matches.model_mapping_admissible),
                sources = join(sort!(unique(matches.source)), "; "),
                frequency = join(sort!(unique(filter(value -> !isempty(value), matches.frequency))), "; "),
                unit = join(sort!(unique(filter(value -> !isempty(value), matches.unit))), "; "),
                shape = join(sort!(unique(filter(value -> !isempty(value), matches.shape))), "; "),
                detail = join(unique(matches.detail), " "),
            ),
        )
    end
    return ledger
end

function economic_outlook_actuals_frame(panel::DataFrame)
    selected = panel[
        (panel.period .>= ECONOMIC_OUTLOOK_ACTUAL_START) .&
            (panel.period .<= ECONOMIC_OUTLOOK_ACTUAL_END),
        :,
    ]
    sort!(selected, :period)
    expected_periods = collect(
        ECONOMIC_OUTLOOK_ACTUAL_START:Month(3):ECONOMIC_OUTLOOK_ACTUAL_END,
    )
    selected.period == expected_periods ||
        error(
        "quarterly_panel must contain exactly the frozen economic-outlook truth window $(ECONOMIC_OUTLOOK_ACTUAL_START)–$(ECONOMIC_OUTLOOK_ACTUAL_END)",
    )
    source_ids = join(
        [
            "nominal_gdp=$(SOURCE_SPEC["quarterly_nipa_lines"]["nominal_gdp_quarterly"])",
            "real_gdp=$(SOURCE_SPEC["quarterly_nipa_lines"]["real_gdp_quarterly"])",
            "real_household_consumption=$(SOURCE_SPEC["quarterly_nipa_lines"]["real_household_consumption_quarterly"])",
            "real_government_consumption=$(SOURCE_SPEC["quarterly_nipa_lines"]["real_government_consumption_quarterly"])",
            "real_fixed_capitalformation=$(SOURCE_SPEC["quarterly_nipa_lines"]["real_fixed_capitalformation_quarterly"])",
            "real_exports=$(SOURCE_SPEC["quarterly_nipa_lines"]["real_exports_quarterly"])",
            "real_imports=$(SOURCE_SPEC["quarterly_nipa_lines"]["real_imports_quarterly"])",
        ],
        "; ",
    )
    return DataFrame(
        period = selected.period,
        nominal_gdp = selected.nominal_gdp_quarterly,
        real_gdp = selected.real_gdp_quarterly,
        gdp_deflator = selected.gdp_deflator_quarterly,
        real_household_consumption =
            selected.real_household_consumption_quarterly,
        real_government_consumption =
            selected.real_government_consumption_quarterly,
        real_fixed_capitalformation =
            selected.real_fixed_capitalformation_quarterly,
        real_exports = selected.real_exports_quarterly,
        real_imports = selected.real_imports_quarterly,
        wages = selected.nominal_wages_quarterly,
        annual_policy_rate = selected.euribor,
        data_truth_vintage =
            fill(string(DATA_TRUTH_VINTAGE), nrow(selected)),
        real_flow_unit =
            fill("millions of chained dollars per quarter (BEA SAAR divided by 4)", nrow(selected)),
        nominal_flow_unit =
            fill("millions of current dollars per quarter", nrow(selected)),
        gdp_deflator_unit =
            fill("nominal GDP / real GDP ratio", nrow(selected)),
        annual_policy_rate_unit =
            fill("annual decimal rate (quarterly mean)", nrow(selected)),
        bea_source_ids = fill(source_ids, nrow(selected)),
        wage_source_id = fill("FRED:A576RC1 (BEA)", nrow(selected)),
        policy_rate_source_id = fill("FRED:FEDFUNDS", nrow(selected)),
    )
end

function write_economic_outlook_actuals!(state::RunState)
    haskey(state.tables, "quarterly_panel") ||
        error("quarterly_panel is required for the economic-outlook truth snapshot")
    snapshot = economic_outlook_actuals_frame(state.tables["quarterly_panel"])
    path = joinpath(VALIDATION_ROOT, "ECONOMIC_OUTLOOK_ACTUALS.csv")
    CSV.write(path, snapshot)
    state.artifacts["economic_outlook_actuals_path"] = path
    return path
end

function write_validation_log!(state::RunState)
    ensure_directories!()
    haskey(state.tables, "quarterly_panel") &&
        write_economic_outlook_actuals!(state)
    ledger = parameter_ledger(state)
    state.tables["parameter_ledger"] = ledger
    checklist_path = joinpath(VALIDATION_ROOT, "DATA_CHECKLIST.md")
    open(checklist_path, "w") do io
        println(io, "# U.S. calibration data checklist")
        println(io)
        println(io, "Generated: `$(now(UTC))`")
        println(io, "Structural reference: `2024Q4`; nowcast: `2026Q1`; economic-outlook truth vintage: `$(DATA_TRUTH_VINTAGE)`; model system: `BEA 68 observed commodity sectors`.")
        println(io)
        println(io, "Overall status is fail-closed across two separate questions: `source_control_reconciles` records whether the retained source/control arithmetic passes, while `model_mapping_admissible` records whether that evidence supports writing the parameter into model state. **APPROVED** passes the stated question; **DUBIOUS** requires the stated sensitivity or unresolved bridge; **REJECTED** is scientifically or mechanically ineligible; **MISSING** has no validated construction.")
        println(io)
        counts = combine(groupby(ledger, :status), nrow => :parameters)
        println(io, "## Parameter coverage")
        println(io)
        println(io, "| Status | Parameters |")
        println(io, "|---|---:|")
        for row in eachrow(sort(counts, :status))
            println(io, "| $(row.status) | $(row.parameters) |")
        end
        println(io)
        println(io, "| Parameter | Overall status | `source_control_reconciles` | `model_mapping_admissible` | Frequency | Unit | Shape | Source(s) | Test note |")
        println(io, "|---|---|---|---|---|---|---:|---|---|")
        for row in eachrow(ledger)
            println(
                io,
                "| $(markdown_escape(row.parameter)) | $(row.status) | $(row.source_control_reconciles) | $(row.model_mapping_admissible) | $(markdown_escape(row.frequency)) | $(markdown_escape(row.unit)) | $(markdown_escape(row.shape)) | $(markdown_escape(row.sources)) | $(markdown_escape(row.detail)) |",
            )
        end
        println(io)
        println(io, "## Source checks")
        println(io)
        println(io, "| Source | Dataset | Check | Status | Observed | Expected | Detail |")
        println(io, "|---|---|---|---|---|---|---|")
        for row in eachrow(state.source_checks)
            println(
                io,
                "| $(markdown_escape(row.source)) | $(markdown_escape(row.dataset)) | $(markdown_escape(row.check_id)) | $(row.status) | $(markdown_escape(row.observed)) | $(markdown_escape(row.expected)) | $(markdown_escape(row.detail)) |",
            )
        end
    end

    test_log_path = joinpath(VALIDATION_ROOT, "TEST_LOG.md")
    open(test_log_path, "w") do io
        println(io, "# U.S. calibration test log")
        println(io)
        println(io, "Generated: `$(now(UTC))`")
        println(io)
        println(io, "## Executed stages")
        println(io)
        println(io, "| Stage | Test | Status | Seconds | Detail |")
        println(io, "|---|---|---|---:|---|")
        for row in eachrow(state.test_events)
            println(
                io,
                "| $(markdown_escape(row.stage)) | $(markdown_escape(row.test_id)) | $(row.status) | $(round(row.elapsed_seconds; digits = 3)) | $(markdown_escape(row.detail)) |",
            )
        end
        println(io)
        println(io, "## Acquisition ledger")
        println(io)
        println(io, "| Source | Dataset | Request | HTTP | Status | Bytes | SHA-256 | Raw path | Detail |")
        println(io, "|---|---|---|---:|---|---:|---|---|---|")
        for row in eachrow(state.acquisitions)
            println(
                io,
                "| $(markdown_escape(row.source)) | $(markdown_escape(row.dataset)) | $(markdown_escape(row.request_id)) | $(row.http_status) | $(row.status) | $(row.byte_count) | `$(row.raw_sha256)` | `$(markdown_escape(row.raw_path))` | $(markdown_escape(row.detail)) |",
            )
        end
        println(io)
        println(io, "## Parameter tests")
        println(io)
        println(io, "| Parameter | Check | Overall status | `source_control_reconciles` | `model_mapping_admissible` | Shape | Detail |")
        println(io, "|---|---|---|---|---|---:|---|")
        for row in eachrow(state.parameter_checks)
            println(
                io,
                "| $(markdown_escape(row.parameter)) | $(markdown_escape(row.check_id)) | $(row.status) | $(row.source_control_reconciles) | $(row.model_mapping_admissible) | $(markdown_escape(row.shape)) | $(markdown_escape(row.detail)) |",
            )
        end
    end

    machine_path = joinpath(VALIDATION_ROOT, "validation.toml")
    machine = Dict{String, Any}(
        "generated_at" => string(now(UTC)),
        "country" => "US",
        "data_truth_vintage" => string(DATA_TRUTH_VINTAGE),
        "economic_outlook_actual_start" =>
            string(ECONOMIC_OUTLOOK_ACTUAL_START),
        "economic_outlook_actual_end" =>
            string(ECONOMIC_OUTLOOK_ACTUAL_END),
        "structural_period" => "2024Q4",
        "nowcast_period" => "2026Q1",
        "sector_count" => 68,
        "model_sector_system" => "BEA summary, retail aggregated to observed 68-commodity topology",
        "database" => relpath(DATABASE_PATH, REPO_ROOT),
        "parameter_counts" => Dict(
            row.status => row.parameters for row in eachrow(combine(groupby(ledger, :status), nrow => :parameters))
        ),
        "source_check_counts" => Dict(
            row.status => row.checks for row in eachrow(combine(groupby(state.source_checks, :status), nrow => :checks))
        ),
        "parameters" => [
            Dict(
                    "name" => row.parameter,
                    "status" => row.status,
                    "source_control_reconciles" =>
                    row.source_control_reconciles,
                    "model_mapping_admissible" =>
                    row.model_mapping_admissible,
                    "source" => row.sources,
                    "frequency" => row.frequency,
                    "unit" => row.unit,
                    "shape" => row.shape,
                    "detail" => row.detail,
                ) for row in eachrow(ledger)
        ],
    )
    open(machine_path, "w") do io
        TOML.print(io, machine; sorted = true)
    end
    return (checklist_path, test_log_path, machine_path)
end

function status!()
    validation_path = joinpath(VALIDATION_ROOT, "validation.toml")
    if !isfile(validation_path)
        println("No U.S. validation ledger exists. Run `all` first.")
        return nothing
    end
    validation = TOML.parsefile(validation_path)
    println("U.S. calibration status")
    println("  structural: ", validation["structural_period"])
    println("  nowcast:    ", validation["nowcast_period"])
    println("  sectors:    ", validation["sector_count"])
    for (status, count) in sort!(collect(validation["parameter_counts"]); by = first)
        println("  ", rpad(status, 9), count)
    end
    println("  checklist:  ", joinpath(VALIDATION_ROOT, "DATA_CHECKLIST.md"))
    println("  database:   ", DATABASE_PATH)
    return validation
end

function parameter_series(frame::DataFrame, parameter::String)
    selected = frame[frame.parameter .== parameter, :]
    sort!(selected, :period)
    return selected
end

function align_quarterly_panel(panel::DataFrame, target_periods)
    :period in propertynames(panel) ||
        error("Quarterly panel has no period column")
    panel_periods = Date.(panel.period)
    targets = Date.(target_periods)
    length(unique(panel_periods)) == length(panel_periods) ||
        error("Quarterly panel contains duplicate periods")
    length(unique(targets)) == length(targets) ||
        error("Target quarterly axis contains duplicate periods")
    row_by_period = Dict(period => index for (index, period) in pairs(panel_periods))
    missing_periods = [period for period in targets if !haskey(row_by_period, period)]
    isempty(missing_periods) ||
        error(
        "Quarterly panel does not cover the target axis; missing periods: " *
            join(string.(missing_periods), ", "),
    )
    aligned = panel[[row_by_period[period] for period in targets], :]
    Date.(aligned.period) == targets ||
        error("Quarterly panel alignment did not preserve the target period order")
    return aligned
end

function output_measurement_specifications()
    real_flow_basis =
        "Official BEA quarterly SAAR divided by four; the origin level anchors the reported series while subsequent changes follow model growth."
    return (
        (
            name = "real_gdp",
            panel_column = :real_gdp_quarterly,
            model_field = :real_gdp,
            unit = "millions of chained dollars per quarter",
            source = "BEA NIPA $(SOURCE_SPEC["quarterly_nipa_lines"]["real_gdp_quarterly"])",
            basis = real_flow_basis,
        ),
        (
            name = "real_household_consumption",
            panel_column = :real_household_consumption_quarterly,
            model_field = :real_household_consumption,
            unit = "millions of chained dollars per quarter",
            source = "BEA NIPA $(SOURCE_SPEC["quarterly_nipa_lines"]["real_household_consumption_quarterly"])",
            basis = real_flow_basis,
        ),
        (
            name = "real_government_consumption",
            panel_column = :real_government_consumption_quarterly,
            model_field = :real_government_consumption,
            unit = "millions of chained dollars per quarter",
            source = "BEA NIPA $(SOURCE_SPEC["quarterly_nipa_lines"]["real_government_consumption_quarterly"])",
            basis = real_flow_basis,
        ),
        (
            name = "real_fixed_capitalformation",
            panel_column = :real_fixed_capitalformation_quarterly,
            model_field = :real_fixed_capitalformation,
            unit = "millions of chained dollars per quarter",
            source = "BEA NIPA $(SOURCE_SPEC["quarterly_nipa_lines"]["real_fixed_capitalformation_quarterly"])",
            basis = real_flow_basis,
        ),
        (
            name = "real_exports",
            panel_column = :real_exports_quarterly,
            model_field = :real_exports,
            unit = "millions of chained dollars per quarter",
            source = "BEA NIPA $(SOURCE_SPEC["quarterly_nipa_lines"]["real_exports_quarterly"])",
            basis = real_flow_basis,
        ),
        (
            name = "real_imports",
            panel_column = :real_imports_quarterly,
            model_field = :real_imports,
            unit = "millions of chained dollars per quarter",
            source = "BEA NIPA $(SOURCE_SPEC["quarterly_nipa_lines"]["real_imports_quarterly"])",
            basis = real_flow_basis,
        ),
        (
            name = "wages",
            panel_column = :nominal_wages_quarterly,
            model_field = :wages,
            unit = "millions of current dollars per quarter",
            source = "BEA Personal Income and Outlays via FRED A576RC1",
            basis =
                "Official monthly SAAR levels averaged within quarter, converted from billions to millions and divided by four; the origin level anchors the reported series while subsequent changes follow model growth.",
        ),
    )
end

function output_measurement_metadata(
        panel::DataFrame,
        calibration_date::DateTime,
        period::String,
        parameters::Dict{String, Any},
        initial_conditions::Dict{String, Any};
        seed::Int = RUN_SEED,
    )
    origin_date = Date(calibration_date)
    origin_rows = findall(==(origin_date), panel.period)
    length(origin_rows) == 1 ||
        error("Output-measurement origin $origin_date must appear exactly once in quarterly_panel")
    origin_row = only(origin_rows)

    Random.seed!(seed)
    model = Bit.Model(deepcopy(parameters), deepcopy(initial_conditions))
    specifications = output_measurement_specifications()
    series = Dict{String, Any}()
    for specification in specifications
        actual_value = Float64(panel[origin_row, specification.panel_column])
        raw_model_value = Float64(first(getproperty(model.data, specification.model_field)))
        isfinite(actual_value) && actual_value > 0 ||
            error("$(specification.name) actual origin value is not finite and positive")
        isfinite(raw_model_value) && raw_model_value > 0 ||
            error("$(specification.name) raw model origin value is not finite and positive")
        entry = Dict{String, Any}(
            "scale" => actual_value / raw_model_value,
            "actual_value" => actual_value,
            "raw_model_value" => raw_model_value,
            "unit" => specification.unit,
            "source" => specification.source,
            "basis" => specification.basis,
        )
        series[specification.name] = entry
    end
    return Dict{String, Any}(
        "schema_version" => "beforeit-output-measurement.v1",
        "method" => "origin_level_times_model_growth",
        "origin_period" => period,
        "data_truth_vintage" => string(DATA_TRUTH_VINTAGE),
        "series" => series,
    )
end

function opening_macro_reconciliation_metadata(
        parameters::Dict{String, Any},
        initial_conditions::Dict{String, Any};
        seed::Int = RUN_SEED,
    )
    controls =
        Bit.validated_opening_macro_controls(initial_conditions)
    controls === nothing &&
        error("Opening macro reconciliation requires source controls")
    Random.seed!(seed)
    model = Bit.Model(
        deepcopy(parameters),
        deepcopy(initial_conditions),
    )
    implied = Bit.model_implied_opening_macro(model)
    source_values = Dict{String, Float64}(
        "nominal_gdp" => controls.nominal_gdp,
        "nominal_household_consumption" =>
            controls.nominal_household_consumption,
        "nominal_government_consumption_and_investment" =>
            controls.nominal_government_consumption_and_investment,
        "nominal_capitalformation" =>
            controls.nominal_capitalformation,
        "nominal_fixed_capitalformation" =>
            controls.nominal_fixed_capitalformation,
        "nominal_inventory_investment" =>
            controls.nominal_inventory_investment,
        "nominal_exports" => controls.nominal_exports,
        "nominal_imports" => controls.nominal_imports,
    )
    implied_values = Dict{String, Float64}(
        "nominal_gdp" => implied.nominal_gdp,
        "nominal_household_consumption" =>
            implied.nominal_household_consumption,
        "nominal_government_consumption_and_investment" =>
            implied.nominal_government_consumption,
        "nominal_capitalformation" =>
            implied.nominal_capitalformation,
        "nominal_fixed_capitalformation" =>
            implied.nominal_fixed_capitalformation,
        "nominal_inventory_investment" =>
            implied.nominal_capitalformation -
            implied.nominal_fixed_capitalformation,
        "nominal_exports" => implied.nominal_exports,
        "nominal_imports" => implied.nominal_imports,
    )
    observed_values = Dict{String, Float64}(
        "nominal_gdp" => first(model.data.nominal_gdp),
        "nominal_household_consumption" =>
            first(model.data.nominal_household_consumption),
        "nominal_government_consumption_and_investment" =>
            first(model.data.nominal_government_consumption),
        "nominal_capitalformation" =>
            first(model.data.nominal_capitalformation),
        "nominal_fixed_capitalformation" =>
            first(model.data.nominal_fixed_capitalformation),
        "nominal_inventory_investment" =>
            first(model.data.nominal_inventory_investment),
        "nominal_exports" => first(model.data.nominal_exports),
        "nominal_imports" => first(model.data.nominal_imports),
    )
    model_minus_source = Dict(
        key => implied_values[key] - source_values[key]
            for key in sort!(collect(keys(source_values)))
    )
    observed_minus_source = Dict(
        key => observed_values[key] - source_values[key]
            for key in sort!(collect(keys(source_values)))
    )
    maximum_component_gap =
        maximum(abs, values(model_minus_source))
    maximum_observation_gap =
        maximum(abs, values(observed_minus_source))
    observed_residuals =
        Bit.get_accounting_residuals(model.data)
    observed_expenditure_residual =
        first(observed_residuals.gdp_and_expenditure)
    observed_private_investment_residual =
        observed_values["nominal_capitalformation"] -
        observed_values["nominal_fixed_capitalformation"] -
        observed_values["nominal_inventory_investment"]
    observation_layer_gate =
        maximum_observation_gap <= MODEL_ACCOUNTING_TOLERANCE &&
        abs(observed_expenditure_residual) <= controls.tolerance &&
        abs(observed_private_investment_residual) <= controls.tolerance
    observation_layer_gate ||
        error("Opening observation row does not match its source controls")
    latent_state_gate =
        maximum_component_gap <= MODEL_ACCOUNTING_TOLERANCE &&
        abs(implied.expenditure_residual) <=
        MODEL_ACCOUNTING_TOLERANCE
    return Dict{String, Any}(
        "schema_version" =>
            "beforeit-opening-macro-reconciliation.v1",
        "diagnostic_seed" => seed,
        "source" => controls.source,
        "unit" => controls.unit,
        "source_rounding_tolerance" => controls.tolerance,
        "model_numeric_tolerance" => MODEL_ACCOUNTING_TOLERANCE,
        "observation_layer_gate" => "PASS",
        "latent_state_reconciliation_gate" =>
            latent_state_gate ? "PASS" : "FAIL",
        "structural_supply_use_gate" => "FAIL_UNRECONCILED",
        "full_accounting_gate" => "FAIL",
        "source_values" => source_values,
        "observed_values" => observed_values,
        "model_implied_values" => implied_values,
        "observed_minus_source" => observed_minus_source,
        "model_minus_source" => model_minus_source,
        "source_expenditure_residual" =>
            controls.expenditure_residual,
        "source_private_investment_residual" =>
            controls.investment_residual,
        "observed_expenditure_residual" =>
            observed_expenditure_residual,
        "observed_private_investment_residual" =>
            observed_private_investment_residual,
        "model_implied_expenditure_residual" =>
            implied.expenditure_residual,
        "maximum_absolute_observation_gap" =>
            maximum_observation_gap,
        "maximum_absolute_component_gap" =>
            maximum_component_gap,
        "inventory_stock_status" =>
            "MISSING_INDEPENDENT_QUARTER_END_STOCK",
        "note" =>
            "The observed first row is source-anchored. This diagnostic " *
            "preserves the unreconciled model-implied state/demand wedge; " *
            "observation anchoring alone cannot promote the artifact.",
    )
end

function calibration_metadata(state::RunState, period::String, kind::String)
    return Dict{String, Any}(
        "schema_version" => 1,
        "country" => "US",
        "period" => period,
        "kind" => kind,
        "data_truth_vintage" => string(DATA_TRUTH_VINTAGE),
        "created_at" => string(now(UTC)),
        "beforeit_version" => "0.6.0",
        "structural_reference_year" => 2024,
        "sector_count" => 68,
        "sector_system" => "BEA summary, 68 observed commodities; retail industries aggregated to 4A0",
        "scale" => Float64(SOURCE_SPEC["pipeline"]["scale"]),
        "database" => relpath(DATABASE_PATH, REPO_ROOT),
        "validation_checklist" => relpath(joinpath(VALIDATION_ROOT, "DATA_CHECKLIST.md"), REPO_ROOT),
        "input_sha256" => sort!(unique(state.acquisitions.raw_sha256)),
        "accounting_adapter" => Dict(
            "schema_version" =>
                "beforeit-us-source-aware-output.v1-diagnostic",
            "industry_output_basis" =>
                "BEA_TABLE_259_T018_INDUSTRY_BASIC_PRICE",
            "commodity_output_basis" =>
                "BEA_TABLE_262_T007_COMMODITY_BASIC_PRICE",
            "commodity_output_use" =>
                "signed_unreconciled_commodity_gap_diagnostic_only",
            "opening_inventory_source" => "absent",
            "discrepancy_derived_opening_inventory" => false,
            "closure_applied" => false,
            "opening_macro_control_source" =>
                OPENING_MACRO_CONTROL_SOURCE,
            "opening_macro_control_gate" => "PASS_AT_SOURCE_ROUNDING",
            "forecast_promotion_status" =>
                "BLOCKED_ACCOUNTING_AND_INVENTORY_GATES",
        ),
        "measurement_status" => Dict(
            "production_network" =>
                "DUBIOUS model bridge: official BEA Table 259 sparse core is column-scaled to T005; raw and observed aggregation retained",
            "commodity_output" =>
                "APPROVED diagnostic input: BEA Table 262 T007, code-keyed and separate from industry output; no balance adjustment",
            "opening_inventory" =>
                "MISSING: unreconciled commodity gap is retained but is not converted into S_s",
            "annual_structure" => "official 2024 BEA/BLS with documented Census/USDA proxies",
            "financial_stocks" => "official NSA Federal Reserve Financial Accounts through 2026Q1",
            "cps_2025q4" =>
                "DUBIOUS: October 2025 was not collected; explicit September/November midpoint used only for continuous regression input",
            "sector_product_taxes" =>
                "DUBIOUS model limitation: observed series retained in curated data, then zeroed by current calibration code",
        ),
    )
end

function build_calibration_object!(state::RunState)
    for required in (
            "sector_annual",
            "financial_quarterly",
            "quarterly_panel",
            "nipa_values",
            "model_codes",
            "domestic_commodity_output_basic_price",
            "source_industry_output_basic_price",
            "supply_industry_output_basic_price_t017",
            "commodity_output_codes",
            "industry_output_codes",
        )
        haskey(state.tables, required) || error("Build stage is missing $required")
    end
    sectors = state.tables["sector_annual"]
    model_codes = state.tables["model_codes"]
    sectors.code == model_codes ||
        error("sector_annual ordering does not match the BEA model code ordering")
    financial = state.tables["financial_quarterly"]
    stock_parameters = [
        "household_cash_quarterly",
        "firm_cash_quarterly",
        "firm_debt_quarterly",
        "government_debt_quarterly",
        "bank_equity_quarterly",
    ]
    stock_frames = [parameter_series(financial, parameter) for parameter in stock_parameters]
    stock_periods = stock_frames[1].period
    all(frame -> frame.period == stock_periods, stock_frames) ||
        error("Financial stock panels do not share one quarter axis")
    nipa = state.tables["nipa_values"]
    labor = state.tables["labor_annual"]
    calibration = Dict{String, Any}(
        "years_num" => [Bit.date2num(DateTime(STRUCTURAL_YEAR, 12, 31))],
        "quarters_num" => Bit.date2num.(DateTime.(stock_periods)),
        "firm_debt_consolidation_ratio_quarterly" => ones(length(stock_periods)),
        "property_income" => [nipa["property_income"]],
        "mixed_income" => [nipa["mixed_income"]],
        "social_benefits" => [nipa["social_benefits"]],
        "unemployment_benefits" => [nipa["unemployment_benefits"]],
        "pension_benefits" => [nipa["pension_benefits"]],
        "corporate_tax" => [nipa["corporate_tax"]],
        "social_contributions" => [nipa["social_contributions"]],
        "income_tax" => [nipa["income_tax"]],
        "capital_taxes" => [nipa["capital_taxes"]],
        "interest_government_debt" => [nipa["interest_government_debt"]],
        "government_deficit" => [nipa["government_deficit"]],
        "firm_interest" => [nipa["firm_interest"]],
        "firms" => reshape(Float64.(sectors.firms), :, 1),
        "employees" => reshape(Float64.(sectors.employees), :, 1),
        "wages_by_sector" => reshape(Float64.(sectors.wages_millions_usd), :, 1),
        "population" => [labor["population"]],
        "unemployed_census" => [labor["unemployed_census"]],
        "inactive_census" => [labor["inactive_census"]],
        "fixed_assets" => reshape(Float64.(sectors.fixed_assets_millions_usd), :, 1),
        "dwellings" => reshape(Float64.(sectors.dwellings_millions_usd), :, 1),
        "capital_consumption" =>
            reshape(Float64.(sectors.capital_consumption_millions_usd), :, 1),
        "gross_capitalformation_dwellings" =>
            [Float64(state.tables["gross_capitalformation_dwellings"])],
    )
    for (parameter, frame) in zip(stock_parameters, stock_frames)
        calibration[parameter] = Float64.(frame.value)
    end

    figaro = Dict{String, Any}(
        "intermediate_consumption" =>
            reshape(Float64.(state.tables["io_bridged"]), 68, 68, 1),
        "household_consumption" =>
            reshape(Float64.(state.tables["household_consumption"]), 68, 1),
        "fixed_capitalformation" =>
            reshape(Float64.(state.tables["fixed_capitalformation"]), 68, 1),
        "exports" => reshape(Float64.(state.tables["exports"]), 68, 1),
        "imports" => reshape(Float64.(state.tables["imports"]), 68, 1),
        "use_explicit_trade" => true,
        "use_product_tax_netting" => true,
        "use_opening_macro_controls" => true,
        "opening_macro_control_source" =>
            OPENING_MACRO_CONTROL_SOURCE,
        "opening_macro_control_unit" =>
            Bit.OPENING_MACRO_CONTROL_UNIT,
        "opening_macro_control_absolute_tolerance" =>
            OPENING_MACRO_CONTROL_TOLERANCE,
        "use_explicit_commodity_output" => true,
        "diagnose_commodity_balance" => true,
        "use_commodity_balance_inventory" => false,
        "domestic_commodity_output_basic_price" =>
            reshape(
            Float64.(
                state.tables[
                    "domestic_commodity_output_basic_price",
                ],
            ),
            68,
            1,
        ),
        "commodity_output_codes" =>
            String.(state.tables["commodity_output_codes"]),
        "commodity_output_basis" =>
            "BEA_TABLE_262_T007_COMMODITY_BASIC_PRICE",
        "industry_output_codes" =>
            String.(state.tables["industry_output_codes"]),
        "industry_output_basis" =>
            "BEA_TABLE_259_T018_INDUSTRY_BASIC_PRICE",
        "source_industry_output_basic_price" =>
            reshape(
            Float64.(state.tables["source_industry_output_basic_price"]),
            68,
            1,
        ),
        "supply_industry_output_basis" =>
            "BEA_TABLE_262_T017_INDUSTRY_BASIC_PRICE",
        "supply_industry_output_basic_price_t017" =>
            reshape(
            Float64.(
                state.tables[
                    "supply_industry_output_basic_price_t017",
                ],
            ),
            68,
            1,
        ),
        "purchasers_to_basic_price" =>
            reshape(
            Float64.(state.tables["purchasers_to_basic_price"]),
            68,
            1,
        ),
        "valuation_bridge_scientific_status" =>
            String(state.tables["valuation_bridge_scientific_status"]),
        "valuation_bridge_runtime_status" =>
            String(state.tables["valuation_bridge_runtime_status"]),
        "compensation_employees" =>
            reshape(Float64.(state.tables["compensation_employees"]), 68, 1),
        "operating_surplus" =>
            reshape(Float64.(state.tables["operating_surplus"]), 68, 1),
        "government_consumption" =>
            reshape(Float64.(state.tables["government_consumption"]), 68, 1),
        "taxes_products_household" =>
            [Float64(state.tables["taxes_products_household"])],
        "taxes_products_capitalformation" =>
            [Float64(state.tables["taxes_products_capitalformation"])],
        "taxes_production" =>
            reshape(Float64.(state.tables["taxes_production"]), 68, 1),
        "taxes_products_government" =>
            [Float64(state.tables["taxes_products_government"])],
        "taxes_products" =>
            reshape(Float64.(state.tables["taxes_products_observed"]), 68, 1),
    )
    panel = state.tables["quarterly_panel"]
    data = Dict{String, Any}(
        "quarters_num" => Bit.date2num.(DateTime.(panel.period)),
        "nominal_gdp_quarterly" => Float64.(panel.nominal_gdp_quarterly),
        "nominal_household_consumption_quarterly" =>
            Float64.(panel.nominal_household_consumption_quarterly),
        "nominal_gross_private_domestic_investment_quarterly" =>
            Float64.(
            panel.nominal_gross_private_domestic_investment_quarterly,
        ),
        "nominal_fixed_investment_quarterly" =>
            Float64.(panel.nominal_fixed_investment_quarterly),
        "nominal_inventory_investment_quarterly" =>
            Float64.(panel.nominal_inventory_investment_quarterly),
        "nominal_exports_quarterly" =>
            Float64.(panel.nominal_exports_quarterly),
        "nominal_imports_quarterly" =>
            Float64.(panel.nominal_imports_quarterly),
        "nominal_government_consumption_and_investment_quarterly" =>
            Float64.(
            panel.nominal_government_consumption_and_investment_quarterly,
        ),
        "real_gdp_quarterly" => Float64.(panel.real_gdp_quarterly),
        "real_household_consumption_quarterly" =>
            Float64.(panel.real_household_consumption_quarterly),
        "real_fixed_capitalformation_quarterly" =>
            Float64.(panel.real_fixed_capitalformation_quarterly),
        "nominal_wages_quarterly" =>
            Float64.(panel.nominal_wages_quarterly),
        "gdp_deflator_quarterly" =>
            Float64.(panel.gdp_deflator_quarterly),
        "unemployment_rate_quarterly" =>
            Float64.(panel.unemployment_rate_quarterly),
        "euribor" => Float64.(panel.euribor),
        "real_government_consumption_quarterly" =>
            Float64.(panel.real_government_consumption_quarterly),
        "real_exports_quarterly" => Float64.(panel.real_exports_quarterly),
        "real_imports_quarterly" => Float64.(panel.real_imports_quarterly),
    )
    ea = Dict{String, Any}(
        "quarters_num" => copy(data["quarters_num"]),
        "nominal_gdp_quarterly" => copy(data["nominal_gdp_quarterly"]),
        "real_gdp_quarterly" => copy(data["real_gdp_quarterly"]),
    )
    object = Bit.CalibrationData(
        calibration,
        figaro,
        data,
        ea,
        DateTime(2024, 12, 31),
        DateTime(1997, 3, 31),
    )
    state.artifacts["calibration_object"] = object
    stock_panel = align_quarterly_panel(panel, stock_periods)
    state.tables["calibration_quarterly"] = DataFrame(
        period = stock_periods,
        real_household_consumption_millions_chained_usd =
            Float64.(stock_panel.real_household_consumption_quarterly),
        real_fixed_capitalformation_millions_chained_usd =
            Float64.(stock_panel.real_fixed_capitalformation_quarterly),
        nominal_wages_millions_usd =
            Float64.(stock_panel.nominal_wages_quarterly),
        gdp_deflator_ratio =
            Float64.(stock_panel.gdp_deflator_quarterly),
        household_cash_millions_usd =
            parameter_series(financial, "household_cash_quarterly").value,
        firm_cash_millions_usd =
            parameter_series(financial, "firm_cash_quarterly").value,
        firm_debt_millions_usd =
            parameter_series(financial, "firm_debt_quarterly").value,
        government_debt_millions_usd =
            parameter_series(financial, "government_debt_quarterly").value,
        bank_equity_millions_usd =
            parameter_series(financial, "bank_equity_quarterly").value,
    )
    for (parameter, frequency, unit, shape, detail) in (
            ("years_num", "A", "MATLAB date number", "1", "2024 year-end structural axis."),
            ("quarters_num", "Q", "MATLAB date number", "$(length(stock_periods))", "Financial-stock quarter axis 1996Q4–2026Q1."),
            ("firm_debt_consolidation_ratio_quarterly", "Q", "ratio", "$(length(stock_periods))", "Set to 1 pending a documented consolidated/nonconsolidated bridge."),
            ("ea.nominal_gdp_quarterly", "Q", "millions USD per quarter", "$(nrow(panel))", "U.S. GDP repeated for the U.S. monetary-policy block."),
            ("ea.real_gdp_quarterly", "Q", "millions chained USD per quarter", "$(nrow(panel))", "U.S. real GDP repeated for the U.S. monetary-policy block."),
        )
        record_parameter_check!(
            state,
            parameter,
            parameter == "firm_debt_consolidation_ratio_quarterly" ?
                "Model assumption" : "Curated U.S. adapter",
            parameter == "firm_debt_consolidation_ratio_quarterly" ?
                "DUBIOUS" : "APPROVED";
            frequency = frequency,
            unit = unit,
            shape = shape,
            check_id = "model_contract",
            detail = detail,
        )
    end
    return object
end

function all_finite(value)
    if value isa Number
        return isfinite(value)
    elseif value isa AbstractArray
        return all(item -> !(item isa Number) || isfinite(item), value)
    elseif value isa AbstractDict
        return all(all_finite, values(value))
    end
    return true
end

function build_baseline!(
        state::RunState,
        calibration_object::Bit.CalibrationData,
        calibration_date::DateTime,
        period::String,
        kind::String,
    )
    parameters, initial_conditions = Bit.get_params_and_initial_conditions(
        calibration_object,
        calibration_date;
        scale = Float64(SOURCE_SPEC["pipeline"]["scale"]),
        use_growth_rate_ar1 = false,
    )
    parameters["G"] == 68 || error("Calibrated model does not have 68 sectors")
    parameters["S"] == 68 || error("Calibrated model does not have 68 industries")
    all_finite(parameters) || error("Calibrated parameters contain nonfinite values")
    for (key, value) in initial_conditions
        if key in ("C_G", "C_E", "Y_I")
            all(isfinite, vec(value)[1:parameters["T_prime"]]) ||
                error("$key contains a nonfinite value in its observed initialization segment")
        else
            all_finite(value) ||
                error("Calibrated initial condition $key contains nonfinite values")
        end
    end
    minimum(eigvals(Symmetric(parameters["C"]))) >= -1.0e-10 ||
        error("Exogenous shock covariance is not positive semidefinite")
    opening_controls =
        Bit.validated_opening_macro_controls(initial_conditions)
    opening_controls === nothing &&
        error("U.S. baseline is missing validated opening macro controls")
    metadata = calibration_metadata(state, period, kind)
    metadata["opening_macro_controls"] = Dict{String, Any}(
        "schema_version" => "beforeit-opening-macro-controls.v1",
        "source" => opening_controls.source,
        "unit" => opening_controls.unit,
        "absolute_tolerance" => opening_controls.tolerance,
        "nominal_gdp" => opening_controls.nominal_gdp,
        "nominal_household_consumption" =>
            opening_controls.nominal_household_consumption,
        "nominal_government_consumption_and_investment" =>
            opening_controls.nominal_government_consumption_and_investment,
        "nominal_gross_private_domestic_investment" =>
            opening_controls.nominal_capitalformation,
        "nominal_fixed_investment" =>
            opening_controls.nominal_fixed_capitalformation,
        "nominal_inventory_investment" =>
            opening_controls.nominal_inventory_investment,
        "nominal_exports" => opening_controls.nominal_exports,
        "nominal_imports" => opening_controls.nominal_imports,
        "expenditure_residual" =>
            opening_controls.expenditure_residual,
        "private_investment_residual" =>
            opening_controls.investment_residual,
        "inventory_stock_treatment" =>
            "absent; signed inventory investment is an opening flow only",
    )
    metadata["opening_macro_reconciliation"] =
        opening_macro_reconciliation_metadata(
        parameters,
        initial_conditions;
        seed = RUN_SEED + (kind == "structural" ? 201 : 202),
    )
    metadata["calibration_firewall"] = Dict{String, Any}(
        "schema_version" => "beforeit-calibration-firewall.v1",
        "raw_parameters" => true,
        "forecast_error_fitted_parameters" => false,
        "postprocessing_embedded" => false,
        "note" =>
            "Forecast-error-fitted overrides and output corrections are separate class-H artifacts.",
    )
    metadata["output_measurement"] = output_measurement_metadata(
        state.tables["quarterly_panel"],
        calibration_date,
        period,
        parameters,
        initial_conditions;
        seed = RUN_SEED + (kind == "structural" ? 101 : 102),
    )
    object_path = joinpath(
        CALIBRATION_ROOT,
        kind == "structural" ?
            "US_2024_calibration_object.jld2" :
            "US_2026Q1_nowcast_object.jld2",
    )
    baseline_path = joinpath(
        BASELINE_ROOT,
        kind == "structural" ?
            "US_2024Q4_structural.jld2" :
            "US_2026Q1_nowcast.jld2",
    )
    mkpath(dirname(object_path))
    mkpath(dirname(baseline_path))
    jldsave(object_path; calibration_object, metadata)
    jldsave(baseline_path; parameters, initial_conditions, metadata)
    state.artifacts["$(kind)_parameters"] = parameters
    state.artifacts["$(kind)_initial_conditions"] = initial_conditions
    state.artifacts["$(kind)_metadata"] = metadata
    state.artifacts["$(kind)_baseline_path"] = baseline_path
    state.artifacts["$(kind)_calibration_path"] = object_path
    return (; parameters, initial_conditions, metadata, object_path, baseline_path)
end

function build_artifacts!(state::RunState)
    object = build_calibration_object!(state)
    structural = build_baseline!(
        state,
        object,
        DateTime(2024, 12, 31),
        "2024-Q4",
        "structural",
    )
    nowcast = build_baseline!(
        state,
        object,
        DateTime(2026, 3, 31),
        "2026-Q1",
        "nowcast",
    )
    return (; object, structural, nowcast)
end

function smoke_baseline!(
        state::RunState,
        kind::String;
        horizon::Int = kind == "structural" ? 4 : 4,
    )
    parameters = state.artifacts["$(kind)_parameters"]
    initial_conditions = state.artifacts["$(kind)_initial_conditions"]
    Random.seed!(RUN_SEED + (kind == "structural" ? 1 : 2))
    model = Bit.Model(parameters, initial_conditions)
    initial_cb, initial_bank = Bit.get_accounting_identity_banks(model)
    Bit.run!(model, horizon; parallel = false)
    final_cb, final_bank = Bit.get_accounting_identity_banks(model)
    finite_outputs = all(
        isfinite,
        vcat(
            model.data.nominal_gdp,
            model.data.real_gdp,
            model.data.nominal_gva,
            model.data.real_gva,
        ),
    )
    positive_real_gdp = all(>(0), model.data.real_gdp)
    tolerance = 1.0e-6
    banking_ok =
        maximum(abs, [initial_cb, initial_bank, final_cb, final_bank]) <= tolerance
    status = finite_outputs && positive_real_gdp && banking_ok ?
        "APPROVED" : "REJECTED"
    frame = get!(
        state.tables,
        "simulation_checks",
        DataFrame(
            baseline = String[],
            horizon_quarters = Int[],
            status = String[],
            initial_central_bank_residual = Float64[],
            initial_commercial_bank_residual = Float64[],
            final_central_bank_residual = Float64[],
            final_commercial_bank_residual = Float64[],
            finite_outputs = Bool[],
            positive_real_gdp = Bool[],
            final_real_gdp = Float64[],
        ),
    )
    push!(
        frame,
        (
            baseline = kind,
            horizon_quarters = horizon,
            status = status,
            initial_central_bank_residual = initial_cb,
            initial_commercial_bank_residual = initial_bank,
            final_central_bank_residual = final_cb,
            final_commercial_bank_residual = final_bank,
            finite_outputs = finite_outputs,
            positive_real_gdp = positive_real_gdp,
            final_real_gdp = model.data.real_gdp[end],
        ),
    )
    record_source_check!(
        state,
        "BeforeIT",
        "$kind baseline",
        "simulation_smoke_$horizon",
        status;
        observed = "finite=$finite_outputs, positive GDP=$positive_real_gdp, max bank residual=$(maximum(abs, [initial_cb, initial_bank, final_cb, final_bank]))",
        expected = "finite positive outputs and bank residuals ≤ $tolerance",
        detail = "Seed $(RUN_SEED + (kind == "structural" ? 1 : 2)); serial simulation.",
    )
    status == "APPROVED" || error("$kind model smoke test failed")
    return model
end

function smoke!(state::RunState)
    with_test_event!(state, "simulation", "structural_4q") do
        smoke_baseline!(state, "structural"; horizon = 4)
    end
    with_test_event!(state, "simulation", "nowcast_4q") do
        smoke_baseline!(state, "nowcast"; horizon = 4)
    end
    return state
end

function mapping_spec()
    isfile(MAPPING_FILE) || error("Sector mapping is missing: $MAPPING_FILE")
    mapping = TOML.parsefile(MAPPING_FILE)
    Int(mapping["model"]["sector_count"]) == 68 ||
        error("Mapping must define the observed 68-sector model")
    length(mapping["sector"]) == 68 ||
        error("Mapping must contain exactly 68 sector entries")
    return mapping
end

function qcew_sum(
        frame::DataFrame,
        naics_codes::Vector{String},
        ownership_codes::Vector{Int},
        field::Symbol,
    )
    isempty(naics_codes) && return 0.0
    total = 0.0
    for naics_code in naics_codes
        rows = frame[
            in.(frame.own_code, Ref(ownership_codes)) .&
                (String.(frame.industry_code) .== naics_code),
            :,
        ]
        isempty(rows) && error("QCEW is missing exact NAICS row $naics_code for ownership $(join(ownership_codes, ","))")
        total += sum(Float64.(rows[!, field]))
    end
    return total
end

function susb_sum(frame::DataFrame, naics_codes::Vector{String}, field::Symbol)
    isempty(naics_codes) && return 0.0
    total = 0.0
    for naics_code in naics_codes
        rows = frame[frame.naics .== naics_code, :]
        nrow(rows) == 0 && return missing
        nrow(rows) == 1 || error("SUSB expected at most one exact row for NAICS $naics_code")
        value = only(rows[!, field])
        value === missing || (total += Float64(value))
    end
    return total
end

function bounded_allocation(total::Float64, weights::Vector{Float64}, caps::Vector{Float64})
    total <= sum(caps) + 1.0e-6 ||
        error("Requested allocation $total exceeds caps $(sum(caps))")
    result = zeros(length(weights))
    active = trues(length(weights))
    remaining = total
    for _ in 1:(length(weights) + 2)
        remaining <= 1.0e-6 && break
        active_indices = findall(active)
        isempty(active_indices) && error("Bounded allocation exhausted all sectors")
        active_weights = weights[active_indices]
        if sum(active_weights) <= 0
            active_weights = caps[active_indices] - result[active_indices]
        end
        proposal = remaining .* active_weights ./ sum(active_weights)
        capacity = caps[active_indices] - result[active_indices]
        over = proposal .>= capacity .- 1.0e-9
        if !any(over)
            result[active_indices] .+= proposal
            remaining = 0.0
            break
        end
        capped_indices = active_indices[over]
        added = capacity[over]
        result[capped_indices] .+= added
        remaining -= sum(added)
        active[capped_indices] .= false
    end
    abs(sum(result) - total) <= 1.0e-4 * max(1.0, total) ||
        error("Bounded allocation did not preserve the control total")
    return result
end

function fixed_asset_value(state::RunState, table_name::String, line_number::Int)
    rows = state.tables["bea_fixed_$table_name"]
    matches = [
        row for row in rows
            if parse(Int, String(row["LineNumber"])) == line_number &&
            String(row["TimePeriod"]) == string(STRUCTURAL_YEAR)
    ]
    length(matches) == 1 ||
        error("$table_name line $line_number expected one $STRUCTURAL_YEAR value")
    value = parse_bea_number(only(matches)["DataValue"])
    value === missing && error("$table_name line $line_number is missing")
    return Float64(value), String(only(matches)["LineDescription"])
end

function build_sector_accounts!(state::RunState)
    mapping = mapping_spec()
    model_codes = String.(mapping["model"]["codes"])
    model_codes == state.tables["model_codes"] ||
        error("Mapping order differs from BEA Table 259 commodity order")
    qcew_2024 = state.tables["qcew_2024"]
    qcew_2022 = state.tables["qcew_2022"]
    susb = state.tables["susb"]
    entries = Dict(String(entry["code"]) => entry for entry in mapping["sector"])
    compensation = Float64.(state.tables["compensation_employees"])
    output_control = Float64.(state.tables["io_output_control"])
    sector_count = length(model_codes)

    raw_jobs = zeros(sector_count)
    raw_wages = zeros(sector_count)
    raw_establishments_2024 = zeros(sector_count)
    raw_establishments_2022 = zeros(sector_count)
    base_firms_2022 = zeros(sector_count)
    firms = zeros(sector_count)
    susb_proxy_codes = String[]
    government_codes = Set(["GFE", "GFGD", "GFGN", "GSLE", "GSLG"])
    for (index, code) in enumerate(model_codes)
        entry = entries[code]
        if code in government_codes || code == "HS"
            continue
        end
        qcew_codes = String.(entry["qcew_2022"])
        raw_jobs[index] = qcew_sum(qcew_2024, qcew_codes, [5], :annual_avg_emplvl)
        raw_wages[index] = qcew_sum(qcew_2024, qcew_codes, [5], :total_annual_wages)
        raw_establishments_2024[index] =
            qcew_sum(qcew_2024, qcew_codes, [5], :annual_avg_estabs)
        raw_establishments_2022[index] =
            qcew_sum(qcew_2022, qcew_codes, [5], :annual_avg_estabs)
        if code != "111CA"
            susb_codes = String.(entry["susb_2017"])
            susb_value = susb_sum(susb, susb_codes, :firms)
            if susb_value === missing
                base_firms_2022[index] = raw_establishments_2022[index]
                push!(susb_proxy_codes, code)
            else
                base_firms_2022[index] = susb_value
            end
            growth = raw_establishments_2022[index] > 0 ?
                raw_establishments_2024[index] / raw_establishments_2022[index] : 1.0
            firms[index] = base_firms_2022[index] * growth
        end
    end

    federal_indices = findall(code -> code in ("GFE", "GFGD", "GFGN"), model_codes)
    state_local_indices = findall(code -> code in ("GSLE", "GSLG"), model_codes)
    function allocate_government!(indices, ownership_codes)
        jobs = qcew_sum(qcew_2024, ["10"], ownership_codes, :annual_avg_emplvl)
        wages = qcew_sum(qcew_2024, ["10"], ownership_codes, :total_annual_wages)
        establishments =
            qcew_sum(qcew_2024, ["10"], ownership_codes, :annual_avg_estabs)
        weights = compensation[indices]
        weights ./= sum(weights)
        raw_jobs[indices] .= jobs .* weights
        raw_wages[indices] .= wages .* weights
        raw_establishments_2024[indices] .= establishments .* weights
        raw_establishments_2022[indices] .=
            qcew_sum(qcew_2022, ["10"], ownership_codes, :annual_avg_estabs) .* weights
        return firms[indices] .= raw_establishments_2024[indices]
    end
    allocate_government!(federal_indices, [1])
    allocate_government!(state_local_indices, [2, 3])
    farms_index = findfirst(==("111CA"), model_codes)
    housing_index = findfirst(==("HS"), model_codes)
    firms[farms_index] = Float64(state.tables["usda_farms"])
    base_firms_2022[farms_index] = firms[farms_index]
    firms[housing_index] = 1.0
    base_firms_2022[housing_index] = 1.0
    record_source_check!(
        state,
        "Census/BLS",
        "SUSB/QCEW",
        "susb_exclusion_proxies",
        isempty(susb_proxy_codes) ? "APPROVED" : "DUBIOUS";
        observed = isempty(susb_proxy_codes) ? "none" : join(susb_proxy_codes, ", "),
        expected = "Explicit QCEW-establishment fallback for SUSB-excluded sectors",
        detail = "Railroads, postal services, and other statutory SUSB exclusions do not have employer-enterprise rows.",
    )

    private_total_jobs = qcew_sum(qcew_2024, ["10"], [5], :annual_avg_emplvl)
    government_total_jobs = qcew_sum(qcew_2024, ["10"], [1, 2, 3], :annual_avg_emplvl)
    private_total_wages = qcew_sum(qcew_2024, ["10"], [5], :total_annual_wages)
    government_total_wages = qcew_sum(qcew_2024, ["10"], [1, 2, 3], :total_annual_wages)
    jobs_coverage = sum(raw_jobs) / (private_total_jobs + government_total_jobs)
    wages_coverage = sum(raw_wages) / (private_total_wages + government_total_wages)
    record_source_check!(
        state,
        "BLS",
        "QCEW",
        "bea68_mapping_coverage",
        min(jobs_coverage, wages_coverage) >= 0.995 ? "APPROVED" : "REJECTED";
        observed = "jobs $(round(100 * jobs_coverage; digits = 3))%; wages $(round(100 * wages_coverage; digits = 3))%",
        expected = "≥ 99.5% of national all-ownership controls",
        detail = "Exact aggregate NAICS 2022 rows; no descendant double counting.",
    )
    jobs_coverage >= 0.995 || error("QCEW job mapping coverage is below 99.5%")
    cps_total = Float64(state.tables["labor_annual"]["employees_total"])
    employees = raw_jobs .* (cps_total / sum(raw_jobs))
    wage_control = Float64(state.tables["nipa_values"]["wages_total"])
    wages = bounded_allocation(
        wage_control,
        raw_wages,
        compensation .* (1 - 1.0e-8),
    )
    all(wages .<= compensation .+ 1.0e-6) ||
        error("Sector wages exceed compensation")
    all(firms .> 0) || error("A sector firm count is non-positive")

    fixed_assets = zeros(sector_count)
    dwellings = zeros(sector_count)
    capital_consumption = zeros(sector_count)
    observed_capital_consumption = zeros(sector_count)
    asset_status = fill("APPROVED", sector_count)
    for (index, code) in enumerate(model_codes)
        lines = Int.(entries[code]["fixed_asset_lines"])
        isempty(lines) && continue
        fixed_assets[index] =
            sum(first(fixed_asset_value(state, "FAAt301ESI", line)) for line in lines)
        capital_consumption[index] =
            sum(first(fixed_asset_value(state, "FAAt304ESI", line)) for line in lines)
        observed_capital_consumption[index] = capital_consumption[index]
    end
    owner_assets, _ = fixed_asset_value(state, "FAAt501", 11)
    tenant_assets, _ = fixed_asset_value(state, "FAAt501", 12)
    owner_depreciation, _ = fixed_asset_value(state, "FAAt504", 11)
    real_estate_assets, _ = fixed_asset_value(state, "FAAt301ESI", 74)
    real_estate_depreciation, _ = fixed_asset_value(state, "FAAt304ESI", 74)
    ore_index = findfirst(==("ORE"), model_codes)
    fixed_assets[housing_index] = owner_assets
    dwellings[housing_index] = 0.999 * owner_assets
    capital_consumption[housing_index] = 0.001 * owner_depreciation
    observed_capital_consumption[housing_index] = owner_depreciation
    asset_status[housing_index] = "DUBIOUS"
    fixed_assets[ore_index] = real_estate_assets - owner_assets
    dwellings[ore_index] = tenant_assets
    capital_consumption[ore_index] =
        real_estate_depreciation - owner_depreciation
    observed_capital_consumption[ore_index] = capital_consumption[ore_index]

    government_enterprise_assets, _ = fixed_asset_value(state, "FAAt701", 79)
    federal_assets, _ = fixed_asset_value(state, "FAAt701", 21)
    federal_defense_assets, _ = fixed_asset_value(state, "FAAt701", 22)
    state_local_assets, _ = fixed_asset_value(state, "FAAt701", 55)
    government_enterprise_depreciation, _ =
        fixed_asset_value(state, "FAAt703", 79)
    federal_depreciation, _ = fixed_asset_value(state, "FAAt703", 21)
    federal_defense_depreciation, _ = fixed_asset_value(state, "FAAt703", 22)
    state_local_depreciation, _ = fixed_asset_value(state, "FAAt703", 55)
    gfe = findfirst(==("GFE"), model_codes)
    gfgd = findfirst(==("GFGD"), model_codes)
    gfgn = findfirst(==("GFGN"), model_codes)
    gsle = findfirst(==("GSLE"), model_codes)
    gslg = findfirst(==("GSLG"), model_codes)
    enterprise_weights = output_control[[gfe, gsle]]
    enterprise_weights ./= sum(enterprise_weights)
    fixed_assets[gfe] = government_enterprise_assets * enterprise_weights[1]
    fixed_assets[gsle] = government_enterprise_assets * enterprise_weights[2]
    fixed_assets[gfgd] = federal_defense_assets
    fixed_assets[gfgn] = federal_assets - federal_defense_assets - fixed_assets[gfe]
    fixed_assets[gslg] = state_local_assets - fixed_assets[gsle]
    capital_consumption[gfe] =
        government_enterprise_depreciation * enterprise_weights[1]
    capital_consumption[gsle] =
        government_enterprise_depreciation * enterprise_weights[2]
    capital_consumption[gfgd] = federal_defense_depreciation
    capital_consumption[gfgn] =
        federal_depreciation - federal_defense_depreciation -
        capital_consumption[gfe]
    capital_consumption[gslg] =
        state_local_depreciation - capital_consumption[gsle]
    observed_capital_consumption[[gfe, gfgd, gfgn, gsle, gslg]] .=
        capital_consumption[[gfe, gfgd, gfgn, gsle, gslg]]
    asset_status[[gfe, gfgd, gfgn, gsle, gslg]] .= "DUBIOUS"
    all(fixed_assets - dwellings .> 0) ||
        error("Every sector must have positive productive fixed assets")
    all(capital_consumption .>= 0) ||
        error("Sector capital consumption must be nonnegative")

    private_expected, _ = fixed_asset_value(state, "FAAt301ESI", 1)
    government_expected, _ = fixed_asset_value(state, "FAAt701", 1)
    private_indices = findall(code -> !(code in government_codes), model_codes)
    private_error = sum(fixed_assets[private_indices]) - private_expected
    government_model_indices = [gfe, gfgd, gfgn, gsle, gslg]
    government_error =
        sum(fixed_assets[government_model_indices]) - government_expected
    record_source_check!(
        state,
        "BEA",
        "FixedAssets",
        "private_and_government_stock_controls",
        max(abs(private_error), abs(government_error)) <= 2.0 ?
            "APPROVED" : "REJECTED";
        observed = "private error \$$(private_error)m; government error \$$(government_error)m",
        expected = "≤ \$2m BEA rounding",
        detail = "Private sector lines plus HS/ORE special split; government level/enterprise allocation preserves national controls.",
    )

    sector_frame = DataFrame(
        code = model_codes,
        year = fill(STRUCTURAL_YEAR, sector_count),
        firms = firms,
        firms_2022_susb = base_firms_2022,
        qcew_establishments_2024 = raw_establishments_2024,
        employees = employees,
        qcew_jobs_2024 = raw_jobs,
        wages_millions_usd = wages,
        qcew_wages_usd_2024 = raw_wages,
        compensation_millions_usd = compensation,
        fixed_assets_millions_usd = fixed_assets,
        dwellings_millions_usd = dwellings,
        capital_consumption_millions_usd = capital_consumption,
        observed_capital_consumption_millions_usd =
            observed_capital_consumption,
        count_status = fill("DUBIOUS", sector_count),
        asset_status = asset_status,
    )
    state.tables["sector_annual"] = sector_frame
    record_parameter_check!(
        state,
        "employees",
        "BLS QCEW shares rescaled to BLS CPS employed persons",
        "DUBIOUS";
        frequency = "A",
        unit = "persons",
        shape = "68×1",
        check_id = "jobs_to_people_bridge",
        detail = "QCEW payroll-job distribution scaled to the 2024 CPS employed-person annual control.",
    )
    record_parameter_check!(
        state,
        "wages_by_sector",
        "BLS QCEW wage shares controlled to BEA NIPA wages",
        "DUBIOUS";
        frequency = "A",
        unit = "millions USD",
        shape = "68×1",
        check_id = "sector_allocation",
        detail = "Constrained allocation preserves the NIPA wage total and keeps every sector below BEA compensation.",
    )
    record_parameter_check!(
        state,
        "firms",
        "Census SUSB + QCEW nowcast + USDA/government/housing proxies",
        "DUBIOUS";
        frequency = "A",
        unit = "productive units",
        shape = "68×1",
        check_id = "firm_concept_bridge",
        detail = "SUSB employer enterprises are nowcast 2022→2024 by QCEW establishments; farms and government require explicit proxies.",
    )
    for parameter in ("fixed_assets", "dwellings", "capital_consumption")
        record_parameter_check!(
            state,
            parameter,
            "BEA Fixed Assets",
            "DUBIOUS";
            frequency = "A",
            unit = "millions USD",
            shape = "68×1",
            check_id = "sector_mapping",
            detail = "Private lines reconcile exactly; government enterprises are allocated by I-O output and HS retains a 0.1% productive-capital/CFC bridge to satisfy the model denominator.",
        )
    end
    return state
end

const NIPA_NOMINAL_EXPENDITURE_KEYS = (
    "nominal_gdp_quarterly",
    "nominal_household_consumption_quarterly",
    "nominal_gross_private_domestic_investment_quarterly",
    "nominal_fixed_investment_quarterly",
    "nominal_inventory_investment_quarterly",
    "nominal_exports_quarterly",
    "nominal_imports_quarterly",
    "nominal_government_consumption_and_investment_quarterly",
)

function nipa_nominal_expenditure_residuals(data)
    for key in NIPA_NOMINAL_EXPENDITURE_KEYS
        haskey(data, key) ||
            error("National quarterly panel is missing $key")
    end
    lengths = length.(getindex.(Ref(data), NIPA_NOMINAL_EXPENDITURE_KEYS))
    all(==(first(lengths)), lengths) ||
        error("Nominal NIPA expenditure controls do not share one axis")
    return Float64.(data["nominal_gdp_quarterly"]) .-
        Float64.(data["nominal_household_consumption_quarterly"]) .-
        Float64.(
        data["nominal_gross_private_domestic_investment_quarterly"],
    ) .-
        Float64.(data["nominal_exports_quarterly"]) .+
        Float64.(data["nominal_imports_quarterly"]) .-
        Float64.(
        data[
            "nominal_government_consumption_and_investment_quarterly",
        ],
    )
end

function nipa_private_investment_residuals(data)
    for key in (
            "nominal_gross_private_domestic_investment_quarterly",
            "nominal_fixed_investment_quarterly",
            "nominal_inventory_investment_quarterly",
        )
        haskey(data, key) ||
            error("National quarterly panel is missing $key")
    end
    return Float64.(
        data["nominal_gross_private_domestic_investment_quarterly"],
    ) .-
        Float64.(data["nominal_fixed_investment_quarterly"]) .-
        Float64.(data["nominal_inventory_investment_quarterly"])
end

function validate_model_contract!(state::RunState)
    object = state.artifacts["calibration_object"]
    calibration = object.calibration
    figaro = object.figaro
    data = object.data
    length(calibration["years_num"]) == 1 ||
        error("Annual calibration axis must have one structural year")
    length(calibration["quarters_num"]) == 118 ||
        error("Financial calibration axis must have 118 quarters")
    size(figaro["intermediate_consumption"]) == (68, 68, 1) ||
        error("Intermediate-use model input must be 68×68×1")
    all(isfinite, figaro["intermediate_consumption"]) ||
        error("Intermediate-use model input contains nonfinite values")
    all(figaro["intermediate_consumption"] .>= 0) ||
        error("Intermediate-use model input contains negative values")
    size(figaro["imports"]) == (68, 1) ||
        error("Measured import input must be 68×1")
    all(isfinite, figaro["imports"]) ||
        error("Measured import input contains nonfinite values")
    all(figaro["imports"] .>= 0) ||
        error("Measured import input contains negative values")
    figaro["use_explicit_trade"] === true ||
        error("Measured trade input must explicitly opt in")
    figaro["use_opening_macro_controls"] === true ||
        error("U.S. calibration must opt into opening macro controls")
    figaro["opening_macro_control_source"] ==
        OPENING_MACRO_CONTROL_SOURCE ||
        error("U.S. opening macro controls have an unsupported source")
    figaro["opening_macro_control_unit"] ==
        Bit.OPENING_MACRO_CONTROL_UNIT ||
        error("U.S. opening macro controls have an unsupported unit")
    Float64(figaro["opening_macro_control_absolute_tolerance"]) ==
        OPENING_MACRO_CONTROL_TOLERANCE ||
        error("U.S. opening macro controls have an unsupported tolerance")
    figaro["use_explicit_commodity_output"] === true ||
        error("U.S. calibration must explicitly opt into commodity output")
    figaro["diagnose_commodity_balance"] === true ||
        error("U.S. calibration must retain the signed commodity-gap diagnostic")
    figaro["use_commodity_balance_inventory"] === false ||
        error(
        "U.S. calibration must not derive opening inventories from the commodity gap",
    )
    commodity_output =
        Bit.explicit_calibration_commodity_output(figaro, 1, 68)
    size(figaro["domestic_commodity_output_basic_price"]) == (68, 1) ||
        error("Domestic commodity output must be 68×1")
    all(isfinite, commodity_output) ||
        error("Domestic commodity output contains nonfinite values")
    all(commodity_output .>= 0) ||
        error("Domestic commodity output contains negative values")
    String.(figaro["commodity_output_codes"]) ==
        String.(figaro["industry_output_codes"]) ||
        error("Commodity and industry controls are not aligned by code")
    figaro["industry_output_basis"] ==
        "BEA_TABLE_259_T018_INDUSTRY_BASIC_PRICE" ||
        error("Industry output has an unsupported economic basis")
    size(figaro["source_industry_output_basic_price"]) == (68, 1) ||
        error("Source industry output must be 68×1")
    all(isfinite, figaro["source_industry_output_basic_price"]) ||
        error("Source industry output contains nonfinite values")
    all(figaro["source_industry_output_basic_price"] .>= 0) ||
        error("Source industry output contains negative values")
    figaro["supply_industry_output_basis"] ==
        "BEA_TABLE_262_T017_INDUSTRY_BASIC_PRICE" ||
        error("Supply-table industry output has an unsupported economic basis")
    size(figaro["supply_industry_output_basic_price_t017"]) == (68, 1) ||
        error("Supply-table industry output must be 68×1")
    all(isfinite, figaro["supply_industry_output_basic_price_t017"]) ||
        error("Supply-table industry output contains nonfinite values")
    maximum(
        abs,
        figaro["supply_industry_output_basic_price_t017"] -
            figaro["source_industry_output_basic_price"],
    ) <= 2.0 ||
        error(
        "Table 262 T017 industry output does not reconcile to Table 259 T018",
    )
    size(figaro["purchasers_to_basic_price"]) == (68, 1) ||
        error("Purchasers-to-basic-price bridge must be 68×1")
    all(isfinite, figaro["purchasers_to_basic_price"]) ||
        error("Purchasers-to-basic-price bridge contains nonfinite values")
    all(figaro["purchasers_to_basic_price"] .> 0) ||
        error("Purchasers-to-basic-price bridge must be strictly positive")
    length(data["quarters_num"]) >= 119 ||
        error("National quarterly panel is too short")
    for key in NIPA_NOMINAL_EXPENDITURE_KEYS
        haskey(data, key) ||
            error("National quarterly panel is missing $key")
        length(data[key]) == length(data["quarters_num"]) ||
            error("$key does not align with the national quarterly axis")
        all(isfinite, data[key]) ||
            error("$key contains nonfinite values")
        key == "nominal_inventory_investment_quarterly" ||
            all(>(0), data[key]) ||
            error("$key contains nonpositive values")
    end
    nipa_expenditure_residuals =
        nipa_nominal_expenditure_residuals(data)
    maximum(abs, nipa_expenditure_residuals) <= 1.0 ||
        error(
        "Nominal NIPA expenditure controls exceed the published rounding tolerance",
    )
    nipa_investment_residuals =
        nipa_private_investment_residuals(data)
    maximum(abs, nipa_investment_residuals) <= 0.5 ||
        error(
        "Gross private domestic investment does not reconcile to fixed investment plus inventory investment",
    )
    record_source_check!(
        state,
        "BEA",
        "NIPA T10105",
        "nominal_expenditure_identity",
        "APPROVED";
        observed = maximum(abs, nipa_expenditure_residuals),
        expected = "maximum absolute source-rounding residual <= 1 million USD per quarter",
        detail = "GDP, PCE, gross private domestic investment, exports, imports, and government consumption/investment are preserved as origin-level macro controls; no commodity discrepancy is relabeled as inventories.",
    )
    record_source_check!(
        state,
        "BEA",
        "NIPA T10105",
        "private_investment_identity",
        "APPROVED";
        observed = maximum(abs, nipa_investment_residuals),
        expected = "maximum absolute source-rounding residual <= 0.5 million USD per quarter",
        detail = "Gross private domestic investment equals fixed investment plus signed change in private inventories at published precision.",
    )
    for key in (
            "real_fixed_capitalformation_quarterly",
            "nominal_wages_quarterly",
            "gdp_deflator_quarterly",
        )
        haskey(data, key) ||
            error("National quarterly panel is missing $key")
        length(data[key]) == length(data["quarters_num"]) ||
            error("$key does not align with the national quarterly axis")
        all(isfinite, data[key]) && all(>(0), data[key]) ||
            error("$key contains nonfinite or nonpositive values")
    end
    data["gdp_deflator_quarterly"] ≈
        data["nominal_gdp_quarterly"] ./ data["real_gdp_quarterly"] ||
        error("GDP deflator does not equal nominal GDP divided by real GDP")

    q2024 = findfirst(
        ==(Bit.date2num(DateTime(2024, 12, 31))),
        data["quarters_num"],
    )
    q2024 === nothing && error("2024Q4 is absent from the national quarterly panel")
    taxes_capitalformation = figaro["taxes_products_capitalformation"][1]
    gross_dwellings = calibration["gross_capitalformation_dwellings"][1]
    fixed_capitalformation = figaro["fixed_capitalformation"][:, 1]
    dwelling_tax =
        gross_dwellings *
        (1 - 1 / (1 + taxes_capitalformation / sum(fixed_capitalformation)))
    annual_income_proxy =
        sum(
        figaro["compensation_employees"][:, 1] +
            figaro["operating_surplus"][:, 1] +
            figaro["taxes_production"][:, 1],
    ) +
        figaro["taxes_products_household"][1] +
        dwelling_tax +
        figaro["taxes_products_government"][1]
    timescale = data["nominal_gdp_quarterly"][q2024] / annual_income_proxy
    record_source_check!(
        state,
        "Curated",
        "model_contract",
        "quarterly_annual_timescale",
        0.2 <= timescale <= 0.3 ? "APPROVED" : "REJECTED";
        observed = timescale,
        expected = "0.20–0.30",
        detail = "Quarterly nominal GDP divided by the annual structural income-account proxy; catches accidental SAAR or stock division.",
    )

    structural_parameters = state.artifacts["structural_parameters"]
    share_keys = ["b_CF_g", "b_CFH_g", "b_HH_g", "c_G_g", "c_E_g", "c_I_g"]
    for key in share_keys
        shares = structural_parameters[key]
        all(isfinite, shares) || error("$key contains nonfinite shares")
        all(shares .>= 0) || error("$key contains negative shares")
        share_sum = sum(shares)
        abs(share_sum - 1) <= 1.0e-8 ||
            error("$key does not sum to one: $share_sum")
    end
    network_column_sums = vec(sum(structural_parameters["a_sg"]; dims = 1))
    all(value -> abs(value - 1) <= 1.0e-8, network_column_sums) ||
        error("An intermediate-input network column does not sum to one")
    rate_bounds = Dict(
        "tau_INC" => (0.0, 1.0),
        "tau_FIRM" => (0.0, 1.0),
        "tau_VAT" => (0.0, 0.5),
        "tau_SIF" => (0.0, 1.0),
        "tau_SIW" => (0.0, 1.0),
        "tau_CF" => (0.0, 0.5),
        "tau_G" => (0.0, 0.5),
    )
    for (key, (lower, upper)) in rate_bounds
        value = structural_parameters[key]
        lower <= value <= upper ||
            error("$key=$value is outside [$lower,$upper]")
    end
    covariance_minimum =
        minimum(eigvals(Symmetric(structural_parameters["C"])))
    covariance_minimum >= -1.0e-10 ||
        error("Shock covariance is not positive semidefinite")
    record_source_check!(
        state,
        "BeforeIT",
        "calibrated parameters",
        "shape_share_rate_covariance",
        "APPROVED";
        observed = "68 sectors; demand/network shares sum to one; minimum covariance eigenvalue $covariance_minimum",
        expected = "Finite shapes, normalized shares, plausible effective rates, PSD covariance",
        detail = "Both structural and nowcast artifacts passed construction-time finite-value checks.",
    )
    return timescale
end

function contains_bytes(haystack::Vector{UInt8}, needle::Vector{UInt8})
    isempty(needle) && return false
    length(needle) > length(haystack) && return false
    first_byte = first(needle)
    for start in eachindex(haystack)
        haystack[start] == first_byte || continue
        stop = start + length(needle) - 1
        stop <= length(haystack) || return false
        @views haystack[start:stop] == needle && return true
    end
    return false
end

function validate_secret_hygiene!(state::RunState)
    secrets = [
        Vector{UInt8}(codeunits(value))
            for (name, value) in state.env
            if endswith(name, "_API_KEY") && !isempty(value)
    ]
    inspected = 0
    violations = 0
    if isdir(RAW_ROOT)
        for (root, _, files) in walkdir(RAW_ROOT)
            for filename in files
                path = joinpath(root, filename)
                bytes = read(path)
                inspected += 1
                if any(secret -> contains_bytes(bytes, secret), secrets)
                    violations += 1
                end
            end
        end
    end
    record_source_check!(
        state,
        "Pipeline",
        "raw archive",
        "credential_persistence_scan",
        violations == 0 ? "APPROVED" : "REJECTED";
        observed = "$inspected files scanned; $violations credential matches",
        expected = "zero configured API-key byte sequences",
        detail = "Credential values are never printed. BEA response echoes are redacted before archival.",
    )
    violations == 0 || error("Configured API credential material was found in persisted raw data")
    return inspected
end

function build!(state::RunState)
    with_test_event!(state, "build", "input_output") do
        build_io!(state)
    end
    with_test_event!(state, "build", "annual_nipa") do
        build_nipa!(state)
    end
    with_test_event!(state, "build", "quarterly_panel") do
        build_quarterly_panel!(state)
    end
    with_test_event!(state, "build", "sector_accounts") do
        build_sector_accounts!(state)
    end
    with_test_event!(state, "build", "calibration_and_baselines") do
        build_artifacts!(state)
    end
    return state
end

function validate!(state::RunState)
    with_test_event!(state, "validate", "model_contract") do
        validate_model_contract!(state)
    end
    with_test_event!(state, "validate", "secret_hygiene") do
        validate_secret_hygiene!(state)
    end
    smoke!(state)
    ledger = parameter_ledger(state)
    unavailable = ledger[in.(ledger.status, Ref(["MISSING", "REJECTED"])), :]
    if nrow(unavailable) > 0
        error(
            "Required model parameters are not usable: " *
                join(["$(row.parameter)=$(row.status)" for row in eachrow(unavailable)], ", "),
        )
    end
    any(==("REJECTED"), state.test_events.status) &&
        error("At least one pipeline test stage was rejected")
    write_validation_log!(state)
    persist_database!(state)
    return state
end

function run_all!()
    state = collect!()
    build!(state)
    validate!(state)
    return state
end

function main(arguments = ARGS)
    command = isempty(arguments) ? "all" : lowercase(String(first(arguments)))
    if command == "all"
        state = run_all!()
        ledger = parameter_ledger(state)
        counts = combine(groupby(ledger, :status), nrow => :count)
        println("U.S. calibration pipeline completed")
        for row in eachrow(sort(counts, :status))
            println("  ", rpad(row.status, 9), row.count)
        end
        println("  structural: ", state.artifacts["structural_baseline_path"])
        println("  nowcast:    ", state.artifacts["nowcast_baseline_path"])
        println("  database:   ", DATABASE_PATH)
        println("  checklist:  ", joinpath(VALIDATION_ROOT, "DATA_CHECKLIST.md"))
        return state
    elseif command == "collect"
        state = collect!()
        collection_root = joinpath(
            RAW_ROOT,
            "pipeline",
            "vintage=$(DATA_TRUTH_VINTAGE)",
            "collection-manifest",
        )
        mkpath(collection_root)
        CSV.write(joinpath(collection_root, "acquisitions.csv"), state.acquisitions)
        CSV.write(joinpath(collection_root, "source_checks.csv"), state.source_checks)
        CSV.write(joinpath(collection_root, "test_events.csv"), state.test_events)
        println("Collected $(nrow(state.acquisitions)) public-source responses.")
        println("  manifest: $collection_root")
        return state
    elseif command == "status"
        return status!()
    elseif command == "health"
        state = RunState()
        println("BEA key configured:  ", !isempty(get(state.env, "BEA_API_KEY", "")))
        println("FRED key configured: ", !isempty(get(state.env, "FRED_API_KEY", "")))
        println("BLS key configured:  ", !isempty(get(state.env, "BLS_API_KEY", "")))
        println("Run `all` for live authenticated and anonymous endpoint tests.")
        return state
    else
        error("Unknown command '$command'. Use all, collect, status, or health.")
    end
end

end # module
