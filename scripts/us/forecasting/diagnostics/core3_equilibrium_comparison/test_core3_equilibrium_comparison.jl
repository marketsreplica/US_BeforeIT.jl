using SHA
using Test

const COMPONENT_DIR = @__DIR__
const MODULE_PATH = joinpath(COMPONENT_DIR, "USCore3EquilibriumComparison.jl")
const EXPECTED_COMPARISON_MODULE_SHA256 =
    "35fa2c699adee61bcb16d7eaf5b40a941122f851a5fcceb8e9e9e6f729025659"

struct ModulePreincludeError <: Exception
    message::String
end

Base.showerror(io::IO, error::ModulePreincludeError) = print(io, error.message)
module_preinclude_fail(message) = throw(ModulePreincludeError(String(message)))

function reject_symbolic_module_path(path)
    current = abspath(path)
    while true
        islink(current) &&
            module_preinclude_fail("comparison module path contains a symbolic link: $current")
        parent = dirname(current)
        parent == current && break
        current = parent
    end
    return nothing
end

function module_file_metadata(file_status)
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

function preinclude_comparison_module_then(
        callback::Function;
        module_path = MODULE_PATH,
        expected_sha256 = EXPECTED_COMPARISON_MODULE_SHA256,
    )
    occursin(r"^[0-9a-f]{64}$", expected_sha256) ||
        module_preinclude_fail("expected comparison module SHA-256 is malformed")
    absolute = abspath(module_path)
    reject_symbolic_module_path(absolute)
    isfile(absolute) || module_preinclude_fail("comparison module is not a regular file")
    before = stat(absolute)
    before.nlink == 1 ||
        module_preinclude_fail("comparison module must have exactly one hard link")
    bytes = read(absolute)
    after = stat(absolute)
    module_file_metadata(before) == module_file_metadata(after) ||
        module_preinclude_fail("comparison module metadata changed while read")
    length(bytes) == before.size ||
        module_preinclude_fail("comparison module byte count changed while read")
    digest = bytes2hex(SHA.sha256(bytes))
    digest == expected_sha256 || module_preinclude_fail(
        "comparison module SHA-256 mismatch: expected $expected_sha256, got $digest",
    )
    return callback(digest)
end

const PREINCLUDE_COMPARISON_MODULE_SHA256 = preinclude_comparison_module_then() do digest
    Base.include(@__MODULE__, MODULE_PATH)
    digest
end
using .USCore3EquilibriumComparison

const M = USCore3EquilibriumComparison

function restamp_attempt(
        attempt;
        point = attempt.point,
        gates = attempt.gates,
        status = attempt.status,
        training_sha256 = attempt.training_sha256,
        diagnostics = attempt.diagnostics,
        upstream_content_sha256 = attempt.upstream_content_sha256,
        failure_code = attempt.failure_code,
        failure_type = attempt.failure_type,
        failure_message = attempt.failure_message,
    )
    values = (
        status,
        attempt.model_id,
        attempt.model_contract_sha256,
        attempt.origin_index,
        attempt.origin_key,
        training_sha256,
        copy(attempt.forecast_keys),
        copy(attempt.target_names),
        attempt.seed,
        attempt.path_count,
        copy(point),
        copy(attempt.draws),
        upstream_content_sha256,
        deepcopy(diagnostics),
        failure_code,
        failure_type,
        failure_message,
        copy(gates),
    )
    unstamped = ForecastAttempt(values..., repeat("0", 64))
    return ForecastAttempt(values..., M.canonical_sha256(M._attempt_payload(unstamped)))
end

function restamp_prefix(prefix; y_train = prefix.y_train)
    matrix = copy(y_train)
    mase_scales = [
        M.seasonal_naive_scale(view(matrix, :, target); seasonality = M.MASE_SEASONALITY)
            for target in 1:3
    ]
    joint_centers = vec(M.mean(matrix; dims = 1))
    joint_scales = vec(M.std(matrix; dims = 1, corrected = true))
    values = (
        prefix.origin_index,
        prefix.origin_key,
        copy(prefix.training_keys),
        copy(prefix.forecast_keys),
        matrix,
        copy(prefix.target_names),
        copy(prefix.target_units),
        prefix.manifest_sha256,
        prefix.panel_sha256,
        prefix.receipts_sha256,
        prefix.core3_values_sha256,
    )
    unstamped = TrainingPrefix(
        values...,
        repeat("0", 64),
        mase_scales,
        joint_centers,
        joint_scales,
    )
    return TrainingPrefix(
        values...,
        M.canonical_sha256(M._prefix_payload(unstamped)),
        mase_scales,
        joint_centers,
        joint_scales,
    )
