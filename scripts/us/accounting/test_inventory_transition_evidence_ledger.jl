using CSV
using DataFrames
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "UST10105Controls.jl"))
include(joinpath(@__DIR__, "USBEAInventoryStockDiagnostic.jl"))
include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
include(joinpath(@__DIR__, "USSymmetricSupplyUse.jl"))
include(joinpath(@__DIR__, "USRequirementsDiagnostics.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsCommonBasis.jl"))
include(joinpath(@__DIR__, "USAfterRedefinitionsModelCore.jl"))
include(joinpath(@__DIR__, "USInventoryStockLedger.jl"))
include(joinpath(@__DIR__, "USInventoryTransitionEvidenceLedger.jl"))

using .USInventoryTransitionEvidenceLedger

const INVENTORY_TRANSITION_CONTRACT_PATH =
    joinpath(@__DIR__, "inventory_transition_evidence_ledger.toml")
const INVENTORY_TRANSITION_CONTRACT_SHA256 =
    "a82f6dd0be400f323d9630c33efa567a985521734f3cac72d763ee3db9d9d3ea"
const F030_SOURCE_ID =
    "bea_after_redefinitions_producer_price_2024_f030"

file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

function rewrite_observation(
        item;
        record_id = item.record_id,
        source_id = item.source_id,
        evidence_role = item.evidence_role,
        source_record_key = item.source_record_key,
        description = item.description,
        reference_period = item.reference_period,
        stock_flow_class = item.stock_flow_class,
        frequency = item.frequency,
        time_basis = item.time_basis,
        price_basis = item.price_basis,
        valuation_basis = item.valuation_basis,
        published_rate_basis = item.published_rate_basis,
        economic_unit = item.economic_unit,
        holder_namespace = item.holder_namespace,
        holder_code = item.holder_code,
        commodity_namespace = item.commodity_namespace,
        commodity_code = item.commodity_code,
        stage_namespace = item.stage_namespace,
        stage_code = item.stage_code,
        value = item.value,
        cell_state = item.cell_state,
        source_manifest_sha256 = item.source_manifest_sha256,
        source_data_sha256 = item.source_data_sha256,
        upstream_source_sha256 = item.upstream_source_sha256,
        source_status = item.source_status,
        forecast_origin_admissible =
            item.forecast_origin_admissible,
    )
    return InventoryEvidenceObservation(
        item.schema_version,
        record_id,
        source_id,
        evidence_role,
        source_record_key,
        description,
        reference_period,
        stock_flow_class,
        frequency,
        time_basis,
        price_basis,
        valuation_basis,
        published_rate_basis,
        economic_unit,
        holder_namespace,
        holder_code,
        commodity_namespace,
        commodity_code,
        stage_namespace,
        stage_code,
        value,
        cell_state,
        source_manifest_sha256,
        source_data_sha256,
        upstream_source_sha256,
        source_status,
        forecast_origin_admissible,
    )
end

function rewrite_transition(
        item;
        status = item.status,
        diagnostic_value = item.diagnostic_value,
        absolute_diagnostic_value = item.absolute_diagnostic_value,
        tolerance = item.tolerance,
        mapping_applied = item.mapping_applied,
        model_output_emitted = item.model_output_emitted,
        forecast_origin_admissible =
            item.forecast_origin_admissible,
    )
    return InventoryTransitionAssessment(
        item.schema_version,
        item.transition_id,
        status,
        diagnostic_value,
        absolute_diagnostic_value,
        tolerance,
        item.blocker,
        item.required_evidence,
        item.basis,
        mapping_applied,
        model_output_emitted,
        forecast_origin_admissible,
    )
end

function observation_by_id(report, record_id)
    return only(
        item for item in report.observations if item.record_id == record_id
    )
end

function check_by_id(report, check_id)
    return only(item for item in report.checks if item.check_id == check_id)
end

