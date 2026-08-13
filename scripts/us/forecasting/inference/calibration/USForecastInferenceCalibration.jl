module USForecastInferenceCalibration

using LinearAlgebra
using Dates
using Random
using SHA
using Statistics
using TOML

include(joinpath(@__DIR__, "..", "USForecastInference.jl"))
using .USForecastInference:
    FixedBlockLength,
    loss_differential,
    stationary_bootstrap_indices

export BLOCK_POLICY_IDS,
    CALIBRATION_STAGES,
    COMMON_FOUR_ORIGIN_OUTAGE,
    COMPLETE,
    DEFAULT_PROTOCOL_PATH,
    EXPECTED_PROTOCOL_SHA256,
    FALSE_NULL_PATTERN_IDS,
    FORBIDDEN_GEOMETRY_FIELD_TOKENS,
    HORIZONS,
    MASTER_SEED,
    MODEL_EXECUTION_FAILURE,
    MODEL_COUNT,
    MissingnessPolicy,
    OUTCOME_DEPENDENT_FORBIDDEN,
    PROTOCOL_SCHEMA_VERSION,
    REHEARSAL_ALL_AVAILABLE_COUNTS,
    REHEARSAL_BALANCED_COUNT,
    REHEARSAL_ROLLING60_COUNTS,
    SCORE_BLIND_LAGGED_STATE,
    TARGET_IDS,
    TARGET_SPECIFIC_GAPS,
    TERMINAL_HORIZON_MATURITY,
    CalibrationContractError,
    CalibrationShard,
    apply_boundary_stress,
    block_policy,
    calibration_shard,
    clopper_pearson_interval,
    clopper_pearson_lower,
    clopper_pearson_upper,
    computed_geometry_sha256,
    computed_protocol_sha256,
    derive_bootstrap_seed,
    derive_dgp_seed,
    eligible_origin_indices,
    estimation_indices,
    execution_authorization,
    false_null_mask,
    family_loss_differentials,
    generate_direct_null_differentials,
    generate_null_forecast_errors,
    hypothesis_ids,
    hypothesis_mapping,
    load_protocol,
    load_score_blind_geometry,
    merge_shards,
    missingness_mask,
    overlap_correlation,
    parse_missingness_policy,
    policy_indices,
    primitive_innovations,
    primitive_loss_eligibility,
    protocol_artifact,
    target_factor_covariance,
    target_factor_loadings,
    validate_protocol,
    validate_score_blind_geometry

const DEFAULT_PROTOCOL_PATH = joinpath(@__DIR__, "calibration_protocol.toml")
const PROTOCOL_SCHEMA_VERSION =
    "beforeit-us-forecast-inference-calibration-protocol.v2"
const GEOMETRY_SCHEMA_VERSION =
    "beforeit-us-inference-score-blind-geometry.v3"
const CANONICALIZATION =
    "sorted_typed_length_aware_v1_excluding_artifact_content_sha256"
const EXPECTED_PROTOCOL_SHA256 =
    "c291c975bac7a419eb47d46841c79ec9eaf31399694ea4296078c3e884e61463"
const MASTER_SEED = UInt64(0x55534643414c4942)
const MODEL_COUNT = 11
const COMPARISON_COUNT = 10
const TARGET_IDS = (
    "real_gdp_growth",
    "pce_inflation",
    "unemployment",
    "effr",
)
const HORIZONS = (1, 2, 4, 8, 12)
const ESTIMATION_WINDOWS = (
    "EXPANDING",
    "ROLLING_40",
    "ROLLING_60",
)
const REHEARSAL_ALL_AVAILABLE_COUNTS = (61, 60, 58, 54, 50)
const REHEARSAL_BALANCED_COUNT = 50
const REHEARSAL_ROLLING60_COUNTS = (41, 40, 38, 34, 30)
const FALSE_NULL_PATTERN_IDS = (
    "SINGLE",
    "TARGET5",
    "MODEL20",
    "DENSE200",
)
const BLOCK_POLICY_IDS = ("J01", "J02", "J03", "J04")
const CALIBRATION_STAGES = (
    "SMOKE",
    "SCREENING",
    "FINAL_NULL_VALIDATION",
    "POWER",
    "HORIZON_SENSITIVITY",
)
const NULL_DGP_IDS = (
    "N00_DIFF_IID",
    "N01_FE_GAUSS_EXP",
    "N02_FE_GAUSS_R40",
    "N03_FE_GAUSS_R60",
    "N04_FE_AR035_EXP",
    "N05_FE_T5_EXP",
    "N06_FE_GARCH_EXP",
    "N07_FE_STRONG_EXP",
)
const FORBIDDEN_GEOMETRY_FIELD_TOKENS = (
    "forecast",
    "truth",
    "error",
    "loss",
    "score",
    "rank",
    "pvalue",
    "p_value",
    "effect",
)
const ALLOWED_REGIME_LABELS = (
    "PRE_PANDEMIC",
    "PANDEMIC_ACUTE",
    "POST_ACUTE",
    "NBER_RECESSION",
    "NBER_EXPANSION",
    "ELB_POLICY",
    "STANDARD_POLICY",
)
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const ID_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:-]*$"
const UTC_TIMESTAMP_PATTERN =
    r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"
const DATE_PATTERN = r"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"
const QUARTER_PATTERN = r"^[0-9]{4}Q[1-4]$"
const TIMESTAMP_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const RESERVED_PLACEHOLDER_IDS = Set(
    (
        "used",
        "other",
        "unknown",
        "dubious",
        "unspecified",
        "unassigned",
        "placeholder",
        "tbd",
        "todo",
        "na",
        "n/a",
        "none",
        "null",
        "missing",
    )
)
const PANDEMIC_REGIME_LABELS = (
    "PRE_PANDEMIC",
    "PANDEMIC_ACUTE",
    "POST_ACUTE",
)
const NBER_REGIME_LABELS = ("NBER_RECESSION", "NBER_EXPANSION")
const POLICY_REGIME_LABELS = ("ELB_POLICY", "STANDARD_POLICY")
const REGIME_ASSIGNMENT_BASIS =
    "EXTERNALLY_REVIEWED_SCORE_BLIND_ASSERTIONS"

struct CalibrationContractError <: Exception
    message::String
end

Base.showerror(io::IO, error::CalibrationContractError) =
    print(io, error.message)

fail(location, message) =
    throw(CalibrationContractError("$location: $message"))

function _expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function _expect_exact_keys(value, keys, location)
    table = _expect_table(value, location)
    actual = Set(String.(collect(Base.keys(table))))
    expected = Set(keys)
    actual == expected ||
        fail(
        location,
        "keys must be exactly $(sort!(collect(expected))); got " *
            "$(sort!(collect(actual)))",
    )
    return table
end

function _expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) && !isempty(text) ||
        fail(location, "must be nonempty and trimmed")
    return text
end

function _expect_bool(value, location)
    value isa Bool || fail(location, "must be Boolean")
    return value
end

function _expect_integer(value, location; minimum = nothing)
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer, not Bool")
    result = try
        Int(value)
    catch
        fail(location, "is outside the supported integer range")
    end
    if !isnothing(minimum)
        result >= minimum || fail(location, "must be at least $minimum")
    end
    return result
end

function _expect_number(value, location)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be numeric, not Bool")
    result = Float64(value)
    isfinite(result) || fail(location, "must be finite")
    return result
end

function _expect_vector(value, location)
    value isa AbstractVector || fail(location, "must be an array")
    return value
end

function _expect_exact(value, expected, location)
    value == expected ||
        fail(location, "must equal $(repr(expected)); got $(repr(value))")
    return value
end

function _expect_hash(value, location)
    text = _expect_string(value, location)
    occursin(HASH_PATTERN, text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        entries =
            sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "S", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "B1" : "B0")
    elseif value isa Integer
        print(io, "I", value, ";")
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) ||
            fail("canonicalization", "cannot encode a nonfinite number")
        print(io, "F", bitstring(number), ";")
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function _canonical_content_bytes(value)
    document = deepcopy(_expect_table(value, "document"))
    artifact =
        _expect_table(get(document, "artifact", nothing), "document.artifact")
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, document)
    return take!(io)
end

computed_protocol_sha256(value) =
    bytes2hex(sha256(_canonical_content_bytes(value)))

computed_geometry_sha256(value) =
    bytes2hex(sha256(_canonical_content_bytes(value)))

function _read_toml(path, label)
    absolute = abspath(String(path))
    isfile(absolute) || fail(label, "file does not exist: $absolute")
    islink(absolute) && fail(label, "must not be a symbolic link")
    bytes = try
        read(absolute)
    catch error
        fail(label, "could not read file: $(sprint(showerror, error))")
    end
    document = try
        TOML.parse(String(copy(bytes)))
    catch error
        fail(label, "could not parse TOML: $(sprint(showerror, error))")
    end
    return (; absolute, bytes, document)
end

const PROTOCOL_ROOT_KEYS = (
    "artifact",
    "contract",
    "rehearsal",
    "family",
    "direct_null",
    "target_factor",
    "estimation",
    "missingness",
    "alternatives",
    "block_policies",
    "stages",
    "thresholds",
    "gates",
)

