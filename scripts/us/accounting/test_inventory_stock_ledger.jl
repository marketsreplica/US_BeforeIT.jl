using CSV
using DataFrames
using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USInventoryStockLedger.jl"))
using .USInventoryStockLedger

const FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "inventory_stock_ledger_contract_v1")
const FIXTURE_SHA256 =
    "809501fd6d0c34ca9312936e762ed691575ea51c847999b8c33b5423a05a0936"
const MANIFEST_SHA256 =
    "60d011228150a9ce7f8ade01b4bf74c32de5ef103584c54f7ba6e6372c592af6"

sha256_hex(path) = bytes2hex(SHA.sha256(read(path)))

function copied_fixture(function_to_run)
    return mktempdir() do directory
        fixture = joinpath(directory, "fixture")
        cp(FIXTURE_DIRECTORY, fixture; force = true)
        function_to_run(fixture)
    end
end

function write_manifest(directory, manifest)
    open(joinpath(directory, "manifest.toml"), "w") do io
        TOML.print(io, manifest; sorted = true)
    end
    return nothing
end

function rehash_fixture!(directory, manifest)
    cells_path = joinpath(directory, "inventory_stock_ledger.csv")
    manifest["fixture_sha256"] = sha256_hex(cells_path)
    manifest["fixture_row_count"] =
        nrow(CSV.read(cells_path, DataFrame))
    write_manifest(directory, manifest)
    return nothing
end

function expect_manifest_semantic_rejection(mutator)
    manifest = TOML.parsefile(joinpath(FIXTURE_DIRECTORY, "manifest.toml"))
    mutator(manifest)
    cells_path = joinpath(FIXTURE_DIRECTORY, "inventory_stock_ledger.csv")
    @test_throws ArgumentError USInventoryStockLedger.validate_manifest(
        manifest,
        cells_path,
    )
    return nothing
end

function copy_observation(
        item;
        observation_id = item.observation_id,
        series_id = item.series_id,
        source_id = item.source_id,
        reference_period = item.reference_period,
        published_value = item.published_value,
        value_millions_current_usd = item.value_millions_current_usd,
        holder_basis = item.holder_basis,
        holder_code = item.holder_code,
        inventory_stage = item.inventory_stage,
        inventory_scope = item.inventory_scope,
        valuation_basis = item.valuation_basis,
        coverage_status = item.coverage_status,
    )
    return InventoryObservation(
        observation_id,
        series_id,
        source_id,
        reference_period,
        published_value,
        value_millions_current_usd,
        holder_basis,
        holder_code,
        inventory_stage,
        inventory_scope,
        valuation_basis,
        coverage_status,
    )
end

function replace_observations(ledger, observation_ids; kwargs...)
    observations = copy(ledger.observations)
    for observation_id in observation_ids
        index = ledger.observation_index[observation_id]
        observations[index] =
            copy_observation(observations[index]; kwargs...)
    end
    return observations
end

function ledger_with_observations(ledger, observations)
    observation_index =
        Dict(item.observation_id => index for (index, item) in pairs(observations))
    residuals = USInventoryStockLedger.build_identity_residuals(
        observations,
        ledger.manifest["identities"],
    )
    return InventoryStockLedger(
        observations,
        observation_index,
        residuals,
        ledger.covered_holder_codes,
        ledger.missing_values_policy,
        ledger.holder_to_commodity_bridge_applied,
        ledger.valuation_bridge_applied,
        ledger.stage_to_model_stock_scope_bridge_applied,
        ledger.sector_coverage_complete,
        ledger.model_state_reconciliation_applied,
        ledger.model_inventory_vector_emitted,
        ledger.forecast_origin_admissible,
        ledger.model_state_write_authorized,
        ledger.promotion_ready,
        ledger.promotion_blockers,
        ledger.manifest,
    )
end

