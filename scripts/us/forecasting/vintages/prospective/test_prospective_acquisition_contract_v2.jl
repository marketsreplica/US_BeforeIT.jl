#!/usr/bin/env julia

using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USProspectiveAcquisitionContractV2.jl"))
using .USProspectiveAcquisitionContractV2

const CONTRACT_PATH =
    joinpath(@__DIR__, "prospective_2026q3_contract_v2.toml")
const EXPECTED_CONTENT_SHA256 =
    "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
const EXPECTED_REQUIREMENT_IDS = [
    "bea_fixed_assets_structural",
    "bea_gdpbyindustry_sector_accounts",
    "bea_industry_io_structural",
    "bea_industry_valuation_structural",
    "bea_inventory_stock_control",
    "bea_nipa_expenditure_history",
    "bea_nipa_income_fiscal_structural",
    "bea_nipa_tier1",
    "bls_cps_structural",
    "bls_employment_tier1",
    "bls_qcew_structural",
    "census_aies_inventory_allocation",
    "census_m3_inventory_stages",
    "census_mrts_inventory_stock",
    "census_mwts_inventory_stock",
    "census_susb_structural",
    "classification_maps",
    "frb_z1_structural",
    "frbny_effr_tier1",
    "fred_policy_rate_history",
    "usda_counts_structural",
]
const EXPECTED_TIER1_TARGETS = Set(
    [
        "core_pce_price_index",
        "effective_federal_funds_rate",
        "gdp_deflator",
        "nominal_gdp",
        "payroll_employment",
        "pce_price_index",
        "real_gdp",
        "unemployment_rate",
    ],
)
const CAPTURE_COMPLETION_TIME = Dict(
    "slow_structural_pre_origin" => "2026-08-06T12:00:00Z",
    "final_structural_pre_origin" => "2026-10-30T12:00:00Z",
    "bea_gdp_2026q3_advance" => "2026-10-29T12:30:05Z",
    "bls_employment_situation_2026_09" => "2026-10-02T12:30:05Z",
    "bls_qcew_2026q1" => "2026-08-28T14:00:05Z",
    "census_m3_2026_08_full" => "2026-10-02T14:00:05Z",
    "census_m3_2026_09_advance" => "2026-10-27T12:30:05Z",
    "census_mrts_inventory_2026_08" => "2026-10-15T14:00:05Z",
    "census_mwts_2026_08" => "2026-10-08T14:00:05Z",
    "frb_z1_2026q2" => "2026-09-11T16:00:05Z",
    "frbny_effr_2026_10_29_first_state" => "2026-10-30T13:00:05Z",
    "frbny_effr_daily_first_state" => "2026-10-30T13:00:05Z",
    "frbny_effr_daily_revision_check" => "2026-10-29T18:30:05Z",
)

checked_contract() = load_contract(CONTRACT_PATH)

function restamp!(contract)
    stamp_contract_sha256!(contract)
    return contract
end

function requirement(contract, requirement_id)
    return only(
        row for row in contract["requirements"] if
            row["requirement_id"] == requirement_id
    )
end

function digest(label)
    return bytes2hex(sha256(Vector{UInt8}(codeunits(label))))
end

function required_capture_id(contract, requirement_id, profile_id)
    row = requirement(contract, requirement_id)
    return get(
        row["profile_capture_overrides"],
        profile_id,
        row["default_capture_id"],
    )
end

function selector_dimension(selector, keys)
    for segment in split(selector, ":")
        for key in keys
            prefix = "$key="
            startswith(segment, prefix) &&
                return segment[(ncodeunits(prefix) + 1):end]
        end
    end
    return nothing
end

function selector_dimensions(selector)
    dimensions = Dict{String, String}()
    for segment in split(selector, ":")
        occursin("=", segment) || continue
        key, value = split(segment, "="; limit = 2)
        dimensions[String(key)] = String(value)
    end
    return dimensions
end

function dynamic_test_resolution_mode(value)
    value == "X" && return "FULL_REQUESTED_HISTORY"
    occursin(r"(?i)(^|[^A-Z0-9])ALL([^A-Z0-9]|$)", value) &&
        return "FULL_PUBLISHED_UNIVERSE"
    occursin(r"(?i)(^|[^A-Z0-9])LATEST([^A-Z0-9]|$)", value) &&
        return "LATEST_ELIGIBLE_SELECTION"
    return "POLICY_RESOLUTION"
end

