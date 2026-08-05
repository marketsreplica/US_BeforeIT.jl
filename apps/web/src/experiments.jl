const EXPERIMENTS_DIR = joinpath(APP_ROOT, "experiments")
const EXPERIMENT_SCHEMA_VERSION = "paired-experiment.v1"
const CASHFLOW_COMPARISON_SCHEMA_VERSION = "cashflow-comparison.v1"

const _EXPERIMENT_METADATA_FIELDS = Set(
    [
        "run_id",
        "name",
        "description",
        "created_at",
        "parent_run_id",
        "experiment_id",
        "experiment_role",
        "provenance",
    ],
)

"""
    _experiment_canonical(value)

Return a deterministic, type-preserving representation of JSON-like data.
Dictionary order never affects the result and floating-point values are encoded
by their IEEE-754 bits. This is intentionally self-contained so experiment
digests do not depend on JSON object ordering or an external hashing package.
"""
function _experiment_canonical(value)
    if value === nothing || value === missing
        return "null"
    elseif value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa Integer
        return "int:$(value)"
    elseif value isa AbstractFloat
        isfinite(value) ||
            throw(ArgumentError("Experiment digests require finite numbers"))
        bits = reinterpret(UInt64, Float64(value))
        return "float:" * string(bits; base = 16, pad = 16)
    elseif value isa Real
        number = Float64(value)
        isfinite(number) ||
            throw(ArgumentError("Experiment digests require finite numbers"))
        bits = reinterpret(UInt64, number)
        return "float:" * string(bits; base = 16, pad = 16)
    elseif value isa AbstractString || value isa Symbol
        text = String(value)
        escaped = replace(
            text,
            '\\' => "\\\\",
            '"' => "\\\"",
            '\n' => "\\n",
            '\r' => "\\r",
            '\t' => "\\t",
        )
        return "string:\"$escaped\""
    elseif value isa NamedTuple
        return _experiment_canonical(Dict(pairs(value)))
    elseif value isa AbstractDict || value isa JSON3.Object
        entries = String[]
        for key in sort!(String.(collect(keys(value))))
            raw_value = if haskey(value, key)
                value[key]
            elseif haskey(value, Symbol(key))
                value[Symbol(key)]
            else
                error("Dictionary key disappeared during canonicalization")
            end
            push!(
                entries,
                _experiment_canonical(key) * ":" *
                    _experiment_canonical(raw_value),
            )
        end
        return "object:{" * join(entries, ",") * "}"
    elseif value isa Tuple || value isa AbstractVector ||
            value isa JSON3.Array
        return "array:[" *
            join((_experiment_canonical(item) for item in value), ",") *
            "]"
    end
    throw(
        ArgumentError(
            "Unsupported value in experiment digest: $(typeof(value))",
        ),
    )
end

function _experiment_fnv1a(value::AbstractString)
    hash = UInt64(0xcbf29ce484222325)
    for byte in codeunits(value)
        hash = (hash ⊻ UInt64(byte)) * UInt64(0x00000100000001b3)
    end
    return string(hash; base = 16, pad = 16)
end

"""
    _experiment_digest(value)

Compute the stable `fnv1a64` digest used in persisted compatibility evidence.
This digest is an identity/checking aid, not a cryptographic signature.
"""
_experiment_digest(value) =
    "fnv1a64:" * _experiment_fnv1a(_experiment_canonical(value))

function _experiment_dict(value)
    value === nothing && return Dict{String, Any}()
    (
        value isa AbstractDict || value isa JSON3.Object ||
            value isa NamedTuple
    ) ||
        throw(ApiError(400, "Expected a JSON object"))
    return _normalize_dict(value)
end

function _experiment_required_text(
        object::AbstractDict,
        key::AbstractString;
        maximum::Int = 240,
    )
    haskey(object, key) ||
        throw(ApiError(400, "$key is required"))
    value = _optional_text(object[key]; maximum)
    value === nothing && throw(ApiError(400, "$key must not be empty"))
    return value
end

function _experiment_uuid(value, label::AbstractString)
    text = strip(String(value))
    parsed = tryparse(UUID, text)
    parsed === nothing && throw(ApiError(400, "Invalid $label"))
    return string(parsed)
end

function _experiment_path(
        experiment_id::AbstractString;
        directory::AbstractString = EXPERIMENTS_DIR,
    )
    canonical_id = _experiment_uuid(experiment_id, "experiment_id")
    return joinpath(directory, "$canonical_id.json")
end

function _experiment_write_json(
        path::AbstractString,
        payload,
    )
    _ensure_dir(dirname(path))
    temporary = "$path.$(uuid4()).tmp"
    try
        open(temporary, "w") do io
            write(io, JSON3.write(_sanitize_for_json(payload)))
        end
        mv(temporary, path; force = true)
    finally
        isfile(temporary) && rm(temporary; force = true)
    end
    return path
end

"""
    get_experiment(experiment_id; directory = EXPERIMENTS_DIR)

Load one persisted first-class experiment. The UUID is canonicalized before a
path is constructed, preventing path traversal through experiment IDs.
"""
function get_experiment(
        experiment_id::AbstractString;
        directory::AbstractString = EXPERIMENTS_DIR,
    )
    path = _experiment_path(experiment_id; directory)
    isfile(path) || throw(ApiError(404, "Unknown experiment_id"))
    return _normalize_dict(JSON3.read(read(path, String)))
end

"""
    list_experiments(; directory = EXPERIMENTS_DIR)

Return persisted experiments newest first. Malformed non-UUID filenames are
ignored; malformed contents fail loudly when their canonical UUID file is read.
"""
function list_experiments(; directory::AbstractString = EXPERIMENTS_DIR)
    isdir(directory) || return Any[]
    experiments = Any[]
    for filename in readdir(directory)
        endswith(filename, ".json") || continue
        experiment_id = first(splitext(filename))
        tryparse(UUID, experiment_id) === nothing && continue
        push!(
            experiments,
            get_experiment(experiment_id; directory),
        )
    end
    sort!(
        experiments;
        by = experiment ->
        String(get(experiment, "created_at", "")),
        rev = true,
    )
    return experiments
end

function _experiment_sim_spec(
        raw,
        dataset_id::AbstractString,
        scenario::AbstractString,
    )
    sim = _experiment_dict(raw)
    defaults = Dict{String, Any}(
        "T" => _dataset_spec(dataset_id).default_horizon,
        "n_sims" => 16,
        "step_multithreading" => true,
        "base_seed" => 1234,
    )
    for (key, value) in sim
        defaults[key] = value
    end
    horizon = try
        Int(defaults["T"])
    catch
        throw(ApiError(400, "Simulation horizon T must be an integer"))
    end
    ensemble_size = try
        Int(defaults["n_sims"])
    catch
        throw(
            ApiError(400, "Simulation ensemble size must be an integer"),
        )
    end
    base_seed = try
        Int(defaults["base_seed"])
    catch
        throw(ApiError(400, "Simulation base_seed must be an integer"))
    end
    parallel_raw = defaults["step_multithreading"]
    parallel = if parallel_raw isa Bool
        parallel_raw
    elseif parallel_raw isa Number
        parallel_raw != 0
    else
        throw(ApiError(400, "step_multithreading must be Boolean"))
    end
    1 <= horizon <= 80 ||
        throw(ApiError(400, "T out of bounds", (T = horizon,)))
    1 <= ensemble_size <= 64 ||
        throw(
        ApiError(
            400,
            "n_sims out of bounds",
            (n_sims = ensemble_size,),
        ),
    )
    scenario != "unconditional" && horizon > 23 &&
        throw(
        ApiError(
            400,
            "Conditional scenario horizon exceeds 2031 Q4",
            (T = horizon, maximum = 23),
        ),
    )
    return Dict{String, Any}(
        "T" => horizon,
        "n_sims" => ensemble_size,
        "step_multithreading" => parallel,
        "base_seed" => base_seed,
    )
end

function _experiment_validate_overrides(
        dataset_id::AbstractString,
        raw,
    )
    overrides = _experiment_dict(raw)
    parameters =
        _experiment_dict(get(overrides, "parameters", nothing))
    initial_conditions =
        _experiment_dict(get(overrides, "initial_conditions", nothing))
    validate_overrides(dataset_id, parameters, initial_conditions)
    return Dict{String, Any}(
        "parameters" => parameters,
        "initial_conditions" => initial_conditions,
    )
end

function _experiment_sector_number(value)
    if value isa Integer
        return Int(value)
    elseif value isa Real && isinteger(value)
        return Int(value)
    end
    text = strip(String(value))
    startswith(text, "sector:") && (text = text[8:end])
    parsed = tryparse(Int, text)
    parsed === nothing &&
        throw(ApiError(400, "sector must be an integer or sector:<integer>"))
    return parsed
end

"""
    _experiment_normalize_intervention(raw, dataset_id, horizon)

Validate an additive experiment diff. Only `shock` and editable `overrides`
are accepted, so simulation length, seeds, scenario, and trace policy cannot be
silently altered by the intervention.

`sector_productivity` is represented truthfully as a permanent multiplier
applied at the first simulated quarter. The run shock normalizer remains the
capability gate, so builds without the corresponding model hook fail before
either run is launched.
"""
function _experiment_normalize_intervention(
        raw,
        dataset_id::AbstractString,
        horizon::Integer,
    )
    diff = _experiment_dict(raw)
    if haskey(diff, "type") && !haskey(diff, "shock")
        diff = Dict{String, Any}("shock" => diff)
    end
    allowed = Set(["shock", "overrides"])
    unknown = sort!(collect(setdiff(Set(keys(diff)), allowed)))
    isempty(unknown) ||
        throw(
        ApiError(
            400,
            "Intervention may change only shock or overrides",
            (unknown_fields = unknown,),
        ),
    )

    result = Dict{String, Any}()
    if haskey(diff, "shock")
        shock = _experiment_dict(diff["shock"])
        shock_type = lowercase(String(get(shock, "type", "none")))
        if shock_type == "sector_productivity"
            sector = _experiment_sector_number(
                get(shock, "sector", get(shock, "sector_id", "")),
            )
            sector_count = length(sector_metadata(dataset_id)["sectors"])
            1 <= sector <= sector_count ||
                throw(
                ApiError(
                    400,
                    "Sector is outside this dataset classification",
                    (sector = sector, sector_count = sector_count),
                ),
            )
            multiplier = _shock_number(shock, "multiplier", 1.0)
            0.0 < multiplier <= 10.0 ||
                throw(
                ApiError(
                    400,
                    "Productivity multiplier must be greater than 0 and at most 10",
                    (multiplier = multiplier,),
                ),
            )
            onset = try
                Int(get(shock, "onset_quarter", 1))
            catch
                throw(
                    ApiError(
                        400,
                        "Sector productivity onset_quarter must be an integer",
                    ),
                )
            end
            onset == 1 ||
                throw(
                ApiError(
                    400,
                    "Sector productivity starts in the first simulated quarter",
                ),
            )
            persistence =
                lowercase(String(get(shock, "persistence", "permanent")))
            persistence == "permanent" ||
                throw(
                ApiError(
                    400,
                    "Sector productivity is permanent in this release",
                ),
            )
            result["shock"] = Dict{String, Any}(
                "type" => "sector_productivity",
                "sector" => sector,
                "multiplier" => multiplier,
            )
        else
            result["shock"] = _normalize_shock_spec(shock, horizon)
        end
    end
    if haskey(diff, "overrides")
        result["overrides"] =
            _experiment_validate_overrides(dataset_id, diff["overrides"])
    end
    return result
