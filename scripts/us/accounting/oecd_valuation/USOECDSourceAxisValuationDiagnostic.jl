module USOECDSourceAxisValuationDiagnostic

using CSV
using JSON
using SHA
using TOML

export AxisCode,
    ComponentObservation,
    CrossSourceResidual,
    OECDSourceAxisValuationReport,
    ObservedValuationSidecar,
    SourceAxisCell,
    SourceAxisKey,
    SourceIdentityEvaluation,
    SourceObservationSemantics,
    SourceTotal,
    TaxDiagnosticCandidate,
    SOURCE_EXPLICIT_ZERO,
    SOURCE_MISSING,
    SOURCE_OBSERVED_NONZERO,
    additive_value,
    candidate_specification_sha256,
    load_oecd_source_axis_valuation_diagnostic,
    replace_component_value,
    request_mapping_or_allocation,
    source_observation_semantics,
    source_total,
    validate_candidate_records,
    validate_source_axis_cells

@enum SourceObservationSemantics begin
    SOURCE_MISSING
    SOURCE_EXPLICIT_ZERO
    SOURCE_OBSERVED_NONZERO
end

const CONTRACT_SCHEMA =
    "beforeit-us-oecd-sut-source-axis-valuation-diagnostic.v2"
const FIXTURE_SCHEMA =
    "beforeit-us-oecd-sut-source-axis-valuation-fixture.v2"
const EXPECTED_CLASSIFICATION =
    "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE"
const EXPECTED_PROMOTION_STATUS = "RESEARCH_ONLY_NOT_PROMOTED"
const APPROVED_CONTRACT_SHA256 =
    "aaddffcf1418299b8350add0dd81950cb2deaf1343e467decc37b009a4cd43f3"
const APPROVED_GENERATOR_SHA256 =
    "e6690b200017f9b2c06cb1f9cc3fd210b73a1b1552902c03d8baac3603be6fde"
const APPROVED_PROJECT_SHA256 =
    "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
const APPROVED_JULIA_MANIFEST_SHA256 =
    "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
const APPROVED_FIXTURE_MANIFEST_SHA256 =
    "62a1f77cc89d1ba735d1ba9e366ff553e132f741de8cac19b42b419247b8367a"
const APPROVED_CELLS_SHA256 =
    "25531db1941cbc00dc8294e31322cc5c425a4ff0365d0f517850a3538176b5a4"
const APPROVED_IDENTITY_EVALUATIONS_SHA256 =
    "30a1dcce1f87283b051bec4ea1e5ea1e5944deb721773463f6d3fb6c15fa3e8e"
const APPROVED_AXIS_CODES_SHA256 =
    "29d56d85154e9bb9317f999576869ea071cd1ca8858baa81c8921d52b6da52f6"
const APPROVED_SOURCE_TOTALS_SHA256 =
    "e10c53d53148005cdf0fc8c396f19bf911bd48ea93b9a21843c6dd72d94f537f"
const APPROVED_NONBASIC_QUARANTINE_SHA256 =
    "3691a589f1678e4aa19f4db0ab9b0545aa7dfc128983a54e9d2df85f1fc7fdc4"
const APPROVED_SOURCE_RECEIPTS_SHA256 =
    "695b683fd6709b9e5cf4225999773bdc5ecb0b4f7bb1a6dec956cba7fa88b083"
const APPROVED_SOURCE_BUNDLE_SHA256 =
    "b202aa776874eb712a207f9be6f312a12c5d73ed367db881c32f7bb81936a1f7"
const APPROVED_BEA_FIXTURE_SHA256 =
    "c4461fbe971d8fb70750ff4cce6bb09e582a024d7cc1f6e8ebd8e3685bab69e0"
const APPROVED_BEA_MANIFEST_SHA256 =
    "564a99ec2011b2566b8951e9eecb4737c0bfbc88f1e077b1eaf596af9894575c"
const EXPECTED_SOURCE_RESPONSE_COUNT = 25
const EXPECTED_SOURCE_AXIS_CELL_COUNT = 10_675
const EXPECTED_AXIS_CODE_COUNT = 245
const EXPECTED_NONBASIC_QUARANTINE_COUNT = 245
const EXPECTED_VALUATION_IDENTITY_EVALUATED_COUNT = 4_226
const EXPECTED_VALUATION_IDENTITY_NOT_EVALUABLE_COUNT = 6_449
const EXPECTED_TAX_IDENTITY_EVALUATED_COUNT = 1_257
const EXPECTED_TAX_IDENTITY_NOT_EVALUABLE_COUNT = 9_418
const EXPECTED_EXPLICIT_ZERO_COUNTS = Dict(
    :purchasers => 111,
    :basic => 14,
    :combined_margin => 137,
    :net_product_tax => 246,
    :gross_product_tax => 177,
    :subsidy_magnitude => 123,
)
const EXPECTED_MISSING_COUNTS = Dict(
    :purchasers => 180,
    :basic => 2,
    :combined_margin => 6_175,
    :net_product_tax => 952,
    :gross_product_tax => 1_120,
    :subsidy_magnitude => 9_250,
)
const COMPONENTS = (
    :purchasers,
    :basic,
    :combined_margin,
    :net_product_tax,
    :gross_product_tax,
    :subsidy_magnitude,
)
const TABLE_COMPONENTS = Dict(
    "T1600" => :purchasers,
    "T1610" => :basic,
    "T1620" => :combined_margin,
    "T1630" => :net_product_tax,
    "T1633" => :gross_product_tax,
    "T1634" => :subsidy_magnitude,
)
const CANDIDATE_SPECIFICATION_FIELDS = (
    "id",
    "tax_mode",
    "tax_source_axis_policy",
    "dynamic_net_product_tax_total_hundredths_million_usd",
    "allocation_applied",
    "observed_sidecar_sha256",
    "fiscal_receipt_status",
    "margin_split_status",
    "model_mapping_status",
    "model_state_write",
    "accounting_gate_effect",
    "forecast_origin_admissible",
    "forecast_score_effect",
)
const EXPECTED_PROHIBITED_OPERATIONS = Set(
    [
        "AGGREGATE_AND_DESCENDANT_DOUBLE_COUNT",
        "PROPORTIONAL_ALLOCATION",
        "LABEL_PERMUTATION",
        "SIGN_REVERSAL",
        "COMPENSATED_CELL_SWAP",
        "USED_OR_OTHER_ABSORPTION",
        "SAME_ID_DIFFERENT_SPECIFICATION",
    ]
)

const REPOSITORY_ROOT =
    normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const DEFAULT_CONTRACT_PATH =
    joinpath(@__DIR__, "oecd_source_axis_valuation.toml")
const DEFAULT_GENERATOR_PATH =
    joinpath(@__DIR__, "generate_oecd_source_axis_fixture.py")
