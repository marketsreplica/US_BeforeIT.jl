module USCore3EquilibriumComparison

using SHA

const COMPONENT_DIRECTORY = @__DIR__
const FORECASTING_DIRECTORY = normpath(joinpath(COMPONENT_DIRECTORY, "..", ".."))
const US_PROJECT_DIRECTORY = normpath(joinpath(FORECASTING_DIRECTORY, ".."))
const SMALL_NK_SOURCE = joinpath(
    FORECASTING_DIRECTORY,
    "benchmarks",
    "small_nk_dsge",
    "USSmallNKDSGEMechanics.jl",
)
const SMALL_NK_FIXTURE = joinpath(
    FORECASTING_DIRECTORY,
    "benchmarks",
    "small_nk_dsge",
    "frbny_gensys_reference.toml",
)
const CORE3_SOURCE = joinpath(
    FORECASTING_DIRECTORY,
    "benchmarks",
    "core3_autoregressive",
    "USCore3AutoregressiveBenchmarks.jl",
)
const SCORING_SOURCE = joinpath(
    FORECASTING_DIRECTORY,
    "scoring",
    "USForecastScores.jl",
)
const INFERENCE_SOURCE = joinpath(
    FORECASTING_DIRECTORY,
    "inference",
    "USForecastInference.jl",
)
const US_PROJECT_FILE = joinpath(US_PROJECT_DIRECTORY, "Project.toml")
const US_MANIFEST_FILE = joinpath(US_PROJECT_DIRECTORY, "Manifest.toml")

const BOOTSTRAP_EXPECTED_HASHES = Dict(
    "small_nk_module" =>
        "2750a95581ba83bdac8578ccdc2cd290a265fa1968d74ddc3d10cfc56e26248a",
    "small_nk_fixture" =>
        "ec0a4a891e49e518ab5e08b98fdeda6b828f1b611600a3ddf4e198d0c70bc89e",
    "core3_module" =>
        "e8444761c55e199ab475eddca31a06c058b8fb2566ce721b186654190746f1c0",
    "scoring_module" =>
        "1cd04371f6cc882094f0a7520b3cbbe7e0d9aee5072f144f0436bea294db51db",
    "inference_module" =>
        "2115a85b27879c72ad43db5f864d4a10389893b20f42a46a93b818a12fe89975",
    "project_toml" =>
        "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
    "manifest_toml" =>
        "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
)
const BOOTSTRAP_PATHS = Dict(
    "small_nk_module" => SMALL_NK_SOURCE,
    "small_nk_fixture" => SMALL_NK_FIXTURE,
    "core3_module" => CORE3_SOURCE,
    "scoring_module" => SCORING_SOURCE,
    "inference_module" => INFERENCE_SOURCE,
    "project_toml" => US_PROJECT_FILE,
    "manifest_toml" => US_MANIFEST_FILE,
)
const EXPECTED_LOAD_PATH_TOKENS = ["@", "@v#.#", "@stdlib"]

struct BootstrapPreflightError <: Exception
    message::String
end

Base.showerror(io::IO, error::BootstrapPreflightError) = print(io, error.message)
bootstrap_fail(message) = throw(BootstrapPreflightError(String(message)))

function _bootstrap_reject_symbolic_path(path::AbstractString, location::AbstractString)
    current = abspath(path)
    while true
        islink(current) &&
            bootstrap_fail("$location contains a symbolic-link path component: $current")
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return nothing
end

function _bootstrap_metadata(file_status)
    return (
        file_status.device,
        file_status.inode,
        file_status.mode,
        file_status.nlink,
        file_status.uid,
        file_status.gid,
        file_status.size,
        file_status.mtime,
        file_status.ctime,
    )
end

function _bootstrap_read_exact_file(path, expected_sha256, location)
    path isa AbstractString || bootstrap_fail("$location path must be a string")
    expected_sha256 isa AbstractString ||
        bootstrap_fail("$location expected SHA-256 must be a string")
    occursin(r"^[0-9a-f]{64}$", expected_sha256) ||
        bootstrap_fail("$location expected SHA-256 must be lowercase hexadecimal")
    absolute = abspath(String(path))
    _bootstrap_reject_symbolic_path(absolute, location)
    isfile(absolute) || bootstrap_fail("$location must be a regular file: $absolute")
    before = stat(absolute)
    before.nlink == 1 ||
        bootstrap_fail("$location must have exactly one hard link: $absolute")
    bytes = read(absolute)
    after = stat(absolute)
    _bootstrap_metadata(before) == _bootstrap_metadata(after) ||
        bootstrap_fail("$location metadata changed while bytes were read")
    length(bytes) == before.size || bootstrap_fail("$location byte count changed while read")
    digest = bytes2hex(SHA.sha256(bytes))
    digest == expected_sha256 ||
        bootstrap_fail("$location SHA-256 mismatch: expected $expected_sha256, got $digest")
    return digest
end

function _bootstrap_preflight(; path_overrides = Dict{String, String}())
    path_overrides isa AbstractDict ||
        bootstrap_fail("bootstrap path overrides must be a map")
    paths = copy(BOOTSTRAP_PATHS)
    for (key, value) in path_overrides
        key isa AbstractString || bootstrap_fail("bootstrap override keys must be strings")
        name = String(key)
        haskey(paths, name) || bootstrap_fail("unknown bootstrap path override $name")
        value isa AbstractString ||
            bootstrap_fail("bootstrap path override $name must be a string")
        paths[name] = String(value)
    end
    Set(keys(paths)) == Set(keys(BOOTSTRAP_EXPECTED_HASHES)) ||
        bootstrap_fail("bootstrap path and expected-hash key sets differ")
    report = Dict{String, String}(
        name => _bootstrap_read_exact_file(
                paths[name],
                BOOTSTRAP_EXPECTED_HASHES[name],
                "bootstrap.$name",
            ) for name in sort!(collect(keys(paths)))
    )
    active_project = Base.active_project()
    active_project isa AbstractString ||
        bootstrap_fail("Base.active_project() must resolve the pinned scripts/us project")
    _bootstrap_reject_symbolic_path(active_project, "Base.active_project()")
    abspath(active_project) == abspath(paths["project_toml"]) || bootstrap_fail(
        "Base.active_project() is not the pinned scripts/us/Project.toml: " *
            "observed $active_project",
    )
    LOAD_PATH == EXPECTED_LOAD_PATH_TOKENS || bootstrap_fail(
        "LOAD_PATH tokens differ from the tested stack; expected " *
            "$(EXPECTED_LOAD_PATH_TOKENS), observed $(LOAD_PATH)",
    )
    resolved_load_path = Base.load_path()
    !isempty(resolved_load_path) && first(resolved_load_path) == abspath(active_project) ||
        bootstrap_fail("the first resolved LOAD_PATH entry is not Base.active_project()")
    return report
end

function _bootstrap_preflight_then(
        callback::Function;
        path_overrides = Dict{String, String}(),
    )
    report = _bootstrap_preflight(; path_overrides)
    return callback(report)
end

# This callback performs the first dependency includes in the module. The
# seven-file stdlib-only preflight above must return before it can be invoked.
const BOOTSTRAP_PREFLIGHT_REPORT = _bootstrap_preflight_then() do report
    Base.include(@__MODULE__, SMALL_NK_SOURCE)
    Base.include(@__MODULE__, CORE3_SOURCE)
    Base.include(@__MODULE__, SCORING_SOURCE)
    Base.include(@__MODULE__, INFERENCE_SOURCE)
    report
end

using LinearAlgebra
using Statistics

using .USCore3AutoregressiveBenchmarks
using .USForecastInference
using .USForecastScores
using .USSmallNKDSGEMechanics

export BootstrapPreflightError,
    ComparisonError,
    ComparisonResult,
    ForecastArchive,
    ForecastAttempt,
    JointScoreCell,
    PairedLossCell,
    PointDensityScoreCell,
    TrainingPrefix,
    TruthAttachment,
    attach_truth_after_lock,
    canonical_design,
    canonical_protocol_sha256,
    canonical_result_summary,
    dependency_pin_report,
    expected_regime_counts,
    load_canonical_training_prefixes,
    load_exact_truth_panel,
    regime_for_period,
    run_canonical_comparison,
    run_canonical_forecast_phase,
    run_forecast_phase,
    score_locked_archive,
    tested_runtime_report,
    validate_comparison_result,
    validate_dependency_pins,
    validate_forecast_archive,
    validate_tested_runtime,
    validate_truth_attachment

const SCHEMA_VERSION = "beforeit-us-core3-equilibrium-comparison.v1"
const PROTOCOL_ID = "revised-core3-equilibrium-vs-autoregressive-30-origin-v1"
const STATUS = "REVISED_CORE3_EQUILIBRIUM_COMPARISON_DESCRIPTIVE_NONADMITTING"
const INFORMATION_TRACK = "final_revised_mixed_vintage_descriptive_only"
const MODEL_SELECTION_TIMING =
    "RETROSPECTIVE_HINDSIGHT_EVALUATION_DESIGN_EXPOSED"
const POINT_ERROR_SIGN = "actual_minus_forecast_positive_means_underprediction"
const TARGET_PANEL_ID = "quarterly_nk3_aggregate_pce_contract_v1"
const TARGET_NAMES = (
    "real_gdp_growth",
    "pce_inflation",
    "effective_federal_funds_rate",
)
const TARGET_UNITS = (
    "annualized_quarter_over_quarter_percent",
    "annualized_quarter_over_quarter_percent",
    "quarterly_average_percent",
)

const SMALL_NK_MODULE_SHA256 = BOOTSTRAP_EXPECTED_HASHES["small_nk_module"]
const SMALL_NK_FIXTURE_SHA256 = BOOTSTRAP_EXPECTED_HASHES["small_nk_fixture"]
const SMALL_NK_MECHANICS_FINGERPRINT_SHA256 =
    "d45d4432c7e24bbe78e03c2953bd02cba52a89f942d45d9d6f11ad0fbc540e21"