end

function _experiment_merge!(
        destination::Dict{String, Any},
        patch::AbstractDict,
    )
    for (key, value) in patch
        if value isa AbstractDict &&
                get(destination, key, nothing) isa AbstractDict
            child = _normalize_dict(destination[key])
            destination[key] =
                _experiment_merge!(child, _normalize_dict(value))
        else
            destination[key] = deepcopy(value)
        end
    end
    return destination
end

function _experiment_base_request(raw)
    base = _experiment_dict(raw)
    dataset_id = _experiment_required_text(base, "dataset_id"; maximum = 80)
    _dataset_spec(dataset_id)
    scenario = _normalize_scenario(
        dataset_id,
        String(
            get(
                base,
                "scenario",
                _dataset_spec(dataset_id).default_scenario,
            ),
        ),
    )
    sim = _experiment_sim_spec(
        get(base, "sim", nothing),
        dataset_id,
        scenario,
    )
    trace = _normalize_trace_spec(get(base, "trace", nothing))
    trace_indices = Int.(collect(trace["realization_indices"]))
    isempty(trace_indices) &&
        throw(
        ApiError(
            400,
            "Paired cash-flow experiments require one representative trace",
        ),
    )
    all(index -> index <= sim["n_sims"], trace_indices) ||
        throw(
        ApiError(
            400,
            "A traced realization exceeds n_sims",
            (
                realization_indices = trace_indices,
                n_sims = sim["n_sims"],
            ),
        ),
    )
    length(trace_indices) <= 1 ||
        throw(
        ApiError(
            400,
            "Paired experiments currently support one representative trace",
        ),
    )
    overrides = _experiment_validate_overrides(
        dataset_id,
        get(base, "overrides", nothing),
    )
    shock = _normalize_shock_spec(
        get(base, "shock", Dict("type" => "none")),
        sim["T"],
    )
    return Dict{String, Any}(
        "dataset_id" => dataset_id,
        "scenario" => scenario,
        "sim" => sim,
        "overrides" => overrides,
        "shock" => shock,
        "trace" => trace,
        "name" => _optional_text(get(base, "name", nothing); maximum = 120),
        "description" =>
            _optional_text(get(base, "description", nothing); maximum = 2000),
    )
end

function _experiment_effective_spec(raw)
    spec = _experiment_dict(raw)
    effective = Dict{String, Any}(
        key => deepcopy(value) for (key, value) in spec if
            !(key in _EXPERIMENT_METADATA_FIELDS)
    )
    sim = _experiment_dict(get(effective, "sim", nothing))
    haskey(sim, "T") && (sim["T"] = Int(sim["T"]))
    haskey(sim, "n_sims") && (sim["n_sims"] = Int(sim["n_sims"]))
    haskey(sim, "base_seed") &&
        (sim["base_seed"] = Int(sim["base_seed"]))
    if haskey(sim, "step_multithreading")
        parallel = sim["step_multithreading"]
        sim["step_multithreading"] =
            parallel isa Bool ? parallel : parallel != 0
    end
    effective["sim"] = sim
    horizon = Int(get(sim, "T", 1))
    effective["shock"] = _normalize_shock_spec(
        get(effective, "shock", Dict("type" => "none")),
        horizon,
    )
    overrides = _normalize_dict(
        get(
            effective,
            "overrides",
            Dict(
                "parameters" => Dict{String, Any}(),
                "initial_conditions" => Dict{String, Any}(),
            ),
        ),
    )
    for group in ("parameters", "initial_conditions")
        values = _normalize_dict(
            get(overrides, group, Dict{String, Any}()),
        )
        for (key, value) in values
            value isa Real ||
                throw(
                ApiError(
                    400,
                    "Stored override must be numeric",
                    (group = group, key = key),
                ),
            )
            values[key] = Float64(value)
        end
        overrides[group] = values
    end
    effective["overrides"] = overrides
    effective["trace"] =
        _normalize_trace_spec(get(effective, "trace", nothing))
    return effective
end

function _experiment_diff!(
        result,
        before,
        after,
        path::AbstractString = "",
    )
    if before isa AbstractDict && after isa AbstractDict
        keys_union = sort!(
            collect(union(Set(keys(before)), Set(keys(after))));
            by = string,
        )
        for key in keys_union
            key_text = String(key)
            child_path =
                isempty(path) ? key_text : "$path.$key_text"
            before_present = haskey(before, key)
            after_present = haskey(after, key)
            if before_present && after_present
                _experiment_diff!(
                    result,
                    before[key],
                    after[key],
                    child_path,
                )
            elseif before_present
                push!(
                    result,
                    Dict(
                        "path" => child_path,
                        "before" => deepcopy(before[key]),
                        "after" => nothing,
                        "operation" => "remove",
                    ),
                )
            else
                push!(
                    result,
                    Dict(
                        "path" => child_path,
                        "before" => nothing,
                        "after" => deepcopy(after[key]),
                        "operation" => "add",
                    ),
                )
            end
        end
    elseif _experiment_canonical(before) != _experiment_canonical(after)
        push!(
            result,
            Dict(
                "path" => path,
                "before" => deepcopy(before),
                "after" => deepcopy(after),
                "operation" => "replace",
            ),
        )
    end
    return result
end

_experiment_spec_diff(before, after) =
    _experiment_diff!(Any[], before, after)

function _experiment_seed_schedule(sim::AbstractDict)
    base_seed = Int(sim["base_seed"])
    ensemble_size = Int(sim["n_sims"])
    return Dict{String, Any}(
        "strategy" => "base_seed_plus_realization_index",
        "base_seed" => base_seed,
        "realizations" => [
            Dict(
                    "realization_index" => index,
                    "seed" => base_seed + index,
                ) for index in 1:ensemble_size
        ],
    )
end

function _experiment_launch_run(
        spec::AbstractDict;
        experiment_id::AbstractString,
        role::AbstractString,
        parent_run_id = nothing,
        name = nothing,
        description = nothing,
        run_creator = create_run,
    )
    return run_creator(
        String(spec["dataset_id"]);
        name,
        description,
        parent_run_id,
        experiment_id,
        experiment_role = role,
        scenario = String(spec["scenario"]),
        sim = _normalize_dict(spec["sim"]),
        overrides = _normalize_dict(spec["overrides"]),
        shock = _normalize_dict(spec["shock"]),
        trace = _normalize_dict(spec["trace"]),
    )
end

function _experiment_spec_evidence(
        baseline_effective,
        treatment_effective,
    )
    diff = _experiment_spec_diff(
        baseline_effective,
        treatment_effective,
    )
    for change in diff
        change["classification"] = "intervention"
    end
    changed_paths = [String(change["path"]) for change in diff]
    non_intervention_fields_identical = all(
        path -> path == "shock" || startswith(path, "shock.") ||
            path == "overrides" || startswith(path, "overrides."),
        changed_paths,
    )
    return Dict{String, Any}(
        "base_spec_digest" =>
            _experiment_digest(baseline_effective),
        "treatment_spec_digest" =>
            _experiment_digest(treatment_effective),
        "changed_paths" => changed_paths,
        "realized_diff" => diff,
        "non_intervention_fields_identical" =>
            non_intervention_fields_identical,
        "seed_schedule_identical" =>
            _experiment_canonical(
            baseline_effective["sim"],
        ) ==
            _experiment_canonical(treatment_effective["sim"]),
        "trace_request_identical" =>
            _experiment_canonical(
            baseline_effective["trace"],
        ) ==
            _experiment_canonical(treatment_effective["trace"]),
    )
end

