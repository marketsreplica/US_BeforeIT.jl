# =====================================================================================
# StructuralVintageCalibration — stage-2b workstream 2b-4 (structural-vintage robustness)
#
# Builds ADDITIONAL annual structural calibrations of the US BeforeIT model for
# reference years 2017 and 2012 (current revised BEA vintage), alongside the existing
# 2024 structure, without touching any existing artifact or pipeline behavior:
#
#   * the ANNUAL/structural row (BEA summary supply-use block, NIPA annual scalars,
#     fixed-asset stocks, sector employment/wages/firm counts, CPS person controls)
#     is rebuilt from the same ingestion path as the 2024 structure, for the target
#     reference year;
#   * every QUARTERLY dynamic series is copied UNCHANGED from the shipped
#     data/us/calibration/US_2024_calibration_object.jld2 (mixed-vintage design of
#     the stage-2b program: same quarterly history, different structural year).
#
# The artifact schema replicated here is the schema of the SHIPPED 2024 artifact
# (produced by scripts/us/USPipeline.jl at commit bff7aa4), NOT the richer schema the
# current USPipeline source would write: the shipped artifact is the object every
# stage-2b run actually consumes. The numeric construction of every shared value is
# identical between that commit and the current source (verified by diff); the
# `golden_test_2024` entry point proves the replication by rebuilding the 2024 annual
# structure from the checked-in raw responses and comparing against the shipped
# artifact value-by-value.
#
# Deliberate, documented deviations from the 2024 ingestion, forced by source-year
# availability (see STAGE2B_PROTOCOL.md 2b-4 "adapt the ingestion minimally"):
#   1. QCEW industry lists: the 2024 build reads NAICS-2022-coded QCEW files through
#      the frozen `qcew_2022` lists in scripts/us/bea71.toml. QCEW files for 2017/2012
#      are NAICS-2017/2012 coded; at the aggregation levels used the only affected
#      sectors are the information sectors, remapped here as
#         BEA 511: ["513"]        -> ["511"]
#         BEA 513: ["516","517"]  -> ["515","517"]
#      (every other list is identical and every row was verified present).
#   2. SUSB firm counts: the 2024 build nowcasts SUSB 2022 enterprises to 2024 with
#      QCEW establishment growth because SUSB lags. For 2017/2012 the SAME-year SUSB
#      publication exists, so firms are taken directly from it (growth factor = 1).
#      The 2017 source is us_state_6digitnaics_2017.xlsx (national 01:Total rows);
#      the 2012 source is us_6digitnaics_r_2012.xlsx (receipt-size file, 01:Total
#      rows = all enterprises). Both are converted to the checked 2022-txt schema by
#      convert_susb_to_national_csv.py; source and extract SHA-256 are recorded.
#      Sectors statutorily excluded from SUSB (rail 482, postal 491) fall back to
#      QCEW establishments exactly as in the 2024 build.
#   3. QCEW 2012 delivery: the BLS CSV slice API starts in 2014, so the 2012 national
#      rows are extracted from the official 2012_annual_singlefile.zip (URL and zip
#      SHA-256 recorded) with an identical column schema.
#   4. Farm count (sector 111CA firms): the 2024 build uses the manual NASS value in
#      sources.toml. 2012 and 2017 are Census of Agriculture years, so the census
#      counts are used (2,109,303 and 2,042,220), same DUBIOUS firm-concept status.
#   5. BEA Table 259 for 2017/2012 does not publish a separate T00OSUB row (other
#      subsidies netting is already inside T00OTOP in those years); the shared
#      `io_get` convention treats the absent row as zero, and the published identity
#      T005 + V001 + V003 + (T00OTOP - T00OSUB) = T018 was verified to hold at the
#      <= $2m BEA rounding tolerance for both years before this module was written.
#
# No file under data/us/raw/{bea,bls,census,fred,usda}, no calibration artifact, and
# no script outside scripts/us/calibration/structural_vintage/ is modified. All new
# raw responses are archived under data/us/raw/structural_vintage/.
# =====================================================================================
module StructuralVintageCalibration

using CSV
using DataFrames
using Dates
using HTTP
using JLD2
using JSON
using Printf
using SHA
using Statistics
using TOML

import BeforeIT as Bit

export build_vintage_calibration, golden_test_2024, MODEL_CODES

const SCRIPT_DIR = @__DIR__
const US_SCRIPTS_DIR = normpath(joinpath(SCRIPT_DIR, "..", ".."))
const REPO_ROOT = normpath(joinpath(US_SCRIPTS_DIR, "..", ".."))
const DATA_ROOT = joinpath(REPO_ROOT, "data", "us")
const RAW_ROOT = joinpath(DATA_ROOT, "raw")
const VINTAGE_RAW_ROOT = joinpath(RAW_ROOT, "structural_vintage")
const CALIBRATION_ROOT = joinpath(DATA_ROOT, "calibration")
const BASE_ARTIFACT_PATH = joinpath(CALIBRATION_ROOT, "US_2024_calibration_object.jld2")
const SOURCE_SPEC = TOML.parsefile(joinpath(US_SCRIPTS_DIR, "sources.toml"))
const MAPPING_SPEC = TOML.parsefile(joinpath(US_SCRIPTS_DIR, "bea71.toml"))
const CONVERTER = joinpath(SCRIPT_DIR, "convert_susb_to_national_csv.py")

# One retrieval vintage for everything this module fetches.
const FETCH_VINTAGE = "2026-08-17"

# BEA summary commodity codes in MODEL ROW ORDER (row order of BEA Table 259 with the
# value-added/control rows removed and retail industries aggregated to 4A0). Identical
# to the list in scripts/us/calibration/reconcile_commodity_balance.jl; asserted, for
# every build year, against the codes actually returned by the source table.
const MODEL_CODES = [
    "111CA", "113FF", "211", "212", "213", "22", "23", "311FT", "313TT", "315AL",
    "321", "322", "323", "324", "325", "326", "327", "331", "332", "333",
    "334", "335", "3361MV", "3364OT", "337", "339", "42", "481", "482", "483",
    "484", "485", "486", "487OS", "493", "4A0", "511", "512", "513", "514",
    "521CI", "523", "524", "525", "532RL", "5411", "5412OP", "5415", "55", "561",
    "562", "61", "621", "622", "623", "624", "711AS", "713", "721", "722",
    "81", "GFE", "GFGD", "GFGN", "GSLE", "GSLG", "HS", "ORE",
]

# NAICS-2017/2012 replacements for the NAICS-2022 `qcew_2022` lists in bea71.toml.
# Only the information sectors differ at the aggregation levels used; every other
# sector's list is valid in the 2017 and 2012 QCEW files unchanged (verified rows).
const QCEW_NAICS2017_OVERRIDES = Dict(
    "511" => ["511"],
    "513" => ["515", "517"],
)

# Same-year farm counts (sector 111CA "firms"); both target years are Census of
# Agriculture years. The 2024 path uses the manual NASS estimate in sources.toml with
# the same DUBIOUS farm-vs-firm concept status.
const FARM_COUNTS = Dict(
    2017 => (
        value = 2_042_220.0,
        source = "USDA NASS 2017 Census of Agriculture, U.S. national farm count",
        url = "https://www.nass.usda.gov/Publications/AgCensus/2017/Full_Report/Volume_1,_Chapter_1_US/",
    ),
    2012 => (
        value = 2_109_303.0,
        source = "USDA NASS 2012 Census of Agriculture, U.S. national farm count",
        url = "https://www.nass.usda.gov/Publications/AgCensus/2012/",
    ),
)