const CORE3_MODULE_SHA256 = BOOTSTRAP_EXPECTED_HASHES["core3_module"]
const SCORING_MODULE_SHA256 = BOOTSTRAP_EXPECTED_HASHES["scoring_module"]
const INFERENCE_MODULE_SHA256 = BOOTSTRAP_EXPECTED_HASHES["inference_module"]
const US_PROJECT_SHA256 = BOOTSTRAP_EXPECTED_HASHES["project_toml"]
const US_MANIFEST_SHA256 = BOOTSTRAP_EXPECTED_HASHES["manifest_toml"]
const REVISED_MANIFEST_SHA256 =
    "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
const REVISED_PANEL_SHA256 =
    "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
const REVISED_RECEIPTS_SHA256 =
    "14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488"
const REVISED_CORE3_VALUES_SHA256 =
    "905875dbbf7dea22850776d94ee9a1c4ec7d92fc96c6ba3608d00d83a1e9a477"

const SMALL_NK_MODEL_ID = "nk3_aggregate_pce_small_nk_fixed_parameters_v1"
const AR_MODEL_ID = "nk3_aggregate_pce_univariate_ar1_ols_v1"
const VAR_MODEL_ID = "nk3_aggregate_pce_var1_ols_v1"
const BVAR_MODEL_ID = "nk3_aggregate_pce_bvar1_mniw_stationary_v1"
const MODEL_IDS = (SMALL_NK_MODEL_ID, AR_MODEL_ID, VAR_MODEL_ID, BVAR_MODEL_ID)
const COMPARATOR_MODEL_IDS = (AR_MODEL_ID, VAR_MODEL_ID, BVAR_MODEL_ID)
const CORE3_MODEL_CONTRACT_SHA256 = Dict(
    AR_MODEL_ID =>
        "0d33cbebb614794097f31f215fe8dd628a85120c0a198d429216bc37af771842",
    VAR_MODEL_ID =>
        "2860c9e0fe1e76e72e365cca1a93559d5adfb1b95755d27b3256ef48c987fc5c",
    BVAR_MODEL_ID =>
        "32c9c0c6409f521ba2e919b7bc2b36bc8a47e5217c5aedc6b0bbe019b6470fd6",
)

const ORIGIN_INDICES = collect(60:89)
const MAXIMUM_HORIZON = 12
const EVALUATION_HORIZONS = (1, 2, 4, 8, 12)
const CANONICAL_PATH_COUNT = 500
const MASE_SEASONALITY = 4
const INTERVAL_ALPHAS = (0.05, 0.2, 0.5)
const VARIOGRAM_ORDER = 0.5
const BASE_SEED = 0x3d32c84811a84b71
const SEED_SCHEME = "sha256-core3-comparison-model-origin-v1"
const REGIME_IDS = (
    "FULL",
    "PRE_PANDEMIC",
    "PANDEMIC_ACUTE",
    "POST_ACUTE",
)
const GATE_NAMES = (
    "origin_admissible",
    "scoring_eligible",
    "empirical_accuracy_evidence",
    "forecast_suitability_evidence",
    "confirmation_evidence",
    "registration_eligible",
    "promotion_eligible",
    "production_eligible",
)
const BLOCKERS = [
    "FINAL_REVISED_MIXED_VINTAGE_DATA_ONLY",
    "NO_AUTHENTICATED_HISTORICAL_ORIGIN",
    "FULL_REVISED_PANEL_MATERIALIZED_IN_FORECAST_PROCESS_BEFORE_PREFIX_EXTRACTION",
    "PREFIX_ONLY_MODEL_API_IS_NOT_PROCESS_LEVEL_FUTURE_BYTE_ISOLATION",
    "RETROSPECTIVE_DESIGN_RANKINGS_PREVIOUSLY_EXPOSED",
    "NO_ABM_COMMON_ORIGIN_COMPARISON",
    "SMALL_NK_PARAMETERS_FIXED_NOT_ESTIMATED",
    "SMALL_NK_ZERO_MEASUREMENT_ERROR",
    "SMALL_NK_PARAMETER_UNCERTAINTY_OMITTED",
    "NUMERICAL_BYTES_TESTED_ONLY_JULIA_1_10_3_DARWIN_AARCH64_APPLE_M1_ONE_JULIA_THREAD_LBT_ILP64_OPENBLAS_EIGHT_BLAS_THREADS",
    "JULIA_EXECUTABLE_STDLIB_SYSTEM_LIBRARY_AND_BLAS_BINARY_BYTES_NOT_PINNED",
    "CROSS_RUNTIME_CPU_OS_BLAS_AND_THREAD_CONFIGURATION_REPRODUCIBILITY_UNATTESTED",
    "LOAD_PATH_TOKENS_VALIDATED_BUT_GLOBAL_ENVIRONMENT_AND_STDLIB_BYTES_UNATTESTED",
    "DEPOT_PACKAGE_SOURCE_ARTIFACT_AND_COMPILED_CACHE_BYTES_NOT_ATTESTED",
    "NO_CONFIRMATORY_OR_PREREGISTERED_EVIDENCE",
    "ALL_ADMISSION_PROMOTION_PRODUCTION_SUITABILITY_GATES_FALSE",
]

const SMALL_NK_MODEL_CONTRACT_SHA256 =
    "5d1bd37ec4977b49b385b11f51b1b7c56726b6f36bc8bf2c0937fc40f24f582a"
const EXPECTED_PROTOCOL_SHA256 =
    "380720dd2d4a5548f7680d2a7b29107ee95344afe86ff2190a29c77f28329bc1"
const EXPECTED_CANONICAL_RESULT_SHA256 =
    "cd0cb535dfa023dd7d75d50783c259c378c88ad3d1b03fa5abbaf192e9a705cd"
const EXPECTED_CANONICAL_ARCHIVE_SHA256 =
    "a1f9dce55a2910a80e7de0b5c1f32371ee3252f8bd7fc95f1f0999e60b8c0212"
const EXPECTED_CANONICAL_TRUTH_ATTACHMENT_SHA256 =
    "9aa8614e1a92408f4fd92f751cc29cbf4a140970f1d72e8b122f8e057147d20d"

struct ComparisonError <: Exception
    code::Symbol
    message::String
end

Base.showerror(io::IO, error::ComparisonError) = print(io, error.message)
fail(code::Symbol, message) = throw(ComparisonError(code, String(message)))

const TESTED_RUNTIME_CEILING = Dict{String, Any}(
    "julia_version" => "1.10.3",
    "kernel" => "Darwin",
    "architecture" => "aarch64",
    "machine" => "arm64-apple-darwin22.4.0",
    "cpu_name" => "apple-m1",
    "word_size" => 64,
    "julia_threads" => 1,
    "blas_vendor" => "lbt",
    "blas_config" => "LBTConfig([ILP64] libopenblas64_.dylib)",
    "blas_threads" => 8,
)

function tested_runtime_report()
    return Dict{String, Any}(
        "julia_version" => string(VERSION),
        "kernel" => string(Sys.KERNEL),
        "architecture" => string(Sys.ARCH),
        "machine" => string(Sys.MACHINE),
        "cpu_name" => string(Sys.CPU_NAME),
        "word_size" => Sys.WORD_SIZE,
        "julia_threads" => Threads.nthreads(),
        "blas_vendor" => string(LinearAlgebra.BLAS.vendor()),
        "blas_config" => sprint(show, LinearAlgebra.BLAS.get_config()),
        "blas_threads" => LinearAlgebra.BLAS.get_num_threads(),
    )
end

function validate_tested_runtime()
    observed = tested_runtime_report()
    observed == TESTED_RUNTIME_CEILING || fail(
        :runtime_ceiling_mismatch,
        "runtime/BLAS configuration is outside the sole byte-tested ceiling; " *
            "expected $(TESTED_RUNTIME_CEILING), observed $observed",
    )
    return observed
end

struct TrainingPrefix
    origin_index::Int
    origin_key::String
    training_keys::Vector{String}
    forecast_keys::Vector{String}
    y_train::Matrix{Float64}
    target_names::Vector{String}
    target_units::Vector{String}
    manifest_sha256::String
    panel_sha256::String
    receipts_sha256::String
    core3_values_sha256::String
    training_sha256::String
    mase_scales::Vector{Float64}
    joint_centers::Vector{Float64}
    joint_scales::Vector{Float64}
end

struct ForecastAttempt
    status::String
    model_id::String
    model_contract_sha256::String
    origin_index::Int
    origin_key::String
    training_sha256::String
    forecast_keys::Vector{String}
    target_names::Vector{String}
    seed::Int
    path_count::Int
    point::Matrix{Float64}
    draws::Array{Float64, 3}
    upstream_content_sha256::Union{Nothing, String}
    diagnostics::Dict{String, Any}
    failure_code::Union{Nothing, String}
    failure_type::Union{Nothing, String}
    failure_message::Union{Nothing, String}
    gates::Dict{String, Bool}
    content_sha256::String
end

struct ForecastArchive
    schema_version::String
    protocol_id::String
    protocol_sha256::String
    status::String
    information_track::String
    model_selection_timing::String
    canonical_full_run::Bool
    maximum_horizon::Int
    evaluation_horizons::Vector{Int}
    path_count::Int
    prefixes::Vector{TrainingPrefix}
    attempts::Vector{ForecastAttempt}
    dependency_hashes::Dict{String, String}
    panel_hashes::Dict{String, String}
    blockers::Vector{String}
    gates::Dict{String, Bool}
    content_sha256::String
end

struct TruthAttachment
    schema_version::String
    archive_sha256::String
    panel_hashes::Dict{String, String}
    origin_indices::Vector{Int}
    forecast_keys::Matrix{String}
    truth::Array{Float64, 3}
    score_truth_attachment_loader_calls::Int
    forecast_lock_validated_before_score_truth_attachment::Bool
    content_sha256::String
end

struct PointDensityScoreCell
    model_id::String
    target_name::String
    horizon::Int
    regime::String
    n::Int
    mean_error::Float64
    rmse::Float64
    mae::Float64
    median_absolute_error::Float64
    mase::Float64
    empirical_m2_crps::Float64
    wis_50_80_95::Float64
    coverage_50::Float64
    width_50::Float64
    coverage_80::Float64
    width_80::Float64
    coverage_95::Float64
    width_95::Float64
end

