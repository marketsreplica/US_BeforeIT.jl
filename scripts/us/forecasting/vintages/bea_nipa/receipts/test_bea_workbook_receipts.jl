using Base64
using Dates
using JSON
using SHA
using TOML
using Test

include(joinpath(@__DIR__, "BEAWorkbookReceipts.jl"))
using .BEAWorkbookReceipts

const FIXTURE_DIR = joinpath(@__DIR__, "fixtures")
const RECEIPT_PATH = joinpath(FIXTURE_DIR, "synthetic_receipt.toml")
const PROFILE_PATH = joinpath(FIXTURE_DIR, "synthetic_target_profile.toml")
const FINGERPRINT_PATH =
    joinpath(FIXTURE_DIR, "synthetic_content_fingerprint.json")
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"

checked_receipt() = TOML.parsefile(RECEIPT_PATH)
checked_profile() = TOML.parsefile(PROFILE_PATH)
checked_fingerprint() = JSON.parsefile(FINGERPRINT_PATH)

function decoded_fixture(workbook)
    path = joinpath(FIXTURE_DIR, workbook["raw_artifact_path"])
    return base64decode(chomp(read(path, String)))
end

function restamp!(artifact)
    stamp_content_sha256!(artifact)
    return artifact
end

function receipt_error(function_to_run)
    caught = try
        function_to_run()
        nothing
    catch error
        error
    end
    @test caught isa ReceiptValidationError
    return sprint(showerror, caught)
end

function parsed_timestamp(text)
    return DateTime(text[1:(end - 1)], TIMESTAMP_FORMAT)
end

function optional_header(workbook, name)
    return workbook["$(name)_status"] == "PRESENT" ?
        String(workbook[name]) : nothing
end

function fixture_fetches(receipt = checked_receipt())
    return [
        WorkbookFetch(
                raw_bytes = decoded_fixture(workbook),
                raw_artifact_path = workbook["raw_artifact_path"],
                storage_encoding = workbook["storage_encoding"],
                release_id = workbook["release_id"],
                workbook_id = workbook["workbook_id"],
                reference_period = workbook["reference_period"],
                estimate_label = workbook["estimate_label"],
                archive_label_url_component =
                workbook["archive_label_url_component"],
                archive_directory_id = workbook["archive_directory_id"],
                section_id = workbook["section_id"],
                filename = workbook["filename"],
                file_format = workbook["file_format"],
                requested_url = workbook["requested_url"],
                effective_url = workbook["effective_url"],
                status_code = workbook["status_code"],
                redirect_count = workbook["redirect_count"],
                content_type = workbook["content_type"],
                content_length_header =
                workbook["content_length_header_status"] == "PRESENT" ?
                workbook["content_length_header"] : nothing,
                etag = optional_header(workbook, "etag"),
                last_modified = optional_header(workbook, "last_modified"),
                content_disposition =
                optional_header(workbook, "content_disposition"),
                acquisition_started_at_utc =
                parsed_timestamp(workbook["acquisition_started_at_utc"]),
                response_headers_at_utc =
                parsed_timestamp(workbook["response_headers_at_utc"]),
                acquisition_completed_at_utc =
                parsed_timestamp(workbook["acquisition_completed_at_utc"]),
            )
            for workbook in receipt["workbooks"]
    ]
end

function modified_fetch(fetch::WorkbookFetch; changes...)
    values = Dict{Symbol, Any}(
        field => getfield(fetch, field) for field in fieldnames(WorkbookFetch)
    )
    for (field, value) in changes
        values[field] = value
    end
    return WorkbookFetch(; values...)
end

