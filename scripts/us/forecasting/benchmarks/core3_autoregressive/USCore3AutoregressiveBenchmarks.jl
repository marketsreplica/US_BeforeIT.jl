module USCore3AutoregressiveBenchmarks

using CSV
using LinearAlgebra
using Random
using SHA
using Statistics
using TOML

export AbstractCore3Spec,
    Core3AR1Spec,
    Core3BVAR1Spec,
    Core3BenchmarkError,
    Core3Failure,
    Core3Forecast,
    Core3RevisedPanel,
    Core3Run,
    Core3Sample,
    Core3VAR1Spec,
    STATUS,
    TARGET_NAMES,
    TARGET_PANEL_ID,
    TARGET_UNITS,
    canonical_sha256,
    default_core3_specs,
    load_revised_core3_panel,
    model_contract,
    model_contract_sha256,
    model_id,
    revised_core3_sample,
    run_core3_benchmark,
    run_core3_family,
    sample_sha256,
    synthetic_core3_sample,
    validate_forecast

const SCHEMA_VERSION = "beforeit-us-core3-autoregressive-forecast.v1"
const SAMPLE_SCHEMA_VERSION = "beforeit-us-core3-autoregressive-sample.v1"
const CONTRACT_ID = "beforeit-us-core3-autoregressive-mechanics.v1"
const STATUS = "CORE3_AUTOREGRESSIVE_MECHANICS_VALIDATED_NONADMITTING"
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
const REVISED_INFORMATION_TRACK = "revised_mixed_vintage_diagnostic"
const SYNTHETIC_INFORMATION_TRACK = "synthetic_mechanics_only"
const ALLOWED_INFORMATION_TRACKS =
    Set([REVISED_INFORMATION_TRACK, SYNTHETIC_INFORMATION_TRACK])
const MINIMUM_TRAINING_ROWS = 60
const MAXIMUM_HORIZON = 12
const MAXIMUM_DRAWS = 100_000
const HASH_PATTERN = r"^[0-9a-f]{64}$"
const IDENTIFIER_PATTERN = r"^[A-Za-z0-9][A-Za-z0-9._:-]*$"
const QUARTER_PATTERN = r"^[0-9]{4}Q[1-4]$"
const CANONICALIZATION = "typed-dimensioned-array-sorted-map-ieee754.v1"

const REVISED_TARGET_ORDER = (
    "real_gdp",
    "pce_price_index",
    "core_pce_price_index",
    "gdp_deflator",
    "unemployment_rate",
    "payroll_employment",
    "effective_federal_funds_rate",
    "nominal_gdp",
)
const REVISED_CORE3_COLUMN_INDICES = (1, 2, 7)
const REVISED_PANEL_SCHEMA_VERSION =
    "beforeit-us-revised-data-quarterly-panel.v1"
const REVISED_PANEL_ARTIFACT_ID =
    "beforeit-us-revised-data-eight-target-panel-2026q2.v1"
const REVISED_PANEL_MANIFEST_SHA256 =
    "fc5209e35bb0d04986c2f8c96563f0c21ad511680753ecc7e6d77f0d8435fb3f"
const REVISED_PANEL_SHA256 =
    "f7bb26a467465937060b1e9e734a020b9158a8136db05d2e0df47c3bff851bbe"
const REVISED_SOURCE_RECEIPTS_SHA256 =
    "14bab08bb573265e0affc878cedbbb8d4a0f8f5510fc59990f92d614f109d488"
const REVISED_CORE3_VALUES_SHA256 =
    "905875dbbf7dea22850776d94ee9a1c4ec7d92fc96c6ba3608d00d83a1e9a477"
const REVISED_PANEL_ROWS = 101
const REVISED_PANEL_START = "2000Q3"
const REVISED_PANEL_END = "2025Q3"
const REVISED_FIXTURE_DIRECTORY = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "diagnostics",
        "revised_data",
        "fixtures",
    ),
)
const REVISED_MANIFEST_PATH =
    joinpath(REVISED_FIXTURE_DIRECTORY, "manifest.toml")
const REVISED_PANEL_PATH =
    joinpath(REVISED_FIXTURE_DIRECTORY, "quarterly_panel.csv")
const REVISED_RECEIPTS_PATH =
    joinpath(REVISED_FIXTURE_DIRECTORY, "source_receipts.json")

const BVAR_TIGHTNESS = 0.2
const BVAR_LAG_DECAY = 1.0
const BVAR_OWN_LAG_MEAN = 0.0
const BVAR_INTERCEPT_VARIANCE = 100.0
const BVAR_IW_DOF_OFFSET = 2
const BVAR_INNOVATION_SCALE = 1.0
const BVAR_SCALE_FLOOR = 1.0e-8

const EXPECTED_MODEL_CONTRACT_SHA256 = Dict(
    "nk3_aggregate_pce_univariate_ar1_ols_v1" =>
        "0d33cbebb614794097f31f215fe8dd628a85120c0a198d429216bc37af771842",
    "nk3_aggregate_pce_var1_ols_v1" =>
        "2860c9e0fe1e76e72e365cca1a93559d5adfb1b95755d27b3256ef48c987fc5c",
    "nk3_aggregate_pce_bvar1_mniw_stationary_v1" =>
        "32c9c0c6409f521ba2e919b7bc2b36bc8a47e5217c5aedc6b0bbe019b6470fd6",
)

struct Core3BenchmarkError <: Exception
    code::Symbol
    message::String
end

Base.showerror(io::IO, error::Core3BenchmarkError) = print(io, error.message)
fail(code::Symbol, message) =
    throw(Core3BenchmarkError(code, String(message)))

struct Core3RevisedPanel
    periods::Vector{String}
    values::Matrix{Float64}
    manifest_sha256::String
    panel_sha256::String
    source_receipts_sha256::String
    core3_values_sha256::String
    information_track::String
end

struct Core3Sample
    schema_version::String
    origin_id::String
    origin_key::String
    training_keys::Vector{String}
    forecast_keys::Vector{String}
    y_train::Matrix{Float64}
    target_names::Vector{String}
    target_units::Vector{String}
    target_panel_id::String
    information_track::String
    source_manifest_sha256::Union{Nothing, String}
    source_panel_sha256::Union{Nothing, String}
    source_receipts_sha256::Union{Nothing, String}
    source_core3_values_sha256::Union{Nothing, String}
    origin_receipt_sha256::Union{Nothing, String}
    origin_bound::Bool
end

abstract type AbstractCore3Spec end

"""Fixed-lag, target-by-target OLS AR(1) with an intercept."""
struct Core3AR1Spec <: AbstractCore3Spec end

"""Fixed-lag, three-equation OLS VAR(1) with an intercept."""
struct Core3VAR1Spec <: AbstractCore3Spec end

"""Fixed-prior natural-conjugate MNIW BVAR(1) for stationary observables."""
struct Core3BVAR1Spec <: AbstractCore3Spec end

struct Core3Forecast
    schema_version::String
    contract_id::String
    status::String
    canonicalization::String
    target_panel_id::String
    model_id::String
    model_contract_sha256::String
    sample_sha256::String
    information_track::String
    origin_id::String
    origin_key::String
    training_keys::Vector{String}
    forecast_keys::Vector{String}
    target_names::Vector{String}
    target_units::Vector{String}
    point::Matrix{Float64}
    draws::Array{Float64, 3}
    diagnostics::Dict{String, Any}
    blockers::Vector{String}
    origin_bound::Bool
    origin_admissible::Bool
    scoring_eligible::Bool
    empirical_accuracy_evidence::Bool
    forecast_suitability_evidence::Bool
    promotion_eligible::Bool
    production_eligible::Bool
    registered_benchmark::Bool
    content_sha256::String
end

struct Core3Failure
    code::Symbol
    exception_type::String
    message::String
end

