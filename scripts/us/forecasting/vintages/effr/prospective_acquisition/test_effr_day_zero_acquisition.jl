using Dates
using Test
using TOML

include(joinpath(@__DIR__, "USEFFRDayZeroAcquisition.jl"))
using .USEFFRDayZeroAcquisition

const M = USEFFRDayZeroAcquisition

function rate_body(;
        revision = "",
        current_state = nothing,
        duplicate = false,
        percent_rate = "3.63",
        padding = "",
    )
    current = current_state === nothing ? "" :
        ",\"currentState\":$(current_state ? "true" : "false")"
    effr =
        """{"effectiveDate":"2026-08-06","type":"EFFR","percentRate":$percent_rate,"percentPercentile1":3.60,"percentPercentile25":3.62,"percentPercentile75":3.63,"percentPercentile99":3.65,"targetRateFrom":3.50,"targetRateTo":3.75,"revisionIndicator":"$revision"$current}"""
    duplicate_row = duplicate ? ",$effr" : ""
    return Vector{UInt8}(
        codeunits(
            """{"refRates":[{"effectiveDate":"2026-08-06","type":"OBFR","percentRate":3.63,"percentPercentile1":3.55,"percentPercentile25":3.62,"percentPercentile75":3.63,"percentPercentile99":3.68,"revisionIndicator":""},$effr$duplicate_row]}$padding""",
        ),
    )
end

function volume_body(;
        revision = "",
        current_state = nothing,
        volume = "114",
        padding = "",
    )
    current = current_state === nothing ? "" :
        ",\"currentState\":$(current_state ? "true" : "false")"
    return Vector{UInt8}(
        codeunits(
            """{"refRates":[{"effectiveDate":"2026-08-06","type":"OBFR","volumeInBillions":233,"revisionIndicator":""},{"effectiveDate":"2026-08-06","type":"EFFR","volumeInBillions":$volume,"revisionIndicator":"$revision"$current}]}$padding""",
        ),
    )
end

function fixture_fetcher(
        phase;
        rate = rate_body(),
        volume = volume_body(),
        fail_object = nothing,
    )
    base = phase == "first" ?
        DateTime(2026, 8, 7, 13, 0, 1) :
        DateTime(2026, 8, 7, 18, 30, 1)
    counter = Ref(0)
    bodies = Dict(
        "rate_response" => rate,
        "volume_response" => volume,
        "api_documentation_snapshot" => Vector{UInt8}(
            codeunits(
                "<html><script>url: './markets-api.yml'</script></html>",
            ),
        ),
        "openapi_snapshot" =>
            Vector{UInt8}(codeunits("openapi: 3.0.1\npaths: {}\n")),
        "terms_snapshot" =>
            Vector{UInt8}(codeunits("<html>Terms snapshot</html>")),
        "holiday_snapshot" =>
            Vector{UInt8}(codeunits("<html>2026 holiday schedule</html>")),
    )
    content_types = Dict(
        "rate_response" => "application/json",
        "volume_response" => "application/json; charset=utf-8",
        "api_documentation_snapshot" => "text/html; charset=UTF-8",
        "openapi_snapshot" => "application/octet-stream;charset=UTF-8",
        "terms_snapshot" => "text/html; charset=utf-8",
        "holiday_snapshot" => "text/html; charset=utf-8",
    )
    return function (spec)
        spec.object_id == fail_object &&
            error("synthetic transport failure")
        counter[] += 1
        started = base + Millisecond(100 * counter[])
        return CapturedObject(
            object_id = spec.object_id,
            body = copy(bodies[spec.object_id]),
            requested_url = spec.requested_url,
            final_url = spec.requested_url,
            http_status = 200,
            content_type = content_types[spec.object_id],
            content_encoding = "identity",
            response_headers = [
                "content-type: $(content_types[spec.object_id])",
                "date: Fri, 07 Aug 2026 13:00:01 GMT",
            ],
            request_started_at_utc = started,
            response_metadata_observed_at_utc =
                started + Millisecond(10),
            response_body_completed_at_utc =
                started + Millisecond(20),
        )
    end
end

