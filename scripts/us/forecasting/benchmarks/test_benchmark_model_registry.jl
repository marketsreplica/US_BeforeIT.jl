using TOML
using Test

if !isdefined(Main, :USBenchmarkModelRegistry)
    include("USBenchmarkModelRegistry.jl")
end
using .USBenchmarkModelRegistry

if !isdefined(Main, :USForecastBenchmarks)
    include("USForecastBenchmarks.jl")
end
using .USForecastBenchmarks

registry_fixture() = TOML.parsefile(DEFAULT_REGISTRY_PATH)

function expected_specs()
    return Any[
        NoChangeSpec(),
        DriftSpec(),
        HistoricalMeanSpec(),
        SeasonalNaiveSpec(4),
        ARSpec(candidate_lags = [1], intercept = true),
        ARSpec(candidate_lags = [4], intercept = true),
        ARSpec(candidate_lags = 1:8, intercept = true),
        DirectARSpec(candidate_lags = [1], intercept = true),
        DirectARSpec(candidate_lags = [4], intercept = true),
        DirectARSpec(candidate_lags = 1:8, intercept = true),
        BeforeITVARSpec(lags = 1, intercept = true),
        BeforeITVARSpec(lags = 2, intercept = true),
        BeforeITVARSpec(lags = 3, intercept = true),
        BVARSpec(lags = 1, intercept = true, own_lag_mean = 0.0),
        SemiStructuralSpec(),
    ]
end

