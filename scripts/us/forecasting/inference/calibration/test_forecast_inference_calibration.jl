using Dates
using LinearAlgebra
using Random
using SHA
using Statistics
using Test
using TOML

include(joinpath(@__DIR__, "USForecastInferenceCalibration.jl"))
using .USForecastInferenceCalibration

function quarter_label(ordinal)
    year_number = fld(ordinal, 4)
    quarter_number = mod(ordinal, 4) + 1
    return "$(year_number)Q$(quarter_number)"
end

function quarter_end(ordinal)
    year_number = fld(ordinal, 4)
    quarter_number = mod(ordinal, 4) + 1
    return lastdayofmonth(Date(year_number, 3quarter_number, 1))
end

function geometry_document(origin_count = 2)
    models = ["model_$(index)" for index in 1:11]
    origins = [
        let
                origin_ordinal = 4 * 2024 + 2 + sequence - 1
                origin_year = fld(origin_ordinal, 4)
                origin_quarter = mod(origin_ordinal, 4) + 1
                origin_month = 3origin_quarter - 2
                Dict{String, Any}(
                    "sequence" => sequence,
                    "origin_id" => "origin_$(sequence)",
                    "origin_timestamp_utc" =>
                    "$(origin_year)-$(lpad(origin_month, 2, '0'))-15T12:00:00Z",
                    "origin_quarter" => quarter_label(origin_ordinal),
                    "target_dates" => [
                        string(quarter_end(origin_ordinal + horizon))
                        for horizon in HORIZONS
                    ],
                    "mature_horizons" => [1, 2, 4, 8, 12],
                    "eligible_model_ids" => copy(models),
                    "eligible_target_ids" => collect(TARGET_IDS),
                    "available_windows" => [
                        "EXPANDING",
                        "ROLLING_40",
                        "ROLLING_60",
                    ],
                    "regime_labels" => [
                        sequence == 1 ? "PRE_PANDEMIC" : "POST_ACUTE",
                        "NBER_EXPANSION",
                        "STANDARD_POLICY",
                    ],
                )
        end for sequence in 1:origin_count
    ]
    document = Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" =>
                "beforeit-us-inference-score-blind-geometry.v3",
            "canonicalization" =>
                "sorted_typed_length_aware_v1_excluding_artifact_content_sha256",
            "content_sha256" => repeat("0", 64),
        ),
        "geometry" => Dict{String, Any}(
            "geometry_id" => "synthetic.geometry.v1",
            "geometry_class" => "SCORE_BLIND_ORIGIN_GEOMETRY",
            "origin_count" => origin_count,
            "model_ids" => models,
            "target_ids" => collect(TARGET_IDS),
            "horizons" => collect(HORIZONS),
            "estimation_windows" => [
                "EXPANDING",
                "ROLLING_40",
                "ROLLING_60",
            ],
            "direction" => "CHALLENGER_MINUS_COMPARATOR",
            "sesoi_registry_id" => "sesoi.policy_units.v1",
            "regime_assignment_basis" =>
                "EXTERNALLY_REVIEWED_SCORE_BLIND_ASSERTIONS",
        ),
        "origins" => origins,
    )
    document["artifact"]["content_sha256"] =
        computed_geometry_sha256(document)
    return document
end

@testset "sealed protocol, semantic pin, and immutable return" begin
    parsed = TOML.parsefile(DEFAULT_PROTOCOL_PATH)
    computed = computed_protocol_sha256(parsed)
    @test computed == EXPECTED_PROTOCOL_SHA256
    @test parsed["artifact"]["content_sha256"] ==
        EXPECTED_PROTOCOL_SHA256

    validated = validate_protocol(parsed)
    @test validated.schema_version == PROTOCOL_SCHEMA_VERSION
    @test validated.content_sha256 == EXPECTED_PROTOCOL_SHA256
    @test validated.contract.synthetic_only
    @test !validated.contract.score_artifact_reads_allowed
    @test !validated.contract.diagnostic_module_import_allowed
    @test validated.contract.full_execution_requires_geometry
    @test validated.contract.full_execution_requires_explicit_expensive_mode
    @test validated.rehearsal.horizons == HORIZONS
    @test validated.rehearsal.all_available_counts ==
        REHEARSAL_ALL_AVAILABLE_COUNTS
    @test validated.rehearsal.balanced_count == 50
    @test validated.rehearsal.rolling60_counts ==
        REHEARSAL_ROLLING60_COUNTS
    @test validated.rehearsal.rolling60_balanced_count == 30
    @test validated.family.model_count == 11
    @test validated.family.comparison_count == 10
    @test validated.family.hypothesis_count == 200
    @test validated.family.target_ids == TARGET_IDS
    @test validated.family.loss_families == ("squared", "absolute")
    @test validated.family.alternative == :less
    @test validated.direct_null.dgp_id == "N00_DIFF_IID"
    @test validated.direct_null.distribution == :standard_gaussian
    @test validated.direct_null.column_dependence == :fully_independent
    @test validated.direct_null.cross_hypothesis_correlation == 0.0
    @test all(!value for value in values(validated.gates))
    @test !hasproperty(validated, :protocol)
    @test !hasproperty(validated, :manifest)

    parsed["contract"]["contract_id"] = "mutated"
    parsed["gates"]["readiness"] = true
    @test validated.contract.contract_id ==
        "us-forecast-inference-calibration.v2"
    @test !validated.gates.readiness
    @test_throws CalibrationContractError validate_protocol(parsed)

    artifact = protocol_artifact()
    @test artifact.content_sha256 == EXPECTED_PROTOCOL_SHA256
    @test occursin("0x55534643414c4942", artifact.canonical_content)
    @test occursin(r"^[0-9a-f]{64}$", artifact.file_sha256)
    @test artifact.file_byte_count == filesize(DEFAULT_PROTOCOL_PATH)
    @test !hasproperty(artifact, :protocol)
