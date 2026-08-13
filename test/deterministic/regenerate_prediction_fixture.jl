import BeforeIT as Bit

using Dates
using JLD2
using Test

get(ENV, "BEFOREIT_REGENERATE_FIXTURES", "false") == "true" ||
    error("set BEFOREIT_REGENERATE_FIXTURES=true to replace the deterministic fixture")

include("epsilon.jl")
include("make_model_deterministic.jl")

calibration = Bit.ITALY_CALIBRATION
calibration_date = DateTime(2010, 3, 31)
parameters, initial_conditions =
    Bit.get_params_and_initial_conditions(calibration, calibration_date; scale = 0.0001)

model = Bit.Model(parameters, initial_conditions)
models = Bit.ensemblerun!((deepcopy(model) for _ in 1:2), 12; parallel = false)
predictions = Bit.get_predictions_from_sims(
    Bit.DataVector(models),
    calibration.data,
    calibration_date,
)

output_path = isempty(ARGS) ? joinpath(@__DIR__, "2010Q1.jld2") : only(ARGS)
save(output_path, "model_dict", predictions)
println("wrote deterministic prediction fixture to $(abspath(output_path))")