function resolved_selector_state(selector, profile_id, catalog_sha256)
    unresolved =
        r"(?i)(^|[^A-Z0-9])(ALL|LATEST|PINNED|SAME|THROUGH)([^A-Z0-9]|$)"
    dimensions = Dict{String, String}()
    set_resolutions = Dict{String, Any}()
    for (key, value) in selector_dimensions(selector)
        if value == "X" || occursin(unresolved, value)
            coverage_mode = dynamic_test_resolution_mode(value)
            members_sha256 =
                digest("members:$profile_id:$key:$value:$catalog_sha256")
            resolved_value = "sha256:$members_sha256"
            dimensions[key] = resolved_value
            set_resolutions[key] = Dict{String, Any}(
                "policy_value" => value,
                "coverage_mode" => coverage_mode,
                "resolved_value" => resolved_value,
                "member_count" =>
                    coverage_mode == "LATEST_ELIGIBLE_SELECTION" ? 1 : 2,
                "members_sha256" => members_sha256,
                "candidate_catalog_sha256" => catalog_sha256,
            )
        else
            dimensions[key] = value
        end
    end
    return dimensions, set_resolutions
end

function official_artifact_locator(selector, requirement_id, profile_id)
    source = first(split(selector, ":"))
    locator_sha256 = digest("locator:$requirement_id:$profile_id")
    if source == "BEFOREIT"
        return "https://github.com/marketsreplica/US_BeforeIT.jl/blob/" *
            locator_sha256 *
            "/scripts/us/bea71.toml"
    end
    host = get(
        Dict(
            "BEA" => "apps.bea.gov",
            "BLS" => "www.bls.gov",
            "CENSUS" => "www2.census.gov",
            "FRB" => "www.federalreserve.gov",
            "FRED" => "fred.stlouisfed.org",
            "FRBNY" => "www.newyorkfed.org",
            "USDA" => "www.nass.usda.gov",
        ),
        source,
        "example.invalid",
    )
    return "https://$host/exact-artifacts/$locator_sha256"
end

function evidence_row(
        contract,
        requirement_id,
        profile_id;
        selector = get(
            requirement(contract, requirement_id)["artifact_profiles"],
            profile_id,
            "UNDECLARED_SELECTOR",
        ),
        capture_id = nothing,
        completed_at_utc = nothing,
        availability_upper_bound_utc = nothing,
        receipt_artifact_status = "VERIFIED",
        durable_storage_status = "VERIFIED",
        retain_until_utc = "2032-10-30T14:00:00Z",
        evidence_id = "evidence.$profile_id",
    )
    resolved_capture_id =
        capture_id === nothing ?
        required_capture_id(contract, requirement_id, profile_id) :
        capture_id
    resolved_completed_at =
        completed_at_utc === nothing ?
        CAPTURE_COMPLETION_TIME[resolved_capture_id] :
        completed_at_utc
    resolved_upper_bound =
        availability_upper_bound_utc === nothing ?
        resolved_completed_at : availability_upper_bound_utc
    raw_sha256 = digest("raw:$requirement_id:$profile_id")
    receipt_sha256 = digest("receipt:$requirement_id:$profile_id")
    requirement_row = requirement(contract, requirement_id)
    reference_period = something(
        selector_dimension(selector, ("ReferencePeriod",)),
        selector_dimension(selector, ("Year",)),
        "2026Q3",
    )
    reference_period in ("X", "LATEST_ELIGIBLE") &&
        (reference_period = "2026Q3")
    candidate_catalog_sha256 =
        digest("catalog:$requirement_id:$profile_id")
    dimensions, set_resolutions = resolved_selector_state(
        selector,
        profile_id,
        candidate_catalog_sha256,
    )
    member = if haskey(dimensions, "member")
        dimensions["member"]
    elseif haskey(dimensions, "archive")
        dimensions["archive"]
    elseif get(dimensions, "resolved_workbook_member_required", "false") ==
            "true"
        "resolved.$profile_id.xlsx"
    else
        "NOT_APPLICABLE"
    end
    fixed_event = findfirst(
        event -> event["event_id"] == resolved_capture_id,
        contract["fixed_events"],
    )
    release_timestamp =
        fixed_event !== nothing &&
        contract["fixed_events"][fixed_event]["timestamp_basis"] ==
        "official_exact" ?
        contract["fixed_events"][fixed_event]["scheduled_timestamp_utc"] :
        "UNKNOWN_NOT_ASSERTED"
    resolution = Dict{String, Any}(
        "resolution_schema" =>
            "beforeit-us-resolved-selector-evidence.v3-draft",
        "requirement_id" => requirement_id,
        "profile_id" => profile_id,
        "policy_selector" => selector,
        "resolution_mode" =>
            occursin("LATEST_ELIGIBLE", uppercase(selector)) ?
            "LATEST_ELIGIBLE" : "FIXED",
        "source_id" => requirement_row["source_id"],
        "release_id" => get(
            dimensions,
            "Release",
            get(dimensions, "release", "release.$resolved_capture_id"),
        ),
        "release_timestamp_utc" => release_timestamp,
        "reference_period" => reference_period,
        "dataset_id" => join(split(selector, ":")[1:2], ":"),
        "frequency" => something(
            get(dimensions, "Frequency", nothing),
            "NOT_APPLICABLE",
        ),
        "table_id" => something(
            get(
                dimensions,
                "TableName",
                get(
                    dimensions,
                    "TableID",
                    get(dimensions, "Table", nothing),
                ),
            ),
            "NOT_APPLICABLE",
        ),
        "line_id" => something(
            get(dimensions, "LineNumber", nothing),
            "NOT_APPLICABLE",
        ),
        "series_id" => something(
            get(
                dimensions,
                "Series",
                get(
                    dimensions,
                    "SeriesID",
                    get(dimensions, "SeriesCode", nothing),
                ),
            ),
            "NOT_APPLICABLE",
        ),
        "official_artifact_locator" => official_artifact_locator(
            selector,
            requirement_id,
            profile_id,
        ),
        "artifact_member_locator" => member,
        "candidate_catalog_sha256" => candidate_catalog_sha256,
        "candidate_rank" => 1,
        "eligible_candidate_count" => 1,
        "raw_sha256" => raw_sha256,
        "receipt_sha256" => receipt_sha256,
        "receipt_completed_at_utc" => resolved_completed_at,
        "resolved_dimensions" => dimensions,
        "set_resolutions" => set_resolutions,
    )
    return Dict{String, Any}(
        "evidence_id" => evidence_id,
        "requirement_id" => requirement_id,
        "profile_id" => profile_id,
        "selector" => selector,
        "capture_id" => resolved_capture_id,
        "raw_sha256" => raw_sha256,
        "receipt_sha256" => receipt_sha256,
        "selector_evidence_sha256" =>
            USProspectiveAcquisitionContractV2.canonical_sha256(resolution),
        "receipt_completed_at_utc" => resolved_completed_at,
        "availability_upper_bound_utc" => resolved_upper_bound,
        "receipt_artifact_status" => receipt_artifact_status,
        "durable_storage_status" => durable_storage_status,
        "retain_until_utc" => retain_until_utc,
        "resolution" => resolution,
    )