# -------------------------------------------------------------------------------------
# Environment / HTTP / archiving (self-contained; mirrors USPipeline conventions)
# -------------------------------------------------------------------------------------

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

safe_slug(value) = begin
    slug = replace(lowercase(String(value)), r"[^a-z0-9._=-]+" => "-")
    strip(slug, '-')
end

sha256_bytes(bytes::Vector{UInt8}) = bytes2hex(SHA.sha256(bytes))
sha256_file(path::AbstractString) = sha256_bytes(read(path))

function redact_secrets(bytes::Vector{UInt8}, env::Dict{String, String})
    text = String(copy(bytes))
    redactions = String[]
    for (name, secret) in env
        isempty(secret) && continue
        if occursin(secret, text)
            text = replace(text, secret => "[REDACTED:$name]")
            push!(redactions, name)
        end
    end
    return Vector{UInt8}(codeunits(text)), sort!(unique(redactions))
end

function http_get(url::String; query = Dict{String, String}())
    last_error = nothing
    for attempt in 1:3
        try
            response = HTTP.get(
                url;
                query = collect(pairs(query)),
                status_exception = false,
                readtimeout = 600,
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
                readtimeout = 300,
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

"""
Record of one archived source retrieval, threaded into artifact provenance.
"""
struct SourceRecord
    source::String
    dataset::String
    request_id::String
    sha256::String
    path::String
    retrieved_at::String
    detail::String
end

function archive_dir(source, dataset, request_id)
    return joinpath(
        VINTAGE_RAW_ROOT,
        safe_slug(source),
        safe_slug(dataset),
        "vintage=$FETCH_VINTAGE",
        safe_slug(request_id),
    )
end

"""
    reuse_archived(source, dataset, request_id, extension)

Idempotent re-runs: if this request was already archived under the module's own raw
subtree, reuse the stored bytes instead of re-fetching.
"""
function reuse_archived(source, dataset, request_id, extension)
    root = archive_dir(source, dataset, request_id)
    isdir(root) || return nothing
    files = sort([f for f in readdir(root) if endswith(f, ".$extension")])
    isempty(files) && return nothing
    path = joinpath(root, files[1])
    metadata_path = replace(path, ".$extension" => ".metadata.json")
    retrieved_at = ""
    detail = ""
    if isfile(metadata_path)
        metadata = JSON.parsefile(metadata_path)
        retrieved_at = String(get(metadata, "retrieved_at", ""))
        detail = String(get(metadata, "detail", ""))
    end
    record = SourceRecord(
        source, dataset, request_id, split(files[1], ".")[1],
        relpath(path, REPO_ROOT), retrieved_at, detail,
    )
    return read(path), record
end

function archive_bytes(
        env::Dict{String, String},
        source::String,
        dataset::String,
        request_id::String,
        bytes::Vector{UInt8};
        extension::String,
        public_request::AbstractDict = Dict{String, Any}(),
        detail::String = "",
    )
    sanitized, redactions = redact_secrets(bytes, env)
    digest = sha256_bytes(sanitized)
    root = archive_dir(source, dataset, request_id)
    mkpath(root)
    path = joinpath(root, "$digest.$extension")
    isfile(path) || write(path, sanitized)
    retrieved_at = string(now(UTC))
    full_detail = isempty(redactions) ? detail :
        string(detail, isempty(detail) ? "" : " ", "API credential echo redacted: ", join(redactions, ", "))
    metadata_path = joinpath(root, "$digest.metadata.json")
    metadata = Dict(
        "source" => source,
        "dataset" => dataset,
        "request_id" => request_id,
        "retrieved_at" => retrieved_at,
        "byte_count" => length(sanitized),
        "sha256" => digest,
        "request" => public_request,
        "detail" => full_detail,
        "secret_fields_redacted_from_response" => redactions,
    )
    isfile(metadata_path) || open(metadata_path, "w") do io
        JSON.print(io, metadata, 2)
    end
    record = SourceRecord(
        source, dataset, request_id, digest,
        relpath(path, REPO_ROOT), retrieved_at, full_detail,
    )
    return sanitized, record
end

# -------------------------------------------------------------------------------------
# Source fetchers (year-parameterized; archive-first, reuse on re-run)
# -------------------------------------------------------------------------------------

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

function bea_rows_from_bytes(bytes)
    payload = JSON.parse(String(copy(bytes)))
    result = bea_results(payload)
    haskey(result, "Data") || error("BEA response has no Data")
    rows = result["Data"]
    isempty(rows) && error("BEA returned no rows")
    return rows
end

function fetch_bea!(
        records::Vector{SourceRecord},
        env::Dict{String, String},
        dataset::String,
        request_id::String,
        parameters::Dict{String, String},
    )
    cached = reuse_archived("BEA", dataset, request_id, "json")
    if cached !== nothing
        bytes, record = cached
        push!(records, record)
        return bea_rows_from_bytes(bytes)
    end
    secret = get(env, "BEA_API_KEY", "")
    isempty(secret) && error("BEA_API_KEY is not configured in $(joinpath(REPO_ROOT, ".env"))")
    query = Dict(
        "UserID" => secret,
        "method" => "GetData",
        "datasetname" => dataset,
        "ResultFormat" => "JSON",
    )
    merge!(query, parameters)
    public_request = Dict{String, Any}("method" => "GetData", "datasetname" => dataset)
    for (key, value) in parameters
        public_request[key] = value
    end
    response = http_get(String(SOURCE_SPEC["endpoints"]["bea"]); query = query)
    response.status == 200 || error("BEA $request_id returned HTTP $(response.status)")
    bytes, record = archive_bytes(
        env, "BEA", dataset, request_id, Vector{UInt8}(response.body);
        extension = "json", public_request = public_request,
    )
    push!(records, record)
    return bea_rows_from_bytes(bytes)
end

function fetch_bls_cps!(records::Vector{SourceRecord}, env::Dict{String, String}, year::Int)
    series_by_name = Dict{String, String}(
        string(name) => String(series_id)
            for (name, series_id) in SOURCE_SPEC["bls_series"]
    )
    series_ids = sort!(collect(values(series_by_name)))
    request_id = "$year-$year-annual"
    cached = reuse_archived("BLS", "CPS", request_id, "json")
    bytes = nothing
    if cached !== nothing
        bytes, record = cached
        push!(records, record)
    else
        request = Dict{String, Any}(
            "seriesid" => series_ids,
            "startyear" => string(year),
            "endyear" => string(year),
        )
        api_key = get(env, "BLS_API_KEY", "")
        isempty(api_key) || (request["registrationkey"] = api_key)
        response = http_post_json(String(SOURCE_SPEC["endpoints"]["bls"]), request)
        response.status == 200 || error("BLS CPS $year returned HTTP $(response.status)")
        bytes, record = archive_bytes(
            env, "BLS", "CPS", request_id, Vector{UInt8}(response.body);
            extension = "json",
            public_request = Dict(
                "seriesid" => series_ids,
                "startyear" => string(year),
                "endyear" => string(year),
                "registrationkey" => isempty(api_key) ? nothing : "[REDACTED]",
            ),
        )
        push!(records, record)
    end
    payload = JSON.parse(String(copy(bytes)))
    get(payload, "status", "") == "REQUEST_SUCCEEDED" ||
        error("BLS CPS $year request failed: $(get(payload, "message", "unknown"))")
    rows = Dict{String, Vector{Any}}(series_id => Any[] for series_id in series_ids)
    for series in payload["Results"]["series"]
        rows[String(series["seriesID"])] = collect(series["data"])
    end
    return rows
end

function fetch_qcew!(records::Vector{SourceRecord}, env::Dict{String, String}, year::Int)
    request_id = "$year-annual-us-area"
    cached = reuse_archived("BLS", "QCEW", request_id, "csv")
    if cached !== nothing
        bytes, record = cached
        push!(records, record)
        return CSV.read(IOBuffer(bytes), DataFrame; normalizenames = true)
    end
    if year >= 2014
        url = "https://data.bls.gov/cew/data/api/$year/a/area/US000.csv"
        response = http_get(url)
        response.status == 200 || error("QCEW $year returned HTTP $(response.status)")
        bytes, record = archive_bytes(
            env, "BLS", "QCEW", request_id, Vector{UInt8}(response.body);
            extension = "csv", public_request = Dict("url" => url),
            detail = "BLS QCEW CSV slice API, annual averages, national area US000.",
        )
        push!(records, record)
        return CSV.read(IOBuffer(bytes), DataFrame; normalizenames = true)
    end
    # The CSV slice API starts in 2014; earlier years ship as annual singlefile zips.
    url = "https://data.bls.gov/cew/data/files/$year/csv/$(year)_annual_singlefile.zip"
    zip_path = joinpath(mktempdir(), "$(year)_annual_singlefile.zip")
    response = http_get(url)
    response.status == 200 || error("QCEW $year singlefile returned HTTP $(response.status)")
    write(zip_path, response.body)
    zip_sha = sha256_file(zip_path)
    filtered = IOBuffer()
    open(`unzip -p $zip_path`) do stream
        for (index, line) in enumerate(eachline(stream))
            if index == 1 || startswith(line, "\"US000\"")
                println(filtered, line)
            end
        end
    end
    bytes, record = archive_bytes(
        env, "BLS", "QCEW", request_id, take!(filtered);
        extension = "csv",
        public_request = Dict("url" => url),
        detail = "National US000 annual rows extracted from $(basename(url)) " *
            "(zip sha256 $zip_sha); identical column schema to the CSV slice API.",
    )
    push!(records, record)
    rm(dirname(zip_path); recursive = true, force = true)
    return CSV.read(IOBuffer(bytes), DataFrame; normalizenames = true)
end

const SUSB_SOURCES = Dict(
    2017 => (
        url = "https://www2.census.gov/programs-surveys/susb/tables/2017/us_state_6digitnaics_2017.xlsx",
        layout = "state_6digitnaics_xlsx",
        note = "National (State=00) rows, enterprise employment size 01: Total.",
    ),
    2012 => (
        url = "https://www2.census.gov/programs-surveys/susb/tables/2012/us_6digitnaics_r_2012.xlsx",
        layout = "us_receiptsize_xlsx",
        note = "US-only receipt-size file; 01: Total receipt-size rows are all employer enterprises. " *
            "The employment-size US file for 2012 is legacy .xls; the receipt-size totals are identical for 01: Total.",
    ),
)

function fetch_susb!(records::Vector{SourceRecord}, env::Dict{String, String}, year::Int)
    request_id = "$year-us-total-enterprises"
    cached = reuse_archived("Census", "SUSB-extract", request_id, "csv")
    if cached !== nothing
        bytes, record = cached
        push!(records, record)
        return susb_frame_from_bytes(bytes)
    end
    haskey(SUSB_SOURCES, year) || error("No SUSB source registered for year $year")
    spec = SUSB_SOURCES[year]
    workdir = mktempdir()
    source_path = joinpath(workdir, basename(spec.url))
    response = http_get(spec.url)
    response.status == 200 || error("SUSB $year returned HTTP $(response.status)")
    write(source_path, response.body)
    source_sha = sha256_file(source_path)
    extract_path = joinpath(workdir, "susb_$(year)_national.csv")
    run(`python3 $CONVERTER --input $source_path --layout $(spec.layout) --output $extract_path`)
    bytes, record = archive_bytes(
        env, "Census", "SUSB-extract", request_id, read(extract_path);
        extension = "csv",
        public_request = Dict("url" => spec.url, "layout" => spec.layout),
        detail = "Converted to the 2022-txt national schema (STATE,NAICS,ENTRSIZE,FIRM,ESTB,EMPL) by " *
            "convert_susb_to_national_csv.py. Source workbook sha256 $source_sha. $(spec.note)",
    )
    push!(records, record)
    rm(workdir; recursive = true, force = true)
    return susb_frame_from_bytes(bytes)
end

"""
    susb_frame_from_bytes(bytes)

Parse SUSB national rows exactly as USPipeline.collect_susb! does (string cells fed
through parse_bea_number), from either the checked-in 2022 txt or this module's
normalized extracts, keeping only STATE=00 / ENTRSIZE=01 rows.
"""
function susb_frame_from_bytes(bytes)
    selected = NamedTuple[]
    rows = CSV.Rows(
        IOBuffer(bytes);
        normalizenames = true,
        types = String,
        reusebuffer = true,
    )
    for row in rows
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
    nrow(frame) > 0 || error("SUSB extract contains no national total rows")
    return frame
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

# -------------------------------------------------------------------------------------
# Shared parsing / arithmetic (verbatim USPipeline logic, made state-free)
# -------------------------------------------------------------------------------------

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

io_get(values, row_code::String, column_code::String) =
    get(values, (row_code, column_code), 0.0)

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
    all(>(0), purchasers_price) ||
        error("BEA T016 purchasers-price controls must be strictly positive")
    values = basic_price ./ purchasers_price
    all(isfinite, values) ||
        error("BEA purchasers-to-basic-price quotient contains nonfinite values")
    all(>(0), values) ||
        error("BEA purchasers-to-basic-price quotient must be strictly positive")
    return (; values, basic_price, purchasers_price)
end

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

# -------------------------------------------------------------------------------------
# I-O block (Tables 259/262 -> the artifact's figaro annual entries)
# -------------------------------------------------------------------------------------

function build_io_block(use_rows, supply_rows, year::Int, log)
    use_frame = io_long(use_rows)
    supply_frame = io_long(supply_rows)
    all(==(year), use_frame.year) || error("BEA Table 259 returned a year other than $year")
    all(==(year), supply_frame.year) || error("BEA Table 262 returned a year other than $year")
    use_values = lookup_matrix(use_frame)
    supply_values = lookup_matrix(supply_frame)
    special_rows = Set(
        [
            "Other", "Used", "T005", "T00OSUB", "T00OTOP", "T00SUB",
            "T00TOP", "T018", "V001", "V003", "VABAS", "VAPRO",
        ]
    )
    ordered_rows = unique(use_frame.row_code)
    model_codes = [code for code in ordered_rows if !(code in special_rows)]
    length(model_codes) == 68 ||
        error("Expected 68 observed BEA commodity sectors; got $(length(model_codes))")
    model_codes == MODEL_CODES ||
        error("BEA Table 259 row order for $year differs from the 2024 model-code order")
    has_osub = "T00OSUB" in ordered_rows
    log(
        "Table 259 rows: $(length(ordered_rows)); T00OSUB published: $has_osub" *
            (has_osub ? "" : " (other-subsidies netting already inside T00OTOP; absent row treated as zero)")
    )

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
    output_control = industry_vector("T018")
    household_consumption = commodity_vector("F010")
    capital_columns = ["F02E", "F02N", "F02R", "F02S"]
    government_columns = [
        "F06C", "F06E", "F06N", "F06S",
        "F07C", "F07E", "F07N", "F07S",
        "F10C", "F10E", "F10N", "F10S",
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
    for commodity_code in model_codes
        commodity_tax =
            io_get(supply_values, commodity_code, "TOP") +
            io_get(supply_values, commodity_code, "MDTY") +
            io_get(supply_values, commodity_code, "SUB")
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

    # ---- fail-closed source controls (the published-rounding gates of build_io!) ----
    # The shipped 2024 gate is $2m per industry column. The 4A0 model column is the
    # code-keyed sum of four source columns (441+445+452+4A0), so its worst-case
    # published-rounding residual is four times the single-column bound (the same
    # term-count scaling as USSupplyMakeDiagnostics.published_rounding_tolerance);
    # every unaggregated column keeps the shipped $2m gate.
    column_tolerance = [code == "4A0" ? 8.0 : 2.0 for code in model_codes]
    model_output =
        vec(sum(bridged; dims = 1)) + compensation + operating_surplus + production_taxes
    identity_errors = abs.(model_output - output_control)
    max_identity_error = maximum(identity_errors)
    all(identity_errors .<= column_tolerance) ||
        error("Output identity T005+V001+V003+(T00OTOP-T00OSUB)=T018 fails: max \$$(max_identity_error)m")
    supply_output = [
        sum(io_get(supply_values, "T017", source_code) for source_code in column_sources(code))
            for code in model_codes
    ]
    supply_output_errors = abs.(supply_output - output_control)
    use_supply_output_error = maximum(supply_output_errors)
    use_total = [io_get(use_values, code, "T019") for code in model_codes]
    supply_total = [io_get(supply_values, code, "T016") for code in model_codes]
    use_supply_total_error = maximum(abs, use_total - supply_total)
    (all(supply_output_errors .<= column_tolerance) && use_supply_total_error <= 2.0) ||
        error("Cross-table 259/262 controls exceed published rounding: output \$$(use_supply_output_error)m, totals \$$(use_supply_total_error)m")
    official_export_control = io_get(use_values, "T005", "F040")
    excluded_exports = sum(
        io_get(use_values, commodity_code, "F040")
            for commodity_code in excluded_commodity_codes
    )
    export_control_error = sum(exports) + excluded_exports - official_export_control
    (abs(export_control_error) <= 2.0 && all(exports .>= 0)) ||
        error("Export control fails: error \$$(export_control_error)m")
    import_control_error = sum(imports) + excluded_imports - official_import_control
    (abs(import_control_error) <= 2.0 && all(isfinite, imports) && all(imports .>= 0)) ||
        error("Import control fails: error \$$(import_control_error)m")

    log(
        @sprintf(
            "I-O block %d: output identity max err \$%.3fm; cross-table max err \$%.3fm/\$%.3fm; export err \$%.3fm; import err \$%.3fm (%d negative MCIF+MADJ rows floored, scale %.6f)",
            year, max_identity_error, use_supply_output_error, use_supply_total_error,
            export_control_error, import_control_error,
            import_adjustment.negative_count, import_adjustment.scale,
        )
    )

    return (;
        model_codes, observed, bridged, bridge_factor, output_control,
        compensation, operating_surplus, production_taxes,
        household_consumption, fixed_capitalformation, government_consumption,
        exports, imports, raw_imports, import_adjustment,
        purchasers_to_basic_price = purchasers_to_basic.values,
        taxes_products_observed = product_taxes,
        taxes_products_household, taxes_products_capitalformation,
        taxes_products_government, taxes_products_inventory,
        gross_capitalformation_dwellings,
        max_identity_error, use_supply_output_error, use_supply_total_error,
        export_control_error, import_control_error,
    )
end

# -------------------------------------------------------------------------------------
# NIPA annual scalars
# -------------------------------------------------------------------------------------

function annual_nipa_value(tables, reference::AbstractString, year::Int)
    table_name, line_text = split(String(reference), ":"; limit = 2)
    rows = tables[String(table_name)]
    matches = [
        row for row in rows
            if parse(Int, String(row["LineNumber"])) == parse(Int, line_text)
    ]
    isempty(matches) && error("$reference is missing from the $year response")
    annual = [row for row in matches if String(row["TimePeriod"]) == string(year)]
    length(annual) == 1 ||
        error("$reference expected one $year observation; got $(length(annual))")
    value = parse_bea_number(only(annual)["DataValue"])
    value === missing && error("$reference has a missing value")
    label = String(only(annual)["LineDescription"])
    isempty(label) && error("$reference has an empty official label")
    return Float64(value)
end

function build_nipa_values(tables, year::Int)
    lines = SOURCE_SPEC["nipa_lines"]
    extracted = Dict{String, Float64}()
    for (name, reference) in lines
        extracted[String(name)] = annual_nipa_value(tables, String(reference), year)
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
    values["social_contributions"] >=
        extracted["compensation_employees"] - extracted["wages_total"] ||
        error("Social-contribution semantics check failed for $year")
    values["government_deficit"] > 0 ||
        error("Government deficit sign convention must be positive for a deficit ($year)")
    return values
end

# -------------------------------------------------------------------------------------
# CPS labor controls
# -------------------------------------------------------------------------------------

function bls_annual_value(rows, source_year::Int)
    matches = [
        row for row in rows
            if String(row["year"]) == string(source_year) &&
            String(row["period"]) == "M13"
    ]
    if length(matches) == 1
        value = parse_bea_number(only(matches)["value"])
        value === missing && error("BLS M13 $source_year is missing")
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
        error("Expected M13 or twelve complete BLS months for $source_year")
    return mean(monthly)
end

function build_labor_annual(bls_rows, year::Int)
    series = Dict{String, String}(
        string(name) => String(value) for (name, value) in SOURCE_SPEC["bls_series"]
    )
    annual = Dict(
        "population" => 1000 * bls_annual_value(bls_rows[series["population"]], year),
        "employees_total" => 1000 * bls_annual_value(bls_rows[series["employed"]], year),
        "unemployed_census" => 1000 * bls_annual_value(bls_rows[series["unemployed"]], year),
        "inactive_census" => 1000 * bls_annual_value(bls_rows[series["inactive"]], year),
        "labor_force" => 1000 * bls_annual_value(bls_rows[series["labor_force"]], year),
    )
    identity_error =
        annual["population"] -
        annual["employees_total"] -
        annual["unemployed_census"] -
        annual["inactive_census"]
    abs(identity_error) <= 10_000 ||
        error("CPS person identity fails for $year: $identity_error persons")
    return annual
end

# -------------------------------------------------------------------------------------
# QCEW / SUSB / fixed-asset sector accounts
# -------------------------------------------------------------------------------------

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

function fixed_asset_value(tables, table_name::String, line_number::Int, year::Int)
    rows = tables[table_name]
    matches = [
        row for row in rows
            if parse(Int, String(row["LineNumber"])) == line_number &&
            String(row["TimePeriod"]) == string(year)
    ]
    length(matches) == 1 ||
        error("$table_name line $line_number expected one $year value; got $(length(matches))")
    value = parse_bea_number(only(matches)["DataValue"])
    value === missing && error("$table_name line $line_number is missing for $year")
    return Float64(value), String(only(matches)["LineDescription"])
end

"""
    build_sector_accounts(...)

Mirror of USPipeline.build_sector_accounts! for one reference year.

`qcew_growth` mode:
  * `:susb_nowcast` (2024 golden path) — firms = SUSB(base file) x establishment
    growth between the two QCEW files (2022 -> 2024), the shipped construction;
  * `:same_year` (2017/2012) — the SUSB publication matches the reference year,
    so firms are taken from it directly (growth factor = 1).
"""
function build_sector_accounts(
        year::Int,
        qcew_year::DataFrame,
        susb::DataFrame,
        fixed_asset_tables,
        compensation::Vector{Float64},
        output_control::Vector{Float64},
        cps_employed_total::Float64,
        nipa_wages_total::Float64,
        farm_count::Float64,
        qcew_lists::Dict{String, Vector{String}},
        log;
        qcew_growth::Symbol = :same_year,
        qcew_establishment_base::Union{Nothing, DataFrame} = nothing,
        susb_base_year_establishment_frame::Union{Nothing, DataFrame} = nothing,
    )
    model_codes = MODEL_CODES
    entries = Dict(String(entry["code"]) => entry for entry in MAPPING_SPEC["sector"])
    sector_count = length(model_codes)

    raw_jobs = zeros(sector_count)
    raw_wages = zeros(sector_count)
    raw_establishments = zeros(sector_count)
    base_firms = zeros(sector_count)
    firms = zeros(sector_count)
    susb_proxy_codes = String[]
    government_codes = Set(["GFE", "GFGD", "GFGN", "GSLE", "GSLG"])
    for (index, code) in enumerate(model_codes)
        entry = entries[code]
        if code in government_codes || code == "HS"
            continue
        end
        qcew_codes = qcew_lists[code]
        raw_jobs[index] = qcew_sum(qcew_year, qcew_codes, [5], :annual_avg_emplvl)
        raw_wages[index] = qcew_sum(qcew_year, qcew_codes, [5], :total_annual_wages)
        raw_establishments[index] =
            qcew_sum(qcew_year, qcew_codes, [5], :annual_avg_estabs)
        if code != "111CA"
            establishments_base = if qcew_growth === :susb_nowcast
                qcew_sum(
                    susb_base_year_establishment_frame, qcew_codes, [5], :annual_avg_estabs,
                )
            else
                raw_establishments[index]
            end
            susb_codes = String.(entry["susb_2017"])
            susb_value = susb_sum(susb, susb_codes, :firms)
            if susb_value === missing
                base_firms[index] = establishments_base
                push!(susb_proxy_codes, code)
            else
                base_firms[index] = susb_value
            end
            growth = establishments_base > 0 ?
                raw_establishments[index] / establishments_base : 1.0
            firms[index] = base_firms[index] * growth
        end
    end

    federal_indices = findall(code -> code in ("GFE", "GFGD", "GFGN"), model_codes)
    state_local_indices = findall(code -> code in ("GSLE", "GSLG"), model_codes)
    function allocate_government!(indices, ownership_codes)
        jobs = qcew_sum(qcew_year, ["10"], ownership_codes, :annual_avg_emplvl)
        wages = qcew_sum(qcew_year, ["10"], ownership_codes, :total_annual_wages)
        establishments =
            qcew_sum(qcew_year, ["10"], ownership_codes, :annual_avg_estabs)
        weights = compensation[indices]
        weights ./= sum(weights)
        raw_jobs[indices] .= jobs .* weights
        raw_wages[indices] .= wages .* weights
        raw_establishments[indices] .= establishments .* weights
        return firms[indices] .= raw_establishments[indices]
    end
    allocate_government!(federal_indices, [1])
    allocate_government!(state_local_indices, [2, 3])
    farms_index = findfirst(==("111CA"), model_codes)
    housing_index = findfirst(==("HS"), model_codes)
    firms[farms_index] = farm_count
    base_firms[farms_index] = firms[farms_index]
    firms[housing_index] = 1.0
    base_firms[housing_index] = 1.0
    isempty(susb_proxy_codes) ||
        log("SUSB statutory-exclusion proxies (QCEW establishments): $(join(susb_proxy_codes, ", "))")

    private_total_jobs = qcew_sum(qcew_year, ["10"], [5], :annual_avg_emplvl)
    government_total_jobs = qcew_sum(qcew_year, ["10"], [1, 2, 3], :annual_avg_emplvl)
    private_total_wages = qcew_sum(qcew_year, ["10"], [5], :total_annual_wages)
    government_total_wages = qcew_sum(qcew_year, ["10"], [1, 2, 3], :total_annual_wages)
    jobs_coverage = sum(raw_jobs) / (private_total_jobs + government_total_jobs)
    wages_coverage = sum(raw_wages) / (private_total_wages + government_total_wages)
    log(@sprintf("QCEW %d coverage: jobs %.3f%%, wages %.3f%%", year, 100 * jobs_coverage, 100 * wages_coverage))
    jobs_coverage >= 0.995 || error("QCEW job mapping coverage is below 99.5% for $year")
    wages_coverage >= 0.995 || error("QCEW wage mapping coverage is below 99.5% for $year")
    employees = raw_jobs .* (cps_employed_total / sum(raw_jobs))
    wages = bounded_allocation(
        nipa_wages_total,
        raw_wages,
        compensation .* (1 - 1.0e-8),
    )
    all(wages .<= compensation .+ 1.0e-6) ||
        error("Sector wages exceed compensation for $year")
    all(firms .> 0) || error("A sector firm count is non-positive for $year")

    fixed_assets = zeros(sector_count)
    dwellings = zeros(sector_count)
    capital_consumption = zeros(sector_count)
    for (index, code) in enumerate(model_codes)
        lines = Int.(entries[code]["fixed_asset_lines"])
        isempty(lines) && continue
        fixed_assets[index] =
            sum(first(fixed_asset_value(fixed_asset_tables, "FAAt301ESI", line, year)) for line in lines)
        capital_consumption[index] =
            sum(first(fixed_asset_value(fixed_asset_tables, "FAAt304ESI", line, year)) for line in lines)
    end
    owner_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt501", 11, year)
    tenant_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt501", 12, year)
    owner_depreciation, _ = fixed_asset_value(fixed_asset_tables, "FAAt504", 11, year)
    real_estate_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt301ESI", 74, year)
    real_estate_depreciation, _ = fixed_asset_value(fixed_asset_tables, "FAAt304ESI", 74, year)
    ore_index = findfirst(==("ORE"), model_codes)
    fixed_assets[housing_index] = owner_assets
    dwellings[housing_index] = 0.999 * owner_assets
    capital_consumption[housing_index] = 0.001 * owner_depreciation
    fixed_assets[ore_index] = real_estate_assets - owner_assets
    dwellings[ore_index] = tenant_assets
    capital_consumption[ore_index] =
        real_estate_depreciation - owner_depreciation

    government_enterprise_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt701", 79, year)
    federal_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt701", 21, year)
    federal_defense_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt701", 22, year)
    state_local_assets, _ = fixed_asset_value(fixed_asset_tables, "FAAt701", 55, year)
    government_enterprise_depreciation, _ =
        fixed_asset_value(fixed_asset_tables, "FAAt703", 79, year)
    federal_depreciation, _ = fixed_asset_value(fixed_asset_tables, "FAAt703", 21, year)
    federal_defense_depreciation, _ = fixed_asset_value(fixed_asset_tables, "FAAt703", 22, year)
    state_local_depreciation, _ = fixed_asset_value(fixed_asset_tables, "FAAt703", 55, year)
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
    all(fixed_assets - dwellings .> 0) ||
        error("Every sector must have positive productive fixed assets ($year)")
    all(capital_consumption .>= 0) ||
        error("Sector capital consumption must be nonnegative ($year)")

    private_expected, _ = fixed_asset_value(fixed_asset_tables, "FAAt301ESI", 1, year)
    government_expected, _ = fixed_asset_value(fixed_asset_tables, "FAAt701", 1, year)
    private_indices = findall(code -> !(code in government_codes), model_codes)
    private_error = sum(fixed_assets[private_indices]) - private_expected
    government_model_indices = [gfe, gfgd, gfgn, gsle, gslg]
    government_error =
        sum(fixed_assets[government_model_indices]) - government_expected
    # Worst-case published-rounding residual for the private control, following
    # USSupplyMakeDiagnostics.published_rounding_tolerance: the private sum contains
    # every FAAt301ESI sector line plus line 74 (FAAt501:11 enters once positively for
    # HS and once negatively for ORE, cancelling exactly), each independently rounded
    # to $1m, compared against one rounded control line. The government sum telescopes
    # to FAAt701 line 21 + line 55, so its shipped $2m gate is retained.
    private_term_count = 1 + sum(
        length(Int.(entries[code]["fixed_asset_lines"])) for code in model_codes
            if !(code in government_codes)
    )
    private_tolerance = (private_term_count + 1) / 2
    abs(private_error) <= private_tolerance ||
        error("Private fixed-asset stock control exceeds published rounding for $year: \$$(private_error)m vs tolerance \$$(private_tolerance)m")
    abs(government_error) <= 2.0 ||
        error("Government fixed-asset stock control exceeds \$2m for $year: \$$(government_error)m")
    log(
        @sprintf(
            "Fixed-asset controls %d: private err \$%.3fm (published-rounding tolerance \$%.1fm over %d terms), government err \$%.3fm",
            year, private_error, private_tolerance, private_term_count, government_error,
        )
    )

    return (;
        firms, employees, wages, fixed_assets, dwellings, capital_consumption,
        raw_jobs, raw_wages, raw_establishments, base_firms, susb_proxy_codes,
        jobs_coverage, wages_coverage, private_error, government_error,
    )
end

function qcew_lists_for_year(year::Int)
    lists = Dict{String, Vector{String}}()
    for entry in MAPPING_SPEC["sector"]
        code = String(entry["code"])
        base = String.(entry["qcew_2022"])
        if year >= 2022
            lists[code] = base
        else
            lists[code] = get(QCEW_NAICS2017_OVERRIDES, code, base)
        end
    end
    return lists
end

# -------------------------------------------------------------------------------------
# Assembly (shipped-2024-artifact schema, quarterly blocks copied from the base object)
# -------------------------------------------------------------------------------------

const COPIED_QUARTERLY_CALIBRATION_KEYS = [
    "quarters_num",
    "firm_debt_consolidation_ratio_quarterly",
    "household_cash_quarterly",
    "firm_cash_quarterly",
    "firm_debt_quarterly",
    "government_debt_quarterly",
    "bank_equity_quarterly",
]

function assemble_calibration_object(
        year::Int,
        base,
        io,
        nipa::Dict{String, Float64},
        labor::Dict,
        sectors,
    )
    calibration = Dict{String, Any}(
        "years_num" => [Bit.date2num(DateTime(year, 12, 31))],
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
        "wages_by_sector" => reshape(Float64.(sectors.wages), :, 1),
        "population" => [labor["population"]],
        "unemployed_census" => [labor["unemployed_census"]],
        "inactive_census" => [labor["inactive_census"]],
        "fixed_assets" => reshape(Float64.(sectors.fixed_assets), :, 1),
        "dwellings" => reshape(Float64.(sectors.dwellings), :, 1),
        "capital_consumption" =>
            reshape(Float64.(sectors.capital_consumption), :, 1),
        "gross_capitalformation_dwellings" =>
            [Float64(io.gross_capitalformation_dwellings)],
    )
    for key in COPIED_QUARTERLY_CALIBRATION_KEYS
        calibration[key] = deepcopy(base.calibration[key])
    end
    figaro = Dict{String, Any}(
        "intermediate_consumption" => reshape(Float64.(io.bridged), 68, 68, 1),
        "household_consumption" => reshape(Float64.(io.household_consumption), 68, 1),
        "fixed_capitalformation" => reshape(Float64.(io.fixed_capitalformation), 68, 1),
        "exports" => reshape(Float64.(io.exports), 68, 1),
        "imports" => reshape(Float64.(io.imports), 68, 1),
        "use_explicit_trade" => true,
        "use_product_tax_netting" => true,
        "use_commodity_balance_inventory" => true,
        "purchasers_to_basic_price" =>
            reshape(Float64.(io.purchasers_to_basic_price), 68, 1),
        "compensation_employees" => reshape(Float64.(io.compensation), 68, 1),
        "operating_surplus" => reshape(Float64.(io.operating_surplus), 68, 1),
        "government_consumption" => reshape(Float64.(io.government_consumption), 68, 1),
        "taxes_products_household" => [Float64(io.taxes_products_household)],
        "taxes_products_capitalformation" => [Float64(io.taxes_products_capitalformation)],
        "taxes_production" => reshape(Float64.(io.production_taxes), 68, 1),
        "taxes_products_government" => [Float64(io.taxes_products_government)],
        "taxes_products" => reshape(Float64.(io.taxes_products_observed), 68, 1),
    )
    data = deepcopy(base.data)
    ea = deepcopy(base.ea)
    return Bit.CalibrationData(
        calibration,
        figaro,
        data,
        ea,
        DateTime(year, 12, 31),
        base.estimation_date,
    )
end

load_base_artifact() = JLD2.load(BASE_ARTIFACT_PATH)["calibration_object"]

# -------------------------------------------------------------------------------------
# Vintage-year build (fetches everything for `year`, assembles, returns object + records)
# -------------------------------------------------------------------------------------

function build_vintage_calibration(year::Int; log = println)
    year in (2017, 2012) ||
        error("build_vintage_calibration supports reference years 2017 and 2012")
    env = load_env()
    records = SourceRecord[]
    base = load_base_artifact()

    io_spec = SOURCE_SPEC["bea"]["input_output"]
    use_rows = fetch_bea!(
        records, env, "InputOutput", "table_$(io_spec["use_table"])-$year",
        Dict("TableID" => String(io_spec["use_table"]), "Year" => string(year)),
    )
    supply_rows = fetch_bea!(
        records, env, "InputOutput", "table_$(io_spec["supply_table"])-$year",
        Dict("TableID" => String(io_spec["supply_table"]), "Year" => string(year)),
    )
    io = build_io_block(use_rows, supply_rows, year, log)

    nipa_tables = Dict{String, Any}()
    for table_name in String.(SOURCE_SPEC["bea"]["nipa"]["annual_tables"])
        nipa_tables[table_name] = fetch_bea!(
            records, env, "NIPA", "$table_name-A-$year",
            Dict("TableName" => table_name, "Frequency" => "A", "Year" => string(year)),
        )
    end
    nipa = build_nipa_values(nipa_tables, year)

    fixed_tables = Dict{String, Any}()
    for table_name in String.(SOURCE_SPEC["bea"]["fixed_assets"]["tables"])
        fixed_tables[table_name] = fetch_bea!(
            records, env, "FixedAssets", "$table_name-$year",
            Dict("TableName" => table_name, "Year" => string(year)),
        )
    end

    bls_rows = fetch_bls_cps!(records, env, year)
    labor = build_labor_annual(bls_rows, year)

    qcew = fetch_qcew!(records, env, year)
    susb = fetch_susb!(records, env, year)
    farm = FARM_COUNTS[year]
    log("Farm count (111CA firms): $(farm.value) — $(farm.source)")

    sectors = build_sector_accounts(
        year, qcew, susb, fixed_tables,
        Float64.(io.compensation), Float64.(io.output_control),
        Float64(labor["employees_total"]), Float64(nipa["wages_total"]),
        Float64(farm.value), qcew_lists_for_year(year), log;
        qcew_growth = :same_year,
    )

    object = assemble_calibration_object(year, base, io, nipa, labor, sectors)
    return (; object, records, io, nipa, labor, sectors, farm)
end

# -------------------------------------------------------------------------------------
# Golden test: rebuild the 2024 annual structure from the checked-in raw responses and
# compare value-by-value against the shipped artifact.
# -------------------------------------------------------------------------------------

function checked_in_json(relative)
    path = joinpath(RAW_ROOT, relative)
    isfile(path) || error("Checked-in raw input is missing: $path")
    return JSON.parsefile(path)
end

const GOLDEN_RAW_2024 = Dict(
    "io_259" => "bea/inputoutput/vintage=2026-08-04/table_259-2024/2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918.json",
    "io_262" => "bea/inputoutput/vintage=2026-08-04/table_262-2024/91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8.json",
    "T11000" => "bea/nipa/vintage=2026-08-04/t11000-a-2024/6cecbaf30f36bf8618117042434a84321a064f7440ea3d6d97dc1e4699ecab91.json",
    "T20100" => "bea/nipa/vintage=2026-08-04/t20100-a-2024/5981c20aacf6a038f67b7ae906d54a32954730ab73affa6d6c208d16009e2ae6.json",
    "T30100" => "bea/nipa/vintage=2026-08-04/t30100-a-2024/88e2ad5a6b9c8daa5b5706585415569e93d70446344f9300b51e16c4c90416d9.json",
    "T30600" => "bea/nipa/vintage=2026-08-04/t30600-a-2024/a63b2652d46209cb0384c3d0fefac38573f1ea792a1f871743a1adeebbb5cec8.json",
    "T31200" => "bea/nipa/vintage=2026-08-04/t31200-a-2024/bf72593f8dcccf1f40a30fa31a5f95982a3c6e7cce3c5071de1f7b01ce1eb828.json",
    "T51100" => "bea/nipa/vintage=2026-08-04/t51100-a-2024/def1a538357384e48a0fe64daf67a607dd8d6e42c75585f83a32253104b0bce8.json",
    "T71100" => "bea/nipa/vintage=2026-08-04/t71100-a-2024/0b9f2129d74e9120a19b71b209bb84a34c18be32718d899ec1e8af0509e3c700.json",
    "FAAt301ESI" => "bea/fixedassets/vintage=2026-08-04/faat301esi-2024/2d76397b0eec272a62e745f00b05365dececd259a0ba149e1701361b884811cc.json",
    "FAAt304ESI" => "bea/fixedassets/vintage=2026-08-04/faat304esi-2024/f30c0026141e1c0eb90fc0fcf25001e6929a5ab64afea47b2a6b42335dc48e31.json",
    "FAAt501" => "bea/fixedassets/vintage=2026-08-04/faat501-2024/050912d4dac039818c31754cc181344846a683326babc0e5ef67ad04b2702c08.json",
    "FAAt504" => "bea/fixedassets/vintage=2026-08-04/faat504-2024/00597b6767063eae3a3c0048271348b2ef69f4253126578046613be89b9955d4.json",
    "FAAt701" => "bea/fixedassets/vintage=2026-08-04/faat701-2024/141f2a03308c216d6d277cf3b1522d45e9c717ea5f04082e662e9abdab49c554.json",
    "FAAt703" => "bea/fixedassets/vintage=2026-08-04/faat703-2024/c9cf148c060b1fa64443a516e6a82f3384c3acc5f52a37fd4777d8b138af95b4.json",
    "cps_2016_2025" => "bls/cps/vintage=2026-08-04/2016-2025-registered/ed6c3c92c4b2039b1f23f842958b2c4f4b7deb3fd39dcb0dd54338890ad1b2e6.json",
    "qcew_2024" => "bls/qcew/vintage=2026-08-04/2024-annual-us-area/48db086828a01798731242c6d3d4957f80f941afe75463a1ff7d43de774bea46.csv",
    "qcew_2022" => "bls/qcew/vintage=2026-08-04/2022-annual-us-area/c45cbb64a1b1eef16bfd743510d9d02792ccad82f60e9df202c5daa3e8c5cc18.csv",
    "susb_2022" => "census/susb/vintage=2026-08-04/2022-us-state-six-digit-naics/6f7b2f2b14cbad9dbfeb31d3bfc9f729368a0e971727de4eda88c9f83f77a513.txt",
)

function golden_build_2024(; log = println)
    base = load_base_artifact()
    year = 2024
    bea_rows(key) = begin
        payload = checked_in_json(GOLDEN_RAW_2024[key])
        result = bea_results(payload)
        result["Data"]
    end
    io = build_io_block(bea_rows("io_259"), bea_rows("io_262"), year, log)
    nipa_tables = Dict{String, Any}(
        name => bea_rows(name) for name in
            ("T11000", "T20100", "T30100", "T30600", "T31200", "T51100", "T71100")
    )
    nipa = build_nipa_values(nipa_tables, year)
    fixed_tables = Dict{String, Any}(
        name => bea_rows(name) for name in
            ("FAAt301ESI", "FAAt304ESI", "FAAt501", "FAAt504", "FAAt701", "FAAt703")
    )
    cps_payload = checked_in_json(GOLDEN_RAW_2024["cps_2016_2025"])
    bls_rows = Dict{String, Vector{Any}}()
    for series in cps_payload["Results"]["series"]
        bls_rows[String(series["seriesID"])] = collect(series["data"])
    end
    labor = build_labor_annual(bls_rows, year)
    qcew_2024 = CSV.read(joinpath(RAW_ROOT, GOLDEN_RAW_2024["qcew_2024"]), DataFrame; normalizenames = true)
    qcew_2022 = CSV.read(joinpath(RAW_ROOT, GOLDEN_RAW_2024["qcew_2022"]), DataFrame; normalizenames = true)
    susb = susb_frame_from_bytes(read(joinpath(RAW_ROOT, GOLDEN_RAW_2024["susb_2022"])))
    farm_count = Float64(SOURCE_SPEC["manual"]["usda_farms"]["value"])
    sectors = build_sector_accounts(
        year, qcew_2024, susb, fixed_tables,
        Float64.(io.compensation), Float64.(io.output_control),
        Float64(labor["employees_total"]), Float64(nipa["wages_total"]),
        farm_count, qcew_lists_for_year(year), log;
        qcew_growth = :susb_nowcast,
        susb_base_year_establishment_frame = qcew_2022,
    )
    object = assemble_calibration_object(year, base, io, nipa, labor, sectors)
    return object, base
end

"""
    golden_test_2024(; rtol = 1.0e-12)

Rebuild the 2024 annual structure from the checked-in raw inputs and compare every
entry of the assembled object with the shipped artifact. Returns (passed, report).
"""
function golden_test_2024(; rtol = 1.0e-12, log = println)
    rebuilt, base = golden_build_2024(; log)
    lines = String[]
    passed = true
    function compare(section, key, a, b)
        if a isa Bool || b isa Bool
            ok = a == b
            ok || (passed = false)
            push!(lines, @sprintf("%-12s %-38s %s", section, key, ok ? "EQUAL" : "MISMATCH ($a vs $b)"))
            return
        end
        av = Float64.(collect(a))
        bv = Float64.(collect(b))
        if size(av) != size(bv)
            passed = false
            push!(lines, @sprintf("%-12s %-38s SHAPE MISMATCH %s vs %s", section, key, size(av), size(bv)))
            return
        end
        scale = max(maximum(abs.(bv)), 1.0)
        deviation = isempty(av) ? 0.0 : maximum(abs.(av .- bv)) / scale
        ok = deviation <= rtol
        ok || (passed = false)
        return push!(lines, @sprintf("%-12s %-38s max rel dev %.3e %s", section, key, deviation, ok ? "" : "MISMATCH"))
    end
    for (section, mine, theirs) in (
            ("calibration", rebuilt.calibration, base.calibration),
            ("figaro", rebuilt.figaro, base.figaro),
            ("data", rebuilt.data, base.data),
            ("ea", rebuilt.ea, base.ea),
        )
        Set(keys(mine)) == Set(keys(theirs)) || begin
            passed = false
            push!(lines, "$section KEY SETS DIFFER: only rebuilt $(setdiff(Set(keys(mine)), Set(keys(theirs)))); only shipped $(setdiff(Set(keys(theirs)), Set(keys(mine))))")
        end
        for key in sort(collect(intersect(Set(keys(mine)), Set(keys(theirs)))))
            compare(section, key, mine[key], theirs[key])
        end
    end
    rebuilt.max_calibration_date == base.max_calibration_date ||
        (passed = false; push!(lines, "max_calibration_date differs"))
    rebuilt.estimation_date == base.estimation_date ||
        (passed = false; push!(lines, "estimation_date differs"))
    return passed, join(lines, "\n")
end

# -------------------------------------------------------------------------------------
# Artifact + provenance writing
# -------------------------------------------------------------------------------------

function artifact_metadata(year::Int, result, base_sha::String)
    return Dict{String, Any}(
        "country" => "US",
        "kind" => "structural",
        "schema_version" => 1,
        "scale" => 1.0e-5,
        "sector_count" => 68,
        "sector_system" => "BEA summary, 68 observed commodities; retail industries aggregated to 4A0",
        "structural_reference_year" => year,
        "period" => "$year-Q4",
        "created_at" => string(now()),
        "annual_structure_data_vintage" => FETCH_VINTAGE,
        "beforeit_version" => string(pkgversion(Bit)),
        "input_sha256" => sort!(unique([record.sha256 for record in result.records])),
        "quarterly_block_source" => relpath(BASE_ARTIFACT_PATH, REPO_ROOT),
        "quarterly_block_source_sha256" => base_sha,
        "workstream" => "stage2b-2b4-structural-vintage-robustness",
        "mixed_vintage_note" =>
            "Annual structural row rebuilt for reference year $year from the current revised " *
            "BEA/BLS/Census vintage (retrieved $FETCH_VINTAGE) through the same ingestion path " *
            "as the shipped 2024 artifact; every quarterly series (data, ea, and the financial " *
            "stock series in calibration) is copied unchanged from the 2024 artifact.",
    )
end

function write_provenance_toml(path::String, artifact_path::String, meta, result)
    open(path, "w") do io
        println(io, "# Provenance for $(relpath(artifact_path, REPO_ROOT))")
        println(io, "# Generated by scripts/us/calibration/structural_vintage/ (stage2b workstream 2b-4)")
        println(io, "artifact_path = \"$(relpath(artifact_path, REPO_ROOT))\"")
        println(io, "artifact_sha256 = \"$(sha256_file(artifact_path))\"")
        for key in (
                "structural_reference_year", "period", "created_at",
                "annual_structure_data_vintage", "beforeit_version",
                "quarterly_block_source", "quarterly_block_source_sha256",
                "workstream",
            )
            value = meta[key]
            println(io, "$key = $(value isa Integer ? value : "\"$(value)\"")")
        end
        println(io, "mixed_vintage_note = \"\"\"$(meta["mixed_vintage_note"])\"\"\"")
        if result !== nothing
            farm = result.farm
            println(io, "farm_count = $(farm.value)")
            println(io, "farm_count_source = \"$(farm.source)\"")
            println(io, "farm_count_url = \"$(farm.url)\"")
            println(io, "farm_count_status = \"DUBIOUS\"  # farm != model firm concept, same as the 2024 path")
        end
        println(io, "")
        if result !== nothing
            for record in result.records
                println(io, "[[source]]")
                println(io, "source = \"$(record.source)\"")
                println(io, "dataset = \"$(record.dataset)\"")
                println(io, "request_id = \"$(record.request_id)\"")
                println(io, "sha256 = \"$(record.sha256)\"")
                println(io, "path = \"$(record.path)\"")
                println(io, "retrieved_at = \"$(record.retrieved_at)\"")
                isempty(record.detail) || println(io, "detail = \"\"\"$(record.detail)\"\"\"")
                println(io, "")
            end
        end
    end
    return path
end

function save_vintage_artifact(year::Int, result; out_path::Union{Nothing, String} = nothing)
    artifact_path = out_path === nothing ?
        joinpath(CALIBRATION_ROOT, "US_$(year)_calibration_object.jld2") : out_path
    isfile(artifact_path) &&
        error("Refusing to overwrite an existing artifact: $artifact_path")
    base_sha = sha256_file(BASE_ARTIFACT_PATH)
    meta = artifact_metadata(year, result, base_sha)
    JLD2.jldsave(artifact_path; calibration_object = result.object, metadata = meta)
    toml_path = replace(artifact_path, ".jld2" => ".provenance.toml")
    write_provenance_toml(toml_path, artifact_path, meta, result)
    return artifact_path, toml_path
end

end # module
