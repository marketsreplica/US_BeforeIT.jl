module BeforeITWeb

import BeforeIT as Bit

using CodecZlib
using Dates
using HTTP
using JSON3
using JLD2
using Logging
using LoggingExtras
using Random
using SHA
using Statistics
using UUIDs

const APP_ROOT = normpath(joinpath(@__DIR__, ".."))
const PUBLIC_DIR = joinpath(APP_ROOT, "public")
const PROTOTYPES_DIR = joinpath(APP_ROOT, "prototypes")
const EXPLORER_DIR = joinpath(APP_ROOT, "explorer")
const METADATA_DIR = joinpath(APP_ROOT, "metadata")
const RUNS_DIR = joinpath(APP_ROOT, "runs")
const RUN_PROVENANCE_SCHEMA_VERSION = "beforeit-run-provenance.v1"
const RUN_RNG_POLICY = Dict{String, Any}(
    "policy_id" => "julia-default-rng-reseeded-per-realization.v1",
    "initialization" =>
        "Random.seed!(base_seed + realization_index) immediately before model construction",
    "dynamics" =>
        "The model consumes Julia's implicit default RNG during initialization and simulation; mechanisms are not assigned independent streams",
    "matched_seed_schedule" => true,
    "mechanism_specific_streams" => false,
    "stream_stable_common_random_numbers" => false,
    "claim" =>
        "Runs can share realization seeds, but treatment-dependent draw consumption may diverge after their paths separate",
)
const _RUN_SOURCE_PROVENANCE_LOCK = ReentrantLock()
const _RUN_SOURCE_PROVENANCE = Ref{Any}(nothing)
const DATASET_ORDER = [
    "US2026Q1",
    "US2024Q4",
    "AUSTRIA2026Q1",
    "AUSTRIA2024Q4",
    "AUSTRIA2010Q1",
    "ITALY2010Q1",
    "STEADY_STATE2010Q1",
]
const DATASET_SPECS = Dict(
    "US2026Q1" => (
        label = "United States 2026 Q1 nowcast",
        country = "US",
        period = "2026-Q1",
        kind = "nowcast",
        structural_reference_year = 2024,
        observed_through = "2026-Q1",
        scenarios = ["unconditional"],
        default_scenario = "unconditional",
        default_horizon = 23,
        description = "Current U.S. quarterly controls through 2026 Q1 on the 2024 BEA structure.",
    ),
    "US2024Q4" => (
        label = "United States 2024 Q4 structural",
        country = "US",
        period = "2024-Q4",
        kind = "structural",
        structural_reference_year = 2024,
        observed_through = "2024-Q4",
        scenarios = ["unconditional"],
        default_scenario = "unconditional",
        default_horizon = 20,
        description = "U.S. structural calibration aligned to the 2024 BEA Input-Output accounts.",
    ),
    "AUSTRIA2026Q1" => (
        label = "Austria 2026 Q1 nowcast",
        country = "AT",
        period = "2026-Q1",
        kind = "nowcast",
        structural_reference_year = 2024,
        observed_through = "2026-Q1",
        scenarios = ["baseline", "upside", "downside", "unconditional"],
        default_scenario = "baseline",
        default_horizon = 23,
        description = "Current quarterly controls through 2026 Q1 on the 2024 FIGARO structure.",
    ),
    "AUSTRIA2024Q4" => (
        label = "Austria 2024 Q4 structural",
        country = "AT",
        period = "2024-Q4",
        kind = "structural",
        structural_reference_year = 2024,
        observed_through = "2024-Q4",
        scenarios = ["unconditional"],
        default_scenario = "unconditional",
        default_horizon = 20,
        description = "Fully aligned 2024 Q4 structural calibration using FIGARO 2024.",
    ),
    "AUSTRIA2010Q1" => (
        label = "Austria 2010 Q1 legacy",
        country = "AT",
        period = "2010-Q1",
        kind = "legacy",
        structural_reference_year = 2010,
        observed_through = "2010-Q1",
        scenarios = ["unconditional"],
        default_scenario = "unconditional",
        default_horizon = 20,
        description = "Original packaged Austrian calibration retained for replication.",
    ),
    "ITALY2010Q1" => (
        label = "Italy 2010 Q1",
        country = "IT",
        period = "2010-Q1",
        kind = "legacy",
        structural_reference_year = 2010,
        observed_through = "2010-Q1",
        scenarios = ["unconditional"],
        default_scenario = "unconditional",
        default_horizon = 20,
        description = "Original packaged Italian calibration.",
    ),
    "STEADY_STATE2010Q1" => (
        label = "Steady state 2010 Q1",
        country = "synthetic",
        period = "2010-Q1",
        kind = "synthetic",
        structural_reference_year = 2010,
        observed_through = "2010-Q1",
        scenarios = ["unconditional"],
        default_scenario = "unconditional",
        default_horizon = 20,
        description = "Synthetic steady-state calibration for model diagnostics.",
    ),
)

"""
    _run_provenance_canonical(value)

Return a deterministic, type-preserving representation for provenance
digests. Arrays record their element type and complete shape before their
column-major values, so (for example) a 2×3 matrix cannot collide with a
length-6 vector. Generic structs are represented by type and named fields,
which lets the same contract hash an initialized `BeforeIT.Model` without
depending on Julia's process-specific object serialization.
"""
function _run_provenance_canonical(value)
    if value === nothing
        return "nothing"
    elseif value === missing
        return "missing"
    elseif value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa Integer
        return "integer<$(typeof(value))>:$(value)"
    elseif value isa AbstractFloat
        bits = reinterpret(UInt64, Float64(value))
        return "float64:" * string(bits; base = 16, pad = 16)
    elseif value isa Real
        number = Float64(value)
        bits = reinterpret(UInt64, number)
        return "real64:" * string(bits; base = 16, pad = 16)
    elseif value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    elseif value isa Symbol
        return "symbol:" * _run_provenance_canonical(String(value))
    elseif value isa Char
        return "char:$(UInt32(value))"
    elseif value isa NamedTuple
        fields = [
            _run_provenance_canonical(String(name)) * "=" *
                _run_provenance_canonical(getfield(value, name)) for
                name in propertynames(value)
        ]
        return "namedtuple:{" * join(fields, ",") * "}"
    elseif value isa AbstractArray
        dimensions = join(size(value), "x")
        items = join(
            (_run_provenance_canonical(item) for item in value),
            ",",
        )
        return "array<$(eltype(value))>[$dimensions]:[$items]"
    elseif value isa Tuple
        return "tuple:$(length(value)):[" *
            join(
            (_run_provenance_canonical(item) for item in value),
            ",",
        ) *
            "]"
    elseif value isa AbstractDict || value isa JSON3.Object
        entries = [
            (
                    _run_provenance_canonical(key),
                    _run_provenance_canonical(item),
                ) for (key, item) in pairs(value)
        ]
        sort!(entries; by = first)
        return "dictionary:{" *
            join(
            ("$(entry[1])=$(entry[2])" for entry in entries),
            ",",
        ) *
            "}"
    elseif value isa AbstractSet
        entries = sort!(
            [_run_provenance_canonical(item) for item in value],
        )
        return "set:{" * join(entries, ",") * "}"
    elseif value isa DataType || value isa UnionAll ||
            value isa Module || value isa Function
        return "identity:" * string(value)
    end

    value_type = typeof(value)
    isstructtype(value_type) || throw(
        ArgumentError(
            "Unsupported provenance value of type $(value_type)",
        ),
    )
    fields = [
        _run_provenance_canonical(String(name)) * "=" *
            _run_provenance_canonical(getfield(value, name)) for
            name in fieldnames(value_type)
    ]
    return "struct<$(value_type)>:{" * join(fields, ",") * "}"
end

function _run_provenance_digest(value)
    canonical = _run_provenance_canonical(value)
    digest = SHA.sha256(Vector{UInt8}(codeunits(canonical)))
    return "sha256:" * bytes2hex(digest)
end

function _run_source_bundle(
        root::AbstractString;
        selected_paths = nothing,
    )
    canonical_root = normpath(root)
    paths = if selected_paths === nothing
        discovered = String[]
        for (directory, _, names) in walkdir(canonical_root)
            for name in names
                endswith(lowercase(name), ".jl") || continue
                push!(discovered, joinpath(directory, name))
            end
        end
        discovered
    else
        [normpath(String(path)) for path in selected_paths]
    end
    sort!(paths; by = path -> replace(relpath(path, canonical_root), '\\' => '/'))
    files = [
        Dict{String, Any}(
                "path" =>
                replace(relpath(path, canonical_root), '\\' => '/'),
                "contents" => read(path, String),
            ) for path in paths
    ]
    return Dict{String, Any}(
        "root_label" => basename(canonical_root),
        "files" => files,
    )
end

function _run_source_provenance()
    return lock(_RUN_SOURCE_PROVENANCE_LOCK) do
        cached = _RUN_SOURCE_PROVENANCE[]
        cached === nothing || return deepcopy(cached)

        web_source_root = joinpath(APP_ROOT, "src")
        model_source_root = dirname(pathof(Bit))
        trace_path = joinpath(web_source_root, "cashflows.jl")
        producer_bundle = _run_source_bundle(web_source_root)
        model_bundle = _run_source_bundle(model_source_root)
        trace_bundle = _run_source_bundle(
            web_source_root;
            selected_paths = [trace_path],
        )
        provenance = Dict{String, Any}(
            "producer_source_digest" =>
                _run_provenance_digest(producer_bundle),
            "producer_source_files" => [
                file["path"] for file in producer_bundle["files"]
            ],
            "model_source_digest" =>
                _run_provenance_digest(model_bundle),
            "model_source_files" => [
                file["path"] for file in model_bundle["files"]
            ],
            "trace_source_digest" =>
                _run_provenance_digest(trace_bundle),
            "trace_source_files" => [
                file["path"] for file in trace_bundle["files"]
            ],
        )
        _RUN_SOURCE_PROVENANCE[] = provenance
        return deepcopy(provenance)
    end
end

function _run_static_provenance(
        dataset_id::AbstractString,
        scenario::AbstractString,
        base_parameters,
        base_initial_conditions,
        effective_parameters,
        effective_initial_conditions,
        sim,
        trace,
    )
    source = _run_source_provenance()
    dataset_identity = Dict{String, Any}(
        "dataset_id" => String(dataset_id),
        "dataset_spec" => _dataset_spec(dataset_id),
        "parameters" => base_parameters,
        "initial_conditions" => base_initial_conditions,
    )
    calibration_identity = Dict{String, Any}(
        "dataset_id" => String(dataset_id),
        "scenario" => String(scenario),
        "horizon" => Int(get(sim, "T", 0)),
        "parameters" => effective_parameters,
        "initial_conditions" => effective_initial_conditions,
    )
    initialization_contract = Dict{String, Any}(
        "model_source_digest" => source["model_source_digest"],
        "calibration_digest" =>
            _run_provenance_digest(calibration_identity),
        "scenario" => String(scenario),
        "horizon" => Int(get(sim, "T", 0)),
        "base_seed" => Int(get(sim, "base_seed", 0)),
        "trace_realization_indices" =>
            Int.(collect(get(trace, "realization_indices", Int[]))),
        "rng_policy" => RUN_RNG_POLICY,
    )
    return merge(
        Dict{String, Any}(
            "schema_version" => RUN_PROVENANCE_SCHEMA_VERSION,
            "digest_algorithm" => "sha256",
            "canonicalization" =>
                "beforeit-shape-and-type-preserving-canonical.v1",
            "dataset_digest" =>
                _run_provenance_digest(dataset_identity),
            "calibration_digest" =>
                _run_provenance_digest(calibration_identity),
            "initialization_contract_digest" =>
                _run_provenance_digest(initialization_contract),
            "rng_policy" => deepcopy(RUN_RNG_POLICY),
        ),
        source,
    )
end

function _run_initial_state_payload(model)
    state = Dict{String, Any}()
    for name in fieldnames(typeof(model))
        name == :data && continue
        state[String(name)] = getfield(model, name)
    end
    return Dict{String, Any}(
        "model_type" => string(typeof(model)),
        "economic_state" => state,
    )
end

struct ApiError <: Exception
    status::Int
    message::String
    details::Any
end

ApiError(status::Int, message::AbstractString) = ApiError(status, String(message), nothing)

