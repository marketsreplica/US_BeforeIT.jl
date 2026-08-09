using Dates
using JSON
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USEFFRRecurringAcquisition.jl"))
using .USEFFRRecurringAcquisition

const CampaignControl =
    USEFFRRecurringAcquisition.USEFFRCampaignControl

digest(value) = bytes2hex(sha256(String(value)))

function effr_body(
        effective_date,
        report_type;
        revision = "",
        current_state = :absent,
        rate = 3.61,
        volume = 112.0,
        duplicate = false,
        effective_override = nothing,
        extra_field = false,
    )
    row = Dict{String, Any}(
        "effectiveDate" => something(
            effective_override,
            string(effective_date),
        ),
        "type" => "EFFR",
        "revisionIndicator" => revision,
    )
    if report_type == "rate"
        merge!(
            row,
            Dict{String, Any}(
                "percentRate" => rate,
                "percentPercentile1" => rate - 0.03,
                "percentPercentile25" => rate - 0.01,
                "percentPercentile75" => rate + 0.01,
                "percentPercentile99" => rate + 0.03,
                "targetRateFrom" => 3.5,
                "targetRateTo" => 3.75,
            ),
        )
    else
        row["volumeInBillions"] = volume
    end
    if current_state === false
        row["currentState"] = false
    elseif current_state === true
        row["currentState"] = true
    elseif current_state != :absent
        row["currentState"] = current_state
    end
    extra_field && (row["invented"] = "not allowed")
    rows = Any[row]
    duplicate && push!(rows, deepcopy(row))
    return Vector{UInt8}(codeunits(JSON.json(Dict("refRates" => rows))))
end

function fixture_responses(
        publication_date,
        phase;
        revision = "",
        current_state = :absent,
        rate = 3.61,
        volume = 112.0,
        rate_body = nothing,
        volume_body = nothing,
        status_overrides = Dict{String, Int}(),
        final_url_overrides = Dict{String, String}(),
        content_type_overrides = Dict{String, String}(),
        content_encoding_overrides = Dict{String, String}(),
        redirect_count_overrides = Dict{String, Int}(),
        proxy_used_overrides = Dict{String, Bool}(),
    )
    plan = dry_run_plan(
        publication_date,
        phase;
        output_root = "/fixture/not-written",
    )
    effective = plan.authorization.effective_date
    bodies = Dict{String, Vector{UInt8}}(
        "rate_response" => something(
            rate_body,
            effr_body(
                effective,
                "rate";
                revision,
                current_state,
                rate,
            ),
        ),
        "volume_response" => something(
            volume_body,
            effr_body(
                effective,
                "volume";
                revision,
                current_state,
                volume,
            ),
        ),
        "api_documentation_snapshot" =>
            Vector{UInt8}(codeunits("<html>markets-api.yml</html>")),
        "openapi_snapshot" =>
            Vector{UInt8}(codeunits("openapi: 3.0.0\ninfo:\n  title: test\n")),
        "terms_snapshot" =>
            Vector{UInt8}(codeunits("<html>terms fixture</html>")),
        "holiday_snapshot" =>
            Vector{UInt8}(codeunits("<html>holiday fixture</html>")),
    )
    content_types = Dict(
        "rate_response" => "application/json;charset=utf-8",
        "volume_response" => "application/json;charset=utf-8",
        "api_documentation_snapshot" => "text/html;charset=utf-8",
        "openapi_snapshot" => "application/octet-stream",
        "terms_snapshot" => "text/html",
        "holiday_snapshot" => "text/html",
    )
    responses = Dict{String, NamedTuple}()
    for request in plan.requests
        object_id = request.object_id
        responses[object_id] = (
            body = bodies[object_id],
            status = get(status_overrides, object_id, 200),
            final_url = get(
                final_url_overrides,
                object_id,
                request.requested_url,
            ),
            headers = [
                "content-type" => get(
                    content_type_overrides,
                    object_id,
                    content_types[object_id],
                ),
                "content-encoding" => get(
                    content_encoding_overrides,
                    object_id,
                    "identity",
                ),
            ],
            content_type = get(
                content_type_overrides,
                object_id,
                content_types[object_id],
            ),
            content_encoding = get(
                content_encoding_overrides,
                object_id,
                "identity",
            ),
            redirect_count = get(redirect_count_overrides, object_id, 0),
            proxy_used = get(proxy_used_overrides, object_id, false),
        )
    end
    return responses
end

function fixture_downloader(
        responses;
        calls = String[],
        fail_at = nothing,
    )
    return function (spec)
        push!(calls, spec.object_id)
        if fail_at !== nothing && length(calls) == fail_at
            error("injected downloader failure")
        end
        return deepcopy(responses[spec.object_id])
    end
end

function fixture_clock(publication_date, phase; outside = false)
    plan = dry_run_plan(
        publication_date,
        phase;
        output_root = "/fixture/not-written",
    )
    start = plan.authorization.window_start_utc
    values = DateTime[]
    if outside
        push!(values, start - Second(1))
    else
        push!(values, start + Millisecond(100))
    end
    for index in 1:6
        push!(values, start + Second(index))
        push!(values, start + Second(index) + Millisecond(250))
    end
    cursor = Ref(0)
    return function ()
        cursor[] += 1
        cursor[] <= length(values) ||
            error("fixture clock exhausted")
        return values[cursor[]]
    end
end

function capture_fixture(
        output_root,
        publication_date,
        phase;
        responses = fixture_responses(publication_date, phase),
        clock = fixture_clock(publication_date, phase),
        calls = String[],
    )
    return acquire_recurring(
        publication_date,
        phase;
        output_root,
        execute_live = true,
        synthetic_test_fixture = true,
        downloader = fixture_downloader(responses; calls),
        clock,
    )
end

load_fixture_bundle(path) = load_and_validate_bundle(
    path;
    allow_synthetic_test_fixture = true,
)

function first_bundle_path(output_root, publication_date)
    plan = dry_run_plan(
        publication_date,
        "first";
        output_root,
    )
    return plan.final_path
end

function failure_text(action)
    try
        action()
    catch error
        return sprint(showerror, error)
    end
    return "NO_ERROR"
end

function constant_clock(value)
    return () -> value
end

function journal_path(output_root, publication_date, phase)
    return dry_run_plan(
        publication_date,
        phase;
        output_root,
    ).journal_path
end

function manifest_triplicate_paths(bundle)
    return [
        joinpath(bundle, "capture-manifest.toml"),
        joinpath(bundle, "replica-a", "capture-manifest.toml"),
        joinpath(bundle, "replica-b", "capture-manifest.toml"),
    ]
end

function replace_manifest_triplicates!(bundle, manifest)
    bytes = USEFFRRecurringAcquisition._toml_bytes(manifest)
    for path in manifest_triplicate_paths(bundle)
        open(path, "w") do io
            write(io, bytes)
        end
    end
    return nothing
end

function replace_storage_triplicates!(bundle, relative_path, storage)
    bytes = USEFFRRecurringAcquisition._toml_bytes(storage)
    for path in (
            joinpath(bundle, relative_path),
            joinpath(bundle, "replica-a", relative_path),
            joinpath(bundle, "replica-b", relative_path),
        )
        open(path, "w") do io
            write(io, bytes)
        end
    end
    return nothing
end

function write_receipt_triplicates!(bundle, report_type, receipt)
    digest = receipt["receipt_sha256"]
    name = "$report_type-receipt-sha256-$digest.toml"
    bytes = USEFFRRecurringAcquisition._toml_bytes(receipt)
    for directory in (
            joinpath(bundle, "receipts"),
            joinpath(bundle, "replica-a", "receipts"),
            joinpath(bundle, "replica-b", "receipts"),
        )
        open(joinpath(directory, name), "w") do io
            write(io, bytes)
        end
    end
    return name
end

function rewrite_receipt_and_manifest!(
        bundle,
        report_type,
        mutate!;
        require_contract_valid = true,
    )
    manifest = deepcopy(bundle.manifest)
    result = manifest["result"]
    old_name = result["$(report_type)_receipt_file"]
    receipt = TOML.parsefile(
        joinpath(bundle.bundle_path, "receipts", old_name),
    )
    mutate!(receipt)
    receipt["receipt_sha256"] =
        USEFFRRecurringAcquisition.ReceiptContract.canonical_receipt_sha256(
        receipt,
    )
    if require_contract_valid
        USEFFRRecurringAcquisition.ReceiptContract.validate_receipt(
            receipt,
            receipt["receipt_sha256"],
        )
    end
    new_name = write_receipt_triplicates!(
        bundle.bundle_path,
        report_type,
        receipt,
    )
    result["$(report_type)_receipt_file"] = new_name
    result["$(report_type)_receipt_sha256"] =
        receipt["receipt_sha256"]
    manifest["artifact"]["manifest_sha256"] =
        USEFFRRecurringAcquisition._semantic_sha256(
        manifest,
        "artifact",
        "manifest_sha256",
    )
    replace_manifest_triplicates!(bundle.bundle_path, manifest)
    return (; manifest, receipt)