const DEFAULT_FIXTURE_DIRECTORY =
    joinpath(@__DIR__, "fixtures", "oecd_sut_usa_2024_v2")
const DEFAULT_RAW_DIRECTORY =
    joinpath(@__DIR__, "raw", "oecd_sut_usa_2024_v2")
const DEFAULT_BEA_FIXTURE_DIRECTORY =
    normpath(joinpath(@__DIR__, "..", "fixtures", "bea_2024_approved"))
const DEFAULT_PROJECT_PATH =
    normpath(joinpath(@__DIR__, "..", "..", "Project.toml"))
const DEFAULT_JULIA_MANIFEST_PATH =
    normpath(joinpath(@__DIR__, "..", "..", "Manifest.toml"))

struct SourceAxisKey
    transaction::String
    activity::String
    product::String
    counterpart_area::String
    sector::String
    accounting_entry::String
end

struct ComponentObservation
    present::Bool
    value_hundredths_million_usd::Union{Missing, Int64}
    obs_status::Union{Missing, String}
end

struct SourceAxisCell
    index::Int
    key::SourceAxisKey
    recipient_type::Symbol
    transaction_axis_role::Symbol
    activity_axis_role::Symbol
    product_axis_role::Symbol
    unit_measure::String
    unit_mult::String
    currency::String
    decimals::String
    obs_status::String
    purchasers::ComponentObservation
    basic::ComponentObservation
    combined_margin::ComponentObservation
    net_product_tax::ComponentObservation
    gross_product_tax::ComponentObservation
    subsidy_magnitude::ComponentObservation
end

struct AxisCode
    axis::Symbol
    code::String
    label::String
    parent_code::Union{Nothing, String}
    depth::Union{Nothing, Int}
    child_count::Union{Nothing, Int}
    is_hierarchy_leaf::Union{Nothing, Bool}
    axis_role::Symbol
end

struct SourceTotal
    table_identifier::String
    component::Symbol
    value_hundredths_million_usd::Int64
    obs_status::String
    aggregation_policy::Symbol
end

"""
One fail-closed evaluation of a published source-axis identity.

A source tuple is evaluated only when every required component is an
observation in the archived response.  An absent component produces
`status == :NOT_EVALUABLE_SOURCE_MISSING`, a `missing` residual, and an
explicit list of absent components.  Source absence is never interpreted as
an additive zero.
"""
struct SourceIdentityEvaluation
    cell_index::Int
    identity::Symbol
    residual_hundredths_million_usd::Union{Missing, Int64}
    status::Symbol
    missing_components::Vector{Symbol}
end

"""
Typed cross-source comparison retained without balancing.

`status == :DUBIOUS_CROSS_SOURCE_RELEASE_BOUNDARY_RESIDUAL` means that the
OECD and BEA values differ but their release identity and exact source scope
have not been established.
`status == :DUBIOUS_OUTSIDE_DERIVED_CROSS_SOURCE_ROUNDING_BOUND` means that
the residual exceeds one half of the sum of the resolutions of the exact
published terms in the comparison.  The exact half-unit bound is stored as
twice the number of hundredths of a million dollars, avoiding a floating-point
or integer-rounding approximation.  `balance_action` is always
`:retain_unadjusted`.
"""
struct CrossSourceResidual
    component::Symbol
    oecd_value_hundredths_million_usd::Int64
    bea_value_hundredths_million_usd::Int64
    residual_hundredths_million_usd::Int64
    oecd_term_codes::Vector{String}
    oecd_term_count::Int
    oecd_term_resolution_hundredths_million_usd::Int64
    bea_term_codes::Vector{String}
    bea_term_count::Int
    bea_term_resolution_hundredths_million_usd::Int64
    rounding_bound_twice_hundredths_million_usd::Int64
    status::Symbol
    boundary_type::Symbol
    balance_action::Symbol
end

"""
Immutable description of the observed OECD valuation sidecar.

The sidecar contains only source hashes and published controls.  The zero-tax
candidate refers to this same immutable observed record; it does not rewrite
or zero the archived observations.
"""
struct ObservedValuationSidecar
    fixture_cells_sha256::String
    combined_margin_total_hundredths_million_usd::Int64
    net_product_tax_total_hundredths_million_usd::Int64
    gross_product_tax_total_hundredths_million_usd::Int64
    subsidy_magnitude_total_hundredths_million_usd::Int64
    obs_status::String
end

struct TaxDiagnosticCandidate
    id::String
    tax_mode::Symbol
    tax_source_axis_policy::Symbol
    dynamic_net_product_tax_total_hundredths_million_usd::Int64
    allocation_applied::Bool
    observed_sidecar::ObservedValuationSidecar
    fiscal_receipt_status::Symbol
    margin_split_status::Symbol
    model_mapping_status::Symbol
    model_state_write::Bool
    accounting_gate_effect::Symbol
    forecast_origin_admissible::Bool
    forecast_score_effect::Symbol
    specification_sha256::String
end

struct OECDSourceAxisValuationReport
    year::Int
    classification::String
    cells::Vector{SourceAxisCell}
    axis_codes::Vector{AxisCode}
    source_totals::Dict{Symbol, SourceTotal}
    valuation_identity_residuals_hundredths_million_usd::Vector{Int64}
    tax_identity_residuals_hundredths_million_usd::Vector{Int64}
    valuation_identity_evaluations::Vector{SourceIdentityEvaluation}
    tax_identity_evaluations::Vector{SourceIdentityEvaluation}
    cross_source_residuals::Vector{CrossSourceResidual}
    observed_sidecar::ObservedValuationSidecar
    tax_candidates::Vector{TaxDiagnosticCandidate}
    contract_sha256::String
    generator_sha256::String
    fixture_manifest_sha256::String
    fixture_cells_sha256::String
    fixture_identity_evaluations_sha256::String
    fixture_axis_codes_sha256::String
    fixture_source_totals_sha256::String
    fixture_nonbasic_quarantine_sha256::String
    fixture_source_receipts_sha256::String
    source_bundle_sha256::String
    project_sha256::String
    julia_manifest_sha256::String
    bea_fixture_sha256::String
    bea_manifest_sha256::String
    combined_margin_split_status::Symbol
    cpa_isic_to_bea_mapping_status::Symbol
    cpa_isic_to_model_mapping_status::Symbol
    model_state_write::Bool
    accounting_gate_effect::Symbol
    forecast_origin_admissible::Bool
    forecast_score_effect::Symbol
    promotion_blockers::Vector{String}
    prohibited_operations::Set{String}
    promotion_ready::Bool
end

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))
sha256_file(path) = sha256_hex(read(path))

