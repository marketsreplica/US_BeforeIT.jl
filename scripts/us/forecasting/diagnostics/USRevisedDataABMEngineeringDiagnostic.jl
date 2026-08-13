module USRevisedDataABMEngineeringDiagnostic

using LinearAlgebra
using SHA
using TOML

if !isdefined(@__MODULE__, :USForecastRegistry)
    include(
        joinpath(
            @__DIR__,
            "..",
            "registry",
            "USForecastRegistry.jl",
        ),
    )
end
using .USForecastRegistry: derive_seed_record

export ABMEngineeringContractError,
    EngineeringExecutionGuard,
    EngineeringFailure,
    PathSeedRecord,
    QualifiedABMInputs,
    build_qualification_manifest,
    derive_path_seed_plan,
    execution_guard,
    path_seed_plan_sha256,
    protocol_sha256,
    reassemble_inputs,
    record_engineering_failure,
    refuse_prohibited_action,
    sanitize_origin_inputs,
    validate_partitions,
    validate_protocol,
    validate_qualification_manifest

const SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-engineering-protocol.v1"
const CONTRACT_ID =
    "beforeit-us-revised-data-abm-engineering-qualification.v1"
const QUALIFIED_INPUT_SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-qualified-input.v1"
const MANIFEST_SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-engineering-manifest.v1"
const INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const DIAGNOSTIC_CLASS = "engineering_input_qualification_only"
const ORIGIN_PERIOD = "2026Q1"
const FORECAST_START_PERIOD = "2026Q2"
const FORECAST_END_PERIOD = "2027Q1"
const HORIZONS = [1, 2, 3, 4]
const PATH_COUNT = 32
const CONSTRUCTION_PATH_PURPOSE =
    "abm_engineering_model_construction"
const SIMULATION_PATH_PURPOSE = "abm_engineering_simulation"
const REQUIRED_PAST_ONLY_SERIES = ["C_G", "C_E", "Y_I"]
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_engineering_protocol.toml",
)
const PROTOCOL_SHA256 =
    "34461f24ff09e1aa1eed7bf9bad5d8b415eab011bd82b8f7e7a114d0e2246743"
const BLOCKERS = [
    "FULL_ACCOUNTING_BRIDGE_UNRESOLVED",
    "OUTPUT_SCALE_BRIDGE_UNVALIDATED",
    "TIER1_TARGET_OPERATOR_COVERAGE_ZERO_OF_EIGHT",
    "HISTORICAL_ORIGIN_COUNT_ZERO",
]
const DECLARATIONS = Dict{String, Any}(
    "origin_admissible" => false,
    "promotion_eligible" => false,
    "confirmatory" => false,
    "truth_blind" => false,
    "class_h_allowed" => false,
    "production_registry_allowed" => false,
    "scoring_allowed" => false,
    "inference_allowed" => false,
    "input_truth_isolation_verified" => false,
    "input_lineage_verified" => false,
    "truth_values_emitted" => false,
    "forecast_values_emitted" => false,
    "distribution_artifacts_emitted" => false,
)
const SANITIZATION = Dict{String, Any}(
    "required_past_only_series" => REQUIRED_PAST_ONLY_SERIES,
    "time_dimension" => 1,
    "retain_rule" => "quarter_le_origin_inclusive",
    "partition_rule" =>
        "parameters_to_structural_declared_series_including_required_to_dynamic_remaining_initial_conditions_to_state",
    "declared_dynamic_future_values_in_qualified_hash" => false,
    "class_h_inputs_rejected" => true,
    "qualified_values_nonfinite_rejected" => true,
    "qualified_values_missing_rejected" => true,
)
const EXECUTION = Dict{String, Any}(
    "serial_only" => true,
    "parallel_allowed" => false,
    "julia_threads" => 1,
    "openblas_threads" => 1,
    "process_global_rng_assumed" => true,
    "seed_before_model_construction" => true,
    "seed_before_simulation" => true,
    "construction_path_purpose" => CONSTRUCTION_PATH_PURPOSE,
    "simulation_path_purpose" => SIMULATION_PATH_PURPOSE,
    "path_ids" => "one_based_contiguous",
)
const INPUT_SERIES = [
    Dict{String, Any}(
        "id" => "C_G",
        "formula" =>
            "timescale*sum(government_consumption_at_origin)*real_government_consumption[t]/real_government_consumption[origin]",
        "unit" => "annualized_model_currency_flow_at_calibration_scale",
        "frequency" => "quarterly",
        "time_semantics" => "history_through_origin_only",
    ),
    Dict{String, Any}(
        "id" => "C_E",
        "formula" =>
            "timescale*sum(domestic_exports_at_origin)*real_exports[t]/real_exports[origin]",
        "unit" => "annualized_model_currency_flow_at_calibration_scale",
        "frequency" => "quarterly",
        "time_semantics" => "history_through_origin_only",
    ),
    Dict{String, Any}(
        "id" => "Y_I",
        "formula" =>
            "timescale*sum(imports_at_origin)*real_imports[t]/real_imports[origin]",
        "unit" => "annualized_model_currency_flow_at_calibration_scale",
        "frequency" => "quarterly",
        "time_semantics" => "history_through_origin_only",
    ),
]
const CANDIDATE_OUTPUT_OPERATORS = [
    Dict{String, Any}(
        "id" => "real_gdp_growth",
        "formula" => "400*log(real_gdp_level[t]/real_gdp_level[t-1])",
        "unit" => "annualized_log_percent",
        "frequency" => "quarterly",
        "status" => "NOT_VALIDATED",
    ),
    Dict{String, Any}(
        "id" => "gdp_deflator_inflation",
        "formula" =>
            "400*log(gdp_deflator_level[t]/gdp_deflator_level[t-1])",
        "unit" => "annualized_log_percent",
        "frequency" => "quarterly",
        "status" => "NOT_VALIDATED",
    ),
]
const FAILURE_CODES = Dict(
    :model_construction => "MODEL_CONSTRUCTION_FAILURE",
    :simulation => "SIMULATION_FAILURE",
    :accounting_gate => "ACCOUNTING_GATE_FAILURE",
    :scale_gate => "SCALE_GATE_FAILURE",
    :target_operator => "TARGET_OPERATOR_FAILURE",
    :nonfinite_output => "NONFINITE_OUTPUT_FAILURE",
    :unexpected => "UNEXPECTED_FAILURE",
)
const FORBIDDEN_INPUT_KEY_FRAGMENTS =
    ("truth", "actual", "realization", "score", "loss")
