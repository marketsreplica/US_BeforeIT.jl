module USBenchmarkModelRegistry

using SHA
using TOML

export CANONICAL_TRACKS,
    DEFAULT_REGISTRY_PATH,
    ModelRegistryValidationError,
    load_model_registry,
    model_entry,
    model_manifest_sha256,
    registry_content_sha256,
    validate_model_registry

const DEFAULT_REGISTRY_PATH =
    joinpath(@__DIR__, "benchmark_model_registry.toml")
const SCHEMA_VERSION = "beforeit-us-benchmark-model-registry.v1"
const REGISTRY_ID = "beforeit-us-quarterly-statistical-benchmarks.v1"
const REGISTRY_STATUS = "frozen_implementation_only"
const CANONICALIZATION = "utf8_length_prefixed_sorted_map.v1"
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const ZERO_HASH = repeat("0", 64)

const CANONICAL_TRACKS = [
    "common_information",
    "published_forecast",
]
const PRODUCT_TRACKS = Dict(
    "quarterly_unconditional" => Set(CANONICAL_TRACKS),
    "ragged_edge_nowcast" => Set(CANONICAL_TRACKS),
    "ex_ante_scenario" => Set(CANONICAL_TRACKS),
    "ex_post_replication" => Set(["common_information"]),
)
const TRACK_FAMILIES = Dict(
    "common_information" => Set(
        [
            "seasonal_naive",
            "random_walk",
            "ar",
            "var",
            "bvar",
            "dynamic_factor_bridge_midas",
            "compact_semi_structural",
            "smets_wouters_dsge",
        ],
    ),
    "published_forecast" => Set(
        [
            "spf",
            "cbo",
            "fomc_sep",
            "frbny_dsge",
            "gdpnow",
            "nyfed_staff_nowcast",
        ],
    ),
)

const TARGET_PANEL_ID = "tier1_quarterly_primary_transformations_v1"
const EXPECTED_TARGETS = [
    (
        target_id = "real_gdp",
        target_version = "bea-real-gdp.v1-draft",
        operator_version = "abm-to-bea-real-gdp.v1-draft",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_growth",
        secondary_transformation = "four_quarter_log_growth",
        transformation_version = "us-real-gdp-growth.v1-draft",
        output_unit = "percentage_points_annual_rate",
    ),
    (
        target_id = "pce_price_index",
        target_version = "bea-pce-price-index.v1-draft",
        operator_version = "abm-to-bea-pce-price-index.v1-draft",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        transformation_version = "us-pce-price-inflation.v1-draft",
        output_unit = "percentage_points_annual_rate",
    ),
    (
        target_id = "core_pce_price_index",
        target_version = "bea-core-pce-price-index.v1-draft",
        operator_version = "abm-to-bea-core-pce-price-index.v1-draft",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        transformation_version =
            "us-core-pce-price-inflation.v1-draft",
        output_unit = "percentage_points_annual_rate",
    ),
    (
        target_id = "gdp_deflator",
        target_version = "bea-gdp-deflator.v1-draft",
        operator_version = "abm-to-bea-gdp-deflator.v1-draft",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_inflation",
        secondary_transformation = "four_quarter_log_inflation",
        transformation_version = "us-gdp-deflator-inflation.v1-draft",
        output_unit = "percentage_points_annual_rate",
    ),
    (
        target_id = "unemployment_rate",
        target_version = "bls-unemployment-rate.v1-draft",
        operator_version = "abm-to-bls-unemployment-rate.v1-draft",
        aggregation = "quarterly_average_monthly",
        primary_transformation = "percent_level",
        secondary_transformation = "quarterly_change",
        transformation_version =
            "us-cps-unemployment-quarterly.v1-draft",
        output_unit = "percentage_points",
    ),
    (
        target_id = "payroll_employment",
        target_version = "bls-payroll-employment.v1-draft",
        operator_version = "abm-to-bls-payroll-employment.v1-draft",
        aggregation = "quarterly_average_monthly",
        primary_transformation = "quarterly_log_growth",
        secondary_transformation = "revision_to_level",
        transformation_version = "us-ces-payroll-quarterly.v1-draft",
        output_unit = "log_points",
    ),
    (
        target_id = "effective_federal_funds_rate",
        target_version = "frb-effective-federal-funds-rate.v1-draft",
        operator_version = "abm-to-frb-effective-federal-funds-rate.v1-draft",
        aggregation = "quarterly_average_daily",
        primary_transformation = "percentage_point_level",
        secondary_transformation = "quarterly_change",
        transformation_version = "us-effr-quarterly-average.v1-draft",
        output_unit = "percentage_points",
    ),
    (
        target_id = "nominal_gdp",
        target_version = "bea-nominal-gdp.v1-draft",
        operator_version = "abm-to-bea-nominal-gdp.v1-draft",
        aggregation = "official_quarterly",
        primary_transformation = "annualized_qoq_log_growth",
        secondary_transformation = "four_quarter_log_growth",
        transformation_version = "us-nominal-gdp-growth.v1-draft",
        output_unit = "percentage_points_annual_rate",
    ),
]
const CORE4_TARGET_PANEL_ID = "quarterly_core4_contract_v1"
target_mapping(target, model_input_name, model_input_unit) = merge(
    target,
    (
        model_input_name = model_input_name,
        model_input_unit = model_input_unit,
    ),
)
const FULL_TARGET_MAPPINGS = [
    target_mapping(target, target.target_id, target.output_unit) for
        target in EXPECTED_TARGETS
]
const CORE4_TARGETS = [
    target_mapping(
        EXPECTED_TARGETS[1],
        "real_gdp_growth",
        "annualized_quarter_over_quarter_percent",
    ),
    target_mapping(
        EXPECTED_TARGETS[2],
        "pce_inflation",
        "annualized_quarter_over_quarter_percent",
    ),
    target_mapping(
        EXPECTED_TARGETS[5],
        "unemployment_rate",
        "quarterly_average_percent",
    ),
    target_mapping(
        EXPECTED_TARGETS[7],
        "effective_federal_funds_rate",
        "quarterly_average_percent",
    ),
]
const EXPECTED_TARGET_PANELS = [
    (
        target_panel_id = TARGET_PANEL_ID,
        selection_rule =
            "all_eight_protocol_tier1_targets_in_protocol_order",
        transformation_rule =
            "pre_estimation_primary_transformation_only",
        missing_data_policy =
            "complete_case_panel_fail_origin_no_imputation",
        targets = FULL_TARGET_MAPPINGS,
    ),
    (
        target_panel_id = CORE4_TARGET_PANEL_ID,
        selection_rule =
            "protocol_core4_real_gdp_pce_unemployment_effr_in_model_order",
        transformation_rule =
            "pre_estimation_primary_transformation_mapped_to_model_contract",
        missing_data_policy =
            "complete_case_core4_fail_origin_no_imputation",
        targets = CORE4_TARGETS,
    ),
]

