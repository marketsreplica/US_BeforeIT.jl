module USRealGDPBridgeDecompositionV1

using SHA
using TOML

export BridgeDecompositionError,
    PROTOCOL_PATH,
    EXPECTED_RESULT_SHA256,
    canonical_sha256,
    current_assessment,
    official_observation,
    official_project_log_growth,
    validate_core3_alias,
    qualify_abm_path,
    validate_protocol,
    validate_result,
    refuse_prohibited_action

const REPOSITORY_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", "..", ".."))
const PROTOCOL_PATH = joinpath(@__DIR__, "real_gdp_bridge_decomposition_v1.toml")
const EXPECTED_PROTOCOL_FILE_SHA256 =
    "9ec277ff22c5222db344f33f62fb4295810ec3a30d4172af2273c56e7be43859"
const EXPECTED_PROTOCOL_CONTENT_SHA256 =
    "7bf5c554e466f9cf1fdb78574b84590f37a1cc7251e02a3cb69c7a18c3ed4bff"
const EXPECTED_RESULT_SHA256 =
    "230186825885e003b406014a75079b3a965a0612eb70937b47a3e71894863969"
const SCHEMA_VERSION = "beforeit-us-real-gdp-bridge-decomposition.v1"
const CONTRACT_ID = "beforeit-us-real-gdp-bridge-decomposition.v1"
const STATUS = "REAL_GDP_BRIDGE_DECOMPOSED_NONADMITTING"
const CANONICALIZATION = "sorted-typed-length-aware-excluding-artifact-content-sha256.v1"
const DECIMAL_PATTERN = r"^(?:0|[1-9][0-9]{0,17})(?:\.[0-9]{1,6})?$"
const PERIOD_PATTERN = r"^[0-9]{4}Q[1-4]$"
const SHA_PATTERN = r"^[0-9a-f]{64}$"
const OFFICIAL_KEYS = (
    :period,
    :level_text,
    :artifact_sha256,
    :release_id,
    :vintage_id,
    :table_id,
    :line_number,
    :series_code,
    :unit,
    :base_year,
    :seasonal_adjustment,
)
const OFFICIAL_IDENTITY_KEYS = (
    :artifact_sha256,
    :release_id,
    :vintage_id,
    :table_id,
    :line_number,
    :series_code,
    :unit,
    :base_year,
    :seasonal_adjustment,
)
const ALLOWED_ROW_BASES = Set(["model_implied_opening", "completed_post_step_flow"])
const PROHIBITED_ACTIONS = Set(
    [
        :run_model,
        :load_truth,
        :emit_forecast,
        :score,
        :admit_origin,
        :approve_operator,
        :mutate_registry,
        :promote,
        :register_production,
    ]
)

struct BridgeDecompositionError <: Exception
    message::String
end

Base.showerror(io::IO, error::BridgeDecompositionError) = print(io, error.message)
fail(message) = throw(BridgeDecompositionError(message))

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function _canonical_write(io::IO, value)
    if value isa AbstractDict || value isa NamedTuple
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector || value isa Tuple
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
    else
        fail("canonicalization does not support $(typeof(value))")
    end
    return io
end

function canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return sha256_hex(take!(io))
end

function protocol_content_sha256(document)
    copy = deepcopy(document)
    artifact = copy["artifact"]
    pop!(artifact, "content_sha256", nothing)
    return canonical_sha256(copy)
end

function _reject_symbolic_components(path)
    cursor = abspath(path)
    components = String[]
    while true
        push!(components, cursor)
        parent = dirname(cursor)
        parent == cursor && break
        cursor = parent
    end
    for component in reverse(components)
        ispath(component) || continue
        islink(component) && fail("symbolic-link path component rejected: $component")
    end
    return path
end

function _stable_regular_bytes(path)
    _reject_symbolic_components(path)
    isfile(path) || fail("required regular file is absent: $path")
    before = stat(path)
    before.nlink == 1 || fail("hard-linked file rejected: $path")
    bytes = read(path)
    after = stat(path)
    before.device == after.device &&
        before.inode == after.inode &&
        before.size == after.size &&
        before.mtime == after.mtime &&
        length(bytes) == before.size || fail("file changed while being read: $path")
    return bytes
end

function _expect_exact_keys(table, keys, location)
    table isa AbstractDict || fail("$location must be a table")
    Set(String.(Base.keys(table))) == Set(String.(keys)) ||
        fail("$location keys differ from the closed contract")
    return table
end