end

@testset "score-blind geometry firewall and immutable schema" begin
    document = geometry_document()
    validated = validate_score_blind_geometry(document)
    @test validated.geometry.geometry_id == "synthetic.geometry.v1"
    @test validated.geometry.origin_count == 2
    @test length(validated.geometry.model_ids) == 11
    @test validated.geometry.target_ids == TARGET_IDS
    @test validated.geometry.horizons == HORIZONS
    @test validated.geometry.direction == :challenger_minus_comparator
    @test validated.geometry.regime_assignment_basis ==
        "EXTERNALLY_REVIEWED_SCORE_BLIND_ASSERTIONS"
    @test length(validated.origins) == 2
    @test validated.origins[1].origin_quarter == "2024Q3"
    @test validated.origins[2].origin_quarter == "2024Q4"
    @test validated.origins[1].target_dates ==
        (
        "2024-12-31",
        "2025-03-31",
        "2025-09-30",
        "2026-09-30",
        "2027-09-30",
    )
    @test validated.origins[1].mature_horizons == HORIZONS
    @test validated.origins[1].regime_labels ==
        ("PRE_PANDEMIC", "NBER_EXPANSION", "STANDARD_POLICY")
    @test validated.content_sha256 ==
        document["artifact"]["content_sha256"]
    @test !hasproperty(validated, :document)

    document["geometry"]["model_ids"][1] = "mutated"
    document["origins"][1]["regime_labels"][1] = "OTHER"
    @test validated.geometry.model_ids[1] == "model_1"
    @test validated.origins[1].regime_labels[1] == "PRE_PANDEMIC"

    old_schema = geometry_document()
    old_schema["artifact"]["schema_version"] =
        "beforeit-us-inference-score-blind-geometry.v2"
    old_schema["artifact"]["content_sha256"] =
        computed_geometry_sha256(old_schema)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        old_schema,
    )

    invalid_timestamp = geometry_document()
    invalid_timestamp["origins"][1]["origin_timestamp_utc"] =
        "2024-02-30T12:00:00Z"
    invalid_timestamp["origins"][1]["origin_quarter"] = "2024Q1"
    invalid_timestamp["artifact"]["content_sha256"] =
        computed_geometry_sha256(invalid_timestamp)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        invalid_timestamp,
    )

    quarter_mismatch = geometry_document()
    quarter_mismatch["origins"][1]["origin_quarter"] = "2024Q2"
    quarter_mismatch["artifact"]["content_sha256"] =
        computed_geometry_sha256(quarter_mismatch)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        quarter_mismatch,
    )

    invalid_target_calendar = geometry_document()
    invalid_target_calendar["origins"][1]["target_dates"][1] =
        "2024-02-30"
    invalid_target_calendar["artifact"]["content_sha256"] =
        computed_geometry_sha256(invalid_target_calendar)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        invalid_target_calendar,
    )

    wrong_target_quarter = geometry_document()
    wrong_target_quarter["origins"][1]["target_dates"][1] =
        "2024-09-30"
    wrong_target_quarter["artifact"]["content_sha256"] =
        computed_geometry_sha256(wrong_target_quarter)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        wrong_target_quarter,
    )

    reversed_timestamps = geometry_document()
    reversed_timestamps["origins"][2]["origin_timestamp_utc"] =
        "2024-07-16T12:00:00Z"
    reversed_timestamps["origins"][2]["origin_quarter"] = "2024Q3"
    reversed_timestamps["origins"][2]["target_dates"] =
        copy(reversed_timestamps["origins"][1]["target_dates"])
    reversed_timestamps["artifact"]["content_sha256"] =
        computed_geometry_sha256(reversed_timestamps)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        reversed_timestamps,
    )

    for mature_horizons in (Any[], Any[2, 1], Any[true, 2])
        bad = geometry_document()
        bad["origins"][1]["mature_horizons"] = mature_horizons
        bad["artifact"]["content_sha256"] =
            computed_geometry_sha256(bad)
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end
    nonprefix_maturity = geometry_document()
    nonprefix_maturity["origins"][1]["mature_horizons"] = [1, 12]
    nonprefix_maturity["artifact"]["content_sha256"] =
        computed_geometry_sha256(nonprefix_maturity)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        nonprefix_maturity,
    )
    bool_geometry_horizon = geometry_document()
    bool_geometry_horizon["geometry"]["horizons"] =
        Any[true, 2, 4, 8, 12]
    bool_geometry_horizon["artifact"]["content_sha256"] =
        computed_geometry_sha256(bool_geometry_horizon)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        bool_geometry_horizon,
    )

    for eligibility_field in (
            "eligible_model_ids",
            "eligible_target_ids",
            "available_windows",
        )
        bad = geometry_document()
        bad["origins"][1][eligibility_field] = String[]
        bad["artifact"]["content_sha256"] =
            computed_geometry_sha256(bad)
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end
    reordered_eligibility = (
        "eligible_model_ids" => ["model_2", "model_1"],
        "eligible_target_ids" => ["pce_inflation", "real_gdp_growth"],
        "available_windows" => ["ROLLING_40", "EXPANDING"],
    )
    for (field, reordered) in reordered_eligibility
        bad = geometry_document()
        bad["origins"][1][field] = reordered
        bad["artifact"]["content_sha256"] =
            computed_geometry_sha256(bad)
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end

    wrong_regime_basis = geometry_document()
    wrong_regime_basis["geometry"]["regime_assignment_basis"] =
        "TIMESTAMP_DERIVED"
    wrong_regime_basis["artifact"]["content_sha256"] =
        computed_geometry_sha256(wrong_regime_basis)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        wrong_regime_basis,
    )

    invalid_regime_families = (
        ["PRE_PANDEMIC", "POST_ACUTE", "NBER_EXPANSION", "STANDARD_POLICY"],
        ["PRE_PANDEMIC", "STANDARD_POLICY"],
        ["PRE_PANDEMIC", "NBER_EXPANSION"],
        ["NBER_EXPANSION", "STANDARD_POLICY"],
        ["PRE_PANDEMIC", "NBER_EXPANSION", "ELB_POLICY", "STANDARD_POLICY"],
    )
    for regimes in invalid_regime_families
        bad = geometry_document()
        bad["origins"][1]["regime_labels"] = regimes
        bad["artifact"]["content_sha256"] =
            computed_geometry_sha256(bad)
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end

    reserved_id_mutations = (
        ("geometry", "geometry_id", "uSeD"),
        ("geometry", "sesoi_registry_id", "OTHER"),
        ("model", "model_ids", "Unknown"),
        ("origin", "origin_id", "nOnE"),
    )
    for (table, field, value) in reserved_id_mutations
        bad = geometry_document()
        if table == "geometry"
            bad["geometry"][field] = value
        elseif table == "model"
            bad["geometry"][field][1] = value
        else
            bad["origins"][1][field] = value
        end
        bad["artifact"]["content_sha256"] =
            computed_geometry_sha256(bad)
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end

    for forbidden in FORBIDDEN_GEOMETRY_FIELD_TOKENS
        bad = geometry_document()
        bad["origins"][1]["$(forbidden)_value"] = 0.0
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end
    for forbidden in (
            "forecast_value",
            "ground_truth",
            "model_error",
            "relative_loss",
            "skill_score",
            "model_rank",
            "pvalue",
            "p_value",
            "estimated_effect",
        )
        bad = geometry_document()
        bad["geometry"][forbidden] = "forbidden"
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end

    unknown_regime = geometry_document()
    unknown_regime["origins"][1]["regime_labels"] = ["UNKNOWN"]
    unknown_regime["artifact"]["content_sha256"] =
        computed_geometry_sha256(unknown_regime)
    @test_throws CalibrationContractError validate_score_blind_geometry(
        unknown_regime,
    )
    for dubious in ("Used", "Other")
        bad = geometry_document()
        bad["origins"][1]["regime_labels"] = [dubious]
        bad["artifact"]["content_sha256"] =
            computed_geometry_sha256(bad)
        @test_throws CalibrationContractError validate_score_blind_geometry(
            bad,
        )
    end

    stale_hash = geometry_document()
    stale_hash["geometry"]["origin_count"] = 3
    @test_throws CalibrationContractError validate_score_blind_geometry(
        stale_hash,
    )