"""
    create_experiment(request; directory = EXPERIMENTS_DIR,
                      run_creator = create_run)

Create a baseline/treatment pair and persist its provenance. `request` accepts:

  * `base_spec` (required unless `baseline_run_id` is supplied),
  * `intervention_diff` (or `intervention`),
  * optional `baseline_run_id`, `name`, and `description`.

Both runs receive an identical horizon, ensemble, base seed, step policy, and
trace request. A reused baseline is never rewritten. The treatment always
records the baseline as its parent. Validation completes before a new baseline
is launched, including a capability-gated call to the run shock normalizer.
"""
function create_experiment(
        request;
        directory::AbstractString = EXPERIMENTS_DIR,
        run_creator = create_run,
    )
    body = _experiment_dict(request)
    name = _optional_text(
        get(body, "name", "Paired policy experiment");
        maximum = 120,
    )
    name === nothing && (name = "Paired policy experiment")
    description =
        _optional_text(get(body, "description", nothing); maximum = 2000)
    baseline_run_id = get(body, "baseline_run_id", nothing)
    baseline_run_id !== nothing && haskey(body, "base_spec") &&
        throw(
        ApiError(
            400,
            "Provide baseline_run_id or base_spec, not both",
        ),
    )
    base_request = if baseline_run_id === nothing
        haskey(body, "base_spec") ||
            throw(
            ApiError(
                400,
                "base_spec is required when baseline_run_id is absent",
            ),
        )
        _experiment_base_request(body["base_spec"])
    else
        canonical_run_id =
            _experiment_uuid(baseline_run_id, "baseline_run_id")
        baseline_path = _run_dir(canonical_run_id)
        isdir(baseline_path) ||
            throw(ApiError(404, "Unknown baseline_run_id"))
        stored = _normalize_dict(
            _read_json_file(joinpath(baseline_path, "spec.json")),
        )
        effective = _experiment_effective_spec(stored)
        dataset_id = String(effective["dataset_id"])
        Dict{String, Any}(
            "dataset_id" => dataset_id,
            "scenario" => effective["scenario"],
            "sim" => _normalize_dict(effective["sim"]),
            # Stored overrides are in model units; create_run accepts UI units.
            "overrides" =>
                _overrides_to_ui(dataset_id, effective["overrides"]),
            "shock" => _normalize_dict(effective["shock"]),
            "trace" => _normalize_dict(effective["trace"]),
            "name" => get(stored, "name", nothing),
            "description" => get(stored, "description", nothing),
        )
    end

    raw_intervention = get(
        body,
        "intervention_diff",
        get(body, "intervention", Dict{String, Any}()),
    )
    intervention = _experiment_normalize_intervention(
        raw_intervention,
        String(base_request["dataset_id"]),
        Int(base_request["sim"]["T"]),
    )
    treatment_request = deepcopy(base_request)
    _experiment_merge!(treatment_request, intervention)

    # Re-run all ordinary run validation against the merged treatment before
    # launching either new worker. This is also the model capability gate for
    # sector-targeted productivity.
    treatment_request = _experiment_base_request(treatment_request)

    experiment_id = string(uuid4())
    base_id = if baseline_run_id === nothing
        _experiment_launch_run(
            base_request;
            experiment_id,
            role = "baseline",
            name = "$name · baseline",
            description,
            run_creator,
        )
    else
        _experiment_uuid(baseline_run_id, "baseline_run_id")
    end
    treatment_id = _experiment_launch_run(
        treatment_request;
        experiment_id,
        role = "treatment",
        parent_run_id = base_id,
        name = "$name · treatment",
        description,
        run_creator,
    )
    String(base_id) != String(treatment_id) ||
        throw(
        ApiError(
            500,
            "Run creator returned the same ID for both experiment roles",
        ),
    )

    base_disk = _normalize_dict(
        _read_json_file(joinpath(_run_dir(base_id), "spec.json")),
    )
    treatment_disk = _normalize_dict(
        _read_json_file(joinpath(_run_dir(treatment_id), "spec.json")),
    )
    base_effective = _experiment_effective_spec(base_disk)
    treatment_effective = _experiment_effective_spec(treatment_disk)
    spec_evidence =
        _experiment_spec_evidence(base_effective, treatment_effective)
    sim = _normalize_dict(base_effective["sim"])
    experiment = Dict{String, Any}(
        "schema_version" => EXPERIMENT_SCHEMA_VERSION,
        "experiment_id" => experiment_id,
        "name" => name,
        "description" => description,
        "created_at" => _now_utc_iso(),
        "base_spec" => base_effective,
        "base_spec_digest" => spec_evidence["base_spec_digest"],
        "intervention_diff" => intervention,
        "realized_intervention_diff" => spec_evidence["realized_diff"],
        "treatment_spec_digest" =>
            spec_evidence["treatment_spec_digest"],
        "run_ids" => Dict(
            "baseline" => String(base_id),
            "treatment" => String(treatment_id),
        ),
        "baseline_reused" => baseline_run_id !== nothing,
        "roles" => Dict(
            String(base_id) => "baseline",
            String(treatment_id) => "treatment",
        ),
        "seed_schedule" => _experiment_seed_schedule(sim),
        "pairing" => Dict(
            "strategy" => "identical_seed_schedule",
            "initialization_policy" =>
                "same_dataset_spec_and_seed_not_cloned_state",
            "dynamic_rng_policy" => "global_rng_seed_per_realization",
            "claim_scope" => "controlled_simulation_contrast",
            "edge_level_causal_attribution" => false,
            "caveat" =>
                "Dynamic random-draw consumption can diverge after treatment; edge deltas are not unique causal paths.",
        ),
        "compatibility_evidence" => merge(
            spec_evidence,
            Dict(
                "dataset_id" => base_effective["dataset_id"],
                "scenario" => base_effective["scenario"],
                "horizon" => sim["T"],
                "ensemble_size" => sim["n_sims"],
                "base_seed" => sim["base_seed"],
                "step_multithreading" => sim["step_multithreading"],
                "trace_realization_indices" =>
                    base_effective["trace"]["realization_indices"],
                "trace_manifest_status" =>
                    "pending_run_completion",
            ),
        ),
    )
    _experiment_write_json(
        _experiment_path(experiment_id; directory),
        experiment,
    )
    return experiment
end

function _experiment_find_for_runs(
        run_a::AbstractString,
        run_b::AbstractString;
        directory::AbstractString = EXPERIMENTS_DIR,
    )
    targets = Set([String(run_a), String(run_b)])
    for experiment in list_experiments(; directory)
        run_ids = _experiment_dict(get(experiment, "run_ids", nothing))
        pair = Set(
            String[
                String(get(run_ids, "baseline", "")),
                String(get(run_ids, "treatment", "")),
            ],
        )
        pair == targets && return experiment
    end
    return nothing
end

function _experiment_check(name, left, right; required::Bool = true)
    passed = _experiment_canonical(left) == _experiment_canonical(right)
    return Dict{String, Any}(
        "name" => String(name),
        "passed" => passed,
        "required" => required,
        "run_a" => left,
        "run_b" => right,
    )
end

function _experiment_integrity_check(
        name,
        passed::Bool,
        evidence;
        required::Bool = true,
    )
    return Dict{String, Any}(
        "name" => String(name),
        "passed" => passed,
        "required" => required,
        "evidence" => evidence,
    )
end

function _experiment_truthy_capability(value)
    value isa Bool && return value
    value isa Number && return value != 0
    text = lowercase(strip(String(value)))
    return !(
        text in (
            "",
            "false",
            "none",
            "unavailable",
            "unsupported",
            "legacy_aggregate_only",
        )
    )
end

function _experiment_required_capabilities(
        level::AbstractString,
        layers,
    )
    capabilities = Set(["normalized_edges"])
    level in ("sector", "firm") && push!(capabilities, "sector_network")
    level == "firm" && push!(capabilities, "firm_network")
    normalized_layers = something(
        _cashflow_layer_filter_values(layers),
        Set{String}(),
    )
    for layer in normalized_layers
        if layer == "products"
            push!(capabilities, "business_counterparties")
        elseif layer in (
                "income",
                "fiscal",
                "interest",
                "credit",
                "deposits",
                "stocks",
            )
            push!(capabilities, "institution_flows")
        elseif layer in ("capacity", "capacity_counterfactual")
            push!(capabilities, "capacity_counterfactual")
        end
    end
    return sort!(collect(capabilities))
end

function _experiment_manifest_version(manifest, key)
    return String(
        get(
            manifest,
            key,
            key == "trace_schema_version" ?
                get(manifest, "schema_version", "") : "",
        ),
    )
end

function _experiment_role_digests(
        experiment,
        run_a::AbstractString,
        effective_a,
        run_b::AbstractString,
        effective_b,
    )
    experiment === nothing &&
        return Dict{String, Any}(
        "passed" => false,
        "reason" =>
            "No first-class experiment links these two runs.",
    )
    run_ids = _experiment_dict(experiment["run_ids"])
    base_id = String(run_ids["baseline"])
    treatment_id = String(run_ids["treatment"])
    base_id != treatment_id ||
        return Dict{String, Any}(
        "passed" => false,
        "reason" =>
            "An experiment must have distinct baseline and treatment runs.",
    )
    if Set([run_a, run_b]) != Set([base_id, treatment_id])
        return Dict{String, Any}(
            "passed" => false,
            "reason" =>
                "Experiment run IDs do not match the requested pair.",
        )
    end
    effective_base = run_a == base_id ? effective_a : effective_b
    effective_treatment =
        run_a == treatment_id ? effective_a : effective_b
    base_digest = _experiment_digest(effective_base)
    treatment_digest = _experiment_digest(effective_treatment)
    expected_base = String(experiment["base_spec_digest"])
    expected_treatment = String(experiment["treatment_spec_digest"])
    passed =
        base_digest == expected_base &&
        treatment_digest == expected_treatment
    return Dict{String, Any}(
        "passed" => passed,
        "experiment_id" => experiment["experiment_id"],
        "baseline_run_id" => base_id,
        "treatment_run_id" => treatment_id,
        "base_spec_digest" => base_digest,
        "expected_base_spec_digest" => expected_base,
        "treatment_spec_digest" => treatment_digest,
        "expected_treatment_spec_digest" => expected_treatment,
        "changed_paths" => [
            String(change["path"]) for change in
                get(experiment, "realized_intervention_diff", Any[])
        ],
        "reason" => passed ? nothing :
            "A run specification changed after the experiment declaration.",
    )
end

const _EXPERIMENT_REQUIRED_PROVENANCE_FIELDS = [
    "schema_version",
    "digest_algorithm",
    "canonicalization",
    "producer_source_digest",
    "model_source_digest",
    "trace_source_digest",
    "dataset_digest",
    "calibration_digest",
    "initialization_contract_digest",
    "initial_state_digest",
    "rng_policy",
    "execution_environment",
]

const _EXPERIMENT_REQUIRED_EXECUTION_ENVIRONMENT_FIELDS = [
    "julia_version",
    "thread_count",
    "architecture",
    "kernel",
    "word_size",
]

function _experiment_valid_execution_environment_field(
        field::AbstractString,
        value,
    )
    if field == "julia_version"
        value isa AbstractString || return false
        text = strip(String(value))
        isempty(text) && return false
        return try
            VersionNumber(text)
            true
        catch
            false
        end
    elseif field in ("architecture", "kernel")
        return value isa AbstractString &&
            !isempty(strip(String(value)))
    elseif field == "thread_count"
        return value isa Integer && !(value isa Bool) && value >= 1
    elseif field == "word_size"
        return value isa Integer &&
            !(value isa Bool) &&
            value in (32, 64)
    end
    return false
end

function _experiment_provenance_presence(provenance)
    normalized = _experiment_dict(provenance)
    missing = String[]
    invalid = String[]
    for field in _EXPERIMENT_REQUIRED_PROVENANCE_FIELDS
        if !haskey(normalized, field)
            push!(missing, field)
            continue
        end
        value = normalized[field]
        if value === nothing ||
                (value isa AbstractString && isempty(strip(String(value)))) ||
                (
                field in ("rng_policy", "execution_environment") &&
                    (!(value isa AbstractDict) || isempty(value))
            )
            push!(missing, field)
        end
    end
    if haskey(normalized, "execution_environment") &&
            normalized["execution_environment"] isa AbstractDict
        environment =
            _experiment_dict(normalized["execution_environment"])
        for field in _EXPERIMENT_REQUIRED_EXECUTION_ENVIRONMENT_FIELDS
            qualified = "execution_environment.$field"
            if !haskey(environment, field)
                push!(missing, qualified)
            elseif !_experiment_valid_execution_environment_field(
                    field,
                    environment[field],
                )
                push!(invalid, qualified)
            end
        end
    end
    return Dict{String, Any}(
        "present" => isempty(missing) && isempty(invalid),
        "missing_fields" => missing,
        "invalid_fields" => invalid,
        "provenance" => normalized,
    )
end