@testset "default benchmark model registry is sealed and complete" begin
    registry = load_model_registry()
    models = registry["models"]
    panels = registry["target_panels"]
    panel = panels[1]

    @test length(registry["artifacts"]) == 7
    @test registry["artifacts"][5]["path"] ==
        "SEMI_STRUCTURAL_MODEL_CARD.md"
    @test registry["artifacts"][6]["path"] == "direct_ar.jl"
    @test registry["artifacts"][7]["path"] == "DIRECT_AR_MODEL_CARD.md"
    @test length(models) == 15
    @test length(panels) == 2
    @test length(panel["targets"]) == 8
    @test registry["canonical_tracks"] ==
        ["common_information", "published_forecast"]
    @test !registry["cross_track_pooling"]
    @test !registry["execution_scope"][
        "empirical_forecast_execution_allowed",
    ]
    @test !registry["execution_scope"]["production_scoring_allowed"]
    @test registry["registry_content_sha256"] ==
        registry_content_sha256(registry)

    registered_ids = [model["model_id"] for model in models]
    instantiated_ids = model_id.(expected_specs())
    @test registered_ids == instantiated_ids
    @test length(unique(registered_ids)) == length(registered_ids)
    @test all(
        model_card(spec)["model_id"] == registered_id for
            (spec, registered_id) in zip(expected_specs(), registered_ids)
    )

    family_counts = Dict(
        family => count(model -> model["family"] == family, models) for
            family in unique(model["family"] for model in models)
    )
    @test family_counts == Dict(
        "random_walk" => 3,
        "seasonal_naive" => 1,
        "ar" => 6,
        "var" => 3,
        "bvar" => 1,
        "compact_semi_structural" => 1,
    )
    @test all(
        model["information_track"] == "common_information" for model in models
    )
    @test all(
        model["products"] == ["quarterly_unconditional"] for model in models
    )
    @test count(
        model -> model["density"]["parameter_uncertainty_included"],
        models,
    ) == 1

    direct_models = models[8:10]
    @test [model["model_id"] for model in direct_models] ==
        model_id.(
        [
            DirectARSpec(candidate_lags = [1], intercept = true),
            DirectARSpec(candidate_lags = [4], intercept = true),
            DirectARSpec(candidate_lags = 1:8, intercept = true),
        ],
    )
    @test all(
        model["target_panel_id"] ==
            "tier1_quarterly_primary_transformations_v1" for
            model in direct_models
    )
    @test all(
        model["source_artifact_ids"] ==
            ["benchmark_kernel_source", "direct_ar_source"] for
            model in direct_models
    )
    @test all(
        model["model_card_artifact_id"] == "direct_ar_model_card" for
            model in direct_models
    )
    @test all(
        model["specification"]["forecast_method"] ==
            "horizon_specific_direct_multi_step_ols" for
            model in direct_models
    )
    @test direct_models[3]["specification"]["parameters"][
        "candidate_comparison_window",
    ] ==
        "origins_max_candidate_lag_through_T_minus_h_common_response_dates"
    @test direct_models[3]["specification"]["parameters"][
        "selected_lag_refit_window",
    ] == "origins_selected_lag_through_T_minus_h"
    @test all(
        model["specification"]["parameters"]["information_window"] ==
            "expanding_origin_only_no_future_target_or_exogenous_data" for
            model in direct_models
    )
    @test all(
        model["density"]["construction"] ==
            "joint_gaussian_plugin_full_aligned_horizon_by_target_residual_covariance" for
            model in direct_models
    )
    @test all(
        !model["density"]["parameter_uncertainty_included"] &&
            !model["specification"]["parameters"][
                "coefficient_uncertainty_included",
            ] &&
            !model["specification"]["parameters"][
                "lag_selection_uncertainty_included",
            ] &&
            !model["specification"]["parameters"][
                "covariance_estimation_uncertainty_included",
            ] for model in direct_models
    )
    @test all(
        model["specification"]["parameters"]["exogenous_policy"] ==
            "reject_x_train_and_x_future" for model in direct_models
    )
    @test all(
        !model["specification"]["parameters"][
                "pandemic_special_treatment",
            ] &&
            !model["specification"]["parameters"]["elb_special_treatment"] &&
            model["specification"]["parameters"]["comparative_claim"] ==
            "no_direct_dominance_claim" for model in direct_models
    )
    @test all(
        model["convergence"]["density_success_gate"] ==
            "aligned_origins_exceed_H_times_K_centered_residual_full_column_rank_covariance_degrees_of_freedom_positive_definite_and_exact_finite_shape_or_structured_failure" for
            model in direct_models
    )

    semi = models[15]
    @test semi["model_id"] == model_id(SemiStructuralSpec())
    @test semi["target_panel_id"] == "quarterly_core4_contract_v1"
    @test semi["specification"]["parameters"]["model_class"] ==
        "semi_structural_not_dsge"
    @test !semi["specification"]["parameters"]["dsge_model"]
    @test !semi["specification"]["parameters"]["origin_parameter_fitting"]
    @test !semi["specification"]["parameters"][
        "full_posterior_parameter_density",
    ]
    @test semi["specification"]["parameters"]["fiscal_block"] ==
        "not_implemented"
    @test semi["specification"]["parameters"]["foreign_block"] ==
        "not_implemented"
    @test !semi["density"]["parameter_uncertainty_included"]

    manifests = [
        model_manifest_sha256(registry, model_id) for
            model_id in registered_ids
    ]
    @test all(digest -> occursin(r"^[0-9a-f]{64}$", digest), manifests)
    @test length(unique(manifests)) == length(manifests)
    @test model_entry(registry, "naive_no_change")["family"] ==
        "random_walk"
    @test_throws ModelRegistryValidationError model_entry(
        registry,
        model_id(BeforeITVARXSpec(lags = 1)),
    )
    @test_throws ModelRegistryValidationError model_entry(
        registry,
        model_id(DirectARSpec(candidate_lags = [2], intercept = true)),
    )
end