end

function complete_evidence(contract, requirement_id)
    profiles = requirement(contract, requirement_id)["artifact_profiles"]
    rows = [
        evidence_row(contract, requirement_id, profile_id)
            for profile_id in sort!(collect(keys(profiles)))
    ]
    return rows
end

function restamp_resolution!(row)
    row["selector_evidence_sha256"] =
        USProspectiveAcquisitionContractV2.canonical_sha256(row["resolution"])
    return row
end

@testset "v2 selector contract is pinned and fail closed" begin
    contract = checked_contract()
    requirements = contract["requirements"]

    @test validate_contract(contract) === contract
    @test contract_sha256(contract) == EXPECTED_CONTENT_SHA256
    @test contract["artifact"]["content_sha256"] ==
        EXPECTED_CONTENT_SHA256
    @test contract["artifact"]["schema_version"] ==
        "beforeit-us-prospective-acquisition-requirements.v6-draft"
    @test contract["artifact"]["contract_id"] ==
        "beforeit-us-prospective-2026q3-acquisition.v2"
    @test [row["requirement_id"] for row in requirements] ==
        EXPECTED_REQUIREMENT_IDS
    @test length(requirements) == 21
    @test sum(row["required_profile_count"] for row in requirements) ==
        107
    @test all(
        row["completion_rule"] == "ALL_PROFILES_VERIFIED"
            for row in requirements
    )
    @test all(
        !isempty(row["default_capture_id"]) for row in requirements
    )
    @test requirement(contract, "census_m3_inventory_stages")[
        "profile_capture_overrides",
    ] == Dict(
        "m3_2026_09_advance_total" =>
            "census_m3_2026_09_advance",
    )
    @test requirement(contract, "bls_qcew_structural")[
        "profile_capture_overrides",
    ] == Dict(
        "qcew_2026q1_quarterly" => "bls_qcew_2026q1",
    )
    @test requirement(contract, "frbny_effr_tier1")[
        "profile_completion_dates",
    ] == Dict(
        "effr_first_state_manifest" => "2026-10-30",
        "effr_revision_manifest" => "2026-10-29",
    )
    @test all(
        row["required_profile_count"] ==
            length(row["artifact_profiles"]) for row in requirements
    )
    @test all(
        row["evidence_status"] == "MISSING_NOT_CAPTURED"
            for row in requirements
    )
    @test all(
        row["registered_raw_artifact_count"] == 0
            for row in requirements
    )
    @test Set(
        target for row in requirements for target in row["target_ids"]
    ) == EXPECTED_TIER1_TARGETS
    @test contract["origin"]["admission_status"] ==
        "PLANNED_NOT_CAPTURED_NOT_ADMITTED"
    @test !contract["origin"]["inventory_mutation_authorized"]
    @test !contract["origin"]["origin_admissible"]
    @test !contract["origin"]["ready"]
    @test !contract["origin"]["accuracy_evaluation_allowed"]
    @test contract["verifier"]["implementation_status"] ==
        "NOT_IMPLEMENTED_FAIL_CLOSED"
    @test contract["selector_resolution_policy"][
        "verifier_attestation_required_for_completion",
    ]
    @test contract["selector_resolution_policy"][
        "shape_complete_is_not_requirement_complete",
    ]
    @test contract["selector_resolution_policy"][
        "resolved_dimensions_bind_every_selector_key",
    ]
    @test contract["selector_resolution_policy"][
        "dynamic_set_resolutions_required",
    ]
    @test contract["selector_resolution_policy"][
        "official_artifact_host_allowlist_enforced",
    ]
    @test contract["selector_resolution_policy"][
        "official_artifact_source_affinity_enforced",
    ]
    @test contract["approval"]["artifact_approval_status"] ==
        "DRAFT_UNAPPROVED"