function _expect_string(value, location)
    value isa AbstractString || fail("$location must be a string")
    isempty(value) && fail("$location must not be empty")
    return String(value)
end

function _expect_bool(value, expected, location)
    value isa Bool || fail("$location must be Bool")
    value == expected || fail("$location changed")
    return value
end

function _expect_integer(value, expected, location)
    value isa Integer && !(value isa Bool) || fail("$location must be Integer")
    value == expected || fail("$location changed")
    return value
end

function _parse_period(text, location)
    text isa String || fail("$location must be String")
    occursin(PERIOD_PATTERN, text) || fail("$location is not YYYYQn")
    return parse(Int, text[1:4]), parse(Int, text[end:end])
end

function _next_period(text)
    year, quarter = _parse_period(text, "period")
    quarter == 4 && return "$(year + 1)Q1"
    return "$(year)Q$(quarter + 1)"
end

function _parse_decimal_rational(text, location)
    text isa String || fail("$location must be an exact String token")
    ncodeunits(text) <= 25 || fail("$location exceeds the closed token bound")
    occursin(DECIMAL_PATTERN, text) || fail("$location is not a canonical nonnegative decimal")
    parts = split(text, '.'; limit = 2)
    whole = parse(BigInt, parts[1])
    if length(parts) == 1
        numerator, denominator = whole, BigInt(1)
    else
        scale = big(10)^ncodeunits(parts[2])
        numerator = whole * scale + parse(BigInt, parts[2])
        denominator = scale
    end
    numerator > 0 || fail("$location must be strictly positive")
    divisor = gcd(numerator, denominator)
    return div(numerator, divisor) // div(denominator, divisor)
end

function _scaled_log_growth(previous, current, precision)
    return setprecision(BigFloat, precision) do
        previous_value = BigFloat(numerator(previous)) / BigFloat(denominator(previous))
        current_value = BigFloat(numerator(current)) / BigFloat(denominator(current))
        scaled = 400 * (log(current_value) - log(previous_value)) * big(10)^12
        round(BigInt, scaled, RoundNearest)
    end
end

function _fixed_decimal(scaled::BigInt, digits::Int = 12)
    sign = scaled < 0 ? "-" : ""
    magnitude = abs(scaled)
    scale = big(10)^digits
    whole = div(magnitude, scale)
    fraction = lpad(string(mod(magnitude, scale)), digits, '0')
    return "$sign$whole.$fraction"
end

function official_observation(;
        period,
        level_text,
        artifact_sha256,
        release_id,
        vintage_id,
        table_id = "T10106",
        line_number = "1",
        series_code = "A191RX",
        unit = "millions_of_chained_dollars",
        base_year = "2017",
        seasonal_adjustment = "seasonally_adjusted_annual_rate",
    )
    values = (
        period = period,
        level_text = level_text,
        artifact_sha256 = artifact_sha256,
        release_id = release_id,
        vintage_id = vintage_id,
        table_id = table_id,
        line_number = line_number,
        series_code = series_code,
        unit = unit,
        base_year = base_year,
        seasonal_adjustment = seasonal_adjustment,
    )
    for key in OFFICIAL_KEYS
        getfield(values, key) isa String || fail("official.$key must be exact String")
        isempty(getfield(values, key)) && fail("official.$key must not be empty")
    end
    _parse_period(values.period, "official.period")
    _parse_decimal_rational(values.level_text, "official.level_text")
    occursin(SHA_PATTERN, values.artifact_sha256) || fail("official artifact hash is invalid")
    values.table_id == "T10106" || fail("official table must be T10106")
    values.line_number == "1" || fail("official line must be 1")
    values.series_code == "A191RX" || fail("official series must be A191RX")
    values.unit == "millions_of_chained_dollars" || fail("official unit changed")
    values.base_year == "2017" || fail("official reference year changed")
    values.seasonal_adjustment == "seasonally_adjusted_annual_rate" ||
        fail("official seasonal basis changed")
    return values
end

function _validate_official_observation(value, location)
    value isa NamedTuple || fail("$location must be an official observation")
    keys(value) == OFFICIAL_KEYS || fail("$location keys differ")
    return official_observation(; pairs(value)...)
end