end

@testset "closed plan and dry-run boundary" begin
    root = joinpath(tempdir(), "effr-dry-run-never-create-" * digest("plan"))
    ispath(root) && rm(root; recursive = true)
    plan = dry_run_plan("2026-08-10", "first"; output_root = root)
    @test plan.dry_run === true
    @test plan.network_requests_made == 0
    @test plan.filesystem_writes_made == 0
    @test !ispath(root)
    @test plan.authorization.publication_date == Date(2026, 8, 10)
    @test plan.authorization.effective_date == Date(2026, 8, 7)
    @test plan.authorization.window_start_utc ==
        DateTime(2026, 8, 10, 13)
    @test plan.authorization.window_deadline_utc ==
        DateTime(2026, 8, 10, 13, 15)
    @test plan.transaction_id == "effr-20260810-first-1300z"
    @test basename(plan.final_path) == plan.transaction_id
    @test plan.predecessor_path == "NOT_APPLICABLE"
    @test length(plan.requests) == 6
    @test [request.object_id for request in plan.requests] == [
        "rate_response",
        "volume_response",
        "api_documentation_snapshot",
        "openapi_snapshot",
        "terms_snapshot",
        "holiday_snapshot",
    ]
    @test plan.requests[1].canonical_query ==
        "endDate=2026-08-07&startDate=2026-08-07&type=rate"
    @test plan.requests[2].canonical_query ==
        "endDate=2026-08-07&startDate=2026-08-07&type=volume"
    @test all(value === false for value in values(plan.gates))
    @test plan.operator_authorization[
        "operator_network_execution_authorized",
    ] === false
    @test plan.operator_authorization[
        "operator_raw_bundle_write_authorized",
    ] === false
    @test plan.operator_authorization[
        "campaign_network_execution_authorized",
    ] === false
    @test plan.operator_authorization[
        "campaign_raw_data_write_authorized",
    ] === false
    @test plan.operator_authorization[
        "separate_from_campaign_governance_gates",
    ] === true
    @test plan.operator_authorization["downloader_invocation_ceiling"] == 6
    @test plan.operator_authorization["network_exchange_count_ceiling"] ==
        "NOT_INDEPENDENTLY_WITNESSED"
    @test canonical_transaction_id("2026-08-10", "revision-check") ==
        "effr-20260810-revision-1830z"
    revision =
        dry_run_plan("2026-08-10", "revision-check"; output_root = root)
    @test revision.predecessor_path == plan.final_path
    @test revision.authorization.window_start_utc ==
        DateTime(2026, 8, 10, 18, 30)
    @test_throws RecurringAcquisitionError dry_run_plan(
        "2026-08-07",
        "first";
        output_root = root,
    )
    @test_throws RecurringAcquisitionError dry_run_plan(
        "2026-08-08",
        "first";
        output_root = root,
    )
    @test_throws RecurringAcquisitionError dry_run_plan(
        "2026-10-30",
        "revision-check";
        output_root = root,
    )
    @test_throws RecurringAcquisitionError canonical_transaction_id(
        "2026-08-10",
        1,
    )
end

@testset "present false first-state capture and validation" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw")
        responses = fixture_responses(
            "2026-08-10",
            "first";
            current_state = false,
        )
        calls = String[]
        validated = capture_fixture(
            output_root,
            "2026-08-10",
            "first";
            responses,
            calls,
        )
        @test calls == [
            "rate_response",
            "volume_response",
            "api_documentation_snapshot",
            "openapi_snapshot",
            "terms_snapshot",
            "holiday_snapshot",
        ]
        @test validated.bundle_path ==
            first_bundle_path(output_root, "2026-08-10")
        @test validated.manifest["result"]["status"] ==
            "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_FIRST_STATE_CANDIDATE"
        @test validated.manifest["result"][
            "one_date_receipt_validated",
        ] === true
        @test validated.manifest["result"]["revision_observed"] === false
        @test validated.manifest["result"][
            "revision_receipt_created",
        ] === false
        @test validated.rate_receipt !== nothing
        @test validated.volume_receipt !== nothing
        @test validated.pair.pair_status ==
            "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT"
        @test all(
            identity["current_state_source"] == "RAW_FIELD_FALSE" for
                identity in validated.manifest["row_identity"]
        )
        @test all(value === false for value in values(validated.manifest["gates"]))
        @test validated.manifest["capture"][
            "persisted_transport_provenance_authenticated",
        ] === false
        @test validated.manifest["capture"][
            "network_exchange_count_externally_witnessed",
        ] === false
        @test validated.manifest["operator_authorization"][
            "operator_authorization_externally_authenticated",
        ] === false
        @test all(
            blocker in validated.manifest["blockers"] for blocker in (
                    "PERSISTED_TRANSPORT_PROVENANCE_NOT_EXTERNALLY_AUTHENTICATED",
                    "NETWORK_EXCHANGE_COUNT_NOT_INDEPENDENTLY_WITNESSED",
                    "OPERATOR_AUTHORIZATION_LOCALLY_SELF_REPORTED_NOT_EXTERNALLY_AUTHENTICATED",
                )
        )
        @test validated.manifest["storage"]["durable_external_copy_count"] == 0
        @test validated.manifest["storage"][
            "external_timestamp_verified",
        ] === false
        @test isfile(joinpath(validated.bundle_path, "capture-manifest.toml"))
        @test !ispath(
            joinpath(
                dirname(validated.bundle_path),
                ".journal-effr-20260810-first-1300z",
            ),
        )
        reloaded = load_fixture_bundle(validated.bundle_path)
        @test reloaded.manifest["artifact"]["manifest_sha256"] ==
            validated.manifest["artifact"]["manifest_sha256"]
        @test occursin(
            "default loader rejects synthetic test fixtures",
            failure_text() do
                load_and_validate_bundle(validated.bundle_path)
            end,
        )
        @test reloaded.manifest["capture"]["synthetic_test_fixture"] === true
        @test reloaded.manifest["capture"]["network_exchange_count"] ==
            "NOT_INDEPENDENTLY_WITNESSED"
        @test reloaded.manifest["capture"][
            "attempted_network_exchange_count",
        ] == "NOT_INDEPENDENTLY_WITNESSED"
        campaign = CampaignControl.evaluate_campaign(
            CampaignControl.load_schedule(),
            [CampaignControl.validated_bundle_manifest(reloaded)],
        )
        @test campaign.status == "CAMPAIGN_CONTROL_INVALID"
        @test campaign.accepted_slot_count == 0
        @test length(campaign.rejected_bundles) == 1
        @test campaign.origin_admissible === false
    end
end

@testset "absent currentState remains non-derived" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw")
        validated = capture_fixture(
            output_root,
            "2026-08-10",
            "first",
        )
        result = validated.manifest["result"]
        @test result["status"] ==
            "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
        @test result["failure_code"] ==
            "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT"
        @test result["rate_receipt_file"] == "NONE"
        @test result["volume_receipt_file"] == "NONE"
        @test result["rate_receipt_sha256"] == "NONE"
        @test result["volume_receipt_sha256"] == "NONE"
        @test validated.rate_receipt === nothing
        @test validated.volume_receipt === nothing
        @test validated.pair === nothing
        @test all(
            identity["raw_current_state_present"] === false for
                identity in validated.manifest["row_identity"]
        )
        @test all(
            identity["raw_current_state_value"] == "ABSENT" for
                identity in validated.manifest["row_identity"]
        )
        @test all(
            identity["current_state_source"] ==
                "ABSENT_FROM_RAW_RESPONSE_NOT_DERIVED" for
                identity in validated.manifest["row_identity"]
        )
        @test "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT" in
            validated.manifest["blockers"]
        campaign = CampaignControl.evaluate_campaign(
            CampaignControl.load_schedule(),
            [CampaignControl.validated_bundle_manifest(validated)],
        )
        @test campaign.status == "CAMPAIGN_CONTROL_INVALID"
        @test campaign.accepted_slot_count == 0
        @test length(campaign.rejected_bundles) == 1
        @test campaign.receipt_semantics_complete === false
        @test campaign.origin_admissible === false
    end
end