struct Core3Run
    status::Symbol
    model_id::String
    origin_id::String
    forecast::Union{Nothing, Core3Forecast}
    failure::Union{Nothing, Core3Failure}
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function _canonical_write(io::IO, value)
    if value === nothing
        print(io, "N0")
    elseif value isa AbstractDict
        all(key -> key isa AbstractString, keys(value)) ||
            fail(:canonicalization, "canonical maps require string keys")
        entries = sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa Tuple
        print(io, "T", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractArray
        print(io, "A", ndims(value), ":")
        for dimension in size(value)
            print(io, dimension, ",")
        end
        print(io, "[")
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
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) ||
            fail(:canonicalization, "canonical floats must be finite")
        print(io, "F", bitstring(number), ";")
    else
        fail(
            :canonicalization,
            "unsupported canonical value of type $(typeof(value))",
        )
    end
    return io
end

function canonical_sha256(value)
    io = IOBuffer()
    _canonical_write(io, value)
    return sha256_hex(take!(io))
end

function _expect_hash(value, location)
    value isa AbstractString || fail(:invalid_schema, "$location must be a string")
    text = String(value)
    occursin(HASH_PATTERN, text) ||
        fail(:invalid_schema, "$location must be lowercase SHA-256")
    return text
end

function _read_exact_regular_file(path, expected_sha256, location)
    absolute = abspath(path)
    cursor = absolute
    while true
        islink(cursor) &&
            fail(:unsafe_file, "$location contains a symbolic-link component")
        parent = dirname(cursor)
        parent == cursor && break
        cursor = parent
    end
    isfile(absolute) || fail(:missing_file, "$location is missing")
    before = stat(absolute)
    before.nlink == 1 ||
        fail(:unsafe_file, "$location must have exactly one hard link")
    bytes = read(absolute)
    after = stat(absolute)
    (
        before.device,
        before.inode,
        before.size,
        before.mtime,
        before.ctime,
    ) == (
        after.device,
        after.inode,
        after.size,
        after.mtime,
        after.ctime,
    ) || fail(:file_changed, "$location changed while being read")
    sha256_hex(bytes) == expected_sha256 ||
        fail(:hash_mismatch, "$location SHA-256 changed")
    return bytes
end

function _required_false(table, key, location)
    return get(table, key, nothing) === false ||
        fail(:invalid_schema, "$location.$key must remain false")
end

function _quarter_ordinal(value, location)
    value isa AbstractString || fail(:invalid_quarter, "$location must be a string")
    text = String(value)
    text == strip(text) ||
        fail(:invalid_quarter, "$location has surrounding whitespace")
    occursin(QUARTER_PATTERN, text) ||
        fail(:invalid_quarter, "$location must use canonical YYYYQ[1-4]")
    year = parse(Int, text[1:4])
    quarter = parse(Int, text[6:6])
    return 4 * year + quarter - 1
end

function _validate_contiguous_quarters(values, location)
    values isa AbstractVector ||
        fail(:invalid_quarter, "$location must be an array")
    isempty(values) && fail(:invalid_quarter, "$location must not be empty")
    texts = String[]
    ordinals = Int[]
    for (index, value) in enumerate(values)
        ordinal = _quarter_ordinal(value, "$location[$index]")
        push!(texts, String(value))
        push!(ordinals, ordinal)
    end
    length(unique(texts)) == length(texts) ||
        fail(:invalid_quarter, "$location contains duplicate quarters")
    all(index -> ordinals[index] == ordinals[index - 1] + 1, 2:length(ordinals)) ||
        fail(:invalid_quarter, "$location must be ascending and contiguous")
    return texts, ordinals
end

function _validate_revised_manifest(manifest)
    manifest isa AbstractDict ||
        fail(:invalid_schema, "revised panel manifest must be a table")
    get(manifest, "schema_version", nothing) == REVISED_PANEL_SCHEMA_VERSION ||
        fail(:invalid_schema, "revised panel schema version changed")
    get(manifest, "artifact_id", nothing) == REVISED_PANEL_ARTIFACT_ID ||
        fail(:invalid_schema, "revised panel artifact identity changed")
    get(manifest, "information_track", nothing) == REVISED_INFORMATION_TRACK ||
        fail(:invalid_schema, "revised panel information track changed")
    for key in (
            "forecast_origin_admissible",
            "promotion_eligible",
            "abm_accuracy_claimed",
            "bitemporal",
            "real_time",
        )
        _required_false(manifest, key, "manifest")
    end
    get(manifest, "revised_current_release_snapshot", nothing) === true ||
        fail(:invalid_schema, "revised snapshot flag changed")
    get(manifest, "target_order", nothing) == collect(REVISED_TARGET_ORDER) ||
        fail(:target_contract_mismatch, "revised panel target order changed")
    get(manifest, "panel_sha256", nothing) == REVISED_PANEL_SHA256 ||
        fail(:hash_mismatch, "revised panel manifest pin changed")
    get(manifest, "source_receipts_sha256", nothing) ==
        REVISED_SOURCE_RECEIPTS_SHA256 ||
        fail(:hash_mismatch, "revised source-receipt pin changed")
    get(manifest, "source_receipts_file", nothing) == "source_receipts.json" ||
        fail(:invalid_schema, "revised source-receipt locator changed")
    get(manifest, "row_count", nothing) == REVISED_PANEL_ROWS ||
        fail(:invalid_schema, "revised panel row count changed")
    get(manifest, "start_period", nothing) == REVISED_PANEL_START ||
        fail(:invalid_schema, "revised panel start changed")
    get(manifest, "end_period", nothing) == REVISED_PANEL_END ||
        fail(:invalid_schema, "revised panel end changed")
    quarantine = get(manifest, "quarantine", nothing)
    quarantine isa AbstractDict ||
        fail(:invalid_schema, "revised panel quarantine table is missing")
    for key in (
            "historical_release_availability_verified",
            "first_release_truth",
            "near_mature_truth",
            "mature_truth",
            "inventory_registered",
        )
        _required_false(quarantine, key, "manifest.quarantine")
    end
    get(quarantine, "origin_count_added", nothing) == 0 ||
        fail(:invalid_schema, "revised panel origin count is nonzero")
    get(quarantine, "abm_forecast_scores_added", nothing) == 0 ||
        fail(:invalid_schema, "revised panel score count is nonzero")
    return manifest
end

function _core3_panel_payload(periods, values)
    return Dict{String, Any}(
        "target_panel_id" => TARGET_PANEL_ID,
        "target_names" => collect(TARGET_NAMES),
        "target_units" => collect(TARGET_UNITS),
        "periods" => periods,
        "values" => values,
        "source_panel_sha256" => REVISED_PANEL_SHA256,
        "source_manifest_sha256" => REVISED_PANEL_MANIFEST_SHA256,
        "source_receipts_sha256" => REVISED_SOURCE_RECEIPTS_SHA256,
    )
end

"""
    load_revised_core3_panel()

Read and validate the exact quarantined 101-row revised panel, then select its
real-GDP-growth, aggregate-PCE-inflation, and EFFR columns in the small-NK
observable order. This function never constructs an admitted origin or reads
future truth into a forecast sample.
"""
function load_revised_core3_panel()
    manifest_bytes = _read_exact_regular_file(
        REVISED_MANIFEST_PATH,
        REVISED_PANEL_MANIFEST_SHA256,
        "revised panel manifest",
    )
    panel_bytes = _read_exact_regular_file(
        REVISED_PANEL_PATH,
        REVISED_PANEL_SHA256,
        "revised panel",
    )
    _read_exact_regular_file(
        REVISED_RECEIPTS_PATH,
        REVISED_SOURCE_RECEIPTS_SHA256,
        "revised source receipts",
    )
    manifest = _validate_revised_manifest(TOML.parse(String(manifest_bytes)))
    _expect_hash(manifest["panel_sha256"], "manifest.panel_sha256")

    types = Dict(
        Symbol(name) => name == "period" ? String : Float64 for
            name in ("period", REVISED_TARGET_ORDER...)
    )
    table = CSV.File(
        IOBuffer(panel_bytes);
        missingstring = nothing,
        types = types,
    )
    expected_columns = ["period"; collect(REVISED_TARGET_ORDER)]
    String.(propertynames(table)) == expected_columns ||
        fail(:target_contract_mismatch, "revised panel columns changed")
    rows = collect(table)
    length(rows) == REVISED_PANEL_ROWS ||
        fail(:invalid_schema, "revised panel row count changed")
    periods = String[getproperty(row, :period) for row in rows]
    _validate_contiguous_quarters(periods, "revised periods")
    first(periods) == REVISED_PANEL_START ||
        fail(:invalid_schema, "revised panel start changed")
    last(periods) == REVISED_PANEL_END ||
        fail(:invalid_schema, "revised panel end changed")

    complete_values = Matrix{Float64}(
        undef,
        length(rows),
        length(REVISED_TARGET_ORDER),
    )
    for (column, name) in enumerate(REVISED_TARGET_ORDER)
        complete_values[:, column] .=
            Float64[getproperty(row, Symbol(name)) for row in rows]
    end
    all(isfinite, complete_values) ||
        fail(:nonfinite_input, "revised panel contains nonfinite values")
    values = complete_values[:, collect(REVISED_CORE3_COLUMN_INDICES)]
    digest = canonical_sha256(_core3_panel_payload(periods, values))
    digest == REVISED_CORE3_VALUES_SHA256 ||
        fail(:hash_mismatch, "derived revised core-three panel changed")
    return Core3RevisedPanel(
        copy(periods),
        copy(values),
        REVISED_PANEL_MANIFEST_SHA256,
        REVISED_PANEL_SHA256,
        REVISED_SOURCE_RECEIPTS_SHA256,
        digest,
        REVISED_INFORMATION_TRACK,
    )