@testset "network-free dry run and fixed clock guard" begin
    mktempdir(@__DIR__) do root
        plan = dry_run_plan(
            "first";
            transaction_id = "dry-run",
            output_root = root,
        )
        @test plan.mode == "DRY_RUN_NO_NETWORK_NO_FILESYSTEM_WRITES"
        @test plan.effective_date == "2026-08-06"
        @test plan.capture_not_before_utc == "2026-08-07T13:00:00.000Z"
        @test length(plan.ordered_requests) == 6
        @test !ispath(plan.output_bundle)
        @test all(value === false for value in values(plan.gates))

        calls = Ref(0)
        fetch = _ -> begin
            calls[] += 1
            error("must not be called")
        end
        @test_throws DayZeroAcquisitionError acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "too-early",
            clock = () -> DateTime(2026, 8, 7, 12, 59, 59),
            fetch,
        )
        @test calls[] == 0
        @test isempty(readdir(root))
    end
    @test_throws DayZeroAcquisitionError dry_run_plan(
        "revision-check";
        transaction_id = "missing-predecessor",
        output_root = "/tmp/unused-effr-day-zero-test",
    )
end

@testset "output preflight rejects symlink roots and date escapes before fetch" begin
    mktempdir(@__DIR__) do sandbox
        target = joinpath(sandbox, "target")
        mkdir(target)
        linked_root = joinpath(sandbox, "linked-output")
        symlink(target, linked_root)
        calls = Ref(0)
        fetch = _ -> begin
            calls[] += 1
            error("must not fetch")
        end
        @test_throws DayZeroAcquisitionError acquire_day_zero(
            linked_root;
            phase = "first",
            transaction_id = "root-symlink",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch,
        )
        @test calls[] == 0
        @test isempty(readdir(target))
    end

    mktempdir(@__DIR__) do sandbox
        root = joinpath(sandbox, "output")
        outside = joinpath(sandbox, "outside")
        mkdir(root)
        mkdir(outside)
        symlink(outside, joinpath(root, "2026-08-07"))
        calls = Ref(0)
        fetch = _ -> begin
            calls[] += 1
            error("must not fetch")
        end
        @test_throws DayZeroAcquisitionError acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "date-symlink",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch,
        )
        @test calls[] == 0
        @test isempty(readdir(outside))
    end
end

@testset "each complete body is dual-journaled before the next request" begin
    mktempdir(@__DIR__) do root
        transaction = "immediate-body-journal"
        rate = rate_body(; duplicate = true)
        digest = bytes2hex(M.SHA.sha256(rate))
        journal = joinpath(
            root,
            "2026-08-07",
            "FIRST_0900_STATE",
            ".journal-$transaction",
        )
        base_fetch = fixture_fetcher("first"; rate)
        fetch = function (spec)
            if spec.object_id == "rate_response"
                @test isfile(joinpath(journal, "journal-preflight.toml"))
                @test (stat(journal).mode & 0o077) == 0
            elseif spec.object_id == "volume_response"
                filename = "raw-sha256-$digest.json"
                @test read(joinpath(journal, "replica-a", filename)) == rate
                @test read(joinpath(journal, "replica-b", filename)) == rate
                @test isfile(
                    joinpath(
                        journal,
                        "attempts",
                        "0001-rate_response-completed.toml",
                    ),
                )
            end
            return base_fetch(spec)
        end
        result = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = transaction,
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch,
        )
        @test !result.success
        manifest = TOML.parsefile(result.manifest_path)
        capture = manifest["capture"]
        @test capture["attempted_request_count"] == 6
        @test capture["completed_response_count"] == 6
        @test capture["validated_response_count"] == 6
        @test capture["failed_attempt_count"] == 1
        @test capture["failed_object_id"] == "rate_response"
        @test capture["failed_attempt_index"] == 1
        @test load_and_validate_bundle(result.bundle_path).pair === nothing
    end
end

