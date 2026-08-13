module USPCEPriceAnalogueQualification

using SHA
using TOML

export AnalogueQualificationError,
    ECONOMIC_OBJECT,
    MECHANICS_STATUS,
    PROTOCOL_PATH,
    PROHIBITED_ACTIONS,
    compute_protocol_content_sha256,
    compute_synthetic_analogue,
    refuse_prohibited_action,
    validate_protocol,
    validate_protocol_semantics,
    validate_source_pins

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const PROTOCOL_PATH = joinpath(@__DIR__, "analogue_qualification.toml")
const EXPECTED_PROTOCOL_BYTE_SHA256 =
    "a52413dc95042ccc6f8c2952ab5c3996e15ac6a96fb4c9ab1a26ecf8e56f1552"
const PROTOCOL_SCHEMA =
    "beforeit-household-consumption-implicit-price-analogue-qualification.v1"
const PROTOCOL_CANONICALIZATION =
    "sorted_typed_v1_excluding_artifact_content_sha256"
const ECONOMIC_OBJECT =
    "beforeit-household-consumption-implicit-price-analogue.v1"
const MECHANICS_STATUS =
    "MODEL_OPERATOR_MECHANICS_VALIDATED_NONADMITTING"
const FIXTURE_CLASS = "SYNTHETIC_OPERATOR_TEST_FIXTURE"
const INPUT_PATH_KIND = "CALLER_SUPPLIED_SYNTHETIC_RAW_PATHS"
const MEASUREMENT_REGIME = "SYNTHETIC_POST_STEP_HOMOGENEOUS"
const TIER1_INVENTORY_CONTENT_SHA256 =
    "bdbbeb48a39c7fdd03972626cf7f1e421ba7c5dd254f5537a40dda0eb4ae1fcb"
const OPENING_MAPPING_CONTENT_SHA256 =
    "a5afb57a8551b06c6583aa81a1f79f41575a334eca95960167d9b2a9e6f1d665"

const EXPECTED_BLOCKERS = (
    "BEA_FISHER_CHAIN_EQUIVALENCE_UNVALIDATED",
    "PCE_NPISH_PAYER_IMPUTATION_SCOPE_UNVALIDATED",
    "PURCHASER_PRICE_TAX_MARGIN_VALUATION_UNVALIDATED",
    "CORE_PCE_FOOD_ENERGY_CROSSWALK_UNVALIDATED",
    "DIRECT_RELEASE_VINTAGES_ABSENT",
    "SEASONAL_ADJUSTMENT_BRIDGE_UNVALIDATED",
    "OPENING_PRICE_BASKET_STITCH_UNRESOLVED",
    "TIER1_PCE_OPERATOR_APPROVAL_FALSE",
    "TIER1_CORE_PCE_OPERATOR_APPROVAL_FALSE",
)

const PROHIBITED_ACTIONS = (
    :construct_model,
    :run_model,
    :load_artifact,
    :load_truth,
    :emit_forecast,
    :score,
    :infer,
    :execute_opening_to_first_step_empirical,
    :admit_origin,
    :approve_tier1_operator,
    :promote,
    :register_production,
    :write_output,
)

const DECLARATION_KEYS = (
    "synthetic_raw_path_input_only",
    "transform_each_path_before_summary",
    "model_construction_allowed",
    "model_execution_allowed",
    "artifact_input_allowed",
    "truth_access_allowed",
    "empirical_input_allowed",
    "opening_to_first_step_empirical_allowed",
    "forecast_emission_allowed",
    "scoring_allowed",
    "inference_allowed",
    "origin_admissible",
    "promotion_eligible",
    "production_registry_allowed",
    "write_output_allowed",
    "official_total_pce_operator_claim_allowed",
    "official_core_pce_operator_claim_allowed",
)