function _experiment_provenance_checks(
        spec_a,
        manifest_a,
        spec_b,
        manifest_b,
    )
    sources = Dict{String, Any}(
        "run_a_spec" => _experiment_provenance_presence(
            get(spec_a, "provenance", nothing),
        ),
        "run_a_manifest" => _experiment_provenance_presence(
            get(manifest_a, "provenance", nothing),
        ),
        "run_b_spec" => _experiment_provenance_presence(
            get(spec_b, "provenance", nothing),
        ),
        "run_b_manifest" => _experiment_provenance_presence(
            get(manifest_b, "provenance", nothing),
        ),
    )
    all_present = all(
        source -> Bool(source["present"]),
        values(sources),
    )
    presence = _experiment_integrity_check(
        "provenance_required_fields",
        all_present,
        Dict{String, Any}(
            "failure_code" =>
                all_present ? nothing : "provenance_missing",
            "required_fields" =>
                copy(_EXPERIMENT_REQUIRED_PROVENANCE_FIELDS),
            "sources" => Dict(
                name => Dict(
                        "present" => source["present"],
                        "missing_fields" => source["missing_fields"],
                        "invalid_fields" => source["invalid_fields"],
                    ) for (name, source) in sources
            ),
        ),
    )

    run_a_spec = sources["run_a_spec"]["provenance"]
    run_a_manifest = sources["run_a_manifest"]["provenance"]
    run_b_spec = sources["run_b_spec"]["provenance"]
    run_b_manifest = sources["run_b_manifest"]["provenance"]
    run_a_internal =
        all_present &&
        _experiment_canonical(run_a_spec) ==
        _experiment_canonical(run_a_manifest)
    run_b_internal =
        all_present &&
        _experiment_canonical(run_b_spec) ==
        _experiment_canonical(run_b_manifest)
    internal = _experiment_integrity_check(
        "provenance_spec_manifest_identity",
        run_a_internal && run_b_internal,
        Dict{String, Any}(
            "failure_code" =>
                run_a_internal && run_b_internal ? nothing :
                "provenance_spec_manifest_mismatch",
            "run_a" => Dict(
                "passed" => run_a_internal,
                "spec" => run_a_spec,
                "manifest" => run_a_manifest,
            ),
            "run_b" => Dict(
                "passed" => run_b_internal,
                "spec" => run_b_spec,
                "manifest" => run_b_manifest,
            ),
        ),
    )

    pair_equal =
        all_present &&
        _experiment_canonical(run_a_manifest) ==
        _experiment_canonical(run_b_manifest)
    pair = _experiment_integrity_check(
        "provenance_pair_identity",
        pair_equal,
        Dict{String, Any}(
            "failure_code" =>
                pair_equal ? nothing : "provenance_pair_mismatch",
            "run_a" => run_a_manifest,
            "run_b" => run_b_manifest,
        ),
    )
    return Any[presence, internal, pair]
end

"""
    _experiment_comparison_compatibility(run_a_path, run_b_path; ...)

Return structured, fail-closed evidence for paired comparison language. Exact
spec digests are checked against the first-class experiment, while dataset,
scenario, horizon, ensemble, seeds, step policy, trace realization, schemas, and
requested capabilities are checked independently for an auditable response.
Every level requires complete, internally consistent, and pair-identical
producer/model/trace, dataset/calibration, initialized-state, and RNG
provenance. Firm-level pairing additionally requires a stream-stable random
protocol; the current implicit-default-RNG policy does not satisfy that stronger
identity contract.
"""
function _experiment_comparison_compatibility(
        run_a_path::AbstractString,
        run_b_path::AbstractString;
        level::AbstractString = "sector",
        layers = nothing,
        experiment = nothing,
        quarter = nothing,
    )
    spec_a = _normalize_dict(
        _read_json_file(joinpath(run_a_path, "spec.json")),
    )
    spec_b = _normalize_dict(
        _read_json_file(joinpath(run_b_path, "spec.json")),
    )
    manifest_a = _normalize_dict(_cashflow_manifest(run_a_path))
    manifest_b = _normalize_dict(_cashflow_manifest(run_b_path))
    effective_a = _experiment_effective_spec(spec_a)
    effective_b = _experiment_effective_spec(spec_b)
    sim_a = _experiment_dict(effective_a["sim"])
    sim_b = _experiment_dict(effective_b["sim"])
    trace_a = _experiment_dict(effective_a["trace"])
    trace_b = _experiment_dict(effective_b["trace"])
    realization_a =
        _experiment_dict(get(manifest_a, "realization", nothing))
    realization_b =
        _experiment_dict(get(manifest_b, "realization", nothing))

    checks = Any[
        _experiment_check(
            "dataset_id",
            effective_a["dataset_id"],
            effective_b["dataset_id"],
        ),
        _experiment_check(
            "scenario",
            effective_a["scenario"],
            effective_b["scenario"],
        ),
        _experiment_check("horizon", sim_a["T"], sim_b["T"]),
        _experiment_check(
            "ensemble_size",
            sim_a["n_sims"],
            sim_b["n_sims"],
        ),
        _experiment_check(
            "base_seed",
            sim_a["base_seed"],
            sim_b["base_seed"],
        ),
        _experiment_check(
            "step_multithreading",
            sim_a["step_multithreading"],
            sim_b["step_multithreading"],
        ),
        _experiment_check(
            "trace_profile",
            trace_a["profile"],
            trace_b["profile"],
        ),
        _experiment_check(
            "trace_realization_request",
            trace_a["realization_indices"],
            trace_b["realization_indices"],
        ),
        _experiment_check(
            "traced_realization",
            get(realization_a, "index", nothing),
            get(realization_b, "index", nothing),
        ),
        _experiment_check(
            "traced_realization_seed",
            get(realization_a, "seed", nothing),
            get(realization_b, "seed", nothing),
        ),
        _experiment_check(
            "trace_schema_version",
            _experiment_manifest_version(
                manifest_a,
                "trace_schema_version",
            ),
            _experiment_manifest_version(
                manifest_b,
                "trace_schema_version",
            ),
        ),
        _experiment_check(
            "api_schema_version",
            _experiment_manifest_version(
                manifest_a,
                "api_schema_version",
            ),
            _experiment_manifest_version(
                manifest_b,
                "api_schema_version",
            ),
        ),
    ]
    append!(
        checks,
        _experiment_provenance_checks(
            spec_a,
            manifest_a,
            spec_b,
            manifest_b,
        ),
    )
    push!(
        checks,
        _experiment_integrity_check(
            "run_manifest_identity",
            String(get(manifest_a, "run_id", "")) ==
                basename(run_a_path) &&
                String(get(manifest_b, "run_id", "")) ==
                basename(run_b_path) &&
                String(get(manifest_a, "dataset_id", "")) ==
                String(effective_a["dataset_id"]) &&
                String(get(manifest_b, "dataset_id", "")) ==
                String(effective_b["dataset_id"]) &&
                String(get(manifest_a, "scenario", "")) ==
                String(effective_a["scenario"]) &&
                String(get(manifest_b, "scenario", "")) ==
                String(effective_b["scenario"]),
            Dict(
                "run_a" => Dict(
                    "path_id" => basename(run_a_path),
                    "manifest_run_id" => get(manifest_a, "run_id", nothing),
                    "spec_dataset_id" => effective_a["dataset_id"],
                    "manifest_dataset_id" =>
                        get(manifest_a, "dataset_id", nothing),
                    "spec_scenario" => effective_a["scenario"],
                    "manifest_scenario" =>
                        get(manifest_a, "scenario", nothing),
                ),
                "run_b" => Dict(
                    "path_id" => basename(run_b_path),
                    "manifest_run_id" => get(manifest_b, "run_id", nothing),
                    "spec_dataset_id" => effective_b["dataset_id"],
                    "manifest_dataset_id" =>
                        get(manifest_b, "dataset_id", nothing),
                    "spec_scenario" => effective_b["scenario"],
                    "manifest_scenario" =>
                        get(manifest_b, "scenario", nothing),
                ),
            ),
        ),
    )
    requested_a = Int.(collect(trace_a["realization_indices"]))
    requested_b = Int.(collect(trace_b["realization_indices"]))
    realization_index_a = get(realization_a, "index", nothing)
    realization_index_b = get(realization_b, "index", nothing)
    realization_seed_a = get(realization_a, "seed", nothing)
    realization_seed_b = get(realization_b, "seed", nothing)
    push!(
        checks,
        _experiment_integrity_check(
            "trace_manifest_integrity",
            length(requested_a) == 1 &&
                length(requested_b) == 1 &&
                realization_index_a == only(requested_a) &&
                realization_index_b == only(requested_b) &&
                get(realization_a, "ensemble_size", nothing) ==
                sim_a["n_sims"] &&
                get(realization_b, "ensemble_size", nothing) ==
                sim_b["n_sims"] &&
                realization_seed_a ==
                sim_a["base_seed"] + realization_index_a &&
                realization_seed_b ==
                sim_b["base_seed"] + realization_index_b &&
                String(get(manifest_a, "trace_profile", "")) ==
                String(trace_a["profile"]) &&
                String(get(manifest_b, "trace_profile", "")) ==
                String(trace_b["profile"]),
            Dict(
                "run_a" => Dict(
                    "request" => requested_a,
                    "manifest" => realization_a,
                    "manifest_trace_profile" =>
                        get(manifest_a, "trace_profile", nothing),
                ),
                "run_b" => Dict(
                    "request" => requested_b,
                    "manifest" => realization_b,
                    "manifest_trace_profile" =>
                        get(manifest_b, "trace_profile", nothing),
                ),
            ),
        ),
    )
    if quarter !== nothing
        quarter_index = Int(quarter)
        period_a = _experiment_period(manifest_a, quarter_index)
        period_b = _experiment_period(manifest_b, quarter_index)
        push!(
            checks,
            _experiment_integrity_check(
                "calendar_period",
                !isempty(period_a) && period_a == period_b,
                Dict(
                    "quarter_index" => quarter_index,
                    "run_a" => period_a,
                    "run_b" => period_b,
                ),
            ),
        )
    end

    capabilities_a =
        _experiment_dict(get(manifest_a, "capabilities", nothing))
    capabilities_b =
        _experiment_dict(get(manifest_b, "capabilities", nothing))
    for capability in _experiment_required_capabilities(level, layers)
        value_a = get(capabilities_a, capability, false)
        value_b = get(capabilities_b, capability, false)
        push!(
            checks,
            Dict{String, Any}(
                "name" => "capability:$capability",
                "passed" =>
                    _experiment_truthy_capability(value_a) &&
                    _experiment_truthy_capability(value_b) &&
                    _experiment_canonical(value_a) ==
                    _experiment_canonical(value_b),
                "required" => true,
                "run_a" => value_a,
                "run_b" => value_b,
            ),
        )
    end

    role_evidence = _experiment_role_digests(
        experiment,
        basename(run_a_path),
        effective_a,
        basename(run_b_path),
        effective_b,
    )
    push!(
        checks,
        Dict{String, Any}(
            "name" => "declared_intervention_only",
            "passed" => Bool(role_evidence["passed"]),
            "required" => true,
            "evidence" => role_evidence,
        ),
    )
    if experiment !== nothing
        experiment_id = String(experiment["experiment_id"])
        experiment_runs = _experiment_dict(experiment["run_ids"])
        baseline_id = String(experiment_runs["baseline"])
        treatment_id = String(experiment_runs["treatment"])
        baseline_spec =
            basename(run_a_path) == baseline_id ? spec_a : spec_b
        treatment_spec =
            basename(run_a_path) == treatment_id ? spec_a : spec_b
        baseline_reused = Bool(
            get(experiment, "baseline_reused", false),
        )
        baseline_link_id = get(baseline_spec, "experiment_id", nothing)
        baseline_link_role =
            get(baseline_spec, "experiment_role", nothing)
        baseline_link_ok = if baseline_reused
            (
                baseline_link_id === nothing ||
                    String(baseline_link_id) == experiment_id
            ) &&
                (
                baseline_link_role === nothing ||
                    String(baseline_link_role) == "baseline"
            )
        else
            baseline_link_id !== nothing &&
                String(baseline_link_id) == experiment_id &&
                baseline_link_role !== nothing &&
                String(baseline_link_role) == "baseline"
        end
        treatment_link_ok =
            get(treatment_spec, "experiment_id", nothing) !== nothing &&
            String(treatment_spec["experiment_id"]) == experiment_id &&
            get(treatment_spec, "experiment_role", nothing) !== nothing &&
            String(treatment_spec["experiment_role"]) == "treatment" &&
            get(treatment_spec, "parent_run_id", nothing) !== nothing &&
            String(treatment_spec["parent_run_id"]) == baseline_id
        push!(
            checks,
            _experiment_integrity_check(
                "run_experiment_linkage",
                baseline_link_ok && treatment_link_ok,
                Dict(
                    "baseline_reused" => baseline_reused,
                    "baseline" => Dict(
                        "run_id" => baseline_id,
                        "experiment_id" => baseline_link_id,
                        "role" => baseline_link_role,
                    ),
                    "treatment" => Dict(
                        "run_id" => treatment_id,
                        "experiment_id" =>
                            get(treatment_spec, "experiment_id", nothing),
                        "role" =>
                            get(treatment_spec, "experiment_role", nothing),
                        "parent_run_id" =>
                            get(treatment_spec, "parent_run_id", nothing),
                    ),
                ),
            ),
        )
    end

    if level == "firm"
        provenance_a =
            _experiment_dict(get(manifest_a, "provenance", nothing))
        provenance_b =
            _experiment_dict(get(manifest_b, "provenance", nothing))
        initialization_a =
            get(provenance_a, "initial_state_digest", nothing)
        initialization_b =
            get(provenance_b, "initial_state_digest", nothing)
        rng_a =
            _experiment_dict(get(provenance_a, "rng_policy", nothing))
        rng_b =
            _experiment_dict(get(provenance_b, "rng_policy", nothing))
        stream_stable_a =
            Bool(get(rng_a, "stream_stable_common_random_numbers", false))
        stream_stable_b =
            Bool(get(rng_b, "stream_stable_common_random_numbers", false))
        push!(
            checks,
            Dict{String, Any}(
                "name" => "firm_identity_protocol",
                "passed" =>
                    initialization_a !== nothing &&
                    initialization_b !== nothing &&
                    initialization_a == initialization_b &&
                    _experiment_canonical(rng_a) ==
                    _experiment_canonical(rng_b) &&
                    stream_stable_a &&
                    stream_stable_b,
                "required" => true,
                "run_a" => Dict(
                    "initial_state_digest" => initialization_a,
                    "rng_policy" => rng_a,
                    "stream_stable_common_random_numbers" =>
                        stream_stable_a,
                ),
                "run_b" => Dict(
                    "initial_state_digest" => initialization_b,
                    "rng_policy" => rng_b,
                    "stream_stable_common_random_numbers" =>
                        stream_stable_b,
                ),
            ),
        )
    end

    required_checks = [
        check for check in checks if Bool(get(check, "required", true))
    ]
    compatible = all(
        check -> Bool(get(check, "passed", false)),
        required_checks,
    )
    reasons = String[]
    for check in required_checks
        Bool(get(check, "passed", false)) && continue
        push!(reasons, "Failed compatibility check: $(check["name"])")
    end
    return Dict{String, Any}(
        "compatible" => compatible,
        "paired" => compatible,
        "eligible" => compatible,
        "paired_eligible" => compatible,
        "paired_treatment_language_allowed" => compatible,
        "comparison_mode" =>
            compatible ? "paired_controlled_contrast" :
            "descriptive_difference",
        "claim_scope" =>
            compatible ? "controlled_simulation_contrast" :
            "descriptive_run_difference",
        "edge_level_causal_attribution" => false,
        "checks" => checks,
        "reasons" => reasons,
        "experiment" => role_evidence,
        "rng_caveat" =>
            "The current model reseeds Julia's implicit default RNG per realization. Identical seeds match initialization schedules, but do not create mechanism-specific or stream-stable common random numbers after treatment paths diverge.",
    )
