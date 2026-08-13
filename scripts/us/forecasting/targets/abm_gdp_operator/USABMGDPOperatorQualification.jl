module USABMGDPOperatorQualification

using SHA
using TOML

export GDPOperatorQualificationError,
    PROTOCOL_PATH,
    compute_synthetic_operators,
    refuse_prohibited_action,
    validate_protocol,
    validate_protocol_semantics,
    validate_source_pins

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const PROTOCOL_PATH = joinpath(@__DIR__, "operator_qualification.toml")
const EXPECTED_PROTOCOL_SHA256 =
    "c94de45ad463db87d93a6002ca4c6ee9ca5e908423bd793396db5c87d52ae148"
const EXPECTED_SCHEMA =
    "beforeit-us-abm-gdp-operator-qualification.v1"
const EXPECTED_CONTRACT = "beforeit-us-abm-gdp-operator-mechanics.v1"
const EXPECTED_INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const MECHANICS_STATUS =
    "MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING"
const EXPECTED_TARGET_INVENTORY_SEMANTIC_SHA256 =
    "bdbbeb48a39c7fdd03972626cf7f1e421ba7c5dd254f5537a40dda0eb4ae1fcb"
const EXPECTED_BLOCKERS = (
    "FULL_ACCOUNTING_BRIDGE_UNRESOLVED",
    "OUTPUT_SCALE_BRIDGE_UNVALIDATED",
    "TIER1_TARGET_OPERATOR_COVERAGE_ZERO_OF_EIGHT",
    "HISTORICAL_ORIGIN_COUNT_ZERO",
    "BEA_CHAIN_TYPE_REAL_GDP_EQUIVALENCE_NOT_VALIDATED",
    "DIRECT_T10109_HISTORICAL_IDENTITY_NOT_VALIDATED",
)
const DECLARATION_KEYS = (
    "synthetic_fixture_only",
    "raw_model_only",
    "model_execution_allowed",
    "empirical_path_allowed",
    "truth_access_allowed",
    "forecast_emission_allowed",
    "scoring_allowed",
    "inference_allowed",
    "class_h_allowed",
    "bridge_adjustment_allowed",
    "origin_reanchoring_allowed",
    "origin_admissible",
    "promotion_eligible",
    "production_registry_allowed",
    "tier1_operator_approved",
)
const EXPECTED_SOURCE_PINS = (
    (
        path = "src/utils/data.jl",
        sha256 =
            "3b42bcc124e5242c2a9b7303d9feddbfa7d6e54b07e62961ef646bf06ff8b5b8",
        role = "native_nominal_and_real_gdp_measurement_fields",
    ),
    (
        path = "src/agent_actions/aggregates.jl",
        sha256 =
            "b8839ce9a624e25c94b1d039747dbd3cb882a4bb4efa4187642631544b440843",
        role = "forbidden_gross_output_agg_y_semantics",
    ),
    (
        path = "src/utils/get_predictions_from_sims.jl",
        sha256 =
            "52829784340cfaef9608df3b45eb9f53c3a120c73d474c3f64ec8ed9c7ce5737",
        role = "legacy_simple_ratio_growth_exclusion",
    ),
    (
        path = "scripts/us/forecasting/targets/tier1_targets.toml",
        sha256 =
            "328a8717e6626dfa8a57b2068cf82ba9b7231c108275760fe6cf2546b58a82fc",
        role = "tier1_target_and_operator_contract",
    ),
    (
        path =
            "scripts/us/forecasting/diagnostics/revised_data/abm_engineering_protocol.toml",
        sha256 =
            "34461f24ff09e1aa1eed7bf9bad5d8b415eab011bd82b8f7e7a114d0e2246743",
        role = "no_output_engineering_boundary",
    ),
)
const EXPECTED_OPERATORS = (
    (
        target_id = "real_gdp",
        target_version = "bea-real-gdp.v1-draft",
        operator_version = "abm-to-bea-real-gdp.v1-draft",
        raw_model_fields = ["data.real_gdp"],
        forbidden_model_fields = ["agg.Y", "data.real_gdp_ea"],
        formula = "400*log(real_gdp[path,t]/real_gdp[path,t-1])",
        output_unit = "percentage_points_annual_rate",
        frequency = "quarterly",
    ),
    (
        target_id = "gdp_deflator",
        target_version = "bea-gdp-deflator.v1-draft",
        operator_version = "abm-to-bea-gdp-deflator.v1-draft",
        raw_model_fields = ["data.nominal_gdp", "data.real_gdp"],
        forbidden_model_fields =
            ["agg.pi_", "data.gdp_deflator_growth_ea"],
        formula = "400*log((nominal_gdp[path,t]/real_gdp[path,t])/(nominal_gdp[path,t-1]/real_gdp[path,t-1]))",
        output_unit = "percentage_points_annual_rate",
        frequency = "quarterly",
    ),
)
const PROHIBITED_ACTIONS = (
    :run_model,
    :load_truth,
    :emit_forecast,
    :score,
    :infer,
    :admit_origin,
    :approve_tier1_operator,
    :promote,
    :register_production,
)