function official_project_log_growth(previous, current)
    left = _validate_official_observation(previous, "previous")
    right = _validate_official_observation(current, "current")
    right.period == _next_period(left.period) || fail("official periods must be adjacent")
    for key in OFFICIAL_IDENTITY_KEYS
        getfield(left, key) == getfield(right, key) ||
            fail("official adjacent levels differ in $key")
    end
    previous_rational = _parse_decimal_rational(left.level_text, "previous.level_text")
    current_rational = _parse_decimal_rational(right.level_text, "current.level_text")
    scaled_256 = _scaled_log_growth(previous_rational, current_rational, 256)
    scaled_512 = _scaled_log_growth(previous_rational, current_rational, 512)
    scaled_256 == scaled_512 || fail("log-growth rounding is precision-sensitive")
    return (
        transformation = "400_times_adjacent_log_difference",
        output_unit = "percentage_points_annual_rate",
        period = right.period,
        value_text = _fixed_decimal(scaled_512),
        scaled_integer = scaled_512,
        scale = 12,
        declared_identity_fields_equal = true,
        source_artifact_reopened = false,
        publisher_authenticated = false,
        origin_bound = false,
        bea_compounded_headline_formula_used = false,
        source_level_tokens = [left.level_text, right.level_text],
    )
end

function validate_core3_alias(
        source_name,
        target_name,
        source_values,
        target_values,
    )
    source_name isa String && source_name == "real_gdp" ||
        fail("core3 source name must be exact String real_gdp")
    target_name isa String && target_name == "real_gdp_growth" ||
        fail("core3 target name must be exact String real_gdp_growth")
    typeof(source_values) === Vector{Float64} || fail("core3 source values must be Vector{Float64}")
    typeof(target_values) === Vector{Float64} || fail("core3 target values must be Vector{Float64}")
    length(source_values) == length(target_values) || fail("core3 alias lengths differ")
    all(isfinite, source_values) && all(isfinite, target_values) || fail("core3 alias values must be finite")
    reinterpret(UInt64, source_values) == reinterpret(UInt64, target_values) ||
        fail("core3 alias is not bitwise identity")
    return (
        source_name = source_name,
        target_name = target_name,
        mapping = "identity_alias_no_second_transformation",
        canonical_unit = "annualized_qoq_log_percentage_points",
        factor = 1,
        bitwise_equal = true,
        official_origin_admissible = false,
    )
end

function qualify_abm_path(periods, real_levels, row_bases)
    typeof(periods) === Vector{String} || fail("ABM periods must be Vector{String}")
    typeof(real_levels) === Vector{Float64} || fail("ABM levels must be Vector{Float64}")
    typeof(row_bases) === Vector{String} || fail("ABM row bases must be Vector{String}")
    length(periods) == length(real_levels) == length(row_bases) || fail("ABM vectors differ in length")
    length(periods) >= 2 || fail("ABM path needs at least two rows")
    all(isfinite, real_levels) && all(>(0.0), real_levels) || fail("ABM levels must be finite and positive")
    all(basis -> basis in ALLOWED_ROW_BASES, row_bases) || fail("unknown ABM row basis")
    for index in eachindex(periods)
        _parse_period(periods[index], "ABM period[$index]")
        index == firstindex(periods) && continue
        periods[index] == _next_period(periods[index - 1]) || fail("ABM periods are not adjacent")
    end
    horizons = NamedTuple[]
    for index in 2:length(periods)
        same_completed_basis = row_bases[index - 1] == "completed_post_step_flow" &&
            row_bases[index] == "completed_post_step_flow"
        push!(
            horizons, (
                horizon = index - 1,
                target_period = periods[index],
                previous_basis = row_bases[index - 1],
                current_basis = row_bases[index],
                growth = 400.0 * (log(real_levels[index]) - log(real_levels[index - 1])),
                same_completed_flow_basis = same_completed_basis,
                mechanical_growth_candidate = same_completed_basis,
                official_fisher_chain_bridge_validated = false,
                scoring_eligible = false,
            )
        )
    end
    return horizons
end

function validate_source_pins(document, root)
    sources = document["sources"]
    sources isa AbstractVector || fail("sources must be an array")
    isempty(sources) && fail("sources must not be empty")
    seen = Set{String}()
    for (index, source) in enumerate(sources)
        _expect_exact_keys(source, ("binding_id", "path", "sha256", "role"), "sources[$index]")
        binding_id = _expect_string(source["binding_id"], "sources[$index].binding_id")
        binding_id in seen && fail("duplicate source binding $binding_id")
        push!(seen, binding_id)
        relative_path = _expect_string(source["path"], "sources[$index].path")
        isabspath(relative_path) && fail("source path must be relative")
        ".." in splitpath(relative_path) && fail("source path traversal rejected")
        expected = _expect_string(source["sha256"], "sources[$index].sha256")
        occursin(SHA_PATTERN, expected) || fail("source hash is invalid")
        normalized_root = normpath(root)
        path = normpath(joinpath(normalized_root, relative_path))
        relative_to_root = relpath(path, normalized_root)
        !isabspath(relative_to_root) && !(".." in splitpath(relative_to_root)) ||
            fail("source escaped repository root")
        sha256_hex(_stable_regular_bytes(path)) == expected || fail("source hash mismatch for $binding_id")
    end
    return true
