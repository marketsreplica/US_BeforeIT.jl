using CSV
using DataFrames
using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USBEAInventoryStockDiagnostic.jl"))
using .USBEAInventoryStockDiagnostic

module T50805BAcquisitionUnderTest
    include(joinpath(@__DIR__, "acquire_bea_t50805b.jl"))
end

const FIXTURE_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_t50805b_2026q1_current_vintage_diagnostic",
)
const CELLS_SHA256 =
    "43ee3f1764c3505f1f752b8115206113dc14d145d412d6b232be7d1656b4d7f4"
const MANIFEST_SHA256 =
    "c1e7c6aa1469557844307478170c9d4820898a49e67c258da49c0c596cbab3f6"

sha256_hex(path) = bytes2hex(SHA.sha256(read(path)))

function fixture_frame()
    return CSV.read(
        joinpath(FIXTURE_DIRECTORY, "cells.csv"),
        DataFrame;
        stringtype = String,
    )
end

function copied_fixture(function_to_run)
    return mktempdir() do directory
        destination = joinpath(directory, "fixture")
        cp(FIXTURE_DIRECTORY, destination; force = true)
        function_to_run(destination)
    end
end

function expect_frame_rejection(mutator)
    frame = fixture_frame()
    mutator(frame)
    @test_throws ArgumentError USBEAInventoryStockDiagnostic.observations_from_frame(
        frame,
    )
    return nothing
end

function expect_manifest_rejection(mutator)
    manifest =
        TOML.parsefile(joinpath(FIXTURE_DIRECTORY, "manifest.toml"))
    mutator(manifest)
    @test_throws ArgumentError USBEAInventoryStockDiagnostic.validate_manifest(
        manifest,
        joinpath(FIXTURE_DIRECTORY, "cells.csv"),
    )
    return nothing
end