function _json_response(status::Int, obj)
    headers = [
        "Content-Type" => "application/json; charset=utf-8",
        "Cache-Control" => "no-store",
    ]
    return HTTP.Response(status, headers, JSON3.write(obj))
end

function _text_response(status::Int, body::AbstractString; content_type::AbstractString = "text/plain; charset=utf-8")
    headers = ["Content-Type" => content_type, "Cache-Control" => "no-store"]
    return HTTP.Response(status, headers, body)
end

function _query_integer(q, name::AbstractString, default = nothing)
    haskey(q, name) || return default
    parsed = tryparse(Int, q[name])
    parsed === nothing &&
        throw(ApiError(400, "$name must be an integer"))
    return parsed
end

function _query_float(q, name::AbstractString, default::Real)
    haskey(q, name) || return Float64(default)
    parsed = tryparse(Float64, q[name])
    parsed === nothing &&
        throw(ApiError(400, "$name must be a number"))
    return parsed
end

function _query_boolean(q, name::AbstractString, default::Bool = false)
    haskey(q, name) || return default
    value = lowercase(strip(q[name]))
    value in ("1", "true", "yes") && return true
    value in ("0", "false", "no") && return false
    throw(ApiError(400, "$name must be true or false"))
end

function _csv_cell(value)
    text = if value === nothing
        ""
    elseif value isa AbstractDict || value isa AbstractVector ||
            value isa Tuple || value isa NamedTuple
        JSON3.write(_sanitize_for_json(value))
    else
        string(value)
    end
    if occursin(',', text) || occursin('"', text) ||
            occursin('\n', text) || occursin('\r', text)
        return "\"$(replace(text, '\"' => "\"\""))\""
    end
    return text
end

function _cashflow_export_response(payload, format::AbstractString)
    normalized_format = lowercase(String(format))
    run_id = String(payload["run_id"])
    quarter = Int(payload["quarter_index"])
    filename = "cashflows-$(run_id)-q$(quarter).$(normalized_format)"
    headers = [
        "Cache-Control" => "no-store",
        "Content-Disposition" => "attachment; filename=\"$filename\"",
    ]
    if normalized_format == "jsonl"
        metadata = Dict{String, Any}(
            String(key) => value for (key, value) in pairs(payload) if
                String(key) != "edges"
        )
        metadata["record_type"] = "metadata"
        lines = String[JSON3.write(_sanitize_for_json(metadata))]
        for edge in payload["edges"]
            record = Dict{String, Any}(
                String(key) => value for (key, value) in pairs(edge)
            )
            record["record_type"] = "edge"
            push!(lines, JSON3.write(_sanitize_for_json(record)))
        end
        push!(headers, "Content-Type" => "application/x-ndjson; charset=utf-8")
        return HTTP.Response(200, headers, join(lines, "\n") * "\n")
    elseif normalized_format == "csv"
        edges = collect(payload["edges"])
        edge_keys = sort!(
            collect(
                union(
                    Set{String}(),
                    (Set(String.(collect(keys(edge)))) for edge in edges)...,
                )
            )
        )
        prefix_keys = [
            "run_id",
            "quarter_index",
            "period",
            "trace_schema_version",
            "api_schema_version",
        ]
        columns = vcat(prefix_keys, edge_keys)
        lines = String[join(_csv_cell.(columns), ',')]
        for edge in edges
            prefix_values = Any[
                payload["run_id"],
                payload["quarter_index"],
                payload["period"],
                payload["trace_schema_version"],
                payload["api_schema_version"],
            ]
            values = vcat(
                prefix_values,
                Any[get(edge, key, nothing) for key in edge_keys],
            )
            push!(lines, join(_csv_cell.(values), ','))
        end
        push!(headers, "Content-Type" => "text/csv; charset=utf-8")
        return HTTP.Response(200, headers, join(lines, "\r\n") * "\r\n")
    end
    throw(ApiError(400, "format must be csv or jsonl"))
end

function _read_json(req::HTTP.Request)
    body = try
        String(req.body)
    catch
        ""
    end
    isempty(body) && return JSON3.Object()
    return JSON3.read(body)
end

function _normalize_value(v)
    if v isa JSON3.Object || v isa AbstractDict
        return _normalize_dict(v)
    elseif v isa JSON3.Array || v isa AbstractVector
        return [_normalize_value(x) for x in v]
    else
        return v
    end
end

function _normalize_dict(obj)::Dict{String, Any}
    out = Dict{String, Any}()
    if obj === nothing
        return out
    end
    for (k, v) in obj
        out[String(k)] = _normalize_value(v)
    end
    return out
end

function _ensure_dir(path::AbstractString)
    isdir(path) || mkpath(path)
    return path
end

