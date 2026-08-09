module BEANIPAPilotReceipt

using Dates
using JSON
using SHA
using TOML

if !isdefined(parentmodule(@__MODULE__), :BEANIPAAcquisition)
    include(joinpath(@__DIR__, "BEANIPAAcquisition.jl"))
end
using ..BEANIPAAcquisition

include(
    joinpath(
        @__DIR__,
        "receipts",
        "BEAWorkbookReceipts.jl",
    ),
)
using .BEAWorkbookReceipts

export PILOT_ARCHIVE_DIRECTORY_ID,
    PILOT_CONTENT_FINGERPRINT_FILE_SHA256,
    PILOT_CONTENT_FINGERPRINT_PARSER_SHA256,
    PILOT_CONTENT_FINGERPRINT_SCHEMA,
    PILOT_PROFILE_FILE_SHA256,
    install_pilot_receipt,
    pilot_content_fingerprint_path,
    receipt_fetches

const PILOT_ARCHIVE_DIRECTORY_ID = "16887"
const PILOT_PROFILE_SOURCE_PATH =
    joinpath(@__DIR__, "pilot_2026q2_target_profile.toml")
const PILOT_PROFILE_FILE_SHA256 =
    "cd1b8ac0d98dafbafcce13a035573e9dec728b68de01c96b53f04a06f5bfba00"
const PILOT_CONTENT_FINGERPRINT_FILE_SHA256 =
    "a08c824620e30d09ebdb9bd35cadd1d9f45e36a7bf5b83e1d4d1551d1310bf33"
const PILOT_CONTENT_FINGERPRINT_SCHEMA =
    "beforeit-us-bea-nipa-content-fingerprint.v2"
const PILOT_CONTENT_FINGERPRINT_PARSER_SHA256 =
    "7f054199aa7077a2ee3a68c001279a3795c9d4305031588253441ddb90cda55e"
const PROFILE_ARTIFACT_NAME =
    "profile-file-sha256-$PILOT_PROFILE_FILE_SHA256.toml"
const RECEIPT_AGENT = "beforeit-bea-nipa-live-capture"
const RECEIPT_AGENT_VERSION = "1.0.0"
const OBSERVER_ID = "beforeit-us-forecasting"
const IDENTIFIER_TIMESTAMP_FORMAT =
    dateformat"yyyymmddTHHMMSSsss"

struct PilotReceiptError <: Exception
    message::String
end

Base.showerror(io::IO, error::PilotReceiptError) =
    print(io, error.message)

fail(location, message) =
    throw(PilotReceiptError("$location: $message"))

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function pilot_content_fingerprint_path(raw_root)
    return joinpath(
        abspath(String(raw_root)),
        "bea_nipa",
        "hmi7",
        "content",
        "bea-nipa-content-fingerprint-sha256-" *
            PILOT_CONTENT_FINGERPRINT_FILE_SHA256 *
            ".json",
    )
end

function _validate_source_file(path, expected_sha256, location)
    isfile(path) || fail(location, "file does not exist: $path")
    islink(path) && fail(location, "must not be a symbolic link")
    bytes = read(path)
    isempty(bytes) && fail(location, "must not be empty")
    actual = sha256_hex(bytes)
    actual == expected_sha256 ||
        fail(
        location,
        "expected SHA-256 $expected_sha256, found $actual",
    )
    return bytes
end

function _validate_content_fingerprint_source(path)
    isfile(path) ||
        fail("content fingerprint", "file does not exist: $path")
    islink(path) &&
        fail("content fingerprint", "must not be a symbolic link")
    bytes = read(path)
    isempty(bytes) &&
        fail("content fingerprint", "must not be empty")
    digest = sha256_hex(bytes)
    expected_name =
        "bea-nipa-content-fingerprint-sha256-$digest.json"
    basename(path) == expected_name ||
        fail(
        "content fingerprint",
        "must be content addressed as $expected_name",
    )
    document = try
        JSON.parse(String(copy(bytes)))
    catch error
        return fail(
            "content fingerprint",
            "is not valid JSON ($(sprint(showerror, error)))",
        )
    end
    artifact = get(document, "artifact", nothing)
    artifact isa AbstractDict ||
        fail("content fingerprint", "has no artifact object")
    get(artifact, "schema_version", nothing) ==
        PILOT_CONTENT_FINGERPRINT_SCHEMA ||
        fail("content fingerprint", "has an unsupported schema")
    get(artifact, "parser_sha256", nothing) ==
        PILOT_CONTENT_FINGERPRINT_PARSER_SHA256 ||
        fail("content fingerprint", "was not emitted by the pinned parser")
    get(artifact, "release_id", nothing) == PILOT_RELEASE_ID ||
        fail("content fingerprint", "belongs to another release")
    get(artifact, "raw_bundle_sha256", nothing) == bundle_sha256() ||
        fail("content fingerprint", "belongs to another raw pair")
    parser_path =
        joinpath(@__DIR__, "fingerprint_2026q2_pilot.py")
    _validate_source_file(
        parser_path,
        PILOT_CONTENT_FINGERPRINT_PARSER_SHA256,
        "content-fingerprint parser",
    )
    return (; bytes, digest)
