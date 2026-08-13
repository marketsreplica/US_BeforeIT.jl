module USPortableAccountingSemantics

using LinearAlgebra
using Random
using SHA

import BeforeIT as Bit

include(joinpath(@__DIR__, "build_opening_accounting_candidate.jl"))
using .USOpeningAccountingCandidate

export PortableConstructionSummary,
    PortableSemanticReport,
    PortableTransitionSummary,
    SemanticInvariantMismatch,
    run_portable_semantic_validation,
    validate_portable_candidate

const MODEL_TOLERANCE = 1.0e-6
const SOURCE_TOLERANCE = 1.0
const DOMAIN_TOLERANCE = 1.0e-10
const TRANSITION_HORIZON = 12
const AGENT_STATE_FIELDS = (
    :w_act,
    :w_inact,
    :firms,
    :bank,
    :cb,
    :gov,
    :rotw,
    :agg,
    :prop,
    :data,
)
const CRITICAL_FIRM_VECTOR_FIELDS =
    (:S_i, :M_i, :DS_i, :DM_i, :Y_i, :beta_i)
const PRICE_FIELDS = (
    (:firms, :P_i),
    (:firms, :P_bar_i),
    (:firms, :P_CF_i),
    (:rotw, :P_m),
    (:rotw, :P_l),
    (:gov, :P_j),
    (:agg, :P_bar),
    (:agg, :P_bar_g),
    (:agg, :P_bar_HH),
    (:agg, :P_bar_CF),
    (:agg, :P_bar_h),
    (:agg, :P_bar_CF_h),
)

struct SemanticInvariantMismatch <: Exception
    phase::String
    mismatches::Vector{String}
end

function Base.showerror(io::IO, error::SemanticInvariantMismatch)
    return print(
        io,
        "portable semantic invariant mismatch in ",
        error.phase,
        ": ",
        join(error.mismatches, "; "),
    )
end

struct PortableConstructionSummary
    candidate_id::String
    canonical_execution_envelope_match::Bool
    execution_envelope_mismatches::Vector{String}
    observed_expenditure_residual::Float64
    latent_expenditure_residual::Float64
    maximum_simulated_nominal_residual::Float64
    maximum_simulated_real_residual::Float64
    maximum_simulated_income_residual::Float64
    origin_admissible::Bool
    promotion_eligible::Bool
end

struct PortableTransitionSummary
    candidate_id::String
    seed::Int
    horizon::Int
    maximum_nominal_transition_residual::Float64
    maximum_real_transition_residual::Float64
    maximum_income_residual::Float64
    maximum_central_bank_residual::Float64
    maximum_commercial_bank_residual::Float64
    maximum_final_inventory_stock_flow_residual::Float64
    maximum_intermediate_inventory_stock_flow_residual::Float64
    minimum_price::Float64
    minimum_final_inventory::Float64
    minimum_intermediate_inventory::Float64
    nonfinite_value_count::Int
    origin_admissible::Bool
    promotion_eligible::Bool
end

struct PortableSemanticReport
    construction::Vector{PortableConstructionSummary}
    transitions::Vector{PortableTransitionSummary}
    runtime_source_tree_sha256::String
    runtime_source_tree_file_count::Int
    actual_execution_envelope::Dict{String, Any}
    canonical_execution_envelope_match::Bool
    execution_envelope_mismatches::Vector{String}
    byte_identity_asserted::Bool
    origin_admissible::Bool
    promotion_eligible::Bool
    accuracy_selection_eligible::Bool
    runtime_selection_eligible::Bool
end

function invariant(condition, mismatches, message)
    condition || push!(mismatches, String(message))
    return condition
end

function dictionary_field(result, name, mismatches)
    if !hasproperty(result, name)
        push!(mismatches, "result.$name is missing")
        return nothing
    end
    value = getproperty(result, name)
    invariant(
        value isa Dict{String, Any},
        mismatches,
        "result.$name must be Dict{String, Any}, got $(typeof(value))",
    )
    return value
end