end

function restamp_archive(archive)
    values = (
        archive.schema_version,
        archive.protocol_id,
        archive.protocol_sha256,
        archive.status,
        archive.information_track,
        archive.model_selection_timing,
        archive.canonical_full_run,
        archive.maximum_horizon,
        copy(archive.evaluation_horizons),
        archive.path_count,
        deepcopy(archive.prefixes),
        deepcopy(archive.attempts),
        copy(archive.dependency_hashes),
        copy(archive.panel_hashes),
        copy(archive.blockers),
        copy(archive.gates),
    )
    unstamped = ForecastArchive(values..., repeat("0", 64))
    return ForecastArchive(values..., M.canonical_sha256(M._archive_payload(unstamped)))
end

@testset "stdlib-only bootstrap and module preinclude barriers" begin
    @test PREINCLUDE_COMPARISON_MODULE_SHA256 == EXPECTED_COMPARISON_MODULE_SHA256
    @test abspath(Base.active_project()) == abspath(M.US_PROJECT_FILE)
    @test LOAD_PATH == M.EXPECTED_LOAD_PATH_TOKENS
    @test first(Base.load_path()) == abspath(M.US_PROJECT_FILE)
    @test M.BOOTSTRAP_PREFLIGHT_REPORT == M.BOOTSTRAP_EXPECTED_HASHES

    source = read(MODULE_PATH, String)
    preflight_invocation = findfirst(
        "const BOOTSTRAP_PREFLIGHT_REPORT = _bootstrap_preflight_then()",
        source,
    )
    first_dependency_include = findfirst(
        "Base.include(@__MODULE__, SMALL_NK_SOURCE)",
        source,
    )
    @test !isnothing(preflight_invocation)
    @test !isnothing(first_dependency_include)
    @test first(preflight_invocation) < first(first_dependency_include)

    mktempdir() do directory
        tampered_module = joinpath(directory, "USCore3EquilibriumComparison.jl")
        write(tampered_module, read(MODULE_PATH), UInt8('\n'))
        callback_calls = Ref(0)
        @test_throws ModulePreincludeError preinclude_comparison_module_then(
            _ -> (callback_calls[] += 1);
            module_path = tampered_module,
        )
        @test callback_calls[] == 0
    end

    for dependency_name in ("core3_module", "project_toml", "manifest_toml")
        mktempdir() do directory
            changed = joinpath(directory, basename(M.BOOTSTRAP_PATHS[dependency_name]))
            write(changed, read(M.BOOTSTRAP_PATHS[dependency_name]), UInt8('\n'))
            callback_calls = Ref(0)
            @test_throws BootstrapPreflightError M._bootstrap_preflight_then(
                _ -> (callback_calls[] += 1);
                path_overrides = Dict(dependency_name => changed),
            )
            @test callback_calls[] == 0
        end
    end

    mktempdir() do directory
        hardlinked = joinpath(directory, "hardlinked-core3.jl")
        Base.Filesystem.hardlink(M.CORE3_SOURCE, hardlinked)
        callback_calls = Ref(0)
        @test_throws BootstrapPreflightError M._bootstrap_preflight_then(
            _ -> (callback_calls[] += 1);
            path_overrides = Dict("core3_module" => hardlinked),
        )
        @test callback_calls[] == 0
    end

    mktempdir() do directory
        linked = joinpath(directory, "linked-core3.jl")
        symlink(M.CORE3_SOURCE, linked)
        callback_calls = Ref(0)
        @test_throws BootstrapPreflightError M._bootstrap_preflight_then(
            _ -> (callback_calls[] += 1);
            path_overrides = Dict("core3_module" => linked),
        )
        @test callback_calls[] == 0
    end

    original_load_path = copy(LOAD_PATH)
    callback_calls = Ref(0)
    try
        push!(LOAD_PATH, "bootstrap-mismatch-test")
        @test_throws BootstrapPreflightError M._bootstrap_preflight_then(
            _ -> (callback_calls[] += 1),
        )
    finally
        empty!(LOAD_PATH)
        append!(LOAD_PATH, original_load_path)
    end
    @test callback_calls[] == 0
end