end

function _experiment_run_complete(run_path::AbstractString)
    status = _read_json_file(joinpath(run_path, "status.json"))
    status === nothing && throw(ApiError(404, "Missing run status"))
    state = lowercase(String(get(status, :state, "unknown")))
    state in ("done", "complete", "completed") ||
        throw(
        ApiError(
            409,
            "Cash-flow comparison requires completed runs",
            (run_id = basename(run_path), state = state),
        ),
    )
    return _normalize_dict(status)
end

const _EXPERIMENT_EDGE_IDENTITY_FIELDS = [
    "canonical_source",
    "canonical_target",
    "level",
    "layer",
    "economic_layer",
    "market",
    "purpose",
    "measure_kind",
    "recognition",
    "units",
    "direction_semantics",
    "valuation_basis",
    "evidence_basis",
    "aggregation",
    "timing",
    "realization_scope",
    "rollup_id",
    "component_id",
    "parent_ids",
    "summation_role",
]

const EXPERIMENT_INDEX_CACHE_MAX_ENTRIES = 4
const EXPERIMENT_JOIN_CACHE_MAX_ENTRIES = 2
const EXPERIMENT_SCOPE_CACHE_MAX_ENTRIES = 6
const _EXPERIMENT_CACHE_LOCK = ReentrantLock()
const _EXPERIMENT_INDEX_CACHE = Dict{String, Any}()
const _EXPERIMENT_JOIN_CACHE = Dict{String, Any}()
const _EXPERIMENT_SCOPE_CACHE = Dict{String, Any}()
const _EXPERIMENT_VALIDATED_PAIRS = Dict{String, UInt64}()
const _EXPERIMENT_CACHE_CLOCK = Ref{UInt64}(0)

function _experiment_index_edges(edges, run_id::AbstractString)
    index = Dict{String, Any}()
    for raw_edge in edges
        edge = raw_edge
        edge_id = String(get(edge, "id", ""))
        isempty(edge_id) &&
            throw(
            ApiError(
                409,
                "Cash-flow edge lacks a stable semantic ID",
                (run_id = run_id,),
            ),
        )
        if haskey(index, edge_id)
            existing = _normalize_dict(index[edge_id])
            edge = _normalize_dict(edge)
            for field in _EXPERIMENT_EDGE_IDENTITY_FIELDS
                _experiment_canonical(get(existing, field, nothing)) ==
                    _experiment_canonical(get(edge, field, nothing)) ||
                    throw(
                    ApiError(
                        409,
                        "Stable edge ID has conflicting semantics",
                        (run_id = run_id, edge_id = edge_id, field = field),
                    ),
                )
            end
            existing["signed_value"] =
                _cashflow_edge_value(existing) +
                _cashflow_edge_value(edge)
            existing["amount"] = abs(existing["signed_value"])
            canonical_source = String(
                get(existing, "canonical_source", get(existing, "source", "")),
            )
            canonical_target = String(
                get(existing, "canonical_target", get(existing, "target", "")),
            )
            existing["source"] =
                existing["signed_value"] >= 0 ?
                canonical_source : canonical_target
            existing["target"] =
                existing["signed_value"] >= 0 ?
                canonical_target : canonical_source
            existing["display_source"] = existing["source"]
            existing["display_target"] = existing["target"]
            existing["quantity"] =
                Float64(get(existing, "quantity", 0.0)) +
                Float64(get(edge, "quantity", 0.0))
            existing["match_count"] =
                Int(get(existing, "match_count", 0)) +
                Int(get(edge, "match_count", 0))
            index[edge_id] = existing
        else
            # JSON3.Object values are immutable views over the cached decoded
            # tape. Keep the view instead of allocating a mutable Dict for
            # every unique edge; only the exceptional duplicate-ID aggregation
            # path above needs a copy.
            index[edge_id] = edge
        end
    end
    return index
end

function _experiment_cache_access!()
    _EXPERIMENT_CACHE_CLOCK[] += 1
    return _EXPERIMENT_CACHE_CLOCK[]
end

function _experiment_evict_lru!(cache, maximum::Integer)
    while length(cache) > maximum
        victim = first(
            sort!(
                collect(keys(cache));
                by = key -> cache[key].access,
            ),
        )
        delete!(cache, victim)
    end
    return nothing
end

function _experiment_cached_index(
        run_path::AbstractString,
        run_id::AbstractString,
        quarter::Integer,
    )
    trace_path = joinpath(run_path, "cashflow-$(Int(quarter)).jld2")
    signature = _cashflow_artifact_signature(trace_path)
    cache_key = abspath(trace_path)
    return lock(_EXPERIMENT_CACHE_LOCK) do
        access = _experiment_cache_access!()
        cached = get(_EXPERIMENT_INDEX_CACHE, cache_key, nothing)
        if cached !== nothing && cached.signature == signature
            _EXPERIMENT_INDEX_CACHE[cache_key] = merge(cached, (; access))
            return cached.index, cached.edge_count, signature
        end
        edges = _cashflow_complete_edges(run_path; quarter = Int(quarter))
        index = _experiment_index_edges(edges, run_id)
        entry = (; signature, index, edge_count = length(edges), access)
        _EXPERIMENT_INDEX_CACHE[cache_key] = entry
        _experiment_evict_lru!(
            _EXPERIMENT_INDEX_CACHE,
            EXPERIMENT_INDEX_CACHE_MAX_ENTRIES,
        )
        return index, length(edges), signature
    end
end

function _experiment_pair_cache_key(
        run_a::AbstractString,
        signature_a,
        run_b::AbstractString,
        signature_b,
        atol::Real,
        rtol::Real,
        paired::Bool,
    )
    return join(
        (
            String(run_a),
            String(signature_a.path),
            string(signature_a.size),
            string(signature_a.mtime),
            String(run_b),
            String(signature_b.path),
            string(signature_b.size),
            string(signature_b.mtime),
            repr(Float64(atol)),
            repr(Float64(rtol)),
            string(paired),
        ),
        "|",
    )
end