struct GDPOperatorQualificationError <: Exception
    message::String
end

Base.showerror(io::IO, error::GDPOperatorQualificationError) =
    print(io, error.message)

fail(message) = throw(GDPOperatorQualificationError(message))

struct SyntheticGDPEnsemble
    fixture_class::String
    fixture_id::String
    path_kind::String
    target_periods::Vector{String}
    path_ids::Vector{Int}
    real_gdp_growth::Matrix{Float64}
    gdp_deflator_inflation::Matrix{Float64}
    mechanics_status::String
    concept_bridge_status::String
    truth_accessed::Bool
    score_emitted::Bool
    origin_admissible::Bool
    promotion_eligible::Bool

    function SyntheticGDPEnsemble(
            fixture_id,
            path_kind,
            target_periods,
            path_ids,
            real_gdp_growth,
            gdp_deflator_inflation,
        )
        path_kind == "RAW_MODEL_UNCORRECTED_SYNTHETIC" ||
            fail("synthetic result path kind changed")
        size(real_gdp_growth) == size(gdp_deflator_inflation) ||
            fail("synthetic result matrices must have identical shapes")
        size(real_gdp_growth, 1) == length(target_periods) ||
            fail("synthetic result period count changed")
        size(real_gdp_growth, 2) == length(path_ids) ||
            fail("synthetic result path count changed")
        return new(
            "SYNTHETIC_OPERATOR_TEST_FIXTURE",
            fixture_id,
            path_kind,
            target_periods,
            path_ids,
            real_gdp_growth,
            gdp_deflator_inflation,
            MECHANICS_STATUS,
            "PENDING_VALIDATION",
            false,
            false,
            false,
            false,
        )
    end
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function exact_keys(table, expected, location)
    table isa AbstractDict || fail("$location must be a table")
    all(key -> key isa AbstractString, keys(table)) ||
        fail("$location must use string keys")
    actual = Set(String.(keys(table)))
    wanted = Set(String.(expected))
    actual == wanted ||
        fail("$location keys differ from the frozen contract")
    return table
end

function exact_string(value, expected, location)
    value isa AbstractString || fail("$location must be a string")
    String(value) == expected || fail("$location changed")
    return String(value)
end

function exact_string_array(value, expected, location)
    value isa AbstractVector || fail("$location must be an array")
    all(entry -> entry isa AbstractString, value) ||
        fail("$location must contain strings")
    String.(value) == collect(expected) || fail("$location changed")
    return value
end