@testset "closed dependency and design identities" begin
    observed = validate_dependency_pins()
    @test observed["small_nk_module"] == M.SMALL_NK_MODULE_SHA256
    @test observed["small_nk_fixture"] == M.SMALL_NK_FIXTURE_SHA256
    @test observed["core3_module"] == M.CORE3_MODULE_SHA256
    @test observed["scoring_module"] == M.SCORING_MODULE_SHA256
    @test observed["inference_module"] == M.INFERENCE_MODULE_SHA256
    @test observed["project_toml"] == M.US_PROJECT_SHA256
    @test observed["manifest_toml"] == M.US_MANIFEST_SHA256
    @test validate_tested_runtime() == M.TESTED_RUNTIME_CEILING
    @test canonical_protocol_sha256() == M.EXPECTED_PROTOCOL_SHA256
    @test M.canonical_sha256(M._small_nk_contract_payload()) ==
        M.SMALL_NK_MODEL_CONTRACT_SHA256
    @test canonical_design().origin_indices == collect(60:89)
    @test canonical_design().maximum_horizon == 12
    @test canonical_design().evaluation_horizons == [1, 2, 4, 8, 12]
    @test canonical_design().path_count == 500
    @test canonical_design().model_selection_timing ==
        "RETROSPECTIVE_HINDSIGHT_EVALUATION_DESIGN_EXPOSED"
    @test M._protocol_payload()["point_error_sign"] ==
        "actual_minus_forecast_positive_means_underprediction"
    @test M._protocol_payload()[
        "mathematical_scores_computed_is_not_repository_scoring_eligible",
    ] === true
    @test M._protocol_payload()["prefix_api_barrier_is_process_isolation"] === false
    @test M._protocol_payload()["process_level_future_byte_absence_proven"] === false
    @test M._protocol_payload()["archive_prefix_source_binding"] ==
        "unconditional_bit_rebinding_to_one_fresh_exact_pinned_panel_for_replay_true_and_false_validation"
    @test "FULL_REVISED_PANEL_MATERIALIZED_IN_FORECAST_PROCESS_BEFORE_PREFIX_EXTRACTION" in
        M.BLOCKERS
    @test "PREFIX_ONLY_MODEL_API_IS_NOT_PROCESS_LEVEL_FUTURE_BYTE_ISOLATION" in
        M.BLOCKERS
    @test "DEPOT_PACKAGE_SOURCE_ARTIFACT_AND_COMPILED_CACHE_BYTES_NOT_ATTESTED" in
        M.BLOCKERS
    @test "CROSS_RUNTIME_CPU_OS_BLAS_AND_THREAD_CONFIGURATION_REPRODUCIBILITY_UNATTESTED" in
        M.BLOCKERS
    @test (:mathematical_scores_computed in fieldnames(ComparisonResult))
    @test (:repository_scoring_eligible in fieldnames(ComparisonResult))
end

@testset "frozen regimes and exact counts" begin
    @test regime_for_period("2019Q4") == "PRE_PANDEMIC"
    @test regime_for_period("2020Q1") == "PANDEMIC_ACUTE"
    @test regime_for_period("2021Q4") == "PANDEMIC_ACUTE"
    @test regime_for_period("2022Q1") == "POST_ACUTE"
    @test expected_regime_counts() == Dict(
        "FULL" => [30, 30, 30, 30, 30],
        "PRE_PANDEMIC" => [18, 17, 15, 11, 7],
        "PANDEMIC_ACUTE" => [8, 8, 8, 8, 8],
        "POST_ACUTE" => [4, 5, 7, 11, 15],
    )
    @test_throws ComparisonError regime_for_period("2020 Q1")
    @test_throws ComparisonError regime_for_period("2020Q5")
end