@testset "protocol vocabulary and target transformations agree" begin
    protocol_path = normpath(joinpath(@__DIR__, "..", "protocol.toml"))
    protocol = TOML.parsefile(protocol_path)
    target_coverage_path =
        normpath(joinpath(@__DIR__, "..", "targets", "tier1_targets.toml"))
    target_coverage = TOML.parsefile(target_coverage_path)
    benchmark_sections = Set(
        String(key) for key in keys(protocol["benchmarks"]) if
            String(key) in CANONICAL_TRACKS
    )
    @test benchmark_sections == Set(CANONICAL_TRACKS)

    product_tracks = String[]
    for (key, product) in protocol["products"]
        key == "cross_product_pooling" && continue
        append!(product_tracks, String.(product["benchmark_tracks"]))
    end
    @test Set(product_tracks) == Set(CANONICAL_TRACKS)
    @test all(track -> track in CANONICAL_TRACKS, product_tracks)
    @test !occursin("published_information", read(protocol_path, String))

    registry = load_model_registry()
    protocol_targets = protocol["targets"]
    registry_targets = registry["target_panels"][1]["targets"]
    @test [target["target_id"] for target in registry_targets] ==
        [target["target_id"] for target in protocol_targets]
    @test [
        target["primary_transformation"] for target in registry_targets
    ] == [target["primary_transformation"] for target in protocol_targets]
    @test [
        target["secondary_transformation"] for target in registry_targets
    ] == [target["secondary_transformation"] for target in protocol_targets]
    coverage_by_id = Dict(
        target["target_id"] => target for target in target_coverage["targets"]
    )
    coverage_fields = [
        "target_version",
        "operator_version",
        "aggregation",
        "primary_transformation",
        "secondary_transformation",
        "transformation_version",
        "output_unit",
    ]
    @test all(
        target[field] == coverage_by_id[target["target_id"]][field] for
            target in registry_targets for field in coverage_fields
    )

    core4 = registry["target_panels"][2]
    @test [target["target_id"] for target in core4["targets"]] == [
        "real_gdp",
        "pce_price_index",
        "unemployment_rate",
        "effective_federal_funds_rate",
    ]
    @test [target["model_input_name"] for target in core4["targets"]] ==
        collect(SEMI_STRUCTURAL_TARGET_NAMES)
    @test [target["model_input_unit"] for target in core4["targets"]] ==
        collect(SEMI_STRUCTURAL_TARGET_UNITS)
    @test [
        target["primary_transformation"] for target in core4["targets"]
    ] == [
        "annualized_qoq_log_growth",
        "annualized_qoq_log_inflation",
        "percent_level",
        "percentage_point_level",
    ]
    @test [target["transformation_version"] for target in core4["targets"]] ==
        [
        "us-real-gdp-growth.v1-draft",
        "us-pce-price-inflation.v1-draft",
        "us-cps-unemployment-quarterly.v1-draft",
        "us-effr-quarterly-average.v1-draft",
    ]
end

@testset "unknown keys and incomplete policy records fail closed" begin
    unknown_root = registry_fixture()
    unknown_root["comment"] = "not part of the schema"
    @test_throws ModelRegistryValidationError validate_model_registry(
        unknown_root;
        verify_artifacts = false,
    )

    unknown_nested = registry_fixture()
    unknown_nested["models"][1]["density"]["oracle_adjustment"] = false
    @test_throws ModelRegistryValidationError validate_model_registry(
        unknown_nested;
        verify_artifacts = false,
    )

    for policy in (
            "transformations",
            "estimation_window",
            "pandemic_elb",
            "density",
            "fallback",
            "convergence",
        )
        incomplete = registry_fixture()
        first_key = first(keys(incomplete["models"][1][policy]))
        pop!(incomplete["models"][1][policy], first_key)
        @test_throws ModelRegistryValidationError validate_model_registry(
            incomplete;
            verify_artifacts = false,
        )
    end

    incomplete_specification = registry_fixture()
    pop!(
        incomplete_specification["models"][7]["specification"],
        "hyperparameter_rule",
    )
    @test_throws ModelRegistryValidationError validate_model_registry(
        incomplete_specification;
        verify_artifacts = false,
    )

    unknown_parameter = registry_fixture()
    unknown_parameter["models"][5]["specification"]["parameters"][
        "lookahead_score",
    ] = "enabled"
    @test_throws ModelRegistryValidationError validate_model_registry(
        unknown_parameter;
        verify_artifacts = false,
    )