function source_observation_semantics(observation::ComponentObservation)
    if !observation.present
        return SOURCE_MISSING
    elseif observation.value_hundredths_million_usd == 0
        return SOURCE_EXPLICIT_ZERO
    end
    return SOURCE_OBSERVED_NONZERO
end

function additive_value(observation::ComponentObservation)
    observation.present ||
        throw(
        ArgumentError(
            "SOURCE_MISSING has no additive value; the source tuple is " *
                "NOT_EVALUABLE_SOURCE_MISSING",
        ),
    )
    return something(observation.value_hundredths_million_usd)
end

function component_observation(row, component::Symbol)
    present_field = Symbol(component, "_present")
    value_field =
        Symbol(component, "_value_hundredths_million_usd")
    status_field = Symbol(component, "_obs_status")
    present = Int(getproperty(row, present_field)) == 1
    raw_value = getproperty(row, value_field)
    raw_status = getproperty(row, status_field)
    if present
        ismissing(raw_value) &&
            throw(ArgumentError("$component is present but has no value"))
        ismissing(raw_status) &&
            throw(ArgumentError("$component is present but has no status"))
        status = String(raw_status)
        status == "A" ||
            throw(ArgumentError("$component observation status is not A"))
        return ComponentObservation(true, Int64(raw_value), status)
    end
    ismissing(raw_value) ||
        throw(ArgumentError("$component is missing but retains a value"))
    ismissing(raw_status) ||
        throw(ArgumentError("$component is missing but retains a status"))
    return ComponentObservation(false, missing, missing)
end

function load_cells(path)
    cells = SourceAxisCell[]
    for row in CSV.File(path)
        push!(
            cells,
            SourceAxisCell(
                Int(row.cell_index),
                SourceAxisKey(
                    String(row.transaction),
                    String(row.activity),
                    String(row.product),
                    String(row.counterpart_area),
                    String(row.sector),
                    String(row.accounting_entry),
                ),
                Symbol(row.recipient_type),
                Symbol(row.transaction_axis_role),
                Symbol(row.activity_axis_role),
                Symbol(row.product_axis_role),
                String(row.unit_measure),
                string(row.unit_mult),
                String(row.currency),
                string(row.decimals),
                String(row.obs_status),
                component_observation(row, :purchasers),
                component_observation(row, :basic),
                component_observation(row, :combined_margin),
                component_observation(row, :net_product_tax),
                component_observation(row, :gross_product_tax),
                component_observation(row, :subsidy_magnitude),
            ),
        )
    end
    return cells
end

optional_string(value) = ismissing(value) ? nothing : String(value)
optional_int(value) = ismissing(value) ? nothing : Int(value)
optional_bool(value) = ismissing(value) ? nothing : Int(value) == 1

function load_axis_codes(path)
    return [
        AxisCode(
                Symbol(row.axis),
                String(row.code),
                String(row.label),
                optional_string(row.parent_code),
                optional_int(row.depth),
                optional_int(row.child_count),
                optional_bool(row.is_hierarchy_leaf),
                Symbol(row.axis_role),
            ) for row in CSV.File(path)
    ]
end

function load_source_totals(path)
    totals = Dict{Symbol, SourceTotal}()
    for row in CSV.File(path)
        component = Symbol(row.component)
        haskey(totals, component) &&
            throw(ArgumentError("duplicate source total for $component"))
        totals[component] = SourceTotal(
            String(row.table_identifier),
            component,
            Int64(row.value_hundredths_million_usd),
            String(row.obs_status),
            Symbol(row.aggregation_policy),
        )
    end
    return totals
end

function load_identity_evaluations(path)
    evaluations = SourceIdentityEvaluation[]
    for row in CSV.File(path)
        status = Symbol(row.status)
        residual = row.residual_hundredths_million_usd
        missing_components = ismissing(row.missing_components) ?
            Symbol[] :
            Symbol.(split(String(row.missing_components), ';'))
        if status == :PASS_AT_SOURCE_ROUNDING
            ismissing(residual) &&
                throw(ArgumentError("evaluated identity has no residual"))
            isempty(missing_components) ||
                throw(
                ArgumentError(
                    "evaluated identity lists missing components",
                ),
            )
        elseif status == :NOT_EVALUABLE_SOURCE_MISSING
            ismissing(residual) ||
                throw(
                ArgumentError(
                    "source-missing identity has a numeric residual",
                ),
            )
            isempty(missing_components) &&
                throw(
                ArgumentError(
                    "source-missing identity omits missing components",
                ),
            )
        else
            throw(ArgumentError("unknown source identity status $status"))
        end
        push!(
            evaluations,
            SourceIdentityEvaluation(
                Int(row.cell_index),
                Symbol(row.identity),
                ismissing(residual) ? missing : Int64(residual),
                status,
                missing_components,
            ),
        )
    end
    return evaluations
end

identity_evaluation_signature(evaluation::SourceIdentityEvaluation) = (
    evaluation.cell_index,
    evaluation.identity,
    evaluation.residual_hundredths_million_usd,
    evaluation.status,
    Tuple(evaluation.missing_components),
)

cell_key_tuple(key::SourceAxisKey) = (
    key.transaction,
    key.activity,
    key.product,
    key.counterpart_area,
    key.sector,
    key.accounting_entry,
)

function observation(cell::SourceAxisCell, component::Symbol)
    component in COMPONENTS ||
        throw(ArgumentError("unknown valuation component $component"))
    return getfield(cell, component)
end

function expected_recipient_type(key::SourceAxisKey)
    if key.transaction == "TU"
        return :total_use
    elseif key.transaction == "P2" && key.activity == "_T"
        return :intermediate_use_total
    elseif key.transaction == "P2"
        return :industry_intermediate_use
    elseif key.activity == "_Z"
        return :final_use
    end
    throw(
        ArgumentError(
            "final-use transaction $(key.transaction) has activity " *
                key.activity,
        ),
    )
end

function evaluate_source_identity(
        cell::SourceAxisCell,
        identity::Symbol,
        components::Tuple,
        residual_function,
        rounding_tolerance_hundredths_million_usd::Int,
    )
    missing_components = Symbol[
        component for component in components if
            !observation(cell, component).present
    ]
    if !isempty(missing_components)
        return SourceIdentityEvaluation(
            cell.index,
            identity,
            missing,
            :NOT_EVALUABLE_SOURCE_MISSING,
            missing_components,
        )
    end
    values = Dict(
        component => additive_value(observation(cell, component)) for
            component in components
    )
    residual = residual_function(values)
    abs(residual) <= rounding_tolerance_hundredths_million_usd ||
        throw(
        ArgumentError(
            "cellwise $identity failed at cell $(cell.index): " *
                "residual $residual",
        ),
    )
    return SourceIdentityEvaluation(
        cell.index,
        identity,
        residual,
        :PASS_AT_SOURCE_ROUNDING,
        Symbol[],
    )
end