end

function _validate_revised_panel(panel::Core3RevisedPanel)
    length(panel.periods) == REVISED_PANEL_ROWS ||
        fail(:invalid_schema, "revised core-three period count changed")
    size(panel.values) == (REVISED_PANEL_ROWS, length(TARGET_NAMES)) ||
        fail(:dimension_mismatch, "revised core-three matrix dimensions changed")
    _validate_contiguous_quarters(panel.periods, "revised core-three periods")
    first(panel.periods) == REVISED_PANEL_START ||
        fail(:invalid_schema, "revised core-three start changed")
    last(panel.periods) == REVISED_PANEL_END ||
        fail(:invalid_schema, "revised core-three end changed")
    all(isfinite, panel.values) ||
        fail(:nonfinite_input, "revised core-three values must be finite")
    panel.manifest_sha256 == REVISED_PANEL_MANIFEST_SHA256 ||
        fail(:hash_mismatch, "revised core-three manifest binding changed")
    panel.panel_sha256 == REVISED_PANEL_SHA256 ||
        fail(:hash_mismatch, "revised core-three panel binding changed")
    panel.source_receipts_sha256 == REVISED_SOURCE_RECEIPTS_SHA256 ||
        fail(:hash_mismatch, "revised core-three receipt binding changed")
    panel.information_track == REVISED_INFORMATION_TRACK ||
        fail(:invalid_schema, "revised core-three information track changed")
    digest = canonical_sha256(_core3_panel_payload(panel.periods, panel.values))
    digest == panel.core3_values_sha256 == REVISED_CORE3_VALUES_SHA256 ||
        fail(:hash_mismatch, "revised core-three in-memory values changed")
    return panel
end

function _copy_observation_matrix(data, location)
    data isa AbstractMatrix ||
        fail(:dimension_mismatch, "$location must be a matrix")
    size(data, 2) == length(TARGET_NAMES) ||
        fail(
        :dimension_mismatch,
        "$location must have exactly $(length(TARGET_NAMES)) columns",
    )
    size(data, 1) >= MINIMUM_TRAINING_ROWS ||
        fail(
        :insufficient_training,
        "$location requires at least $MINIMUM_TRAINING_ROWS rows",
    )
    matrix = Matrix{Float64}(undef, size(data))
    for index in eachindex(data)
        value = data[index]
        value isa Real && !(value isa Bool) ||
            fail(:invalid_numeric_type, "$location must contain non-Boolean reals")
        number = Float64(value)
        isfinite(number) ||
            fail(:nonfinite_input, "$location must contain only finite values")
        matrix[index] = iszero(number) ? 0.0 : number
    end
    return matrix
end

function _make_sample(;
        schema_version,
        origin_id,
        origin_key,
        training_keys,
        forecast_keys,
        y_train,
        target_names,
        target_units,
        target_panel_id,
        information_track,
        source_manifest_sha256,
        source_panel_sha256,
        source_receipts_sha256,
        source_core3_values_sha256,
        origin_receipt_sha256,
        origin_bound,
        future_targets,
        x_train,
        x_future,
    )
    future_targets === nothing ||
        fail(:future_target_leakage, "future_targets is forbidden")
    x_train === nothing || fail(:exogenous_forbidden, "x_train is forbidden")
    x_future === nothing || fail(:exogenous_forbidden, "x_future is forbidden")
    schema_version == SAMPLE_SCHEMA_VERSION ||
        fail(:invalid_schema, "core-three sample schema version changed")
    origin_id isa AbstractString ||
        fail(:invalid_identifier, "origin_id must be a string")
    id = String(origin_id)
    id == strip(id) && occursin(IDENTIFIER_PATTERN, id) ||
        fail(:invalid_identifier, "origin_id is not canonical")
    training, training_ordinals =
        _validate_contiguous_quarters(training_keys, "training_keys")
    forecast, forecast_ordinals =
        _validate_contiguous_quarters(forecast_keys, "forecast_keys")
    origin_ordinal = _quarter_ordinal(origin_key, "origin_key")
    origin = String(origin_key)
    last(training_ordinals) == origin_ordinal ||
        fail(:origin_mismatch, "origin_key must equal the last training quarter")
    first(forecast_ordinals) == origin_ordinal + 1 ||
        fail(:origin_mismatch, "forecast_keys must start one quarter after origin")
    length(forecast) <= MAXIMUM_HORIZON ||
        fail(:invalid_horizon, "forecast horizon exceeds $MAXIMUM_HORIZON")
    matrix = _copy_observation_matrix(y_train, "y_train")
    size(matrix, 1) == length(training) ||
        fail(:dimension_mismatch, "y_train and training_keys row counts differ")
    (target_names isa AbstractVector || target_names isa Tuple) &&
        all(value -> value isa AbstractString, target_names) ||
        fail(:target_contract_mismatch, "target names must be strings")
    String.(target_names) == collect(TARGET_NAMES) ||
        fail(:target_contract_mismatch, "target names or order changed")
    (target_units isa AbstractVector || target_units isa Tuple) &&
        all(value -> value isa AbstractString, target_units) ||
        fail(:target_contract_mismatch, "target units must be strings")
    String.(target_units) == collect(TARGET_UNITS) ||
        fail(:target_contract_mismatch, "target units or order changed")
    target_panel_id isa AbstractString && target_panel_id == TARGET_PANEL_ID ||
        fail(:target_contract_mismatch, "target panel identity changed")
    information_track isa AbstractString &&
        information_track in ALLOWED_INFORMATION_TRACKS ||
        fail(:invalid_information_track, "information track is not closed")
    origin_receipt_sha256 === nothing ||
        fail(:origin_binding_forbidden, "candidate cannot accept an origin receipt")
    origin_bound === false ||
        fail(:origin_binding_forbidden, "candidate cannot mark an origin bound")
    if information_track == SYNTHETIC_INFORMATION_TRACK
        all(
            value -> value === nothing,
            (
                source_manifest_sha256,
                source_panel_sha256,
                source_receipts_sha256,
                source_core3_values_sha256,
            ),
        ) || fail(:invalid_source_binding, "synthetic sample cannot claim source hashes")
    else
        source_manifest_sha256 == REVISED_PANEL_MANIFEST_SHA256 ||
            fail(:hash_mismatch, "revised sample manifest binding changed")
        source_panel_sha256 == REVISED_PANEL_SHA256 ||
            fail(:hash_mismatch, "revised sample panel binding changed")
        source_receipts_sha256 == REVISED_SOURCE_RECEIPTS_SHA256 ||
            fail(:hash_mismatch, "revised sample receipt binding changed")
        source_core3_values_sha256 == REVISED_CORE3_VALUES_SHA256 ||
            fail(:hash_mismatch, "revised sample derived-panel binding changed")
    end
    return Core3Sample(
        SAMPLE_SCHEMA_VERSION,
        id,
        origin,
        copy(training),
        copy(forecast),
        matrix,
        collect(TARGET_NAMES),
        collect(TARGET_UNITS),
        TARGET_PANEL_ID,
        String(information_track),
        source_manifest_sha256,
        source_panel_sha256,
        source_receipts_sha256,
        source_core3_values_sha256,
        nothing,
        false,
    )