end

@testset "all 21 atomic requirement families require every selector" begin
    contract = checked_contract()
    for requirement_id in EXPECTED_REQUIREMENT_IDS
        rows = complete_evidence(contract, requirement_id)
        result =
            evaluate_requirement_completion(contract, requirement_id, rows)
        @test result.completion_rule == "ALL_PROFILES_VERIFIED"
        @test result.expected_profile_count ==
            requirement(contract, requirement_id)["required_profile_count"]
        @test result.accepted_profile_count == length(rows)
        @test isempty(result.missing_profile_ids)
        @test isempty(result.rejected_evidence)
        @test result.shape_complete
        @test !result.verifier_attested
        @test !result.complete
        @test !result.origin_admissible
        @test !result.ready
        @test !result.inventory_mutation_authorized
    end
end

@testset "arbitrary bytes and partial selector families cannot satisfy" begin
    contract = checked_contract()
    requirement_id = "bea_fixed_assets_structural"
    complete_rows = complete_evidence(contract, requirement_id)

    arbitrary = evidence_row(
        contract,
        requirement_id,
        "arbitrary_file";
        selector = "file:///tmp/unrelated.csv",
    )
    arbitrary_result = evaluate_requirement_completion(
        contract,
        requirement_id,
        [arbitrary],
    )
    @test !arbitrary_result.complete
    @test arbitrary_result.accepted_profile_count == 0
    @test length(arbitrary_result.missing_profile_ids) == 8
    @test arbitrary_result.rejected_evidence ==
        ["evidence.arbitrary_file:UNKNOWN_PROFILE"]

    missing_profile = pop!(complete_rows)
    missing_result = evaluate_requirement_completion(
        contract,
        requirement_id,
        complete_rows,
    )
    @test !missing_result.complete
    @test missing_result.accepted_profile_count == 7
    @test missing_result.missing_profile_ids ==
        [missing_profile["profile_id"]]
    @test isempty(missing_result.rejected_evidence)

    wrong_selector_rows = complete_evidence(contract, requirement_id)
    wrong_selector_profile = wrong_selector_rows[1]["profile_id"]
    wrong_selector_rows[1]["selector"] = "ARBITRARY_FILE_SELECTOR"
    wrong_selector_result = evaluate_requirement_completion(
        contract,
        requirement_id,
        wrong_selector_rows,
    )
    @test !wrong_selector_result.complete
    @test wrong_selector_result.missing_profile_ids ==
        [wrong_selector_profile]
    @test wrong_selector_result.rejected_evidence ==
        ["evidence.$wrong_selector_profile:SELECTOR_MISMATCH"]

    duplicate_rows = complete_evidence(contract, requirement_id)
    duplicate = deepcopy(first(duplicate_rows))
    duplicate["evidence_id"] = "evidence.duplicate"
    push!(duplicate_rows, duplicate)
    duplicate_result = evaluate_requirement_completion(
        contract,
        requirement_id,
        duplicate_rows,
    )
    @test !duplicate_result.complete
    @test first(duplicate_rows)["profile_id"] in
        duplicate_result.missing_profile_ids
    @test duplicate_result.rejected_evidence ==
        ["evidence.duplicate:DUPLICATE_PROFILE"]

    extra_rows = complete_evidence(contract, requirement_id)
    push!(extra_rows, arbitrary)
    extra_result = evaluate_requirement_completion(
        contract,
        requirement_id,
        extra_rows,
    )
    @test !extra_result.complete
    @test extra_result.accepted_profile_count == 8
    @test extra_result.rejected_evidence ==
        ["evidence.arbitrary_file:UNKNOWN_PROFILE"]
    @test !extra_result.origin_admissible
    @test !extra_result.ready
    @test !extra_result.inventory_mutation_authorized
end

