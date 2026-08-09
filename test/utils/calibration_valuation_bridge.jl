import BeforeIT as Bit
using Random
using Test

@testset "Calibration valuation bridge" begin
    figaro = Dict{String, Any}(
        "purchasers_to_basic_price" =>
            reshape([2.0, 0.5], 2, 1),
    )
    bridge = Bit.calibration_valuation_bridge(figaro, 1, 2)
    @test bridge == [2.0, 0.5]
    @test Bit.calibration_valuation_bridge(
        Dict{String, Any}(),
        1,
        2,
    ) === nothing
    @test_throws ErrorException Bit.calibration_valuation_bridge(
        Dict{String, Any}(
            "purchasers_to_basic_price" =>
                reshape([2.0, 0.0], 2, 1),
        ),
        1,
        2,
    )

    levels = [10.0, 30.0]
    bridged_levels =
        Bit.apply_valuation_bridge(levels, bridge, "test levels")
    @test sum(bridged_levels) ≈ sum(levels)
    @test bridged_levels ≈ [20.0, 15.0] .* (40.0 / 35.0)
    @test_throws ErrorException Bit.apply_valuation_bridge(
        [10.0, -1.0],
        bridge,
        "negative test levels",
    )

    uses = [1.0 2.0; 3.0 2.0]
    bridged_uses =
        Bit.apply_valuation_bridge(uses, bridge, "test uses")
    @test vec(sum(bridged_uses, dims = 1)) ≈
        vec(sum(uses, dims = 1))
    expected = uses .* reshape(bridge, :, 1)
    expected .*= reshape(
        vec(sum(uses, dims = 1)) ./
            vec(sum(expected, dims = 1)),
        1,
        :,
    )
    @test bridged_uses ≈ expected

    @testset "Opt-in net product-tax controls" begin
        intermediate_taxes = [0.25, -0.5]
        intermediate_controls = vec(sum(uses, dims = 1))
        net_intermediate_controls = Bit.net_product_tax_targets(
            intermediate_controls,
            intermediate_taxes,
            "intermediate test",
        )
        @test net_intermediate_controls ≈ [3.75, 4.5]
        net_uses = Bit.apply_valuation_bridge(
            uses,
            bridge,
            "net intermediate test";
            target_totals = net_intermediate_controls,
        )
        @test vec(sum(net_uses, dims = 1)) ≈
            net_intermediate_controls

        net_household_control =
            Bit.net_product_tax_targets(40.0, 4.0, "household test")
        net_household = Bit.apply_valuation_bridge(
            levels,
            bridge,
            "net household test";
            target_total = net_household_control,
        )
        @test sum(net_household) ≈ 36.0
        @test all(net_household .>= 0)

        # Without a target override, the legacy aggregate is unchanged.
        @test sum(Bit.apply_valuation_bridge(levels, bridge, "legacy")) ≈
            sum(levels)
        @test_throws ErrorException Bit.net_product_tax_targets(
            4.0,
            5.0,
            "negative target",
        )
        @test_throws ErrorException Bit.net_product_tax_targets(
            4.0,
            Inf,
            "nonfinite tax",
        )
        @test Bit.calibration_boolean_marker(
            Dict("use_product_tax_netting" => true),
            "use_product_tax_netting",
        )
        @test !Bit.calibration_boolean_marker(
            Dict{String, Any}(),
            "use_product_tax_netting",
        )
        @test_throws ErrorException Bit.calibration_boolean_marker(
            Dict("use_product_tax_netting" => 1),
            "use_product_tax_netting",
        )
    end

    @testset "Explicit commodity output keeps its economic basis" begin
        source_aware = Dict{String, Any}(
            "use_explicit_commodity_output" => true,
            "domestic_commodity_output_basic_price" =>
                reshape([10.0, 8.0], 2, 1),
            "commodity_output_codes" => ["A", "B"],
            "commodity_output_basis" =>
                "BEA_TABLE_262_T007_COMMODITY_BASIC_PRICE",
            "industry_output_codes" => ["A", "B"],
        )
        @test Bit.explicit_calibration_commodity_output(
            source_aware,
            1,
            2,
        ) == [10.0, 8.0]
        @test Bit.explicit_calibration_commodity_output(
            Dict{String, Any}(),
            1,
            2,
        ) === nothing

        bad_basis = deepcopy(source_aware)
        bad_basis["commodity_output_basis"] =
            "BEA_TABLE_259_T018_INDUSTRY_BASIC_PRICE"
        @test_throws ErrorException Bit.explicit_calibration_commodity_output(
            bad_basis,
            1,
            2,
        )
        duplicate_codes = deepcopy(source_aware)
        duplicate_codes["commodity_output_codes"] = ["A", "A"]
        @test_throws ErrorException Bit.explicit_calibration_commodity_output(
            duplicate_codes,
            1,
            2,
        )
        reordered_industries = deepcopy(source_aware)
        reordered_industries["industry_output_codes"] = ["B", "A"]
        @test_throws ErrorException Bit.explicit_calibration_commodity_output(
            reordered_industries,
            1,
            2,
        )
        negative_output = deepcopy(source_aware)
        negative_output["domestic_commodity_output_basic_price"] =
            reshape([10.0, -1.0], 2, 1)
        @test_throws ErrorException Bit.explicit_calibration_commodity_output(
            negative_output,
            1,
            2,
        )
        missing_codes = deepcopy(source_aware)
        delete!(missing_codes, "commodity_output_codes")
        @test_throws ErrorException Bit.explicit_calibration_commodity_output(
            missing_codes,
            1,
            2,
        )
        missing_industry_codes = deepcopy(source_aware)
        delete!(missing_industry_codes, "industry_output_codes")
        @test_throws ErrorException Bit.explicit_calibration_commodity_output(
            missing_industry_codes,
            1,
            2,
        )
    end

    @testset "Unreconciled commodity diagnostic and legacy inventory opt-in" begin
        diagnostics = Bit.commodity_balance_diagnostics(
            [10.0, 8.0],
            [2.0, 1.0],
            [13.0, 7.0],
        )
        @test diagnostics.unreconciled_gap == [-1.0, 2.0]
        @test diagnostics.domestic_commodity_output == [10.0, 8.0]
        @test diagnostics.closure_applied === false
        @test diagnostics.interpretation ===
            :unreconciled_commodity_measurement_gap
        @test !hasproperty(
            diagnostics,
            :inventory_statistical_discrepancy,
        )
        @test !hasproperty(diagnostics, :residual)
        @test diagnostics.supply - diagnostics.uses ==
            diagnostics.unreconciled_gap

        legacy_diagnostics =
            Bit.legacy_commodity_balance_diagnostics(
            [10.0, 8.0],
            [2.0, 1.0],
            [13.0, 7.0],
        )
        @test legacy_diagnostics.inventory_statistical_discrepancy ==
            diagnostics.unreconciled_gap
        @test all(iszero, legacy_diagnostics.residual)

        source_aware_initial_conditions = Dict{String, Any}()
        Bit.store_commodity_balance_diagnostics!(
            source_aware_initial_conditions,
            diagnostics;
            codes = ["A", "B"],
        )
        @test source_aware_initial_conditions[
            "unreconciled_commodity_gap_g",
        ] == [-1.0, 2.0]
        @test source_aware_initial_conditions[
            "commodity_balance_closure_applied",
        ] === false
        @test source_aware_initial_conditions["commodity_output_codes"] ==
            ["A", "B"]
        @test !haskey(source_aware_initial_conditions, "S_s")
        @test !haskey(
            source_aware_initial_conditions,
            "inventory_statistical_discrepancy_s",
        )

        legacy_initial_conditions = Dict{String, Any}()
        Bit.store_commodity_balance_diagnostics!(
            legacy_initial_conditions,
            diagnostics;
            initialize_inventory = true,
            timescale = 0.25,
        )
        @test legacy_initial_conditions["S_s"] == [0.25, 0.0]
        @test legacy_initial_conditions[
            "inventory_statistical_discrepancy_s",
        ] == [-1.0, 2.0]
        @test all(
            iszero,
            legacy_initial_conditions["commodity_balance_residual_s"],
        )

        opening_inventory =
            Bit.opening_inventory_from_discrepancy(
            diagnostics.unreconciled_gap,
            0.25,
        )
        @test opening_inventory == [0.25, 0.0]
        @test all(opening_inventory .>= 0)

        firm_inventory = Bit.allocate_sector_initial_inventories(
            [1.0, 3.0, 2.0],
            [1, 1, 2],
            [4.0, 2.0],
            2,
        )
        @test firm_inventory == [1.0, 3.0, 2.0]
        @test all(firm_inventory .>= 0)
        @test sum(firm_inventory[[1, 2]]) == 4.0
        @test firm_inventory[3] == 2.0
    end

    @testset "Optional firm inventory preserves legacy initialization" begin
        parameters = Bit.AUSTRIA2010Q1.parameters
        legacy_initial_conditions =
            Bit.AUSTRIA2010Q1.initial_conditions
        legacy_firms = Bit.Firms(parameters, legacy_initial_conditions)
        @test all(iszero, legacy_firms.S_i)

        inventory_initial_conditions =
            deepcopy(legacy_initial_conditions)
        inventory_initial_conditions["S_s"] =
            collect(1.0:Float64(parameters["G"]))
        inventory_firms =
            Bit.Firms(parameters, inventory_initial_conditions)
        for g in 1:Int(parameters["G"])
            @test sum(inventory_firms.S_i[inventory_firms.G_i .== g]) ≈
                inventory_initial_conditions["S_s"][g]
        end
        @test all(inventory_firms.S_i .>= 0)
    end

    @testset "Opening current-price macro controls" begin
        @test Bit.validated_opening_macro_controls(
            Dict{String, Any}(),
        ) === nothing
        @test Bit.validated_opening_macro_controls(
            Dict{String, Any}(
                "use_opening_macro_controls" => false,
            ),
        ) === nothing

        controls = Dict{String, Any}(
            "use_opening_macro_controls" => true,
            "opening_macro_control_source" => "synthetic_exact_fixture",
            "opening_macro_control_unit" =>
                Bit.OPENING_MACRO_CONTROL_UNIT,
            "opening_macro_control_absolute_tolerance" => 1.0e-10,
            "opening_nominal_gdp" => 100.0,
            "opening_nominal_household_consumption" => 60.0,
            "opening_nominal_government_consumption_and_investment" =>
                20.0,
            "opening_nominal_capitalformation" => 15.0,
            "opening_nominal_fixed_capitalformation" => 12.0,
            "opening_nominal_inventory_investment" => 3.0,
            "opening_nominal_fixed_capitalformation_dwellings" => 4.0,
            "opening_nominal_exports" => 10.0,
            "opening_nominal_imports" => 5.0,
        )
        validated =
            Bit.validated_opening_macro_controls(controls)
        @test validated.nominal_gdp == 100.0
        @test validated.nominal_inventory_investment == 3.0
        @test validated.expenditure_residual == 0.0
        @test validated.investment_residual == 0.0

        negative_inventory = deepcopy(controls)
        negative_inventory["opening_nominal_capitalformation"] = 10.0
        negative_inventory["opening_nominal_inventory_investment"] = -2.0
        negative_inventory["opening_nominal_gdp"] = 95.0
        @test Bit.validated_opening_macro_controls(
            negative_inventory,
        ).nominal_inventory_investment == -2.0

        missing_control = deepcopy(controls)
        delete!(missing_control, "opening_nominal_exports")
        @test_throws ArgumentError Bit.validated_opening_macro_controls(
            missing_control,
        )
        bad_gdp = deepcopy(controls)
        bad_gdp["opening_nominal_gdp"] = 101.0
        @test_throws ArgumentError Bit.validated_opening_macro_controls(
            bad_gdp,
        )
        bad_investment = deepcopy(controls)
        bad_investment["opening_nominal_inventory_investment"] = 4.0
        @test_throws ArgumentError Bit.validated_opening_macro_controls(
            bad_investment,
        )
        bad_dwellings = deepcopy(controls)
        bad_dwellings[
            "opening_nominal_fixed_capitalformation_dwellings",
        ] = 13.0
        @test_throws ArgumentError Bit.validated_opening_macro_controls(
            bad_dwellings,
        )
        bad_unit = deepcopy(controls)
        bad_unit["opening_macro_control_unit"] = "annual_saar"
        @test_throws ArgumentError Bit.validated_opening_macro_controls(
            bad_unit,
        )

        calibration_marker = Dict{String, Any}(
            "use_opening_macro_controls" => true,
            "opening_macro_control_source" => "synthetic_exact_fixture",
            "opening_macro_control_unit" =>
                Bit.OPENING_MACRO_CONTROL_UNIT,
            "opening_macro_control_absolute_tolerance" => 1.0e-10,
        )
        calibration_data = Dict{String, Any}(
            "nominal_gdp_quarterly" => [90.0, 100.0],
            "nominal_household_consumption_quarterly" => [54.0, 60.0],
            "nominal_government_consumption_and_investment_quarterly" =>
                [18.0, 20.0],
            "nominal_gross_private_domestic_investment_quarterly" =>
                [13.5, 15.0],
            "nominal_fixed_investment_quarterly" => [10.8, 12.0],
            "nominal_inventory_investment_quarterly" => [2.7, 3.0],
            "nominal_exports_quarterly" => [9.0, 10.0],
            "nominal_imports_quarterly" => [4.5, 5.0],
        )
        materialized = Bit.calibration_opening_macro_controls(
            calibration_marker,
            calibration_data,
            2,
            1 / 3,
        )
        @test materialized["opening_nominal_gdp"] == 100.0
        @test materialized[
            "opening_nominal_fixed_capitalformation_dwellings",
        ] == 4.0
        @test Bit.calibration_opening_macro_controls(
            Dict{String, Any}(),
            calibration_data,
            2,
            1 / 3,
        ) === nothing
        @test_throws ErrorException Bit.calibration_opening_macro_controls(
            calibration_marker,
            calibration_data,
            3,
            1 / 3,
        )

        anchored_initial_conditions =
            deepcopy(Bit.AUSTRIA2010Q1.initial_conditions)
        merge!(anchored_initial_conditions, controls)
        Random.seed!(20260806)
        anchored_model = Bit.Model(
            deepcopy(Bit.AUSTRIA2010Q1.parameters),
            anchored_initial_conditions,
        )
        @test anchored_model.data.nominal_gdp == [100.0]
        @test anchored_model.data.nominal_household_consumption == [60.0]
        @test anchored_model.data.nominal_government_consumption == [20.0]
        @test anchored_model.data.nominal_capitalformation == [15.0]
        @test anchored_model.data.nominal_fixed_capitalformation == [12.0]
        @test anchored_model.data.nominal_inventory_investment == [3.0]
        @test anchored_model.data.nominal_fixed_capitalformation_dwellings ==
            [4.0]
        @test anchored_model.data.nominal_exports == [10.0]
        @test anchored_model.data.nominal_imports == [5.0]
        @test anchored_model.prop.opening_nominal_inventory_investment == 3.0
        implied_opening =
            Bit.model_implied_opening_macro(anchored_model)
        @test implied_opening.nominal_gdp != 100.0
        @test abs(implied_opening.expenditure_residual) <= 1.0e-8
        @test only(
            Bit.get_accounting_residuals(
                anchored_model.data,
            ).gdp_and_expenditure,
        ) == 0.0
        Bit.run!(anchored_model, 1; parallel = false)
        @test anchored_model.data.nominal_inventory_investment ≈
            anchored_model.data.nominal_capitalformation -
            anchored_model.data.nominal_fixed_capitalformation
        @test maximum(
            abs,
            Bit.get_accounting_residuals(
                anchored_model.data,
            ).gdp_and_expenditure,
        ) <= 1.0e-8
    end
end
