using CSV
using JSON
using SHA
using Test
using TOML

include(
    joinpath(
        @__DIR__,
        "USOECDSourceAxisValuationDiagnostic.jl",
    ),
)
using .USOECDSourceAxisValuationDiagnostic

const OECD_CONTRACT_PATH =
    joinpath(@__DIR__, "oecd_source_axis_valuation.toml")
const OECD_GENERATOR_PATH =
    joinpath(@__DIR__, "generate_oecd_source_axis_fixture.py")
const OECD_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "oecd_sut_usa_2024_v2")
const OECD_RAW_DIRECTORY =
    joinpath(@__DIR__, "raw", "oecd_sut_usa_2024_v2")
const OECD_BEA_FIXTURE_DIRECTORY =
    normpath(joinpath(@__DIR__, "..", "fixtures", "bea_2024_approved"))
const OECD_PROJECT_PATH =
    normpath(joinpath(@__DIR__, "..", "..", "Project.toml"))
const OECD_MANIFEST_PATH =
    normpath(joinpath(@__DIR__, "..", "..", "Manifest.toml"))

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function copy_fixture(source_directory)
    target_directory = mktempdir()
    for filename in (
            "axis_codes.csv",
            "cells.csv",
            "identity_evaluations.csv",
            "manifest.toml",
            "source_receipts.json",
            "source_totals.csv",
            "t1610_nonbasic_quarantine.csv",
        )
        cp(
            joinpath(source_directory, filename),
            joinpath(target_directory, filename),
        )
    end
    return target_directory
end

function with_key(cell, key)
    return SourceAxisCell(
        cell.index,
        key,
        cell.recipient_type,
        cell.transaction_axis_role,
        cell.activity_axis_role,
        cell.product_axis_role,
        cell.unit_measure,
        cell.unit_mult,
        cell.currency,
        cell.decimals,
        cell.obs_status,
        cell.purchasers,
        cell.basic,
        cell.combined_margin,
        cell.net_product_tax,
        cell.gross_product_tax,
        cell.subsidy_magnitude,
    )
end