@testset "receipt and capture evidence fail closed" begin
    contract = checked_contract()
    requirement_id = "bea_fixed_assets_structural"
    profile_id = "faat301esi_net_stock"

    mismatched_bound = evidence_row(
        contract,
        requirement_id,
        profile_id;
        availability_upper_bound_utc = "2026-10-30T11:59:59Z",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [mismatched_bound],
    ).rejected_evidence == [
        "evidence.$profile_id:UPPER_BOUND_MISMATCH",
    ]

    outside_window = evidence_row(
        contract,
        requirement_id,
        profile_id;
        completed_at_utc = "2026-10-30T14:00:01Z",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [outside_window],
    ).rejected_evidence == [
        "evidence.$profile_id:OUTSIDE_CAPTURE_WINDOW",
    ]

    unverified = evidence_row(
        contract,
        requirement_id,
        profile_id;
        receipt_artifact_status = "NOT_VERIFIED",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [unverified],
    ).rejected_evidence == [
        "evidence.$profile_id:RECEIPT_NOT_VERIFIED",
    ]

    ephemeral = evidence_row(
        contract,
        requirement_id,
        profile_id;
        durable_storage_status = "NOT_VERIFIED",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [ephemeral],
    ).rejected_evidence == [
        "evidence.$profile_id:STORAGE_NOT_VERIFIED",
    ]

    short_retention = evidence_row(
        contract,
        requirement_id,
        profile_id;
        retain_until_utc = "2031-10-30T13:59:59Z",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [short_retention],
    ).rejected_evidence == [
        "evidence.$profile_id:RETENTION_TOO_SHORT",
    ]

    unauthorized = evidence_row(
        contract,
        requirement_id,
        profile_id;
        capture_id = "census_mwts_2026_08",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [unauthorized],
    ).rejected_evidence == [
        "evidence.$profile_id:WRONG_PROFILE_CAPTURE",
    ]

    recurring = evidence_row(
        contract,
        "frbny_effr_tier1",
        "effr_first_state_manifest";
        capture_id = "frbny_effr_daily_first_state",
        completed_at_utc = "2026-10-30T13:00:05Z",
    )
    recurring_result = evaluate_requirement_completion(
        contract,
        "frbny_effr_tier1",
        [recurring],
    )
    @test recurring_result.accepted_profile_ids ==
        ["effr_first_state_manifest"]
    @test !recurring_result.complete

    premature_manifest = evidence_row(
        contract,
        "frbny_effr_tier1",
        "effr_first_state_manifest";
        capture_id = "frbny_effr_daily_first_state",
        completed_at_utc = "2026-08-07T13:00:05Z",
    )
    @test evaluate_requirement_completion(
        contract,
        "frbny_effr_tier1",
        [premature_manifest],
    ).rejected_evidence == [
        "evidence.effr_first_state_manifest:PROFILE_COVERAGE_DATE_MISMATCH",
    ]

    holiday_manifest = evidence_row(
        contract,
        "frbny_effr_tier1",
        "effr_first_state_manifest";
        capture_id = "frbny_effr_daily_first_state",
        completed_at_utc = "2026-09-07T13:00:05Z",
    )
    @test evaluate_requirement_completion(
        contract,
        "frbny_effr_tier1",
        [holiday_manifest],
    ).rejected_evidence == [
        "evidence.effr_first_state_manifest:OUTSIDE_CAPTURE_WINDOW",
    ]

    rehearsal = evidence_row(
        contract,
        "bls_employment_tier1",
        "ces_total_nonfarm_payroll";
        capture_id = "bls_employment_situation_2026_07",
        completed_at_utc = "2026-08-07T12:30:05Z",
    )
    @test evaluate_requirement_completion(
        contract,
        "bls_employment_tier1",
        [rehearsal],
    ).rejected_evidence == [
        "evidence.ces_total_nonfarm_payroll:WRONG_PROFILE_CAPTURE",
    ]

    stale_snapshot = evidence_row(
        contract,
        requirement_id,
        profile_id;
        capture_id = "slow_structural_pre_origin",
        completed_at_utc = "2026-08-06T12:00:00Z",
    )
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [stale_snapshot],
    ).rejected_evidence == [
        "evidence.$profile_id:WRONG_PROFILE_CAPTURE",
    ]

    wrong_m3_event = evidence_row(
        contract,
        "census_m3_inventory_stages",
        "m3_2026_09_advance_total";
        capture_id = "census_m3_2026_08_full",
        completed_at_utc = "2026-10-02T14:00:05Z",
    )
    @test evaluate_requirement_completion(
        contract,
        "census_m3_inventory_stages",
        [wrong_m3_event],
    ).rejected_evidence == [
        "evidence.m3_2026_09_advance_total:WRONG_PROFILE_CAPTURE",
    ]

    bad_hash = evidence_row(contract, requirement_id, profile_id)
    bad_hash["raw_sha256"] = "not-a-hash"
    @test_throws ProspectiveContractV2ValidationError evaluate_requirement_completion(
        contract,
        requirement_id,
        [bad_hash],
    )