const EXPECTED_ARTIFACTS = [
    (
        artifact_id = "benchmark_kernel_source",
        kind = "source",
        path = "USForecastBenchmarks.jl",
    ),
    (
        artifact_id = "bvar_source",
        kind = "source",
        path = "bvar.jl",
    ),
    (
        artifact_id = "semi_structural_source",
        kind = "source",
        path = "semi_structural.jl",
    ),
    (
        artifact_id = "benchmark_model_card",
        kind = "model_card",
        path = "MODEL_CARD.md",
    ),
    (
        artifact_id = "semi_structural_model_card",
        kind = "model_card",
        path = "SEMI_STRUCTURAL_MODEL_CARD.md",
    ),
    (
        artifact_id = "direct_ar_source",
        kind = "source",
        path = "direct_ar.jl",
    ),
    (
        artifact_id = "direct_ar_model_card",
        kind = "model_card",
        path = "DIRECT_AR_MODEL_CARD.md",
    ),
]
const KERNEL_SOURCE = ["benchmark_kernel_source"]
const BVAR_SOURCES = ["benchmark_kernel_source", "bvar_source"]
const SEMI_STRUCTURAL_SOURCES =
    ["benchmark_kernel_source", "semi_structural_source"]
const DIRECT_AR_SOURCES =
    ["benchmark_kernel_source", "direct_ar_source"]
const MODEL_CARD_ARTIFACT = "benchmark_model_card"
const SEMI_STRUCTURAL_MODEL_CARD_ARTIFACT =
    "semi_structural_model_card"
const DIRECT_AR_MODEL_CARD_ARTIFACT = "direct_ar_model_card"

const COMMON_MODEL_METADATA = (
    information_track = "common_information",
    products = ["quarterly_unconditional"],
)

function specification(
        constructor,
        forecast_method,
        lag_rule,
        hyperparameter_rule,
        parameters,
    )
    return Dict{String, Any}(
        "constructor" => constructor,
        "forecast_method" => forecast_method,
        "lag_rule" => lag_rule,
        "hyperparameter_rule" => hyperparameter_rule,
        "parameters" => parameters,
    )
end

function direct_ar_parameters(candidate_lags)
    return Dict{String, Any}(
        "candidate_lags" => collect(candidate_lags),
        "intercept" => true,
        "equation_type" =>
            "horizon_specific_direct_multi_step_univariate_ols",
        "lag_selection_scope" => "separate_by_target_and_horizon",
        "candidate_comparison_window" =>
            "origins_max_candidate_lag_through_T_minus_h_common_response_dates",
        "selected_lag_refit_window" =>
            "origins_selected_lag_through_T_minus_h",
        "selection_tie_break" => "smallest_lag",
        "information_window" =>
            "expanding_origin_only_no_future_target_or_exogenous_data",
        "aligned_residual_window" =>
            "origins_max_selected_lag_across_horizon_target_through_T_minus_H",
        "joint_residual_vector_order" => "horizon_major_target_minor",
        "residual_covariance_estimator" =>
            "column_centered_corrected_full_sample_covariance",
        "density_distribution" =>
            "joint_zero_mean_gaussian_plugin_added_to_full_H_by_K_point_path",
        "coefficient_uncertainty_included" => false,
        "lag_selection_uncertainty_included" => false,
        "covariance_estimation_uncertainty_included" => false,
        "exogenous_policy" => "reject_x_train_and_x_future",
        "pandemic_special_treatment" => false,
        "elb_special_treatment" => false,
        "comparative_claim" => "no_direct_dominance_claim",
    )
end

