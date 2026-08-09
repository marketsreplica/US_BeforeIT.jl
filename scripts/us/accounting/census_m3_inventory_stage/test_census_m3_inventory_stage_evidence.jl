using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USCensusM3InventoryStageEvidence.jl"))
using .USCensusM3InventoryStageEvidence

const CONTRACT_PATH =
    joinpath(@__DIR__, "census_m3_inventory_stage_evidence.toml")
const CONTRACT_SHA256 =
    "21cf991d9caa74c793fac50a07a61ec4368b41f99714bbc6c96d2bf824db949e"

file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

function series_row(
        evidence,
        series_id,
        year,
    )
    return only(
        row for row in evidence.series_rows if
            row.series_id == series_id && row.year == year
    )
end

function rewrite_series_row(
        row;
        series_id = row.series_id,
        seasonal_adjustment_code = row.seasonal_adjustment_code,
        m3_series_code = row.m3_series_code,
        item_code = row.item_code,
        values = row.values,
    )
    return M3InventorySeriesRow(
        row.source_row,
        series_id,
        seasonal_adjustment_code,
        m3_series_code,
        item_code,
        row.year,
        values,
    )
end

function rewrite_identity(
        check;
        total_millions = check.total_millions,
        residual_millions = check.residual_millions,
        status = check.status,
    )
    return M3InventoryIdentityCheck(
        check.check_id,
        check.seasonal_adjustment_code,
        check.m3_series_code,
        check.reference_period,
        check.total_series_id,
        check.materials_series_id,
        check.work_in_process_series_id,
        check.finished_goods_series_id,
        total_millions,
        check.materials_millions,
        check.work_in_process_millions,
        check.finished_goods_millions,
        residual_millions,
        status,
    )
end