@testset "closed revision transition matrix and predecessor closure" begin
    @testset "byte-identical empty token creates no revision receipt" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            first_responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            )
            first = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = first_responses,
            )
            revision_calls = String[]
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = deepcopy(first_responses),
                calls = revision_calls,
            )
            result = revision.manifest["result"]
            @test revision_calls == [
                "rate_response",
                "volume_response",
                "api_documentation_snapshot",
                "openapi_snapshot",
                "terms_snapshot",
                "holiday_snapshot",
            ]
            @test result["status"] ==
                "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
            @test result["byte_equality_rate"] === true
            @test result["byte_equality_volume"] === true
            @test result["revision_observed"] === false
            @test result["revision_receipt_created"] === false
            @test result["rate_receipt_file"] == "NONE"
            @test result["volume_receipt_file"] == "NONE"
            @test result["predecessor_bundle"] == first.bundle_path
            @test result["predecessor_manifest_sha256"] ==
                first.manifest["artifact"]["manifest_sha256"]
            @test result["predecessor_rate_raw_sha256"] ==
                bytes2hex(sha256(first.rate_bytes))
            @test result["predecessor_volume_raw_sha256"] ==
                bytes2hex(sha256(first.volume_bytes))
            @test result["predecessor_rate_receipt_sha256"] ==
                first.manifest["result"]["rate_receipt_sha256"]
            @test result["predecessor_volume_receipt_sha256"] ==
                first.manifest["result"]["volume_receipt_sha256"]
            @test revision.rate_receipt === nothing
            @test revision.volume_receipt === nothing
            @test load_fixture_bundle(revision.bundle_path).manifest[
                "artifact",
            ]["manifest_sha256"] ==
                revision.manifest["artifact"]["manifest_sha256"]
        end
    end

    @testset "changed closed-token bytes create linked revision receipts" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            first = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = fixture_responses(
                    "2026-08-10",
                    "revision-check";
                    revision = "r",
                    current_state = false,
                    rate = 3.62,
                    volume = 113.0,
                ),
            )
            result = revision.manifest["result"]
            @test result["status"] ==
                "LOCAL_INTEGRITY_VALIDATED_NONADMITTING_REVISION_CANDIDATE"
            @test result["byte_equality_rate"] === false
            @test result["byte_equality_volume"] === false
            @test result["revision_observed"] === true
            @test result["revision_receipt_created"] === true
            @test result["one_date_receipt_validated"] === true
            @test revision.pair.pair_status ==
                "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT"
            @test revision.rate_receipt["lineage"][
                "predecessor_receipt_sha256",
            ] == first.manifest["result"]["rate_receipt_sha256"]
            @test revision.volume_receipt["lineage"][
                "predecessor_receipt_sha256",
            ] == first.manifest["result"]["volume_receipt_sha256"]
            @test revision.rate_receipt["lineage"][
                "supersession_status",
            ] == "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE"
            @test all(
                value === false for
                    value in values(revision.manifest["gates"])
            )
        end
    end

    @testset "absent state is preserved across revision outcomes" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            first_responses =
                fixture_responses("2026-08-10", "first")
            first = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = first_responses,
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = deepcopy(first_responses),
            )
            @test revision.manifest["result"]["status"] ==
                "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED"
            @test revision.manifest["result"][
                "predecessor_rate_receipt_sha256",
            ] == "NONE"
            @test revision.rate_receipt === nothing
            @test "ONE_DATE_CONTRACT_RAW_CURRENT_STATE_FIELD_ABSENT" in
                revision.manifest["blockers"]
            @test first.manifest["result"]["rate_receipt_sha256"] == "NONE"
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = fixture_responses(
                    "2026-08-10",
                    "revision-check";
                    revision = "r",
                    current_state = :absent,
                    rate = 3.62,
                ),
            )
            result = revision.manifest["result"]
            @test result["status"] ==
                "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
            @test result["revision_observed"] === true
            @test result["revision_receipt_created"] === false
            @test result["rate_receipt_file"] == "NONE"
            @test result["volume_receipt_file"] == "NONE"
            @test revision.rate_receipt === nothing
        end
    end

    @testset "invalid raw transition combinations fail closed" begin
        for case in ("changed-empty", "receiptless-predecessor")
            mktempdir() do temporary
                output_root = joinpath(realpath(temporary), "raw")
                first_state = case == "receiptless-predecessor" ?
                    :absent : false
                first_responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = first_state,
                )
                capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses = first_responses,
                )
                revision_responses = if case == "changed-empty"
                    fixture_responses(
                        "2026-08-10",
                        "revision-check";
                        current_state = false,
                        rate = 3.62,
                    )
                else
                    fixture_responses(
                        "2026-08-10",
                        "revision-check";
                        revision = "r",
                        current_state = false,
                        rate = 3.62,
                    )
                end
                message = failure_text() do
                    capture_fixture(
                        output_root,
                        "2026-08-10",
                        "revision-check";
                        responses = revision_responses,
                    )
                end
                @test message != "NO_ERROR"
                @test occursin(
                    case == "changed-empty" ?
                        "bytes changed without" :
                        "predecessor rate receipt is absent",
                    message,
                )
                failed_journal = journal_path(
                    output_root,
                    "2026-08-10",
                    "revision-check",
                )
                @test isfile(
                    joinpath(failed_journal, "capture-failure.toml"),
                )
                @test !ispath(
                    dry_run_plan(
                        "2026-08-10",
                        "revision-check";
                        output_root,
                    ).final_path,
                )
            end
        end
        plan = dry_run_plan(
            "2026-08-10",
            "revision-check";
            output_root = "/not-used",
        )
        responses = fixture_responses(
            "2026-08-10",
            "revision-check";
            revision = "r",
            current_state = false,
            rate = 3.62,
        )
        objects = [
            USEFFRRecurringAcquisition._normalize_download(
                    responses[spec.object_id],
                    spec,
                    plan.authorization.window_start_utc,
                    plan.authorization.window_start_utc,
                ) for spec in plan.requests
        ]
        predecessor = (
            bundle_path = "/synthetic/predecessor",
            manifest_sha256 = repeat("a", 64),
            rate_bytes = objects[1].body,
            volume_bytes = objects[2].body,
            rate_raw_sha256 = bytes2hex(sha256(objects[1].body)),
            volume_raw_sha256 = bytes2hex(sha256(objects[2].body)),
            rate_receipt_sha256 = repeat("b", 64),
            volume_receipt_sha256 = repeat("c", 64),
        )
        message = failure_text() do
            USEFFRRecurringAcquisition._evaluate_capture(
                nothing,
                plan.authorization,
                objects,
                repeat("d", 64),
                predecessor,
            )
        end
        @test occursin("token r appeared without", message)
    end
end