function validate_source_axis_cells(
        cells::Vector{SourceAxisCell};
        rounding_tolerance_hundredths_million_usd::Int = 1,
        expected_count::Union{Nothing, Int} = nothing,
        enforce_approved_semantics_counts::Bool = false,
    )
    expected_count === nothing ||
        length(cells) == expected_count ||
        throw(
        ArgumentError(
            "source-axis cell count $(length(cells)) != $expected_count",
        ),
    )
    [cell.index for cell in cells] == collect(1:length(cells)) ||
        throw(ArgumentError("source-axis cell index is not canonical"))
    keys = [cell_key_tuple(cell.key) for cell in cells]
    length(Set(keys)) == length(keys) ||
        throw(ArgumentError("duplicate source-axis key"))

    valuation_evaluations = SourceIdentityEvaluation[]
    tax_evaluations = SourceIdentityEvaluation[]
    explicit_zero_counts = Dict(component => 0 for component in COMPONENTS)
    missing_counts = Dict(component => 0 for component in COMPONENTS)
    for cell in cells
        any(
            code in ("Used", "Other") for
                code in (
                    cell.key.transaction,
                    cell.key.activity,
                    cell.key.product,
                )
        ) &&
            throw(
            ArgumentError(
                "Used/Other absorption is forbidden on OECD source axes",
            ),
        )
        cell.recipient_type == expected_recipient_type(cell.key) ||
            throw(ArgumentError("recipient type changed"))
        cell.unit_measure == "XDC" ||
            throw(ArgumentError("unit measure changed"))
        cell.unit_mult == "6" ||
            throw(ArgumentError("unit multiplier changed"))
        cell.currency == "USD" ||
            throw(ArgumentError("currency changed"))
        cell.decimals == "2" ||
            throw(ArgumentError("source decimals changed"))
        cell.obs_status == "A" ||
            throw(ArgumentError("source observation status changed"))
        for component in COMPONENTS
            item = observation(cell, component)
            if item.present
                ismissing(item.value_hundredths_million_usd) &&
                    throw(ArgumentError("present component lost its value"))
                item.obs_status == "A" ||
                    throw(ArgumentError("present component status changed"))
            else
                ismissing(item.value_hundredths_million_usd) ||
                    throw(
                    ArgumentError(
                        "missing component was reclassified as zero",
                    ),
                )
                ismissing(item.obs_status) ||
                    throw(ArgumentError("missing component retained status"))
            end
            semantics = source_observation_semantics(item)
            semantics == SOURCE_EXPLICIT_ZERO &&
                (explicit_zero_counts[component] += 1)
            semantics == SOURCE_MISSING &&
                (missing_counts[component] += 1)
        end

        push!(
            valuation_evaluations,
            evaluate_source_identity(
                cell,
                :purchasers_equals_basic_plus_margin_plus_net_tax,
                (
                    :purchasers,
                    :basic,
                    :combined_margin,
                    :net_product_tax,
                ),
                values ->
                values[:purchasers] -
                    values[:basic] -
                    values[:combined_margin] -
                    values[:net_product_tax],
                rounding_tolerance_hundredths_million_usd,
            ),
        )

        push!(
            tax_evaluations,
            evaluate_source_identity(
                cell,
                :net_tax_equals_gross_tax_minus_subsidy,
                (
                    :net_product_tax,
                    :gross_product_tax,
                    :subsidy_magnitude,
                ),
                values ->
                values[:net_product_tax] -
                    values[:gross_product_tax] +
                    values[:subsidy_magnitude],
                rounding_tolerance_hundredths_million_usd,
            ),
        )
    end
    if enforce_approved_semantics_counts
        explicit_zero_counts == EXPECTED_EXPLICIT_ZERO_COUNTS ||
            throw(
            ArgumentError(
                "explicit-zero semantics counts changed: " *
                    string(explicit_zero_counts),
            ),
        )
        missing_counts == EXPECTED_MISSING_COUNTS ||
            throw(
            ArgumentError(
                "missing-observation semantics counts changed: " *
                    string(missing_counts),
            ),
        )
    end
    valuation_residuals = Int64[
        something(evaluation.residual_hundredths_million_usd) for
            evaluation in valuation_evaluations if
            evaluation.status == :PASS_AT_SOURCE_ROUNDING
    ]
    tax_residuals = Int64[
        something(evaluation.residual_hundredths_million_usd) for
            evaluation in tax_evaluations if
            evaluation.status == :PASS_AT_SOURCE_ROUNDING
    ]
    return (;
        valuation_residuals,
        tax_residuals,
        valuation_evaluations,
        tax_evaluations,
        explicit_zero_counts,
        missing_counts,
        maximum_valuation_residual = maximum(abs, valuation_residuals),
        maximum_tax_residual = maximum(abs, tax_residuals),
    )
end

function validate_axis_codes(
        axis_codes::Vector{AxisCode},
        cells::Vector{SourceAxisCell},
    )
    length(axis_codes) == EXPECTED_AXIS_CODE_COUNT ||
        throw(ArgumentError("axis code count changed"))
    keyed = Dict{Tuple{Symbol, String}, AxisCode}()
    for code in axis_codes
        key = (code.axis, code.code)
        haskey(keyed, key) &&
            throw(ArgumentError("duplicate axis code $(code.axis)/$(code.code)"))
        isempty(code.label) &&
            throw(ArgumentError("axis code $(code.code) lost its label"))
        code.code in ("Used", "Other") &&
            throw(ArgumentError("Used/Other absorption is forbidden"))
        if code.axis_role == :not_applicable
            code.code == "_Z" ||
                throw(ArgumentError("non-_Z not-applicable axis code"))
            if code.depth !== nothing
                code.child_count == 0 ||
                    throw(ArgumentError("_Z has hierarchy children"))
                code.is_hierarchy_leaf == true ||
                    throw(ArgumentError("_Z hierarchy leaf flag changed"))
            end
        else
            code.depth === nothing &&
                throw(ArgumentError("hierarchical code lost its depth"))
            code.child_count === nothing &&
                throw(ArgumentError("hierarchical code lost child count"))
            if code.axis_role == :leaf
                code.child_count == 0 ||
                    throw(ArgumentError("leaf has hierarchy children"))
                code.is_hierarchy_leaf == true ||
                    throw(ArgumentError("leaf flag changed"))
            elseif code.axis_role in (:aggregate, :published_total)
                code.child_count > 0 ||
                    throw(ArgumentError("aggregate has no hierarchy children"))
            end
        end
        keyed[key] = code
    end
    for cell in cells
        for (axis, code, role) in (
                (
                    :transaction,
                    cell.key.transaction,
                    cell.transaction_axis_role,
                ),
                (:activity, cell.key.activity, cell.activity_axis_role),
                (:product, cell.key.product, cell.product_axis_role),
            )
            axis_code = get(keyed, (axis, code), nothing)
            axis_code === nothing &&
                throw(ArgumentError("cell axis code $axis/$code is unknown"))
            axis_code.axis_role == role ||
                throw(ArgumentError("cell axis role changed for $axis/$code"))
        end
    end
    return keyed
