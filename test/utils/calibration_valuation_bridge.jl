import BeforeIT as Bit
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

    @testset "Commodity-balance inventory closure" begin
        diagnostics = Bit.commodity_balance_diagnostics(
            [10.0, 8.0],
            [2.0, 1.0],
            [13.0, 7.0],
        )
        @test diagnostics.inventory_statistical_discrepancy ==
            [-1.0, 2.0]
        @test all(iszero, diagnostics.residual)
        @test diagnostics.supply ==
            diagnostics.uses +
            diagnostics.inventory_statistical_discrepancy

        opening_inventory =
            Bit.opening_inventory_from_discrepancy(
            diagnostics.inventory_statistical_discrepancy,
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
end