end

@testset "duplicate and unsupported identities fail closed" begin
    duplicate_model = registry_fixture()
    duplicate_model["models"][2]["model_id"] =
        duplicate_model["models"][1]["model_id"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        duplicate_model;
        verify_artifacts = false,
    )

    unsupported_model = registry_fixture()
    unsupported_model["models"][1]["model_id"] = "unregistered_oracle_model"
    @test_throws ModelRegistryValidationError validate_model_registry(
        unsupported_model;
        verify_artifacts = false,
    )

    missing_model = registry_fixture()
    pop!(missing_model["models"])
    missing_model["expected_model_count"] = 14
    @test_throws ModelRegistryValidationError validate_model_registry(
        missing_model;
        verify_artifacts = false,
    )

    duplicate_artifact = registry_fixture()
    duplicate_artifact["artifacts"][2]["artifact_id"] =
        duplicate_artifact["artifacts"][1]["artifact_id"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        duplicate_artifact;
        verify_artifacts = false,
    )

    duplicate_product = registry_fixture()
    duplicate_product["models"][1]["products"] =
        ["quarterly_unconditional", "quarterly_unconditional"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        duplicate_product;
        verify_artifacts = false,
    )

    duplicate_source = registry_fixture()
    duplicate_source["models"][14]["source_artifact_ids"] = [
        "benchmark_kernel_source",
        "benchmark_kernel_source",
    ]
    @test_throws ModelRegistryValidationError validate_model_registry(
        duplicate_source;
        verify_artifacts = false,
    )

    duplicate_target = registry_fixture()
    duplicate_target["target_panels"][1]["targets"][2]["target_id"] =
        duplicate_target["target_panels"][1]["targets"][1]["target_id"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        duplicate_target;
        verify_artifacts = false,
    )
end

@testset "track and product boundaries fail closed" begin
    wrong_track = registry_fixture()
    wrong_track["models"][1]["information_track"] = "published_forecast"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_track;
        verify_artifacts = false,
    )

    obsolete_vocabulary = registry_fixture()
    obsolete_vocabulary["models"][1]["information_track"] =
        "published_information"
    @test_throws ModelRegistryValidationError validate_model_registry(
        obsolete_vocabulary;
        verify_artifacts = false,
    )

    cross_product = registry_fixture()
    cross_product["models"][1]["products"] = ["ex_post_replication"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        cross_product;
        verify_artifacts = false,
    )

    pooled_tracks = registry_fixture()
    pooled_tracks["cross_track_pooling"] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        pooled_tracks;
        verify_artifacts = false,
    )
end