const EXPECTED_SOURCE_PINS = (
    (
        path = "src/utils/data.jl",
        sha256 =
            "3b42bcc124e5242c2a9b7303d9feddbfa7d6e54b07e62961ef646bf06ff8b5b8",
        role = "opening_normalization_and_post_step_nominal_real_consumption_identity",
    ),
    (
        path = "src/markets/search_and_matching.jl",
        sha256 =
            "940d50110feeeb8c816379375b4cd2b714687f465962699be134e05935b3e61d",
        role = "internal_household_price_aggregate_construction",
    ),
    (
        path = "scripts/us/forecasting/targets/tier1_targets.toml",
        sha256 =
            "328a8717e6626dfa8a57b2068cf82ba9b7231c108275760fe6cf2546b58a82fc",
        role = "direct_total_and_core_pce_target_contracts_and_false_approval_state",
    ),
    (
        path = "scripts/us/forecasting/origins/opening_macro_mapping.toml",
        sha256 =
            "55402fd1620cb5094c267bb8d34145cefdc0c6946c84ef5876dc83cbab838850",
        role = "unresolved_opening_pce_mapping",
    ),
)

const EXPECTED_OFFICIAL_SOURCES = (
    (
        source_id = "bea-nipa-handbook-chapter-4",
        provider = "U.S. Bureau of Economic Analysis",
        title = "NIPA Handbook, Chapter 4: Estimating Methods",
        url =
            "https://www.bea.gov/resources/methodologies/nipa-handbook/pdf/chapter-04.pdf",
        role = "fisher_chain_and_implicit_price_deflator_distinction",
    ),
    (
        source_id = "bea-nipa-handbook-chapter-5",
        provider = "U.S. Bureau of Economic Analysis",
        title = "NIPA Handbook, Chapter 5: Personal Consumption Expenditures",
        url =
            "https://www.bea.gov/resources/methodologies/nipa-handbook/pdf/chapter-05.pdf",
        role = "pce_component_scope_price_quantity_and_fisher_aggregation",
    ),
    (
        source_id = "bea-faq-521",
        provider = "U.S. Bureau of Economic Analysis",
        title = "How are the PCE price indexes calculated?",
        url = "https://www.bea.gov/help/faq/521",
        role = "pce_price_and_quantity_methods",
    ),
    (
        source_id = "bea-faq-555",
        provider = "U.S. Bureau of Economic Analysis",
        title = "How does the PCE price index differ from the CPI?",
        url = "https://www.bea.gov/help/faq/555",
        role = "pce_scope_weight_and_formula_boundary",
    ),
    (
        source_id = "bea-faq-1009",
        provider = "U.S. Bureau of Economic Analysis",
        title = "How are nonprofit institutions serving households treated in the NIPAs?",
        url = "https://www.bea.gov/help/faq/1009",
        role = "npish_scope_boundary",
    ),
    (
        source_id = "bea-faq-83",
        provider = "U.S. Bureau of Economic Analysis",
        title = "What is the market-based PCE price index?",
        url = "https://www.bea.gov/help/faq/83",
        role = "imputation_and_market_scope_boundary",
    ),
    (
        source_id = "bea-faq-518",
        provider = "U.S. Bureau of Economic Analysis",
        title = "What is the core PCE price index?",
        url = "https://www.bea.gov/help/faq/518",
        role = "core_food_and_energy_exclusion_boundary",
    ),
    (
        source_id = "bea-core-pce-food-energy-composition",
        provider = "U.S. Bureau of Economic Analysis",
        title = "Composition of food and energy excluded from the core PCE price index",
        url =
            "https://www.bea.gov/sites/default/files/2018-04/Composition%20of%20food%20and%20energy%20excluded%20from%20Core%20PCE%20Price%20Index.xls",
        role = "detailed_core_product_crosswalk_boundary",
    ),
)

const EXPECTED_TRUTH_SELECTORS = (
    (
        target_id = "pce_price_index",
        dataset_id = "NIPA",
        table_id = "T20304",
        line_number = "1",
        series_code = "DPCERG",
        status = "DOCUMENTED_NOT_LOADED",
    ),
    (
        target_id = "core_pce_price_index",
        dataset_id = "NIPA",
        table_id = "T20304",
        line_number = "25",
        series_code = "DPCCRG",
        status = "DOCUMENTED_NOT_LOADED",
    ),
)

struct AnalogueQualificationError <: Exception
    message::String