const EXPECTED_MODELS = [
    (
        model_id = "naive_no_change",
        family = "random_walk",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "NoChangeSpec()",
            "iterated",
            "not_applicable",
            "none",
            Dict{String, Any}(),
        ),
        density_construction =
            "recursive_joint_gaussian_training_first_differences",
        parameter_uncertainty = false,
        cross_target_dependence = "training_residual_covariance",
        convergence_class = "closed_form_summary",
        estimation_success_gate = "finite_required_training_moments",
    ),
    (
        model_id = "naive_drift",
        family = "random_walk",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "DriftSpec()",
            "iterated",
            "not_applicable",
            "training_only_mean_first_difference",
            Dict{String, Any}(),
        ),
        density_construction =
            "recursive_joint_gaussian_demeaned_training_first_differences",
        parameter_uncertainty = false,
        cross_target_dependence = "training_residual_covariance",
        convergence_class = "closed_form_summary",
        estimation_success_gate = "finite_required_training_moments",
    ),
    (
        model_id = "naive_historical_mean",
        family = "random_walk",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "HistoricalMeanSpec()",
            "constant_all_horizons",
            "not_applicable",
            "training_only_sample_mean",
            Dict{String, Any}(),
        ),
        density_construction =
            "independent_horizon_joint_gaussian_training_mean_residuals",
        parameter_uncertainty = false,
        cross_target_dependence = "training_residual_covariance",
        convergence_class = "closed_form_summary",
        estimation_success_gate = "finite_required_training_moments",
    ),
    (
        model_id = "naive_seasonal_4",
        family = "seasonal_naive",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "SeasonalNaiveSpec(4)",
            "iterated",
            "fixed_seasonal_period_4",
            "fixed_preregistered",
            Dict{String, Any}("period" => 4),
        ),
        density_construction =
            "recursive_joint_gaussian_training_seasonal_differences",
        parameter_uncertainty = false,
        cross_target_dependence = "training_residual_covariance",
        convergence_class = "closed_form_summary",
        estimation_success_gate = "finite_required_training_moments",
    ),
    (
        model_id = "univariate_ar_p1_constant",
        family = "ar",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "ARSpec(candidate_lags = [1], intercept = true)",
            "iterated",
            "fixed_lag_1",
            "fixed_preregistered",
            Dict{String, Any}(
                "candidate_lags" => [1],
                "intercept" => true,
            ),
        ),
        density_construction =
            "recursive_target_independent_gaussian_fitted_innovations",
        parameter_uncertainty = false,
        cross_target_dependence = "none",
        convergence_class = "least_squares_fixed_lag",
        estimation_success_gate =
            "each_target_full_rank_fit_with_residual_degrees_of_freedom",
    ),
    (
        model_id = "univariate_ar_p4_constant",
        family = "ar",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "ARSpec(candidate_lags = [4], intercept = true)",
            "iterated",
            "fixed_lag_4",
            "fixed_preregistered",
            Dict{String, Any}(
                "candidate_lags" => [4],
                "intercept" => true,
            ),
        ),
        density_construction =
            "recursive_target_independent_gaussian_fitted_innovations",
        parameter_uncertainty = false,
        cross_target_dependence = "none",
        convergence_class = "least_squares_fixed_lag",
        estimation_success_gate =
            "each_target_full_rank_fit_with_residual_degrees_of_freedom",
    ),
    (
        model_id = "univariate_ar_bic_p1-2-3-4-5-6-7-8_constant",
        family = "ar",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "ARSpec(candidate_lags = 1:8, intercept = true)",
            "iterated",
            "target_specific_bic_over_lags_1_through_8",
            "target_specific_bic_on_common_training_only_window",
            Dict{String, Any}(
                "candidate_lags" => collect(1:8),
                "intercept" => true,
            ),
        ),
        density_construction =
            "recursive_target_independent_gaussian_selected_fit_innovations",
        parameter_uncertainty = false,
        cross_target_dependence = "none",
        convergence_class = "least_squares_finite_bic_grid",
        estimation_success_gate =
            "each_target_has_finite_bic_candidate_and_full_rank_selected_fit",
    ),
    (
        model_id =
            "direct_univariate_ar_v1_fixed_p1_constant_joint_aligned_residual_gaussian_v1",
        family = "ar",
        source_artifact_ids = DIRECT_AR_SOURCES,
        model_card_artifact_id = DIRECT_AR_MODEL_CARD_ARTIFACT,
        specification = specification(
            "DirectARSpec(candidate_lags = [1], intercept = true)",
            "horizon_specific_direct_multi_step_ols",
            "fixed_lag_1_for_every_target_and_horizon",
            "fixed_preregistered_single_candidate_horizon_specific_refit",
            direct_ar_parameters([1]),
        ),
        density_construction =
            "joint_gaussian_plugin_full_aligned_horizon_by_target_residual_covariance",
        parameter_uncertainty = false,
        cross_target_dependence =
            "full_aligned_horizon_by_target_residual_covariance",
        convergence_class =
            "horizon_specific_least_squares_finite_lag_grid_and_joint_residual_covariance",
        estimation_success_gate =
            "every_target_horizon_ols_design_full_rank_with_residual_degrees_of_freedom_and_finite_fit",
        density_success_gate =
            "aligned_origins_exceed_H_times_K_centered_residual_full_column_rank_covariance_degrees_of_freedom_positive_definite_and_exact_finite_shape_or_structured_failure",
    ),
    (
        model_id =
            "direct_univariate_ar_v1_fixed_p4_constant_joint_aligned_residual_gaussian_v1",
        family = "ar",
        source_artifact_ids = DIRECT_AR_SOURCES,
        model_card_artifact_id = DIRECT_AR_MODEL_CARD_ARTIFACT,
        specification = specification(
            "DirectARSpec(candidate_lags = [4], intercept = true)",
            "horizon_specific_direct_multi_step_ols",
            "fixed_lag_4_for_every_target_and_horizon",
            "fixed_preregistered_single_candidate_horizon_specific_refit",
            direct_ar_parameters([4]),
        ),
        density_construction =
            "joint_gaussian_plugin_full_aligned_horizon_by_target_residual_covariance",
        parameter_uncertainty = false,
        cross_target_dependence =
            "full_aligned_horizon_by_target_residual_covariance",
        convergence_class =
            "horizon_specific_least_squares_finite_lag_grid_and_joint_residual_covariance",
        estimation_success_gate =
            "every_target_horizon_ols_design_full_rank_with_residual_degrees_of_freedom_and_finite_fit",
        density_success_gate =
            "aligned_origins_exceed_H_times_K_centered_residual_full_column_rank_covariance_degrees_of_freedom_positive_definite_and_exact_finite_shape_or_structured_failure",
    ),
    (
        model_id =
            "direct_univariate_ar_v1_bic_p1-2-3-4-5-6-7-8_constant_joint_aligned_residual_gaussian_v1",
        family = "ar",
        source_artifact_ids = DIRECT_AR_SOURCES,
        model_card_artifact_id = DIRECT_AR_MODEL_CARD_ARTIFACT,
        specification = specification(
            "DirectARSpec(candidate_lags = 1:8, intercept = true)",
            "horizon_specific_direct_multi_step_ols",
            "target_and_horizon_specific_bic_over_lags_1_through_8",
            "bic_on_horizon_specific_common_candidate_window_then_selected_lag_full_window_refit",
            direct_ar_parameters(1:8),
        ),
        density_construction =
            "joint_gaussian_plugin_full_aligned_horizon_by_target_residual_covariance",
        parameter_uncertainty = false,
        cross_target_dependence =
            "full_aligned_horizon_by_target_residual_covariance",
        convergence_class =
            "horizon_specific_least_squares_finite_lag_grid_and_joint_residual_covariance",
        estimation_success_gate =
            "every_target_horizon_ols_design_full_rank_with_residual_degrees_of_freedom_and_finite_fit",
        density_success_gate =
            "aligned_origins_exceed_H_times_K_centered_residual_full_column_rank_covariance_degrees_of_freedom_positive_definite_and_exact_finite_shape_or_structured_failure",
    ),
    (
        model_id = "beforeit_var_p1_constant",
        family = "var",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "BeforeITVARSpec(lags = 1, intercept = true)",
            "iterated",
            "fixed_lag_1",
            "fixed_preregistered",
            Dict{String, Any}("lags" => 1, "intercept" => true),
        ),
        density_construction =
            "recursive_joint_gaussian_fitted_innovation_covariance",
        parameter_uncertainty = false,
        cross_target_dependence = "full_fitted_innovation_covariance",
        convergence_class = "least_squares_fixed_lag",
        estimation_success_gate =
            "finite_coefficients_covariance_and_forecast",
    ),
    (
        model_id = "beforeit_var_p2_constant",
        family = "var",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "BeforeITVARSpec(lags = 2, intercept = true)",
            "iterated",
            "fixed_lag_2",
            "fixed_preregistered",
            Dict{String, Any}("lags" => 2, "intercept" => true),
        ),
        density_construction =
            "recursive_joint_gaussian_fitted_innovation_covariance",
        parameter_uncertainty = false,
        cross_target_dependence = "full_fitted_innovation_covariance",
        convergence_class = "least_squares_fixed_lag",
        estimation_success_gate =
            "finite_coefficients_covariance_and_forecast",
    ),
    (
        model_id = "beforeit_var_p3_constant",
        family = "var",
        source_artifact_ids = KERNEL_SOURCE,
        specification = specification(
            "BeforeITVARSpec(lags = 3, intercept = true)",
            "iterated",
            "fixed_lag_3",
            "fixed_preregistered",
            Dict{String, Any}("lags" => 3, "intercept" => true),
        ),
        density_construction =
            "recursive_joint_gaussian_fitted_innovation_covariance",
        parameter_uncertainty = false,
        cross_target_dependence = "full_fitted_innovation_covariance",
        convergence_class = "least_squares_fixed_lag",
        estimation_success_gate =
            "finite_coefficients_covariance_and_forecast",
    ),
    (
        model_id =
            "bvar_mniw_v1_p1_constant_tight3fc999999999999a_decay3ff0000000000000_own0000000000000000_ivar4059000000000000_iwoff2_iscale3ff0000000000000_floor3e45798ee2308c3a_diffmse_scale",
        family = "bvar",
        source_artifact_ids = BVAR_SOURCES,
        specification = specification(
            "BVARSpec(lags = 1, intercept = true, tightness = 0.2, lag_decay = 1.0, own_lag_mean = 0.0, intercept_variance = 100.0, iw_dof_offset = 2, innovation_scale = 1.0, scale_floor = 1.0e-8)",
            "iterated_posterior_mean_point_and_posterior_predictive_density",
            "fixed_lag_1",
            "none_all_constructor_fixed_and_model_id_encoded",
            Dict{String, Any}(
                "lags" => 1,
                "intercept" => true,
                "tightness" => 0.2,
                "lag_decay" => 1.0,
                "own_lag_mean" => 0.0,
                "intercept_variance" => 100.0,
                "iw_dof_offset" => 2,
                "innovation_scale" => 1.0,
                "scale_floor" => 1.0e-8,
                "prior_family" => "matrix_normal_inverse_wishart",
                "prior_version" => "mniw_minnesota_style_v1",
                "scale_rule" => "training_first_difference_mse_with_floor",
            ),
        ),
        density_construction =
            "recursive_mniw_posterior_predictive_joint_parameter_covariance_and_innovation_draws",
        parameter_uncertainty = true,
        cross_target_dependence =
            "full_posterior_innovation_covariance_and_coefficient_matrix",
        convergence_class = "closed_form_conjugate_posterior",
        estimation_success_gate =
            "proper_positive_definite_prior_and_posterior_with_finite_forecast",
    ),
    (
        model_id =
            "semi_structural_lgssm_v1_quarterly_core4_contract_v1_8dd9b5ddf4875de7cf44569dd3acaa5706bf19f8b34a1020b65afad1772b3715",
        family = "compact_semi_structural",
        source_artifact_ids = SEMI_STRUCTURAL_SOURCES,
        model_card_artifact_id = SEMI_STRUCTURAL_MODEL_CARD_ARTIFACT,
        target_panel_id = CORE4_TARGET_PANEL_ID,
        specification = specification(
            "SemiStructuralSpec()",
            "exact_kalman_filter_and_iterated_state_space_prediction",
            "fixed_quarterly_state_transition",
            "none_all_parameters_constructor_fixed_and_model_id_digest_bound",
            Dict{String, Any}(
                "target_contract_version" =>
                    "quarterly_core4_contract_v1",
                "model_class" => "semi_structural_not_dsge",
                "dsge_model" => false,
                "origin_parameter_fitting" => false,
                "full_posterior_parameter_density" => false,
                "fiscal_block" => "not_implemented",
                "foreign_block" => "not_implemented",
                "gap_annualization" => 4.0,
                "potential_growth_mean" => 2.0,
                "potential_growth_persistence" => 0.85,
                "output_gap_persistence" => 0.75,
                "is_slope" => 0.12,
                "natural_unemployment_mean" => 4.5,
                "natural_unemployment_persistence" => 0.95,
                "neutral_rate_mean" => 1.0,
                "neutral_rate_persistence" => 0.9,
                "inflation_anchor_mean" => 2.0,
                "inflation_anchor_persistence" => 0.95,
                "inflation_persistence" => 0.65,
                "phillips_slope" => 0.08,
                "okun_slope" => 0.45,
                "policy_smoothing" => 0.75,
                "taylor_inflation" => 1.5,
                "taylor_output" => 0.35,
                "state_innovation_stddev_diagonal" =>
                    [0.08, 0.35, 0.05, 0.08, 0.05, 0.2, 0.15],
                "measurement_stddev_diagonal" =>
                    [0.12, 0.08, 0.05, 0.04],
                "initial_state_stddev_diagonal" =>
                    [0.5, 1.0, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0],
            ),
        ),
        density_construction =
            "fixed_parameter_conditional_posterior_state_predictive_filtered_state_process_and_measurement_uncertainty",
        parameter_uncertainty = false,
        cross_target_dependence =
            "joint_filtered_state_and_shared_state_transition",
        convergence_class =
            "exact_linear_gaussian_kalman_filter_fixed_parameters",
        estimation_success_gate =
            "finite_exact_kalman_updates_positive_definite_innovation_covariance_and_finite_forecast",
        stability_rule =
            "constructor_requires_transition_spectral_radius_below_one",
        elb_treatment =
            "no_elb_mechanism_observed_effective_federal_funds_rate_only",
    ),
]

