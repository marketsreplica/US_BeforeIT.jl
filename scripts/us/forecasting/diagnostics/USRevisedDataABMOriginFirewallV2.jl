module USRevisedDataABMOriginFirewallV2

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

export ABMOriginFirewallV2Error,
    BasePathSeedRecord,
    QualifiedBaseOriginInputs,
    derive_base_path_seed_plan,
    path_seed_plan_sha256,
    protocol_sha256,
    qualify_base_origin_inputs,
    reassemble_model_inputs,
    refuse_prohibited_action,
    validate_protocol,
    validate_qualified_inputs,
    validate_source_pins

const SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-origin-firewall.v2"
const CONTRACT_ID =
    "beforeit-us-revised-data-abm-origin-firewall-base-qualification.v2"
const QUALIFIED_SCHEMA_VERSION =
    "beforeit-us-revised-data-abm-origin-qualified-input.v2"
const INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const DIAGNOSTIC_CLASS = "origin_input_firewall_only"
const ORIGIN_PERIOD = "2026Q1"
const MODEL_VARIANT = "base"
const MODEL_CONSTRUCTOR_ID = "BeforeIT.Model"
const PATH_COUNT = 32
const INTEGER_WORD_SIZE_BITS = 64
const RAW_PARAMETER_COUNT = 66
const EXCLUDED_PARAMETER_COUNT = 6
const MODEL_PARAMETER_COUNT = 60
const RAW_INITIAL_CONDITION_COUNT = 34
const STATIC_STATE_COUNT = 17
const DYNAMIC_HISTORY_COUNT = 5
const EXCLUDED_INITIAL_CONDITION_COUNT = 12
const CONSTRUCTION_PURPOSE = "abm_engineering_model_construction"
const SIMULATION_PURPOSE = "abm_engineering_simulation"
const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const PROTOCOL_PATH = joinpath(
    @__DIR__,
    "revised_data",
    "abm_origin_firewall_v2.toml",
)
const PROTOCOL_SHA256 =
    "efcdce3fb08e0b7496f9293c299787994eda85f2d7f750603a7f5a8b0856cab4"

const RAW_PARAMETER_KEYS = (
    "C",
    "G",
    "H_act",
    "H_inact",
    "I_s",
    "J",
    "L",
    "S",
    "T",
    "T_max",
    "T_prime",
    "a_sg",
    "alpha_E",
    "alpha_G",
    "alpha_I",
    "alpha_Y_EA",
    "alpha_pi_EA",
    "alpha_s",
    "b_CFH_g",
    "b_CF_g",
    "b_HH_g",
    "beta_E",
    "beta_G",
    "beta_I",
    "beta_Y_EA",
    "beta_pi_EA",
    "beta_s",
    "c_E_g",
    "c_G_g",
    "c_I_g",
    "delta_s",
    "kappa_s",
    "mu",
    "pi_star",
    "psi",
    "psi_H",
    "r_G",
    "r_star",
    "rho",
    "sigma_E",
    "sigma_G",
    "sigma_I",
    "sigma_Y_EA",
    "sigma_pi_EA",
    "tau_CF",
    "tau_EXPORT",
    "tau_FIRM",
    "tau_G",
    "tau_INC",
    "tau_K_s",
    "tau_SIF",
    "tau_SIW",
    "tau_VAT",
    "tau_Y_s",
    "theta",
    "theta_DIV",
    "theta_UB",
    "use_commodity_balance_inventory",
    "use_growth_rate_ar1",
    "use_product_tax_netting",
    "w_s",
    "xi_gamma",
    "xi_pi",
    "zeta",
    "zeta_LTV",
    "zeta_b",
)
const EXCLUDED_PARAMETER_KEYS = (
    "S",
    "T",
    "T_max",
    "use_commodity_balance_inventory",
    "use_growth_rate_ar1",
    "use_product_tax_netting",
)
const MODEL_PARAMETER_KEYS = (
    "C",
    "G",
    "H_act",
    "H_inact",
    "I_s",
    "J",
    "L",
    "T_prime",
    "a_sg",
    "alpha_E",
    "alpha_G",
    "alpha_I",
    "alpha_Y_EA",
    "alpha_pi_EA",
    "alpha_s",
    "b_CFH_g",
    "b_CF_g",
    "b_HH_g",
    "beta_E",
    "beta_G",
    "beta_I",
    "beta_Y_EA",
    "beta_pi_EA",
    "beta_s",
    "c_E_g",
    "c_G_g",
    "c_I_g",
    "delta_s",
    "kappa_s",
    "mu",
    "pi_star",
    "psi",
    "psi_H",
    "r_G",
    "r_star",
    "rho",
    "sigma_E",
    "sigma_G",
    "sigma_I",
    "sigma_Y_EA",
    "sigma_pi_EA",
    "tau_CF",
    "tau_EXPORT",
    "tau_FIRM",
    "tau_G",
    "tau_INC",
    "tau_K_s",
    "tau_SIF",
    "tau_SIW",
    "tau_VAT",
    "tau_Y_s",
    "theta",
    "theta_DIV",
    "theta_UB",
    "w_s",
    "xi_gamma",
    "xi_pi",
    "zeta",
    "zeta_LTV",
    "zeta_b",
)
const PARAMETER_VECTOR_KEYS = (
    "I_s",
    "alpha_s",
    "b_CFH_g",
    "b_CF_g",
    "b_HH_g",
    "c_E_g",
    "c_G_g",
    "c_I_g",
    "delta_s",
    "kappa_s",
    "tau_K_s",
    "tau_Y_s",
    "w_s",
)
const INTEGER_LIKE_PARAMETER_KEYS =
    ("H_act", "H_inact", "J", "L")

const RAW_INITIAL_CONDITION_KEYS = (
    "C_E",
    "C_G",
    "D_H",
    "D_I",
    "D_RoW",
    "E_CB",
    "E_k",
    "K_H",
    "L_G",
    "L_I",
    "N_s",
    "S_s",
    "Y",
    "Y_EA",
    "Y_EA_series",
    "Y_I",
    "basic_price_fixed_capital_control",
    "basic_price_government_control",
    "basic_price_household_control",
    "basic_price_intermediate_controls_s",
    "commodity_balance_modeled_uses_s",
    "commodity_balance_residual_s",
    "commodity_balance_supply_s",
    "inventory_statistical_discrepancy_s",
    "observed_intermediate_product_taxes_s",
    "omega",
    "pi",
    "pi_EA",
    "pi_EA_series",
    "r_bar",
    "r_bar_series",
    "sb_inact",
    "sb_other",
    "w_UB",
)
const STATIC_STATE_KEYS = (
    "D_H",
    "D_I",
    "D_RoW",
    "E_CB",
    "E_k",
    "K_H",
    "L_G",
    "L_I",
    "N_s",
    "S_s",
    "Y_EA",
    "omega",
    "pi_EA",
    "r_bar",
    "sb_inact",
    "sb_other",
    "w_UB",
)
const DYNAMIC_HISTORY_KEYS = ("C_E", "C_G", "Y", "Y_I", "pi")
const COLUMN_HISTORY_KEYS = ("C_E", "C_G", "Y_I")
const POSITIVE_HISTORY_KEYS = ("C_E", "C_G", "Y", "Y_I")
const EXCLUDED_INITIAL_CONDITION_KEYS = (
    "Y_EA_series",
    "basic_price_fixed_capital_control",
    "basic_price_government_control",
    "basic_price_household_control",
    "basic_price_intermediate_controls_s",
    "commodity_balance_modeled_uses_s",
    "commodity_balance_residual_s",
    "commodity_balance_supply_s",
    "inventory_statistical_discrepancy_s",
    "observed_intermediate_product_taxes_s",
    "pi_EA_series",
    "r_bar_series",
)
const EXCLUDED_DIAGNOSTIC_VECTOR_KEYS = (
    "basic_price_intermediate_controls_s",
    "commodity_balance_modeled_uses_s",
    "commodity_balance_residual_s",
    "commodity_balance_supply_s",
    "inventory_statistical_discrepancy_s",
    "observed_intermediate_product_taxes_s",
)
const EXCLUDED_DIAGNOSTIC_SCALAR_KEYS = (
    "basic_price_fixed_capital_control",
    "basic_price_government_control",
    "basic_price_household_control",
)
const EXCLUDED_BASE_HISTORY_KEYS =
    ("Y_EA_series", "pi_EA_series", "r_bar_series")