@testset "hashes, files, and registry seal fail closed" begin
    zero_source_hash = registry_fixture()
    zero_source_hash["artifacts"][1]["sha256"] = repeat("0", 64)
    @test_throws ModelRegistryValidationError validate_model_registry(
        zero_source_hash;
        verify_artifacts = false,
    )

    malformed_card_hash = registry_fixture()
    malformed_card_hash["artifacts"][4]["sha256"] = "not-a-hash"
    @test_throws ModelRegistryValidationError validate_model_registry(
        malformed_card_hash;
        verify_artifacts = false,
    )

    unhashed_model = registry_fixture()
    unhashed_model["models"][1]["source_artifact_ids"] = String[]
    @test_throws ModelRegistryValidationError validate_model_registry(
        unhashed_model;
        verify_artifacts = false,
    )

    missing_card = registry_fixture()
    missing_card["models"][1]["model_card_artifact_id"] = "missing_card"
    @test_throws ModelRegistryValidationError validate_model_registry(
        missing_card;
        verify_artifacts = false,
    )

    wrong_file_hash = registry_fixture()
    wrong_file_hash["artifacts"][1]["sha256"] = repeat("f", 64)
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_file_hash;
        base_dir = @__DIR__,
        verify_artifacts = true,
    )

    if Sys.iswindows()
        @test true
    else
        mktempdir() do temp_dir
            cp(
                joinpath(@__DIR__, "USForecastBenchmarks.jl"),
                joinpath(temp_dir, "kernel_target.jl"),
            )
            symlink(
                "kernel_target.jl",
                joinpath(temp_dir, "USForecastBenchmarks.jl"),
            )
            symlinked_artifact = registry_fixture()
            @test_throws ModelRegistryValidationError validate_model_registry(
                symlinked_artifact;
                base_dir = temp_dir,
                verify_artifacts = true,
            )
        end
    end

    mktempdir() do temp_dir
        mkdir(joinpath(temp_dir, "USForecastBenchmarks.jl"))
        non_regular_artifact = registry_fixture()
        @test_throws ModelRegistryValidationError validate_model_registry(
            non_regular_artifact;
            base_dir = temp_dir,
            verify_artifacts = true,
        )
    end

    tampered_seal = registry_fixture()
    tampered_seal["registry_content_sha256"] = repeat("a", 64)
    @test_throws ModelRegistryValidationError validate_model_registry(
        tampered_seal;
        verify_artifacts = false,
    )

    changed_policy = registry_fixture()
    original_manifest =
        model_manifest_sha256(changed_policy, "naive_no_change")
    changed_policy["models"][1]["pandemic_elb"]["regime_selection"] =
        "outcome_selected"
    @test model_manifest_sha256(changed_policy, "naive_no_change") !=
        original_manifest
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_policy;
        verify_artifacts = false,
    )

    changed_source = registry_fixture()
    original_source_manifest =
        model_manifest_sha256(changed_source, "naive_no_change")
    changed_source["artifacts"][1]["sha256"] = repeat("b", 64)
    @test model_manifest_sha256(changed_source, "naive_no_change") !=
        original_source_manifest

    changed_semi_card = registry_fixture()
    original_semi_manifest = model_manifest_sha256(
        changed_semi_card,
        model_id(SemiStructuralSpec()),
    )
    changed_semi_card["artifacts"][5]["sha256"] = repeat("c", 64)
    @test model_manifest_sha256(
        changed_semi_card,
        model_id(SemiStructuralSpec()),
    ) != original_semi_manifest

    direct_id =
        model_id(DirectARSpec(candidate_lags = 1:8, intercept = true))
    changed_direct_source = registry_fixture()
    original_direct_source_manifest =
        model_manifest_sha256(changed_direct_source, direct_id)
    changed_direct_source["artifacts"][6]["sha256"] = repeat("d", 64)
    @test model_manifest_sha256(changed_direct_source, direct_id) !=
        original_direct_source_manifest

    changed_direct_card = registry_fixture()
    original_direct_card_manifest =
        model_manifest_sha256(changed_direct_card, direct_id)
    changed_direct_card["artifacts"][7]["sha256"] = repeat("e", 64)
    @test model_manifest_sha256(changed_direct_card, direct_id) !=
        original_direct_card_manifest
end