end

@testset "deterministic domain-separated seeds" begin
    dgp_seed = derive_dgp_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        1,
    )
    bootstrap_seed = derive_bootstrap_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        "J01",
        1,
    )
    @test MASTER_SEED == 0x55534643414c4942
    @test dgp_seed == 0x6a8755500d01fa6d
    @test bootstrap_seed == 0x97eb200ae4ee273e
    @test dgp_seed == derive_dgp_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        1,
    )
    @test dgp_seed != derive_dgp_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        2,
    )
    @test dgp_seed != derive_dgp_seed(
        "SCREENING",
        "N02_FE_GAUSS_R40",
        "geom.v1",
        1,
    )
    @test bootstrap_seed != derive_bootstrap_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        "J02",
        1,
    )
    @test_throws CalibrationContractError derive_dgp_seed(
        "Other",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        1,
    )
    @test_throws CalibrationContractError derive_bootstrap_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        "Used",
        1,
    )
    @test_throws CalibrationContractError derive_dgp_seed(
        "SCREENING",
        "UNKNOWN",
        "geom.v1",
        1,
    )
    @test_throws CalibrationContractError derive_dgp_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "uNkNoWn",
        1,
    )
    @test_throws CalibrationContractError derive_dgp_seed(
        "SCREENING",
        "N01_FE_GAUSS_EXP",
        "geom.v1",
        true,
    )