struct JointScoreCell
    model_id::String
    horizon::Int
    regime::String
    n::Int
    energy_score::Float64
    variogram_score::Float64
end

struct PairedLossCell
    challenger_model_id::String
    comparator_model_id::String
    target_name::String
    horizon::Int
    regime::String
    loss::String
    n::Int
    mean_challenger_minus_comparator::Float64
    hln_dm_status::String
    hln_dm_reason::Union{Nothing, String}
    hln_dm_statistic::Union{Nothing, Float64}
    hln_dm_p_value::Union{Nothing, Float64}
    confidence_lower::Union{Nothing, Float64}
    confidence_upper::Union{Nothing, Float64}
end

struct ComparisonResult
    schema_version::String
    protocol_id::String
    protocol_sha256::String
    status::String
    information_track::String
    model_selection_timing::String
    point_error_sign::String
    mathematical_scores_computed::Bool
    repository_scoring_eligible::Bool
    archive_sha256::String
    truth_attachment_sha256::String
    point_density_scores::Vector{PointDensityScoreCell}
    joint_scores::Vector{JointScoreCell}
    paired_loss_cells::Vector{PairedLossCell}
    failed_attempts::Vector{String}
    exact_regime_counts::Dict{String, Vector{Int}}
    density_semantics::Dict{String, String}
    blockers::Vector{String}
    gates::Dict{String, Bool}
    content_sha256::String
end

_false_gates() = Dict{String, Bool}(name => false for name in GATE_NAMES)

function _validate_false_gates(gates)
    gates isa AbstractDict || fail(:invalid_gates, "gates must be a map")
    Set(String.(keys(gates))) == Set(GATE_NAMES) ||
        fail(:invalid_gates, "gate names differ from the closed protocol")
    for name in GATE_NAMES
        get(gates, name, nothing) === false ||
            fail(:gate_elevation, "gate $name must remain exactly false")
    end
    return gates
end

function dependency_pin_report(; path_overrides = Dict{String, String}())
    return try
        _bootstrap_preflight(; path_overrides)
    catch error
        error isa BootstrapPreflightError || rethrow()
        fail(:dependency_hash_mismatch, sprint(showerror, error))
    end
end

function validate_dependency_pins(; path_overrides = Dict{String, String}())
    observed = dependency_pin_report(; path_overrides)
    observed == BOOTSTRAP_EXPECTED_HASHES || fail(
        :dependency_hash_mismatch,
        "dependency, Project.toml, or Manifest.toml SHA-256 differs from the frozen protocol",
    )
    parameters = adapted_mechanics_parameters()
    system = build_canonical_system(parameters)
    solution = solve_gensys(system)
    measurement = build_measurement_system(parameters)
    mechanics_fingerprint(parameters, system, solution, measurement) ==
        SMALL_NK_MECHANICS_FINGERPRINT_SHA256 || fail(
        :mechanics_fingerprint_mismatch,
        "small-NK mechanics fingerprint differs from the frozen protocol",
    )
    for spec in default_core3_specs()
        expected_hash = get(CORE3_MODEL_CONTRACT_SHA256, model_id(spec), nothing)
        expected_hash === nothing && fail(:model_contract_mismatch, "unknown core3 model")
        model_contract_sha256(spec) == expected_hash || fail(
            :model_contract_mismatch,
            "core3 model contract differs for $(model_id(spec))",
        )
    end
    return observed
end

function _small_nk_contract_payload()
    return Dict{String, Any}(
        "model_id" => SMALL_NK_MODEL_ID,
        "family" => "fixed_parameter_small_new_keynesian_dsge",
        "target_panel_id" => TARGET_PANEL_ID,
        "target_names" => collect(TARGET_NAMES),
        "target_units" => collect(TARGET_UNITS),
        "mechanics_module_sha256" => SMALL_NK_MODULE_SHA256,
        "reference_fixture_sha256" => SMALL_NK_FIXTURE_SHA256,
        "mechanics_fingerprint_sha256" => SMALL_NK_MECHANICS_FINGERPRINT_SHA256,
        "parameter_estimation" => "none_fixed_before_score_exposure",
        "measurement_error" => "exactly_zero",
        "parameter_uncertainty" => false,
        "predictive_uncertainty" =>
            "filtered_state_uncertainty_and_future_structural_shocks_only",
        "filter" => "stationary_initialization_linear_gaussian",
        "maximum_horizon" => MAXIMUM_HORIZON,
        "future_truth_field_or_panel_reference_passed_to_model_api" => false,
        "process_level_future_byte_absence_proven" => false,
        "origin_admissible" => false,
        "forecast_suitability_evidence" => false,
    )
end

function _protocol_payload()
    return Dict{String, Any}(
        "schema_version" => SCHEMA_VERSION,
        "protocol_id" => PROTOCOL_ID,
        "status" => STATUS,
        "information_track" => INFORMATION_TRACK,
        "model_selection_timing" => MODEL_SELECTION_TIMING,
        "point_error_sign" => POINT_ERROR_SIGN,
        "mathematical_scores_computed_is_not_repository_scoring_eligible" => true,
        "target_panel_id" => TARGET_PANEL_ID,
        "target_names" => collect(TARGET_NAMES),
        "target_units" => collect(TARGET_UNITS),
        "origin_indices" => ORIGIN_INDICES,
        "origin_periods" => ["2015Q2", "2022Q3"],
        "maximum_horizon" => MAXIMUM_HORIZON,
        "evaluation_horizons" => collect(EVALUATION_HORIZONS),
        "path_count_per_model_origin" => CANONICAL_PATH_COUNT,
        "models" => collect(MODEL_IDS),
        "small_nk_contract_sha256" => SMALL_NK_MODEL_CONTRACT_SHA256,
        "core3_model_contract_sha256" => CORE3_MODEL_CONTRACT_SHA256,
        "dependency_hashes" => copy(BOOTSTRAP_EXPECTED_HASHES),
        "dependency_preflight" =>
            "stdlib_only_regular_file_no_symbolic_path_single_hard_link_stable_read_sha256_before_dependency_include",
        "active_project_requirement" =>
            "Base.active_project_exactly_pinned_scripts_us_Project_toml_before_dependency_include",
        "load_path_tokens" => copy(EXPECTED_LOAD_PATH_TOKENS),
        "load_path_limit" =>
            "active_entry_validated_global_environment_and_stdlib_bytes_unattested",
        "depot_and_cache_limit" =>
            "package_source_artifact_compiled_cache_and_depot_bytes_not_independently_attested",
        "canonical_entrypoint_module_preflight" =>
            "comparison_module_regular_file_no_symbolic_path_single_hard_link_stable_read_sha256_before_include",
        "tested_runtime_ceiling" => copy(TESTED_RUNTIME_CEILING),
        "runtime_bytes_pinned" => false,
        "runtime_attestation_limit" =>
            "Julia_executable_stdlib_system_library_and_BLAS_binary_bytes_not_pinned_other_configurations_unattested",
        "panel_hashes" => _expected_panel_hashes(),
        "forecast_strategy" =>
            "one_joint_12_quarter_run_per_model_origin_extract_1_2_4_8_12_without_restart",
        "forecast_process_input_limitation" =>
            "builder_materializes_full_revised_panel_same_process_then_executor_receives_owned_prefix_only_object",
        "prefix_api_barrier_is_process_isolation" => false,
        "process_level_future_byte_absence_proven" => false,
        "revised_prefix_dispatch_binding" =>
            "every_prefix_bit_rebound_to_freshly_loaded_exact_pinned_panel_before_model_dispatch",
        "archive_prefix_source_binding" =>
            "unconditional_bit_rebinding_to_one_fresh_exact_pinned_panel_for_replay_true_and_false_validation",
        "synthetic_core3_sample_role" =>
            "internal_transport_after_revised_prefix_rebinding_never_source_claim",
        "phase2_score_attachment_barrier" =>
            "forecast_content_replayed_and_locked_before_score_truth_attachment_callback",
        "phase2_callback_panel_validation" =>
            "full_axes_values_and_hashes_validated_then_bit_compared_to_fresh_exact_pinned_panel_before_truth_copy",
        "replay_identity" =>
            "complete_attempt_payload_identity_including_diagnostics_upstream_hash_and_failure_evidence",
        "mase_scale" => "origin_target_training_only_quarterly_seasonal_naive_lag_4",
        "joint_center" => "origin_target_training_only_arithmetic_mean",
        "joint_scale" => "origin_target_training_only_corrected_standard_deviation",
        "interval_miscoverage" => collect(INTERVAL_ALPHAS),
        "crps" => "equal_weight_empirical_distribution_m_squared_not_fair_u_statistic",
        "variogram_order" => VARIOGRAM_ORDER,
        "paired_loss_direction" =>
            "challenger_minus_comparator_negative_favors_challenger",
        "regimes" => collect(REGIME_IDS),
        "base_seed" => Int(BASE_SEED),
        "seed_scheme" => SEED_SCHEME,
        "gates" => _false_gates(),
        "blockers" => BLOCKERS,
    )
end

function canonical_protocol_sha256()
    digest = canonical_sha256(_protocol_payload())
    digest == EXPECTED_PROTOCOL_SHA256 ||
        fail(:protocol_mismatch, "closed protocol SHA-256 differs from its frozen identity")
    return digest
end

function canonical_design()
    return (
        protocol_id = PROTOCOL_ID,
        protocol_sha256 = canonical_protocol_sha256(),
        origin_indices = copy(ORIGIN_INDICES),
        evaluation_horizons = collect(EVALUATION_HORIZONS),
        maximum_horizon = MAXIMUM_HORIZON,
        path_count = CANONICAL_PATH_COUNT,
        model_selection_timing = MODEL_SELECTION_TIMING,
    )
end

_expected_panel_hashes() = Dict(
    "manifest_sha256" => REVISED_MANIFEST_SHA256,
    "panel_sha256" => REVISED_PANEL_SHA256,
    "receipts_sha256" => REVISED_RECEIPTS_SHA256,
    "core3_values_sha256" => REVISED_CORE3_VALUES_SHA256,
)