@testset "Staged U.S. inventory-stock ledger checkpoint" begin
    @testset "Synthetic fixture is hermetic and stage-additive" begin
        fixture_path =
            joinpath(FIXTURE_DIRECTORY, "inventory_stock_ledger.csv")
        manifest_path = joinpath(FIXTURE_DIRECTORY, "manifest.toml")
        @test sha256_hex(fixture_path) == FIXTURE_SHA256
        @test sha256_hex(manifest_path) == MANIFEST_SHA256
        @test FIXTURE_MANIFEST_SHA256 == MANIFEST_SHA256

        ledger = load_inventory_stock_fixture(FIXTURE_DIRECTORY)
        @test length(ledger.observations) == 5
        @test stage_additivity_pass(ledger)
        @test only(identity_residuals(ledger)).residual == 0.0
        @test only(identity_residuals(ledger)).passed

        bea = observation(
            ledger,
            "bea_total_private_inventory_q1_2026",
        )
        @test bea.published_value == 4.0
        @test bea.value_millions_current_usd == 4_000.0
        @test bea.value_millions_current_usd !=
            bea.published_value * 1_000 / 4
        @test bea.reference_period == Date(2026, 3, 31)
        @test bea.inventory_stage == :total
        @test bea.holder_basis == :holder_industry
        @test bea.valuation_basis == :current_replacement_cost

        materials =
            observation(ledger, "m3_materials_q1_2026")
        work_in_process =
            observation(ledger, "m3_work_in_process_q1_2026")
        finished =
            observation(ledger, "m3_finished_goods_q1_2026")
        total =
            observation(ledger, "m3_total_inventory_q1_2026")
        @test materials.value_millions_current_usd == 40.0
        @test work_in_process.value_millions_current_usd == 25.0
        @test finished.value_millions_current_usd == 35.0
        @test total.value_millions_current_usd == 100.0
        @test total.value_millions_current_usd ==
            materials.value_millions_current_usd +
            work_in_process.value_millions_current_usd +
            finished.value_millions_current_usd
        @test all(
            item -> item.holder_code == "31-33",
            (materials, work_in_process, finished, total),
        )
        @test all(
            item -> item.valuation_basis == :non_lifo_cost,
            (materials, work_in_process, finished, total),
        )
        @test all(
            item ->
            item.source_id == "census_m3_contract" &&
                item.inventory_scope == "manufacturing" &&
                item.coverage_status == "PARTIAL_HOLDER_COVERAGE",
            (materials, work_in_process, finished, total),
        )
    end

    @testset "M3 identity terms cannot mix or relabel semantics" begin
        ledger = load_inventory_stock_fixture(FIXTURE_DIRECTORY)
        identities = ledger.manifest["identities"]
        finished_id = ["m3_finished_goods_q1_2026"]
        all_term_ids = [
            "m3_total_inventory_q1_2026",
            "m3_materials_q1_2026",
            "m3_work_in_process_q1_2026",
            "m3_finished_goods_q1_2026",
        ]

        single_term_mutations = [
            (; source_id = "bea_nipa_t50805b_contract"),
            (; valuation_basis = :current_replacement_cost),
            (; inventory_scope = "retail"),
            (; coverage_status = "AGGREGATE_CONTROL"),
        ]
        for mutation in single_term_mutations
            observations =
                replace_observations(ledger, finished_id; mutation...)
            @test_throws ArgumentError USInventoryStockLedger.build_identity_residuals(
                observations,
                identities,
            )
        end

        uniform_non_m3_mutations = [
            (; source_id = "bea_nipa_t50805b_contract"),
            (; holder_code = "44-45"),
            (; valuation_basis = :current_replacement_cost),
            (; inventory_scope = "retail"),
            (; coverage_status = "AGGREGATE_CONTROL"),
        ]
        for mutation in uniform_non_m3_mutations
            observations =
                replace_observations(ledger, all_term_ids; mutation...)
            @test_throws ArgumentError USInventoryStockLedger.build_identity_residuals(
                observations,
                identities,
            )
        end
    end

    @testset "Model and promotion boundary remains fail-closed" begin
        ledger = load_inventory_stock_fixture(FIXTURE_DIRECTORY)
        @test ledger.covered_holder_codes == ["31-33"]
        @test ledger.missing_values_policy == :missing_not_zero
        @test !ledger.holder_to_commodity_bridge_applied
        @test !ledger.valuation_bridge_applied
        @test !ledger.stage_to_model_stock_scope_bridge_applied
        @test !ledger.sector_coverage_complete
        @test !ledger.model_state_reconciliation_applied
        @test !ledger.model_inventory_vector_emitted
        @test !ledger.forecast_origin_admissible
        @test !ledger.model_state_write_authorized
        @test !ledger.promotion_ready
        @test ledger.promotion_blockers == PROMOTION_BLOCKERS
        @test stage_additivity_pass(ledger) && !ledger.promotion_ready
        @test !isdefined(USInventoryStockLedger, :source_controls_pass)
        @test_throws KeyError observation(ledger, "missing_model_sector")
        @test !isdefined(USInventoryStockLedger, :S_s)
        @test :S_s ∉ names(USInventoryStockLedger)
        @test ledger.manifest["accounting_gate_effect"] == "NONE"
        @test ledger.manifest["classification"] ==
            "SYNTHETIC_CONTRACT_FIXTURE_NOT_SOURCE_EVIDENCE"
    end

    @testset "Byte, schema, and row mutations are rejected or exposed" begin
        copied_fixture() do directory
            manifest_path = joinpath(directory, "manifest.toml")
            open(manifest_path, "a") do io
                write(io, "\n")
            end
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        copied_fixture() do directory
            cells_path =
                joinpath(directory, "inventory_stock_ledger.csv")
            open(cells_path, "a") do io
                write(io, "\n")
            end
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        copied_fixture() do directory
            cells_path =
                joinpath(directory, "inventory_stock_ledger.csv")
            frame = CSV.read(cells_path, DataFrame)
            rename!(frame, :published_value => :wrong_value)
            CSV.write(cells_path, frame)
            manifest = TOML.parsefile(joinpath(directory, "manifest.toml"))
            rehash_fixture!(directory, manifest)
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        copied_fixture() do directory
            cells_path =
                joinpath(directory, "inventory_stock_ledger.csv")
            frame = CSV.read(cells_path, DataFrame)
            frame.observation_id[2] = frame.observation_id[1]
            CSV.write(cells_path, frame)
            manifest = TOML.parsefile(joinpath(directory, "manifest.toml"))
            rehash_fixture!(directory, manifest)
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        copied_fixture() do directory
            cells_path =
                joinpath(directory, "inventory_stock_ledger.csv")
            frame = CSV.read(cells_path, DataFrame)
            frame.value_millions_current_usd[2] = -1.0
            CSV.write(cells_path, frame)
            manifest = TOML.parsefile(joinpath(directory, "manifest.toml"))
            rehash_fixture!(directory, manifest)
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        copied_fixture() do directory
            cells_path =
                joinpath(directory, "inventory_stock_ledger.csv")
            frame = CSV.read(cells_path, DataFrame)
            frame.reference_period[1] = Date(2026, 3, 30)
            CSV.write(cells_path, frame)
            manifest = TOML.parsefile(joinpath(directory, "manifest.toml"))
            rehash_fixture!(directory, manifest)
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        copied_fixture() do directory
            cells_path =
                joinpath(directory, "inventory_stock_ledger.csv")
            frame = CSV.read(cells_path, DataFrame)
            finished_row = only(
                findall(
                    ==("m3_finished_goods_q1_2026"),
                    frame.observation_id,
                ),
            )
            frame.published_value[finished_row] = 34.0
            frame.value_millions_current_usd[finished_row] = 34.0
            CSV.write(cells_path, frame)
            manifest = TOML.parsefile(joinpath(directory, "manifest.toml"))
            rehash_fixture!(directory, manifest)
            @test_throws ArgumentError load_inventory_stock_fixture(directory)
        end

        ledger = load_inventory_stock_fixture(FIXTURE_DIRECTORY)
        observations = replace_observations(
            ledger,
            ["m3_finished_goods_q1_2026"];
            published_value = 34.0,
            value_millions_current_usd = 34.0,
        )
        inconsistent_ledger = ledger_with_observations(ledger, observations)
        @test !stage_additivity_pass(inconsistent_ledger)
        @test only(identity_residuals(inconsistent_ledger)).residual == 1.0
        @test !inconsistent_ledger.promotion_ready
    end

    @testset "Stock, unit, basis, valuation, and coverage claims are frozen" begin
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["stock_flow_index_rate"] = "FLOW"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["annual_rate_flag"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["saar_divisor"] = 4.0
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["multiplier_to_millions"] = 250.0
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["period_semantics"] = "flow_over_period"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["economic_basis"] = "commodity"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][2]["valuation_basis"] = "sales_price"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["series"][1]["holder_basis"] = "commodity"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["series"][2]["inventory_stage"] = "MERCHANDISE"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["missing_values_policy"] = "ZERO_FILL"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["covered_holder_codes"] = String[]
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["covered_holder_codes"] = ["44-45"]
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["identities"][1]["tolerance_millions_usd"] = 1.0
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["raw_sha256"] = repeat("1", 64)
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["metadata_sha256"] = repeat("1", 64)
        end
    end

    @testset "Every promotion or model-write claim is rejected" begin
        expect_manifest_semantic_rejection() do manifest
            manifest["forecast_origin_admissible"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["model_state_write_authorized"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["accounting_gate_effect"] = "PASS"
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["holder_to_commodity_bridge_applied"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["valuation_bridge_applied"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["stage_to_model_stock_scope_bridge_applied"] =
                true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["sector_coverage_complete"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["model_state_reconciliation_applied"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["model_inventory_vector_emitted"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["production_promotion_ready"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["boundary"]["promotion_blockers"] =
                PROMOTION_BLOCKERS[2:end]
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["origin_admissible"] = true
        end
    end

    @testset "Manifest topology is exact" begin
        expect_manifest_semantic_rejection() do manifest
            manifest["unexpected"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            delete!(manifest, "classification")
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["sources"][1]["unexpected"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["series"][1]["unexpected"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["identities"][1]["unexpected"] = true
        end
        expect_manifest_semantic_rejection() do manifest
            manifest["series"][2]["source_id"] = "missing_source"
        end
        ledger = load_inventory_stock_fixture(FIXTURE_DIRECTORY)
        manifest = deepcopy(ledger.manifest)
        manifest["identities"][1]["rhs_observation_ids"] =
            ["missing", "also_missing", "still_missing"]
        @test_throws ArgumentError USInventoryStockLedger.build_identity_residuals(
            ledger.observations,
            manifest["identities"],
        )
    end
end