@testset "OECD USA 2024 source-axis valuation diagnostic" begin
    report = load_oecd_source_axis_valuation_diagnostic()
    contract = TOML.parsefile(OECD_CONTRACT_PATH)
    fixture_manifest =
        TOML.parsefile(joinpath(OECD_FIXTURE_DIRECTORY, "manifest.toml"))
    receipts = JSON.parsefile(
        joinpath(OECD_FIXTURE_DIRECTORY, "source_receipts.json"),
    )

    @testset "Pinned current-vintage retrieval-only boundary" begin
        @test sha256_hex(read(OECD_CONTRACT_PATH)) ==
            "aaddffcf1418299b8350add0dd81950cb2deaf1343e467decc37b009a4cd43f3"
        @test sha256_hex(read(OECD_GENERATOR_PATH)) ==
            "e6690b200017f9b2c06cb1f9cc3fd210b73a1b1552902c03d8baac3603be6fde"
        @test sha256_hex(read(OECD_PROJECT_PATH)) ==
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
        @test sha256_hex(read(OECD_MANIFEST_PATH)) ==
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
        @test sha256_hex(
            read(joinpath(OECD_FIXTURE_DIRECTORY, "manifest.toml")),
        ) ==
            "62a1f77cc89d1ba735d1ba9e366ff553e132f741de8cac19b42b419247b8367a"
        @test sha256_hex(
            read(joinpath(OECD_FIXTURE_DIRECTORY, "cells.csv")),
        ) ==
            "25531db1941cbc00dc8294e31322cc5c425a4ff0365d0f517850a3538176b5a4"
        @test sha256_hex(
            read(
                joinpath(
                    OECD_FIXTURE_DIRECTORY,
                    "identity_evaluations.csv",
                ),
            ),
        ) ==
            "30a1dcce1f87283b051bec4ea1e5ea1e5944deb721773463f6d3fb6c15fa3e8e"
        @test sha256_hex(
            read(joinpath(OECD_FIXTURE_DIRECTORY, "axis_codes.csv")),
        ) ==
            "29d56d85154e9bb9317f999576869ea071cd1ca8858baa81c8921d52b6da52f6"
        @test sha256_hex(
            read(joinpath(OECD_FIXTURE_DIRECTORY, "source_totals.csv")),
        ) ==
            "e10c53d53148005cdf0fc8c396f19bf911bd48ea93b9a21843c6dd72d94f537f"
        @test sha256_hex(
            read(
                joinpath(
                    OECD_FIXTURE_DIRECTORY,
                    "t1610_nonbasic_quarantine.csv",
                ),
            ),
        ) ==
            "3691a589f1678e4aa19f4db0ab9b0545aa7dfc128983a54e9d2df85f1fc7fdc4"
        @test sha256_hex(
            read(
                joinpath(
                    OECD_FIXTURE_DIRECTORY,
                    "source_receipts.json",
                ),
            ),
        ) ==
            "695b683fd6709b9e5cf4225999773bdc5ecb0b4f7bb1a6dec956cba7fa88b083"
        @test sha256_hex(
            read(joinpath(OECD_BEA_FIXTURE_DIRECTORY, "cells.csv")),
        ) ==
            "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0"
        @test sha256_hex(
            read(joinpath(OECD_BEA_FIXTURE_DIRECTORY, "manifest.toml")),
        ) ==
            "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c"

        @test contract["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test !contract["forecast_origin_admissible"]
        @test !contract["model_state_write"]
        @test contract["accounting_gate_effect"] == "NONE"
        @test contract["forecast_score_effect"] == "NONE"
        @test contract["mapping_policy"] ==
            "Every CPA08/ISIC4 to BEA or model mapping is NOT_RUN_BLOCKED."
        @test contract["combined_margin_policy"] ==
            "T1620 remains the combined trade-plus-transport margin. No split is attempted."
        @test occursin(
            "NOT_EVALUABLE_SOURCE_MISSING",
            contract["missing_component_arithmetic"],
        )
        @test contract["structural_zero_policy"] ==
            "Only an explicit source observation of numeric zero is SOURCE_EXPLICIT_ZERO. The archived OECD metadata supplies no separate structural-zero designation for absent component tuples."
        @test fixture_manifest["source_missing_identity_policy"] ==
            "NOT_EVALUABLE_SOURCE_MISSING"
        @test fixture_manifest["structural_zero_metadata_status"] ==
            "ABSENT"
        @test fixture_manifest["equation_diagnostics"][
            "valuation_identity_evaluated_count",
        ] == 4_226
        @test fixture_manifest["equation_diagnostics"][
            "valuation_identity_not_evaluable_source_missing_count",
        ] == 6_449
        @test fixture_manifest["equation_diagnostics"][
            "tax_identity_evaluated_count",
        ] == 1_257
        @test fixture_manifest["equation_diagnostics"][
            "tax_identity_not_evaluable_source_missing_count",
        ] == 9_418
        @test report.classification == contract["classification"]
        @test report.year == 2024
        @test !report.model_state_write
        @test report.accounting_gate_effect == :none
        @test !report.forecast_origin_admissible
        @test report.forecast_score_effect == :none
        @test report.combined_margin_split_status == :not_run_blocked
        @test report.cpa_isic_to_bea_mapping_status == :not_run_blocked
        @test report.cpa_isic_to_model_mapping_status == :not_run_blocked
        @test !report.promotion_ready
        @test length(report.promotion_blockers) == 13
        @test "OECD_BEA_150_33_BILLION_PP_BP_RESIDUAL_DUBIOUS" in
            report.promotion_blockers
        @test "OECD_BEA_COMBINED_MARGIN_OUTSIDE_DERIVED_ROUNDING_BOUND_DUBIOUS" in
            report.promotion_blockers
        @test length(report.prohibited_operations) == 7
    end

    @testset "Exact raw response archive and retrieval receipts" begin
        @test receipts["captured_at_utc"] == "2026-08-06T15:10:26Z"
        @test receipts["credentials_required"] == false
        @test receipts["http_method"] == "GET"
        @test receipts["sdmx_version"] == "2.0"
        @test receipts["response_hash_policy"] ==
            "exact_raw_response_bytes"
        @test receipts["source_bundle_sha256"] ==
            "b202aa776874eb712a207f9be6f312a12c5d73ed367db881c32f7bb81936a1f7"
        @test receipts["oecd_dataset_url"] ==
            "https://www.oecd.org/en/data/datasets/supply-and-use-tables.html"
        @test receipts["oecd_api_documentation_url"] ==
            "https://www.oecd.org/en/data/insights/data-explainers/2024/09/api.html"
        @test receipts["oecd_terms_url"] ==
            "https://www.oecd.org/en/about/terms-conditions.html"
        @test occursin("OECD (2026)", receipts["oecd_attribution"])
        responses = receipts["responses"]
        @test length(responses) == 25
        @test count(item -> item["kind"] == "data", responses) == 6
        @test count(item -> item["kind"] == "structure", responses) == 3
        @test count(item -> item["kind"] == "hierarchy", responses) == 4
        @test count(item -> item["kind"] == "codelist", responses) == 12
        @test length(readdir(OECD_RAW_DIRECTORY)) == 25
        for response in responses
            path = joinpath(OECD_RAW_DIRECTORY, response["local_name"])
            @test isfile(path)
            @test filesize(path) == response["byte_count"]
            @test sha256_hex(read(path)) == response["sha256"]
            @test response["retrieved_at_utc"] ==
                "2026-08-06T15:10:26Z"
            @test response["query_parameters"] ==
                split(response["url"], "?"; limit = 2)[2]
            @test response["response_content_type"] ==
                (
                response["kind"] == "data" ?
                    "text/csv; charset=utf-8" :
                    "application/vnd.sdmx.structure+xml; charset=utf-8; version=2.1"
            )
            @test startswith(
                response["url"],
                "https://sdmx.oecd.org/public/rest/",
            )
        end
        data_urls = Dict(
            item["name"] => item["url"] for
                item in responses if item["kind"] == "data"
        )
        @test occursin(
            "DSD_NASU@DF_USEPP,2.0/A.USA......V.T1600",
            data_urls["data_T1600"],
        )
        @test occursin(
            "DSD_NASU@DF_USEBP,2.0/A.USA......V.T1610",
            data_urls["data_T1610"],
        )
        for table in ("T1620", "T1630", "T1633", "T1634")
            @test occursin(
                "DSD_NASU@DF_VALUATION,2.0/A.USA......V.$table",
                data_urls["data_$table"],
            )
        end
        @test all(
            occursin("startPeriod=2024&endPeriod=2024", url) for
                url in values(data_urls)
        )
        @test all(
            occursin("dimensionAtObservation=AllDimensions", url) for
                url in values(data_urls)
        )
    end

    @testset "Source axes, recipients, hierarchy, and zero semantics" begin
        @test length(report.cells) == 10_675
        @test length(report.axis_codes) == 245
        @test fixture_manifest["source_axis_cell_count"] == 10_675
        @test fixture_manifest["axis_code_count"] == 245
        @test fixture_manifest["t1610_nonbasic_quarantine_count"] == 245
        audit = validate_source_axis_cells(
            report.cells;
            expected_count = 10_675,
            enforce_approved_semantics_counts = true,
        )
        @test audit.maximum_valuation_residual == 1
        @test audit.maximum_tax_residual == 1
        @test audit.explicit_zero_counts == Dict(
            :purchasers => 111,
            :basic => 14,
            :combined_margin => 137,
            :net_product_tax => 246,
            :gross_product_tax => 177,
            :subsidy_magnitude => 123,
        )
        @test audit.missing_counts == Dict(
            :purchasers => 180,
            :basic => 2,
            :combined_margin => 6_175,
            :net_product_tax => 952,
            :gross_product_tax => 1_120,
            :subsidy_magnitude => 9_250,
        )
        @test count(
            cell -> cell.recipient_type == :industry_intermediate_use,
            report.cells,
        ) > 0
        @test count(
            cell -> cell.recipient_type == :intermediate_use_total,
            report.cells,
        ) > 0
        @test count(
            cell -> cell.recipient_type == :final_use,
            report.cells,
        ) > 0
        @test count(
            cell -> cell.recipient_type == :total_use,
            report.cells,
        ) > 0
        @test all(cell -> cell.unit_measure == "XDC", report.cells)
        @test all(cell -> cell.unit_mult == "6", report.cells)
        @test all(cell -> cell.currency == "USD", report.cells)
        @test all(cell -> cell.decimals == "2", report.cells)
        @test all(cell -> cell.obs_status == "A", report.cells)

        missing_observation = first(
            cell.subsidy_magnitude for
                cell in report.cells if !cell.subsidy_magnitude.present
        )
        explicit_zero_observation = first(
            cell.subsidy_magnitude for
                cell in report.cells if
                source_observation_semantics(cell.subsidy_magnitude) ==
                SOURCE_EXPLICIT_ZERO
        )
        @test source_observation_semantics(missing_observation) ==
            SOURCE_MISSING
        @test ismissing(
            missing_observation.value_hundredths_million_usd,
        )
        @test_throws ArgumentError additive_value(missing_observation)
        @test source_observation_semantics(explicit_zero_observation) ==
            SOURCE_EXPLICIT_ZERO
        @test explicit_zero_observation.value_hundredths_million_usd == 0
        @test additive_value(explicit_zero_observation) == 0

        @test any(
            code ->
            code.axis == :activity &&
                code.code == "A" &&
                code.axis_role == :aggregate &&
                code.child_count == 3,
            report.axis_codes,
        )
        @test any(
            code ->
            code.axis == :activity &&
                code.code == "A01" &&
                code.axis_role == :leaf &&
                code.parent_code == "A",
            report.axis_codes,
        )
        @test any(
            code ->
            code.axis == :product &&
                code.code == "_T" &&
                code.axis_role == :published_total,
            report.axis_codes,
        )
        @test any(
            code ->
            code.axis == :transaction &&
                code.code == "TU" &&
                code.axis_role == :aggregate,
            report.axis_codes,
        )

        quarantined = collect(
            CSV.File(
                joinpath(
                    OECD_FIXTURE_DIRECTORY,
                    "t1610_nonbasic_quarantine.csv",
                ),
            ),
        )
        @test length(quarantined) == 245
        @test count(row -> String(row.valuation) == "O", quarantined) == 123
        @test count(row -> String(row.valuation) == "Y", quarantined) == 122
        @test all(
            row ->
            String(row.quarantine_reason) ==
                "not_basic_valuation_for_T1610_source_axis_identity",
            quarantined,
        )
    end

    @testset "Cellwise identities and published source controls" begin
        @test length(
            report.valuation_identity_evaluations,
        ) == 10_675
        @test length(report.tax_identity_evaluations) == 10_675
        @test count(
            evaluation ->
            evaluation.status == :PASS_AT_SOURCE_ROUNDING,
            report.valuation_identity_evaluations,
        ) == 4_226
        @test count(
            evaluation ->
            evaluation.status == :NOT_EVALUABLE_SOURCE_MISSING,
            report.valuation_identity_evaluations,
        ) == 6_449
        @test count(
            evaluation ->
            evaluation.status == :PASS_AT_SOURCE_ROUNDING,
            report.tax_identity_evaluations,
        ) == 1_257
        @test count(
            evaluation ->
            evaluation.status == :NOT_EVALUABLE_SOURCE_MISSING,
            report.tax_identity_evaluations,
        ) == 9_418
        @test all(
            evaluation ->
            evaluation.status != :NOT_EVALUABLE_SOURCE_MISSING ||
                (
                ismissing(
                    evaluation.residual_hundredths_million_usd,
                ) &&
                    !isempty(evaluation.missing_components)
            ),
            vcat(
                report.valuation_identity_evaluations,
                report.tax_identity_evaluations,
            ),
        )
        @test all(
            evaluation ->
            evaluation.status != :PASS_AT_SOURCE_ROUNDING ||
                (
                !ismissing(
                    evaluation.residual_hundredths_million_usd,
                ) &&
                    isempty(evaluation.missing_components)
            ),
            vcat(
                report.valuation_identity_evaluations,
                report.tax_identity_evaluations,
            ),
        )
        @test length(
            report.valuation_identity_residuals_hundredths_million_usd,
        ) == 4_226
        @test length(
            report.tax_identity_residuals_hundredths_million_usd,
        ) == 1_257
        @test maximum(
            abs,
            report.valuation_identity_residuals_hundredths_million_usd,
        ) == 1
        @test maximum(
            abs,
            report.tax_identity_residuals_hundredths_million_usd,
        ) == 1
        @test all(
            residual -> abs(residual) <= 1,
            report.valuation_identity_residuals_hundredths_million_usd,
        )
        @test all(
            residual -> abs(residual) <= 1,
            report.tax_identity_residuals_hundredths_million_usd,
        )
        expected_totals = Dict(
            :purchasers => 5_456_842_235,
            :basic => 5_355_809_681,
            :combined_margin => -4,
            :net_product_tax => 101_032_558,
            :gross_product_tax => 109_968_166,
            :subsidy_magnitude => 8_935_607,
        )
        for (component, expected) in expected_totals
            @test source_total(report, component) == expected
            @test report.source_totals[component].aggregation_policy ==
                :published_total_cell_only
        end
        @test abs(
            source_total(report, :net_product_tax) -
                source_total(report, :gross_product_tax) +
                source_total(report, :subsidy_magnitude),
        ) <= 1
        @test source_total(report, :purchasers) ==
            source_total(report, :basic) +
            source_total(report, :combined_margin) +
            source_total(report, :net_product_tax)

        naive_purchasers_sum = sum(
            additive_value(cell.purchasers) for
                cell in report.cells if cell.purchasers.present
        )
        @test naive_purchasers_sum == 56_878_231_313
        @test naive_purchasers_sum != source_total(report, :purchasers)
        @test_throws ArgumentError source_total(
            report,
            :purchasers;
            aggregation = :sum_all_aggregate_and_child_rows,
        )
    end

    @testset "Derived BEA rounding bounds and retained DUBIOUS residuals" begin
        residuals = Dict(
            residual.component => residual for
                residual in report.cross_source_residuals
        )
        @test residuals[:net_product_tax].residual_hundredths_million_usd ==
            -42
        @test residuals[:gross_product_tax].residual_hundredths_million_usd ==
            -34
        @test residuals[:subsidy_magnitude].residual_hundredths_million_usd ==
            7
        @test residuals[:combined_margin].residual_hundredths_million_usd ==
            96
        for component in (
                :net_product_tax,
                :gross_product_tax,
                :subsidy_magnitude,
            )
            @test residuals[component].status ==
                :PASS_AT_CROSS_SOURCE_ROUNDING
            @test 2 * abs(
                residuals[component].residual_hundredths_million_usd,
            ) <= residuals[component].rounding_bound_twice_hundredths_million_usd
            @test residuals[component].balance_action ==
                :retain_unadjusted
        end
        @test residuals[:combined_margin].status ==
            :DUBIOUS_OUTSIDE_DERIVED_CROSS_SOURCE_ROUNDING_BOUND
        @test residuals[:combined_margin].boundary_type ==
            :outside_component_specific_derived_rounding_bound
        @test residuals[:combined_margin].rounding_bound_twice_hundredths_million_usd ==
            101
        @test 2 * abs(
            residuals[:combined_margin].residual_hundredths_million_usd,
        ) > residuals[:combined_margin].rounding_bound_twice_hundredths_million_usd
        @test residuals[:combined_margin].balance_action ==
            :retain_unadjusted

        for component in (
                :purchasers,
                :basic,
                :combined_margin,
                :net_product_tax,
                :subsidy_magnitude,
            )
            @test residuals[component].oecd_term_count == 1
            @test residuals[component].oecd_term_resolution_hundredths_million_usd ==
                1
            @test residuals[component].bea_term_count == 1
            @test residuals[component].bea_term_resolution_hundredths_million_usd ==
                100
            @test residuals[component].rounding_bound_twice_hundredths_million_usd ==
                101
        end
        @test residuals[:gross_product_tax].oecd_term_count == 1
        @test residuals[:gross_product_tax].oecd_term_codes == ["T1633"]
        @test residuals[:gross_product_tax].oecd_term_resolution_hundredths_million_usd ==
            1
        @test residuals[:gross_product_tax].bea_term_count == 2
        @test residuals[:gross_product_tax].bea_term_codes ==
            ["TOP", "MDTY"]
        @test residuals[:gross_product_tax].bea_term_resolution_hundredths_million_usd ==
            100
        @test residuals[:gross_product_tax].rounding_bound_twice_hundredths_million_usd ==
            201
        @test residuals[:net_product_tax].oecd_term_codes == ["T1630"]
        @test residuals[:net_product_tax].bea_term_codes == ["T015"]
        @test residuals[:subsidy_magnitude].oecd_term_codes == ["T1634"]
        @test residuals[:subsidy_magnitude].bea_term_codes == ["SUB"]

        @test residuals[:purchasers].residual_hundredths_million_usd ==
            15_033_035
        @test residuals[:basic].residual_hundredths_million_usd ==
            15_032_881
        @test residuals[:purchasers].status ==
            :DUBIOUS_CROSS_SOURCE_RELEASE_BOUNDARY_RESIDUAL
        @test residuals[:basic].status ==
            :DUBIOUS_CROSS_SOURCE_RELEASE_BOUNDARY_RESIDUAL
        @test residuals[:purchasers].boundary_type ==
            :unbound_oecd_bea_release_and_scope
        @test residuals[:basic].boundary_type ==
            :unbound_oecd_bea_release_and_scope
        @test residuals[:purchasers].balance_action ==
            :retain_unadjusted
        @test residuals[:basic].balance_action == :retain_unadjusted
        @test residuals[:purchasers].residual_hundredths_million_usd /
            100_000 ≈ 150.33035
        @test residuals[:basic].residual_hundredths_million_usd /
            100_000 ≈ 150.32881

        synthetic_oecd_values = Dict(
            :purchasers => 0,
            :basic => 0,
            :combined_margin => 51,
            :net_product_tax => 50,
            :gross_product_tax => 100,
            :subsidy_magnitude => 50,
        )
        synthetic_totals = Dict(
            component => SourceTotal(
                    "SYNTHETIC",
                    component,
                    value,
                    "A",
                    :published_total_cell_only,
                ) for (component, value) in synthetic_oecd_values
        )
        synthetic_bea = Dict(component => 0 for component in keys(synthetic_totals))
        synthetic_residuals =
            USOECDSourceAxisValuationDiagnostic.cross_source_residuals(
            synthetic_totals,
            synthetic_bea,
            synthetic_oecd_values,
            deepcopy(contract["cross_source_rounding_bounds"]),
        )
        synthetic_by_component = Dict(
            residual.component => residual for residual in synthetic_residuals
        )
        @test synthetic_by_component[:combined_margin].status ==
            :DUBIOUS_OUTSIDE_DERIVED_CROSS_SOURCE_ROUNDING_BOUND
        @test synthetic_by_component[:net_product_tax].status ==
            :PASS_AT_CROSS_SOURCE_ROUNDING
        @test synthetic_by_component[:gross_product_tax].status ==
            :PASS_AT_CROSS_SOURCE_ROUNDING

        malformed_bounds =
            deepcopy(contract["cross_source_rounding_bounds"])
        malformed_bounds["gross_product_tax"][
            "derived_rounding_bound_twice_hundredths_million_usd",
        ] = 200
        @test_throws ArgumentError USOECDSourceAxisValuationDiagnostic.cross_source_residuals(
            synthetic_totals,
            synthetic_bea,
            synthetic_oecd_values,
            malformed_bounds,
        )
        malformed_terms =
            deepcopy(contract["cross_source_rounding_bounds"])
        malformed_terms["gross_product_tax"]["bea_term_codes"] = ["TOP"]
        @test_throws ArgumentError USOECDSourceAxisValuationDiagnostic.cross_source_residuals(
            synthetic_totals,
            synthetic_bea,
            synthetic_oecd_values,
            malformed_terms,
        )
    end

    @testset "Observed-tax and zero-tax candidate isolation" begin
        @test length(report.tax_candidates) == 2
        observed, zero = report.tax_candidates
        @test observed.id == "oecd_usa_2024_observed_tax_source_axis"
        @test observed.tax_mode == :observed
        @test observed.dynamic_net_product_tax_total_hundredths_million_usd ==
            source_total(report, :net_product_tax)
        @test zero.id == "oecd_usa_2024_zero_tax_source_axis"
        @test zero.tax_mode == :zero
        @test zero.dynamic_net_product_tax_total_hundredths_million_usd == 0
        @test !ismutabletype(typeof(report.observed_sidecar))
        @test observed.observed_sidecar.fixture_cells_sha256 ==
            report.fixture_cells_sha256
        @test zero.observed_sidecar.fixture_cells_sha256 ==
            report.fixture_cells_sha256
        @test observed.observed_sidecar.net_product_tax_total_hundredths_million_usd ==
            zero.observed_sidecar.net_product_tax_total_hundredths_million_usd
        for candidate in report.tax_candidates
            @test !candidate.allocation_applied
            @test candidate.fiscal_receipt_status == :not_run_blocked
            @test candidate.margin_split_status == :not_run_blocked
            @test candidate.model_mapping_status == :not_run_blocked
            @test !candidate.model_state_write
            @test candidate.accounting_gate_effect == :none
            @test !candidate.forecast_origin_admissible
            @test candidate.forecast_score_effect == :none
        end
        @test observed.specification_sha256 ==
            "dd38a8a94dbcbe361b78dfcbd601131991c8d0562a774783797888088f28206d"
        @test zero.specification_sha256 ==
            "b63393185fe6287f27adcaab2f62c54415955718053af666011a404c902518da"
    end

    @testset "Adversarial fail-closed boundaries" begin
        margin_index = findfirst(
            cell ->
            cell.combined_margin.present &&
                additive_value(cell.combined_margin) != 0,
            report.cells,
        )
        @test margin_index !== nothing
        sign_reversal = copy(report.cells)
        margin_cell = sign_reversal[margin_index]
        sign_reversal[margin_index] = replace_component_value(
            margin_cell,
            :combined_margin,
            -additive_value(margin_cell.combined_margin),
        )
        @test_throws ArgumentError validate_source_axis_cells(sign_reversal)

        swap_indices = findall(
            cell ->
            cell.purchasers.present &&
                additive_value(cell.purchasers) != 0,
            report.cells,
        )[1:2]
        compensated_swap = copy(report.cells)
        first_index, second_index = swap_indices
        first_value =
            additive_value(compensated_swap[first_index].purchasers)
        second_value =
            additive_value(compensated_swap[second_index].purchasers)
        compensated_swap[first_index] = replace_component_value(
            compensated_swap[first_index],
            :purchasers,
            first_value + 100,
        )
        compensated_swap[second_index] = replace_component_value(
            compensated_swap[second_index],
            :purchasers,
            second_value - 100,
        )
        @test sum(
            additive_value(cell.purchasers) for
                cell in compensated_swap if cell.purchasers.present
        ) == sum(
            additive_value(cell.purchasers) for
                cell in report.cells if cell.purchasers.present
        )
        @test_throws ArgumentError validate_source_axis_cells(
            compensated_swap,
        )

        label_permutation = copy(report.cells)
        label_index = findfirst(
            cell ->
            cell.purchasers.present &&
                cell.basic.present &&
                additive_value(cell.purchasers) !=
                additive_value(cell.basic),
            label_permutation,
        )
        label_cell = label_permutation[label_index]
        purchasers_value = additive_value(label_cell.purchasers)
        basic_value = additive_value(label_cell.basic)
        permuted = replace_component_value(
            label_cell,
            :purchasers,
            basic_value,
        )
        permuted =
            replace_component_value(permuted, :basic, purchasers_value)
        label_permutation[label_index] = permuted
        @test_throws ArgumentError validate_source_axis_cells(
            label_permutation,
        )

        missing_index =
            findfirst(cell -> !cell.subsidy_magnitude.present, report.cells)
        missing_tax_evaluation =
            report.tax_identity_evaluations[missing_index]
        @test missing_tax_evaluation.status ==
            :NOT_EVALUABLE_SOURCE_MISSING
        @test ismissing(
            missing_tax_evaluation.residual_hundredths_million_usd,
        )
        @test :subsidy_magnitude in
            missing_tax_evaluation.missing_components
        missing_to_zero = copy(report.cells)
        missing_to_zero[missing_index] = replace_component_value(
            missing_to_zero[missing_index],
            :subsidy_magnitude,
            0,
        )
        @test_throws ArgumentError validate_source_axis_cells(
            missing_to_zero;
            enforce_approved_semantics_counts = true,
        )

        malformed_identity_fixture = mktempdir()
        malformed_identity_path =
            joinpath(malformed_identity_fixture, "identity_evaluations.csv")
        identity_lines = readlines(
            joinpath(
                OECD_FIXTURE_DIRECTORY,
                "identity_evaluations.csv",
            );
            keep = true,
        )
        source_missing_line = findfirst(
            line -> occursin("NOT_EVALUABLE_SOURCE_MISSING", line),
            identity_lines,
        )
        source_missing_fields = split(
            chomp(identity_lines[source_missing_line]),
            ',';
            keepempty = true,
        )
        source_missing_fields[4] = "0"
        identity_lines[source_missing_line] =
            join(source_missing_fields, ',') * "\n"
        write(malformed_identity_path, join(identity_lines))
        @test_throws ArgumentError USOECDSourceAxisValuationDiagnostic.load_identity_evaluations(
            malformed_identity_path,
        )

        used_absorption = copy(report.cells)
        original = used_absorption[1]
        used_absorption[1] = with_key(
            original,
            SourceAxisKey(
                original.key.transaction,
                original.key.activity,
                "Used",
                original.key.counterpart_area,
                original.key.sector,
                original.key.accounting_entry,
            ),
        )
        @test_throws ArgumentError validate_source_axis_cells(
            used_absorption,
        )

        @test_throws ArgumentError request_mapping_or_allocation(
            report,
            :proportional,
        )
        @test_throws ArgumentError request_mapping_or_allocation(
            report,
            :used_absorption,
        )
        @test_throws ArgumentError request_mapping_or_allocation(
            report,
            :other_absorption,
        )
        @test_throws ArgumentError request_mapping_or_allocation(
            report,
            :cpa08_isic4_to_bea,
        )

        candidate_records = deepcopy(contract["tax_candidates"])
        candidate_records[1][
            "dynamic_net_product_tax_total_hundredths_million_usd",
        ] += 1
        @test_throws ArgumentError validate_candidate_records(
            candidate_records,
        )
        duplicate_identifier = deepcopy(contract["tax_candidates"])
        duplicate_identifier[2]["id"] = duplicate_identifier[1]["id"]
        duplicate_identifier[2]["specification_sha256"] =
            candidate_specification_sha256(duplicate_identifier[2])
        @test_throws ArgumentError validate_candidate_records(
            duplicate_identifier,
        )

        permuted_fixture = copy_fixture(OECD_FIXTURE_DIRECTORY)
        cells_path = joinpath(permuted_fixture, "cells.csv")
        lines = readlines(cells_path; keep = true)
        lines[2], lines[3] = lines[3], lines[2]
        write(cells_path, join(lines))
        @test_throws ArgumentError load_oecd_source_axis_valuation_diagnostic(
            OECD_CONTRACT_PATH;
            fixture_directory = permuted_fixture,
        )
    end
end