end

@testset "rehearsal geometry and no-future estimation windows" begin
    @test estimation_indices(41, "EXPANDING") == 1:40
    @test estimation_indices(41, "ROLLING_40") == 1:40
    @test estimation_indices(61, "ROLLING_60") == 1:60
    @test estimation_indices(75, "ROLLING_40") == 35:74
    @test maximum(estimation_indices(75, "EXPANDING")) == 74
    @test maximum(estimation_indices(75, "ROLLING_40")) == 74
    @test maximum(estimation_indices(75, "ROLLING_60")) == 74
    @test_throws CalibrationContractError estimation_indices(
        41,
        "ROLLING_60",
    )
    @test_throws CalibrationContractError estimation_indices(41, "Used")
    @test_throws CalibrationContractError estimation_indices(true, "EXPANDING")

    all_counts = Tuple(
        length(eligible_origin_indices(horizon, "EXPANDING"))
            for horizon in HORIZONS
    )
    rolling_counts = Tuple(
        length(eligible_origin_indices(horizon, "ROLLING_60"))
            for horizon in HORIZONS
    )
    @test all_counts == REHEARSAL_ALL_AVAILABLE_COUNTS
    @test rolling_counts == REHEARSAL_ROLLING60_COUNTS
    @test intersect(
        (
            collect(eligible_origin_indices(horizon, "EXPANDING"))
                for horizon in HORIZONS
        )...,
    ) == collect(41:90)
    @test intersect(
        (
            collect(eligible_origin_indices(horizon, "ROLLING_60"))
                for horizon in HORIZONS
        )...,
    ) == collect(61:90)
    @test length(41:90) == REHEARSAL_BALANCED_COUNT
    @test length(61:90) == 30
    @test_throws CalibrationContractError eligible_origin_indices(
        3,
        "EXPANDING",
    )
end

@testset "target factors are unit variance and PSD" begin
    loadings = target_factor_loadings()
    covariance = target_factor_covariance()
    @test size(loadings) == (4, 6)
    @test size(covariance) == (4, 4)
    @test covariance ≈ transpose(covariance)
    @test diag(covariance) ≈ ones(4)
    @test minimum(eigvals(Symmetric(covariance))) >= -1.0e-14
    @test covariance[1, 2] ≈ 0.28
    @test covariance[1, 3] ≈ -0.42
    @test covariance[3, 4] ≈ -0.13

    strong_loadings = target_factor_loadings(; strong_common = true)
    strong_covariance = target_factor_covariance(; strong_common = true)
    @test diag(strong_covariance) ≈ ones(4)
    @test minimum(eigvals(Symmetric(strong_covariance))) >= -1.0e-14
    @test all(
        isapprox.(
            vec(sum(strong_loadings[:, 1:2] .^ 2; dims = 2)),
            fill(0.7, 4);
            atol = 1.0e-14,
        ),
    )
end

@testset "primitive generators, burn-in, and boundary labels" begin
    kinds = (
        "IID_GAUSSIAN",
        "AR035",
        "AR075",
        "STUDENT_T5",
        "STUDENT_T3",
        "GARCH_010_085",
    )
    for (index, kind) in enumerate(kinds)
        values = primitive_innovations(
            kind,
            64;
            seed = UInt64(index),
            burn_in = kind == "IID_GAUSSIAN" ? 0 : 2_000,
        )
        repeated = primitive_innovations(
            kind,
            64;
            seed = UInt64(index),
            burn_in = kind == "IID_GAUSSIAN" ? 0 : 2_000,
        )
        @test length(values) == 64
        @test all(isfinite, values)
        @test values == repeated
        @test std(values) > 0
    end
    @test_throws CalibrationContractError primitive_innovations(
        "AR035",
        10;
        seed = 1,
        burn_in = 1_999,
    )
    @test_throws CalibrationContractError primitive_innovations(
        "GARCH_010_085",
        10;
        seed = 1,
        burn_in = 0,
    )
    @test_throws CalibrationContractError primitive_innovations(
        "Other",
        10;
        seed = 1,
    )
    @test_throws CalibrationContractError primitive_innovations(
        "IID_GAUSSIAN",
        10;
        seed = true,
    )

    base = ones(16)
    acute = apply_boundary_stress(base, "ACUTE_VARIANCE_9X")
    permanent = apply_boundary_stress(base, "PERMANENT_VARIANCE_4X")
    reversal = apply_boundary_stress(
        zeros(16),
        "WHOLE_SAMPLE_ZERO_MEAN_REVERSAL",
    )
    @test count(==(3.0), acute) == 8
    @test count(==(1.0), acute) == 8
    @test permanent[1:8] == ones(8)
    @test permanent[9:16] == fill(2.0, 8)
    @test mean(reversal) == 0.0
    @test reversal[1:8] == ones(8)
    @test reversal[9:16] == fill(-1.0, 8)
    @test apply_boundary_stress(base, "NONE") == base
    @test_throws CalibrationContractError apply_boundary_stress(
        ones(7),
        "ACUTE_VARIANCE_9X",
    )

    @test primitive_loss_eligibility(
        "STUDENT_T3",
        :squared,
    ) == (
        eligible = false,
        role = :negative_control,
        reason = :undefined_fourth_moment,
    )
    @test primitive_loss_eligibility(
        "STUDENT_T3",
        :absolute,
    ).role == :boundary_diagnostic_only
    @test !primitive_loss_eligibility(
        "STUDENT_T3",
        :absolute,
    ).eligible
    @test primitive_loss_eligibility(
        "STUDENT_T5",
        :squared,
    ).eligible