const PROHIBITED_ACTIONS = Set(
    [
        :score,
        :inference,
        :promotion,
        :origin_admission,
        :production_registry,
        :class_h,
        :truth_access,
        :forecast_emission,
    ],
)

struct ABMEngineeringContractError <: Exception
    message::String
end

Base.showerror(io::IO, error::ABMEngineeringContractError) =
    print(io, error.message)

fail(message) =
    throw(ABMEngineeringContractError(String(message)))

struct QualifiedABMInputs
    protocol_sha256::String
    origin_period::String
    structural::Dict{String, Any}
    dynamic::Dict{String, Any}
    state::Dict{String, Any}
    dynamic_periods::Dict{String, Vector{String}}
    structural_members::Vector{String}
    dynamic_members::Vector{String}
    state_members::Vector{String}
    partition_sha256::Dict{String, String}
    qualified_input_sha256::String
end

struct PathSeedRecord
    master_seed::Int
    experiment_id::String
    origin_manifest_sha256::String
    model_id::String
    path_id::Int
    construction_seed::Int
    construction_seed_key_sha256::String
    simulation_seed::Int
    simulation_seed_key_sha256::String
end

struct EngineeringExecutionGuard
    parallel::Bool
    julia_threads::Int
    openblas_threads::Int
    process_global_rng_assumed::Bool
    seed_before_model_construction::Bool
    seed_before_simulation::Bool
end

struct EngineeringFailure
    path_id::Int
    substream::String
    seed_key_sha256::String
    stage::String
    code::String
    exception_type::String
    message::String
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
protocol_sha256() = PROTOCOL_SHA256

function canonical(value)
    if value === nothing
        return "nothing:"
    elseif value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa Integer
        return "integer:" * string(value)
    elseif value isa AbstractFloat
        isfinite(value) || fail("cannot canonicalize a nonfinite number")
        return "float64:" * bitstring(Float64(value))
    elseif value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    elseif value isa AbstractArray
        dimensions = join(size(value), ",")
        encoded = canonical.(vec(value))
        return "array:$(ndims(value)):$(dimensions):$(length(encoded)):" *
            join(
            ("$(ncodeunits(item)):$item" for item in encoded),
            "",
        )
    elseif value isa AbstractDict
        keys_sorted = sort!(collect(String.(keys(value))))
        fields = String[]
        for key in keys_sorted
            encoded = canonical(value[key])
            push!(
                fields,
                "$(ncodeunits(key)):$key$(ncodeunits(encoded)):$encoded",
            )
        end
        return "dict:$(length(fields)):" * join(fields, "")
    end
    return fail("cannot canonicalize unsupported type $(typeof(value))")
end

semantic_sha256(value) = sha256_hex(canonical(value))