function _experiment_cached_join(
        index_a,
        run_a::AbstractString,
        signature_a,
        index_b,
        run_b::AbstractString,
        signature_b;
        atol::Real,
        rtol::Real,
        paired::Bool,
    )
    cache_key = _experiment_pair_cache_key(
        run_a,
        signature_a,
        run_b,
        signature_b,
        atol,
        rtol,
        paired,
    )
    return lock(_EXPERIMENT_CACHE_LOCK) do
        access = _experiment_cache_access!()
        cached = get(_EXPERIMENT_JOIN_CACHE, cache_key, nothing)
        if cached !== nothing
            _EXPERIMENT_JOIN_CACHE[cache_key] = merge(cached, (; access))
            return cached.edge_ids, cached.semantic_count,
                cached.comparison_row_count, cache_key
        end
        validation_key = join(
            sort!(
                [
                    "$(run_a):$(signature_a.path):$(signature_a.size):$(signature_a.mtime)",
                    "$(run_b):$(signature_b.path):$(signature_b.size):$(signature_b.mtime)",
                ],
            ),
            "|",
        )
        if !haskey(_EXPERIMENT_VALIDATED_PAIRS, validation_key)
            _experiment_validate_cross_edge_identity!(index_a, index_b)
            _EXPERIMENT_VALIDATED_PAIRS[validation_key] = access
            if length(_EXPERIMENT_VALIDATED_PAIRS) > 8
                oldest = first(
                    sort!(
                        collect(keys(_EXPERIMENT_VALIDATED_PAIRS));
                        by = key -> _EXPERIMENT_VALIDATED_PAIRS[key],
                    ),
                )
                delete!(_EXPERIMENT_VALIDATED_PAIRS, oldest)
            end
        else
            _EXPERIMENT_VALIDATED_PAIRS[validation_key] = access
        end
        edge_ids = sort!(
            collect(union(Set(keys(index_a)), Set(keys(index_b)))),
        )
        comparison_row_count = length(edge_ids)
        for edge_id in edge_ids
            edge_a = get(index_a, edge_id, nothing)
            edge_b = get(index_b, edge_id, nothing)
            edge_a === nothing && continue
            edge_b === nothing && continue
            value_a = _cashflow_edge_value(edge_a)
            value_b = _cashflow_edge_value(edge_b)
            zero_a = _experiment_values_close(value_a, 0.0; atol, rtol)
            zero_b = _experiment_values_close(value_b, 0.0; atol, rtol)
            !zero_a && !zero_b && signbit(value_a) != signbit(value_b) &&
                (comparison_row_count += 1)
        end
        _EXPERIMENT_JOIN_CACHE[cache_key] =
            (;
            edge_ids,
            semantic_count = length(edge_ids),
            comparison_row_count,
            access,
        )
        _experiment_evict_lru!(
            _EXPERIMENT_JOIN_CACHE,
            EXPERIMENT_JOIN_CACHE_MAX_ENTRIES,
        )
        return edge_ids, length(edge_ids), comparison_row_count, cache_key
    end
end

function _experiment_clear_caches!()
    lock(_EXPERIMENT_CACHE_LOCK) do
        empty!(_EXPERIMENT_INDEX_CACHE)
        empty!(_EXPERIMENT_JOIN_CACHE)
        empty!(_EXPERIMENT_SCOPE_CACHE)
        empty!(_EXPERIMENT_VALIDATED_PAIRS)
        _EXPERIMENT_CACHE_CLOCK[] = 0
    end
    return nothing
end

function _experiment_validate_cross_edge_identity!(
        index_a,
        index_b,
    )
    for edge_id in intersect(Set(keys(index_a)), Set(keys(index_b)))
        edge_a = index_a[edge_id]
        edge_b = index_b[edge_id]
        for field in _EXPERIMENT_EDGE_IDENTITY_FIELDS
            _experiment_canonical(get(edge_a, field, nothing)) ==
                _experiment_canonical(get(edge_b, field, nothing)) ||
                throw(
                ApiError(
                    409,
                    "Stable edge ID changed economic semantics between runs",
                    (edge_id = edge_id, field = field),
                ),
            )
        end
    end
    return nothing
end

function _experiment_values_close(
        left::Real,
        right::Real;
        atol::Real,
        rtol::Real,
    )
    return isapprox(
        Float64(left),
        Float64(right);
        atol = Float64(atol),
        rtol = Float64(rtol),
    )
end

function _experiment_display_endpoints(
        edge,
        canonical_source::AbstractString,
        canonical_target::AbstractString,
        canonical_value::Real,
    )
    fallback_source =
        canonical_value >= 0 ? canonical_source : canonical_target
    fallback_target =
        canonical_value >= 0 ? canonical_target : canonical_source
    source = String(
        get(
            edge,
            "display_source",
            get(edge, "source", fallback_source),
        ),
    )
    target = String(
        get(
            edge,
            "display_target",
            get(edge, "target", fallback_target),
        ),
    )
    return source, target
end

function _experiment_delta_class(
        amount_a::Real,
        amount_b::Real;
        atol::Real,
        rtol::Real,
    )
    zero_a = _experiment_values_close(amount_a, 0.0; atol, rtol)
    zero_b = _experiment_values_close(amount_b, 0.0; atol, rtol)
    unchanged =
        _experiment_values_close(amount_a, amount_b; atol, rtol)
    delta = Float64(amount_b) - Float64(amount_a)
    return if unchanged
        "unchanged"
    elseif zero_a && !zero_b
        "added"
    elseif !zero_a && zero_b
        "removed"
    elseif delta > 0
        "increased"
    else
        "decreased"
    end
end

function _experiment_comparison_row(
        edge_id::AbstractString,
        template,
        direction_edge;
        row_suffix::AbstractString,
        canonical_value_a::Real,
        canonical_value_b::Real,
        amount_a::Real,
        amount_b::Real,
        atol::Real,
        rtol::Real,
        paired::Bool,
        direction_reversed::Bool = false,
        reversal_leg = nothing,
        direction_basis::AbstractString = "shared_recorded_direction",
        present_in_a::Bool = true,
        present_in_b::Bool = true,
        semantic_present_in_a::Bool = true,
        semantic_present_in_b::Bool = true,
    )
    result = _normalize_dict(template)
    canonical_source =
        String(get(result, "canonical_source", get(result, "source", "")))
    canonical_target =
        String(get(result, "canonical_target", get(result, "target", "")))
    direction_value =
        present_in_b ? canonical_value_b : canonical_value_a
    source, target = _experiment_display_endpoints(
        direction_edge,
        canonical_source,
        canonical_target,
        direction_value,
    )
    magnitude_a = Float64(amount_a)
    magnitude_b = Float64(amount_b)
    magnitude_delta = magnitude_b - magnitude_a
    canonical_delta =
        Float64(canonical_value_b) - Float64(canonical_value_a)
    change = _experiment_delta_class(
        magnitude_a,
        magnitude_b;
        atol,
        rtol,
    )
    row_id = "delta:$(edge_id):$(row_suffix)"

    # A comparison row is directed exactly as the payment/flow it describes.
    # `delta` is therefore the change in non-negative magnitude along that
    # displayed direction. The signed change in the edge's canonical
    # source→target coordinate is retained separately.
    result["id"] = row_id
    result["stable_id"] = row_id
    result["comparison_edge_id"] = row_id
    result["semantic_id"] = String(edge_id)
    result["original_edge_id"] = String(edge_id)
    result["canonical_source"] = canonical_source
    result["canonical_target"] = canonical_target
    result["source"] = source
    result["target"] = target
    result["display_source"] = source
    result["display_target"] = target
    result["value_a"] = Float64(canonical_value_a)
    result["value_b"] = Float64(canonical_value_b)
    result["canonical_value_a"] = Float64(canonical_value_a)
    result["canonical_value_b"] = Float64(canonical_value_b)
    result["canonical_signed_delta"] = canonical_delta
    result["canonical_delta"] = canonical_delta
    result["amount_a"] = magnitude_a
    result["amount_b"] = magnitude_b
    result["display_magnitude_a"] = magnitude_a
    result["display_magnitude_b"] = magnitude_b
    result["magnitude_delta"] = magnitude_delta
    result["display_magnitude_delta"] = magnitude_delta
    result["delta"] = magnitude_delta
    result["signed_value"] = magnitude_delta
    result["comparison_signed_value"] = magnitude_delta
    result["amount"] = abs(magnitude_delta)
    result["abs_delta"] = abs(magnitude_delta)
    result["delta_sign"] =
        magnitude_delta > 0 ? "positive" :
        magnitude_delta < 0 ? "negative" : "zero"
    result["canonical_delta_sign"] =
        canonical_delta > 0 ? "positive" :
        canonical_delta < 0 ? "negative" : "zero"
    result["change"] = change
    result["delta_class"] = change
    result["delta_basis"] = "display_direction_magnitude"
    result["direction_basis"] = String(direction_basis)
    result["direction_reversed"] = direction_reversed
    result["direction_reversal_split"] = direction_reversed
    result["reversal_group_id"] =
        direction_reversed ? "reversal:$(edge_id)" : nothing
    result["reversal_leg"] = reversal_leg
    result["present_in_a"] = present_in_a
    result["present_in_b"] = present_in_b
    result["semantic_present_in_a"] = semantic_present_in_a
    result["semantic_present_in_b"] = semantic_present_in_b
    result["comparison_direction"] = "run_a_to_run_b"
    result["comparison_evidence"] =
        paired ? "paired_simulation_difference" :
        "descriptive_run_difference"
    result["edge_level_causal_attribution"] = false
    result["measure_domain_id"] = _experiment_delta_domain(result)
    return result
end

function _experiment_delta_edges(
        edge_id::AbstractString,
        edge_a,
        edge_b;
        atol::Real,
        rtol::Real,
        paired::Bool,
    )
    template = edge_b === nothing ? edge_a : edge_b
    value_a = edge_a === nothing ? 0.0 : _cashflow_edge_value(edge_a)
    value_b = edge_b === nothing ? 0.0 : _cashflow_edge_value(edge_b)
    zero_a = _experiment_values_close(value_a, 0.0; atol, rtol)
    zero_b = _experiment_values_close(value_b, 0.0; atol, rtol)
    semantic_present_in_a = edge_a !== nothing
    semantic_present_in_b = edge_b !== nothing
    reversed =
        !zero_a && !zero_b && signbit(value_a) != signbit(value_b)

    if reversed
        # A sign reversal changes the recorded payment direction. It cannot be
        # represented truthfully by one arrow, so emit two independently
        # addressable rows: removal of A's direction and addition of B's.
        removed = _experiment_comparison_row(
            edge_id,
            edge_a,
            edge_a;
            row_suffix = "removed-run-a-direction",
            canonical_value_a = value_a,
            canonical_value_b = 0.0,
            amount_a = abs(value_a),
            amount_b = 0.0,
            atol,
            rtol,
            paired,
            direction_reversed = true,
            reversal_leg = "removed_run_a_direction",
            direction_basis = "run_a_recorded_direction",
            present_in_a = true,
            present_in_b = false,
            semantic_present_in_a,
            semantic_present_in_b,
        )
        added = _experiment_comparison_row(
            edge_id,
            edge_b,
            edge_b;
            row_suffix = "added-run-b-direction",
            canonical_value_a = 0.0,
            canonical_value_b = value_b,
            amount_a = 0.0,
            amount_b = abs(value_b),
            atol,
            rtol,
            paired,
            direction_reversed = true,
            reversal_leg = "added_run_b_direction",
            direction_basis = "run_b_recorded_direction",
            present_in_a = false,
            present_in_b = true,
            semantic_present_in_a,
            semantic_present_in_b,
        )
        return Any[removed, added]
    end

    direction_edge = if zero_b && !zero_a
        edge_a
    else
        edge_b === nothing ? edge_a : edge_b
    end
    direction_basis = if zero_a && !zero_b
        "run_b_recorded_direction"
    elseif !zero_a && zero_b
        "run_a_recorded_direction"
    else
        "shared_recorded_direction"
    end
    return Any[
        _experiment_comparison_row(
            edge_id,
            template,
            direction_edge;
            row_suffix = "shared-direction",
            canonical_value_a = value_a,
            canonical_value_b = value_b,
            amount_a = abs(value_a),
            amount_b = abs(value_b),
            atol,
            rtol,
            paired,
            direction_basis,
            present_in_a = !zero_a,
            present_in_b = !zero_b,
            semantic_present_in_a,
            semantic_present_in_b,
        ),
    ]
