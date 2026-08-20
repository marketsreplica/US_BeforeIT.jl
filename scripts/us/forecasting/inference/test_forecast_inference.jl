using LinearAlgebra
using Statistics
using Test

include(joinpath(@__DIR__, "USForecastInference.jl"))
using .USForecastInference

@testset "paired loss differential orientation and validation" begin
    challenger = [1.0, -2.0, 0.5]
    comparator = [2.0, -1.0, 1.5]

    @test loss_differential(challenger, comparator) ==
        [-3.0, 3.0, -2.0]
    @test loss_differential(
        challenger,
        comparator;
        loss = :absolute,
    ) == [-1.0, 1.0, -1.0]
    @test all(
        loss_differential([0.5, 1.0], [1.0, 2.0]) .< 0
    )

    @test_throws DimensionMismatch loss_differential([1.0], [1.0, 2.0])
    @test_throws ArgumentError loss_differential(Float64[], Float64[])
    @test_throws ArgumentError loss_differential(
        [1.0, NaN],
        [1.0, 2.0],
    )
    @test_throws ArgumentError loss_differential(
        [1.0, 2.0],
        [1.0, Inf],
    )
    @test_throws ArgumentError loss_differential(
        [1.0],
        [1.0];
        loss = :unknown,
    )
    @test_throws ArgumentError loss_differential(
        Real[1.0, true],
        [1.0, 2.0],
    )
    @test_throws ArgumentError loss_differential(
        [1.0, 2.0],
        Real[1.0, false],
    )
    @test_throws DomainError loss_differential(
        [floatmax(Float64)],
        [0.0],
    )
end

@testset "HLN-DM reference formula, effect, and confidence interval" begin
    challenger_errors = [1.0, 2.0, 1.5, 3.0, 2.5, 4.0]
    comparator_errors = [1.2, 1.5, 2.0, 2.5, 3.0, 3.5]
    horizon = 2
    differential = challenger_errors .^ 2 .- comparator_errors .^ 2
    centered = differential .- mean(differential)
    n = length(differential)
    gamma_zero = dot(centered, centered) / n
    gamma_one =
        dot(centered[2:end], centered[1:(end - 1)]) / n
    expected_lrv = gamma_zero + gamma_one
    expected_standard_error = sqrt(expected_lrv / n)
    expected_correction = sqrt(
        (n + 1 - 2horizon + horizon * (horizon - 1) / n) / n
    )
    expected_corrected_standard_error =
        expected_standard_error / expected_correction
    expected_statistic =
        mean(differential) / expected_corrected_standard_error
    t_critical_df5 = 2.5705818356363146
    expected_margin =
        t_critical_df5 * expected_corrected_standard_error

    result = hln_dm(differential, horizon)

    @test result.n == n
    @test result.horizon == horizon
    @test result.mean_differential ≈ mean(differential) atol = 1.0e-14
    @test result.long_run_variance ≈ expected_lrv atol = 1.0e-14
    @test result.standard_error ≈ expected_standard_error atol = 1.0e-14
    @test result.hln_correction ≈ expected_correction atol = 1.0e-14
    @test result.corrected_standard_error ≈
        expected_corrected_standard_error atol = 1.0e-14
    @test result.statistic ≈ expected_statistic atol = 1.0e-14
    @test result.p_value ≈ 0.389329276626978 atol = 2.0e-13
    @test result.confidence_lower ≈
        mean(differential) - expected_margin atol = 2.0e-13
    @test result.confidence_upper ≈
        mean(differential) + expected_margin atol = 2.0e-13
    @test result.confidence_lower < result.mean_differential <
        result.confidence_upper

    one_step = hln_dm(
        [-1.2, -0.4, 0.3, -0.7, -1.0, 0.1],
        1;
        confidence_level = 0.9,
    )
    @test one_step.hln_correction ≈ sqrt(5 / 6)
    @test one_step.mean_differential < 0
    @test one_step.statistic < 0
    @test 0 < one_step.p_value < 1
end

