using Dates
using JLD2

const AUSTRIA_BASELINE_FILES = Dict(
    :structural_2024Q4 => joinpath(
        dir,
        "data",
        "austria",
        "baselines",
        "AT_2024Q4_structural.jld2",
    ),
    :nowcast_2026Q1 => joinpath(
        dir,
        "data",
        "austria",
        "baselines",
        "AT_2026Q1_nowcast.jld2",
    ),
)

const AUSTRIA_CALIBRATION_FILES = Dict(
    :structural_2024Q4 => joinpath(
        dir,
        "data",
        "austria",
        "calibration",
        "AT_2024_calibration_object.jld2",
    ),
    :nowcast_2026Q1 => joinpath(
        dir,
        "data",
        "austria",
        "calibration",
        "AT_2026Q1_nowcast_object.jld2",
    ),
)

const AUSTRIA_SCENARIO_FILE = joinpath(
    dir,
    "data",
    "austria",
    "scenarios",
    "AT_2026_2031_annual.csv",
)

function normalize_austria_vintage(vintage)
    value = lowercase(replace(String(vintage), "-" => "", "_" => ""))
    if value in ("structural", "2024q4", "structural2024q4")
        return :structural_2024Q4
    elseif value in ("nowcast", "current", "2026q1", "nowcast2026q1")
        return :nowcast_2026Q1
    end
    throw(
        ArgumentError(
            "Unknown Austria vintage '$vintage'. Use 2024Q4/structural or 2026Q1/nowcast.",
        ),
    )
end

"""
    available_austria_baselines()

Return the installed Austrian structural and nowcast baseline vintages.
"""
available_austria_baselines() = sort!(collect(keys(AUSTRIA_BASELINE_FILES)))

"""
    load_austria_baseline(vintage=:nowcast)

Load a versioned Austrian parameter/initial-condition artifact. Accepted
aliases are `2024Q4`/`structural` and `2026Q1`/`nowcast`.
"""
function load_austria_baseline(vintage = :nowcast)
    normalized = normalize_austria_vintage(vintage)
    path = AUSTRIA_BASELINE_FILES[normalized]
    isfile(path) || error("Austria baseline artifact is not installed: $path")
    artifact = JLD2.load(path)
    return (
        parameters = artifact["parameters"],
        initial_conditions = artifact["initial_conditions"],
        metadata = artifact["metadata"],
        path = path,
    )
end

"""
    load_austria_calibration(vintage=:nowcast)

Load the calibration object behind a versioned Austrian baseline.
"""
function load_austria_calibration(vintage = :nowcast)
    normalized = normalize_austria_vintage(vintage)
    path = AUSTRIA_CALIBRATION_FILES[normalized]
    isfile(path) || error("Austria calibration artifact is not installed: $path")
    artifact = JLD2.load(path)
    return (
        calibration_object = artifact["calibration_object"],
        metadata = artifact["metadata"],
        path = path,
    )
end

"""
    load_austria_scenarios()

Load the annual baseline, upside, and downside assumptions for 2026-2031.
GDP and HICP entries are scenario anchors. Government consumption, exports,
and imports are the paths imposed by `build_austria_scenario_model`.
"""
function load_austria_scenarios()
    isfile(AUSTRIA_SCENARIO_FILE) ||
        error("Austria scenario assumptions are not installed: $AUSTRIA_SCENARIO_FILE")
    return CSV.read(AUSTRIA_SCENARIO_FILE, DataFrame)
end

@object struct AustriaScenarioModel(Model) <: AbstractModel end

@object mutable struct AustriaScenarioGovernment(Government) <: AbstractGovernment
    C_G_path::Vector{typeFloat}
end

@object mutable struct AustriaScenarioRestOfTheWorld(RestOfTheWorld) <:
    AbstractRestOfTheWorld
    C_E_path::Vector{typeFloat}
    Y_I_path::Vector{typeFloat}
end

function gov_expenditure(model::AustriaScenarioModel)
    government = model.gov
    index = min(model.agg.t, length(government.C_G_path))
    C_G = government.C_G_path[index]
    J = length(government.C_d_j)
    C_d_j =
        C_G ./ J .* ones(J) .* sum(model.prop.c_G_g .* model.agg.P_bar_g) .*
        (1 + model.agg.pi_e)
    return C_G, C_d_j
end