function validate_portable_candidate(result)
    mismatches = String[]
    parameters = dictionary_field(result, :parameters, mismatches)
    initial_conditions =
        dictionary_field(result, :initial_conditions, mismatches)
    metadata = dictionary_field(result, :metadata, mismatches)
    if parameters !== nothing
        invariant(
            get(parameters, "use_commodity_balance_inventory", nothing) ===
                false,
            mismatches,
            "parameters.use_commodity_balance_inventory must be Bool false",
        )
    end
    if initial_conditions !== nothing
        invariant(
            get(
                initial_conditions,
                "commodity_balance_closure_applied",
                nothing,
            ) === false,
            mismatches,
            "initial_conditions.commodity_balance_closure_applied must be Bool false",
        )
        invariant(
            isempty(
                intersect(
                    Set(keys(initial_conditions)),
                    USOpeningAccountingCandidate.REJECTED_INVENTORY_ALIAS_KEYS,
                ),
            ),
            mismatches,
            "initial_conditions contain rejected inventory aliases",
        )
    end
    if metadata !== nothing
        invariant(
            get(metadata, "forecast_origin_admissible", nothing) === false,
            mismatches,
            "metadata.forecast_origin_admissible must be Bool false",
        )
        environment = get(metadata, "build_environment", nothing)
        invariant(
            environment isa Dict{String, Any},
            mismatches,
            "metadata.build_environment must be Dict{String, Any}, got $(typeof(environment))",
        )
        if environment isa Dict{String, Any}
            invariant(
                get(environment, "execution_validation_mode", "") ==
                    string(PORTABLE_SEMANTIC_BUILD),
                mismatches,
                "build environment must use PORTABLE_SEMANTIC_BUILD",
            )
            invariant(
                get(environment, "byte_identity_eligible", nothing) ===
                    false,
                mismatches,
                "portable construction must not be byte-identity eligible",
            )
            invariant(
                get(
                    environment,
                    "cross_machine_byte_determinism_claimed",
                    nothing,
                ) === false,
                mismatches,
                "portable construction must not claim cross-machine byte determinism",
            )
        end
        gates = get(metadata, "gate_split", nothing)
        invariant(
            gates isa Dict{String, Any},
            mismatches,
            "metadata.gate_split must be Dict{String, Any}, got $(typeof(gates))",
        )
        if gates isa Dict{String, Any}
            invariant(
                get(gates, "opening_macro_control_identity", "") ==
                    "PASS_AT_SOURCE_ROUNDING",
                mismatches,
                "opening observation gate must pass only at source rounding",
            )
            for gate in (
                    "latent_state_reconciliation",
                    "structural_supply_use",
                    "overall_accounting_promotion",
                    "forecast_promotion",
                )
                invariant(
                    get(gates, gate, "") == "FAIL",
                    mismatches,
                    "$gate must remain FAIL",
                )
            end
        end
    end
    isempty(mismatches) ||
        throw(SemanticInvariantMismatch("candidate construction", mismatches))
    try
        USOpeningAccountingCandidate.validate_candidate(result)
    catch error
        throw(
            SemanticInvariantMismatch(
                "candidate construction",
                ["candidate validator raised $(typeof(error)): $(sprint(showerror, error))"],
            ),
        )
    end
    return result
end

function numeric_values!(destination::Vector{Float64}, value, location)
    if value isa Bool
        push!(destination, value ? 1.0 : 0.0)
    elseif value isa Real
        push!(destination, Float64(value))
    elseif value isa Base.RefValue
        numeric_values!(destination, value[], location)
    elseif value isa AbstractDict
        for (key, entry) in pairs(value)
            numeric_values!(destination, entry, "$location.$key")
        end
    elseif value isa AbstractArray
        for entry in value
            numeric_values!(destination, entry, location)
        end
    else
        throw(
            SemanticInvariantMismatch(
                "transition type coverage",
                ["$location has unsupported numeric state type $(typeof(value))"],
            ),
        )
    end
    return destination
end

function model_numeric_values(model)
    values = Float64[]
    for object_name in AGENT_STATE_FIELDS[1:(end - 1)]
        object = getproperty(model, object_name)
        for field_name in fieldnames(typeof(object))
            numeric_values!(
                values,
                getfield(object, field_name),
                "$object_name.$field_name",
            )
        end
    end
    for field_name in fieldnames(typeof(model.data))
        numeric_values!(
            values,
            getfield(model.data, field_name),
            "data.$field_name",
        )
    end
    return values
end

function price_values(model)
    values = Float64[]
    for (object_name, field_name) in PRICE_FIELDS
        numeric_values!(
            values,
            getproperty(getproperty(model, object_name), field_name),
            "$object_name.$field_name",
        )
    end
    return values
end

function validate_model_types(model, candidate_id, seed)
    mismatches = String[]
    invariant(
        fieldnames(typeof(model)) == AGENT_STATE_FIELDS,
        mismatches,
        "$candidate_id seed $seed model fields changed: " *
            repr(fieldnames(typeof(model))),
    )
    for field_name in CRITICAL_FIRM_VECTOR_FIELDS
        value = getproperty(model.firms, field_name)
        invariant(
            value isa Vector{Float64},
            mismatches,
            "$candidate_id seed $seed firms.$field_name must be Vector{Float64}, got $(typeof(value))",
        )
        invariant(
            !isempty(value),
            mismatches,
            "$candidate_id seed $seed firms.$field_name must be nonempty",
        )
    end
    collection_time = model.data.collection_time
    invariant(
        collection_time isa AbstractVector{<:Integer},
        mismatches,
        "$candidate_id seed $seed data.collection_time must be an integer vector, got $(typeof(collection_time))",
    )
    isempty(mismatches) ||
        throw(SemanticInvariantMismatch("transition type coverage", mismatches))
    return model
