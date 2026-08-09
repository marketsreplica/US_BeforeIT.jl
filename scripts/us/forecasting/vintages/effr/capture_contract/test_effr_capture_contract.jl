using Test

include(joinpath(@__DIR__, "USEFFRCaptureContract.jl"))
using .USEFFRCaptureContract

const HEX_A = repeat("a", 64)
const HEX_B = repeat("b", 64)
const HEX_C = repeat("c", 64)
const HEX_D = repeat("d", 64)
const HEX_E = repeat("e", 64)

function raw_fields(report_type, state_class; footnote = "", blank_field = nothing)
    revision = state_class == "FIRST_0900_STATE" ? "" :
        state_class in ("SAME_DAY_1430_REVISION", "LATER_CORRECTION") ? "r" : ""
    current = state_class == "CURRENT_STATE"
    not_requested = "NOT_REQUESTED_IN_REPORT_TYPE"
    row = Dict{String, Any}(
        "effectiveDate" => "2026-08-06",
        "type" => report_type,
        "percentRate" => report_type == "rate" ? 4.33 : not_requested,
        "percentPercentile1" => report_type == "rate" ? 4.3 : not_requested,
        "percentPercentile25" => report_type == "rate" ? 4.32 : not_requested,
        "percentPercentile75" => report_type == "rate" ? 4.34 : not_requested,
        "percentPercentile99" => report_type == "rate" ? 4.38 : not_requested,
        "targetRateFrom" => report_type == "rate" ? 4.25 : not_requested,
        "targetRateTo" => report_type == "rate" ? 4.5 : not_requested,
        "volumeInBillions" => report_type == "volume" ? 79 : not_requested,
        "footnote" => footnote,
        "revisionIndicator" => revision,
        "currentState" => current,
    )
    blank_field === nothing || (row[blank_field] = "")
    return row
end