end

Base.showerror(io::IO, error::AnalogueQualificationError) =
    print(io, error.message)

fail(location, message) =
    throw(AnalogueQualificationError("$location: $message"))

struct SyntheticPCEAnalogueResult
    fixture_class::String
    fixture_id::String
    economic_object::String
    input_path_kind::String
    measurement_regime::String
    input_periods::Vector{String}
    path_ids::Vector{Int}
    implicit_price_analogue::Matrix{Float64}
    qoq_target_periods::Vector{String}
    annualized_qoq_log_change::Matrix{Float64}
    four_quarter_target_periods::Vector{String}
    four_quarter_log_change::Union{Nothing, Matrix{Float64}}
    mechanics_status::String
    official_equivalence_status::String
    truth_accessed::Bool
    artifact_accessed::Bool
    model_executed::Bool
    empirical_input::Bool
    opening_stitch_used::Bool
    origin_admissible::Bool
    promotion_eligible::Bool
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    wanted = Set(String.(expected))
    actual == wanted || fail(location, "keys differ from the frozen contract")
    return table
end

function expect_exact(value, expected, location)
    typeof(value) === typeof(expected) ||
        fail(location, "type differs from the frozen contract")
    value == expected || fail(location, "value differs from the frozen contract")
    return value
end

function expect_exact_string_array(value, expected, location)
    value isa AbstractVector || fail(location, "must be an array")
    all(entry -> typeof(entry) === String, value) ||
        fail(location, "must contain only strings")
    String.(value) == collect(expected) ||
        fail(location, "value differs from the frozen contract")
    return value
end

function expect_hash(value, location)
    typeof(value) === String || fail(location, "must be a string")
    occursin(r"^[0-9a-f]{64}$", value) ||
        fail(location, "must be a lowercase SHA-256")
    return value
end

function canonical_write(io::IO, value)
    if value isa AbstractDict
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            canonical_write(io, String(key))
            canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            canonical_write(io, entry)
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

function compute_protocol_content_sha256(value)
    document = deepcopy(expect_table(value, "protocol"))
    artifact = expect_table(
        get(document, "artifact", nothing),
        "protocol.artifact",
    )
    pop!(artifact, "content_sha256", nothing)
    io = IOBuffer()
    canonical_write(io, document)
    return sha256_hex(take!(io))
end