@testset "clock boundary, transport, and crash journal adversaries" begin
    @testset "capture window is closed and boundary-inclusive" begin
        for boundary in ("start", "deadline")
            mktempdir() do temporary
                output_root = joinpath(realpath(temporary), "raw")
                plan = dry_run_plan(
                    "2026-08-10",
                    "first";
                    output_root,
                )
                instant = boundary == "start" ?
                    plan.authorization.window_start_utc :
                    plan.authorization.window_deadline_utc
                validated = capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses = fixture_responses(
                        "2026-08-10",
                        "first";
                        current_state = false,
                    ),
                    clock = constant_clock(instant),
                )
                @test validated.manifest["result"]["success"] === true
            end
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            calls = String[]
            message = failure_text() do
                acquire_recurring(
                    "2026-08-10",
                    "first";
                    output_root,
                    execute_live = true,
                    synthetic_test_fixture = true,
                    downloader = fixture_downloader(
                        fixture_responses("2026-08-10", "first");
                        calls,
                    ),
                    clock = fixture_clock(
                        "2026-08-10",
                        "first";
                        outside = true,
                    ),
                )
            end
            @test occursin("outside the frozen capture window", message)
            @test isempty(calls)
            @test !ispath(output_root)
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            plan = dry_run_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            values = [
                plan.authorization.window_start_utc,
                plan.authorization.window_start_utc,
                plan.authorization.window_deadline_utc + Millisecond(1),
            ]
            cursor = Ref(0)
            clock = () -> begin
                cursor[] += 1
                values[min(cursor[], length(values))]
            end
            calls = String[]
            message = failure_text() do
                acquire_recurring(
                    "2026-08-10",
                    "first";
                    output_root,
                    execute_live = true,
                    synthetic_test_fixture = true,
                    downloader = fixture_downloader(
                        fixture_responses("2026-08-10", "first");
                        calls,
                    ),
                    clock,
                )
            end
            @test occursin("capture is outside the frozen window", message)
            @test calls == ["rate_response"]
            journal = plan.journal_path
            @test isfile(joinpath(journal, "capture-failure.toml"))
            @test length(
                filter(
                    name -> startswith(name, "raw-sha256-"),
                    readdir(joinpath(journal, "replica-a")),
                ),
            ) == 1
        end
    end

    @testset "transport anomalies retain bytes before rejection" begin
        cases = [
            (
                "http-status",
                (; status_overrides = Dict("rate_response" => 503)),
                "HTTP status is not 200",
            ),
            (
                "redirect-url",
                (;
                    final_url_overrides =
                        Dict("rate_response" => "https://example.invalid/"),
                ),
                "redirect or final URL mismatch",
            ),
            (
                "redirect-count",
                (;
                    redirect_count_overrides =
                        Dict("rate_response" => 1),
                ),
                "redirect count must be zero",
            ),
            (
                "proxy",
                (;
                    proxy_used_overrides =
                        Dict("rate_response" => true),
                ),
                "proxy use is forbidden",
            ),
            (
                "encoding",
                (;
                    content_encoding_overrides =
                        Dict("rate_response" => "gzip"),
                ),
                "content encoding must be identity",
            ),
            (
                "media-type",
                (;
                    content_type_overrides =
                        Dict("rate_response" => "text/html"),
                ),
                "unexpected media type",
            ),
        ]
        for (name, overrides, expected) in cases
            mktempdir() do temporary
                output_root =
                    joinpath(realpath(temporary), "raw-$name")
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    overrides...,
                )
                calls = String[]
                message = failure_text() do
                    capture_fixture(
                        output_root,
                        "2026-08-10",
                        "first";
                        responses,
                        calls,
                    )
                end
                @test occursin(expected, message)
                @test calls == ["rate_response"]
                journal = journal_path(
                    output_root,
                    "2026-08-10",
                    "first",
                )
                @test isfile(
                    joinpath(journal, "capture-failure.toml"),
                )
                raw_files = filter(
                    item -> startswith(item, "raw-sha256-"),
                    readdir(joinpath(journal, "replica-a")),
                )
                @test length(raw_files) == 1
                @test read(
                    joinpath(journal, "replica-a", only(raw_files)),
                ) == responses["rate_response"].body
                @test read(
                    joinpath(journal, "replica-b", only(raw_files)),
                ) == responses["rate_response"].body
            end
        end
    end

    @testset "downloader crash is append-only and has no implicit retry" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            responses = fixture_responses("2026-08-10", "first")
            calls = String[]
            message = failure_text() do
                acquire_recurring(
                    "2026-08-10",
                    "first";
                    output_root,
                    execute_live = true,
                    synthetic_test_fixture = true,
                    downloader = fixture_downloader(
                        responses;
                        calls,
                        fail_at = 3,
                    ),
                    clock = fixture_clock("2026-08-10", "first"),
                )
            end
            @test occursin("injected downloader failure", message)
            @test calls == [
                "rate_response",
                "volume_response",
                "api_documentation_snapshot",
            ]
            journal = journal_path(
                output_root,
                "2026-08-10",
                "first",
            )
            @test isfile(
                joinpath(
                    journal,
                    "attempts",
                    "0003-api_documentation_snapshot-started.toml",
                ),
            )
            @test !isfile(
                joinpath(
                    journal,
                    "attempts",
                    "0003-api_documentation_snapshot-completed.toml",
                ),
            )
            @test TOML.parsefile(
                joinpath(journal, "capture-failure.toml"),
            )["retry_without_recovery_forbidden"] === true
            retry_calls = String[]
            retry_message = failure_text() do
                acquire_recurring(
                    "2026-08-10",
                    "first";
                    output_root,
                    execute_live = true,
                    synthetic_test_fixture = true,
                    downloader = fixture_downloader(
                        responses;
                        calls = retry_calls,
                    ),
                    clock = fixture_clock("2026-08-10", "first"),
                )
            end
            @test occursin("append-only target already exists", retry_message)
            @test isempty(retry_calls)
        end
    end
end

@testset "strict raw schema rejection retains the complete response set" begin
    case_names = [
        "malformed-json",
        "zero-effr",
        "duplicate-effr",
        "unknown-field",
        "wrong-effective-date",
        "revision-token-mismatch",
        "current-state-presence-mismatch",
        "true-current-state",
        "first-state-r-token",
    ]
    for case in case_names
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$case")
            plan = dry_run_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            effective = plan.authorization.effective_date
            responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            )
            if case == "malformed-json"
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (body = Vector{UInt8}(codeunits("{not-json")),),
                )
            elseif case == "zero-effr"
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (
                        body = Vector{UInt8}(
                            codeunits(JSON.json(Dict("refRates" => Any[]))),
                        ),
                    ),
                )
            elseif case == "duplicate-effr"
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (
                        body = effr_body(
                            effective,
                            "rate";
                            current_state = false,
                            duplicate = true,
                        ),
                    ),
                )
            elseif case == "unknown-field"
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (
                        body = effr_body(
                            effective,
                            "rate";
                            current_state = false,
                            extra_field = true,
                        ),
                    ),
                )
            elseif case == "wrong-effective-date"
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (
                        body = effr_body(
                            effective,
                            "rate";
                            current_state = false,
                            effective_override = "2026-08-06",
                        ),
                    ),
                )
            elseif case == "revision-token-mismatch"
                responses["volume_response"] = merge(
                    responses["volume_response"],
                    (
                        body = effr_body(
                            effective,
                            "volume";
                            revision = "r",
                            current_state = false,
                        ),
                    ),
                )
            elseif case == "current-state-presence-mismatch"
                responses["volume_response"] = merge(
                    responses["volume_response"],
                    (
                        body = effr_body(
                            effective,
                            "volume";
                            current_state = :absent,
                        ),
                    ),
                )
            elseif case == "true-current-state"
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (
                        body = effr_body(
                            effective,
                            "rate";
                            current_state = true,
                        ),
                    ),
                )
            else
                responses["rate_response"] = merge(
                    responses["rate_response"],
                    (
                        body = effr_body(
                            effective,
                            "rate";
                            revision = "r",
                            current_state = false,
                        ),
                    ),
                )
                responses["volume_response"] = merge(
                    responses["volume_response"],
                    (
                        body = effr_body(
                            effective,
                            "volume";
                            revision = "r",
                            current_state = false,
                        ),
                    ),
                )
            end
            calls = String[]
            @test failure_text() do
                capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses,
                    calls,
                )
            end != "NO_ERROR"
            @test length(calls) == 6
            @test isfile(
                joinpath(plan.journal_path, "capture-failure.toml"),
            )
            @test all(
                isfile(
                        joinpath(
                            plan.journal_path,
                            "attempts",
                            lpad(string(index), 4, '0') *
                            "-$(request.object_id)-validated.toml",
                        ),
                    ) for
                    (index, request) in enumerate(plan.requests)
            )
            @test length(
                filter(
                    item -> startswith(item, "raw-sha256-"),
                    readdir(joinpath(plan.journal_path, "replica-a")),
                ),
            ) == 6
        end
    end
end

@testset "filesystem confinement, append-only publication, and loader attacks" begin
    @testset "symlink output component is rejected before downloader use" begin
        mktempdir() do temporary
            base = realpath(temporary)
            real_target = joinpath(base, "real-target")
            mkdir(real_target)
            linked = joinpath(base, "linked")
            symlink(real_target, linked)
            output_root = joinpath(linked, "raw")
            calls = String[]
            message = failure_text() do
                acquire_recurring(
                    "2026-08-10",
                    "first";
                    output_root,
                    execute_live = true,
                    synthetic_test_fixture = true,
                    downloader = fixture_downloader(
                        fixture_responses("2026-08-10", "first");
                        calls,
                    ),
                    clock = fixture_clock("2026-08-10", "first"),
                )
            end
            @test occursin("symbolic-link component rejected", message)
            @test isempty(calls)
            @test isempty(readdir(real_target))
        end
    end

    @testset "published final path cannot be retried or overwritten" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            first = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            calls = String[]
            message = failure_text() do
                capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses = fixture_responses(
                        "2026-08-10",
                        "first";
                        current_state = false,
                    ),
                    calls,
                )
            end
            @test occursin("append-only target already exists", message)
            @test isempty(calls)
            @test load_fixture_bundle(first.bundle_path).manifest[
                "artifact",
            ]["manifest_sha256"] ==
                first.manifest["artifact"]["manifest_sha256"]
        end
    end

    @testset "loader rejects hardlinks, symlinks, and path escape" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            record = only(
                item for item in bundle.manifest["objects"] if
                    item["object_id"] == "rate_response"
            )
            source = joinpath(bundle.bundle_path, record["primary_path"])
            shadow = joinpath(realpath(temporary), "hardlink-shadow")
            Base.Filesystem.hardlink(source, shadow)
            @test occursin(
                "hard-linked file rejected",
                failure_text() do
                    load_fixture_bundle(bundle.bundle_path)
                end,
            )
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            replica_manifest =
                joinpath(bundle.bundle_path, "replica-b", "capture-manifest.toml")
            rm(replica_manifest)
            symlink(
                joinpath(bundle.bundle_path, "capture-manifest.toml"),
                replica_manifest,
            )
            @test occursin(
                "symbolic-link descendant rejected",
                failure_text() do
                    load_fixture_bundle(bundle.bundle_path)
                end,
            )
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            manifest = deepcopy(bundle.manifest)
            rate = only(
                item for item in manifest["objects"] if
                    item["object_id"] == "rate_response"
            )
            rate["primary_path"] = "../escape.json"
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisition._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            @test occursin(
                "primary_path",
                failure_text() do
                    load_fixture_bundle(bundle.bundle_path)
                end,
            )
        end
    end

    @testset "loader revalidates manifest and operator authorization" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            open(
                joinpath(bundle.bundle_path, "capture-manifest.toml"),
                "a",
            ) do io
                write(io, "\n# tamper\n")
            end
            @test occursin(
                "triplicate bytes differ",
                failure_text() do
                    load_fixture_bundle(bundle.bundle_path)
                end,
            )
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            manifest = deepcopy(bundle.manifest)
            manifest["operator_authorization"][
                "campaign_network_execution_authorized",
            ] = true
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisition._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            @test occursin(
                "campaign_network_execution_authorized",
                failure_text() do
                    load_fixture_bundle(bundle.bundle_path)
                end,
            )
        end
    end