@testset "recoverable journal is retained and never overwritten" begin
    mktempdir(@__DIR__) do root
        transaction = "publish-collision"
        state_root = joinpath(
            root,
            "2026-08-07",
            "FIRST_0900_STATE",
        )
        final_path = joinpath(state_root, transaction)
        journal = joinpath(state_root, ".journal-$transaction")
        base_fetch = fixture_fetcher("first")
        fetch = function (spec)
            object = base_fetch(spec)
            if spec.object_id == "holiday_snapshot"
                mkdir(final_path)
                open(joinpath(final_path, "adversary-marker"), "w") do io
                    write(io, "do-not-overwrite")
                end
            end
            return object
        end
        @test_throws DayZeroAcquisitionError acquire_day_zero(
            root;
            phase = "first",
            transaction_id = transaction,
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch,
        )
        @test read(joinpath(final_path, "adversary-marker"), String) ==
            "do-not-overwrite"
        @test isdir(journal)
        @test isfile(joinpath(journal, "journal-preflight.toml"))
        @test length(
            filter(
                name -> startswith(name, "raw-sha256-"),
                readdir(joinpath(journal, "replica-a")),
            ),
        ) == 6
        @test length(
            filter(
                name -> startswith(name, "raw-sha256-"),
                readdir(joinpath(journal, "replica-b")),
            ),
        ) == 6
    end

    mktempdir(@__DIR__) do root
        state_root = joinpath(
            root,
            "2026-08-07",
            "FIRST_0900_STATE",
        )
        mkpath(state_root)
        journal = joinpath(state_root, ".journal-existing")
        mkdir(journal)
        marker = joinpath(journal, "recovery-marker")
        write(marker, "preserve")
        calls = Ref(0)
        fetch = _ -> begin
            calls[] += 1
            error("must not fetch")
        end
        @test_throws DayZeroAcquisitionError acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "existing",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch,
        )
        @test calls[] == 0
        @test read(marker, String) == "preserve"
    end
end

@testset "live-shaped first state preserves bytes and blocks incompatible receipt" begin
    mktempdir(@__DIR__) do root
        result = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-valid",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher("first"),
        )
        @test result.success
        @test result.raw_capture_installed
        @test result.raw_capture_complete
        @test !result.one_date_receipt_validated
        @test result.failure_code ==
            "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"
        @test result.status ==
            "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
        validation = load_and_validate_bundle(result.bundle_path)
        @test validation.pair === nothing
        manifest = validation.manifest
        @test manifest["row_identity"][1]["raw_identity_value"] == "EFFR"
        @test manifest["row_identity"][1]["json_pointer"] == "/refRates/1"
        @test !manifest["row_identity"][1]["raw_current_state_present"]
        @test manifest["row_identity"][1]["raw_current_state_value"] == "ABSENT"
        @test manifest["row_identity"][1]["alias_or_first_row_fallback_used"] ===
            false
        @test manifest["governance"]["terms_snapshot_sha256"] ==
            bytes2hex(M.SHA.sha256(codeunits("<html>Terms snapshot</html>")))
        @test all(value === false for value in values(manifest["gates"]))
        @test manifest["storage"]["durable_external_copy_count"] == 0
        @test !manifest["storage"]["external_timestamp_verified"]
        @test manifest["result"]["rate_receipt_file"] == "NONE"
        rate_record = M._find_object_record(manifest, "rate_response")
        @test read(joinpath(result.bundle_path, rate_record["primary_path"])) ==
            rate_body()
        @test read(joinpath(result.bundle_path, rate_record["replica_path"])) ==
            rate_body()
        @test_throws DayZeroAcquisitionError acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-valid",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher("first"),
        )
    end
end

@testset "synthetic raw currentState=false exercises one-date validator" begin
    mktempdir(@__DIR__) do root
        result = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-explicit-raw-current-state",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher(
                "first";
                rate = rate_body(; current_state = false),
                volume = volume_body(; current_state = false),
            ),
        )
        @test result.success
        @test result.one_date_receipt_validated
        @test result.failure_code == "NONE"
        @test result.status ==
            "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
        validation = load_and_validate_bundle(result.bundle_path)
        @test validation.pair.joined_record.effective_date == "2026-08-06"
        @test validation.pair.joined_record.percent_rate == 3.63
        @test validation.pair.joined_record.volume_in_billions == 114.0
        @test validation.manifest["row_identity"][1][
            "raw_current_state_present"
        ]
        @test all(
            value === false for
                value in values(validation.manifest["gates"])
        )
    end
end

@testset "schema failures retain bytes but create no receipt claim" begin
    cases = (
        (
            id = "duplicate-effr",
            rate = rate_body(; duplicate = true),
            expected = "EFFR_ROW_CARDINALITY_FAILURE",
        ),
        (
            id = "current-state",
            rate = rate_body(; current_state = true),
            expected = "CURRENT_STATE_SCHEMA_CONFLICT",
        ),
        (
            id = "unknown-revision",
            rate = rate_body(; revision = "Y"),
            expected = "REVISION_TOKEN_SCHEMA_CONFLICT",
        ),
    )
    for case in cases
        mktempdir(@__DIR__) do root
            result = acquire_day_zero(
                root;
                phase = "first",
                transaction_id = case.id,
                clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
                fetch = fixture_fetcher("first"; rate = case.rate),
            )
            @test !result.success
            @test result.failure_code == case.expected
            @test result.status ==
                "FAIL_CLOSED_RAW_BYTES_RETAINED_NO_RECEIPT_CLAIM"
            manifest = TOML.parsefile(result.manifest_path)
            @test manifest["result"]["rate_receipt_file"] == "NONE"
            @test all(value === false for value in values(manifest["gates"]))
            record = M._find_object_record(manifest, "rate_response")
            @test read(joinpath(result.bundle_path, record["primary_path"])) ==
                case.rate
            validated = load_and_validate_bundle(result.bundle_path)
            @test validated.pair === nothing
        end
    end