function validate_protocol_semantics(document)
    expect_exact_keys(
        document,
        (
            "artifact",
            "contract",
            "boundaries",
            "declarations",
            "source_files",
            "official_sources",
            "direct_truth_selectors",
        ),
        "protocol",
    )

    artifact = expect_exact_keys(
        document["artifact"],
        ("schema_version", "canonicalization", "content_sha256"),
        "protocol.artifact",
    )
    expect_exact(
        artifact["schema_version"],
        PROTOCOL_SCHEMA,
        "protocol.artifact.schema_version",
    )
    expect_exact(
        artifact["canonicalization"],
        PROTOCOL_CANONICALIZATION,
        "protocol.artifact.canonicalization",
    )
    declared =
        expect_hash(artifact["content_sha256"], "protocol.artifact.content_sha256")
    computed = compute_protocol_content_sha256(document)
    declared == computed ||
        fail("protocol.artifact.content_sha256", "semantic self-hash mismatch")

    contract = expect_exact_keys(
        document["contract"],
        (
            "economic_object",
            "qualification_status",
            "information_track",
            "fixture_class",
            "input_path_kind",
            "measurement_regime",
            "raw_inputs",
            "ratio_formula",
            "qoq_formula",
            "four_quarter_formula",
            "transformation_convention",
            "qoq_period_mapping",
            "four_quarter_period_mapping",
            "path_evaluation_rule",
            "rebase_rule",
            "opening_stitch_rule",
            "minimum_qoq_rows",
            "minimum_four_quarter_rows",
            "frequency",
            "qoq_output_unit",
            "four_quarter_output_unit",
            "official_equivalence_status",
            "tier1_total_pce_operator_approved",
            "tier1_core_pce_operator_approved",
            "origin_admissible",
            "promotion_eligible",
        ),
        "protocol.contract",
    )
    expected_contract = (
        economic_object = ECONOMIC_OBJECT,
        qualification_status = MECHANICS_STATUS,
        information_track = "synthetic_model_operator_mechanics",
        fixture_class = FIXTURE_CLASS,
        input_path_kind = INPUT_PATH_KIND,
        measurement_regime = MEASUREMENT_REGIME,
        ratio_formula = "D[path,t]=N[path,t]/R[path,t]",
        qoq_formula = "400*log(D[path,t]/D[path,t-1])",
        four_quarter_formula = "100*log(D[path,t]/D[path,t-4])",
        transformation_convention =
            "continuous_log_for_model_and_eventual_direct_truth_not_bea_published_compounded_annual_rate",
        qoq_period_mapping = "input_row_t_maps_to_same_period_output_row_t_minus_1",
        four_quarter_period_mapping =
            "input_row_t_maps_to_same_period_output_row_t_minus_4",
        path_evaluation_rule = "transform_each_raw_path_before_any_summary",
        rebase_rule = "positive_time_invariant_path_specific_D_scale_cancels",
        opening_stitch_rule =
            "opening_D0_equals_one_by_normalization_and_must_not_be_joined_to_first_post_step_for_empirical_execution",
        minimum_qoq_rows = 2,
        minimum_four_quarter_rows = 5,
        frequency = "quarterly",
        qoq_output_unit = "percentage_points_annual_rate",
        four_quarter_output_unit = "percentage_points",
        official_equivalence_status = "NOT_VALIDATED",
        tier1_total_pce_operator_approved = false,
        tier1_core_pce_operator_approved = false,
        origin_admissible = false,
        promotion_eligible = false,
    )
    for key in keys(expected_contract)
        text_key = String(key)
        expect_exact(
            contract[text_key],
            getproperty(expected_contract, key),
            "protocol.contract.$text_key",
        )
    end
    expect_exact_string_array(
        contract["raw_inputs"],
        ("nominal_household_consumption", "real_household_consumption"),
        "protocol.contract.raw_inputs",
    )

    boundaries = expect_exact_keys(
        document["boundaries"],
        ("blockers", "prohibited_actions"),
        "protocol.boundaries",
    )
    expect_exact_string_array(
        boundaries["blockers"],
        EXPECTED_BLOCKERS,
        "protocol.boundaries.blockers",
    )
    expect_exact_string_array(
        boundaries["prohibited_actions"],
        String.(PROHIBITED_ACTIONS),
        "protocol.boundaries.prohibited_actions",
    )

    declarations = expect_exact_keys(
        document["declarations"],
        DECLARATION_KEYS,
        "protocol.declarations",
    )
    declarations["synthetic_raw_path_input_only"] === true ||
        fail(
        "protocol.declarations.synthetic_raw_path_input_only",
        "must remain true",
    )
    declarations["transform_each_path_before_summary"] === true ||
        fail(
        "protocol.declarations.transform_each_path_before_summary",
        "must remain true",
    )
    for key in DECLARATION_KEYS
        key in (
            "synthetic_raw_path_input_only",
            "transform_each_path_before_summary",
        ) && continue
        declarations[key] === false ||
            fail("protocol.declarations.$key", "must remain false")
    end

    source_files = document["source_files"]
    source_files isa AbstractVector ||
        fail("protocol.source_files", "must be an array")
    length(source_files) == length(EXPECTED_SOURCE_PINS) ||
        fail("protocol.source_files", "count changed")
    for (index, expected) in enumerate(EXPECTED_SOURCE_PINS)
        source = expect_exact_keys(
            source_files[index],
            ("path", "sha256", "role"),
            "protocol.source_files[$index]",
        )
        for key in (:path, :sha256, :role)
            expect_exact(
                source[String(key)],
                getproperty(expected, key),
                "protocol.source_files[$index].$(String(key))",
            )
        end
    end

    official_sources = document["official_sources"]
    official_sources isa AbstractVector ||
        fail("protocol.official_sources", "must be an array")
    length(official_sources) == length(EXPECTED_OFFICIAL_SOURCES) ||
        fail("protocol.official_sources", "count changed")
    for (index, expected) in enumerate(EXPECTED_OFFICIAL_SOURCES)
        source = expect_exact_keys(
            official_sources[index],
            ("source_id", "provider", "title", "url", "role"),
            "protocol.official_sources[$index]",
        )
        for key in (:source_id, :provider, :title, :url, :role)
            expect_exact(
                source[String(key)],
                getproperty(expected, key),
                "protocol.official_sources[$index].$(String(key))",
            )
        end
        startswith(source["url"], "https://www.bea.gov/") ||
            fail(
            "protocol.official_sources[$index].url",
            "must remain an official BEA locator",
        )
    end

    selectors = document["direct_truth_selectors"]
    selectors isa AbstractVector ||
        fail("protocol.direct_truth_selectors", "must be an array")
    length(selectors) == length(EXPECTED_TRUTH_SELECTORS) ||
        fail("protocol.direct_truth_selectors", "count changed")
    for (index, expected) in enumerate(EXPECTED_TRUTH_SELECTORS)
        selector = expect_exact_keys(
            selectors[index],
            (
                "target_id",
                "dataset_id",
                "table_id",
                "line_number",
                "series_code",
                "status",
            ),
            "protocol.direct_truth_selectors[$index]",
        )
        for key in keys(expected)
            expect_exact(
                selector[String(key)],
                getproperty(expected, key),
                "protocol.direct_truth_selectors[$index].$(String(key))",
            )
        end
    end
    return document