end

@testset "revision preflight validates the canonical predecessor first" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw")
        calls = String[]
        message = failure_text() do
            acquire_recurring(
                "2026-08-10",
                "revision-check";
                output_root,
                execute_live = true,
                synthetic_test_fixture = true,
                downloader = fixture_downloader(
                    fixture_responses(
                        "2026-08-10",
                        "revision-check";
                        revision = "r",
                        current_state = false,
                    );
                    calls,
                ),
                clock = fixture_clock(
                    "2026-08-10",
                    "revision-check",
                ),
            )
        end
        @test occursin("not a directory", message)
        @test isempty(calls)
        @test !ispath(
            journal_path(
                output_root,
                "2026-08-10",
                "revision-check",
            ),
        )
    end
    for tamper_class in ("raw", "receipt")
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            first = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            tampered_path = if tamper_class == "raw"
                record = only(
                    item for item in first.manifest["objects"] if
                        item["object_id"] == "rate_response"
                )
                joinpath(first.bundle_path, record["primary_path"])
            else
                joinpath(
                    first.bundle_path,
                    "receipts",
                    first.manifest["result"]["rate_receipt_file"],
                )
            end
            open(tampered_path, "a") do io
                write(io, UInt8[0x0a])
            end
            calls = String[]
            message = failure_text() do
                acquire_recurring(
                    "2026-08-10",
                    "revision-check";
                    output_root,
                    execute_live = true,
                    synthetic_test_fixture = true,
                    downloader = fixture_downloader(
                        fixture_responses(
                            "2026-08-10",
                            "revision-check";
                            revision = "r",
                            current_state = false,
                            rate = 3.62,
                        );
                        calls,
                    ),
                    clock = fixture_clock(
                        "2026-08-10",
                        "revision-check",
                    ),
                )
            end
            @test occursin("replicas differ", message) ||
                occursin("triplicate bytes differ", message)
            @test isempty(calls)
            @test !ispath(
                journal_path(
                    output_root,
                    "2026-08-10",
                    "revision-check",
                ),
            )
        end
    end
end

@testset "v3 duplicate-member and synthetic provenance firewall" begin
    plan = dry_run_plan(
        "2026-08-10",
        "first";
        output_root = "/not-written",
    )
    envelope_duplicate = Vector{UInt8}(
        codeunits("{\"refRates\":[],\"ref\\u0052ates\":[]}"),
    )
    @test occursin(
        "duplicate JSON member name after escape decoding: refRates",
        failure_text() do
            USEFFRRecurringAcquisition._reject_duplicate_json_members(
                envelope_duplicate,
                "probe",
            )
        end,
    )
    base = String(
        effr_body(
            plan.authorization.effective_date,
            "rate";
            current_state = false,
        ),
    )
    duplicate = replace(
        base,
        "\"currentState\":false" =>
            "\"currentState\":true,\"current\\u0053tate\":false";
        count = 1,
    )
    @test duplicate != base
    @test occursin(
        "duplicate JSON member name after escape decoding: currentState",
        failure_text() do
            USEFFRRecurringAcquisition._select_effr_row(
                Vector{UInt8}(codeunits(duplicate)),
                "rate",
                plan.authorization.effective_date,
            )
        end,
    )
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-duplicate")
        responses = fixture_responses(
            "2026-08-10",
            "first";
            current_state = false,
        )
        responses["rate_response"] = merge(
            responses["rate_response"],
            (body = Vector{UInt8}(codeunits(duplicate)),),
        )
        calls = String[]
        message = failure_text() do
            capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses,
                calls,
            )
        end
        @test occursin("duplicate JSON member name", message)
        @test length(calls) == 6
        journal = journal_path(output_root, "2026-08-10", "first")
        @test length(
            filter(
                name -> startswith(name, "raw-sha256-"),
                readdir(joinpath(journal, "replica-a")),
            ),
        ) == 6
        @test !ispath(
            dry_run_plan(
                "2026-08-10",
                "first";
                output_root,
            ).final_path,
        )
    end
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-unmarked")
        calls = String[]
        message = failure_text() do
            acquire_recurring(
                "2026-08-10",
                "first";
                output_root,
                execute_live = true,
                downloader = fixture_downloader(
                    fixture_responses("2026-08-10", "first");
                    calls,
                ),
                clock = fixture_clock("2026-08-10", "first"),
            )
        end
        @test occursin("requires synthetic_test_fixture=true", message)
        @test isempty(calls)
        @test !ispath(output_root)
    end
    built_in = USEFFRRecurringAcquisition._operator_authorization(
        plan.authorization,
        true,
    )
    @test built_in["operator_network_execution_authorized"] === true
    @test built_in["synthetic_test_fixture"] === false
    @test built_in["built_in_transport_required"] === true
    @test length(request_plan("2026-08-10", "first")) == 6
end

@testset "v3 response preservation and header firewall" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-clock")
        plan = dry_run_plan(
            "2026-08-10",
            "first";
            output_root,
        )
        cursor = Ref(0)
        clock = () -> begin
            cursor[] += 1
            cursor[] <= 2 ||
                error("injected completion clock exhaustion")
            return plan.authorization.window_start_utc
        end
        calls = String[]
        message = failure_text() do
            acquire_recurring(
                "2026-08-10",
                "first";
                output_root,
                execute_live = true,
                synthetic_test_fixture = true,
                downloader = fixture_downloader(
                    fixture_responses("2026-08-10", "first");
                    calls,
                ),
                clock,
            )
        end
        @test occursin("completion clock exhaustion", message)
        @test calls == ["rate_response"]
        @test length(
            filter(
                name -> startswith(name, "raw-sha256-"),
                readdir(joinpath(plan.journal_path, "replica-a")),
            ),
        ) == 1
        @test isfile(joinpath(plan.journal_path, "capture-failure.toml"))
    end
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-no-body")
        plan = dry_run_plan(
            "2026-08-10",
            "first";
            output_root,
        )
        response = fixture_responses("2026-08-10", "first")["rate_response"]
        no_body = (;
            (
                name => getproperty(response, name) for
                    name in propertynames(response) if name != :body
            )...,
        )
        calls = Ref(0)
        message = failure_text() do
            acquire_recurring(
                "2026-08-10",
                "first";
                output_root,
                execute_live = true,
                synthetic_test_fixture = true,
                downloader = _ -> begin
                    calls[] += 1
                    no_body
                end,
                clock = fixture_clock("2026-08-10", "first"),
            )
        end
        @test occursin("without a preservable body", message)
        @test calls[] == 1
        @test isempty(
            filter(
                name -> startswith(name, "raw-sha256-"),
                readdir(joinpath(plan.journal_path, "replica-a")),
            ),
        )
    end
    header_cases = [
        (
            "ctl-crlf",
            [
                "content-type" => "application/json",
                "content-encoding" => "identity",
                "x-test" => "safe\r\ninjected: true",
            ],
            "forbidden control character",
        ),
        (
            "ctl-nul",
            [
                "content-type" => "application/json",
                "content-encoding" => "identity",
                "x-test" => "safe\0unsafe",
            ],
            "forbidden control character",
        ),
        (
            "invalid-name",
            [
                "content-type" => "application/json",
                "content-encoding" => "identity",
                "bad name" => "value",
            ],
            "not a valid HTTP field-name",
        ),
        (
            "leading-name-whitespace",
            [
                " content-type" => "application/json",
                "content-encoding" => "identity",
            ],
            "must not have leading or trailing whitespace",
        ),
        (
            "trailing-name-whitespace",
            [
                "content-type " => "application/json",
                "content-encoding" => "identity",
            ],
            "must not have leading or trailing whitespace",
        ),
        (
            "duplicate-content-type",
            [
                "content-type" => "application/json",
                "content-type" => "text/html",
                "content-encoding" => "identity",
            ],
            "conflicting duplicate content-type",
        ),
        (
            "duplicate-content-encoding",
            [
                "content-type" => "application/json",
                "content-encoding" => "identity",
                "content-encoding" => "gzip",
            ],
            "conflicting duplicate content-encoding",
        ),
    ]
    for (name, headers, expected) in header_cases
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$name")
            plan = dry_run_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            responses = fixture_responses("2026-08-10", "first")
            responses["rate_response"] =
                merge(responses["rate_response"], (; headers))
            calls = String[]
            message = failure_text() do
                capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses,
                    calls,
                )
            end
            @test occursin(expected, message)
            @test calls == ["rate_response"]
            @test length(
                filter(
                    item -> startswith(item, "raw-sha256-"),
                    readdir(joinpath(plan.journal_path, "replica-a")),
                ),
            ) == 1
        end
    end
    for (name, malformed_name) in (
            ("persisted-leading-name-whitespace", " content-type"),
            ("persisted-trailing-name-whitespace", "content-type "),
        )
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$name")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first",
            )
            manifest = deepcopy(bundle.manifest)
            record = manifest["objects"][1]
            header_index = findfirst(
                header -> startswith(header, "content-type:"),
                record["response_headers"],
            )
            @test header_index !== nothing
            original = record["response_headers"][header_index]
            value = strip(split(original, ':'; limit = 2)[2])
            record["response_headers"][header_index] =
                "$malformed_name: $value"
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisition._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            message = failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end
            @test occursin(
                "must not have leading or trailing whitespace",
                message,
            )
            @test message != "NO_ERROR"
        end
    end