end

function _optional_header(value)
    value == "NOT_PROVIDED" && return nothing
    return String(value)
end

function _raw_artifact_name(expectation)
    return "raw-sha256-$(expectation.expected_sha256).xlsx"
end

function receipt_fetches(acquisition)
    length(acquisition.fetched_workbooks) == length(PILOT_EXPECTATIONS) ||
        fail("acquisition", "does not contain the exact pilot pair")
    validate_fetched_pair(acquisition.fetched_workbooks)
    return [
        WorkbookFetch(
                raw_bytes = fetched.raw_bytes,
                raw_artifact_path = _raw_artifact_name(expectation),
                storage_encoding = "identity",
                release_id = expectation.release_id,
                workbook_id = expectation.workbook_id,
                reference_period = "2026Q2",
                estimate_label = "advance",
                archive_label_url_component = "Advance_July-30-2026",
                archive_directory_id = PILOT_ARCHIVE_DIRECTORY_ID,
                section_id = expectation.section_id,
                filename = basename(expectation.requested_locator),
                file_format = "xlsx",
                requested_url = fetched.requested_locator,
                effective_url = fetched.effective_locator,
                status_code = fetched.http_status,
                redirect_count = 0,
                content_type = fetched.content_type,
                content_length_header = parse(
                    Int,
                    fetched.content_length,
                ),
                etag = _optional_header(fetched.etag),
                last_modified = _optional_header(fetched.last_modified),
                content_disposition = nothing,
                acquisition_started_at_utc =
                fetched.acquisition_started_at_utc,
                response_headers_at_utc =
                fetched.response_headers_at_utc,
                acquisition_completed_at_utc =
                fetched.acquisition_completed_at_utc,
            )
            for (expectation, fetched) in
            zip(PILOT_EXPECTATIONS, acquisition.fetched_workbooks)
    ]
end

function _identifier_timestamp(value)
    return lowercase(
        Dates.format(value, IDENTIFIER_TIMESTAMP_FORMAT) * "z",
    )
end