@testset "frozen estimation and density rules reject drift" begin
    changed_window = registry_fixture()
    changed_window["models"][11]["estimation_window"]["kind"] = "rolling"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_window;
        verify_artifacts = false,
    )

    changed_lag = registry_fixture()
    changed_lag["models"][12]["specification"]["parameters"]["lags"] = 4
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_lag;
        verify_artifacts = false,
    )

    changed_bvar_prior = registry_fixture()
    changed_bvar_prior["models"][14]["specification"]["parameters"][
        "tightness",
    ] = 0.3
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_bvar_prior;
        verify_artifacts = false,
    )

    changed_pandemic_policy = registry_fixture()
    changed_pandemic_policy["models"][1]["pandemic_elb"][
        "pandemic_treatment",
    ] = "drop_pandemic"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_pandemic_policy;
        verify_artifacts = false,
    )

    changed_elb_policy = registry_fixture()
    changed_elb_policy["models"][1]["pandemic_elb"]["elb_treatment"] =
        "shadow_rate"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_elb_policy;
        verify_artifacts = false,
    )

    changed_density = registry_fixture()
    changed_density["models"][11]["density"]["construction"] =
        "independent_equation_noise"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_density;
        verify_artifacts = false,
    )

    changed_fallback = registry_fixture()
    changed_fallback["models"][11]["fallback"]["silent_substitution"] =
        "naive_no_change"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_fallback;
        verify_artifacts = false,
    )

    changed_convergence = registry_fixture()
    changed_convergence["models"][14]["convergence"]["failure_action"] =
        "retain_last_draw"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_convergence;
        verify_artifacts = false,
    )

    changed_transformation = registry_fixture()
    changed_transformation["target_panels"][1]["targets"][1][
        "primary_transformation",
    ] = "level"
    @test_throws ModelRegistryValidationError validate_model_registry(
        changed_transformation;
        verify_artifacts = false,
    )
end

@testset "direct AR implementation and uncertainty contract fails closed" begin
    wrong_direct_panel = registry_fixture()
    wrong_direct_panel["models"][8]["target_panel_id"] =
        "quarterly_core4_contract_v1"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_direct_panel;
        verify_artifacts = false,
    )

    missing_direct_source = registry_fixture()
    missing_direct_source["models"][8]["source_artifact_ids"] =
        ["benchmark_kernel_source"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        missing_direct_source;
        verify_artifacts = false,
    )

    wrong_direct_card = registry_fixture()
    wrong_direct_card["models"][8]["model_card_artifact_id"] =
        "benchmark_model_card"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_direct_card;
        verify_artifacts = false,
    )

    unequal_candidate_window = registry_fixture()
    unequal_candidate_window["models"][10]["specification"]["parameters"][
        "candidate_comparison_window",
    ] = "candidate_specific_windows"
    @test_throws ModelRegistryValidationError validate_model_registry(
        unequal_candidate_window;
        verify_artifacts = false,
    )

    no_selected_refit = registry_fixture()
    no_selected_refit["models"][10]["specification"]["parameters"][
        "selected_lag_refit_window",
    ] = "retain_common_candidate_window"
    @test_throws ModelRegistryValidationError validate_model_registry(
        no_selected_refit;
        verify_artifacts = false,
    )

    ignored_exogenous_input = registry_fixture()
    ignored_exogenous_input["models"][8]["specification"]["parameters"][
        "exogenous_policy",
    ] = "silently_ignore"
    @test_throws ModelRegistryValidationError validate_model_registry(
        ignored_exogenous_input;
        verify_artifacts = false,
    )

    invented_selection_uncertainty = registry_fixture()
    invented_selection_uncertainty["models"][10]["specification"][
        "parameters",
    ]["lag_selection_uncertainty_included"] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        invented_selection_uncertainty;
        verify_artifacts = false,
    )

    invented_covariance_uncertainty = registry_fixture()
    invented_covariance_uncertainty["models"][8]["specification"][
        "parameters",
    ]["covariance_estimation_uncertainty_included"] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        invented_covariance_uncertainty;
        verify_artifacts = false,
    )

    weakened_joint_density_gate = registry_fixture()
    weakened_joint_density_gate["models"][8]["convergence"][
        "density_success_gate",
    ] = "finite_covariance_only"
    @test_throws ModelRegistryValidationError validate_model_registry(
        weakened_joint_density_gate;
        verify_artifacts = false,
    )

    invented_pandemic_treatment = registry_fixture()
    invented_pandemic_treatment["models"][8]["specification"]["parameters"][
        "pandemic_special_treatment",
    ] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        invented_pandemic_treatment;
        verify_artifacts = false,
    )

    false_dominance_claim = registry_fixture()
    false_dominance_claim["models"][8]["specification"]["parameters"][
        "comparative_claim",
    ] = "direct_dominates_iterated"
    @test_throws ModelRegistryValidationError validate_model_registry(
        false_dominance_claim;
        verify_artifacts = false,
    )