function validate_protocol_semantics(document)
    exact_keys(
        document,
        (
            "schema_version",
            "contract_id",
            "information_track",
            "qualification_status",
            "target_inventory_semantic_sha256",
            "operator_count",
            "path_evaluation_rule",
            "origin_row_rule",
            "quarterly_flow_rule",
            "historical_identity_validation_status",
            "official_concept_validation_status",
            "seasonal_adjustment_bridge_status",
            "release_revision_policy",
            "accepted_path_kind",
            "blockers",
            "declarations",
            "source_files",
            "operators",
            "prohibited_actions",
        ),
        "protocol",
    )
    exact_string(document["schema_version"], EXPECTED_SCHEMA, "schema_version")
    exact_string(document["contract_id"], EXPECTED_CONTRACT, "contract_id")
    exact_string(
        document["information_track"],
        EXPECTED_INFORMATION_TRACK,
        "information_track",
    )
    exact_string(
        document["qualification_status"],
        MECHANICS_STATUS,
        "qualification_status",
    )
    exact_string(
        document["target_inventory_semantic_sha256"],
        EXPECTED_TARGET_INVENTORY_SEMANTIC_SHA256,
        "target_inventory_semantic_sha256",
    )
    document["operator_count"] isa Integer &&
        !(document["operator_count"] isa Bool) &&
        document["operator_count"] == 2 ||
        fail("operator_count changed")
    exact_string(
        document["path_evaluation_rule"],
        "transform_each_raw_path_before_any_ensemble_summary",
        "path_evaluation_rule",
    )
    exact_string(
        document["origin_row_rule"],
        "row_one_is_origin_and_output_row_h_plus_one_is_horizon_h",
        "origin_row_rule",
    )
    exact_string(
        document["quarterly_flow_rule"],
        "model_gdp_flows_are_quarterly_and_saar_divide_by_four_constants_cancel_in_log_growth",
        "quarterly_flow_rule",
    )
    exact_string(
        document["historical_identity_validation_status"],
        "NOT_RUN",
        "historical_identity_validation_status",
    )
    exact_string(
        document["official_concept_validation_status"],
        "NOT_RUN",
        "official_concept_validation_status",
    )
    exact_string(
        document["seasonal_adjustment_bridge_status"],
        "NOT_MODELED",
        "seasonal_adjustment_bridge_status",
    )
    exact_string(
        document["release_revision_policy"],
        "NOT_CONSUMED_SYNTHETIC_MECHANICS_ONLY",
        "release_revision_policy",
    )
    exact_string(
        document["accepted_path_kind"],
        "RAW_MODEL_UNCORRECTED_SYNTHETIC",
        "accepted_path_kind",
    )
    exact_string_array(document["blockers"], EXPECTED_BLOCKERS, "blockers")

    declarations =
        exact_keys(document["declarations"], DECLARATION_KEYS, "declarations")
    declarations["synthetic_fixture_only"] === true ||
        fail("synthetic_fixture_only must remain true")
    declarations["raw_model_only"] === true ||
        fail("raw_model_only must remain true")
    for key in DECLARATION_KEYS
        key in ("synthetic_fixture_only", "raw_model_only") && continue
        declarations[key] === false ||
            fail("declarations.$key must remain false")
    end

    source_files = document["source_files"]
    source_files isa AbstractVector ||
        fail("source_files must be an array")
    length(source_files) == length(EXPECTED_SOURCE_PINS) ||
        fail("source_files count changed")
    for (index, expected) in enumerate(EXPECTED_SOURCE_PINS)
        source = exact_keys(
            source_files[index],
            ("path", "sha256", "role"),
            "source_files[$index]",
        )
        for key in ("path", "sha256", "role")
            exact_string(
                source[key],
                getproperty(expected, Symbol(key)),
                "source_files[$index].$key",
            )
        end
    end

    operators = document["operators"]
    operators isa AbstractVector || fail("operators must be an array")
    length(operators) == length(EXPECTED_OPERATORS) ||
        fail("operators count changed")
    for (index, expected) in enumerate(EXPECTED_OPERATORS)
        operator = exact_keys(
            operators[index],
            (
                "target_id",
                "target_version",
                "operator_version",
                "raw_model_fields",
                "forbidden_model_fields",
                "formula",
                "output_unit",
                "frequency",
                "mechanics_status",
                "concept_bridge_status",
            ),
            "operators[$index]",
        )
        for key in (
                "target_id",
                "target_version",
                "operator_version",
                "formula",
                "output_unit",
                "frequency",
            )
            exact_string(
                operator[key],
                getproperty(expected, Symbol(key)),
                "operators[$index].$key",
            )
        end
        exact_string_array(
            operator["raw_model_fields"],
            expected.raw_model_fields,
            "operators[$index].raw_model_fields",
        )
        exact_string_array(
            operator["forbidden_model_fields"],
            expected.forbidden_model_fields,
            "operators[$index].forbidden_model_fields",
        )
        exact_string(
            operator["mechanics_status"],
            MECHANICS_STATUS,
            "operators[$index].mechanics_status",
        )
        exact_string(
            operator["concept_bridge_status"],
            "PENDING_VALIDATION",
            "operators[$index].concept_bridge_status",
        )
    end
    exact_string_array(
        document["prohibited_actions"],
        String.(PROHIBITED_ACTIONS),
        "prohibited_actions",
    )
    return document
