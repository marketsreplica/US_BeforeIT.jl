using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BLSEmploymentArchiveCapture.jl"))
using .BLSEmploymentArchiveCapture

const FIXTURE_BYTES = Vector{UInt8}(
    codeunits(
        "%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n" *
            "startxref\n0\n%%EOF\n",
    ),
)
const FIXTURE_SHA256 =
    "c9f7a3f2e40eddbe3b3d956b34fe32cb1e3f87927651528c13657130bd67c470"
const FIXTURE_EXPECTATION = ArchiveExpectation(
    "bls_empsit_01022030",
    "2029-12",
    "https://www.bls.gov/news.release/archives/empsit_01022030.pdf",
    FIXTURE_SHA256,
    63,
)
const FIXTURE_RECEIPT_SHA256 =
    "be698f890966be6e280ecd23a817333642fdc7c80baa22ea28f24c884e82a8c7"
const FIXTURE_RECEIPT_FILE_SHA256 =
    "3045685e41fada342d9f0ae301b67315d2d36ef127915df0175d64ee8d8daae7"
const FIXED_DATE = Date(2026, 8, 7)
const BROWSER_TIME = DateTime(2026, 8, 7, 1, 0, 0)
const IMPORT_START = DateTime(2026, 8, 7, 1, 0, 1)
const IMPORT_COMPLETE = DateTime(2026, 8, 7, 1, 0, 2)
const INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "current_inventory.toml"))

sha(bytes) = bytes2hex(SHA.sha256(bytes))

function write_fixture(directory; name = "fixture.pdf", bytes = FIXTURE_BYTES)
    path = joinpath(directory, name)
    open(path, "w") do io
        write(io, bytes)
    end
    return path
end

function import_fixture(
        input,
        raw_root;
        expectation = FIXTURE_EXPECTATION,
        live = true,
        terms_reviewed_local_date = FIXED_DATE,
        browser_download_observed_at_utc = BROWSER_TIME,
        import_local_date = FIXED_DATE,
        import_started_at_utc = IMPORT_START,
        import_completed_at_utc = IMPORT_COMPLETE,
    )
    return BLSEmploymentArchiveCapture._import_browser_download(
        input,
        raw_root;
        expectation,
        live,
        terms_reviewed_local_date,
        browser_download_observed_at_utc,
        import_local_date,
        import_started_at_utc,
        import_completed_at_utc,
    )
end

function replace_receipt(receipt; reseal = false, kwargs...)
    replacements = Dict{Symbol, Any}(kwargs)
    values = Any[
        get(
                replacements,
                name,
                name == :receipt_sha256 && reseal ?
                repeat("0", 64) :
                getfield(receipt, name),
            )
            for name in fieldnames(BLSEmploymentCaptureReceipt)
    ]
    changed = BLSEmploymentCaptureReceipt(values...)
    if reseal
        values = Any[
            name == :receipt_sha256 ?
                receipt_sha256(changed) :
                getfield(changed, name)
                for name in fieldnames(BLSEmploymentCaptureReceipt)
        ]
        changed = BLSEmploymentCaptureReceipt(values...)
    end
    return changed
end

function make_writable(path)
    isdir(path) ? chmod(path, 0o755) : chmod(path, 0o644)
    return path
end

function canonical_tempdir(callback)
    return mktempdir() do directory
        callback(realpath(directory))
    end
end