end

@testset "resolved selector evidence is canonical and byte-bound" begin
    contract = checked_contract()
    requirement_id = "bea_fixed_assets_structural"
    profile_id = "faat301esi_net_stock"

    valid = evidence_row(contract, requirement_id, profile_id)
    valid_result = evaluate_requirement_completion(
        contract,
        requirement_id,
        [valid],
    )
    @test valid_result.accepted_profile_ids == [profile_id]
    @test isempty(valid_result.rejected_evidence)
    @test !valid_result.shape_complete
    @test !valid_result.complete

    hash_mismatch = deepcopy(valid)
    hash_mismatch["resolution"]["release_id"] = "release.changed"
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [hash_mismatch],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_HASH_MISMATCH",
    ]

    unresolved = deepcopy(valid)
    unresolved["resolution"]["release_id"] = "LATEST"
    restamp_resolution!(unresolved)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [unresolved],
    ).rejected_evidence == [
        "evidence.$profile_id:UNRESOLVED_SELECTOR_IDENTITY",
    ]

    unbound_raw = deepcopy(valid)
    unbound_raw["resolution"]["raw_sha256"] = digest("different raw")
    restamp_resolution!(unbound_raw)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [unbound_raw],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_HASH_BINDING_MISMATCH",
    ]

    wrong_rank = deepcopy(valid)
    wrong_rank["resolution"]["candidate_rank"] = 2
    wrong_rank["resolution"]["eligible_candidate_count"] = 2
    restamp_resolution!(wrong_rank)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [wrong_rank],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_CANDIDATE_RANK_INVALID",
    ]

    wrong_dimension = deepcopy(valid)
    wrong_dimension["resolution"]["frequency"] = "Q"
    restamp_resolution!(wrong_dimension)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [wrong_dimension],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_DIMENSION_MISMATCH",
    ]

    wrong_year = deepcopy(valid)
    wrong_year["resolution"]["resolved_dimensions"]["Year"] = "1999"
    restamp_resolution!(wrong_year)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [wrong_year],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_DIMENSION_MISMATCH",
    ]

    valuation = evidence_row(
        contract,
        "bea_industry_valuation_structural",
        "producer_use_2024",
    )
    valuation["resolution"]["artifact_member_locator"] = "NOT_APPLICABLE"
    restamp_resolution!(valuation)
    @test evaluate_requirement_completion(
        contract,
        "bea_industry_valuation_structural",
        [valuation],
    ).rejected_evidence == [
        "evidence.producer_use_2024:RESOLUTION_MEMBER_MISMATCH",
    ]

    wrong_host = deepcopy(valid)
    wrong_host["resolution"]["official_artifact_locator"] =
        "https://example.invalid/exact-artifact"
    restamp_resolution!(wrong_host)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [wrong_host],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_LOCATOR_HOST_INVALID",
    ]

    cross_source_host = deepcopy(valid)
    cross_source_host["resolution"]["official_artifact_locator"] =
        "https://www2.census.gov/econ/exact-artifact.xlsx"
    restamp_resolution!(cross_source_host)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [cross_source_host],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_LOCATOR_HOST_INVALID",
    ]

    beforeit_bridge = evidence_row(
        contract,
        "classification_maps",
        "beforeit_bea71_model_bridge",
    )
    beforeit_bridge["resolution"]["official_artifact_locator"] =
        "https://github.com/other-owner/other-repository/blob/" *
        digest("wrong repository revision") *
        "/scripts/us/bea71.toml"
    restamp_resolution!(beforeit_bridge)
    @test evaluate_requirement_completion(
        contract,
        "classification_maps",
        [beforeit_bridge],
    ).rejected_evidence == [
        "evidence.beforeit_bea71_model_bridge:RESOLUTION_LOCATOR_REPOSITORY_INVALID",
    ]

    route_only = deepcopy(valid)
    route_only["resolution"]["official_artifact_locator"] =
        requirement(contract, requirement_id)["source_locator"]
    restamp_resolution!(route_only)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [route_only],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_LOCATOR_INVALID",
    ]

    future_release = deepcopy(valid)
    future_release["resolution"]["release_timestamp_utc"] =
        "2026-10-30T14:00:01Z"
    restamp_resolution!(future_release)
    @test evaluate_requirement_completion(
        contract,
        requirement_id,
        [future_release],
    ).rejected_evidence == [
        "evidence.$profile_id:RESOLUTION_RELEASE_TIME_INVALID",
    ]

    z1 = evidence_row(
        contract,
        "frb_z1_structural",
        "z1_2026q2_data_bundle",
    )
    z1["resolution"]["release_timestamp_utc"] = "UNKNOWN_NOT_ASSERTED"
    restamp_resolution!(z1)
    @test evaluate_requirement_completion(
        contract,
        "frb_z1_structural",
        [z1],
    ).rejected_evidence == [
        "evidence.z1_2026q2_data_bundle:RESOLUTION_RELEASE_TIME_MISMATCH",
    ]

    singleton_cases = (
        (
            "bea_gdpbyindustry_sector_accounts",
            "gdpbyindustry_t1_value_added_annual_2024",
            "Industry",
            "11",
        ),
        (
            "bea_nipa_income_fiscal_structural",
            "nipa_t11000_income_full",
            "LineNumber",
            "1",
        ),
        (
            "bea_nipa_expenditure_history",
            "nipa_t10105_l1_nominal_gdp",
            "Year",
            "2026",
        ),
        (
            "census_susb_structural",
            "susb_employer_enterprises",
            "ENTRSIZE",
            "01",
        ),
    )
    for (
            singleton_requirement,
            singleton_profile,
            dimension,
            singleton,
        ) in singleton_cases
        narrowed = evidence_row(
            contract,
            singleton_requirement,
            singleton_profile,
        )
        narrowed["resolution"]["resolved_dimensions"][dimension] = singleton
        restamp_resolution!(narrowed)
        @test evaluate_requirement_completion(
            contract,
            singleton_requirement,
            [narrowed],
        ).rejected_evidence == [
            "evidence.$singleton_profile:SET_RESOLUTION_DIMENSION_MISMATCH",
        ]
    end

    dynamic_profile = evidence_row(
        contract,
        "bea_gdpbyindustry_sector_accounts",
        "gdpbyindustry_t1_value_added_annual_2024",
    )
    dynamic_profile["resolution"]["set_resolutions"]["Industry"][
        "candidate_catalog_sha256",
    ] = digest("different candidate catalog")
    restamp_resolution!(dynamic_profile)
    @test evaluate_requirement_completion(
        contract,
        "bea_gdpbyindustry_sector_accounts",
        [dynamic_profile],
    ).rejected_evidence == [
        "evidence.gdpbyindustry_t1_value_added_annual_2024:SET_RESOLUTION_CATALOG_MISMATCH",
    ]

    singleton_claim = evidence_row(
        contract,
        "bea_gdpbyindustry_sector_accounts",
        "gdpbyindustry_t1_value_added_annual_2024",
    )
    singleton_claim["resolution"]["set_resolutions"]["Industry"][
        "member_count",
    ] = 1
    restamp_resolution!(singleton_claim)
    @test_throws ProspectiveContractV2ValidationError evaluate_requirement_completion(
        contract,
        "bea_gdpbyindustry_sector_accounts",
        [singleton_claim],
    )