function receipt(
        report_type = "rate",
        state_class = "FIRST_0900_STATE";
        effective_date = "2026-08-06",
        publication_date = state_class == "LATER_CORRECTION" ?
            "2026-08-10" : "2026-08-07",
        publication_utc_offset = "-04:00",
        request_started_at_utc = state_class == "SAME_DAY_1430_REVISION" ?
            "2026-08-07T18:30:00.000Z" :
            state_class == "LATER_CORRECTION" ?
            "2026-08-10T16:00:00.000Z" :
            "2026-08-07T13:00:00.000Z",
        response_headers_at_utc = state_class == "SAME_DAY_1430_REVISION" ?
            "2026-08-07T18:30:00.100Z" :
            state_class == "LATER_CORRECTION" ?
            "2026-08-10T16:00:00.100Z" :
            "2026-08-07T13:00:00.100Z",
        response_body_completed_at_utc =
            state_class == "SAME_DAY_1430_REVISION" ?
            "2026-08-07T18:30:00.200Z" :
            state_class == "LATER_CORRECTION" ?
            "2026-08-10T16:00:00.200Z" :
            "2026-08-07T13:00:00.200Z",
        footnote = "",
        blank_field = nothing,
        schema_mismatch = false,
        terms_decision = "APPROVED_FOR_BOUNDED_CAPTURE",
        terms_snapshot_sha256 = HEX_E,
        terms_snapshot_date = publication_date,
        attribution_requirement = nothing,
        disclaimer_requirement = nothing,
        redistribution_scope = nothing,
        openapi_sha256 = HEX_C,
        predecessor = "NONE",
    )
    revision = state_class == "FIRST_0900_STATE" ? "" :
        state_class in ("SAME_DAY_1430_REVISION", "LATER_CORRECTION") ? "r" : ""
    encoded_revision = isempty(revision) ? "EMPTY" : revision
    publication_window = Dict(
        "FIRST_0900_STATE" => "NYFED_APPROX_0900_ET",
        "SAME_DAY_1430_REVISION" => "NYFED_APPROX_1430_ET",
        "LATER_CORRECTION" => "EXTRAORDINARY_LATER_CORRECTION",
        "CURRENT_STATE" => "CURRENT_API_OBSERVATION_TIME",
    )[state_class]
    raw = raw_fields(
        report_type,
        state_class;
        footnote = footnote,
        blank_field = blank_field,
    )
    raw["effectiveDate"] = effective_date
    schema_class = if schema_mismatch
        "SCHEMA_MISMATCH_QUARANTINED"
    elseif revision == "r"
        "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET"
    else
        "PINNED_CURRENT_API_EXACT_FIELDSET"
    end
    quarantine =
        schema_mismatch || blank_field !== nothing ?
        "QUARANTINED_PENDING_MATCHED_STATE_REVIEW" : "NOT_QUARANTINED"
    blockers = Set(
        (
            "EMPIRICAL_EXECUTION_FORBIDDEN",
            "HISTORICAL_FIRST_BYTES_UNPROVEN",
            "ORIGIN_ADMISSION_FORBIDDEN",
            "PRODUCTION_USE_FORBIDDEN",
            "PROMOTION_FORBIDDEN",
            "RATE_VOLUME_PAIR_NOT_YET_VALIDATED",
            "READINESS_FALSE",
        ),
    )
    state_class == "CURRENT_STATE" &&
        push!(blockers, "CURRENT_API_NOT_HISTORICAL_VINTAGE")
    revision == "r" &&
        push!(blockers, "OPENAPI_EXAMPLE_MISMATCH_PRESERVED")
    blank_field === nothing ||
        push!(blockers, "UNSUPPORTED_BLANK_UNKNOWN_NOT_ZERO")
    terms_decision == "PENDING_PROJECT_SPECIFIC_REVIEW" &&
        push!(blockers, "TERMS_REVIEW_PENDING")
    terms_decision == "REJECTED" &&
        push!(blockers, "TERMS_REVIEW_REJECTED")
    schema_mismatch && push!(blockers, "SCHEMA_MISMATCH")
    quarantine == "QUARANTINED_PENDING_MATCHED_STATE_REVIEW" &&
        push!(blockers, "MATCHED_STATE_REVIEW_REQUIRED")
    query = "endDate=$effective_date&startDate=$effective_date&type=$report_type"
    expected_governance = if terms_decision == "APPROVED_FOR_BOUNDED_CAPTURE" &&
            redistribution_scope != "PUBLIC_DERIVED_ONLY"
        (
            attribution =
                "ATTRIBUTION_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK",
            disclaimer =
                "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_DERIVED_USE",
            redistribution = "INTERNAL_RESEARCH_ONLY",
        )
    elseif terms_decision == "APPROVED_FOR_BOUNDED_CAPTURE"
        (
            attribution =
                "ATTRIBUTION_AND_DERIVATIVE_LABEL_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK",
            disclaimer =
                "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_PUBLIC_DERIVED_USE",
            redistribution = "PUBLIC_DERIVED_ONLY",
        )
    elseif terms_decision == "PENDING_PROJECT_SPECIFIC_REVIEW"
        (
            attribution = "ATTRIBUTION_REQUIREMENT_PENDING_REVIEW",
            disclaimer = "DISCLAIMER_REQUIREMENT_PENDING_REVIEW",
            redistribution = "PROHIBITED",
        )
    else
        (
            attribution = "USE_REJECTED_ATTRIBUTION_NOT_APPLICABLE",
            disclaimer = "USE_REJECTED_DISCLAIMER_NOT_APPLICABLE",
            redistribution = "PROHIBITED",
        )
    end
    attribution_requirement === nothing &&
        (attribution_requirement = expected_governance.attribution)
    disclaimer_requirement === nothing &&
        (disclaimer_requirement = expected_governance.disclaimer)
    redistribution_scope === nothing &&
        (redistribution_scope = expected_governance.redistribution)
    document = Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "receipt_id" =>
            "EFFR:$effective_date:$(uppercase(report_type)):$(state_class)",
        "source" => Dict(
            "authority" => "Federal Reserve Bank of New York",
            "source_id" => "NYFED_MARKETS_API",
            "series_id" => "EFFR",
            "evidence_track" => state_class == "CURRENT_STATE" ?
                "CURRENT_REVISED_PROXY" : "STRICT_FIRST_PUBLIC_BYTES",
            "concept_regime" => "POST_2016_FR2420_VOLUME_WEIGHTED_MEDIAN",
            "route_class" => state_class == "CURRENT_STATE" ?
                "NYFED_CURRENT_API" : "NYFED_PROSPECTIVE_CAPTURE",
            "historical_vintage_claim" =>
                "CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE",
        ),
        "observation" => Dict(
            "effective_date" => effective_date,
            "publication_date" => publication_date,
            "publication_utc_offset" => publication_utc_offset,
            "report_type" => report_type,
            "state_class" => state_class,
            "scheduled_publication_window" => publication_window,
            "pair_key" =>
                "effectiveDate=$effective_date;revisionToken=$encoded_revision",
        ),
        "request" => Dict(
            "endpoint" =>
                "https://markets.newyorkfed.org/api/rates/all/search.json",
            "canonical_query" => query,
            "requested_url" =>
                "https://markets.newyorkfed.org/api/rates/all/search.json?$query",
            "request_started_at_utc" => request_started_at_utc,
            "secret_ref" => "NOT_REQUIRED_PUBLIC_ENDPOINT",
        ),
        "response" => Dict(
            "response_headers_at_utc" => response_headers_at_utc,
            "response_body_completed_at_utc" =>
                response_body_completed_at_utc,
            "availability_upper_bound_utc" =>
                response_body_completed_at_utc,
            "http_status" => 200,
            "final_host" => "markets.newyorkfed.org",
            "final_url" =>
                "https://markets.newyorkfed.org/api/rates/all/search.json?$query",
            "redirect_count" => 0,
            "redirect_chain" => Any[],
            "headers_complete" => true,
            "content_type" => "application/json",
            "content_encoding" => "identity",
            "content_length" => report_type == "rate" ? 723 : 212,
        ),
        "artifact" => Dict(
            "raw_sha256" => report_type == "rate" ? HEX_A : HEX_B,
            "openapi_sha256" => openapi_sha256,
            "durable_storage_locator" =>
                "artifact-sha256:" * (report_type == "rate" ? HEX_A : HEX_B),
            "durable_storage_receipt_sha256" => HEX_D,
        ),
        "raw_fields" => raw,
        "classification" => Dict(
            "revision_class" => isempty(revision) ?
                "NOT_REVISED_RAW_EMPTY_TOKEN" :
                "DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH",
            "footnote_class" => Dict(
                "" => "NO_FOOTNOTE_RAW_EMPTY_TOKEN",
                "1" => "DOCUMENTED_REDUCED_VOLUME",
                "2" => "DOCUMENTED_BROKER_CONTINGENCY",
                "3" => "DOCUMENTED_PRIOR_DAY_REPUBLICATION",
            )[footnote],
            "rate_report_volume_class" => report_type == "rate" ?
                "NOT_REQUESTED_IN_REPORT_TYPE" : "PUBLISHED_VOLUME_FIELD",
            "unsupported_blank_class" => blank_field === nothing ?
                "NO_UNSUPPORTED_BLANK" : "UNKNOWN_NOT_ZERO",
            "current_state_class" => state_class == "CURRENT_STATE" ?
                "CURRENT_STATE_FLAG_NOT_VINTAGE" : "NOT_CURRENT_STATE_FLAG",
            "schema_class" => schema_class,
            "schema_mismatch_detail" => schema_mismatch ?
                "response envelope did not match the pinned object path" : "NONE",
            "quarantine_class" => quarantine,
            "adjudication_state" =>
                quarantine == "NOT_QUARANTINED" ?
                "NOT_REQUIRED_EXACT_SCHEMA" :
                "PENDING_INDEPENDENT_MATCHED_STATE_REVIEW",
            "evidence_locator" =>
                "artifact-sha256:" * (report_type == "rate" ? HEX_A : HEX_B),
            "blockers" => sort!(collect(blockers)),
        ),
        "governance" => Dict(
            "terms_url" => "https://www.newyorkfed.org/privacy/termsofuse",
            "terms_snapshot_sha256" => terms_snapshot_sha256,
            "terms_snapshot_date" => terms_snapshot_date,
            "terms_review_decision" => terms_decision,
            "attribution_requirement" => attribution_requirement,
            "disclaimer_requirement" => disclaimer_requirement,
            "redistribution_scope" => redistribution_scope,
            "secret_ref" => "NOT_REQUIRED_PUBLIC_ENDPOINT",
        ),
        "lineage" => Dict(
            "predecessor_receipt_sha256" => predecessor,
            "supersedes_receipt_sha256" => predecessor,
            "supersession_status" => predecessor == "NONE" ?
                "NEW_NONOVERWRITING_STATE" :
                "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE",
        ),
        "gates" => Dict(
            "historical_first_byte_proven" => false,
            "origin_admissible" => false,
            "empirical_forecast_allowed" => false,
            "source_inventory_mutation_allowed" => false,
            "promotion_eligible" => false,
            "production_scoring_allowed" => false,
            "readiness" => false,
            "current_api_proves_historical_vintage" => false,
        ),
        "receipt_sha256" => repeat("0", 64),
    )
    document["receipt_sha256"] = canonical_receipt_sha256(document)
    return document