function _quarter_ordinal(period)
    period isa AbstractString || fail(:invalid_period, "period must be a string")
    text = String(period)
    match_result = match(r"^([0-9]{4})Q([1-4])$", text)
    match_result === nothing && fail(:invalid_period, "invalid quarter $text")
    return parse(Int, match_result.captures[1]) * 4 + parse(Int, match_result.captures[2])
end

function regime_for_period(period)
    ordinal = _quarter_ordinal(period)
    if ordinal <= _quarter_ordinal("2019Q4")
        return "PRE_PANDEMIC"
    elseif ordinal <= _quarter_ordinal("2021Q4")
        return "PANDEMIC_ACUTE"
    else
        return "POST_ACUTE"
    end
end

function expected_regime_counts()
    return Dict(
        "FULL" => [30, 30, 30, 30, 30],
        "PRE_PANDEMIC" => [18, 17, 15, 11, 7],
        "PANDEMIC_ACUTE" => [8, 8, 8, 8, 8],
        "POST_ACUTE" => [4, 5, 7, 11, 15],
    )
end

function _prefix_payload(prefix::TrainingPrefix)
    return Dict{String, Any}(
        "origin_index" => prefix.origin_index,
        "origin_key" => prefix.origin_key,
        "training_keys" => prefix.training_keys,
        "forecast_keys" => prefix.forecast_keys,
        "y_train" => prefix.y_train,
        "target_names" => prefix.target_names,
        "target_units" => prefix.target_units,
        "manifest_sha256" => prefix.manifest_sha256,
        "panel_sha256" => prefix.panel_sha256,
        "receipts_sha256" => prefix.receipts_sha256,
        "core3_values_sha256" => prefix.core3_values_sha256,
        "mase_scales" => prefix.mase_scales,
        "joint_centers" => prefix.joint_centers,
        "joint_scales" => prefix.joint_scales,
    )
end

function _validate_prefix(prefix::TrainingPrefix)
    prefix.origin_index isa Int || fail(:invalid_type, "origin index must be Int")
    length(prefix.training_keys) == prefix.origin_index ||
        fail(:prefix_mismatch, "training row count differs from origin index")
    length(prefix.forecast_keys) == MAXIMUM_HORIZON ||
        fail(:prefix_mismatch, "prefix must carry exactly 12 future labels")
    size(prefix.y_train) == (prefix.origin_index, 3) ||
        fail(:prefix_mismatch, "training matrix dimensions changed")
    prefix.origin_key == prefix.training_keys[end] ||
        fail(:prefix_mismatch, "origin key differs from last training key")
    prefix.target_names == collect(TARGET_NAMES) ||
        fail(:target_order_mismatch, "target order changed")
    prefix.target_units == collect(TARGET_UNITS) ||
        fail(:target_order_mismatch, "target units changed")
    all(isfinite, prefix.y_train) || fail(:nonfinite, "training matrix is nonfinite")
    all(isfinite, prefix.mase_scales) && all(>(0.0), prefix.mase_scales) ||
        fail(:invalid_scale, "MASE scales must be finite and positive")
    all(isfinite, prefix.joint_centers) ||
        fail(:invalid_scale, "joint centers must be finite")
    all(isfinite, prefix.joint_scales) && all(>(0.0), prefix.joint_scales) ||
        fail(:invalid_scale, "joint scales must be finite and positive")
    length(prefix.mase_scales) == 3 && length(prefix.joint_centers) == 3 &&
        length(prefix.joint_scales) == 3 || fail(:invalid_scale, "scale dimensions changed")
    Dict(
        "manifest_sha256" => prefix.manifest_sha256,
        "panel_sha256" => prefix.panel_sha256,
        "receipts_sha256" => prefix.receipts_sha256,
        "core3_values_sha256" => prefix.core3_values_sha256,
    ) == _expected_panel_hashes() ||
        fail(:panel_hash_mismatch, "prefix panel identities changed")
    canonical_sha256(_prefix_payload(prefix)) == prefix.training_sha256 ||
        fail(:training_hash_mismatch, "training prefix content changed")
    for index in 2:length(prefix.training_keys)
        _quarter_ordinal(prefix.training_keys[index]) ==
            _quarter_ordinal(prefix.training_keys[index - 1]) + 1 ||
            fail(:prefix_mismatch, "training quarter axis is not contiguous")
    end
    for (step, key) in enumerate(prefix.forecast_keys)
        _quarter_ordinal(key) == _quarter_ordinal(prefix.origin_key) + step ||
            fail(:prefix_mismatch, "forecast labels do not follow the origin")
    end
    recomputed_mase = [
        seasonal_naive_scale(view(prefix.y_train, :, target); seasonality = MASE_SEASONALITY)
            for target in 1:3
    ]
    reinterpret.(UInt64, recomputed_mase) == reinterpret.(UInt64, prefix.mase_scales) ||
        fail(:invalid_scale, "stored MASE scale is not training-derived")
    recomputed_centers = vec(mean(prefix.y_train; dims = 1))
    recomputed_joint_scales = vec(std(prefix.y_train; dims = 1, corrected = true))
    reinterpret.(UInt64, recomputed_centers) == reinterpret.(UInt64, prefix.joint_centers) ||
        fail(:invalid_scale, "stored joint centers are not training-derived")
    reinterpret.(UInt64, recomputed_joint_scales) ==
        reinterpret.(UInt64, prefix.joint_scales) ||
        fail(:invalid_scale, "stored joint scales are not training-derived")
    return prefix
end

function _load_fresh_exact_revised_panel()
    panel = load_revised_core3_panel()
    USCore3AutoregressiveBenchmarks._validate_revised_panel(panel)
    return panel
end

function _validate_revised_prefix_binding(
        prefix::TrainingPrefix,
        panel::Core3RevisedPanel,
    )
    _validate_prefix(prefix)
    USCore3AutoregressiveBenchmarks._validate_revised_panel(panel)
    prefix.origin_index + MAXIMUM_HORIZON <= length(panel.periods) ||
        fail(:prefix_source_mismatch, "prefix extends beyond the exact pinned panel")
    prefix.training_keys == panel.periods[1:prefix.origin_index] ||
        fail(:prefix_source_mismatch, "prefix training axis differs from the pinned panel")
    prefix.forecast_keys == panel.periods[
        (prefix.origin_index + 1):(prefix.origin_index + MAXIMUM_HORIZON),
    ] || fail(:prefix_source_mismatch, "prefix forecast axis differs from the pinned panel")
    _bits_equal(prefix.y_train, @view(panel.values[1:prefix.origin_index, :])) ||
        fail(
        :prefix_source_mismatch,
        "prefix training values differ bit-for-bit from the freshly loaded pinned panel",
    )
    Dict(
        "manifest_sha256" => prefix.manifest_sha256,
        "panel_sha256" => prefix.panel_sha256,
        "receipts_sha256" => prefix.receipts_sha256,
        "core3_values_sha256" => prefix.core3_values_sha256,
    ) == _expected_panel_hashes() ||
        fail(:panel_hash_mismatch, "prefix source labels differ from the pinned panel")
    return prefix
end


function _validate_revised_prefix_binding(prefix::TrainingPrefix)
    return _validate_revised_prefix_binding(prefix, _load_fresh_exact_revised_panel())
end

function _make_prefix(panel, origin_index::Int)
    sample = revised_core3_sample(panel, origin_index; horizon = MAXIMUM_HORIZON)
    y_train = copy(sample.y_train)
    Base.mightalias(y_train, panel.values) && fail(
        :prefix_alias_violation,
        "training prefix unexpectedly aliases the full revised panel",
    )
    mase_scales = [
        seasonal_naive_scale(view(y_train, :, target); seasonality = MASE_SEASONALITY)
            for target in 1:3
    ]
    centers = vec(mean(y_train; dims = 1))
    scales = vec(std(y_train; dims = 1, corrected = true))
    values = (
        origin_index,
        sample.origin_key,
        copy(sample.training_keys),
        copy(sample.forecast_keys),
        y_train,
        copy(sample.target_names),
        copy(sample.target_units),
        panel.manifest_sha256,
        panel.panel_sha256,
        panel.source_receipts_sha256,
        panel.core3_values_sha256,
    )
    unstamped = TrainingPrefix(values..., repeat("0", 64), mase_scales, centers, scales)
    prefix = TrainingPrefix(
        values...,
        canonical_sha256(_prefix_payload(unstamped)),
        mase_scales,
        centers,
        scales,
    )
    return _validate_revised_prefix_binding(prefix, panel)
end

function _validate_origin_indices(indices)
    indices isa AbstractVector || fail(:invalid_type, "origin indices must be a vector")
    isempty(indices) && fail(:invalid_origins, "origin indices must be nonempty")
    any(value -> value isa Bool, indices) &&
        fail(:invalid_type, "origin indices must not contain Bool")
    all(value -> value isa Integer, indices) ||
        fail(:invalid_type, "origin indices must contain integers")
    values = Int.(indices)
    issorted(values) && allunique(values) ||
        fail(:invalid_origins, "origin indices must be unique and sorted")
    all(value -> value in ORIGIN_INDICES, values) ||
        fail(:invalid_origins, "origin index lies outside frozen rows 60:89")
    return values
end

function load_canonical_training_prefixes(; origin_indices = ORIGIN_INDICES)
    validate_dependency_pins()
    indices = _validate_origin_indices(origin_indices)
    panel = load_revised_core3_panel()
    USCore3AutoregressiveBenchmarks._validate_revised_panel(panel)
    Dict(
        "manifest_sha256" => panel.manifest_sha256,
        "panel_sha256" => panel.panel_sha256,
        "receipts_sha256" => panel.source_receipts_sha256,
        "core3_values_sha256" => panel.core3_values_sha256,
    ) == _expected_panel_hashes() ||
        fail(:panel_hash_mismatch, "loaded revised panel identities changed")
    return [_make_prefix(panel, index) for index in indices]
end

function _seed_for(model::String, origin_index::Int)
    model in MODEL_IDS || fail(:unknown_model, "unknown model $model")
    bytes = SHA.sha256(
        string(SEED_SCHEME, "|", Int(BASE_SEED), "|", model, "|", origin_index),
    )
    value = zero(UInt64)
    for byte in bytes[1:8]
        value = (value << 8) | UInt64(byte)
    end
    return Int(value & UInt64(typemax(Int)))