@testset "pinned live identity and synthetic PDF validation" begin
    @test JANUARY_2020_EXPECTATION.release_id ==
        "bls_empsit_01102020"
    @test JANUARY_2020_EXPECTATION.reference_period == "2019-12"
    @test JANUARY_2020_EXPECTATION.source_url ==
        "https://www.bls.gov/news.release/archives/empsit_01102020.pdf"
    @test JANUARY_2020_EXPECTATION.expected_raw_sha256 ==
        "e9005e394f25ad62315817fcada7bfff102442290a995a13417f82f027ceb066"
    @test JANUARY_2020_EXPECTATION.expected_byte_count == 356_586
    live_evidence = BLSEmploymentArchiveCapture._document_evidence(
        JANUARY_2020_EXPECTATION,
    )
    @test live_evidence.archive_document_state ==
        "REISSUED_CORRECTED_NOT_HISTORICAL_FIRST_STATE"
    @test live_evidence.pdf_declared_evidence_basis ==
        "MANUAL_PDF_INSPECTION_PINNED_BY_EXACT_RAW_SHA256"
    @test live_evidence.pdf_metadata_creation_date ==
        "D:20200106100753-05'00'"
    @test live_evidence.pdf_metadata_modification_date ==
        "D:20200220142443-05'00'"
    @test live_evidence.pdf_declared_reissue_date == "2020-02-21"
    @test live_evidence.pdf_declared_correction_scope ==
        "REISSUED_TO_CORRECT_TABLE_A-5"
    @test live_evidence.diagnostic_payroll_change_thousands == 145
    @test live_evidence.diagnostic_unemployment_rate_percent == "3.5"
    @test live_evidence.diagnostic_headline_values_status ==
        "PDF_DECLARED_DIAGNOSTIC_ONLY_NOT_SEMANTIC_IMPORT"

    @test length(FIXTURE_BYTES) == 63
    @test sha(FIXTURE_BYTES) == FIXTURE_SHA256
    validation =
        validate_browser_download(FIXTURE_BYTES, FIXTURE_EXPECTATION)
    @test validation.raw_bytes == FIXTURE_BYTES
    @test validation.raw_bytes !== FIXTURE_BYTES
    @test validation.raw_sha256 == FIXTURE_SHA256
    @test validation.raw_byte_count == 63
    @test validation.pdf_signature == "%PDF-"

    short = FIXTURE_BYTES[1:(end - 6)]
    @test_throws BLSEmploymentCaptureError validate_browser_download(
        short,
        ArchiveExpectation(
            FIXTURE_EXPECTATION.release_id,
            FIXTURE_EXPECTATION.reference_period,
            FIXTURE_EXPECTATION.source_url,
            sha(short),
            length(short),
        ),
    )

    bad_header = copy(FIXTURE_BYTES)
    bad_header[1] = UInt8('!')
    @test_throws BLSEmploymentCaptureError validate_browser_download(
        bad_header,
        ArchiveExpectation(
            FIXTURE_EXPECTATION.release_id,
            FIXTURE_EXPECTATION.reference_period,
            FIXTURE_EXPECTATION.source_url,
            sha(bad_header),
            length(bad_header),
        ),
    )

    bad_version = copy(FIXTURE_BYTES)
    bad_version[8] = UInt8('x')
    @test_throws BLSEmploymentCaptureError validate_browser_download(
        bad_version,
        ArchiveExpectation(
            FIXTURE_EXPECTATION.release_id,
            FIXTURE_EXPECTATION.reference_period,
            FIXTURE_EXPECTATION.source_url,
            sha(bad_version),
            length(bad_version),
        ),
    )

    bad_eof = copy(FIXTURE_BYTES)
    bad_eof[end - 1] = UInt8('X')
    @test_throws BLSEmploymentCaptureError validate_browser_download(
        bad_eof,
        ArchiveExpectation(
            FIXTURE_EXPECTATION.release_id,
            FIXTURE_EXPECTATION.reference_period,
            FIXTURE_EXPECTATION.source_url,
            sha(bad_eof),
            length(bad_eof),
        ),
    )

    wrong_hash = copy(FIXTURE_BYTES)
    wrong_hash[20] = xor(wrong_hash[20], 0x01)
    @test_throws BLSEmploymentCaptureError validate_browser_download(
        wrong_hash,
        FIXTURE_EXPECTATION,
    )
    @test_throws BLSEmploymentCaptureError validate_browser_download(
        FIXTURE_BYTES[1:(end - 1)],
        FIXTURE_EXPECTATION,
    )

    for bad_expectation in (
            ArchiveExpectation(
                "wrong",
                FIXTURE_EXPECTATION.reference_period,
                FIXTURE_EXPECTATION.source_url,
                FIXTURE_SHA256,
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                "2029Q4",
                FIXTURE_EXPECTATION.source_url,
                FIXTURE_SHA256,
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                "http://www.bls.gov/news.release/archives/empsit_01022030.pdf",
                FIXTURE_SHA256,
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                FIXTURE_EXPECTATION.source_url * "?download=1",
                FIXTURE_SHA256,
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                "https://evil.example/news.release/archives/empsit_01022030.pdf",
                FIXTURE_SHA256,
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                "https://www.bls.gov/news.release/archives/../empsit_01022030.pdf",
                FIXTURE_SHA256,
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                FIXTURE_EXPECTATION.source_url,
                uppercase(FIXTURE_SHA256),
                63,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                FIXTURE_EXPECTATION.source_url,
                FIXTURE_SHA256,
                0,
            ),
            ArchiveExpectation(
                FIXTURE_EXPECTATION.release_id,
                FIXTURE_EXPECTATION.reference_period,
                FIXTURE_EXPECTATION.source_url,
                FIXTURE_SHA256,
                5_000_001,
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_browser_download(
            FIXTURE_BYTES,
            bad_expectation,
        )
    end
end

@testset "deterministic content-addressed import and receipt" begin
    inventory_before = read(INVENTORY_PATH)
    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)

        @test result.raw_sha256 == FIXTURE_SHA256
        @test result.raw_byte_count == 63
        @test result.receipt_sha256 == FIXTURE_RECEIPT_SHA256
        @test result.receipt_file_sha256 ==
            FIXTURE_RECEIPT_FILE_SHA256
        @test isfile(result.raw_object_path)
        @test !islink(result.raw_object_path)
        @test stat(result.raw_object_path).mode & 0o222 == 0
        @test stat(dirname(result.raw_object_path)).mode & 0o222 == 0
        @test read(result.raw_object_path) == FIXTURE_BYTES
        @test basename(result.raw_object_path) ==
            "raw-sha256-$FIXTURE_SHA256.pdf"
        @test basename(dirname(result.raw_object_path)) ==
            "sha256-$FIXTURE_SHA256"
        @test isfile(result.receipt_path)
        @test !islink(result.receipt_path)
        @test stat(result.receipt_path).mode & 0o222 == 0
        @test stat(dirname(result.receipt_path)).mode & 0o222 == 0
        @test basename(result.receipt_path) ==
            "receipt-self-sha256-$FIXTURE_RECEIPT_SHA256.toml"
        @test basename(dirname(result.receipt_path)) ==
            "sha256-$FIXTURE_RECEIPT_SHA256"
        @test sha(read(result.receipt_path)) ==
            FIXTURE_RECEIPT_FILE_SHA256

        receipt = result.receipt
        @test isimmutable(receipt)
        @test receipt_sha256(receipt) == FIXTURE_RECEIPT_SHA256
        @test receipt_file_sha256(receipt) ==
            FIXTURE_RECEIPT_FILE_SHA256
        @test receipt.source_agency ==
            "U.S. Bureau of Labor Statistics"
        @test receipt.publication_name == "Employment Situation"
        @test receipt.source_attribution ==
            "Source: U.S. Bureau of Labor Statistics"
        @test receipt.copyright_terms_locator ==
            "https://www.bls.gov/opub/copyright-information.htm"
        @test receipt.api_terms_locator ==
            "https://www.bls.gov/developers/termsOfService.htm"
        @test receipt.terms_reviewed_local_date == "2026-08-07"
        @test receipt.api_terms_applicability ==
            "NOT_APPLICABLE_DIRECT_ARCHIVE_PDF_BROWSER_DOWNLOAD_NO_API"
        @test receipt.file_specific_image_review_required
        @test receipt.file_specific_image_review_status ==
            "NOT_COMPLETED_CAPTURE_ONLY_REVIEW_REQUIRED_BEFORE_REDISTRIBUTION"
        @test receipt.archive_document_state ==
            "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
        @test receipt.pdf_declared_evidence_basis ==
            "NOT_APPLICABLE_SYNTHETIC_FIXTURE"
        @test receipt.diagnostic_payroll_change_thousands == 0
        @test receipt.diagnostic_unemployment_rate_percent ==
            "NOT_APPLICABLE_SYNTHETIC_FIXTURE"
        @test receipt.diagnostic_headline_values_status ==
            "SYNTHETIC_FIXTURE_NO_SOURCE_SEMANTICS"
        @test !receipt.bls_emblem_reuse_authorized
        @test !receipt.redistribution_authorized
        @test receipt.browser_download_observed_at_utc ==
            "2026-08-07T01:00:00Z"
        @test receipt.import_started_at_utc ==
            "2026-08-07T01:00:01Z"
        @test receipt.import_completed_at_utc ==
            "2026-08-07T01:00:02Z"
        @test receipt.release_stated_embargo_time ==
            "NOT_EXTRACTED_NOT_VERIFIED"
        @test receipt.release_stated_public_time ==
            "NOT_EXTRACTED_NOT_VERIFIED"
        @test receipt.release_event_timestamp_utc ==
            "UNKNOWN_NOT_INFERRED"
        @test !receipt.release_time_inferred_from_browser_capture
        @test !receipt.browser_retrieval_is_release_event_evidence

        for field in (
                :historical_first_state_verified,
                :historical_availability_verified,
                :origin_admissible,
                :empirical_execution_allowed,
                :inventory_mutation_authorized,
                :ready,
            )
            @test !getfield(receipt, field)
            @test !getfield(result, field)
        end

        validated = validate_receipt_file(result.receipt_path, raw_root)
        @test validated.receipt_sha256 == result.receipt_sha256
        @test validated.raw_object_path == result.raw_object_path

        repeated = import_fixture(input, raw_root)
        @test repeated.receipt_path == result.receipt_path
        @test repeated.raw_object_path == result.raw_object_path
        @test repeated.receipt_file_sha256 ==
            result.receipt_file_sha256
    end
    @test read(INVENTORY_PATH) == inventory_before
end

@testset "opt-in, clock, and local-path refusal" begin
    inventory_before = read(INVENTORY_PATH)
    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "public-raw")
        public_arguments = (
            live = true,
            terms_reviewed_local_date = Dates.today(),
            browser_download_observed_at_utc = now(UTC) - Second(1),
        )
        @test_throws MethodError import_browser_download(
            input,
            raw_root;
            public_arguments...,
            expectation = FIXTURE_EXPECTATION,
        )
        @test_throws MethodError import_browser_download(
            input,
            raw_root;
            public_arguments...,
            import_local_date = Date(1900, 1, 1),
        )
        @test_throws MethodError import_browser_download(
            input,
            raw_root;
            public_arguments...,
            import_started_at_utc = DateTime(2100, 1, 1),
        )
        @test_throws BLSEmploymentCaptureError import_browser_download(
            input,
            raw_root;
            live = true,
            terms_reviewed_local_date = Date(1900, 1, 1),
            browser_download_observed_at_utc =
                DateTime(1900, 1, 1),
        )
        @test !ispath(raw_root)
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root;
            live = false,
        )
        @test !ispath(raw_root)
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root;
            terms_reviewed_local_date = Date(2026, 8, 6),
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root;
            browser_download_observed_at_utc =
                DateTime(2026, 8, 7, 1, 0, 2),
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root;
            import_completed_at_utc =
                DateTime(2026, 8, 7, 1, 0, 0),
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root;
            browser_download_observed_at_utc = "2026-08-07 01:00:00",
        )

        missing = joinpath(directory, "missing.pdf")
        @test_throws BLSEmploymentCaptureError import_fixture(
            missing,
            raw_root,
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            directory,
            raw_root,
        )
        input_link = joinpath(directory, "input-link.pdf")
        symlink(input, input_link)
        @test_throws BLSEmploymentCaptureError import_fixture(
            input_link,
            raw_root,
        )

        raw_file = joinpath(directory, "raw-file")
        write_fixture(directory; name = "raw-file")
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_file,
        )
        @test_throws BLSEmploymentCaptureError import_fixture(input, "/")
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "must-not-be-created")
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root;
            import_completed_at_utc =
                DateTime(2026, 8, 7, 1, 0, 0),
        )
        @test !ispath(raw_root)
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        target = joinpath(directory, "target")
        mkdir(target)
        raw_link = joinpath(directory, "raw")
        symlink(target, raw_link)
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_link,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        mkdir(raw_root)
        link_target = joinpath(directory, "external-bls")
        mkdir(link_target)
        symlink(link_target, joinpath(raw_root, "bls"))
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
        @test isempty(readdir(link_target))
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        target_parent = joinpath(directory, "raw-target")
        mkdir(target_parent)
        linked_parent = joinpath(directory, "raw-parent-link")
        symlink(target_parent, linked_parent)
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            joinpath(linked_parent, "raw"),
        )
        @test isempty(readdir(target_parent))
    end

    canonical_tempdir() do directory
        input_target = joinpath(directory, "input-target")
        mkdir(input_target)
        write_fixture(input_target)
        input_parent_link = joinpath(directory, "input-parent-link")
        symlink(input_target, input_parent_link)
        raw_root = joinpath(directory, "raw")
        @test_throws BLSEmploymentCaptureError import_fixture(
            joinpath(input_parent_link, "fixture.pdf"),
            raw_root,
        )
        @test !ispath(raw_root)
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        mkdir(raw_root)
        symlink(
            joinpath(directory, "missing-target"),
            joinpath(raw_root, "bls"),
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        source_root = joinpath(directory, "source-raw")
        result = import_fixture(write_fixture(directory), source_root)
        missing_root = joinpath(directory, "missing-validation-root")
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            missing_root,
        )
        @test !ispath(missing_root)
    end
    @test read(INVENTORY_PATH) == inventory_before
