using Dates
using JSON
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USEFFRRecurringAcquisitionRestartV4.jl"))
using .USEFFRRecurringAcquisitionRestartV4

include(
    joinpath(
        @__DIR__,
        "..",
        "recurring_acquisition",
        "USEFFRRecurringAcquisition.jl",
    ),
)
const LegacyRecurringV3 = USEFFRRecurringAcquisition

const RestartControl =
    USEFFRRecurringAcquisitionRestartV4.USEFFRCampaignRestartV2

function test_plan(publication_date, phase; output_root)
    synthetic =
        abspath(String(output_root)) !=
        USEFFRRecurringAcquisitionRestartV4.RESTART_OUTPUT_ROOT
    return USEFFRRecurringAcquisitionRestartV4.dry_run_plan(
        publication_date,
        phase;
        output_root,
        synthetic_test_fixture = synthetic,
    )
end

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
        footnote_id = :absent,
        footnote_alias = :absent,
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
    footnote_id != :absent && (row["footnoteId"] = footnote_id)
    footnote_alias != :absent && (row["footnote"] = footnote_alias)
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
        footnote_id = :absent,
        rate_footnote_id = footnote_id,
        volume_footnote_id = footnote_id,
        rate_body = nothing,
        volume_body = nothing,
        status_overrides = Dict{String, Int}(),
        final_url_overrides = Dict{String, String}(),
        content_type_overrides = Dict{String, String}(),
        content_encoding_overrides = Dict{String, String}(),
        redirect_count_overrides = Dict{String, Int}(),
        proxy_used_overrides = Dict{String, Bool}(),
    )
    plan = test_plan(
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
                footnote_id = rate_footnote_id,
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
                footnote_id = volume_footnote_id,
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
    plan = test_plan(
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
        push!(values, start + Second(index) + Millisecond(100))
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
    return acquire_restart_recurring(
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
    plan = test_plan(
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

function adjudicate_fixture(bundle; binding_kwargs...)
    preliminary = evaluate_restart_result(
        bundle.bundle_path;
        allow_synthetic_test_fixture = true,
    )
    revision_record =
        USEFFRRecurringAcquisitionRestartV4._manifest_object(
        bundle.manifest,
        "volume_response",
    )
    created_at = USEFFRRecurringAcquisitionRestartV4._manifest_timestamp(
        revision_record["response_metadata_observed_at_utc"],
        "test decision binding",
    )
    binding = RestartDecisionBinding(
        decision_id =
            "synthetic-restart-v4-$(bundle.manifest["event"]["publication_date"])",
        created_at_utc = created_at,
        predecessor_observation_sha256 =
            preliminary.morning_observation_sha256,
        predecessor_decision_sha256 = repeat("a", 64),
        superseded_capture_manifest_sha256 = repeat("b", 64);
        binding_kwargs...,
    )
    evaluated = evaluate_restart_result(
        bundle.bundle_path;
        decision_binding = binding,
        allow_synthetic_test_fixture = true,
    )
    return (; preliminary, binding, evaluated)
end

function constant_clock(value)
    return () -> value
end

function journal_path(output_root, publication_date, phase)
    return test_plan(
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
    bytes = USEFFRRecurringAcquisitionRestartV4._toml_bytes(manifest)
    for path in manifest_triplicate_paths(bundle)
        open(path, "w") do io
            write(io, bytes)
        end
    end
    return nothing
end

function replace_storage_triplicates!(bundle, relative_path, storage)
    bytes = USEFFRRecurringAcquisitionRestartV4._toml_bytes(storage)
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
    bytes = USEFFRRecurringAcquisitionRestartV4._toml_bytes(receipt)
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
        USEFFRRecurringAcquisitionRestartV4.ReceiptContract.canonical_receipt_sha256(
        receipt,
    )
    if require_contract_valid
        USEFFRRecurringAcquisitionRestartV4.ReceiptContract.validate_receipt(
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
        USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
    plan = test_plan("2026-08-10", "first"; output_root = root)
    @test plan.dry_run === true
    @test plan.network_requests_made == 0
    @test plan.filesystem_writes_made == 0
    @test !ispath(root)
    campaign_plan =
        USEFFRRecurringAcquisitionRestartV4.dry_run_plan(
        "2026-08-10",
        "first",
    )
    @test dirname(dirname(dirname(campaign_plan.final_path))) ==
        USEFFRRecurringAcquisitionRestartV4.RESTART_OUTPUT_ROOT
    @test campaign_plan.campaign_eligible === true
    @test_throws RestartRecurringAcquisitionError USEFFRRecurringAcquisitionRestartV4.dry_run_plan(
        "2026-08-10",
        "first";
        output_root = root,
    )
    @test_throws RestartRecurringAcquisitionError USEFFRRecurringAcquisitionRestartV4.dry_run_plan(
        "2026-08-10",
        "first";
        synthetic_test_fixture = true,
    )
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
    @test plan.source_bindings.restart_control_file_sha256 ==
        "5e0873ec7c427c377386bf9bd33c782f39a4735391011cffc7e24a1c67aa7155"
    @test plan.source_bindings.restart_schedule_file_sha256 ==
        "670e5b02b740e9195b768d22e002ee3de49f037efb5f0b1228f0c9482e3e0136"
    @test plan.source_bindings.restart_schedule_content_sha256 ==
        "cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b"
    @test all(value === false for value in values(plan.gates))
    @test plan.operator_authorization[
        "operator_network_execution_authorized",
    ] === false
    @test plan.operator_authorization[
        "operator_raw_bundle_write_authorized",
    ] === false
    @test plan.operator_authorization[
        "restart_schedule_network_execution_authorized",
    ] === false
    @test plan.operator_authorization[
        "restart_schedule_raw_data_write_authorized",
    ] === false
    @test plan.operator_authorization[
        "separate_from_restart_schedule_governance_gates",
    ] === true
    @test plan.operator_authorization["downloader_invocation_ceiling"] == 6
    @test plan.operator_authorization["network_exchange_count_ceiling"] ==
        "NOT_INDEPENDENTLY_WITNESSED"
    @test canonical_transaction_id("2026-08-10", "revision-check") ==
        "effr-20260810-revision-1830z"
    revision =
        test_plan("2026-08-10", "revision-check"; output_root = root)
    @test revision.predecessor_path == plan.final_path
    @test revision.authorization.window_start_utc ==
        DateTime(2026, 8, 10, 18, 30)
    @test_throws RestartRecurringAcquisitionError test_plan(
        "2026-08-07",
        "first";
        output_root = root,
    )
    @test_throws RestartRecurringAcquisitionError test_plan(
        "2026-08-08",
        "first";
        output_root = root,
    )
    @test_throws RestartRecurringAcquisitionError test_plan(
        "2026-10-30",
        "revision-check";
        output_root = root,
    )
    @test_throws RestartRecurringAcquisitionError canonical_transaction_id(
        "2026-08-10",
        1,
    )
end

@testset "restart v4 derives every campaign field from all 115 schedule rows" begin
    schedule = RestartControl.load_restart_schedule()
    @test schedule["artifact"]["content_sha256"] ==
        "cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b"
    @test schedule["policy"]["output_root"] ==
        "data/us/raw/forecasting/effr/prospective/2026q3_restart_v2"
    @test schedule["claim_ceiling"]["unchanged_revision_status"] ==
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
    @test length(schedule["slots"]) == 115
    for (index, row) in enumerate(schedule["slots"])
        authorization =
            USEFFRRecurringAcquisitionRestartV4._authorization(
            schedule,
            row["publication_date"],
            row["phase"],
        )
        paths = USEFFRRecurringAcquisitionRestartV4._canonical_paths(
            USEFFRRecurringAcquisitionRestartV4.RESTART_OUTPUT_ROOT,
            authorization,
        )
        requests =
            USEFFRRecurringAcquisitionRestartV4._request_specs(authorization)
        @test authorization.publication_date == Date(row["publication_date"])
        @test authorization.effective_date == Date(row["effective_date"])
        @test authorization.window_start_utc ==
            DateTime(chop(row["scheduled_at_utc"]; tail = 1))
        @test authorization.window_deadline_utc ==
            DateTime(chop(row["deadline_at_utc"]; tail = 1))
        @test authorization.transaction_id == row["transaction_id"]
        @test authorization.state_class_candidate == row["state_class"]
        @test authorization.network_execution_authorized === false
        @test authorization.raw_data_write_authorized === false
        @test paths.final_path ==
            normpath(
            joinpath(
                USEFFRRecurringAcquisitionRestartV4.REPOSITORY_ROOT,
                row["bundle_path"],
            ),
        )
        @test paths.journal_path ==
            normpath(
            joinpath(
                USEFFRRecurringAcquisitionRestartV4.REPOSITORY_ROOT,
                row["journal_path"],
            ),
        )
        if row["phase"] == "revision-check"
            @test paths.predecessor_path == normpath(
                joinpath(
                    USEFFRRecurringAcquisitionRestartV4.REPOSITORY_ROOT,
                    row["predecessor_bundle_path"],
                ),
            )
        else
            @test row["predecessor_bundle_path"] == "NOT_APPLICABLE"
        end
        @test requests[1].canonical_query == row["rate_query"]
        @test requests[2].canonical_query == row["volume_query"]
        @test requests[1].requested_url ==
            "https://markets.newyorkfed.org/api/rates/all/search.json?$(row["rate_query"])"
        @test requests[2].requested_url ==
            "https://markets.newyorkfed.org/api/rates/all/search.json?$(row["volume_query"])"
        @test authorization.transaction_id ==
            RestartControl.planned_slot(
            schedule,
            row["publication_date"],
            row["phase"],
        ).transaction_id
        @test index == row["sequence"]
    end
    @test_throws RestartRecurringAcquisitionError USEFFRRecurringAcquisitionRestartV4._authorization(
        schedule,
        "2026-08-07",
        "first",
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
        message = failure_text() do
            evaluate_restart_result(
                reloaded.bundle_path;
                allow_synthetic_test_fixture = true,
            )
        end
        @test occursin("requires the restart revision-check bundle", message)
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
        message = failure_text() do
            evaluate_restart_result(
                validated.bundle_path;
                allow_synthetic_test_fixture = true,
            )
        end
        @test occursin("requires the restart revision-check bundle", message)
    end
end

@testset "restart v4 manifest binding is closed and cannot validate as v3" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-binding-baseline")
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
        binding = bundle.manifest["contract_binding"]
        @test binding["restart_schedule_id"] ==
            "beforeit-us-effr-2026q3-prospective-restart-20260810.v2"
        @test binding["restart_control_file_sha256"] ==
            "5e0873ec7c427c377386bf9bd33c782f39a4735391011cffc7e24a1c67aa7155"
        @test binding["restart_schedule_file_sha256"] ==
            "670e5b02b740e9195b768d22e002ee3de49f037efb5f0b1228f0c9482e3e0136"
        @test binding["restart_schedule_content_sha256"] ==
            "cae7f463b752ff2c60c78751ca0186712a53fb1732c7970e8bb0e4368d9e477b"
        @test binding["recurring_v3_source_base_module_sha256"] ==
            "3685e0c0ca3d440bdf2816d3c3bc229656d4a2339d6009b34f2c754c4a7051de"
        @test binding["recurring_v3_source_base_cli_sha256"] ==
            "e2f293dd77da818c5fd0ee64e8bb520a162f62e805c17fdc6cf6131f6db3800f"
        @test binding["recurring_v3_source_base_test_sha256"] ==
            "256eac940dace2e749efb98be33e9ba059f21883da5b6d0bf92fdac2beb7e41b"
        @test binding["recurring_v3_source_base_readme_sha256"] ==
            "052d02b3117037d86830de50783f43f782907ae84824fa7507acd36b70784d02"
        @test binding["source_base_reuse_is_not_behavioral_attestation"] ===
            true
        @test binding["observed_state_v3_contract_file_sha256"] ==
            "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6"
        @test binding["observed_state_v3_protocol_file_sha256"] ==
            "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716"
        @test binding["observed_state_v3_protocol_content_sha256"] ==
            "33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c"
        @test binding["observed_state_v3_role"] ==
            "OFFLINE_ADJUDICATION_ONLY_NOT_ACQUISITION_AUTHORITY"
        @test binding["legacy_schedule_authorizes_restart_acquisition"] ===
            false
        @test binding["raw_capture_status_is_observed_state_decision"] ===
            false
        @test binding["accepted_schedule_runner_restart_binding_complete"] ===
            false
        @test binding[
            "operator_flag_does_not_relabel_schedule_binding_complete",
        ] === true
        @test occursin(
            "schema_version",
            failure_text() do
                LegacyRecurringV3.load_and_validate_bundle(
                    bundle.bundle_path;
                    allow_synthetic_test_fixture = true,
                )
            end,
        )
    end

    mutations = [
        (
            "restart-schedule-id",
            manifest -> manifest["contract_binding"]["restart_schedule_id"] =
                "beforeit-us-effr-2026q3-prospective-campaign.v1",
        ),
        (
            "restart-control-hash",
            manifest -> manifest["contract_binding"][
                "restart_control_file_sha256",
            ] = repeat("0", 64),
        ),
        (
            "restart-schedule-file-hash",
            manifest -> manifest["contract_binding"][
                "restart_schedule_file_sha256",
            ] = repeat("1", 64),
        ),
        (
            "restart-schedule-semantic-hash",
            manifest -> manifest["contract_binding"][
                "restart_schedule_content_sha256",
            ] = repeat("2", 64),
        ),
        (
            "v3-base-module-hash",
            manifest -> manifest["contract_binding"][
                "recurring_v3_source_base_module_sha256",
            ] = repeat("3", 64),
        ),
        (
            "v3-base-behavior-attestation",
            manifest -> manifest["contract_binding"][
                "source_base_reuse_is_not_behavioral_attestation",
            ] = false,
        ),
        (
            "observed-state-module-hash",
            manifest -> manifest["contract_binding"][
                "observed_state_v3_contract_file_sha256",
            ] = repeat("5", 64),
        ),
        (
            "observed-state-role",
            manifest -> manifest["contract_binding"][
                "observed_state_v3_role",
            ] = "ACQUISITION_AUTHORITY",
        ),
        (
            "legacy-schedule-authority",
            manifest -> manifest["contract_binding"][
                "legacy_schedule_authorizes_restart_acquisition",
            ] = true,
        ),
        (
            "raw-status-relabel",
            manifest -> manifest["contract_binding"][
                "raw_capture_status_is_observed_state_decision",
            ] = true,
        ),
        (
            "schedule-runner-binding-relabel",
            manifest -> manifest["contract_binding"][
                "accepted_schedule_runner_restart_binding_complete",
            ] = true,
        ),
        (
            "old-v1-binding-alias",
            manifest -> manifest["contract_binding"][
                "campaign_schedule_content_sha256",
            ] = repeat("4", 64),
        ),
        (
            "old-v1-campaign-id",
            manifest -> manifest["event"]["campaign_id"] =
                "frbny_effr_daily_first_state_and_revision_check",
        ),
        (
            "legacy-unchanged-alias",
            manifest -> manifest["result"]["status"] =
                "BYTE_IDENTICAL_NO_REVISION_RECEIPT_CREATED",
        ),
        (
            "observed-claim-as-raw-status",
            manifest -> manifest["result"]["status"] =
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE",
        ),
    ]
    for (name, mutate!) in mutations
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$name")
            bundle = capture_fixture(output_root, "2026-08-10", "first")
            manifest = deepcopy(bundle.manifest)
            mutate!(manifest)
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            message = failure_text() do
                load_fixture_bundle(bundle.bundle_path)
            end
            @test message != "NO_ERROR"
        end
    end
end

@testset "restart v4 exact integer footnoteId and pair symmetry" begin
    for identifier in 1:3
        mktempdir() do temporary
            output_root =
                joinpath(realpath(temporary), "raw-valid-$identifier")
            bundle = capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses = fixture_responses(
                    "2026-08-10",
                    "first";
                    current_state = false,
                    footnote_id = identifier,
                ),
            )
            token = string(identifier)
            @test all(
                row["normalized_footnote_token"] == token for
                    row in bundle.manifest["row_identity"]
            )
            @test bundle.rate_receipt["raw_fields"]["footnote"] == token
            @test bundle.volume_receipt["raw_fields"]["footnote"] == token
            reloaded = load_fixture_bundle(bundle.bundle_path)
            @test reloaded.rate_receipt["raw_fields"]["footnote"] == token
            @test reloaded.volume_receipt["raw_fields"]["footnote"] == token
        end
    end

    effective = Date(2026, 8, 7)
    integer_body = effr_body(
        effective,
        "rate";
        footnote_id = 1,
    )
    exponent_text = replace(
        String(integer_body),
        r"\"footnoteId\":1(?=[,}])" => "\"footnoteId\":1e0",
    )
    @test exponent_text != String(integer_body)
    invalid_cases = [
        (
            "alias",
            effr_body(effective, "rate"; footnote_alias = 1),
            "unknown fields: footnote",
        ),
        (
            "string",
            effr_body(effective, "rate"; footnote_id = "1"),
            "must be an exact raw JSON integer",
        ),
        (
            "decimal",
            effr_body(effective, "rate"; footnote_id = 1.0),
            "must be an exact raw JSON integer",
        ),
        (
            "exponent",
            Vector{UInt8}(codeunits(exponent_text)),
            "must be an exact raw JSON integer",
        ),
        (
            "boolean",
            effr_body(effective, "rate"; footnote_id = true),
            "must be an exact raw JSON integer",
        ),
        (
            "unknown",
            effr_body(effective, "rate"; footnote_id = 4),
            "outside the closed integer vocabulary",
        ),
    ]
    for (name, rate_body, expected) in invalid_cases
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$name")
            calls = String[]
            message = failure_text() do
                capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses = fixture_responses(
                        "2026-08-10",
                        "first";
                        rate_body,
                    ),
                    calls,
                )
            end
            @test occursin(expected, message)
            @test length(calls) == 6
            journal = journal_path(output_root, "2026-08-10", "first")
            @test isfile(joinpath(journal, "capture-failure.toml"))
            @test length(
                filter(
                    file -> startswith(file, "raw-sha256-"),
                    readdir(joinpath(journal, "replica-a")),
                ),
            ) == 6
        end
    end

    for (name, rate_footnote_id, volume_footnote_id) in (
            ("presence-mismatch", 1, :absent),
            ("value-mismatch", 1, 2),
        )
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-$name")
            calls = String[]
            message = failure_text() do
                capture_fixture(
                    output_root,
                    "2026-08-10",
                    "first";
                    responses = fixture_responses(
                        "2026-08-10",
                        "first";
                        rate_footnote_id,
                        volume_footnote_id,
                    ),
                    calls,
                )
            end
            @test occursin("footnoteId presence/value differs", message)
            @test length(calls) == 6
            journal = journal_path(output_root, "2026-08-10", "first")
            @test isfile(joinpath(journal, "capture-failure.toml"))
            @test length(
                filter(
                    file -> startswith(file, "raw-sha256-"),
                    readdir(joinpath(journal, "replica-b")),
                ),
            ) == 6
        end
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
                "RAW_BYTE_IDENTICAL_EMPTY_REVISION_TOKEN_NONADMITTING_CAPTURE_PRESERVED"
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
            message = failure_text() do
                evaluate_restart_result(
                    revision.bundle_path;
                    allow_synthetic_test_fixture = true,
                )
            end
            @test occursin("SCHEMA_DRIFT_CURRENT_STATE_PRESENT", message)
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
                "RAW_BYTE_IDENTICAL_EMPTY_REVISION_TOKEN_NONADMITTING_CAPTURE_PRESERVED"
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
                    test_plan(
                        "2026-08-10",
                        "revision-check";
                        output_root,
                    ).final_path,
                )
            end
        end
        plan = test_plan(
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
            USEFFRRecurringAcquisitionRestartV4._normalize_download(
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
            USEFFRRecurringAcquisitionRestartV4._evaluate_capture(
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

@testset "observed-state-v3 alone adjudicates restart transitions" begin
    @testset "byte-identical absent-field pair selects exact claim only after binding" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            responses = fixture_responses("2026-08-10", "first")
            capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses,
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = deepcopy(responses),
            )
            @test revision.manifest["result"]["status"] ==
                "RAW_BYTE_IDENTICAL_EMPTY_REVISION_TOKEN_NONADMITTING_CAPTURE_PRESERVED"
            preliminary = evaluate_restart_result(
                revision.bundle_path;
                allow_synthetic_test_fixture = true,
            )
            @test preliminary.adjudication_status ==
                "DECISION_BINDING_REQUIRED"
            @test preliminary.endpoint_state_claim == "NOT_ADJUDICATED"
            @test preliminary.exact_unchanged_claim_selected === false
            @test preliminary.raw_capture_status_is_observed_state_decision ===
                false
            @test preliminary.synthetic_test_fixture === true
            @test preliminary.synthetic_fixture_permanently_nonempirical ===
                true
            @test preliminary.legacy_schedule_authorizes_restart_acquisition ===
                false
            @test preliminary.observed_state_role ==
                "OFFLINE_ADJUDICATION_ONLY_NOT_ACQUISITION_AUTHORITY"
            @test preliminary.observed_state_contract_file_sha256 ==
                "3b3040245dd04b800bcdb25d1af0f57c211bf29ce3462f7134418f0263f1f4d6"
            @test preliminary.observed_state_protocol_file_sha256 ==
                "d09e7d378b22a36a364cd4b08e7f0c42d7a3804c473e8332a22fbe4d9fc20716"
            @test preliminary.observed_state_protocol_content_sha256 ==
                "33eb8eba8a6399568c0890d86d555cb5177659d62c098522098ca5d6ce21952c"
            @test "OBSERVED_STATE_V3_DECISION_BINDING_REQUIRED" in
                preliminary.blockers

            adjudicated = adjudicate_fixture(revision)
            evaluation = adjudicated.evaluated
            @test evaluation.adjudication_status ==
                "OBSERVED_STATE_V3_ADJUDICATED"
            @test evaluation.observed_state_outcome ==
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
            @test evaluation.endpoint_state_claim ==
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
            @test evaluation.exact_unchanged_claim_selected === true
            @test evaluation.observed_state_decision["decision"]["outcome"] ==
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
            @test evaluation.observed_state_decision["decision"][
                "no_later_revision_claimed",
            ] === false
            @test evaluation.observed_state_decision["decision"][
                "final_state_for_day_claimed",
            ] === false
            @test evaluation.no_later_same_day_revision_claimed === false
            @test evaluation.final_state_for_day_claimed === false
            @test evaluation.decision_binding_provenance_authenticated === false
            @test evaluation.empirical_evidence_allowed === false
            @test evaluation.origin_admissible === false
            @test evaluation.accuracy_evaluation_allowed === false
            @test all(value === false for value in values(evaluation.gates))

            bad_binding = RestartDecisionBinding(
                decision_id = "synthetic-restart-v4-bad-predecessor",
                created_at_utc = adjudicated.binding.created_at_utc,
                predecessor_observation_sha256 = repeat("f", 64),
                predecessor_decision_sha256 = repeat("a", 64),
                superseded_capture_manifest_sha256 = repeat("b", 64),
            )
            message = failure_text() do
                evaluate_restart_result(
                    revision.bundle_path;
                    decision_binding = bad_binding,
                    allow_synthetic_test_fixture = true,
                )
            end
            @test occursin("PREDECESSOR_MISMATCH", message)

            relabeled = deepcopy(revision.manifest)
            relabeled["result"]["status"] =
                "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
            relabeled["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
                relabeled,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(
                revision.bundle_path,
                relabeled,
            )
            message = failure_text() do
                load_fixture_bundle(revision.bundle_path)
            end
            @test occursin(
                "observed-state-v3 claim is forbidden as a raw acquisition status",
                message,
            )
        end
    end

    @testset "strict exact-rational marked-revision policy is replayed" begin
        for (rate, expected_outcome, expected_claim) in (
                (
                    3.62,
                    "QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT",
                    "RAW_R_TOKEN_LACKS_STRICTLY_GREATER_THAN_ONE_BASIS_POINT_RATE_CHANGE",
                ),
                (
                    3.63,
                    "MARKED_SAME_DAY_REVISION_OBSERVED",
                    "MARKED_SAME_DAY_REVISION_OBSERVED",
                ),
            )
            mktempdir() do temporary
                output_root = joinpath(realpath(temporary), "raw-$rate")
                capture_fixture(output_root, "2026-08-10", "first")
                revision = capture_fixture(
                    output_root,
                    "2026-08-10",
                    "revision-check";
                    responses = fixture_responses(
                        "2026-08-10",
                        "revision-check";
                        revision = "r",
                        rate,
                        volume = 113.0,
                    ),
                )
                @test revision.manifest["result"]["status"] ==
                    "RAW_CAPTURE_COMPLETED_NONADMITTING_ONE_DATE_CONTRACT_INCOMPATIBLE"
                evaluation = adjudicate_fixture(revision).evaluated
                @test evaluation.observed_state_outcome == expected_outcome
                @test evaluation.endpoint_state_claim == expected_claim
                @test evaluation.exact_unchanged_claim_selected === false
                @test all(value === false for value in values(evaluation.gates))
            end
        end
    end

    @testset "raw-preservable v3 schema and timestamp drift is quarantined" begin
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-current-state")
            responses = fixture_responses(
                "2026-08-10",
                "first";
                current_state = false,
            )
            capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses,
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = deepcopy(responses),
            )
            message = failure_text() do
                evaluate_restart_result(
                    revision.bundle_path;
                    allow_synthetic_test_fixture = true,
                )
            end
            @test occursin("SCHEMA_DRIFT_CURRENT_STATE_PRESENT", message)
        end

        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-unknown-row")
            effective = Date(2026, 8, 7)
            rate_document = JSON.parse(String(effr_body(effective, "rate")))
            volume_document =
                JSON.parse(String(effr_body(effective, "volume")))
            push!(rate_document["refRates"], Dict("type" => "ALIEN"))
            push!(volume_document["refRates"], Dict("type" => "ALIEN"))
            responses = fixture_responses(
                "2026-08-10",
                "first";
                rate_body = Vector{UInt8}(codeunits(JSON.json(rate_document))),
                volume_body =
                    Vector{UInt8}(codeunits(JSON.json(volume_document))),
            )
            capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses,
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = deepcopy(responses),
            )
            message = failure_text() do
                evaluate_restart_result(
                    revision.bundle_path;
                    allow_synthetic_test_fixture = true,
                )
            end
            @test occursin("UNKNOWN_ROW_TYPE", message)
        end

        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw-equal-times")
            first_plan =
                test_plan("2026-08-10", "first"; output_root)
            responses = fixture_responses("2026-08-10", "first")
            capture_fixture(
                output_root,
                "2026-08-10",
                "first";
                responses,
                clock = constant_clock(
                    first_plan.authorization.window_start_utc,
                ),
            )
            revision_plan = test_plan(
                "2026-08-10",
                "revision-check";
                output_root,
            )
            revision = capture_fixture(
                output_root,
                "2026-08-10",
                "revision-check";
                responses = deepcopy(responses),
                clock = constant_clock(
                    revision_plan.authorization.window_start_utc,
                ),
            )
            message = failure_text() do
                evaluate_restart_result(
                    revision.bundle_path;
                    allow_synthetic_test_fixture = true,
                )
            end
            @test occursin("CAPTURE_WINDOW_VIOLATION", message)
        end
    end
end

@testset "clock boundary, transport, and crash journal adversaries" begin
    @testset "capture window is closed and boundary-inclusive" begin
        for boundary in ("start", "deadline")
            mktempdir() do temporary
                output_root = joinpath(realpath(temporary), "raw")
                plan = test_plan(
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
                acquire_restart_recurring(
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
            @test occursin(
                "outside the schedule-derived closed UTC window",
                message,
            )
            @test isempty(calls)
            @test !ispath(output_root)
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            plan = test_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            values = [
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
                acquire_restart_recurring(
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
            @test occursin("request was not issued", message)
            @test isempty(calls)
            @test isfile(
                joinpath(plan.journal_path, "capture-failure.toml"),
            )
            failure = TOML.parsefile(
                joinpath(plan.journal_path, "capture-failure.toml"),
            )
            @test failure["downloader_invoked"] === false
            @test failure["request_started_at_utc"] ==
                "NOT_OBSERVED_REQUEST_NOT_ISSUED"
            @test isempty(
                readdir(joinpath(plan.journal_path, "attempts")),
            )
            @test isempty(
                filter(
                    name -> startswith(name, "raw-sha256-"),
                    readdir(joinpath(plan.journal_path, "replica-a")),
                ),
            )
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            plan = test_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            start = plan.authorization.window_start_utc
            values = [
                start,
                start + Second(1),
                plan.authorization.window_deadline_utc + Millisecond(1),
            ]
            cursor = Ref(0)
            clock = () -> begin
                cursor[] += 1
                values[min(cursor[], length(values))]
            end
            calls = String[]
            message = failure_text() do
                acquire_restart_recurring(
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
            @test occursin("request was not issued", message)
            @test isempty(calls)
            journal = plan.journal_path
            attempts = sort!(readdir(joinpath(journal, "attempts")))
            @test attempts == [
                "0001-rate_response-prepared.toml",
            ]
            prepared = TOML.parsefile(
                joinpath(journal, "attempts", only(attempts)),
            )
            @test prepared["state"] == "prepared"
            @test prepared["fields"]["request_start_pending"] === true
            @test prepared["fields"]["written_before_request"] === true
            @test !haskey(
                prepared["fields"],
                "request_started_at_utc",
            )
            failure = TOML.parsefile(
                joinpath(journal, "capture-failure.toml"),
            )
            @test failure["attempt_index"] == 1
            @test failure["object_id"] == "rate_response"
            @test failure["downloader_invoked"] === false
            @test failure["request_started_at_utc"] ==
                "NOT_OBSERVED_REQUEST_NOT_ISSUED"
            @test isempty(
                filter(
                    name -> startswith(name, "raw-sha256-"),
                    readdir(joinpath(journal, "replica-a")),
                ),
            )
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            plan = test_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            start = plan.authorization.window_start_utc
            values = [
                start,
                start + Second(1),
                start + Second(1) + Millisecond(100),
                start + Second(1) + Millisecond(250),
                plan.authorization.window_deadline_utc + Millisecond(1),
            ]
            cursor = Ref(0)
            clock = () -> begin
                cursor[] += 1
                values[min(cursor[], length(values))]
            end
            calls = String[]
            message = failure_text() do
                acquire_restart_recurring(
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
            @test occursin("request was not issued", message)
            @test calls == ["rate_response"]
            @test isfile(
                joinpath(plan.journal_path, "capture-failure.toml"),
            )
            @test length(
                filter(
                    name -> startswith(name, "raw-sha256-"),
                    readdir(joinpath(plan.journal_path, "replica-a")),
                ),
            ) == 1
            @test isempty(
                filter(
                    name -> occursin("02-volume_response", name),
                    readdir(joinpath(plan.journal_path, "attempts")),
                ),
            )
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            plan = test_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            start = plan.authorization.window_start_utc
            values = [
                start,
                start + Second(1),
                start + Second(1) + Millisecond(100),
                start + Second(1) + Millisecond(250),
                start + Second(2),
                plan.authorization.window_deadline_utc + Millisecond(1),
            ]
            cursor = Ref(0)
            clock = () -> begin
                cursor[] += 1
                values[min(cursor[], length(values))]
            end
            calls = String[]
            message = failure_text() do
                acquire_restart_recurring(
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
            @test occursin("request was not issued", message)
            @test calls == ["rate_response"]
            journal = plan.journal_path
            attempts = sort!(readdir(joinpath(journal, "attempts")))
            @test attempts == [
                "0001-rate_response-completed.toml",
                "0001-rate_response-prepared.toml",
                "0001-rate_response-validated.toml",
                "0002-volume_response-prepared.toml",
            ]
            completed = TOML.parsefile(
                joinpath(journal, "attempts", attempts[1]),
            )
            @test haskey(
                completed["fields"],
                "request_started_at_utc",
            )
            failure = TOML.parsefile(
                joinpath(journal, "capture-failure.toml"),
            )
            @test failure["attempt_index"] == 2
            @test failure["object_id"] == "volume_response"
            @test failure["downloader_invoked"] === false
            @test failure["request_started_at_utc"] ==
                "NOT_OBSERVED_REQUEST_NOT_ISSUED"
            @test length(
                filter(
                    name -> startswith(name, "raw-sha256-"),
                    readdir(joinpath(journal, "replica-a")),
                ),
            ) == 1
        end
        mktempdir() do temporary
            output_root = joinpath(realpath(temporary), "raw")
            plan = test_plan(
                "2026-08-10",
                "first";
                output_root,
            )
            values = [
                plan.authorization.window_start_utc,
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
                acquire_restart_recurring(
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
                acquire_restart_recurring(
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
                    "0003-api_documentation_snapshot-prepared.toml",
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
                acquire_restart_recurring(
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
            plan = test_plan(
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
                acquire_restart_recurring(
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
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
                "restart_schedule_network_execution_authorized",
            ] = true
            manifest["artifact"]["manifest_sha256"] =
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
                manifest,
                "artifact",
                "manifest_sha256",
            )
            replace_manifest_triplicates!(bundle.bundle_path, manifest)
            @test occursin(
                "restart_schedule_network_execution_authorized",
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
            acquire_restart_recurring(
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
                acquire_restart_recurring(
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

@testset "restart v4 duplicate-member and synthetic provenance firewall" begin
    plan = test_plan(
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
            USEFFRRecurringAcquisitionRestartV4._reject_duplicate_json_members(
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
            USEFFRRecurringAcquisitionRestartV4._select_effr_row(
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
            test_plan(
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
            acquire_restart_recurring(
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
    built_in = USEFFRRecurringAcquisitionRestartV4._operator_authorization(
        plan.authorization,
        true,
    )
    @test built_in["operator_network_execution_authorized"] === true
    @test built_in["synthetic_test_fixture"] === false
    @test built_in["built_in_transport_required"] === true
    @test length(request_plan("2026-08-10", "first")) == 6
end

@testset "restart v4 response preservation and header firewall" begin
    mktempdir() do temporary
        output_root = joinpath(realpath(temporary), "raw-clock")
        plan = test_plan(
            "2026-08-10",
            "first";
            output_root,
        )
        cursor = Ref(0)
        clock = () -> begin
            cursor[] += 1
            cursor[] <= 3 ||
                error("injected completion clock exhaustion")
            return plan.authorization.window_start_utc
        end
        calls = String[]
        message = failure_text() do
            acquire_restart_recurring(
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
        plan = test_plan(
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
            acquire_restart_recurring(
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
            plan = test_plan(
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
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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

@testset "restart v4 loader closes transitions and non-elevating trust fields" begin
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
        selected = USEFFRRecurringAcquisitionRestartV4._select_effr_row(
            volume_bytes,
            "volume",
            effective,
        )
        manifest["row_identity"][2] =
            USEFFRRecurringAcquisitionRestartV4._identity_record(
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
@testset "restart v4 reconstructed receipts reject coordinated value rewrites" begin
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
            @test USEFFRRecurringAcquisitionRestartV4._select_effr_row(
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
        @test error isa RestartRecurringAcquisitionError
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
@testset "restart v4 resolved containment rejects symlinked child directories" begin
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
@testset "restart v4 recursive scalar types and typed loader failures" begin
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
                USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            @test error isa RestartRecurringAcquisitionError
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
                    USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
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
            @test error isa RestartRecurringAcquisitionError
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
        @test error isa RestartRecurringAcquisitionError
        @test occursin("bundle validation", sprint(showerror, error))
    end
end

# This exercises the ordinary `synthetic_fixture=false` manifest-construction
# branch without making a network claim: captured response objects come from a
# marked hermetic fixture, and the resulting in-memory manifest is never
# installed as empirical evidence.
@testset "restart v4 built-in manifest constructor keeps provenance unauthenticated" begin
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
        authorization = test_plan(
            "2026-08-10",
            "first";
            output_root,
        ).authorization
        paths = USEFFRRecurringAcquisitionRestartV4._canonical_paths(
            output_root,
            authorization,
            synthetic_fixture = true,
        )
        specs = request_plan("2026-08-10", "first")
        objects = USEFFRRecurringAcquisitionRestartV4.CapturedResponse[]
        for record in fixture.manifest["objects"]
            body = USEFFRRecurringAcquisitionRestartV4._read_object(
                fixture.bundle_path,
                record,
            )
            push!(
                objects,
                USEFFRRecurringAcquisitionRestartV4._captured_response_from_manifest(
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
                blocker != USEFFRRecurringAcquisitionRestartV4.SYNTHETIC_BLOCKER,
                fixture.manifest["blockers"],
            ),
            row_identity = deepcopy(fixture.manifest["row_identity"]),
        )
        receipt_files = Dict(
            "rate" => fixture.manifest["result"]["rate_receipt_file"],
            "volume" =>
                fixture.manifest["result"]["volume_receipt_file"],
        )
        manifest = USEFFRRecurringAcquisitionRestartV4._build_manifest(
            paths,
            authorization,
            specs,
            objects,
            storage,
            evaluation,
            receipt_files,
            USEFFRRecurringAcquisitionRestartV4._source_bindings(),
            USEFFRRecurringAcquisitionRestartV4._operator_authorization(
                authorization,
                true,
            ),
            false,
        )
        capture = manifest["capture"]
        operator = manifest["operator_authorization"]
        @test capture["synthetic_test_fixture"] === false
        @test capture["transport_provenance"] ==
            USEFFRRecurringAcquisitionRestartV4.BUILTIN_TRANSPORT_PROVENANCE
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
@testset "restart v4 marker-stripping limitation remains permanently nonadmitting" begin
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
        @test_throws RestartRecurringAcquisitionError load_and_validate_bundle(
            bundle.bundle_path,
        )
        manifest = deepcopy(bundle.manifest)
        manifest["event"]["campaign_id"] =
            USEFFRRecurringAcquisitionRestartV4.CAMPAIGN_ID
        manifest["capture"]["transport_policy"] =
            USEFFRRecurringAcquisitionRestartV4.BUILTIN_TRANSPORT_POLICY
        manifest["capture"]["transport_provenance"] =
            USEFFRRecurringAcquisitionRestartV4.BUILTIN_TRANSPORT_PROVENANCE
        manifest["capture"]["synthetic_test_fixture"] = false
        manifest["operator_authorization"] =
            USEFFRRecurringAcquisitionRestartV4._operator_authorization(
            bundle.manifest["event"]["publication_date"] ==
                "2026-08-10" ?
                test_plan(
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
                USEFFRRecurringAcquisitionRestartV4.SYNTHETIC_BLOCKER,
            manifest["blockers"],
        )
        manifest["artifact"]["manifest_sha256"] =
            USEFFRRecurringAcquisitionRestartV4._semantic_sha256(
            manifest,
            "artifact",
            "manifest_sha256",
        )
        replace_manifest_triplicates!(bundle.bundle_path, manifest)
        message = failure_text() do
            load_and_validate_bundle(bundle.bundle_path)
        end
        @test occursin("fixed to", message)
        @test occursin("2026q3_restart_v2", message)
    end
end

const REPOSITORY_ROOT = normpath(
    joinpath(@__DIR__, "..", "..", "..", "..", "..", ".."),
)
const US_PROJECT = joinpath(REPOSITORY_ROOT, "scripts", "us")
const RECURRING_CLI =
    joinpath(@__DIR__, "capture_effr_recurring_restart_v4.jl")

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
    result = run_cli(
        [
            "--publication-date",
            "2026-08-10",
            "--phase",
            "first",
        ];
        directory = "/tmp",
    )
    @test result.exitcode == 0
    @test occursin("Dry run: true", result.stdout)
    @test occursin("Request count: 6", result.stdout)
    @test occursin("Network requests made: 0", result.stdout)
    @test occursin("Filesystem writes made: 0", result.stdout)
    @test occursin("2026q3_restart_v2", result.stdout)
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
            "--execute-live",
        ],
    )
    @test day_zero_live.exitcode == 1
    @test occursin("date/phase is not present exactly once", day_zero_live.stderr)
    output_override = run_cli(
        [
            "--publication-date",
            "2026-08-10",
            "--phase",
            "first",
            "--output-root",
            "/tmp/not-used",
        ],
    )
    @test output_override.exitcode == 2
    @test occursin("unknown argument: --output-root", output_override.stderr)
end