end

@testset "exchangeable null generator and production loss construction" begin
    generated = generate_null_forecast_errors(
        41:43;
        design = "EXPANDING",
        primitive_kind = "IID_GAUSSIAN",
        seed = 0x1234,
    )
    repeated = generate_null_forecast_errors(
        41:43;
        design = "EXPANDING",
        primitive_kind = "IID_GAUSSIAN",
        seed = 0x1234,
    )
    @test generated.origins == (41, 42, 43)
    @test generated.design == :expanding
    @test size(generated.errors) == (3, 11, 4, 5)
    @test all(isfinite, generated.errors)
    @test generated.errors == repeated.errors
    @test generated.errors[:, 1, :, :] != generated.errors[:, 2, :, :]
    @test generated.target_covariance ≈ target_factor_covariance()
    @test overlap_correlation(12, 0) == 1.0
    @test overlap_correlation(12, 1) == 11 / 12
    @test overlap_correlation(12, 11) == 1 / 12
    @test overlap_correlation(12, 12) == 0.0
    @test overlap_correlation(4, 7) == 0.0
    @test_throws CalibrationContractError overlap_correlation(3, 1)

    squared = family_loss_differentials(
        generated.errors;
        loss = :squared,
    )
    absolute = family_loss_differentials(
        generated.errors;
        loss = :absolute,
    )
    @test size(squared.differentials) == (3, 200)
    @test size(absolute.differentials) == (3, 200)
    @test length(squared.hypothesis_ids) == 200
    @test length(unique(squared.hypothesis_ids)) == 200
    @test squared.hypothesis_ids[1] ==
        "comparison1_real_gdp_growth_h1"
    @test squared.hypothesis_ids[200] == "comparison10_effr_h12"
    @test squared.mapping[1] == (
        column = 1,
        hypothesis_id = "comparison1_real_gdp_growth_h1",
        comparison_id = "comparison1",
        comparator_model_position = 1,
        challenger_model_position = 2,
        target_position = 1,
        target_id = "real_gdp_growth",
        horizon_position = 1,
        horizon = 1,
    )
    @test squared.mapping[200] == (
        column = 200,
        hypothesis_id = "comparison10_effr_h12",
        comparison_id = "comparison10",
        comparator_model_position = 1,
        challenger_model_position = 11,
        target_position = 4,
        target_id = "effr",
        horizon_position = 5,
        horizon = 12,
    )
    @test squared.horizons[1:5] == HORIZONS
    @test squared.loss == :squared
    @test absolute.loss == :absolute
    expected_first_squared =
        generated.errors[:, 2, 1, 1] .^ 2 .-
        generated.errors[:, 1, 1, 1] .^ 2
    expected_first_absolute =
        abs.(generated.errors[:, 2, 1, 1]) .-
        abs.(generated.errors[:, 1, 1, 1])
    @test squared.differentials[:, 1] == expected_first_squared
    @test absolute.differentials[:, 1] == expected_first_absolute
    expected_last_squared =
        generated.errors[:, 11, 4, 5] .^ 2 .-
        generated.errors[:, 1, 4, 5] .^ 2
    @test squared.differentials[:, 200] == expected_last_squared

    direct = generate_direct_null_differentials(
        20;
        hypotheses = 7,
        seed = 0x99,
    )
    @test size(direct) == (20, 7)
    @test direct == generate_direct_null_differentials(
        20;
        hypotheses = 7,
        seed = 0x99,
    )
    @test all(isfinite, direct)
    reference_rng = MersenneTwister(UInt64(0x99))
    independent_reference = Matrix{Float64}(undef, 20, 7)
    randn!(reference_rng, independent_reference)
    @test direct == independent_reference
    large_direct = generate_direct_null_differentials(
        5_000;
        hypotheses = 3,
        seed = 0x1122,
    )
    direct_correlations = cor(large_direct)
    @test maximum(
        abs.(
            direct_correlations -
                Matrix{Float64}(I, 3, 3)
        ),
    ) < 0.05