end

@testset "partial network failure journal is immutable and nonadmitting" begin
    mktempdir(@__DIR__) do root
        result = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "network-failure",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher("first"; fail_object = "openapi_snapshot"),
        )
        @test !result.success
        @test result.failure_code == "NETWORK_REQUEST_FAILURE"
        manifest = TOML.parsefile(result.manifest_path)
        @test manifest["capture"]["object_count"] == 3
        @test manifest["capture"]["attempted_request_count"] == 4
        @test manifest["capture"]["network_request_count"] == 4
        @test manifest["capture"]["completed_response_count"] == 3
        @test manifest["capture"]["failed_attempt_count"] == 1
        @test manifest["capture"]["failed_object_id"] ==
            "openapi_snapshot"
        @test manifest["capture"]["failed_attempt_index"] == 4
        @test manifest["result"]["rate_receipt_file"] == "NONE"
        @test length(manifest["objects"]) == 3
        @test load_and_validate_bundle(result.bundle_path).pair === nothing
    end
end

@testset "completed invalid HTTP response body is preserved before rejection" begin
    mktempdir(@__DIR__) do root
        base_fetch = fixture_fetcher("first")
        expected_body = Ref(UInt8[])
        fetch = function (spec)
            object = base_fetch(spec)
            spec.object_id == "openapi_snapshot" || return object
            expected_body[] = copy(object.body)
            return CapturedObject(
                object_id = object.object_id,
                body = copy(object.body),
                requested_url = object.requested_url,
                final_url = object.final_url,
                http_status = 404,
                content_type = object.content_type,
                content_encoding = object.content_encoding,
                response_headers = object.response_headers,
                request_started_at_utc = object.request_started_at_utc,
                response_metadata_observed_at_utc =
                    object.response_metadata_observed_at_utc,
                response_body_completed_at_utc =
                    object.response_body_completed_at_utc,
            )
        end
        result = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "completed-http-404",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch,
        )
        @test !result.success
        @test result.raw_capture_installed
        @test !result.raw_capture_complete
        manifest = TOML.parsefile(result.manifest_path)
        @test manifest["capture"]["object_count"] == 4
        @test manifest["capture"]["attempted_request_count"] == 4
        @test manifest["capture"]["completed_response_count"] == 4
        @test manifest["capture"]["validated_response_count"] == 3
        @test manifest["capture"]["failed_attempt_count"] == 1
        @test manifest["capture"]["failed_object_id"] ==
            "openapi_snapshot"
        record = M._find_object_record(manifest, "openapi_snapshot")
        @test record["http_status"] == 404
        @test read(joinpath(result.bundle_path, record["primary_path"])) ==
            expected_body[]
        @test read(joinpath(result.bundle_path, record["replica_path"])) ==
            expected_body[]
    end
end

@testset "unchanged revision check creates no revision receipt" begin
    mktempdir(@__DIR__) do root
        first = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-for-unchanged",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher("first"),
        )
        revision = acquire_day_zero(
            root;
            phase = "revision-check",
            transaction_id = "unchanged-check",
            predecessor_bundle = first.bundle_path,
            clock = () -> DateTime(2026, 8, 7, 18, 30, 0),
            fetch = fixture_fetcher("revision-check"),
        )
        @test revision.success
        @test revision.failure_code == "NONE"
        @test revision.status ==
            "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
        manifest = TOML.parsefile(revision.manifest_path)
        @test manifest["result"]["byte_equality_rate"]
        @test manifest["result"]["byte_equality_volume"]
        @test !manifest["result"]["revision_receipt_created"]
        @test !manifest["result"]["revision_observed"]
        @test manifest["result"]["rate_receipt_file"] == "NONE"
        @test manifest["result"]["predecessor_rate_receipt_sha256"] ==
            TOML.parsefile(first.manifest_path)["result"]["rate_receipt_sha256"]
        validated = load_and_validate_bundle(revision.bundle_path)
        @test validated.pair === nothing
    end
