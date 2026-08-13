#!/usr/bin/env julia

using Dates
using HTTP
using JSON
using SHA

const SOURCE_URL =
    "https://apps.bea.gov/industry/release/zip/" *
    "MAKE-USE-IMPORTS%20(AFTER%20REDEFINITIONS).zip"
const EXPECTED_SHA256 =
    "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
const EXPECTED_BYTE_COUNT = 8_326_144
const EXPECTED_CONTENT_TYPE = "application/x-zip-compressed"
const USER_AGENT = "BeforeIT-US-accounting-research/1.0"

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
timestamp(value) =
    Dates.format(value, dateformat"yyyy-mm-ddTHH:MM:SS.sss") * "Z"

function usage(io = stdout)
    return println(
        io,
        "usage: julia --project=scripts/us scripts/us/accounting/" *
            "acquire_bea_after_redefinitions.jl ARCHIVE_PATH METADATA_PATH",
    )
end

function usage_error()
    io = IOBuffer()
    usage(io)
    throw(ArgumentError(String(take!(io))))
end

function header_value(response, name)
    value = HTTP.header(response, name, nothing)
    return value === nothing ? "" : String(value)
end

function canonical_json(value)
    if value isa AbstractDict
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        fields = [
            JSON.json(String(key)) * ":" * canonical_json(item)
                for (key, item) in entries
        ]
        return "{" * join(fields, ",") * "}"
    elseif value isa AbstractVector
        return "[" * join(canonical_json.(value), ",") * "]"
    elseif value === nothing ||
            value isa Bool ||
            value isa Number ||
            value isa AbstractString
        return JSON.json(value)
    end
    error("unsupported canonical JSON value of type $(typeof(value))")
end

function validate_output_paths(args)
    length(args) == 2 || usage_error()
    archive_path, metadata_path = String.(args)
    for (label, path) in (
            ("archive", archive_path),
            ("metadata", metadata_path),
        )
        isempty(strip(path)) && error("$label output path must not be empty")
        path == "-" && error("$label output path must be a file, not standard output")
        isdir(path) && error("$label output path is an existing directory: $path")
    end
    endswith(lowercase(archive_path), ".zip") ||
        error("archive output path must end in .zip")
    endswith(lowercase(metadata_path), ".json") ||
        error("metadata output path must end in .json")

    archive_path = abspath(normpath(archive_path))
    metadata_path = abspath(normpath(metadata_path))
    archive_path != metadata_path ||
        error("archive and metadata output paths must be different")
    return archive_path, metadata_path
end

function write_exclusive(path, bytes)
    if isfile(path)
        read(path) == bytes ||
            error("refusing to overwrite different bytes at $path")
        return false
    elseif ispath(path)
        error("refusing to replace non-file output at $path")
    end

    mkpath(dirname(path))
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

function main(args = ARGS)
    if length(args) == 1 && only(args) in ("-h", "--help")
        usage()
        return nothing
    end
    archive_path, metadata_path = validate_output_paths(args)

    response = HTTP.get(
        SOURCE_URL;
        headers = ["User-Agent" => USER_AGENT],
        redirect = true,
        status_exception = false,
    )
    acquired_at = now(UTC)

    response.status == 200 ||
        error("BEA after-redefinitions download returned HTTP $(response.status)")
    bytes = Vector{UInt8}(response.body)
    length(bytes) == EXPECTED_BYTE_COUNT ||
        error(
        "BEA after-redefinitions ZIP byte count changed: expected " *
            "$(EXPECTED_BYTE_COUNT), received $(length(bytes))",
    )
    digest = sha256_hex(bytes)
    digest == EXPECTED_SHA256 ||
        error(
        "BEA after-redefinitions ZIP SHA-256 changed: expected " *
            "$EXPECTED_SHA256, received $digest",
    )

    content_type = lowercase(
        first(split(header_value(response, "Content-Type"), ';')),
    )
    content_type == EXPECTED_CONTENT_TYPE ||
        error(
        "BEA after-redefinitions ZIP content type changed: expected " *
            "$EXPECTED_CONTENT_TYPE, received $content_type",
    )

    metadata = Dict{String, Any}(
        "accounting_gate_effect" => "NONE",
        "acquired_at_utc" => timestamp(acquired_at),
        "byte_count" => length(bytes),
        "expected_byte_count" => EXPECTED_BYTE_COUNT,
        "expected_sha256" => EXPECTED_SHA256,
        "forecast_origin_admissible" => false,
        "http_content_length" => header_value(response, "Content-Length"),
        "http_content_type" => header_value(response, "Content-Type"),
        "http_etag" => header_value(response, "ETag"),
        "http_last_modified" => header_value(response, "Last-Modified"),
        "http_status" => response.status,
        "model_state_write" => false,
        "model_write_effect" => "NONE",
        "mutable_source_warning" =>
            "The public BEA URL is mutable in place; this receipt proves only " *
            "the bytes retrieved at acquired_at_utc.",
        "request_method" => "GET",
        "schema_version" => "beforeit-us-http-acquisition.v1",
        "sha256" => digest,
        "source_agency" => "U.S. Bureau of Economic Analysis",
        "source_artifact" =>
            "MAKE-USE-IMPORTS (AFTER REDEFINITIONS).zip",
        "source_dataset" => "Input-Output (After Redefinitions)",
        "source_url" => SOURCE_URL,
    )
    metadata_bytes =
        Vector{UInt8}(codeunits(canonical_json(metadata) * "\n"))

    write_exclusive(archive_path, bytes)
    write_exclusive(metadata_path, metadata_bytes)

    println("archived BEA after-redefinitions ZIP")
    println("  archive: $archive_path")
    println("  metadata: $metadata_path")
    println("  SHA-256: $digest")
    println("  bytes: $(length(bytes))")
    println("  acquired: $(timestamp(acquired_at))")
    println("  metadata SHA-256: $(sha256_hex(metadata_bytes))")
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
