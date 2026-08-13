#!/usr/bin/env julia

using Dates
using HTTP
using JSON
using SHA

const ENDPOINT = "https://apps.bea.gov/api/data"
const TABLE_NAME = "T50805B"
const REQUEST_YEARS = "2025,2026"
const REDACTION_TOKEN = "[REDACTED:BEA_API_KEY]"
const EXPECTED_ROW_COUNT = 174
const EXPECTED_PERIODS =
    ["2025Q1", "2025Q2", "2025Q3", "2025Q4", "2026Q1", "2026Q2"]
const EXPECTED_CONTENT_FINGERPRINT_SHA256 =
    "e141b2edd846e8046af278b33e9fe3951e6416e03c41d953351b1784bc916ab1"
const DATA_FIELDS = (
    "TableName",
    "SeriesCode",
    "LineNumber",
    "LineDescription",
    "TimePeriod",
    "METRIC_NAME",
    "CL_UNIT",
    "UNIT_MULT",
    "DataValue",
    "NoteRef",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
timestamp(value) =
    Dates.format(value, dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"

function usage_error()
    error(
        "usage: BEA_API_KEY=... julia --project=scripts/us " *
            "scripts/us/accounting/acquire_bea_t50805b.jl OUTPUT_DIRECTORY",
    )
end

function header_value(response, name)
    value = HTTP.header(response, name, nothing)
    return value === nothing ? "" : String(value)
end

function write_exclusive(path, bytes)
    if isfile(path)
        read(path) == bytes ||
            error("refusing to overwrite different bytes at $path")
        return false
    end
    temporary_path, io = mktemp(dirname(path))
    try
        write(io, bytes)
        close(io)
        mv(temporary_path, path; force = false)
    catch
        isopen(io) && close(io)
        isfile(temporary_path) && rm(temporary_path)
        rethrow()
    end
    return true
end

function request_parameters(user_id)
    return [
        "UserID" => user_id,
        "method" => "GetData",
        "DataSetName" => "NIPA",
        "TableName" => TABLE_NAME,
        "Frequency" => "Q",
        "Year" => REQUEST_YEARS,
        "ResultFormat" => "JSON",
    ]
end

function redact_user_id(bytes, user_id)
    text = String(copy(bytes))
    occurrences = length(findall(user_id, text))
    occurrences == 1 ||
        error(
        "BEA response must echo the API key exactly once before archival",
    )
    redacted = replace(text, user_id => REDACTION_TOKEN; count = 1)
    occursin(user_id, redacted) &&
        error("BEA API key remains in the response after redaction")
    return Vector{UInt8}(codeunits(redacted))
end

function request_map(payload)
    parameters = payload["BEAAPI"]["Request"]["RequestParam"]
    result = Dict{String, String}()
    for parameter in parameters
        name = uppercase(String(parameter["ParameterName"]))
        haskey(result, name) &&
            error("BEA response contains a duplicate request parameter")
        result[name] = String(parameter["ParameterValue"])
    end
    return result
end

function validate_payload(payload)
    haskey(payload, "BEAAPI") ||
        error("BEA response has no BEAAPI envelope")
    root = payload["BEAAPI"]
    haskey(root, "Request") && haskey(root, "Results") ||
        error("BEA response omits its request or results envelope")
    request = request_map(payload)
    request == Dict(
        "USERID" => REDACTION_TOKEN,
        "METHOD" => "GETDATA",
        "DATASETNAME" => "NIPA",
        "TABLENAME" => TABLE_NAME,
        "FREQUENCY" => "Q",
        "YEAR" => REQUEST_YEARS,
        "RESULTFORMAT" => "JSON",
    ) || error("BEA response request echo differs from the frozen query")

    results = root["Results"]
    haskey(results, "Error") &&
        error("BEA response contains an API error")
    rows = get(results, "Data", nothing)
    rows isa AbstractVector ||
        error("BEA response has no Data array")
    length(rows) == EXPECTED_ROW_COUNT ||
        error("BEA response row count changed")
    observed_periods =
        sort!(unique(String(row["TimePeriod"]) for row in rows))
    observed_periods == EXPECTED_PERIODS ||
        error("BEA response quarter coverage changed")
    for period in EXPECTED_PERIODS
        period_rows = [row for row in rows if row["TimePeriod"] == period]
        sort(
            [
                parse(Int, String(row["LineNumber"]))
                    for row in period_rows
            ]
        ) ==
            collect(1:29) ||
            error("BEA response line coverage changed for $period")
    end
    for row in rows
        String(row["TableName"]) == TABLE_NAME ||
            error("BEA response contains a row from another table")
        line_number = parse(Int, String(row["LineNumber"]))
        if line_number <= 26
            String(row["METRIC_NAME"]) == "Current Dollars" ||
                error("BEA current-dollar metric changed")
            String(row["CL_UNIT"]) == "Level" ||
                error("BEA level selector changed")
            String(row["UNIT_MULT"]) == "6" ||
                error("BEA current-dollar unit multiplier changed")
        else
            String(row["METRIC_NAME"]) == "Current Dollar Ratios" ||
                error("BEA ratio metric changed")
            String(row["CL_UNIT"]) == "Level" ||
                error("BEA ratio level selector changed")
            String(row["UNIT_MULT"]) == "0" ||
                error("BEA ratio unit multiplier changed")
        end
    end
    notes = get(results, "Notes", Any[])
    any(
        note ->
        String(get(note, "NoteRef", "")) == "T50805B" &&
            occursin(
            "LastRevised: July 30, 2026",
            String(get(note, "NoteText", "")),
        ),
        notes,
    ) || error("BEA table revision note changed")
    return nothing
end

function content_fingerprint(results)
    io = IOBuffer()
    for row in results["Data"]
        for field in DATA_FIELDS
            value = String(row[field])
            write(io, string(ncodeunits(value)), ':', value, '\0')
        end
    end
    for note in results["Notes"]
        for field in ("NoteRef", "NoteText")
            value = String(note[field])
            write(io, string(ncodeunits(value)), ':', value, '\0')
        end
    end
    write(io, String(results["Statistic"]))
    return sha256_hex(take!(io))
end

function main(args = ARGS)
    length(args) == 1 || usage_error()
    user_id = get(ENV, "BEA_API_KEY", "")
    isempty(strip(user_id)) &&
        error("BEA_API_KEY must be provided without placing it on the command line")
    output_directory = only(args)

    started_at = now(UTC)
    response = HTTP.get(
        ENDPOINT;
        query = request_parameters(user_id),
        headers = ["User-Agent" => "BeforeIT-US-accounting-research/1.0"],
        redirect = true,
        status_exception = false,
    )
    completed_at = now(UTC)

    response.status == 200 ||
        error("BEA T50805B request returned HTTP $(response.status)")
    content_type =
        lowercase(first(split(header_value(response, "Content-Type"), ';')))
    content_type == "application/json" ||
        error("BEA T50805B response content type changed")

    wire_bytes = Vector{UInt8}(response.body)
    wire_byte_count = length(wire_bytes)
    wire_byte_count > 0 ||
        error("BEA T50805B response body is empty")
    content_length = tryparse(
        Int,
        strip(header_value(response, "Content-Length")),
    )
    content_length == wire_byte_count ||
        error("BEA T50805B Content-Length differs from received bytes")
    redacted_bytes = redact_user_id(wire_bytes, user_id)
    length(wire_bytes) == wire_byte_count ||
        error("BEA T50805B redaction mutated the wire-byte buffer")
    payload = JSON.parse(String(copy(redacted_bytes)))
    validate_payload(payload)
    digest = sha256_hex(redacted_bytes)
    results = payload["BEAAPI"]["Results"]
    fingerprint = content_fingerprint(results)
    fingerprint == EXPECTED_CONTENT_FINGERPRINT_SHA256 ||
        error("BEA T50805B content fingerprint changed: $fingerprint")

    mkpath(output_directory)
    source_path = joinpath(output_directory, "$digest.redacted.json")
    metadata_path = joinpath(output_directory, "$digest.metadata.json")
    write_exclusive(source_path, redacted_bytes)

    metadata = Dict{String, Any}(
        "schema_version" => "beforeit-us-http-acquisition.v1",
        "source_agency" => "U.S. Bureau of Economic Analysis",
        "source_dataset" => "NIPA",
        "source_table" => TABLE_NAME,
        "source_url" => ENDPOINT,
        "request_method" => "GET",
        "request" => Dict(
            "method" => "GetData",
            "DataSetName" => "NIPA",
            "TableName" => TABLE_NAME,
            "Frequency" => "Q",
            "Year" => REQUEST_YEARS,
            "ResultFormat" => "JSON",
        ),
        "retrieval_started_at_utc" => timestamp(started_at),
        "retrieval_completed_at_utc" => timestamp(completed_at),
        "http_status" => response.status,
        "content_type" => header_value(response, "Content-Type"),
        "content_length" => string(content_length),
        "http_date" => header_value(response, "Date"),
        "etag" => header_value(response, "ETag"),
        "last_modified" => header_value(response, "Last-Modified"),
        "wire_byte_count" => wire_byte_count,
        "redacted_byte_count" => length(redacted_bytes),
        "redacted_sha256" => digest,
        "content_fingerprint_sha256" => fingerprint,
        "api_production_time_utc" =>
            String(results["UTCProductionTime"]) * "Z",
        "row_count" => length(results["Data"]),
        "periods" => EXPECTED_PERIODS,
        "redaction" => Dict(
            "request_field" => "UserID",
            "replacement" => REDACTION_TOKEN,
            "occurrence_count" => 1,
            "wire_payload_archived" => false,
        ),
        "vintage_classification" =>
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE",
        "forecast_origin_admissible" => false,
        "accounting_gate_effect" => "NONE",
        "model_state_write_authorized" => false,
        "promotion_ready" => false,
        "mutable_source_warning" =>
            "The BEA API is mutable; this receipt proves only the redacted " *
            "response bytes retrieved at the recorded completion time.",
    )
    metadata_bytes = Vector{UInt8}(codeunits(JSON.json(metadata, 2) * "\n"))
    write_exclusive(metadata_path, metadata_bytes)

    println("archived redacted BEA NIPA T50805B response")
    println("  SHA-256: $digest")
    println("  bytes: $(length(redacted_bytes))")
    println("  retrieval completed: $(timestamp(completed_at))")
    println("  metadata SHA-256: $(sha256_hex(metadata_bytes))")
    return (; source_path, metadata_path, digest)
end

abspath(PROGRAM_FILE) == abspath(@__FILE__) && main()