end

@testset "semi-structural core-four and limitation contract fails closed" begin
    wrong_panel = registry_fixture()
    wrong_panel["models"][15]["target_panel_id"] =
        "tier1_quarterly_primary_transformations_v1"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_panel;
        verify_artifacts = false,
    )

    wrong_model_name = registry_fixture()
    wrong_model_name["target_panels"][2]["targets"][1]["model_input_name"] =
        "real_gdp"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_model_name;
        verify_artifacts = false,
    )

    wrong_model_unit = registry_fixture()
    wrong_model_unit["target_panels"][2]["targets"][2]["model_input_unit"] =
        "quarterly_percent"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_model_unit;
        verify_artifacts = false,
    )

    wrong_core_transform = registry_fixture()
    wrong_core_transform["target_panels"][2]["targets"][2][
        "primary_transformation",
    ] = "annualized_qoq_log_growth"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_core_transform;
        verify_artifacts = false,
    )

    wrong_transformation_version = registry_fixture()
    wrong_transformation_version["target_panels"][2]["targets"][1][
        "transformation_version",
    ] = "caller-asserted.v1"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_transformation_version;
        verify_artifacts = false,
    )

    missing_semi_source = registry_fixture()
    missing_semi_source["models"][15]["source_artifact_ids"] =
        ["benchmark_kernel_source"]
    @test_throws ModelRegistryValidationError validate_model_registry(
        missing_semi_source;
        verify_artifacts = false,
    )

    wrong_semi_card = registry_fixture()
    wrong_semi_card["models"][15]["model_card_artifact_id"] =
        "benchmark_model_card"
    @test_throws ModelRegistryValidationError validate_model_registry(
        wrong_semi_card;
        verify_artifacts = false,
    )

    fitted_at_origin = registry_fixture()
    fitted_at_origin["models"][15]["specification"]["parameters"][
        "origin_parameter_fitting",
    ] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        fitted_at_origin;
        verify_artifacts = false,
    )

    false_dsge_claim = registry_fixture()
    false_dsge_claim["models"][15]["specification"]["parameters"][
        "dsge_model",
    ] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        false_dsge_claim;
        verify_artifacts = false,
    )

    false_parameter_posterior = registry_fixture()
    false_parameter_posterior["models"][15]["density"][
        "parameter_uncertainty_included",
    ] = true
    @test_throws ModelRegistryValidationError validate_model_registry(
        false_parameter_posterior;
        verify_artifacts = false,
    )

    invented_fiscal_block = registry_fixture()
    invented_fiscal_block["models"][15]["specification"]["parameters"][
        "fiscal_block",
    ] = "implemented"
    @test_throws ModelRegistryValidationError validate_model_registry(
        invented_fiscal_block;
        verify_artifacts = false,
    )

    invented_foreign_block = registry_fixture()
    invented_foreign_block["models"][15]["specification"]["parameters"][
        "foreign_block",
    ] = "implemented"
    @test_throws ModelRegistryValidationError validate_model_registry(
        invented_foreign_block;
        verify_artifacts = false,
    )

    weakened_stability_gate = registry_fixture()
    weakened_stability_gate["models"][15]["convergence"]["stability_rule"] =
        "diagnostics_only"
    @test_throws ModelRegistryValidationError validate_model_registry(
        weakened_stability_gate;
        verify_artifacts = false,
    )
end