end

function validation_error(document; pin = document["receipt_sha256"])
    try
        validate_receipt(document, pin)
    catch error
        return sprint(showerror, error)
    end
    return "NO_ERROR"
end

function restamp!(document)
    document["receipt_sha256"] = canonical_receipt_sha256(document)
    return document
end

@testset "immutable closed contract" begin
    contract = trusted_contract()
    @test contract.schema_version == SCHEMA_VERSION
    @test getproperty.(contract.state_classes, :state_class) == (
        "FIRST_0900_STATE",
        "SAME_DAY_1430_REVISION",
        "LATER_CORRECTION",
        "ALFRED_DATE_STATE",
        "CURRENT_STATE",
    )
    @test contract.state_classes[4].vintage_scope ==
        "DATE_LEVEL_VINTAGE_NOT_INTRADAY"
    @test contract.state_classes[5].vintage_scope ==
        "CURRENT_STATE_FLAG_NOT_VINTAGE"
    @test all(
        state.overwrite_policy != "OVERWRITE" for
            state in contract.state_classes
    )
    @test contract.raw_byte_input == "NOT_ACCEPTED_BY_THIS_MODULE"
    @test contract.filesystem_path_input == "NOT_ACCEPTED_BY_THIS_MODULE"
    @test contract.network_client == "ABSENT"
    @test all(!value for value in values(contract.gates))
    @test contract.footnote_classes.footnote_1 ==
        "DOCUMENTED_REDUCED_VOLUME"
    @test contract.footnote_classes.footnote_2 ==
        "DOCUMENTED_BROKER_CONTINGENCY"
    @test contract.footnote_classes.footnote_3 ==
        "DOCUMENTED_PRIOR_DAY_REPUBLICATION"