function rotw_import_export(model::AustriaScenarioModel)
    rotw = model.rotw
    index = min(model.agg.t, length(rotw.C_E_path))
    C_E = rotw.C_E_path[index]
    Y_I = rotw.Y_I_path[index]
    L = length(rotw.C_d_l)
    C_d_l =
        C_E ./ L .* ones(L) .* sum(model.prop.c_E_g .* model.agg.P_bar_g) .*
        (1 + model.agg.pi_e)
    Y_m = model.prop.c_I_g * Y_I
    P_m = model.agg.P_bar_g * (1 + model.agg.pi_e)
    return C_E, Y_I, C_d_l, Y_m, P_m
end

function quarterly_path(
        initial_value::Real,
        annual_assumptions::DataFrame,
        growth_column::Symbol,
        horizon::Integer,
    )
    growth_by_year = Dict(
        Int(row.year) => Float64(row[growth_column]) / 100
            for row in eachrow(annual_assumptions)
    )
    path = Vector{typeFloat}(undef, horizon)
    value = typeFloat(initial_value)
    for step in 1:horizon
        # The baseline date is 2026 Q1, so step 1 is 2026 Q2 and step 4
        # is 2027 Q1.
        forecast_year = 2026 + fld(step, 4)
        annual_growth = get(
            growth_by_year,
            forecast_year,
            growth_by_year[maximum(keys(growth_by_year))],
        )
        value *= (1 + annual_growth)^(1 / 4)
        path[step] = value
    end
    return path
end

"""
    build_austria_scenario_model(
        scenario=:baseline;
        horizon=23,
        baseline=:nowcast,
        parameters=nothing,
        initial_conditions=nothing,
    )

Create a model initialized at 2026 Q1 with deterministic real government
consumption, export-demand, and import-supply paths. A 23-quarter horizon runs
from 2026 Q2 through 2031 Q4. `parameters` and `initial_conditions` can be
supplied to apply validated overrides while retaining the selected scenario
paths.
"""
function build_austria_scenario_model(
        scenario = :baseline;
        horizon::Integer = 23,
        baseline = :nowcast,
        parameters = nothing,
        initial_conditions = nothing,
    )
    scenario_name = lowercase(String(scenario))
    scenario_name in ("baseline", "upside", "downside") ||
        throw(ArgumentError("scenario must be baseline, upside, or downside"))
    artifact = load_austria_baseline(baseline)
    model_parameters =
        parameters === nothing ? artifact.parameters : parameters
    model_initial_conditions =
        initial_conditions === nothing ?
        artifact.initial_conditions : initial_conditions
    assumptions = subset(
        load_austria_scenarios(),
        :scenario => ByRow(==(scenario_name)),
    )
    sort!(assumptions, :year)

    firms = Firms(model_parameters, model_initial_conditions)
    workers_active, workers_inactive =
        Workers(model_parameters, model_initial_conditions)
    central_bank = CentralBank(model_parameters, model_initial_conditions)
    bank = Bank(model_parameters, model_initial_conditions)
    aggregates = Aggregates(model_parameters, model_initial_conditions)
    properties = Properties(model_parameters, model_initial_conditions)
    data = Data()
    standard_government =
        Government(model_parameters, model_initial_conditions)
    standard_rotw =
        RestOfTheWorld(model_parameters, model_initial_conditions)

    government_path = quarterly_path(
        standard_government.C_G,
        assumptions,
        :government_consumption_growth,
        horizon,
    )
    export_path =
        quarterly_path(standard_rotw.C_E, assumptions, :exports_growth, horizon)
    import_path =
        quarterly_path(standard_rotw.Y_I, assumptions, :imports_growth, horizon)

    government =
        AustriaScenarioGovernment(fields(standard_government)..., government_path)
    rotw = AustriaScenarioRestOfTheWorld(
        fields(standard_rotw)...,
        export_path,
        import_path,
    )
    return AustriaScenarioModel(
        (
            workers_active,
            workers_inactive,
            firms,
            bank,
            central_bank,
            government,
            rotw,
            aggregates,
            properties,
            data,
        ),
    )
end

"""
    run_austria_scenario(
        scenario=:baseline;
        horizon=23,
        simulations=8,
        parallel=true,
    )

Run a conditional Austrian forecast from 2026 Q1 to 2031 Q4.
"""
function run_austria_scenario(
        scenario = :baseline;
        horizon::Integer = 23,
        simulations::Integer = 8,
        parallel::Bool = true,
    )
    model = build_austria_scenario_model(scenario; horizon)
    return ensemblerun(model, Int(horizon), Int(simulations); parallel)
end