@testset "prefix-only forecast phase and explicit test path count" begin
    prefixes = load_canonical_training_prefixes(origin_indices = [60])
    @test length(prefixes) == 1
    prefix = only(prefixes)
    @test prefix.origin_key == "2015Q2"
    @test size(prefix.y_train) == (60, 3)
    @test prefix.forecast_keys[1] == "2015Q3"
    @test prefix.forecast_keys[end] == "2018Q2"
    @test prefix.y_train isa Matrix{Float64}
    @test !any(
        field -> getfield(prefix, field) isa M.Core3RevisedPanel,
        fieldnames(TrainingPrefix),
    )
    @test !(:truth in fieldnames(TrainingPrefix))
    @test !(:panel in fieldnames(TrainingPrefix))
    panel = M.load_revised_core3_panel()
    isolated_prefix = M._make_prefix(panel, 60)
    @test !Base.mightalias(isolated_prefix.y_train, panel.values)

    archive = run_forecast_phase(prefixes; path_count = 5)
    @test !archive.canonical_full_run
    @test archive.path_count == 5
    @test length(archive.attempts) == 4
    @test all(attempt -> attempt.status == "ok", archive.attempts)
    @test all(attempt -> size(attempt.point) == (12, 3), archive.attempts)
    @test all(attempt -> size(attempt.draws) == (12, 3, 5), archive.attempts)
    @test all(
        attempt -> attempt.diagnostics[
            "future_truth_field_or_panel_reference_passed_to_executor",
        ] === false,
        archive.attempts,
    )
    @test all(
        attempt -> attempt.diagnostics["process_level_future_byte_absence_proven"] ===
            false,
        archive.attempts,
    )
    @test all(attempt -> all(iszero, values(attempt.gates)), archive.attempts)
    @test validate_forecast_archive(archive) === archive
    @test_throws ComparisonError run_forecast_phase(
        prefixes;
        path_count = 5,
        require_canonical = true,
    )

    shorter = run_forecast_phase(prefixes; path_count = 3)
    for model_slot in eachindex(shorter.attempts)
        @test M._bits_equal(
            shorter.attempts[model_slot].point,
            archive.attempts[model_slot].point,
        )
        @test M._bits_equal(
            shorter.attempts[model_slot].draws,
            archive.attempts[model_slot].draws[:, :, 1:3],
        )
    end

    counter = Ref(0)
    attachment = attach_truth_after_lock(
        archive;
        score_attachment_counter = counter,
    )
    @test counter[] == 1
    @test attachment.score_truth_attachment_loader_calls == 1
    @test attachment.forecast_lock_validated_before_score_truth_attachment
    @test attachment.forecast_keys[1, 1] == "2015Q3"
    @test size(attachment.truth) == (1, 12, 3)
    @test validate_truth_attachment(attachment, archive) === attachment
end

@testset "forecast lock defeats alteration before phase-two score attachment" begin
    prefixes = load_canonical_training_prefixes(origin_indices = [60])
    archive = run_forecast_phase(prefixes; path_count = 2)

    changed_point = copy(archive.attempts[1].point)
    changed_point[1, 1] = nextfloat(changed_point[1, 1])
    archive.attempts[1] = restamp_attempt(archive.attempts[1]; point = changed_point)
    archive = restamp_archive(archive)
    counter = Ref(0)
    @test_throws ComparisonError attach_truth_after_lock(
        archive;
        score_attachment_counter = counter,
    )
    @test counter[] == 0

    archive2 = run_forecast_phase(prefixes; path_count = 2)
    elevated = copy(archive2.attempts[1].gates)
    elevated["promotion_eligible"] = true
    archive2.attempts[1] = restamp_attempt(archive2.attempts[1]; gates = elevated)
    archive2 = restamp_archive(archive2)
    @test_throws ComparisonError validate_forecast_archive(archive2)

    archive3 = run_forecast_phase(prefixes; path_count = 2)
    reverse!(archive3.attempts[1].target_names)
    @test_throws ComparisonError validate_forecast_archive(archive3)

    archive4 = run_forecast_phase(prefixes; path_count = 2)
    attempt = archive4.attempts[1]
    failed_values = (
        "failed",
        attempt.model_id,
        attempt.model_contract_sha256,
        attempt.origin_index,
        attempt.origin_key,
        attempt.training_sha256,
        copy(attempt.forecast_keys),
        copy(attempt.target_names),
        attempt.seed,
        attempt.path_count,
        zeros(Float64, 0, 0),
        zeros(Float64, 0, 0, 0),
        nothing,
        Dict{String, Any}(
            "future_truth_field_or_panel_reference_passed_to_executor" => false,
            "process_level_future_byte_absence_proven" => false,
        ),
        "visible_test_failure",
        "VisibleTestFailure",
        "failure details must not be dropped",
        copy(attempt.gates),
    )
    unstamped = ForecastAttempt(failed_values..., repeat("0", 64))
    archive4.attempts[1] = ForecastAttempt(
        failed_values...,
        M.canonical_sha256(M._attempt_payload(unstamped)),
    )
    @test archive4.attempts[1].failure_code == "visible_test_failure"
    @test archive4.attempts[1].failure_message == "failure details must not be dropped"
    @test_throws ComparisonError validate_forecast_archive(archive4)

    archive5 = run_forecast_phase(prefixes; path_count = 2)
    filter!(
        !=("FULL_REVISED_PANEL_MATERIALIZED_IN_FORECAST_PROCESS_BEFORE_PREFIX_EXTRACTION"),
        archive5.blockers,
    )
    archive5 = restamp_archive(archive5)
    @test_throws ComparisonError validate_forecast_archive(archive5)
end

