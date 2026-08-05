using Dates
using Random
using Test

@testset "Current Austria baselines" begin
    @test Set(Bit.available_austria_baselines()) ==
        Set((:structural_2024Q4, :nowcast_2026Q1))

    structural = Bit.load_austria_baseline(:structural)
    nowcast = Bit.load_austria_baseline("2026-Q1")
    @test structural.metadata["country"] == "AT"
    @test structural.metadata["period"] == "2024-Q4"
    @test structural.metadata["structural_reference_year"] == 2024
    @test nowcast.metadata["period"] == "2026-Q1"
    @test nowcast.metadata["structural_reference_year"] == 2024
    @test length(nowcast.metadata["live_source_records"]) == 18

    calibration = Bit.load_austria_calibration(:nowcast)
    @test calibration.calibration_object.max_calibration_date ==
        DateTime(2024, 12, 31)
    @test last(calibration.calibration_object.data["quarters_num"]) ==
        Bit.date2num(DateTime(2026, 3, 31))

    assumptions = Bit.load_austria_scenarios()
    @test size(assumptions) == (18, 12)
    @test Set(assumptions.scenario) == Set(("baseline", "upside", "downside"))
    @test all(
        scenario -> Set(
            assumptions.year[assumptions.scenario .== scenario],
        ) == Set(2026:2031),
        ("baseline", "upside", "downside"),
    )

    baseline_model =
        Bit.build_austria_scenario_model(:baseline; horizon = 23)
    upside_model = Bit.build_austria_scenario_model(:upside; horizon = 23)
    downside_model =
        Bit.build_austria_scenario_model(:downside; horizon = 23)
    @test length(baseline_model.gov.C_G_path) == 23
    @test length(baseline_model.rotw.C_E_path) == 23
    @test upside_model.gov.C_G_path[1] > baseline_model.gov.C_G_path[1]
    @test downside_model.gov.C_G_path[1] < baseline_model.gov.C_G_path[1]

    Random.seed!(20260729)
    Bit.run!(baseline_model, 1; parallel = false)
    central_bank_residual, commercial_bank_residual =
        Bit.get_accounting_identity_banks(baseline_model)
    @test all(isfinite, baseline_model.data.real_gdp)
    @test all(>(0), baseline_model.data.real_gdp)
    @test abs(central_bank_residual) <= 1.0e-6
    @test abs(commercial_bank_residual) <= 1.0e-6
end