expected_target_panel_id(expected) =
    hasproperty(expected, :target_panel_id) ?
    expected.target_panel_id : TARGET_PANEL_ID

expected_model_card_artifact_id(expected) =
    hasproperty(expected, :model_card_artifact_id) ?
    expected.model_card_artifact_id : MODEL_CARD_ARTIFACT

expected_stability_rule(expected) =
    hasproperty(expected, :stability_rule) ?
    expected.stability_rule :
    "no_stability_filter_or_replacement_diagnostics_only_when_available"

expected_elb_treatment(expected) =
    hasproperty(expected, :elb_treatment) ?
    expected.elb_treatment :
    "observed_effective_federal_funds_rate_no_censoring_or_shadow_rate"

expected_density_success_gate(expected) =
    hasproperty(expected, :density_success_gate) ?
    expected.density_success_gate :
    "exact_shape_and_all_finite_or_structured_failure"

const ROOT_KEYS = Set(
    [
        "schema_version",
        "registry_id",
        "registry_status",
        "canonicalization",
        "digest_algorithm",
        "canonical_tracks",
        "cross_track_pooling",
        "expected_target_panel_count",
        "expected_model_count",
        "execution_scope",
        "artifacts",
        "target_panels",
        "models",
        "registry_content_sha256",
    ],
)
const ARTIFACT_KEYS =
    Set(["artifact_id", "kind", "path", "sha256"])