end

@testset "object tampering, symlinks, and unexpected files" begin
    inventory_before = read(INVENTORY_PATH)
    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        make_writable(result.raw_object_path)
        tampered = copy(FIXTURE_BYTES)
        tampered[20] = xor(tampered[20], 0x01)
        open(result.raw_object_path, "w") do io
            write(io, tampered)
        end
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        make_writable(result.receipt_path)
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        make_writable(result.receipt_path)
        open(result.receipt_path, "a") do io
            write(io, "# semantically inert but noncanonical\n")
        end
        chmod(result.receipt_path, 0o444)
        @test sha(read(result.receipt_path)) !=
            receipt_file_sha256(result.receipt)
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        make_writable(dirname(result.raw_object_path))
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        object_directory = dirname(result.raw_object_path)
        make_writable(object_directory)
        open(joinpath(object_directory, "unexpected"), "w") do io
            write(io, "unexpected")
        end
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        make_writable(result.receipt_path)
        document = TOML.parsefile(result.receipt_path)
        document["gates"]["ready"] = true
        open(result.receipt_path, "w") do io
            TOML.print(io, document; sorted = true)
        end
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        receipt_link = joinpath(directory, "receipt-link.toml")
        symlink(result.receipt_path, receipt_link)
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            receipt_link,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        mkdir(raw_root)
        object_parent = joinpath(
            raw_root,
            "bls",
            "employment_situation",
            "archive",
            "objects",
        )
        mkpath(object_parent)
        external = joinpath(directory, "external-object")
        mkdir(external)
        symlink(
            external,
            joinpath(object_parent, "sha256-$FIXTURE_SHA256"),
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
        @test isempty(readdir(external))
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        mkdir(raw_root)
        object_parent = joinpath(
            raw_root,
            "bls",
            "employment_situation",
            "archive",
            "objects",
        )
        mkpath(object_parent)
        symlink(
            joinpath(directory, "missing-object-target"),
            joinpath(object_parent, "sha256-$FIXTURE_SHA256"),
        )
        @test_throws BLSEmploymentCaptureError import_fixture(
            input,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        object_directory = dirname(result.raw_object_path)
        make_writable(object_directory)
        make_writable(result.raw_object_path)
        rm(result.raw_object_path)
        external = write_fixture(directory; name = "external.pdf")
        symlink(external, result.raw_object_path)
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        receipt_directory = dirname(result.receipt_path)
        make_writable(receipt_directory)
        open(joinpath(receipt_directory, "unexpected"), "w") do io
            write(io, "unexpected")
        end
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            raw_root,
        )
    end

    canonical_tempdir() do directory
        input = write_fixture(directory)
        raw_root = joinpath(directory, "raw")
        result = import_fixture(input, raw_root)
        copied_bundle = joinpath(
            directory,
            "copied",
            "sha256-$(result.receipt_sha256)",
        )
        mkpath(copied_bundle)
        copied_receipt = joinpath(
            copied_bundle,
            basename(result.receipt_path),
        )
        open(copied_receipt, "w") do io
            write(io, read(result.receipt_path))
        end
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            copied_receipt,
            raw_root,
        )

        wrong_root = joinpath(directory, "other-raw")
        mkdir(wrong_root)
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            wrong_root,
        )
    end
    @test read(INVENTORY_PATH) == inventory_before