@testset "HLN-DM fail-closed cases" begin
    @test_throws ArgumentError hln_dm([1.0], 1)
    @test_throws ArgumentError hln_dm([1.0, NaN, 2.0], 1)
    @test_throws ArgumentError hln_dm(Real[1.0, true, 2.0], 1)
    @test_throws ArgumentError hln_dm([1.0, 2.0], 0)
    @test_throws ArgumentError hln_dm([1.0, 2.0], true)
    @test_throws ArgumentError hln_dm([1.0, 2.0], 2)
    @test_throws ArgumentError hln_dm(
        [1.0, 2.0, 3.0],
        1;
        confidence_level = 1.0,
    )
    @test_throws ArgumentError hln_dm(
        [1.0, 2.0, 3.0],
        1;
        confidence_level = true,
    )
    @test_throws DomainError hln_dm(fill(1.0, 8), 1)
    @test_throws DomainError hln_dm(zeros(8), 4)
    @test_throws DomainError hln_dm(
        [floatmax(Float64), -floatmax(Float64), 1.0],
        1,
    )
end

@testset "dependency-free Student-t reference grid" begin
    reference = [
        (1, 12.706204736432095, 0.2951672353008664),
        (2, 4.302652729696142, 0.1835034190722739),
        (5, 2.570581835636314, 0.10193947882985832),
        (30, 2.0422724563012373, 0.05462504496298311),
        (100, 1.9839715184496334, 0.048212178731133634),
        (1000, 1.9623390808264074, 0.045770346493251665),
    ]
    for (degrees_freedom, critical, p_at_two) in reference
        @test USForecastInference._student_t_critical(
            0.95,
            degrees_freedom,
        ) ≈ critical atol = 5.0e-10
        @test USForecastInference._student_t_two_sided_pvalue(
            2.0,
            degrees_freedom,
        ) ≈ p_at_two atol = 3.0e-12
    end
    @test USForecastInference._student_t_two_sided_pvalue(0.0, 5) == 1.0
end

@testset "block-length resolution is explicit and horizon-bounded" begin
    fixed = resolve_block_length(
        FixedBlockLength(2),
        [1, 4, 2],
        12;
        horizon_floor_policy = :max_horizon,
    )
    @test fixed.source == :fixed
    @test fixed.requested == 2.0
    @test fixed.horizon_floor_policy == :max_horizon
    @test fixed.horizon_floor == 4
    @test fixed.effective == 4.0
    @test fixed.horizon_bounded
    @test fixed.method_id == "fixed"
    @test fixed.provenance === nothing

    unfloored = resolve_block_length(
        FixedBlockLength(2),
        [1, 4, 2],
        12;
        horizon_floor_policy = :none,
    )
    @test unfloored.source == :fixed
    @test unfloored.requested == 2.0
    @test unfloored.horizon_floor_policy == :none
    @test unfloored.horizon_floor === nothing
    @test unfloored.effective == 2.0
    @test !unfloored.horizon_bounded

    plugin_provenance = "artifact-sha256:" * repeat("a", 64)
    plugin = resolve_block_length(
        ExternalPluginBlockLength(
            5.5,
            "corrected_politis_white_external.v1",
            plugin_provenance,
        ),
        [1, 4],
        12;
        horizon_floor_policy = :max_horizon,
    )
    @test plugin.source == :external_plugin
    @test plugin.requested == 5.5
    @test plugin.horizon_floor_policy == :max_horizon
    @test plugin.horizon_floor == 4
    @test plugin.effective == 5.5
    @test !plugin.horizon_bounded
    @test plugin.method_id ==
        "corrected_politis_white_external.v1"
    @test plugin.provenance == plugin_provenance

    @test_throws ArgumentError FixedBlockLength(0)
    @test_throws ArgumentError FixedBlockLength(true)
    @test_throws ArgumentError FixedBlockLength(Inf)
    @test_throws ArgumentError ExternalPluginBlockLength(2, "", "source")
    @test_throws ArgumentError ExternalPluginBlockLength(2, "method", " ")
    @test_throws ArgumentError ExternalPluginBlockLength(
        2,
        "method",
        "artifact-sha256:abc",
    )
    @test_throws ArgumentError ExternalPluginBlockLength(
        2,
        "method",
        "artifact-sha256:" * repeat("A", 64),
    )
    @test_throws UndefKeywordError resolve_block_length(
        FixedBlockLength(1),
        [1],
        12,
    )
    @test_throws ArgumentError resolve_block_length(
        FixedBlockLength(13),
        [1],
        12;
        horizon_floor_policy = :none,
    )
    @test_throws ArgumentError resolve_block_length(
        FixedBlockLength(1),
        Int[],
        12;
        horizon_floor_policy = :max_horizon,
    )
    @test_throws ArgumentError resolve_block_length(
        FixedBlockLength(1),
        [12],
        12;
        horizon_floor_policy = :max_horizon,
    )
    @test_throws ArgumentError resolve_block_length(
        FixedBlockLength(1),
        [true],
        12;
        horizon_floor_policy = :max_horizon,
    )
    @test_throws ArgumentError resolve_block_length(
        FixedBlockLength(1),
        [1],
        12;
        horizon_floor_policy = :invalid,
    )