end

@testset "calendar adds exact Census events and final capture" begin
    contract = checked_contract()
    fixed = Dict(row["event_id"] => row for row in contract["fixed_events"])
    campaigns = Dict(
        row["campaign_id"] => row for row in contract["snapshot_campaigns"]
    )

    @test length(fixed) == 12
    @test fixed["census_m3_2026_08_full"]["scheduled_timestamp_utc"] ==
        "2026-10-02T14:00:00Z"
    @test fixed["census_mwts_2026_08"]["scheduled_timestamp_utc"] ==
        "2026-10-08T14:00:00Z"
    @test fixed["census_mrts_inventory_2026_08"][
        "scheduled_timestamp_utc",
    ] == "2026-10-15T14:00:00Z"
    @test fixed["census_m3_2026_09_advance"][
        "scheduled_timestamp_utc",
    ] == "2026-10-27T12:30:00Z"
    @test all(
        fixed[id]["timestamp_basis"] == "official_exact" for id in (
                "census_m3_2026_08_full",
                "census_mwts_2026_08",
                "census_mrts_inventory_2026_08",
                "census_m3_2026_09_advance",
            )
    )
    @test fixed["bea_annual_update_2026"]["requirement_ids"] == [
        "bea_fixed_assets_structural",
        "bea_gdpbyindustry_sector_accounts",
        "bea_industry_io_structural",
        "bea_industry_valuation_structural",
        "bea_nipa_expenditure_history",
        "bea_nipa_income_fiscal_structural",
        "bea_nipa_tier1",
    ]
    @test !fixed["bea_annual_update_2026"]["required_for_complete_origin"]
    @test requirement(
        contract,
        "bea_industry_valuation_structural",
    )["default_capture_id"] == "slow_structural_pre_origin"
    @test "bea_industry_valuation_structural" in
        campaigns["slow_structural_pre_origin"]["requirement_ids"]
    @test !(
        "bea_industry_valuation_structural" in
            campaigns["final_structural_pre_origin"]["requirement_ids"]
    )
    @test "fred_policy_rate_history" in
        campaigns["final_structural_pre_origin"]["requirement_ids"]
    @test fixed["bea_gdp_2026q3_advance"]["requirement_ids"] == [
        "bea_inventory_stock_control",
        "bea_nipa_expenditure_history",
        "bea_nipa_income_fiscal_structural",
        "bea_nipa_tier1",
    ]
    @test fixed["bls_employment_situation_2026_09"][
        "requirement_ids",
    ] == [
        "bls_cps_structural",
        "bls_employment_tier1",
    ]
    @test all(
        row["excluded_dates"] == ["2026-09-07", "2026-10-12"]
            for row in contract["recurring_windows"]
    )
    @test campaigns["final_structural_pre_origin"][
        "capture_not_before_utc",
    ] == "2026-10-29T13:30:00Z"
    @test campaigns["final_structural_pre_origin"][
        "capture_deadline_utc",
    ] == "2026-10-30T13:45:00Z"
    @test all(row["receipt_count"] == 0 for row in contract["fixed_events"])
    @test all(!row["origin_eligible"] for row in contract["fixed_events"])
    @test all(
        row["receipt_count"] == 0 for row in contract["snapshot_campaigns"]
    )
    @test all(
        !row["origin_eligible"] for row in contract["snapshot_campaigns"]
    )