const DECLARATIONS = Dict{String, Any}(
    "source_schema_validated" => true,
    "runtime_projection_schema_validated" => true,
    "constructor_integer_conversion_validated" => true,
    "constructor_domain_admissibility_validated" => false,
    "qualified_input_integrity_binding_only" => true,
    "qualified_input_authentication_proof" => false,
    "downstream_raw_requalification_or_authenticated_receipt_required" =>
        true,
    "origin_admissible" => false,
    "promotion_eligible" => false,
    "confirmatory" => false,
    "truth_blind" => false,
    "class_h_allowed" => false,
    "input_lineage_verified" => false,
    "source_period_labels_authenticated" => false,
    "repository_preference_files_required_absent" => true,
    "runtime_numeric_preferences_validated" => false,
    "runtime_julia_version_validated" => false,
    "external_dependency_source_artifact_closure_validated" => false,
    "production_registry_allowed" => false,
    "scoring_allowed" => false,
    "inference_allowed" => false,
    "truth_values_emitted" => false,
    "forecast_values_emitted" => false,
    "distribution_artifacts_emitted" => false,
)
const PROJECTION = Dict{String, Any}(
    "raw_source_keys_validated_before_projection" => true,
    "excluded_values_in_qualified_hash" => false,
    "excluded_values_in_seed_namespace" => false,
    "post_origin_dynamic_values_in_qualified_hash" => false,
    "retain_rule" => "quarter_le_origin_inclusive",
    "time_dimension" => 1,
    "array_indexing_rule" =>
        "one_based_axes_required_before_projection",
    "common_retained_axis_required" => true,
    "t_prime_rule" =>
        "integer_nonboolean_equal_common_retained_history_length",
    "run_length_source" =>
        "maximum_frozen_protocol_horizon_not_source_T",
    "external_run_horizon" => 4,
    "source_T_disposition" => "validate_then_strip",
    "source_T_max_disposition" => "validate_then_strip",
    "source_S_disposition" => "validate_equal_G_then_strip",
    "source_use_growth_rate_ar1_rule" =>
        "must_be_false_then_strip",
    "constructor_integer_fields" =>
        ["H_act", "H_inact", "I_s", "J", "L", "N_s"],
    "constructor_integer_rule" =>
        "finite_nonboolean_exact_Int_value_preserved_by_Float64_projection",
    "constructor_runtime_type_check" =>
        "v3_must_require_BeforeIT.typeFloat_Float64_and_typeInt_Int64",
    "constructor_runtime_julia_version_check" =>
        "v3_must_require_VERSION_1.10.3",
    "constructor_external_dependency_check" =>
        "v3_must_bind_installed_dependency_trees_artifacts_and_runtime",
    "raw_source_parameter_count" => RAW_PARAMETER_COUNT,
    "excluded_parameter_count" => EXCLUDED_PARAMETER_COUNT,
    "model_parameter_projection_count" => MODEL_PARAMETER_COUNT,
    "raw_source_initial_condition_count" =>
        RAW_INITIAL_CONDITION_COUNT,
    "static_state_projection_count" => STATIC_STATE_COUNT,
    "dynamic_history_projection_count" => DYNAMIC_HISTORY_COUNT,
    "excluded_initial_condition_count" =>
        EXCLUDED_INITIAL_CONDITION_COUNT,
)
const EXECUTION = Dict{String, Any}(
    "construction_path_purpose" => CONSTRUCTION_PURPOSE,
    "simulation_path_purpose" => SIMULATION_PURPOSE,
    "path_ids" => "one_based_contiguous",
    "integer_word_size_bits" => INTEGER_WORD_SIZE_BITS,
    "seed_modulus_rule" => "UInt64_digest_prefix_mod_typemax_Int",
    "process_global_rng_assumed" => true,
    "serial_only" => true,
)
const FUTURE_VARIANTS = [
    Dict{String, Any}(
        "model_variant" => "growth_rate_ar1",
        "model_constructor_id" => "BeforeIT.ModelGR",
        "status" => "NOT_ALLOWED_BY_V2",
        "required_dynamic_history_keys" =>
            ["C_E", "C_G", "Y", "Y_I", "pi"],
    ),
    Dict{String, Any}(
        "model_variant" => "canvas",
        "model_constructor_id" => "BeforeIT.ModelCANVAS",
        "status" => "NOT_ALLOWED_BY_V2",
        "required_dynamic_history_keys" => [
            "C_E",
            "C_G",
            "Y",
            "Y_EA_series",
            "Y_I",
            "pi",
            "pi_EA_series",
            "r_bar_series",
        ],
    ),
]
const SOURCE_FILES = [
    Dict{String, Any}(
        "path" =>
            "scripts/us/forecasting/diagnostics/USRevisedDataABMEngineeringDiagnostic.jl",
        "sha256" =>
            "052343cefac1e286a3a93f8de2d60b2d232316a9b0c2a847cf68225bce224147",
        "role" => "v1_no_output_engineering_primitives",
    ),
    Dict{String, Any}(
        "path" =>
            "scripts/us/forecasting/diagnostics/revised_data/abm_engineering_protocol.toml",
        "sha256" =>
            "34461f24ff09e1aa1eed7bf9bad5d8b415eab011bd82b8f7e7a114d0e2246743",
        "role" => "v1_no_output_engineering_boundary",
    ),
    Dict{String, Any}(
        "path" =>
            "scripts/us/forecasting/registry/USForecastRegistry.jl",
        "sha256" =>
            "f1729f0d7bb06fd9cd11eaaad9d53c699896783f7634ffa4566674d13a463486",
        "role" => "domain_separated_seed_derivation",
    ),
    Dict{String, Any}(
        "path" => "Project.toml",
        "sha256" =>
            "b68e5fcdd48d08abc2508a07e3b28bac382e8d53782d5868929638e9c4b76903",
        "role" => "beforeit_package_definition",
    ),
    Dict{String, Any}(
        "path" => "scripts/us/Project.toml",
        "sha256" =>
            "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c",
        "role" => "us_diagnostic_environment_definition",
    ),
    Dict{String, Any}(
        "path" => "scripts/us/Manifest.toml",
        "sha256" =>
            "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263",
        "role" => "us_diagnostic_environment_lock",
    ),
    Dict{String, Any}(
        "path" => "src/BeforeIT.jl",
        "sha256" =>
            "896578a133edcafa7b191e2869e6b6a01f948fb29201defc5d177ccc010e99c8",
        "role" => "beforeit_module_and_constructor_include_graph",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/object_macro.jl",
        "sha256" =>
            "b74812f3c7932583bdfcadaa39a6c33f5fc94ba5c2d67e7b9346e309b1d68ff7",
        "role" => "constructor_object_schema_macro",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/agents.jl",
        "sha256" =>
            "4830956e9c8aaccf1ba7cf11d58db051345064731561edcfc840830d451a1dc3",
        "role" => "base_model_state_schema_and_finalizer",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init_properties.jl",
        "sha256" =>
            "f82625d25c0adafeb2ee3a8bb9615a67779ba9d4f33ff1900e1cb5d9ebfd0efe",
        "role" => "base_properties_constructor",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init_banks.jl",
        "sha256" =>
            "b47366222af5d5b6cd4341e6f22b4f5c039e7ce68bf50f979cb6fa45a5e45980",
        "role" => "base_bank_and_central_bank_constructors",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init_firms.jl",
        "sha256" =>
            "65ffa48432db22a5b20b72e1dd93ce67cc5f87af11fabee349b9cd91d1b96baf",
        "role" => "base_firms_constructor",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init_workers.jl",
        "sha256" =>
            "80659af0bed6c0586631ae328d740ea1341743c28aa3c65c614161e9cdebc1b9",
        "role" => "base_workers_constructor",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init_government.jl",
        "sha256" =>
            "adffaa1ccddc1e0b4b8c50ad187a6a4c57bf9e3b47022b2930aa47cc921e4bfe",
        "role" => "base_government_constructor",
    ),
    Dict{String, Any}(
        "path" =>
            "src/model_init/init_rest_of_the_world.jl",
        "sha256" =>
            "d964ccb497c34d54d95f93111c9cb5aa9d5afaa4bd4ac8253c2b5c0c7cc2e88c",
        "role" => "base_rest_of_world_constructor",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init_aggregates.jl",
        "sha256" =>
            "708671d97034620089b4f35d787dc857b243a3eaabce2173e0e2504be9c059d8",
        "role" => "base_aggregates_constructor",
    ),
    Dict{String, Any}(
        "path" => "src/model_init/init.jl",
        "sha256" =>
            "be6da22d939427794188a6637e3183ce8307ad3913f5734042e0e830442a7636",
        "role" => "base_model_constructor_entrypoint",
    ),
    Dict{String, Any}(
        "path" => "src/utils/randpl.jl",
        "sha256" =>
            "af93389566c795447100f49ae40abd9719954fa585b1d517cb273b0eadd7ade5",
        "role" => "base_firm_employment_random_allocator",
    ),
    Dict{String, Any}(
        "path" => "src/utils/data.jl",
        "sha256" =>
            "3b42bcc124e5242c2a9b7303d9feddbfa7d6e54b07e62961ef646bf06ff8b5b8",
        "role" => "base_constructor_opening_data_collector",
    ),
    Dict{String, Any}(
        "path" => "src/utils/estimate.jl",
        "sha256" =>
            "8574d562541ebabc8350cb7ae122aa332a6264d2c30f01228d99667b3990b67a",
        "role" => "future_growth_rate_constructor_estimator",
    ),
    Dict{String, Any}(
        "path" =>
            "src/model_extensions/init_growth_rate_model.jl",
        "sha256" =>
            "bd01718238c84a2fb5c9b6410e7312adf40160a164a5df3d9d3d3282eeeb87a7",
        "role" => "future_growth_rate_constructor_scope",
    ),
    Dict{String, Any}(
        "path" => "src/model_extensions/init_CANVAS.jl",
        "sha256" =>
            "023a60ebcea46213d0754c8e85a1ebb5d85c095db14e5d81ca94ee02c38e3ed5",
        "role" => "future_canvas_constructor_scope",
    ),
]
const SOURCE_CLOSURES = [
    Dict{String, Any}(
        "roots" => ["src", "ext"],
        "suffix" => ".jl",
        "member_count" => 60,
        "sha256" =>
            "29268915e9b2360231cbb8656110df3898e6a25e769f4e17df5a322bba4daad3",
        "role" => "complete_beforeit_repository_source_closure",
    ),
]
const REQUIRED_ABSENT_FILES = (
    "JuliaLocalPreferences.toml",
    "LocalPreferences.toml",
    "scripts/us/JuliaLocalPreferences.toml",
    "scripts/us/LocalPreferences.toml",
)
const PROHIBITED_ACTIONS = Set(
    [
        :construct_model,
        :step_model,
        :run_model,
        :emit_forecast,
        :truth_access,
        :score,
        :inference,
        :origin_admission,
        :promotion,
        :production_registry,
        :class_h,
    ],
)