const EXECUTION_SCOPE_KEYS = Set(
    [
        "evidence_class",
        "empirical_forecast_execution_allowed",
        "production_scoring_allowed",
        "unsupported_model_policy",
        "hash_verification",
    ],
)
const TARGET_PANEL_KEYS = Set(
    [
        "target_panel_id",
        "frequency",
        "selection_rule",
        "transformation_rule",
        "missing_data_policy",
        "targets",
    ],
)
const TARGET_KEYS = Set(
    [
        "target_id",
        "target_version",
        "operator_version",
        "aggregation",
        "primary_transformation",
        "secondary_transformation",
        "transformation_version",
        "output_unit",
        "model_input_name",
        "model_input_unit",
    ],
)
const MODEL_KEYS = Set(
    [
        "model_id",
        "support_status",
        "family",
        "information_track",
        "products",
        "target_panel_id",
        "source_artifact_ids",
        "model_card_artifact_id",
        "specification",
        "transformations",
        "estimation_window",
        "pandemic_elb",
        "density",
        "fallback",
        "convergence",
    ],
)
const SPECIFICATION_KEYS = Set(
    [
        "constructor",
        "forecast_method",
        "lag_rule",
        "hyperparameter_rule",
        "parameters",
    ],
)
const TRANSFORMATION_KEYS = Set(
    [
        "target_panel_rule",
        "estimation_input",
        "inverse_transform",
        "future_target_policy",
    ],
)
const ESTIMATION_WINDOW_KEYS = Set(
    [
        "kind",
        "minimum_training_quarters",
        "start_rule",
        "end_rule",
        "missing_data_policy",
    ],
)
const PANDEMIC_ELB_KEYS = Set(
    [
        "pandemic_treatment",
        "pandemic_sensitivity_policy",
        "elb_treatment",
        "regime_selection",
    ],
)
const DENSITY_KEYS = Set(
    [
        "required",
        "construction",
        "draw_count_rule",
        "seed_rule",
        "parameter_uncertainty_included",
        "cross_target_dependence",
        "stochastic_volatility",
    ],
)
const FALLBACK_KEYS = Set(
    [
        "invalid_origin",
        "estimation_failure",
        "silent_substitution",
        "ranking_failure_policy",
    ],
)
const CONVERGENCE_KEYS = Set(
    [
        "algorithm_class",
        "estimation_success_gate",
        "density_success_gate",
        "stability_rule",
        "iterative_convergence",
        "failure_action",
    ],
)

struct ModelRegistryValidationError <: Exception
    message::String
end

Base.showerror(io::IO, error::ModelRegistryValidationError) =
    print(io, error.message)

fail(path, message) =
    throw(ModelRegistryValidationError("$path: $message"))