end

@testset "stationary-bootstrap indices are deterministic and auditable" begin
    first = stationary_bootstrap_indices(
        10,
        [1, 4];
        block_length = FixedBlockLength(2),
        horizon_floor_policy = :max_horizon,
        seed = 0x2a,
        replicates = 30,
    )
    repeated = stationary_bootstrap_indices(
        10,
        [1, 4];
        block_length = FixedBlockLength(2),
        horizon_floor_policy = :max_horizon,
        seed = 42,
        replicates = 30,
    )
    changed = stationary_bootstrap_indices(
        10,
        [1, 4];
        block_length = FixedBlockLength(2),
        horizon_floor_policy = :max_horizon,
        seed = 43,
        replicates = 30,
    )

    @test first.n == 10
    @test first.replicates == 30
    @test first.seed == UInt64(42)
    @test size(first.indices) == (10, 30)
    @test all(index -> 1 <= index <= 10, first.indices)
    @test first.block_length.horizon_floor_policy == :max_horizon
    @test first.block_length.effective == 4.0
    @test first.block_length.horizon_bounded
    @test first.indices == repeated.indices
    @test first.indices != changed.indices

    sealed_fixture = stationary_bootstrap_indices(
        6,
        [1];
        block_length = FixedBlockLength(2),
        horizon_floor_policy = :none,
        seed = 42,
        replicates = 4,
    )
    @test sealed_fixture.indices == [
        5 2 6 1
        6 2 1 3
        2 6 2 4
        3 1 2 6
        4 5 5 2
        5 6 1 3
    ]
    @test sealed_fixture.block_length.horizon_floor_policy == :none
    @test sealed_fixture.block_length.horizon_floor === nothing

    @test_throws ArgumentError stationary_bootstrap_indices(
        1,
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
    )
    @test_throws ArgumentError stationary_bootstrap_indices(
        10,
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = true,
    )
    @test_throws ArgumentError stationary_bootstrap_indices(
        10,
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = -1,
    )
    @test_throws ArgumentError stationary_bootstrap_indices(
        10,
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = false,
    )
    @test_throws UndefKeywordError stationary_bootstrap_indices(
        10,
        [1];
        block_length = FixedBlockLength(1),
        seed = 1,
    )
end

@testset "joint studentized stationary bootstrap" begin
    n = 24
    base = [
        sin(0.47index) +
            0.3cos(0.19index) +
            0.04index for index in 1:n
    ]
    differentials = hcat(base .- 1.0, 2 .* (base .- 1.0))
    horizons = [2, 2]
    first = studentized_stationary_bootstrap(
        differentials,
        horizons;
        block_length = FixedBlockLength(4),
        horizon_floor_policy = :none,
        seed = 20260807,
        replicates = 999,
    )
    repeated = studentized_stationary_bootstrap(
        differentials,
        horizons;
        block_length = FixedBlockLength(4),
        horizon_floor_policy = :none,
        seed = 20260807,
        replicates = 999,
    )

    @test first.n == n
    @test first.hypotheses == 2
    @test first.replicates == 999
    @test first.block_length.horizon_floor_policy == :none
    @test first.seed == UInt64(20260807)
    @test first.indices == repeated.indices
    @test first.statistics == repeated.statistics
    @test first.bootstrap_statistics == repeated.bootstrap_statistics
    @test first.marginal_p_values == repeated.marginal_p_values
    @test first.confidence_lower == repeated.confidence_lower
    @test first.confidence_upper == repeated.confidence_upper
    @test first.effects[2] ≈ 2first.effects[1] atol = 2.0e-14
    @test first.corrected_standard_errors[2] ≈
        2first.corrected_standard_errors[1] atol = 2.0e-14
    @test first.statistics[1] ≈ first.statistics[2] atol = 2.0e-14
    @test all(
        first.bootstrap_statistics[:, 1] .≈
            first.bootstrap_statistics[:, 2]
    )
    @test all(value -> 0 < value <= 1, first.marginal_p_values)
    @test all(first.confidence_lower .<= first.confidence_upper)

    other_seed = studentized_stationary_bootstrap(
        differentials,
        horizons;
        block_length = FixedBlockLength(4),
        horizon_floor_policy = :none,
        seed = 20260808,
        replicates = 999,
    )
    @test first.indices != other_seed.indices
    @test first.bootstrap_statistics != other_seed.bootstrap_statistics