end

function _validate_protocol_semantics(document)
    _expect_exact_keys(
        document,
        ("artifact", "contract", "official_transform", "core3_alias", "abm_measurement", "current_evidence", "gates", "sources", "prohibited_actions"),
        "protocol",
    )
    artifact = _expect_exact_keys(document["artifact"], ("schema_version", "contract_id", "canonicalization", "content_sha256"), "artifact")
    artifact["schema_version"] == SCHEMA_VERSION || fail("schema version changed")
    artifact["contract_id"] == CONTRACT_ID || fail("contract ID changed")
    artifact["canonicalization"] == CANONICALIZATION || fail("canonicalization changed")
    artifact["content_sha256"] == EXPECTED_PROTOCOL_CONTENT_SHA256 || fail("protocol semantic identity changed")
    protocol_content_sha256(document) == EXPECTED_PROTOCOL_CONTENT_SHA256 || fail("protocol semantic hash mismatch")
    contract = document["contract"]
    _expect_exact_keys(contract, ("status", "scope", "bridge_truth_artifact_accessed", "bridge_model_executed", "bridge_forecast_emitted", "bridge_score_emitted", "bridge_origin_admitted"), "contract")
    contract["status"] == STATUS || fail("status changed")
    contract["scope"] == "pure_operator_decomposition_current_bytes_nonadmitting" || fail("scope changed")
    for key in ("bridge_truth_artifact_accessed", "bridge_model_executed", "bridge_forecast_emitted", "bridge_score_emitted", "bridge_origin_admitted")
        _expect_bool(contract[key], false, "contract.$key")
    end
    official = document["official_transform"]
    _expect_exact_keys(official, ("target_id", "table_id", "line_number", "series_code", "source_level_unit", "source_base_year", "source_seasonal_adjustment", "canonical_level_unit", "canonical_unit_alias_factor", "frequency", "project_formula", "bea_headline_formula", "same_release_vintage_required", "mechanics_validated", "historical_origin_validated"), "official_transform")
    official["target_id"] == "real_gdp" || fail("official target changed")
    official["table_id"] == "T10106" || fail("official table changed")
    official["line_number"] == "1" || fail("official line changed")
    official["series_code"] == "A191RX" || fail("official series changed")
    official["source_level_unit"] == "millions_of_chained_dollars" || fail("official source unit changed")
    official["source_base_year"] == "2017" || fail("official source base changed")
    official["source_seasonal_adjustment"] == "seasonally_adjusted_annual_rate" || fail("official source seasonal basis changed")
    official["canonical_level_unit"] == "millions_chained_2017_dollars_saar" || fail("official canonical unit changed")
    _expect_integer(official["canonical_unit_alias_factor"], 1, "official_transform.canonical_unit_alias_factor")
    official["project_formula"] == "400*(ln(level_t)-ln(level_t_minus_1))" || fail("project formula changed")
    official["bea_headline_formula"] == "100*((level_t/level_t_minus_1)^4-1)" || fail("headline formula changed")
    _expect_bool(official["same_release_vintage_required"], true, "official_transform.same_release_vintage_required")
    _expect_bool(official["mechanics_validated"], true, "official_transform.mechanics_validated")
    _expect_bool(official["historical_origin_validated"], false, "official_transform.historical_origin_validated")
    core3 = document["core3_alias"]
    _expect_exact_keys(core3, ("source_name", "target_name", "mapping", "unit", "factor", "mechanics_validated", "origin_bound"), "core3_alias")
    core3["source_name"] == "real_gdp" || fail("core3 source changed")
    core3["target_name"] == "real_gdp_growth" || fail("core3 target changed")
    core3["mapping"] == "identity_alias_no_second_transformation" || fail("core3 mapping changed")
    _expect_integer(core3["factor"], 1, "core3_alias.factor")
    _expect_bool(core3["mechanics_validated"], true, "core3_alias.mechanics_validated")
    _expect_bool(core3["origin_bound"], false, "core3_alias.origin_bound")
    abm = document["abm_measurement"]
    _expect_exact_keys(abm, ("origin_row_basis", "later_row_basis", "horizon_basis", "h1_same_basis", "h2_h4_same_basis", "origin_flow_identified", "fisher_chain_equivalence_validated", "burn_in_or_horizon_shift_allowed"), "abm_measurement")
    abm["horizon_basis"] == ["model_implied_opening_to_post_step_flow", "post_step_flow_to_post_step_flow", "post_step_flow_to_post_step_flow", "post_step_flow_to_post_step_flow"] || fail("ABM horizon basis changed")
    _expect_bool(abm["h1_same_basis"], false, "abm_measurement.h1_same_basis")
    _expect_bool(abm["h2_h4_same_basis"], true, "abm_measurement.h2_h4_same_basis")
    _expect_bool(abm["origin_flow_identified"], false, "abm_measurement.origin_flow_identified")
    _expect_bool(abm["fisher_chain_equivalence_validated"], false, "abm_measurement.fisher_chain_equivalence_validated")
    _expect_bool(abm["burn_in_or_horizon_shift_allowed"], false, "abm_measurement.burn_in_or_horizon_shift_allowed")
    current = document["current_evidence"]
    _expect_exact_keys(current, ("official_transform_mechanics", "core3_alias_mechanics", "abm_h1_same_basis", "abm_h2_h4_same_basis", "official_concept_bridge", "historical_origin", "operator_approved", "blocking_reasons"), "current_evidence")
    current["blocking_reasons"] isa Vector{String} || fail("blocking reasons must be strings")
    issorted(current["blocking_reasons"]) || fail("blocking reasons must be sorted")
    length(unique(current["blocking_reasons"])) == length(current["blocking_reasons"]) || fail("blocking reasons duplicate")
    for (key, expected) in (("official_transform_mechanics", true), ("core3_alias_mechanics", true), ("abm_h1_same_basis", false), ("abm_h2_h4_same_basis", true), ("official_concept_bridge", false), ("historical_origin", false), ("operator_approved", false))
        _expect_bool(current[key], expected, "current_evidence.$key")
    end
    gates = document["gates"]
    gates isa AbstractDict || fail("gates must be a table")
    isempty(gates) && fail("gates must not be empty")
    all(value -> value isa Bool && !value, values(gates)) || fail("every gate must be false")
    actions = document["prohibited_actions"]
    actions isa Vector{String} || fail("prohibited actions must be strings")
    Set(Symbol.(actions)) == PROHIBITED_ACTIONS || fail("prohibited actions changed")
    return document