end

function _synthetic_sample(prefix::TrainingPrefix)
    _validate_prefix(prefix)
    return synthetic_core3_sample(
        origin_id = "comparison-prefix-$(prefix.origin_key)",
        origin_key = prefix.origin_key,
        training_keys = prefix.training_keys,
        forecast_keys = prefix.forecast_keys,
        y_train = prefix.y_train,
    )
end

function _attempt_payload(attempt::ForecastAttempt)
    return Dict{String, Any}(
        "status" => attempt.status,
        "model_id" => attempt.model_id,
        "model_contract_sha256" => attempt.model_contract_sha256,
        "origin_index" => attempt.origin_index,
        "origin_key" => attempt.origin_key,
        "training_sha256" => attempt.training_sha256,
        "forecast_keys" => attempt.forecast_keys,
        "target_names" => attempt.target_names,
        "seed" => attempt.seed,
        "path_count" => attempt.path_count,
        "point" => attempt.point,
        "draws" => attempt.draws,
        "upstream_content_sha256" => attempt.upstream_content_sha256,
        "diagnostics" => attempt.diagnostics,
        "failure_code" => attempt.failure_code,
        "failure_type" => attempt.failure_type,
        "failure_message" => attempt.failure_message,
        "gates" => attempt.gates,
    )
end

function _model_contract_hash(model::String)
    model == SMALL_NK_MODEL_ID && return SMALL_NK_MODEL_CONTRACT_SHA256
    hash = get(CORE3_MODEL_CONTRACT_SHA256, model, nothing)
    hash === nothing && fail(:unknown_model, "unknown model $model")
    return hash
end

function _small_nk_forecast(prefix::TrainingPrefix, path_count::Int, seed::Int)
    parameters = adapted_mechanics_parameters()
    system = build_canonical_system(parameters)
    solution = solve_gensys(system)
    measurement = build_measurement_system(parameters)
    mechanics_fingerprint(parameters, system, solution, measurement) ==
        SMALL_NK_MECHANICS_FINGERPRINT_SHA256 ||
        fail(:mechanics_fingerprint_mismatch, "small-NK mechanics changed")
    filtered = filter_loglikelihood(copy(prefix.y_train), solution, measurement)
    moments = conditional_forecast_moments(
        filtered,
        solution,
        measurement,
        MAXIMUM_HORIZON,
    )
    draws = draw_joint_predictive_paths(
        filtered,
        solution,
        measurement,
        MAXIMUM_HORIZON,
        path_count;
        seed,
    )
    diagnostics = Dict{String, Any}(
        "filter_loglikelihood" => filtered.loglikelihood,
        "innovation_ranks" => filtered.innovation_ranks,
        "measurement_covariance_max_abs" => maximum(abs, measurement.measurement_covariance),
        "parameter_estimation" => "none_fixed_before_score_exposure",
        "parameter_uncertainty" => false,
        "state_uncertainty" => true,
        "future_structural_shock_uncertainty" => true,
        "future_truth_field_or_panel_reference_passed_to_executor" => false,
        "process_level_future_byte_absence_proven" => false,
        "revised_prefix_rebound_before_dispatch" => true,
        "source_binding_semantics" =>
            "fresh_exact_pinned_panel_bit_rebinding_before_model_API_call",
        "forecast_run_horizon" => MAXIMUM_HORIZON,
    )
    return copy(moments.means), draws, nothing, diagnostics
end

function _core_spec(model::String)
    for spec in default_core3_specs()
        model_id(spec) == model && return spec
    end
    return fail(:unknown_model, "unknown core3 model $model")
end

function _core3_forecast(
        model::String,
        prefix::TrainingPrefix,
        path_count::Int,
        seed::Int,
    )
    sample = _synthetic_sample(prefix)
    run = run_core3_benchmark(_core_spec(model), sample; n_draws = path_count, seed)
    run.status == :ok || fail(
        :upstream_forecast_failure,
        "$(run.model_id) failed: $(run.failure.code): $(run.failure.message)",
    )
    forecast = run.forecast
    diagnostics = Dict{String, Any}(
        "upstream_status" => forecast.status,
        "upstream_information_track" => forecast.information_track,
        "parameter_uncertainty" =>
            model == BVAR_MODEL_ID,
        "covariance_uncertainty" =>
            model == BVAR_MODEL_ID,
        "innovation_uncertainty" => true,
        "future_truth_field_or_panel_reference_passed_to_executor" => false,
        "process_level_future_byte_absence_proven" => false,
        "revised_prefix_rebound_before_dispatch" => true,
        "synthetic_core3_sample_role" =>
            "internal_transport_after_revised_prefix_rebinding_not_source_claim",
        "source_binding_semantics" =>
            "fresh_exact_pinned_panel_bit_rebinding_before_model_API_call",
        "forecast_run_horizon" => MAXIMUM_HORIZON,
    )
    return copy(forecast.point), copy(forecast.draws), forecast.content_sha256, diagnostics
end

function _execute_attempt(model::String, prefix::TrainingPrefix, path_count::Int)
    seed = _seed_for(model, prefix.origin_index)
    local attempt_values
    try
        point, draws, upstream_hash, diagnostics = if model == SMALL_NK_MODEL_ID
            _small_nk_forecast(prefix, path_count, seed)
        else
            _core3_forecast(model, prefix, path_count, seed)
        end
        attempt_values = (
            "ok",
            model,
            _model_contract_hash(model),
            prefix.origin_index,
            prefix.origin_key,
            prefix.training_sha256,
            copy(prefix.forecast_keys),
            collect(TARGET_NAMES),
            seed,
            path_count,
            point,
            draws,
            upstream_hash,
            diagnostics,
            nothing,
            nothing,
            nothing,
            _false_gates(),
        )
    catch error
        attempt_values = (
            "failed",
            model,
            _model_contract_hash(model),
            prefix.origin_index,
            prefix.origin_key,
            prefix.training_sha256,
            copy(prefix.forecast_keys),
            collect(TARGET_NAMES),
            seed,
            path_count,
            zeros(Float64, 0, 0),
            zeros(Float64, 0, 0, 0),
            nothing,
            Dict{String, Any}(
                "future_truth_field_or_panel_reference_passed_to_executor" => false,
                "process_level_future_byte_absence_proven" => false,
                "revised_prefix_rebound_before_dispatch" => true,
                "source_binding_semantics" =>
                    "fresh_exact_pinned_panel_bit_rebinding_before_model_API_call",
            ),
            error isa ComparisonError ? String(error.code) : "execution_failure",
            string(typeof(error)),
            sprint(showerror, error),
            _false_gates(),
        )
    end
    unstamped = ForecastAttempt(attempt_values..., repeat("0", 64))
    return ForecastAttempt(
        attempt_values...,
        canonical_sha256(_attempt_payload(unstamped)),
    )
end

function _dispatch_revised_attempt(
        model::String,
        prefix::TrainingPrefix,
        path_count::Int,
        source_panel::Core3RevisedPanel,
    )
    _validate_revised_prefix_binding(prefix, source_panel)
    return _execute_attempt(model, prefix, path_count)
end

function _bits_equal(left, right)
    size(left) == size(right) || return false
    for index in eachindex(left, right)
        reinterpret(UInt64, left[index]) == reinterpret(UInt64, right[index]) ||
            return false
    end
    return true
end

function _validate_attempt(
        attempt::ForecastAttempt,
        prefix::TrainingPrefix;
        replay = true,
        source_panel = nothing,
    )
    panel = if isnothing(source_panel)
        _load_fresh_exact_revised_panel()
    else
        source_panel isa Core3RevisedPanel ||
            fail(:invalid_source_panel, "source_panel must be Core3RevisedPanel")
        source_panel
    end
    _validate_revised_prefix_binding(prefix, panel)
    attempt.model_id in MODEL_IDS || fail(:unknown_model, "attempt model is unknown")
    attempt.origin_index == prefix.origin_index && attempt.origin_key == prefix.origin_key ||
        fail(:attempt_mismatch, "attempt origin differs from prefix")
    attempt.training_sha256 == prefix.training_sha256 ||
        fail(:attempt_mismatch, "attempt training identity differs from prefix")
    attempt.forecast_keys == prefix.forecast_keys ||
        fail(:attempt_mismatch, "attempt forecast labels differ from prefix")
    attempt.target_names == collect(TARGET_NAMES) ||
        fail(:target_order_mismatch, "attempt target order changed")
    attempt.model_contract_sha256 == _model_contract_hash(attempt.model_id) ||
        fail(:model_contract_mismatch, "attempt model contract changed")
    attempt.seed == _seed_for(attempt.model_id, prefix.origin_index) ||
        fail(:seed_mismatch, "attempt seed changed")
    attempt.path_count isa Int && attempt.path_count >= 1 ||
        fail(:invalid_path_count, "attempt path count must be a positive Int")
    _validate_false_gates(attempt.gates)
    canonical_sha256(_attempt_payload(attempt)) == attempt.content_sha256 ||
        fail(:attempt_hash_mismatch, "attempt content changed after phase lock")
    attempt.status in ("ok", "failed") || fail(:invalid_status, "attempt status changed")
    if attempt.status == "ok"
        size(attempt.point) == (MAXIMUM_HORIZON, 3) ||
            fail(:dimension_mismatch, "attempt point dimensions changed")
        size(attempt.draws) == (MAXIMUM_HORIZON, 3, attempt.path_count) ||
            fail(:dimension_mismatch, "attempt draw dimensions changed")
        all(isfinite, attempt.point) && all(isfinite, attempt.draws) ||
            fail(:nonfinite, "attempt contains nonfinite forecasts")
        all(isnothing, (attempt.failure_code, attempt.failure_type, attempt.failure_message)) ||
            fail(:invalid_failure, "successful attempt carries failure fields")
    else
        isempty(attempt.point) && isempty(attempt.draws) ||
            fail(:invalid_failure, "failed attempt carries forecast content")
        all(!isnothing, (attempt.failure_code, attempt.failure_type, attempt.failure_message)) ||
            fail(:invalid_failure, "failed attempt lacks visible failure fields")
    end
    if replay
        expected = _dispatch_revised_attempt(
            attempt.model_id,
            deepcopy(prefix),
            attempt.path_count,
            panel,
        )
        expected.content_sha256 == attempt.content_sha256 || fail(
            :replay_mismatch,
            "complete replay-derived attempt identity differs, including diagnostics, " *
                "upstream hash, or success/failure evidence",
        )
    end
    return attempt