@testset "Fail-closed Census M3 inventory-stage evidence" begin
    evidence = load_m3_inventory_stage_evidence(CONTRACT_PATH)
    contract = evidence.contract
    fixture = evidence.fixture_manifest

    @testset "Pinned current-workbook capture and official scope" begin
        @test file_sha256(CONTRACT_PATH) == CONTRACT_SHA256
        @test APPROVED_CONTRACT_SHA256 == CONTRACT_SHA256
        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test !contract["forecast_origin_admissible"]
        @test !contract["economy_wide_scope_claimed"]
        @test !contract["bea_allocation_applied"]
        @test !contract["commodity_holder_crosswalk_applied"]
        @test !contract["transition_emitted"]
        @test !contract["model_inventory_vector_emitted"]
        @test !contract["model_state_write"]
        @test contract["accounting_gate_effect"] == "NONE"
        @test contract["forecast_score_effect"] == "NONE"
        @test contract["source_semantics"]["scope"] ==
            "DOMESTIC_MANUFACTURING_M3_SURVEY_ONLY"
        @test contract["source_semantics"]["time_basis"] ==
            "END_OF_MONTH_STOCK_LEVEL"
        @test contract["source_semantics"]["about_page_valuation_basis"] ==
            "CURRENT_COST_OR_MARKET_VALUE"
        @test contract["source_semantics"][
            "historical_documentation_valuation_basis",
        ] == "MILLIONS_OF_DOLLARS_AT_CURRENT_MARKET"
        @test contract["source_semantics"][
            "definitions_page_valuation_basis",
        ] == "COST_USING_ANY_VALUATION_METHOD_OTHER_THAN_LIFO"
        @test fixture["source_workbook_vintage"] ==
            "CURRENT_MUTABLE_CAPTURE_NOT_IMMUTABLE_RELEASE"
        @test fixture["source_revision_status"] ==
            "NOT_ENCODED_PER_CELL_IN_WORKBOOK"
        @test fixture["workbook_internal_period_hint"] == "2026/Jun26"
        @test fixture["expected"]["latest_observed_period"] == "2026-06"
        @test all(
            startswith(value, "https://www.census.gov/")
                for value in values(contract["citations"])
        )
        @test contract["citations"]["methodology_url"] ==
            "https://www.census.gov/manufacturing/m3/how_the_data_are_collected/index.html"

        mktempdir() do directory
            changed = joinpath(directory, "changed.toml")
            write(changed, read(CONTRACT_PATH), UInt8('\n'))
            @test_throws ArgumentError load_m3_inventory_stage_evidence(
                changed,
            )
        end
    end

    @testset "Adjusted, unadjusted, stage, and source-missing codes" begin
        @test length(evidence.series_rows) == 11_060
        @test length(Set(row.series_id for row in evidence.series_rows)) == 316
        @test count(
            startswith("A"),
            Set(row.series_id for row in evidence.series_rows),
        ) == 158
        @test count(
            startswith("U"),
            Set(row.series_id for row in evidence.series_rows),
        ) == 158
        @test count(
            row -> row.item_code == "TI" && row.year == 1992,
            evidence.series_rows,
        ) == 172
        @test count(
            row -> row.item_code == "MI" && row.year == 1992,
            evidence.series_rows,
        ) == 48
        @test count(
            row -> row.item_code == "WI" && row.year == 1992,
            evidence.series_rows,
        ) == 48
        @test count(
            row -> row.item_code == "FI" && row.year == 1992,
            evidence.series_rows,
        ) == 48

        adjusted_total = series_row(evidence, "AMTMTI", 2026)
        adjusted_materials = series_row(evidence, "AMTMMI", 2026)
        adjusted_work_in_process = series_row(evidence, "AMTMWI", 2026)
        adjusted_finished = series_row(evidence, "AMTMFI", 2026)
        @test adjusted_total.values[6] == 962_917
        @test adjusted_materials.values[6] == 362_981
        @test adjusted_work_in_process.values[6] == 271_540
        @test adjusted_finished.values[6] == 328_396
        @test all(
            ismissing,
            adjusted_total.values[7:12],
        )
        @test source_cell_state(missing) == SOURCE_MISSING
        @test source_cell_state(0) == SOURCE_EXPLICIT_ZERO
        @test source_cell_state(1) == SOURCE_OBSERVED_NONZERO
        @test source_cell_state(-1) == SOURCE_OBSERVED_NONZERO

        @test decode_series_id("AMTMTI") == (
            seasonal_adjustment_code = "A",
            m3_series_code = "MTM",
            item_code = "TI",
        )
        @test decode_series_id("U25SWI").item_code == "WI"
        @test_throws ArgumentError decode_series_id("BMTMTI")
        @test_throws ArgumentError decode_series_id("AMTMXX")
        @test_throws ArgumentError decode_series_id("AMTMT")
    end

    @testset "Published stage identities are exact but source-controlled" begin
        @test length(evidence.identity_checks) == 20_160
        @test count(
            check -> check.status == :PASS_EXACT_SOURCE_IDENTITY,
            evidence.identity_checks,
        ) == 19_872
        @test count(
            check -> check.status == :NOT_RUN_SOURCE_MISSING,
            evidence.identity_checks,
        ) == 288
        @test all(
            check ->
            ismissing(check.residual_millions) ||
                iszero(check.residual_millions),
            evidence.identity_checks,
        )
        june = only(
            check for check in evidence.identity_checks if
                check.check_id == "AMTM_2026-06"
        )
        @test june.total_millions == 962_917
        @test june.materials_millions == 362_981
        @test june.work_in_process_millions == 271_540
        @test june.finished_goods_millions == 328_396
        @test june.residual_millions == 0
        july = only(
            check for check in evidence.identity_checks if
                check.check_id == "AMTM_2026-07"
        )
        @test july.status == :NOT_RUN_SOURCE_MISSING
        @test all(
            ismissing,
            (
                july.total_millions,
                july.materials_millions,
                july.work_in_process_millions,
                july.finished_goods_millions,
                july.residual_millions,
            ),
        )
        @test contract["source_method"][
            "stage_control_allocation_is_census_method",
        ]
        @test occursin(
            "PROPORTIONALLY_ALLOCATED",
            contract["source_method"]["unadjusted_stage_method"],
        )
        @test occursin(
            "PROPORTIONALLY_ALLOCATED",
            contract["source_method"]["seasonally_adjusted_stage_method"],
        )
        @test occursin(
            "CANNOT_REPORT_STAGE_DETAIL",
            contract["source_method"]["reason"],
        )
        @test !contract["source_method"][
            "independent_stage_measurement_claimed",
        ]
        @test !contract["source_method"]["project_allocation_applied"]
    end

    @testset "Adversarial missing, zero, code, and identity mutations fail" begin
        source_zero = deepcopy(evidence)
        index = findfirst(
            row -> row.series_id == "AMTMTI" && row.year == 2026,
            source_zero.series_rows,
        )
        original = source_zero.series_rows[index]
        changed_values = Base.setindex(original.values, Int64(0), 7)
        source_zero.series_rows[index] = rewrite_series_row(
            original;
            values = changed_values,
        )
        @test_throws ArgumentError validate_m3_inventory_stage_evidence(
            source_zero,
        )

        source_missing = deepcopy(evidence)
        original = source_missing.series_rows[index]
        changed_values = Base.setindex(original.values, missing, 6)
        source_missing.series_rows[index] = rewrite_series_row(
            original;
            values = changed_values,
        )
        @test_throws ArgumentError validate_m3_inventory_stage_evidence(
            source_missing,
        )

        bad_code = deepcopy(evidence)
        original = bad_code.series_rows[1]
        bad_code.series_rows[1] = rewrite_series_row(
            original;
            series_id = "BMTMTI",
            seasonal_adjustment_code = "B",
        )
        @test_throws ArgumentError validate_m3_inventory_stage_evidence(
            bad_code,
        )

        bad_identity = deepcopy(evidence)
        check_index = findfirst(
            check -> check.check_id == "AMTM_2026-06",
            bad_identity.identity_checks,
        )
        original_check = bad_identity.identity_checks[check_index]
        bad_identity.identity_checks[check_index] = rewrite_identity(
            original_check;
            total_millions = original_check.total_millions + 1,
            residual_millions = 1,
            status = :FAIL_SOURCE_IDENTITY,
        )
        @test_throws ArgumentError validate_m3_inventory_stage_evidence(
            bad_identity,
        )
    end

    @testset "Every unsupported model boundary remains blocked" begin
        for operation in (
                :economy_wide_bea_allocation,
                :commodity_holder_crosswalk,
                :stage_to_model_stock_scope_bridge,
                :stock_flow_transition,
                :current_vintage_to_forecast_origin,
                :model_state_write,
                :accounting_gate,
                :forecast_score,
            )
            @test_throws ArgumentError request_model_bridge(
                evidence,
                operation,
            )
        end
        @test_throws ArgumentError request_model_bridge(
            evidence,
            :unknown_operation,
        )
    end
end
