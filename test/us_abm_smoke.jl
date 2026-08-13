# Hermetic smoke test for the U.S. agent-based model.
#
# Builds the model from each committed U.S. calibration artifact and steps it a
# full year. It reads only files already in the repository, performs no network
# access, and runs at scale 1e-5 so the whole file costs a few seconds.
#
# What it protects:
#   * the shipped 2024 artifact still builds and simulates to finite, positive
#     real and nominal GDP;
#   * the commodity-balance reconciled artifact does the same, carries the
#     random-walk-with-drift expectation marker, and its opening commodity
#     balance actually clears;
#   * `expectation_rw_drift` stays default-off, which is what keeps the Austria
#     and Italy paths bit-identical to upstream.

using Test
using Dates
using JLD2
using Random

const US_SMOKE_SCALE = 1.0e-5
const US_SMOKE_ORIGIN = DateTime(2024, 12, 31)
const US_SMOKE_QUARTERS = 4
const US_SMOKE_SEED = 20260810

const US_SMOKE_ARTIFACTS = (
    baseline = joinpath(
        @__DIR__,
        "..",
        "data",
        "us",
        "calibration",
        "US_2024_calibration_object.jld2",
    ),
    reconciled = joinpath(
        @__DIR__,
        "..",
        "data",
        "us",
        "calibration",
        "US_2024_calibration_object_reconciled.jld2",
    ),
)

"""
    us_smoke_inputs(path; overrides)

Parameters and initial conditions at the 2024Q4 origin. `overrides` are merged
into a copy of the artifact's `figaro` block, so the artifact on disk is never
mutated and the stepped model never sees a diagnostic-only marker.
"""
function us_smoke_inputs(path; overrides = Dict{String, Any}())
    stored = JLD2.load(path)
    calibration_object = stored["calibration_object"]
    figaro = copy(calibration_object.figaro)
    merge!(figaro, overrides)
    calibration = copy(calibration_object.calibration)
    calibration["years_num"] = [Bit.date2num(US_SMOKE_ORIGIN)]
    object = Bit.CalibrationData(
        calibration,
        figaro,
        calibration_object.data,
        calibration_object.ea,
        US_SMOKE_ORIGIN,
        calibration_object.estimation_date,
    )
    return Bit.get_params_and_initial_conditions(
        object,
        US_SMOKE_ORIGIN;
        scale = US_SMOKE_SCALE,
        use_growth_rate_ar1 = false,
    )
end

"""
    us_smoke_simulate(parameters, initial_conditions)

Seed the global RNG, construct the model and step it serially. `Bit.Model`
draws the initial microstate from the global RNG, so the seed has to be set
immediately before construction.
"""
function us_smoke_simulate(parameters, initial_conditions)
    Random.seed!(US_SMOKE_SEED)
    model = Bit.Model(parameters, initial_conditions)
    for _ in 1:US_SMOKE_QUARTERS
        Bit.step!(model; parallel = false)
        Bit.collect_data!(model)
    end
    return model
end

"""
    us_smoke_commodity_gap(path)

The largest relative opening commodity-balance gap, `max |uses/supply - 1|`,
read off the library's own diagnostic. The two markers are set for this
derivation only; supply is `industry_output + measured imports`, which is the
row control the reconciliation was solved against.
"""
function us_smoke_commodity_gap(path)
    _, initial_conditions = us_smoke_inputs(
        path;
        overrides = Dict{String, Any}(
            "diagnose_commodity_balance" => true,
            "use_commodity_balance_inventory" => true,
        ),
    )
    supply = vec(initial_conditions["commodity_supply_g"])
    uses = vec(initial_conditions["modeled_commodity_uses_g"])
    return maximum(abs.(uses ./ supply .- 1))
end

@testset "U.S. ABM smoke test" begin
    if !all(isfile, values(US_SMOKE_ARTIFACTS))
        @info "U.S. calibration artifacts absent; skipping the ABM smoke test"
        @test true
    else
        @testset "shipped 2024 artifact" begin
            parameters, initial_conditions =
                us_smoke_inputs(US_SMOKE_ARTIFACTS.baseline)

            # Default-off: the flag is registered only when the artifact carries
            # the marker, which is what keeps Austria and Italy bit-identical.
            @test !haskey(parameters, "expectation_rw_drift")

            model = us_smoke_simulate(parameters, initial_conditions)
            @test model.prop.expectation_rw_drift == false

            @test length(model.data.real_gdp) == US_SMOKE_QUARTERS + 1
            @test length(model.data.nominal_gdp) == US_SMOKE_QUARTERS + 1
            @test all(isfinite, model.data.real_gdp)
            @test all(isfinite, model.data.nominal_gdp)
            @test all(>(0), model.data.real_gdp)
            @test all(>(0), model.data.nominal_gdp)
            # The deflator is derived, not collected: nominal / real.
            deflator = model.data.nominal_gdp ./ model.data.real_gdp
            @test all(isfinite, deflator)
            @test all(>(0), deflator)
        end

        @testset "commodity-balance reconciled artifact" begin
            parameters, initial_conditions =
                us_smoke_inputs(US_SMOKE_ARTIFACTS.reconciled)

            @test parameters["expectation_rw_drift"] == true

            model = us_smoke_simulate(parameters, initial_conditions)
            @test model.prop.expectation_rw_drift == true

            @test length(model.data.real_gdp) == US_SMOKE_QUARTERS + 1
            @test length(model.data.nominal_gdp) == US_SMOKE_QUARTERS + 1
            @test all(isfinite, model.data.real_gdp)
            @test all(isfinite, model.data.nominal_gdp)
            @test all(>(0), model.data.real_gdp)
            @test all(>(0), model.data.nominal_gdp)
            # The deflator is derived, not collected: nominal / real.
            deflator = model.data.nominal_gdp ./ model.data.real_gdp
            @test all(isfinite, deflator)
            @test all(>(0), deflator)
        end

        @testset "opening commodity balance" begin
            # The reconciled artifact re-derives to a clearing balance through
            # the unmodified pipeline; the shipped one does not, and that gap is
            # the defect the reconciliation exists to remove.
            @test us_smoke_commodity_gap(US_SMOKE_ARTIFACTS.reconciled) < 1.0e-6
            @test us_smoke_commodity_gap(US_SMOKE_ARTIFACTS.baseline) > 0.25
        end
    end
end