end

function validate_source_totals(
        totals::Dict{Symbol, SourceTotal},
        cells::Vector{SourceAxisCell},
    )
    Set(keys(totals)) == Set(COMPONENTS) ||
        throw(ArgumentError("source-total components changed"))
    total_cell_index = findfirst(
        cell ->
        cell_key_tuple(cell.key) ==
            ("TU", "_Z", "_T", "D", "S1", "D"),
        cells,
    )
    total_cell_index === nothing &&
        throw(ArgumentError("published TU/_Z/_T source total cell is absent"))
    total_cell = cells[total_cell_index]
    for (table, component) in TABLE_COMPONENTS
        total = totals[component]
        total.table_identifier == table ||
            throw(ArgumentError("source-total table/component label changed"))
        total.aggregation_policy == :published_total_cell_only ||
            throw(
            ArgumentError(
                "aggregate-and-descendant double count is forbidden",
            ),
        )
        total.obs_status == "A" ||
            throw(ArgumentError("source-total status changed"))
        total.value_hundredths_million_usd ==
            additive_value(observation(total_cell, component)) ||
            throw(ArgumentError("source total differs from its published cell"))
    end
    return total_cell
end

function canonical_candidate_value(value)
    value isa Bool && return lowercase(string(value))
    return string(value)
end

function candidate_specification_sha256(record::AbstractDict)
    bytes = UInt8[]
    for field in CANDIDATE_SPECIFICATION_FIELDS
        haskey(record, field) ||
            throw(ArgumentError("candidate specification omits $field"))
        append!(
            bytes,
            codeunits(
                "$field=$(canonical_candidate_value(record[field]))\0",
            ),
        )
    end
    return sha256_hex(bytes)
end

function validate_candidate_records(records)
    identifiers = String[]
    for record in records
        identifier = String(record["id"])
        identifier in identifiers &&
            throw(
            ArgumentError(
                "same candidate ID appears with another specification",
            ),
        )
        push!(identifiers, identifier)
        digest = candidate_specification_sha256(record)
        digest == record["specification_sha256"] ||
            throw(
            ArgumentError(
                "candidate $identifier has the same ID but a different " *
                    "specification",
            ),
        )
    end
    return records
end

function load_candidates(records, sidecar)
    validate_candidate_records(records)
    candidates = TaxDiagnosticCandidate[]
    for record in records
        record["observed_sidecar_sha256"] ==
            sidecar.fixture_cells_sha256 ||
            throw(ArgumentError("candidate observed sidecar changed"))
        !record["allocation_applied"] ||
            throw(ArgumentError("candidate applied an allocation"))
        record["fiscal_receipt_status"] == "NOT_RUN_BLOCKED" ||
            throw(ArgumentError("fiscal receipt was not blocked"))
        record["margin_split_status"] == "NOT_RUN_BLOCKED" ||
            throw(ArgumentError("T1620 split was not blocked"))
        record["model_mapping_status"] == "NOT_RUN_BLOCKED" ||
            throw(ArgumentError("model mapping was not blocked"))
        !record["model_state_write"] ||
            throw(ArgumentError("candidate writes model state"))
        !record["forecast_origin_admissible"] ||
            throw(ArgumentError("candidate admits a forecast origin"))
        push!(
            candidates,
            TaxDiagnosticCandidate(
                String(record["id"]),
                Symbol(lowercase(record["tax_mode"])),
                Symbol(lowercase(record["tax_source_axis_policy"])),
                Int64(
                    record[
                        "dynamic_net_product_tax_total_hundredths_million_usd",
                    ],
                ),
                record["allocation_applied"],
                sidecar,
                Symbol(lowercase(record["fiscal_receipt_status"])),
                Symbol(lowercase(record["margin_split_status"])),
                Symbol(lowercase(record["model_mapping_status"])),
                record["model_state_write"],
                Symbol(lowercase(record["accounting_gate_effect"])),
                record["forecast_origin_admissible"],
                Symbol(lowercase(record["forecast_score_effect"])),
                String(record["specification_sha256"]),
            ),
        )
    end
    length(candidates) == 2 ||
        throw(ArgumentError("expected observed-tax and zero-tax candidates"))
    candidates[1].tax_mode == :observed ||
        throw(ArgumentError("first candidate is not observed-tax"))
    candidates[2].tax_mode == :zero ||
        throw(ArgumentError("second candidate is not zero-tax"))
    candidates[1].dynamic_net_product_tax_total_hundredths_million_usd ==
        sidecar.net_product_tax_total_hundredths_million_usd ||
        throw(ArgumentError("observed candidate tax total changed"))
    candidates[2].dynamic_net_product_tax_total_hundredths_million_usd ==
        0 ||
        throw(ArgumentError("zero-tax candidate is not zero"))
    return candidates
end

function validate_raw_responses(receipts_path, raw_directory)
    receipts = JSON.parsefile(receipts_path)
    receipts["schema_version"] ==
        "beforeit-us-oecd-sut-source-response-receipts.v1" ||
        throw(ArgumentError("source receipt schema changed"))
    receipts["captured_at_utc"] == "2026-08-06T15:10:26Z" ||
        throw(ArgumentError("source retrieval timestamp changed"))
    receipts["credentials_required"] == false ||
        throw(ArgumentError("source unexpectedly requires credentials"))
    receipts["sdmx_version"] == "2.0" ||
        throw(ArgumentError("source SDMX version changed"))
    responses = receipts["responses"]
    length(responses) == EXPECTED_SOURCE_RESPONSE_COUNT ||
        throw(ArgumentError("source response count changed"))
    names = String[]
    canonical = IOBuffer()
    for response in sort(responses; by = item -> item["name"])
        name = String(response["name"])
        local_filename = String(response["local_name"])
        name in names &&
            throw(ArgumentError("duplicate source receipt $name"))
        push!(names, name)
        startswith(
            response["url"],
            "https://sdmx.oecd.org/public/rest/",
        ) ||
            throw(ArgumentError("source endpoint changed"))
        path = joinpath(raw_directory, local_filename)
        isfile(path) ||
            throw(ArgumentError("archived raw response is absent: $path"))
        bytes = read(path)
        length(bytes) == response["byte_count"] ||
            throw(ArgumentError("raw response byte count changed: $name"))
        digest = sha256_hex(bytes)
        digest == response["sha256"] ||
            throw(ArgumentError("raw response SHA-256 changed: $name"))
        write(
            canonical,
            name,
            '\0',
            digest,
            '\0',
            string(length(bytes)),
            '\n',
        )
    end
    bundle_digest = sha256_hex(take!(canonical))
    bundle_digest == APPROVED_SOURCE_BUNDLE_SHA256 ||
        throw(ArgumentError("source bundle SHA-256 changed"))
    receipts["source_bundle_sha256"] == bundle_digest ||
        throw(ArgumentError("source receipt bundle digest changed"))
    return receipts