end

function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("operator protocol is absent: $path")
    digest = sha256_hex(read(path))
    digest == EXPECTED_PROTOCOL_SHA256 ||
        fail("operator protocol byte identity changed")
    document = try
        TOML.parsefile(path)
    catch error
        fail("operator protocol could not be parsed: $(typeof(error))")
    end
    validate_protocol_semantics(document)
    return (; document, sha256 = digest)
end

function validate_source_pins(
        repository_root::AbstractString = REPOSITORY_ROOT;
        protocol_path::AbstractString = PROTOCOL_PATH,
    )
    protocol = validate_protocol(protocol_path)
    root = rstrip(abspath(repository_root), ('/', '\\'))
    isdir(root) || fail("repository root is absent")
    root_real = realpath(root)
    for source in protocol.document["source_files"]
        relative = source["path"]
        isabspath(relative) && fail("source pin path must be relative")
        occursin('\\', relative) &&
            fail("source pin path must use repository separators")
        path = normpath(joinpath(root, relative))
        startswith(path, root * Base.Filesystem.path_separator) ||
            fail("source pin escapes repository root")
        isfile(path) || fail("source pin is absent: $relative")
        cursor = root
        for component in splitpath(relative)
            cursor = joinpath(cursor, component)
            islink(cursor) &&
                fail("source pin traverses a symbolic link: $relative")
        end
        resolved = realpath(path)
        startswith(
            resolved,
            root_real * Base.Filesystem.path_separator,
        ) || fail("source pin resolves outside repository root: $relative")
        sha256_hex(read(path)) == source["sha256"] ||
            fail("source pin changed: $relative")
    end
    inventory_path =
        joinpath(root, "scripts", "us", "forecasting", "targets", "tier1_targets.toml")
    inventory = try
        TOML.parsefile(inventory_path)
    catch error
        fail("Tier-1 inventory could not be parsed: $(typeof(error))")
    end
    get(get(inventory, "artifact", Dict()), "content_sha256", nothing) ==
        EXPECTED_TARGET_INVENTORY_SEMANTIC_SHA256 ||
        fail("Tier-1 inventory semantic identity changed")
    return true
end

function parse_quarter(period, location)
    period isa AbstractString || fail("$location must be a string")
    text = String(period)
    text == strip(text) || fail("$location has surrounding whitespace")
    matched = match(r"^([0-9]{4})Q([1-4])$", text)
    matched === nothing || length(matched.match) == length(text) ||
        fail("$location must use YYYYQ[1-4]")
    matched === nothing && fail("$location must use YYYYQ[1-4]")
    year = parse(Int, matched.captures[1])
    year >= 1900 || fail("$location year is outside the supported range")
    quarter = parse(Int, matched.captures[2])
    return (year * 4 + quarter - 1, text)
end

function validate_periods(periods)
    periods isa AbstractVector || fail("periods must be an array")
    length(periods) >= 2 ||
        fail("periods must contain an origin and at least one horizon")
    parsed = [
        parse_quarter(period, "periods[$index]")
            for (index, period) in enumerate(periods)
    ]
    for index in 2:length(parsed)
        parsed[index][1] == parsed[index - 1][1] + 1 ||
            fail("periods must be strictly consecutive quarters")
    end
    return last.(parsed)
end

function validate_path_ids(path_ids, path_count)
    path_ids isa AbstractVector || fail("path_ids must be an array")
    length(path_ids) == path_count ||
        fail("path_ids count must equal the ensemble column count")
    ids = Int[]
    for (index, value) in enumerate(path_ids)
        value isa Integer && !(value isa Bool) ||
            fail("path_ids[$index] must be an integer")
        typemin(Int) <= value <= typemax(Int) ||
            fail("path_ids[$index] is outside the supported integer range")
        push!(ids, Int(value))
    end
    ids == collect(1:path_count) ||
        fail("path_ids must be one-based, sorted, and contiguous")
    return ids
end