end

function validate_protocol(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || fail("protocol", "file is absent: $(abspath(path))")
    bytes = read(path)
    byte_sha256 = sha256_hex(bytes)
    byte_sha256 == EXPECTED_PROTOCOL_BYTE_SHA256 ||
        fail("protocol", "byte identity changed")
    document = try
        TOML.parse(String(bytes))
    catch error
        fail("protocol", "could not parse TOML: $(typeof(error))")
    end
    validate_protocol_semantics(document)
    return (
        document = document,
        byte_sha256 = byte_sha256,
        content_sha256 = document["artifact"]["content_sha256"],
    )
end

function path_is_within(path, root)
    separator = Base.Filesystem.path_separator
    return path == root || startswith(path, root * separator)
end

function validate_source_pins(
        repository_root::AbstractString = REPOSITORY_ROOT;
        protocol_path::AbstractString = PROTOCOL_PATH,
    )
    protocol = validate_protocol(protocol_path)
    root = rstrip(abspath(repository_root), ('/', '\\'))
    isdir(root) || fail("source_pins", "repository root is absent")
    islink(root) && fail("source_pins", "repository root must not be a symlink")
    resolved_root = realpath(root)
    root == resolved_root ||
        fail("source_pins", "repository root path must already be resolved")

    for source in protocol.document["source_files"]
        relative = source["path"]
        isabspath(relative) &&
            fail("source_pins.$relative", "path must be relative")
        occursin('\\', relative) &&
            fail("source_pins.$relative", "path must use repository separators")
        components = splitpath(relative)
        any(component -> component in (".", ".."), components) &&
            fail("source_pins.$relative", "path contains traversal components")
        path = normpath(joinpath(root, relative))
        path_is_within(path, root) ||
            fail("source_pins.$relative", "path escapes repository root")
        cursor = root
        for component in components
            cursor = joinpath(cursor, component)
            islink(cursor) &&
                fail("source_pins.$relative", "path traverses a symlink")
        end
        isfile(path) || fail("source_pins.$relative", "file is absent")
        resolved = realpath(path)
        path_is_within(resolved, resolved_root) ||
            fail("source_pins.$relative", "file resolves outside repository root")
        sha256_hex(read(path)) == source["sha256"] ||
            fail("source_pins.$relative", "SHA-256 changed")
    end

    inventory_path = joinpath(
        root,
        "scripts",
        "us",
        "forecasting",
        "targets",
        "tier1_targets.toml",
    )
    inventory = try
        TOML.parsefile(inventory_path)
    catch error
        fail("source_pins.tier1_targets", "could not parse: $(typeof(error))")
    end
    get(get(inventory, "artifact", Dict()), "content_sha256", nothing) ==
        TIER1_INVENTORY_CONTENT_SHA256 ||
        fail("source_pins.tier1_targets", "semantic identity changed")

    mapping_path = joinpath(
        root,
        "scripts",
        "us",
        "forecasting",
        "origins",
        "opening_macro_mapping.toml",
    )
    mapping = try
        TOML.parsefile(mapping_path)
    catch error
        fail("source_pins.opening_mapping", "could not parse: $(typeof(error))")
    end
    get(get(mapping, "artifact", Dict()), "content_sha256", nothing) ==
        OPENING_MAPPING_CONTENT_SHA256 ||
        fail("source_pins.opening_mapping", "semantic identity changed")
    return true
end

function parse_quarter(period, location)
    typeof(period) === String || fail(location, "must be a String")
    period == strip(period) || fail(location, "has surrounding whitespace")
    matched = match(r"^([0-9]{4})Q([1-4])$", period)
    matched === nothing && fail(location, "must use canonical YYYYQ[1-4]")
    year = parse(Int, matched.captures[1])
    year >= 1900 || fail(location, "year precedes the supported range")
    quarter = parse(Int, matched.captures[2])
    return (4 * year + quarter - 1, period)
end

function validate_periods(periods)
    typeof(periods) === Vector{String} ||
        fail("periods", "must be a Vector{String}")
    length(periods) >= 2 ||
        fail("periods", "must contain at least two sequential quarters")
    parsed = [
        parse_quarter(period, "periods[$index]")
            for (index, period) in enumerate(periods)
    ]
    for index in 2:length(parsed)
        parsed[index][1] == parsed[index - 1][1] + 1 ||
            fail("periods[$index]", "must immediately follow the prior quarter")
    end
    return copy(last.(parsed))
end

function validate_matrix(values, name, period_count)
    typeof(values) === Matrix{Float64} ||
        fail(name, "must be a dense Matrix{Float64}")
    axes(values) == (Base.OneTo(size(values, 1)), Base.OneTo(size(values, 2))) ||
        fail(name, "must use one-based axes")
    size(values, 1) == period_count ||
        fail(name, "row count must equal the period count")
    size(values, 2) >= 1 || fail(name, "must contain at least one path")
    all(isfinite, values) || fail(name, "contains a nonfinite value")
    all(>(0.0), values) || fail(name, "must be strictly positive")
    return values
end

function validate_path_ids(path_ids, path_count)
    typeof(path_ids) === Vector{Int} ||
        fail("path_ids", "must be a Vector{Int}")
    axes(path_ids) == (Base.OneTo(length(path_ids)),) ||
        fail("path_ids", "must use one-based axes")
    length(path_ids) == path_count ||
        fail("path_ids", "count must equal the matrix column count")
    path_ids == collect(1:path_count) ||
        fail("path_ids", "must be one-based, sorted, and contiguous")
    return copy(path_ids)
end

function validate_fixture_id(fixture_id)
    typeof(fixture_id) === String ||
        fail("fixture_id", "must be a String")
    fixture_id == strip(fixture_id) ||
        fail("fixture_id", "has surrounding whitespace")
    occursin(r"^synthetic-[a-z0-9][a-z0-9._-]*$", fixture_id) ||
        fail("fixture_id", "must use the synthetic-* namespace")
    return fixture_id
end

function require_false(value, location)
    value isa Bool || fail(location, "must be a Bool")
    value === false || fail(location, "must remain false")
    return false
end

"""
    compute_synthetic_analogue(periods, path_ids, nominal, real; ...)

Compute the household-consumption implicit-price analogue `D = nominal / real`
and its pathwise quarterly log changes from caller-supplied synthetic matrices.
This function performs no file, artifact, truth, model, network, or write
operation and returns no ensemble summary.
"""
function compute_synthetic_analogue(
        periods,
        path_ids,
        nominal,
        real;
        fixture_class,
        fixture_id,
        input_path_kind,
        measurement_regime,
        include_four_quarter,
        truth_accessed,
        artifact_accessed,
        model_executed,
        empirical_input,
        opening_stitch_used,
    )
    typeof(fixture_class) === String ||
        fail("fixture_class", "must be a String")
    fixture_class == FIXTURE_CLASS ||
        fail("fixture_class", "must remain $FIXTURE_CLASS")
    typeof(input_path_kind) === String ||
        fail("input_path_kind", "must be a String")
    input_path_kind == INPUT_PATH_KIND ||
        fail("input_path_kind", "must remain $INPUT_PATH_KIND")
    typeof(measurement_regime) === String ||
        fail("measurement_regime", "must be a String")
    measurement_regime == MEASUREMENT_REGIME ||
        fail("measurement_regime", "must remain $MEASUREMENT_REGIME")
    include_four_quarter isa Bool ||
        fail("include_four_quarter", "must be a Bool")
    require_false(truth_accessed, "truth_accessed")
    require_false(artifact_accessed, "artifact_accessed")
    require_false(model_executed, "model_executed")
    require_false(empirical_input, "empirical_input")
    require_false(opening_stitch_used, "opening_stitch_used")

    fixed_fixture_id = validate_fixture_id(fixture_id)
    fixed_periods = validate_periods(periods)
    nominal_values = validate_matrix(nominal, "nominal", length(fixed_periods))
    real_values = validate_matrix(real, "real", length(fixed_periods))
    size(nominal_values) == size(real_values) ||
        fail("inputs", "nominal and real matrices must have identical shapes")
    fixed_path_ids = validate_path_ids(path_ids, size(nominal_values, 2))
    include_four_quarter && length(fixed_periods) < 5 &&
        fail(
        "include_four_quarter",
        "requires at least five sequential quarterly rows",
    )

    implicit_price = nominal_values ./ real_values
    all(isfinite, implicit_price) ||
        fail("implicit_price_analogue", "division produced a nonfinite value")
    all(>(0.0), implicit_price) ||
        fail("implicit_price_analogue", "division must remain strictly positive")

    qoq = Matrix{Float64}(
        undef,
        length(fixed_periods) - 1,
        length(fixed_path_ids),
    )
    for path in axes(implicit_price, 2), row in 2:size(implicit_price, 1)
        qoq[row - 1, path] = 400.0 * (
            log(implicit_price[row, path]) -
                log(implicit_price[row - 1, path])
        )
    end
    all(isfinite, qoq) ||
        fail("annualized_qoq_log_change", "operator produced a nonfinite value")

    four_quarter = nothing
    four_quarter_periods = String[]
    if include_four_quarter
        four_quarter = Matrix{Float64}(
            undef,
            length(fixed_periods) - 4,
            length(fixed_path_ids),
        )
        for path in axes(implicit_price, 2), row in 5:size(implicit_price, 1)
            four_quarter[row - 4, path] = 100.0 * (
                log(implicit_price[row, path]) -
                    log(implicit_price[row - 4, path])
            )
        end
        all(isfinite, four_quarter) ||
            fail(
            "four_quarter_log_change",
            "operator produced a nonfinite value",
        )
        four_quarter_periods = copy(fixed_periods[5:end])
    end

    return SyntheticPCEAnalogueResult(
        fixture_class,
        fixed_fixture_id,
        ECONOMIC_OBJECT,
        input_path_kind,
        measurement_regime,
        fixed_periods,
        fixed_path_ids,
        implicit_price,
        copy(fixed_periods[2:end]),
        qoq,
        four_quarter_periods,
        four_quarter,
        MECHANICS_STATUS,
        "NOT_VALIDATED",
        false,
        false,
        false,
        false,
        false,
        false,
        false,
    )
end

function refuse_prohibited_action(action)
    action isa Symbol || fail("action", "must be a Symbol")
    action in PROHIBITED_ACTIONS ||
        fail("action", "unknown action $(String(action))")
    return fail(
        "action",
        "$(String(action)) is forbidden; this boundary is synthetic analogue mechanics only",
    )
end

end