end

@testset "first-state receipts and exact rate-volume pairing" begin
    rate = receipt("rate")
    volume = receipt("volume")
    validated_rate = validate_receipt(rate, rate["receipt_sha256"])
    validated_volume = validate_receipt(volume, volume["receipt_sha256"])
    @test validated_rate.raw_fields.percentRate == 4.33
    @test validated_rate.raw_fields.volumeInBillions ==
        "NOT_REQUESTED_IN_REPORT_TYPE"
    @test validated_volume.raw_fields.volumeInBillions == 79.0
    @test validated_rate.classification.revision_class ==
        "NOT_REVISED_RAW_EMPTY_TOKEN"
    @test validated_rate.classification.rate_report_volume_class ==
        "NOT_REQUESTED_IN_REPORT_TYPE"
    @test validated_rate.response.availability_upper_bound_utc ==
        validated_rate.response.response_body_completed_at_utc
    @test validated_rate.request.canonical_query ==
        "endDate=2026-08-06&startDate=2026-08-06&type=rate"
    @test all(!value for value in values(validated_rate.gates))
    @test isimmutable(validated_rate)
    @test_throws ErrorException setproperty!(
        validated_rate,
        :receipt_id,
        "CHANGED",
    )

    pair = pair_receipts(
        rate,
        rate["receipt_sha256"],
        volume,
        volume["receipt_sha256"],
    )
    @test pair.pair_status ==
        "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT"
    @test pair.joined_record.effective_date == "2026-08-06"
    @test pair.joined_record.revision_token == ""
    @test pair.joined_record.volume_in_billions == 79.0
    @test pair.joined_record.pairing_rule ==
        "EXACT_DATE_TOKEN_STATE_PUBLICATION_OPENAPI_GOVERNANCE_CONTEXT"
    @test pair.joined_record.overwrite_policy ==
        "NEW_IMMUTABLE_JOINED_RECORD"
    @test !pair.origin_admissible
    @test !pair.empirical_forecast_allowed
    @test !pair.promotion_eligible
    @test !pair.production_scoring_allowed
    @test !pair.readiness
end

@testset "revision, later-correction, and current-state classes" begin
    for state_class in ("SAME_DAY_1430_REVISION", "LATER_CORRECTION")
        rate = receipt(
            "rate",
            state_class;
            predecessor = HEX_E,
        )
        volume = receipt(
            "volume",
            state_class;
            predecessor = HEX_E,
        )
        validated = validate_receipt(rate, rate["receipt_sha256"])
        @test validated.raw_fields.revisionIndicator == "r"
        @test validated.classification.revision_class ==
            "DOCUMENTED_REVISED_RAW_TOKEN_WITH_SCHEMA_MISMATCH"
        @test validated.classification.schema_class ==
            "DOCUMENTED_OPENAPI_EXAMPLE_MISMATCH_PINNED_FIELDSET"
        @test validated.lineage.supersession_status ==
            "SUPERSEDES_BY_POINTER_WITHOUT_OVERWRITE"
        @test "OPENAPI_EXAMPLE_MISMATCH_PRESERVED" in
            validated.classification.blockers
        pair = pair_receipts(
            rate,
            rate["receipt_sha256"],
            volume,
            volume["receipt_sha256"],
        )
        @test pair.pair_status ==
            "PAIR_VALIDATED_EXACT_STATE_SCHEMA_AND_GOVERNANCE_CONTEXT"
        @test pair.joined_record.revision_token == "r"
    end

    current = receipt("rate", "CURRENT_STATE")
    validated = validate_receipt(current, current["receipt_sha256"])
    @test validated.raw_fields.currentState
    @test validated.classification.current_state_class ==
        "CURRENT_STATE_FLAG_NOT_VINTAGE"
    @test validated.source.evidence_track == "CURRENT_REVISED_PROXY"
    @test validated.source.historical_vintage_claim ==
        "CURRENT_API_DOES_NOT_PROVE_HISTORICAL_VINTAGE"
    @test "CURRENT_API_NOT_HISTORICAL_VINTAGE" in
        validated.classification.blockers
    @test !validated.gates.current_api_proves_historical_vintage
end