end

@testset "typed missingness is fail-closed and never imputes" begin
    @test parse_missingness_policy("COMPLETE") == COMPLETE
    @test parse_missingness_policy("TERMINAL_HORIZON_MATURITY") ==
        TERMINAL_HORIZON_MATURITY
    for invalid in ("Used", "Other", "UNKNOWN", "")
        @test_throws CalibrationContractError parse_missingness_policy(invalid)
    end

    @test_throws UndefKeywordError missingness_mask(
        COMPLETE;
        origin_count = 50,
    )
    @test_throws CalibrationContractError missingness_mask(
        COMPLETE;
        origin_count = 50,
        minimum_retained_origins = 1,
    )
    @test_throws CalibrationContractError missingness_mask(
        COMPLETE;
        origin_count = 3,
        minimum_retained_origins = 4,
    )
    complete = missingness_mask(
        COMPLETE;
        origin_count = 50,
        minimum_retained_origins = 40,
    )
    @test size(complete.mask) == (50, 200)
    @test all(complete.mask)
    @test complete.retained_origins == Tuple(1:50)
    @test complete.action == :complete_case_without_imputation
    @test complete.minimum_retained_origins == 40

    terminal = missingness_mask(
        TERMINAL_HORIZON_MATURITY;
        origin_count = 61,
        minimum_retained_origins = 50,
    )
    @test length(terminal.retained_origins) == 50
    @test Tuple(sum(terminal.mask[:, horizon:5:200]) ÷ 40 for horizon in 1:5) ==
        REHEARSAL_ALL_AVAILABLE_COUNTS
    @test_throws CalibrationContractError missingness_mask(
        TERMINAL_HORIZON_MATURITY;
        origin_count = 50,
        minimum_retained_origins = 2,
    )

    outage = missingness_mask(
        COMMON_FOUR_ORIGIN_OUTAGE;
        origin_count = 50,
        minimum_retained_origins = 40,
        outage_origins = (2, 7, 11, 49),
    )
    @test length(outage.retained_origins) == 46
    @test all(.!outage.mask[[2, 7, 11, 49], :])
    @test_throws CalibrationContractError missingness_mask(
        COMMON_FOUR_ORIGIN_OUTAGE;
        origin_count = 50,
        minimum_retained_origins = 2,
        outage_origins = (1, 2, 3),
    )
    @test_throws CalibrationContractError missingness_mask(
        COMMON_FOUR_ORIGIN_OUTAGE;
        origin_count = 5,
        minimum_retained_origins = 2,
        outage_origins = (1, 2, 3, 4),
    )

    lagged = missingness_mask(
        SCORE_BLIND_LAGGED_STATE;
        origin_count = 5,
        minimum_retained_origins = 3,
        lagged_state = (true, false, true, false, true),
    )
    @test lagged.retained_origins == (1, 3, 5)
    @test_throws CalibrationContractError missingness_mask(
        SCORE_BLIND_LAGGED_STATE;
        origin_count = 2,
        minimum_retained_origins = 2,
        lagged_state = (true, 1),
    )

    @test_throws CalibrationContractError missingness_mask(
        TARGET_SPECIFIC_GAPS;
        origin_count = 10,
        minimum_retained_origins = 2,
        target_gap_pairs = ((2, 1),),
    )
    global_intersection = missingness_mask(
        TARGET_SPECIFIC_GAPS;
        origin_count = 10,
        minimum_retained_origins = 8,
        target_gap_pairs = ((2, 1), (7, 4), (2, 3)),
        global_intersection_sealed = true,
    )
    @test global_intersection.retained_origins ==
        (1, 3, 4, 5, 6, 8, 9, 10)
    @test all(.!global_intersection.mask[[2, 7], :])
    @test_throws CalibrationContractError missingness_mask(
        TARGET_SPECIFIC_GAPS;
        origin_count = 10,
        minimum_retained_origins = 2,
        target_gap_pairs = ((2, 1), (2, 1)),
        global_intersection_sealed = true,
    )

    @test_throws CalibrationContractError missingness_mask(
        MODEL_EXECUTION_FAILURE;
        origin_count = 50,
        minimum_retained_origins = 2,
    )
    @test_throws CalibrationContractError missingness_mask(
        OUTCOME_DEPENDENT_FORBIDDEN;
        origin_count = 50,
        minimum_retained_origins = 2,
    )
end