function built_fixture_receipt(;
        fetches = fixture_fetches(),
        base_dir = FIXTURE_DIR,
        profile_artifact_path = basename(PROFILE_PATH),
        content_fingerprint_artifact_path = basename(FINGERPRINT_PATH),
        max_pair_span_seconds = 300,
    )
    fixture = checked_receipt()
    return build_receipt(
        receipt_id = fixture["artifact"]["receipt_id"],
        transaction_id = fixture["capture"]["transaction_id"],
        observer_id = fixture["capture"]["observer_id"],
        capture_agent = fixture["capture"]["capture_agent"],
        capture_agent_version =
            fixture["capture"]["capture_agent_version"],
        fetched_workbooks = fetches,
        profile_artifact_path = profile_artifact_path,
        content_fingerprint_artifact_path =
            content_fingerprint_artifact_path,
        base_dir = base_dir,
        max_pair_span_seconds = max_pair_span_seconds,
        scope = fixture["artifact"]["scope"],
        allow_synthetic = true,
    )
end

function write_json(path, document; canonical = true)
    text = if canonical
        JSON.json(document; sort_keys = true)
    else
        JSON.json(document; pretty = 2, sort_keys = true)
    end
    open(path, "w") do io
        write(io, text)
        write(io, '\n')
    end
    return path
end

function copy_fixture_dependencies(temporary)
    write(
        joinpath(temporary, basename(PROFILE_PATH)),
        read(PROFILE_PATH),
    )
    write(
        joinpath(temporary, basename(FINGERPRINT_PATH)),
        read(FINGERPRINT_PATH),
    )
    for workbook in checked_receipt()["workbooks"]
        source = joinpath(FIXTURE_DIR, workbook["raw_artifact_path"])
        write(joinpath(temporary, basename(source)), read(source))
    end
    return temporary
end

function fingerprint_mutation_error(
        mutator;
        relink_file_hash = true,
        canonical = true,
        receipt_mutator = receipt -> nothing,
    )
    return mktempdir() do temporary
        copy_fixture_dependencies(temporary)
        receipt = checked_receipt()
        fingerprint = checked_fingerprint()
        mutator(fingerprint)
        temporary_fingerprint =
            joinpath(temporary, basename(FINGERPRINT_PATH))
        write_json(
            temporary_fingerprint,
            fingerprint;
            canonical = canonical,
        )
        if relink_file_hash
            receipt["semantic_linkage"]["content_fingerprint_file_sha256"] =
                bytes2hex(sha256(read(temporary_fingerprint)))
        end
        receipt_mutator(receipt)
        restamp!(receipt)
        return receipt_error(
            () -> validate_receipt(
                receipt,
                temporary;
                allow_synthetic = true,
            ),
        )
    end
end

function write_toml(path, document)
    open(path, "w") do io
        TOML.print(io, document; sorted = true)
        write(io, '\n')
    end
    return path
end

@testset "fixture provenance and exact file hashes" begin
    manifest = TOML.parsefile(joinpath(FIXTURE_DIR, "fixture_manifest.toml"))
    artifact = manifest["artifact"]
    @test artifact["schema_version"] ==
        "beforeit-us-bea-nipa-receipt-fixtures.v1"
    @test artifact["status"] ==
        "SYNTHETIC_CONTRACT_FIXTURES_NOT_SOURCE_EVIDENCE"
    @test artifact["as_of_date"] == "2026-08-05"
    @test artifact["source_workbook_bytes_included"] == false
    @test artifact["historical_availability_evidence_included"] == false
    @test artifact["origin_admission_evidence_included"] == false
    @test artifact["live_acquisition_receipt_included"] == false

    entries = manifest["fixtures"]
    @test length(entries) == 5
    @test issorted([entry["path"] for entry in entries])
    @test length(unique(entry["path"] for entry in entries)) == 5
    for entry in entries
        path = joinpath(FIXTURE_DIR, entry["path"])
        @test isfile(path)
        @test bytes2hex(sha256(read(path))) == entry["file_sha256"]
        @test entry["synthetic"]
        @test !entry["source_evidence"]
        @test !entry["origin_admissible"]
    end

    raw_entries =
        filter(entry -> entry["fixture_kind"] == "base64_raw_workbook", entries)
    @test length(raw_entries) == 2
    for entry in raw_entries
        decoded = base64decode(chomp(read(joinpath(FIXTURE_DIR, entry["path"]), String)))
        @test length(decoded) == entry["decoded_raw_bytes"]
        @test bytes2hex(sha256(decoded)) == entry["decoded_raw_sha256"]
        @test occursin("SYNTHETIC", String(decoded))
    end