end

@testset "9,999-replicate API path" begin
    n = 16
    base = [
        sin(0.61index) + 0.2cos(0.17index) + 0.03index for
            index in 1:n
    ]
    result = studentized_stationary_bootstrap(
        reshape(base, :, 1),
        [2];
        block_length = FixedBlockLength(3),
        horizon_floor_policy = :none,
        seed = 99,
    )
    @test result.replicates == 9_999
    @test size(result.indices) == (n, 9_999)
    @test size(result.bootstrap_statistics) == (9_999, 1)
    @test result.marginal_p_values[1] >= 1 / 10_000
end

@testset "studentized bootstrap fail-closed cases" begin
    healthy = reshape(collect(1.0:8.0), :, 1)

    @test_throws ArgumentError studentized_stationary_bootstrap(
        zeros(1, 1),
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws ArgumentError studentized_stationary_bootstrap(
        zeros(8, 0),
        Int[];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws ArgumentError studentized_stationary_bootstrap(
        fill(NaN, 8, 1),
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws DimensionMismatch studentized_stationary_bootstrap(
        hcat(healthy, healthy),
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws DomainError studentized_stationary_bootstrap(
        zeros(8, 1),
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws ArgumentError studentized_stationary_bootstrap(
        healthy,
        [8];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws ArgumentError studentized_stationary_bootstrap(
        healthy,
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 998,
    )
    @test_throws ArgumentError studentized_stationary_bootstrap(
        reshape(Real[1.0, true, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0], :, 1),
        [1];
        block_length = FixedBlockLength(1),
        horizon_floor_policy = :none,
        seed = 1,
        replicates = 999,
    )
    @test_throws UndefKeywordError studentized_stationary_bootstrap(
        healthy,
        [1];
        block_length = FixedBlockLength(1),
        seed = 1,
        replicates = 999,
    )
end

@testset "Romano-Wolf stepdown max-t" begin
    n = 30
    base = [
        sin(0.41index) +
            0.2cos(0.13index) +
            0.02index for index in 1:n
    ]
    differentials = hcat(base .- 1.6, base .- 0.6, base)
    bootstrap = studentized_stationary_bootstrap(
        differentials,
        [1, 1, 1];
        block_length = FixedBlockLength(3),
        horizon_floor_policy = :none,
        seed = 1729,
        replicates = 999,
    )
    result = romano_wolf_stepdown(
        bootstrap;
        hypothesis_ids = ["strong", "moderate", "null"],
        alternative = :less,
        alpha = 0.05,
    )

    @test result.hypothesis_ids == ["strong", "moderate", "null"]
    @test result.alternative == :less
    @test result.alpha == 0.05
    @test result.stepdown_order[1] == 1
    @test result.evidence_statistics == .-result.observed_statistics
    @test all(value -> 0 < value <= 1, result.unadjusted_p_values)
    @test all(value -> 0 < value <= 1, result.adjusted_p_values)
    @test all(
        result.adjusted_p_values .>= result.unadjusted_p_values
    )
    ordered_adjusted =
        result.adjusted_p_values[result.stepdown_order]
    @test issorted(ordered_adjusted)
    @test result.rejected[1]

    permutation = [3, 1, 2]
    permuted_bootstrap = studentized_stationary_bootstrap(
        differentials[:, permutation],
        [1, 1, 1];
        block_length = FixedBlockLength(3),
        horizon_floor_policy = :none,
        seed = 1729,
        replicates = 999,
    )
    permuted = romano_wolf_stepdown(
        permuted_bootstrap;
        hypothesis_ids = ["null", "strong", "moderate"],
        alternative = :less,
    )
    inverse_permutation = invperm(permutation)
    @test permuted.adjusted_p_values[inverse_permutation] ==
        result.adjusted_p_values
    @test permuted.unadjusted_p_values[inverse_permutation] ==
        result.unadjusted_p_values

    single_bootstrap = studentized_stationary_bootstrap(
        differentials[:, 1:1],
        [1];
        block_length = FixedBlockLength(3),
        horizon_floor_policy = :none,
        seed = 1729,
        replicates = 999,
    )
    single = romano_wolf_stepdown(
        single_bootstrap;
        alternative = :two_sided,
    )
    @test single.adjusted_p_values == single.unadjusted_p_values

    greater = romano_wolf_stepdown(
        bootstrap;
        alternative = :greater,
    )
    two_sided = romano_wolf_stepdown(
        bootstrap;
        alternative = :two_sided,
    )
    @test greater.evidence_statistics == bootstrap.statistics
    @test two_sided.evidence_statistics == abs.(bootstrap.statistics)

    @test_throws ArgumentError romano_wolf_stepdown(
        bootstrap;
        alternative = :invalid,
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        bootstrap;
        alpha = 0.0,
    )
    @test_throws DimensionMismatch romano_wolf_stepdown(
        bootstrap;
        hypothesis_ids = ["only_one"],
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        bootstrap;
        hypothesis_ids = ["duplicate", "duplicate", "third"],
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        bootstrap;
        hypothesis_ids = ["first", " ", "third"],
    )

    low_resolution = StudentizedBootstrapResult(
        bootstrap.n,
        bootstrap.hypotheses,
        998,
        bootstrap.seed,
        copy(bootstrap.horizons),
        bootstrap.block_length,
        copy(bootstrap.indices[:, 1:998]),
        copy(bootstrap.effects),
        copy(bootstrap.corrected_standard_errors),
        copy(bootstrap.statistics),
        copy(bootstrap.bootstrap_statistics[1:998, :]),
        bootstrap.confidence_level,
        copy(bootstrap.marginal_p_values),
        copy(bootstrap.confidence_lower),
        copy(bootstrap.confidence_upper),
    )
    @test_throws ArgumentError romano_wolf_stepdown(low_resolution)

    reblock = block_length -> StudentizedBootstrapResult(
        bootstrap.n,
        bootstrap.hypotheses,
        bootstrap.replicates,
        bootstrap.seed,
        copy(bootstrap.horizons),
        block_length,
        copy(bootstrap.indices),
        copy(bootstrap.effects),
        copy(bootstrap.corrected_standard_errors),
        copy(bootstrap.statistics),
        copy(bootstrap.bootstrap_statistics),
        bootstrap.confidence_level,
        copy(bootstrap.marginal_p_values),
        copy(bootstrap.confidence_lower),
        copy(bootstrap.confidence_upper),
    )
    fixed = bootstrap.block_length
    @test_throws ArgumentError romano_wolf_stepdown(
        reblock(
            ResolvedBlockLength(
                :unknown,
                fixed.requested,
                fixed.horizon_floor_policy,
                fixed.horizon_floor,
                fixed.effective,
                fixed.horizon_bounded,
                fixed.method_id,
                fixed.provenance,
            )
        )
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        reblock(
            ResolvedBlockLength(
                :fixed,
                fixed.requested,
                fixed.horizon_floor_policy,
                fixed.horizon_floor,
                fixed.effective,
                fixed.horizon_bounded,
                "forged",
                nothing,
            )
        )
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        reblock(
            ResolvedBlockLength(
                :fixed,
                fixed.requested,
                fixed.horizon_floor_policy,
                fixed.horizon_floor,
                fixed.effective,
                fixed.horizon_bounded,
                "fixed",
                "artifact-sha256:" * repeat("a", 64),
            )
        )
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        reblock(
            ResolvedBlockLength(
                :external_plugin,
                fixed.requested,
                fixed.horizon_floor_policy,
                fixed.horizon_floor,
                fixed.effective,
                fixed.horizon_bounded,
                " ",
                "artifact-sha256:" * repeat("a", 64),
            )
        )
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        reblock(
            ResolvedBlockLength(
                :external_plugin,
                fixed.requested,
                fixed.horizon_floor_policy,
                fixed.horizon_floor,
                fixed.effective,
                fixed.horizon_bounded,
                "external",
                nothing,
            )
        )
    )
    @test_throws ArgumentError romano_wolf_stepdown(
        reblock(
            ResolvedBlockLength(
                :external_plugin,
                fixed.requested,
                fixed.horizon_floor_policy,
                fixed.horizon_floor,
                fixed.effective,
                fixed.horizon_bounded,
                "external",
                "artifact-sha256:" * repeat("A", 64),
            )
        )
    )

    saved_bootstrap_statistic = bootstrap.bootstrap_statistics[1, 1]
    bootstrap.bootstrap_statistics[1, 1] = NaN
    @test_throws ArgumentError romano_wolf_stepdown(bootstrap)
    bootstrap.bootstrap_statistics[1, 1] = saved_bootstrap_statistic

    saved_index = bootstrap.indices[1, 1]
    bootstrap.indices[1, 1] = 0
    @test_throws ArgumentError romano_wolf_stepdown(bootstrap)
    bootstrap.indices[1, 1] = saved_index

    saved_observed_statistic = bootstrap.statistics[1]
    bootstrap.statistics[1] += 1
    @test_throws ArgumentError romano_wolf_stepdown(bootstrap)
    bootstrap.statistics[1] = saved_observed_statistic
end

@testset "model confidence set" begin
    n = 40
    raw_first = [
        0.3sin(0.9index) + 0.2cos(0.31index) for index in 1:n
    ]
    raw_second = [
        0.3sin(0.9index + 2.0) + 0.2cos(0.31index + 1.0) for
            index in 1:n
    ]
    good_first = raw_first .- mean(raw_first)
    good_second = raw_second .- mean(raw_second)
    bad = [
        0.25sin(0.7index + 0.5) + 0.2cos(0.23index) for index in 1:n
    ]
    losses = hcat(
        1.0 .+ good_first,
        1.0 .+ good_second,
        3.0 .+ bad,
    )

    result = model_confidence_set(
        losses;
        block_length = FixedBlockLength(4),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 20260817,
    )
    @test result.n == n
    @test result.models == 3
    @test result.statistic == :t_max
    @test result.alpha == 0.05
    @test result.seed == UInt64(20260817)
    @test result.replicates == 999
    @test result.block_length.source == :fixed
    @test result.block_length.effective == 4.0
    @test result.block_length.horizon_floor_policy == :none
    @test sort(result.elimination_order) == [1, 2, 3]
    @test result.elimination_order[1] == 3
    @test result.step_p_values[1] == 0.001
    @test result.step_p_values[2] == 1.0
    @test result.step_p_values[3] == 1.0
    @test result.mcs_p_values[1] == 1.0
    @test result.mcs_p_values[2] == 1.0
    @test result.mcs_p_values[3] == 0.001
    @test result.included == [1, 2]

    repeated = model_confidence_set(
        losses;
        block_length = FixedBlockLength(4),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 20260817,
    )
    @test repeated.elimination_order == result.elimination_order
    @test repeated.step_p_values == result.step_p_values
    @test repeated.mcs_p_values == result.mcs_p_values
    @test repeated.included == result.included

    @test issorted(result.mcs_p_values[result.elimination_order])
    @test result.mcs_p_values[result.elimination_order] ==
        accumulate(max, result.step_p_values)
    @test result.mcs_p_values[result.elimination_order[end]] == 1.0

    permutation = [3, 1, 2]
    permuted = model_confidence_set(
        losses[:, permutation];
        block_length = FixedBlockLength(4),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 20260817,
    )
    inverse_permutation = invperm(permutation)
    @test permuted.mcs_p_values[inverse_permutation] ==
        result.mcs_p_values
    @test sort(permutation[permuted.included]) == result.included

    range_result = model_confidence_set(
        losses;
        block_length = FixedBlockLength(4),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 20260817,
        statistic = :t_range,
    )
    @test range_result.statistic == :t_range
    @test range_result.elimination_order[1] == 3
    @test range_result.mcs_p_values[3] == 0.001
    @test range_result.included == [1, 2]
    @test issorted(
        range_result.mcs_p_values[range_result.elimination_order]
    )
    @test range_result.mcs_p_values[range_result.elimination_order[end]] ==
        1.0

    two_losses = hcat(1.0 .+ good_first, 2.5 .+ good_second)
    two = model_confidence_set(
        two_losses;
        block_length = FixedBlockLength(3),
        bootstrap_replications = 999,
        alpha = 0.1,
        seed = 7,
    )
    @test two.elimination_order == [2, 1]
    @test two.step_p_values == [0.001, 1.0]
    @test two.mcs_p_values == [1.0, 0.001]
    @test two.mcs_p_values[argmin(vec(mean(two_losses; dims = 1)))] ==
        1.0
    @test two.included == [1]

    bad_centered = bad .- mean(bad)
    binding = hcat(
        1.0 .+ good_first,
        1.8 .+ 3.0 .* good_second,
        1.85 .+ 3.0 .* bad_centered,
    )
    monotonized = model_confidence_set(
        binding;
        block_length = FixedBlockLength(4),
        bootstrap_replications = 999,
        alpha = 0.1,
        seed = 271828,
    )
    @test monotonized.elimination_order[end] == 1
    @test sort(monotonized.elimination_order[1:2]) == [2, 3]
    @test 0.005 < monotonized.step_p_values[1] < 0.5
    @test monotonized.step_p_values[2] <
        monotonized.step_p_values[1]
    @test monotonized.mcs_p_values[monotonized.elimination_order[2]] ==
        monotonized.step_p_values[1]
    @test issorted(
        monotonized.mcs_p_values[monotonized.elimination_order]
    )
    @test monotonized.mcs_p_values[1] == 1.0
    @test monotonized.included == [1]

    structural = hcat(
        1.0 .+ good_first,
        1.0 .+ good_second,
        1.12 .+ 0.8 .* good_first .+ 0.2 .* bad,
        3.0 .+ bad,
    )
    four = model_confidence_set(
        structural;
        block_length = FixedBlockLength(4),
        bootstrap_replications = 999,
        alpha = 0.25,
        seed = 99,
    )
    @test sort(four.elimination_order) == [1, 2, 3, 4]
    @test four.elimination_order[1] == 4
    @test four.elimination_order[2] == 3
    @test all(value -> 0 < value <= 1, four.step_p_values)
    @test four.mcs_p_values[four.elimination_order] ==
        accumulate(max, four.step_p_values)
    @test four.mcs_p_values[3] <= 0.01
    @test four.mcs_p_values[4] <= 0.01
    @test four.included == [1, 2]

    healthy = hcat(
        [1.0 + 0.2sin(0.8index) for index in 1:12],
        [1.1 + 0.2cos(0.5index) for index in 1:12],
    )
    with_nan = copy(healthy)
    with_nan[4, 2] = NaN
    with_inf = copy(healthy)
    with_inf[7, 1] = Inf
    with_bool = Matrix{Real}(healthy)
    with_bool[2, 1] = true

    @test_throws ArgumentError model_confidence_set(
        healthy[1:9, :];
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy[:, 1:1];
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        with_nan;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        with_inf;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        with_bool;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.0,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 1.0,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = true,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
        statistic = :invalid,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 998,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = -1,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = true,
    )
    @test_throws ArgumentError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(13),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws UndefKeywordError model_confidence_set(
        healthy;
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
    )
    @test_throws DomainError model_confidence_set(
        hcat(healthy[:, 1], healthy[:, 1]);
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
    )
    @test_throws DomainError model_confidence_set(
        hcat(healthy[:, 1], healthy[:, 1]);
        block_length = FixedBlockLength(2),
        bootstrap_replications = 999,
        alpha = 0.05,
        seed = 1,
        statistic = :t_range,
    )
end