@testset "New York publication clock and lag are enforced" begin
    daylight = receipt(
        "rate";
        effective_date = "2026-03-06",
        publication_date = "2026-03-09",
        publication_utc_offset = "-04:00",
        request_started_at_utc = "2026-03-09T13:00:00.000Z",
        response_headers_at_utc = "2026-03-09T13:00:00.100Z",
        response_body_completed_at_utc = "2026-03-09T13:00:00.200Z",
    )
    @test validate_receipt(daylight, daylight["receipt_sha256"]).
    observation.publication_utc_offset == "-04:00"

    standard = receipt(
        "rate";
        effective_date = "2026-01-02",
        publication_date = "2026-01-05",
        publication_utc_offset = "-05:00",
        request_started_at_utc = "2026-01-05T14:00:00.000Z",
        response_headers_at_utc = "2026-01-05T14:00:00.100Z",
        response_body_completed_at_utc = "2026-01-05T14:00:00.200Z",
    )
    @test validate_receipt(standard, standard["receipt_sha256"]).
    observation.publication_utc_offset == "-05:00"

    wrong_offset = deepcopy(daylight)
    wrong_offset["observation"]["publication_utc_offset"] = "-05:00"
    restamp!(wrong_offset)
    @test occursin(
        "expected \"-04:00\"",
        validation_error(wrong_offset),
    )

    weekend_publication = receipt(
        "rate";
        publication_date = "2026-08-08",
        request_started_at_utc = "2026-08-08T13:00:00.000Z",
        response_headers_at_utc = "2026-08-08T13:00:00.100Z",
        response_body_completed_at_utc = "2026-08-08T13:00:00.200Z",
    )
    @test occursin(
        "Monday-through-Friday",
        validation_error(weekend_publication),
    )

    weekend_effective = receipt(
        "rate";
        effective_date = "2026-08-01",
        publication_date = "2026-08-03",
        request_started_at_utc = "2026-08-03T13:00:00.000Z",
        response_headers_at_utc = "2026-08-03T13:00:00.100Z",
        response_body_completed_at_utc = "2026-08-03T13:00:00.200Z",
    )
    @test occursin(
        "Monday-through-Friday",
        validation_error(weekend_effective),
    )

    retrospective_first = receipt(
        "rate";
        effective_date = "2017-05-31",
    )
    @test occursin(
        "strict intraday state requires",
        validation_error(retrospective_first),
    )

    retrospective_current = receipt(
        "rate",
        "CURRENT_STATE";
        effective_date = "2017-05-31",
    )
    @test validate_receipt(
        retrospective_current,
        retrospective_current["receipt_sha256"],
    ).observation.state_class == "CURRENT_STATE"

    midnight_first = receipt(
        "rate";
        request_started_at_utc = "2026-08-07T00:00:00.000Z",
        response_headers_at_utc = "2026-08-07T00:00:00.100Z",
        response_body_completed_at_utc = "2026-08-07T00:00:00.200Z",
    )
    @test occursin(
        "declared New York publication date",
        validation_error(midnight_first),
    )

    early_revision = receipt(
        "rate",
        "SAME_DAY_1430_REVISION";
        predecessor = HEX_E,
        request_started_at_utc = "2026-08-07T13:00:00.000Z",
        response_headers_at_utc = "2026-08-07T13:00:00.100Z",
        response_body_completed_at_utc = "2026-08-07T13:00:00.200Z",
    )
    @test occursin(
        "inside [14:30,24:00)",
        validation_error(early_revision),
    )

    first_crosses_revision = receipt(
        "rate";
        request_started_at_utc = "2026-08-07T18:29:59.900Z",
        response_headers_at_utc = "2026-08-07T18:29:59.950Z",
        response_body_completed_at_utc = "2026-08-07T18:30:00.000Z",
    )
    @test occursin(
        "inside [09:00,14:30)",
        validation_error(first_crosses_revision),
    )

    pre_concept = receipt(
        "rate";
        effective_date = "2016-02-29",
        publication_date = "2016-03-01",
        request_started_at_utc = "2016-03-01T14:00:00.000Z",
        response_headers_at_utc = "2016-03-01T14:00:00.100Z",
        response_body_completed_at_utc = "2016-03-01T14:00:00.200Z",
        terms_snapshot_date = "2016-03-01",
    )
    @test occursin(
        "post-2016 EFFR concept regime",
        validation_error(pre_concept),
    )

    mislabeled_later = receipt(
        "rate",
        "LATER_CORRECTION";
        publication_date = "2026-08-07",
        request_started_at_utc = "2026-08-07T19:00:00.000Z",
        response_headers_at_utc = "2026-08-07T19:00:00.100Z",
        response_body_completed_at_utc = "2026-08-07T19:00:00.200Z",
        predecessor = HEX_E,
    )
    @test occursin(
        "later correction requires",
        validation_error(mislabeled_later),
    )
end

@testset "footnotes and unsupported blank remain typed" begin
    expected = Dict(
        "1" => "DOCUMENTED_REDUCED_VOLUME",
        "2" => "DOCUMENTED_BROKER_CONTINGENCY",
        "3" => "DOCUMENTED_PRIOR_DAY_REPUBLICATION",
    )
    for (token, classification) in expected
        document = receipt("rate"; footnote = token)
        validated =
            validate_receipt(document, document["receipt_sha256"])
        @test validated.raw_fields.footnote == token
        @test validated.classification.footnote_class == classification
    end

    rate = receipt("rate"; blank_field = "targetRateFrom")
    volume = receipt("volume")
    validated = validate_receipt(rate, rate["receipt_sha256"])
    @test validated.raw_fields.targetRateFrom == ""
    @test validated.blank_fields == ("targetRateFrom",)
    @test validated.classification.unsupported_blank_class ==
        "UNKNOWN_NOT_ZERO"
    @test validated.classification.quarantine_class ==
        "QUARANTINED_PENDING_MATCHED_STATE_REVIEW"
    @test "UNSUPPORTED_BLANK_UNKNOWN_NOT_ZERO" in
        validated.classification.blockers
    pair = pair_receipts(
        rate,
        rate["receipt_sha256"],
        volume,
        volume["receipt_sha256"],
    )
    @test pair.pair_status ==
        "QUARANTINED_PENDING_MATCHED_STATE_REVIEW"
    @test pair.blocker == "INPUT_RECEIPT_QUARANTINED"
    @test pair.joined_record === nothing