@testset "BEA NIPA T50805B current-vintage stock diagnostic" begin
    @testset "Acquisition redaction preserves wire-byte provenance" begin
        secret = "0123456789abcdefghijklmnopqrstuvwxyz"
        wire = Vector{UInt8}(
            codeunits(
                "{\"UserID\":\"$secret\",\"payload\":\"inventory\"}",
            ),
        )
        original = copy(wire)
        redacted =
            T50805BAcquisitionUnderTest.redact_user_id(wire, secret)
        @test wire == original
        @test length(wire) == length(original)
        @test !occursin(secret, String(copy(redacted)))
        @test occursin(
            "[REDACTED:BEA_API_KEY]",
            String(copy(redacted)),
        )
    end

    @testset "Fixture bytes and complete typed projection are pinned" begin
        cells_path = joinpath(FIXTURE_DIRECTORY, "cells.csv")
        manifest_path = joinpath(FIXTURE_DIRECTORY, "manifest.toml")
        @test sha256_hex(cells_path) == CELLS_SHA256
        @test sha256_hex(manifest_path) == MANIFEST_SHA256
        @test FIXTURE_MANIFEST_SHA256 == MANIFEST_SHA256

        fixture = load_bea_inventory_stock_fixture(FIXTURE_DIRECTORY)
        report = diagnose_bea_inventory_stocks(fixture)
        @test length(report.observations) == 29
        @test report.stock_line_numbers == collect(1:24)
        @test report.excluded_line_numbers == collect(25:29)
        @test count(
            item -> item.semantic == StockLevel,
            report.observations,
        ) == 24
        @test count(
            item -> item.semantic == ExcludedFinalSales,
            report.observations,
        ) == 2
        @test count(
            item -> item.semantic == ExcludedRatio,
            report.observations,
        ) == 3
        @test all(
            item -> item.reference_period == Date(2026, 3, 31),
            report.observations,
        )
        @test [item.line_number for item in report.observations] ==
            collect(1:29)
        @test all(
            item ->
            item.metric_name == "Current Dollars" &&
                item.cl_unit == "Level" &&
                item.unit_mult == 6 &&
                item.economic_unit == :millions_current_usd,
            report.observations[1:26],
        )
        @test all(
            item ->
            item.metric_name == "Current Dollar Ratios" &&
                item.cl_unit == "Level" &&
                item.unit_mult == 0 &&
                item.economic_unit == :ratio,
            report.observations[27:29],
        )
    end

    @testset "Stock values are end-of-quarter levels with no annual-rate division" begin
        report = diagnose_bea_inventory_stocks(
            load_bea_inventory_stock_fixture(FIXTURE_DIRECTORY),
        )
        primary = stock_observation(report, 1)
        duplicate = stock_observation(report, 16)
        wholesale = stock_observation(report, 7)
        duplicate_wholesale = stock_observation(report, 20)

        @test primary.series_code == "A371RC"
        @test primary.data_value == "4,223,030"
        @test stock_value_millions(primary) == 4_223_030.0
        @test report.private_inventory_total_millions == 4_223_030.0
        @test report.duplicate_private_inventory_total_millions ==
            4_223_030.0
        @test stock_value_millions(primary) ==
            stock_value_millions(duplicate)
        @test stock_value_millions(primary) != 4_223_030.0 / 4
        @test stock_value_millions(wholesale) ==
            stock_value_millions(duplicate_wholesale)
        @test sum(
            stock_value_millions(report.observations[line])
                for line in 1:24
        ) > report.private_inventory_total_millions
        @test report.stock_time_semantics == :end_of_quarter_level
        @test report.holder_basis == :published_holder_industry
        @test report.valuation_basis ==
            :current_dollars_at_respective_end_of_quarter_prices
        @test report.duplicate_rows_preserved
        @test !report.duplicate_rows_double_counted
        @test !report.annual_rate_division_applied
        @test !report.flow_conversion_applied

        @test_throws ArgumentError stock_observation(report, 25)
        @test_throws ArgumentError stock_observation(report, 27)
        @test_throws ArgumentError stock_value_millions(
            report.observations[25],
        )
        @test_throws ArgumentError stock_value_millions(
            report.observations[27],
        )
        @test_throws KeyError stock_observation(report, 30)
    end

    @testset "Published stock identities and inventory-sales ratios pass" begin
        report = diagnose_bea_inventory_stocks(
            load_bea_inventory_stock_fixture(FIXTURE_DIRECTORY),
        )
        @test length(report.identity_residuals) == 11
        @test published_identities_pass(report)
        @test Dict(
            residual.identity_id => residual.residual_millions
                for residual in report.identity_residuals
        ) == Dict(
            "primary_holder_partition" => -1.0,
            "manufacturing_durability" => 0.0,
            "wholesale_durability" => 1.0,
            "retail_detail" => 0.0,
            "private_total_duplicate" => 0.0,
            "private_total_durability" => 0.0,
            "farm_nonfarm_partition" => 0.0,
            "nonfarm_holder_partition" => -1.0,
            "wholesale_total_duplicate" => 0.0,
            "wholesale_merchant_partition" => 1.0,
            "merchant_wholesale_durability" => 0.0,
        )
        @test maximum(
            abs(residual.residual_millions)
                for residual in report.identity_residuals
        ) == 1.0
        @test all(
            residual ->
            abs(residual.residual_millions) <=
                residual.tolerance_millions,
            report.identity_residuals,
        )

        @test length(report.ratio_residuals) == 3
        @test published_ratios_pass(report)
        @test isapprox(
            report.ratio_residuals[1].calculated_ratio,
            4_223_030 / 1_869_524;
            atol = 0,
            rtol = 0,
        )
        @test [residual.published_ratio for residual in report.ratio_residuals] ==
            [2.26, 2.09, 3.85]
        @test maximum(
            abs(residual.residual)
                for residual in report.ratio_residuals
        ) < 0.005
        @test all(
            residual -> residual.tolerance == 0.005,
            report.ratio_residuals,
        )
    end

    @testset "Origin, state, gate, and promotion boundary is hard false" begin
        report = diagnose_bea_inventory_stocks(
            load_bea_inventory_stock_fixture(FIXTURE_DIRECTORY),
        )
        @test !report.holder_to_model_sector_mapping_applied
        @test !report.holder_to_commodity_bridge_applied
        @test !report.valuation_bridge_applied
        @test !report.inventory_stage_decomposition_applied
        @test !report.stage_to_model_stock_scope_bridge_applied
        @test !report.latent_state_reconciliation_applied
        @test !report.model_inventory_vector_emitted
        @test !report.forecast_origin_admissible
        @test report.accounting_gate_effect == :none
        @test !report.model_state_write_authorized
        @test !report.promotion_ready
        @test report.promotion_blockers == PROMOTION_BLOCKERS
        @test Set(report.promotion_blockers) == Set(
            [
                "CURRENT_VINTAGE_NOT_FIRST_RELEASE_ORIGIN_EVIDENCE",
                "NO_HOLDER_TO_MODEL_SECTOR_MAPPING",
                "NO_HOLDER_TO_COMMODITY_BRIDGE",
                "NO_END_OF_QUARTER_PRICE_TO_MODEL_VALUATION_BRIDGE",
                "NO_INVENTORY_STAGE_DECOMPOSITION",
                "NO_STAGE_TO_MODEL_STOCK_SCOPE_BRIDGE",
                "NO_LATENT_STATE_RECONCILIATION",
            ],
        )
        @test !isdefined(USBEAInventoryStockDiagnostic, :S_s)
        @test :S_s ∉ names(USBEAInventoryStockDiagnostic)

        manifest = report.manifest
        @test manifest["classification"] ==
            "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
        @test manifest["accounting_gate_effect"] == "NONE"
        @test manifest["stock_time_semantics"] ==
            "END_OF_QUARTER_LEVEL_NOT_AN_ANNUAL_RATE"
        @test manifest["duplicate_policy"] ==
            "PRESERVE_PUBLISHED_DUPLICATES; ADDRESS_BY_LINE; NEVER_SUM_ALL_STOCK_ROWS"
        @test manifest["source_metadata_sha256"] ==
            "8c06cc9ff25b0c13af8bd40cf594b6b6b1073a97ffd4cf344f76365f1cf0bb97"
        @test manifest["source_byte_count"] == 44_627
        @test manifest["source_wire_byte_count"] == 44_641
        @test !manifest["wire_payload_archived"]
        @test !manifest["annual_rate_division_applied"]
        @test !manifest["flow_conversion_applied"]
        @test !manifest["model_inventory_vector_emitted"]
        @test !manifest["forecast_origin_admissible"]
        @test !manifest["model_state_write_authorized"]
        @test !manifest["promotion_ready"]
    end

    @testset "Byte and row mutations fail closed" begin
        copied_fixture() do directory
            open(joinpath(directory, "manifest.toml"), "a") do io
                write(io, "\n")
            end
            @test_throws ArgumentError load_bea_inventory_stock_fixture(
                directory,
            )
        end
        copied_fixture() do directory
            open(joinpath(directory, "cells.csv"), "a") do io
                write(io, "\n")
            end
            @test_throws ArgumentError load_bea_inventory_stock_fixture(
                directory,
            )
        end

        expect_frame_rejection() do frame
            rename!(frame, :series_code => :wrong_series)
        end
        expect_frame_rejection() do frame
            frame.line_number[2] = 1
        end
        expect_frame_rejection() do frame
            sort!(frame, :line_number; rev = true)
        end
        expect_frame_rejection() do frame
            frame.time_period[1] = "2026Q2"
        end
        expect_frame_rejection() do frame
            frame.series_code[1] = "WRONG"
        end
        expect_frame_rejection() do frame
            frame.line_description[1] = "Inventories"
        end
        expect_frame_rejection() do frame
            frame.metric_name[1] = "Current Dollar Ratios"
        end
        expect_frame_rejection() do frame
            frame.cl_unit[1] = "Rate"
        end
        expect_frame_rejection() do frame
            frame.unit_mult[1] = 0
        end
        expect_frame_rejection() do frame
            frame.data_value[1] = "4,223,031"
        end
        expect_frame_rejection() do frame
            frame.numeric_value[1] = 0.0
            frame.data_value[1] = "0"
        end
        expect_frame_rejection() do frame
            frame.economic_unit[1] = "ratio"
        end
        expect_frame_rejection() do frame
            frame.note_ref[1] = "T50805B"
        end
        expect_frame_rejection() do frame
            frame.row_semantic[25] = "STOCK_LEVEL"
        end
        expect_frame_rejection() do frame
            frame.counting_role[16] = "PRIMARY_HOLDER_TOTAL"
        end
    end

    @testset "Manifest and arithmetic adversaries cannot promote the data" begin
        for key in (
                "annual_rate_division_applied",
                "flow_conversion_applied",
                "duplicate_rows_double_counted",
                "holder_to_model_sector_mapping_applied",
                "holder_to_commodity_bridge_applied",
                "valuation_bridge_applied",
                "inventory_stage_decomposition_applied",
                "stage_to_model_stock_scope_bridge_applied",
                "latent_state_reconciliation_applied",
                "model_inventory_vector_emitted",
                "forecast_origin_admissible",
                "model_state_write_authorized",
                "promotion_ready",
            )
            expect_manifest_rejection() do manifest
                manifest[key] = true
            end
        end
        expect_manifest_rejection() do manifest
            manifest["accounting_gate_effect"] = "PASS"
        end
        expect_manifest_rejection() do manifest
            manifest["source_wire_byte_count"] = 0
        end
        expect_manifest_rejection() do manifest
            manifest["wire_payload_archived"] = true
        end
        expect_manifest_rejection() do manifest
            manifest["classification"] = "APPROVED_ORIGIN"
        end
        expect_manifest_rejection() do manifest
            manifest["stock_line_numbers"] = collect(1:29)
        end
        expect_manifest_rejection() do manifest
            manifest["excluded_line_numbers"] = Int[]
        end
        expect_manifest_rejection() do manifest
            manifest["duplicate_rows_preserved"] = false
        end
        expect_manifest_rejection() do manifest
            manifest["promotion_blockers"] = String[]
        end
        expect_manifest_rejection() do manifest
            manifest["valuation_basis"] = "MODEL_VALUATION"
        end
        expect_manifest_rejection() do manifest
            manifest["fixture_sha256"] = repeat("0", 64)
        end

        frame = fixture_frame()
        frame.numeric_value[2] += 100.0
        frame.data_value[2] = "310,229"
        observations =
            USBEAInventoryStockDiagnostic.observations_from_frame(frame)
        index = Dict(
            item.line_number => position
                for (position, item) in pairs(observations)
        )
        residuals =
            USBEAInventoryStockDiagnostic.build_identity_residuals(
            observations,
            index,
        )
        @test !all(item.passed for item in residuals)
        @test only(
            item
                for item in residuals
                if item.identity_id == "primary_holder_partition"
        ).residual_millions == -101.0

        ratio_frame = fixture_frame()
        ratio_frame.numeric_value[27] = 3.0
        ratio_frame.data_value[27] = "3.0"
        ratio_observations =
            USBEAInventoryStockDiagnostic.observations_from_frame(
            ratio_frame,
        )
        ratio_index = Dict(
            item.line_number => position
                for (position, item) in pairs(ratio_observations)
        )
        ratio_residuals =
            USBEAInventoryStockDiagnostic.build_ratio_residuals(
            ratio_observations,
            ratio_index,
        )
        @test !all(item.passed for item in ratio_residuals)
        @test first(ratio_residuals).residual > 0.7
    end
end