end

function _archive_payload(archive::ForecastArchive)
    return Dict{String, Any}(
        "schema_version" => archive.schema_version,
        "protocol_id" => archive.protocol_id,
        "protocol_sha256" => archive.protocol_sha256,
        "status" => archive.status,
        "information_track" => archive.information_track,
        "model_selection_timing" => archive.model_selection_timing,
        "canonical_full_run" => archive.canonical_full_run,
        "maximum_horizon" => archive.maximum_horizon,
        "evaluation_horizons" => archive.evaluation_horizons,
        "path_count" => archive.path_count,
        "training_prefix_sha256" => [prefix.training_sha256 for prefix in archive.prefixes],
        "attempt_sha256" => [attempt.content_sha256 for attempt in archive.attempts],
        "dependency_hashes" => archive.dependency_hashes,
        "panel_hashes" => archive.panel_hashes,
        "blockers" => archive.blockers,
        "gates" => archive.gates,
    )
end

function run_forecast_phase(prefixes::Vector{TrainingPrefix}; path_count, require_canonical = false)
    path_count isa Integer && !(path_count isa Bool) ||
        fail(:invalid_path_count, "path_count must be an integer, not Bool")
    count = Int(path_count)
    count >= 1 || fail(:invalid_path_count, "path_count must be positive")
    isempty(prefixes) && fail(:invalid_origins, "prefix collection must be nonempty")
    source_panel = _load_fresh_exact_revised_panel()
    sealed_prefixes = TrainingPrefix[]
    for prefix in prefixes
        candidate = deepcopy(prefix)
        _validate_revised_prefix_binding(candidate, source_panel)
        push!(sealed_prefixes, candidate)
    end
    origin_indices = [prefix.origin_index for prefix in sealed_prefixes]
    issorted(origin_indices) && allunique(origin_indices) ||
        fail(:invalid_origins, "prefix origins must be unique and sorted")
    is_canonical = origin_indices == ORIGIN_INDICES && count == CANONICAL_PATH_COUNT &&
        tested_runtime_report() == TESTED_RUNTIME_CEILING
    require_canonical && !is_canonical && fail(
        :not_canonical_design,
        "canonical forecast phase requires all 30 origins and exactly 500 paths",
    )
    dependencies = validate_dependency_pins()
    attempts = ForecastAttempt[]
    for prefix in sealed_prefixes
        for model in MODEL_IDS
            # Narrow API property only: the builder already materialized the
            # full revised panel in this process before constructing `prefixes`.
            # `_dispatch_revised_attempt` uses `source_panel` only to rebind
            # the owned prefix bit-for-bit. The model executor beneath that
            # wrapper receives no panel reference, future-value view, score
            # callback, or sibling-origin collection. This is not
            # process-level future-byte isolation.
            push!(
                attempts,
                _dispatch_revised_attempt(
                    model,
                    deepcopy(prefix),
                    count,
                    source_panel,
                ),
            )
        end
    end
    values = (
        SCHEMA_VERSION,
        PROTOCOL_ID,
        canonical_protocol_sha256(),
        STATUS,
        INFORMATION_TRACK,
        MODEL_SELECTION_TIMING,
        is_canonical,
        MAXIMUM_HORIZON,
        collect(EVALUATION_HORIZONS),
        count,
        deepcopy(sealed_prefixes),
        attempts,
        dependencies,
        _expected_panel_hashes(),
        copy(BLOCKERS),
        _false_gates(),
    )
    unstamped = ForecastArchive(values..., repeat("0", 64))
    archive = ForecastArchive(values..., canonical_sha256(_archive_payload(unstamped)))
    return validate_forecast_archive(archive)
end

function run_canonical_forecast_phase()
    validate_tested_runtime()
    prefixes = load_canonical_training_prefixes()
    return run_forecast_phase(
        prefixes;
        path_count = CANONICAL_PATH_COUNT,
        require_canonical = true,
    )
end

function validate_forecast_archive(archive::ForecastArchive; replay = true)
    archive.schema_version == SCHEMA_VERSION || fail(:invalid_schema, "archive schema changed")
    archive.protocol_id == PROTOCOL_ID || fail(:protocol_mismatch, "archive protocol changed")
    archive.protocol_sha256 == canonical_protocol_sha256() ||
        fail(:protocol_mismatch, "archive protocol SHA-256 changed")
    archive.status == STATUS || fail(:invalid_status, "archive status changed")
    archive.information_track == INFORMATION_TRACK ||
        fail(:invalid_status, "archive information track changed")
    archive.model_selection_timing == MODEL_SELECTION_TIMING ||
        fail(:selection_timing_mismatch, "model-selection timing disclosure changed")
    archive.maximum_horizon == MAXIMUM_HORIZON ||
        fail(:design_mismatch, "maximum horizon changed")
    archive.evaluation_horizons == collect(EVALUATION_HORIZONS) ||
        fail(:design_mismatch, "evaluation horizons changed")
    archive.path_count isa Int && archive.path_count >= 1 ||
        fail(:invalid_path_count, "archive path count changed")
    archive.dependency_hashes == validate_dependency_pins() ||
        fail(:dependency_hash_mismatch, "archive dependency identities changed")
    archive.panel_hashes == _expected_panel_hashes() ||
        fail(:panel_hash_mismatch, "archive panel identities changed")
    archive.blockers == BLOCKERS || fail(:blocker_mismatch, "archive blockers changed")
    _validate_false_gates(archive.gates)
    isempty(archive.prefixes) && fail(:invalid_origins, "archive contains no prefixes")
    source_panel = _load_fresh_exact_revised_panel()
    for prefix in archive.prefixes
        _validate_revised_prefix_binding(prefix, source_panel)
    end
    expected_attempt_count = length(archive.prefixes) * length(MODEL_IDS)
    length(archive.attempts) == expected_attempt_count ||
        fail(:attempt_mismatch, "archive attempt count changed")
    cursor = 0
    for prefix in archive.prefixes
        for model in MODEL_IDS
            cursor += 1
            attempt = archive.attempts[cursor]
            attempt.model_id == model || fail(:attempt_mismatch, "attempt order changed")
            attempt.path_count == archive.path_count ||
                fail(:attempt_mismatch, "attempt path count differs from archive")
            _validate_attempt(attempt, prefix; replay, source_panel)
        end
    end
    expected_canonical =
        [prefix.origin_index for prefix in archive.prefixes] == ORIGIN_INDICES &&
        archive.path_count == CANONICAL_PATH_COUNT &&
        tested_runtime_report() == TESTED_RUNTIME_CEILING
    archive.canonical_full_run == expected_canonical ||
        fail(:design_mismatch, "canonical-run flag does not match archive geometry")
    canonical_sha256(_archive_payload(archive)) == archive.content_sha256 ||
        fail(:archive_hash_mismatch, "archive content changed after phase lock")
    archive.canonical_full_run &&
        archive.content_sha256 != EXPECTED_CANONICAL_ARCHIVE_SHA256 && fail(
        :archive_hash_mismatch,
        "canonical archive differs from its frozen result identity",
    )
    return archive
end

function load_exact_truth_panel()
    panel = load_revised_core3_panel()
    USCore3AutoregressiveBenchmarks._validate_revised_panel(panel)
    Dict(
        "manifest_sha256" => panel.manifest_sha256,
        "panel_sha256" => panel.panel_sha256,
        "receipts_sha256" => panel.source_receipts_sha256,
        "core3_values_sha256" => panel.core3_values_sha256,
    ) == _expected_panel_hashes() ||
        fail(:panel_hash_mismatch, "truth panel identities changed")
    return panel
end

function _validate_phase2_callback_panel(panel::Core3RevisedPanel)
    USCore3AutoregressiveBenchmarks._validate_revised_panel(panel)
    fresh = load_revised_core3_panel()
    USCore3AutoregressiveBenchmarks._validate_revised_panel(fresh)
    panel.periods == fresh.periods ||
        fail(:truth_mismatch, "phase-2 callback panel axis differs from the fresh pinned panel")
    _bits_equal(panel.values, fresh.values) || fail(
        :truth_mismatch,
        "phase-2 callback panel values differ bit-for-bit from the fresh pinned panel",
    )
    (
        panel.manifest_sha256,
        panel.panel_sha256,
        panel.source_receipts_sha256,
        panel.core3_values_sha256,
        panel.information_track,
    ) == (
        fresh.manifest_sha256,
        fresh.panel_sha256,
        fresh.source_receipts_sha256,
        fresh.core3_values_sha256,
        fresh.information_track,
    ) || fail(
        :panel_hash_mismatch,
        "phase-2 callback panel labels differ from the fresh pinned panel",
    )
    return panel
end

function _truth_payload(attachment::TruthAttachment)
    return Dict{String, Any}(
        "schema_version" => attachment.schema_version,
        "archive_sha256" => attachment.archive_sha256,
        "panel_hashes" => attachment.panel_hashes,
        "origin_indices" => attachment.origin_indices,
        "forecast_keys" => attachment.forecast_keys,
        "truth" => attachment.truth,
        "score_truth_attachment_loader_calls" =>
            attachment.score_truth_attachment_loader_calls,
        "forecast_lock_validated_before_score_truth_attachment" =>
            attachment.forecast_lock_validated_before_score_truth_attachment,
    )
end