end

@testset "pair mismatches quarantine without a join" begin
    rate = receipt("rate")
    wrong_date = receipt("volume"; effective_date = "2026-08-05")
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        wrong_date,
        wrong_date["receipt_sha256"],
    )
    @test result.pair_status ==
        "QUARANTINED_PENDING_MATCHED_STATE_REVIEW"
    @test result.blocker == "PAIR_EFFECTIVE_DATE_MISMATCH"
    @test result.joined_record === nothing

    revised_volume = receipt(
        "volume",
        "SAME_DAY_1430_REVISION";
        predecessor = HEX_E,
    )
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        revised_volume,
        revised_volume["receipt_sha256"],
    )
    @test result.blocker == "PAIR_REVISION_TOKEN_MISMATCH"
    @test result.joined_record === nothing

    later_volume = receipt(
        "volume",
        "LATER_CORRECTION";
        predecessor = HEX_E,
    )
    revised_rate = receipt(
        "rate",
        "SAME_DAY_1430_REVISION";
        predecessor = HEX_E,
    )
    result = pair_receipts(
        revised_rate,
        revised_rate["receipt_sha256"],
        later_volume,
        later_volume["receipt_sha256"],
    )
    @test result.blocker == "PAIR_STATE_CLASS_MISMATCH"
end

@testset "pairing binds publication, OpenAPI, and governance context" begin
    rate = receipt("rate")

    later_publication = receipt(
        "volume";
        publication_date = "2026-08-10",
        request_started_at_utc = "2026-08-10T13:00:00.000Z",
        response_headers_at_utc = "2026-08-10T13:00:00.100Z",
        response_body_completed_at_utc = "2026-08-10T13:00:00.200Z",
    )
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        later_publication,
        later_publication["receipt_sha256"],
    )
    @test result.blocker == "PAIR_PUBLICATION_DATE_MISMATCH"
    @test result.joined_record === nothing

    other_openapi = receipt("volume"; openapi_sha256 = HEX_D)
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        other_openapi,
        other_openapi["receipt_sha256"],
    )
    @test result.blocker == "OPENAPI_PIN_MISMATCH"
    @test result.joined_record === nothing

    other_terms_hash =
        receipt("volume"; terms_snapshot_sha256 = HEX_D)
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        other_terms_hash,
        other_terms_hash["receipt_sha256"],
    )
    @test result.blocker == "GOVERNANCE_CONTEXT_MISMATCH"
    @test result.mismatch_fields == ("terms_snapshot_sha256",)
    @test result.joined_record === nothing

    other_terms_date =
        receipt("volume"; terms_snapshot_date = "2026-08-06")
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        other_terms_date,
        other_terms_date["receipt_sha256"],
    )
    @test result.blocker == "GOVERNANCE_CONTEXT_MISMATCH"
    @test result.mismatch_fields == ("terms_snapshot_date",)
    @test result.joined_record === nothing

    pending_volume = receipt(
        "volume";
        terms_decision = "PENDING_PROJECT_SPECIFIC_REVIEW",
    )
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        pending_volume,
        pending_volume["receipt_sha256"],
    )
    @test result.blocker == "GOVERNANCE_CONTEXT_MISMATCH"
    @test result.mismatch_fields == (
        "terms_review_decision",
        "attribution_requirement",
        "disclaimer_requirement",
        "redistribution_scope",
    )
    @test result.joined_record === nothing

    public_volume = receipt(
        "volume";
        redistribution_scope = "PUBLIC_DERIVED_ONLY",
    )
    result = pair_receipts(
        rate,
        rate["receipt_sha256"],
        public_volume,
        public_volume["receipt_sha256"],
    )
    @test result.blocker == "GOVERNANCE_CONTEXT_MISMATCH"
    @test result.mismatch_fields == (
        "attribution_requirement",
        "disclaimer_requirement",
        "redistribution_scope",
    )
    @test result.joined_record === nothing

    pending_rate = receipt(
        "rate";
        terms_decision = "PENDING_PROJECT_SPECIFIC_REVIEW",
    )
    result = pair_receipts(
        pending_rate,
        pending_rate["receipt_sha256"],
        pending_volume,
        pending_volume["receipt_sha256"],
    )
    @test result.blocker == "TERMS_REVIEW_NOT_APPROVED"
    @test result.joined_record === nothing

    rejected_rate = receipt("rate"; terms_decision = "REJECTED")
    rejected_volume = receipt("volume"; terms_decision = "REJECTED")
    result = pair_receipts(
        rejected_rate,
        rejected_rate["receipt_sha256"],
        rejected_volume,
        rejected_volume["receipt_sha256"],
    )
    @test result.blocker == "TERMS_REVIEW_NOT_APPROVED"
    @test result.joined_record === nothing
