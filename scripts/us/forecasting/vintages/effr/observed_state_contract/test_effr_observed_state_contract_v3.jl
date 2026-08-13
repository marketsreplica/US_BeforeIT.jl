using Base64
using Dates
using JSON
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USEFFRObservedStateContractV3.jl"))
using .USEFFRObservedStateContractV3

const Contract = USEFFRObservedStateContractV3
const PUBLICATION_DATE = Date(2026, 8, 7)
const EFFECTIVE_DATE = Date(2026, 8, 6)
const HEX_A = repeat("a", 64)
const HEX_B = repeat("b", 64)
const HEX_C = repeat("c", 64)
const AUGUST7_MANIFEST_SHA256 =
    "f801b5539a550857a4ca6c69e0f16ad1c7645ab83e3c87407a0c99aeed4db6d1"
const AUGUST7_RATE_BASE64 =
    "eyAicmVmUmF0ZXMiOiBbIHsgImVmZmVjdGl2ZURhdGUiOiAiMjAyNi0wOC0wNiIsICJ0eXBlIjogIkVGRlIiICwicGVyY2VudFJhdGUiOiAzLjYzICwicGVyY2VudFBlcmNlbnRpbGUxIjogMy42MCAsInBlcmNlbnRQZXJjZW50aWxlMjUiOiAzLjYyICwicGVyY2VudFBlcmNlbnRpbGU3NSI6IDMuNjMgLCJwZXJjZW50UGVyY2VudGlsZTk5IjogMy42NSAsInRhcmdldFJhdGVGcm9tIjogMy41MCAsInRhcmdldFJhdGVUbyI6IDMuNzUgLCJyZXZpc2lvbkluZGljYXRvciI6ICIiIH0sIHsgImVmZmVjdGl2ZURhdGUiOiAiMjAyNi0wOC0wNiIsICJ0eXBlIjogIk9CRlIiICwicGVyY2VudFJhdGUiOiAzLjYzICwicGVyY2VudFBlcmNlbnRpbGUxIjogMy41MyAsInBlcmNlbnRQZXJjZW50aWxlMjUiOiAzLjYyICwicGVyY2VudFBlcmNlbnRpbGU3NSI6IDMuNjMgLCJwZXJjZW50UGVyY2VudGlsZTk5IjogMy42OCAsInJldmlzaW9uSW5kaWNhdG9yIjogIiIgfSwgeyAiZWZmZWN0aXZlRGF0ZSI6ICIyMDI2LTA4LTA2IiwgInR5cGUiOiAiVEdDUiIgLCJwZXJjZW50UmF0ZSI6IDMuNjMgLCJwZXJjZW50UGVyY2VudGlsZTEiOiAzLjU4ICwicGVyY2VudFBlcmNlbnRpbGUyNSI6IDMuNjMgLCJwZXJjZW50UGVyY2VudGlsZTc1IjogMy42MyAsInBlcmNlbnRQZXJjZW50aWxlOTkiOiAzLjY1ICwicmV2aXNpb25JbmRpY2F0b3IiOiAiIiB9LCB7ICJlZmZlY3RpdmVEYXRlIjogIjIwMjYtMDgtMDYiLCAidHlwZSI6ICJCR0NSIiAsInBlcmNlbnRSYXRlIjogMy42MyAsInBlcmNlbnRQZXJjZW50aWxlMSI6IDMuNTggLCJwZXJjZW50UGVyY2VudGlsZTI1IjogMy42MyAsInBlcmNlbnRQZXJjZW50aWxlNzUiOiAzLjYzICwicGVyY2VudFBlcmNlbnRpbGU5OSI6IDMuNjggLCJyZXZpc2lvbkluZGljYXRvciI6ICIiIH0sIHsgImVmZmVjdGl2ZURhdGUiOiAiMjAyNi0wOC0wNiIsICJ0eXBlIjogIlNPRlIiICwicGVyY2VudFJhdGUiOiAzLjY1ICwicGVyY2VudFBlcmNlbnRpbGUxIjogMy42MSAsInBlcmNlbnRQZXJjZW50aWxlMjUiOiAzLjYzICwicGVyY2VudFBlcmNlbnRpbGU3NSI6IDMuNzAgLCJwZXJjZW50UGVyY2VudGlsZTk5IjogMy43MyAsInJldmlzaW9uSW5kaWNhdG9yIjogIiIgfSwgeyAiZWZmZWN0aXZlRGF0ZSI6ICIyMDI2LTA4LTA2IiwgInR5cGUiOiAiU09GUkFJIiAsImF2ZXJhZ2UzMGRheSI6IDMuNjIyNDYgLCJhdmVyYWdlOTBkYXkiOiAzLjYyNzUzICwiYXZlcmFnZTE4MGRheSI6IDMuNjYyOTQgLCJpbmRleCI6IDEuMjUzNzYxODAgLCJyZXZpc2lvbkluZGljYXRvciI6ICIiIH0gXSB9"
const AUGUST7_VOLUME_BASE64 =
    "eyAicmVmUmF0ZXMiOiBbIHsgImVmZmVjdGl2ZURhdGUiOiAiMjAyNi0wOC0wNiIsICJ0eXBlIjogIkVGRlIiICwidm9sdW1lSW5CaWxsaW9ucyI6IDExMyAsInJldmlzaW9uSW5kaWNhdG9yIjogIiIgfSwgeyAiZWZmZWN0aXZlRGF0ZSI6ICIyMDI2LTA4LTA2IiwgInR5cGUiOiAiT0JGUiIgLCJ2b2x1bWVJbkJpbGxpb25zIjogMjM5ICwicmV2aXNpb25JbmRpY2F0b3IiOiAiIiB9LCB7ICJlZmZlY3RpdmVEYXRlIjogIjIwMjYtMDgtMDYiLCAidHlwZSI6ICJUR0NSIiAsInZvbHVtZUluQmlsbGlvbnMiOiAxMjA4ICwicmV2aXNpb25JbmRpY2F0b3IiOiAiIiB9LCB7ICJlZmZlY3RpdmVEYXRlIjogIjIwMjYtMDgtMDYiLCAidHlwZSI6ICJCR0NSIiAsInZvbHVtZUluQmlsbGlvbnMiOiAxMjMwICwicmV2aXNpb25JbmRpY2F0b3IiOiAiIiB9LCB7ICJlZmZlY3RpdmVEYXRlIjogIjIwMjYtMDgtMDYiLCAidHlwZSI6ICJTT0ZSIiAsInZvbHVtZUluQmlsbGlvbnMiOiAzMDU1ICwicmV2aXNpb25JbmRpY2F0b3IiOiAiIiB9LCB7ICJlZmZlY3RpdmVEYXRlIjogIjIwMjYtMDgtMDYiLCAidHlwZSI6ICJTT0ZSQUkiICwicmV2aXNpb25JbmRpY2F0b3IiOiAiIiB9IF0gfQ=="

hex(bytes) = bytes2hex(sha256(bytes))

function replace_first_numeric_lexeme(body, field, replacement)
    text = String(copy(body))
    marker = "\"$field\":"
    marker_range = findfirst(marker, text)
    marker_range === nothing && error("missing numeric fixture field $field")
    cursor = last(marker_range) + 1
    while cursor <= ncodeunits(text) && text[cursor] in (' ', '\t', '\r', '\n')
        cursor += 1
    end
    matched = match(
        r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?",
        SubString(text, cursor),
    )
    matched === nothing && error("fixture field $field is not numeric")
    last_index = cursor + ncodeunits(matched.match) - 1
    replaced = string(
        SubString(text, firstindex(text), cursor - 1),
        replacement,
        SubString(text, last_index + 1, lastindex(text)),
    )
    return Vector{UInt8}(codeunits(replaced))