end

@testset "synthetic receipt is explicit, immutable, and non-admitting" begin
    @test occursin(
        "allow_synthetic=true",
        receipt_error(() -> validate_receipt_file(RECEIPT_PATH)),
    )
    result = validate_receipt_file(RECEIPT_PATH; allow_synthetic = true)
    @test result.receipt_id ==
        "bea-nipa-synthetic-r2026q2-advance-pair.v1"
    @test result.transaction_id ==
        "bea-nipa-synthetic-capture-20260805t215530z"
    @test result.scope ==
        "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
    @test result.state == "SYNTHETIC_CONTRACT_FIXTURE"
    @test result.release_id == "r2026q2_advance"
    @test result.reference_period == "2026Q2"
    @test result.profile_id == "september_2023_rebase"
    @test result.linked_target_ids == [
        "core_pce_price_index",
        "gdp_deflator",
        "nominal_gdp",
        "pce_price_index",
        "real_gdp",
    ]
    @test result.content_sha256 ==
        checked_receipt()["artifact"]["content_sha256"]
    @test result.profile_content_sha256 ==
        checked_profile()["artifact"]["content_sha256"]
    @test result.profile_file_sha256 == bytes2hex(sha256(read(PROFILE_PATH)))
    @test result.content_fingerprint_file_sha256 ==
        bytes2hex(sha256(read(FINGERPRINT_PATH)))
    @test result.content_fingerprint_schema_version ==
        "beforeit-us-bea-nipa-content-fingerprint.v2"
    @test result.content_fingerprint_parser_sha256 ==
        "7f054199aa7077a2ee3a68c001279a3795c9d4305031588253441ddb90cda55e"
    @test result.receipt_file_sha256 == bytes2hex(sha256(read(RECEIPT_PATH)))
    @test result.receipt_file_bytes == filesize(RECEIPT_PATH)
    @test result.present_day_acquisition_observed
    @test !result.historical_release_availability_verified
    @test !result.release_event_timestamp_verified
    @test !result.first_state_verified
    @test !result.origin_admissible
    @test !result.inventory_registered
    @test !result.ready
    @test [workbook.section_id for workbook in result.workbooks] ==
        ["1", "2"]
    @test result.pair_started == DateTime(2026, 8, 5, 21, 55, 30)
    @test result.pair_completed == DateTime(2026, 8, 5, 21, 55, 37)
end