end

@testset "v3 loader closes transitions and non-elevating trust fields" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-transition")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first",
        )
        manifest = deepcopy(bundle.manifest)
        effective = Date(2026, 8, 7)
        volume_bytes = effr_body(
            effective,
            "volume";
            revision = "r",
            current_state = :absent,
        )
        volume_hash = bytes2hex(sha256(volume_bytes))
        record = only(
            item for item in manifest["objects"] if
                item["object_id"] == "volume_response"
        )
        raw_name = "raw-sha256-$volume_hash.json"
        record["raw_sha256"] = volume_hash
        record["raw_byte_count"] = length(volume_bytes)
        record["primary_path"] = "replica-a/$raw_name"
        record["replica_path"] = "replica-b/$raw_name"
        for path in (
                joinpath(bundle.bundle_path, record["primary_path"]),
                joinpath(bundle.bundle_path, record["replica_path"]),
            )
            open(path, "w") do io
                write(io, volume_bytes)
            end
        end
        selected = USEFFRRecurringAcquisition._select_effr_row(
            volume_bytes,
            "volume",
            effective,
        )
        manifest["row_identity"][2] =
            USEFFRRecurringAcquisition._identity_record(
            "volume",
            selected,
        )
        storage_path =
            manifest["storage"]["local_storage_receipt_file"]
        storage = TOML.parsefile(
            joinpath(bundle.bundle_path, storage_path),
        )
        storage_record = only(
            item for item in storage["objects"] if
                item["object_id"] == "volume_response"
        )
        storage_record["raw_sha256"] = volume_hash
        storage_record["raw_byte_count"] = length(volume_bytes)
        storage["artifact"]["receipt_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            storage,
            "artifact",
            "receipt_sha256",
        )
        replace_storage_triplicates!(
            bundle.bundle_path,
            storage_path,
            storage,
        )
        manifest["storage"]["local_storage_receipt_sha256"] =
            storage["artifact"]["receipt_sha256"]
        manifest["artifact"]["manifest_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            manifest,
            "artifact",
            "manifest_sha256",
        )
        replace_manifest_triplicates!(bundle.bundle_path, manifest)
        @test occursin(
            "rate and volume revision tokens differ",
            failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end,
        )
    end
    mutations = [
        (
            "result-authentication",
            manifest -> manifest["result"][
                "receipt_authentication_status",
            ] = "OUT_OF_BAND_AUTHENTICATED",
        ),
        (
            "result-detail",
            manifest -> manifest["result"]["failure_detail"] =
                "TRUST_ME",
        ),
        (
            "blocker-removal",
            manifest -> filter!(
                blocker ->
                blocker !=
                    "LOCAL_RECEIPT_PIN_NOT_OUT_OF_BAND_AUTHENTICATION",
                manifest["blockers"],
            ),
        ),
        (
            "gate-elevation",
            manifest -> manifest["gates"]["origin_admissible"] = true,
        ),
        (
            "storage-retention",
            manifest -> manifest["storage"][
                "retention_through_2031_attested",
            ] = true,
        ),
    ]
    for (name, mutate!) in mutations
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$name")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first",
            )
            manifest = deepcopy(bundle.manifest)
            mutate!(manifest)
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisition._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            @test failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end != "NO_ERROR"
        end
    end
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-storage-receipt")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first",
        )
        manifest = deepcopy(bundle.manifest)
        storage_path =
            manifest["storage"]["local_storage_receipt_file"]
        storage = TOML.parsefile(
            joinpath(bundle.bundle_path, storage_path),
        )
        storage["retention_through_2031_attested"] = true
        storage["artifact"]["receipt_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            storage,
            "artifact",
            "receipt_sha256",
        )
        replace_storage_triplicates!(
            bundle.bundle_path,
            storage_path,
            storage,
        )
        manifest["storage"]["local_storage_receipt_sha256"] =
            storage["artifact"]["receipt_sha256"]
        manifest["artifact"]["manifest_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            manifest,
            "artifact",
            "manifest_sha256",
        )
        replace_manifest_triplicates!(bundle.bundle_path, manifest)
        @test occursin(
            "bundle storage receipt",
            failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end,
        )
    end
end

# Regression family for rejected manifest witness
# 0443dabc53005823b42cc67d42214be7205e2daf3ef35c5d5828429be779a010.
@testset "v3 reconstructed receipts reject coordinated value rewrites" begin
    valid_mutations = [
        (
            "raw-percent-rate",
            receipt -> receipt["raw_fields"]["percentRate"] = 3.615,
            "percentRate",
        ),
        (
            "response-metadata",
            receipt -> begin
                timestamp = "2026-08-10T13:00:01.251Z"
                receipt["response"]["response_headers_at_utc"] =
                    timestamp
                receipt["response"][
                    "response_body_completed_at_utc",
                ] = timestamp
                receipt["response"][
                    "availability_upper_bound_utc",
                ] = timestamp
            end,
            "availability_upper_bound_utc",
        ),
        (
            "openapi-binding",
            receipt -> receipt["artifact"]["openapi_sha256"] =
                repeat("a", 64),
            "openapi_sha256",
        ),
        (
            "terms-binding",
            receipt -> receipt["governance"][
                "terms_snapshot_sha256",
            ] = repeat("b", 64),
            "terms_snapshot_sha256",
        ),
        (
            "storage-binding",
            receipt -> receipt["artifact"][
                "durable_storage_receipt_sha256",
            ] = repeat("c", 64),
            "durable_storage_receipt_sha256",
        ),
        (
            "phase-and-state",
            receipt -> begin
                receipt["receipt_id"] = replace(
                    receipt["receipt_id"],
                    "FIRST_0900_STATE" =>
                        "SAME_DAY_1430_REVISION",
                )
                observation = receipt["observation"]
                observation["state_class"] =
                    "SAME_DAY_1430_REVISION"
                observation["scheduled_publication_window"] =
                    "NYFED_APPROX_1430_ET"
                observation["pair_key"] =
                    "effectiveDate=2026-08-07;revisionToken=r"
                receipt["request"]["request_started_at_utc"] =
                    "2026-08-10T18:30:01.000Z"
                for field in (
                        "response_headers_at_utc",
                        "response_body_completed_at_utc",
                        "availability_upper_bound_utc",
                    )
                    receipt["response"][field] =
                        "2026-08-10T18:30:01.250Z"
                end
                receipt["raw_fields"]["revisionIndicator"] = "r"
                classification = receipt["classification"]
                classification["revision_class"] =
                    "DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH"
                classification["schema_class"] =
                    "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET"
                push!(
                    classification["blockers"],
                    "OPENAPI_EXAMPLE_MISMATCH_PRESERVED",
                )
                sort!(unique!(classification["blockers"]))
                predecessor = repeat("d", 64)
                receipt["lineage"]["predecessor_receipt_sha256"] =
                    predecessor
                receipt["lineage"]["supersedes_receipt_sha256"] =
                    predecessor
                receipt["lineage"]["supersession_status"] =
                    "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE"
            end,
            "bundle reconstructed rate receipt",
        ),
    ]
    for (name, mutate!, expected_fragment) in valid_mutations
        mktempdir() do temporary
            output_root =
                joinpath(realpath(temporary), "raw-receipt-$name")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            @test USEFFRRecurringAcquisition._select_effr_row(
                bundle.rate_bytes,
                "rate",
                Date(2026, 8, 7),
            ).values["percentRate"] == 3.61
            rewritten = rewrite_receipt_and_manifest!(
                bundle,
                "rate",
                mutate!,
            )
            @test rewritten.receipt["receipt_sha256"] !=
                bundle.manifest["result"]["rate_receipt_sha256"]
            message = failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end
            @test occursin("bundle reconstructed rate receipt", message)
            @test occursin(expected_fragment, message)
            @test message != "NO_ERROR"
        end
    end
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-receipt-bool-int")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first";
            responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            ),
        )
        rewrite_receipt_and_manifest!(
            bundle,
            "rate",
            receipt ->
            receipt["gates"]["origin_admissible"] = 0;
            require_contract_valid = false,
        )
        error = try
            load_fixture_bundle(bundle.bundle_path)
            nothing
        catch caught
            caught
        end
        @test error isa RecurringAcquisitionError
        @test occursin("must be a Boolean", sprint(showerror, error))
    end
    mktempdir() do temporary
        output_root =
            joinpath(realpath(temporary), "raw-receipt-predecessor")
        capture_fixture(
            output_root,
            "2026-08-10",
            "first";
            responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            ),
        )
        revision = capture_fixture(
            output_root,
            "2026-08-10",
            "revision-check";
            responses = fixture_responses(
                "2026-08-10",
                "revision-check";
                revision = "r",
                current_state = false,
                rate = 3.62,
                volume = 113.0,
            ),
            clock = fixture_clock(
                "2026-08-10",
                "revision-check",
            ),
        )
        false_predecessor = repeat("e", 64)
        rewrite_receipt_and_manifest!(
            revision,
            "rate",
            receipt -> begin
                receipt["lineage"]["predecessor_receipt_sha256"] =
                    false_predecessor
                receipt["lineage"]["supersedes_receipt_sha256"] =
                    false_predecessor
            end,
        )
        message = failure_text() do
            load_fixture_bundle(revision.bundle_path)
        end
        @test occursin("bundle reconstructed rate receipt", message)
        @test occursin("predecessor_receipt_sha256", message)
    end