end

"""Construct a copied, synthetic-only sample with no future target field."""
function synthetic_core3_sample(;
        schema_version = SAMPLE_SCHEMA_VERSION,
        origin_id,
        origin_key,
        training_keys,
        forecast_keys,
        y_train,
        target_names = collect(TARGET_NAMES),
        target_units = collect(TARGET_UNITS),
        target_panel_id = TARGET_PANEL_ID,
        future_targets = nothing,
        x_train = nothing,
        x_future = nothing,
    )
    return _make_sample(;
        schema_version = schema_version,
        origin_id = origin_id,
        origin_key = origin_key,
        training_keys = training_keys,
        forecast_keys = forecast_keys,
        y_train = y_train,
        target_names = target_names,
        target_units = target_units,
        target_panel_id = target_panel_id,
        information_track = SYNTHETIC_INFORMATION_TRACK,
        source_manifest_sha256 = nothing,
        source_panel_sha256 = nothing,
        source_receipts_sha256 = nothing,
        source_core3_values_sha256 = nothing,
        origin_receipt_sha256 = nothing,
        origin_bound = false,
        future_targets = future_targets,
        x_train = x_train,
        x_future = x_future,
    )
end

"""
    revised_core3_sample(panel, origin_index; horizon)

Copy only rows through `origin_index` from the pinned revised panel. Future
period labels are retained for dimensional alignment; future target values are
neither accepted nor copied.
"""
function revised_core3_sample(
        panel::Core3RevisedPanel,
        origin_index;
        horizon,
        future_targets = nothing,
        x_train = nothing,
        x_future = nothing,
    )
    _validate_revised_panel(panel)
    origin_index isa Integer && !(origin_index isa Bool) ||
        fail(:invalid_origin_index, "origin_index must be an integer")
    index = Int(origin_index)
    index >= MINIMUM_TRAINING_ROWS ||
        fail(:insufficient_training, "origin_index is before the minimum window")
    horizon isa Integer && !(horizon isa Bool) ||
        fail(:invalid_horizon, "horizon must be an integer")
    steps = Int(horizon)
    1 <= steps <= MAXIMUM_HORIZON ||
        fail(:invalid_horizon, "horizon must lie in 1:$MAXIMUM_HORIZON")
    index + steps <= length(panel.periods) ||
        fail(:invalid_horizon, "revised panel has insufficient future period labels")
    origin = panel.periods[index]
    return _make_sample(;
        schema_version = SAMPLE_SCHEMA_VERSION,
        origin_id = "revised-core3-diagnostic-$origin",
        origin_key = origin,
        training_keys = panel.periods[1:index],
        forecast_keys = panel.periods[(index + 1):(index + steps)],
        y_train = panel.values[1:index, :],
        target_names = collect(TARGET_NAMES),
        target_units = collect(TARGET_UNITS),
        target_panel_id = TARGET_PANEL_ID,
        information_track = REVISED_INFORMATION_TRACK,
        source_manifest_sha256 = panel.manifest_sha256,
        source_panel_sha256 = panel.panel_sha256,
        source_receipts_sha256 = panel.source_receipts_sha256,
        source_core3_values_sha256 = panel.core3_values_sha256,
        origin_receipt_sha256 = nothing,
        origin_bound = false,
        future_targets = future_targets,
        x_train = x_train,
        x_future = x_future,
    )
end

function _float64_matrix_bits_equal(left, right)
    size(left) == size(right) || return false
    for index in eachindex(left, right)
        reinterpret(UInt64, left[index]) == reinterpret(UInt64, right[index]) ||
            return false
    end
    return true
end

function _validate_revised_sample_binding(sample::Core3Sample)
    panel = load_revised_core3_panel()
    origin_index = length(sample.training_keys)
    horizon = length(sample.forecast_keys)
    origin_index + horizon <= length(panel.periods) ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample extends beyond the pinned panel",
    )
    expected_origin = panel.periods[origin_index]
    sample.origin_id == "revised-core3-diagnostic-$expected_origin" ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample origin identity is not the pinned-panel origin",
    )
    sample.origin_key == expected_origin ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample origin key is not the pinned-panel origin",
    )
    sample.training_keys == panel.periods[1:origin_index] ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample training keys are not the exact pinned-panel prefix",
    )
    sample.forecast_keys ==
        panel.periods[(origin_index + 1):(origin_index + horizon)] ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample forecast keys are not the exact following pinned-panel labels",
    )
    _float64_matrix_bits_equal(
        sample.y_train,
        @view(panel.values[1:origin_index, :]),
    ) ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample observations are not the bit-exact pinned-panel prefix",
    )
    (
        sample.source_manifest_sha256,
        sample.source_panel_sha256,
        sample.source_receipts_sha256,
        sample.source_core3_values_sha256,
    ) == (
        panel.manifest_sha256,
        panel.panel_sha256,
        panel.source_receipts_sha256,
        panel.core3_values_sha256,
    ) ||
        fail(
        :revised_sample_binding_mismatch,
        "revised sample source identities are not the independently loaded panel identities",
    )
    return sample
end

function _validate_sample(sample::Core3Sample)
    rebuilt = _make_sample(;
        schema_version = sample.schema_version,
        origin_id = sample.origin_id,
        origin_key = sample.origin_key,
        training_keys = sample.training_keys,
        forecast_keys = sample.forecast_keys,
        y_train = sample.y_train,
        target_names = sample.target_names,
        target_units = sample.target_units,
        target_panel_id = sample.target_panel_id,
        information_track = sample.information_track,
        source_manifest_sha256 = sample.source_manifest_sha256,
        source_panel_sha256 = sample.source_panel_sha256,
        source_receipts_sha256 = sample.source_receipts_sha256,
        source_core3_values_sha256 = sample.source_core3_values_sha256,
        origin_receipt_sha256 = sample.origin_receipt_sha256,
        origin_bound = sample.origin_bound,
        future_targets = nothing,
        x_train = nothing,
        x_future = nothing,
    )
    canonical_sha256(_sample_payload(rebuilt)) ==
        canonical_sha256(_sample_payload(sample)) ||
        fail(:invalid_sample, "sample failed canonical reconstruction")
    sample.information_track == REVISED_INFORMATION_TRACK &&
        _validate_revised_sample_binding(sample)
    return sample
end

function _sample_payload(sample::Core3Sample)
    return Dict{String, Any}(
        "schema_version" => sample.schema_version,
        "origin_id" => sample.origin_id,
        "origin_key" => sample.origin_key,
        "training_keys" => sample.training_keys,
        "forecast_keys" => sample.forecast_keys,
        "y_train" => sample.y_train,
        "target_names" => sample.target_names,
        "target_units" => sample.target_units,
        "target_panel_id" => sample.target_panel_id,
        "information_track" => sample.information_track,
        "source_manifest_sha256" => sample.source_manifest_sha256,
        "source_panel_sha256" => sample.source_panel_sha256,
        "source_receipts_sha256" => sample.source_receipts_sha256,
        "source_core3_values_sha256" => sample.source_core3_values_sha256,
        "origin_receipt_sha256" => sample.origin_receipt_sha256,
        "origin_bound" => sample.origin_bound,
    )
end

sample_sha256(sample::Core3Sample) =
    canonical_sha256(_sample_payload(_validate_sample(sample)))

model_id(::Core3AR1Spec) = "nk3_aggregate_pce_univariate_ar1_ols_v1"
model_id(::Core3VAR1Spec) = "nk3_aggregate_pce_var1_ols_v1"
model_id(::Core3BVAR1Spec) = "nk3_aggregate_pce_bvar1_mniw_stationary_v1"
model_id(::AbstractCore3Spec) = "unsupported_core3_spec"