end

function bea_control_values(bea_directory)
    controls = Dict{String, Int64}()
    for row in CSV.File(joinpath(bea_directory, "cells.csv"))
        if string(row.table_id) == "262" && String(row.row_code) == "T017"
            code = String(row.column_code)
            if code in (
                    "T016",
                    "T013",
                    "T014",
                    "T015",
                    "TOP",
                    "MDTY",
                    "SUB",
                )
                controls[code] = round(Int64, 100 * Float64(row.value))
            end
        end
    end
    Set(keys(controls)) ==
        Set(["T016", "T013", "T014", "T015", "TOP", "MDTY", "SUB"]) ||
        throw(ArgumentError("BEA T017 valuation controls are incomplete"))
    return Dict(
        :purchasers => controls["T016"],
        :basic => controls["T013"],
        :combined_margin => controls["T014"],
        :net_product_tax => controls["T015"],
        :gross_product_tax => controls["TOP"] + controls["MDTY"],
        :subsidy_magnitude => -controls["SUB"],
    )
end

function cross_source_residuals(
        source_totals,
        bea_controls,
        expected_residuals,
        rounding_bound_records,
    )
    Set(keys(rounding_bound_records)) == Set(String.(COMPONENTS)) ||
        throw(ArgumentError("cross-source rounding-bound components changed"))
    residuals = CrossSourceResidual[]
    for component in COMPONENTS
        oecd = source_totals[component].value_hundredths_million_usd
        bea = bea_controls[component]
        residual = oecd - bea
        residual == expected_residuals[component] ||
            throw(ArgumentError("$component cross-source residual changed"))
        record = rounding_bound_records[String(component)]
        oecd_term_codes = String.(record["oecd_term_codes"])
        oecd_term_count = Int(record["oecd_term_count"])
        oecd_resolution = Int64(
            record[
                "oecd_term_resolution_hundredths_million_usd",
            ],
        )
        bea_term_codes = String.(record["bea_term_codes"])
        bea_term_count = Int(record["bea_term_count"])
        bea_resolution = Int64(
            record[
                "bea_term_resolution_hundredths_million_usd",
            ],
        )
        oecd_term_count > 0 ||
            throw(ArgumentError("$component has no OECD rounding term"))
        bea_term_count > 0 ||
            throw(ArgumentError("$component has no BEA rounding term"))
        length(oecd_term_codes) == oecd_term_count ||
            throw(
            ArgumentError(
                "$component OECD term count differs from its exact codes",
            ),
        )
        length(bea_term_codes) == bea_term_count ||
            throw(
            ArgumentError(
                "$component BEA term count differs from its exact codes",
            ),
        )
        length(Set(oecd_term_codes)) == oecd_term_count &&
            all(code -> !isempty(code), oecd_term_codes) ||
            throw(ArgumentError("$component OECD term codes are invalid"))
        length(Set(bea_term_codes)) == bea_term_count &&
            all(code -> !isempty(code), bea_term_codes) ||
            throw(ArgumentError("$component BEA term codes are invalid"))
        oecd_resolution > 0 ||
            throw(ArgumentError("$component OECD resolution is not positive"))
        bea_resolution > 0 ||
            throw(ArgumentError("$component BEA resolution is not positive"))
        derived_bound_twice =
            oecd_term_count * oecd_resolution +
            bea_term_count * bea_resolution
        configured_bound_twice = Int64(
            record[
                "derived_rounding_bound_twice_hundredths_million_usd",
            ],
        )
        configured_bound_twice == derived_bound_twice ||
            throw(
            ArgumentError(
                "$component rounding bound is not mathematically derived " *
                    "from its term counts and published resolutions",
            ),
        )
        within_derived_rounding_bound =
            2 * abs(residual) <= configured_bound_twice
        if component in (:purchasers, :basic)
            status = :DUBIOUS_CROSS_SOURCE_RELEASE_BOUNDARY_RESIDUAL
            boundary = :unbound_oecd_bea_release_and_scope
        elseif within_derived_rounding_bound
            status = :PASS_AT_CROSS_SOURCE_ROUNDING
            boundary =
                :within_component_specific_derived_rounding_bound
        else
            status =
                :DUBIOUS_OUTSIDE_DERIVED_CROSS_SOURCE_ROUNDING_BOUND
            boundary =
                :outside_component_specific_derived_rounding_bound
        end
        push!(
            residuals,
            CrossSourceResidual(
                component,
                oecd,
                bea,
                residual,
                oecd_term_codes,
                oecd_term_count,
                oecd_resolution,
                bea_term_codes,
                bea_term_count,
                bea_resolution,
                configured_bound_twice,
                status,
                boundary,
                :retain_unadjusted,
            ),
        )
    end
    return residuals
end

