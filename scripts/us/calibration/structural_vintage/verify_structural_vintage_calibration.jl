# =====================================================================================
# Verification for a structural-vintage U.S. calibration artifact (stage-2b 2b-4).
#
#   julia --project=scripts/us scripts/us/calibration/structural_vintage/verify_structural_vintage_calibration.jl \
#       --artifact=data/us/calibration/US_2017_calibration_object_reconciled.jld2 --year=2017
#
# Loads the artifact through the existing loader convention
# (JLD2.load(path)["calibration_object"]), constructs parameters and initial
# conditions at the reference year's Q4 calibration date via
# Bit.get_params_and_initial_conditions at scale 1e-5, instantiates Bit.Model,
# steps it 4 quarters serially, and reports:
#   * whether any parameter / initial condition / simulated series is NaN/Inf,
#   * real and nominal GDP positivity over the simulated path,
#   * opening GDP levels for the record.
# Exit code 0 only if every check passes.
# =====================================================================================
using Dates
using JLD2
using Printf
using Random
import BeforeIT as Bit

function cli_option(name::AbstractString, default)
    prefix = "--" * name * "="
    for argument in ARGS
        startswith(argument, prefix) && return argument[(length(prefix) + 1):end]
    end
    return default
end

const ARTIFACT = abspath(String(cli_option("artifact", "")))
isempty(cli_option("artifact", "")) && error("Pass --artifact=<path to .jld2>")
isfile(ARTIFACT) || error("Artifact not found: $ARTIFACT")
const YEAR = parse(Int, String(cli_option("year", "")))
const SCALE = parse(Float64, String(cli_option("scale", "0.00001")))
const QUARTERS = parse(Int, String(cli_option("quarters", "4")))
const SEED = parse(Int, String(cli_option("seed", "20260817")))

all_finite(x::AbstractArray) = all(all_finite, x)
all_finite(x::Number) = isfinite(x)
all_finite(x) = true

function dict_nonfinite_keys(d)
    bad = String[]
    for (k, v) in d
        v isa AbstractArray && !isempty(v) && eltype(v) <: Number && !all_finite(v) && push!(bad, String(k))
        v isa Number && !isfinite(v) && push!(bad, String(k))
    end
    return bad
end

println("="^100)
println("STRUCTURAL VINTAGE VERIFICATION")
println("artifact : $ARTIFACT")
println("calibration date : $(Date(YEAR, 12, 31)) ($(YEAR)Q4)   scale : $SCALE   quarters : $QUARTERS   seed : $SEED")
println("="^100)

stored = JLD2.load(ARTIFACT)
haskey(stored, "calibration_object") || error("Artifact has no calibration_object key")
calibration_object = stored["calibration_object"]
metadata = get(stored, "metadata", Dict{String, Any}())
println("metadata structural_reference_year = $(get(metadata, "structural_reference_year", "?")); reconciled = $(haskey(metadata, "method"))")

calibration_date = DateTime(YEAR, 12, 31)
parameters, initial_conditions = Bit.get_params_and_initial_conditions(
    calibration_object, calibration_date;
    scale = SCALE,
    use_growth_rate_ar1 = false,
)

failures = String[]
bad_parameters = dict_nonfinite_keys(parameters)
isempty(bad_parameters) || push!(failures, "nonfinite parameters: $(join(bad_parameters, ", "))")
bad_initial = dict_nonfinite_keys(initial_conditions)
isempty(bad_initial) || push!(failures, "nonfinite initial conditions: $(join(bad_initial, ", "))")
println("parameters: $(length(parameters)) entries, nonfinite: $(isempty(bad_parameters) ? "none" : join(bad_parameters, ", "))")
println("initial conditions: $(length(initial_conditions)) entries, nonfinite: $(isempty(bad_initial) ? "none" : join(bad_initial, ", "))")
@printf("T_prime = %d ; G = %d\n", Int(parameters["T_prime"]), Int(parameters["G"]))

Random.seed!(SEED)
model = Bit.Model(parameters, initial_conditions)
println("model constructed: $(Int(model.prop.H_act)) active households, $(length(model.firms.Y_i)) firms, $(Int(model.prop.G)) sectors")
for _ in 1:QUARTERS
    Bit.step!(model; parallel = false)
    Bit.collect_data!(model)
end

real_gdp = collect(model.data.real_gdp)
nominal_gdp = collect(model.data.nominal_gdp)
gdp_deflator = nominal_gdp ./ real_gdp
println("\nsimulated series over $(QUARTERS) quarters (index 1 = opening $(YEAR)Q4 state):")
@printf("  real_gdp    : %s\n", join([@sprintf("%.4e", value) for value in real_gdp], "  "))
@printf("  nominal_gdp : %s\n", join([@sprintf("%.4e", value) for value in nominal_gdp], "  "))
@printf("  deflator    : %s\n", join([@sprintf("%.4f", value) for value in gdp_deflator], "  "))

all(isfinite, real_gdp) || push!(failures, "real_gdp contains NaN/Inf")
all(isfinite, nominal_gdp) || push!(failures, "nominal_gdp contains NaN/Inf")
all(isfinite, gdp_deflator) || push!(failures, "gdp_deflator contains NaN/Inf")
all(>(0.0), real_gdp) || push!(failures, "real_gdp not strictly positive")
all(>(0.0), nominal_gdp) || push!(failures, "nominal_gdp not strictly positive")
for field in propertynames(model.data)
    series = getproperty(model.data, field)
    series isa AbstractArray || continue
    isempty(series) && continue
    eltype(series) <: Number || continue
    all_finite(series) || push!(failures, "model.data.$field contains NaN/Inf")
end

println()
if isempty(failures)
    println("VERIFICATION PASSED: no NaN/Inf in parameters, initial conditions, or any collected series; GDP strictly positive over $(QUARTERS) simulated quarters.")
else
    println("VERIFICATION FAILED:")
    for failure in failures
        println("  - $failure")
    end
    exit(1)
end