@testset "unconditional revised-source rebinding and no-alias boundary" begin
    caller_prefixes = load_canonical_training_prefixes(origin_indices = [60])
    caller_before = copy(caller_prefixes[1].y_train)
    archive = run_forecast_phase(caller_prefixes; path_count = 2)
    caller_prefixes[1].y_train[1, 1] = nextfloat(caller_prefixes[1].y_train[1, 1])
    @test M._bits_equal(archive.prefixes[1].y_train, caller_before)
    @test validate_forecast_archive(archive; replay = false) === archive

    exact_prefix = only(load_canonical_training_prefixes(origin_indices = [60]))
    changed_y = copy(exact_prefix.y_train)
    changed_y[1, 1] = nextfloat(changed_y[1, 1])
    restamped_prefix = restamp_prefix(exact_prefix; y_train = changed_y)
    @test M._validate_prefix(restamped_prefix) === restamped_prefix
    @test_throws ComparisonError run_forecast_phase(
        [restamped_prefix];
        path_count = 2,
    )

    archive = run_forecast_phase([exact_prefix]; path_count = 2)
    archive.prefixes[1] = restamped_prefix
    archive = restamp_archive(archive)
    @test_throws ComparisonError validate_forecast_archive(archive; replay = false)
end

@testset "complete replay identity and phase-two panel validation" begin
    prefix = only(load_canonical_training_prefixes(origin_indices = [60]))

    diagnostics_archive = run_forecast_phase([prefix]; path_count = 2)
    changed_diagnostics = deepcopy(diagnostics_archive.attempts[1].diagnostics)
    @test changed_diagnostics["process_level_future_byte_absence_proven"] === false
    changed_diagnostics["process_level_future_byte_absence_proven"] = true
    diagnostics_archive.attempts[1] = restamp_attempt(
        diagnostics_archive.attempts[1];
        diagnostics = changed_diagnostics,
    )
    diagnostics_archive = restamp_archive(diagnostics_archive)
    @test_throws ComparisonError validate_forecast_archive(
        diagnostics_archive;
        replay = true,
    )

    upstream_archive = run_forecast_phase([prefix]; path_count = 2)
    @test upstream_archive.attempts[2].upstream_content_sha256 isa String
    upstream_archive.attempts[2] = restamp_attempt(
        upstream_archive.attempts[2];
        upstream_content_sha256 = repeat("f", 64),
    )
    upstream_archive = restamp_archive(upstream_archive)
    @test_throws ComparisonError validate_forecast_archive(
        upstream_archive;
        replay = true,
    )

    clean_archive = run_forecast_phase([prefix]; path_count = 2)
    panel = load_exact_truth_panel()
    changed_values = copy(panel.values)
    changed_values[1, 1] = nextfloat(changed_values[1, 1])
    mislabeled_panel = M.Core3RevisedPanel(
        copy(panel.periods),
        changed_values,
        panel.manifest_sha256,
        panel.panel_sha256,
        panel.source_receipts_sha256,
        panel.core3_values_sha256,
        panel.information_track,
    )
    counter = Ref(0)
    @test_throws M.Core3BenchmarkError attach_truth_after_lock(
        clean_archive;
        score_truth_loader = () -> mislabeled_panel,
        score_attachment_counter = counter,
    )
    @test counter[] == 1
end

@testset "source, target, type, and finite-value fail-closed checks" begin
    mktempdir() do directory
        changed = joinpath(directory, "USCore3AutoregressiveBenchmarks.jl")
        write(changed, read(M.CORE3_SOURCE), UInt8('\n'))
        @test_throws ComparisonError validate_dependency_pins(
            path_overrides = Dict("core3_module" => changed),
        )
    end
    @test_throws ComparisonError load_canonical_training_prefixes(origin_indices = [true])
    prefixes = load_canonical_training_prefixes(origin_indices = [60])
    @test_throws ComparisonError run_forecast_phase(prefixes; path_count = true)
    @test_throws ComparisonError run_forecast_phase(prefixes; path_count = 0)

    prefixes[1].y_train[1, 1] = NaN
    @test_throws ComparisonError M._validate_prefix(prefixes[1])
end

@testset "accepted score and inference semantics are actually callable" begin
    @test M.point_scores([2.0], [1.0]).mean_error == 1.0
    @test M.ensemble_crps(0.0, [-1.0, 1.0]) == 0.5
    differences = M.loss_differential(
        [1.0, 1.5, 0.5, 1.2, 0.8],
        [2.0, 2.0, 1.5, 1.8, 1.4];
        loss = :squared,
    )
    @test all(<(0.0), differences)
    dm = M.hln_dm(differences, 1)
    @test dm.mean_differential < 0.0
end