end

# Regression for rejected manifest witness
# c7a67eda7c53008b23bb967ab749750ffbf18d47743c2234f445225fd82f29c2.
@testset "v3 resolved containment rejects symlinked child directories" begin
    for child in ("replica-a", "replica-b", "receipts")
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$child")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                ),
            )
            source = joinpath(bundle.bundle_path, child)
            external = joinpath(realpath(temporary), "external-$child")
            cp(source, external; force = true)
            rm(source; recursive = true)
            symlink(external, source)
            message = failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end
            @test occursin("symbolic-link descendant rejected", message)
            @test occursin(child, message)
        end
    end
end

# Regression for rejected manifest witness
# 60362f73774116e21427cc925e23fce56e4d121e74b3f4f0b3478585ca8e8b3a.
@testset "v3 recursive scalar types and typed loader failures" begin
    typed_mutations = [
        (
            "artifact",
            manifest -> manifest["artifact"]["manifest_id"] = 1,
        ),
        (
            "event",
            manifest -> manifest["event"][
                "official_publication_day_validated",
            ] = 0,
        ),
        (
            "capture",
            manifest -> manifest["capture"]["failed_attempt_count"] =
                false,
        ),
        (
            "operator",
            manifest -> manifest["operator_authorization"][
                "operator_network_execution_authorized",
            ] = 0,
        ),
        (
            "result",
            manifest -> manifest["result"]["success"] = 1,
        ),
        (
            "gates",
            manifest -> manifest["gates"]["origin_admissible"] = 0,
        ),
        (
            "storage",
            manifest -> manifest["storage"][
                "durable_external_copy_count",
            ] = false,
        ),
        (
            "object",
            manifest -> manifest["objects"][1]["redirect_count"] = false,
        ),
    ]
    for (name, mutate!) in typed_mutations
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-type-$name")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first",
            )
            manifest = deepcopy(bundle.manifest)
            mutate!(manifest)
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisition._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            error = try
                load_fixture_bundle(bundle.bundle_path)
                nothing
            catch caught
                caught
            end
            @test error isa RecurringAcquisitionError
            message = sprint(showerror, error)
            @test occursin("type differs", message) ||
                occursin("must be Bool", message) ||
                occursin("must be Int and not Bool", message)
        end
    end
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-coordinated-types")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first",
        )
        manifest = deepcopy(bundle.manifest)
        manifest["capture"]["failed_attempt_count"] = false
        manifest["operator_authorization"][
            "operator_network_execution_authorized",
        ] = 0
        manifest["result"]["success"] = 1
        manifest["gates"]["origin_admissible"] = 0
        manifest["storage"]["durable_external_copy_count"] = false
        manifest["objects"][1]["redirect_count"] = false
        manifest["artifact"]["manifest_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            manifest,
            "artifact",
            "manifest_sha256",
        )
        replace_manifest_triplicates!(bundle.bundle_path, manifest)
        message = failure_text() do
            load_fixture_bundle(bundle.bundle_path)
        end
        @test occursin("type differs", message) ||
            occursin("must be Bool", message) ||
            occursin("must be Int and not Bool", message)
    end
    mktempdir() do temporary
        output_root =
            joinpath(realpath(temporary), "raw-storage-receipt-type")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first",
        )
        manifest = deepcopy(bundle.manifest)
        storage_path =
            manifest["storage"]["local_storage_receipt_file"]
        storage = TOML.parsefile(
            joinpath(bundle.bundle_path, storage_path),
        )
        storage["durable_external_copy_count"] = false
        storage["artifact"]["receipt_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            storage,
            "artifact",
            "receipt_sha256",
        )
        replace_storage_triplicates!(
            bundle.bundle_path,
            storage_path,
            storage,
        )
        manifest["storage"]["local_storage_receipt_sha256"] =
            storage["artifact"]["receipt_sha256"]
        manifest["artifact"]["manifest_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            manifest,
            "artifact",
            "manifest_sha256",
        )
        replace_manifest_triplicates!(bundle.bundle_path, manifest)
        @test occursin(
            "must be Int and not Bool",
            failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end,
        )
    end
    for section in ("artifact", "event", "capture")
        mktempdir() do temporary
            output_root =
                joinpath(realpath(temporary), "raw-malformed-$section")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first",
            )
            manifest = deepcopy(bundle.manifest)
            manifest[section] = "MALFORMED_TOP_LEVEL_SECTION"
            if section != "artifact"
                manifest["artifact"]["manifest_sha256"] =
                    USEFFRRecurringAcquisition._semantic_sha256(
                    manifest,
                    "artifact",
                    "manifest_sha256",
                )
            end
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            error = try
                load_fixture_bundle(bundle.bundle_path)
                nothing
            catch caught
                caught
            end
            @test error isa RecurringAcquisitionError
            @test !occursin("KeyError", sprint(showerror, error))
        end
    end
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-malformed-toml")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first",
        )
        malformed = Vector{UInt8}(codeunits("[artifact\n"))
        for path in manifest_triplicate_paths(bundle.bundle_path)
            open(path, "w") do io
                write(io, malformed)
            end
        end
        error = try
            load_fixture_bundle(bundle.bundle_path)
            nothing
        catch caught
            caught
        end
        @test error isa RecurringAcquisitionError
        @test occursin("bundle validation", sprint(showerror, error))
    end
end