struct ABMOriginFirewallV2Error <: Exception
    message::String
end

Base.showerror(io::IO, error::ABMOriginFirewallV2Error) =
    print(io, error.message)

fail(message) =
    throw(ABMOriginFirewallV2Error(String(message)))

struct QualifiedBaseOriginInputs
    protocol_sha256::String
    model_variant::String
    model_constructor_id::String
    origin_period::String
    integer_word_size_bits::Int
    parameters::Dict{String, Any}
    dynamic::Dict{String, Any}
    static::Dict{String, Any}
    dynamic_periods::Dict{String, Vector{String}}
    excluded_source_parameter_members::Vector{String}
    excluded_source_initial_condition_members::Vector{String}
    partition_sha256::Dict{String, String}
    qualified_input_sha256::String
end

struct BasePathSeedRecord
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
        expect_one_based_indexing(value, "canonical array")
        dimensions = join(size(value), ",")
        encoded = canonical.(vec(value))
        return "array:$(ndims(value)):$(dimensions):$(length(encoded)):" *
            join(
            ("$(ncodeunits(item)):$item" for item in encoded),
            "",
        )
    elseif value isa AbstractDict
        all(key -> key isa AbstractString, keys(value)) ||
            fail("cannot canonicalize a dictionary with non-string keys")
        raw_keys = collect(keys(value))
        normalized_keys = String.(raw_keys)
        length(unique(normalized_keys)) == length(normalized_keys) ||
            fail("cannot canonicalize duplicate normalized string keys")
        entries = collect(zip(normalized_keys, raw_keys))
        sort!(entries; by = first)
        fields = String[]
        for (key, raw_key) in entries
            encoded = canonical(value[raw_key])
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
    value isa AbstractDict || fail("$location must be a dictionary")
    all(key -> key isa AbstractString, keys(value)) ||
        fail("$location must use string keys")
    raw_keys = collect(keys(value))
    normalized_keys = String.(raw_keys)
    length(normalized_keys) == length(expected) ||
        fail("$location must contain exactly $(length(expected)) entries")
    length(unique(normalized_keys)) == length(normalized_keys) ||
        fail("$location contains duplicate normalized string keys")
    actual = Set(normalized_keys)
    wanted = Set(String.(expected))
    missing = sort!(collect(setdiff(wanted, actual)))
    unknown = sort!(collect(setdiff(actual, wanted)))
    isempty(missing) ||
        fail("$location is missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail("$location has unknown keys: $(join(unknown, ", "))")
    return value
end

function expect_equal(actual, expected, location)
    canonical(actual) == canonical(expected) ||
        fail("$location changed from the frozen v2 contract")
    return actual
end

function expect_unique_members(value, expected_count, location)
    value isa Union{Tuple, AbstractVector} ||
        fail("$location must be an ordered member list")
    all(member -> member isa AbstractString, value) ||
        fail("$location must contain only string members")
    members = String.(collect(value))
    length(members) == expected_count ||
        fail("$location must contain exactly $expected_count members")
    length(unique(members)) == expected_count ||
        fail("$location must not contain duplicate members")
    return members
end

function expect_hash(value, location)
    value isa AbstractString ||
        fail("$location must be a lowercase SHA-256")
    text = String(value)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail("$location must be 64 lowercase hexadecimal characters")
    return text
end

function expect_integer(value, location; minimum = nothing)
    value isa Integer && !(value isa Bool) ||
        fail("$location must be an integer, not Bool")
    converted = try
        Int(value)
    catch
        fail("$location is outside the supported Int range")
    end
    minimum === nothing || converted >= minimum ||
        fail("$location must be at least $minimum")
    return converted
end

function expect_finite_real(value, location)
    value isa Real && !(value isa Bool) ||
        fail("$location must be a real number, not Bool")
    converted = Float64(value)
    isfinite(converted) || fail("$location must be finite")
    return converted
end

function expect_constructor_integer(value, location; minimum)
    value isa Real && !(value isa Bool) ||
        fail("$location must be a real number, not Bool")
    source_integer = try
        Int(value)
    catch
        fail("$location must be integer-valued and inside the constructor Int range")
    end
    source_integer >= minimum ||
        fail("$location must be at least $minimum")
    numeric = try
        Float64(value)
    catch
        fail("$location cannot be represented by the Float64 projection")
    end
    isfinite(numeric) || fail("$location must be finite")
    projected_integer = try
        Int(numeric)
    catch
        fail("$location cannot be represented exactly by the Float64 projection")
    end
    projected_integer == source_integer ||
        fail("$location changes value in the Float64 projection")
    return numeric
end

function expect_one_based_indexing(value, location)
    value isa AbstractArray || fail("$location must be an array")
    try
        Base.require_one_based_indexing(value)
    catch
        fail("$location must use one-based axes")
    end
    return value
end

function copy_numeric_array(value, location)
    expect_one_based_indexing(value, location)
    copied = Float64[]
    sizehint!(copied, length(value))
    for (index, item) in enumerate(vec(value))
        push!(copied, expect_finite_real(item, "$location[$index]"))
    end
    return reshape(copied, size(value))
end

function quarter_ordinal(value)
    value isa AbstractString || fail("quarter identifier must be a string")
    text = String(value)
    matched = match(r"^([1-9][0-9]{3})Q([1-4])$", text)
    matched === nothing &&
        fail("invalid quarterly period $(repr(value))")
    return 4parse(Int, matched.captures[1]) +
        parse(Int, matched.captures[2])
end

function validate_periods(value, location)
    value isa AbstractVector ||
        fail("$location must be a quarterly-period vector")
    expect_one_based_indexing(value, location)
    periods = String[]
    for (index, item) in enumerate(value)
        item isa AbstractString ||
            fail("$location[$index] must be a quarterly-period string")
        text = String(item)
        quarter_ordinal(text)
        push!(periods, text)
    end
    isempty(periods) && fail("$location must not be empty")
    length(unique(periods)) == length(periods) ||
        fail("$location contains duplicate quarters")
    all(diff(quarter_ordinal.(periods)) .== 1) ||
        fail("$location must be strictly contiguous")
    return periods
end

function validate_protocol_semantics(document)
    Sys.WORD_SIZE == INTEGER_WORD_SIZE_BITS ||
        fail("v2 seed contract requires a 64-bit Julia runtime")
    expect_exact_keys(
        document,
        (
            "schema_version",
            "contract_id",
            "information_track",
            "diagnostic_class",
            "origin_period",
            "model_variant",
            "model_constructor_id",
            "path_count",
            "runner_implemented",
            "model_constructed",
            "model_stepped",
            "forecast_emitted",
            "raw_source_parameter_keys",
            "excluded_source_parameter_keys",
            "qualified_model_parameter_keys",
            "raw_source_initial_condition_keys",
            "qualified_static_state_keys",
            "qualified_dynamic_history_keys",
            "excluded_source_initial_condition_keys",
            "projection",
            "declarations",
            "execution",
            "future_variants",
            "source_files",
            "source_closures",
            "required_absent_files",
        ),
        "v2 origin-firewall protocol",
    )
    member_lists = (
        (
            "raw_source_parameter_keys",
            RAW_PARAMETER_KEYS,
            RAW_PARAMETER_COUNT,
        ),
        (
            "excluded_source_parameter_keys",
            EXCLUDED_PARAMETER_KEYS,
            EXCLUDED_PARAMETER_COUNT,
        ),
        (
            "qualified_model_parameter_keys",
            MODEL_PARAMETER_KEYS,
            MODEL_PARAMETER_COUNT,
        ),
        (
            "raw_source_initial_condition_keys",
            RAW_INITIAL_CONDITION_KEYS,
            RAW_INITIAL_CONDITION_COUNT,
        ),
        (
            "qualified_static_state_keys",
            STATIC_STATE_KEYS,
            STATIC_STATE_COUNT,
        ),
        (
            "qualified_dynamic_history_keys",
            DYNAMIC_HISTORY_KEYS,
            DYNAMIC_HISTORY_COUNT,
        ),
        (
            "excluded_source_initial_condition_keys",
            EXCLUDED_INITIAL_CONDITION_KEYS,
            EXCLUDED_INITIAL_CONDITION_COUNT,
        ),
    )
    for (field, compiled_members, expected_count) in member_lists
        expect_unique_members(
            compiled_members,
            expected_count,
            "compiled $field",
        )
        expect_unique_members(
            document[field],
            expected_count,
            "protocol $field",
        )
    end
    parameter_members = Set(RAW_PARAMETER_KEYS)
    projected_parameter_members = Set(MODEL_PARAMETER_KEYS)
    excluded_parameter_members = Set(EXCLUDED_PARAMETER_KEYS)
    isempty(
        intersect(
            projected_parameter_members,
            excluded_parameter_members,
        ),
    ) || fail("parameter projection and exclusion sets must be disjoint")
    union(
        projected_parameter_members,
        excluded_parameter_members,
    ) == parameter_members ||
        fail("parameter projection and exclusion sets must partition raw keys")
    initial_condition_members = Set(RAW_INITIAL_CONDITION_KEYS)
    projected_initial_condition_members =
        union(Set(STATIC_STATE_KEYS), Set(DYNAMIC_HISTORY_KEYS))
    excluded_initial_condition_members =
        Set(EXCLUDED_INITIAL_CONDITION_KEYS)
    isempty(
        intersect(
            projected_initial_condition_members,
            excluded_initial_condition_members,
        ),
    ) ||
        fail("initial-condition projection and exclusion sets must be disjoint")
    union(
        projected_initial_condition_members,
        excluded_initial_condition_members,
    ) == initial_condition_members ||
        fail(
        "initial-condition projection and exclusion sets must partition raw keys",
    )
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
    document["model_variant"] == MODEL_VARIANT ||
        fail("protocol model_variant changed")
    document["model_constructor_id"] == MODEL_CONSTRUCTOR_ID ||
        fail("protocol model_constructor_id changed")
    document["path_count"] == PATH_COUNT ||
        fail("protocol path_count changed")
    for key in (
            "runner_implemented",
            "model_constructed",
            "model_stepped",
            "forecast_emitted",
        )
        document[key] === false ||
            fail("protocol $key must remain false")
    end
    expect_equal(
        document["raw_source_parameter_keys"],
        collect(RAW_PARAMETER_KEYS),
        "raw parameter schema",
    )
    expect_equal(
        document["excluded_source_parameter_keys"],
        collect(EXCLUDED_PARAMETER_KEYS),
        "excluded parameter schema",
    )
    expect_equal(
        document["qualified_model_parameter_keys"],
        collect(MODEL_PARAMETER_KEYS),
        "model parameter projection",
    )
    expect_equal(
        document["raw_source_initial_condition_keys"],
        collect(RAW_INITIAL_CONDITION_KEYS),
        "raw initial-condition schema",
    )
    expect_equal(
        document["qualified_static_state_keys"],
        collect(STATIC_STATE_KEYS),
        "static-state projection",
    )
    expect_equal(
        document["qualified_dynamic_history_keys"],
        collect(DYNAMIC_HISTORY_KEYS),
        "dynamic-history projection",
    )
    expect_equal(
        document["excluded_source_initial_condition_keys"],
        collect(EXCLUDED_INITIAL_CONDITION_KEYS),
        "excluded initial-condition schema",
    )
    expect_equal(document["projection"], PROJECTION, "projection rules")
    expect_equal(document["declarations"], DECLARATIONS, "declarations")
    expect_equal(document["execution"], EXECUTION, "execution rules")
    expect_equal(
        document["future_variants"],
        FUTURE_VARIANTS,
        "future variant exclusions",
    )
    expect_equal(document["source_files"], SOURCE_FILES, "source pins")
    expect_equal(
        document["source_closures"],
        SOURCE_CLOSURES,
        "source closure pins",
    )
    expect_equal(
        document["required_absent_files"],
        collect(REQUIRED_ABSENT_FILES),
        "required absent preference files",
    )
    return document
end

function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("v2 origin-firewall protocol is missing: $path")
    bytes = read(path)
    digest = sha256_hex(bytes)
    digest == PROTOCOL_SHA256 ||
        fail("v2 origin-firewall protocol SHA-256 changed")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail("v2 origin-firewall protocol is invalid TOML: $(sprint(showerror, error))")
    end
    validate_protocol_semantics(document)
    return (document = document, sha256 = digest)
end

function source_path(repository_root, relative_path)
    isdir(repository_root) ||
        fail("source-pin repository root is not a directory")
    root = realpath(repository_root)
    current = root
    for component in splitpath(relative_path)
        component in ("", ".") && continue
        component == ".." &&
            fail("source-pin path must not contain parent traversal")
        current = joinpath(current, component)
        islink(current) &&
            fail("source-pin path contains a symbolic link: $relative_path")
    end
    isfile(current) || fail("pinned source file is missing: $relative_path")
    resolved = realpath(current)
    separator = string(Base.Filesystem.path_separator)
    startswith(resolved, root * separator) ||
        fail("pinned source resolves outside the repository: $relative_path")
    return resolved
end

function source_closure_members(repository_root, closure)
    root = realpath(repository_root)
    members = String[]
    for relative_root in closure["roots"]
        directory = joinpath(root, relative_root)
        isdir(directory) ||
            fail("source-closure root is missing: $relative_root")
        islink(directory) &&
            fail("source-closure root is a symbolic link: $relative_root")
        for (current, directories, files) in walkdir(
                directory;
                follow_symlinks = false,
            )
            for name in directories
                islink(joinpath(current, name)) &&
                    fail(
                    "source-closure directory is a symbolic link: " *
                        relpath(joinpath(current, name), root),
                )
            end
            for name in files
                endswith(name, closure["suffix"]) || continue
                path = joinpath(current, name)
                relative = relpath(path, root)
                source_path(root, relative)
                push!(members, relative)
            end
        end
    end
    sort!(members)
    length(unique(members)) == length(members) ||
        fail("source-closure roots overlap")
    return members
end

function source_closure_sha256(repository_root, closure)
    members = source_closure_members(repository_root, closure)
    payload = Dict{String, Any}(
        member => sha256_hex(
                read(source_path(repository_root, member)),
            ) for member in members
    )
    return semantic_sha256(payload)
end

function validate_source_pins(
        repository_root::AbstractString = REPOSITORY_ROOT,
    )
    validate_protocol()
    for source in SOURCE_FILES
        path = source_path(repository_root, source["path"])
        sha256_hex(read(path)) == source["sha256"] ||
            fail("pinned source SHA-256 changed: $(source["path"])")
    end
    for closure in SOURCE_CLOSURES
        members = source_closure_members(repository_root, closure)
        length(members) == closure["member_count"] ||
            fail("source-closure member count changed")
        source_closure_sha256(repository_root, closure) ==
            closure["sha256"] ||
            fail("source-closure SHA-256 changed")
    end
    for relative_path in REQUIRED_ABSENT_FILES
        ispath(joinpath(repository_root, relative_path)) &&
            fail("forbidden repository preference file is present: $relative_path")
    end
    return true
end

function validate_raw_parameters(parameters)
    expect_exact_keys(parameters, RAW_PARAMETER_KEYS, "raw parameters")
    source = Dict{String, Any}(
        String(key) => value for (key, value) in pairs(parameters)
    )
    source_T = expect_integer(source["T"], "raw parameters.T"; minimum = 4)
    source_T_max =
        expect_integer(source["T_max"], "raw parameters.T_max"; minimum = 0)
    source_T_max <= source_T ||
        fail("raw parameters.T_max exceeds raw parameters.T")
    G = expect_integer(source["G"], "raw parameters.G"; minimum = 1)
    source_S = expect_integer(source["S"], "raw parameters.S"; minimum = 1)
    source_S == G || fail("raw parameters.S must equal raw parameters.G")
    T_prime = expect_integer(
        source["T_prime"],
        "raw parameters.T_prime";
        minimum = 1,
    )
    for key in (
            "use_commodity_balance_inventory",
            "use_growth_rate_ar1",
            "use_product_tax_netting",
        )
        source[key] isa Bool ||
            fail("raw parameters.$key must be Bool")
    end
    source["use_growth_rate_ar1"] === false ||
        fail("base v2 requires raw use_growth_rate_ar1=false")

    result = Dict{String, Any}()
    result["G"] = G
    result["T_prime"] = T_prime
    for key in PARAMETER_VECTOR_KEYS
        value = source[key]
        value isa AbstractVector ||
            fail("raw parameters.$key must be a vector")
        expect_one_based_indexing(value, "raw parameters.$key")
        length(value) == G ||
            fail("raw parameters.$key must have length G")
        if key == "I_s"
            copied = reshape(
                [
                    expect_constructor_integer(
                            item,
                            "raw parameters.I_s[$index]";
                            minimum = 1,
                        ) for (index, item) in enumerate(vec(value))
                ],
                size(value),
            )
        else
            copied = copy_numeric_array(
                value,
                "raw parameters.$key",
            )
        end
        result[key] = copied
    end
    value_C = source["C"]
    value_C isa AbstractMatrix ||
        fail("raw parameters.C must be a 3x3 matrix")
    expect_one_based_indexing(value_C, "raw parameters.C")
    size(value_C) == (3, 3) ||
        fail("raw parameters.C must be a 3x3 matrix")
    result["C"] = copy_numeric_array(value_C, "raw parameters.C")
    value_a = source["a_sg"]
    value_a isa AbstractMatrix ||
        fail("raw parameters.a_sg must be a GxG matrix")
    expect_one_based_indexing(value_a, "raw parameters.a_sg")
    size(value_a) == (G, G) ||
        fail("raw parameters.a_sg must be a GxG matrix")
    result["a_sg"] =
        copy_numeric_array(value_a, "raw parameters.a_sg")
    value_beta = source["beta_s"]
    value_beta isa AbstractMatrix ||
        fail("raw parameters.beta_s must be a Gx1 matrix")
    expect_one_based_indexing(value_beta, "raw parameters.beta_s")
    size(value_beta) == (G, 1) ||
        fail("raw parameters.beta_s must be a Gx1 matrix")
    result["beta_s"] =
        copy_numeric_array(value_beta, "raw parameters.beta_s")

    array_keys = Set(
        [
            "C",
            "a_sg",
            "beta_s",
            PARAMETER_VECTOR_KEYS...,
        ],
    )
    for key in MODEL_PARAMETER_KEYS
        key in ("G", "T_prime") && continue
        key in array_keys && continue
        result[key] = if key in INTEGER_LIKE_PARAMETER_KEYS
            expect_constructor_integer(
                source[key],
                "raw parameters.$key";
                minimum = 1,
            )
        else
            expect_finite_real(
                source[key],
                "raw parameters.$key",
            )
        end
    end
    expect_exact_keys(
        result,
        MODEL_PARAMETER_KEYS,
        "qualified model parameters",
    )
    return result
end

function validate_excluded_initial_conditions(source, G, T_prime)
    for key in EXCLUDED_DIAGNOSTIC_VECTOR_KEYS
        value = source[key]
        value isa AbstractVector ||
            fail("raw initial_conditions.$key must be a vector")
        expect_one_based_indexing(
            value,
            "raw initial_conditions.$key",
        )
        length(value) == G ||
            fail("raw initial_conditions.$key must have length G")
        copy_numeric_array(value, "raw initial_conditions.$key")
    end
    for key in EXCLUDED_DIAGNOSTIC_SCALAR_KEYS
        expect_finite_real(
            source[key],
            "raw initial_conditions.$key",
        )
    end
    for key in EXCLUDED_BASE_HISTORY_KEYS
        value = source[key]
        value isa AbstractVector ||
            fail("raw initial_conditions.$key must be a vector")
        expect_one_based_indexing(
            value,
            "raw initial_conditions.$key",
        )
        length(value) == T_prime ||
            fail("raw initial_conditions.$key must have length T_prime")
        copy_numeric_array(value, "raw initial_conditions.$key")
    end
    return nothing
end

function project_static_state(source, G)
    result = Dict{String, Any}()
    for key in ("N_s", "S_s")
        value = source[key]
        value isa AbstractVector ||
            fail("raw initial_conditions.$key must be a vector")
        expect_one_based_indexing(
            value,
            "raw initial_conditions.$key",
        )
        length(value) == G ||
            fail("raw initial_conditions.$key must have length G")
        copied = if key == "N_s"
            reshape(
                [
                    expect_constructor_integer(
                            item,
                            "raw initial_conditions.N_s[$index]";
                            minimum = 0,
                        ) for (index, item) in enumerate(vec(value))
                ],
                size(value),
            )
        else
            copy_numeric_array(
                value,
                "raw initial_conditions.$key",
            )
        end
        if key == "S_s"
            all(>=(0), copied) ||
                fail("raw initial_conditions.S_s must be nonnegative")
        end
        result[key] = copied
    end
    for key in STATIC_STATE_KEYS
        key in ("N_s", "S_s") && continue
        result[key] = expect_finite_real(
            source[key],
            "raw initial_conditions.$key",
        )
    end
    expect_exact_keys(result, STATIC_STATE_KEYS, "qualified static state")
    return result
end

function normalize_period_map(periods_by_series)
    expect_exact_keys(
        periods_by_series,
        DYNAMIC_HISTORY_KEYS,
        "periods_by_series",
    )
    return Dict{String, Vector{String}}(
        key => validate_periods(
                periods_by_series[key],
                "periods_by_series.$key",
            ) for key in DYNAMIC_HISTORY_KEYS
    )
end

function project_dynamic_histories(
        source,
        periods_by_series,
        T_prime,
    )
    source_periods = normalize_period_map(periods_by_series)
    retained_periods = Dict{String, Vector{String}}()
    dynamic = Dict{String, Any}()
    common_axis = nothing
    for key in DYNAMIC_HISTORY_KEYS
        value = source[key]
        value isa AbstractArray ||
            fail("raw initial_conditions.$key must be an array")
        expect_one_based_indexing(
            value,
            "raw initial_conditions.$key",
        )
        if key in COLUMN_HISTORY_KEYS
            value isa AbstractMatrix && size(value, 2) == 1 ||
                fail("raw initial_conditions.$key must be an n-by-1 matrix")
        else
            value isa AbstractVector ||
                fail("raw initial_conditions.$key must be a vector")
        end
        periods = source_periods[key]
        size(value, 1) == length(periods) ||
            fail("raw initial_conditions.$key has no one-to-one period axis")
        origin_index = findfirst(==(ORIGIN_PERIOD), periods)
        origin_index === nothing &&
            fail("periods_by_series.$key does not contain the origin")
        origin_index == T_prime ||
            fail("$key origin index must equal T_prime")
        retained_axis = periods[1:origin_index]
        if common_axis === nothing
            common_axis = retained_axis
        else
            retained_axis == common_axis ||
                fail("retained dynamic period axes must be identical")
        end
        retained = copy(selectdim(value, 1, 1:origin_index))
        copied = copy_numeric_array(
            retained,
            "raw initial_conditions.$key retained prefix",
        )
        if key in POSITIVE_HISTORY_KEYS
            all(>(0), copied) ||
                fail("$key retained history must be strictly positive")
        end
        retained_periods[key] = retained_axis
        dynamic[key] = copied
    end
    common_axis === nothing &&
        fail("dynamic history projection is unexpectedly empty")
    length(common_axis) == T_prime ||
        fail("T_prime does not equal the common retained history length")
    return dynamic, retained_periods
end

function qualified_payload(inputs::QualifiedBaseOriginInputs)
    return Dict{String, Any}(
        "schema_version" => QUALIFIED_SCHEMA_VERSION,
        "protocol_sha256" => inputs.protocol_sha256,
        "model_variant" => inputs.model_variant,
        "model_constructor_id" => inputs.model_constructor_id,
        "origin_period" => inputs.origin_period,
        "integer_word_size_bits" => inputs.integer_word_size_bits,
        "parameters" => inputs.parameters,
        "dynamic" => inputs.dynamic,
        "static" => inputs.static,
        "dynamic_periods" => inputs.dynamic_periods,
        "excluded_source_members" => Dict{String, Any}(
            "parameters" =>
                inputs.excluded_source_parameter_members,
            "initial_conditions" =>
                inputs.excluded_source_initial_condition_members,
        ),
    )
end

function expected_partition_hashes(inputs::QualifiedBaseOriginInputs)
    return Dict{String, String}(
        "parameters" => semantic_sha256(inputs.parameters),
        "dynamic" => semantic_sha256(
            Dict{String, Any}(
                "values" => inputs.dynamic,
                "periods" => inputs.dynamic_periods,
            ),
        ),
        "static" => semantic_sha256(inputs.static),
    )
end

function validate_qualified_inputs(inputs::QualifiedBaseOriginInputs)
    expect_hash(inputs.protocol_sha256, "qualified protocol_sha256")
    inputs.protocol_sha256 == PROTOCOL_SHA256 ||
        fail("qualified input protocol SHA-256 changed")
    inputs.model_variant == MODEL_VARIANT ||
        fail("qualified input model_variant changed")
    inputs.model_constructor_id == MODEL_CONSTRUCTOR_ID ||
        fail("qualified input model_constructor_id changed")
    inputs.origin_period == ORIGIN_PERIOD ||
        fail("qualified input origin_period changed")
    inputs.integer_word_size_bits == INTEGER_WORD_SIZE_BITS ||
        fail("qualified input integer word size changed")
    inputs.integer_word_size_bits == Sys.WORD_SIZE ||
        fail("qualified input integer word size differs from runtime")
    expect_exact_keys(
        inputs.parameters,
        MODEL_PARAMETER_KEYS,
        "qualified parameters",
    )
    expect_exact_keys(
        inputs.dynamic,
        DYNAMIC_HISTORY_KEYS,
        "qualified dynamic histories",
    )
    expect_exact_keys(
        inputs.static,
        STATIC_STATE_KEYS,
        "qualified static state",
    )
    expect_exact_keys(
        inputs.dynamic_periods,
        DYNAMIC_HISTORY_KEYS,
        "qualified dynamic periods",
    )
    inputs.excluded_source_parameter_members ==
        collect(EXCLUDED_PARAMETER_KEYS) ||
        fail("excluded source parameter membership changed")
    inputs.excluded_source_initial_condition_members ==
        collect(EXCLUDED_INITIAL_CONDITION_KEYS) ||
        fail("excluded source initial-condition membership changed")

    G = expect_integer(inputs.parameters["G"], "qualified G"; minimum = 1)
    T_prime = expect_integer(
        inputs.parameters["T_prime"],
        "qualified T_prime";
        minimum = 1,
    )
    common_axis = nothing
    for key in DYNAMIC_HISTORY_KEYS
        periods = validate_periods(
            inputs.dynamic_periods[key],
            "qualified periods.$key",
        )
        last(periods) == ORIGIN_PERIOD ||
            fail("qualified $key periods do not end at the origin")
        length(periods) == T_prime ||
            fail("qualified $key period count differs from T_prime")
        if common_axis === nothing
            common_axis = periods
        else
            periods == common_axis ||
                fail("qualified dynamic period axes differ")
        end
        value = inputs.dynamic[key]
        value isa AbstractArray ||
            fail("qualified $key must be an array")
        expect_one_based_indexing(value, "qualified dynamic.$key")
        if key in COLUMN_HISTORY_KEYS
            value isa AbstractMatrix &&
                size(value) == (T_prime, 1) ||
                fail("qualified $key must be a T_prime-by-1 matrix")
        else
            value isa AbstractVector && length(value) == T_prime ||
                fail("qualified $key must be a T_prime vector")
        end
        copied = copy_numeric_array(value, "qualified dynamic.$key")
        if key in POSITIVE_HISTORY_KEYS
            all(>(0), copied) ||
                fail("qualified $key history must be positive")
        end
    end
    for key in ("N_s", "S_s")
        value = inputs.static[key]
        value isa AbstractVector ||
            fail("qualified static.$key must be a G-vector")
        expect_one_based_indexing(value, "qualified static.$key")
        length(value) == G ||
            fail("qualified static.$key must be a G-vector")
        copied = copy_numeric_array(value, "qualified static.$key")
        if key == "N_s"
            for (index, item) in enumerate(copied)
                expect_constructor_integer(
                    item,
                    "qualified static.N_s[$index]";
                    minimum = 0,
                )
            end
        else
            all(>=(0), copied) ||
                fail("qualified S_s must be nonnegative")
        end
    end
    for key in STATIC_STATE_KEYS
        key in ("N_s", "S_s") && continue
        expect_finite_real(inputs.static[key], "qualified static.$key")
    end
    validate_projected_parameter_shapes(inputs.parameters)

    inputs.partition_sha256 == expected_partition_hashes(inputs) ||
        fail("qualified partition SHA-256 changed")
    semantic_sha256(qualified_payload(inputs)) ==
        inputs.qualified_input_sha256 ||
        fail("qualified input SHA-256 changed")
    return inputs
end

function validate_projected_parameter_shapes(parameters)
    G = expect_integer(parameters["G"], "qualified G"; minimum = 1)
    for key in PARAMETER_VECTOR_KEYS
        value = parameters[key]
        value isa AbstractVector ||
            fail("qualified parameters.$key must be a G-vector")
        expect_one_based_indexing(value, "qualified parameters.$key")
        length(value) == G ||
            fail("qualified parameters.$key must be a G-vector")
        copied = copy_numeric_array(value, "qualified parameters.$key")
        if key == "I_s"
            for (index, item) in enumerate(copied)
                expect_constructor_integer(
                    item,
                    "qualified parameters.I_s[$index]";
                    minimum = 1,
                )
            end
        end
    end
    matrix_shapes = (
        ("C", (3, 3), "3x3"),
        ("a_sg", (G, G), "GxG"),
        ("beta_s", (G, 1), "Gx1"),
    )
    for (key, expected_shape, shape_label) in matrix_shapes
        value = parameters[key]
        value isa AbstractMatrix ||
            fail("qualified parameters.$key must be $shape_label")
        expect_one_based_indexing(
            value,
            "qualified parameters.$key",
        )
        size(value) == expected_shape ||
            fail("qualified parameters.$key must be $shape_label")
        copy_numeric_array(value, "qualified parameters.$key")
    end
    array_keys = Set(
        [
            "C",
            "a_sg",
            "beta_s",
            PARAMETER_VECTOR_KEYS...,
        ],
    )
    for key in MODEL_PARAMETER_KEYS
        key in ("G", "T_prime") && continue
        key in array_keys && continue
        numeric =
            expect_finite_real(parameters[key], "qualified parameters.$key")
        if key in INTEGER_LIKE_PARAMETER_KEYS
            expect_constructor_integer(
                numeric,
                "qualified parameters.$key";
                minimum = 1,
            )
        end
    end
    return parameters
end

"""
    qualify_base_origin_inputs(parameters, initial_conditions,
                               periods_by_series;
                               model_variant, model_constructor_id,
                               class_h_used)

Validate the complete frozen U.S. source envelope, then retain only the exact
inputs consumed by `BeforeIT.Model`. Source `T`, `T_max`, `S`, calibration
markers, diagnostics, CANVAS-only histories, and every post-origin value are
excluded from the qualified hash and seed namespace.
"""
function qualify_base_origin_inputs(
        parameters::AbstractDict,
        initial_conditions::AbstractDict,
        periods_by_series::AbstractDict;
        model_variant::AbstractString,
        model_constructor_id::AbstractString,
        class_h_used::Bool,
        protocol_path::AbstractString = PROTOCOL_PATH,
    )
    protocol = validate_protocol(protocol_path)
    validate_source_pins()
    String(model_variant) == MODEL_VARIANT ||
        fail("v2 permits only model_variant=base")
    String(model_constructor_id) == MODEL_CONSTRUCTOR_ID ||
        fail("v2 permits only model_constructor_id=BeforeIT.Model")
    class_h_used &&
        fail("class-H inputs are forbidden by the v2 firewall")

    projected_parameters = validate_raw_parameters(parameters)
    expect_exact_keys(
        initial_conditions,
        RAW_INITIAL_CONDITION_KEYS,
        "raw initial_conditions",
    )
    source_initial = Dict{String, Any}(
        String(key) => value for
            (key, value) in pairs(initial_conditions)
    )
    G = projected_parameters["G"]
    T_prime = projected_parameters["T_prime"]
    validate_excluded_initial_conditions(source_initial, G, T_prime)
    static = project_static_state(source_initial, G)
    dynamic, retained_periods = project_dynamic_histories(
        source_initial,
        periods_by_series,
        T_prime,
    )

    provisional = QualifiedBaseOriginInputs(
        protocol.sha256,
        MODEL_VARIANT,
        MODEL_CONSTRUCTOR_ID,
        ORIGIN_PERIOD,
        INTEGER_WORD_SIZE_BITS,
        projected_parameters,
        dynamic,
        static,
        retained_periods,
        collect(EXCLUDED_PARAMETER_KEYS),
        collect(EXCLUDED_INITIAL_CONDITION_KEYS),
        Dict{String, String}(),
        "",
    )
    hashes = expected_partition_hashes(provisional)
    with_hashes = QualifiedBaseOriginInputs(
        provisional.protocol_sha256,
        provisional.model_variant,
        provisional.model_constructor_id,
        provisional.origin_period,
        provisional.integer_word_size_bits,
        provisional.parameters,
        provisional.dynamic,
        provisional.static,
        provisional.dynamic_periods,
        provisional.excluded_source_parameter_members,
        provisional.excluded_source_initial_condition_members,
        hashes,
        "",
    )
    result = QualifiedBaseOriginInputs(
        with_hashes.protocol_sha256,
        with_hashes.model_variant,
        with_hashes.model_constructor_id,
        with_hashes.origin_period,
        with_hashes.integer_word_size_bits,
        with_hashes.parameters,
        with_hashes.dynamic,
        with_hashes.static,
        with_hashes.dynamic_periods,
        with_hashes.excluded_source_parameter_members,
        with_hashes.excluded_source_initial_condition_members,
        with_hashes.partition_sha256,
        semantic_sha256(qualified_payload(with_hashes)),
    )
    return validate_qualified_inputs(result)
end

function reassemble_model_inputs(inputs::QualifiedBaseOriginInputs)
    validate_qualified_inputs(inputs)
    initial_conditions = deepcopy(inputs.static)
    for key in DYNAMIC_HISTORY_KEYS
        haskey(initial_conditions, key) &&
            fail("qualified static and dynamic inputs overlap at $key")
        initial_conditions[key] = deepcopy(inputs.dynamic[key])
    end
    expect_exact_keys(
        initial_conditions,
        [STATIC_STATE_KEYS...; DYNAMIC_HISTORY_KEYS...],
        "reassembled initial_conditions",
    )
    return (
        parameters = deepcopy(inputs.parameters),
        initial_conditions = initial_conditions,
        periods_by_series = deepcopy(inputs.dynamic_periods),
        model_variant = inputs.model_variant,
        model_constructor_id = inputs.model_constructor_id,
        integer_word_size_bits = inputs.integer_word_size_bits,
    )
end

function seed_record_payload(record::BasePathSeedRecord)
    return Dict{String, Any}(
        "master_seed" => record.master_seed,
        "experiment_id" => record.experiment_id,
        "origin_manifest_sha256" =>
            record.origin_manifest_sha256,
        "model_id" => record.model_id,
        "path_id" => record.path_id,
        "construction_purpose" => CONSTRUCTION_PURPOSE,
        "construction_seed" => record.construction_seed,
        "construction_seed_key_sha256" =>
            record.construction_seed_key_sha256,
        "simulation_purpose" => SIMULATION_PURPOSE,
        "simulation_seed" => record.simulation_seed,
        "simulation_seed_key_sha256" =>
            record.simulation_seed_key_sha256,
    )
end

function validate_seed_namespace_uniqueness(records)
    construction_keys =
        getfield.(records, :construction_seed_key_sha256)
    simulation_keys =
        getfield.(records, :simulation_seed_key_sha256)
    all_keys = [construction_keys; simulation_keys]
    length(unique(all_keys)) == 2 * PATH_COUNT ||
        fail("construction and simulation seed namespaces are not globally unique")
    construction_seeds = getfield.(records, :construction_seed)
    simulation_seeds = getfield.(records, :simulation_seed)
    all_seeds = [construction_seeds; simulation_seeds]
    length(unique(all_seeds)) == 2 * PATH_COUNT ||
        fail("construction and simulation numeric seeds collided")
    return records
end

function validate_seed_plan(records, inputs::QualifiedBaseOriginInputs)
    validate_qualified_inputs(inputs)
    records isa AbstractVector ||
        fail("base path seed plan must be a vector")
    length(records) == PATH_COUNT ||
        fail("base path seed plan must contain $PATH_COUNT records")
    all(record -> record isa BasePathSeedRecord, records) ||
        fail("base path seed plan contains an unsupported record")
    validate_seed_namespace_uniqueness(records)
    getfield.(records, :path_id) == collect(1:PATH_COUNT) ||
        fail("base path seed plan must be one-based contiguous")
    first_record = first(records)
    first_record.master_seed >= 0 ||
        fail("base path seed master seed must be nonnegative")
    for record in records
        record.master_seed == first_record.master_seed ||
            fail("base path seed plan mixes master seeds")
        record.experiment_id == first_record.experiment_id ||
            fail("base path seed plan mixes experiment IDs")
        record.model_id == first_record.model_id ||
            fail("base path seed plan mixes model IDs")
        record.origin_manifest_sha256 ==
            inputs.qualified_input_sha256 ||
            fail("base path seed plan is not bound to the qualified input")
        construction = try
            derive_seed_record(
                record.master_seed;
                experiment_id = record.experiment_id,
                origin_manifest_sha256 =
                    record.origin_manifest_sha256,
                model_id = record.model_id,
                path_id = record.path_id,
                purpose = CONSTRUCTION_PURPOSE,
            )
        catch error
            fail("construction seed validation failed: $(sprint(showerror, error))")
        end
        simulation = try
            derive_seed_record(
                record.master_seed;
                experiment_id = record.experiment_id,
                origin_manifest_sha256 =
                    record.origin_manifest_sha256,
                model_id = record.model_id,
                path_id = record.path_id,
                purpose = SIMULATION_PURPOSE,
            )
        catch error
            fail("simulation seed validation failed: $(sprint(showerror, error))")
        end
        record.construction_seed == construction.seed ||
            fail("construction seed changed")
        record.construction_seed_key_sha256 ==
            construction.seed_key_sha256 ||
            fail("construction seed-key SHA-256 changed")
        record.simulation_seed == simulation.seed ||
            fail("simulation seed changed")
        record.simulation_seed_key_sha256 ==
            simulation.seed_key_sha256 ||
            fail("simulation seed-key SHA-256 changed")
    end
    return records
end

function derive_base_path_seed_plan(
        master_seed::Integer,
        inputs::QualifiedBaseOriginInputs;
        experiment_id::AbstractString,
        model_id::AbstractString,
        path_ids = collect(1:PATH_COUNT),
    )
    master_seed isa Bool &&
        fail("master_seed must be an integer, not Bool")
    master = expect_integer(master_seed, "master_seed"; minimum = 0)
    validate_qualified_inputs(inputs)
    path_ids isa AbstractVector ||
        fail("path_ids must be a vector")
    normalized_ids = Int[]
    for (index, path_id) in enumerate(path_ids)
        push!(
            normalized_ids,
            expect_integer(path_id, "path_ids[$index]"; minimum = 1),
        )
    end
    sort!(normalized_ids)
    normalized_ids == collect(1:PATH_COUNT) ||
        fail("path_ids must contain exactly 1:$PATH_COUNT")
    records = BasePathSeedRecord[]
    for path_id in normalized_ids
        construction = try
            derive_seed_record(
                master;
                experiment_id,
                origin_manifest_sha256 =
                    inputs.qualified_input_sha256,
                model_id,
                path_id,
                purpose = CONSTRUCTION_PURPOSE,
            )
        catch error
            fail("construction seed derivation failed: $(sprint(showerror, error))")
        end
        simulation = try
            derive_seed_record(
                master;
                experiment_id,
                origin_manifest_sha256 =
                    inputs.qualified_input_sha256,
                model_id,
                path_id,
                purpose = SIMULATION_PURPOSE,
            )
        catch error
            fail("simulation seed derivation failed: $(sprint(showerror, error))")
        end
        push!(
            records,
            BasePathSeedRecord(
                master,
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

function path_seed_plan_sha256(
        records,
        inputs::QualifiedBaseOriginInputs,
    )
    validate_seed_plan(records, inputs)
    return semantic_sha256(seed_record_payload.(records))
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("unknown v2 origin-firewall action $action")
    return fail(
        "v2 origin firewall forbids $(String(action)); " *
            "it validates inputs without constructing or stepping a model",
    )
end

end