end

@testset "terms freshness and decision context are fail closed" begin
    stale = receipt("rate"; terms_snapshot_date = "1990-01-01")
    @test occursin(
        "no more than $MAX_TERMS_SNAPSHOT_AGE_DAYS days old",
        validation_error(stale),
    )

    future = receipt("rate"; terms_snapshot_date = "2026-08-08")
    @test occursin(
        "no more than $MAX_TERMS_SNAPSHOT_AGE_DAYS days old",
        validation_error(future),
    )

    none_required = receipt(
        "rate";
        attribution_requirement = "NONE_REQUIRED",
    )
    @test occursin(
        "ATTRIBUTION_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK",
        validation_error(none_required),
    )

    wrong_disclaimer = receipt(
        "rate";
        disclaimer_requirement = "NONE_REQUIRED",
    )
    @test occursin(
        "REFERENCE_RATE_DISCLAIMER_REQUIRED_FOR_DERIVED_USE",
        validation_error(wrong_disclaimer),
    )

    inconsistent_public = receipt(
        "rate";
        redistribution_scope = "PUBLIC_DERIVED_ONLY",
        attribution_requirement =
            "ATTRIBUTION_REQUIRED_FEDERAL_RESERVE_BANK_OF_NEW_YORK",
    )
    @test occursin(
        "ATTRIBUTION_AND_DERIVATIVE_LABEL_REQUIRED",
        validation_error(inconsistent_public),
    )

    public_redistribution = receipt(
        "rate";
        redistribution_scope = "PUBLIC_DERIVED_ONLY",
    )
    @test validate_receipt(
        public_redistribution,
        public_redistribution["receipt_sha256"],
    ).governance.redistribution_scope == "PUBLIC_DERIVED_ONLY"

    approved_with_rejected_profile = receipt(
        "rate";
        redistribution_scope = "PROHIBITED",
        attribution_requirement =
            "USE_REJECTED_ATTRIBUTION_NOT_APPLICABLE",
        disclaimer_requirement =
            "USE_REJECTED_DISCLAIMER_NOT_APPLICABLE",
    )
    @test occursin(
        "not a registered closed profile",
        validation_error(approved_with_rejected_profile),
    )
    valid_volume = receipt("volume")
    @test_throws EFFRCaptureContractError pair_receipts(
        approved_with_rejected_profile,
        approved_with_rejected_profile["receipt_sha256"],
        valid_volume,
        valid_volume["receipt_sha256"],
    )

    pending = receipt(
        "rate";
        terms_decision = "PENDING_PROJECT_SPECIFIC_REVIEW",
    )
    validated_pending =
        validate_receipt(pending, pending["receipt_sha256"])
    @test "TERMS_REVIEW_PENDING" in
        validated_pending.classification.blockers
    @test !validated_pending.gates.origin_admissible

    rejected = receipt("rate"; terms_decision = "REJECTED")
    validated_rejected =
        validate_receipt(rejected, rejected["receipt_sha256"])
    @test "TERMS_REVIEW_REJECTED" in
        validated_rejected.classification.blockers
    @test !validated_rejected.gates.empirical_forecast_allowed
end

@testset "rate structure is semantically ordered" begin
    invalid_cases = (
        ("percentPercentile1", 4.33, "percentPercentile1 must not exceed"),
        ("percentPercentile25", 4.34, "percentPercentile25 must not exceed"),
        ("percentRate", 4.35, "percentRate must not exceed"),
        ("percentPercentile75", 4.39, "percentPercentile75 must not exceed"),
        ("targetRateFrom", 4.51, "targetRateFrom must not exceed"),
    )
    for (field, value, message) in invalid_cases
        document = receipt("rate")
        document["raw_fields"][field] = value
        restamp!(document)
        @test occursin(message, validation_error(document))
        volume = receipt("volume")
        @test_throws EFFRCaptureContractError pair_receipts(
            document,
            document["receipt_sha256"],
            volume,
            volume["receipt_sha256"],
        )
    end
end

@testset "schema mismatch is explicit and quarantined" begin
    document = receipt("rate"; schema_mismatch = true)
    validated = validate_receipt(document, document["receipt_sha256"])
    @test validated.classification.schema_class ==
        "SCHEMA_MISMATCH_QUARANTINED"
    @test validated.classification.schema_mismatch_detail != "NONE"
    @test validated.classification.quarantine_class ==
        "QUARANTINED_PENDING_MATCHED_STATE_REVIEW"
    @test "SCHEMA_MISMATCH" in validated.classification.blockers

    aliased = receipt("rate")
    aliased["raw_fields"]["rate"] =
        pop!(aliased["raw_fields"], "percentRate")
    restamp!(aliased)
    @test occursin(
        "missing keys: percentRate",
        validation_error(aliased),
    )
    extra_alias = receipt("rate")
    extra_alias["raw_fields"]["rate"] = 4.33
    restamp!(extra_alias)
    @test occursin("unknown keys: rate", validation_error(extra_alias))