# This exercises the ordinary `synthetic_fixture=false` manifest-construction
# branch without making a network claim: captured response objects come from a
# marked hermetic fixture, and the resulting in-memory manifest is never
# installed as empirical evidence.
@testset "v3 built-in manifest constructor keeps provenance unauthenticated" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-built-in-template")
        fixture = capture_fixture(
            output_root,
            "2026-08-10",
            "first";
            responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            ),
        )
        authorization = dry_run_plan(
            "2026-08-10",
            "first";
            output_root,
        ).authorization
        paths = USEFFRRecurringAcquisition._canonical_paths(
            output_root,
            authorization,
        )
        specs = request_plan("2026-08-10", "first")
        objects = USEFFRRecurringAcquisition.CapturedResponse[]
        for record in fixture.manifest["objects"]
            body = USEFFRRecurringAcquisition._read_object(
                fixture.bundle_path,
                record,
            )
            push!(
                objects,
                USEFFRRecurringAcquisition._captured_response_from_manifest(
                    record,
                    body,
                ),
            )
        end
        storage = TOML.parsefile(
            joinpath(
                fixture.bundle_path,
                fixture.manifest["storage"][
                    "local_storage_receipt_file",
                ],
            ),
        )
        receipts = Dict(
            "rate" => fixture.rate_receipt,
            "volume" => fixture.volume_receipt,
        )
        evaluation = (
            result = deepcopy(fixture.manifest["result"]),
            receipts,
            pair = fixture.pair,
            blockers = filter(
                blocker ->
                blocker != USEFFRRecurringAcquisition.SYNTHETIC_BLOCKER,
                fixture.manifest["blockers"],
            ),
            row_identity = deepcopy(fixture.manifest["row_identity"]),
        )
        receipt_files = Dict(
            "rate" => fixture.manifest["result"]["rate_receipt_file"],
            "volume" =>
                fixture.manifest["result"]["volume_receipt_file"],
        )
        manifest = USEFFRRecurringAcquisition._build_manifest(
            paths,
            authorization,
            specs,
            objects,
            storage,
            evaluation,
            receipt_files,
            USEFFRRecurringAcquisition._source_bindings(),
            USEFFRRecurringAcquisition._operator_authorization(
                authorization,
                true,
            ),
            false,
        )
        capture = manifest["capture"]
        operator = manifest["operator_authorization"]
        @test capture["synthetic_test_fixture"] === false
        @test capture["transport_provenance"] ==
            USEFFRRecurringAcquisition.BUILTIN_TRANSPORT_PROVENANCE
        @test capture["transport_provenance_assertion_status"] ==
            "LOCAL_UNAUTHENTICATED_RUNTIME_ASSERTION"
        @test capture[
            "persisted_transport_provenance_authenticated",
        ] === false
        @test capture[
            "network_exchange_count_externally_witnessed",
        ] === false
        @test capture[
            "operator_authorization_externally_authenticated",
        ] === false
        @test capture["network_exchange_count"] ==
            "NOT_INDEPENDENTLY_WITNESSED"
        @test capture["attempted_network_exchange_count"] ==
            "NOT_INDEPENDENTLY_WITNESSED"
        @test operator[
            "persisted_transport_provenance_authenticated",
        ] === false
        @test operator[
            "network_exchange_count_externally_witnessed",
        ] === false
        @test operator[
            "operator_authorization_externally_authenticated",
        ] === false
        @test all(value === false for value in values(manifest["gates"]))
        @test all(
            blocker in manifest["blockers"] for blocker in (
                    "PERSISTED_TRANSPORT_PROVENANCE_NOT_EXTERNALLY_AUTHENTICATED",
                    "NETWORK_EXCHANGE_COUNT_NOT_INDEPENDENTLY_WITNESSED",
                    "OPERATOR_AUTHORIZATION_LOCALLY_SELF_REPORTED_NOT_EXTERNALLY_AUTHENTICATED",
                )
        )
    end
end

# Regression for rejected manifest witness
# 3768e1667fd29509fc2e7f29b0283a8a468247f3e828a87b4bd9e85a0d1852ac.
@testset "v3 marker-stripping limitation remains permanently nonadmitting" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-marker-rewrite")
        bundle = capture_fixture(
            output_root,
            "2026-08-10",
            "first";
            responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            ),
        )
        @test_throws RecurringAcquisitionError load_and_validate_bundle(
            bundle.bundle_path,
        )
        manifest = deepcopy(bundle.manifest)
        manifest["event"]["campaign_id"] =
            USEFFRRecurringAcquisition.CAMPAIGN_ID
        manifest["capture"]["transport_policy"] =
            USEFFRRecurringAcquisition.BUILTIN_TRANSPORT_POLICY
        manifest["capture"]["transport_provenance"] =
            USEFFRRecurringAcquisition.BUILTIN_TRANSPORT_PROVENANCE
        manifest["capture"]["synthetic_test_fixture"] = false
        manifest["operator_authorization"] =
            USEFFRRecurringAcquisition._operator_authorization(
            bundle.manifest["event"]["publication_date"] ==
                "2026-08-10" ?
                dry_run_plan(
                    "2026-08-10",
                    "first";
                    output_root,
                ).authorization :
                error("fixture publication date changed"),
            true,
        )
        filter!(
            blocker ->
            blocker !=
                USEFFRRecurringAcquisition.SYNTHETIC_BLOCKER,
            manifest["blockers"],
        )
        manifest["artifact"]["manifest_sha256"] =
            USEFFRRecurringAcquisition._semantic_sha256(
            manifest,
            "artifact",
            "manifest_sha256",
        )
        replace_manifest_triplicates!(bundle.bundle_path, manifest)
        rewritten = load_and_validate_bundle(bundle.bundle_path)
        @test rewritten.manifest["capture"][
            "transport_provenance_assertion_status",
        ] == "LOCAL_UNAUTHENTICATED_RUNTIME_ASSERTION"
        @test rewritten.manifest["capture"][
            "persisted_transport_provenance_authenticated",
        ] === false
        @test rewritten.manifest["capture"][
            "network_exchange_count_externally_witnessed",
        ] === false
        @test rewritten.manifest["operator_authorization"][
            "operator_authorization_externally_authenticated",
        ] === false
        @test all(value === false for value in values(rewritten.manifest["gates"]))
        @test all(
            blocker in rewritten.manifest["blockers"] for blocker in (
                    "PERSISTED_TRANSPORT_PROVENANCE_NOT_EXTERNALLY_AUTHENTICATED",
                    "NETWORK_EXCHANGE_COUNT_NOT_INDEPENDENTLY_WITNESSED",
                    "OPERATOR_AUTHORIZATION_LOCALLY_SELF_REPORTED_NOT_EXTERNALLY_AUTHENTICATED",
                )
        )
        campaign = CampaignControl.evaluate_campaign(
            CampaignControl.load_schedule(),
            [CampaignControl.validated_bundle_manifest(rewritten)],
        )
        @test campaign.accepted_slot_count == 1
        @test campaign.origin_admissible === false
    end
end

const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."),
)
const US_PROJECT = joinpath(REPOSITORY_ROOT, "scripts", "us")
const RECURRING_CLI =
    joinpath(@__DIR__, "capture_effr_recurring.jl")

function run_cli(arguments; directory = REPOSITORY_ROOT)
    command = Cmd(
        `$(Base.julia_cmd()) --startup-file=no --project=$US_PROJECT $RECURRING_CLI $arguments`;
        dir = directory,
    )
    stdout_buffer = IOBuffer()
    stderr_buffer = IOBuffer()
    process = run(
        pipeline(
            ignorestatus(command);
            stdout = stdout_buffer,
            stderr = stderr_buffer,
        ),
    )
    return (
        exitcode = process.exitcode,
        stdout = String(take!(stdout_buffer)),
        stderr = String(take!(stderr_buffer)),
    )
end

@testset "CLI is dry by default and has strict parsing and exits" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "cli-must-not-exist")
        result = run_cli(
            [
                "--publication-date",
                "2026-08-10",
                "--phase",
                "first",
                "--output-root",
                output_root,
            ];
            directory = "/tmp",
        )
        @test result.exitcode == 0
        @test occursin("Dry run: true", result.stdout)
        @test occursin("Request count: 6", result.stdout)
        @test occursin("Network requests made: 0", result.stdout)
        @test occursin("Filesystem writes made: 0", result.stdout)
        @test !ispath(output_root)
    end
    help = run_cli(["--help"])
    @test help.exitcode == 0
    @test occursin("--execute-live", help.stdout)
    @test occursin("separate bounded operator authorization", help.stdout)
    @test occursin("exactly six built-in direct GETs", help.stdout)
    unknown = run_cli(["--unknown"])
    @test unknown.exitcode == 2
    @test occursin("unknown argument", unknown.stderr)
    duplicate = run_cli(
        [
            "--publication-date",
            "2026-08-10",
            "--publication-date",
            "2026-08-11",
            "--phase",
            "first",
            "--output-root",
            "/tmp/not-used",
        ],
    )
    @test duplicate.exitcode == 2
    @test occursin("duplicate --publication-date", duplicate.stderr)
    invalid_phase = run_cli(
        [
            "--publication-date",
            "2026-08-10",
            "--phase",
            "other",
            "--output-root",
            "/tmp/not-used",
        ],
    )
    @test invalid_phase.exitcode == 1
    @test occursin("must be first or revision-check", invalid_phase.stderr)
    day_zero_live = run_cli(
        [
            "--publication-date",
            "2026-08-07",
            "--phase",
            "first",
            "--output-root",
            "/tmp/not-used",
            "--execute-live",
        ],
    )
    @test day_zero_live.exitcode == 1
    @test occursin("immutable day-zero runner", day_zero_live.stderr)
end