function validate_levels(values, periods, name)
    values isa AbstractMatrix || fail("$name must be a path matrix")
    size(values, 1) == length(periods) ||
        fail("$name row count must equal the period count")
    size(values, 2) >= 1 || fail("$name must contain at least one path")
    result = Matrix{Float64}(undef, size(values))
    for index in eachindex(values)
        value = values[index]
        value isa Real && !(value isa Bool) ||
            fail("$name must contain numeric non-Boolean levels")
        number = Float64(value)
        isfinite(number) || fail("$name contains a nonfinite level")
        number > 0 || fail("$name levels must be strictly positive")
        result[index] = number
    end
    return result
end

function validate_fixture_id(fixture_id)
    fixture_id isa AbstractString ||
        fail("fixture_id must be a string")
    text = String(fixture_id)
    text == strip(text) || fail("fixture_id has surrounding whitespace")
    occursin(r"^synthetic-[a-z0-9][a-z0-9._-]*$", text) ||
        fail("fixture_id must use the synthetic-* namespace")
    return text
end

"""
    compute_synthetic_operators(periods, path_ids, real_gdp, nominal_gdp; ...)

Apply the two frozen GDP operator formulas independently to every matrix
column. This API accepts synthetic fixtures only. It neither constructs the
ABM nor reads truth, writes an artifact, scores a forecast, approves a bridge,
or admits an origin.
"""
function compute_synthetic_operators(
        periods,
        path_ids,
        real_gdp,
        nominal_gdp;
        fixture_class::AbstractString,
        fixture_id,
        path_kind::AbstractString,
        truth_accessed::Bool,
        empirical_path::Bool,
        class_h_used::Bool,
        bridge_adjusted::Bool,
        origin_reanchored::Bool,
    )
    validate_source_pins()
    fixture_class == "SYNTHETIC_OPERATOR_TEST_FIXTURE" ||
        fail("fixture_class must remain SYNTHETIC_OPERATOR_TEST_FIXTURE")
    path_kind == "RAW_MODEL_UNCORRECTED_SYNTHETIC" ||
        fail("path_kind must remain RAW_MODEL_UNCORRECTED_SYNTHETIC")
    truth_accessed === false ||
        fail("synthetic operator qualification cannot access truth")
    empirical_path === false ||
        fail("synthetic operator qualification cannot accept empirical paths")
    class_h_used === false ||
        fail("synthetic operator qualification cannot accept class-H paths")
    bridge_adjusted === false ||
        fail("synthetic operator qualification cannot accept bridge-adjusted paths")
    origin_reanchored === false ||
        fail("synthetic operator qualification cannot accept reanchored paths")
    fixed_periods = validate_periods(periods)
    real = validate_levels(real_gdp, fixed_periods, "real_gdp")
    nominal = validate_levels(nominal_gdp, fixed_periods, "nominal_gdp")
    size(real) == size(nominal) ||
        fail("real_gdp and nominal_gdp path matrices must have identical shapes")
    ids = validate_path_ids(path_ids, size(real, 2))
    fixed_fixture_id = validate_fixture_id(fixture_id)

    horizon_count = size(real, 1) - 1
    path_count = size(real, 2)
    real_growth = Matrix{Float64}(undef, horizon_count, path_count)
    deflator_inflation =
        Matrix{Float64}(undef, horizon_count, path_count)
    for path in axes(real, 2), row in 2:size(real, 1)
        output_row = row - 1
        real_growth[output_row, path] =
            400.0 * (log(real[row, path]) - log(real[row - 1, path]))
        deflator_inflation[output_row, path] =
            400.0 * (
            (log(nominal[row, path]) - log(real[row, path])) -
                (
                log(nominal[row - 1, path]) -
                    log(real[row - 1, path])
            )
        )
    end
    all(isfinite, real_growth) ||
        fail("real-GDP operator produced a nonfinite value")
    all(isfinite, deflator_inflation) ||
        fail("GDP-deflator operator produced a nonfinite value")

    return SyntheticGDPEnsemble(
        fixed_fixture_id,
        String(path_kind),
        fixed_periods[2:end],
        ids,
        real_growth,
        deflator_inflation,
    )
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS ||
        fail("unknown operator action $(String(action))")
    return fail(
        "GDP operator qualification forbids $(String(action)); " *
            "the boundary is synthetic mechanics only",
    )
end

end