end

@testset "closed vocabularies reject Used, Other, and unknown" begin
    mutations = (
        ("source", "evidence_track", "Used"),
        ("source", "route_class", "Other"),
        ("observation", "state_class", "UNKNOWN"),
        ("observation", "report_type", "Other"),
        ("raw_fields", "revisionIndicator", "Used"),
        ("raw_fields", "footnote", "Other"),
        ("classification", "schema_class", "Other"),
        ("classification", "quarantine_class", "Used"),
        ("governance", "terms_review_decision", "Other"),
        ("governance", "redistribution_scope", "Used"),
    )
    for (table, key, value) in mutations
        document = receipt("rate")
        document[table][key] = value
        restamp!(document)
        @test validation_error(document) != "NO_ERROR"
    end

    alfred = receipt("rate")
    alfred["observation"]["state_class"] = "ALFRED_DATE_STATE"
    alfred["observation"]["scheduled_publication_window"] =
        "ALFRED_DATE_LEVEL_LOAD_DATE"
    restamp!(alfred)
    @test occursin(
        "not a New York Fed capture receipt",
        validation_error(alfred),
    )
end

@testset "numeric and Boolean types are not coercive" begin
    cases = (
        ("response", "http_status", true),
        ("response", "content_length", false),
        ("raw_fields", "percentRate", true),
        ("raw_fields", "percentPercentile1", false),
        ("raw_fields", "volumeInBillions", true),
    )
    for (table, key, value) in cases
        report_type = key == "volumeInBillions" ? "volume" : "rate"
        document = receipt(report_type)
        document[table][key] = value
        restamp!(document)
        @test occursin("Boolean", validation_error(document))
    end
    for value in (NaN, Inf, -Inf)
        document = receipt("rate")
        document["raw_fields"]["percentRate"] = value
        restamp!(document)
        @test occursin("finite", validation_error(document))
    end
end

@testset "request, response, governance, lineage, and gates are exact" begin
    mutations = (
        ("request", "canonical_query", "startDate=2026-08-06&endDate=2026-08-06&type=rate"),
        ("request", "requested_url", "https://markets.newyorkfed.org/api/rates/all/latest.json"),
        ("response", "final_host", "example.com"),
        ("response", "final_url", "https://example.com/data"),
        ("response", "availability_upper_bound_utc", "2026-08-07T13:00:00.300Z"),
        ("response", "content_type", "text/html"),
        ("response", "headers_complete", false),
        ("governance", "terms_url", "https://example.com/terms"),
        ("source", "historical_vintage_claim", "CURRENT_API_PROVES_HISTORICAL_VINTAGE"),
    )
    for (table, key, value) in mutations
        document = receipt("rate")
        document[table][key] = value
        restamp!(document)
        @test validation_error(document) != "NO_ERROR"
    end

    redirected = receipt("rate")
    redirected["response"]["redirect_count"] = 1
    redirected["response"]["redirect_chain"] =
        ["301|official|other"]
    restamp!(redirected)
    @test occursin("between 0 and 0", validation_error(redirected))

    revision_without_predecessor =
        receipt("rate", "SAME_DAY_1430_REVISION")
    @test occursin(
        "requires a predecessor",
        validation_error(revision_without_predecessor),
    )

    for key in keys(receipt("rate")["gates"])
        document = receipt("rate")
        document["gates"][key] = true
        restamp!(document)
        @test occursin(
            "permanently false",
            validation_error(document),
        )
    end
end

@testset "external pin defeats forged self-rehash" begin
    document = receipt("rate")
    original_pin = document["receipt_sha256"]
    forged = deepcopy(document)
    forged["raw_fields"]["percentRate"] = 4.335
    restamp!(forged)
    @test forged["receipt_sha256"] != original_pin
    @test occursin(
        "out-of-band pin does not match",
        validation_error(forged; pin = original_pin),
    )
    @test validate_receipt(forged, forged["receipt_sha256"]).
    raw_fields.percentRate == 4.335

    embedded_only = deepcopy(document)
    embedded_only["receipt_sha256"] = HEX_B
    @test occursin(
        "does not match canonical receipt bytes",
        validation_error(embedded_only; pin = original_pin),
    )
    @test occursin(
        "64 lowercase hexadecimal",
        validation_error(document; pin = "NOT_A_HASH"),
    )
end

@testset "no filesystem or raw-byte ingestion surface" begin
    document = receipt("rate")
    @test_throws EFFRCaptureContractError validate_receipt(
        "/tmp/untrusted-receipt.toml",
        document["receipt_sha256"],
    )
    @test_throws EFFRCaptureContractError validate_receipt(
        UInt8[0x7b, 0x7d],
        document["receipt_sha256"],
    )
end