function attach_truth_after_lock(
        archive::ForecastArchive;
        score_truth_loader = load_exact_truth_panel,
        score_attachment_counter = Ref(0),
    )
    score_attachment_counter isa Base.RefValue ||
        fail(:invalid_counter, "score-truth attachment counter must be a Ref")
    score_attachment_counter[] isa Integer &&
        !(score_attachment_counter[] isa Bool) ||
        fail(:invalid_counter, "score-truth attachment counter must contain an integer")
    score_attachment_counter[] == 0 || fail(
        :score_truth_attachment_order_violation,
        "phase-2 score-truth attachment callback was accessed before forecast validation",
    )
    validate_forecast_archive(archive; replay = true)
    score_attachment_counter[] += 1
    panel = score_truth_loader()
    panel isa Core3RevisedPanel || fail(
        :invalid_truth,
        "phase-2 score-truth attachment loader must return the exact core3 panel type",
    )
    _validate_phase2_callback_panel(panel)
    Dict(
        "manifest_sha256" => panel.manifest_sha256,
        "panel_sha256" => panel.panel_sha256,
        "receipts_sha256" => panel.source_receipts_sha256,
        "core3_values_sha256" => panel.core3_values_sha256,
    ) == archive.panel_hashes ||
        fail(:panel_hash_mismatch, "truth panel differs from archive panel identities")
    origin_count = length(archive.prefixes)
    keys = Matrix{String}(undef, origin_count, MAXIMUM_HORIZON)
    truth = Array{Float64, 3}(undef, origin_count, MAXIMUM_HORIZON, 3)
    for (origin_slot, prefix) in enumerate(archive.prefixes)
        panel.periods[1:prefix.origin_index] == prefix.training_keys ||
            fail(:prefix_source_mismatch, "training keys differ from exact truth panel prefix")
        _bits_equal(panel.values[1:prefix.origin_index, :], prefix.y_train) ||
            fail(:prefix_source_mismatch, "training values differ from exact panel prefix")
        expected_keys = panel.periods[
            (prefix.origin_index + 1):(prefix.origin_index + MAXIMUM_HORIZON),
        ]
        expected_keys == prefix.forecast_keys ||
            fail(:prefix_source_mismatch, "forecast labels differ from exact panel")
        keys[origin_slot, :] = expected_keys
        truth[origin_slot, :, :] = panel.values[
            (prefix.origin_index + 1):(prefix.origin_index + MAXIMUM_HORIZON),
            :,
        ]
    end
    values = (
        SCHEMA_VERSION,
        archive.content_sha256,
        copy(archive.panel_hashes),
        [prefix.origin_index for prefix in archive.prefixes],
        keys,
        truth,
        Int(score_attachment_counter[]),
        true,
    )
    unstamped = TruthAttachment(values..., repeat("0", 64))
    attachment = TruthAttachment(values..., canonical_sha256(_truth_payload(unstamped)))
    return validate_truth_attachment(attachment, archive)
end

function validate_truth_attachment(attachment::TruthAttachment, archive::ForecastArchive)
    validate_forecast_archive(archive; replay = false)
    attachment.schema_version == SCHEMA_VERSION ||
        fail(:invalid_schema, "truth attachment schema changed")
    attachment.archive_sha256 == archive.content_sha256 ||
        fail(:archive_hash_mismatch, "truth attachment references another archive")
    attachment.panel_hashes == archive.panel_hashes ||
        fail(:panel_hash_mismatch, "truth attachment panel identities changed")
    attachment.origin_indices == [prefix.origin_index for prefix in archive.prefixes] ||
        fail(:truth_mismatch, "truth origin indices changed")
    size(attachment.forecast_keys) == (length(archive.prefixes), MAXIMUM_HORIZON) ||
        fail(:dimension_mismatch, "truth key dimensions changed")
    size(attachment.truth) == (length(archive.prefixes), MAXIMUM_HORIZON, 3) ||
        fail(:dimension_mismatch, "truth dimensions changed")
    all(isfinite, attachment.truth) || fail(:nonfinite, "truth contains nonfinite values")
    attachment.score_truth_attachment_loader_calls == 1 || fail(
        :score_truth_attachment_order_violation,
        "phase-2 score-truth attachment callback count is not one",
    )
    attachment.forecast_lock_validated_before_score_truth_attachment === true || fail(
        :score_truth_attachment_order_violation,
        "forecast lock was not validated before phase-2 score-truth attachment",
    )
    for (slot, prefix) in enumerate(archive.prefixes)
        vec(attachment.forecast_keys[slot, :]) == prefix.forecast_keys ||
            fail(:truth_mismatch, "truth forecast keys differ from archive")
    end
    canonical_sha256(_truth_payload(attachment)) == attachment.content_sha256 ||
        fail(:truth_hash_mismatch, "truth attachment content changed")
    archive.canonical_full_run &&
        attachment.content_sha256 != EXPECTED_CANONICAL_TRUTH_ATTACHMENT_SHA256 && fail(
        :truth_hash_mismatch,
        "canonical truth attachment differs from its frozen result identity",
    )
    return attachment
end

function _attempt(archive::ForecastArchive, origin_slot::Int, model::String)
    model_slot = findfirst(==(model), MODEL_IDS)
    model_slot === nothing && fail(:unknown_model, "unknown model $model")
    return archive.attempts[(origin_slot - 1) * length(MODEL_IDS) + model_slot]
end

function _origin_slots_for_regime(
        attachment::TruthAttachment,
        horizon::Int,
        regime::String,
    )
    slots = collect(axes(attachment.truth, 1))
    regime == "FULL" && return slots
    regime in REGIME_IDS || fail(:unknown_regime, "unknown regime $regime")
    return [
        slot for slot in slots if
            regime_for_period(attachment.forecast_keys[slot, horizon]) == regime
    ]
end

function _mean_finite(values, location)
    isempty(values) && fail(:empty_score_cell, "$location has no observations")
    all(isfinite, values) || fail(:nonfinite, "$location contains nonfinite values")
    result = mean(values)
    isfinite(result) || fail(:nonfinite, "$location mean is nonfinite")
    return result
end

function _score_point_density_cell(
        archive,
        attachment,
        model,
        target_index,
        horizon,
        regime,
    )
    slots = _origin_slots_for_regime(attachment, horizon, regime)
    actual = [attachment.truth[slot, horizon, target_index] for slot in slots]
    forecast = [
        _attempt(archive, slot, model).point[horizon, target_index] for slot in slots
    ]
    scores = point_scores(actual, forecast)
    mase_values = Float64[]
    crps_values = Float64[]
    wis_values = Float64[]
    lower_by_alpha = Dict(alpha => Float64[] for alpha in INTERVAL_ALPHAS)
    upper_by_alpha = Dict(alpha => Float64[] for alpha in INTERVAL_ALPHAS)
    for (cell, slot) in enumerate(slots)
        attempt = _attempt(archive, slot, model)
        draws = vec(attempt.draws[horizon, target_index, :])
        scale = archive.prefixes[slot].mase_scales[target_index]
        single = point_scores(
            [actual[cell]],
            [forecast[cell]];
            mase_denominator = scale,
        )
        push!(mase_values, single.mase)
        push!(crps_values, ensemble_crps(actual[cell], draws))
        lowers = Float64[]
        uppers = Float64[]
        for alpha in INTERVAL_ALPHAS
            lower = quantile(draws, alpha / 2)
            upper = quantile(draws, 1 - alpha / 2)
            push!(lower_by_alpha[alpha], lower)
            push!(upper_by_alpha[alpha], upper)
            push!(lowers, lower)
            push!(uppers, upper)
        end
        push!(
            wis_values,
            weighted_interval_score(
                actual[cell],
                quantile(draws, 0.5),
                lowers,
                uppers,
                collect(INTERVAL_ALPHAS),
            ),
        )
    end
    summaries = Dict(
        alpha => coverage_summary(actual, lower_by_alpha[alpha], upper_by_alpha[alpha])
            for alpha in INTERVAL_ALPHAS
    )
    return PointDensityScoreCell(
        model,
        TARGET_NAMES[target_index],
        horizon,
        regime,
        length(slots),
        scores.mean_error,
        scores.rmse,
        scores.mae,
        scores.median_absolute_error,
        _mean_finite(mase_values, "MASE"),
        _mean_finite(crps_values, "empirical M-squared CRPS"),
        _mean_finite(wis_values, "WIS"),
        summaries[0.5].coverage,
        summaries[0.5].mean_width,
        summaries[0.2].coverage,
        summaries[0.2].mean_width,
        summaries[0.05].coverage,
        summaries[0.05].mean_width,
    )
end

function _score_joint_cell(archive, attachment, model, horizon, regime)
    slots = _origin_slots_for_regime(attachment, horizon, regime)
    energy_values = Float64[]
    variogram_values = Float64[]
    weights = ones(Float64, 3, 3) - Matrix{Float64}(I, 3, 3)
    for slot in slots
        attempt = _attempt(archive, slot, model)
        actual = vec(attachment.truth[slot, horizon, :])
        draws = permutedims(attempt.draws[horizon, :, :], (2, 1))
        prefix = archive.prefixes[slot]
        push!(energy_values, energy_score(actual, draws; scales = prefix.joint_scales))
        push!(
            variogram_values,
            variogram_score(
                actual,
                draws;
                centers = prefix.joint_centers,
                scales = prefix.joint_scales,
                weights,
                order = VARIOGRAM_ORDER,
            ),
        )
    end
    return JointScoreCell(
        model,
        horizon,
        regime,
        length(slots),
        _mean_finite(energy_values, "energy score"),
        _mean_finite(variogram_values, "variogram score"),
    )
end

function _paired_loss_cell(
        archive,
        attachment,
        comparator,
        target_index,
        horizon,
        regime,
        loss,
    )
    slots = _origin_slots_for_regime(attachment, horizon, regime)
    challenger_errors = [
        attachment.truth[slot, horizon, target_index] -
            _attempt(archive, slot, SMALL_NK_MODEL_ID).point[horizon, target_index]
            for slot in slots
    ]
    comparator_errors = [
        attachment.truth[slot, horizon, target_index] -
            _attempt(archive, slot, comparator).point[horizon, target_index]
            for slot in slots
    ]
    differential = loss_differential(
        challenger_errors,
        comparator_errors;
        loss = Symbol(loss),
    )
    mean_difference = _mean_finite(differential, "paired loss differential")
    hln_status = "not_computed"
    reason = nothing
    statistic = nothing
    p_value = nothing
    lower = nothing
    upper = nothing
    if length(differential) <= horizon
        reason = "HORIZON_NOT_SMALLER_THAN_PAIRED_COUNT"
    else
        try
            dm = hln_dm(differential, horizon)
            hln_status = "computed"
            statistic = dm.statistic
            p_value = dm.p_value
            lower = dm.confidence_lower
            upper = dm.confidence_upper
        catch error
            reason = "VISIBLE_HLN_DM_FAILURE:" * string(typeof(error)) * ":" *
                sprint(showerror, error)
        end
    end
    return PairedLossCell(
        SMALL_NK_MODEL_ID,
        comparator,
        TARGET_NAMES[target_index],
        horizon,
        regime,
        String(loss),
        length(differential),
        mean_difference,
        hln_status,
        reason,
        statistic,
        p_value,
        lower,
        upper,
    )