end

function construction_summary(result)
    validate_portable_candidate(result)
    metadata = result.metadata
    environment = metadata["build_environment"]
    reconciliation = metadata["opening_macro_reconciliation"]
    simulation = metadata["simulated_accounting"]
    observed = Float64(reconciliation["observed_expenditure_residual"])
    latent = Float64(reconciliation["model_implied_expenditure_residual"])
    mismatches = String[]
    invariant(
        abs(observed) <= SOURCE_TOLERANCE,
        mismatches,
        "opening observation residual exceeds source tolerance",
    )
    invariant(
        isfinite(latent) && abs(latent) > MODEL_TOLERANCE,
        mismatches,
        "latent opening wedge no longer fails",
    )
    for (key, label) in (
            (
                "maximum_nominal_gdp_expenditure_residual_after_opening",
                "simulated nominal residual",
            ),
            (
                "maximum_real_gdp_expenditure_residual_after_opening",
                "simulated real residual",
            ),
            (
                "maximum_income_production_residual",
                "simulated income residual",
            ),
        )
        value = get(simulation, key, nothing)
        invariant(
            value isa Real && !(value isa Bool) &&
                isfinite(Float64(value)) &&
                Float64(value) <= MODEL_TOLERANCE,
            mismatches,
            "$label must be finite and at most $MODEL_TOLERANCE",
        )
    end
    isempty(mismatches) ||
        throw(
        SemanticInvariantMismatch(
            "candidate construction economics",
            mismatches,
        ),
    )
    return PortableConstructionSummary(
        String(metadata["candidate_id"]),
        Bool(environment["canonical_execution_envelope_match"]),
        String.(environment["canonical_execution_envelope_mismatches"]),
        observed,
        latent,
        Float64(
            simulation[
                "maximum_nominal_gdp_expenditure_residual_after_opening",
            ],
        ),
        Float64(
            simulation[
                "maximum_real_gdp_expenditure_residual_after_opening",
            ],
        ),
        Float64(simulation["maximum_income_production_residual"]),
        false,
        false,
    )
end