@testset "false-null masks have exact registered cardinality" begin
    expected_counts = (1, 5, 20, 200)
    for (pattern, expected) in zip(
            FALSE_NULL_PATTERN_IDS,
            expected_counts,
        )
        mask = false_null_mask(pattern)
        @test length(mask) == 200
        @test count(mask) == expected
    end
    @test findall(false_null_mask("SINGLE")) == [1]
    @test findall(false_null_mask("TARGET5")) == collect(1:5)
    @test findall(false_null_mask("MODEL20")) == collect(1:20)
    @test all(false_null_mask("DENSE200"))
    for invalid in ("Used", "Other", "UNKNOWN")
        @test_throws CalibrationContractError false_null_mask(invalid)
    end
end

@testset "registered joint block policies and effective-12 equivalence" begin
    expected = (
        "J01" => (1.0, :none, 1.0),
        "J02" => (4.0, :none, 4.0),
        "J03" => (4.0, :max_horizon, 12.0),
        "J04" => (24.0, :none, 24.0),
    )
    for (policy_id, values) in expected
        policy = block_policy(policy_id)
        @test policy.policy_id == policy_id
        @test policy.requested_block_length == values[1]
        @test policy.horizon_floor_policy == values[2]
        @test policy.joint_effective_block_length == values[3]
    end
    @test_throws CalibrationContractError block_policy("Used")
    @test_throws CalibrationContractError block_policy("Other")

    j03 = policy_indices(
        50,
        "J03";
        seed = 0xfeed,
        replicates = 37,
    )
    reference =
        USForecastInferenceCalibration.USForecastInference.stationary_bootstrap_indices(
        50,
        collect(HORIZONS);
        block_length =
            USForecastInferenceCalibration.USForecastInference.FixedBlockLength(
            12,
        ),
        horizon_floor_policy = :none,
        seed = 0xfeed,
        replicates = 37,
    )
    @test j03.indices == reference.indices
    @test j03.metadata.requested_block_length == 4.0
    @test j03.metadata.horizon_floor_policy == :max_horizon
    @test j03.metadata.joint_effective_block_length == 12.0
    @test reference.block_length.requested == 12.0
    @test reference.block_length.horizon_floor_policy == :none
    @test reference.block_length.effective == 12.0
    @test policy_indices(
        50,
        "J03";
        seed = 0xfeed,
        replicates = 37,
    ).indices == j03.indices
end

@testset "exact Clopper-Pearson references and boundaries" begin
    five = clopper_pearson_interval(5, 100; confidence_level = 0.95)
    @test five.lower ≈ 0.016431879182052158 atol = 8.0e-15
    @test five.upper ≈ 0.11283491110546275 atol = 8.0e-15
    @test clopper_pearson_upper(
        5,
        100;
        confidence_level = 0.95,
    ) ≈ 0.1022533776432745 atol = 8.0e-15

    zero = clopper_pearson_interval(0, 100; confidence_level = 0.95)
    full = clopper_pearson_interval(100, 100; confidence_level = 0.95)
    @test zero.lower == 0.0
    @test zero.upper ≈ 0.03621669264517641 atol = 8.0e-15
    @test full.lower ≈ 0.9637833073548236 atol = 8.0e-15
    @test full.upper == 1.0
    @test clopper_pearson_lower(
        0,
        100;
        confidence_level = 0.95,
    ) == 0.0
    @test clopper_pearson_upper(
        100,
        100;
        confidence_level = 0.95,
    ) == 1.0

    half = clopper_pearson_interval(50, 100; confidence_level = 0.99)
    @test half.lower ≈ 0.36886143735892407 atol = 8.0e-15
    @test half.upper ≈ 0.6311385626410759 atol = 8.0e-15
    @test_throws CalibrationContractError clopper_pearson_interval(6, 5)
    @test_throws CalibrationContractError clopper_pearson_interval(
        true,
        5,
    )
    @test_throws CalibrationContractError clopper_pearson_interval(
        1,
        5;
        confidence_level = true,
    )
end

@testset "shard identity and merge are scheduling invariant" begin
    first_shard = calibration_shard(
        stage = "SCREENING",
        configuration_id = "N01.n50.J01",
        replication_ids = 1:5,
        rejection_count = 1,
        numeric_failure_count = 0,
        payload_sha256 = repeat("a", 64),
    )
    second_shard = calibration_shard(
        stage = "SCREENING",
        configuration_id = "N01.n50.J01",
        replication_ids = 6:10,
        rejection_count = 2,
        numeric_failure_count = 0,
        payload_sha256 = repeat("b", 64),
    )
    repeated = calibration_shard(
        stage = "SCREENING",
        configuration_id = "N01.n50.J01",
        replication_ids = 1:5,
        rejection_count = 1,
        numeric_failure_count = 0,
        payload_sha256 = repeat("a", 64),
    )
    @test first_shard.shard_id == repeated.shard_id
    @test first_shard.replication_ids == Tuple(1:5)
    @test occursin(r"^[0-9a-f]{64}$", first_shard.shard_id)

    forward = merge_shards(
        [first_shard, second_shard];
        expected_replication_ids = 1:10,
    )
    reverse = merge_shards(
        [second_shard, first_shard];
        expected_replication_ids = 1:10,
    )
    @test forward == reverse
    @test forward.replication_ids == Tuple(1:10)
    @test forward.ordered_shard_ids ==
        (first_shard.shard_id, second_shard.shard_id)
    @test forward.rejection_count == 3
    @test forward.numeric_failure_count == 0
    @test occursin(r"^[0-9a-f]{64}$", forward.merge_sha256)

    @test_throws CalibrationContractError merge_shards(
        [first_shard, first_shard];
        expected_replication_ids = 1:5,
    )
    @test_throws CalibrationContractError merge_shards(
        [first_shard];
        expected_replication_ids = 1:10,
    )
    @test_throws CalibrationContractError merge_shards(
        [first_shard, second_shard];
        expected_replication_ids = vcat(collect(1:9), 11),
    )
    @test_throws CalibrationContractError calibration_shard(
        stage = "SMOKE",
        configuration_id = "smoke",
        replication_ids = 1:2,
        rejection_count = 0,
        numeric_failure_count = 0,
        payload_sha256 = repeat("a", 64),
    )