end

function _cell_payload(cell::PointDensityScoreCell)
    return Dict{String, Any}(String(field) => getfield(cell, field) for field in fieldnames(typeof(cell)))
end

function _cell_payload(cell::JointScoreCell)
    return Dict{String, Any}(String(field) => getfield(cell, field) for field in fieldnames(typeof(cell)))
end

function _cell_payload(cell::PairedLossCell)
    return Dict{String, Any}(String(field) => getfield(cell, field) for field in fieldnames(typeof(cell)))
end

function _result_payload(result::ComparisonResult)
    return Dict{String, Any}(
        "schema_version" => result.schema_version,
        "protocol_id" => result.protocol_id,
        "protocol_sha256" => result.protocol_sha256,
        "status" => result.status,
        "information_track" => result.information_track,
        "model_selection_timing" => result.model_selection_timing,
        "point_error_sign" => result.point_error_sign,
        "mathematical_scores_computed" => result.mathematical_scores_computed,
        "repository_scoring_eligible" => result.repository_scoring_eligible,
        "archive_sha256" => result.archive_sha256,
        "truth_attachment_sha256" => result.truth_attachment_sha256,
        "point_density_scores" => [_cell_payload(cell) for cell in result.point_density_scores],
        "joint_scores" => [_cell_payload(cell) for cell in result.joint_scores],
        "paired_loss_cells" => [_cell_payload(cell) for cell in result.paired_loss_cells],
        "failed_attempts" => result.failed_attempts,
        "exact_regime_counts" => result.exact_regime_counts,
        "density_semantics" => result.density_semantics,
        "blockers" => result.blockers,
        "gates" => result.gates,
    )
end

function score_locked_archive(archive::ForecastArchive, attachment::TruthAttachment)
    validate_forecast_archive(archive; replay = false)
    validate_truth_attachment(attachment, archive)
    archive.canonical_full_run || fail(
        :not_canonical_design,
        "empirical comparison scoring requires the exact 30-origin, 500-path archive",
    )
    failures = [
        "$(attempt.origin_key)|$(attempt.model_id)|$(attempt.failure_code)|$(attempt.failure_message)"
            for attempt in archive.attempts if attempt.status == "failed"
    ]
    isempty(failures) || fail(
        :visible_model_failures,
        "canonical scoring refused failed model attempts: " * join(failures, "; "),
    )
    point_density = PointDensityScoreCell[]
    joint = JointScoreCell[]
    paired = PairedLossCell[]
    for model in MODEL_IDS, horizon in EVALUATION_HORIZONS, regime in REGIME_IDS
        for target_index in eachindex(TARGET_NAMES)
            push!(
                point_density,
                _score_point_density_cell(
                    archive,
                    attachment,
                    model,
                    target_index,
                    horizon,
                    regime,
                ),
            )
        end
        push!(joint, _score_joint_cell(archive, attachment, model, horizon, regime))
    end
    for comparator in COMPARATOR_MODEL_IDS,
            target_index in eachindex(TARGET_NAMES),
            horizon in EVALUATION_HORIZONS,
            regime in REGIME_IDS,
            loss in ("squared", "absolute")
        push!(
            paired,
            _paired_loss_cell(
                archive,
                attachment,
                comparator,
                target_index,
                horizon,
                regime,
                loss,
            ),
        )
    end
    observed_counts = Dict(
        regime => [
                length(_origin_slots_for_regime(attachment, horizon, regime))
                for horizon in EVALUATION_HORIZONS
            ] for regime in REGIME_IDS
    )
    observed_counts == expected_regime_counts() ||
        fail(:regime_count_mismatch, "frozen regime counts changed")
    density_semantics = Dict(
        SMALL_NK_MODEL_ID =>
            "fixed_parameters_zero_measurement_error_state_and_shock_uncertainty_no_parameter_uncertainty",
        AR_MODEL_ID =>
            "plugin_gaussian_innovation_uncertainty_independent_targets_no_parameter_or_covariance_uncertainty",
        VAR_MODEL_ID =>
            "plugin_joint_gaussian_innovation_uncertainty_no_parameter_or_covariance_uncertainty",
        BVAR_MODEL_ID =>
            "mniw_parameter_covariance_and_joint_future_innovation_uncertainty",
        "crps" => "equal_weight_empirical_M_squared_not_fair",
    )
    values = (
        SCHEMA_VERSION,
        PROTOCOL_ID,
        canonical_protocol_sha256(),
        STATUS,
        INFORMATION_TRACK,
        MODEL_SELECTION_TIMING,
        POINT_ERROR_SIGN,
        true,
        false,
        archive.content_sha256,
        attachment.content_sha256,
        point_density,
        joint,
        paired,
        failures,
        observed_counts,
        density_semantics,
        copy(BLOCKERS),
        _false_gates(),
    )
    unstamped = ComparisonResult(values..., repeat("0", 64))
    result = ComparisonResult(values..., canonical_sha256(_result_payload(unstamped)))
    return validate_comparison_result(result, archive, attachment)
end

function validate_comparison_result(result, archive, attachment)
    validate_forecast_archive(archive; replay = false)
    validate_truth_attachment(attachment, archive)
    result.schema_version == SCHEMA_VERSION || fail(:invalid_schema, "result schema changed")
    result.protocol_id == PROTOCOL_ID && result.protocol_sha256 == canonical_protocol_sha256() ||
        fail(:protocol_mismatch, "result protocol changed")
    result.status == STATUS && result.information_track == INFORMATION_TRACK ||
        fail(:invalid_status, "result status changed")
    result.model_selection_timing == MODEL_SELECTION_TIMING ||
        fail(:selection_timing_mismatch, "result timing disclosure changed")
    result.point_error_sign == POINT_ERROR_SIGN ||
        fail(:score_semantics_mismatch, "point-error sign convention changed")
    result.mathematical_scores_computed === true ||
        fail(:score_semantics_mismatch, "mathematical score-computation flag changed")
    result.repository_scoring_eligible === false ||
        fail(:gate_elevation, "repository scoring-eligibility flag must remain false")
    result.archive_sha256 == archive.content_sha256 ||
        fail(:archive_hash_mismatch, "result archive identity changed")
    result.truth_attachment_sha256 == attachment.content_sha256 ||
        fail(:truth_hash_mismatch, "result truth identity changed")
    length(result.point_density_scores) == 4 * 5 * 4 * 3 ||
        fail(:score_geometry_mismatch, "point-density score geometry changed")
    length(result.joint_scores) == 4 * 5 * 4 ||
        fail(:score_geometry_mismatch, "joint score geometry changed")
    length(result.paired_loss_cells) == 3 * 3 * 5 * 4 * 2 ||
        fail(:score_geometry_mismatch, "paired score geometry changed")
    result.exact_regime_counts == expected_regime_counts() ||
        fail(:regime_count_mismatch, "result regime counts changed")
    isempty(result.failed_attempts) ||
        fail(:visible_model_failures, "canonical result must not hide model failures")
    result.blockers == BLOCKERS || fail(:blocker_mismatch, "result blockers changed")
    _validate_false_gates(result.gates)
    canonical_sha256(_result_payload(result)) == result.content_sha256 ||
        fail(:result_hash_mismatch, "comparison result content changed")
    archive.canonical_full_run &&
        result.content_sha256 != EXPECTED_CANONICAL_RESULT_SHA256 && fail(
        :result_hash_mismatch,
        "canonical comparison differs from its frozen result identity",
    )
    return result
end

function run_canonical_comparison()
    archive = run_canonical_forecast_phase()
    attachment = attach_truth_after_lock(archive)
    return score_locked_archive(archive, attachment)
end

function _find_point_cell(result, model, target, horizon, regime)
    matches = filter(
        cell -> cell.model_id == model && cell.target_name == target &&
            cell.horizon == horizon && cell.regime == regime,
        result.point_density_scores,
    )
    length(matches) == 1 || fail(:score_geometry_mismatch, "score cell is not unique")
    return only(matches)
end

function canonical_result_summary(result::ComparisonResult)
    rows = Dict{String, Any}[]
    for model in MODEL_IDS, target in TARGET_NAMES, horizon in EVALUATION_HORIZONS
        cell = _find_point_cell(result, model, target, horizon, "FULL")
        push!(
            rows,
            Dict{String, Any}(
                "model_id" => model,
                "target_name" => target,
                "horizon" => horizon,
                "n" => cell.n,
                "rmse" => cell.rmse,
                "mae" => cell.mae,
                "mase" => cell.mase,
                "empirical_m2_crps" => cell.empirical_m2_crps,
                "wis_50_80_95" => cell.wis_50_80_95,
                "coverage_50" => cell.coverage_50,
                "coverage_80" => cell.coverage_80,
                "coverage_95" => cell.coverage_95,
            ),
        )
    end
    return Dict{String, Any}(
        "protocol_sha256" => result.protocol_sha256,
        "archive_sha256" => result.archive_sha256,
        "truth_attachment_sha256" => result.truth_attachment_sha256,
        "result_sha256" => result.content_sha256,
        "status" => result.status,
        "model_selection_timing" => result.model_selection_timing,
        "point_error_sign" => result.point_error_sign,
        "mathematical_scores_computed" => result.mathematical_scores_computed,
        "repository_scoring_eligible" => result.repository_scoring_eligible,
        "full_sample_point_density_metrics" => rows,
        "regime_counts" => result.exact_regime_counts,
        "gates" => result.gates,
        "blockers" => result.blockers,
    )
end

end