default_core3_specs() =
    AbstractCore3Spec[Core3AR1Spec(), Core3VAR1Spec(), Core3BVAR1Spec()]

function _common_model_contract(spec::AbstractCore3Spec)
    return Dict{String, Any}(
        "contract_id" => CONTRACT_ID,
        "model_id" => model_id(spec),
        "target_panel_id" => TARGET_PANEL_ID,
        "target_names" => collect(TARGET_NAMES),
        "target_units" => collect(TARGET_UNITS),
        "lags" => 1,
        "intercept" => true,
        "forecast_method" => "iterated_recursive",
        "predictive_rng_semantics" =>
            "sha256_domain_separated_mersenne_twister_per_path",
        "minimum_training_rows" => MINIMUM_TRAINING_ROWS,
        "maximum_horizon" => MAXIMUM_HORIZON,
        "information_policy" =>
            "training_targets_through_origin_only_no_future_targets_no_exogenous_inputs",
        "origin_estimation" => "refit_from_identical_origin_training_matrix",
        "pandemic_special_treatment" => false,
        "elb_special_treatment" => false,
        "origin_admissible" => false,
        "scoring_eligible" => false,
        "empirical_accuracy_evidence" => false,
        "forecast_suitability_evidence" => false,
        "promotion_eligible" => false,
        "production_eligible" => false,
        "registered_benchmark" => false,
    )
end

function model_contract(spec::Core3AR1Spec)
    contract = _common_model_contract(spec)
    contract["family"] = "univariate_autoregression"
    contract["estimator"] = "target_by_target_full_rank_ols"
    contract["point_semantics"] = "iterated_plugin_conditional_mean"
    contract["density_semantics"] =
        "recursive_target_independent_gaussian_plugin_innovations"
    contract["coefficient_uncertainty"] = false
    contract["covariance_uncertainty"] = false
    contract["cross_target_dependence"] = "none"
    return contract
end

function model_contract(spec::Core3VAR1Spec)
    contract = _common_model_contract(spec)
    contract["family"] = "vector_autoregression"
    contract["estimator"] = "joint_full_rank_ols"
    contract["point_semantics"] = "iterated_plugin_conditional_mean"
    contract["density_semantics"] =
        "recursive_joint_gaussian_plugin_innovations"
    contract["innovation_covariance"] =
        "ols_residual_sum_of_squares_over_residual_degrees_of_freedom"
    contract["covariance_factorization"] = "exact_cholesky_no_jitter"
    contract["coefficient_uncertainty"] = false
    contract["covariance_uncertainty"] = false
    contract["cross_target_dependence"] = "full_innovation_covariance"
    return contract
end

function model_contract(spec::Core3BVAR1Spec)
    contract = _common_model_contract(spec)
    contract["family"] = "natural_conjugate_bayesian_var"
    contract["estimator"] = "analytic_matrix_normal_inverse_wishart_update"
    contract["prior_family"] = "matrix_normal_inverse_wishart"
    contract["prior_version"] = "core3_stationary_mniw_v1"
    contract["prior_hyperparameters"] = Dict{String, Any}(
        "tightness" => BVAR_TIGHTNESS,
        "lag_decay" => BVAR_LAG_DECAY,
        "own_lag_mean" => BVAR_OWN_LAG_MEAN,
        "intercept_variance" => BVAR_INTERCEPT_VARIANCE,
        "inverse_wishart_dof_offset" => BVAR_IW_DOF_OFFSET,
        "innovation_scale" => BVAR_INNOVATION_SCALE,
        "training_scale_floor" => BVAR_SCALE_FLOOR,
        "training_scale_rule" =>
            "max(mean_squared_first_difference,training_scale_floor)",
    )
    contract["hyperparameter_selection"] = "none_fixed_before_origin"
    contract["stationarity_semantics"] =
        "zero_own_lag_prior_center_for_stationary_transformed_observables"
    contract["stability_enforcement"] = false
    contract["unstable_draw_truncation"] = false
    contract["point_semantics"] =
        "iterated_posterior_coefficient_mean_plugin_not_multistep_posterior_mean"
    contract["density_semantics"] =
        "one_covariance_and_conditional_coefficient_draw_per_recursive_path_plus_joint_future_innovations"
    contract["coefficient_uncertainty"] = true
    contract["covariance_uncertainty"] = true
    contract["cross_target_dependence"] = "full_drawn_innovation_covariance"
    return contract
end

model_contract(::AbstractCore3Spec) =
    fail(:unknown_model, "unsupported core-three specification")

function model_contract_sha256(spec::AbstractCore3Spec)
    digest = canonical_sha256(model_contract(spec))
    expected = get(EXPECTED_MODEL_CONTRACT_SHA256, model_id(spec), nothing)
    expected === nothing &&
        fail(:unknown_model, "model contract has no frozen identity")
    digest == expected ||
        fail(:model_hash_mismatch, "model contract SHA-256 changed")
    return digest
end

function _validate_draw_count(n_draws)
    n_draws isa Integer && !(n_draws isa Bool) ||
        fail(:invalid_draw_count, "n_draws must be an integer")
    0 <= n_draws <= MAXIMUM_DRAWS ||
        fail(:invalid_draw_count, "n_draws must lie in 0:$MAXIMUM_DRAWS")
    return Int(n_draws)
end

function _validate_seed(seed)
    seed isa Integer && !(seed isa Bool) ||
        fail(:invalid_seed, "seed must be an integer")
    0 <= seed <= typemax(Int) ||
        fail(:invalid_seed, "seed must be a nonnegative Int")
    return Int(seed)
end

function _path_rng(model_domain, seed, draw_index)
    digest = canonical_sha256(
        Dict{String, Any}(
            "contract_id" => CONTRACT_ID,
            "model_domain" => model_domain,
            "seed" => seed,
            "draw_index" => draw_index,
        ),
    )
    raw_seed = parse(UInt64, digest[1:16]; base = 16)
    path_seed = Int(raw_seed % UInt64(typemax(Int)))
    return MersenneTwister(path_seed)
end

function _numerical_rank(matrix)
    values = svdvals(Matrix{Float64}(matrix))
    isempty(values) && return 0, 0.0
    tolerance = max(size(matrix)...) * eps(Float64) * maximum(values)
    return count(>(tolerance), values), tolerance
end

function _require_full_rank(matrix, location)
    numerical_rank, tolerance = _numerical_rank(matrix)
    expected = size(matrix, 2)
    numerical_rank == expected ||
        fail(
        :rank_deficient,
        "$location rank is $numerical_rank; expected $expected at tolerance $tolerance",
    )
    return numerical_rank, tolerance
end

function _lag1_design(training)
    observations, variables = size(training)
    observations > 2 || fail(:insufficient_training, "lag-one fit is too short")
    design = Matrix{Float64}(undef, observations - 1, variables + 1)
    design[:, 1] .= 1.0
    design[:, 2:end] .= training[1:(end - 1), :]
    response = copy(training[2:end, :])
    return design, response
end

function _fit_ar1(training)
    observations, variables = size(training)
    response_rows = observations - 1
    coefficients = Matrix{Float64}(undef, 2, variables)
    variances = Vector{Float64}(undef, variables)
    ranks = Vector{Int}(undef, variables)
    tolerances = Vector{Float64}(undef, variables)
    for variable in 1:variables
        design = hcat(ones(response_rows), training[1:(end - 1), variable])
        response = training[2:end, variable]
        rank_value, tolerance =
            _require_full_rank(design, "AR target $(TARGET_NAMES[variable]) design")
        response_rows > size(design, 2) ||
            fail(:insufficient_training, "AR fit has no residual degrees of freedom")
        fitted = design \ response
        residuals = response - design * fitted
        degrees_of_freedom = response_rows - size(design, 2)
        variance = sum(abs2, residuals) / degrees_of_freedom
        minimum_variance =
            100 * eps(Float64) * max(mean(abs2, response), 1.0)
        isfinite(variance) && variance > minimum_variance ||
            fail(
            :singular_covariance,
            "AR target $(TARGET_NAMES[variable]) innovation variance is degenerate",
        )
        coefficients[:, variable] .= fitted
        variances[variable] = variance
        ranks[variable] = rank_value
        tolerances[variable] = tolerance
    end
    return (
        coefficients = coefficients,
        innovation_variances = variances,
        design_ranks = ranks,
        rank_tolerances = tolerances,
        response_rows = response_rows,
        residual_degrees_of_freedom = response_rows - 2,
    )