end

function validate_protocol(; root = REPOSITORY_ROOT)
    bytes = _stable_regular_bytes(PROTOCOL_PATH)
    sha256_hex(bytes) == EXPECTED_PROTOCOL_FILE_SHA256 || fail("protocol file identity changed")
    document = TOML.parse(String(bytes))
    _validate_protocol_semantics(document)
    validate_source_pins(document, root)
    return document
end

function current_assessment(; root = REPOSITORY_ROOT)
    document = validate_protocol(; root)
    evidence = document["current_evidence"]
    return (
        schema_version = SCHEMA_VERSION,
        contract_id = CONTRACT_ID,
        status = STATUS,
        official_transform_mechanics = evidence["official_transform_mechanics"],
        core3_alias_mechanics = evidence["core3_alias_mechanics"],
        abm_h1_same_basis = evidence["abm_h1_same_basis"],
        abm_h2_h4_same_basis = evidence["abm_h2_h4_same_basis"],
        official_concept_bridge = evidence["official_concept_bridge"],
        historical_origin = evidence["historical_origin"],
        operator_approved = evidence["operator_approved"],
        blocking_reasons = copy(evidence["blocking_reasons"]),
        bridge_truth_artifact_accessed = false,
        bridge_model_executed = false,
        bridge_forecast_emitted = false,
        bridge_score_emitted = false,
        bridge_origin_admitted = false,
        bridge_promotion_eligible = false,
        bridge_production_eligible = false,
    )
end

function validate_result(result; root = REPOSITORY_ROOT)
    result isa NamedTuple || fail("result must be NamedTuple")
    expected = current_assessment(; root)
    keys(result) == keys(expected) || fail("result keys differ")
    result == expected || fail("result differs from source-rederived assessment")
    canonical_sha256(result) == EXPECTED_RESULT_SHA256 || fail("result identity changed")
    return result
end

function refuse_prohibited_action(action::Symbol)
    action in PROHIBITED_ACTIONS || fail("unknown action")
    return fail("action $action is prohibited by the nonadmitting bridge contract")
end

end