end

@testset "raw revised response without currentState is captured but not receipted" begin
    mktempdir(@__DIR__) do root
        first = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-for-raw-revision",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher("first"),
        )
        revision = acquire_day_zero(
            root;
            phase = "revision-check",
            transaction_id = "raw-revision-without-current-state",
            predecessor_bundle = first.bundle_path,
            clock = () -> DateTime(2026, 8, 7, 18, 30, 0),
            fetch = fixture_fetcher(
                "revision-check";
                rate = rate_body(; revision = "r"),
                volume = volume_body(; revision = "r", volume = "115"),
            ),
        )
        @test revision.success
        @test revision.raw_capture_complete
        @test !revision.one_date_receipt_validated
        @test revision.failure_code ==
            "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"
        @test revision.status ==
            "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
        manifest = TOML.parsefile(revision.manifest_path)
        @test manifest["result"]["revision_observed"]
        @test !manifest["result"]["revision_receipt_created"]
        @test manifest["result"]["rate_receipt_file"] == "NONE"
        @test manifest["result"]["volume_receipt_file"] == "NONE"
        @test !manifest["result"]["byte_equality_volume"]
        validation = load_and_validate_bundle(revision.bundle_path)
        @test validation.pair === nothing
        @test all(value === false for value in values(manifest["gates"]))
    end
end

@testset "changed bytes without r fail; closed r creates linked receipts" begin
    mktempdir(@__DIR__) do root
        first = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-for-changes",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher(
                "first";
                rate = rate_body(; current_state = false),
                volume = volume_body(; current_state = false),
            ),
        )
        ambiguous = acquire_day_zero(
            root;
            phase = "revision-check",
            transaction_id = "changed-without-token",
            predecessor_bundle = first.bundle_path,
            clock = () -> DateTime(2026, 8, 7, 18, 30, 0),
            fetch = fixture_fetcher(
                "revision-check";
                rate = rate_body(; padding = " "),
            ),
        )
        @test !ambiguous.success
        @test ambiguous.status ==
            "FAIL_CLOSED_RAW_BYTES_RETAINED_NO_RECEIPT_CLAIM"
        @test TOML.parsefile(ambiguous.manifest_path)["result"][
            "revision_receipt_created"
        ] === false

        revised = acquire_day_zero(
            root;
            phase = "revision-check",
            transaction_id = "closed-revision",
            predecessor_bundle = first.bundle_path,
            clock = () -> DateTime(2026, 8, 7, 18, 30, 0),
            fetch = fixture_fetcher(
                "revision-check";
                rate = rate_body(
                    ;
                    revision = "r",
                    percent_rate = "3.63",
                    current_state = false,
                ),
                volume = volume_body(
                    ;
                    revision = "r",
                    volume = "115",
                    current_state = false,
                ),
            ),
        )
        @test revised.success
        @test revised.status ==
            "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
        validation = load_and_validate_bundle(revised.bundle_path)
        @test validation.pair.joined_record.revision_token == "r"
        @test validation.pair.joined_record.percent_rate == 3.63
        @test validation.pair.joined_record.volume_in_billions == 115.0
        @test validation.validated_rate.lineage.predecessor_receipt_sha256 ==
            TOML.parsefile(first.manifest_path)["result"]["rate_receipt_sha256"]
        @test all(value === false for value in values(validation.manifest["gates"]))
    end
end

@testset "tampered predecessor raw bytes are rejected before revision claim" begin
    mktempdir(@__DIR__) do root
        first = acquire_day_zero(
            root;
            phase = "first",
            transaction_id = "first-for-tamper",
            clock = () -> DateTime(2026, 8, 7, 13, 0, 0),
            fetch = fixture_fetcher("first"),
        )
        manifest = TOML.parsefile(first.manifest_path)
        record = M._find_object_record(manifest, "rate_response")
        open(joinpath(first.bundle_path, record["primary_path"]), "a") do io
            write(io, UInt8('x'))
        end
        revision = acquire_day_zero(
            root;
            phase = "revision-check",
            transaction_id = "tampered-predecessor-check",
            predecessor_bundle = first.bundle_path,
            clock = () -> DateTime(2026, 8, 7, 18, 30, 0),
            fetch = fixture_fetcher("revision-check"),
        )
        @test !revision.success
        @test occursin("local replicas differ", revision.failure_detail)
        @test TOML.parsefile(revision.manifest_path)["result"][
            "revision_receipt_created"
        ] === false
    end
end