function transition_summary(result, seed::Int)
    candidate_id = String(result.metadata["candidate_id"])
    Random.seed!(seed)
    model = Bit.Model(
        deepcopy(result.parameters),
        deepcopy(result.initial_conditions),
    )
    validate_model_types(model, candidate_id, seed)
    opening_residuals = Bit.get_accounting_residuals(model.data)
    opening_observed = Float64(first(opening_residuals.gdp_and_expenditure))
    opening_latent =
        Float64(Bit.model_implied_opening_macro(model).expenditure_residual)
    mismatches = String[]
    invariant(
        abs(opening_observed) <= SOURCE_TOLERANCE,
        mismatches,
        "$candidate_id seed $seed opening observation exceeds source tolerance",
    )
    invariant(
        isfinite(opening_latent) && abs(opening_latent) > MODEL_TOLERANCE,
        mismatches,
        "$candidate_id seed $seed latent opening wedge no longer fails",
    )

    maximum_nominal = 0.0
    maximum_real = 0.0
    maximum_income = abs(Float64(first(opening_residuals.income_and_production)))
    maximum_central_bank = 0.0
    maximum_commercial_bank = 0.0
    maximum_final_stock_flow = 0.0
    maximum_intermediate_stock_flow = 0.0
    minimum_price = Inf
    minimum_final_inventory = minimum(model.firms.S_i)
    minimum_intermediate_inventory = minimum(model.firms.M_i)
    nonfinite_count = count(!isfinite, model_numeric_values(model))

    for _ in 1:TRANSITION_HORIZON
        previous_final_inventory = copy(model.firms.S_i)
        previous_intermediate_inventory = copy(model.firms.M_i)
        Bit.step!(model; parallel = false)
        Bit.collect_data!(model)
        validate_model_types(model, candidate_id, seed)
        residuals = Bit.get_accounting_residuals(model.data)
        maximum_nominal = max(
            maximum_nominal,
            abs(Float64(last(residuals.gdp_and_expenditure))),
        )
        maximum_real = max(
            maximum_real,
            abs(Float64(last(residuals.gdp_and_expenditure_real))),
        )
        maximum_income = max(
            maximum_income,
            abs(Float64(last(residuals.income_and_production))),
        )
        central_bank, commercial_bank =
            Bit.get_accounting_identity_banks(model)
        maximum_central_bank =
            max(maximum_central_bank, abs(Float64(central_bank)))
        maximum_commercial_bank =
            max(maximum_commercial_bank, abs(Float64(commercial_bank)))
        maximum_final_stock_flow = max(
            maximum_final_stock_flow,
            maximum(
                abs,
                model.firms.S_i .-
                    previous_final_inventory .-
                    model.firms.DS_i,
            ),
        )
        maximum_intermediate_stock_flow = max(
            maximum_intermediate_stock_flow,
            maximum(
                abs,
                model.firms.M_i .-
                    previous_intermediate_inventory .+
                    model.firms.Y_i ./ model.firms.beta_i .-
                    model.firms.DM_i,
            ),
        )
        prices = price_values(model)
        minimum_price = min(minimum_price, minimum(prices))
        minimum_final_inventory =
            min(minimum_final_inventory, minimum(model.firms.S_i))
        minimum_intermediate_inventory =
            min(minimum_intermediate_inventory, minimum(model.firms.M_i))
        nonfinite_count += count(!isfinite, model_numeric_values(model))
    end

    for (value, label) in (
            (maximum_nominal, "nominal transition residual"),
            (maximum_real, "real transition residual"),
            (maximum_income, "income residual"),
            (maximum_central_bank, "central-bank residual"),
            (maximum_commercial_bank, "commercial-bank residual"),
            (maximum_final_stock_flow, "final inventory stock-flow residual"),
            (
                maximum_intermediate_stock_flow,
                "intermediate inventory stock-flow residual",
            ),
        )
        invariant(
            isfinite(value) && value <= MODEL_TOLERANCE,
            mismatches,
            "$candidate_id seed $seed $label is $(repr(value)), tolerance $MODEL_TOLERANCE",
        )
    end
    invariant(
        isfinite(minimum_price) && minimum_price > 0,
        mismatches,
        "$candidate_id seed $seed minimum price is $(repr(minimum_price))",
    )
    invariant(
        minimum_final_inventory >= -DOMAIN_TOLERANCE,
        mismatches,
        "$candidate_id seed $seed final inventory domain fails",
    )
    invariant(
        minimum_intermediate_inventory >= -DOMAIN_TOLERANCE,
        mismatches,
        "$candidate_id seed $seed intermediate inventory domain fails",
    )
    invariant(
        nonfinite_count == 0,
        mismatches,
        "$candidate_id seed $seed has $nonfinite_count nonfinite values",
    )
    isempty(mismatches) ||
        throw(SemanticInvariantMismatch("transition economics", mismatches))

    return PortableTransitionSummary(
        candidate_id,
        seed,
        TRANSITION_HORIZON,
        maximum_nominal,
        maximum_real,
        maximum_income,
        maximum_central_bank,
        maximum_commercial_bank,
        maximum_final_stock_flow,
        maximum_intermediate_stock_flow,
        minimum_price,
        minimum_final_inventory,
        minimum_intermediate_inventory,
        nonfinite_count,
        false,
        false,
    )
end

function run_portable_semantic_validation(
        config_path::AbstractString = joinpath(
            @__DIR__,
            "opening_macro_candidates.toml",
        );
        repo_root::AbstractString = normpath(
            joinpath(@__DIR__, "..", "..", ".."),
        ),
    )
    config = load_build_config(config_path; repo_root)
    assessment =
        USOpeningAccountingCandidate.USJuliaExecutionEnvelope.validate_portable_semantic_environment(
        config,
    )
    config_sha256 = bytes2hex(SHA.sha256(read(config_path)))
    construction = PortableConstructionSummary[]
    transitions = PortableTransitionSummary[]
    for candidate in config["candidate"]
        result = build_candidate(
            config,
            candidate;
            repo_root,
            config_sha256,
            execution_mode = PORTABLE_SEMANTIC_BUILD,
        )
        push!(construction, construction_summary(result))
        for seed in (20261003, 20261004)
            push!(transitions, transition_summary(result, seed))
        end
    end
    digest = source_tree_digest(
        joinpath(repo_root, String(config["runtime_source_tree_path"])),
    )
    digest.sha256 == config["runtime_source_tree_sha256"] ||
        throw(
        SemanticInvariantMismatch(
            "runtime provenance",
            ["runtime source-tree SHA-256 changed during validation"],
        ),
    )
    return PortableSemanticReport(
        construction,
        transitions,
        digest.sha256,
        digest.file_count,
        assessment.actual,
        assessment.canonical_match,
        copy(assessment.mismatches),
        false,
        false,
        false,
        false,
        false,
    )
end

end # module