end

@testset "semantic tampering fails after an attacker recomputes the digest" begin
    ready = checked_contract()
    ready["origin"]["ready"] = true
    restamp!(ready)
    @test_throws ProspectiveContractV2ValidationError validate_contract(ready)

    admissible = checked_contract()
    admissible["origin"]["origin_admissible"] = true
    restamp!(admissible)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        admissible,
    )

    inventory_write = checked_contract()
    inventory_write["origin"]["inventory_mutation_authorized"] = true
    restamp!(inventory_write)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        inventory_write,
    )

    admitted = checked_contract()
    admitted["origin"]["admission_status"] = "ADMITTED"
    restamp!(admitted)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        admitted,
    )

    any_profile = checked_contract()
    any_profile["requirements"][1]["completion_rule"] =
        "ANY_PROFILE_VERIFIED"
    restamp!(any_profile)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        any_profile,
    )

    removed_profile = checked_contract()
    delete!(
        removed_profile["requirements"][1]["artifact_profiles"],
        "faat703_government_depreciation",
    )
    removed_profile["requirements"][1]["required_profile_count"] = 7
    restamp!(removed_profile)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        removed_profile,
    )

    arbitrary_profile = checked_contract()
    delete!(
        arbitrary_profile["requirements"][1]["artifact_profiles"],
        "faat703_government_depreciation",
    )
    arbitrary_profile["requirements"][1]["artifact_profiles"][
        "arbitrary_file",
    ] = "file:///tmp/unrelated.csv"
    restamp!(arbitrary_profile)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        arbitrary_profile,
    )

    census_basis_drift = checked_contract()
    census_basis_drift["fixed_events"][7]["timestamp_basis"] =
        "official_approximate_window"
    restamp!(census_basis_drift)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        census_basis_drift,
    )

    event_binding_drift = checked_contract()
    pop!(event_binding_drift["fixed_events"][5]["requirement_ids"])
    restamp!(event_binding_drift)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        event_binding_drift,
    )

    profile_capture_drift = checked_contract()
    requirement(
        profile_capture_drift,
        "census_m3_inventory_stages",
    )["profile_capture_overrides"][
        "m3_2026_09_advance_total",
    ] = "census_m3_2026_08_full"
    restamp!(profile_capture_drift)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        profile_capture_drift,
    )

    profile_date_drift = checked_contract()
    requirement(
        profile_date_drift,
        "frbny_effr_tier1",
    )["profile_completion_dates"][
        "effr_first_state_manifest",
    ] = "2026-08-07"
    restamp!(profile_date_drift)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        profile_date_drift,
    )

    holiday_drift = checked_contract()
    empty!(holiday_drift["recurring_windows"][1]["excluded_dates"])
    restamp!(holiday_drift)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        holiday_drift,
    )

    campaign_drift = checked_contract()
    campaign_drift["snapshot_campaigns"][2]["capture_deadline_utc"] =
        "2026-10-30T13:46:00Z"
    restamp!(campaign_drift)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        campaign_drift,
    )

    fabricated_receipt = checked_contract()
    fabricated_receipt["fixed_events"][1]["receipt_count"] = 1
    restamp!(fabricated_receipt)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        fabricated_receipt,
    )

    extra_policy_key = checked_contract()
    extra_policy_key["availability_policy"]["backdoor"] = true
    restamp!(extra_policy_key)
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        extra_policy_key,
    )

    digest_tamper = TOML.parsefile(CONTRACT_PATH)
    digest_tamper["requirements"][1]["source_locator"] =
        "https://example.invalid/arbitrary"
    @test_throws ProspectiveContractV2ValidationError validate_contract(
        digest_tamper,
    )
end