function _now_utc_iso()
    return Dates.format(Dates.now(Dates.UTC), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ")
end

function _dataset_spec(id::AbstractString)
    dataset_id = String(id)
    haskey(DATASET_SPECS, dataset_id) ||
        throw(ApiError(404, "Unknown dataset_id: $(id)"))
    return DATASET_SPECS[dataset_id]
end

function _dataset_artifact(id::AbstractString)
    if id == "US2026Q1"
        return Bit.load_us_baseline(:nowcast)
    elseif id == "US2024Q4"
        return Bit.load_us_baseline(:structural)
    elseif id == "AUSTRIA2026Q1"
        return Bit.load_austria_baseline(:nowcast)
    elseif id == "AUSTRIA2024Q4"
        return Bit.load_austria_baseline(:structural)
    end
    return nothing
end

function _dataset_person_multiplier(id::AbstractString)
    artifact = _dataset_artifact(id)
    artifact === nothing && return 1.0
    scale = try
        Float64(get(artifact.metadata, "scale", 1.0))
    catch
        1.0
    end
    return isfinite(scale) && scale > 0 ? inv(scale) : 1.0
end

function _dataset_by_id(id::AbstractString)
    artifact = _dataset_artifact(id)
    if artifact !== nothing
        return artifact.parameters, artifact.initial_conditions
    elseif id == "AUSTRIA2010Q1"
        return Bit.AUSTRIA2010Q1.parameters, Bit.AUSTRIA2010Q1.initial_conditions
    elseif id == "ITALY2010Q1"
        return Bit.ITALY2010Q1.parameters, Bit.ITALY2010Q1.initial_conditions
    elseif id == "STEADY_STATE2010Q1"
        return Bit.STEADY_STATE2010Q1.parameters, Bit.STEADY_STATE2010Q1.initial_conditions
    end
    throw(ApiError(404, "Unknown dataset_id: $(id)"))
end

function _dataset_units(id::AbstractString)
    spec = _dataset_spec(id)
    currency = spec.country == "US" ? "USD" : "EUR"
    currency_symbol = currency == "USD" ? "\$" : "€"
    unit_stem = lowercase(currency)
    return (
        currency = currency,
        currency_symbol = currency_symbol,
        flow_units = "million_$(unit_stem)_per_quarter",
        stock_units = "million_$(unit_stem)",
    )
end

function dataset_metadata(id::AbstractString)
    spec = _dataset_spec(id)
    units = _dataset_units(id)
    metadata = Dict{String, Any}(
        "id" => String(id),
        "label" => spec.label,
        "country" => spec.country,
        "period" => spec.period,
        "kind" => spec.kind,
        "structural_reference_year" => spec.structural_reference_year,
        "observed_through" => spec.observed_through,
        "scenarios" => spec.scenarios,
        "default_scenario" => spec.default_scenario,
        "default_horizon" => spec.default_horizon,
        "description" => spec.description,
        "currency" => units.currency,
        "currency_symbol" => units.currency_symbol,
        "flow_units" => units.flow_units,
        "stock_units" => units.stock_units,
    )
    artifact = _dataset_artifact(id)
    if artifact !== nothing
        artifact_metadata = artifact.metadata
        artifact_path = try
            relpath(artifact.path, normpath(joinpath(APP_ROOT, "..", "..")))
        catch
            basename(artifact.path)
        end
        metadata["measurement_status"] =
            get(artifact_metadata, "measurement_status", Dict{String, Any}())
        metadata["output_measurement"] = _normalize_value(
            get(
                artifact_metadata,
                "output_measurement",
                Dict{String, Any}(),
            ),
        )
        records = get(
            artifact_metadata,
            "live_source_records",
            Dict{String, Any}[],
        )
        metadata["live_source_count"] = length(records)
        updates = [
            String(record["updated"]) for record in records if
                haskey(record, "updated") && !ismissing(record["updated"])
        ]
        metadata["latest_source_update"] =
            isempty(updates) ? nothing : maximum(updates)
        metadata["calibratebeforeit_revision"] = get(
            artifact_metadata,
            "calibratebeforeit_revision",
            nothing,
        )
        metadata["eurostat_snapshot_sha256"] =
            get(artifact_metadata, "eurostat_snapshot_sha256", nothing)
        metadata["figaro_sha256"] =
            get(artifact_metadata, "figaro_sha256", nothing)
        input_sha256 =
            get(artifact_metadata, "input_sha256", String[])
        validation_checklist =
            get(artifact_metadata, "validation_checklist", nothing)
        database = get(artifact_metadata, "database", nothing)
        metadata["artifact_path"] = artifact_path
        metadata["validation_checklist"] = validation_checklist
        metadata["database"] = database
        metadata["input_snapshot_count"] = length(input_sha256)
        metadata["artifact_provenance"] = Dict{String, Any}(
            "artifact_path" => artifact_path,
            "artifact_schema_version" =>
                get(artifact_metadata, "schema_version", nothing),
            "artifact_created_at" =>
                get(artifact_metadata, "created_at", nothing),
            "beforeit_version" =>
                get(artifact_metadata, "beforeit_version", nothing),
            "sector_system" =>
                get(artifact_metadata, "sector_system", nothing),
            "sector_count" =>
                get(artifact_metadata, "sector_count", nothing),
            "scale" => get(artifact_metadata, "scale", nothing),
            "input_sha256" => input_sha256,
            "input_sha256_count" => length(input_sha256),
            "validation_checklist" => validation_checklist,
            "database" => database,
        )
    else
        metadata["measurement_status"] = Dict(
            "calibration" => "Packaged legacy or synthetic calibration",
        )
        metadata["output_measurement"] = Dict{String, Any}()
        metadata["live_source_count"] = 0
        metadata["latest_source_update"] = nothing
    end
    return metadata
end

available_datasets() = [dataset_metadata(id) for id in DATASET_ORDER]

function _sector_group(index::Integer)
    groups = if index <= 3
        ("PRIMARY", "Primary", 1, "#77b98b")
    elseif index <= 23
        ("INDUSTRY", "Manufacturing & industry", 2, "#e0a458")
    elseif index <= 26
        ("UTILITIES", "Utilities", 3, "#66b8c6")
    elseif index == 27
        ("CONSTRUCTION", "Construction", 4, "#d88f70")
    elseif index <= 30
        ("TRADE", "Trade", 5, "#d7bf63")
    elseif index <= 35
        ("TRANSPORT", "Transport & logistics", 6, "#63a7d8")
    elseif index == 36
        ("HOSPITALITY", "Hospitality", 7, "#d9829b")
    elseif index <= 40
        ("INFORMATION", "Information & communication", 8, "#8f88d8")
    elseif index <= 43
        ("FINANCE", "Financial services", 9, "#8db4e2")
    elseif index == 44
        ("REAL_ESTATE", "Real estate", 10, "#b39773")
    elseif index <= 49
        ("PROFESSIONAL", "Professional services", 11, "#a889c6")
    elseif index <= 53
        ("BUSINESS", "Business services", 12, "#8ec3a7")
    elseif index == 54
        ("PUBLIC", "Public administration", 13, "#cc8f75")
    elseif index == 55
        ("EDUCATION", "Education", 14, "#74b8aa")
    elseif index <= 57
        ("HEALTH", "Health & social care", 15, "#df8797")
    elseif index <= 62
        ("CULTURE", "Culture & personal services", 16, "#b894d1")
    else
        ("OTHER", "Other sectors", 99, "#8fa3a0")
    end
    return (
        id = groups[1],
        label = groups[2],
        order = groups[3],
        color = groups[4],
    )
end

function _sector_metadata_source(spec)
    if spec.country == "US"
        return (
            filename = "BEA68.json",
            classification = "BEA Summary I-O",
            classification_label = "BEA Summary Input-Output",
            version = "BEA68.web.v1",
        )
    end
    return (
        filename = "NACE62.json",
        classification = "NACE/FIGARO",
        classification_label = "NACE / FIGARO",
        version = "NACE62.web.v1",
    )
end

function sector_metadata(dataset_id::AbstractString)
    spec = _dataset_spec(dataset_id)
    units = _dataset_units(dataset_id)
    params, _ = _dataset_by_id(dataset_id)
    sector_count = haskey(params, "b_HH_g") ? length(params["b_HH_g"]) : 0
    metadata_source = _sector_metadata_source(spec)
    canonical_path =
        joinpath(METADATA_DIR, "sectors", metadata_source.filename)
    canonical = isfile(canonical_path) ?
        JSON3.read(read(canonical_path, String)) : Any[]
    canonical_rows =
        canonical isa AbstractDict || canonical isa JSON3.Object ?
        get(_normalize_dict(canonical), "sectors", Any[]) : canonical
    use_canonical = sector_count == length(canonical_rows)
    sectors = Vector{Any}(undef, sector_count)
    for index in 1:sector_count
        source =
            use_canonical ? _normalize_dict(canonical_rows[index]) :
            Dict{String, Any}()
        group =
            use_canonical && spec.country != "US" ?
            _sector_group(index) : _sector_group(typemax(Int))
        label = String(get(source, "label", "Dataset sector $index"))
        sectors[index] = Dict{String, Any}(
            "index" => index,
            "code" => String(
                get(source, "code", "S$(lpad(index, 3, '0'))"),
            ),
            "label" => label,
            "short_label" =>
                String(get(source, "short_label", label)),
            "group_id" => String(get(source, "group_id", group.id)),
            "group_label" =>
                String(get(source, "group_label", group.label)),
            "group_order" =>
                Int(get(source, "group_order", group.order)),
            "group_color" =>
                String(get(source, "group_color", group.color)),
        )
    end
    classification =
        use_canonical ? metadata_source.classification :
        "dataset-defined-index"
    classification_label =
        use_canonical ? metadata_source.classification_label :
        "Dataset-defined sector index"
    return Dict{String, Any}(
        "dataset_id" => String(dataset_id),
        "classification" => classification,
        "classification_label" => classification_label,
        "version" =>
            use_canonical ? metadata_source.version : "dataset-index.v1",
        "currency" => units.currency,
        "currency_symbol" => units.currency_symbol,
        "flow_units" => units.flow_units,
        "stock_units" => units.stock_units,
        "person_multiplier" => _dataset_person_multiplier(dataset_id),
        "sectors" => sectors,
    )
end

function _normalize_scenario(
        dataset_id::AbstractString,
        scenario::AbstractString,
    )
    spec = _dataset_spec(dataset_id)
    normalized = lowercase(String(scenario))
    normalized in spec.scenarios || throw(
        ApiError(
            400,
            "Scenario '$scenario' is unavailable for $(spec.label)",
            (allowed = spec.scenarios,),
        ),
    )
    return normalized
end

function scenario_assumptions(
        dataset_id::AbstractString,
        scenario::AbstractString,
    )
    normalized = _normalize_scenario(dataset_id, scenario)
    normalized == "unconditional" && return Any[]
    assumptions = Bit.load_austria_scenarios()
    rows = Vector{Any}()
    for row in eachrow(assumptions)
        String(row.scenario) == normalized || continue
        push!(
            rows,
            (
                scenario = String(row.scenario),
                year = Int(row.year),
                real_gdp_growth = Float64(row.real_gdp_growth),
                hicp_inflation = Float64(row.hicp_inflation),
                private_consumption_growth =
                    Float64(row.private_consumption_growth),
                government_consumption_growth =
                    Float64(row.government_consumption_growth),
                fixed_capital_formation_growth =
                    Float64(row.fixed_capital_formation_growth),
                exports_growth = Float64(row.exports_growth),
                imports_growth = Float64(row.imports_growth),
                budget_balance_pct_gdp =
                    Float64(row.budget_balance_pct_gdp),
                source = String(row.source),
                method = String(row.method),
            ),
        )
    end
    return rows
end

function _value_kind_and_shape(v)
    if v isa Number || v isa AbstractString || v isa Bool
        return ("scalar", nothing)
    elseif v isa AbstractArray
        shp = size(v)
        if ndims(v) == 1
            return ("vector", Tuple(shp))
        elseif ndims(v) == 2 && (shp[1] == 1 || shp[2] == 1)
            return ("vector", Tuple(shp))
        else
            return ("matrix", Tuple(shp))
        end
    else
        return ("other", nothing)
    end
end

function summarize_dict(d::Dict{String, Any})
    items = Vector{Any}()
    for k in sort(collect(keys(d)))
        v = d[k]
        kind, shape = _value_kind_and_shape(v)
        push!(
            items,
            (key = k, kind = kind, eltype = string(typeof(v)), shape = shape),
        )
    end
    return items
end

function _json_value(v)
    if v isa Bool || v isa AbstractString
        return v
    elseif v isa Real
        return isfinite(v) ? v : nothing
    elseif v isa Number
        throw(ApiError(400, "Unsupported numeric value for JSON: $(typeof(v))"))
    elseif v isa AbstractArray
        shp = size(v)
        if ndims(v) == 1
            return [_json_value(value) for value in v]
        elseif ndims(v) == 2 && (shp[1] == 1 || shp[2] == 1)
            return [_json_value(value) for value in vec(v)]
        elseif ndims(v) == 2
            return [
                [_json_value(value) for value in view(v, row, :)]
                    for row in axes(v, 1)
            ]
        else
            return map(_json_value, v)
        end
    else
        throw(ApiError(400, "Unsupported value type for JSON: $(typeof(v))"))
    end
end

"""
Curated knobs. Each entry returns:
- group: "parameters" | "initial_conditions"
- key: dict key
- label: UI label
- min/max: numeric bounds in UI units
- unit: display unit
- transform_in: :identity | :annual_to_quarterly_rate
- transform_out: :identity | :quarterly_to_annual_rate
"""
function knob_specs()
    return [
        (group = "parameters", key = "tau_INC", label = "Income tax (tau_INC)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_FIRM", label = "Corporate tax (tau_FIRM)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_VAT", label = "VAT (tau_VAT)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_SIF", label = "Social insurance employer (tau_SIF)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_SIW", label = "Social insurance employee (tau_SIW)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_EXPORT", label = "Export tax (tau_EXPORT)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_CF", label = "Capital formation tax (tau_CF)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "tau_G", label = "Gov. consumption tax (tau_G)", min = 0.0, max = 0.8, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "psi", label = "Consume share (psi)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "psi_H", label = "Housing invest share (psi_H)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "theta_UB", label = "Unemployment benefit replacement (theta_UB)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "theta_DIV", label = "Dividend payout (theta_DIV)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),

        (group = "parameters", key = "mu", label = "Bank risk premium (mu)", min = 0.0, max = 0.2, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "zeta", label = "Capital requirement (zeta)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "zeta_LTV", label = "Loan-to-value (zeta_LTV)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "zeta_b", label = "Loan-to-capital new firms (zeta_b)", min = 0.0, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "theta", label = "Debt installment rate (theta)", min = 1.0e-6, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),

        (group = "parameters", key = "rho", label = "CB smoothing (rho)", min = 0.0, max = 0.999, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "r_star", label = "CB real neutral rate (r_star, quarterly)", min = -0.05, max = 0.05, unit = "quarterly", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "pi_star", label = "CB inflation target (pi_star, quarterly)", min = -0.02, max = 0.05, unit = "quarterly", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "xi_pi", label = "CB inflation weight (xi_pi)", min = 0.0, max = 5.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "xi_gamma", label = "CB growth weight (xi_gamma)", min = 0.0, max = 5.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "parameters", key = "r_G", label = "Quarterly government debt rate (r_G)", min = 0.0, max = 0.1, unit = "", transform_in = :identity, transform_out = :identity),

        (group = "initial_conditions", key = "r_bar", label = "Policy rate (annualized)", min = -0.05, max = 0.2, unit = "annual", transform_in = :annual_to_quarterly_rate, transform_out = :quarterly_to_annual_rate),
        (group = "initial_conditions", key = "sb_other", label = "Other benefits (sb_other)", min = 0.0, max = 100.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "initial_conditions", key = "sb_inact", label = "Inactive benefits (sb_inact)", min = 0.0, max = 100.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "initial_conditions", key = "w_UB", label = "Unemployment benefit wage (w_UB)", min = 0.0, max = 100.0, unit = "", transform_in = :identity, transform_out = :identity),
        (group = "initial_conditions", key = "omega", label = "Capacity utilization (omega)", min = 1.0e-6, max = 1.0, unit = "", transform_in = :identity, transform_out = :identity),
    ]
end

function _transform_in(spec, x::Real)
    if spec.transform_in == :identity
        return Float64(x)
    elseif spec.transform_in == :annual_to_quarterly_rate
        return (1.0 + Float64(x))^(1 / 4) - 1.0
    end
    throw(ApiError(500, "Unknown transform_in: $(spec.transform_in)"))
end

function _transform_out(spec, x::Real)
    if spec.transform_out == :identity
        return Float64(x)
    elseif spec.transform_out == :quarterly_to_annual_rate
        return (1.0 + Float64(x))^4 - 1.0
    end
    throw(ApiError(500, "Unknown transform_out: $(spec.transform_out)"))
end

function get_knobs(dataset_id::AbstractString)
    params, inits = _dataset_by_id(dataset_id)
    out = Vector{Any}()
    for spec in knob_specs()
        group_dict = spec.group == "parameters" ? params : inits
        haskey(group_dict, spec.key) || continue
        base_val = group_dict[spec.key]
        (base_val isa Number) || continue
        ui_default = _transform_out(spec, base_val)
        push!(
            out,
            (
                group = spec.group,
                key = spec.key,
                label = spec.label,
                unit = spec.unit,
                min = spec.min,
                max = spec.max,
                default = ui_default,
            ),
        )
    end
    return out
end

function _knob_index()
    idx = Dict{Tuple{String, String}, Any}()
    for spec in knob_specs()
        idx[(spec.group, spec.key)] = spec
    end
    return idx
end

function validate_overrides(dataset_id::AbstractString, overrides_params::Dict, overrides_inits::Dict)
    params, inits = _dataset_by_id(dataset_id)
    idx = _knob_index()

    validated_params = Dict{String, Float64}()
    validated_inits = Dict{String, Float64}()

    function validate_group!(validated::Dict{String, Float64}, group::String, overrides::Dict)
        for (k_any, v_any) in overrides
            k = String(k_any)
            spec = get(idx, (group, k), nothing)
            spec === nothing && throw(ApiError(400, "Key not editable: $(group).$(k)"))
            v_any isa Number || throw(ApiError(400, "Override must be numeric: $(group).$(k)"))
            v_ui = Float64(v_any)
            if !(spec.min <= v_ui <= spec.max)
                throw(ApiError(400, "Out of bounds: $(group).$(k)", (min = spec.min, max = spec.max, got = v_ui)))
            end
            validated[k] = _transform_in(spec, v_ui)
        end
        return
    end

    validate_group!(validated_params, "parameters", overrides_params)
    validate_group!(validated_inits, "initial_conditions", overrides_inits)

    # Some official-data calibrations can imply a baseline propensity sum above
    # one when households dissave. Preserve that calibrated baseline, but keep
    # the UI's cross-field constraint whenever either propensity is edited.
    if haskey(validated_params, "psi") || haskey(validated_params, "psi_H")
        base_psi = Float64(params["psi"])
        base_psi_h = Float64(params["psi_H"])
        psi = get(validated_params, "psi", base_psi)
        psi_h = get(validated_params, "psi_H", base_psi_h)
        if psi + psi_h > 1.0 + 1.0e-12
            throw(
                ApiError(
                    400,
                    "Constraint violated: psi + psi_H must be <= 1",
                    (psi = psi, psi_H = psi_h),
                ),
            )
        end
    end

    return validated_params, validated_inits
end

function _run_dir(run_id::AbstractString)
    return joinpath(RUNS_DIR, run_id)
end

function _next_quarter(period::AbstractString)
    matched = match(r"^(\d{4})-Q([1-4])$", period)
    matched === nothing &&
        throw(ApiError(500, "Invalid dataset period: $period"))
    year = parse(Int, matched.captures[1])
    quarter = parse(Int, matched.captures[2])
    return quarter == 4 ? "$(year + 1)-Q1" : "$year-Q$(quarter + 1)"
end

function _quarter_labels(start_period::AbstractString, horizon::Integer)
    labels = String[String(start_period)]
    for _ in 1:horizon
        push!(labels, _next_quarter(last(labels)))
    end
    return labels
end

function _read_json_file(path::AbstractString)
    isfile(path) || return nothing
    return JSON3.read(read(path, String))
end

function _overrides_to_ui(dataset_id::AbstractString, overrides)
    normalized = _normalize_dict(overrides)
    index = _knob_index()
    result = Dict(
        "parameters" => Dict{String, Float64}(),
        "initial_conditions" => Dict{String, Float64}(),
    )
    for group in ("parameters", "initial_conditions")
        values = get(normalized, group, Dict{String, Any}())
        values isa AbstractDict || continue
        for (key_any, value_any) in values
            key = String(key_any)
            spec = get(index, (group, key), nothing)
            spec === nothing && continue
            value_any isa Real || continue
            result[group][key] = _transform_out(spec, Float64(value_any))
        end
    end
    return result
end

function _optional_text(value; maximum::Int = 240)
    value === nothing && return nothing
    text = strip(String(value))
    isempty(text) && return nothing
    ncodeunits(text) <= maximum ||
        throw(ApiError(400, "Text field is too long", (maximum = maximum,)))
    return text
end

function _normalize_trace_spec(trace)
    raw = trace === nothing ? Dict{String, Any}() : _normalize_dict(trace)
    profile = replace(
        lowercase(String(get(raw, "profile", "standard"))),
        '-' => '_',
        ' ' => '_',
    )
    profile in ("summary", "standard", "deep", "ensemble_network", "checkpoint") ||
        throw(
        ApiError(
            400,
            "Unknown trace profile",
            (allowed = ["summary", "standard", "deep", "ensemble_network", "checkpoint"],),
        ),
    )

    indices_raw = get(raw, "realization_indices", profile == "summary" ? Any[] : Any[1])
    indices_raw isa AbstractVector ||
        throw(ApiError(400, "trace.realization_indices must be an array"))
    indices = Int[]
    for value in indices_raw
        index = try
            Int(value)
        catch
            throw(ApiError(400, "Trace realization indices must be integers"))
        end
        1 <= index <= 64 ||
            throw(ApiError(400, "Trace realization index out of bounds", (index = index,)))
        index in indices || push!(indices, index)
    end
    sort!(indices)
    profile != "summary" && isempty(indices) && push!(indices, 1)

    phase_detail = replace(
        lowercase(String(get(raw, "phase_detail", "none"))),
        '-' => '_',
        ' ' => '_',
    )
    phase_detail in ("none", "settlement", "phases") ||
        throw(ApiError(400, "Unknown trace.phase_detail"))
    checkpoints_raw = get(raw, "checkpoints", profile == "checkpoint")
    checkpoints = checkpoints_raw isa Bool ? checkpoints_raw :
        checkpoints_raw isa Number ? checkpoints_raw != 0 : false

    return Dict{String, Any}(
        "profile" => profile,
        "realization_indices" => indices,
        "phase_detail" => phase_detail,
        "checkpoints" => checkpoints,
    )
end

function _run_spec_payload(run_path::AbstractString)
    spec = _read_json_file(joinpath(run_path, "spec.json"))
    spec === nothing && throw(ApiError(404, "Missing run specification"))
    dataset_id = String(get(spec, :dataset_id, ""))
    raw_overrides = get(spec, :overrides, Dict{String, Any}())
    return Dict(
        "run_id" => String(get(spec, :run_id, basename(run_path))),
        "name" => _optional_text(get(spec, :name, nothing); maximum = 120),
        "description" => _optional_text(get(spec, :description, nothing); maximum = 2000),
        "parent_run_id" => _optional_text(get(spec, :parent_run_id, nothing); maximum = 80),
        "experiment_id" => _optional_text(get(spec, :experiment_id, nothing); maximum = 80),
        "experiment_role" => _optional_text(get(spec, :experiment_role, nothing); maximum = 40),
        "dataset_id" => dataset_id,
        "scenario" => String(get(spec, :scenario, "unconditional")),
        "created_at" => String(get(spec, :created_at, "")),
        "sim" => _normalize_dict(get(spec, :sim, Dict{String, Any}())),
        "overrides" => _overrides_to_ui(dataset_id, raw_overrides),
        "shock" => _normalize_dict(
            get(spec, :shock, Dict{String, Any}("type" => "none")),
        ),
        "trace" => _normalize_trace_spec(get(spec, :trace, Dict{String, Any}())),
        "provenance" => _normalize_dict(
            get(spec, :provenance, Dict{String, Any}()),
        ),
    )
end

function list_runs()
    _ensure_dir(RUNS_DIR)
    runs = Vector{Any}()
    for name in readdir(RUNS_DIR)
        run_path = joinpath(RUNS_DIR, name)
        isdir(run_path) || continue
        spec = _read_json_file(joinpath(run_path, "spec.json"))
        status = _read_json_file(joinpath(run_path, "status.json"))
        spec === nothing && continue
        overrides = _normalize_dict(
            get(spec, :overrides, Dict{String, Any}()),
        )
        override_count = sum(
            length(get(overrides, group, Dict{String, Any}()))
                for group in ("parameters", "initial_conditions")
        )
        shock = _normalize_dict(
            get(spec, :shock, Dict{String, Any}("type" => "none")),
        )
        sim = _normalize_dict(get(spec, :sim, Dict{String, Any}()))
        cashflow_manifest = _read_json_file(
            joinpath(run_path, "cashflows-manifest.json"),
        )
        cashflow_quarters =
            cashflow_manifest === nothing ? 0 :
            length(get(cashflow_manifest, :quarters, Any[]))
        run_name = _optional_text(get(spec, :name, nothing); maximum = 120)
        description = _optional_text(get(spec, :description, nothing); maximum = 2000)
        dataset_id = String(get(spec, :dataset_id, ""))
        scenario = String(get(spec, :scenario, "unconditional"))
        created_at = String(get(spec, :created_at, ""))
        display_name = run_name === nothing ?
            "$(get(DATASET_SPECS, dataset_id, (label = dataset_id,)).label) · $(scenario)" : run_name
        push!(
            runs,
            (
                run_id = String(get(spec, :run_id, name)),
                name = run_name,
                display_name = display_name,
                description = description,
                parent_run_id = get(spec, :parent_run_id, nothing),
                experiment_id = get(spec, :experiment_id, nothing),
                experiment_role = get(spec, :experiment_role, nothing),
                dataset_id = dataset_id,
                scenario = scenario,
                created_at = created_at,
                horizon = Int(get(sim, "T", 0)),
                n_sims = Int(get(sim, "n_sims", 0)),
                base_seed = Int(get(sim, "base_seed", 0)),
                trace = _normalize_trace_spec(get(spec, :trace, Dict{String, Any}())),
                override_count = override_count,
                shock_type = String(get(shock, "type", "none")),
                cashflows_available = cashflow_manifest !== nothing,
                cashflow_quarters = cashflow_quarters,
                capabilities = cashflow_manifest === nothing ?
                    Dict{String, Any}() :
                    _normalize_dict(get(cashflow_manifest, :capabilities, Dict{String, Any}())),
                state = status === nothing ? "unknown" : String(get(status, :state, "unknown")),
                progress = status === nothing ? 0.0 : Float64(get(status, :progress, 0.0)),
                message = status === nothing ? "" : String(get(status, :message, "")),
            ),
        )
    end
    sort!(runs; by = run -> run.created_at, rev = true)
    return runs
end

function create_run(
        dataset_id::AbstractString;
        name = nothing,
        description = nothing,
        parent_run_id = nothing,
        experiment_id = nothing,
        experiment_role = nothing,
        scenario = _dataset_spec(dataset_id).default_scenario,
        sim = Dict{String, Any}(),
        overrides = Dict{String, Any}(),
        shock = Dict{String, Any}(),
        trace = Dict{String, Any}(),
    )
    _ensure_dir(RUNS_DIR)
    normalized_scenario =
        _normalize_scenario(dataset_id, String(scenario))
    run_id = string(uuid4())
    run_path = _run_dir(run_id)

    sim_defaults = Dict{String, Any}(
        "T" => _dataset_spec(dataset_id).default_horizon,
        "n_sims" => 16,
        "step_multithreading" => true,
        "base_seed" => 1234,
    )
    for (k, v) in sim
        sim_defaults[String(k)] = v
    end
    horizon = try
        Int(sim_defaults["T"])
    catch
        throw(ApiError(400, "Simulation horizon T must be an integer"))
    end
    1 <= horizon <= 80 ||
        throw(ApiError(400, "T out of bounds", (T = horizon, min = 1, max = 80)))
    if normalized_scenario != "unconditional" && horizon > 23
        throw(
            ApiError(
                400,
                "Conditional scenario horizon exceeds 2031 Q4",
                (T = horizon, maximum = 23),
            ),
        )
    end
    normalized_shock = _normalize_shock_spec(shock, horizon)
    if normalized_shock["type"] == "sector_productivity"
        sector_count = length(sector_metadata(dataset_id)["sectors"])
        1 <= normalized_shock["sector"] <= sector_count || throw(
            ApiError(
                400,
                "Shock sector is outside this dataset",
                (
                    sector = normalized_shock["sector"],
                    sector_count,
                ),
            ),
        )
    end
    normalized_trace = _normalize_trace_spec(trace)
    ensemble_size = try
        Int(sim_defaults["n_sims"])
    catch
        throw(ApiError(400, "Simulation ensemble size must be an integer"))
    end
    1 <= ensemble_size <= 64 || throw(
        ApiError(
            400,
            "n_sims out of bounds",
            (n_sims = ensemble_size, min = 1, max = 64),
        ),
    )
    trace_profile = String(normalized_trace["profile"])
    trace_indices = Int.(collect(normalized_trace["realization_indices"]))
    all(index -> index <= ensemble_size, trace_indices) || throw(
        ApiError(
            400,
            "A traced realization exceeds the simulation ensemble size",
            (realization_indices = trace_indices, n_sims = ensemble_size),
        ),
    )
    length(trace_indices) <= 1 || throw(
        ApiError(
            400,
            "This release supports one exact representative trace per run",
            (
                requested = trace_indices,
                supported_profiles = ["summary", "standard"],
            ),
        ),
    )
    if trace_profile in ("deep", "ensemble_network", "checkpoint") ||
            String(normalized_trace["phase_detail"]) != "none" ||
            Bool(normalized_trace["checkpoints"])
        throw(
            ApiError(
                400,
                "The requested trace mechanics are capability-gated and are not enabled by this model build",
                (
                    profile = trace_profile,
                    phase_detail = normalized_trace["phase_detail"],
                    checkpoints = normalized_trace["checkpoints"],
                    supported_profiles = ["summary", "standard"],
                ),
            ),
        )
    end

    base_seed = try
        Int(sim_defaults["base_seed"])
    catch
        throw(ApiError(400, "Simulation base_seed must be an integer"))
    end
    parallel_value = sim_defaults["step_multithreading"]
    step_multithreading =
        parallel_value isa Bool ? parallel_value :
        parallel_value isa Number ? parallel_value != 0 :
        throw(
            ApiError(
                400,
                "Simulation step_multithreading must be a boolean",
            ),
        )
    sim_defaults["T"] = horizon
    sim_defaults["n_sims"] = ensemble_size
    sim_defaults["base_seed"] = base_seed
    sim_defaults["step_multithreading"] = step_multithreading

    overrides_params = haskey(overrides, "parameters") ? Dict{String, Any}(_normalize_dict(overrides["parameters"])) : Dict{String, Any}()
    overrides_inits =
        haskey(overrides, "initial_conditions") ? Dict{String, Any}(_normalize_dict(overrides["initial_conditions"])) :
        Dict{String, Any}()

    validated_params, validated_inits = validate_overrides(dataset_id, overrides_params, overrides_inits)
    base_parameters, base_initial_conditions =
        _dataset_by_id(dataset_id)
    effective_parameters = copy(base_parameters)
    effective_initial_conditions = copy(base_initial_conditions)
    _apply_overrides!(
        effective_parameters,
        effective_initial_conditions,
        Dict(
            "parameters" => validated_params,
            "initial_conditions" => validated_inits,
        ),
    )
    provenance = _run_static_provenance(
        dataset_id,
        normalized_scenario,
        base_parameters,
        base_initial_conditions,
        effective_parameters,
        effective_initial_conditions,
        sim_defaults,
        normalized_trace,
    )

    spec = Dict{String, Any}(
        "run_id" => run_id,
        "name" => _optional_text(name; maximum = 120),
        "description" => _optional_text(description; maximum = 2000),
        "parent_run_id" => _optional_text(parent_run_id; maximum = 80),
        "experiment_id" => _optional_text(experiment_id; maximum = 80),
        "experiment_role" => _optional_text(experiment_role; maximum = 40),
        "dataset_id" => dataset_id,
        "scenario" => normalized_scenario,
        "created_at" => _now_utc_iso(),
        "sim" => sim_defaults,
        "overrides" => Dict("parameters" => validated_params, "initial_conditions" => validated_inits),
        "shock" => normalized_shock,
        "trace" => normalized_trace,
        "provenance" => provenance,
    )

    _ensure_dir(run_path)
    open(joinpath(run_path, "spec.json"), "w") do io
        write(io, JSON3.write(spec))
    end

    status = Dict{String, Any}("state" => "queued", "progress" => 0.0, "message" => "queued", "started_at" => "", "finished_at" => "")
    open(joinpath(run_path, "status.json"), "w") do io
        write(io, JSON3.write(status))
    end

    spawn_worker(run_path)

    return run_id
end

function spawn_worker(run_path::AbstractString)
    worker_script = joinpath(APP_ROOT, "src", "worker", "run.jl")
    cmd = `julia -t auto --project=$(APP_ROOT) $(worker_script) $(run_path)`
    run(cmd; wait = false)
    return nothing
end

function _write_status(run_path::AbstractString; state::AbstractString, progress::Real, message::AbstractString, started_at::AbstractString = "", finished_at::AbstractString = "")
    status_path = joinpath(run_path, "status.json")
    status = Dict{String, Any}(
        "state" => String(state),
        "progress" => Float64(progress),
        "message" => String(message),
        "started_at" => String(started_at),
        "finished_at" => String(finished_at),
    )
    open(status_path, "w") do io
        write(io, JSON3.write(status))
    end
    return nothing
end

function _apply_overrides!(params::Dict{String, Any}, inits::Dict{String, Any}, overrides::Any)
    if overrides === nothing
        return params, inits
    end
    if haskey(overrides, "parameters")
        for (k_any, v_any) in overrides["parameters"]
            params[String(k_any)] = Float64(v_any)
        end
    end
    if haskey(overrides, "initial_conditions")
        for (k_any, v_any) in overrides["initial_conditions"]
            inits[String(k_any)] = Float64(v_any)
        end
    end
    return params, inits
end

function _build_model(
        dataset_id::AbstractString,
        scenario::AbstractString,
        params::Dict{String, Any},
        inits::Dict{String, Any},
        horizon::Integer,
    )
    if scenario == "unconditional"
        return Bit.Model(params, inits)
    end
    dataset_id == "AUSTRIA2026Q1" || throw(
        ApiError(
            400,
            "Conditional forecast scenarios require the Austria 2026 Q1 nowcast",
        ),
    )
    return Bit.build_austria_scenario_model(
        Symbol(scenario);
        horizon = horizon,
        parameters = params,
        initial_conditions = inits,
    )
end

function _shock_number(shock::AbstractDict, key::AbstractString, default::Real)
    value = get(shock, key, default)
    value isa Real ||
        throw(ApiError(400, "Shock field '$key' must be numeric"))
    number = Float64(value)
    isfinite(number) ||
        throw(ApiError(400, "Shock field '$key' must be finite"))
    return number
end

function _shock_final_time(
        shock::AbstractDict,
        horizon::Integer,
    )
    value = get(shock, "final_time", 1)
    value isa Real && isinteger(value) ||
        throw(ApiError(400, "Shock final_time must be an integer"))
    final_time = Int(value)
    1 <= final_time <= horizon || throw(
        ApiError(
            400,
            "Shock final_time must fall inside the simulation horizon",
            (final_time = final_time, horizon = horizon),
        ),
    )
    return final_time
end

function _normalize_shock_spec(shock::Any, horizon::Integer)
    if shock !== nothing &&
            !(shock isa JSON3.Object || shock isa AbstractDict)
        throw(ApiError(400, "Shock must be a JSON object"))
    end
    normalized =
        shock === nothing ? Dict{String, Any}() : _normalize_dict(shock)
    stype = lowercase(String(get(normalized, "type", "none")))
    if stype == "none"
        return Dict{String, Any}("type" => "none")
    elseif stype == "interest_rate"
        annual_rate = _shock_number(normalized, "annual_rate", 0.0)
        -0.9 < annual_rate <= 1.0 || throw(
            ApiError(
                400,
                "Interest-rate shock must be between -90 and +100 percentage points",
                (annual_rate = annual_rate,),
            ),
        )
        return Dict{String, Any}(
            "type" => stype,
            "annual_rate" => annual_rate,
            "final_time" => _shock_final_time(normalized, horizon),
        )
    elseif stype == "productivity"
        multiplier = _shock_number(normalized, "multiplier", 1.0)
        0.0 < multiplier <= 10.0 || throw(
            ApiError(
                400,
                "Productivity multiplier must be greater than 0 and at most 10",
                (multiplier = multiplier,),
            ),
        )
        return Dict{String, Any}(
            "type" => stype,
            "multiplier" => multiplier,
        )
    elseif stype == "sector_productivity"
        multiplier = _shock_number(normalized, "multiplier", 1.0)
        0.0 < multiplier <= 10.0 || throw(
            ApiError(
                400,
                "Sector-productivity multiplier must be greater than 0 and at most 10",
                (multiplier = multiplier,),
            ),
        )
        sector_value = get(normalized, "sector", nothing)
        sector_value isa Real && isinteger(sector_value) || throw(
            ApiError(400, "Sector-productivity shock requires an integer sector index"),
        )
        sector = Int(sector_value)
        sector > 0 || throw(ApiError(400, "Shock sector must be positive"))
        return Dict{String, Any}(
            "type" => stype,
            "multiplier" => multiplier,
            "sector" => sector,
        )
    elseif stype == "consumption"
        multiplier = _shock_number(normalized, "multiplier", 1.0)
        0.0 < multiplier <= 10.0 || throw(
            ApiError(
                400,
                "Consumption multiplier must be greater than 0 and at most 10",
                (multiplier = multiplier,),
            ),
        )
        return Dict{String, Any}(
            "type" => stype,
            "multiplier" => multiplier,
            "final_time" => _shock_final_time(normalized, horizon),
        )
    end
    throw(
        ApiError(
            400,
            "Unknown shock type: $stype",
            (allowed = ["none", "interest_rate", "productivity", "sector_productivity", "consumption"],),
        ),
    )
end

struct _AnnualizedInterestRateDeltaShock
    annual_rate::Float64
    final_time::Int
end

struct _SectorProductivityShock
    multiplier::Float64
    sector::Int
end

function (shock::_SectorProductivityShock)(model::Bit.AbstractModel)
    model.agg.t == 1 || return nothing
    maximum(model.firms.G_i; init = 0) >= shock.sector || throw(
        ApiError(
            400,
            "Sector-productivity shock sector is outside this dataset",
            (sector = shock.sector,),
        ),
    )
    selected = model.firms.G_i .== shock.sector
    any(selected) || throw(
        ApiError(
            400,
            "Sector-productivity shock selected a sector with no model firms",
            (sector = shock.sector,),
        ),
    )
    model.firms.alpha_bar_i[selected] .*= shock.multiplier
    return nothing
end

function (shock::_AnnualizedInterestRateDeltaShock)(
        model::Bit.AbstractModel,
    )
    model.agg.t <= shock.final_time || return nothing
    current_annual = (1.0 + model.cb.r_bar)^4 - 1.0
    shocked_annual = current_annual + shock.annual_rate
    shocked_annual > -1.0 || throw(
        ApiError(
            400,
            "Interest-rate shock would push the annual rate to or below -100%",
        ),
    )
    model.cb.r_bar = (1.0 + shocked_annual)^(1 / 4) - 1.0
    return nothing
end

function _shock_from_spec(shock::Any, horizon::Integer)
    normalized = _normalize_shock_spec(shock, horizon)
    stype = normalized["type"]
    if stype == "none"
        return Bit.NoShock()
    elseif stype == "interest_rate"
        return _AnnualizedInterestRateDeltaShock(
            normalized["annual_rate"],
            normalized["final_time"],
        )
    elseif stype == "productivity"
        return Bit.ProductivityShock(normalized["multiplier"])
    elseif stype == "sector_productivity"
        return _SectorProductivityShock(
            normalized["multiplier"],
            normalized["sector"],
        )
    elseif stype == "consumption"
        return Bit.ConsumptionShock(
            normalized["multiplier"],
            normalized["final_time"],
        )
    end
    error("Validated shock type was not handled: $stype")
end

include("cashflows.jl")
include("experiments.jl")

function _summarize_series(mat::AbstractMatrix{<:Real})
    m = vec(mean(mat; dims = 2))
    s = vec(std(mat; dims = 2, corrected = false))
    return m, s
end

function _normalize_output_path_correction(
        series_name::AbstractString,
        path_correction,
    )
    if !(
            path_correction isa AbstractDict ||
                path_correction isa JSON3.Object
        )
        throw(
            ArgumentError(
                "output_measurement.series.$series_name.path_correction must be a dictionary",
            ),
        )
    end
    correction = _normalize_dict(path_correction)

    method = get(correction, "method", nothing)
    method isa AbstractString &&
        method == "damped_log_bias" || throw(
        ArgumentError(
            "output_measurement.series.$series_name.path_correction.method must be damped_log_bias",
        ),
    )

    function finite_number(field::AbstractString)
        haskey(correction, field) || throw(
            ArgumentError(
                "output_measurement.series.$series_name.path_correction.$field is required",
            ),
        )
        value = correction[field]
        value isa Real && !(value isa Bool) || throw(
            ArgumentError(
                "output_measurement.series.$series_name.path_correction.$field must be numeric",
            ),
        )
        number = Float64(value)
        isfinite(number) || throw(
            ArgumentError(
                "output_measurement.series.$series_name.path_correction.$field must be finite",
            ),
        )
        return number
    end

    amplitude = finite_number("amplitude")
    decay = finite_number("decay")
    decay > 0 || throw(
        ArgumentError(
            "output_measurement.series.$series_name.path_correction.decay must be positive",
        ),
    )

    origin_horizon_value = get(correction, "origin_horizon", 0)
    if !(
            origin_horizon_value isa Integer &&
                !(origin_horizon_value isa Bool)
        )
        throw(
            ArgumentError(
                "output_measurement.series.$series_name.path_correction.origin_horizon must be a nonnegative integer",
            ),
        )
    end
    origin_horizon = try
        Int(origin_horizon_value)
    catch
        throw(
            ArgumentError(
                "output_measurement.series.$series_name.path_correction.origin_horizon must fit in an Int",
            ),
        )
    end
    origin_horizon >= 0 || throw(
        ArgumentError(
            "output_measurement.series.$series_name.path_correction.origin_horizon must be a nonnegative integer",
        ),
    )

    correction["method"] = "damped_log_bias"
    correction["amplitude"] = amplitude
    correction["decay"] = decay
    correction["origin_horizon"] = origin_horizon
    get!(
        correction,
        "formula",
        "factor(h) = exp(amplitude * (1 - exp(-decay * h))); factor(0) = 1"
    )
    correction["origin_factor"] =
        exp(amplitude * (1 - exp(-decay * origin_horizon)))
    correction["applied_formula"] =
        "relative_factor(h) = factor(origin_horizon + h) / factor(origin_horizon); relative_factor(0) = 1"
    return correction
end

function _apply_output_path_correction(
        values::AbstractArray{<:Real},
        correction::AbstractDict,
        series_name::AbstractString,
    )
    dimensions = ndims(values)
    dimensions in (1, 2) || throw(
        ArgumentError(
            "output_measurement path_correction for $series_name supports only vectors and matrices",
        ),
    )

    horizon_count = size(values, 1)
    amplitude = correction["amplitude"]
    decay = correction["decay"]
    origin_horizon = correction["origin_horizon"]
    factors = [
        exp(
                amplitude * (
                    exp(-decay * origin_horizon) -
                    exp(-decay * (origin_horizon + horizon))
                ),
            ) for
            horizon in 0:(horizon_count - 1)
    ]
    isempty(factors) || (factors[1] = 1.0)
    if dimensions == 1
        return values .* factors
    end
    return values .* reshape(factors, :, 1)
end

"""
    _output_measurement_series(output_measurement)

Normalize the artifact's output-measurement contract and return its per-series
entries. The canonical layout nests entries below `series`; accepting entries
directly at the top level keeps older locally-built artifacts readable.
"""
function _output_measurement_series(output_measurement)
    measurement = if output_measurement === nothing
        Dict{String, Any}()
    elseif output_measurement isa AbstractDict ||
            output_measurement isa JSON3.Object
        _normalize_dict(output_measurement)
    else
        throw(
            ArgumentError(
                "output_measurement must be a dictionary",
            ),
        )
    end

    canonical = haskey(measurement, "series")
    entries = canonical ? measurement["series"] : measurement
    if !(entries isa AbstractDict || entries isa JSON3.Object)
        throw(
            ArgumentError(
                "output_measurement.series must be a dictionary",
            ),
        )
    end

    normalized = Dict{String, Dict{String, Any}}()
    for (name_any, entry_any) in pairs(entries)
        name = String(name_any)
        if !(entry_any isa AbstractDict || entry_any isa JSON3.Object)
            canonical && throw(
                ArgumentError(
                    "output_measurement.series.$name must be a dictionary",
                ),
            )
            continue
        end
        entry = _normalize_dict(entry_any)
        if !haskey(entry, "scale")
            canonical && throw(
                ArgumentError(
                    "output_measurement.series.$name is missing scale",
                ),
            )
            continue
        end
        scale = try
            Float64(entry["scale"])
        catch
            throw(
                ArgumentError(
                    "output_measurement.series.$name.scale must be numeric",
                ),
            )
        end
        isfinite(scale) && scale > 0 || throw(
            ArgumentError(
                "output_measurement.series.$name.scale must be finite and positive",
            ),
        )
        entry["scale"] = scale
        if haskey(entry, "path_correction")
            entry["path_correction"] =
                _normalize_output_path_correction(
                name,
                entry["path_correction"],
            )
        end
        normalized[name] = entry
    end
    return measurement, normalized
end

"""
    _apply_output_measurement(raw_series, output_measurement)

Apply explicitly configured, multiplicative publication scales without
mutating the model series. GDP deflator is always derived after adjustment so
it remains consistent with the published real-GDP level.
"""
function _apply_output_measurement(
        raw_series::AbstractDict,
        output_measurement,
    )
    measurement, specifications =
        _output_measurement_series(output_measurement)
    raw = Dict{String, Any}(
        String(name) => values for (name, values) in pairs(raw_series)
    )
    adjusted = copy(raw)
    applied = Dict{String, Any}()
    path_corrected = Dict{String, Any}()
    unmatched = String[]
    ignored_derived = String[]

    for name in sort!(collect(keys(specifications)))
        if name == "gdp_deflator"
            push!(ignored_derived, name)
            continue
        elseif !haskey(raw, name)
            push!(unmatched, name)
            continue
        elseif !(raw[name] isa AbstractArray{<:Real})
            throw(
                ArgumentError(
                    "Configured output series $name must be a numeric array",
                ),
            )
        end

        entry = deepcopy(specifications[name])
        scale = entry["scale"]
        published = raw[name] .* scale
        if haskey(entry, "path_correction")
            published = _apply_output_path_correction(
                published,
                entry["path_correction"],
                name,
            )
            entry["formula"] =
                "published_value[h] = model_raw_value[h] * scale * factor(origin_horizon + h) / factor(origin_horizon)"
            path_corrected[name] =
                deepcopy(entry["path_correction"])
        else
            entry["formula"] =
                "published_value = model_raw_value * scale"
        end
        adjusted[name] = published
        applied[name] = entry
    end

    deflator_derived = false
    if haskey(raw, "nominal_gdp") && haskey(adjusted, "real_gdp")
        adjusted["gdp_deflator"] =
            raw["nominal_gdp"] ./ adjusted["real_gdp"]
        deflator_derived = true
    end

    adjustment = Dict{String, Any}(
        "applied" => !isempty(applied),
        "schema_version" =>
            get(measurement, "schema_version", nothing),
        "method" => get(measurement, "method", nothing),
        "origin_period" => get(measurement, "origin_period", nothing),
        "formula" => "published_value = model_raw_value * scale",
        "raw_series_field" => "model_raw",
        "adjusted_series" => applied,
        "path_corrected_series" => path_corrected,
        "configured_series" => sort!(collect(keys(specifications))),
        "unmatched_configured_series" => unmatched,
        "ignored_derived_series" => ignored_derived,
        "sector_real_gva_adjusted" =>
            haskey(applied, "real_sector_gva"),
        "gdp_deflator" => Dict{String, Any}(
            "derived" => deflator_derived,
            "formula" => "nominal_gdp / published_real_gdp",
            "uses_adjusted_real_gdp" =>
                haskey(applied, "real_gdp"),
        ),
    )
    return adjusted, adjustment
end

function _sanitize_number_for_json(value::Real)
    value isa Integer && return value
    number = Float64(value)
    return isfinite(number) ? number : nothing
end

function _sanitize_array_for_json(array::AbstractArray{<:Real})
    if ndims(array) == 1
        return [_sanitize_number_for_json(value) for value in array]
    elseif ndims(array) == 2
        return [
            [_sanitize_number_for_json(array[row, column]) for column in axes(array, 2)]
                for row in axes(array, 1)
        ]
    end
    throw(ArgumentError("JSON export supports vectors and matrices only"))
end

function _sanitize_for_json(v)
    if v isa Bool
        return v
    elseif v isa AbstractArray{Bool}
        if ndims(v) == 1
            return [Bool(value) for value in v]
        elseif ndims(v) == 2
            return [
                [Bool(v[row, column]) for column in axes(v, 2)] for
                    row in axes(v, 1)
            ]
        end
        throw(ArgumentError("JSON export supports Boolean vectors and matrices only"))
    elseif v isa AbstractArray{<:Real}
        return _sanitize_array_for_json(v)
    elseif v isa Real
        return _sanitize_number_for_json(v)
    elseif v isa AbstractArray
        return [_sanitize_for_json(value) for value in v]
    elseif v isa AbstractDict
        out = Dict{String, Any}()
        for (k, val) in v
            out[String(k)] = _sanitize_for_json(val)
        end
        return out
    elseif v isa NamedTuple
        return Dict(
            String(key) => _sanitize_for_json(value) for
                (key, value) in pairs(v)
        )
    else
        return v
    end
end

function _run_verify_static_provenance(
        stored,
        current::AbstractDict,
    )
    stored_dict =
        stored === nothing ? Dict{String, Any}() : _normalize_dict(stored)
    isempty(stored_dict) && return deepcopy(current)
    failures = Any[]
    for key in sort!(collect(keys(current)))
        if !haskey(stored_dict, key)
            push!(
                failures,
                Dict(
                    "field" => key,
                    "reason" => "missing_from_stored_run_spec",
                ),
            )
        elseif _run_provenance_canonical(stored_dict[key]) !=
                _run_provenance_canonical(current[key])
            push!(
                failures,
                Dict(
                    "field" => key,
                    "reason" => "stored_value_does_not_match_worker",
                    "stored" => stored_dict[key],
                    "worker" => current[key],
                ),
            )
        end
    end
    isempty(failures) || throw(
        ApiError(
            409,
            "Run provenance changed between specification and execution",
            Dict("failures" => failures),
        ),
    )
    return deepcopy(current)
end

function _run_complete_provenance(
        static_provenance::AbstractDict,
        model;
        realization_index::Integer,
        realization_seed::Integer,
    )
    provenance = deepcopy(static_provenance)
    provenance["initial_state_digest"] =
        _run_provenance_digest(_run_initial_state_payload(model))
    provenance["initial_state"] = Dict{String, Any}(
        "realization_index" => Int(realization_index),
        "realization_seed" => Int(realization_seed),
        "timing" => "after model construction and before the first shock/step",
        "scope" =>
            "all economic model fields except the empty output accumulator",
        "array_contract" =>
            "element type, full shape, and column-major values are hashed",
    )
    provenance["execution_environment"] = Dict{String, Any}(
        "julia_version" => string(VERSION),
        "thread_count" => Threads.nthreads(),
        "architecture" => string(Sys.ARCH),
        "kernel" => string(Sys.KERNEL),
        "word_size" => Sys.WORD_SIZE,
        "scope" =>
            "Replay compatibility evidence; paired runs require exact agreement",
    )
    return provenance
end

function run_worker(run_path::AbstractString)
    started_at = _now_utc_iso()
    _write_status(run_path; state = "running", progress = 0.0, message = "starting", started_at = started_at)

    try
        spec = _normalize_dict(
            JSON3.read(read(joinpath(run_path, "spec.json"), String)),
        )
        dataset_id = String(spec["dataset_id"])
        scenario = _normalize_scenario(
            dataset_id,
            String(get(spec, "scenario", "unconditional")),
        )
        sim = spec["sim"]
        T = Int(get(sim, "T", 20))
        n_sims = Int(get(sim, "n_sims", 16))
        step_multithreading_any = get(sim, "step_multithreading", true)
        step_multithreading =
            step_multithreading_any isa Bool ? step_multithreading_any :
            step_multithreading_any isa Number ? step_multithreading_any != 0 : true
        base_seed = Int(get(sim, "base_seed", 1234))
        trace = _normalize_trace_spec(
            get(spec, "trace", Dict{String, Any}()),
        )
        trace_profile = String(trace["profile"])
        trace_indices = Int.(collect(trace["realization_indices"]))
        traced_realization = isempty(trace_indices) ? nothing : first(trace_indices)

        if !(1 <= T <= 80)
            throw(ApiError(400, "T out of bounds", (T = T,)))
        end
        if !(1 <= n_sims <= 64)
            throw(ApiError(400, "n_sims out of bounds", (n_sims = n_sims,)))
        end
        length(trace_indices) <= 1 || throw(
            ApiError(
                400,
                "Only one representative trace is supported per run",
                (requested = trace_indices,),
            ),
        )
        all(index -> index <= n_sims, trace_indices) || throw(
            ApiError(
                400,
                "Traced realization exceeds n_sims",
                (requested = trace_indices, n_sims = n_sims),
            ),
        )
        if scenario != "unconditional" && T > 23
            throw(
                ApiError(
                    400,
                    "Conditional scenario horizon exceeds 2031 Q4",
                    (T = T, maximum = 23),
                ),
            )
        end

        params0, inits0 = _dataset_by_id(dataset_id)
        params = copy(params0)
        inits = copy(inits0)
        params, inits = _apply_overrides!(params, inits, spec["overrides"])
        static_provenance = _run_static_provenance(
            dataset_id,
            scenario,
            params0,
            inits0,
            params,
            inits,
            sim,
            trace,
        )
        static_provenance = _run_verify_static_provenance(
            get(spec, "provenance", nothing),
            static_provenance,
        )
        initialization_realization =
            traced_realization === nothing ? 1 : traced_realization
        completed_provenance = nothing

        shock = _shock_from_spec(spec["shock"], T)
        metadata = dataset_metadata(dataset_id)
        periods = _quarter_labels(String(metadata["period"]), T)
        run_id = String(get(spec, "run_id", basename(run_path)))
        scale_maxima = Dict{String, Float64}()
        scale_counts = Dict{String, Int}()
        firm_directory = Any[]
        sector_directory = Any[]

        data_vec = Vector{Bit.Data}(undef, n_sims)
        for sim_i in 1:n_sims
            Random.seed!(base_seed + sim_i)
            model = _build_model(
                dataset_id,
                scenario,
                params,
                inits,
                T,
            )

            if sim_i == initialization_realization
                completed_provenance = _run_complete_provenance(
                    static_provenance,
                    model;
                    realization_index = sim_i,
                    realization_seed = base_seed + sim_i,
                )
                stored_provenance = _normalize_dict(
                    get(spec, "provenance", Dict{String, Any}()),
                )
                if haskey(stored_provenance, "initial_state_digest") &&
                        _run_provenance_canonical(
                        stored_provenance["initial_state_digest"],
                    ) !=
                        _run_provenance_canonical(
                        completed_provenance["initial_state_digest"],
                    )
                    throw(
                        ApiError(
                            409,
                            "Initialized model state does not match the persisted run provenance",
                            Dict(
                                "stored_initial_state_digest" =>
                                    stored_provenance["initial_state_digest"],
                                "worker_initial_state_digest" =>
                                    completed_provenance["initial_state_digest"],
                            ),
                        ),
                    )
                end
                spec["provenance"] = completed_provenance
                _experiment_write_json(
                    joinpath(run_path, "spec.json"),
                    spec,
                )
            end

            if sim_i == traced_realization
                opening_payload = _cashflow_opening_payload(
                    model;
                    run_id,
                    dataset_id,
                    scenario,
                    period = periods[1],
                    realization_index = sim_i,
                    realization_seed = base_seed + sim_i,
                    ensemble_size = n_sims,
                )
                firm_directory = collect(opening_payload["firms"])
                sector_directory = collect(opening_payload["sectors"])
                _cashflow_compact_payload!(opening_payload)
                jldsave(
                    joinpath(run_path, "cashflow-0.jld2"),
                    false;
                    payload = opening_payload,
                )
            end

            for epoch in 1:T
                if sim_i == traced_realization
                    relationships, transaction_logger =
                        _cashflow_collector(
                        model;
                        markets = (:business_goods, :final_demand),
                    )
                    pre_step = _cashflow_snapshot(model)
                    opening = Ref{Any}(nothing)
                    capture_opening =
                        opening_model ->
                    opening[] = _cashflow_snapshot(opening_model)
                    Bit.step!(
                        model;
                        parallel = step_multithreading,
                        shock! = shock,
                        transaction_logger,
                        transaction_markets =
                            (:business_goods, :final_demand),
                        opening_state_logger = capture_opening,
                    )
                    opening[] === nothing &&
                        error("Cash-flow opening snapshot was not collected")
                    Bit.collect_data!(model)
                    payload = _cashflow_payload(
                        model,
                        relationships,
                        pre_step,
                        opening[];
                        run_id,
                        dataset_id,
                        scenario,
                        period = periods[epoch + 1],
                        quarter_index = epoch,
                        summary_index = epoch + 1,
                        realization_index = sim_i,
                        realization_seed = base_seed + sim_i,
                        ensemble_size = n_sims,
                    )
                    for edge in payload["edges"]
                        domain = _cashflow_edge_domain(edge)
                        value = abs(
                            Float64(
                                get(
                                    edge,
                                    "signed_value",
                                    edge["amount"],
                                ),
                            ),
                        )
                        scale_maxima[domain] =
                            max(get(scale_maxima, domain, 0.0), value)
                        scale_counts[domain] =
                            get(scale_counts, domain, 0) + 1
                    end
                    _cashflow_compact_payload!(payload)
                    jldsave(
                        joinpath(run_path, "cashflow-$(epoch).jld2"),
                        false;
                        payload,
                    )
                else
                    Bit.step!(
                        model;
                        parallel = step_multithreading,
                        shock! = shock,
                    )
                    Bit.collect_data!(model)
                end
                progress = (sim_i - 1 + epoch / T) / n_sims
                _write_status(run_path; state = "running", progress = progress, message = "sim $(sim_i)/$(n_sims), epoch $(epoch)/$(T)", started_at = started_at)
            end

            data_vec[sim_i] = model.data
        end

        if traced_realization !== nothing
            scale_domains = Dict{String, Any}(
                domain => Dict{String, Any}(
                        "min" => 0.0,
                        "max" => scale_maxima[domain],
                        "mapping" => "sqrt",
                        "count" => scale_counts[domain],
                    ) for domain in sort!(collect(keys(scale_maxima)))
            )
            cashflow_manifest = Dict{String, Any}(
                "schema_version" => CASHFLOW_SCHEMA_VERSION,
                "trace_schema_version" => CASHFLOW_SCHEMA_VERSION,
                "api_schema_version" => CASHFLOW_API_SCHEMA_VERSION,
                "run_id" => run_id,
                "dataset_id" => dataset_id,
                "scenario" => scenario,
                "trace_profile" => trace_profile,
                "quarters" => collect(0:T),
                "periods" => periods,
                "initial_period" => periods[1],
                "initial_period_has_flows" => false,
                "units" => _cashflow_units(dataset_id),
                "realization" => Dict(
                    "index" => traced_realization,
                    "seed" => base_seed + traced_realization,
                    "ensemble_size" => n_sims,
                ),
                "traced_realizations" => [traced_realization],
                "provenance" => completed_provenance,
                "firm_directory" => firm_directory,
                "sector_directory" => sector_directory,
                "scale_domains" => scale_domains,
                "capabilities" => Dict(
                    "normalized_edges" => true,
                    "institution_flows" => true,
                    "institution_components" => true,
                    "sector_network" => true,
                    "firm_network" => true,
                    "business_counterparties" => true,
                    "final_demand_counterparties" => true,
                    "capacity_counterfactual" => true,
                    "true_unmet_demand" => false,
                    "household_cohorts" => true,
                    "node_stock_flow_reconciliation" => true,
                    "opening_snapshot" => true,
                    "phase_trace" => false,
                    "checkpoints" => false,
                ),
            )
            open(joinpath(run_path, "cashflows-manifest.json"), "w") do io
                write(io, JSON3.write(cashflow_manifest))
            end
        end

        dv = Bit.DataVector(data_vec)

        outputs = Dict{String, Any}()
        outputs["t"] = collect(1:(T + 1))
        outputs["periods"] = periods
        outputs["T"] = T
        outputs["n_sims"] = n_sims
        outputs["dataset_id"] = dataset_id
        outputs["dataset_metadata"] = metadata
        outputs["scenario"] = scenario
        outputs["forecast_start_period"] =
            _next_quarter(String(metadata["period"]))
        outputs["trace_profile"] = trace_profile
        outputs["cashflows_available"] = traced_realization !== nothing
        outputs["created_at"] = String(get(spec, "created_at", ""))
        outputs["run_id"] = run_id

        series_names = [
            "real_gdp",
            "real_household_consumption",
            "real_government_consumption",
            "real_fixed_capitalformation",
            "real_exports",
            "real_imports",
            "wages",
            "euribor_q",
            "gdp_deflator",
        ]

        # Sector paths are T+1 x G x n_sims. They participate in the same
        # adapter, but are adjusted only when explicitly configured.
        sector_paths = [
            permutedims(reduce(hcat, data.real_sector_gva)) for
                data in dv.vector
        ]
        sector = cat(sector_paths...; dims = 3)

        raw_series = Dict{String, Any}(
            "nominal_gdp" => dv.nominal_gdp,
            "real_gdp" => dv.real_gdp,
            "real_household_consumption" =>
                dv.real_household_consumption,
            "real_government_consumption" =>
                dv.real_government_consumption,
            "real_fixed_capitalformation" =>
                dv.real_fixed_capitalformation,
            "real_exports" => dv.real_exports,
            "real_imports" => dv.real_imports,
            "wages" => dv.wages,
            "euribor_q" => dv.euribor,
            "gdp_deflator" => dv.nominal_gdp ./ dv.real_gdp,
            "real_sector_gva" => sector,
        )
        adjusted_series, measurement_adjustment =
            _apply_output_measurement(
            raw_series,
            get(metadata, "output_measurement", Dict{String, Any}()),
        )
        outputs["measurement_adjustment"] = measurement_adjustment

        model_raw = Dict{String, Any}()
        applied_measurements =
            measurement_adjustment["adjusted_series"]
        for name in series_names
            mean_v, std_v =
                _summarize_series(adjusted_series[name])
            summary = Dict{String, Any}(
                "mean" => mean_v,
                "std" => std_v,
            )
            if haskey(applied_measurements, name)
                summary["measurement"] =
                    applied_measurements[name]
            elseif name == "gdp_deflator"
                summary["measurement"] =
                    measurement_adjustment["gdp_deflator"]
            end
            outputs[name] = summary

            raw_mean, raw_std =
                _summarize_series(raw_series[name])
            model_raw[name] =
                Dict("mean" => raw_mean, "std" => raw_std)
        end

        nominal_mean, nominal_std =
            _summarize_series(raw_series["nominal_gdp"])
        model_raw["nominal_gdp"] =
            Dict("mean" => nominal_mean, "std" => nominal_std)

        euribor_annual = (1 .+ dv.euribor) .^ 4 .- 1
        mean_v, std_v = _summarize_series(euribor_annual)
        outputs["euribor_annual"] =
            Dict("mean" => mean_v, "std" => std_v)
        model_raw["euribor_annual"] =
            Dict("mean" => mean_v, "std" => std_v)

        sector_adjusted = adjusted_series["real_sector_gva"]
        sector_mean = mean(sector_adjusted; dims = 3)[:, :, 1]
        sector_std =
            std(sector_adjusted; dims = 3, corrected = false)[:, :, 1]
        sector_summary = Dict{String, Any}(
            "mean" => sector_mean,
            "std" => sector_std,
        )
        if haskey(applied_measurements, "real_sector_gva")
            sector_summary["measurement"] =
                applied_measurements["real_sector_gva"]
        end
        outputs["real_sector_gva"] = sector_summary

        raw_sector_mean = mean(sector; dims = 3)[:, :, 1]
        raw_sector_std =
            std(sector; dims = 3, corrected = false)[:, :, 1]
        model_raw["real_sector_gva"] = Dict(
            "mean" => raw_sector_mean,
            "std" => raw_sector_std,
        )
        outputs["model_raw"] = model_raw

        # persist
        jldsave(joinpath(run_path, "results.jld2"); data_vector = dv, summary = outputs)
        outputs_json = _sanitize_for_json(outputs)
        open(joinpath(run_path, "summary.json"), "w") do io
            write(io, JSON3.write(outputs_json))
        end

        # simple CSV export (mean/std only)
        csv_path = joinpath(run_path, "summary.csv")
        open(csv_path, "w") do io
            header = ["t", "period"]
            for name in series_names
                push!(header, "$(name)_mean")
                push!(header, "$(name)_std")
            end
            push!(header, "euribor_annual_mean")
            push!(header, "euribor_annual_std")
            write(io, join(header, ",") * "\n")
            for i in 1:(T + 1)
                row = [string(i), outputs["periods"][i]]
                for name in series_names
                    push!(row, string(outputs[name]["mean"][i]))
                    push!(row, string(outputs[name]["std"][i]))
                end
                push!(row, string(outputs["euribor_annual"]["mean"][i]))
                push!(row, string(outputs["euribor_annual"]["std"][i]))
                write(io, join(row, ",") * "\n")
            end
        end

        finished_at = _now_utc_iso()
        _write_status(run_path; state = "done", progress = 1.0, message = "done", started_at = started_at, finished_at = finished_at)
        return nothing
    catch e
        finished_at = _now_utc_iso()
        msg = sprint(showerror, e)
        _write_status(run_path; state = "error", progress = 1.0, message = msg, started_at = started_at, finished_at = finished_at)
        rethrow()
    end
end

function _asset_file_response(root::AbstractString, path::AbstractString)
    normalized_root = abspath(root)
    full = abspath(joinpath(normalized_root, path))
    relative = relpath(full, normalized_root)
    (relative == ".." || startswith(relative, "../") || isabspath(relative)) &&
        throw(ApiError(403, "Forbidden"))
    isfile(full) || throw(ApiError(404, "Not found"))

    ext = lowercase(splitext(full)[2])
    ctype = if ext == ".html"
        "text/html; charset=utf-8"
    elseif ext == ".js"
        "application/javascript; charset=utf-8"
    elseif ext == ".css"
        "text/css; charset=utf-8"
    elseif ext == ".json"
        "application/json; charset=utf-8"
    elseif ext == ".svg"
        "image/svg+xml"
    elseif ext == ".png"
        "image/png"
    elseif ext == ".jpg" || ext == ".jpeg"
        "image/jpeg"
    elseif ext == ".webp"
        "image/webp"
    else
        "application/octet-stream"
    end

    headers = ["Content-Type" => ctype, "Cache-Control" => "no-store"]
    return HTTP.Response(200, headers, read(full))
end

_static_file_response(path::AbstractString) =
    _asset_file_response(PUBLIC_DIR, path)

_prototype_file_response(path::AbstractString) =
    _asset_file_response(PROTOTYPES_DIR, path)

_explorer_file_response(path::AbstractString) =
    _asset_file_response(EXPLORER_DIR, path)

function start_server(; host::AbstractString = "127.0.0.1", port::Int = 8080)
    _ensure_dir(RUNS_DIR)

    router = HTTP.Router()

    HTTP.register!(router, "GET", "/", _req -> _static_file_response("index.html"))
    HTTP.register!(router, "GET", "/app.js", _req -> _static_file_response("app.js"))
    HTTP.register!(router, "GET", "/style.css", _req -> _static_file_response("style.css"))
    HTTP.register!(router, "GET", "/sector-metadata.json", _req -> _static_file_response("sector-metadata.json"))

    HTTP.register!(router, "GET", "/api/datasets", _req -> _json_response(200, available_datasets()))

    HTTP.register!(
        router, "GET", "/api/datasets/metadata", req -> begin
            q = HTTP.queryparams(HTTP.URI(req.target))
            dataset_id = get(q, "dataset_id", "AUSTRIA2026Q1")
            return _json_response(200, dataset_metadata(dataset_id))
        end
    )

    HTTP.register!(
        router, "GET", "/api/scenarios", req -> begin
            q = HTTP.queryparams(HTTP.URI(req.target))
            dataset_id = get(q, "dataset_id", "AUSTRIA2026Q1")
            scenario = get(
                q,
                "scenario",
                _dataset_spec(dataset_id).default_scenario,
            )
            return _json_response(
                200,
                Dict(
                    "dataset_id" => dataset_id,
                    "scenario" => scenario,
                    "assumptions" =>
                        scenario_assumptions(dataset_id, scenario),
                ),
            )
        end
    )

    HTTP.register!(
        router, "GET", "/api/knobs", req -> begin
            q = HTTP.queryparams(HTTP.URI(req.target))
            dataset_id = get(q, "dataset_id", "AUSTRIA2026Q1")
            return _json_response(200, get_knobs(dataset_id))
        end
    )

    HTTP.register!(
        router, "GET", "/api/datasets/schema", req -> begin
            q = HTTP.queryparams(HTTP.URI(req.target))
            dataset_id = get(q, "dataset_id", "AUSTRIA2026Q1")
            params, inits = _dataset_by_id(dataset_id)
            return _json_response(
                200,
                Dict(
                    "dataset_id" => dataset_id,
                    "parameters" => summarize_dict(params),
                    "initial_conditions" => summarize_dict(inits),
                ),
            )
        end
    )

    HTTP.register!(
        router, "GET", "/api/datasets/value", req -> begin
            q = HTTP.queryparams(HTTP.URI(req.target))
            dataset_id = get(q, "dataset_id", "AUSTRIA2026Q1")
            group = get(q, "group", "")
            key = get(q, "key", "")
            (group in ("parameters", "initial_conditions")) || throw(ApiError(400, "Invalid group"))
            isempty(key) && throw(ApiError(400, "Missing key"))
            params, inits = _dataset_by_id(dataset_id)
            d = group == "parameters" ? params : inits
            haskey(d, key) || throw(ApiError(404, "Unknown key"))
            v = d[key]
            kind, shape = _value_kind_and_shape(v)
            return _json_response(200, Dict("dataset_id" => dataset_id, "group" => group, "key" => key, "kind" => kind, "shape" => shape, "value" => _json_value(v)))
        end
    )

    HTTP.register!(router, "GET", "/api/runs", _req -> _json_response(200, list_runs()))

    HTTP.register!(
        router,
        "GET",
        "/api/experiments",
        _req -> _json_response(200, _sanitize_for_json(list_experiments())),
    )

    HTTP.register!(
        router,
        "POST",
        "/api/experiments",
        req -> _create_experiment_response(_read_json(req)),
    )

    HTTP.register!(
        router,
        "GET",
        "/api/compare/cashflows",
        req -> begin
            q = HTTP.queryparams(HTTP.URI(req.target))
            run_a = get(q, "run_a", nothing)
            run_b = get(q, "run_b", nothing)
            quarter = _query_integer(q, "quarter")
            run_a === nothing && throw(ApiError(400, "run_a is required"))
            run_b === nothing && throw(ApiError(400, "run_b is required"))
            quarter === nothing &&
                throw(ApiError(400, "quarter is required"))
            return _compare_cashflows_response(
                ;
                run_a,
                run_b,
                quarter,
                level = get(q, "level", "sector"),
                layers = get(q, "layers", nothing),
                focus = get(q, "focus", nothing),
                direction = get(q, "direction", nothing),
                recognition = get(q, "recognition", nothing),
                coverage = _query_float(q, "coverage", 1.0),
                limit = _query_integer(q, "limit", 1000),
                min_amount = _query_float(q, "min_amount", 0.0),
                min_delta = _query_float(q, "min_delta", 0.0),
                include_unchanged =
                    _query_boolean(q, "include_unchanged", false),
                include_counterfactual =
                    _query_boolean(q, "include_potential", false),
                experiment_id = get(q, "experiment_id", nothing),
            )
        end,
    )

    HTTP.register!(
        router, "POST", "/api/runs", req -> begin
            obj = _read_json(req)
            dataset_id = String(get(obj, :dataset_id, "AUSTRIA2026Q1"))
            scenario = String(
                get(
                    obj,
                    :scenario,
                    _dataset_spec(dataset_id).default_scenario,
                ),
            )
            sim = haskey(obj, :sim) ? _normalize_dict(obj[:sim]) : Dict{String, Any}()
            overrides = haskey(obj, :overrides) ? _normalize_dict(obj[:overrides]) : Dict{String, Any}()
            shock = haskey(obj, :shock) ? _normalize_dict(obj[:shock]) : Dict{String, Any}("type" => "none")
            trace = haskey(obj, :trace) ? _normalize_dict(obj[:trace]) : Dict{String, Any}()
            run_id = create_run(
                dataset_id;
                name = get(obj, :name, nothing),
                description = get(obj, :description, nothing),
                parent_run_id = get(obj, :parent_run_id, nothing),
                experiment_id = get(obj, :experiment_id, nothing),
                experiment_role = get(obj, :experiment_role, nothing),
                scenario,
                sim,
                overrides,
                shock,
                trace,
            )
            return _json_response(200, Dict("run_id" => run_id))
        end
    )

    handler = function (req::HTTP.Request)
        try
            uri = HTTP.URI(req.target)
            path = String(uri.path)

            if req.method == "GET" && path == "/explorer"
                return HTTP.Response(
                    308,
                    [
                        "Location" => "/explorer/",
                        "Cache-Control" => "no-store",
                    ],
                )
            elseif req.method == "GET" && startswith(path, "/explorer/")
                relative = path[(length("/explorer/") + 1):end]
                if isempty(relative) || endswith(relative, "/")
                    relative = joinpath(relative, "index.html")
                end
                return _explorer_file_response(relative)
            elseif req.method == "GET" && path == "/prototypes"
                return HTTP.Response(
                    308,
                    [
                        "Location" => "/prototypes/",
                        "Cache-Control" => "no-store",
                    ],
                )
            elseif req.method == "GET" && startswith(path, "/prototypes/")
                relative = path[(length("/prototypes/") + 1):end]
                if isempty(relative) || endswith(relative, "/")
                    relative = joinpath(relative, "index.html")
                end
                return _prototype_file_response(relative)
            end

            if req.method == "GET" && startswith(path, "/api/datasets/")
                parts = split(path, '/')
                if length(parts) == 5 && parts[5] == "sector-metadata"
                    dataset_id = HTTP.unescapeuri(parts[4])
                    return _json_response(200, sector_metadata(dataset_id))
                end
            end

            if req.method == "GET" && startswith(path, "/api/experiments/")
                parts = split(path, '/')
                length(parts) == 4 ||
                    throw(ApiError(404, "Unknown experiment route"))
                return _get_experiment_response(
                    HTTP.unescapeuri(parts[4]),
                )
            end

            if startswith(path, "/api/runs/")
                parts = split(path, '/')
                if length(parts) >= 5
                    run_id = parts[4]
                    action = parts[5]
                    if !all(c -> isxdigit(c) || c == '-', run_id)
                        throw(ApiError(400, "Invalid run_id"))
                    end
                    run_path = _run_dir(run_id)
                    isdir(run_path) || throw(ApiError(404, "Unknown run_id"))

                    if req.method == "GET" && action == "status"
                        status = _read_json_file(joinpath(run_path, "status.json"))
                        status === nothing && throw(ApiError(404, "Missing status"))
                        return _json_response(200, status)
                    elseif req.method == "GET" && action == "summary"
                        summary_path = joinpath(run_path, "summary.json")
                        isfile(summary_path) || throw(ApiError(404, "Summary not ready"))
                        headers = ["Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store"]
                        return HTTP.Response(200, headers, read(summary_path))
                    elseif req.method == "GET" && action == "spec"
                        return _json_response(
                            200,
                            _run_spec_payload(run_path),
                        )
                    elseif req.method == "GET" && action == "cashflows" &&
                            length(parts) == 6 && parts[6] == "export"
                        q = HTTP.queryparams(uri)
                        quarter = _query_integer(q, "quarter")
                        quarter === nothing &&
                            throw(ApiError(400, "quarter is required for export"))
                        export_payload = _cashflow_export_payload(
                            run_path;
                            quarter,
                            level = get(q, "level", "all"),
                            focus = get(q, "focus", nothing),
                            layers = get(q, "layers", nothing),
                            recognition = get(q, "recognition", nothing),
                            direction = get(q, "direction", nothing),
                            parent_id = get(q, "parent_id", nothing),
                            edge_id = get(q, "edge_id", nothing),
                            min_amount = _query_float(q, "min_amount", 0.0),
                            include_counterfactual =
                                _query_boolean(q, "include_potential", true),
                        )
                        return _cashflow_export_response(
                            _sanitize_for_json(export_payload),
                            get(q, "format", "csv"),
                        )
                    elseif req.method == "GET" && action == "cashflows" &&
                            length(parts) == 5
                        q = HTTP.queryparams(uri)
                        quarter = _query_integer(q, "quarter")
                        limit = _query_integer(q, "limit", 240)
                        sector_limit =
                            _query_integer(q, "sector_limit", 480)
                        firm_id = _query_integer(q, "firm_id")
                        include_potential =
                            _query_boolean(q, "include_potential", false)
                        payload = _cashflow_api_payload(
                            run_path;
                            quarter,
                            detail = get(q, "detail", "sector"),
                            limit,
                            sector_limit,
                            firm_id,
                            include_potential,
                            level = get(q, "level", nothing),
                            focus = get(q, "focus", nothing),
                            layers = get(q, "layers", nothing),
                            recognition = get(q, "recognition", nothing),
                            direction = get(q, "direction", nothing),
                            parent_id = get(q, "parent_id", nothing),
                            edge_id = get(q, "edge_id", nothing),
                            min_amount = _query_float(q, "min_amount", 0.0),
                            coverage = _query_float(q, "coverage", 1.0),
                            page_size = _query_integer(q, "page_size"),
                            cursor = get(q, "cursor", nothing),
                        )
                        return _json_response(
                            200,
                            _sanitize_for_json(payload),
                        )
                    elseif req.method == "GET" && action == "download"
                        q = HTTP.queryparams(uri)
                        fmt = get(q, "format", "csv")
                        file = if fmt == "csv"
                            joinpath(run_path, "summary.csv")
                        elseif fmt == "jld2"
                            joinpath(run_path, "results.jld2")
                        else
                            throw(ApiError(400, "Unknown format"))
                        end
                        isfile(file) || throw(ApiError(404, "File not ready"))
                        ctype = fmt == "csv" ? "text/csv; charset=utf-8" : "application/octet-stream"
                        headers = ["Content-Type" => ctype, "Cache-Control" => "no-store"]
                        return HTTP.Response(200, headers, read(file))
                    end
                end
            end

            return router(req)
        catch e
            if e isa ApiError
                return _json_response(e.status, Dict("error" => e.message, "details" => e.details))
            end
            return _json_response(500, Dict("error" => "Internal error", "details" => sprint(showerror, e)))
        end
    end

    @info "BeforeITWeb listening on http://$(host):$(port)"
    # Browsers intentionally abort superseded Explorer queries. HTTP.jl tags
    # those harmless EPIPE writes as verbosity-1 messages even though their log
    # level is Error. Filter that connection-level group while preserving
    # ordinary application logs and the structured API failures above.
    return LoggingExtras.withlevel(Logging.Info; verbosity = 0) do
        HTTP.serve(handler, host, port; verbose = -1)
    end
end

end # module