end

function _experiment_delta_domain(edge)
    explicit = get(edge, "measure_domain_id", nothing)
    explicit !== nothing && !isempty(String(explicit)) &&
        return String(explicit)
    return _cashflow_edge_domain(edge)
end

function _experiment_shared_scale_domains(manifest_a, manifest_b)
    domains_a = _experiment_dict(get(manifest_a, "scale_domains", nothing))
    domains_b = _experiment_dict(get(manifest_b, "scale_domains", nothing))
    result = Dict{String, Any}()
    for domain_id in sort!(
            collect(union(Set(keys(domains_a)), Set(keys(domains_b)))),
        )
        domain_a = _experiment_dict(get(domains_a, domain_id, nothing))
        domain_b = _experiment_dict(get(domains_b, domain_id, nothing))
        max_a = Float64(get(domain_a, "max", 0.0))
        max_b = Float64(get(domain_b, "max", 0.0))
        result[domain_id] = Dict{String, Any}(
            "min" => 0.0,
            "max" => max(max_a, max_b),
            "mapping" => "sqrt",
            "stable" => !isempty(domain_a) && !isempty(domain_b),
            "shared" => true,
            "scope" => "run_wide_max_across_a_and_b",
            "run_a_max" => max_a,
            "run_b_max" => max_b,
        )
    end
    return result
end

function _experiment_sort_deltas!(edges)
    sort!(
        edges;
        by = edge -> (
            -Float64(get(edge, "abs_delta", 0.0)),
            String(edge["id"]),
        ),
    )
    return edges
end

function _experiment_select_coverage(edges, coverage::Real)
    0 < coverage <= 1 ||
        throw(ApiError(400, "coverage must be greater than 0 and at most 1"))
    coverage >= 1 && return copy(edges)
    by_domain = Dict{String, Vector{Any}}()
    for edge in edges
        push!(
            get!(
                by_domain,
                _experiment_delta_domain(edge),
                Any[],
            ),
            edge,
        )
    end
    selected = Set{String}()
    for domain_edges in values(by_domain)
        _experiment_sort_deltas!(domain_edges)
        total = sum(
            Float64(get(edge, "abs_delta", 0.0)) for
                edge in domain_edges
            ;
            init = 0.0,
        )
        if total <= 0
            foreach(
                edge -> push!(selected, String(edge["id"])),
                domain_edges,
            )
            continue
        end
        threshold = Float64(coverage) * total
        cumulative = 0.0
        for edge in domain_edges
            cumulative >= threshold && break
            push!(selected, String(edge["id"]))
            cumulative += Float64(get(edge, "abs_delta", 0.0))
        end
    end
    return [edge for edge in edges if String(edge["id"]) in selected]
end

function _experiment_delta_coverage(
        joined,
        matching,
        selected,
        returned,
        count_a::Integer,
        count_b::Integer,
        complete_semantic_relationship_count::Integer,
        complete_comparison_row_count::Integer,
    )
    domains = sort!(
        collect(
            union(
                Set(_experiment_delta_domain(edge) for edge in joined),
                Set(_experiment_delta_domain(edge) for edge in matching),
                Set(_experiment_delta_domain(edge) for edge in returned),
            ),
        ),
    )
    by_domain = Dict{String, Any}()
    for domain in domains
        domain_joined =
            [
            edge for edge in joined if
                _experiment_delta_domain(edge) == domain
        ]
        domain_matching =
            [
            edge for edge in matching if
                _experiment_delta_domain(edge) == domain
        ]
        domain_selected =
            [
            edge for edge in selected if
                _experiment_delta_domain(edge) == domain
        ]
        domain_returned =
            [
            edge for edge in returned if
                _experiment_delta_domain(edge) == domain
        ]
        total_delta = sum(
            Float64(get(edge, "abs_delta", 0.0)) for
                edge in domain_matching
            ;
            init = 0.0,
        )
        selected_delta = sum(
            Float64(get(edge, "abs_delta", 0.0)) for
                edge in domain_selected
            ;
            init = 0.0,
        )
        returned_delta = sum(
            Float64(get(edge, "abs_delta", 0.0)) for
                edge in domain_returned
            ;
            init = 0.0,
        )
        by_domain[domain] = Dict{String, Any}(
            "count_joined" => length(domain_joined),
            "count_matching" => length(domain_matching),
            "count_selected_for_coverage" => length(domain_selected),
            "count_returned" => length(domain_returned),
            "abs_delta_matching" => total_delta,
            "abs_delta_selected" => selected_delta,
            "abs_delta_returned" => returned_delta,
            "amount_matching" => total_delta,
            "amount_selected" => selected_delta,
            "amount_returned" => returned_delta,
            "count_fraction_returned" =>
                isempty(domain_matching) ? 1.0 :
                length(domain_returned) / length(domain_matching),
            "value_fraction_returned" =>
                total_delta > 0 ? returned_delta / total_delta : 1.0,
        )
    end
    total_delta = sum(
        Float64(get(edge, "abs_delta", 0.0)) for edge in matching
        ;
        init = 0.0,
    )
    returned_delta = sum(
        Float64(get(edge, "abs_delta", 0.0)) for edge in returned
        ;
        init = 0.0,
    )
    return Dict{String, Any}(
        "complete_inputs_loaded_before_scope_filter" => true,
        "join_performed_before_coverage_and_truncation" => true,
        "edge_count_run_a" => Int(count_a),
        "edge_count_run_b" => Int(count_b),
        "count_complete_joined" =>
            Int(complete_semantic_relationship_count),
        "count_complete_semantic_relationships" =>
            Int(complete_semantic_relationship_count),
        "count_complete_comparison_rows" =>
            Int(complete_comparison_row_count),
        "count_joined" => length(joined),
        "count_matching" => length(matching),
        "count_selected_for_coverage" => length(selected),
        "count_returned" => length(returned),
        "abs_delta_matching" => total_delta,
        "abs_delta_returned" => returned_delta,
        "amount_matching" => total_delta,
        "amount_returned" => returned_delta,
        "count_fraction_returned" =>
            isempty(matching) ? 1.0 :
            length(returned) / length(matching),
        "value_fraction_returned" =>
            total_delta > 0 ? returned_delta / total_delta : 1.0,
        "by_domain" => by_domain,
    )
end

function _experiment_period(manifest, quarter::Integer)
    periods = collect(get(manifest, "periods", Any[]))
    quarters = Int.(collect(get(manifest, "quarters", Any[])))
    index = findfirst(==(quarter), quarters)
    if index !== nothing && index <= length(periods)
        return String(periods[index])
    end
    return ""
end

function _experiment_shock_context(experiment)
    experiment === nothing && return nothing
    intervention = _experiment_dict(
        get(experiment, "intervention_diff", nothing),
    )
    if haskey(intervention, "shock")
        shock = _experiment_dict(intervention["shock"])
        shock_type = String(get(shock, "type", "none"))
        context = Dict{String, Any}(
            "type" => shock_type,
            "label" => replace(shock_type, '_' => ' '),
            "quarter" => 1,
            "onset_quarter" => 1,
            "timing" => "first_simulated_quarter",
        )
        if haskey(shock, "multiplier")
            context["magnitude"] = shock["multiplier"]
            context["units"] = "multiplier"
        elseif haskey(shock, "annual_rate")
            context["magnitude"] = shock["annual_rate"]
            context["units"] = "annual_rate_delta"
        end
        haskey(shock, "final_time") &&
            (context["duration"] = shock["final_time"])
        haskey(shock, "sector") &&
            (context["sector"] = shock["sector"])
        return context
    elseif haskey(intervention, "overrides")
        return Dict{String, Any}(
            "type" => "run_start_override",
            "label" => "Run-start parameter override",
            "quarter" => 0,
            "onset_quarter" => 0,
            "timing" => "initialization",
        )
    end
    return Dict{String, Any}(
        "type" => "no_op",
        "label" => "No-op intervention",
        "quarter" => 1,
        "onset_quarter" => 1,
        "timing" => "first_simulated_quarter",
    )
end