end

@testset "full execution remains explicitly fail-closed" begin
    smoke = execution_authorization("SMOKE")
    @test smoke.authorized
    @test !smoke.evidentiary
    @test smoke.geometry === nothing
    @test !smoke.calibration_evidence_created
    @test_throws CalibrationContractError execution_authorization(
        "SMOKE";
        explicit_expensive_mode = true,
    )
    @test_throws CalibrationContractError execution_authorization(
        "SMOKE";
        geometry_path = "forbidden.toml",
    )
    @test_throws CalibrationContractError execution_authorization(
        "SMOKE";
        expected_geometry_sha256 = repeat("a", 64),
    )
    @test_throws CalibrationContractError execution_authorization("SCREENING")
    @test_throws CalibrationContractError execution_authorization(
        "SCREENING";
        explicit_expensive_mode = true,
    )
    @test_throws CalibrationContractError execution_authorization(
        "Used";
        explicit_expensive_mode = true,
    )

    mktempdir() do directory
        path = joinpath(directory, "geometry.toml")
        original_document = geometry_document()
        original_pin = original_document["artifact"]["content_sha256"]
        open(path, "w") do io
            TOML.print(io, original_document)
        end
        loaded = load_score_blind_geometry(path)
        @test loaded.geometry.geometry_id == "synthetic.geometry.v1"
        @test loaded.content_sha256 ==
            computed_geometry_sha256(TOML.parsefile(path))
        @test occursin(r"^[0-9a-f]{64}$", loaded.file_sha256)
        @test_throws CalibrationContractError execution_authorization(
            "SCREENING";
            geometry_path = path,
            explicit_expensive_mode = true,
        )
        @test_throws CalibrationContractError execution_authorization(
            "SCREENING";
            geometry_path = path,
            expected_geometry_sha256 = repeat("a", 64),
            explicit_expensive_mode = true,
        )
        @test_throws CalibrationContractError execution_authorization(
            "SCREENING";
            geometry_path = path,
            expected_geometry_sha256 = "not-a-hash",
            explicit_expensive_mode = true,
        )
        authorization = execution_authorization(
            "SCREENING";
            geometry_path = path,
            expected_geometry_sha256 = original_pin,
            explicit_expensive_mode = true,
        )
        @test authorization.authorized
        @test !authorization.evidentiary
        @test authorization.stage == :screening
        @test authorization.geometry.path == abspath(path)
        @test authorization.geometry.geometry_id == "synthetic.geometry.v1"
        @test authorization.geometry.expected_content_sha256 == original_pin
        @test authorization.geometry.content_sha256 == original_pin
        @test !authorization.calibration_evidence_created

        tampered_path = joinpath(directory, "tampered_geometry.toml")
        tampered = geometry_document()
        tampered["geometry"]["sesoi_registry_id"] =
            "sesoi.policy_units.v2"
        tampered["artifact"]["content_sha256"] =
            computed_geometry_sha256(tampered)
        @test tampered["artifact"]["content_sha256"] != original_pin
        open(tampered_path, "w") do io
            TOML.print(io, tampered)
        end
        @test load_score_blind_geometry(tampered_path).content_sha256 ==
            tampered["artifact"]["content_sha256"]
        @test_throws CalibrationContractError execution_authorization(
            "SCREENING";
            geometry_path = tampered_path,
            expected_geometry_sha256 = original_pin,
            explicit_expensive_mode = true,
        )
    end
end

@testset "source boundary excludes diagnostic imports and runner claims" begin
    source = read(joinpath(@__DIR__, "USForecastInferenceCalibration.jl"), String)
    @test !occursin("USRevisedDataSemiStructuralComparison", source)
    @test !occursin("run_revised_data", source)
    @test !occursin("data/us/", source)
    @test !isfile(joinpath(@__DIR__, "calibration_results.toml"))
    @test !isfile(joinpath(@__DIR__, "selected_policy.toml"))
end