end

@testset "receipt self-hash, false gates, and strict shape" begin
    canonical_tempdir() do directory
        result = import_fixture(
            write_fixture(directory),
            joinpath(directory, "raw"),
        )
        receipt = result.receipt

        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                receipt_sha256 = repeat("a", 64),
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                immutable_receipt = false,
                reseal = true,
            ),
        )
        for field in (
                :release_time_inferred_from_browser_capture,
                :browser_retrieval_is_release_event_evidence,
                :bls_emblem_reuse_authorized,
                :redistribution_authorized,
                :historical_first_state_verified,
                :historical_availability_verified,
                :origin_admissible,
                :empirical_execution_allowed,
                :inventory_mutation_authorized,
                :ready,
            )
            @test_throws BLSEmploymentCaptureError validate_receipt(
                replace_receipt(
                    receipt;
                    reseal = true,
                    Dict(field => true)...,
                ),
            )
        end
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                raw_object_relative_path = "../../escape.pdf",
                reseal = true,
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                terms_reviewed_local_date = "2026-08-06",
                reseal = true,
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                release_stated_public_time =
                    receipt.browser_download_observed_at_utc,
                reseal = true,
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                archive_document_state =
                    "REISSUED_CORRECTED_NOT_HISTORICAL_FIRST_STATE",
                reseal = true,
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                api_terms_applicability = "APPLICABLE",
                reseal = true,
            ),
        )
        @test_throws BLSEmploymentCaptureError validate_receipt(
            replace_receipt(
                receipt;
                file_specific_image_review_required = false,
                reseal = true,
            ),
        )

        make_writable(result.receipt_path)
        document = TOML.parsefile(result.receipt_path)
        document["unexpected"] = Dict("field" => true)
        open(result.receipt_path, "w") do io
            TOML.print(io, document; sorted = true)
        end
        @test_throws BLSEmploymentCaptureError validate_receipt_file(
            result.receipt_path,
            joinpath(directory, "raw"),
        )
    end