end

function error_code(action)
    try
        action()
    catch error
        error isa ObservedStateContractError || rethrow()
        return error.code
    end
    return "NO_ERROR"
end

function error_text(action)
    try
        action()
    catch error
        return sprint(showerror, error)
    end
    return "NO_ERROR"
end

function fixture_body(
        report_type;
        effective_date = EFFECTIVE_DATE,
        revision = "",
        rate = 3.63,
        volume = 113,
        footnote = nothing,
        non_effr_rate = 3.62,
        extra_effr_field = nothing,
        current_state = nothing,
        include_non_effr = true,
    )
    effr = Dict{String, Any}(
        "effectiveDate" => string(effective_date),
        "type" => "EFFR",
        "revisionIndicator" => revision,
    )
    if report_type == "rate"
        merge!(
            effr,
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
        effr["volumeInBillions"] = volume
    end
    footnote === nothing || (effr["footnoteId"] = footnote)
    current_state === nothing || (effr["currentState"] = current_state)
    extra_effr_field === nothing ||
        (effr[String(first(extra_effr_field))] = last(extra_effr_field))
    rows = Any[effr]
    if include_non_effr
        other = Dict{String, Any}(
            "effectiveDate" => string(effective_date),
            "type" => "OBFR",
            "revisionIndicator" => revision,
        )
        if report_type == "rate"
            merge!(
                other,
                Dict{String, Any}(
                    "percentRate" => non_effr_rate,
                    "percentPercentile1" => non_effr_rate - 0.03,
                    "percentPercentile25" => non_effr_rate - 0.01,
                    "percentPercentile75" => non_effr_rate + 0.01,
                    "percentPercentile99" => non_effr_rate + 0.03,
                ),
            )
        else
            other["volumeInBillions"] = volume + 100
        end
        footnote === nothing || (other["footnoteId"] = footnote)
        push!(rows, other)
    end
    return Vector{UInt8}(codeunits(JSON.json(Dict("refRates" => rows))))
end

function fixture_capture(
        report_type,
        observation_class;
        body = fixture_body(report_type),
        publication_date = PUBLICATION_DATE,
        effective_date = EFFECTIVE_DATE,
        headers = [
            "content-type" => "application/json;charset=utf-8",
            "content-encoding" => "identity",
            "date" => "Fri, 07 Aug 2026 13:00:06 GMT",
        ],
        start_override = nothing,
        completion_override = nothing,
        metadata_override = nothing,
        canonical_query_override = nothing,
        requested_url_override = nothing,
        final_url_override = nothing,
        http_status = 200,
        redirect_count = 0,
    )
    base = observation_class == MORNING_WINDOW_ENDPOINT_OBSERVATION ?
        DateTime(publication_date) + Hour(13) :
        DateTime(publication_date) + Hour(18) + Minute(30)
    offset = report_type == "rate" ? Millisecond(100) : Millisecond(500)
    started = something(start_override, base + offset)
    completed = something(completion_override, base + offset + Millisecond(100))
    metadata = something(metadata_override, base + offset + Millisecond(200))
    query = something(
        canonical_query_override,
        "endDate=$effective_date&startDate=$effective_date&type=$report_type",
    )
    requested = something(
        requested_url_override,
        "https://markets.newyorkfed.org/api/rates/all/search.json?$query",
    )
    return CapturedReport(
        report_type = report_type,
        body = copy(body),
        canonical_query = query,
        requested_url = requested,
        final_url = something(final_url_override, requested),
        http_status = http_status,
        redirect_count = redirect_count,
        response_headers = copy(headers),
        request_started_at_utc = started,
        response_body_completed_at_utc = completed,
        response_metadata_observed_at_utc = metadata,
    )
end

function fixture_observation(
        observation_class;
        rate_body = fixture_body("rate"),
        volume_body = fixture_body("volume"),
        rate_kwargs = NamedTuple(),
        volume_kwargs = NamedTuple(),
    )
    rate = fixture_capture(
        "rate",
        observation_class;
        body = rate_body,
        rate_kwargs...,
    )
    volume = fixture_capture(
        "volume",
        observation_class;
        body = volume_body,
        volume_kwargs...,
    )
    return validate_endpoint_observation(
        rate,
        volume;
        observation_class,
        publication_date = PUBLICATION_DATE,
        effective_date = EFFECTIVE_DATE,
    )
end

function binding(
        morning;
        created_at = DateTime(2026, 8, 7, 19),
        predecessor_decision = HEX_A,
        manifest = HEX_B,
        timestamp_status = "NOT_PROVIDED",
        timestamp_hash = "NONE",
        kwargs...,
    )
    return DecisionBinding(
        decision_id = "effr-20260807-observed-state-v3",
        created_at_utc = created_at,
        predecessor_observation_sha256 = morning.observation_sha256,
        predecessor_decision_sha256 = predecessor_decision,
        superseded_capture_manifest_sha256 = manifest,
        timestamp_evidence_status = timestamp_status,
        timestamp_token_sha256 = timestamp_hash;
        kwargs...,
    )
end

function restamp_protocol!(document)
    document["artifact"]["content_sha256"] =
        protocol_semantic_sha256(document)
    return document
end

function restamp_decision!(document)
    document["artifact"]["decision_sha256"] =
        Contract._decision_semantic_sha256(document)
    return document
end

@testset "protocol pins and incompatible governance boundary" begin
    protocol = validate_protocol()
    @test protocol["artifact"]["schema_version"] ==
        "beforeit-us-effr-observed-state-contract.v3"
    @test protocol["artifact"]["contract_version"] == "3.0.0"
    @test protocol["artifact"]["incompatible_with"] ==
        "beforeit-us-effr-one-effective-date-capture-receipt.v2"
    @test protocol["artifact"]["status"] == "CANDIDATE_OFFLINE_NONADMITTING"
    @test protocol_semantic_sha256(protocol) ==
        protocol["artifact"]["content_sha256"]
    @test protocol["current_state_disposition"] == Dict(
        "current_openapi_definition" => "ABSENT",
        "captured_wire_presence" => "ABSENT",
        "authoritative_evidence_ever_official" => "NOT_ESTABLISHED",
        "raw_false_derivation_allowed" => false,
        "synthetic_current_state_allowed" => false,
    )
    @test protocol["estimand"]["status"] == "PENDING"
    @test protocol["estimand"]["candidate_estimands"] == [
        "STRICT_FIRST_PUBLIC_BYTES",
        "PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE",
    ]
    @test protocol["policy"]["footnote_required_for_marked_revision"] ===
        false
    @test protocol["policy"]["footnote_pair_rule"] ==
        "EXACT_FOOTNOTE_ID_INTEGER_OR_ABSENCE_MATCH_OR_QUARANTINE"
    @test protocol["parser"]["footnote_field"] == "footnoteId"
    @test protocol["parser"]["footnote_alias_allowed"] === false
    @test protocol["parser"]["exact_numeric_lexemes_preserved"] === true
    @test protocol["parser"]["max_json_number_bytes"] == 96
    @test protocol["parser"]["max_json_mantissa_digits"] == 40
    @test protocol["parser"]["max_json_abs_exponent"] == 20
    @test protocol["parser"]["max_json_body_bytes"] == 1_048_576
    @test protocol["parser"]["max_json_nesting_depth"] == 64
    @test all(value === false for value in values(protocol["gates"]))
    @test protocol["source_bindings"]["openapi_current_state_occurrences"] == 0
    @test protocol["source_bindings"]["api_documentation_current_state_occurrences"] ==
        0
    @test protocol["source_bindings"]["openapi_revision_indicator_occurrences"] ==
        6
    @test protocol["source_bindings"]["openapi_footnote_id_schema_members"] == 5
    @test protocol["source_bindings"]["openapi_standalone_footnote_schema_members"] ==
        0
    @test protocol["source_bindings"]["openapi_effr_record_schema_path"] ==
        "#/components/schemas/effr-record"
    @test protocol["source_bindings"]["august7_rate_raw_sha256"] ==
        "5977e0aafae9f34d348ad69166afce47c223b6147312654155855e0450315341"
    @test protocol["source_bindings"]["august7_volume_raw_sha256"] ==
        "13f146b7f27a724f28a63343fed40c1cdb3c447eec1a5663d5b1b5f192febc61"
    @test length(protocol["transition_matrix"]) == 8
    @test length(protocol["citations"]) == 10
    @test any(
        citation -> citation["id"] == "RFC_8259_JSON",
        protocol["citations"],
    )
    @test any(
        citation -> citation["id"] == "RFC_3161_TIMESTAMP",
        protocol["citations"],
    )
    @test any(
        citation -> citation["id"] == "SEMVER_2_0_0",
        protocol["citations"],
    )

    mutated = deepcopy(protocol)
    mutated["gates"]["origin_admissible"] = true
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "TRUST_ELEVATION_FORBIDDEN"

    mutated = deepcopy(protocol)
    mutated["current_state_disposition"]["raw_false_derivation_allowed"] = true
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "TRUST_ELEVATION_FORBIDDEN"

    mutated = deepcopy(protocol)
    mutated["current_state_disposition"]["authoritative_evidence_ever_official"] =
        "NEVER_OFFICIAL"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "CURRENT_STATE_DISPOSITION_CHANGED"

    mutated = deepcopy(protocol)
    mutated["estimand"]["status"] = "SELECTED"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "ESTIMAND_PRESELECTION_FORBIDDEN"

    mutated = deepcopy(protocol)
    mutated["artifact"]["status"] = "ACCEPTED"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "TRUST_ELEVATION_FORBIDDEN"

    mutated = deepcopy(protocol)
    mutated["artifact"]["contract_id"] = "Other"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "WRONG_CONTRACT_ID"

    mutated = deepcopy(protocol)
    mutated["policy"]["rate_change_threshold_basis_points"] = 0
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "RANGE_VIOLATION"

    mutated = deepcopy(protocol)
    mutated["source_bindings"]["openapi_current_state_occurrences"] = 1
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "SOURCE_ASSERTION_CHANGED"

    mutated = deepcopy(protocol)
    push!(mutated["transition_matrix"], deepcopy(last(mutated["transition_matrix"])))
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "TRANSITION_MATRIX_CHANGED"

    mutated = deepcopy(protocol)
    mutated["transition_matrix"][1]["evidence"] = "Other"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "TRANSITION_MATRIX_CHANGED"

    mutated = deepcopy(protocol)
    mutated["citations"][1]["url"] = "https://example.invalid"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "CITATION_SET_CHANGED"

    mutated = deepcopy(protocol)
    mutated["citations"][3]["local_authentication_status"] =
        "REMOTE_LITERATURE_ASSERTION_NOT_LOCALLY_AUTHENTICATED"
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "CITATION_SET_CHANGED"

    mutated = deepcopy(protocol)
    mutated["unreviewed"] = true
    restamp_protocol!(mutated)
    @test error_code(() -> validate_protocol_document(mutated)) ==
        "CLOSED_SCHEMA_VIOLATION"

    protocol["gates"]["origin_admissible"] = true
    @test validate_protocol()["gates"]["origin_admissible"] === false
end

@testset "exact copied August 7 bytes and linked offline re-adjudication" begin
    rate_bytes = base64decode(AUGUST7_RATE_BASE64)
    volume_bytes = base64decode(AUGUST7_VOLUME_BASE64)
    @test length(rate_bytes) == 1299
    @test length(volume_bytes) == 604
    @test hex(rate_bytes) ==
        "5977e0aafae9f34d348ad69166afce47c223b6147312654155855e0450315341"
    @test hex(volume_bytes) ==
        "13f146b7f27a724f28a63343fed40c1cdb3c447eec1a5663d5b1b5f192febc61"
    original_rate = copy(rate_bytes)
    original_volume = copy(volume_bytes)
    morning = validate_endpoint_observation(
        fixture_capture(
            "rate",
            MORNING_WINDOW_ENDPOINT_OBSERVATION;
            body = rate_bytes,
        ),
        fixture_capture(
            "volume",
            MORNING_WINDOW_ENDPOINT_OBSERVATION;
            body = volume_bytes,
        );
        observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
        publication_date = PUBLICATION_DATE,
        effective_date = EFFECTIVE_DATE,
    )
    @test rate_bytes == original_rate
    @test volume_bytes == original_volume
    @test morning.rate.raw_sha256 ==
        "5977e0aafae9f34d348ad69166afce47c223b6147312654155855e0450315341"
    @test morning.volume.raw_sha256 ==
        "13f146b7f27a724f28a63343fed40c1cdb3c447eec1a5663d5b1b5f192febc61"
    @test morning.rate.revision_token == ""
    @test morning.volume.revision_token == ""
    @test morning.rate.selected_json_pointer == "/refRates/0"
    @test morning.volume.selected_json_pointer == "/refRates/0"
    @test Contract._field(morning.rate, "percentRate") == "3.63"
    @test Contract._field(morning.volume, "volumeInBillions") == "113"
    @test morning.rate_completion_claim ==
        "RATE_ENDPOINT_STATE_OBSERVED_BY_RECORDED_BODY_COMPLETION_TIME"
    @test morning.volume_completion_claim ==
        "VOLUME_ENDPOINT_STATE_OBSERVED_BY_RECORDED_BODY_COMPLETION_TIME"
    @test morning.pair_as_of_utc ==
        morning.volume.response_body_completed_at_utc
    @test morning.requests_sequential_not_atomic
    morning_document = observation_document(morning)
    @test morning_document["observation_sha256"] ==
        morning.observation_sha256
    @test morning_document["rate"]["http_status"] == 200
    @test morning_document["rate"]["redirect_count"] == 0
    @test morning_document["rate"]["response_headers"][1] ==
        ("content-type" => "application/json;charset=utf-8")
    @test any(
        field ->
        first(field) == "percentRate" &&
            field[2] == "JSON_NUMBER" &&
            last(field) == "3.63",
        morning_document["rate"]["selected_fields"],
    )

    linked = adjudicate_morning_observation(
        morning,
        binding(
            morning;
            predecessor_decision = AUGUST7_MANIFEST_SHA256,
            manifest = AUGUST7_MANIFEST_SHA256,
        ),
    )
    @test linked["decision"]["outcome"] ==
        "MORNING_WINDOW_ENDPOINT_OBSERVATION_RECORDED"
    @test linked["decision"]["decision_class"] ==
        MORNING_WINDOW_ENDPOINT_OBSERVATION
    @test linked["decision"]["later_observation_sha256"] == "NOT_APPLICABLE"
    @test linked["decision"]["morning_percent_rate_lexeme"] == "3.63"
    @test linked["decision"]["later_percent_rate_lexeme"] == "NOT_APPLICABLE"
    @test linked["decision"]["rate_change_basis_points_numerator"] ==
        "NOT_APPLICABLE"
    @test linked["decision"]["rate_change_basis_points_denominator"] ==
        "NOT_APPLICABLE"
    @test linked["binding"]["superseded_contract_schema_version"] ==
        "beforeit-us-effr-one-effective-date-capture-receipt.v2"
    @test linked["binding"]["superseded_receipt_status"] ==
        "NOT_CREATED_RAW_CURRENT_STATE_FIELD_ABSENT"
    @test linked["binding"]["superseded_capture_manifest_sha256"] ==
        AUGUST7_MANIFEST_SHA256
    @test linked["binding"]["supersession_mode"] ==
        "APPEND_ONLY_OFFLINE_READJUDICATION_NO_MUTATION_NO_BACKDATING"
    @test linked["current_state_disposition"]["raw_false_derivation_allowed"] ===
        false
    @test linked["current_state_disposition"]["synthetic_current_state_added"] ===
        false
    @test linked["decision"]["final_state_for_day_claimed"] === false
    @test linked["decision"]["no_later_revision_claimed"] === false
    @test all(value === false for value in values(linked["gates"]))
    @test linked["estimand"]["status"] == "PENDING"
    @test validate_decision_document(
        linked,
        linked["artifact"]["decision_sha256"],
    ) == linked

    outside_morning_window = deepcopy(linked)
    outside_morning_window["decision"]["morning_pair_as_of_utc"] =
        DateTime(2026, 8, 7, 0)
    outside_morning_window["decision"]["latest_evidence_observed_at_utc"] =
        DateTime(2026, 8, 7, 0, 1)
    restamp_decision!(outside_morning_window)
    @test error_code(
        () -> validate_decision_document(
            outside_morning_window,
            outside_morning_window["artifact"]["decision_sha256"],
        ),
    ) == "DECISION_WINDOW_VIOLATION"
end

@testset "closed parser and raw-schema quarantine" begin
    normal = fixture_body("rate")
    before = copy(normal)
    parsed = validate_report(
        fixture_capture(
            "rate",
            MORNING_WINDOW_ENDPOINT_OBSERVATION;
            body = normal,
        ),
        PUBLICATION_DATE,
        EFFECTIVE_DATE,
        MORNING_WINDOW_ENDPOINT_OBSERVATION,
    )
    @test normal == before
    @test parsed.raw_sha256 == hex(normal)
    @test parsed.revision_token == ""
    @test parsed.footnote_token == "NONE"
    @test parsed.footnote_class == "NONE"

    literal = String(copy(normal))
    duplicate = replace(
        literal,
        "\"type\":\"EFFR\"" =>
            "\"type\":\"EFFR\",\"t\\u0079pe\":\"EFFR\"";
        count = 1,
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = Vector{UInt8}(codeunits(duplicate)),
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "DUPLICATE_JSON_MEMBER"

    envelope_duplicate =
        "{\"refRates\":[],\"ref\\u0052ates\":[]}"
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = Vector{UInt8}(codeunits(envelope_duplicate)),
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "DUPLICATE_JSON_MEMBER"

    for state in (false, true)
        body = fixture_body("rate"; current_state = state)
        @test error_code(
            () -> validate_report(
                fixture_capture(
                    "rate",
                    MORNING_WINDOW_ENDPOINT_OBSERVATION;
                    body,
                ),
                PUBLICATION_DATE,
                EFFECTIVE_DATE,
                MORNING_WINDOW_ENDPOINT_OBSERVATION,
            ),
        ) == "SCHEMA_DRIFT_CURRENT_STATE_PRESENT"
    end

    alias = replace(literal, "\"percentRate\"" => "\"percent\""; count = 1)
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = Vector{UInt8}(codeunits(alias)),
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "MISSING_FIELD"

    unknown = fixture_body("rate"; extra_effr_field = "newField" => 1)
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = unknown,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "SCHEMA_DRIFT_UNKNOWN_FIELD"

    token_y = fixture_body("rate"; revision = "Y")
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = token_y,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "UNKNOWN_REVISION_TOKEN"

    parsed_json = JSON.parse(String(copy(normal)))
    delete!(first(parsed_json["refRates"]), "revisionIndicator")
    missing_token = Vector{UInt8}(codeunits(JSON.json(parsed_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = missing_token,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "MISSING_FIELD"

    parsed_json = JSON.parse(String(copy(normal)))
    first(parsed_json["refRates"])["percentRate"] = true
    boolean_rate = Vector{UInt8}(codeunits(JSON.json(parsed_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = boolean_rate,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "TYPE_MISMATCH"

    string_volume_json =
        JSON.parse(String(copy(fixture_body("volume"))))
    first(string_volume_json["refRates"])["volumeInBillions"] = "113"
    string_volume = Vector{UInt8}(codeunits(JSON.json(string_volume_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "volume",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = string_volume,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "TYPE_MISMATCH"

    for bad_footnote in (true, 4)
        body = fixture_body("rate"; footnote = bad_footnote)
        expected = bad_footnote === true ? "FOOTNOTE_ID_TYPE_MISMATCH" :
            "UNKNOWN_FOOTNOTE_TOKEN"
        @test error_code(
            () -> validate_report(
                fixture_capture(
                    "rate",
                    MORNING_WINDOW_ENDPOINT_OBSERVATION;
                    body,
                ),
                PUBLICATION_DATE,
                EFFECTIVE_DATE,
                MORNING_WINDOW_ENDPOINT_OBSERVATION,
            ),
        ) == expected
    end

    for bad_footnote in ("1", 1.0)
        body = fixture_body("rate"; footnote = bad_footnote)
        @test error_code(
            () -> validate_report(
                fixture_capture(
                    "rate",
                    MORNING_WINDOW_ENDPOINT_OBSERVATION;
                    body,
                ),
                PUBLICATION_DATE,
                EFFECTIVE_DATE,
                MORNING_WINDOW_ENDPOINT_OBSERVATION,
            ),
        ) == "FOOTNOTE_ID_TYPE_MISMATCH"
    end

    exponent_footnote = replace_first_numeric_lexeme(
        fixture_body("rate"; footnote = 1),
        "footnoteId",
        "1e0",
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = exponent_footnote,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "FOOTNOTE_ID_TYPE_MISMATCH"

    alias_only = replace(
        String(copy(fixture_body("rate"; footnote = 1))),
        "\"footnoteId\"" => "\"footnote\"";
        count = 1,
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = Vector{UInt8}(codeunits(alias_only)),
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "SCHEMA_DRIFT_UNKNOWN_FIELD"

    conflicting_json =
        JSON.parse(String(copy(fixture_body("rate"; footnote = 1))))
    first(conflicting_json["refRates"])["footnote"] = "1"
    conflicting =
        Vector{UInt8}(codeunits(JSON.json(conflicting_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = conflicting,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "SCHEMA_DRIFT_UNKNOWN_FIELD"

    unknown_type_json = JSON.parse(String(copy(fixture_body("rate"))))
    last(unknown_type_json["refRates"])["type"] = "Other"
    unknown_type =
        Vector{UInt8}(codeunits(JSON.json(unknown_type_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = unknown_type,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "UNKNOWN_ROW_TYPE"

    non_effr_new_field_json =
        JSON.parse(String(copy(fixture_body("rate"))))
    last(non_effr_new_field_json["refRates"])["invented"] = 1
    non_effr_new_field =
        Vector{UInt8}(codeunits(JSON.json(non_effr_new_field_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = non_effr_new_field,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "SCHEMA_DRIFT_UNKNOWN_FIELD"

    non_effr_current_state_json =
        JSON.parse(String(copy(fixture_body("rate"))))
    last(non_effr_current_state_json["refRates"])["currentState"] = false
    non_effr_current_state =
        Vector{UInt8}(codeunits(JSON.json(non_effr_current_state_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = non_effr_current_state,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "SCHEMA_DRIFT_CURRENT_STATE_PRESENT"

    non_effr_y_json = JSON.parse(String(copy(fixture_body("rate"))))
    last(non_effr_y_json["refRates"])["revisionIndicator"] = "Y"
    non_effr_y = Vector{UInt8}(codeunits(JSON.json(non_effr_y_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = non_effr_y,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "UNKNOWN_REVISION_TOKEN"

    duplicate_effr_json = JSON.parse(String(copy(fixture_body("rate"))))
    push!(
        duplicate_effr_json["refRates"],
        deepcopy(first(duplicate_effr_json["refRates"])),
    )
    duplicate_effr =
        Vector{UInt8}(codeunits(JSON.json(duplicate_effr_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = duplicate_effr,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "DUPLICATE_EFFR_ROW"

    extra_envelope = Vector{UInt8}(
        codeunits(
            JSON.json(
                Dict(
                    "refRates" =>
                        JSON.parse(String(copy(normal)))["refRates"],
                    "meta" => Dict(),
                ),
            ),
        ),
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = extra_envelope,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "CLOSED_SCHEMA_VIOLATION"

    empty = Vector{UInt8}(codeunits("{\"refRates\":[]}"))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = empty,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "MISSING_EFFR_ROW"

    ordering_json = JSON.parse(String(copy(normal)))
    first(ordering_json["refRates"])["percentPercentile1"] = 3.7
    ordering = Vector{UInt8}(codeunits(JSON.json(ordering_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = ordering,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "RATE_ORDERING_VIOLATION"

    target_json = JSON.parse(String(copy(normal)))
    first(target_json["refRates"])["targetRateFrom"] = 4.0
    target = Vector{UInt8}(codeunits(JSON.json(target_json)))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = target,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "TARGET_RANGE_VIOLATION"

    invalid = Vector{UInt8}(codeunits("{\"refRates\":[}"))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = invalid,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "INVALID_JSON"

    too_deep = Vector{UInt8}(
        codeunits(repeat("[", 66) * "0" * repeat("]", 66)),
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = too_deep,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "JSON_NESTING_LIMIT_EXCEEDED"

    too_large = vcat(fill(UInt8(' '), 1_048_577), codeunits("{}"))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = too_large,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "JSON_BODY_LIMIT_EXCEEDED"

    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = UInt8[0x22, 0xff, 0x22],
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "INVALID_JSON_UTF8"

    unpaired_surrogate = Vector{UInt8}(codeunits("\"\\ud800\""))
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = unpaired_surrogate,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "INVALID_JSON_UNICODE"
end

@testset "query host media redirect windows and sequential pair" begin
    rate = fixture_capture("rate", MORNING_WINDOW_ENDPOINT_OBSERVATION)
    volume = fixture_capture("volume", MORNING_WINDOW_ENDPOINT_OBSERVATION)
    observation = validate_endpoint_observation(
        rate,
        volume;
        observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
        publication_date = PUBLICATION_DATE,
        effective_date = EFFECTIVE_DATE,
    )
    @test observation.rate.canonical_query ==
        "endDate=2026-08-06&startDate=2026-08-06&type=rate"
    @test observation.volume.canonical_query ==
        "endDate=2026-08-06&startDate=2026-08-06&type=volume"
    @test observation.rate.request_started_at_utc <
        observation.rate.response_body_completed_at_utc <
        observation.rate.response_metadata_observed_at_utc <
        observation.volume.request_started_at_utc <
        observation.volume.response_body_completed_at_utc <
        observation.volume.response_metadata_observed_at_utc

    bad_cases = (
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                canonical_query_override =
                    "startDate=2026-08-06&endDate=2026-08-06&type=rate",
            ),
            "QUERY_MISMATCH",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                requested_url_override =
                    "https://example.invalid/api?endDate=2026-08-06&startDate=2026-08-06&type=rate",
            ),
            "REQUEST_URL_MISMATCH",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                final_url_override =
                    "https://example.invalid/api?endDate=2026-08-06&startDate=2026-08-06&type=rate",
            ),
            "FINAL_URL_OR_REDIRECT_MISMATCH",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                http_status = 204,
            ),
            "HTTP_STATUS_MISMATCH",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                redirect_count = 1,
            ),
            "REDIRECT_FORBIDDEN",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                headers = ["content-type" => "application/problem+json"],
            ),
            "MEDIA_TYPE_MISMATCH",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                headers = [
                    "content-type" => "application/json",
                    "content-encoding" => "gzip",
                ],
            ),
            "CONTENT_ENCODING_MISMATCH",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                headers = [
                    "content-type" => "application/json",
                    "Content-Type" => "application/json",
                ],
            ),
            "DUPLICATE_RESPONSE_HEADER",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                headers = [" content-type" => "application/json"],
            ),
            "INVALID_HEADER_NAME",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                headers = ["content-type" => " application/json"],
            ),
            "INVALID_HEADER_VALUE",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                start_override = DateTime(2026, 8, 7, 12, 59, 59),
            ),
            "CAPTURE_WINDOW_VIOLATION",
        ),
        (
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                completion_override = DateTime(2026, 8, 7, 13, 0, 0),
            ),
            "CAPTURE_WINDOW_VIOLATION",
        ),
    )
    for (bad, expected) in bad_cases
        @test error_code(
            () -> validate_report(
                bad,
                PUBLICATION_DATE,
                EFFECTIVE_DATE,
                MORNING_WINDOW_ENDPOINT_OBSERVATION,
            ),
        ) == expected
    end

    @test error_code(
        () -> validate_report(
            rate,
            PUBLICATION_DATE,
            Date(2026, 8, 5),
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "EFFECTIVE_DATE_MISMATCH"

    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
                publication_date = Date(2026, 10, 30),
                effective_date = Date(2026, 10, 29),
            ),
            Date(2026, 10, 30),
            Date(2026, 10, 29),
            POST_REVISION_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "UNAUTHORIZED_REVISION_WINDOW"

    overlapping_volume = fixture_capture(
        "volume",
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        start_override = rate.response_body_completed_at_utc,
        completion_override = rate.response_body_completed_at_utc +
            Millisecond(100),
        metadata_override = rate.response_body_completed_at_utc +
            Millisecond(200),
    )
    @test error_code(
        () -> validate_endpoint_observation(
            rate,
            overlapping_volume;
            observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
            publication_date = PUBLICATION_DATE,
            effective_date = EFFECTIVE_DATE,
        ),
    ) == "RATE_VOLUME_NOT_SEQUENTIAL"

    mismatched_volume = fixture_capture(
        "volume",
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        body = fixture_body("volume"; revision = "r", footnote = 1),
    )
    @test error_code(
        () -> validate_endpoint_observation(
            rate,
            mismatched_volume;
            observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
            publication_date = PUBLICATION_DATE,
            effective_date = EFFECTIVE_DATE,
        ),
    ) == "RATE_VOLUME_PAIR_MISMATCH"

    footnoted_rate = fixture_capture(
        "rate",
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        body = fixture_body("rate"; footnote = 1),
    )
    @test error_code(
        () -> validate_endpoint_observation(
            footnoted_rate,
            volume;
            observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
            publication_date = PUBLICATION_DATE,
            effective_date = EFFECTIVE_DATE,
        ),
    ) == "RATE_VOLUME_PAIR_MISMATCH"

    footnoted_volume = fixture_capture(
        "volume",
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        body = fixture_body("volume"; footnote = 2),
    )
    @test error_code(
        () -> validate_endpoint_observation(
            footnoted_rate,
            footnoted_volume;
            observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
            publication_date = PUBLICATION_DATE,
            effective_date = EFFECTIVE_DATE,
        ),
    ) == "RATE_VOLUME_PAIR_MISMATCH"

    volume_alias_json =
        JSON.parse(String(copy(fixture_body("volume"; footnote = 1))))
    volume_alias_row = first(volume_alias_json["refRates"])
    delete!(volume_alias_row, "footnoteId")
    volume_alias_row["footnote"] = "1"
    volume_alias = fixture_capture(
        "volume",
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        body = Vector{UInt8}(codeunits(JSON.json(volume_alias_json))),
    )
    @test error_code(
        () -> validate_endpoint_observation(
            footnoted_rate,
            volume_alias;
            observation_class = MORNING_WINDOW_ENDPOINT_OBSERVATION,
            publication_date = PUBLICATION_DATE,
            effective_date = EFFECTIVE_DATE,
        ),
    ) == "SCHEMA_DRIFT_UNKNOWN_FIELD"
end

@testset "full observed-transition matrix and claim ceiling" begin
    morning = fixture_observation(MORNING_WINDOW_ENDPOINT_OBSERVATION)
    unchanged = fixture_observation(POST_REVISION_WINDOW_ENDPOINT_OBSERVATION)
    unchanged_decision = adjudicate_transition(
        morning,
        unchanged,
        binding(
            morning;
            predecessor_decision = HEX_C,
            created_at = DateTime(2026, 8, 7, 19),
        ),
    )
    @test unchanged_decision["decision"]["decision_class"] ==
        OBSERVED_EFFR_TRANSITION
    @test unchanged_decision["decision"]["outcome"] ==
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
    @test unchanged_decision["decision"]["claim"] ==
        "NO_MARKED_REVISION_OBSERVED_AS_OF_SECOND_CAPTURE"
    @test unchanged_decision["decision"]["final_state_for_day_claimed"] === false
    @test unchanged_decision["decision"]["no_later_revision_claimed"] === false
    @test unchanged_decision["decision"]["rate_volume_requests_atomic"] === false

    marked = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body(
            "rate";
            revision = "r",
            rate = 3.65,
            footnote = 1,
        ),
        volume_body = fixture_body(
            "volume";
            revision = "r",
            volume = 113,
            footnote = 1,
        ),
    )
    marked_decision = adjudicate_transition(
        morning,
        marked,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test marked_decision["decision"]["outcome"] ==
        "MARKED_SAME_DAY_REVISION_OBSERVED"
    @test marked_decision["decision"]["morning_percent_rate_lexeme"] == "3.63"
    @test marked_decision["decision"]["later_percent_rate_lexeme"] == "3.65"
    @test marked_decision["decision"]["rate_change_basis_points_numerator"] ==
        "2"
    @test marked_decision["decision"]["rate_change_basis_points_denominator"] ==
        "1"
    @test Contract._field(marked.volume, "volumeInBillions") == "113"
    @test "LATER_OR_EXTRAORDINARY_CORRECTION_NOT_RULED_OUT" in
        marked_decision["blockers"]

    morning_revised = fixture_observation(
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body(
            "rate";
            revision = "r",
            rate = 3.63,
            footnote = 1,
        ),
        volume_body = fixture_body(
            "volume";
            revision = "r",
            footnote = 1,
        ),
    )
    morning_revised_decision = adjudicate_transition(
        morning_revised,
        marked,
        binding(morning_revised),
    )
    @test morning_revised_decision["decision"]["outcome"] ==
        "QUARANTINED_MORNING_ALREADY_MARKED_REVISED"

    unmarked = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body("rate"; rate = 3.65),
    )
    unmarked_decision = adjudicate_transition(
        morning,
        unmarked,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test unmarked_decision["decision"]["outcome"] ==
        "QUARANTINED_UNMARKED_EFFR_TRANSITION"

    unmarked_volume = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        volume_body = fixture_body("volume"; volume = 114),
    )
    unmarked_volume_decision = adjudicate_transition(
        morning,
        unmarked_volume,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test unmarked_volume_decision["decision"]["outcome"] ==
        "QUARANTINED_UNMARKED_EFFR_TRANSITION"

    summary_json = JSON.parse(String(copy(fixture_body("rate"))))
    first(summary_json["refRates"])["percentPercentile99"] = 3.67
    summary_change = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = Vector{UInt8}(codeunits(JSON.json(summary_json))),
    )
    summary_decision = adjudicate_transition(
        morning,
        summary_change,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test summary_decision["decision"]["outcome"] ==
        "QUARANTINED_UNMARKED_EFFR_TRANSITION"

    exactly_one_bp = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body(
            "rate";
            revision = "r",
            rate = 3.64,
            footnote = 1,
        ),
        volume_body = fixture_body(
            "volume";
            revision = "r",
            footnote = 1,
        ),
    )
    one_bp_decision = adjudicate_transition(
        morning,
        exactly_one_bp,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test one_bp_decision["decision"]["outcome"] ==
        "QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT"

    no_contingency_footnote = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body("rate"; revision = "r", rate = 3.65),
        volume_body = fixture_body("volume"; revision = "r"),
    )
    no_contingency_footnote_decision = adjudicate_transition(
        morning,
        no_contingency_footnote,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test no_contingency_footnote_decision["decision"]["outcome"] ==
        "MARKED_SAME_DAY_REVISION_OBSERVED"
    @test no_contingency_footnote.rate.footnote_token == "NONE"
    @test no_contingency_footnote.volume.footnote_token == "NONE"

    non_effr_change = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body("rate"; non_effr_rate = 3.61),
    )
    non_effr_decision = adjudicate_transition(
        morning,
        non_effr_change,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test non_effr_decision["decision"]["outcome"] ==
        "QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION"

    original_rate = fixture_body("rate")
    spaced_rate = vcat(UInt8(' '), original_rate)
    @test hex(spaced_rate) != hex(original_rate)
    serialization_change = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = spaced_rate,
    )
    serialization_decision = adjudicate_transition(
        morning,
        serialization_change,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test serialization_decision["decision"]["outcome"] ==
        "QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION"

    @test all(value === false for value in values(marked_decision["gates"]))
    @test marked_decision["estimand"]["status"] == "PENDING"
    @test marked_decision["estimand"]["selected_estimand"] == "NONE"
    @test marked_decision["evidence_layers"]["local_integrity_validated"]
    @test marked_decision["evidence_layers"]["publication_endpoint_state_observed"]
    @test !marked_decision["evidence_layers"]["publisher_provenance_authenticated"]
    @test !marked_decision["evidence_layers"]["origin_admitted"]
end

@testset "exact decimal lexemes and strict revision boundary" begin
    morning = fixture_observation(MORNING_WINDOW_ENDPOINT_OBSERVATION)
    just_over_body = replace_first_numeric_lexeme(
        fixture_body("rate"; revision = "r", rate = 3.64),
        "percentRate",
        "3.6400000000000001",
    )
    just_over = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = just_over_body,
        volume_body = fixture_body("volume"; revision = "r"),
    )
    just_over_decision = adjudicate_transition(
        morning,
        just_over,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test just_over_decision["decision"]["outcome"] ==
        "MARKED_SAME_DAY_REVISION_OBSERVED"
    @test Contract._field(just_over.rate, "percentRate") ==
        "3.6400000000000001"
    @test just_over_decision["decision"]["later_percent_rate_lexeme"] ==
        "3.6400000000000001"
    @test just_over_decision["decision"]["rate_change_basis_points_numerator"] ==
        "100000000000001"
    @test just_over_decision["decision"]["rate_change_basis_points_denominator"] ==
        "100000000000000"

    equivalent_lexeme_body = replace_first_numeric_lexeme(
        fixture_body("rate"),
        "percentRate",
        "3.6300",
    )
    equivalent_lexeme = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = equivalent_lexeme_body,
    )
    @test equivalent_lexeme.rate.selected_row_sha256 ==
        morning.rate.selected_row_sha256
    @test equivalent_lexeme.rate.selected_value_sha256 ==
        morning.rate.selected_value_sha256
    @test equivalent_lexeme.rate.raw_sha256 != morning.rate.raw_sha256
    equivalent_lexeme_decision = adjudicate_transition(
        morning,
        equivalent_lexeme,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test equivalent_lexeme_decision["decision"]["outcome"] ==
        "QUARANTINED_FULL_RESPONSE_CHANGED_WITHOUT_EFFR_TRANSITION"
    @test equivalent_lexeme_decision["decision"]["later_percent_rate_lexeme"] ==
        "3.6300"
    @test equivalent_lexeme_decision["decision"]["rate_change_basis_points_numerator"] ==
        "0"
    @test equivalent_lexeme_decision["decision"]["rate_change_basis_points_denominator"] ==
        "1"

    exponent_just_over_body = replace_first_numeric_lexeme(
        fixture_body("rate"; revision = "r", rate = 3.64),
        "percentRate",
        "36400000000000001e-16",
    )
    exponent_just_over = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = exponent_just_over_body,
        volume_body = fixture_body("volume"; revision = "r"),
    )
    exponent_decision = adjudicate_transition(
        morning,
        exponent_just_over,
        binding(morning; predecessor_decision = HEX_C),
    )
    @test exponent_decision["decision"]["outcome"] ==
        "MARKED_SAME_DAY_REVISION_OBSERVED"
    @test exponent_decision["decision"]["later_percent_rate_lexeme"] ==
        "36400000000000001e-16"
    @test exponent_decision["decision"]["rate_change_basis_points_numerator"] ==
        "100000000000001"
    @test exponent_decision["decision"]["rate_change_basis_points_denominator"] ==
        "100000000000000"

    for boundary_lexeme in ("3.6400000000000000", "364e-2")
        boundary_body = replace_first_numeric_lexeme(
            fixture_body("rate"; revision = "r", rate = 3.64),
            "percentRate",
            boundary_lexeme,
        )
        boundary = fixture_observation(
            POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
            rate_body = boundary_body,
            volume_body = fixture_body("volume"; revision = "r"),
        )
        boundary_decision = adjudicate_transition(
            morning,
            boundary,
            binding(morning; predecessor_decision = HEX_C),
        )
        @test boundary_decision["decision"]["outcome"] ==
            "QUARANTINED_MARKED_REVISION_POLICY_INCONSISTENT"
        @test boundary_decision["decision"]["later_percent_rate_lexeme"] ==
            boundary_lexeme
        @test boundary_decision["decision"]["rate_change_basis_points_numerator"] ==
            "1"
        @test boundary_decision["decision"]["rate_change_basis_points_denominator"] ==
            "1"
    end

    negative_morning = fixture_observation(
        MORNING_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = fixture_body("rate"; rate = -0.02),
    )
    negative_later_body = replace_first_numeric_lexeme(
        fixture_body("rate"; revision = "r", rate = -0.03),
        "percentRate",
        "-0.0300000000000001",
    )
    negative_later = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = negative_later_body,
        volume_body = fixture_body("volume"; revision = "r"),
    )
    negative_decision = adjudicate_transition(
        negative_morning,
        negative_later,
        binding(negative_morning; predecessor_decision = HEX_C),
    )
    @test negative_decision["decision"]["outcome"] ==
        "MARKED_SAME_DAY_REVISION_OBSERVED"
    @test negative_decision["decision"]["morning_percent_rate_lexeme"] ==
        "-0.02"
    @test negative_decision["decision"]["later_percent_rate_lexeme"] ==
        "-0.0300000000000001"
    @test negative_decision["decision"]["rate_change_basis_points_numerator"] ==
        "100000000000001"
    @test negative_decision["decision"]["rate_change_basis_points_denominator"] ==
        "100000000000000"

    numeric_limit_cases = (
        (
            "3." * repeat("6", 40),
            "NUMBER_PRECISION_LIMIT_EXCEEDED",
        ),
        ("3.64e21", "NUMBER_EXPONENT_LIMIT_EXCEEDED"),
        (
            "0." * repeat("0", 95),
            "NUMBER_TOKEN_LIMIT_EXCEEDED",
        ),
        (
            "-3." * repeat("6", 40),
            "NUMBER_PRECISION_LIMIT_EXCEEDED",
        ),
    )
    for (lexeme, expected) in numeric_limit_cases
        body = replace_first_numeric_lexeme(
            fixture_body("rate"),
            "percentRate",
            lexeme,
        )
        @test error_code(
            () -> validate_report(
                fixture_capture(
                    "rate",
                    MORNING_WINDOW_ENDPOINT_OBSERVATION;
                    body,
                ),
                PUBLICATION_DATE,
                EFFECTIVE_DATE,
                MORNING_WINDOW_ENDPOINT_OBSERVATION,
            ),
        ) == expected
    end

    leading_zero_exponent = Contract._exact_json_number(
        "1e+000000000000000000020",
        "test exponent",
    )
    @test leading_zero_exponent.value == big(10)^20 // big(1)

    sub_float_ordering = replace_first_numeric_lexeme(
        fixture_body("rate"),
        "percentPercentile1",
        "3.6200000000000001",
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = sub_float_ordering,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "RATE_ORDERING_VIOLATION"

    sub_float_target = replace_first_numeric_lexeme(
        fixture_body("rate"),
        "targetRateFrom",
        "3.7500000000000001",
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "rate",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = sub_float_target,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "TARGET_RANGE_VIOLATION"

    negative_sub_float_volume = replace_first_numeric_lexeme(
        fixture_body("volume"),
        "volumeInBillions",
        "-1e-20",
    )
    @test error_code(
        () -> validate_report(
            fixture_capture(
                "volume",
                MORNING_WINDOW_ENDPOINT_OBSERVATION;
                body = negative_sub_float_volume,
            ),
            PUBLICATION_DATE,
            EFFECTIVE_DATE,
            MORNING_WINDOW_ENDPOINT_OBSERVATION,
        ),
    ) == "RANGE_VIOLATION"

    forged = deepcopy(just_over_decision)
    forged["decision"]["rate_change_basis_points_numerator"] =
        "100000000000000"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "EXACT_RATE_CHANGE_MISMATCH"

    forged = deepcopy(just_over_decision)
    forged["decision"]["rate_change_basis_points_denominator"] =
        "0100000000000000"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "NONCANONICAL_EXACT_RATIONAL"

    boundary = fixture_observation(
        POST_REVISION_WINDOW_ENDPOINT_OBSERVATION;
        rate_body = replace_first_numeric_lexeme(
            fixture_body("rate"; revision = "r", rate = 3.64),
            "percentRate",
            "3.6400000000000000",
        ),
        volume_body = fixture_body("volume"; revision = "r"),
    )
    forged = adjudicate_transition(
        morning,
        boundary,
        binding(morning; predecessor_decision = HEX_C),
    )
    forged["decision"]["outcome"] = "MARKED_SAME_DAY_REVISION_OBSERVED"
    forged["decision"]["claim"] = "MARKED_SAME_DAY_REVISION_OBSERVED"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "DECISION_RECOMPUTATION_MISMATCH"

    forged = deepcopy(just_over_decision)
    forged["decision"]["later_revision_token"] = ""
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "DECISION_RECOMPUTATION_MISMATCH"

    forged = deepcopy(just_over_decision)
    filter!(
        blocker -> blocker != "LATER_OR_EXTRAORDINARY_CORRECTION_NOT_RULED_OUT",
        forged["blockers"],
    )
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "BLOCKER_RECOMPUTATION_MISMATCH"
end

@testset "bindings, self-rehash, and timestamp non-elevation" begin
    morning = fixture_observation(MORNING_WINDOW_ENDPOINT_OBSERVATION)
    later = fixture_observation(POST_REVISION_WINDOW_ENDPOINT_OBSERVATION)

    @test error_code(
        () -> adjudicate_transition(
            morning,
            later,
            DecisionBinding(
                decision_id = "effr-20260807-observed-state-v3",
                created_at_utc = DateTime(2026, 8, 7, 19),
                predecessor_observation_sha256 = HEX_A,
                predecessor_decision_sha256 = HEX_B,
                superseded_capture_manifest_sha256 = HEX_C,
            ),
        ),
    ) == "PREDECESSOR_MISMATCH"

    @test error_code(
        () -> adjudicate_transition(
            morning,
            later,
            binding(
                morning;
                created_at = DateTime(2026, 8, 7, 18, 30),
            ),
        ),
    ) == "BACKDATING_FORBIDDEN"

    @test error_code(
        () -> adjudicate_transition(
            morning,
            later,
            binding(
                morning;
                superseded_contract_schema_version = "Other",
            ),
        ),
    ) == "SUPERSESSION_MISMATCH"

    @test error_code(
        () -> adjudicate_transition(
            morning,
            later,
            binding(
                morning;
                superseded_receipt_status = "CREATED",
            ),
        ),
    ) == "SUPERSESSION_MISMATCH"

    @test error_code(
        () -> adjudicate_transition(
            morning,
            later,
            binding(
                morning;
                supersession_mode = "MUTATE_V2",
            ),
        ),
    ) == "MUTATION_OR_BACKDATING_FORBIDDEN"

    @test error_code(
        () -> adjudicate_transition(
            morning,
            later,
            binding(
                morning;
                timestamp_status = "NOT_PROVIDED",
                timestamp_hash = HEX_A,
            ),
        ),
    ) == "TIMESTAMP_BINDING_MISMATCH"

    timestamped = adjudicate_transition(
        morning,
        later,
        binding(
            morning;
            timestamp_status =
                "CALLER_ASSERTED_RFC3161_TOKEN_NOT_CRYPTOGRAPHICALLY_VERIFIED",
            timestamp_hash = HEX_C,
        ),
    )
    @test timestamped["binding"]["timestamp_token_sha256"] == HEX_C
    @test timestamped["gates"]["external_timestamp_authenticated"] === false
    @test timestamped["gates"]["publisher_provenance_authenticated"] === false
    @test timestamped["evidence_layers"]["external_timestamp_authenticated"] ===
        false
    @test timestamped["evidence_layers"]["publisher_provenance_authenticated"] ===
        false

    forged = deepcopy(timestamped)
    forged["artifact"]["canonicalization"] = "UNSUPPORTED"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "CANONICALIZATION_CHANGED"

    forged = deepcopy(timestamped)
    forged["decision"]["later_revision_token"] = "r"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "TRANSITION_FACT_INCONSISTENT"

    forged = deepcopy(timestamped)
    forged["decision"]["later_percent_rate_lexeme"] = "3.630"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "TRANSITION_FACT_INCONSISTENT"

    forged = deepcopy(timestamped)
    forged["decision"]["later_observation_sha256"] =
        forged["decision"]["morning_observation_sha256"]
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "TRANSITION_OBSERVATION_COLLISION"

    forged = deepcopy(timestamped)
    forged["decision"]["morning_pair_as_of_utc"] = DateTime(2026, 8, 7, 0)
    forged["decision"]["later_pair_as_of_utc"] = DateTime(2026, 8, 7, 0, 1)
    forged["decision"]["latest_evidence_observed_at_utc"] =
        DateTime(2026, 8, 7, 0, 2)
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "DECISION_WINDOW_VIOLATION"

    original_pin = timestamped["artifact"]["decision_sha256"]
    forged = deepcopy(timestamped)
    forged["gates"]["publisher_provenance_authenticated"] = true
    restamp_decision!(forged)
    forged_pin = forged["artifact"]["decision_sha256"]
    @test forged_pin != original_pin
    @test error_code(
        () -> validate_decision_document(forged, forged_pin),
    ) == "TRUST_ELEVATION_FORBIDDEN"
    @test error_code(
        () -> validate_decision_document(forged, original_pin),
    ) == "OUT_OF_BAND_PIN_MISMATCH"

    forged = deepcopy(timestamped)
    forged["estimand"]["status"] = "SELECTED"
    forged["estimand"]["selected_estimand"] =
        "PRE_ORIGIN_OBSERVED_ENDPOINT_VINTAGE"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "ESTIMAND_PRESELECTION_FORBIDDEN"

    forged = deepcopy(timestamped)
    forged["current_state_disposition"]["raw_false_derivation_allowed"] = true
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "TRUST_ELEVATION_FORBIDDEN"

    forged = deepcopy(timestamped)
    forged["decision"]["final_state_for_day_claimed"] = true
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "TRUST_ELEVATION_FORBIDDEN"

    forged = deepcopy(timestamped)
    forged["artifact"]["decision_sha256"] = HEX_A
    @test error_code(
        () -> validate_decision_document(forged, HEX_A),
    ) == "DECISION_DIGEST_MISMATCH"

    forged = deepcopy(timestamped)
    forged["decision"]["claim"] = "NO_REVISION_FOR_DAY_FINAL_STATE"
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "CLAIM_CEILING_VIOLATION"

    forged = deepcopy(timestamped)
    forged["binding"]["predecessor_observation_sha256"] = HEX_A
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "PREDECESSOR_MISMATCH"

    forged = deepcopy(timestamped)
    forged["binding"]["created_at_utc"] = DateTime(2026, 8, 7, 18, 30)
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "BACKDATING_FORBIDDEN"

    forged = deepcopy(timestamped)
    forged["decision"]["latest_evidence_observed_at_utc"] =
        DateTime(2026, 8, 7, 12)
    restamp_decision!(forged)
    @test error_code(
        () -> validate_decision_document(
            forged,
            forged["artifact"]["decision_sha256"],
        ),
    ) == "DECISION_TIME_ORDER_VIOLATION"
end

@testset "offline implementation has no capture or raw-write surface" begin
    source = read(
        joinpath(@__DIR__, "USEFFRObservedStateContractV3.jl"),
        String,
    )
    @test !occursin("using Downloads", source)
    @test !occursin("using HTTP", source)
    @test !occursin("download(", source)
    @test !occursin("data/us/raw", source)
    @test !occursin("open(path, \"w\"", source)
    @test !occursin("write(", source)
    @test validate_protocol()["gates"]["source_inventory_mutation_allowed"] ===
        false
end