function _validate_protocol_artifact(protocol)
    artifact = _expect_exact_keys(
        protocol["artifact"],
        ("schema_version", "canonicalization", "content_sha256"),
        "protocol.artifact",
    )
    _expect_exact(
        artifact["schema_version"],
        PROTOCOL_SCHEMA_VERSION,
        "protocol.artifact.schema_version",
    )
    _expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "protocol.artifact.canonicalization",
    )
    declared = _expect_hash(
        artifact["content_sha256"],
        "protocol.artifact.content_sha256",
    )
    computed = computed_protocol_sha256(protocol)
    declared == computed ||
        fail(
        "protocol.artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    declared == EXPECTED_PROTOCOL_SHA256 ||
        fail(
        "protocol.artifact.content_sha256",
        "does not match the compiled protocol pin",
    )
    return declared
end

function _validate_protocol_direct_null(protocol)
    direct = _expect_exact_keys(
        protocol["direct_null"],
        (
            "dgp_id",
            "distribution",
            "column_dependence",
            "cross_hypothesis_correlation",
        ),
        "protocol.direct_null",
    )
    _expect_exact(
        direct["dgp_id"],
        "N00_DIFF_IID",
        "protocol.direct_null.dgp_id",
    )
    _expect_exact(
        direct["distribution"],
        "STANDARD_GAUSSIAN",
        "protocol.direct_null.distribution",
    )
    _expect_exact(
        direct["column_dependence"],
        "FULLY_INDEPENDENT",
        "protocol.direct_null.column_dependence",
    )
    correlation = _expect_number(
        direct["cross_hypothesis_correlation"],
        "protocol.direct_null.cross_hypothesis_correlation",
    )
    _expect_exact(
        correlation,
        0.0,
        "protocol.direct_null.cross_hypothesis_correlation",
    )
    return (;
        dgp_id = "N00_DIFF_IID",
        distribution = :standard_gaussian,
        column_dependence = :fully_independent,
        cross_hypothesis_correlation = 0.0,
    )
end

function _validate_protocol_contract(protocol)
    contract = _expect_exact_keys(
        protocol["contract"],
        (
            "contract_id",
            "master_seed_hex",
            "synthetic_only",
            "score_artifact_reads_allowed",
            "diagnostic_module_import_allowed",
            "full_execution_requires_geometry",
            "full_execution_requires_explicit_expensive_mode",
        ),
        "protocol.contract",
    )
    _expect_exact(
        contract["contract_id"],
        "us-forecast-inference-calibration.v2",
        "protocol.contract.contract_id",
    )
    _expect_exact(
        contract["master_seed_hex"],
        "0x55534643414c4942",
        "protocol.contract.master_seed_hex",
    )
    _expect_exact(
        _expect_bool(
            contract["synthetic_only"],
            "protocol.contract.synthetic_only",
        ),
        true,
        "protocol.contract.synthetic_only",
    )
    for key in (
            "score_artifact_reads_allowed",
            "diagnostic_module_import_allowed",
        )
        _expect_exact(
            _expect_bool(contract[key], "protocol.contract.$key"),
            false,
            "protocol.contract.$key",
        )
    end
    for key in (
            "full_execution_requires_geometry",
            "full_execution_requires_explicit_expensive_mode",
        )
        _expect_exact(
            _expect_bool(contract[key], "protocol.contract.$key"),
            true,
            "protocol.contract.$key",
        )
    end
    return contract
end

function _validate_protocol_rehearsal(protocol)
    rehearsal = _expect_exact_keys(
        protocol["rehearsal"],
        (
            "horizons",
            "all_available_counts",
            "balanced_count",
            "rolling60_counts",
            "rolling60_balanced_count",
        ),
        "protocol.rehearsal",
    )
    _expect_exact(
        Tuple(_expect_vector(rehearsal["horizons"], "protocol.rehearsal.horizons")),
        HORIZONS,
        "protocol.rehearsal.horizons",
    )
    _expect_exact(
        Tuple(
            _expect_vector(
                rehearsal["all_available_counts"],
                "protocol.rehearsal.all_available_counts",
            ),
        ),
        REHEARSAL_ALL_AVAILABLE_COUNTS,
        "protocol.rehearsal.all_available_counts",
    )
    _expect_exact(
        _expect_integer(
            rehearsal["balanced_count"],
            "protocol.rehearsal.balanced_count",
        ),
        REHEARSAL_BALANCED_COUNT,
        "protocol.rehearsal.balanced_count",
    )
    _expect_exact(
        Tuple(
            _expect_vector(
                rehearsal["rolling60_counts"],
                "protocol.rehearsal.rolling60_counts",
            ),
        ),
        REHEARSAL_ROLLING60_COUNTS,
        "protocol.rehearsal.rolling60_counts",
    )
    _expect_exact(
        _expect_integer(
            rehearsal["rolling60_balanced_count"],
            "protocol.rehearsal.rolling60_balanced_count",
        ),
        30,
        "protocol.rehearsal.rolling60_balanced_count",
    )
    return rehearsal
end

function _validate_protocol_family(protocol)
    family = _expect_exact_keys(
        protocol["family"],
        (
            "model_count",
            "comparison_count",
            "target_ids",
            "horizons",
            "hypothesis_count",
            "loss_families",
            "alternative",
            "differential_orientation",
        ),
        "protocol.family",
    )
    exact_values = (
        "model_count" => MODEL_COUNT,
        "comparison_count" => COMPARISON_COUNT,
        "hypothesis_count" => 200,
        "alternative" => "less",
        "differential_orientation" => "challenger_minus_comparator",
    )
    for (key, expected) in exact_values
        _expect_exact(family[key], expected, "protocol.family.$key")
    end
    _expect_exact(
        Tuple(family["target_ids"]),
        TARGET_IDS,
        "protocol.family.target_ids",
    )
    _expect_exact(
        Tuple(family["horizons"]),
        HORIZONS,
        "protocol.family.horizons",
    )
    _expect_exact(
        Tuple(family["loss_families"]),
        ("squared", "absolute"),
        "protocol.family.loss_families",
    )
    return family
end

function _validate_protocol_fixed_tables(protocol)
    factor = _expect_exact_keys(
        protocol["target_factor"],
        ("factor1", "factor2", "strong_common_variance"),
        "protocol.target_factor",
    )
    _expect_exact(
        Tuple(_expect_number(value, "protocol.target_factor.factor1") for value in factor["factor1"]),
        (0.7, 0.4, -0.6, 0.3),
        "protocol.target_factor.factor1",
    )
    _expect_exact(
        Tuple(_expect_number(value, "protocol.target_factor.factor2") for value in factor["factor2"]),
        (0.0, 0.4, 0.1, 0.5),
        "protocol.target_factor.factor2",
    )
    _expect_exact(
        _expect_number(
            factor["strong_common_variance"],
            "protocol.target_factor.strong_common_variance",
        ),
        0.7,
        "protocol.target_factor.strong_common_variance",
    )

    estimation = _expect_exact_keys(
        protocol["estimation"],
        (
            "windows",
            "initial_length",
            "rolling40_length",
            "rolling60_length",
            "component_loading",
            "forecast_error_loading",
            "burn_in",
            "future_outcomes_disjoint",
        ),
        "protocol.estimation",
    )
    _expect_exact(
        Tuple(estimation["windows"]),
        ESTIMATION_WINDOWS,
        "protocol.estimation.windows",
    )
    for (key, expected) in (
            "initial_length" => 40,
            "rolling40_length" => 40,
            "rolling60_length" => 60,
            "burn_in" => 2_000,
        )
        _expect_exact(estimation[key], expected, "protocol.estimation.$key")
    end
    for (key, expected) in (
            "component_loading" => 0.5,
            "forecast_error_loading" => 0.35,
        )
        _expect_exact(
            _expect_number(estimation[key], "protocol.estimation.$key"),
            expected,
            "protocol.estimation.$key",
        )
    end
    _expect_exact(
        estimation["future_outcomes_disjoint"],
        true,
        "protocol.estimation.future_outcomes_disjoint",
    )

    missingness = _expect_exact_keys(
        protocol["missingness"],
        ("policy_ids", "imputation_allowed", "used_token_allowed"),
        "protocol.missingness",
    )
    _expect_exact(
        Tuple(missingness["policy_ids"]),
        (
            "COMPLETE",
            "TERMINAL_HORIZON_MATURITY",
            "COMMON_FOUR_ORIGIN_OUTAGE",
            "SCORE_BLIND_LAGGED_STATE",
            "TARGET_SPECIFIC_GAPS",
            "MODEL_EXECUTION_FAILURE",
            "OUTCOME_DEPENDENT_FORBIDDEN",
        ),
        "protocol.missingness.policy_ids",
    )
    for key in ("imputation_allowed", "used_token_allowed")
        _expect_exact(
            _expect_bool(missingness[key], "protocol.missingness.$key"),
            false,
            "protocol.missingness.$key",
        )
    end

    alternatives = _expect_exact_keys(
        protocol["alternatives"],
        (
            "power_scales",
            "false_null_pattern_ids",
            "false_null_counts",
        ),
        "protocol.alternatives",
    )
    _expect_exact(
        Tuple(_expect_number(value, "protocol.alternatives.power_scales") for value in alternatives["power_scales"]),
        (0.9, 0.75, 0.5),
        "protocol.alternatives.power_scales",
    )
    _expect_exact(
        Tuple(alternatives["false_null_pattern_ids"]),
        FALSE_NULL_PATTERN_IDS,
        "protocol.alternatives.false_null_pattern_ids",
    )
    _expect_exact(
        Tuple(alternatives["false_null_counts"]),
        (1, 5, 20, 200),
        "protocol.alternatives.false_null_counts",
    )
    return (; factor, estimation, missingness, alternatives)
end

function _validate_protocol_policies(protocol)
    policies = _expect_vector(
        protocol["block_policies"],
        "protocol.block_policies",
    )
    length(policies) == 4 ||
        fail("protocol.block_policies", "must contain exactly four rows")
    expected = (
        ("J01", 1.0, "none", 1.0),
        ("J02", 4.0, "none", 4.0),
        ("J03", 4.0, "max_horizon", 12.0),
        ("J04", 24.0, "none", 24.0),
    )
    rows = map(enumerate(zip(policies, expected))) do (index, pair)
        row, expected_row = pair
        table = _expect_exact_keys(
            row,
            (
                "policy_id",
                "requested_block_length",
                "horizon_floor_policy",
                "joint_effective_block_length",
            ),
            "protocol.block_policies[$index]",
        )
        values = (
            _expect_string(
                table["policy_id"],
                "protocol.block_policies[$index].policy_id",
            ),
            _expect_number(
                table["requested_block_length"],
                "protocol.block_policies[$index].requested_block_length",
            ),
            _expect_string(
                table["horizon_floor_policy"],
                "protocol.block_policies[$index].horizon_floor_policy",
            ),
            _expect_number(
                table["joint_effective_block_length"],
                "protocol.block_policies[$index].joint_effective_block_length",
            ),
        )
        _expect_exact(values, expected_row, "protocol.block_policies[$index]")
        return (;
            policy_id = values[1],
            requested_block_length = values[2],
            horizon_floor_policy = Symbol(values[3]),
            joint_effective_block_length = values[4],
        )
    end
    return Tuple(rows)
end

function _validate_protocol_stages(protocol)
    stages = _expect_exact_keys(
        protocol["stages"],
        (
            "screening",
            "final_null_validation",
            "power",
            "horizon_sensitivity",
        ),
        "protocol.stages",
    )
    expected = (
        "screening" => (5_000, 999),
        "final_null_validation" => (20_000, 9_999),
        "power" => (10_000, 9_999),
        "horizon_sensitivity" => (5_000, 9_999),
    )
    result = map(expected) do pair
        key, values = pair
        row = _expect_exact_keys(
            stages[key],
            ("outer_replications", "bootstrap_draws"),
            "protocol.stages.$key",
        )
        _expect_exact(
            row["outer_replications"],
            values[1],
            "protocol.stages.$key.outer_replications",
        )
        _expect_exact(
            row["bootstrap_draws"],
            values[2],
            "protocol.stages.$key.bootstrap_draws",
        )
        return (
            Symbol(key),
            (;
                outer_replications = values[1],
                bootstrap_draws = values[2],
            ),
        )
    end
    return (; result...)
end

function _validate_protocol_thresholds(protocol)
    thresholds = _expect_exact_keys(
        protocol["thresholds"],
        (
            "nominal_alpha",
            "screening_upper_99_max",
            "final_upper_99_max",
            "well_calibrated_lower",
            "well_calibrated_upper",
            "coverage_lower_99_min",
            "power_lower_95_min",
        ),
        "protocol.thresholds",
    )
    expected = (
        "nominal_alpha" => 0.05,
        "screening_upper_99_max" => 0.075,
        "final_upper_99_max" => 0.06,
        "well_calibrated_lower" => 0.04,
        "well_calibrated_upper" => 0.06,
        "coverage_lower_99_min" => 0.93,
        "power_lower_95_min" => 0.8,
    )
    for (key, value) in expected
        _expect_exact(
            _expect_number(thresholds[key], "protocol.thresholds.$key"),
            value,
            "protocol.thresholds.$key",
        )
    end
    return (; (Symbol(key) => value for (key, value) in expected)...)
end

function _validate_protocol_gates(protocol)
    gates = _expect_exact_keys(
        protocol["gates"],
        (
            "empirical_data_read",
            "origin_created",
            "promotion_eligible",
            "production_scoring_allowed",
            "readiness",
            "superiority_claim_allowed",
            "primary_policy_selected",
            "calibration_evidence_created",
        ),
        "protocol.gates",
    )
    for key in keys(gates)
        _expect_exact(
            _expect_bool(gates[key], "protocol.gates.$key"),
            false,
            "protocol.gates.$key",
        )
    end
    return (;
        empirical_data_read = false,
        origin_created = false,
        promotion_eligible = false,
        production_scoring_allowed = false,
        readiness = false,
        superiority_claim_allowed = false,
        primary_policy_selected = false,
        calibration_evidence_created = false,
    )
end

"""
    validate_protocol(protocol)

Validate the self-hashed synthetic-only calibration protocol. The return
value is an immutable graph of named tuples, tuples, and scalar values and
never aliases the caller's parsed TOML.
"""
function validate_protocol(protocol)
    root = _expect_exact_keys(protocol, PROTOCOL_ROOT_KEYS, "protocol")
    contract = _validate_protocol_contract(root)
    rehearsal = _validate_protocol_rehearsal(root)
    family = _validate_protocol_family(root)
    direct_null = _validate_protocol_direct_null(root)
    fixed = _validate_protocol_fixed_tables(root)
    policies = _validate_protocol_policies(root)
    stages = _validate_protocol_stages(root)
    thresholds = _validate_protocol_thresholds(root)
    gates = _validate_protocol_gates(root)
    digest = _validate_protocol_artifact(root)
    return (;
        schema_version = PROTOCOL_SCHEMA_VERSION,
        canonicalization = CANONICALIZATION,
        contract = (;
            contract_id = String(contract["contract_id"]),
            master_seed_hex = String(contract["master_seed_hex"]),
            synthetic_only = true,
            score_artifact_reads_allowed = false,
            diagnostic_module_import_allowed = false,
            full_execution_requires_geometry = true,
            full_execution_requires_explicit_expensive_mode = true,
        ),
        rehearsal = (;
            horizons = HORIZONS,
            all_available_counts = REHEARSAL_ALL_AVAILABLE_COUNTS,
            balanced_count = REHEARSAL_BALANCED_COUNT,
            rolling60_counts = REHEARSAL_ROLLING60_COUNTS,
            rolling60_balanced_count = 30,
        ),
        family = (;
            model_count = MODEL_COUNT,
            comparison_count = COMPARISON_COUNT,
            target_ids = TARGET_IDS,
            horizons = HORIZONS,
            hypothesis_count = 200,
            loss_families = ("squared", "absolute"),
            alternative = :less,
            differential_orientation = :challenger_minus_comparator,
        ),
        direct_null,
        target_factor = (;
            factor1 = Tuple(Float64.(fixed.factor["factor1"])),
            factor2 = Tuple(Float64.(fixed.factor["factor2"])),
            strong_common_variance =
                Float64(fixed.factor["strong_common_variance"]),
        ),
        estimation = (;
            windows = ESTIMATION_WINDOWS,
            initial_length = 40,
            rolling40_length = 40,
            rolling60_length = 60,
            component_loading = 0.5,
            forecast_error_loading = 0.35,
            burn_in = 2_000,
            future_outcomes_disjoint = true,
        ),
        missingness = (;
            policy_ids = Tuple(String.(fixed.missingness["policy_ids"])),
            imputation_allowed = false,
            used_token_allowed = false,
        ),
        alternatives = (;
            power_scales =
                Tuple(Float64.(fixed.alternatives["power_scales"])),
            false_null_pattern_ids = FALSE_NULL_PATTERN_IDS,
            false_null_counts = (1, 5, 20, 200),
        ),
        block_policies = policies,
        stages,
        thresholds,
        gates,
        content_sha256 = String(digest),
    )
end

function load_protocol(path::AbstractString = DEFAULT_PROTOCOL_PATH)
    source = _read_toml(path, "protocol")
    return validate_protocol(source.document)
end

function protocol_artifact(path::AbstractString = DEFAULT_PROTOCOL_PATH)
    source = _read_toml(path, "protocol")
    validated = validate_protocol(source.document)
    return (;
        path = source.absolute,
        schema_version = validated.schema_version,
        canonicalization = validated.canonicalization,
        contract = validated.contract,
        rehearsal = validated.rehearsal,
        family = validated.family,
        direct_null = validated.direct_null,
        target_factor = validated.target_factor,
        estimation = validated.estimation,
        missingness = validated.missingness,
        alternatives = validated.alternatives,
        block_policies = validated.block_policies,
        stages = validated.stages,
        thresholds = validated.thresholds,
        gates = validated.gates,
        content_sha256 = validated.content_sha256,
        canonical_content =
            String(_canonical_content_bytes(source.document)),
        file_sha256 = bytes2hex(sha256(source.bytes)),
        file_byte_count = length(source.bytes),
    )
end

function _reject_forbidden_geometry_fields(value, location = "geometry")
    if value isa AbstractDict
        for (key, entry) in pairs(value)
            key isa AbstractString ||
                fail(location, "geometry keys must be strings")
            normalized = lowercase(String(key))
            for token in FORBIDDEN_GEOMETRY_FIELD_TOKENS
                occursin(token, normalized) &&
                    fail(
                    "$location.$key",
                    "field name contains forbidden token $(repr(token))",
                )
            end
            _reject_forbidden_geometry_fields(
                entry,
                "$location.$(String(key))",
            )
        end
    elseif value isa AbstractVector
        for (index, entry) in enumerate(value)
            _reject_forbidden_geometry_fields(entry, "$location[$index]")
        end
    end
    return nothing
end

function _validate_nonplaceholder_id(value, location)
    text = _expect_string(value, location)
    occursin(ID_PATTERN, text) ||
        fail(location, "contains unsupported characters")
    lowercase(text) in RESERVED_PLACEHOLDER_IDS &&
        fail(
        location,
        "reserved placeholder IDs are forbidden case-insensitively",
    )
    return text
end

function _parse_utc_timestamp(value, location)
    text = _expect_string(value, location)
    occursin(UTC_TIMESTAMP_PATTERN, text) ||
        fail(
        location,
        "must be an RFC3339 UTC timestamp at second precision",
    )
    parsed = try
        DateTime(text[1:(end - 1)], TIMESTAMP_FORMAT)
    catch
        fail(location, "must contain a valid calendar date and time")
    end
    return (; text, parsed)
end

function _parse_quarter(value, location)
    text = _expect_string(value, location)
    occursin(QUARTER_PATTERN, text) ||
        fail(location, "must use YYYYQn")
    year_number = parse(Int, text[1:4])
    quarter_number = parse(Int, text[end:end])
    ordinal = 4year_number + quarter_number - 1
    return (; text, year_number, quarter_number, ordinal)
end

function _parse_date(value, location)
    text = _expect_string(value, location)
    occursin(DATE_PATTERN, text) ||
        fail(location, "must use YYYY-MM-DD")
    parsed = try
        Date(text, dateformat"yyyy-mm-dd")
    catch
        fail(location, "must contain a valid calendar date")
    end
    string(parsed) == text ||
        fail(location, "must use canonical YYYY-MM-DD form")
    return (; text, parsed)
end

function _target_quarter_end(origin_quarter, horizon)
    target_ordinal = origin_quarter.ordinal + horizon
    year_number = fld(target_ordinal, 4)
    quarter_number = mod(target_ordinal, 4) + 1
    month_number = 3quarter_number
    return lastdayofmonth(Date(year_number, month_number, 1))
end

function _is_ordered_subsequence(values, registry)
    registry_position = 0
    for value in values
        next_position = findnext(
            candidate -> candidate == value,
            registry,
            registry_position + 1,
        )
        isnothing(next_position) && return false
        registry_position = next_position
    end
    return true
end

function _validate_geometry_row(row, sequence, model_ids)
    location = "geometry.origins[$sequence]"
    table = _expect_exact_keys(
        row,
        (
            "sequence",
            "origin_id",
            "origin_timestamp_utc",
            "origin_quarter",
            "target_dates",
            "mature_horizons",
            "eligible_model_ids",
            "eligible_target_ids",
            "available_windows",
            "regime_labels",
        ),
        location,
    )
    _expect_exact(
        _expect_integer(table["sequence"], "$location.sequence"; minimum = 1),
        sequence,
        "$location.sequence",
    )
    origin_id =
        _validate_nonplaceholder_id(table["origin_id"], "$location.origin_id")
    timestamp = _parse_utc_timestamp(
        table["origin_timestamp_utc"],
        "$location.origin_timestamp_utc",
    )
    origin_quarter =
        _parse_quarter(table["origin_quarter"], "$location.origin_quarter")
    timestamp_quarter = fld(month(timestamp.parsed) - 1, 3) + 1
    year(timestamp.parsed) == origin_quarter.year_number &&
        timestamp_quarter == origin_quarter.quarter_number ||
        fail(
        "$location.origin_quarter",
        "must contain origin_timestamp_utc",
    )
    target_date_values = _expect_vector(
        table["target_dates"],
        "$location.target_dates",
    )
    length(target_date_values) == length(HORIZONS) ||
        fail("$location.target_dates", "must contain one date per horizon")
    parsed_target_dates = Tuple(
        _parse_date(value, "$location.target_dates[$index]")
            for (index, value) in enumerate(target_date_values)
    )
    for (index, horizon) in enumerate(HORIZONS)
        expected = _target_quarter_end(origin_quarter, horizon)
        parsed_target_dates[index].parsed == expected ||
            fail(
            "$location.target_dates[$index]",
            "must equal quarter end $expected for horizon $horizon",
        )
    end
    target_dates = Tuple(value.text for value in parsed_target_dates)
    mature_horizons = Tuple(
        _expect_integer(value, "$location.mature_horizons"; minimum = 1)
            for value in _expect_vector(
                table["mature_horizons"],
                "$location.mature_horizons",
            )
    )
    !isempty(mature_horizons) ||
        fail("$location.mature_horizons", "must not be empty")
    all(horizon -> horizon in HORIZONS, mature_horizons) ||
        fail("$location.mature_horizons", "contains an unknown horizon")
    issorted(mature_horizons) ||
        fail("$location.mature_horizons", "must be sorted")
    length(mature_horizons) == length(unique(mature_horizons)) ||
        fail("$location.mature_horizons", "must be unique")
    mature_horizons == HORIZONS[1:length(mature_horizons)] ||
        fail(
        "$location.mature_horizons",
        "must be a downward-closed nonempty prefix of registered horizons",
    )
    eligible_models = Tuple(
        _expect_string(value, "$location.eligible_model_ids")
            for value in _expect_vector(
                table["eligible_model_ids"],
                "$location.eligible_model_ids",
            )
    )
    !isempty(eligible_models) ||
        fail("$location.eligible_model_ids", "must not be empty")
    all(model -> model in model_ids, eligible_models) ||
        fail("$location.eligible_model_ids", "contains an unknown model")
    length(eligible_models) == length(unique(eligible_models)) ||
        fail("$location.eligible_model_ids", "must be unique")
    _is_ordered_subsequence(eligible_models, model_ids) ||
        fail(
        "$location.eligible_model_ids",
        "must preserve model registry order",
    )
    eligible_targets = Tuple(
        _expect_string(value, "$location.eligible_target_ids")
            for value in _expect_vector(
                table["eligible_target_ids"],
                "$location.eligible_target_ids",
            )
    )
    !isempty(eligible_targets) ||
        fail("$location.eligible_target_ids", "must not be empty")
    all(target -> target in TARGET_IDS, eligible_targets) ||
        fail("$location.eligible_target_ids", "contains an unknown target")
    length(eligible_targets) == length(unique(eligible_targets)) ||
        fail("$location.eligible_target_ids", "must be unique")
    _is_ordered_subsequence(eligible_targets, TARGET_IDS) ||
        fail(
        "$location.eligible_target_ids",
        "must preserve target registry order",
    )
    windows = Tuple(
        _expect_string(value, "$location.available_windows")
            for value in _expect_vector(
                table["available_windows"],
                "$location.available_windows",
            )
    )
    !isempty(windows) ||
        fail("$location.available_windows", "must not be empty")
    all(window -> window in ESTIMATION_WINDOWS, windows) ||
        fail("$location.available_windows", "contains an unknown window")
    length(windows) == length(unique(windows)) ||
        fail("$location.available_windows", "must be unique")
    _is_ordered_subsequence(windows, ESTIMATION_WINDOWS) ||
        fail(
        "$location.available_windows",
        "must preserve estimation-window registry order",
    )
    regimes = Tuple(
        _expect_string(value, "$location.regime_labels")
            for value in _expect_vector(
                table["regime_labels"],
                "$location.regime_labels",
            )
    )
    !isempty(regimes) ||
        fail("$location.regime_labels", "must not be empty")
    all(regime -> regime in ALLOWED_REGIME_LABELS, regimes) ||
        fail(
        "$location.regime_labels",
        "contains an unknown, Used, Other, or unregistered regime",
    )
    length(regimes) == length(unique(regimes)) ||
        fail("$location.regime_labels", "must be unique")
    for (family_name, family) in (
            "pandemic" => PANDEMIC_REGIME_LABELS,
            "NBER" => NBER_REGIME_LABELS,
            "policy" => POLICY_REGIME_LABELS,
        )
        count(label -> label in family, regimes) == 1 ||
            fail(
            "$location.regime_labels",
            "must contain exactly one $family_name-family label",
        )
    end
    length(regimes) == 3 ||
        fail(
        "$location.regime_labels",
        "must contain exactly one label from each of three families",
    )
    return (;
        sequence,
        origin_id,
        origin_timestamp_utc = timestamp.text,
        origin_timestamp_value = timestamp.parsed,
        origin_quarter = origin_quarter.text,
        origin_quarter_ordinal = origin_quarter.ordinal,
        target_dates,
        mature_horizons,
        eligible_model_ids = eligible_models,
        eligible_target_ids = eligible_targets,
        available_windows = windows,
        regime_labels = regimes,
    )
end

"""
    validate_score_blind_geometry(document)

Validate a separately supplied geometry artifact. Field names containing any
forecast, truth, error, loss, score, rank, p-value, or effect token are
rejected recursively before schema validation.
"""
function validate_score_blind_geometry(document)
    _reject_forbidden_geometry_fields(document)
    root = _expect_exact_keys(
        document,
        ("artifact", "geometry", "origins"),
        "geometry",
    )
    artifact = _expect_exact_keys(
        root["artifact"],
        ("schema_version", "canonicalization", "content_sha256"),
        "geometry.artifact",
    )
    _expect_exact(
        artifact["schema_version"],
        GEOMETRY_SCHEMA_VERSION,
        "geometry.artifact.schema_version",
    )
    _expect_exact(
        artifact["canonicalization"],
        CANONICALIZATION,
        "geometry.artifact.canonicalization",
    )
    declared =
        _expect_hash(artifact["content_sha256"], "geometry.artifact.content_sha256")
    computed = computed_geometry_sha256(root)
    declared == computed ||
        fail(
        "geometry.artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    geometry = _expect_exact_keys(
        root["geometry"],
        (
            "geometry_id",
            "geometry_class",
            "origin_count",
            "model_ids",
            "target_ids",
            "horizons",
            "estimation_windows",
            "direction",
            "sesoi_registry_id",
            "regime_assignment_basis",
        ),
        "geometry.geometry",
    )
    geometry_id = _validate_nonplaceholder_id(
        geometry["geometry_id"],
        "geometry.geometry_id",
    )
    _expect_exact(
        geometry["geometry_class"],
        "SCORE_BLIND_ORIGIN_GEOMETRY",
        "geometry.geometry_class",
    )
    origin_count = _expect_integer(
        geometry["origin_count"],
        "geometry.origin_count";
        minimum = 2,
    )
    model_ids = Tuple(
        _validate_nonplaceholder_id(value, "geometry.model_ids")
            for value in _expect_vector(
                geometry["model_ids"],
                "geometry.model_ids",
            )
    )
    length(model_ids) == MODEL_COUNT ||
        fail("geometry.model_ids", "must contain exactly 11 model IDs")
    length(model_ids) == length(unique(model_ids)) ||
        fail("geometry.model_ids", "must be unique")
    all(model -> occursin(ID_PATTERN, model), model_ids) ||
        fail("geometry.model_ids", "contains unsupported characters")
    _expect_exact(
        Tuple(geometry["target_ids"]),
        TARGET_IDS,
        "geometry.target_ids",
    )
    geometry_horizons = Tuple(
        _expect_integer(value, "geometry.horizons"; minimum = 1)
            for value in _expect_vector(
                geometry["horizons"],
                "geometry.horizons",
            )
    )
    _expect_exact(
        geometry_horizons,
        HORIZONS,
        "geometry.horizons",
    )
    _expect_exact(
        Tuple(geometry["estimation_windows"]),
        ESTIMATION_WINDOWS,
        "geometry.estimation_windows",
    )
    _expect_exact(
        geometry["direction"],
        "CHALLENGER_MINUS_COMPARATOR",
        "geometry.direction",
    )
    _expect_exact(
        geometry["regime_assignment_basis"],
        REGIME_ASSIGNMENT_BASIS,
        "geometry.regime_assignment_basis",
    )
    sesoi_registry_id = _validate_nonplaceholder_id(
        geometry["sesoi_registry_id"],
        "geometry.sesoi_registry_id",
    )
    rows = _expect_vector(root["origins"], "geometry.origins")
    length(rows) == origin_count ||
        fail("geometry.origins", "row count does not match origin_count")
    validated_rows = Tuple(
        _validate_geometry_row(row, sequence, model_ids)
            for (sequence, row) in enumerate(rows)
    )
    origin_ids = getproperty.(validated_rows, :origin_id)
    length(origin_ids) == length(unique(origin_ids)) ||
        fail("geometry.origins", "origin_id values must be unique")
    timestamps = getproperty.(validated_rows, :origin_timestamp_value)
    issorted(timestamps; lt = <) ||
        fail("geometry.origins", "timestamps must be strictly increasing")
    length(timestamps) == length(unique(timestamps)) ||
        fail("geometry.origins", "timestamps must be unique")
    quarter_ordinals =
        getproperty.(validated_rows, :origin_quarter_ordinal)
    issorted(quarter_ordinals; lt = <) ||
        fail("geometry.origins", "origin quarters must be strictly increasing")
    length(quarter_ordinals) == length(unique(quarter_ordinals)) ||
        fail("geometry.origins", "origin quarters must be unique")
    return (;
        schema_version = GEOMETRY_SCHEMA_VERSION,
        canonicalization = CANONICALIZATION,
        geometry = (;
            geometry_id,
            geometry_class = :score_blind_origin_geometry,
            origin_count,
            model_ids,
            target_ids = TARGET_IDS,
            horizons = HORIZONS,
            estimation_windows = ESTIMATION_WINDOWS,
            direction = :challenger_minus_comparator,
            sesoi_registry_id,
            regime_assignment_basis = REGIME_ASSIGNMENT_BASIS,
        ),
        origins = validated_rows,
        content_sha256 = String(declared),
    )
end

function load_score_blind_geometry(path::AbstractString)
    source = _read_toml(path, "geometry")
    validated = validate_score_blind_geometry(source.document)
    return (;
        path = source.absolute,
        schema_version = validated.schema_version,
        canonicalization = validated.canonicalization,
        geometry = validated.geometry,
        origins = validated.origins,
        content_sha256 = validated.content_sha256,
        canonical_content =
            String(_canonical_content_bytes(source.document)),
        file_sha256 = bytes2hex(sha256(source.bytes)),
        file_byte_count = length(source.bytes),
    )
end

function _validate_identity(value, location)
    return _validate_nonplaceholder_id(value, location)
end

function _seed_payload(domain, components)
    io = IOBuffer()
    write(io, "USFCALIB-SEED-v1")
    write(io, UInt8(0))
    write(io, lowercase(string(MASTER_SEED; base = 16, pad = 16)))
    for component in (domain, components...)
        text = string(component)
        write(io, UInt8(0))
        write(io, string(ncodeunits(text)))
        write(io, UInt8(':'))
        write(io, text)
    end
    return take!(io)
end

function _derive_seed(domain, components...)
    digest = sha256(_seed_payload(domain, components))
    result = zero(UInt64)
    for byte in digest[1:8]
        result = (result << 8) | UInt64(byte)
    end
    return result
end

function _validate_seed_coordinates(stage, dgp, geometry_id, outer_replication)
    stage_id = _validate_identity(stage, "stage")
    stage_id in CALIBRATION_STAGES ||
        fail("stage", "is not a registered calibration stage")
    dgp_id = _validate_identity(dgp, "dgp")
    dgp_id in NULL_DGP_IDS ||
        fail("dgp", "is not a registered null DGP")
    geometry = _validate_identity(geometry_id, "geometry_id")
    outer = _expect_integer(
        outer_replication,
        "outer_replication";
        minimum = 1,
    )
    return (; stage_id, dgp_id, geometry, outer)
end

"""
    derive_dgp_seed(stage, dgp, geometry_id, outer_replication)

Derive a domain-separated `UInt64` DGP seed. Block policy is intentionally
absent, preserving common random numbers across policy candidates.
"""
function derive_dgp_seed(stage, dgp, geometry_id, outer_replication)
    coordinates = _validate_seed_coordinates(
        stage,
        dgp,
        geometry_id,
        outer_replication,
    )
    return _derive_seed(
        "DGP",
        coordinates.stage_id,
        coordinates.dgp_id,
        coordinates.geometry,
        coordinates.outer,
    )
end

"""
    derive_bootstrap_seed(stage, dgp, geometry_id, policy, outer_replication)

Derive a domain-separated bootstrap seed. The signature deliberately has no
model, target, horizon, or loss-family coordinate.
"""
function derive_bootstrap_seed(
        stage,
        dgp,
        geometry_id,
        policy,
        outer_replication,
    )
    coordinates = _validate_seed_coordinates(
        stage,
        dgp,
        geometry_id,
        outer_replication,
    )
    policy_id = _validate_identity(policy, "policy")
    policy_id in BLOCK_POLICY_IDS ||
        fail("policy", "is not a registered joint-family policy")
    return _derive_seed(
        "BOOTSTRAP",
        coordinates.stage_id,
        coordinates.dgp_id,
        coordinates.geometry,
        policy_id,
        coordinates.outer,
    )
end

function estimation_indices(
        origin_index::Integer,
        design::AbstractString;
        history_start::Integer = 1,
    )
    origin = _expect_integer(origin_index, "origin_index"; minimum = 2)
    first_history =
        _expect_integer(history_start, "history_start"; minimum = 1)
    first_history < origin ||
        fail("history_start", "must precede origin_index")
    design_id = _expect_string(design, "design")
    design_id in ESTIMATION_WINDOWS ||
        fail("design", "must be EXPANDING, ROLLING_40, or ROLLING_60")
    window_length = if design_id == "EXPANDING"
        origin - first_history
    elseif design_id == "ROLLING_40"
        40
    else
        60
    end
    origin - first_history >= window_length ||
        fail(
        "origin_index",
        "does not have enough prior history for $design_id",
    )
    first_index = design_id == "EXPANDING" ?
        first_history : origin - window_length
    indices = first_index:(origin - 1)
    maximum(indices) < origin ||
        fail("estimation_indices", "future leakage detected")
    return indices
end

function eligible_origin_indices(
        horizon::Integer,
        design::AbstractString;
        history_start::Integer = 1,
        initial_length::Integer = 40,
        maximum_target_index::Integer = 101,
    )
    h = _expect_integer(horizon, "horizon"; minimum = 1)
    h in HORIZONS || fail("horizon", "is not registered")
    start = _expect_integer(history_start, "history_start"; minimum = 1)
    initial =
        _expect_integer(initial_length, "initial_length"; minimum = 1)
    target_max = _expect_integer(
        maximum_target_index,
        "maximum_target_index";
        minimum = 1,
    )
    design_id = _expect_string(design, "design")
    design_id in ESTIMATION_WINDOWS ||
        fail("design", "is not registered")
    required = design_id == "ROLLING_60" ? 60 : initial
    first_origin = start + required
    last_origin = target_max - h + 1
    last_origin >= first_origin ||
        fail("geometry", "contains no eligible origin")
    origins = first_origin:last_origin
    for origin in origins
        maximum(estimation_indices(origin, design_id; history_start = start)) <
            origin ||
            fail("geometry", "future leakage detected")
        last_outcome = origin + h - 1
        last_outcome <= target_max ||
            fail("geometry", "target maturity overflow")
    end
    return origins
end

function overlap_correlation(horizon::Integer, displacement::Integer)
    h = _expect_integer(horizon, "horizon"; minimum = 1)
    k = _expect_integer(displacement, "displacement"; minimum = 0)
    h in HORIZONS || fail("horizon", "is not registered")
    return k < h ? (h - k) / h : 0.0
end

function target_factor_loadings(; strong_common::Bool = false)
    factor1 = [0.7, 0.4, -0.6, 0.3]
    factor2 = [0.0, 0.4, 0.1, 0.5]
    loadings = zeros(Float64, length(TARGET_IDS), 2 + length(TARGET_IDS))
    for target in eachindex(TARGET_IDS)
        first = factor1[target]
        second = factor2[target]
        common_variance = first^2 + second^2
        if strong_common
            common_variance > 0 ||
                fail("target_factor", "cannot rescale a zero common loading")
            scale = sqrt(0.7 / common_variance)
            first *= scale
            second *= scale
            common_variance = 0.7
        end
        common_variance <= 1 ||
            fail("target_factor", "common-factor variance exceeds one")
        loadings[target, 1] = first
        loadings[target, 2] = second
        loadings[target, 2 + target] = sqrt(1 - common_variance)
    end
    return loadings
end

function target_factor_covariance(; strong_common::Bool = false)
    loadings = target_factor_loadings(; strong_common)
    covariance = loadings * transpose(loadings)
    isapprox(
        covariance,
        transpose(covariance);
        rtol = 0,
        atol = 32eps(Float64),
    ) || fail("target_factor", "covariance is not symmetric")
    minimum(eigvals(Symmetric(covariance))) >= -128eps(Float64) ||
        fail("target_factor", "covariance is not positive semidefinite")
    all(isapprox.(diag(covariance), 1.0; rtol = 0, atol = 64eps(Float64))) ||
        fail("target_factor", "target variances must equal one")
    return covariance
end

function _student_t_draw(rng, degrees_freedom)
    numerator = randn(rng)
    denominator = 0.0
    for _ in 1:degrees_freedom
        value = randn(rng)
        denominator += value^2
    end
    return numerator / sqrt(denominator / degrees_freedom)
end

"""
    primitive_innovations(kind, count; seed, burn_in=2000)

Generate a standardized primitive series. AR and GARCH cases require at least
2,000 discarded observations. Student-t5 and t3 are variance-standardized;
t3 remains a squared-loss negative control because its fourth moment is
undefined.
"""
function primitive_innovations(
        kind::AbstractString,
        count::Integer;
        seed::Integer,
        burn_in::Integer = 2_000,
    )
    kind_id = _expect_string(kind, "kind")
    kind_id in (
        "IID_GAUSSIAN",
        "AR035",
        "AR075",
        "STUDENT_T5",
        "STUDENT_T3",
        "GARCH_010_085",
    ) || fail("kind", "is not a registered primitive")
    n = _expect_integer(count, "count"; minimum = 1)
    burn = _expect_integer(burn_in, "burn_in"; minimum = 0)
    if kind_id in ("AR035", "AR075", "GARCH_010_085")
        burn >= 2_000 ||
            fail("burn_in", "AR and GARCH primitives require at least 2000")
    end
    seed isa Bool && fail("seed", "must be an integer, not Bool")
    seed_value = try
        UInt64(seed)
    catch
        fail("seed", "must fit UInt64")
    end
    rng = MersenneTwister(seed_value)
    total = n + burn
    result = Vector{Float64}(undef, total)
    if kind_id == "IID_GAUSSIAN"
        randn!(rng, result)
    elseif kind_id in ("STUDENT_T5", "STUDENT_T3")
        degrees_freedom = kind_id == "STUDENT_T5" ? 5 : 3
        scale = sqrt((degrees_freedom - 2) / degrees_freedom)
        for index in eachindex(result)
            result[index] =
                scale * _student_t_draw(rng, degrees_freedom)
        end
    elseif kind_id in ("AR035", "AR075")
        rho = kind_id == "AR035" ? 0.35 : 0.75
        innovation_scale = sqrt(1 - rho^2)
        previous = randn(rng)
        for index in eachindex(result)
            previous = rho * previous + innovation_scale * randn(rng)
            result[index] = previous
        end
    else
        omega = 0.05
        alpha = 0.1
        beta = 0.85
        variance = omega / (1 - alpha - beta)
        previous = sqrt(variance) * randn(rng)
        for index in eachindex(result)
            variance = omega + alpha * previous^2 + beta * variance
            isfinite(variance) && variance > 0 ||
                fail("primitive", "GARCH variance became invalid")
            previous = sqrt(variance) * randn(rng)
            result[index] = previous
        end
    end
    kept = result[(burn + 1):end]
    all(isfinite, kept) ||
        fail("primitive", "generated a nonfinite value")
    return kept
end

function primitive_loss_eligibility(
        kind::AbstractString,
        loss::Symbol,
    )
    kind_id = _expect_string(kind, "kind")
    kind_id in (
        "IID_GAUSSIAN",
        "AR035",
        "AR075",
        "STUDENT_T5",
        "STUDENT_T3",
        "GARCH_010_085",
    ) || fail("kind", "is not a registered primitive")
    loss in (:squared, :absolute) ||
        fail("loss", "must be :squared or :absolute")
    if kind_id == "STUDENT_T3" && loss == :squared
        return (;
            eligible = false,
            role = :negative_control,
            reason = :undefined_fourth_moment,
        )
    elseif kind_id == "STUDENT_T3"
        return (;
            eligible = false,
            role = :boundary_diagnostic_only,
            reason = :not_primary_calibration_evidence,
        )
    end
    return (;
        eligible = true,
        role = :registered_synthetic_design,
        reason = :finite_required_moments,
    )
end

function apply_boundary_stress(
        values::AbstractVector{<:Real},
        stress::AbstractString,
    )
    any(value -> value isa Bool, values) &&
        fail("values", "must not contain Bool")
    result = Float64.(values)
    !isempty(result) || fail("values", "must be nonempty")
    all(isfinite, result) || fail("values", "must be finite")
    stress_id = _expect_string(stress, "stress")
    stress_id in (
        "NONE",
        "ACUTE_VARIANCE_9X",
        "PERMANENT_VARIANCE_4X",
        "WHOLE_SAMPLE_ZERO_MEAN_REVERSAL",
    ) || fail("stress", "is not registered")
    if stress_id == "ACUTE_VARIANCE_9X"
        length(result) >= 8 ||
            fail("values", "acute stress requires at least eight values")
        first_index = fld(length(result) - 8, 2) + 1
        result[first_index:(first_index + 7)] .*= 3
    elseif stress_id == "PERMANENT_VARIANCE_4X"
        first_index = fld(length(result), 2) + 1
        result[first_index:end] .*= 2
    elseif stress_id == "WHOLE_SAMPLE_ZERO_MEAN_REVERSAL"
        first_count = fld(length(result), 2)
        second_count = length(result) - first_count
        first_count >= 1 ||
            fail("values", "mean reversal requires at least two values")
        result[1:first_count] .+= 1
        result[(first_count + 1):end] .-= first_count / second_count
    end
    return result
end

function _component_series(kind, count, root_seed, component)
    seed = _derive_seed("PRIMITIVE", root_seed, component)
    return primitive_innovations(kind, count; seed, burn_in = 2_000)
end

function _validate_origin_vector(origin_indices, design)
    origins = Tuple(
        _expect_integer(value, "origin_indices"; minimum = 2)
            for value in origin_indices
    )
    !isempty(origins) || fail("origin_indices", "must be nonempty")
    issorted(origins) || fail("origin_indices", "must be sorted")
    length(origins) == length(unique(origins)) ||
        fail("origin_indices", "must be unique")
    for origin in origins
        estimation_indices(origin, design)
    end
    return origins
end

"""
    generate_null_forecast_errors(origin_indices; ...)

Generate an exchangeable 11-model null error tensor with dimensions
`origin × model × target × horizon`. Outcome innovations overlap
analytically across horizons; every estimation window ends before its
origin.
"""
function generate_null_forecast_errors(
        origin_indices;
        design::AbstractString,
        primitive_kind::AbstractString,
        seed::Integer,
        strong_common::Bool = false,
    )
    design_id = _expect_string(design, "design")
    design_id in ESTIMATION_WINDOWS ||
        fail("design", "is not registered")
    origins = _validate_origin_vector(origin_indices, design_id)
    seed isa Bool && fail("seed", "must be an integer, not Bool")
    root_seed = try
        UInt64(seed)
    catch
        fail("seed", "must fit UInt64")
    end
    timeline_count = maximum(origins) + maximum(HORIZONS) - 1
    loadings = target_factor_loadings(; strong_common)
    factor_components = [
        _component_series(
                primitive_kind,
                timeline_count,
                root_seed,
                "outcome_factor_$component",
            )
            for component in 1:size(loadings, 2)
    ]
    outcome = Matrix{Float64}(undef, timeline_count, length(TARGET_IDS))
    for time in 1:timeline_count, target in eachindex(TARGET_IDS)
        value = 0.0
        for component in 1:size(loadings, 2)
            value +=
                loadings[target, component] *
                factor_components[component][time]
        end
        outcome[time, target] = value
    end

    global_component = _component_series(
        primitive_kind,
        timeline_count,
        root_seed,
        "estimation_global",
    )
    target_components = [
        _component_series(
                primitive_kind,
                timeline_count,
                root_seed,
                "estimation_target_$target",
            )
            for target in eachindex(TARGET_IDS)
    ]
    model_components = [
        _component_series(
                primitive_kind,
                timeline_count,
                root_seed,
                "estimation_model_$model",
            )
            for model in 1:MODEL_COUNT
    ]
    idiosyncratic_components = [
        _component_series(
                primitive_kind,
                timeline_count,
                root_seed,
                "estimation_idio_$(model)_$(target)",
            )
            for model in 1:MODEL_COUNT, target in eachindex(TARGET_IDS)
    ]

    errors = Array{Float64}(
        undef,
        length(origins),
        MODEL_COUNT,
        length(TARGET_IDS),
        length(HORIZONS),
    )
    for (origin_position, origin) in enumerate(origins)
        window = estimation_indices(origin, design_id)
        window_length = length(window)
        for target in eachindex(TARGET_IDS)
            for (horizon_position, horizon) in enumerate(HORIZONS)
                future = origin:(origin + horizon - 1)
                minimum(future) > maximum(window) ||
                    fail("generator", "future outcome overlaps estimation")
                outcome_innovation =
                    sum(view(outcome, future, target)) / sqrt(horizon)
                for model in 1:MODEL_COUNT
                    disturbance_sum = 0.0
                    for time in window
                        disturbance_sum += 0.5 * (
                            global_component[time] +
                                target_components[target][time] +
                                model_components[model][time] +
                                idiosyncratic_components[model, target][time]
                        )
                    end
                    disturbance =
                        sqrt(40) / window_length * disturbance_sum
                    errors[
                        origin_position,
                        model,
                        target,
                        horizon_position,
                    ] = outcome_innovation +
                        0.35 * sqrt(horizon) * disturbance
                end
            end
        end
    end
    all(isfinite, errors) ||
        fail("generator", "forecast-error tensor contains nonfinite values")
    return (;
        origins,
        design = Symbol(lowercase(design_id)),
        primitive_kind = String(primitive_kind),
        seed = root_seed,
        strong_common,
        target_covariance = target_factor_covariance(; strong_common),
        errors,
    )
end

function hypothesis_mapping()
    rows = NamedTuple[]
    column = 0
    for comparison in 1:COMPARISON_COUNT
        for (target_position, target_id) in enumerate(TARGET_IDS)
            for (horizon_position, horizon) in enumerate(HORIZONS)
                column += 1
                comparison_id = "comparison$(comparison)"
                push!(
                    rows,
                    (;
                        column,
                        hypothesis_id =
                            "$(comparison_id)_$(target_id)_h$(horizon)",
                        comparison_id,
                        comparator_model_position = 1,
                        challenger_model_position = comparison + 1,
                        target_position,
                        target_id,
                        horizon_position,
                        horizon,
                    ),
                )
            end
        end
    end
    return Tuple(rows)
end

hypothesis_ids() =
    Tuple(row.hypothesis_id for row in hypothesis_mapping())

_hypothesis_horizons() =
    Tuple(row.horizon for row in hypothesis_mapping())

function family_loss_differentials(
        errors::AbstractArray{<:Real, 4};
        loss::Symbol,
    )
    size(errors, 2) == MODEL_COUNT ||
        fail("errors", "model dimension must equal 11")
    size(errors, 3) == length(TARGET_IDS) ||
        fail("errors", "target dimension must equal 4")
    size(errors, 4) == length(HORIZONS) ||
        fail("errors", "horizon dimension must equal 5")
    loss in (:squared, :absolute) ||
        fail("loss", "must be :squared or :absolute")
    n = size(errors, 1)
    result = Matrix{Float64}(undef, n, 200)
    mapping = hypothesis_mapping()
    for row in mapping
        result[:, row.column] = loss_differential(
            view(
                errors,
                :,
                row.challenger_model_position,
                row.target_position,
                row.horizon_position,
            ),
            view(
                errors,
                :,
                row.comparator_model_position,
                row.target_position,
                row.horizon_position,
            );
            loss,
        )
    end
    return (;
        mapping,
        hypothesis_ids =
            Tuple(row.hypothesis_id for row in mapping),
        horizons = Tuple(row.horizon for row in mapping),
        loss,
        differentials = result,
    )
end

function generate_direct_null_differentials(
        n::Integer;
        hypotheses::Integer = 200,
        seed::Integer,
    )
    observations = _expect_integer(n, "n"; minimum = 2)
    columns = _expect_integer(hypotheses, "hypotheses"; minimum = 1)
    seed isa Bool && fail("seed", "must be an integer, not Bool")
    rng = MersenneTwister(UInt64(seed))
    result = Matrix{Float64}(undef, observations, columns)
    randn!(rng, result)
    return result
end

@enum MissingnessPolicy begin
    COMPLETE
    TERMINAL_HORIZON_MATURITY
    COMMON_FOUR_ORIGIN_OUTAGE
    SCORE_BLIND_LAGGED_STATE
    TARGET_SPECIFIC_GAPS
    MODEL_EXECUTION_FAILURE
    OUTCOME_DEPENDENT_FORBIDDEN
end

function parse_missingness_policy(value::AbstractString)
    text = _expect_string(value, "missingness_policy")
    mapping = Dict(
        "COMPLETE" => COMPLETE,
        "TERMINAL_HORIZON_MATURITY" => TERMINAL_HORIZON_MATURITY,
        "COMMON_FOUR_ORIGIN_OUTAGE" => COMMON_FOUR_ORIGIN_OUTAGE,
        "SCORE_BLIND_LAGGED_STATE" => SCORE_BLIND_LAGGED_STATE,
        "TARGET_SPECIFIC_GAPS" => TARGET_SPECIFIC_GAPS,
        "MODEL_EXECUTION_FAILURE" => MODEL_EXECUTION_FAILURE,
        "OUTCOME_DEPENDENT_FORBIDDEN" => OUTCOME_DEPENDENT_FORBIDDEN,
    )
    haskey(mapping, text) ||
        fail(
        "missingness_policy",
        "unknown, Used, Other, and unregistered values are fatal",
    )
    return mapping[text]
end

function _hypothesis_target_positions()
    return Tuple(row.target_position for row in hypothesis_mapping())
end

function missingness_mask(
        policy::MissingnessPolicy;
        origin_count::Integer,
        minimum_retained_origins::Integer,
        outage_origins = (),
        lagged_state = (),
        target_gap_pairs = (),
        global_intersection_sealed::Bool = false,
    )
    n = _expect_integer(origin_count, "origin_count"; minimum = 1)
    minimum_retained = _expect_integer(
        minimum_retained_origins,
        "minimum_retained_origins";
        minimum = 2,
    )
    minimum_retained <= n ||
        fail(
        "minimum_retained_origins",
        "must not exceed origin_count",
    )
    mask = trues(n, 200)
    if policy == COMPLETE
        nothing
    elseif policy == TERMINAL_HORIZON_MATURITY
        n == 61 ||
            fail(
            "origin_count",
            "terminal rehearsal policy requires the 61-row geometry",
        )
        for (column, horizon) in enumerate(_hypothesis_horizons())
            retained = 62 - horizon
            retained < n && (mask[(retained + 1):end, column] .= false)
        end
    elseif policy == COMMON_FOUR_ORIGIN_OUTAGE
        outages = Tuple(
            _expect_integer(value, "outage_origins"; minimum = 1)
                for value in outage_origins
        )
        length(outages) == 4 &&
            length(outages) == length(unique(outages)) ||
            fail("outage_origins", "must contain exactly four unique rows")
        all(value -> value <= n, outages) ||
            fail("outage_origins", "contains an out-of-range row")
        mask[collect(outages), :] .= false
    elseif policy == SCORE_BLIND_LAGGED_STATE
        states = Tuple(lagged_state)
        length(states) == n ||
            fail("lagged_state", "must contain one Boolean per origin")
        all(value -> value isa Bool, states) ||
            fail("lagged_state", "must contain only Boolean values")
        for (row, retained) in enumerate(states)
            retained || (mask[row, :] .= false)
        end
    elseif policy == TARGET_SPECIFIC_GAPS
        global_intersection_sealed ||
            fail(
            "target_specific_gaps",
            "joint family aborts without a pre-sealed global intersection",
        )
        gaps = Tuple(target_gap_pairs)
        !isempty(gaps) ||
            fail("target_gap_pairs", "must not be empty")
        affected_origins = Int[]
        normalized_pairs = Tuple{Int, Int}[]
        for (index, pair) in enumerate(gaps)
            pair isa Tuple && length(pair) == 2 ||
                fail(
                "target_gap_pairs[$index]",
                "must be an (origin, target) tuple",
            )
            origin = _expect_integer(
                pair[1],
                "target_gap_pairs[$index].origin";
                minimum = 1,
            )
            target = _expect_integer(
                pair[2],
                "target_gap_pairs[$index].target";
                minimum = 1,
            )
            origin <= n ||
                fail("target_gap_pairs[$index].origin", "is out of range")
            target <= length(TARGET_IDS) ||
                fail("target_gap_pairs[$index].target", "is out of range")
            push!(affected_origins, origin)
            push!(normalized_pairs, (origin, target))
        end
        length(normalized_pairs) == length(unique(normalized_pairs)) ||
            fail("target_gap_pairs", "must not contain duplicate pairs")
        mask[unique(affected_origins), :] .= false
    elseif policy == MODEL_EXECUTION_FAILURE
        fail(
            "missingness_policy",
            "model-origin failure aborts the primary family",
        )
    else
        fail(
            "missingness_policy",
            "outcome-dependent masking is forbidden",
        )
    end
    retained_origins = Tuple(
        row for row in 1:n if all(view(mask, row, :))
    )
    length(retained_origins) >= minimum_retained ||
        fail(
        "missingness",
        "global intersection retained $(length(retained_origins)) " *
            "origins, below mandatory minimum $minimum_retained",
    )
    return (;
        policy,
        action = :complete_case_without_imputation,
        minimum_retained_origins = minimum_retained,
        retained_origins,
        mask,
    )
end

function false_null_mask(pattern::AbstractString)
    pattern_id = _expect_string(pattern, "false_null_pattern")
    pattern_id in FALSE_NULL_PATTERN_IDS ||
        fail(
        "false_null_pattern",
        "unknown, Used, Other, and unregistered values are fatal",
    )
    mask = falses(200)
    if pattern_id == "SINGLE"
        mask[1] = true
    elseif pattern_id == "TARGET5"
        mask[1:5] .= true
    elseif pattern_id == "MODEL20"
        mask[1:20] .= true
    else
        mask .= true
    end
    expected = Dict(
        "SINGLE" => 1,
        "TARGET5" => 5,
        "MODEL20" => 20,
        "DENSE200" => 200,
    )[pattern_id]
    count(mask) == expected ||
        fail("false_null_pattern", "internal cardinality mismatch")
    return mask
end

function block_policy(policy::AbstractString)
    policy_id = _expect_string(policy, "policy")
    policies = (
        J01 = (;
            policy_id = "J01",
            requested_block_length = 1.0,
            horizon_floor_policy = :none,
            joint_effective_block_length = 1.0,
        ),
        J02 = (;
            policy_id = "J02",
            requested_block_length = 4.0,
            horizon_floor_policy = :none,
            joint_effective_block_length = 4.0,
        ),
        J03 = (;
            policy_id = "J03",
            requested_block_length = 4.0,
            horizon_floor_policy = :max_horizon,
            joint_effective_block_length = 12.0,
        ),
        J04 = (;
            policy_id = "J04",
            requested_block_length = 24.0,
            horizon_floor_policy = :none,
            joint_effective_block_length = 24.0,
        ),
    )
    symbol = Symbol(policy_id)
    hasproperty(policies, symbol) ||
        fail("policy", "unknown, Used, Other, and unregistered values are fatal")
    return getproperty(policies, symbol)
end

function policy_indices(
        n::Integer,
        policy::AbstractString;
        seed::Integer,
        replicates::Integer,
    )
    metadata = block_policy(policy)
    result = stationary_bootstrap_indices(
        n,
        collect(HORIZONS);
        block_length = FixedBlockLength(metadata.requested_block_length),
        horizon_floor_policy = metadata.horizon_floor_policy,
        seed,
        replicates,
    )
    result.block_length.effective ==
        metadata.joint_effective_block_length ||
        fail("policy", "effective block length does not match protocol")
    return (;
        metadata,
        seed = result.seed,
        indices = result.indices,
    )
end

function _beta_quantile(probability, first_shape, second_shape)
    0 <= probability <= 1 ||
        fail("probability", "must be in [0, 1]")
    probability == 0 && return 0.0
    probability == 1 && return 1.0
    lower = 0.0
    upper = 1.0
    for _ in 1:180
        midpoint = (lower + upper) / 2
        cumulative =
            USForecastInference._regularized_incomplete_beta(
            midpoint,
            Float64(first_shape),
            Float64(second_shape),
        )
        if cumulative < probability
            lower = midpoint
        else
            upper = midpoint
        end
    end
    return (lower + upper) / 2
end

function _validate_binomial(successes, trials, confidence_level)
    count_success =
        _expect_integer(successes, "successes"; minimum = 0)
    count_trials = _expect_integer(trials, "trials"; minimum = 1)
    count_success <= count_trials ||
        fail("successes", "must not exceed trials")
    confidence = _expect_number(confidence_level, "confidence_level")
    0 < confidence < 1 ||
        fail("confidence_level", "must be strictly between zero and one")
    return (; count_success, count_trials, confidence)
end

function clopper_pearson_interval(
        successes::Integer,
        trials::Integer;
        confidence_level::Real = 0.99,
    )
    values = _validate_binomial(successes, trials, confidence_level)
    alpha = 1 - values.confidence
    lower = values.count_success == 0 ? 0.0 :
        _beta_quantile(
            alpha / 2,
            values.count_success,
            values.count_trials - values.count_success + 1,
        )
    upper = values.count_success == values.count_trials ? 1.0 :
        _beta_quantile(
            1 - alpha / 2,
            values.count_success + 1,
            values.count_trials - values.count_success,
        )
    return (;
        successes = values.count_success,
        trials = values.count_trials,
        confidence_level = values.confidence,
        lower,
        upper,
        sidedness = :two_sided,
    )
end

function clopper_pearson_upper(
        successes::Integer,
        trials::Integer;
        confidence_level::Real = 0.99,
    )
    values = _validate_binomial(successes, trials, confidence_level)
    upper = values.count_success == values.count_trials ? 1.0 :
        _beta_quantile(
            values.confidence,
            values.count_success + 1,
            values.count_trials - values.count_success,
        )
    return upper
end

function clopper_pearson_lower(
        successes::Integer,
        trials::Integer;
        confidence_level::Real = 0.99,
    )
    values = _validate_binomial(successes, trials, confidence_level)
    lower = values.count_success == 0 ? 0.0 :
        _beta_quantile(
            1 - values.confidence,
            values.count_success,
            values.count_trials - values.count_success + 1,
        )
    return lower
end

struct CalibrationShard
    stage::String
    configuration_id::String
    replication_ids::Tuple{Vararg{Int}}
    rejection_count::Int
    numeric_failure_count::Int
    payload_sha256::String
    shard_id::String

    function CalibrationShard(
            stage,
            configuration_id,
            replication_ids,
            rejection_count,
            numeric_failure_count,
            payload_sha256,
        )
        stage_id = _validate_identity(stage, "shard.stage")
        stage_id in CALIBRATION_STAGES ||
            fail("shard.stage", "is not registered")
        stage_id == "SMOKE" &&
            fail("shard.stage", "smoke outputs are not calibration shards")
        configuration =
            _validate_identity(configuration_id, "shard.configuration_id")
        replications = Tuple(
            _expect_integer(value, "shard.replication_ids"; minimum = 1)
                for value in replication_ids
        )
        !isempty(replications) ||
            fail("shard.replication_ids", "must not be empty")
        issorted(replications) ||
            fail("shard.replication_ids", "must be sorted")
        length(replications) == length(unique(replications)) ||
            fail("shard.replication_ids", "must be unique")
        rejected = _expect_integer(
            rejection_count,
            "shard.rejection_count";
            minimum = 0,
        )
        rejected <= length(replications) ||
            fail(
            "shard.rejection_count",
            "must not exceed replication count",
        )
        failures = _expect_integer(
            numeric_failure_count,
            "shard.numeric_failure_count";
            minimum = 0,
        )
        failures <= length(replications) ||
            fail(
            "shard.numeric_failure_count",
            "must not exceed replication count",
        )
        payload = _expect_hash(payload_sha256, "shard.payload_sha256")
        io = IOBuffer()
        print(
            io,
            "USFCALIB-SHARD-v1\n",
            stage_id,
            "\n",
            configuration,
            "\n",
            join(replications, ","),
            "\n",
            rejected,
            "\n",
            failures,
            "\n",
            payload,
        )
        identifier = bytes2hex(sha256(take!(io)))
        return new(
            stage_id,
            configuration,
            replications,
            rejected,
            failures,
            payload,
            identifier,
        )
    end
end

function calibration_shard(;
        stage,
        configuration_id,
        replication_ids,
        rejection_count,
        numeric_failure_count,
        payload_sha256,
    )
    return CalibrationShard(
        stage,
        configuration_id,
        replication_ids,
        rejection_count,
        numeric_failure_count,
        payload_sha256,
    )
end

function merge_shards(
        shards::AbstractVector{CalibrationShard};
        expected_replication_ids,
    )
    !isempty(shards) || fail("shards", "must not be empty")
    expected = Tuple(
        _expect_integer(value, "expected_replication_ids"; minimum = 1)
            for value in expected_replication_ids
    )
    !isempty(expected) ||
        fail("expected_replication_ids", "must not be empty")
    issorted(expected) ||
        fail("expected_replication_ids", "must be sorted")
    length(expected) == length(unique(expected)) ||
        fail("expected_replication_ids", "must be unique")
    stage = first(shards).stage
    configuration = first(shards).configuration_id
    all(shard -> shard.stage == stage, shards) ||
        fail("shards", "all stages must match")
    all(shard -> shard.configuration_id == configuration, shards) ||
        fail("shards", "all configuration IDs must match")
    ordered = sort(
        collect(shards);
        by = shard -> (first(shard.replication_ids), shard.shard_id),
        alg = MergeSort,
    )
    observed = Int[]
    for shard in ordered
        append!(observed, shard.replication_ids)
    end
    length(observed) == length(unique(observed)) ||
        fail("shards", "duplicate replication ID detected")
    observed_tuple = Tuple(sort(observed))
    observed_tuple == expected ||
        fail(
        "shards",
        "missing or unexpected replication IDs; expected $(expected), " *
            "got $(observed_tuple)",
    )
    rejection_count = sum(shard.rejection_count for shard in ordered)
    numeric_failure_count =
        sum(shard.numeric_failure_count for shard in ordered)
    io = IOBuffer()
    print(io, "USFCALIB-MERGE-v1\n", stage, "\n", configuration, "\n")
    for shard in ordered
        print(io, shard.shard_id, "\n")
    end
    print(io, rejection_count, "\n", numeric_failure_count)
    merge_sha256 = bytes2hex(sha256(take!(io)))
    return (;
        stage,
        configuration_id = configuration,
        replication_ids = observed_tuple,
        ordered_shard_ids = Tuple(shard.shard_id for shard in ordered),
        rejection_count,
        numeric_failure_count,
        merge_sha256,
    )
end

"""
    execution_authorization(stage; geometry_path=nothing,
                            expected_geometry_sha256=nothing,
                            explicit_expensive_mode=false)

Authorize only a non-evidentiary smoke action by default. Every registered
expensive stage requires a separately stored, valid score-blind geometry
artifact, an external expected semantic SHA-256, and an exact Boolean opt-in.
The external pin is the acceptance boundary against a modified file whose
internal digest was recomputed. This function does not run an experiment.
"""
function execution_authorization(
        stage::AbstractString;
        geometry_path::Union{Nothing, AbstractString} = nothing,
        expected_geometry_sha256::Union{Nothing, AbstractString} = nothing,
        explicit_expensive_mode::Bool = false,
    )
    stage_id = _expect_string(stage, "stage")
    stage_id in CALIBRATION_STAGES ||
        fail("stage", "is not registered")
    if stage_id == "SMOKE"
        explicit_expensive_mode &&
            fail("explicit_expensive_mode", "must be false for smoke")
        isnothing(geometry_path) ||
            fail("geometry_path", "must be absent for smoke")
        isnothing(expected_geometry_sha256) ||
            fail(
            "expected_geometry_sha256",
            "must be absent for smoke",
        )
        return (;
            stage = :smoke,
            authorized = true,
            evidentiary = false,
            geometry = nothing,
            calibration_evidence_created = false,
        )
    end
    explicit_expensive_mode ||
        fail(
        "explicit_expensive_mode",
        "must be true for a full calibration stage",
    )
    isnothing(geometry_path) &&
        fail(
        "geometry_path",
        "a separate score-blind geometry artifact is required",
    )
    isnothing(expected_geometry_sha256) &&
        fail(
        "expected_geometry_sha256",
        "an external expected geometry SHA-256 is required",
    )
    expected_digest = _expect_hash(
        expected_geometry_sha256,
        "expected_geometry_sha256",
    )
    geometry = load_score_blind_geometry(geometry_path)
    geometry.content_sha256 == expected_digest ||
        fail(
        "expected_geometry_sha256",
        "external pin $expected_digest does not match validated " *
            "geometry $(geometry.content_sha256)",
    )
    return (;
        stage = Symbol(lowercase(stage_id)),
        authorized = true,
        evidentiary = false,
        geometry = (;
            path = geometry.path,
            geometry_id = geometry.geometry.geometry_id,
            expected_content_sha256 = expected_digest,
            content_sha256 = geometry.content_sha256,
            file_sha256 = geometry.file_sha256,
        ),
        calibration_evidence_created = false,
    )
end

end