@testset "Fail-closed U.S. inventory transition evidence ledger" begin
    contract = load_inventory_transition_contract(
        INVENTORY_TRANSITION_CONTRACT_PATH,
    )
    report = build_inventory_transition_evidence(contract)

    @testset "Hermetic contract and valuation boundary" begin
        @test file_sha256(INVENTORY_TRANSITION_CONTRACT_PATH) ==
            INVENTORY_TRANSITION_CONTRACT_SHA256
        @test APPROVED_CONTRACT_SHA256 ==
            INVENTORY_TRANSITION_CONTRACT_SHA256
        @test length(contract.artifacts) == 20
        @test Set(keys(contract.sources)) == Set(
            [
                "bea_nipa_t10105_cipi",
                "bea_nipa_t50805b_holder_stocks",
                F030_SOURCE_ID,
                "synthetic_inventory_stage_comparator",
            ],
        )
        @test all(
            item.sha256 == file_sha256(item.path)
                for item in values(contract.artifacts)
        )
        @test contract.implementation["module_hash_policy"] ==
            "SHA256_AFTER_REPLACING_SINGLE_APPROVED_CONTRACT_HASH_LITERAL_WITH_64_ZEROES"
        @test contract.implementation["module_normalized_sha256"] ==
            normalized_module_sha256(
            joinpath(
                @__DIR__,
                "USInventoryTransitionEvidenceLedger.jl",
            ),
        )
        @test contract.implementation["runner_sha256"] ==
            file_sha256(
            joinpath(
                @__DIR__,
                "run_inventory_transition_evidence_ledger.jl",
            ),
        )
        @test contract.classification ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test contract.promotion_status ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test occursin(
            "after-redefinitions producer-price",
            contract.scientific_role,
        )
        @test occursin(
            "Legacy Table 259 purchasers-price F030 is a different valuation/source boundary",
            contract.scientific_role,
        )
        @test contract.sources[F030_SOURCE_ID].price_basis ==
            "PRODUCERS_PRICES"
        @test all(
            !occursin("T259", item.source_id)
                for item in report.observations
        )
        @test !contract.forecast_origin_admissible
        @test !contract.promotion_ready
        @test !contract.model_inventory_vector_emitted
        @test !contract.s_s_emitted
        @test !contract.model_state_write
        @test contract.accounting_gate_effect == :none

        mktempdir() do directory
            changed = joinpath(directory, "changed.toml")
            write(
                changed,
                read(INVENTORY_TRANSITION_CONTRACT_PATH),
                UInt8('\n'),
            )
            @test_throws ArgumentError load_inventory_transition_contract(
                changed,
            )
            changed_module = joinpath(directory, "changed_module.jl")
            write(
                changed_module,
                read(
                    joinpath(
                        @__DIR__,
                        "USInventoryTransitionEvidenceLedger.jl",
                    ),
                ),
                codeunits("\n# provenance mutation\n"),
            )
            @test normalized_module_sha256(changed_module) !=
                contract.implementation["module_normalized_sha256"]
        end
    end

    @testset "T10105 is quarterized exactly once and remains signed" begin
        t10105 = filter(
            item -> item.source_id == "bea_nipa_t10105_cipi",
            report.observations,
        )
        @test length(t10105) == 119
        @test count(item -> item.value > 0, t10105) == 94
        @test count(item -> item.value < 0, t10105) == 25
        @test count(item -> iszero(item.value), t10105) == 0
        @test all(isinteger(4 * item.value) for item in t10105)
        @test all(
            item ->
            item.stock_flow_class == "FLOW" &&
                item.frequency == "QUARTERLY" &&
                item.published_rate_basis ==
                "SOURCE_SAAR_DIVIDED_BY_4_EXACTLY_ONCE_UPSTREAM",
            t10105,
        )
        @test observation_by_id(
            report,
            "t10105_cipi_2024-12-31",
        ).value == 4_447.25
        @test observation_by_id(
            report,
            "t10105_cipi_2026-03-31",
        ).value == -7_013.25
        @test report.summary.t10105_2024_total_millions == 53_546.0
        gpdi = check_by_id(
            report,
            "t10105_gpdi_identity_maximum_absolute_residual",
        )
        @test gpdi.status == "PASS_AT_SOURCE_ROUNDING"
        @test gpdi.diagnostic_value == 0.25
        @test gpdi.tolerance == 1.0

        divided_twice = deepcopy(report)
        for index in eachindex(divided_twice.observations)
            item = divided_twice.observations[index]
            item.source_id == "bea_nipa_t10105_cipi" || continue
            divided_twice.observations[index] =
                rewrite_observation(item; value = item.value / 4)
        end
        @test_throws ArgumentError validate_inventory_transition_evidence(
            divided_twice,
            contract,
        )

        not_divided = deepcopy(report)
        for index in eachindex(not_divided.observations)
            item = not_divided.observations[index]
            item.source_id == "bea_nipa_t10105_cipi" || continue
            not_divided.observations[index] =
                rewrite_observation(item; value = item.value * 4)
        end
        @test_throws ArgumentError validate_inventory_transition_evidence(
            not_divided,
            contract,
        )
    end

    @testset "T50805B holder stock and duplicate controls stay typed" begin
        stocks = filter(
            item ->
            item.source_id == "bea_nipa_t50805b_holder_stocks",
            report.observations,
        )
        @test length(stocks) == 24
        @test unique(getfield.(stocks, :reference_period)) == ["2026-03-31"]
        @test all(
            item ->
            item.stock_flow_class == "STOCK" &&
                item.time_basis == "END_OF_QUARTER_LEVEL" &&
                item.published_rate_basis == "LEVEL_NOT_ANNUAL_RATE",
            stocks,
        )
        primary =
            observation_by_id(report, "t50805b_stock_line_001")
        duplicate =
            observation_by_id(report, "t50805b_stock_line_016")
        @test primary.value == duplicate.value == 4_223_030.0
        @test primary.source_record_key == "line=1|series=A371RC"
        @test duplicate.source_record_key == "line=16|series=A371RC"
        @test primary.holder_code == "L001:A371RC"
        @test duplicate.holder_code == "L016:A371RC"
        @test report.summary.t50805b_private_total_millions ==
            4_223_030.0
        @test report.summary.t50805b_duplicate_total_millions ==
            4_223_030.0
        @test report.summary.t50805b_reference_period_count == 1
        @test_throws ArgumentError reject_stock_difference_equals_cipi(
            report,
        )

        @test all(
            item ->
            item.status == "NOT_RUN_BLOCKED" &&
                ismissing(item.diagnostic_value) &&
                ismissing(item.absolute_diagnostic_value) &&
                ismissing(item.tolerance),
            report.transitions,
        )
        invented_zero = deepcopy(report)
        transition = invented_zero.transitions[2]
        invented_zero.transitions[2] = rewrite_transition(
            transition;
            status = "PASS",
            diagnostic_value = 0.0,
            absolute_diagnostic_value = 0.0,
            tolerance = 0.0,
        )
        @test_throws ArgumentError validate_inventory_transition_evidence(
            invented_zero,
            contract,
        )
    end

    @testset "Annual producer-price F030 preserves signs and source zeros" begin
        f030 = filter(
            item -> item.source_id == F030_SOURCE_ID,
            report.observations,
        )
        core = filter(
            item ->
            item.commodity_namespace ==
                "BEA_IO_2024_CORE_COMMODITY",
            f030,
        )
        closure = filter(
            item ->
            item.commodity_namespace ==
                "BEA_IO_2024_CLOSURE_COMMODITY",
            f030,
        )
        @test length(core) == 68
        @test length(closure) == 2
        @test sum(getfield.(core, :value)) == 44_095.0
        @test sum(getfield.(closure, :value)) == 9_450.0
        @test sum(getfield.(f030, :value)) == 53_545.0
        @test count(item -> item.value < 0, core) == 7
        @test count(item -> item.value < 0, closure) == 0
        @test Dict(
            item.commodity_code => item.value
                for item in core if item.value < 0
        ) == Dict(
            "211" => -909.0,
            "212" => -432.0,
            "213" => -15.0,
            "311FT" => -448.0,
            "331" => -577.0,
            "486" => -1.0,
            "511" => -327.0,
        )
        @test all(
            item ->
            item.frequency == "ANNUAL" &&
                item.price_basis == "PRODUCERS_PRICES" &&
                item.published_rate_basis ==
                "ANNUAL_NOT_SAAR_NOT_DIVIDED_BY_4",
            f030,
        )
        used = only(item for item in closure if item.commodity_code == "Used")
        other =
            only(item for item in closure if item.commodity_code == "Other")
        @test used.value == 9_450.0
        @test used.cell_state == "SOURCE_EXPLICIT_NUMERIC"
        @test other.value == 0.0
        @test other.cell_state == "SOURCE_SELECTED_ZERO_NOT_SHOWN"
        @test count(
            item -> item.cell_state == "SOURCE_EXPLICIT_NUMERIC",
            f030,
        ) == 33
        @test count(
            item ->
            item.value == 0.0 &&
                item.cell_state == "SOURCE_SELECTED_ZERO_NOT_SHOWN",
            f030,
        ) == 37

        cells_to_control = check_by_id(
            report,
            "f030_core_plus_closure_to_published_column_control",
        )
        @test cells_to_control.status ==
            "PASS_AT_DERIVED_SOURCE_ROUNDING"
        @test cells_to_control.diagnostic_value == -1.0
        @test cells_to_control.tolerance == 37.0
        @test !cells_to_control.correction_applied
        @test report.summary.f030_published_column_control_millions ==
            53_546.0
        @test report.summary.f030_cell_minus_published_control_millions ==
            -1.0

        cross_source = check_by_id(
            report,
            "f030_published_control_minus_t10105_2024_aggregate",
        )
        @test cross_source.status ==
            "PASS_AT_DERIVED_SOURCE_ROUNDING"
        @test cross_source.diagnostic_value == 0.0
        @test cross_source.tolerance == 1.0
        @test !cross_source.correction_applied

        divided = deepcopy(report)
        for index in eachindex(divided.observations)
            item = divided.observations[index]
            item.source_id == F030_SOURCE_ID || continue
            divided.observations[index] =
                rewrite_observation(item; value = item.value / 4)
        end
        @test_throws ArgumentError validate_inventory_transition_evidence(
            divided,
            contract,
        )

        clipped = deepcopy(report)
        for index in eachindex(clipped.observations)
            item = clipped.observations[index]
            item.source_id == F030_SOURCE_ID && item.value < 0 || continue
            clipped.observations[index] =
                rewrite_observation(item; value = 0.0)
        end
        @test_throws ArgumentError validate_inventory_transition_evidence(
            clipped,
            contract,
        )
    end

    @testset "Namespaces, duplicates, and provenance fail closed" begin
        other_index = findfirst(
            item ->
            item.source_id == F030_SOURCE_ID &&
                item.commodity_code == "Other",
            report.observations,
        )
        collided = deepcopy(report)
        collided.observations[other_index] = rewrite_observation(
            collided.observations[other_index];
            commodity_namespace = "BEA_IO_2024_CORE_COMMODITY",
        )
        @test_throws ArgumentError validate_inventory_transition_evidence(
            collided,
            contract,
        )

        duplicated = deepcopy(report)
        duplicated.observations[2] = rewrite_observation(
            duplicated.observations[2];
            source_record_key =
                duplicated.observations[1].source_record_key,
        )
        @test_throws ArgumentError validate_inventory_transition_evidence(
            duplicated,
            contract,
        )

        absent_provenance = deepcopy(report)
        absent_provenance.observations[1] = rewrite_observation(
            absent_provenance.observations[1];
            source_manifest_sha256 = "",
        )
        @test_throws ArgumentError validate_inventory_transition_evidence(
            absent_provenance,
            contract,
        )

        t508_other_labels = filter(
            item ->
            item.source_id == "bea_nipa_t50805b_holder_stocks" &&
                occursin("Other", item.description),
            report.observations,
        )
        @test length(t508_other_labels) == 2
        @test all(isempty(item.commodity_code) for item in t508_other_labels)
        @test only(
            item for item in report.observations if
                item.commodity_code == "Other"
        ).commodity_namespace == "BEA_IO_2024_CLOSURE_COMMODITY"
    end

    @testset "Synthetic stages remain non-evidentiary and outputs stay zero" begin
        synthetic = filter(
            item ->
            item.source_id == "synthetic_inventory_stage_comparator",
            report.observations,
        )
        @test length(synthetic) == 5
        @test all(
            item ->
            item.evidence_role ==
                "SYNTHETIC_NON_EVIDENTIARY_COMPARATOR",
            synthetic,
        )
        @test all(
            item -> item.upstream_source_sha256 ==
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            synthetic,
        )
        @test all(
            item ->
            item.stage_namespace == "SYNTHETIC_INVENTORY_STAGE",
            synthetic,
        )
        synthetic_check = check_by_id(
            report,
            "synthetic_manufacturing_stage_additivity",
        )
        @test synthetic_check.status ==
            "PASS_NON_EVIDENTIARY_COMPARATOR"
        @test synthetic_check.diagnostic_value == 0.0
        @test !synthetic_check.forecast_origin_admissible

        @test report.summary.observation_count == 218
        @test report.summary.evidentiary_observation_count == 213
        @test report.summary.non_evidentiary_observation_count == 5
        @test report.summary.model_vector_output_count == 0
        @test report.summary.s_s_output_count == 0
        @test report.summary.state_write_count == 0
        @test report.summary.gate_effect_count == 0
        @test report.summary.origin_admissible_output_count == 0
        @test !report.model_inventory_vector_emitted
        @test !report.s_s_emitted
        @test !report.model_state_write
        @test !report.forecast_origin_admissible
        @test report.accounting_gate_effect == :none
        @test :S_s ∉ fieldnames(InventoryTransitionEvidenceReport)
        @test :model_inventory_vector ∉
            fieldnames(InventoryTransitionEvidenceReport)
    end

    @testset "Writer is byte-deterministic and retains structural missingness" begin
        mktempdir() do directory
            first_directory = joinpath(directory, "first")
            second_directory = joinpath(directory, "second")
            first_written = write_inventory_transition_evidence(
                report,
                contract,
                first_directory,
            )
            second_written = write_inventory_transition_evidence(
                report,
                contract,
                second_directory,
            )
            @test first_written.observation_count == 218
            @test first_written.source_check_count == 19
            @test first_written.blocked_transition_count == 8
            @test first_written.observations_sha256 ==
                second_written.observations_sha256
            @test first_written.checks_sha256 ==
                second_written.checks_sha256
            @test first_written.transitions_sha256 ==
                second_written.transitions_sha256
            @test first_written.manifest_sha256 ==
                second_written.manifest_sha256
            @test sort(readdir(first_directory)) ==
                sort(readdir(second_directory))
            for filename in readdir(first_directory)
                @test read(joinpath(first_directory, filename)) ==
                    read(joinpath(second_directory, filename))
            end

            transitions = CSV.read(
                joinpath(
                    first_directory,
                    "inventory_transition_assessments.csv",
                ),
                DataFrames.DataFrame,
            )
            @test all(ismissing, transitions.diagnostic_value)
            @test all(ismissing, transitions.absolute_diagnostic_value)
            @test all(ismissing, transitions.tolerance)
            @test all(==("NOT_RUN_BLOCKED"), transitions.status)

            manifest =
                TOML.parsefile(joinpath(first_directory, "manifest.toml"))
            @test manifest["cross_source_correction_applied"] === false
            @test manifest["forecast_origin_admissible"] === false
            @test manifest["model_inventory_vector_emitted"] === false
            @test manifest["s_s_emitted"] === false
            @test manifest["model_state_write"] === false
            @test manifest["accounting_gate_effect"] == "NONE"
            @test manifest["implementation"]["module_hash_policy"] ==
                "SHA256_AFTER_REPLACING_SINGLE_APPROVED_CONTRACT_HASH_LITERAL_WITH_64_ZEROES"
            @test manifest["implementation"]["module_normalized_sha256"] ==
                normalized_module_sha256(
                joinpath(
                    @__DIR__,
                    "USInventoryTransitionEvidenceLedger.jl",
                ),
            )
            @test manifest["implementation"]["module_sha256"] ==
                file_sha256(
                joinpath(
                    @__DIR__,
                    "USInventoryTransitionEvidenceLedger.jl",
                ),
            )
            @test manifest["implementation"]["runner_sha256"] ==
                file_sha256(
                joinpath(
                    @__DIR__,
                    "run_inventory_transition_evidence_ledger.jl",
                ),
            )
            @test manifest["summary"][
                "f030_cell_minus_published_control_millions",
            ] == -1.0
            @test_throws ArgumentError write_inventory_transition_evidence(
                report,
                contract,
                first_directory,
            )
        end
    end
end