function expect_exact_keys(value, expected, location)
    value isa AbstractDict || fail("$location must be a table")
    actual = Set(String.(keys(value)))
    wanted = Set(String.(expected))
    missing = sort!(collect(setdiff(wanted, actual)))
    unknown = sort!(collect(setdiff(actual, wanted)))
    isempty(missing) ||
        fail("$location is missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail("$location has unknown keys: $(join(unknown, ", "))")
    return value
end

function expect_hash(value, location)
    value isa AbstractString ||
        fail("$location must be a lowercase SHA-256 string")
    text = String(value)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail("$location must be 64 lowercase hexadecimal characters")
    return text
end

function expect_equal(actual, expected, location)
    canonical(actual) == canonical(expected) ||
        fail("$location changed from the frozen contract")
    return actual
end

function validated_input_key(key, location)
    key isa AbstractString ||
        fail("$location has a non-string key")
    text = String(key)
    lowered = lowercase(text)
    any(
        fragment -> occursin(fragment, lowered),
        FORBIDDEN_INPUT_KEY_FRAGMENTS,
    ) &&
        fail("$location.$text has a forbidden truth/score key")
    return text
end

function input_dictionary_shell(value::AbstractDict, location)
    result = Dict{String, Any}()
    for (key, item) in pairs(value)
        text = validated_input_key(key, location)
        haskey(result, text) &&
            fail("$location has duplicate key $text")
        result[text] = item
    end
    return result
end

function validated_copy(value, location)
    if value === missing
        fail("$location contains a missing value")
    elseif value === nothing
        fail("$location contains nothing")
    elseif value isa Bool
        return value
    elseif value isa Integer
        return try
            Int(value)
        catch
            fail("$location contains an out-of-range integer")
        end
    elseif value isa Real
        result = Float64(value)
        isfinite(result) || fail("$location contains a nonfinite value")
        return result
    elseif value isa AbstractString
        return String(value)
    elseif value isa AbstractArray
        result = [
            validated_copy(item, "$location[$index]")
                for (index, item) in enumerate(vec(value))
        ]
        return reshape(result, size(value))
    elseif value isa AbstractDict
        result = Dict{String, Any}()
        for (key, item) in pairs(value)
            text = validated_input_key(key, location)
            haskey(result, text) &&
                fail("$location has duplicate key $text")
            result[text] = validated_copy(item, "$location.$text")
        end
        return result
    end
    return fail("$location contains unsupported type $(typeof(value))")
end

function quarter_ordinal(period)
    period isa AbstractString ||
        fail("quarter identifier must be a string")
    matched = match(r"^([1-9][0-9]{3})Q([1-4])$", String(period))
    matched === nothing &&
        fail("invalid quarterly period $(repr(period))")
    year = parse(Int, matched.captures[1])
    quarter = parse(Int, matched.captures[2])
    return 4year + quarter
end

function quarter_string(ordinal)
    quarter = mod(ordinal - 1, 4) + 1
    year = (ordinal - quarter) ÷ 4
    return "$(year)Q$(quarter)"
end

function validate_periods(periods, location)
    periods isa AbstractVector ||
        fail("$location must be a quarterly-period vector")
    result = String[]
    for (index, period) in enumerate(periods)
        period isa AbstractString ||
            fail("$location[$index] must be a quarterly-period string")
        text = String(period)
        quarter_ordinal(text)
        push!(result, text)
    end
    isempty(result) && fail("$location must not be empty")
    length(unique(result)) == length(result) ||
        fail("$location contains duplicate quarters")
    ordinals = quarter_ordinal.(result)
    all(diff(ordinals) .== 1) ||
        fail("$location must be strictly contiguous")
    return result
end

function validate_protocol_semantics(document)
    top_level_keys = [
        "schema_version",
        "contract_id",
        "information_track",
        "diagnostic_class",
        "origin_period",
        "forecast_start_period",
        "forecast_end_period",
        "horizons",
        "path_count",
        "runner_implemented",
        "ensemble_executed",
        "blockers",
        "declarations",
        "sanitization",
        "execution",
        "input_series",
        "candidate_output_operators",
    ]
    expect_exact_keys(document, top_level_keys, "ABM engineering protocol")
    document["schema_version"] == SCHEMA_VERSION ||
        fail("protocol schema_version changed")
    document["contract_id"] == CONTRACT_ID ||
        fail("protocol contract_id changed")
    document["information_track"] == INFORMATION_TRACK ||
        fail("protocol information_track changed")
    document["diagnostic_class"] == DIAGNOSTIC_CLASS ||
        fail("protocol diagnostic_class changed")
    document["origin_period"] == ORIGIN_PERIOD ||
        fail("protocol origin_period changed")
    document["forecast_start_period"] == FORECAST_START_PERIOD ||
        fail("protocol forecast_start_period changed")
    document["forecast_end_period"] == FORECAST_END_PERIOD ||
        fail("protocol forecast_end_period changed")
    expect_equal(document["horizons"], HORIZONS, "protocol horizons")
    document["path_count"] == PATH_COUNT ||
        fail("protocol path_count changed")
    document["runner_implemented"] === false ||
        fail("protocol runner_implemented must remain false")
    document["ensemble_executed"] === false ||
        fail("protocol ensemble_executed must remain false")
    expect_equal(document["blockers"], BLOCKERS, "protocol blockers")
    expect_equal(
        document["declarations"],
        DECLARATIONS,
        "protocol declarations",
    )
    expect_equal(
        document["sanitization"],
        SANITIZATION,
        "protocol sanitization",
    )
    expect_equal(document["execution"], EXECUTION, "protocol execution")
    expect_equal(
        document["input_series"],
        INPUT_SERIES,
        "protocol input-series formulas and units",
    )
    expect_equal(
        document["candidate_output_operators"],
        CANDIDATE_OUTPUT_OPERATORS,
        "protocol candidate output-operator formulas and units",
    )

    origin_ordinal = quarter_ordinal(document["origin_period"])
    target_periods =
        quarter_string.(origin_ordinal .+ document["horizons"])
    first(target_periods) == document["forecast_start_period"] ||
        fail("forecast_start_period does not map from origin and horizons")
    last(target_periods) == document["forecast_end_period"] ||
        fail("forecast_end_period does not map from origin and horizons")
    return document
end

"""
    validate_protocol(path=PROTOCOL_PATH)

Validate the byte-pinned, fail-closed ABM engineering protocol and return its
parsed document plus byte hash.
"""
function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("ABM engineering protocol is missing: $path")
    bytes = read(path)
    actual_sha256 = sha256_hex(bytes)
    actual_sha256 == PROTOCOL_SHA256 ||
        fail("ABM engineering protocol SHA-256 changed")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail("ABM engineering protocol is not valid TOML: $(sprint(showerror, error))")
    end
    validate_protocol_semantics(document)
    return (document = document, sha256 = actual_sha256)
end

function partition_payload(inputs::QualifiedABMInputs)
    return Dict{String, Any}(
        "schema_version" => QUALIFIED_INPUT_SCHEMA_VERSION,
        "protocol_sha256" => inputs.protocol_sha256,
        "information_track" => INFORMATION_TRACK,
        "origin_period" => inputs.origin_period,
        "structural" => inputs.structural,
        "dynamic" => inputs.dynamic,
        "state" => inputs.state,
        "dynamic_periods" => inputs.dynamic_periods,
        "partition_members" => Dict{String, Any}(
            "structural" => inputs.structural_members,
            "dynamic" => inputs.dynamic_members,
            "state" => inputs.state_members,
        ),
    )
end

function expected_members(prefix, dictionary)
    return sort!(["$prefix.$key" for key in keys(dictionary)])
end

"""
    validate_partitions(inputs)

Recompute disjointness, exhaustiveness, period bounds, partition hashes, and
the qualified-input hash. This catches mutation of any retained structural,
dynamic, or state value after construction.
"""
function validate_partitions(inputs::QualifiedABMInputs)
    expect_hash(inputs.protocol_sha256, "qualified input protocol_sha256")
    inputs.origin_period == ORIGIN_PERIOD ||
        fail("qualified input origin changed")
    structural_members = expected_members("parameters", inputs.structural)
    dynamic_members =
        expected_members("initial_conditions", inputs.dynamic)
    state_members = expected_members("initial_conditions", inputs.state)
    inputs.structural_members == structural_members ||
        fail("structural partition membership changed")
    inputs.dynamic_members == dynamic_members ||
        fail("dynamic partition membership changed")
    inputs.state_members == state_members ||
        fail("state partition membership changed")

    all_members =
        [structural_members; dynamic_members; state_members]
    length(all_members) == length(unique(all_members)) ||
        fail("structural, dynamic, and state partitions overlap")
    dynamic_names = Set(keys(inputs.dynamic))
    Set(REQUIRED_PAST_ONLY_SERIES) ⊆ dynamic_names ||
        fail("mandatory C_G/C_E/Y_I dynamic histories are missing")
    Set(keys(inputs.dynamic_periods)) == dynamic_names ||
        fail("dynamic period keys are not exhaustive")
    for name in sort!(collect(dynamic_names))
        periods =
            validate_periods(inputs.dynamic_periods[name], "$name periods")
        last(periods) == inputs.origin_period ||
            fail("$name retained periods do not end at the origin")
        values = inputs.dynamic[name]
        values isa AbstractArray ||
            fail("$name dynamic values must be an array")
        size(values, 1) == length(periods) ||
            fail("$name time dimension does not match retained periods")
        validated_copy(values, "dynamic.$name")
    end
    validated_copy(inputs.structural, "structural")
    validated_copy(inputs.state, "state")

    expected_hashes = Dict(
        "structural" => semantic_sha256(inputs.structural),
        "dynamic" => semantic_sha256(
            Dict(
                "values" => inputs.dynamic,
                "periods" => inputs.dynamic_periods,
            ),
        ),
        "state" => semantic_sha256(inputs.state),
    )
    inputs.partition_sha256 == expected_hashes ||
        fail("qualified input partition SHA-256 changed")
    semantic_sha256(partition_payload(inputs)) ==
        inputs.qualified_input_sha256 ||
        fail("qualified input SHA-256 changed")
    return inputs
end

"""
    sanitize_origin_inputs(parameters, initial_conditions, periods_by_series;
                           origin_period="2026Q1",
                           dynamic_keys=["C_G", "C_E", "Y_I"],
                           class_h_used)

Create a sanitized input bundle. All parameters enter the `structural`
partition; explicitly named time series enter `dynamic` after an inclusive
origin slice; all remaining initial conditions enter `state`. Arrays left in
`state` are preserved but are not certified past-only by this function.
"""
function sanitize_origin_inputs(
        parameters::AbstractDict,
        initial_conditions::AbstractDict,
        periods_by_series::AbstractDict;
        origin_period::AbstractString = ORIGIN_PERIOD,
        dynamic_keys = REQUIRED_PAST_ONLY_SERIES,
        class_h_used::Bool,
        protocol_path::AbstractString = PROTOCOL_PATH,
    )
    protocol = validate_protocol(protocol_path)
    String(origin_period) == protocol.document["origin_period"] ||
        fail("only the frozen 2026Q1 engineering origin is allowed")
    class_h_used &&
        fail("class-H inputs are forbidden by the engineering contract")

    structural =
        validated_copy(parameters, "parameters")::Dict{String, Any}
    initial =
        input_dictionary_shell(initial_conditions, "initial_conditions")
    isempty(structural) && fail("parameters must not be empty")
    isempty(initial) && fail("initial_conditions must not be empty")

    names = String[]
    for (index, key) in enumerate(dynamic_keys)
        key isa AbstractString ||
            fail("dynamic_keys[$index] must be a string")
        push!(names, String(key))
    end
    length(names) == length(unique(names)) ||
        fail("dynamic_keys contains duplicates")
    Set(REQUIRED_PAST_ONLY_SERIES) ⊆ Set(names) ||
        fail("dynamic_keys must include C_G, C_E, and Y_I")
    all(haskey(initial, name) for name in names) ||
        fail("a requested dynamic series is absent from initial_conditions")

    period_keys = Set{String}()
    normalized_periods = Dict{String, Vector{String}}()
    for (key, periods) in pairs(periods_by_series)
        key isa AbstractString ||
            fail("periods_by_series has a non-string key")
        text = String(key)
        text in period_keys &&
            fail("periods_by_series has duplicate key $text")
        push!(period_keys, text)
        normalized_periods[text] =
            validate_periods(periods, "$text source periods")
    end
    period_keys == Set(names) ||
        fail("periods_by_series keys must exactly equal dynamic_keys")

    dynamic = Dict{String, Any}()
    retained_periods = Dict{String, Vector{String}}()
    for name in sort(names)
        values = initial[name]
        values isa AbstractArray ||
            fail("$name must be an array with time on dimension 1")
        periods = normalized_periods[name]
        size(values, 1) == length(periods) ||
            fail("$name time dimension does not match its source periods")
        origin_index = findfirst(==(String(origin_period)), periods)
        origin_index === nothing &&
            fail("$name source periods do not contain the origin")
        retained_periods[name] = periods[1:origin_index]
        retained = copy(selectdim(values, 1, 1:origin_index))
        dynamic[name] = validated_copy(
            retained,
            "initial_conditions.$name retained prefix",
        )
    end
    state = Dict{String, Any}(
        key => validated_copy(value, "initial_conditions.$key")
            for (key, value) in initial if !(key in Set(names))
    )
    structural_members = expected_members("parameters", structural)
    dynamic_members = expected_members("initial_conditions", dynamic)
    state_members = expected_members("initial_conditions", state)
    partition_hashes = Dict(
        "structural" => semantic_sha256(structural),
        "dynamic" => semantic_sha256(
            Dict("values" => dynamic, "periods" => retained_periods),
        ),
        "state" => semantic_sha256(state),
    )
    provisional = QualifiedABMInputs(
        protocol.sha256,
        String(origin_period),
        structural,
        dynamic,
        state,
        retained_periods,
        structural_members,
        dynamic_members,
        state_members,
        partition_hashes,
        "",
    )
    result = QualifiedABMInputs(
        provisional.protocol_sha256,
        provisional.origin_period,
        provisional.structural,
        provisional.dynamic,
        provisional.state,
        provisional.dynamic_periods,
        provisional.structural_members,
        provisional.dynamic_members,
        provisional.state_members,
        provisional.partition_sha256,
        semantic_sha256(partition_payload(provisional)),
    )
    return validate_partitions(result)
end

"""
    reassemble_inputs(inputs)

Return only the sanitized parameters, initial conditions, and dynamic period
vectors. Post-origin values from declared dynamic series cannot be recovered
from this representation. State arrays that were not declared dynamic remain
outside that guarantee.
"""
function reassemble_inputs(inputs::QualifiedABMInputs)
    validate_partitions(inputs)
    initial_conditions = deepcopy(inputs.state)
    for (key, value) in inputs.dynamic
        haskey(initial_conditions, key) &&
            fail("dynamic and state partitions overlap at $key")
        initial_conditions[key] = deepcopy(value)
    end
    return (
        parameters = deepcopy(inputs.structural),
        initial_conditions = initial_conditions,
        periods_by_series = deepcopy(inputs.dynamic_periods),
    )
end

function validate_seed_records_intrinsic(records)
    records isa AbstractVector ||
        fail("path seed plan must be a vector")
    isempty(records) && fail("path seed plan must not be empty")
    all(record -> record isa PathSeedRecord, records) ||
        fail("path seed plan contains an unsupported record")
    length(records) == PATH_COUNT ||
        fail("path seed plan must contain exactly $PATH_COUNT records")
    path_ids = getfield.(records, :path_id)
    path_ids == collect(1:PATH_COUNT) ||
        fail("path seed plan must be sorted and one-based contiguous")
    length(unique(path_ids)) == PATH_COUNT ||
        fail("path seed plan contains duplicate path IDs")
    master_seed = first(records).master_seed
    experiment_id = first(records).experiment_id
    origin_manifest_sha256 =
        first(records).origin_manifest_sha256
    model_id = first(records).model_id
    master_seed >= 0 ||
        fail("path-plan master seed must be non-negative")
    all(record -> record.master_seed == master_seed, records) ||
        fail("path seed plan mixes master seeds")
    all(record -> record.experiment_id == experiment_id, records) ||
        fail("path seed plan mixes experiment IDs")
    all(
        record ->
        record.origin_manifest_sha256 == origin_manifest_sha256,
        records,
    ) || fail("path seed plan mixes origin hashes")
    all(record -> record.model_id == model_id, records) ||
        fail("path seed plan mixes model IDs")
    expect_hash(origin_manifest_sha256, "path-plan origin SHA-256")
    for record in records
        record.path_id >= 0 || fail("path ID must be non-negative")
        construction = try
            derive_seed_record(
                record.master_seed;
                experiment_id = record.experiment_id,
                origin_manifest_sha256 =
                    record.origin_manifest_sha256,
                model_id = record.model_id,
                path_id = record.path_id,
                purpose = CONSTRUCTION_PATH_PURPOSE,
            )
        catch error
            fail(
                "construction seed record is invalid: " *
                    sprint(showerror, error),
            )
        end
        simulation = try
            derive_seed_record(
                record.master_seed;
                experiment_id = record.experiment_id,
                origin_manifest_sha256 =
                    record.origin_manifest_sha256,
                model_id = record.model_id,
                path_id = record.path_id,
                purpose = SIMULATION_PATH_PURPOSE,
            )
        catch error
            fail(
                "simulation seed record is invalid: " *
                    sprint(showerror, error),
            )
        end
        record.construction_seed == construction.seed ||
            fail("construction seed does not match registry derivation")
        record.construction_seed_key_sha256 ==
            construction.seed_key_sha256 ||
            fail(
            "construction seed-key SHA-256 does not match registry derivation",
        )
        record.simulation_seed == simulation.seed ||
            fail("simulation seed does not match registry derivation")
        record.simulation_seed_key_sha256 ==
            simulation.seed_key_sha256 ||
            fail(
            "simulation seed-key SHA-256 does not match registry derivation",
        )
    end
    all_seed_key_hashes = [
        getfield.(records, :construction_seed_key_sha256)
        getfield.(records, :simulation_seed_key_sha256)
    ]
    length(unique(all_seed_key_hashes)) == 2PATH_COUNT ||
        fail("construction/simulation seed-key hashes are not unique")
    all_seeds = [
        getfield.(records, :construction_seed)
        getfield.(records, :simulation_seed)
    ]
    length(unique(all_seeds)) == 2PATH_COUNT ||
        fail("derived construction/simulation seeds collided")
    return records
end

function validate_seed_plan(records, inputs::QualifiedABMInputs)
    validate_seed_records_intrinsic(records)
    all(
        record ->
        record.origin_manifest_sha256 == inputs.qualified_input_sha256,
        records,
    ) || fail("path seed origin hash is not the qualified-input hash")
    for record in records
        expect_hash(
            record.construction_seed_key_sha256,
            "construction seed-key SHA-256",
        )
        expect_hash(
            record.simulation_seed_key_sha256,
            "simulation seed-key SHA-256",
        )
        record.construction_seed >= 0 ||
            fail("construction seed must be non-negative")
        record.simulation_seed >= 0 ||
            fail("simulation seed must be non-negative")
    end
    return records
end

"""
    derive_path_seed_plan(master_seed, inputs; experiment_id, model_id,
                          path_ids=1:32)

Derive registry-compatible, scheduling-independent construction and simulation
substreams for every path. The returned plan is always sorted by path ID.
"""
function derive_path_seed_plan(
        master_seed,
        inputs::QualifiedABMInputs;
        experiment_id,
        model_id,
        path_ids = collect(1:PATH_COUNT),
    )
    validate_partitions(inputs)
    master_seed isa Integer && !(master_seed isa Bool) ||
        fail("master_seed must be an integer")
    master_seed >= 0 ||
        fail("master_seed must be non-negative")
    requested = Int[]
    for path_id in path_ids
        path_id isa Integer && !(path_id isa Bool) ||
            fail("path_ids must contain integers")
        push!(requested, Int(path_id))
    end
    length(requested) == length(unique(requested)) ||
        fail("path_ids contains duplicates")
    sort(requested) == collect(1:PATH_COUNT) ||
        fail("path_ids must be exactly 1:$PATH_COUNT")

    records = PathSeedRecord[]
    for path_id in sort(requested)
        construction = try
            derive_seed_record(
                master_seed;
                experiment_id,
                origin_manifest_sha256 = inputs.qualified_input_sha256,
                model_id,
                path_id,
                purpose = CONSTRUCTION_PATH_PURPOSE,
            )
        catch error
            fail(
                "registry construction-seed derivation failed: " *
                    sprint(showerror, error),
            )
        end
        simulation = try
            derive_seed_record(
                master_seed;
                experiment_id,
                origin_manifest_sha256 = inputs.qualified_input_sha256,
                model_id,
                path_id,
                purpose = SIMULATION_PATH_PURPOSE,
            )
        catch error
            fail(
                "registry simulation-seed derivation failed: " *
                    sprint(showerror, error),
            )
        end
        push!(
            records,
            PathSeedRecord(
                Int(master_seed),
                String(experiment_id),
                inputs.qualified_input_sha256,
                String(model_id),
                path_id,
                construction.seed,
                construction.seed_key_sha256,
                simulation.seed,
                simulation.seed_key_sha256,
            ),
        )
    end
    return validate_seed_plan(records, inputs)
end

function path_seed_payload(record::PathSeedRecord)
    return Dict{String, Any}(
        "master_seed" => record.master_seed,
        "experiment_id" => record.experiment_id,
        "origin_manifest_sha256" => record.origin_manifest_sha256,
        "model_id" => record.model_id,
        "path_id" => record.path_id,
        "construction_purpose" => CONSTRUCTION_PATH_PURPOSE,
        "construction_seed" => record.construction_seed,
        "construction_seed_key_sha256" =>
            record.construction_seed_key_sha256,
        "simulation_purpose" => SIMULATION_PATH_PURPOSE,
        "simulation_seed" => record.simulation_seed,
        "simulation_seed_key_sha256" =>
            record.simulation_seed_key_sha256,
    )
end

function path_seed_plan_sha256(records)
    validate_seed_records_intrinsic(records)
    return semantic_sha256(path_seed_payload.(records))
end

function validate_execution_guard(guard::EngineeringExecutionGuard)
    guard.julia_threads == Threads.nthreads() ||
        fail("execution guard Julia-thread count does not match runtime")
    guard.openblas_threads == BLAS.get_num_threads() ||
        fail("execution guard BLAS-thread count does not match runtime")
    guard.parallel === false ||
        fail("parallel ABM engineering execution is forbidden")
    guard.julia_threads == 1 ||
        fail("ABM engineering execution requires one Julia thread")
    guard.openblas_threads == 1 ||
        fail("ABM engineering execution requires one BLAS thread")
    guard.process_global_rng_assumed === true ||
        fail("the current process-global RNG dependency must be acknowledged")
    guard.seed_before_model_construction === true ||
        fail("seed-before-model-construction is required")
    guard.seed_before_simulation === true ||
        fail("seed-before-simulation is required")
    return guard
end

"""
    execution_guard(; parallel=false, julia_threads=Threads.nthreads(),
                    openblas_threads=BLAS.get_num_threads(), ...)

Validate the serial execution declarations required while the ABM consumes the
process-global RNG, including equality with active Julia/BLAS thread counts. A
future runner must still place `Random.seed!` immediately before construction
and simulation using the respective domain-separated substream.
"""
function execution_guard(;
        parallel::Bool = false,
        julia_threads::Integer = Threads.nthreads(),
        openblas_threads::Integer = BLAS.get_num_threads(),
        process_global_rng_assumed::Bool = true,
        seed_before_model_construction::Bool = true,
        seed_before_simulation::Bool = true,
    )
    julia_threads isa Bool &&
        fail("julia_threads must be an integer, not Bool")
    openblas_threads isa Bool &&
        fail("openblas_threads must be an integer, not Bool")
    actual_julia_threads = Threads.nthreads()
    actual_openblas_threads = BLAS.get_num_threads()
    Int(julia_threads) == actual_julia_threads ||
        fail(
        "declared Julia threads do not match runtime: " *
            "$(Int(julia_threads)) != $actual_julia_threads",
    )
    Int(openblas_threads) == actual_openblas_threads ||
        fail(
        "declared BLAS threads do not match runtime: " *
            "$(Int(openblas_threads)) != $actual_openblas_threads",
    )
    guard = EngineeringExecutionGuard(
        parallel,
        Int(julia_threads),
        Int(openblas_threads),
        process_global_rng_assumed,
        seed_before_model_construction,
        seed_before_simulation,
    )
    return validate_execution_guard(guard)
end

failure_substream(stage::Symbol) =
    stage == :model_construction ?
    CONSTRUCTION_PATH_PURPOSE : SIMULATION_PATH_PURPOSE

function seed_key_for_stage(record::PathSeedRecord, stage::Symbol)
    return stage == :model_construction ?
        record.construction_seed_key_sha256 :
        record.simulation_seed_key_sha256
end

function validate_failures(failures, seed_plan)
    validate_seed_records_intrinsic(seed_plan)
    failures isa AbstractVector ||
        fail("engineering failures must be a vector")
    all(item -> item isa EngineeringFailure, failures) ||
        fail("engineering failures contain an unsupported record")
    path_ids = getfield.(failures, :path_id)
    length(path_ids) == length(unique(path_ids)) ||
        fail("only one terminal failure may be recorded per path")
    seeds_by_path =
        Dict(record.path_id => record for record in seed_plan)
    for failure in failures
        haskey(seeds_by_path, failure.path_id) ||
            fail("failure references an unknown path")
        haskey(FAILURE_CODES, Symbol(failure.stage)) ||
            fail("failure stage is unsupported")
        stage = Symbol(failure.stage)
        failure.substream == failure_substream(stage) ||
            fail("failure substream does not match its stage")
        failure.seed_key_sha256 ==
            seed_key_for_stage(seeds_by_path[failure.path_id], stage) ||
            fail("failure seed-key SHA-256 changed")
        failure.code == FAILURE_CODES[Symbol(failure.stage)] ||
            fail("failure code does not match its stage")
        occursin(
            r"^[A-Za-z_][A-Za-z0-9_.]{0,127}$",
            failure.exception_type,
        ) || fail("failure exception_type must be a short Julia identifier")
        isempty(failure.message) &&
            fail("failure message must not be empty")
        ncodeunits(failure.message) <= 4096 ||
            fail("failure message exceeds 4096 bytes")
    end
    return failures
end

"""
    record_engineering_failure(seed_plan, path_id, stage, error)

Create one terminal engineering-failure record. Accounting and scale failures
remain distinct blockers and are never converted into forecast cells.
"""
function record_engineering_failure(
        seed_plan,
        path_id::Integer,
        stage::Symbol,
        error::Exception,
    )
    path_id isa Bool &&
        fail("engineering failure path_id must be an integer, not Bool")
    validate_seed_records_intrinsic(seed_plan)
    haskey(FAILURE_CODES, stage) ||
        fail("unsupported engineering failure stage $stage")
    matches = filter(record -> record.path_id == path_id, seed_plan)
    length(matches) == 1 ||
        fail("engineering failure path is absent or duplicated")
    message = sprint(showerror, error)
    isempty(message) && (message = string(typeof(error)))
    if ncodeunits(message) > 4096
        buffer = IOBuffer()
        for character in message
            encoded = string(character)
            position(buffer) + ncodeunits(encoded) > 4096 && break
            write(buffer, encoded)
        end
        message = String(take!(buffer))
    end
    record = only(matches)
    return EngineeringFailure(
        Int(path_id),
        failure_substream(stage),
        seed_key_for_stage(record, stage),
        String(stage),
        FAILURE_CODES[stage],
        String(nameof(typeof(error))),
        message,
    )
end

function input_manifest_payload(inputs::QualifiedABMInputs)
    bounds = Dict{String, Any}()
    for name in sort!(collect(keys(inputs.dynamic_periods)))
        periods = inputs.dynamic_periods[name]
        bounds[name] = Dict{String, Any}(
            "start_period" => first(periods),
            "end_period" => last(periods),
            "observation_count" => length(periods),
        )
    end
    return Dict{String, Any}(
        "qualified_input_sha256" => inputs.qualified_input_sha256,
        "partition_sha256" => deepcopy(inputs.partition_sha256),
        "partition_members" => Dict{String, Any}(
            "structural" => copy(inputs.structural_members),
            "dynamic" => copy(inputs.dynamic_members),
            "state" => copy(inputs.state_members),
        ),
        "dynamic_period_bounds" => bounds,
    )
end

function guard_payload(guard::EngineeringExecutionGuard)
    return Dict{String, Any}(
        "serial_only" => true,
        "parallel" => guard.parallel,
        "julia_threads" => guard.julia_threads,
        "openblas_threads" => guard.openblas_threads,
        "process_global_rng_assumed" =>
            guard.process_global_rng_assumed,
        "seed_before_model_construction" =>
            guard.seed_before_model_construction,
        "seed_before_simulation" => guard.seed_before_simulation,
        "runner_implemented" => false,
        "ensemble_executed" => false,
    )
end

function failure_payload(failure::EngineeringFailure)
    return Dict{String, Any}(
        "path_id" => failure.path_id,
        "substream" => failure.substream,
        "seed_key_sha256" => failure.seed_key_sha256,
        "stage" => failure.stage,
        "code" => failure.code,
        "exception_type_sha256" =>
            sha256_hex(failure.exception_type),
        "message_sha256" => sha256_hex(failure.message),
    )
end

"""
    build_qualification_manifest(inputs, seed_plan, guard; failures=[])

Build a hash-only, no-output engineering manifest. The manifest contains no
raw state, truth, forecast, distribution, score, or inference result.
"""
function build_qualification_manifest(
        inputs::QualifiedABMInputs,
        seed_plan,
        guard::EngineeringExecutionGuard;
        failures = EngineeringFailure[],
        protocol_path::AbstractString = PROTOCOL_PATH,
    )
    protocol = validate_protocol(protocol_path)
    validate_partitions(inputs)
    inputs.protocol_sha256 == protocol.sha256 ||
        fail("qualified input was built under another protocol")
    validate_seed_plan(seed_plan, inputs)
    validate_execution_guard(guard)
    validate_failures(failures, seed_plan)
    return Dict{String, Any}(
        "schema_version" => MANIFEST_SCHEMA_VERSION,
        "contract_id" => CONTRACT_ID,
        "protocol_sha256" => protocol.sha256,
        "information_track" => INFORMATION_TRACK,
        "diagnostic_class" => DIAGNOSTIC_CLASS,
        "qualification_status" => "CONTRACT_ONLY_NOT_RUN_BLOCKED",
        "origin_period" => ORIGIN_PERIOD,
        "forecast_start_period" => FORECAST_START_PERIOD,
        "forecast_end_period" => FORECAST_END_PERIOD,
        "horizons" => copy(HORIZONS),
        "declarations" => deepcopy(DECLARATIONS),
        "blockers" => copy(BLOCKERS),
        "candidate_output_operators" =>
            deepcopy(CANDIDATE_OUTPUT_OPERATORS),
        "input" => input_manifest_payload(inputs),
        "execution" => guard_payload(guard),
        "path_seed_plan_sha256" =>
            path_seed_plan_sha256(seed_plan),
        "path_seed_plan" => path_seed_payload.(seed_plan),
        "failures" => failure_payload.(failures),
    )
end

"""
    validate_qualification_manifest(manifest, inputs, seed_plan, guard;
                                    failures=[])

Require exact equality with the reproducible no-output manifest. Unknown
fields, removed blockers, or changed declarations fail closed.
"""
function validate_qualification_manifest(
        manifest,
        inputs::QualifiedABMInputs,
        seed_plan,
        guard::EngineeringExecutionGuard;
        failures = EngineeringFailure[],
        protocol_path::AbstractString = PROTOCOL_PATH,
    )
    manifest isa AbstractDict ||
        fail("ABM engineering manifest must be a table")
    expected = build_qualification_manifest(
        inputs,
        seed_plan,
        guard;
        failures,
        protocol_path,
    )
    canonical(manifest) == canonical(expected) ||
        fail("ABM engineering manifest changed or contains unknown output")
    return manifest
end

"""
    refuse_prohibited_action(action)

Raise a contract error for scoring, inference, promotion, origin admission,
production registration, class-H use, truth access, or forecast emission.
"""
function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("unknown ABM engineering action $action")
    return fail(
        "ABM engineering contract forbids $(String(action)); " *
            "this qualification emits no forecasts or accuracy evidence",
    )
end

end