end

@testset "CLI argument contract" begin
    include(joinpath(@__DIR__, "import_local_browser_capture.jl"))
    @test_throws ErrorException parse_arguments(String[])
    @test_throws ErrorException parse_arguments(["--live"])
    @test_throws ErrorException parse_arguments(
        [
            "--input",
            "a.pdf",
            "--raw-root",
            "raw",
            "--terms-reviewed-local-date",
            "2026-08-07",
            "--browser-download-observed-at-utc",
            "2026-08-07T01:00:00Z",
        ],
    )
    @test_throws ErrorException parse_arguments(
        [
            "--input",
            "a.pdf",
            "--input",
            "b.pdf",
            "--raw-root",
            "raw",
            "--terms-reviewed-local-date",
            "2026-08-07",
            "--browser-download-observed-at-utc",
            "2026-08-07T01:00:00Z",
            "--live",
        ],
    )
    @test_throws ErrorException parse_arguments(["--unknown", "--live"])
    parsed = parse_arguments(
        [
            "--input",
            "a.pdf",
            "--raw-root",
            "raw",
            "--terms-reviewed-local-date",
            "2026-08-07",
            "--browser-download-observed-at-utc",
            "2026-08-07T01:00:00Z",
            "--live",
        ],
    )
    @test parsed.input == "a.pdf"
    @test parsed.raw_root == "raw"
    @test parsed.terms_reviewed_local_date == "2026-08-07"
    @test parsed.browser_download_observed_at_utc ==
        "2026-08-07T01:00:00Z"
    @test parsed.live
end