function validate_contract_files(
        contract,
        contract_path,
        generator_path,
        fixture_directory,
        raw_directory,
        project_path,
        julia_manifest_path,
        bea_directory,
    )
    sha256_file(contract_path) == APPROVED_CONTRACT_SHA256 ||
        throw(ArgumentError("OECD valuation contract SHA-256 changed"))
    contract["schema_version"] == CONTRACT_SCHEMA ||
        throw(ArgumentError("OECD valuation contract schema changed"))
    contract["classification"] == EXPECTED_CLASSIFICATION ||
        throw(ArgumentError("diagnostic classification changed"))
    contract["promotion_status"] == EXPECTED_PROMOTION_STATUS ||
        throw(ArgumentError("diagnostic promotion status changed"))
    !contract["forecast_origin_admissible"] ||
        throw(ArgumentError("contract admits a forecast origin"))
    !contract["model_state_write"] ||
        throw(ArgumentError("contract writes model state"))
    contract["accounting_gate_effect"] == "NONE" ||
        throw(ArgumentError("contract affects an accounting gate"))
    contract["forecast_score_effect"] == "NONE" ||
        throw(ArgumentError("contract affects a forecast score"))
    contract["missing_component_arithmetic"] ==
        "A published identity is evaluated only when every required " *
        "component is present. Any absent component yields " *
        "NOT_EVALUABLE_SOURCE_MISSING with no numeric residual. Absence is " *
        "never substituted as zero." ||
        throw(ArgumentError("source-missing arithmetic policy changed"))
    contract["structural_zero_policy"] ==
        "Only an explicit source observation of numeric zero is " *
        "SOURCE_EXPLICIT_ZERO. The archived OECD metadata supplies no " *
        "separate structural-zero designation for absent component tuples." ||
        throw(ArgumentError("structural-zero policy changed"))
    contract["cross_source_rounding_bound_policy"] ==
        "For independently nearest-rounded published terms, twice the " *
        "maximum rounding error in hundredths of a million dollars equals " *
        "the sum over terms of each published resolution in hundredths. A " *
        "residual r is within rounding only when 2*abs(r) is no greater than " *
        "that component-specific bound." ||
        throw(ArgumentError("cross-source rounding-bound policy changed"))
    Set(String.(contract["prohibited_operations"])) ==
        EXPECTED_PROHIBITED_OPERATIONS ||
        throw(ArgumentError("prohibited-operation policy changed"))

    pinned = (
        (generator_path, APPROVED_GENERATOR_SHA256, "generator"),
        (project_path, APPROVED_PROJECT_SHA256, "Project.toml"),
        (
            julia_manifest_path,
            APPROVED_JULIA_MANIFEST_SHA256,
            "Manifest.toml",
        ),
        (
            joinpath(fixture_directory, "manifest.toml"),
            APPROVED_FIXTURE_MANIFEST_SHA256,
            "fixture manifest",
        ),
        (
            joinpath(fixture_directory, "cells.csv"),
            APPROVED_CELLS_SHA256,
            "fixture cells",
        ),
        (
            joinpath(fixture_directory, "identity_evaluations.csv"),
            APPROVED_IDENTITY_EVALUATIONS_SHA256,
            "fixture identity evaluations",
        ),
        (
            joinpath(fixture_directory, "axis_codes.csv"),
            APPROVED_AXIS_CODES_SHA256,
            "fixture axis codes",
        ),
        (
            joinpath(fixture_directory, "source_totals.csv"),
            APPROVED_SOURCE_TOTALS_SHA256,
            "fixture source totals",
        ),
        (
            joinpath(fixture_directory, "t1610_nonbasic_quarantine.csv"),
            APPROVED_NONBASIC_QUARANTINE_SHA256,
            "T1610 non-basic quarantine",
        ),
        (
            joinpath(fixture_directory, "source_receipts.json"),
            APPROVED_SOURCE_RECEIPTS_SHA256,
            "source receipts",
        ),
        (
            joinpath(bea_directory, "cells.csv"),
            APPROVED_BEA_FIXTURE_SHA256,
            "BEA fixture",
        ),
        (
            joinpath(bea_directory, "manifest.toml"),
            APPROVED_BEA_MANIFEST_SHA256,
            "BEA manifest",
        ),
    )
    for (path, expected, label) in pinned
        isfile(path) || throw(ArgumentError("$label is absent: $path"))
        actual = sha256_file(path)
        actual == expected ||
            throw(ArgumentError("$label SHA-256 changed: $actual"))
    end

    fixture_manifest =
        TOML.parsefile(joinpath(fixture_directory, "manifest.toml"))
    fixture_manifest["schema_version"] == FIXTURE_SCHEMA ||
        throw(ArgumentError("fixture schema changed"))
    fixture_manifest["classification"] == EXPECTED_CLASSIFICATION ||
        throw(ArgumentError("fixture classification changed"))
    fixture_manifest["source_response_count"] ==
        EXPECTED_SOURCE_RESPONSE_COUNT ||
        throw(ArgumentError("fixture response count changed"))
    fixture_manifest["source_axis_cell_count"] ==
        EXPECTED_SOURCE_AXIS_CELL_COUNT ||
        throw(ArgumentError("fixture cell count changed"))
    fixture_manifest["axis_code_count"] == EXPECTED_AXIS_CODE_COUNT ||
        throw(ArgumentError("fixture axis count changed"))
    fixture_manifest["t1610_nonbasic_quarantine_count"] ==
        EXPECTED_NONBASIC_QUARANTINE_COUNT ||
        throw(ArgumentError("fixture quarantine count changed"))
    fixture_manifest["source_bundle_sha256"] ==
        APPROVED_SOURCE_BUNDLE_SHA256 ||
        throw(ArgumentError("fixture source-bundle digest changed"))
    fixture_manifest["generator_sha256"] ==
        APPROVED_GENERATOR_SHA256 ||
        throw(ArgumentError("fixture generator digest changed"))
    fixture_manifest["project_sha256"] == APPROVED_PROJECT_SHA256 ||
        throw(ArgumentError("fixture Project.toml digest changed"))
    fixture_manifest["julia_manifest_sha256"] ==
        APPROVED_JULIA_MANIFEST_SHA256 ||
        throw(ArgumentError("fixture Manifest.toml digest changed"))
    fixture_manifest["combined_margin_split_status"] ==
        "NOT_RUN_BLOCKED" ||
        throw(ArgumentError("T1620 split status changed"))
    fixture_manifest["model_mapping_status"] == "NOT_RUN_BLOCKED" ||
        throw(ArgumentError("fixture mapping status changed"))
    fixture_manifest["state_write_status"] == "NOT_RUN_BLOCKED" ||
        throw(ArgumentError("fixture state-write status changed"))
    fixture_manifest["source_missing_identity_policy"] ==
        "NOT_EVALUABLE_SOURCE_MISSING" ||
        throw(ArgumentError("source-missing identity policy changed"))
    fixture_manifest["structural_zero_metadata_status"] == "ABSENT" ||
        throw(ArgumentError("structural-zero metadata status changed"))
    equation_diagnostics = fixture_manifest["equation_diagnostics"]
    equation_diagnostics["valuation_identity_evaluated_count"] ==
        EXPECTED_VALUATION_IDENTITY_EVALUATED_COUNT ||
        throw(ArgumentError("valuation identity evaluated count changed"))
    equation_diagnostics[
        "valuation_identity_not_evaluable_source_missing_count",
    ] == EXPECTED_VALUATION_IDENTITY_NOT_EVALUABLE_COUNT ||
        throw(
        ArgumentError(
            "valuation identity source-missing count changed",
        ),
    )
    equation_diagnostics["tax_identity_evaluated_count"] ==
        EXPECTED_TAX_IDENTITY_EVALUATED_COUNT ||
        throw(ArgumentError("tax identity evaluated count changed"))
    equation_diagnostics[
        "tax_identity_not_evaluable_source_missing_count",
    ] == EXPECTED_TAX_IDENTITY_NOT_EVALUABLE_COUNT ||
        throw(
        ArgumentError(
            "tax identity source-missing count changed",
        ),
    )

    raw_receipts = validate_raw_responses(
        joinpath(fixture_directory, "source_receipts.json"),
        raw_directory,
    )
    return (; fixture_manifest, raw_receipts)
end