"""
    compare_cashflows(run_a, run_b; quarter, level = "sector", ...)

Load both complete normalized edge tables and join their union by stable
semantic ID before applying level/layer/focus filters. Missing edges are zero.
Coverage selection and `limit` are applied to the joined deltas, never to either
input table. The response classifies every in-scope relationship before
optional unchanged/minimum filtering and reports count/value coverage after the
join.
"""
function compare_cashflows(
        run_a::AbstractString,
        run_b::AbstractString;
        quarter,
        level::AbstractString = "sector",
        layers = nothing,
        focus = nothing,
        direction = nothing,
        recognition = nothing,
        coverage::Real = 1.0,
        limit::Integer = 1000,
        min_amount::Real = 0.0,
        min_delta::Real = 0.0,
        include_unchanged::Bool = false,
        include_counterfactual::Bool = false,
        experiment_id = nothing,
        experiments_directory::AbstractString = EXPERIMENTS_DIR,
        atol::Real = 1.0e-9,
        rtol::Real = 1.0e-10,
    )
    run_a_id = _experiment_uuid(run_a, "run_a")
    run_b_id = _experiment_uuid(run_b, "run_b")
    run_a_path = _run_dir(run_a_id)
    run_b_path = _run_dir(run_b_id)
    isdir(run_a_path) || throw(ApiError(404, "Unknown run_a"))
    isdir(run_b_path) || throw(ApiError(404, "Unknown run_b"))
    _experiment_run_complete(run_a_path)
    _experiment_run_complete(run_b_path)
    try
        _cashflow_level_rank(level)
    catch error
        error isa ArgumentError || rethrow()
        throw(ApiError(400, error.msg))
    end
    level == "all" &&
        throw(
        ApiError(
            400,
            "Comparison level must be macro, sector, or firm",
        ),
    )
    1 <= limit <= 10000 ||
        throw(ApiError(400, "limit must be between 1 and 10000"))
    0 < coverage <= 1 ||
        throw(ApiError(400, "coverage must be greater than 0 and at most 1"))
    min_delta >= 0 ||
        throw(ApiError(400, "min_delta must be non-negative"))
    min_amount >= 0 ||
        throw(ApiError(400, "min_amount must be non-negative"))
    atol >= 0 && rtol >= 0 ||
        throw(ApiError(400, "Comparison tolerances must be non-negative"))

    manifest_a = _normalize_dict(_cashflow_manifest(run_a_path))
    manifest_b = _normalize_dict(_cashflow_manifest(run_b_path))
    quarter_index = try
        Int(quarter)
    catch
        throw(ApiError(400, "quarter must be an integer"))
    end
    quarter_index in Int.(collect(manifest_a["quarters"])) ||
        throw(ApiError(400, "Quarter is unavailable in run_a"))
    quarter_index in Int.(collect(manifest_b["quarters"])) ||
        throw(ApiError(400, "Quarter is unavailable in run_b"))

    experiment = if experiment_id === nothing
        _experiment_find_for_runs(
            run_a_id,
            run_b_id;
            directory = experiments_directory,
        )
    else
        get_experiment(
            _experiment_uuid(experiment_id, "experiment_id");
            directory = experiments_directory,
        )
    end
    compatibility = _experiment_comparison_compatibility(
        run_a_path,
        run_b_path;
        level,
        layers,
        experiment,
        quarter = quarter_index,
    )

    # Cache complete decoded/indexed quarters, but always join before filters,
    # coverage selection, or truncation. Entries are invalidated by file
    # signature and bounded for predictable server memory use.
    index_a, count_a, signature_a = _experiment_cached_index(
        run_a_path,
        run_a_id,
        quarter_index,
    )
    index_b, count_b, signature_b = _experiment_cached_index(
        run_b_path,
        run_b_id,
        quarter_index,
    )
    paired = Bool(compatibility["paired"])
    edge_ids, semantic_count, complete_comparison_row_count, pair_cache_key =
        _experiment_cached_join(
        index_a,
        run_a_id,
        signature_a,
        index_b,
        run_b_id,
        signature_b;
        atol,
        rtol,
        paired,
    )
    prepared_layer_filter = _cashflow_layer_filter_values(layers)
    prepared_recognition_filter = _cashflow_filter_values(recognition)
    prepared_focus_node = if focus === nothing
        nothing
    else
        focus_text = string(focus)
        tryparse(Int, focus_text) !== nothing ?
            "firm:$focus_text" : focus_text
    end
    scope_cache_key = pair_cache_key * "|" * _experiment_digest(
        Dict{String, Any}(
            "level" => level,
            "layers" => sort!(
                collect(
                    something(
                        prepared_layer_filter,
                        Set{String}(),
                    )
                )
            ),
            "focus" => something(prepared_focus_node, ""),
            "direction" => something(direction, ""),
            "recognition" => sort!(
                collect(
                    something(
                        prepared_recognition_filter,
                        Set{String}(),
                    )
                )
            ),
            "min_amount" => Float64(min_amount),
            "include_counterfactual" => include_counterfactual,
        ),
    )
    cached_scope = lock(_EXPERIMENT_CACHE_LOCK) do
        access = _experiment_cache_access!()
        cached = get(_EXPERIMENT_SCOPE_CACHE, scope_cache_key, nothing)
        if cached !== nothing
            _EXPERIMENT_SCOPE_CACHE[scope_cache_key] = merge(cached, (; access))
            cached.edges
        else
            nothing
        end
    end
    joined = cached_scope === nothing ? try
            scoped = Any[]
            for edge_id in edge_ids
                edge_a = get(index_a, edge_id, nothing)
                edge_b = get(index_b, edge_id, nothing)
                template = edge_b === nothing ? edge_a : edge_b
                value_a = edge_a === nothing ? 0.0 : _cashflow_edge_value(edge_a)
                value_b = edge_b === nothing ? 0.0 : _cashflow_edge_value(edge_b)
                zero_a = _experiment_values_close(value_a, 0.0; atol, rtol)
                zero_b = _experiment_values_close(value_b, 0.0; atol, rtol)
                # The full outer union above is the join. Apply coarse semantic
                # scope only after that union, before allocating one or two delta
                # dictionaries for the relationship. Direction is checked on each
                # resulting row because a sign reversal has two display directions.
                _cashflow_edge_in_level(template, level) || continue
                _cashflow_edge_matches(
                    template;
                    focus,
                    layers,
                    recognition,
                    direction = nothing,
                    min_amount = 0.0,
                    include_counterfactual,
                    prepared_layer_filter,
                    prepared_recognition_filter,
                    prepared_focus_node,
                ) || continue
                max(abs(value_a), abs(value_b)) >= Float64(min_amount) || continue
                rows = _experiment_delta_edges(
                    edge_id,
                    edge_a,
                    edge_b;
                    atol,
                    rtol,
                    paired,
                )
                for row in rows
                    _cashflow_edge_matches(
                        row;
                        focus,
                        direction,
                        min_amount = 0.0,
                        include_counterfactual,
                        prepared_layer_filter = nothing,
                        prepared_recognition_filter = nothing,
                        prepared_focus_node,
                    ) || continue
                    push!(scoped, row)
            end
        end
            scoped
    catch error
            error isa ArgumentError || rethrow()
            throw(ApiError(400, error.msg))
    end : cached_scope
    if cached_scope === nothing
        lock(_EXPERIMENT_CACHE_LOCK) do
            access = _experiment_cache_access!()
            _EXPERIMENT_SCOPE_CACHE[scope_cache_key] =
                (; edges = joined, access)
            _experiment_evict_lru!(
                _EXPERIMENT_SCOPE_CACHE,
                EXPERIMENT_SCOPE_CACHE_MAX_ENTRIES,
            )
        end
    end
    class_counts = Dict(
        class => count(
                edge -> String(edge["change"]) == class,
                joined,
            ) for class in
            ("added", "removed", "increased", "decreased", "unchanged")
    )
    matching = [
        edge for edge in joined if
            (
                include_unchanged ||
                String(edge["change"]) != "unchanged"
            ) &&
            Float64(edge["abs_delta"]) >= Float64(min_delta)
    ]
    _experiment_sort_deltas!(matching)
    selected = _experiment_select_coverage(matching, coverage)
    _experiment_sort_deltas!(selected)
    returned = selected[1:min(length(selected), Int(limit))]
    coverage_payload = _experiment_delta_coverage(
        joined,
        matching,
        selected,
        returned,
        count_a,
        count_b,
        semantic_count,
        complete_comparison_row_count,
    )
    exact_zero =
        all(
        edge -> _experiment_values_close(
            Float64(edge["delta"]),
            0.0;
            atol,
            rtol,
        ),
        joined,
    )
    run_spec_diff = experiment === nothing ? Any[] :
        collect(
            get(
                experiment,
                "realized_intervention_diff",
                Any[],
            ),
        )
    intervention_diff = experiment === nothing ?
        Dict{String, Any}() :
        _experiment_dict(
            get(experiment, "intervention_diff", nothing),
        )
    shock_context = _experiment_shock_context(experiment)
    run_roles = experiment === nothing ? Dict{String, Any}() :
        _experiment_dict(get(experiment, "roles", nothing))
    comparison_orientation = if experiment === nothing
        "unpaired"
    elseif get(run_roles, run_a_id, "") == "baseline" &&
            get(run_roles, run_b_id, "") == "treatment"
        "baseline_to_treatment"
    elseif get(run_roles, run_a_id, "") == "treatment" &&
            get(run_roles, run_b_id, "") == "baseline"
        "treatment_to_baseline"
    else
        "declared_pair_unknown_orientation"
    end
    if shock_context !== nothing
        shock_context["comparison_orientation"] = comparison_orientation
    end
    return Dict{String, Any}(
        "schema_version" => CASHFLOW_COMPARISON_SCHEMA_VERSION,
        "run_a" => run_a_id,
        "run_b" => run_b_id,
        "quarter_index" => quarter_index,
        "period" => _experiment_period(manifest_a, quarter_index),
        "period_a" => _experiment_period(manifest_a, quarter_index),
        "period_b" => _experiment_period(manifest_b, quarter_index),
        "level" => level,
        "layers" =>
            sort!(
            collect(
                something(
                    _cashflow_layer_filter_values(layers),
                    Set{String}(),
                )
            )
        ),
        "comparison_direction" => "run_a_to_run_b",
        "comparison_orientation" => comparison_orientation,
        "run_roles" => run_roles,
        "query_applied_after_join" => true,
        "representative_realization_delta" => true,
        "realization_scope" => "representative",
        "ensemble_outcome_delta" => false,
        "compatibility" => compatibility,
        "experiment_id" => experiment === nothing ? nothing :
            experiment["experiment_id"],
        "intervention_diff" => intervention_diff,
        "run_spec_diff" => run_spec_diff,
        "shock_context" => shock_context,
        "numeric_contract" => Dict(
            "atol" => Float64(atol),
            "rtol" => Float64(rtol),
            "absolute_tolerance" => Float64(atol),
            "relative_tolerance" => Float64(rtol),
            "zero_test" => "isapprox",
            "exact_zero_diff_within_contract" => exact_zero,
            "delta_definition" =>
                "display_direction_magnitude_run_b_minus_run_a",
            "magnitude_delta_definition" =>
                "amount_b_minus_amount_a_in_the_recorded_display_direction",
            "canonical_signed_delta_definition" =>
                "canonical_signed_value_run_b_minus_run_a",
            "side_amount_definition" =>
                "nonnegative_magnitude_in_the_comparison_row_display_direction",
            "side_value_definition" =>
                "signed_value_in_the_original_edge_canonical_direction",
            "same_direction_classification" =>
                "added_removed_increased_decreased_or_unchanged_by_display_magnitude",
            "sign_reversal_representation" =>
                "removed_run_a_direction_row_plus_added_run_b_direction_row",
            "comparison_row_identity" =>
                "id_and_stable_id_identify_the_directional_comparison_row; semantic_id_and_original_edge_id_identify_the_joined_economic_relationship",
        ),
        "shared_scale_domains" =>
            _experiment_shared_scale_domains(manifest_a, manifest_b),
        "class_counts" => class_counts,
        "coverage" => coverage_payload,
        "query" => Dict(
            "coverage" => Float64(coverage),
            "limit" => Int(limit),
            "min_delta" => Float64(min_delta),
            "min_amount" => Float64(min_amount),
            "focus" => focus,
            "direction" => direction,
            "recognition" => recognition,
            "include_unchanged" => include_unchanged,
            "include_counterfactual" => include_counterfactual,
        ),
        "edges" => returned,
    )
end

"""
    _create_experiment_response(request)
    _get_experiment_response(experiment_id)
    _compare_cashflows_response(; ...)

Thin route-integration helpers. Routes remain in `BeforeITWeb.jl`, while all
normalization and comparison semantics live in this file.
"""
_create_experiment_response(request) =
    _json_response(201, _sanitize_for_json(create_experiment(request)))

_get_experiment_response(experiment_id::AbstractString) =
    _json_response(
    200,
    _sanitize_for_json(get_experiment(experiment_id)),
)

function _compare_cashflows_response(; run_a, run_b, kwargs...)
    return _json_response(
        200,
        _sanitize_for_json(
            compare_cashflows(
                String(run_a),
                String(run_b);
                kwargs...,
            ),
        ),
    )
end