function _toml_bytes(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    isempty(bytes) && fail("receipt serialization", "must not be empty")
    if bytes[end] != UInt8('\n')
        push!(bytes, UInt8('\n'))
    end
    return bytes
end

function _write_exact(path, bytes)
    ispath(path) &&
        fail("receipt staging", "refuses to overwrite $path")
    open(path, "w") do io
        write(io, bytes)
        flush(io)
    end
    read(path) == bytes ||
        fail("receipt staging", "written bytes failed read-back at $path")
    return path
end

function _validate_existing_bundle(
        bundle_path,
        receipt_name,
        expected_files,
    )
    islink(bundle_path) &&
        fail("receipt bundle", "must not be a symbolic link")
    isdir(bundle_path) ||
        fail("receipt bundle", "existing path is not a directory")
    readdir(bundle_path; sort = true) == sort!(collect(keys(expected_files))) ||
        fail("receipt bundle", "contains an unexpected file set")
    for (name, bytes) in expected_files
        path = joinpath(bundle_path, name)
        isfile(path) ||
            fail("receipt bundle", "missing regular file $name")
        islink(path) &&
            fail("receipt bundle", "$name must not be a symbolic link")
        read(path) == bytes ||
            fail("receipt bundle", "$name does not match expected bytes")
    end
    result = validate_receipt_file(joinpath(bundle_path, receipt_name))
    raw_results = verify_local_raw_files(
        TOML.parsefile(joinpath(bundle_path, receipt_name)),
        bundle_path,
    )
    return (; result, raw_results)
end

"""
    install_pilot_receipt(raw_root, acquisition)

Build and atomically persist an immutable present-day receipt bundle for one
already completed exact-pair acquisition. The bundle includes adjacent copies
of the exact raw bytes, production target profile, parsed-content fingerprint,
and receipt. It cannot establish historical availability, mutate the source
inventory, admit an origin, or emit READY.
"""
function install_pilot_receipt(
        raw_root,
        acquisition;
        content_fingerprint_path =
            pilot_content_fingerprint_path(raw_root),
    )
    acquisition.release_id == PILOT_RELEASE_ID ||
        fail("acquisition.release_id", "does not match the pilot release")
    acquisition.bundle_sha256 == bundle_sha256() ||
        fail("acquisition.bundle_sha256", "does not match the pilot pair")

    profile_bytes = _validate_source_file(
        PILOT_PROFILE_SOURCE_PATH,
        PILOT_PROFILE_FILE_SHA256,
        "target profile",
    )
    fingerprint = _validate_content_fingerprint_source(
        abspath(String(content_fingerprint_path)),
    )
    fingerprint_bytes = fingerprint.bytes
    fingerprint_artifact_name =
        "content-fingerprint-sha256-$(fingerprint.digest).json"
    fetches = receipt_fetches(acquisition)

    receipt_root = joinpath(
        abspath(String(raw_root)),
        "bea_nipa",
        "hmi7",
        "receipts",
        "objects",
    )
    mkpath(receipt_root)
    islink(receipt_root) &&
        fail("receipt root", "must not be a symbolic link")
    staging_path = mktempdir(receipt_root; prefix = ".staging-")
    installed = false
    try
        _write_exact(
            joinpath(staging_path, PROFILE_ARTIFACT_NAME),
            profile_bytes,
        )
        _write_exact(
            joinpath(
                staging_path,
                fingerprint_artifact_name,
            ),
            fingerprint_bytes,
        )

        pair_started =
            minimum(fetch.acquisition_started_at_utc for fetch in fetches)
        identifier_timestamp = _identifier_timestamp(pair_started)
        receipt = build_receipt(
            receipt_id =
                "bea-nipa-r2026q2-advance-pair-$identifier_timestamp.v1",
            transaction_id =
                "bea-nipa-r2026q2-advance-$identifier_timestamp",
            observer_id = OBSERVER_ID,
            capture_agent = RECEIPT_AGENT,
            capture_agent_version = RECEIPT_AGENT_VERSION,
            fetched_workbooks = fetches,
            profile_artifact_path = PROFILE_ARTIFACT_NAME,
            content_fingerprint_artifact_path =
                fingerprint_artifact_name,
            base_dir = staging_path,
        )
        receipt_content_sha256 =
            receipt["artifact"]["content_sha256"]
        receipt_name =
            "receipt-content-sha256-$receipt_content_sha256.toml"
        receipt_bytes = _toml_bytes(receipt)

        expected_files = Dict{String, Vector{UInt8}}(
            PROFILE_ARTIFACT_NAME => profile_bytes,
            fingerprint_artifact_name => fingerprint_bytes,
            receipt_name => receipt_bytes,
        )
        for fetch in fetches
            expected_files[fetch.raw_artifact_path] = fetch.raw_bytes
        end
        for (name, bytes) in expected_files
            name == PROFILE_ARTIFACT_NAME && continue
            name == fingerprint_artifact_name && continue
            _write_exact(joinpath(staging_path, name), bytes)
        end

        staged = _validate_existing_bundle(
            staging_path,
            receipt_name,
            expected_files,
        )
        bundle_path =
            joinpath(receipt_root, "sha256-$receipt_content_sha256")
        if ispath(bundle_path)
            existing = _validate_existing_bundle(
                bundle_path,
                receipt_name,
                expected_files,
            )
            rm(staging_path; recursive = true)
            installed = true
            return (
                bundle_path = bundle_path,
                receipt_path = joinpath(bundle_path, receipt_name),
                receipt_file_sha256 = sha256_hex(receipt_bytes),
                receipt_content_sha256 = receipt_content_sha256,
                content_fingerprint_file_sha256 = fingerprint.digest,
                validation = existing.result,
                raw_validation = existing.raw_results,
                historical_release_availability_verified = false,
                origin_admissible = false,
                ready = false,
                inventory_mutated = false,
            )
        end
        mv(staging_path, bundle_path)
        installed = true
        return (
            bundle_path = bundle_path,
            receipt_path = joinpath(bundle_path, receipt_name),
            receipt_file_sha256 = sha256_hex(receipt_bytes),
            receipt_content_sha256 = receipt_content_sha256,
            content_fingerprint_file_sha256 = fingerprint.digest,
            validation = staged.result,
            raw_validation = staged.raw_results,
            historical_release_availability_verified = false,
            origin_admissible = false,
            ready = false,
            inventory_mutated = false,
        )
    finally
        !installed && ispath(staging_path) &&
            rm(staging_path; recursive = true)
    end
end

end