function expect_table(value, path)
    value isa AbstractDict || fail(path, "expected a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(path, "table keys must be strings")
    return value
end

function check_keys(value, expected, path)
    table = expect_table(value, path)
    actual = Set(String.(keys(table)))
    missing = sort!(collect(setdiff(expected, actual)))
    unknown = sort!(collect(setdiff(actual, expected)))
    isempty(missing) ||
        fail(path, "missing required key(s): $(join(missing, ", "))")
    isempty(unknown) ||
        fail(path, "unknown key(s): $(join(unknown, ", "))")
    return table
end

function expect_string(value, path)
    value isa AbstractString || fail(path, "expected a string")
    text = String(value)
    isempty(text) && fail(path, "must not be empty")
    strip(text) == text ||
        fail(path, "must not have surrounding whitespace")
    return text
end

function expect_bool(value, path)
    value isa Bool || fail(path, "expected a Boolean")
    return value
end

function expect_integer(value, path; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(path, "expected an integer")
    value >= minimum || fail(path, "must be at least $minimum")
    return Int(value)
end

function expect_hash(value, path)
    digest = expect_string(value, path)
    occursin(HASH_PATTERN, digest) ||
        fail(path, "expected 64 lowercase hexadecimal SHA-256 characters")
    digest != ZERO_HASH || fail(path, "zero hashes are not evidence")
    return digest
end

function expect_string_vector(
        value,
        path;
        allow_empty = false,
    )
    value isa AbstractVector ||
        fail(path, "expected an array of strings")
    result = String[]
    for (index, entry) in enumerate(value)
        push!(result, expect_string(entry, "$path[$index]"))
    end
    allow_empty || !isempty(result) ||
        fail(path, "must not be empty")
    length(unique(result)) == length(result) ||
        fail(path, "must not contain duplicates")
    return result
end

function expect_exact(value, expected, path)
    value == expected ||
        fail(path, "expected $(repr(expected)), got $(repr(value))")
    return value
end

function canonical(value)
    if value isa Bool
        return value ? "bool:true" : "bool:false"
    elseif value isa Integer
        return "integer:" * string(value)
    elseif value isa AbstractFloat
        isfinite(value) || fail("canonical", "non-finite number")
        return "float64:" * bitstring(Float64(value))
    elseif value isa AbstractString
        text = String(value)
        return "string:$(ncodeunits(text)):$text"
    elseif value isa AbstractVector
        encoded = canonical.(value)
        return "array:$(length(encoded)):" *
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
    return fail("canonical", "unsupported type $(typeof(value))")
end

sha256_hex(value::AbstractString) = bytes2hex(SHA.sha256(value))

function without_key(value, excluded_key)
    return Dict{String, Any}(
        String(key) => item for
            (key, item) in pairs(value) if String(key) != excluded_key
    )
end

registry_content_sha256(registry) =
    sha256_hex(canonical(without_key(registry, "registry_content_sha256")))

function validate_execution_scope(scope)
    path = "registry.execution_scope"
    check_keys(scope, EXECUTION_SCOPE_KEYS, path)
    expect_exact(
        scope["evidence_class"],
        "hermetic_validation_only_no_empirical_forecasts",
        "$path.evidence_class",
    )
    expect_bool(
        scope["empirical_forecast_execution_allowed"],
        "$path.empirical_forecast_execution_allowed",
    ) === false ||
        fail(
        "$path.empirical_forecast_execution_allowed",
        "must remain false",
    )
    expect_bool(
        scope["production_scoring_allowed"],
        "$path.production_scoring_allowed",
    ) === false ||
        fail("$path.production_scoring_allowed", "must remain false")
    expect_exact(
        scope["unsupported_model_policy"],
        "reject",
        "$path.unsupported_model_policy",
    )
    expect_exact(
        scope["hash_verification"],
        "required_before_model_execution",
        "$path.hash_verification",
    )
    return scope
end

function validate_target_panel(panel, expected, panel_index)
    path = "registry.target_panels[$panel_index]"
    check_keys(panel, TARGET_PANEL_KEYS, path)
    expect_exact(
        panel["target_panel_id"],
        expected.target_panel_id,
        "$path.target_panel_id",
    )
    expect_exact(panel["frequency"], "quarterly", "$path.frequency")
    expect_exact(
        panel["selection_rule"],
        expected.selection_rule,
        "$path.selection_rule",
    )
    expect_exact(
        panel["transformation_rule"],
        expected.transformation_rule,
        "$path.transformation_rule",
    )
    expect_exact(
        panel["missing_data_policy"],
        expected.missing_data_policy,
        "$path.missing_data_policy",
    )

    targets = panel["targets"]
    targets isa AbstractVector ||
        fail("$path.targets", "expected an array of target tables")
    length(targets) == length(expected.targets) ||
        fail(
        "$path.targets",
        "expected exactly $(length(expected.targets)) targets",
    )
    target_ids = String[]
    for (index, (target, expected_target)) in
        enumerate(zip(targets, expected.targets))
        target_path = "$path.targets[$index]"
        check_keys(target, TARGET_KEYS, target_path)
        target_id = expect_string(target["target_id"], "$target_path.target_id")
        push!(target_ids, target_id)
        for field in keys(expected_target)
            key = String(field)
            expect_exact(
                target[key],
                getproperty(expected_target, field),
                "$target_path.$key",
            )
        end
    end
    length(unique(target_ids)) == length(target_ids) ||
        fail("$path.targets", "target IDs must be unique")
    return panel
end

function validate_specification(specification_table, expected, path)
    check_keys(specification_table, SPECIFICATION_KEYS, path)
    for key in (
            "constructor",
            "forecast_method",
            "lag_rule",
            "hyperparameter_rule",
        )
        expect_exact(
            specification_table[key],
            expected.specification[key],
            "$path.$key",
        )
    end
    parameters =
        expect_table(specification_table["parameters"], "$path.parameters")
    expected_parameters = expected.specification["parameters"]
    check_keys(
        parameters,
        Set(String.(keys(expected_parameters))),
        "$path.parameters",
    )
    for key in keys(expected_parameters)
        expect_exact(
            parameters[key],
            expected_parameters[key],
            "$path.parameters.$key",
        )
    end
    return specification_table
end

function validate_transformations(transformations, path)
    check_keys(transformations, TRANSFORMATION_KEYS, path)
    expected = Dict(
        "target_panel_rule" => "use_registered_panel_in_declared_order",
        "estimation_input" => "registered_primary_transformation",
        "inverse_transform" => "not_applied_by_benchmark_kernel",
        "future_target_policy" => "interface_has_no_future_target_field",
    )
    for key in keys(expected)
        expect_exact(transformations[key], expected[key], "$path.$key")
    end
    return transformations
end

function validate_estimation_window(window, path)
    check_keys(window, ESTIMATION_WINDOW_KEYS, path)
    expect_exact(window["kind"], "expanding", "$path.kind")
    expect_exact(
        expect_integer(
            window["minimum_training_quarters"],
            "$path.minimum_training_quarters";
            minimum = 1,
        ),
        40,
        "$path.minimum_training_quarters",
    )
    expect_exact(
        window["start_rule"],
        "first_contiguous_complete_case_quarter_available_at_origin",
        "$path.start_rule",
    )
    expect_exact(
        window["end_rule"],
        "latest_eligible_complete_target_quarter_at_or_before_origin",
        "$path.end_rule",
    )
    expect_exact(
        window["missing_data_policy"],
        "fail_origin_no_imputation",
        "$path.missing_data_policy",
    )
    return window
end

function validate_pandemic_elb(policy, expected, path)
    check_keys(policy, PANDEMIC_ELB_KEYS, path)
    expect_exact(
        policy["pandemic_treatment"],
        "include_all_eligible_observations_no_dummy_no_downweighting",
        "$path.pandemic_treatment",
    )
    expect_exact(
        policy["pandemic_sensitivity_policy"],
        "separately_versioned_prespecified_slices_never_selected_on_rankings",
        "$path.pandemic_sensitivity_policy",
    )
    expect_exact(
        policy["elb_treatment"],
        expected_elb_treatment(expected),
        "$path.elb_treatment",
    )
    expect_exact(
        policy["regime_selection"],
        "none",
        "$path.regime_selection",
    )
    return policy
end

function validate_density(density, expected, path)
    check_keys(density, DENSITY_KEYS, path)
    expect_bool(density["required"], "$path.required") ||
        fail("$path.required", "common-information density must be required")
    expect_exact(
        density["construction"],
        expected.density_construction,
        "$path.construction",
    )
    expect_exact(
        density["draw_count_rule"],
        "positive_preregistered_count_required_for_density_scoring",
        "$path.draw_count_rule",
    )
    expect_exact(
        density["seed_rule"],
        "explicit_nonnegative_integer_derived_by_origin_model_path",
        "$path.seed_rule",
    )
    expect_exact(
        expect_bool(
            density["parameter_uncertainty_included"],
            "$path.parameter_uncertainty_included",
        ),
        expected.parameter_uncertainty,
        "$path.parameter_uncertainty_included",
    )
    expect_exact(
        density["cross_target_dependence"],
        expected.cross_target_dependence,
        "$path.cross_target_dependence",
    )
    expect_bool(
        density["stochastic_volatility"],
        "$path.stochastic_volatility",
    ) === false ||
        fail("$path.stochastic_volatility", "unsupported by these models")
    return density
end

function validate_fallback(fallback, path)
    check_keys(fallback, FALLBACK_KEYS, path)
    expected = Dict(
        "invalid_origin" => "reject_before_estimation",
        "estimation_failure" => "structured_failure_record",
        "silent_substitution" => "prohibited",
        "ranking_failure_policy" =>
            "not_ranked_if_any_required_model_origin_failure",
    )
    for key in keys(expected)
        expect_exact(fallback[key], expected[key], "$path.$key")
    end
    return fallback
end

function validate_convergence(convergence, expected, path)
    check_keys(convergence, CONVERGENCE_KEYS, path)
    expect_exact(
        convergence["algorithm_class"],
        expected.convergence_class,
        "$path.algorithm_class",
    )
    expect_exact(
        convergence["estimation_success_gate"],
        expected.estimation_success_gate,
        "$path.estimation_success_gate",
    )
    expect_exact(
        convergence["density_success_gate"],
        expected_density_success_gate(expected),
        "$path.density_success_gate",
    )
    expect_exact(
        convergence["stability_rule"],
        expected_stability_rule(expected),
        "$path.stability_rule",
    )
    expect_exact(
        convergence["iterative_convergence"],
        "not_applicable_no_iterative_optimizer_or_mcmc",
        "$path.iterative_convergence",
    )
    expect_exact(
        convergence["failure_action"],
        "retain_structured_failure_never_impute_or_omit",
        "$path.failure_action",
    )
    return convergence
end

function safe_artifact_path(base_dir, relative_path, path)
    relative = expect_string(relative_path, path)
    isabspath(relative) &&
        fail(path, "artifact paths must be relative to the registry")
    splitpath(normpath(relative)) == [relative] ||
        fail(path, "artifact paths must be plain local filenames")
    resolved_base = try
        realpath(base_dir)
    catch error
        fail(path, "registry directory cannot be resolved: $(sprint(showerror, error))")
    end
    isdir(resolved_base) ||
        fail(path, "registry directory is not a directory: $resolved_base")
    artifact_path = joinpath(base_dir, relative)
    islink(artifact_path) &&
        fail(path, "artifact must not be a symbolic link: $artifact_path")
    isfile(artifact_path) ||
        fail(path, "artifact must be an existing regular file: $artifact_path")
    resolved_artifact = try
        realpath(artifact_path)
    catch error
        fail(path, "artifact cannot be resolved: $(sprint(showerror, error))")
    end
    dirname(resolved_artifact) == resolved_base ||
        fail(
        path,
        "resolved artifact must remain directly inside the registry directory",
    )
    return artifact_path
end

function verify_artifact(base_dir, relative_path, digest, path)
    artifact_path =
        safe_artifact_path(base_dir, relative_path, "$path.path")
    actual = bytes2hex(SHA.sha256(read(artifact_path)))
    actual == digest ||
        fail(
        path,
        "artifact hash mismatch for $relative_path; expected $digest, got $actual",
    )
    return artifact_path
end

function validate_artifacts(
        artifacts;
        base_dir,
        verify_artifacts,
    )
    path = "registry.artifacts"
    artifacts isa AbstractVector ||
        fail(path, "expected an array of artifact tables")
    length(artifacts) == length(EXPECTED_ARTIFACTS) ||
        fail(
        path,
        "expected exactly $(length(EXPECTED_ARTIFACTS)) artifacts",
    )
    artifact_ids = String[]
    lookup = Dict{String, Any}()
    for (index, (artifact, expected)) in
        enumerate(zip(artifacts, EXPECTED_ARTIFACTS))
        artifact_path = "$path[$index]"
        check_keys(artifact, ARTIFACT_KEYS, artifact_path)
        artifact_id =
            expect_string(artifact["artifact_id"], "$artifact_path.artifact_id")
        push!(artifact_ids, artifact_id)
        expect_exact(
            artifact_id,
            expected.artifact_id,
            "$artifact_path.artifact_id",
        )
        expect_exact(
            artifact["kind"],
            expected.kind,
            "$artifact_path.kind",
        )
        expect_exact(
            artifact["path"],
            expected.path,
            "$artifact_path.path",
        )
        digest = expect_hash(
            artifact["sha256"],
            "$artifact_path.sha256",
        )
        verify_artifacts &&
            verify_artifact(
            base_dir,
            artifact["path"],
            digest,
            artifact_path,
        )
        lookup[artifact_id] = artifact
    end
    length(unique(artifact_ids)) == length(artifact_ids) ||
        fail(path, "artifact IDs must be unique")
    return lookup
end

function validate_model(
        model,
        expected,
        index;
        artifact_lookup,
    )
    path = "registry.models[$index]"
    check_keys(model, MODEL_KEYS, path)
    expect_exact(model["model_id"], expected.model_id, "$path.model_id")
    expect_exact(
        model["support_status"],
        "supported",
        "$path.support_status",
    )
    expect_exact(model["family"], expected.family, "$path.family")

    track = expect_string(model["information_track"], "$path.information_track")
    track in CANONICAL_TRACKS ||
        fail(
        "$path.information_track",
        "unsupported track '$track'; use canonical protocol vocabulary",
    )
    expected.family in TRACK_FAMILIES[track] ||
        fail(
        "$path.family",
        "family '$(expected.family)' is incompatible with track '$track'",
    )
    expect_exact(
        track,
        COMMON_MODEL_METADATA.information_track,
        "$path.information_track",
    )

    products = expect_string_vector(model["products"], "$path.products")
    expect_exact(
        products,
        COMMON_MODEL_METADATA.products,
        "$path.products",
    )
    for (product_index, product) in enumerate(products)
        haskey(PRODUCT_TRACKS, product) ||
            fail("$path.products[$product_index]", "unsupported product")
        track in PRODUCT_TRACKS[product] ||
            fail(
            "$path.products[$product_index]",
            "product '$product' does not permit track '$track'",
        )
    end
    expect_exact(
        model["target_panel_id"],
        expected_target_panel_id(expected),
        "$path.target_panel_id",
    )

    source_artifact_ids = expect_string_vector(
        model["source_artifact_ids"],
        "$path.source_artifact_ids",
    )
    expect_exact(
        source_artifact_ids,
        expected.source_artifact_ids,
        "$path.source_artifact_ids",
    )
    for (source_index, artifact_id) in enumerate(source_artifact_ids)
        haskey(artifact_lookup, artifact_id) ||
            fail(
            "$path.source_artifact_ids[$source_index]",
            "unknown artifact '$artifact_id'",
        )
        artifact_lookup[artifact_id]["kind"] == "source" ||
            fail(
            "$path.source_artifact_ids[$source_index]",
            "artifact '$artifact_id' is not source code",
        )
    end

    card_artifact_id = expect_string(
        model["model_card_artifact_id"],
        "$path.model_card_artifact_id",
    )
    expect_exact(
        card_artifact_id,
        expected_model_card_artifact_id(expected),
        "$path.model_card_artifact_id",
    )
    haskey(artifact_lookup, card_artifact_id) ||
        fail(
        "$path.model_card_artifact_id",
        "unknown artifact '$card_artifact_id'",
    )
    artifact_lookup[card_artifact_id]["kind"] == "model_card" ||
        fail(
        "$path.model_card_artifact_id",
        "artifact '$card_artifact_id' is not a model card",
    )

    validate_specification(
        model["specification"],
        expected,
        "$path.specification",
    )
    validate_transformations(
        model["transformations"],
        "$path.transformations",
    )
    validate_estimation_window(
        model["estimation_window"],
        "$path.estimation_window",
    )
    validate_pandemic_elb(
        model["pandemic_elb"],
        expected,
        "$path.pandemic_elb",
    )
    validate_density(model["density"], expected, "$path.density")
    validate_fallback(model["fallback"], "$path.fallback")
    validate_convergence(
        model["convergence"],
        expected,
        "$path.convergence",
    )

    return model
end

"""
    validate_model_registry(registry; base_dir = @__DIR__,
        verify_artifacts = true)

Validate a parsed benchmark registry. Validation is fail-closed: every table
has an exact key set, the model inventory is a complete ordered whitelist, and
all source/model-card hashes are verified by default.
"""
function validate_model_registry(
        registry;
        base_dir = @__DIR__,
        verify_artifacts = true,
    )
    path = "registry"
    check_keys(registry, ROOT_KEYS, path)
    expect_exact(
        registry["schema_version"],
        SCHEMA_VERSION,
        "$path.schema_version",
    )
    expect_exact(registry["registry_id"], REGISTRY_ID, "$path.registry_id")
    expect_exact(
        registry["registry_status"],
        REGISTRY_STATUS,
        "$path.registry_status",
    )
    expect_exact(
        registry["canonicalization"],
        CANONICALIZATION,
        "$path.canonicalization",
    )
    expect_exact(
        registry["digest_algorithm"],
        "sha256",
        "$path.digest_algorithm",
    )
    tracks =
        expect_string_vector(registry["canonical_tracks"], "$path.canonical_tracks")
    expect_exact(tracks, CANONICAL_TRACKS, "$path.canonical_tracks")
    expect_bool(
        registry["cross_track_pooling"],
        "$path.cross_track_pooling",
    ) === false ||
        fail("$path.cross_track_pooling", "must remain false")
    expect_exact(
        expect_integer(
            registry["expected_target_panel_count"],
            "$path.expected_target_panel_count";
            minimum = 1,
        ),
        length(EXPECTED_TARGET_PANELS),
        "$path.expected_target_panel_count",
    )
    expect_exact(
        expect_integer(
            registry["expected_model_count"],
            "$path.expected_model_count";
            minimum = 1,
        ),
        length(EXPECTED_MODELS),
        "$path.expected_model_count",
    )
    validate_execution_scope(registry["execution_scope"])
    artifact_lookup = validate_artifacts(
        registry["artifacts"];
        base_dir = String(base_dir),
        verify_artifacts = verify_artifacts,
    )

    panels = registry["target_panels"]
    panels isa AbstractVector ||
        fail("$path.target_panels", "expected an array of target-panel tables")
    length(panels) == length(EXPECTED_TARGET_PANELS) ||
        fail(
        "$path.target_panels",
        "expected exactly $(length(EXPECTED_TARGET_PANELS)) target panels",
    )
    panel_ids = String[]
    for (panel_index, (panel, expected_panel)) in
        enumerate(zip(panels, EXPECTED_TARGET_PANELS))
        panel_table =
            expect_table(panel, "$path.target_panels[$panel_index]")
        haskey(panel_table, "target_panel_id") ||
            fail(
            "$path.target_panels[$panel_index]",
            "missing required key(s): target_panel_id",
        )
        push!(
            panel_ids,
            expect_string(
                panel_table["target_panel_id"],
                "$path.target_panels[$panel_index].target_panel_id",
            ),
        )
        validate_target_panel(panel_table, expected_panel, panel_index)
    end
    length(unique(panel_ids)) == length(panel_ids) ||
        fail("$path.target_panels", "target-panel IDs must be unique")

    models = registry["models"]
    models isa AbstractVector ||
        fail("$path.models", "expected an array of model tables")
    length(models) == length(EXPECTED_MODELS) ||
        fail(
        "$path.models",
        "expected exactly $(length(EXPECTED_MODELS)) supported models",
    )
    model_ids = String[]
    for (index, model) in enumerate(models)
        model_table = expect_table(model, "$path.models[$index]")
        haskey(model_table, "model_id") ||
            fail("$path.models[$index]", "missing required key(s): model_id")
        push!(
            model_ids,
            expect_string(model_table["model_id"], "$path.models[$index].model_id"),
        )
    end
    length(unique(model_ids)) == length(model_ids) ||
        fail("$path.models", "model IDs must be unique")
    expected_ids = [entry.model_id for entry in EXPECTED_MODELS]
    unsupported = setdiff(Set(model_ids), Set(expected_ids))
    isempty(unsupported) ||
        fail(
        "$path.models",
        "unsupported model ID(s): $(join(sort!(collect(unsupported)), ", "))",
    )
    expect_exact(model_ids, expected_ids, "$path.models model-id order")

    for (index, (model, expected)) in
        enumerate(zip(models, EXPECTED_MODELS))
        validate_model(
            model,
            expected,
            index;
            artifact_lookup = artifact_lookup,
        )
    end

    declared_registry_hash = expect_hash(
        registry["registry_content_sha256"],
        "$path.registry_content_sha256",
    )
    computed_registry_hash = registry_content_sha256(registry)
    declared_registry_hash == computed_registry_hash ||
        fail(
        "$path.registry_content_sha256",
        "registry content hash mismatch; expected $computed_registry_hash",
    )
    return registry
end

"""
    load_model_registry(path = DEFAULT_REGISTRY_PATH; verify_artifacts = true)

Parse and validate a registry, resolving source and model-card paths relative
to the registry file.
"""
function load_model_registry(
        path = DEFAULT_REGISTRY_PATH;
        verify_artifacts = true,
    )
    registry_path = abspath(String(path))
    isfile(registry_path) ||
        fail("registry", "registry file is missing: $registry_path")
    registry = try
        TOML.parsefile(registry_path)
    catch error
        error isa ModelRegistryValidationError && rethrow()
        fail("registry", "invalid TOML: $(sprint(showerror, error))")
    end
    return validate_model_registry(
        registry;
        base_dir = dirname(registry_path),
        verify_artifacts = verify_artifacts,
    )
end

"""
    model_entry(registry, model_id)

Return the unique registered model record. Unknown or duplicate IDs fail.
"""
function model_entry(registry, requested_model_id)
    model_id_text = expect_string(requested_model_id, "model_id")
    matches = [
        model for model in registry["models"] if
            get(model, "model_id", nothing) == model_id_text
    ]
    isempty(matches) &&
        fail("model_id", "unsupported or unregistered model '$model_id_text'")
    length(matches) == 1 ||
        fail("model_id", "duplicate registered model '$model_id_text'")
    return only(matches)
end

"""
    model_manifest_sha256(registry, model_id)

Return the canonical manifest hash for one validated model record together
with the exact source and model-card artifact records it references. This
derived seal changes whenever code, the shared model card, or policy changes.
"""
function model_manifest_sha256(registry, requested_model_id)
    model = model_entry(registry, requested_model_id)
    artifacts = Dict(
        artifact["artifact_id"] => artifact for
            artifact in registry["artifacts"]
    )
    source_artifacts = [
        begin
                haskey(artifacts, artifact_id) ||
                fail(
                    "model.source_artifact_ids",
                    "unknown artifact '$artifact_id'",
                )
                artifacts[artifact_id]
            end for artifact_id in model["source_artifact_ids"]
    ]
    card_artifact_id = model["model_card_artifact_id"]
    haskey(artifacts, card_artifact_id) ||
        fail(
        "model.model_card_artifact_id",
        "unknown artifact '$card_artifact_id'",
    )
    model_card_artifact = artifacts[card_artifact_id]
    payload = Dict{String, Any}(
        "model" => model,
        "source_artifacts" => source_artifacts,
        "model_card_artifact" => model_card_artifact,
    )
    return sha256_hex(canonical(payload))
end

end