@testset "local raw verifier binds exact decoded bytes and containers" begin
    raw = verify_local_raw_files(checked_receipt(), FIXTURE_DIR)
    @test Set(keys(raw)) == Set(["1", "2"])
    @test raw["1"].sha256 ==
        "597d1c6f4ba3b7c2c859ad95c382d971afe0e73ffe4308764cb08814f7ebe3f3"
    @test raw["2"].sha256 ==
        "1fcbbed42071c751ff8ce4dba55dd46d08dd187ff7ba1ba3ad4cd5d16ee5fd18"
    @test raw["1"].byte_count == 2324
    @test raw["2"].byte_count == 2324
    @test raw["1"].bytes[1:4] == UInt8[0x50, 0x4b, 0x03, 0x04]
    @test raw["2"].bytes[1:4] == UInt8[0x50, 0x4b, 0x03, 0x04]

    wrong_hash = checked_receipt()
    wrong_hash["workbooks"][1]["raw_sha256"] = repeat("a", 64)
    restamp!(wrong_hash)
    @test occursin(
        "decoded artifact hashes",
        receipt_error(
            () -> validate_receipt(
                wrong_hash,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    wrong_count = checked_receipt()
    wrong_count["workbooks"][1]["raw_bytes"] += 1
    restamp!(wrong_count)
    @test occursin(
        "decoded artifact has 2324 bytes",
        receipt_error(
            () -> validate_receipt(
                wrong_count,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    wrong_signature = checked_receipt()
    wrong_signature["workbooks"][1]["container_signature"] =
        "ole_compound_file"
    restamp!(wrong_signature)
    @test occursin(
        "detected ooxml_zip",
        receipt_error(
            () -> validate_receipt(
                wrong_signature,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    bad_path = checked_receipt()
    bad_path["workbooks"][1]["raw_artifact_path"] = "../outside.xlsx"
    restamp!(bad_path)
    @test occursin(
        "adjacent file",
        receipt_error(
            () -> validate_receipt(
                bad_path,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )
end

@testset "raw-file corruption and incomplete pair fail closed" begin
    mktempdir() do temporary
        receipt = checked_receipt()
        profile_bytes = read(PROFILE_PATH)
        write(joinpath(temporary, basename(PROFILE_PATH)), profile_bytes)
        for workbook in receipt["workbooks"]
            source = joinpath(FIXTURE_DIR, workbook["raw_artifact_path"])
            write(joinpath(temporary, basename(source)), read(source))
        end
        first_path =
            joinpath(temporary, receipt["workbooks"][1]["raw_artifact_path"])
        corrupted = read(first_path)
        corrupted[10] = corrupted[10] == UInt8('A') ? UInt8('B') : UInt8('A')
        write(first_path, corrupted)
        @test occursin(
            "decoded artifact hashes",
            receipt_error(
                () -> validate_receipt(
                    receipt,
                    temporary;
                    allow_synthetic = true,
                ),
            ),
        )
    end

    mktempdir() do temporary
        receipt = checked_receipt()
        write(joinpath(temporary, basename(PROFILE_PATH)), read(PROFILE_PATH))
        workbook = receipt["workbooks"][1]
        write(
            joinpath(temporary, workbook["raw_artifact_path"]),
            read(joinpath(FIXTURE_DIR, workbook["raw_artifact_path"])),
        )
        @test occursin(
            "file does not exist",
            receipt_error(
                () -> verify_local_raw_files(receipt, temporary),
            ),
        )
    end
end

@testset "HTTP and exact official URL metadata fail closed" begin
    mutations = [
        (
            "status_code",
            503,
            "must equal 200",
        ),
        (
            "redirect_count",
            1,
            "must equal 0",
        ),
        (
            "content_type",
            "text/html",
            "application/vnd.openxmlformats",
        ),
        (
            "content_length_header",
            1,
            "decoded raw byte count",
        ),
        (
            "last_modified",
            "2026-07-30",
            "IMF-fixdate",
        ),
        (
            "content_disposition_status",
            "PRESENT",
            "observed header",
        ),
    ]
    for (field, value, expected_message) in mutations
        tampered = checked_receipt()
        tampered["workbooks"][1][field] = value
        restamp!(tampered)
        @test occursin(
            expected_message,
            receipt_error(
                () -> validate_receipt(
                    tampered,
                    FIXTURE_DIR;
                    allow_synthetic = true,
                ),
            ),
        )
    end

    redirected = checked_receipt()
    redirected["workbooks"][1]["requested_url"] =
        "https://apps.bea.gov/redirect"
    restamp!(redirected)
    @test occursin(
        "redirected workbook responses are ambiguous",
        receipt_error(
            () -> validate_receipt(
                redirected,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    wrong_host = checked_receipt()
    wrong_host["workbooks"][1]["requested_url"] =
        replace(
        wrong_host["workbooks"][1]["requested_url"],
        "apps.bea.gov" => "example.com",
    )
    wrong_host["workbooks"][1]["effective_url"] =
        wrong_host["workbooks"][1]["requested_url"]
    restamp!(wrong_host)
    @test occursin(
        "exact official apps.bea.gov",
        receipt_error(
            () -> validate_receipt(
                wrong_host,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    wrong_filename = checked_receipt()
    wrong_filename["workbooks"][1]["filename"] =
        "Section2all_xls.xlsx"
    restamp!(wrong_filename)
    @test occursin(
        "does not match section_id",
        receipt_error(
            () -> validate_receipt(
                wrong_filename,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )
end

@testset "atomic pair timestamps and identities fail closed" begin
    reversed = checked_receipt()
    reversed["workbooks"][1]["response_headers_at_utc"] =
        "2026-08-05T21:55:29Z"
    restamp!(reversed)
    @test occursin(
        "timestamps are not ordered",
        receipt_error(
            () -> validate_receipt(
                reversed,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    wrong_span = checked_receipt()
    wrong_span["capture"]["observed_pair_span_seconds"] = 8
    restamp!(wrong_span)
    @test occursin(
        "timestamps imply 7",
        receipt_error(
            () -> validate_receipt(
                wrong_span,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    too_slow = checked_receipt()
    too_slow["capture"]["max_pair_span_seconds"] = 6
    restamp!(too_slow)
    @test occursin(
        "exceeds maximum span",
        receipt_error(
            () -> validate_receipt(
                too_slow,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    outside = checked_receipt()
    outside["capture"]["pair_completed_at_utc"] =
        "2026-08-05T21:55:36Z"
    outside["capture"]["observed_pair_span_seconds"] = 6
    restamp!(outside)
    @test occursin(
        "lies outside pair interval",
        receipt_error(
            () -> validate_receipt(
                outside,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    for (field, value, expected_message) in (
            ("reference_period", "2026Q1", "URL quarter"),
            (
                "estimate_label",
                "third",
                "archive label does not encode estimate_label",
            ),
            (
                "archive_label_url_component",
                "Third_July-30-2026",
                "archive label does not encode estimate_label",
            ),
            (
                "archive_directory_id",
                "999902",
                "multiple archive directory IDs",
            ),
        )
        tampered = checked_receipt()
        tampered["workbooks"][2][field] = value
        if field == "archive_label_url_component"
            tampered["workbooks"][2]["requested_url"] = replace(
                tampered["workbooks"][2]["requested_url"],
                "Advance_July-30-2026" => value,
            )
            tampered["workbooks"][2]["effective_url"] =
                tampered["workbooks"][2]["requested_url"]
        end
        restamp!(tampered)
        @test occursin(
            expected_message,
            receipt_error(
                () -> validate_receipt(
                    tampered,
                    FIXTURE_DIR;
                    allow_synthetic = true,
                ),
            ),
        )
    end
end

@testset "semantic profile linkage is exact and audit-pinned" begin
    @test occursin(
        "allow_synthetic=true",
        receipt_error(() -> validate_target_profile(checked_profile())),
    )
    profile = validate_target_profile(
        checked_profile();
        allow_synthetic = true,
    )
    @test profile.profile_id == "september_2023_rebase"
    @test profile.release_id == "r2026q2_advance"
    @test profile.reference_period == "2026Q2"
    @test Set(keys(profile.workbooks_by_section)) == Set(["1", "2"])
    @test length(profile.target_fingerprints) == 5

    bad_fingerprint = checked_profile()
    bad_fingerprint["targets"][1]["mapping_fingerprint"] *= "-tampered"
    restamp!(bad_fingerprint)
    @test occursin(
        "exact target mapping",
        receipt_error(
            () -> validate_target_profile(
                bad_fingerprint;
                allow_synthetic = true,
            ),
        ),
    )

    bad_audit = checked_profile()
    bad_audit["artifact"]["source_mapping_audit_file_sha256"] =
        repeat("a", 64)
    restamp!(bad_audit)
    @test occursin(
        "pinned mapping audit",
        receipt_error(
            () -> validate_target_profile(
                bad_audit;
                allow_synthetic = true,
            ),
        ),
    )

    production_profile = checked_profile()
    production_profile["artifact"]["scope"] =
        "EXACT_INSPECTED_WORKBOOK_TARGET_PROFILE"
    audit = BEAWorkbookReceipts.BEANIPAMappingAudit.load_mapping_audit()
    for workbook in production_profile["workbooks"]
        workbook["synthetic_bytes"] = false
        workbook["raw_sha256"] =
            audit.workbooks_by_id[workbook["workbook_id"]]["sha256"]
    end
    restamp!(production_profile)
    production = validate_target_profile(production_profile)
    @test production.scope == "EXACT_INSPECTED_WORKBOOK_TARGET_PROFILE"
    @test production.target_ids == profile.target_ids

    bad_profile_file = checked_receipt()
    bad_profile_file["semantic_linkage"]["profile_file_sha256"] =
        repeat("a", 64)
    restamp!(bad_profile_file)
    @test occursin(
        "exact profile bytes hash",
        receipt_error(
            () -> validate_receipt(
                bad_profile_file,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    bad_targets = checked_receipt()
    reverse!(bad_targets["semantic_linkage"]["linked_target_ids"])
    restamp!(bad_targets)
    @test occursin(
        "must be sorted",
        receipt_error(
            () -> validate_receipt(
                bad_targets,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )
end

@testset "content fingerprint binds exact JSON, raw pair, and five mappings" begin
    stale_bytes = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["platform"] = "tampered-platform";
        relink_file_hash = false,
    )
    @test occursin("exact JSON bytes hash", stale_bytes)

    noncanonical = fingerprint_mutation_error(
        fingerprint -> fingerprint;
        canonical = false,
    )
    @test occursin("must be canonical JSON", noncanonical)

    bad_schema_link = checked_receipt()
    bad_schema_link["semantic_linkage"][
        "content_fingerprint_schema_version",
    ] = "beforeit-us-bea-nipa-content-fingerprint.v3"
    restamp!(bad_schema_link)
    @test occursin(
        "does not match the content-fingerprint artifact",
        receipt_error(
            () -> validate_receipt(
                bad_schema_link,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    bad_parser_link = checked_receipt()
    bad_parser_link["semantic_linkage"][
        "content_fingerprint_parser_sha256",
    ] = repeat("c", 64)
    restamp!(bad_parser_link)
    @test occursin(
        "does not match the content-fingerprint artifact",
        receipt_error(
            () -> validate_receipt(
                bad_parser_link,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    bad_artifact_schema = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["schema_version"] =
            "beforeit-us-bea-nipa-content-fingerprint.v3",
    )
    @test occursin(
        "must equal beforeit-us-bea-nipa-content-fingerprint.v2",
        bad_artifact_schema,
    )

    bad_artifact_parser = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["parser_sha256"] = repeat("d", 64),
    )
    @test occursin(
        "pinned v2 parser SHA-256",
        bad_artifact_parser,
    )

    co_tampered_parser = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["parser_sha256"] = repeat("e", 64);
        receipt_mutator = receipt ->
        receipt["semantic_linkage"][
            "content_fingerprint_parser_sha256",
        ] = repeat("e", 64),
    )
    @test occursin("pinned v2 parser SHA-256", co_tampered_parser)

    bad_canonicalization = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["canonicalization"] =
            "environment_sensitive_json",
    )
    @test occursin(
        "must equal utf8_sorted_keys_compact_json_lf",
        bad_canonicalization,
    )

    bad_identity_scope = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["semantic_identity_scope"] =
            "PARSER_ENVIRONMENT_INCLUDED",
    )
    @test occursin(
        "RAW_WORKBOOK_BYTES_RELEASE_MAPPING_PARSED_VALUES_AND_PARSER_BYTES",
        bad_identity_scope,
    )

    for field in (
            "execution_environment_included",
            "repository_state_included",
        )
        environment_sensitive = fingerprint_mutation_error(
            fingerprint -> fingerprint["artifact"][field] = true,
        )
        @test occursin("must remain false", environment_sensitive)
    end

    old_environment_field = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["artifact"]["python_version"] = "3.12.13",
    )
    @test occursin("extra=[\"python_version\"]", old_environment_field)

    for workbook_index in 1:2
        bad_raw = fingerprint_mutation_error(
            fingerprint ->
            fingerprint["workbooks"][workbook_index]["raw_sha256"] =
                repeat(workbook_index == 1 ? "c" : "d", 64),
        )
        @test occursin("does not match the receipt's exact raw bytes", bad_raw)
    end

    for target_index in 1:5
        bad_mapping = fingerprint_mutation_error(
            fingerprint ->
            fingerprint["targets"][target_index]["sheet_name"] *=
                "-tampered",
        )
        @test occursin(
            "mapping fingerprint does not match the target profile",
            bad_mapping,
        )
    end

    bad_artifact_flag = fingerprint_mutation_error(
        fingerprint -> fingerprint["artifact"]["ready"] = true,
    )
    @test occursin("must remain false", bad_artifact_flag)

    bad_workbook_flag = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["workbooks"][1]["origin_admissible"] = true,
    )
    @test occursin("must remain false", bad_workbook_flag)

    bad_target_flag = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["targets"][1][
            "historical_availability_verified",
        ] = true,
    )
    @test occursin("must remain false", bad_target_flag)

    missing_target = fingerprint_mutation_error(
        fingerprint -> pop!(fingerprint["targets"]),
    )
    @test occursin("exactly five records", missing_target)

    duplicate_target = fingerprint_mutation_error(
        fingerprint ->
        fingerprint["targets"][5] =
            deepcopy(fingerprint["targets"][4]),
    )
    @test occursin("duplicates pce_price_index", duplicate_target)

    reversed_pair = fingerprint_mutation_error(
        fingerprint -> reverse!(fingerprint["workbooks"]),
    )
    @test occursin("must be sorted by workbook_id", reversed_pair)

    bad_path = checked_receipt()
    bad_path["semantic_linkage"]["content_fingerprint_artifact_path"] =
        "../outside.json"
    restamp!(bad_path)
    @test occursin(
        "adjacent file",
        receipt_error(
            () -> validate_receipt(
                bad_path,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )
end

@testset "programmatic builder reconstructs the complete receipt" begin
    built = built_fixture_receipt()
    @test built == checked_receipt()
    @test built["artifact"]["content_sha256"] ==
        computed_content_sha256(built)
    @test validate_receipt(
        built,
        FIXTURE_DIR;
        allow_synthetic = true,
    ).receipt_id == built["artifact"]["receipt_id"]

    fractional_fetches = fixture_fetches()
    fractional_fetches[1] = modified_fetch(
        fractional_fetches[1];
        acquisition_started_at_utc =
            DateTime(2026, 8, 5, 21, 55, 30, 900),
        response_headers_at_utc =
            DateTime(2026, 8, 5, 21, 55, 31, 50),
        acquisition_completed_at_utc =
            DateTime(2026, 8, 5, 21, 55, 31, 200),
    )
    fractional_fetches[2] = modified_fetch(
        fractional_fetches[2];
        acquisition_started_at_utc =
            DateTime(2026, 8, 5, 21, 55, 31, 300),
        response_headers_at_utc =
            DateTime(2026, 8, 5, 21, 55, 31, 700),
        acquisition_completed_at_utc =
            DateTime(2026, 8, 5, 21, 55, 32, 50),
    )
    fractional = built_fixture_receipt(fetches = fractional_fetches)
    @test fractional["capture"]["pair_started_at_utc"] ==
        "2026-08-05T21:55:30Z"
    @test fractional["capture"]["pair_completed_at_utc"] ==
        "2026-08-05T21:55:32Z"
    @test fractional["capture"]["observed_pair_span_seconds"] == 2
    fractional_result = validate_receipt(
        fractional,
        FIXTURE_DIR;
        allow_synthetic = true,
    )
    @test all(
        workbook ->
        fractional_result.pair_started <= workbook.started <=
            workbook.completed <= fractional_result.pair_completed,
        fractional_result.workbooks,
    )

    raw_millisecond_floor = deepcopy(fractional)
    raw_millisecond_floor["capture"]["observed_pair_span_seconds"] = 1
    restamp!(raw_millisecond_floor)
    @test occursin(
        "timestamps imply 2",
        receipt_error(
            () -> validate_receipt(
                raw_millisecond_floor,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )
    @test occursin(
        "exceeds maximum span",
        receipt_error(
            () -> built_fixture_receipt(
                fetches = fractional_fetches,
                max_pair_span_seconds = 1,
            ),
        ),
    )

    @test occursin(
        "exactly two",
        receipt_error(
            () -> built_fixture_receipt(
                fetches = fixture_fetches()[1:1],
            ),
        ),
    )

    duplicate_section = fixture_fetches()
    duplicate_section[2] = WorkbookFetch(
        raw_bytes = duplicate_section[2].raw_bytes,
        raw_artifact_path = duplicate_section[2].raw_artifact_path,
        storage_encoding = duplicate_section[2].storage_encoding,
        release_id = duplicate_section[2].release_id,
        workbook_id = duplicate_section[2].workbook_id,
        reference_period = duplicate_section[2].reference_period,
        estimate_label = duplicate_section[2].estimate_label,
        archive_label_url_component =
            duplicate_section[2].archive_label_url_component,
        archive_directory_id =
            duplicate_section[2].archive_directory_id,
        section_id = "1",
        filename = duplicate_section[2].filename,
        file_format = duplicate_section[2].file_format,
        requested_url = duplicate_section[2].requested_url,
        effective_url = duplicate_section[2].effective_url,
        content_type = duplicate_section[2].content_type,
        acquisition_started_at_utc =
            duplicate_section[2].acquisition_started_at_utc,
        response_headers_at_utc =
            duplicate_section[2].response_headers_at_utc,
        acquisition_completed_at_utc =
            duplicate_section[2].acquisition_completed_at_utc,
    )
    @test occursin(
        "Sections 1 and 2",
        receipt_error(
            () -> built_fixture_receipt(fetches = duplicate_section),
        ),
    )

    mktempdir() do temporary
        write(joinpath(temporary, basename(PROFILE_PATH)), read(PROFILE_PATH))
        write(
            joinpath(temporary, basename(FINGERPRINT_PATH)),
            read(FINGERPRINT_PATH),
        )
        built_without_raw_files = built_fixture_receipt(base_dir = temporary)
        @test built_without_raw_files == checked_receipt()
        @test occursin(
            "file does not exist",
            receipt_error(
                () -> verify_local_raw_files(
                    built_without_raw_files,
                    temporary,
                ),
            ),
        )
    end
end

@testset "manifest hashes, schemas, and ambiguity fail closed" begin
    extra = checked_receipt()
    extra["unexpected"] = true
    restamp!(extra)
    @test occursin(
        "extra=[\"unexpected\"]",
        receipt_error(
            () -> validate_receipt(
                extra,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    stale_hash = checked_receipt()
    stale_hash["capture"]["observer_id"] = "changed-observer"
    @test occursin(
        "declares",
        receipt_error(
            () -> validate_receipt(
                stale_hash,
                FIXTURE_DIR;
                allow_synthetic = true,
            ),
        ),
    )

    @test occursin(
        "duplicates receipt_id",
        receipt_error(
            () -> validate_receipt_set(
                [RECEIPT_PATH, RECEIPT_PATH];
                allow_synthetic = true,
            ),
        ),
    )
end