function load_oecd_source_axis_valuation_diagnostic(
        contract_path = DEFAULT_CONTRACT_PATH;
        generator_path = DEFAULT_GENERATOR_PATH,
        fixture_directory = DEFAULT_FIXTURE_DIRECTORY,
        raw_directory = DEFAULT_RAW_DIRECTORY,
        project_path = DEFAULT_PROJECT_PATH,
        julia_manifest_path = DEFAULT_JULIA_MANIFEST_PATH,
        bea_directory = DEFAULT_BEA_FIXTURE_DIRECTORY,
    )
    contract = TOML.parsefile(contract_path)
    validate_contract_files(
        contract,
        contract_path,
        generator_path,
        fixture_directory,
        raw_directory,
        project_path,
        julia_manifest_path,
        bea_directory,
    )

    cells = load_cells(joinpath(fixture_directory, "cells.csv"))
    cell_audit = validate_source_axis_cells(
        cells;
        rounding_tolerance_hundredths_million_usd = Int(
            contract[
                "rounding_tolerance_hundredths_million_usd",
            ],
        ),
        expected_count = EXPECTED_SOURCE_AXIS_CELL_COUNT,
        enforce_approved_semantics_counts = true,
    )
    identity_evaluations = load_identity_evaluations(
        joinpath(fixture_directory, "identity_evaluations.csv"),
    )
    expected_identity_evaluations = vcat(
        cell_audit.valuation_evaluations,
        cell_audit.tax_evaluations,
    )
    isequal(
        identity_evaluation_signature.(identity_evaluations),
        identity_evaluation_signature.(expected_identity_evaluations),
    ) ||
        throw(
        ArgumentError(
            "derived identity evaluations differ from source cells",
        ),
    )
    axis_codes =
        load_axis_codes(joinpath(fixture_directory, "axis_codes.csv"))
    validate_axis_codes(axis_codes, cells)
    source_totals =
        load_source_totals(joinpath(fixture_directory, "source_totals.csv"))
    validate_source_totals(source_totals, cells)

    sidecar = ObservedValuationSidecar(
        APPROVED_CELLS_SHA256,
        source_totals[:combined_margin].value_hundredths_million_usd,
        source_totals[:net_product_tax].value_hundredths_million_usd,
        source_totals[:gross_product_tax].value_hundredths_million_usd,
        source_totals[:subsidy_magnitude].value_hundredths_million_usd,
        "A",
    )
    candidates = load_candidates(contract["tax_candidates"], sidecar)

    bea_controls = bea_control_values(bea_directory)
    expected_bea = Dict(
        Symbol(component) => Int64(value) for
            (component, value) in
            contract["bea_controls_hundredths_million_usd"]
    )
    bea_controls == expected_bea ||
        throw(ArgumentError("local BEA controls changed"))
    expected_residuals = Dict(
        Symbol(component) => Int64(value) for
            (component, value) in
            contract[
                "expected_cross_source_residuals_hundredths_million_usd",
            ]
    )
    residuals = cross_source_residuals(
        source_totals,
        bea_controls,
        expected_residuals,
        contract["cross_source_rounding_bounds"],
    )

    return OECDSourceAxisValuationReport(
        Int(contract["source_year"]),
        String(contract["classification"]),
        cells,
        axis_codes,
        source_totals,
        cell_audit.valuation_residuals,
        cell_audit.tax_residuals,
        cell_audit.valuation_evaluations,
        cell_audit.tax_evaluations,
        residuals,
        sidecar,
        candidates,
        sha256_file(contract_path),
        sha256_file(generator_path),
        sha256_file(joinpath(fixture_directory, "manifest.toml")),
        sha256_file(joinpath(fixture_directory, "cells.csv")),
        sha256_file(
            joinpath(fixture_directory, "identity_evaluations.csv"),
        ),
        sha256_file(joinpath(fixture_directory, "axis_codes.csv")),
        sha256_file(joinpath(fixture_directory, "source_totals.csv")),
        sha256_file(
            joinpath(
                fixture_directory,
                "t1610_nonbasic_quarantine.csv",
            ),
        ),
        sha256_file(joinpath(fixture_directory, "source_receipts.json")),
        APPROVED_SOURCE_BUNDLE_SHA256,
        sha256_file(project_path),
        sha256_file(julia_manifest_path),
        sha256_file(joinpath(bea_directory, "cells.csv")),
        sha256_file(joinpath(bea_directory, "manifest.toml")),
        :not_run_blocked,
        :not_run_blocked,
        :not_run_blocked,
        false,
        :none,
        false,
        :none,
        String.(contract["promotion_blockers"]),
        Set(String.(contract["prohibited_operations"])),
        false,
    )
end

function source_total(
        report::OECDSourceAxisValuationReport,
        component::Symbol;
        aggregation::Symbol = :published_total_cell,
    )
    aggregation == :published_total_cell ||
        throw(
        ArgumentError(
            "aggregate-and-descendant double count is forbidden; " *
                "use the OECD published TU/_Z/_T control cell",
        ),
    )
    return report.source_totals[component].value_hundredths_million_usd
end

function request_mapping_or_allocation(
        ::OECDSourceAxisValuationReport,
        method::Symbol,
    )
    if method == :proportional
        throw(
            ArgumentError(
                "proportional allocation is explicitly forbidden; " *
                    "CPA08/ISIC4 mapping remains NOT_RUN_BLOCKED",
            ),
        )
    elseif method in (:used_absorption, :other_absorption)
        throw(
            ArgumentError(
                "Used/Other absorption is explicitly forbidden; mapping " *
                    "remains NOT_RUN_BLOCKED",
            ),
        )
    end
    throw(
        ArgumentError(
            "CPA08/ISIC4 to BEA/model mapping remains NOT_RUN_BLOCKED",
        ),
    )
end

function replace_component_value(
        cell::SourceAxisCell,
        component::Symbol,
        value_hundredths_million_usd::Int64;
        present::Bool = true,
        obs_status::String = "A",
    )
    component in COMPONENTS ||
        throw(ArgumentError("unknown valuation component $component"))
    replacement = present ?
        ComponentObservation(
            true,
            value_hundredths_million_usd,
            obs_status,
        ) :
        ComponentObservation(false, missing, missing)
    values = Dict(
        item => (item == component ? replacement : observation(cell, item))
            for item in COMPONENTS
    )
    return SourceAxisCell(
        cell.index,
        cell.key,
        cell.recipient_type,
        cell.transaction_axis_role,
        cell.activity_axis_role,
        cell.product_axis_role,
        cell.unit_measure,
        cell.unit_mult,
        cell.currency,
        cell.decimals,
        cell.obs_status,
        values[:purchasers],
        values[:basic],
        values[:combined_margin],
        values[:net_product_tax],
        values[:gross_product_tax],
        values[:subsidy_magnitude],
    )
end

end