end

function _recursive_ar1(training, fit, horizon, n_draws, seed)
    variables = size(training, 2)
    point = Matrix{Float64}(undef, horizon, variables)
    previous = copy(vec(training[end, :]))
    for step in 1:horizon
        previous = fit.coefficients[1, :] .+
            fit.coefficients[2, :] .* previous
        point[step, :] .= previous
    end
    draws = Array{Float64}(undef, horizon, variables, n_draws)
    scales = sqrt.(fit.innovation_variances)
    for draw in 1:n_draws
        rng = _path_rng(model_id(Core3AR1Spec()), seed, draw)
        previous = copy(vec(training[end, :]))
        for step in 1:horizon
            previous = fit.coefficients[1, :] .+
                fit.coefficients[2, :] .* previous .+
                scales .* randn(rng, variables)
            draws[step, :, draw] .= previous
        end
    end
    return point, draws
end

function _fit_var1(training)
    design, response = _lag1_design(training)
    response_rows, coefficient_rows = size(design)
    response_rows > coefficient_rows ||
        fail(:insufficient_training, "VAR fit has no residual degrees of freedom")
    design_rank, rank_tolerance = _require_full_rank(design, "VAR design")
    coefficients = design \ response
    residuals = response - design * coefficients
    degrees_of_freedom = response_rows - coefficient_rows
    covariance = Matrix(
        Symmetric((residuals' * residuals) / degrees_of_freedom),
    )
    factor = _positive_definite_factor(covariance, "VAR innovation covariance")
    return (
        coefficients = coefficients,
        covariance = covariance,
        covariance_factor = factor.L,
        response_rows = response_rows,
        design_columns = coefficient_rows,
        design_rank = design_rank,
        rank_tolerance = rank_tolerance,
        residual_degrees_of_freedom = degrees_of_freedom,
    )
end

function _recursive_var1(
        training,
        coefficients,
        covariance_factor,
        horizon,
        n_draws,
        seed,
        model_domain,
    )
    variables = size(training, 2)
    point = Matrix{Float64}(undef, horizon, variables)
    previous = copy(vec(training[end, :]))
    for step in 1:horizon
        regressor = [1.0; previous]
        previous = vec(coefficients' * regressor)
        point[step, :] .= previous
    end
    draws = Array{Float64}(undef, horizon, variables, n_draws)
    for draw in 1:n_draws
        rng = _path_rng(model_domain, seed, draw)
        previous = copy(vec(training[end, :]))
        for step in 1:horizon
            regressor = [1.0; previous]
            previous = vec(coefficients' * regressor) +
                covariance_factor * randn(rng, variables)
            draws[step, :, draw] .= previous
        end
    end
    return point, draws
end

function _positive_definite_factor(matrix, location)
    size(matrix, 1) == size(matrix, 2) ||
        fail(:dimension_mismatch, "$location must be square")
    all(isfinite, matrix) ||
        fail(:nonfinite_output, "$location must be finite")
    isapprox(matrix, matrix'; rtol = 1.0e-12, atol = 0.0) ||
        fail(:singular_covariance, "$location must be symmetric")
    return try
        cholesky(Symmetric(matrix))
    catch error
        if error isa PosDefException
            fail(:singular_covariance, "$location must be positive definite")
        end
        rethrow()
    end
end

function _fit_bvar1(training)
    design, response = _lag1_design(training)
    response_rows, coefficient_rows = size(design)
    design_rank, rank_tolerance = _require_full_rank(design, "BVAR design")
    variables = size(training, 2)
    differences = diff(training; dims = 1)
    raw_scale_variances = [
        mean(abs2, view(differences, :, variable)) for
            variable in 1:variables
    ]
    all(isfinite, raw_scale_variances) ||
        fail(:nonfinite_input, "BVAR training scales are nonfinite")
    scale_variances = max.(raw_scale_variances, BVAR_SCALE_FLOOR)
    prior_mean = zeros(coefficient_rows, variables)
    prior_variances = Vector{Float64}(undef, coefficient_rows)
    prior_variances[1] = BVAR_INTERCEPT_VARIANCE
    for predictor in 1:variables
        row = predictor + 1
        prior_variances[row] =
            BVAR_TIGHTNESS^2 /
            (1.0^(2 * BVAR_LAG_DECAY) * scale_variances[predictor])
        prior_mean[row, predictor] = BVAR_OWN_LAG_MEAN
    end
    prior_precision = Matrix(Diagonal(1.0 ./ prior_variances))
    prior_dof = variables + BVAR_IW_DOF_OFFSET
    prior_scale = Matrix(
        Diagonal(
            (BVAR_IW_DOF_OFFSET - 1) *
                BVAR_INNOVATION_SCALE .* scale_variances,
        ),
    )
    posterior = _mniw_posterior(
        response,
        design,
        prior_mean,
        prior_precision,
        prior_scale,
        prior_dof,
    )
    return merge(
        posterior,
        (
            design = design,
            response = response,
            design_rank = design_rank,
            rank_tolerance = rank_tolerance,
            raw_scale_variances = raw_scale_variances,
            scale_variances = scale_variances,
            prior_mean = prior_mean,
            prior_precision = prior_precision,
            prior_scale = prior_scale,
            prior_dof = prior_dof,
        ),
    )
end

function _mniw_posterior(
        response,
        design,
        prior_mean,
        prior_precision,
        prior_scale,
        prior_dof,
    )
    observations, variables = size(response)
    coefficients = size(design, 2)
    size(design, 1) == observations ||
        fail(:dimension_mismatch, "MNIW design and response rows differ")
    size(prior_mean) == (coefficients, variables) ||
        fail(:dimension_mismatch, "MNIW prior mean dimensions changed")
    size(prior_precision) == (coefficients, coefficients) ||
        fail(:dimension_mismatch, "MNIW prior precision dimensions changed")
    size(prior_scale) == (variables, variables) ||
        fail(:dimension_mismatch, "MNIW prior scale dimensions changed")
    _positive_definite_factor(prior_precision, "MNIW prior precision")
    _positive_definite_factor(prior_scale, "MNIW prior scale")
    posterior_precision = Matrix(
        Symmetric(prior_precision + design' * design),
    )
    precision_factor =
        _positive_definite_factor(posterior_precision, "MNIW posterior precision")
    row_covariance = precision_factor \
        Matrix{Float64}(I, coefficients, coefficients)
    posterior_mean = precision_factor \
        (prior_precision * prior_mean + design' * response)
    residuals = response - design * posterior_mean
    prior_distance = posterior_mean - prior_mean
    posterior_scale = Matrix(
        Symmetric(
            prior_scale +
                residuals' * residuals +
                prior_distance' * prior_precision * prior_distance,
        ),
    )
    _positive_definite_factor(posterior_scale, "MNIW posterior scale")
    return (
        posterior_mean = posterior_mean,
        posterior_row_covariance = Matrix(Symmetric(row_covariance)),
        posterior_scale = posterior_scale,
        posterior_dof = prior_dof + observations,
    )
end

function _rand_inverse_wishart(rng, scale, degrees_of_freedom)
    variables = size(scale, 1)
    degrees_of_freedom > variables - 1 ||
        fail(:invalid_prior, "inverse-Wishart degrees of freedom are invalid")
    scale_factor = _positive_definite_factor(scale, "inverse-Wishart scale")
    inverse_scale_factor =
        scale_factor.U \ Matrix{Float64}(I, variables, variables)
    normals = randn(rng, variables, degrees_of_freedom)
    precision = Matrix(
        Symmetric(
            inverse_scale_factor * normals * normals' * inverse_scale_factor',
        ),
    )
    precision_factor =
        _positive_definite_factor(precision, "inverse-Wishart precision draw")
    return Matrix(
        Symmetric(
            precision_factor \ Matrix{Float64}(I, variables, variables),
        ),
    )
end

function _recursive_bvar1(training, fit, horizon, n_draws, seed)
    variables = size(training, 2)
    zero_factor = zeros(Float64, variables, variables)
    point, _ = _recursive_var1(
        training,
        fit.posterior_mean,
        zero_factor,
        horizon,
        0,
        seed,
        model_id(Core3BVAR1Spec()),
    )
    draws = Array{Float64}(undef, horizon, variables, n_draws)
    row_factor = _positive_definite_factor(
        fit.posterior_row_covariance,
        "BVAR posterior row covariance",
    ).L
    for draw in 1:n_draws
        rng = _path_rng(model_id(Core3BVAR1Spec()), seed, draw)
        innovation_covariance = _rand_inverse_wishart(
            rng,
            fit.posterior_scale,
            fit.posterior_dof,
        )
        innovation_factor = _positive_definite_factor(
            innovation_covariance,
            "BVAR innovation covariance draw",
        ).L
        coefficient_draw = fit.posterior_mean +
            row_factor *
            randn(rng, size(fit.posterior_mean)) *
            innovation_factor'
        previous = copy(vec(training[end, :]))
        for step in 1:horizon
            regressor = [1.0; previous]
            previous = vec(coefficient_draw' * regressor) +
                innovation_factor * randn(rng, variables)
            draws[step, :, draw] .= previous
        end
    end
    return point, draws
end

function _companion_radius(coefficients)
    transition = Matrix(coefficients[2:end, :]')
    return maximum(abs, eigvals(transition))
end

function _forecast_ar1(sample, n_draws, seed)
    fit = _fit_ar1(sample.y_train)
    point, draws = _recursive_ar1(
        sample.y_train,
        fit,
        length(sample.forecast_keys),
        n_draws,
        seed,
    )
    diagnostics = Dict{String, Any}(
        "estimator" => "target_by_target_full_rank_ols",
        "lags" => 1,
        "intercept" => true,
        "coefficient_matrix_intercept_then_own_lag" => fit.coefficients,
        "innovation_variances" => fit.innovation_variances,
        "design_ranks" => fit.design_ranks,
        "rank_tolerances" => fit.rank_tolerances,
        "training_response_rows" => fit.response_rows,
        "residual_degrees_of_freedom" => fit.residual_degrees_of_freedom,
        "companion_spectral_radius" => maximum(abs, fit.coefficients[2, :]),
        "stable_within_unit_circle" =>
            maximum(abs, fit.coefficients[2, :]) < 1.0,
        "cross_target_dependence" => "none",
        "coefficient_uncertainty_in_draws" => false,
        "covariance_uncertainty_in_draws" => false,
    )
    return point, draws, diagnostics
end

function _forecast_var1(sample, n_draws, seed)
    fit = _fit_var1(sample.y_train)
    point, draws = _recursive_var1(
        sample.y_train,
        fit.coefficients,
        fit.covariance_factor,
        length(sample.forecast_keys),
        n_draws,
        seed,
        model_id(Core3VAR1Spec()),
    )
    radius = _companion_radius(fit.coefficients)
    diagnostics = Dict{String, Any}(
        "estimator" => "joint_full_rank_ols",
        "lags" => 1,
        "intercept" => true,
        "coefficient_matrix_intercept_then_lag_block" => fit.coefficients,
        "innovation_covariance" => fit.covariance,
        "training_response_rows" => fit.response_rows,
        "design_columns" => fit.design_columns,
        "design_rank" => fit.design_rank,
        "rank_tolerance" => fit.rank_tolerance,
        "residual_degrees_of_freedom" => fit.residual_degrees_of_freedom,
        "companion_spectral_radius" => radius,
        "stable_within_unit_circle" => radius < 1.0,
        "cross_target_dependence" => "full_innovation_covariance",
        "coefficient_uncertainty_in_draws" => false,
        "covariance_uncertainty_in_draws" => false,
        "covariance_factorization" => "exact_cholesky_no_jitter",
    )
    return point, draws, diagnostics
end

function _forecast_bvar1(sample, n_draws, seed)
    fit = _fit_bvar1(sample.y_train)
    point, draws = _recursive_bvar1(
        sample.y_train,
        fit,
        length(sample.forecast_keys),
        n_draws,
        seed,
    )
    posterior_innovation_mean = fit.posterior_scale /
        (fit.posterior_dof - length(TARGET_NAMES) - 1)
    radius = _companion_radius(fit.posterior_mean)
    diagnostics = Dict{String, Any}(
        "estimator" => "analytic_matrix_normal_inverse_wishart_update",
        "prior_family" => "matrix_normal_inverse_wishart",
        "prior_version" => "core3_stationary_mniw_v1",
        "lags" => 1,
        "intercept" => true,
        "prior_tightness" => BVAR_TIGHTNESS,
        "prior_lag_decay" => BVAR_LAG_DECAY,
        "prior_own_lag_mean" => BVAR_OWN_LAG_MEAN,
        "prior_intercept_variance" => BVAR_INTERCEPT_VARIANCE,
        "prior_inverse_wishart_dof_offset" => BVAR_IW_DOF_OFFSET,
        "prior_innovation_scale" => BVAR_INNOVATION_SCALE,
        "prior_scale_floor" => BVAR_SCALE_FLOOR,
        "training_raw_scale_variances" => fit.raw_scale_variances,
        "training_scale_variances" => fit.scale_variances,
        "prior_coefficient_mean" => fit.prior_mean,
        "prior_precision_diagonal" => diag(fit.prior_precision),
        "prior_inverse_wishart_scale" => fit.prior_scale,
        "prior_inverse_wishart_dof" => fit.prior_dof,
        "posterior_coefficient_mean" => fit.posterior_mean,
        "posterior_row_covariance" => fit.posterior_row_covariance,
        "posterior_inverse_wishart_scale" => fit.posterior_scale,
        "posterior_inverse_wishart_dof" => fit.posterior_dof,
        "posterior_mean_innovation_covariance" => posterior_innovation_mean,
        "training_response_rows" => size(fit.response, 1),
        "design_columns" => size(fit.design, 2),
        "design_rank" => fit.design_rank,
        "rank_tolerance" => fit.rank_tolerance,
        "companion_spectral_radius" => radius,
        "stable_within_unit_circle" => radius < 1.0,
        "stationarity_semantics" =>
            "zero_own_lag_prior_center_for_stationary_transformed_observables",
        "stability_enforced" => false,
        "unstable_draws_truncated" => false,
        "cross_target_dependence" => "full_drawn_innovation_covariance",
        "coefficient_uncertainty_in_draws" => true,
        "covariance_uncertainty_in_draws" => true,
        "coefficient_draw_frequency" => "once_per_predictive_path",
        "covariance_draw_frequency" => "once_per_predictive_path",
        "point_path_limitation" =>
            "posterior_coefficient_mean_plugin_not_multistep_posterior_mean",
    )
    return point, draws, diagnostics
end

function _validate_output(point, draws, sample, n_draws)
    expected_point = (length(sample.forecast_keys), length(TARGET_NAMES))
    size(point) == expected_point ||
        fail(:dimension_mismatch, "point forecast dimensions changed")
    size(draws) == (expected_point..., n_draws) ||
        fail(:dimension_mismatch, "density draw dimensions changed")
    all(isfinite, point) ||
        fail(:nonfinite_output, "point forecast is nonfinite")
    all(isfinite, draws) ||
        fail(:nonfinite_output, "density draws are nonfinite")
    return nothing
end

function _blockers(information_track)
    common = [
        "NONADMITTING_CORE3_AUTOREGRESSIVE_CANDIDATE",
        "AUTHENTICATED_ORIGIN_RECEIPT_NOT_BOUND",
        "SCORING_AND_ACCURACY_GATES_FALSE",
        "SMALL_NK_ESTIMATED_SUCCESSOR_NOT_AVAILABLE",
    ]
    if information_track == SYNTHETIC_INFORMATION_TRACK
        push!(common, "SYNTHETIC_MECHANICS_INPUT")
    else
        push!(common, "REVISED_MIXED_VINTAGE_DIAGNOSTIC_ONLY")
        push!(common, "HISTORICAL_RELEASE_AVAILABILITY_UNVERIFIED")
    end
    return common
end

function _forecast_payload(forecast::Core3Forecast)
    return Dict{String, Any}(
        "schema_version" => forecast.schema_version,
        "contract_id" => forecast.contract_id,
        "status" => forecast.status,
        "canonicalization" => forecast.canonicalization,
        "target_panel_id" => forecast.target_panel_id,
        "model_id" => forecast.model_id,
        "model_contract_sha256" => forecast.model_contract_sha256,
        "sample_sha256" => forecast.sample_sha256,
        "information_track" => forecast.information_track,
        "origin_id" => forecast.origin_id,
        "origin_key" => forecast.origin_key,
        "training_keys" => forecast.training_keys,
        "forecast_keys" => forecast.forecast_keys,
        "target_names" => forecast.target_names,
        "target_units" => forecast.target_units,
        "point" => forecast.point,
        "draws" => forecast.draws,
        "diagnostics" => forecast.diagnostics,
        "blockers" => forecast.blockers,
        "origin_bound" => forecast.origin_bound,
        "origin_admissible" => forecast.origin_admissible,
        "scoring_eligible" => forecast.scoring_eligible,
        "empirical_accuracy_evidence" => forecast.empirical_accuracy_evidence,
        "forecast_suitability_evidence" =>
            forecast.forecast_suitability_evidence,
        "promotion_eligible" => forecast.promotion_eligible,
        "production_eligible" => forecast.production_eligible,
        "registered_benchmark" => forecast.registered_benchmark,
    )
end

function _make_forecast(spec, sample, point, draws, diagnostics, n_draws, seed)
    diagnostics["seed"] = seed
    diagnostics["n_draws"] = n_draws
    diagnostics["training_rows"] = size(sample.y_train, 1)
    diagnostics["forecast_horizon"] = length(sample.forecast_keys)
    diagnostics["target_order"] = collect(TARGET_NAMES)
    diagnostics["target_units"] = collect(TARGET_UNITS)
    diagnostics["predictive_rng_semantics"] =
        "sha256_domain_separated_mersenne_twister_per_path"
    diagnostics["future_targets_available_to_model"] = false
    diagnostics["exogenous_inputs_available_to_model"] = false
    diagnostics["point_forecast_depends_on_draw_count"] = false
    values = (
        SCHEMA_VERSION,
        CONTRACT_ID,
        STATUS,
        CANONICALIZATION,
        TARGET_PANEL_ID,
        model_id(spec),
        model_contract_sha256(spec),
        sample_sha256(sample),
        sample.information_track,
        sample.origin_id,
        sample.origin_key,
        copy(sample.training_keys),
        copy(sample.forecast_keys),
        copy(sample.target_names),
        copy(sample.target_units),
        point,
        draws,
        diagnostics,
        _blockers(sample.information_track),
        false,
        false,
        false,
        false,
        false,
        false,
        false,
        false,
    )
    unstamped = Core3Forecast(values..., repeat("0", 64))
    return Core3Forecast(values..., canonical_sha256(_forecast_payload(unstamped)))
end

function _execute_core3(spec::AbstractCore3Spec, sample::Core3Sample, n_draws, seed)
    _validate_sample(sample)
    draw_count = _validate_draw_count(n_draws)
    rng_seed = _validate_seed(seed)
    model_contract_sha256(spec)
    point, draws, diagnostics = if spec isa Core3AR1Spec
        _forecast_ar1(sample, draw_count, rng_seed)
    elseif spec isa Core3VAR1Spec
        _forecast_var1(sample, draw_count, rng_seed)
    elseif spec isa Core3BVAR1Spec
        _forecast_bvar1(sample, draw_count, rng_seed)
    else
        fail(:unknown_model, "unsupported core-three specification")
    end
    _validate_output(point, draws, sample, draw_count)
    return _make_forecast(
        spec,
        sample,
        point,
        draws,
        diagnostics,
        draw_count,
        rng_seed,
    )
end

"""Run one nonadmitting core-three benchmark with a structured failure envelope."""
function run_core3_benchmark(
        spec::AbstractCore3Spec,
        sample::Core3Sample;
        n_draws = 0,
        seed = 0,
    )
    try
        forecast = _execute_core3(spec, sample, n_draws, seed)
        return Core3Run(:ok, model_id(spec), sample.origin_id, forecast, nothing)
    catch error
        code = error isa Core3BenchmarkError ?
            error.code :
            error isa DimensionMismatch ?
            :dimension_mismatch :
            error isa PosDefException || error isa SingularException ?
            :estimation_failure : :execution_failure
        failure = Core3Failure(
            code,
            string(typeof(error)),
            sprint(showerror, error),
        )
        return Core3Run(:failed, model_id(spec), sample.origin_id, nothing, failure)
    end
end

"""Run the frozen AR(1), VAR(1), and BVAR(1) set on one identical sample."""
function run_core3_family(sample::Core3Sample; n_draws = 0, seed = 0)
    expected_ids = [
        "nk3_aggregate_pce_univariate_ar1_ols_v1",
        "nk3_aggregate_pce_var1_ols_v1",
        "nk3_aggregate_pce_bvar1_mniw_stationary_v1",
    ]
    specs = default_core3_specs()
    model_id.(specs) == expected_ids ||
        fail(:model_set_changed, "default core-three model set changed")
    return [
        run_core3_benchmark(spec, sample; n_draws = n_draws, seed = seed) for
            spec in specs
    ]
end

"""
    validate_forecast(forecast, spec, sample)

Validate the content hash and independently rerun the deterministic local
mechanics from the bound sample, seed, and draw count. This is reproducibility,
not authentication or origin admission.
"""
function validate_forecast(
        forecast::Core3Forecast,
        spec::AbstractCore3Spec,
        sample::Core3Sample,
    )
    _validate_sample(sample)
    _expect_hash(forecast.content_sha256, "forecast.content_sha256")
    canonical_sha256(_forecast_payload(forecast)) == forecast.content_sha256 ||
        fail(:content_hash_mismatch, "forecast content SHA-256 changed")
    forecast.schema_version == SCHEMA_VERSION ||
        fail(:invalid_schema, "forecast schema version changed")
    forecast.contract_id == CONTRACT_ID ||
        fail(:invalid_schema, "forecast contract identity changed")
    forecast.status == STATUS || fail(:invalid_status, "forecast status changed")
    forecast.target_panel_id == TARGET_PANEL_ID ||
        fail(:target_contract_mismatch, "forecast target panel changed")
    forecast.model_id == model_id(spec) ||
        fail(:model_hash_mismatch, "forecast model identity changed")
    forecast.model_contract_sha256 == model_contract_sha256(spec) ||
        fail(:model_hash_mismatch, "forecast model hash changed")
    forecast.sample_sha256 == sample_sha256(sample) ||
        fail(:sample_hash_mismatch, "forecast sample hash changed")
    forecast.target_names == collect(TARGET_NAMES) ||
        fail(:target_contract_mismatch, "forecast target order changed")
    forecast.target_units == collect(TARGET_UNITS) ||
        fail(:target_contract_mismatch, "forecast target units changed")
    all(
        value -> value === false,
        (
            forecast.origin_bound,
            forecast.origin_admissible,
            forecast.scoring_eligible,
            forecast.empirical_accuracy_evidence,
            forecast.forecast_suitability_evidence,
            forecast.promotion_eligible,
            forecast.production_eligible,
            forecast.registered_benchmark,
        ),
    ) || fail(:gate_elevation, "a nonadmitting forecast gate was elevated")
    draw_count = get(forecast.diagnostics, "n_draws", nothing)
    seed = get(forecast.diagnostics, "seed", nothing)
    expected = _execute_core3(spec, sample, draw_count, seed)
    expected.content_sha256 == forecast.content_sha256 ||
        fail(:replay_mismatch, "forecast does not rederive from sample and model")
    return forecast
end

end # module
