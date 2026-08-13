#!/usr/bin/env julia

using Dates
using HTTP
using JSON
using SHA

const SOURCE_URL =
    "https://apps.bea.gov/industry/release/zip/" *
    "DIRECT%20REQUIREMENTS%20AND%20MARKET%20SHARE%20MATRICES.zip"
const EXPECTED_SHA256 =
    "e9b9ac6b45bc0385aeb7c21f38ffbcf3eab2e92c0ecadecc43b11ab6dd104eae"
const EXPECTED_BYTE_COUNT = 8_486_511
const EXPECTED_CONTENT_TYPE = "application/x-zip-compressed"
const EXPECTED_MEMBERS = Dict(
    "CxI_DR_Summary.xlsx" =>
        "2e128bc5a51e7a12854e9a58afd5ebaca2e384e80abe113fd4274179628b3439",
    "IxC_MS_Summary.xlsx" =>
        "57c858ae61fa02d6f5b419d265a695318386ec21078ac24d0622f2001aca89d2",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function usage_error()
    error(
        "usage: julia --project=scripts/us scripts/us/accounting/" *
            "acquire_direct_requirements.jl OUTPUT_DIRECTORY",
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

length(ARGS) == 1 || usage_error()
output_directory = only(ARGS)
started_at = now(UTC)
response = HTTP.get(
    SOURCE_URL;
    headers = ["User-Agent" => "BeforeIT-US-accounting-research/1.0"],
    redirect = true,
    status_exception = false,
)
completed_at = now(UTC)

response.status == 200 ||
    error("BEA direct-requirements download returned HTTP $(response.status)")
bytes = Vector{UInt8}(response.body)
length(bytes) == EXPECTED_BYTE_COUNT ||
    error("BEA direct-requirements ZIP byte count changed")
digest = sha256_hex(bytes)
digest == EXPECTED_SHA256 ||
    error("BEA direct-requirements ZIP SHA-256 changed")
content_type = lowercase(
    first(split(header_value(response, "Content-Type"), ';')),
)
content_type == EXPECTED_CONTENT_TYPE ||
    error("BEA direct-requirements ZIP content type changed")

mkpath(output_directory)
raw_path = joinpath(output_directory, "$digest.zip")
metadata_path = joinpath(output_directory, "$digest.metadata.json")
write_exclusive(raw_path, bytes)

timestamp(value) =
    Dates.format(value, dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"
metadata = Dict{String, Any}(
    "schema_version" => "beforeit-us-http-acquisition.v1",
    "source_agency" => "U.S. Bureau of Economic Analysis",
    "source_dataset" => "Input-Output (After Redefinitions)",
    "source_artifact" =>
        "DIRECT REQUIREMENTS AND MARKET SHARE MATRICES.zip",
    "source_url" => SOURCE_URL,
    "request_method" => "GET",
    "retrieval_started_at_utc" => timestamp(started_at),
    "retrieval_completed_at_utc" => timestamp(completed_at),
    "http_status" => response.status,
    "content_type" => header_value(response, "Content-Type"),
    "content_length" => header_value(response, "Content-Length"),
    "last_modified" => header_value(response, "Last-Modified"),
    "etag" => header_value(response, "ETag"),
    "sha256" => digest,
    "byte_count" => length(bytes),
    "expected_members" => EXPECTED_MEMBERS,
    "vintage_classification" =>
        "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE",
    "forecast_origin_admissible" => false,
    "accounting_gate_effect" => "NONE",
    "mutable_source_warning" =>
        "The public BEA URL is mutable in place; this receipt proves only " *
        "the bytes retrieved at the recorded completion time.",
)
metadata_bytes = Vector{UInt8}(codeunits(JSON.json(metadata, 2) * "\n"))
write_exclusive(metadata_path, metadata_bytes)

println("archived BEA direct-requirements ZIP")
println("  SHA-256: $digest")
println("  bytes: $(length(bytes))")
println("  retrieval completed: $(timestamp(completed_at))")
println("  metadata SHA-256: $(sha256_hex(metadata_bytes))")
