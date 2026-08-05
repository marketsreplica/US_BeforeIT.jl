const CASHFLOW_SCHEMA_VERSION = "quarter-ledger.v2"
const CASHFLOW_LEGACY_SCHEMA_VERSION = "quarter-ledger.v1"
const CASHFLOW_API_SCHEMA_VERSION = "explorer-edges.v2"

function _cashflow_units(dataset_id::AbstractString)
    units = _dataset_units(dataset_id)
    return Dict{String, Any}(
        "currency" => units.currency,
        "currency_symbol" => units.currency_symbol,
        "flow" => units.flow_units,
        "stock" => units.stock_units,
        "rate" => "quarterly_fraction",
    )
end

function _cashflow_apply_dataset_units!(value, dataset_id::AbstractString)
    units = _cashflow_units(dataset_id)
    replacements = Dict(
        "million_eur_per_quarter" => units["flow"],
        "million_eur" => units["stock"],
    )

    function apply!(item)
        if item isa AbstractDict
            for (key, child) in collect(pairs(item))
                if child isa AbstractString && haskey(replacements, child)
                    item[key] = replacements[child]
                else
                    apply!(child)
                end
            end
        elseif item isa AbstractVector
            for index in eachindex(item)
                child = item[index]
                if child isa AbstractString && haskey(replacements, child)
                    item[index] = replacements[child]
                else
                    apply!(child)
                end
            end
        end
        return item
    end

    apply!(value)
    if value isa AbstractDict
        value["units"] = units
    end
    return value
end

const _CASHFLOW_MARKET_BUSINESS = UInt8(1)
const _CASHFLOW_MARKET_FINAL = UInt8(2)
const _CASHFLOW_STAGE_REALIZED = UInt8(1)
const _CASHFLOW_STAGE_CAPACITY = UInt8(2)
const _CASHFLOW_SELLER_FIRM = UInt8(1)
const _CASHFLOW_SELLER_OUTSIDE = UInt8(2)

const _CASHFLOW_BUYER_KIND_LABELS = Dict(
    UInt8(1) => "firm",
    UInt8(2) => "active_worker_household",
    UInt8(3) => "inactive_household",
    UInt8(4) => "firm_owner_household",
    UInt8(5) => "bank_owner_household",
    UInt8(6) => "foreign_buyer",
    UInt8(7) => "government",
)

const _CashflowTraceKey =
    Tuple{UInt8, UInt8, Int32, UInt8, Int32, Int16, UInt8}

mutable struct _BilateralAggregate
    realized_quantity::Float64
    realized_amount::Float64
    realized_count::Int
    potential_quantity::Float64
    potential_amount::Float64
    potential_count::Int
end

_BilateralAggregate() = _BilateralAggregate(0.0, 0.0, 0, 0.0, 0.0, 0)

mutable struct _TransactionAggregate
    quantity::Float64
    amount::Float64
    count::Int
end

_TransactionAggregate() = _TransactionAggregate(0.0, 0.0, 0)

"""
    _CashflowCollection

Per-good transaction buckets used by the market observer. `search_and_matching!`
assigns each good to exactly one task, so a bucket has one writer even when the
market runs in parallel. This avoids the global lock and prevents the household
identifier cardinality from entering Standard traces.
"""
mutable struct _CashflowCollection
    buckets::Vector{
        Union{Nothing, Dict{_CashflowTraceKey, _TransactionAggregate}},
    }
    market_mask::UInt8
end

@inline function _cashflow_market_code(market)
    market == "business_goods" && return _CASHFLOW_MARKET_BUSINESS
    market == "final_demand" && return _CASHFLOW_MARKET_FINAL
    return UInt8(0)
end

@inline function _cashflow_seller_code(seller_kind)
    seller_kind == "firm" && return _CASHFLOW_SELLER_FIRM
    seller_kind == "outside_supplier" && return _CASHFLOW_SELLER_OUTSIDE
    return UInt8(0)
end

@inline function _cashflow_stage_code(transaction)
    return transaction.cash_recognized ? _CASHFLOW_STAGE_REALIZED :
        _CASHFLOW_STAGE_CAPACITY
end

@inline function _cashflow_buyer_code(buyer_kind)
    buyer_kind == "firm" && return UInt8(1)
    buyer_kind == "worker" && return UInt8(2)
    buyer_kind == "inactive_household" && return UInt8(3)
    buyer_kind == "firm_owner" && return UInt8(4)
    buyer_kind == "bank_owner" && return UInt8(5)
    buyer_kind == "outside_buyer" && return UInt8(6)
    buyer_kind == "government" && return UInt8(7)
    return UInt8(0)
end

"""
    _cashflow_collector(; maximum_goods = 4096,
        markets = (:business_goods,))

Return a bounded, online collector and its callback. Business transactions keep
the synthetic buyer-firm ID. Final demand deliberately collapses buyer IDs to
buyer cohorts while retaining seller, good, stage, quantity, amount, and count.
"""
function _cashflow_collector(;
        maximum_goods::Integer = 4096,
        markets = (:business_goods,),
    )
    maximum_goods > 0 ||
        throw(ArgumentError("maximum_goods must be positive"))
    market_mask = UInt8(0)
    for market in markets
        code = _cashflow_market_code(String(market))
        code == _CASHFLOW_MARKET_BUSINESS && (market_mask |= UInt8(1))
        code == _CASHFLOW_MARKET_FINAL && (market_mask |= UInt8(2))
    end
    collection = _CashflowCollection(
        Union{
            Nothing,
            Dict{_CashflowTraceKey, _TransactionAggregate},
        }[nothing for _ in 1:maximum_goods],
        market_mask,
    )

    @inline function record!(transaction)
        market = _cashflow_market_code(transaction.market)
        market == 0 && return nothing
        market_bit =
            market == _CASHFLOW_MARKET_BUSINESS ? UInt8(1) : UInt8(2)
        collection.market_mask & market_bit != 0 || return nothing
        seller_kind = _cashflow_seller_code(transaction.seller_kind)
        seller_kind == 0 && return nothing
        buyer_kind = _cashflow_buyer_code(transaction.buyer_kind)
        buyer_kind == 0 && return nothing
        good = Int(transaction.good)
        1 <= good <= length(collection.buckets) || throw(
            ArgumentError(
                "transaction good $good exceeds collector capacity " *
                    "$(length(collection.buckets))",
            ),
        )
        bucket = collection.buckets[good]
        if bucket === nothing
            bucket = Dict{_CashflowTraceKey, _TransactionAggregate}()
            collection.buckets[good] = bucket
        end
        buyer_id =
            market == _CASHFLOW_MARKET_BUSINESS ?
            Int32(transaction.buyer_id) : Int32(0)
        key = (
            market,
            buyer_kind,
            buyer_id,
            seller_kind,
            Int32(transaction.seller_id),
            Int16(good),
            _cashflow_stage_code(transaction),
        )
        aggregate = get(bucket, key, nothing)
        if aggregate === nothing
            aggregate = _TransactionAggregate()
            bucket[key] = aggregate
        end
        aggregate.quantity += Float64(transaction.quantity)
        aggregate.amount += Float64(transaction.amount)
        aggregate.count += 1
        return nothing
    end

    return collection, record!
end

function _cashflow_collector(
        model;
        markets = (:business_goods, :final_demand),
    )
    return _cashflow_collector(;
        maximum_goods = length(model.agg.P_bar_g),
        markets,
    )
end

function _cashflow_market_enabled(
        collection::_CashflowCollection,
        market::UInt8,
    )
    bit = market == _CASHFLOW_MARKET_BUSINESS ? UInt8(1) : UInt8(2)
    return collection.market_mask & bit != 0
end

function _cashflow_each_transaction(collection::_CashflowCollection)
    return Iterators.flatten(
        bucket === nothing ? () : pairs(bucket) for
            bucket in collection.buckets
    )
end

function _cashflow_legacy_business_aggregates(
        collection::_CashflowCollection,
    )
    relationships =
        Dict{Tuple{Int, String, Int, Int}, _BilateralAggregate}()
    for (key, transaction) in _cashflow_each_transaction(collection)
        market, _, buyer_id, seller_code, seller_id, good, stage = key
        market == _CASHFLOW_MARKET_BUSINESS || continue
        seller_kind =
            seller_code == _CASHFLOW_SELLER_FIRM ? "firm" :
            "outside_supplier"
        legacy_key = (
            Int(buyer_id),
            seller_kind,
            Int(seller_id),
            Int(good),
        )
        aggregate = get!(relationships, legacy_key) do
            _BilateralAggregate()
        end
        if stage == _CASHFLOW_STAGE_REALIZED
            aggregate.realized_quantity += transaction.quantity
            aggregate.realized_amount += transaction.amount
            aggregate.realized_count += transaction.count
        else
            aggregate.potential_quantity += transaction.quantity
            aggregate.potential_amount += transaction.amount
            aggregate.potential_count += transaction.count
        end
    end
    return relationships
end

function _cashflow_snapshot(model)
    household_deposits = [
        model.w_act.D_h
        model.w_inact.D_h
        model.firms.D_h
        [model.bank.D_h]
    ]
    return (
        household_deposits = copy(household_deposits),
        active_worker_deposits = copy(model.w_act.D_h),
        inactive_household_deposits = copy(model.w_inact.D_h),
        firm_owner_deposits = copy(model.firms.D_h),
        bank_owner_deposit = Float64(model.bank.D_h),
        firm_deposits = copy(model.firms.D_i),
        firm_loans = copy(model.firms.L_i),
        firm_equity = copy(model.firms.E_i),
        bank_equity = Float64(model.bank.E_k),
        bank_position = Float64(model.bank.D_k),
        government_debt = Float64(model.gov.L_G),
        central_bank_equity = Float64(model.cb.E_CB),
        external_position = Float64(model.rotw.D_RoW),
    )
end

function _cashflow_node(
        id, label, kind;
        group = "institution",
        sector = nothing,
        metrics = Dict{String, Any}(),
        attributes = Dict{String, Any}(),
    )
    node = Dict{String, Any}(
        "id" => String(id),
        "label" => String(label),
        "kind" => String(kind),
        "group" => String(group),
        "sector" => sector,
        "metrics" => metrics,
    )
    for (key, value) in attributes
        node[String(key)] = value
    end
    return node
end

function _cashflow_deposit_account(
        account_id,
        holder_node_id,
        opening_value,
        closing_value;
        level,
        aggregation,
    )
    opening = Float64(opening_value)
    closing = Float64(closing_value)
    recorded_change = closing - opening
    residual = closing - (opening + recorded_change)
    tolerance =
        1.0e-10 +
        1.0e-12 * max(abs(opening), abs(closing), abs(recorded_change), 1.0)
    return Dict{String, Any}(
        "account_id" => String(account_id),
        "account_kind" => "deposit_or_overdraft_position",
        "account_holder_node_id" => String(holder_node_id),
        "account_counterparty_node_id" => "bank",
        "account_level" => String(level),
        "account_aggregation" => String(aggregation),
        "account_units" => "million_eur",
        "opening_value" => opening,
        "recorded_change" => recorded_change,
        "closing_value" => closing,
        "residual" => residual,
        "tolerance" => tolerance,
        "reconciliation_residual" => residual,
        "reconciliation_tolerance" => tolerance,
        "reconciliation_status" =>
            abs(residual) <= tolerance ? "within_tolerance" :
            "outside_tolerance",
        "reconciliation_basis" =>
            "opening_plus_snapshot_derived_change_equals_closing",
        "reconciliation_evidence_basis" =>
            "exact_model_state_snapshots",
        "change_classification" => "recorded_stock_change",
        "signed_position_semantics" =>
            "positive_deposit_negative_overdraft",
        "classified_cashflow_identity_supported" => false,
        "reconciliation_explanation" =>
            "The change is the signed difference between exact opening and closing model-state snapshots. It is not a classification of every cash transaction affecting the account.",
    )
end

function _push_flow!(
        flows, id, source, target, label, amount;
        category,
        layer = "transactions",
        provenance = "exact_model_equation",
        explanation = "",
    )
    value = Float64(amount)
    isfinite(value) && value > 1.0e-12 || return flows
    push!(
        flows,
        Dict{String, Any}(
            "id" => String(id),
            "source" => String(source),
            "target" => String(target),
            "label" => String(label),
            "amount" => value,
            "category" => String(category),
            "layer" => String(layer),
            "provenance" => String(provenance),
            "explanation" => String(explanation),
        ),
    )
    return flows
end

function _push_signed_flow!(
        flows, id, positive_source, positive_target, label, amount;
        category,
        layer = "balance_sheet",
        provenance = "exact_stock_change",
        explanation = "",
    )
    value = Float64(amount)
    abs(value) > 1.0e-12 || return flows
    if value > 0
        return _push_flow!(
            flows,
            id,
            positive_source,
            positive_target,
            label,
            value;
            category,
            layer,
            provenance,
            explanation,
        )
    end
    return _push_flow!(
        flows,
        id,
        positive_target,
        positive_source,
        label,
        -value;
        category,
        layer,
        provenance,
        explanation,
    )
end

function _cashflow_sector_metadata_rows(
        dataset_id::AbstractString,
        sector_count::Integer,
    )
    raw = try
        sector_metadata(String(dataset_id))
    catch error
        if error isa MethodError
            try
                sector_metadata()
            catch
                nothing
            end
        else
            nothing
        end
    end
    if raw === nothing
        path = joinpath(APP_ROOT, "public", "sector-metadata.json")
        raw = isfile(path) ? JSON3.read(read(path, String)) : Any[]
    end
    rows = if raw isa AbstractDict || raw isa JSON3.Object
        normalized = _normalize_dict(raw)
        get(normalized, "sectors", Any[])
    else
        raw
    end
    by_index = Dict{Int, Dict{String, Any}}()
    for raw_row in rows
        row = _normalize_dict(raw_row)
        index = try
            Int(get(row, "index", 0))
        catch
            0
        end
        1 <= index <= sector_count || continue
        code = String(
            get(row, "code", "S$(lpad(string(index), 2, '0'))"),
        )
        label = String(get(row, "label", "Sector $index"))
        row["index"] = index
        row["code"] = code
        row["label"] = label
        row["short_label"] = String(get(row, "short_label", label))
        row["group_id"] = String(get(row, "group_id", "UNGROUPED"))
        row["group_label"] =
            String(get(row, "group_label", "Other sectors"))
        row["group_order"] = Int(get(row, "group_order", 999))
        row["group_color"] =
            String(get(row, "group_color", "#6f8194"))
        by_index[index] = row
    end
    return [
        get(
                by_index,
                sector,
                Dict{String, Any}(
                    "index" => sector,
                    "code" => "S$(lpad(string(sector), 2, '0'))",
                    "label" => "Sector $sector",
                    "short_label" => "Sector $sector",
                    "group_id" => "UNGROUPED",
                    "group_label" => "Other sectors",
                    "group_order" => 999,
                    "group_color" => "#6f8194",
                ),
            ) for sector in 1:sector_count
    ]
end

function _cashflow_firm_nodes(
        model;
        dataset_id::AbstractString = "",
        metadata_rows = nothing,
        opening_snapshot = nothing,
        closing_snapshot = nothing,
    )
    firms = model.firms
    opening_deposits =
        opening_snapshot === nothing ? firms.D_i :
        opening_snapshot.firm_deposits
    closing_deposits =
        closing_snapshot === nothing ? firms.D_i :
        closing_snapshot.firm_deposits
    sector_count = length(model.agg.P_bar_g)
    metadata_rows === nothing &&
        (
        metadata_rows = _cashflow_sector_metadata_rows(
            dataset_id,
            sector_count,
        )
    )
    nodes = Vector{Any}(undef, length(firms))
    sector_ordinals = zeros(Int, sector_count)
    for i in eachindex(firms.ID)
        sector = Int(firms.G_i[i])
        sector_ordinals[sector] += 1
        metadata = metadata_rows[sector]
        code = String(metadata["code"])
        short_label = String(metadata["short_label"])
        ordinal = sector_ordinals[sector]
        nodes[i] = _cashflow_node(
            "firm:$(firms.ID[i])",
            "$code · $short_label · Firm $(lpad(string(ordinal), 3, '0'))",
            "firm";
            group = "production",
            sector,
            metrics = Dict{String, Any}(
                "production" => Float64(firms.Y_i[i]),
                "sales" => Float64(firms.P_i[i] * firms.Q_i[i]),
                "employment" => Int(firms.N_i[i]),
                "deposits" => Float64(firms.D_i[i]),
                "loans" => Float64(firms.L_i[i]),
                "equity" => Float64(firms.E_i[i]),
                "profit" => Float64(firms.Pi_i[i]),
            ),
            attributes = Dict{String, Any}(
                "dataset_id" => String(dataset_id),
                "sector_code" => code,
                "sector_label" => String(metadata["label"]),
                "sector_short_label" => short_label,
                "firm_ordinal" => ordinal,
                "synthetic" => true,
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:firm:$(firms.ID[i])",
                        "firm:$(firms.ID[i])",
                        opening_deposits[i],
                        closing_deposits[i];
                        level = "firm",
                        aggregation = "none",
                    ),
                ],
            ),
        )
    end
    return nodes
end

function _cashflow_sector_nodes(
        model;
        dataset_id::AbstractString = "",
        metadata_rows = nothing,
        opening_snapshot = nothing,
        closing_snapshot = nothing,
    )
    firms = model.firms
    opening_deposits =
        opening_snapshot === nothing ? firms.D_i :
        opening_snapshot.firm_deposits
    closing_deposits =
        closing_snapshot === nothing ? firms.D_i :
        closing_snapshot.firm_deposits
    sector_count = length(model.agg.P_bar_g)
    metadata_rows === nothing &&
        (
        metadata_rows = _cashflow_sector_metadata_rows(
            dataset_id,
            sector_count,
        )
    )
    nodes = Vector{Any}(undef, sector_count)
    for sector in 1:sector_count
        member = firms.G_i .== sector
        metadata = metadata_rows[sector]
        code = String(metadata["code"])
        short_label = String(metadata["short_label"])
        nodes[sector] = _cashflow_node(
            "sector:$sector",
            "$code · $short_label",
            "sector";
            group = "production",
            sector,
            metrics = Dict{String, Any}(
                "firms" => count(member),
                "production" => Float64(sum(firms.Y_i[member])),
                "sales" =>
                    Float64(sum(firms.P_i[member] .* firms.Q_i[member])),
                "employment" => Int(sum(firms.N_i[member])),
                "deposits" => Float64(sum(firms.D_i[member])),
                "loans" => Float64(sum(firms.L_i[member])),
                "profit" => Float64(sum(firms.Pi_i[member])),
            ),
            attributes = Dict{String, Any}(
                "dataset_id" => String(dataset_id),
                "code" => code,
                "sector_label" => String(metadata["label"]),
                "short_label" => short_label,
                "group_id" => metadata["group_id"],
                "group_label" => metadata["group_label"],
                "group_order" => metadata["group_order"],
                "group_color" => metadata["group_color"],
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:sector:$sector",
                        "sector:$sector",
                        sum(opening_deposits[member]),
                        sum(closing_deposits[member]);
                        level = "sector",
                        aggregation = "firm_to_sector_exact_sum",
                    ),
                ],
            ),
        )
    end
    return nodes
end

function _cashflow_semantic_layer(
        layer;
        category = "",
        market = "",
        purpose = "",
    )
    raw = lowercase(String(layer))
    category_text = lowercase(String(category))
    market_text = lowercase(String(market))
    purpose_text = lowercase(String(purpose))
    raw in (
        "products",
        "capacity",
        "income",
        "fiscal",
        "credit",
        "interest",
        "deposits",
        "stocks",
        "foreign",
    ) && return raw
    (
        occursin("capacity", raw) ||
            occursin("counterfactual", raw)
    ) && return "capacity"
    (
        purpose_text in ("exports", "imports") ||
            category_text == "external" ||
            occursin("foreign", raw) ||
            occursin("external", raw)
    ) && return "foreign"
    category_text in (
        "products",
        "income",
        "fiscal",
        "credit",
        "interest",
        "deposits",
        "stocks",
        "foreign",
    ) && return category_text
    category_text == "goods" && return "products"
    (
        raw in ("wages", "dividends") ||
            occursin("income", raw) ||
            occursin("wage", raw) ||
            occursin("dividend", raw)
    ) && return "income"
    (
        raw == "benefits" ||
            occursin("fiscal", raw) ||
            occursin("tax", raw) ||
            occursin("benefit", raw) ||
            market_text in ("government_revenue", "social_benefits")
    ) && return "fiscal"
    occursin("interest", raw) && return "interest"
    (
        raw == "credit" ||
            occursin("principal", raw) ||
            occursin("boundary_adjustment", raw)
    ) && return "credit"
    raw == "financial_stocks" && return "stocks"
    if raw in ("financial_stock_change", "balance_sheet")
        occursin("deposit", purpose_text) ||
            category_text == "deposits" ||
            category_text == "deposit" || return "stocks"
        return "deposits"
    end
    occursin("deposit", raw) && return "deposits"
    occursin("stock", raw) && return "stocks"
    raw in ("money_flow", "transactions") && return "products"
    return raw
end

function _cashflow_normalized_edge(
        id,
        canonical_source,
        canonical_target,
        signed_value;
        label,
        layer,
        market,
        purpose,
        measure_kind,
        recognition,
        evidence_basis,
        aggregation,
        timing = "quarterly_window",
        units = "million_eur_per_quarter",
        direction_semantics = "payer_to_recipient",
        valuation_basis = "model_book_value",
        realization_scope = "representative_realization",
        realization_index = 1,
        level = "macro",
        category = layer,
        quantity = 0.0,
        match_count = 0,
        rollup_id = nothing,
        component_id = nothing,
        parent_ids = String[],
        ancestor_ids = String[],
        explanation = "",
        summation_role = "detail",
        attributes = Dict{String, Any}(),
    )
    value = Float64(signed_value)
    isfinite(value) || return nothing
    abs(value) > 1.0e-12 || return nothing
    source_layer = String(layer)
    semantic_layer = _cashflow_semantic_layer(
        source_layer;
        category,
        market,
        purpose,
    )
    source =
        value >= 0 ? String(canonical_source) : String(canonical_target)
    target =
        value >= 0 ? String(canonical_target) : String(canonical_source)
    immediate_parent_ids = unique(String.(parent_ids))
    ancestor_parent_ids = [
        ancestor for ancestor in unique(String.(ancestor_ids)) if
            !(ancestor in immediate_parent_ids)
    ]
    if rollup_id !== nothing
        primary_parent_id = String(rollup_id)
        primary_parent_id in immediate_parent_ids || throw(
            ArgumentError(
                "rollup_id must identify an immediate parent in parent_ids",
            ),
        )
    end
    edge = Dict{String, Any}(
        "id" => String(id),
        "canonical_source" => String(canonical_source),
        "canonical_target" => String(canonical_target),
        "source" => source,
        "target" => target,
        "display_source" => source,
        "display_target" => target,
        "signed_value" => value,
        "amount" => abs(value),
        "quantity" => Float64(quantity),
        "match_count" => Int(match_count),
        "label" => String(label),
        "layer" => semantic_layer,
        "economic_layer" => source_layer,
        "market" => String(market),
        "purpose" => String(purpose),
        "measure_kind" => String(measure_kind),
        "cash_recognition" => String(recognition),
        "recognition" => String(recognition),
        "evidence_basis" => String(evidence_basis),
        "realization_scope" => String(realization_scope),
        "realization_index" => Int(realization_index),
        "aggregation" => String(aggregation),
        "timing" => String(timing),
        "units" => String(units),
        "direction_semantics" => String(direction_semantics),
        "valuation_basis" => String(valuation_basis),
        "level" => String(level),
        "category" => String(category),
        "rollup_id" => rollup_id,
        "component_id" => component_id,
        # `parent_ids` is intentionally direct-only. Deeper lineage is kept
        # separately so a macro deep link cannot select both its sector
        # children and the firms below those sectors, then double-count them.
        "parent_ids" => immediate_parent_ids,
        "ancestor_ids" => ancestor_parent_ids,
        "explanation" => String(explanation),
        "summation_role" => String(summation_role),
    )
    for (key, attribute) in attributes
        edge[String(key)] = attribute
    end
    return edge
end

function _cashflow_push_edge!(edges, args...; kwargs...)
    edge = _cashflow_normalized_edge(args...; kwargs...)
    edge === nothing || push!(edges, edge)
    return edge
end

function _cashflow_edge_domain(edge)
    return join(
        (
            String(get(edge, "level", "unknown")),
            String(get(edge, "layer", "unknown")),
            String(get(edge, "measure_kind", "unknown")),
            String(get(edge, "units", "unknown")),
            String(get(edge, "recognition", "unknown")),
        ),
        "|",
    )
end

function _cashflow_edge_value(edge)
    value =
        haskey(edge, "signed_value") ?
        edge["signed_value"] : get(edge, "amount", 0.0)
    return Float64(value)
end

"""
    _cashflow_scale_domains(edges)

Return deterministic display domains without mixing incompatible economic
measures. Run workers can call this on the concatenated complete edge arrays for
all quarters to obtain run-wide domains.
"""
function _cashflow_scale_domains(edges)
    maxima = Dict{String, Float64}()
    counts = Dict{String, Int}()
    for edge in edges
        domain = _cashflow_edge_domain(edge)
        value = abs(_cashflow_edge_value(edge))
        maxima[domain] = max(get(maxima, domain, 0.0), value)
        counts[domain] = get(counts, domain, 0) + 1
    end
    return Dict{String, Any}(
        domain => Dict{String, Any}(
                "min" => 0.0,
                "max" => maxima[domain],
                "mapping" => "sqrt",
                "count" => counts[domain],
            ) for domain in sort!(collect(keys(maxima)))
    )
end

function _cashflow_buyer_node(buyer_kind::UInt8)
    buyer_kind == UInt8(2) && return "household:active-workers"
    buyer_kind == UInt8(3) && return "household:inactive"
    buyer_kind == UInt8(4) && return "household:firm-owners"
    buyer_kind == UInt8(5) && return "household:bank-owner"
    buyer_kind == UInt8(6) && return "outside-world"
    buyer_kind == UInt8(7) && return "government"
    return "production"
end

function _cashflow_final_demand_purpose(buyer_kind::UInt8)
    buyer_kind in (UInt8(2), UInt8(3), UInt8(4), UInt8(5)) &&
        return "household_final_demand"
    buyer_kind == UInt8(6) && return "exports"
    buyer_kind == UInt8(7) && return "government_purchase"
    return "final_demand"
end

function _cashflow_transaction_macro_id(
        market::UInt8,
        purpose::AbstractString,
        stage::UInt8,
    )
    if stage == _CASHFLOW_STAGE_CAPACITY
        market_name =
            market == _CASHFLOW_MARKET_BUSINESS ? "business-goods" :
            "final-demand"
        return "capacity-counterfactual:$market_name:$purpose"
    end
    market == _CASHFLOW_MARKET_BUSINESS &&
        return "macro:business-goods"
    purpose == "household_final_demand" &&
        return "macro:household-goods"
    purpose == "government_purchase" &&
        return "macro:government-goods"
    purpose == "exports" && return "macro:exports"
    return "macro:final-demand"
end

function _cashflow_transaction_totals()
    return Dict{String, Float64}(
        "business_realized" => 0.0,
        "business_capacity_counterfactual" => 0.0,
        "household_final_demand_realized" => 0.0,
        "government_final_demand_realized" => 0.0,
        "foreign_final_demand_realized" => 0.0,
        "final_demand_capacity_counterfactual" => 0.0,
        "all_realized" => 0.0,
    )
end

function _cashflow_transaction_edges(
        model,
        collection::_CashflowCollection;
        realization_index::Integer = 1,
    )
    firms = model.firms
    firm_index = Dict(Int(id) => index for (index, id) in pairs(firms.ID))
    edges = Vector{Any}()
    sector_aggregates =
        Dict{
        Tuple{UInt8, UInt8, Int16, UInt8, Int16, Int16, UInt8},
        _TransactionAggregate,
    }()
    totals = _cashflow_transaction_totals()
    observed_markets = Set{String}()
    _cashflow_market_enabled(collection, _CASHFLOW_MARKET_BUSINESS) &&
        push!(observed_markets, "business_goods")
    _cashflow_market_enabled(collection, _CASHFLOW_MARKET_FINAL) &&
        push!(observed_markets, "final_demand")

    for (key, transaction) in _cashflow_each_transaction(collection)
        market, buyer_kind, buyer_id, seller_kind, seller_id, good, stage =
            key
        market_name =
            market == _CASHFLOW_MARKET_BUSINESS ? "business_goods" :
            "final_demand"
        stage_name =
            stage == _CASHFLOW_STAGE_REALIZED ? "realized" :
            "capacity_counterfactual"
        realized = stage == _CASHFLOW_STAGE_REALIZED
        layer = if !realized
            "capacity"
        elseif seller_kind == _CASHFLOW_SELLER_OUTSIDE ||
                buyer_kind == UInt8(6)
            "foreign"
        else
            "products"
        end
        recognition =
            realized ? "realized_cash" : "capacity_counterfactual"
        measure_kind =
            realized ? "cash_transaction" : "counterfactual_match"
        buyer_sector = Int16(0)
        source = ""
        purpose = ""
        aggregation = ""
        if market == _CASHFLOW_MARKET_BUSINESS
            buyer_i = get(firm_index, Int(buyer_id), 0)
            buyer_i == 0 && continue
            buyer_sector = Int16(firms.G_i[buyer_i])
            source = "firm:$(Int(buyer_id))"
            purpose = "business_inputs"
            aggregation = "exact_bilateral_matches"
            total_key =
                realized ? "business_realized" :
                "business_capacity_counterfactual"
            totals[total_key] += transaction.amount
        else
            source = _cashflow_buyer_node(buyer_kind)
            purpose = _cashflow_final_demand_purpose(buyer_kind)
            aggregation = "buyer_cohort_to_seller_firm"
            if realized
                totals["all_realized"] += transaction.amount
                if purpose == "household_final_demand"
                    totals["household_final_demand_realized"] +=
                        transaction.amount
                elseif purpose == "government_purchase"
                    totals["government_final_demand_realized"] +=
                        transaction.amount
                elseif purpose == "exports"
                    totals["foreign_final_demand_realized"] +=
                        transaction.amount
                end
            else
                totals["final_demand_capacity_counterfactual"] +=
                    transaction.amount
            end
        end
        market == _CASHFLOW_MARKET_BUSINESS && realized &&
            (totals["all_realized"] += transaction.amount)

        seller_sector = if seller_kind == _CASHFLOW_SELLER_FIRM
            seller_i = get(firm_index, Int(seller_id), 0)
            seller_i == 0 ? Int16(good) :
                Int16(firms.G_i[seller_i])
        else
            Int16(good)
        end
        target =
            seller_kind == _CASHFLOW_SELLER_FIRM ?
            "firm:$(Int(seller_id))" :
            "outside:$(Int(seller_sector))"
        stable_buyer =
            market == _CASHFLOW_MARKET_BUSINESS ?
            "firm-$(Int(buyer_id))" :
            _CASHFLOW_BUYER_KIND_LABELS[buyer_kind]
        stable_seller =
            seller_kind == _CASHFLOW_SELLER_FIRM ?
            "firm-$(Int(seller_id))" :
            "outside-$(Int(seller_sector))"
        firm_id =
            "$market_name:$stage_name:firm:$stable_buyer:$stable_seller:" *
            "good-$(Int(good))"
        sector_target =
            seller_kind == _CASHFLOW_SELLER_FIRM ?
            "sector-$(Int(seller_sector))" :
            "outside-$(Int(seller_sector))"
        sector_id = if market == _CASHFLOW_MARKET_BUSINESS
            "$market_name:$stage_name:sector:sector-$(Int(buyer_sector)):" *
                "$sector_target:good-$(Int(good))"
        else
            "$market_name:$stage_name:sector:$stable_buyer:" *
                "$sector_target:good-$(Int(good))"
        end
        macro_id = _cashflow_transaction_macro_id(
            market,
            purpose,
            stage,
        )
        if market == _CASHFLOW_MARKET_BUSINESS ||
                seller_kind == _CASHFLOW_SELLER_FIRM
            _cashflow_push_edge!(
                edges,
                firm_id,
                source,
                target,
                transaction.amount;
                label =
                    market == _CASHFLOW_MARKET_BUSINESS ?
                    "Business inputs" : replace(purpose, "_" => " "),
                layer,
                market = market_name,
                purpose,
                measure_kind,
                recognition,
                evidence_basis = "transaction_event",
                aggregation,
                direction_semantics = "buyer_to_seller",
                valuation_basis =
                    "seller_price_excluding_buyer_side_taxes",
                realization_index,
                level = "firm",
                category =
                    market == _CASHFLOW_MARKET_BUSINESS ? "business" :
                    "final_demand",
                quantity = transaction.quantity,
                match_count = transaction.count,
                rollup_id = sector_id,
                parent_ids = [sector_id],
                ancestor_ids = [macro_id],
                explanation =
                    realized ?
                    "Exact sum of recorded seller matches in the selected realization." :
                    "Second-pass match against unused productive capacity; this is not cash or observed unmet demand.",
                attributes = Dict(
                    "stage" => stage_name,
                    "good" => Int(good),
                    "buyer_kind" =>
                        _CASHFLOW_BUYER_KIND_LABELS[buyer_kind],
                    "seller_kind" =>
                        seller_kind == _CASHFLOW_SELLER_FIRM ? "firm" :
                        "outside_supplier",
                    "seller_sector" => Int(seller_sector),
                    "product_source" => target,
                    "product_target" => source,
                ),
            )
        end

        sector_key = (
            market,
            buyer_kind,
            buyer_sector,
            seller_kind,
            seller_sector,
            good,
            stage,
        )
        sector_aggregate = get!(sector_aggregates, sector_key) do
            _TransactionAggregate()
        end
        sector_aggregate.quantity += transaction.quantity
        sector_aggregate.amount += transaction.amount
        sector_aggregate.count += transaction.count
    end

    for (key, transaction) in sector_aggregates
        market, buyer_kind, buyer_sector, seller_kind, seller_sector, good,
            stage = key
        market_name =
            market == _CASHFLOW_MARKET_BUSINESS ? "business_goods" :
            "final_demand"
        stage_name =
            stage == _CASHFLOW_STAGE_REALIZED ? "realized" :
            "capacity_counterfactual"
        realized = stage == _CASHFLOW_STAGE_REALIZED
        source = if market == _CASHFLOW_MARKET_BUSINESS
            "sector:$(Int(buyer_sector))"
        else
            _cashflow_buyer_node(buyer_kind)
        end
        target =
            seller_kind == _CASHFLOW_SELLER_FIRM ?
            "sector:$(Int(seller_sector))" :
            "outside:$(Int(seller_sector))"
        purpose =
            market == _CASHFLOW_MARKET_BUSINESS ?
            "business_inputs" :
            _cashflow_final_demand_purpose(buyer_kind)
        stable_buyer =
            market == _CASHFLOW_MARKET_BUSINESS ?
            "sector-$(Int(buyer_sector))" :
            _CASHFLOW_BUYER_KIND_LABELS[buyer_kind]
        sector_target =
            seller_kind == _CASHFLOW_SELLER_FIRM ?
            "sector-$(Int(seller_sector))" :
            "outside-$(Int(seller_sector))"
        sector_id =
            "$market_name:$stage_name:sector:$stable_buyer:" *
            "$sector_target:good-$(Int(good))"
        macro_id = _cashflow_transaction_macro_id(
            market,
            purpose,
            stage,
        )
        _cashflow_push_edge!(
            edges,
            sector_id,
            source,
            target,
            transaction.amount;
            label =
                market == _CASHFLOW_MARKET_BUSINESS ?
                "Business inputs" : replace(purpose, "_" => " "),
            layer = if !realized
                "capacity"
            elseif seller_kind == _CASHFLOW_SELLER_OUTSIDE ||
                    buyer_kind == UInt8(6)
                "foreign"
            else
                "products"
            end,
            market = market_name,
            purpose,
            measure_kind =
                realized ? "cash_transaction" :
                "counterfactual_match",
            recognition =
                realized ? "realized_cash" :
                "capacity_counterfactual",
            evidence_basis = "transaction_event",
            aggregation =
                market == _CASHFLOW_MARKET_BUSINESS ?
                "firm_matches_to_sector_pair" :
                "buyer_cohort_to_seller_sector",
            direction_semantics = "buyer_to_seller",
            valuation_basis = "seller_price_excluding_buyer_side_taxes",
            realization_index,
            level = "sector",
            category =
                market == _CASHFLOW_MARKET_BUSINESS ? "business" :
                "final_demand",
            quantity = transaction.quantity,
            match_count = transaction.count,
            rollup_id = macro_id,
            parent_ids = [macro_id],
            explanation =
                realized ?
                "Exact sector rollup of recorded matches." :
                "Capacity-counterfactual sector rollup; excluded from cash totals.",
            attributes = Dict(
                "stage" => stage_name,
                "good" => Int(good),
                "buyer_kind" =>
                    _CASHFLOW_BUYER_KIND_LABELS[buyer_kind],
                "seller_kind" =>
                    seller_kind == _CASHFLOW_SELLER_FIRM ? "firm" :
                    "outside_supplier",
                "seller_sector" => Int(seller_sector),
                "product_source" => target,
                "product_target" => source,
            ),
        )
    end
    return edges, totals, sort!(collect(observed_markets))
end

function _cashflow_relationship_payload(model, aggregates)
    if aggregates isa _CashflowCollection
        aggregates = _cashflow_legacy_business_aggregates(aggregates)
    end
    firms = model.firms
    firm_index = Dict(Int(id) => i for (i, id) in pairs(firms.ID))
    relationships = Vector{Any}()
    sector_aggregates =
        Dict{Tuple{Int, String, Int}, _BilateralAggregate}()

    for (
            (buyer_id, seller_kind, seller_id, good),
            aggregate,
        ) in aggregates
        buyer_i = get(firm_index, buyer_id, 0)
        buyer_i == 0 && continue
        buyer_sector = Int(firms.G_i[buyer_i])
        seller_sector = if seller_kind == "firm"
            seller_i = get(firm_index, seller_id, 0)
            seller_i == 0 ? good : Int(firms.G_i[seller_i])
        else
            good
        end

        push!(
            relationships,
            Dict{String, Any}(
                "id" =>
                    "business:$buyer_id:$seller_kind:$seller_id:$good",
                "source" => "firm:$buyer_id",
                "target" =>
                    seller_kind == "firm" ? "firm:$seller_id" :
                    "outside:$seller_sector",
                "buyer_id" => buyer_id,
                "buyer_sector" => buyer_sector,
                "seller_kind" => seller_kind,
                "seller_id" => seller_id,
                "seller_sector" => seller_sector,
                "good" => good,
                "amount" => aggregate.realized_amount,
                "quantity" => aggregate.realized_quantity,
                "transaction_count" => aggregate.realized_count,
                "potential_amount" => aggregate.potential_amount,
                "potential_quantity" => aggregate.potential_quantity,
                "potential_match_count" => aggregate.potential_count,
                "provenance" => "exact_representative_realization",
                "purpose" => "materials_and_capital_goods_combined",
            ),
        )

        sector_key = (buyer_sector, seller_kind, seller_sector)
        sector_aggregate = get!(sector_aggregates, sector_key) do
            _BilateralAggregate()
        end
        sector_aggregate.realized_quantity += aggregate.realized_quantity
        sector_aggregate.realized_amount += aggregate.realized_amount
        sector_aggregate.realized_count += aggregate.realized_count
        sector_aggregate.potential_quantity += aggregate.potential_quantity
        sector_aggregate.potential_amount += aggregate.potential_amount
        sector_aggregate.potential_count += aggregate.potential_count
    end

    sector_relationships = Vector{Any}()
    outside_sectors = Set{Int}()
    for (
            (buyer_sector, seller_kind, seller_sector),
            aggregate,
        ) in sector_aggregates
        seller_kind == "outside_supplier" &&
            push!(outside_sectors, seller_sector)
        push!(
            sector_relationships,
            Dict{String, Any}(
                "id" =>
                    "sector-business:$buyer_sector:$seller_kind:$seller_sector",
                "source" => "sector:$buyer_sector",
                "target" =>
                    seller_kind == "firm" ? "sector:$seller_sector" :
                    "outside:$seller_sector",
                "buyer_sector" => buyer_sector,
                "seller_kind" => seller_kind,
                "seller_sector" => seller_sector,
                "amount" => aggregate.realized_amount,
                "quantity" => aggregate.realized_quantity,
                "transaction_count" => aggregate.realized_count,
                "potential_amount" => aggregate.potential_amount,
                "potential_quantity" => aggregate.potential_quantity,
                "potential_match_count" => aggregate.potential_count,
                "provenance" => "exact_representative_realization",
            ),
        )
    end

    sort!(relationships; by = edge -> edge["amount"], rev = true)
    sort!(sector_relationships; by = edge -> edge["amount"], rev = true)
    return relationships, sector_relationships, outside_sectors
end

function _cashflow_relationship_columns(relationships)
    count = length(relationships)
    columns = Dict{String, Any}(
        "buyer_id" => Vector{Int32}(undef, count),
        "buyer_sector" => Vector{Int16}(undef, count),
        "seller_kind" => Vector{Int8}(undef, count),
        "seller_id" => Vector{Int32}(undef, count),
        "seller_sector" => Vector{Int16}(undef, count),
        "good" => Vector{Int16}(undef, count),
        "amount" => Vector{Float64}(undef, count),
        "quantity" => Vector{Float64}(undef, count),
        "transaction_count" => Vector{Int32}(undef, count),
        "potential_amount" => Vector{Float64}(undef, count),
        "potential_quantity" => Vector{Float64}(undef, count),
        "potential_match_count" => Vector{Int32}(undef, count),
    )
    for (index, edge) in pairs(relationships)
        columns["buyer_id"][index] = edge["buyer_id"]
        columns["buyer_sector"][index] = edge["buyer_sector"]
        columns["seller_kind"][index] =
            edge["seller_kind"] == "firm" ? 1 : 2
        columns["seller_id"][index] = edge["seller_id"]
        columns["seller_sector"][index] = edge["seller_sector"]
        columns["good"][index] = edge["good"]
        columns["amount"][index] = edge["amount"]
        columns["quantity"][index] = edge["quantity"]
        columns["transaction_count"][index] =
            edge["transaction_count"]
        columns["potential_amount"][index] =
            edge["potential_amount"]
        columns["potential_quantity"][index] =
            edge["potential_quantity"]
        columns["potential_match_count"][index] =
            edge["potential_match_count"]
    end
    return columns
end

function _cashflow_sector_relationship_columns(relationships)
    count = length(relationships)
    columns = Dict{String, Any}(
        "buyer_sector" => Vector{Int16}(undef, count),
        "seller_kind" => Vector{Int8}(undef, count),
        "seller_sector" => Vector{Int16}(undef, count),
        "amount" => Vector{Float64}(undef, count),
        "quantity" => Vector{Float64}(undef, count),
        "transaction_count" => Vector{Int32}(undef, count),
        "potential_amount" => Vector{Float64}(undef, count),
        "potential_quantity" => Vector{Float64}(undef, count),
        "potential_match_count" => Vector{Int32}(undef, count),
    )
    for (index, edge) in pairs(relationships)
        columns["buyer_sector"][index] = edge["buyer_sector"]
        columns["seller_kind"][index] =
            edge["seller_kind"] == "firm" ? 1 : 2
        columns["seller_sector"][index] = edge["seller_sector"]
        columns["amount"][index] = edge["amount"]
        columns["quantity"][index] = edge["quantity"]
        columns["transaction_count"][index] =
            edge["transaction_count"]
        columns["potential_amount"][index] =
            edge["potential_amount"]
        columns["potential_quantity"][index] =
            edge["potential_quantity"]
        columns["potential_match_count"][index] =
            edge["potential_match_count"]
    end
    return columns
end

function _cashflow_materialize_sector_relationships(
        columns;
        include_potential = false,
        limit = 480,
    )
    count = length(columns["amount"])
    indices = collect(1:count)
    if include_potential
        sort!(
            indices;
            by = index -> max(
                columns["amount"][index],
                columns["potential_amount"][index],
            ),
            rev = true,
        )
    end

    rows = Vector{Any}()
    matching_count = 0
    for index in indices
        !include_potential && columns["amount"][index] <= 0 && continue
        matching_count += 1
        length(rows) >= limit && continue
        buyer_sector = Int(columns["buyer_sector"][index])
        seller_is_firm = columns["seller_kind"][index] == 1
        seller_sector = Int(columns["seller_sector"][index])
        seller_kind =
            seller_is_firm ? "firm" : "outside_supplier"
        push!(
            rows,
            Dict{String, Any}(
                "id" =>
                    "sector-business:$buyer_sector:$seller_kind:$seller_sector",
                "source" => "sector:$buyer_sector",
                "target" =>
                    seller_is_firm ? "sector:$seller_sector" :
                    "outside:$seller_sector",
                "buyer_sector" => buyer_sector,
                "seller_kind" => seller_kind,
                "seller_sector" => seller_sector,
                "amount" => columns["amount"][index],
                "quantity" => columns["quantity"][index],
                "transaction_count" =>
                    Int(columns["transaction_count"][index]),
                "potential_amount" =>
                    columns["potential_amount"][index],
                "potential_quantity" =>
                    columns["potential_quantity"][index],
                "potential_match_count" =>
                    Int(columns["potential_match_count"][index]),
                "provenance" =>
                    "exact_representative_realization",
            ),
        )
    end
    return rows, matching_count
end

function _cashflow_materialize_relationships(
        columns;
        firm_id = nothing,
        include_potential = false,
        limit = 240,
    )
    count = length(columns["amount"])
    indices = collect(1:count)
    if include_potential
        sort!(
            indices;
            by = index -> max(
                columns["amount"][index],
                columns["potential_amount"][index],
            ),
            rev = true,
        )
    end

    rows = Vector{Any}()
    matching_count = 0
    for index in indices
        buyer_id = Int(columns["buyer_id"][index])
        seller_is_firm = columns["seller_kind"][index] == 1
        seller_id = Int(columns["seller_id"][index])
        firm_id !== nothing &&
            buyer_id != firm_id &&
            !(seller_is_firm && seller_id == firm_id) && continue
        !include_potential && columns["amount"][index] <= 0 && continue
        matching_count += 1
        length(rows) >= limit && continue

        buyer_sector = Int(columns["buyer_sector"][index])
        seller_sector = Int(columns["seller_sector"][index])
        seller_kind =
            seller_is_firm ? "firm" : "outside_supplier"
        push!(
            rows,
            Dict{String, Any}(
                "id" =>
                    "business:$buyer_id:$seller_kind:$seller_id:$(columns["good"][index])",
                "source" => "firm:$buyer_id",
                "target" =>
                    seller_is_firm ? "firm:$seller_id" :
                    "outside:$seller_sector",
                "buyer_id" => buyer_id,
                "buyer_sector" => buyer_sector,
                "seller_kind" => seller_kind,
                "seller_id" => seller_id,
                "seller_sector" => seller_sector,
                "good" => Int(columns["good"][index]),
                "amount" => columns["amount"][index],
                "quantity" => columns["quantity"][index],
                "transaction_count" =>
                    Int(columns["transaction_count"][index]),
                "potential_amount" =>
                    columns["potential_amount"][index],
                "potential_quantity" =>
                    columns["potential_quantity"][index],
                "potential_match_count" =>
                    Int(columns["potential_match_count"][index]),
                "provenance" =>
                    "exact_representative_realization",
                "purpose" =>
                    "materials_and_capital_goods_combined",
            ),
        )
    end
    return rows, matching_count
end

function _cashflow_cohort_nodes(
        model,
        snapshot;
        opening_snapshot = snapshot,
    )
    return [
        _cashflow_node(
            "household:active-workers",
            "Active worker households",
            "household_cohort";
            metrics = Dict(
                "agents" => length(model.w_act),
                "deposits" => sum(snapshot.active_worker_deposits),
            ),
            attributes = Dict(
                "synthetic" => true,
                "cohort" => "active_workers",
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:household:active-workers",
                        "household:active-workers",
                        sum(opening_snapshot.active_worker_deposits),
                        sum(snapshot.active_worker_deposits);
                        level = "macro",
                        aggregation = "household_cohort_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "household:inactive",
            "Inactive households",
            "household_cohort";
            metrics = Dict(
                "agents" => length(model.w_inact),
                "deposits" =>
                    sum(snapshot.inactive_household_deposits),
            ),
            attributes = Dict(
                "synthetic" => true,
                "cohort" => "inactive",
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:household:inactive",
                        "household:inactive",
                        sum(opening_snapshot.inactive_household_deposits),
                        sum(snapshot.inactive_household_deposits);
                        level = "macro",
                        aggregation = "household_cohort_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "household:firm-owners",
            "Firm-owner households",
            "household_cohort";
            metrics = Dict(
                "agents" => length(model.firms),
                "deposits" => sum(snapshot.firm_owner_deposits),
            ),
            attributes = Dict(
                "synthetic" => true,
                "cohort" => "firm_owners",
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:household:firm-owners",
                        "household:firm-owners",
                        sum(opening_snapshot.firm_owner_deposits),
                        sum(snapshot.firm_owner_deposits);
                        level = "macro",
                        aggregation = "household_cohort_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "household:bank-owner",
            "Bank-owner household",
            "household_cohort";
            metrics = Dict(
                "agents" => 1,
                "deposits" => snapshot.bank_owner_deposit,
            ),
            attributes = Dict(
                "synthetic" => true,
                "cohort" => "bank_owner",
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:household:bank-owner",
                        "household:bank-owner",
                        opening_snapshot.bank_owner_deposit,
                        snapshot.bank_owner_deposit;
                        level = "macro",
                        aggregation = "single_household_account",
                    ),
                ],
            ),
        ),
    ]
end

function _cashflow_stock_payload(opening, closing)
    return Dict{String, Any}(
        "household_deposits" => Dict(
            "open" => sum(opening.household_deposits),
            "close" => sum(closing.household_deposits),
        ),
        "active_worker_deposits" => Dict(
            "open" => sum(opening.active_worker_deposits),
            "close" => sum(closing.active_worker_deposits),
        ),
        "inactive_household_deposits" => Dict(
            "open" => sum(opening.inactive_household_deposits),
            "close" => sum(closing.inactive_household_deposits),
        ),
        "firm_owner_deposits" => Dict(
            "open" => sum(opening.firm_owner_deposits),
            "close" => sum(closing.firm_owner_deposits),
        ),
        "bank_owner_deposit" => Dict(
            "open" => opening.bank_owner_deposit,
            "close" => closing.bank_owner_deposit,
        ),
        "firm_deposits" => Dict(
            "open" => sum(opening.firm_deposits),
            "close" => sum(closing.firm_deposits),
        ),
        "firm_loans" => Dict(
            "open" => sum(opening.firm_loans),
            "close" => sum(closing.firm_loans),
        ),
        "firm_equity" => Dict(
            "open" => sum(opening.firm_equity),
            "close" => sum(closing.firm_equity),
        ),
        "government_debt" => Dict(
            "open" => opening.government_debt,
            "close" => closing.government_debt,
        ),
        "bank_equity" => Dict(
            "open" => opening.bank_equity,
            "close" => closing.bank_equity,
        ),
        "bank_position" => Dict(
            "open" => opening.bank_position,
            "close" => closing.bank_position,
        ),
        "central_bank_equity" => Dict(
            "open" => opening.central_bank_equity,
            "close" => closing.central_bank_equity,
        ),
        "external_position" => Dict(
            "open" => opening.external_position,
            "close" => closing.external_position,
        ),
    )
end

function _cashflow_rollup(
        id,
        label,
        amount,
        component_totals;
        level = "macro",
        units = "million_eur_per_quarter",
        valuation_basis = "model_book_value",
    )
    components = sort!(String.(collect(keys(component_totals))))
    return Dict{String, Any}(
        "id" => String(id),
        "label" => String(label),
        "amount" => Float64(amount),
        "components" => components,
        "component_totals" => Dict(
            String(key) => Float64(component_totals[key]) for
                key in keys(component_totals)
        ),
        "level" => String(level),
        "units" => String(units),
        "valuation_basis" => String(valuation_basis),
        "summation_rule" => "components_only",
    )
end

function _cashflow_macro_market_edges(
        flows;
        realization_index::Integer = 1,
    )
    market_ids = Set(
        [
            "household-goods",
            "business-goods",
            "government-goods",
            "exports",
            "domestic-sales",
            "imports",
            "restart-financing",
        ]
    )
    edges = Vector{Any}()
    for flow in flows
        String(flow["id"]) in market_ids || continue
        valuation_basis = if flow["id"] in (
                "household-goods",
                "government-goods",
                "exports",
            )
            "seller_price_excluding_buyer_side_taxes"
        else
            "model_book_value"
        end
        _cashflow_push_edge!(
            edges,
            "macro:$(flow["id"])",
            flow["source"],
            flow["target"],
            flow["amount"];
            label = flow["label"],
            layer =
                flow["id"] == "restart-financing" ?
                "boundary_adjustment" : "money_flow",
            market =
                flow["id"] == "restart-financing" ? "insolvency" :
                "aggregate_goods_market",
            purpose = flow["id"],
            measure_kind =
                flow["id"] == "restart-financing" ?
                "boundary_adjustment" : "model_equation",
            recognition = "realized_cash",
            evidence_basis = "model_equation",
            aggregation = "macro_equation",
            timing =
                flow["id"] == "restart-financing" ?
                "quarter_opening_boundary" : "quarterly_window",
            direction_semantics = "payer_to_recipient",
            valuation_basis,
            realization_index,
            level = "macro",
            category = flow["category"],
            explanation = get(flow, "explanation", ""),
            summation_role = "rollup",
        )
    end
    return edges
end

function _cashflow_sector_endpoints(kind::AbstractString, sector::Integer)
    sector_node = "sector:$sector"
    if kind in (
            "wages",
            "employer_social_contribution",
            "product_tax",
            "production_tax",
            "corporate_tax",
            "firm_dividend",
            "principal",
            "loan_interest",
            "deposit_change",
            "deposit_stock",
        )
        source = sector_node
    else
        source = "bank"
    end
    target = if kind == "wages"
        "household:active-workers"
    elseif kind in (
            "employer_social_contribution",
            "product_tax",
            "production_tax",
            "corporate_tax",
        )
        "government"
    elseif kind == "firm_dividend"
        "household:firm-owners"
    elseif kind in ("new_credit", "deposit_interest", "loan_stock")
        sector_node
    else
        "bank"
    end
    return source, target
end

function _cashflow_macro_endpoints(kind::AbstractString)
    source = if kind in (
            "wages",
            "firm_dividend",
            "principal",
            "loan_interest",
            "deposit_change",
            "deposit_stock",
        )
        "production"
    else
        "bank"
    end
    target = if kind == "wages"
        "household:active-workers"
    elseif kind == "firm_dividend"
        "household:firm-owners"
    elseif kind in ("new_credit", "deposit_interest", "loan_stock")
        "production"
    else
        "bank"
    end
    return source, target
end

function _cashflow_institution_edges(
        model,
        opening,
        closing;
        realization_index::Integer = 1,
    )
    firms, bank, cb, gov, rotw, prop = model.firms, model.bank,
        model.cb, model.gov, model.rotw, model.prop
    P_bar_HH = model.agg.P_bar_HH
    edges = Vector{Any}()
    rollups = Vector{Any}()

    wages_by_firm = firms.w_i .* firms.N_i .* P_bar_HH
    total_wages = sum(wages_by_firm)
    household_consumption =
        sum(model.w_act.C_h) + sum(model.w_inact.C_h) +
        sum(firms.C_h) + bank.C_h
    household_investment =
        sum(model.w_act.I_h) + sum(model.w_inact.I_h) +
        sum(firms.I_h) + bank.I_h
    firm_positive_profit = sum(max.(0, firms.Pi_i))
    bank_positive_profit = max(0, bank.Pi_k)
    exports = rotw.C_l

    fiscal_components = Dict{String, Float64}(
        "employer_social_contribution" => prop.tau_SIF * total_wages,
        "worker_social_contribution" => prop.tau_SIW * total_wages,
        "labour_income_tax" =>
            prop.tau_INC * (1 - prop.tau_SIW) * total_wages,
        "vat" => prop.tau_VAT * household_consumption,
        "household_capital_formation_tax" =>
            prop.tau_CF * household_investment,
        "capital_income_tax" =>
            prop.tau_INC * (1 - prop.tau_FIRM) * prop.theta_DIV *
            (firm_positive_profit + bank_positive_profit),
        "corporate_tax" =>
            prop.tau_FIRM *
            (firm_positive_profit + bank_positive_profit),
        "product_tax" =>
            sum(firms.tau_Y_i .* firms.P_i .* firms.Y_i),
        "production_tax" =>
            sum(firms.tau_K_i .* firms.P_i .* firms.Y_i),
        "export_tax" => prop.tau_EXPORT * exports,
    )
    fiscal_rollup_id = "fiscal:government-revenue"
    push!(
        rollups,
        _cashflow_rollup(
            fiscal_rollup_id,
            "Government revenue",
            gov.Y_G,
            fiscal_components;
            valuation_basis = "government_revenue_equation",
        ),
    )

    function push_fiscal_component!(
            id,
            source,
            label,
            amount,
            component_id;
            explanation = "",
        )
        return _cashflow_push_edge!(
            edges,
            id,
            source,
            "government",
            amount;
            label,
            layer = "fiscal",
            market = "government_revenue",
            purpose = component_id,
            measure_kind = "model_equation",
            recognition = "realized_cash",
            evidence_basis = "model_equation",
            aggregation = "macro_component",
            direction_semantics = "payer_to_recipient",
            valuation_basis = "government_revenue_equation",
            realization_index,
            level = "macro",
            category = "fiscal",
            rollup_id = fiscal_rollup_id,
            component_id,
            parent_ids = [fiscal_rollup_id],
            explanation,
            summation_role = "component",
        )
    end

    push_fiscal_component!(
        "fiscal:employer-social-contribution",
        "production",
        "Employer social contribution",
        fiscal_components["employer_social_contribution"],
        "employer_social_contribution",
    )
    push_fiscal_component!(
        "fiscal:worker-social-contribution",
        "household:active-workers",
        "Worker social contribution",
        fiscal_components["worker_social_contribution"],
        "worker_social_contribution",
    )
    push_fiscal_component!(
        "fiscal:labour-income-tax",
        "household:active-workers",
        "Labour income tax",
        fiscal_components["labour_income_tax"],
        "labour_income_tax",
    )
    household_tax_bases = (
        (
            suffix = "active-workers",
            node = "household:active-workers",
            consumption = sum(model.w_act.C_h),
            investment = sum(model.w_act.I_h),
        ),
        (
            suffix = "inactive",
            node = "household:inactive",
            consumption = sum(model.w_inact.C_h),
            investment = sum(model.w_inact.I_h),
        ),
        (
            suffix = "firm-owners",
            node = "household:firm-owners",
            consumption = sum(firms.C_h),
            investment = sum(firms.I_h),
        ),
        (
            suffix = "bank-owner",
            node = "household:bank-owner",
            consumption = bank.C_h,
            investment = bank.I_h,
        ),
    )
    for cohort in household_tax_bases
        push_fiscal_component!(
            "fiscal:vat:$(cohort.suffix)",
            cohort.node,
            "VAT",
            prop.tau_VAT * cohort.consumption,
            "vat";
            explanation =
                "Exact cohort tax equation; seller allocation is unavailable because consumption and housing investment are combined before matching.",
        )
        push_fiscal_component!(
            "fiscal:household-capital-formation-tax:$(cohort.suffix)",
            cohort.node,
            "Household capital-formation tax",
            prop.tau_CF * cohort.investment,
            "household_capital_formation_tax";
            explanation =
                "Exact cohort tax equation; no receipt-level seller attribution is claimed.",
        )
    end
    firm_capital_income_tax =
        prop.tau_INC * (1 - prop.tau_FIRM) * prop.theta_DIV *
        firm_positive_profit
    bank_capital_income_tax =
        prop.tau_INC * (1 - prop.tau_FIRM) * prop.theta_DIV *
        bank_positive_profit
    push_fiscal_component!(
        "fiscal:capital-income-tax:firm-owners",
        "household:firm-owners",
        "Capital income tax · firm owners",
        firm_capital_income_tax,
        "capital_income_tax",
    )
    push_fiscal_component!(
        "fiscal:capital-income-tax:bank-owner",
        "household:bank-owner",
        "Capital income tax · bank owner",
        bank_capital_income_tax,
        "capital_income_tax",
    )
    push_fiscal_component!(
        "fiscal:corporate-tax:firms",
        "production",
        "Corporate tax · firms",
        prop.tau_FIRM * firm_positive_profit,
        "corporate_tax",
    )
    push_fiscal_component!(
        "fiscal:corporate-tax:bank",
        "bank",
        "Corporate tax · commercial bank",
        prop.tau_FIRM * bank_positive_profit,
        "corporate_tax",
    )
    push_fiscal_component!(
        "fiscal:product-tax",
        "production",
        "Product tax",
        fiscal_components["product_tax"],
        "product_tax",
    )
    push_fiscal_component!(
        "fiscal:production-tax",
        "production",
        "Production tax",
        fiscal_components["production_tax"],
        "production_tax",
    )
    push_fiscal_component!(
        "fiscal:export-tax",
        "outside-world",
        "Export tax",
        fiscal_components["export_tax"],
        "export_tax",
    )

    inactive_benefit =
        length(model.w_inact) * gov.sb_inact * P_bar_HH
    unemployment_benefit =
        prop.theta_UB *
        sum(model.w_act.w_h[model.w_act.O_h .== 0]) * P_bar_HH
    other_benefit = prop.H * gov.sb_other * P_bar_HH
    benefit_components = Dict{String, Float64}(
        "inactive_benefit" => inactive_benefit,
        "unemployment_benefit" => unemployment_benefit,
        "other_benefit" => other_benefit,
    )
    benefit_rollup_id = "fiscal:social-benefits"
    benefit_total = sum(values(benefit_components))
    push!(
        rollups,
        _cashflow_rollup(
            benefit_rollup_id,
            "Social benefits",
            benefit_total,
            benefit_components;
            valuation_basis = "government_benefit_equation",
        ),
    )

    function push_benefit!(
            id,
            target,
            label,
            amount,
            component_id,
        )
        return _cashflow_push_edge!(
            edges,
            id,
            "government",
            target,
            amount;
            label,
            layer = "benefits",
            market = "social_benefits",
            purpose = component_id,
            measure_kind = "model_equation",
            recognition = "realized_cash",
            evidence_basis = "model_equation",
            aggregation = "household_cohort",
            direction_semantics = "payer_to_recipient",
            valuation_basis = "government_benefit_equation",
            realization_index,
            level = "macro",
            category = "fiscal",
            rollup_id = benefit_rollup_id,
            component_id,
            parent_ids = [benefit_rollup_id],
            summation_role = "component",
        )
    end

    push_benefit!(
        "benefit:inactive",
        "household:inactive",
        "Inactive benefit",
        inactive_benefit,
        "inactive_benefit",
    )
    push_benefit!(
        "benefit:unemployment",
        "household:active-workers",
        "Unemployment benefit",
        unemployment_benefit,
        "unemployment_benefit",
    )
    other_benefit_counts = (
        ("active-workers", "household:active-workers", length(model.w_act)),
        ("inactive", "household:inactive", length(model.w_inact)),
        ("firm-owners", "household:firm-owners", length(firms)),
        ("bank-owner", "household:bank-owner", 1),
    )
    for (suffix, target, count) in other_benefit_counts
        push_benefit!(
            "benefit:other:$suffix",
            target,
            "Other benefit",
            count * gov.sb_other * P_bar_HH,
            "other_benefit",
        )
    end

    sector_sums = Dict{Tuple{Int, String}, Float64}()
    sector_specs = Dict{String, Any}()
    for i in eachindex(firms.ID)
        firm_id = Int(firms.ID[i])
        sector = Int(firms.G_i[i])
        wage = Float64(wages_by_firm[i])
        firm_deposit_account = _cashflow_deposit_account(
            "deposit:firm:$firm_id",
            "firm:$firm_id",
            opening.firm_deposits[i],
            closing.firm_deposits[i];
            level = "firm",
            aggregation = "none",
        )
        specs = (
            (
                kind = "wages",
                source = "firm:$firm_id",
                target = "household:active-workers",
                amount = wage,
                label = "Wages",
                layer = "wages",
                market = "income",
                purpose = "employee_compensation",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "consumer_price_basis",
                component_id = nothing,
                macro_id = "macro:wages",
            ),
            (
                kind = "employer_social_contribution",
                source = "firm:$firm_id",
                target = "government",
                amount = prop.tau_SIF * wage,
                label = "Employer social contribution",
                layer = "fiscal",
                market = "government_revenue",
                purpose = "employer_social_contribution",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "government_revenue_equation",
                component_id = "employer_social_contribution",
                macro_id = "fiscal:employer-social-contribution",
            ),
            (
                kind = "product_tax",
                source = "firm:$firm_id",
                target = "government",
                amount =
                    firms.tau_Y_i[i] * firms.P_i[i] * firms.Y_i[i],
                label = "Product tax",
                layer = "fiscal",
                market = "government_revenue",
                purpose = "product_tax",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "government_revenue_equation",
                component_id = "product_tax",
                macro_id = "fiscal:product-tax",
            ),
            (
                kind = "production_tax",
                source = "firm:$firm_id",
                target = "government",
                amount =
                    firms.tau_K_i[i] * firms.P_i[i] * firms.Y_i[i],
                label = "Production tax",
                layer = "fiscal",
                market = "government_revenue",
                purpose = "production_tax",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "government_revenue_equation",
                component_id = "production_tax",
                macro_id = "fiscal:production-tax",
            ),
            (
                kind = "corporate_tax",
                source = "firm:$firm_id",
                target = "government",
                amount = prop.tau_FIRM * max(0, firms.Pi_i[i]),
                label = "Corporate tax",
                layer = "fiscal",
                market = "government_revenue",
                purpose = "corporate_tax",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "government_revenue_equation",
                component_id = "corporate_tax",
                macro_id = "fiscal:corporate-tax:firms",
            ),
            (
                kind = "firm_dividend",
                source = "firm:$firm_id",
                target = "household:firm-owners",
                amount =
                    prop.theta_DIV * (1 - prop.tau_FIRM) *
                    max(0, firms.Pi_i[i]),
                label = "Firm dividend",
                layer = "dividends",
                market = "income",
                purpose = "firm_owner_dividend",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "after_corporate_tax_before_income_tax",
                component_id = nothing,
                macro_id = "macro:firm-dividends",
            ),
            (
                kind = "new_credit",
                source = "bank",
                target = "firm:$firm_id",
                amount = firms.DL_i[i],
                label = "New credit",
                layer = "credit",
                market = "credit",
                purpose = "credit_grant",
                measure_kind = "state_derived_flow",
                recognition = "realized_cash",
                evidence_basis = "model_state",
                valuation_basis = "nominal_book_value",
                component_id = nothing,
                macro_id = "macro:new-credit",
            ),
            (
                kind = "principal",
                source = "firm:$firm_id",
                target = "bank",
                amount = prop.theta * opening.firm_loans[i],
                label = "Loan principal",
                layer = "credit",
                market = "financial_settlement",
                purpose = "principal_repayment",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "opening_loan_book_value",
                component_id = nothing,
                macro_id = "macro:principal",
            ),
            (
                kind = "loan_interest",
                source = "firm:$firm_id",
                target = "bank",
                amount =
                    bank.r * (
                    opening.firm_loans[i] +
                        max(0, -opening.firm_deposits[i])
                ),
                label = "Loan and overdraft interest",
                layer = "interest",
                market = "financial_settlement",
                purpose = "loan_interest",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "opening_balance_at_current_quarter_rate",
                component_id = nothing,
                macro_id = "macro:firm-credit-interest",
            ),
            (
                kind = "deposit_interest",
                source = "bank",
                target = "firm:$firm_id",
                amount =
                    cb.r_bar * max(0, opening.firm_deposits[i]),
                label = "Deposit interest",
                layer = "interest",
                market = "financial_settlement",
                purpose = "deposit_interest",
                measure_kind = "model_equation",
                recognition = "realized_cash",
                evidence_basis = "model_equation",
                valuation_basis = "opening_balance_at_policy_rate",
                component_id = nothing,
                macro_id = "macro:firm-deposit-interest",
            ),
            (
                kind = "deposit_change",
                source = "firm:$firm_id",
                target = "bank",
                amount =
                    closing.firm_deposits[i] -
                    opening.firm_deposits[i],
                label = "Net firm deposit change",
                layer = "financial_stock_change",
                market = "balance_sheet",
                purpose = "deposit_change",
                measure_kind = "stock_change",
                recognition = "stock_non_cash",
                evidence_basis = "model_state",
                valuation_basis = "nominal_book_value",
                component_id = nothing,
                macro_id = "macro:firm-deposit-change",
            ),
            (
                kind = "loan_stock",
                source = "bank",
                target = "firm:$firm_id",
                amount = closing.firm_loans[i],
                label = "Outstanding firm loan",
                layer = "financial_stocks",
                market = "balance_sheet",
                purpose = "loan_stock",
                measure_kind = "stock",
                recognition = "stock_non_cash",
                evidence_basis = "model_state",
                valuation_basis = "closing_nominal_book_value",
                component_id = nothing,
                macro_id = "stock:firm-loans",
            ),
            (
                kind = "deposit_stock",
                source = "firm:$firm_id",
                target = "bank",
                amount = closing.firm_deposits[i],
                label = "Firm deposit or overdraft",
                layer = "financial_stocks",
                market = "balance_sheet",
                purpose = "deposit_stock",
                measure_kind = "stock",
                recognition = "stock_non_cash",
                evidence_basis = "model_state",
                valuation_basis = "closing_nominal_book_value",
                component_id = nothing,
                macro_id = "stock:firm-deposits",
            ),
        )
        for spec in specs
            sector_id = "institution:$(spec.kind):sector:$sector"
            _cashflow_push_edge!(
                edges,
                "institution:$(spec.kind):firm:$firm_id",
                spec.source,
                spec.target,
                spec.amount;
                label = spec.label,
                layer = spec.layer,
                market = spec.market,
                purpose = spec.purpose,
                measure_kind = spec.measure_kind,
                recognition = spec.recognition,
                evidence_basis = spec.evidence_basis,
                aggregation = "none",
                timing =
                    spec.measure_kind == "stock" ?
                    "closing_snapshot" : "quarterly_window",
                units =
                    spec.measure_kind == "stock" ?
                    "million_eur" : "million_eur_per_quarter",
                direction_semantics = "payer_to_recipient",
                valuation_basis = spec.valuation_basis,
                realization_index,
                level = "firm",
                category = spec.layer,
                rollup_id = sector_id,
                component_id = spec.component_id,
                parent_ids = [sector_id],
                ancestor_ids = [spec.macro_id],
                summation_role = "detail",
                attributes =
                    spec.kind in ("deposit_change", "deposit_stock") ?
                    merge(
                        firm_deposit_account,
                        Dict{String, Any}(
                            "account_edge_role" =>
                            spec.kind == "deposit_change" ?
                            "recorded_change" : "closing_stock",
                        ),
                    ) : Dict{String, Any}(),
            )
            key = (sector, spec.kind)
            sector_sums[key] =
                get(sector_sums, key, 0.0) + Float64(spec.amount)
            sector_specs[spec.kind] = spec
        end
    end

    for ((sector, kind), amount) in sector_sums
        spec = sector_specs[kind]
        source, target = _cashflow_sector_endpoints(kind, sector)
        sector_deposit_account = if kind in (
                "deposit_change",
                "deposit_stock",
            )
            sector_member = firms.G_i .== sector
            _cashflow_deposit_account(
                "deposit:sector:$sector",
                "sector:$sector",
                sum(opening.firm_deposits[sector_member]),
                sum(closing.firm_deposits[sector_member]);
                level = "sector",
                aggregation = "firm_to_sector_exact_sum",
            )
        else
            nothing
        end
        _cashflow_push_edge!(
            edges,
            "institution:$kind:sector:$sector",
            source,
            target,
            amount;
            label = spec.label,
            layer = spec.layer,
            market = spec.market,
            purpose = spec.purpose,
            measure_kind = spec.measure_kind,
            recognition = spec.recognition,
            evidence_basis = spec.evidence_basis,
            aggregation = "firm_to_sector_exact_sum",
            timing =
                spec.measure_kind == "stock" ?
                "closing_snapshot" : "quarterly_window",
            units =
                spec.measure_kind == "stock" ?
                "million_eur" : "million_eur_per_quarter",
            direction_semantics = "payer_to_recipient",
            valuation_basis = spec.valuation_basis,
            realization_index,
            level = "sector",
            category = spec.layer,
            rollup_id = spec.macro_id,
            component_id = spec.component_id,
            parent_ids = [spec.macro_id],
            summation_role = "component",
            attributes =
                kind in ("deposit_change", "deposit_stock") ?
                merge(
                    sector_deposit_account,
                    Dict{String, Any}(
                        "account_edge_role" =>
                        kind == "deposit_change" ?
                        "recorded_change" : "closing_stock",
                    ),
                ) : Dict{String, Any}(),
        )
    end

    macro_institution_kinds = (
        "wages",
        "firm_dividend",
        "new_credit",
        "principal",
        "loan_interest",
        "deposit_interest",
        "deposit_change",
        "loan_stock",
        "deposit_stock",
    )
    for kind in macro_institution_kinds
        spec = sector_specs[kind]
        amount = sum(
            value for ((_, candidate_kind), value) in sector_sums if
                candidate_kind == kind
        )
        source, target = _cashflow_macro_endpoints(kind)
        macro_deposit_account = if kind in (
                "deposit_change",
                "deposit_stock",
            )
            _cashflow_deposit_account(
                "deposit:production",
                "production",
                sum(opening.firm_deposits),
                sum(closing.firm_deposits);
                level = "macro",
                aggregation = "sector_to_macro_exact_sum",
            )
        else
            nothing
        end
        _cashflow_push_edge!(
            edges,
            spec.macro_id,
            source,
            target,
            amount;
            label = spec.label,
            layer = spec.layer,
            market = spec.market,
            purpose = spec.purpose,
            measure_kind = spec.measure_kind,
            recognition = spec.recognition,
            evidence_basis = spec.evidence_basis,
            aggregation = "sector_to_macro_exact_sum",
            timing =
                spec.measure_kind == "stock" ?
                "closing_snapshot" : "quarterly_window",
            units =
                spec.measure_kind == "stock" ?
                "million_eur" : "million_eur_per_quarter",
            direction_semantics = "payer_to_recipient",
            valuation_basis = spec.valuation_basis,
            realization_index,
            level = "macro",
            category = spec.layer,
            component_id = spec.component_id,
            summation_role = "rollup",
            explanation =
                "Exact macro rollup of the sector institution-flow edges.",
            attributes =
                kind in ("deposit_change", "deposit_stock") ?
                merge(
                    macro_deposit_account,
                    Dict{String, Any}(
                        "account_edge_role" =>
                        kind == "deposit_change" ?
                        "recorded_change" : "closing_stock",
                    ),
                ) : Dict{String, Any}(),
        )
    end

    household_cohorts = (
        (
            id = "active-workers",
            node = "household:active-workers",
            opening = opening.active_worker_deposits,
            closing = closing.active_worker_deposits,
        ),
        (
            id = "inactive",
            node = "household:inactive",
            opening = opening.inactive_household_deposits,
            closing = closing.inactive_household_deposits,
        ),
        (
            id = "firm-owners",
            node = "household:firm-owners",
            opening = opening.firm_owner_deposits,
            closing = closing.firm_owner_deposits,
        ),
        (
            id = "bank-owner",
            node = "household:bank-owner",
            opening = [opening.bank_owner_deposit],
            closing = [closing.bank_owner_deposit],
        ),
    )
    for cohort in household_cohorts
        opening_total = sum(cohort.opening)
        closing_total = sum(cohort.closing)
        cohort_deposit_account = _cashflow_deposit_account(
            "deposit:household:$(cohort.id)",
            cohort.node,
            opening_total,
            closing_total;
            level = "macro",
            aggregation = "household_cohort_exact_sum",
        )
        _cashflow_push_edge!(
            edges,
            "institution:household-deposit-change:$(cohort.id)",
            cohort.node,
            "bank",
            closing_total - opening_total;
            label = "Net household deposit change",
            layer = "financial_stock_change",
            market = "balance_sheet",
            purpose = "deposit_change",
            measure_kind = "stock_change",
            recognition = "stock_non_cash",
            evidence_basis = "model_state",
            aggregation = "household_cohort",
            valuation_basis = "nominal_book_value",
            realization_index,
            level = "macro",
            category = "deposits",
            rollup_id = "macro:household-deposit-change",
            parent_ids = ["macro:household-deposit-change"],
            summation_role = "component",
            attributes = merge(
                cohort_deposit_account,
                Dict{String, Any}(
                    "account_edge_role" => "recorded_change",
                ),
            ),
        )
        _cashflow_push_edge!(
            edges,
            "institution:household-deposit-stock:$(cohort.id)",
            cohort.node,
            "bank",
            closing_total;
            label = "Household deposit or overdraft",
            layer = "financial_stocks",
            market = "balance_sheet",
            purpose = "deposit_stock",
            measure_kind = "stock",
            recognition = "stock_non_cash",
            evidence_basis = "model_state",
            aggregation = "household_cohort",
            timing = "closing_snapshot",
            units = "million_eur",
            valuation_basis = "closing_nominal_book_value",
            realization_index,
            level = "macro",
            category = "deposits",
            rollup_id = "stock:household-deposits",
            parent_ids = ["stock:household-deposits"],
            summation_role = "component",
            attributes = merge(
                cohort_deposit_account,
                Dict{String, Any}(
                    "account_edge_role" => "closing_stock",
                ),
            ),
        )
        _cashflow_push_edge!(
            edges,
            "institution:household-deposit-interest:$(cohort.id)",
            "bank",
            cohort.node,
            cb.r_bar * sum(max.(0, cohort.opening));
            label = "Household deposit interest",
            layer = "interest",
            market = "financial_settlement",
            purpose = "deposit_interest",
            measure_kind = "model_equation",
            recognition = "realized_cash",
            evidence_basis = "model_equation",
            aggregation = "household_cohort",
            valuation_basis = "opening_balance_at_policy_rate",
            realization_index,
            level = "macro",
            category = "interest",
            rollup_id = "macro:household-deposit-interest",
            parent_ids = ["macro:household-deposit-interest"],
        )
        _cashflow_push_edge!(
            edges,
            "institution:household-overdraft-interest:$(cohort.id)",
            cohort.node,
            "bank",
            bank.r * sum(max.(0, -cohort.opening));
            label = "Household overdraft interest",
            layer = "interest",
            market = "financial_settlement",
            purpose = "overdraft_interest",
            measure_kind = "model_equation",
            recognition = "realized_cash",
            evidence_basis = "model_equation",
            aggregation = "household_cohort",
            valuation_basis = "opening_balance_at_current_quarter_rate",
            realization_index,
            level = "macro",
            category = "interest",
            rollup_id = "macro:household-credit-interest",
            parent_ids = ["macro:household-credit-interest"],
        )
    end

    household_deposit_account = _cashflow_deposit_account(
        "deposit:households",
        "households",
        sum(opening.household_deposits),
        sum(closing.household_deposits);
        level = "macro",
        aggregation = "household_cohort_to_macro_exact_sum",
    )
    _cashflow_push_edge!(
        edges,
        "macro:household-deposit-change",
        "households",
        "bank",
        household_deposit_account["recorded_change"];
        label = "Net household deposit change",
        layer = "financial_stock_change",
        market = "balance_sheet",
        purpose = "deposit_change",
        measure_kind = "stock_change",
        recognition = "stock_non_cash",
        evidence_basis = "model_state",
        aggregation = "household_cohort_to_macro_exact_sum",
        valuation_basis = "nominal_book_value",
        realization_index,
        level = "macro",
        category = "deposits",
        summation_role = "rollup",
        explanation =
            "Exact signed sum of the household-cohort deposit changes.",
        attributes = merge(
            household_deposit_account,
            Dict{String, Any}(
                "account_edge_role" => "recorded_change",
            ),
        ),
    )
    _cashflow_push_edge!(
        edges,
        "stock:household-deposits",
        "households",
        "bank",
        household_deposit_account["closing_value"];
        label = "Household deposits or overdrafts",
        layer = "financial_stocks",
        market = "balance_sheet",
        purpose = "deposit_stock",
        measure_kind = "stock",
        recognition = "stock_non_cash",
        evidence_basis = "model_state",
        aggregation = "household_cohort_to_macro_exact_sum",
        timing = "closing_snapshot",
        units = "million_eur",
        valuation_basis = "closing_nominal_book_value",
        realization_index,
        level = "macro",
        category = "deposits",
        summation_role = "rollup",
        explanation =
            "Exact signed sum of the household-cohort closing deposit positions.",
        attributes = merge(
            household_deposit_account,
            Dict{String, Any}(
                "account_edge_role" => "closing_stock",
            ),
        ),
    )

    bank_dividend =
        prop.theta_DIV * (1 - prop.tau_FIRM) * bank_positive_profit
    _cashflow_push_edge!(
        edges,
        "institution:bank-dividend",
        "bank",
        "household:bank-owner",
        bank_dividend;
        label = "Bank dividend",
        layer = "dividends",
        market = "income",
        purpose = "bank_owner_dividend",
        measure_kind = "model_equation",
        recognition = "realized_cash",
        evidence_basis = "model_equation",
        aggregation = "none",
        valuation_basis = "after_corporate_tax_before_income_tax",
        realization_index,
        level = "macro",
        category = "income",
        rollup_id = "macro:bank-dividends",
        parent_ids = ["macro:bank-dividends"],
    )
    _cashflow_push_edge!(
        edges,
        "institution:government-interest",
        "government",
        "central-bank",
        cb.r_G * opening.government_debt;
        label = "Government debt interest",
        layer = "interest",
        market = "financial_settlement",
        purpose = "government_debt_interest",
        measure_kind = "model_equation",
        recognition = "realized_cash",
        evidence_basis = "model_equation",
        aggregation = "none",
        valuation_basis = "opening_government_debt",
        realization_index,
        level = "macro",
        category = "interest",
    )
    _cashflow_push_edge!(
        edges,
        "institution:bank-reserve-interest",
        "central-bank",
        "bank",
        cb.r_bar * opening.bank_position;
        label = "Reserve-position interest",
        layer = "interest",
        market = "financial_settlement",
        purpose = "reserve_position_interest",
        measure_kind = "model_equation",
        recognition = "realized_cash",
        evidence_basis = "model_equation",
        aggregation = "none",
        valuation_basis = "opening_bank_position",
        realization_index,
        level = "macro",
        category = "interest",
    )
    _cashflow_push_edge!(
        edges,
        "institution:government-debt-change",
        "central-bank",
        "government",
        closing.government_debt - opening.government_debt;
        label = "Net government borrowing",
        layer = "financial_stock_change",
        market = "balance_sheet",
        purpose = "government_debt_change",
        measure_kind = "stock_change",
        recognition = "stock_non_cash",
        evidence_basis = "model_state",
        aggregation = "none",
        valuation_basis = "nominal_book_value",
        realization_index,
        level = "macro",
        category = "credit",
    )

    return edges, rollups
end

function _cashflow_payload(
        model,
        aggregates,
        pre_step,
        opening;
        run_id,
        dataset_id,
        scenario,
        period,
        quarter_index,
        summary_index,
        realization_index,
        realization_seed,
        ensemble_size,
    )
    firms, bank, cb = model.firms, model.bank, model.cb
    gov, rotw, prop = model.gov, model.rotw, model.prop
    closing = _cashflow_snapshot(model)

    household_consumption =
        sum(model.w_act.C_h) + sum(model.w_inact.C_h) +
        sum(firms.C_h) + bank.C_h
    household_investment =
        sum(model.w_act.I_h) + sum(model.w_inact.I_h) +
        sum(firms.I_h) + bank.I_h
    business_purchases =
        sum(firms.DM_i .* firms.P_bar_i) +
        sum(firms.I_i .* firms.P_CF_i)
    domestic_sales = sum(firms.P_i .* firms.Q_i)
    imports = sum(rotw.P_m .* rotw.Q_m)
    exports = rotw.C_l
    wages = sum(firms.w_i .* firms.N_i) * model.agg.P_bar_HH

    benefits_inactive =
        length(model.w_inact) * gov.sb_inact * model.agg.P_bar_HH
    benefits_unemployment =
        prop.theta_UB *
        sum(model.w_act.w_h[model.w_act.O_h .== 0]) *
        model.agg.P_bar_HH
    benefits_other = prop.H * gov.sb_other * model.agg.P_bar_HH
    benefits =
        benefits_inactive + benefits_unemployment + benefits_other

    positive_profits = sum(max.(0, firms.Pi_i)) + max(0, bank.Pi_k)
    social_employer = prop.tau_SIF * wages
    social_worker = prop.tau_SIW * wages
    income_tax = prop.tau_INC * (1 - prop.tau_SIW) * wages
    consumption_tax = prop.tau_VAT * household_consumption
    capital_formation_tax = prop.tau_CF * household_investment
    capital_income_tax =
        prop.tau_INC * (1 - prop.tau_FIRM) *
        prop.theta_DIV * positive_profits
    corporate_tax = prop.tau_FIRM * positive_profits
    product_tax = sum(firms.tau_Y_i .* firms.P_i .* firms.Y_i)
    production_tax = sum(firms.tau_K_i .* firms.P_i .* firms.Y_i)
    export_tax = prop.tau_EXPORT * exports
    household_taxes =
        social_worker + income_tax + consumption_tax +
        capital_formation_tax + capital_income_tax
    production_taxes =
        social_employer + corporate_tax + product_tax + production_tax

    dividends_firms =
        prop.theta_DIV * (1 - prop.tau_FIRM) *
        sum(max.(0, firms.Pi_i))
    dividends_bank =
        prop.theta_DIV * (1 - prop.tau_FIRM) * max(0, bank.Pi_k)
    new_credit = sum(firms.DL_i)
    effective_opening_loans = sum(opening.firm_loans)
    principal_repayment = prop.theta * effective_opening_loans
    firm_credit_interest =
        bank.r * (
        effective_opening_loans +
            sum(max.(0, -opening.firm_deposits))
    )
    household_credit_interest =
        bank.r * sum(max.(0, -opening.household_deposits))
    household_deposit_interest =
        cb.r_bar * sum(max.(0, opening.household_deposits))
    firm_deposit_interest =
        cb.r_bar * sum(max.(0, opening.firm_deposits))
    government_interest = cb.r_G * opening.government_debt
    bank_reserve_interest = cb.r_bar * opening.bank_position
    restart_financing =
        max(0.0, pre_step.bank_equity - opening.bank_equity)

    flows = Vector{Any}()
    _push_flow!(
        flows,
        "household-goods",
        "households",
        "goods-market",
        "Consumption + household investment",
        household_consumption + household_investment;
        category = "goods",
        explanation =
            "Realized household consumption and dwelling investment, before product taxes.",
    )
    _push_flow!(
        flows,
        "business-goods",
        "production",
        "goods-market",
        "Materials + capital goods",
        business_purchases;
        category = "goods",
        explanation =
            "Realized firm purchases. The model combines material and capital demand before seller matching.",
    )
    _push_flow!(
        flows,
        "government-goods",
        "government",
        "goods-market",
        "Government purchases",
        gov.C_j;
        category = "goods",
    )
    _push_flow!(
        flows,
        "exports",
        "outside-world",
        "goods-market",
        "Exports",
        exports;
        category = "external",
    )
    _push_flow!(
        flows,
        "domestic-sales",
        "goods-market",
        "production",
        "Domestic seller revenue",
        domestic_sales;
        category = "goods",
    )
    _push_flow!(
        flows,
        "imports",
        "goods-market",
        "outside-world",
        "Imports",
        imports;
        category = "external",
    )
    _push_flow!(
        flows,
        "wages",
        "production",
        "households",
        "Wages",
        wages;
        category = "income",
    )
    _push_flow!(
        flows,
        "benefits",
        "government",
        "households",
        "Social benefits",
        benefits;
        category = "fiscal",
    )
    _push_flow!(
        flows,
        "household-taxes",
        "households",
        "government",
        "Household taxes",
        household_taxes;
        category = "fiscal",
        explanation =
            "Employee contributions, income and dividend taxes, VAT, and household capital-formation tax.",
    )
    _push_flow!(
        flows,
        "production-taxes",
        "production",
        "government",
        "Firm taxes",
        production_taxes;
        category = "fiscal",
        explanation =
            "Employer contributions, corporate, product, and production taxes.",
    )
    _push_flow!(
        flows,
        "export-tax",
        "outside-world",
        "government",
        "Export tax",
        export_tax;
        category = "fiscal",
    )
    _push_flow!(
        flows,
        "firm-dividends",
        "production",
        "households",
        "Firm dividends",
        dividends_firms;
        category = "income",
    )
    _push_flow!(
        flows,
        "bank-dividends",
        "bank",
        "households",
        "Bank dividends",
        dividends_bank;
        category = "income",
    )
    _push_flow!(
        flows,
        "new-credit",
        "bank",
        "production",
        "New firm credit",
        new_credit;
        category = "credit",
    )
    _push_flow!(
        flows,
        "principal",
        "production",
        "bank",
        "Loan principal",
        principal_repayment;
        category = "credit",
    )
    _push_flow!(
        flows,
        "firm-credit-interest",
        "production",
        "bank",
        "Firm loan interest",
        firm_credit_interest;
        category = "interest",
    )
    _push_flow!(
        flows,
        "household-credit-interest",
        "households",
        "bank",
        "Household overdraft interest",
        household_credit_interest;
        category = "interest",
    )
    _push_flow!(
        flows,
        "household-deposit-interest",
        "bank",
        "households",
        "Household deposit interest",
        household_deposit_interest;
        category = "interest",
    )
    _push_flow!(
        flows,
        "firm-deposit-interest",
        "bank",
        "production",
        "Firm deposit interest",
        firm_deposit_interest;
        category = "interest",
    )
    _push_flow!(
        flows,
        "government-interest",
        "government",
        "central-bank",
        "Government debt interest",
        government_interest;
        category = "interest",
    )
    _push_signed_flow!(
        flows,
        "bank-reserve-interest",
        "central-bank",
        "bank",
        "Reserve-position interest",
        bank_reserve_interest;
        category = "interest",
        layer = "transactions",
        provenance = "exact_model_equation",
    )
    _push_flow!(
        flows,
        "restart-financing",
        "bank",
        "production",
        "Insolvent-firm restart financing",
        restart_financing;
        category = "credit",
        layer = "boundary_adjustment",
        explanation =
            "Bank recapitalization of existing insolvent firms at the quarter boundary; firm IDs are preserved.",
    )

    _push_signed_flow!(
        flows,
        "household-deposit-change",
        "households",
        "bank",
        "Net household saving",
        sum(closing.household_deposits) -
            sum(opening.household_deposits);
        category = "deposits",
    )
    _push_signed_flow!(
        flows,
        "firm-deposit-change",
        "production",
        "bank",
        "Net firm deposit change",
        sum(closing.firm_deposits) - sum(opening.firm_deposits);
        category = "deposits",
    )
    _push_signed_flow!(
        flows,
        "government-debt-change",
        "central-bank",
        "government",
        "Net government borrowing",
        closing.government_debt - opening.government_debt;
        category = "credit",
    )

    relationships, sector_relationships, outside_sectors =
        _cashflow_relationship_payload(model, aggregates)
    transaction_edges = Vector{Any}()
    transaction_totals = _cashflow_transaction_totals()
    observed_markets = String["business_goods"]
    if aggregates isa _CashflowCollection
        transaction_edges, transaction_totals, observed_markets =
            _cashflow_transaction_edges(
            model,
            aggregates;
            realization_index,
        )
    else
        transaction_totals["business_realized"] =
            sum(
            (edge["amount"] for edge in relationships);
            init = 0.0,
        )
        transaction_totals["business_capacity_counterfactual"] =
            sum(
            (
                edge["potential_amount"] for
                    edge in relationships
            );
            init = 0.0,
        )
        transaction_totals["all_realized"] =
            transaction_totals["business_realized"]
    end
    for edge in transaction_edges
        seller_sector = get(edge, "seller_sector", nothing)
        get(edge, "seller_kind", "") == "outside_supplier" &&
            seller_sector !== nothing &&
            push!(outside_sectors, Int(seller_sector))
    end
    institution_edges, rollups = _cashflow_institution_edges(
        model,
        opening,
        closing;
        realization_index,
    )
    macro_edges = _cashflow_macro_market_edges(
        flows;
        realization_index,
    )
    edges = vcat(transaction_edges, institution_edges, macro_edges)
    sort!(edges; by = edge -> String(edge["id"]))

    sector_count = length(model.agg.P_bar_g)
    sector_metadata_rows =
        _cashflow_sector_metadata_rows(dataset_id, sector_count)
    outside_nodes = [
        _cashflow_node(
                "outside:$sector",
                "External supplier · " *
                String(sector_metadata_rows[sector]["short_label"]),
                "outside_portal";
                group = "world",
                sector,
                attributes = Dict(
                    "sector_code" =>
                    sector_metadata_rows[sector]["code"],
                    "sector_label" =>
                    sector_metadata_rows[sector]["label"],
                ),
            ) for sector in sort!(collect(outside_sectors))
    ]

    institution_nodes = [
        _cashflow_node(
            "households",
            "Households",
            "households";
            metrics = Dict(
                "agents" =>
                    length(model.w_act) + length(model.w_inact) +
                    length(firms) + 1,
                "deposits" => sum(closing.household_deposits),
            ),
            attributes = Dict(
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:households",
                        "households",
                        sum(opening.household_deposits),
                        sum(closing.household_deposits);
                        level = "macro",
                        aggregation =
                            "household_cohort_to_macro_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "production",
            "$(String(dataset_id)) production network",
            "production";
            metrics = Dict(
                "firms" => length(firms),
                "sales" => domestic_sales,
                "employment" => sum(firms.N_i),
            ),
            attributes = Dict(
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:production",
                        "production",
                        sum(opening.firm_deposits),
                        sum(closing.firm_deposits);
                        level = "macro",
                        aggregation = "sector_to_macro_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "goods-market",
            "Products & services market",
            "market",
        ),
        _cashflow_node(
            "government",
            "Government",
            "government";
            metrics = Dict(
                "revenue" => gov.Y_G,
                "debt" => closing.government_debt,
            ),
        ),
        _cashflow_node(
            "bank",
            "Commercial bank",
            "bank";
            metrics = Dict(
                "equity" => closing.bank_equity,
                "position" => closing.bank_position,
            ),
        ),
        _cashflow_node(
            "central-bank",
            "Central bank",
            "central_bank";
            metrics = Dict(
                "equity" => closing.central_bank_equity,
                "policy_rate" => cb.r_bar,
            ),
        ),
        _cashflow_node(
            "outside-world",
            "External economy",
            "outside_world";
            group = "world",
            metrics = Dict(
                "external_position" => closing.external_position,
                "imports" => imports,
                "exports" => exports,
            ),
        ),
    ]
    append!(
        institution_nodes,
        _cashflow_cohort_nodes(
            model,
            closing;
            opening_snapshot = opening,
        ),
    )

    recorded_business =
        sum(
        (edge["amount"] for edge in relationships);
        init = 0.0,
    )
    potential_business =
        sum(
        (edge["potential_amount"] for edge in relationships);
        init = 0.0,
    )
    seller_cash = domestic_sales + imports
    buyer_cash =
        household_consumption + household_investment +
        business_purchases + gov.C_j + exports
    latest = lastindex(model.data.nominal_gdp)
    nominal_gdp_residual =
        model.data.nominal_gdp[latest] -
        model.data.nominal_household_consumption[latest] -
        model.data.nominal_government_consumption[latest] -
        model.data.nominal_capitalformation[latest] -
        model.data.nominal_exports[latest] +
        model.data.nominal_imports[latest]
    real_gdp_residual =
        model.data.real_gdp[latest] -
        model.data.real_household_consumption[latest] -
        model.data.real_government_consumption[latest] -
        model.data.real_capitalformation[latest] -
        model.data.real_exports[latest] +
        model.data.real_imports[latest]
    central_bank_balance, commercial_bank_balance =
        Bit.get_accounting_identity_banks(model)
    tolerance =
        1.0e-8 +
        1.0e-12 * max(
        seller_cash,
        buyer_cash,
        abs(gov.Y_G),
        sum(abs.(closing.firm_loans)),
        1.0,
    )
    business_traced = "business_goods" in observed_markets
    final_demand_traced = "final_demand" in observed_markets
    firm_loan_residuals =
        closing.firm_loans .-
        ((1 - prop.theta) .* opening.firm_loans .+ firms.DL_i)
    bank_equity_residual =
        closing.bank_equity -
        opening.bank_equity -
        (
        bank.Pi_k - dividends_bank -
            prop.tau_FIRM * max(0, bank.Pi_k)
    )
    government_debt_residual =
        closing.government_debt -
        opening.government_debt -
        (benefits + gov.C_j + government_interest - gov.Y_G)
    external_position_residual =
        closing.external_position -
        opening.external_position -
        (imports - (1 + prop.tau_EXPORT) * exports)
    central_bank_equity_residual =
        closing.central_bank_equity -
        opening.central_bank_equity -
        (government_interest - bank_reserve_interest)
    cohort_count =
        length(model.w_act) + length(model.w_inact) + length(firms) + 1
    diagnostics = Dict{String, Any}(
        "tolerance" => tolerance,
        "goods_market_residual" => seller_cash - buyer_cash,
        "business_trace_residual" =>
            business_traced ?
            transaction_totals["business_realized"] -
            business_purchases : nothing,
        "household_final_demand_trace_residual" =>
            final_demand_traced ?
            transaction_totals["household_final_demand_realized"] -
            (household_consumption + household_investment) : nothing,
        "government_final_demand_trace_residual" =>
            final_demand_traced ?
            transaction_totals["government_final_demand_realized"] -
            gov.C_j : nothing,
        "foreign_final_demand_trace_residual" =>
            final_demand_traced ?
            transaction_totals["foreign_final_demand_realized"] -
            exports : nothing,
        "all_market_trace_residual" =>
            business_traced && final_demand_traced ?
            transaction_totals["all_realized"] - seller_cash : nothing,
        "nominal_gdp_residual" => nominal_gdp_residual,
        "real_gdp_residual" => real_gdp_residual,
        "central_bank_balance_residual" => central_bank_balance,
        "commercial_bank_balance_residual" => commercial_bank_balance,
        "government_revenue_residual" =>
            gov.Y_G -
            (
            household_taxes + production_taxes + export_tax
        ),
        "government_debt_residual" => government_debt_residual,
        "external_position_residual" => external_position_residual,
        "central_bank_equity_residual" =>
            central_bank_equity_residual,
        "bank_equity_residual" => bank_equity_residual,
        "firm_loan_identity_max_residual" =>
            isempty(firm_loan_residuals) ?
            0.0 : maximum(abs.(firm_loan_residuals)),
        "household_cohort_count_residual" => cohort_count - prop.H,
        "potential_demand_not_cash" =>
            transaction_totals[
            "business_capacity_counterfactual",
        ] +
            transaction_totals[
            "final_demand_capacity_counterfactual",
        ],
        "legacy_business_trace_amount" => recorded_business,
        "legacy_potential_business_amount" => potential_business,
        "identity_kinds" => Dict(
            "goods_market_residual" => "independent",
            "business_trace_residual" => "independent",
            "household_final_demand_trace_residual" => "independent",
            "government_final_demand_trace_residual" => "independent",
            "foreign_final_demand_trace_residual" => "independent",
            "all_market_trace_residual" => "independent",
            "nominal_gdp_residual" => "independent",
            "real_gdp_residual" => "independent",
            "central_bank_balance_residual" => "independent",
            "commercial_bank_balance_residual" => "definition",
            "government_revenue_residual" => "independent",
            "government_debt_residual" => "independent",
            "external_position_residual" => "independent",
            "central_bank_equity_residual" => "independent",
            "bank_equity_residual" => "independent",
            "firm_loan_identity_max_residual" => "independent",
            "household_cohort_count_residual" => "definition",
        ),
    )
    diagnostic_checks = [
        key for key in keys(diagnostics["identity_kinds"]) if
            get(diagnostics, key, nothing) isa Real
    ]
    diagnostics["passed"] = all(
        abs(Float64(diagnostics[key])) <= tolerance for
            key in diagnostic_checks
    )
    stocks = _cashflow_stock_payload(opening, closing)
    relationship_columns =
        _cashflow_relationship_columns(relationships)
    sector_relationship_columns =
        _cashflow_sector_relationship_columns(sector_relationships)

    payload = Dict{String, Any}(
        "schema_version" => CASHFLOW_SCHEMA_VERSION,
        "trace_schema_version" => CASHFLOW_SCHEMA_VERSION,
        "api_schema_version" => CASHFLOW_API_SCHEMA_VERSION,
        "run_id" => String(run_id),
        "dataset_id" => String(dataset_id),
        "scenario" => String(scenario),
        "period" => String(period),
        "quarter_index" => Int(quarter_index),
        "summary_index" => Int(summary_index),
        "realization" => Dict(
            "index" => Int(realization_index),
            "seed" => Int(realization_seed),
            "ensemble_size" => Int(ensemble_size),
            "label" =>
                "Exact representative realization $(Int(realization_index)); macro charts summarize the full ensemble.",
        ),
        "timing" => Dict(
            "opening" => "after_insolvency_restructuring",
            "closing" => "after_quarter_settlement",
            "flow_window" => "one_quarter",
            "initial_period_has_flows" => false,
        ),
        "units" => _cashflow_units(dataset_id),
        "observability" => Dict(
            "institution_flows" => "exact_model_equations",
            "bilateral_business_goods" =>
                business_traced ?
                "exact_representative_realization" : "not_instrumented",
            "bilateral_goods_purpose" =>
                "materials_and_capital_goods_combined",
            "final_demand_counterparties" =>
                final_demand_traced ?
                "buyer_cohort_to_seller_firm_and_sector" :
                "not_instrumented",
            "capacity_counterfactual" =>
                business_traced || final_demand_traced ?
                "second_pass_unused_productive_capacity" :
                "not_instrumented",
            "potential_demand_is_cash" => false,
            "true_unmet_demand" => "not_instrumented",
            "observed_markets" => observed_markets,
        ),
        "capabilities" => Dict(
            "institution_flows" => true,
            "institution_components" => true,
            "sector_network" => true,
            "firm_network" => true,
            "business_counterparties" => business_traced,
            "final_demand_counterparties" => final_demand_traced,
            "capacity_counterfactual" =>
                business_traced || final_demand_traced,
            "true_unmet_demand" => false,
            "household_cohorts" => true,
            "node_stock_flow_reconciliation" => true,
            "opening_snapshot" => false,
            "normalized_edges" => true,
        ),
        "nodes" => institution_nodes,
        "sector_metadata" => sector_metadata_rows,
        "sectors" => _cashflow_sector_nodes(
            model;
            dataset_id,
            metadata_rows = sector_metadata_rows,
            opening_snapshot = opening,
            closing_snapshot = closing,
        ),
        "firms" => _cashflow_firm_nodes(
            model;
            dataset_id,
            metadata_rows = sector_metadata_rows,
            opening_snapshot = opening,
            closing_snapshot = closing,
        ),
        "outside_portals" => outside_nodes,
        "flows" => flows,
        "edges" => edges,
        "edge_count" => length(edges),
        "scale_domains_current_quarter" =>
            _cashflow_scale_domains(edges),
        "rollups" => rollups,
        "transaction_totals" => transaction_totals,
        "sector_relationship_columns" =>
            sector_relationship_columns,
        "sector_relationship_count" =>
            length(sector_relationships),
        "relationship_columns" => relationship_columns,
        "relationship_count" => length(relationships),
        "stocks" => stocks,
        "diagnostics" => diagnostics,
    )
    return _cashflow_apply_dataset_units!(payload, dataset_id)
end

"""
    _cashflow_opening_payload(model; ...)

Build the quarter-zero artifact immediately after model construction. It exposes
the calibrated, pre-restructuring stock state on the same timeline as quarterly
ledgers and intentionally contains no transaction or equation-flow edges.
"""
function _cashflow_opening_payload(
        model;
        run_id,
        dataset_id,
        scenario,
        period,
        realization_index,
        realization_seed,
        ensemble_size,
    )
    firms, bank, cb, gov, rotw = model.firms, model.bank, model.cb,
        model.gov, model.rotw
    snapshot = _cashflow_snapshot(model)
    sector_count = length(model.agg.P_bar_g)
    metadata_rows =
        _cashflow_sector_metadata_rows(dataset_id, sector_count)
    cohort_nodes = _cashflow_cohort_nodes(model, snapshot)
    institution_nodes = [
        _cashflow_node(
            "households",
            "Households",
            "households";
            metrics = Dict(
                "agents" =>
                    length(model.w_act) + length(model.w_inact) +
                    length(firms) + 1,
                "deposits" => sum(snapshot.household_deposits),
            ),
            attributes = Dict(
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:households",
                        "households",
                        sum(snapshot.household_deposits),
                        sum(snapshot.household_deposits);
                        level = "macro",
                        aggregation =
                            "household_cohort_to_macro_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "production",
            "$(String(dataset_id)) production network",
            "production";
            metrics = Dict(
                "firms" => length(firms),
                "employment" => sum(firms.N_i),
            ),
            attributes = Dict(
                "account_reconciliations" => [
                    _cashflow_deposit_account(
                        "deposit:production",
                        "production",
                        sum(snapshot.firm_deposits),
                        sum(snapshot.firm_deposits);
                        level = "macro",
                        aggregation = "sector_to_macro_exact_sum",
                    ),
                ],
            ),
        ),
        _cashflow_node(
            "goods-market",
            "Products & services market",
            "market",
        ),
        _cashflow_node(
            "government",
            "Government",
            "government";
            metrics = Dict("debt" => snapshot.government_debt),
        ),
        _cashflow_node(
            "bank",
            "Commercial bank",
            "bank";
            metrics = Dict(
                "equity" => snapshot.bank_equity,
                "position" => snapshot.bank_position,
            ),
        ),
        _cashflow_node(
            "central-bank",
            "Central bank",
            "central_bank";
            metrics = Dict(
                "equity" => snapshot.central_bank_equity,
                "policy_rate" => cb.r_bar,
            ),
        ),
        _cashflow_node(
            "outside-world",
            "External economy",
            "outside_world";
            group = "world",
            metrics = Dict(
                "external_position" => snapshot.external_position,
            ),
        ),
    ]
    append!(institution_nodes, cohort_nodes)
    central_bank_balance, commercial_bank_balance =
        Bit.get_accounting_identity_banks(model)
    tolerance =
        1.0e-8 +
        1.0e-12 * max(
        abs(snapshot.government_debt),
        sum(abs.(snapshot.firm_loans)),
        sum(abs.(snapshot.household_deposits)),
        1.0,
    )
    cohort_count =
        length(model.w_act) + length(model.w_inact) + length(firms) + 1
    diagnostics = Dict{String, Any}(
        "tolerance" => tolerance,
        "central_bank_balance_residual" => central_bank_balance,
        "commercial_bank_balance_residual" => commercial_bank_balance,
        "household_cohort_count_residual" =>
            cohort_count - model.prop.H,
        "identity_kinds" => Dict(
            "central_bank_balance_residual" => "independent",
            "commercial_bank_balance_residual" => "definition",
            "household_cohort_count_residual" => "definition",
        ),
    )
    diagnostics["passed"] = all(
        abs(Float64(diagnostics[key])) <= tolerance for
            key in keys(diagnostics["identity_kinds"])
    )
    relationship_columns =
        _cashflow_relationship_columns(Any[])
    sector_relationship_columns =
        _cashflow_sector_relationship_columns(Any[])

    payload = Dict{String, Any}(
        "schema_version" => CASHFLOW_SCHEMA_VERSION,
        "trace_schema_version" => CASHFLOW_SCHEMA_VERSION,
        "api_schema_version" => CASHFLOW_API_SCHEMA_VERSION,
        "run_id" => String(run_id),
        "dataset_id" => String(dataset_id),
        "scenario" => String(scenario),
        "period" => String(period),
        "quarter_index" => 0,
        "summary_index" => 1,
        "snapshot_kind" => "calibrated_pre_restructuring",
        "realization" => Dict(
            "index" => Int(realization_index),
            "seed" => Int(realization_seed),
            "ensemble_size" => Int(ensemble_size),
            "label" =>
                "Opening state for exact representative realization $(Int(realization_index)).",
        ),
        "timing" => Dict(
            "opening" => "calibrated_pre_restructuring",
            "closing" => "calibrated_pre_restructuring",
            "flow_window" => "none",
            "initial_period_has_flows" => false,
        ),
        "units" => _cashflow_units(dataset_id),
        "observability" => Dict(
            "institution_flows" =>
                "not_applicable_at_opening_snapshot",
            "bilateral_business_goods" =>
                "not_applicable_at_opening_snapshot",
            "final_demand_counterparties" =>
                "not_applicable_at_opening_snapshot",
            "potential_demand_is_cash" => false,
        ),
        "capabilities" => Dict(
            "institution_flows" => true,
            "institution_components" => true,
            "sector_network" => true,
            "firm_network" => true,
            "business_counterparties" => true,
            "final_demand_counterparties" => true,
            "capacity_counterfactual" => true,
            "true_unmet_demand" => false,
            "household_cohorts" => true,
            "node_stock_flow_reconciliation" => true,
            "opening_snapshot" => true,
            "normalized_edges" => true,
        ),
        "nodes" => institution_nodes,
        "sector_metadata" => metadata_rows,
        "sectors" => _cashflow_sector_nodes(
            model;
            dataset_id,
            metadata_rows,
        ),
        "firms" => _cashflow_firm_nodes(
            model;
            dataset_id,
            metadata_rows,
        ),
        "outside_portals" => Any[],
        "flows" => Any[],
        "edges" => Any[],
        "edge_count" => 0,
        "scale_domains_current_quarter" =>
            Dict{String, Any}(),
        "rollups" => Any[],
        "transaction_totals" => _cashflow_transaction_totals(),
        "sector_relationship_columns" =>
            sector_relationship_columns,
        "sector_relationship_count" => 0,
        "relationship_columns" => relationship_columns,
        "relationship_count" => 0,
        "stocks" => _cashflow_stock_payload(snapshot, snapshot),
        "diagnostics" => diagnostics,
    )
    return _cashflow_apply_dataset_units!(payload, dataset_id)
end

function _cashflow_adapt_legacy_edges(
        payload,
        relationships,
        sector_relationships,
    )
    edges = Vector{Any}()
    realization = get(payload, "realization", Dict{String, Any}())
    realization_index = Int(get(realization, "index", 1))
    for flow in get(payload, "flows", Any[])
        layer = String(get(flow, "layer", "legacy"))
        recognition =
            layer == "balance_sheet" ? "stock_non_cash" :
            layer == "boundary_adjustment" ? "boundary_adjustment" :
            "realized_cash"
        measure_kind =
            layer == "balance_sheet" ? "stock_change" :
            layer == "boundary_adjustment" ?
            "boundary_adjustment" : "legacy_model_value"
        _cashflow_push_edge!(
            edges,
            "legacy:macro:$(flow["id"])",
            flow["source"],
            flow["target"],
            flow["amount"];
            label = flow["label"],
            layer,
            market = "legacy_aggregate",
            purpose = String(flow["id"]),
            measure_kind,
            recognition,
            evidence_basis =
                String(get(flow, "provenance", "legacy_unspecified")),
            aggregation = "legacy_macro_adapter",
            timing =
                layer == "boundary_adjustment" ?
                "quarter_opening_boundary" : "quarterly_window",
            direction_semantics = "legacy_display_direction",
            valuation_basis = "legacy_unspecified",
            realization_index,
            level = "macro",
            category = String(get(flow, "category", layer)),
            explanation =
                "Adapted from quarter-ledger.v1; stable signed canonical direction and valuation detail were not retained.",
            attributes = Dict(
                "legacy_adapter" => true,
                "legacy_id" => String(flow["id"]),
            ),
        )
    end

    function push_legacy_relationship!(
            row,
            level,
            prefix,
        )
        realized = Float64(get(row, "amount", 0.0))
        potential = Float64(get(row, "potential_amount", 0.0))
        realized > 1.0e-12 && _cashflow_push_edge!(
            edges,
            "legacy:$prefix:realized:$(row["id"])",
            row["source"],
            row["target"],
            realized;
            label = "Business inputs",
            layer = "products",
            market = "business_goods",
            purpose = "business_inputs",
            measure_kind = "cash_transaction",
            recognition = "realized_cash",
            evidence_basis = "transaction_event",
            aggregation =
                level == "firm" ?
                "exact_bilateral_matches" :
                "firm_matches_to_sector_pair",
            direction_semantics = "buyer_to_seller",
            valuation_basis = "seller_price",
            realization_index,
            level,
            category = "business",
            quantity = Float64(get(row, "quantity", 0.0)),
            match_count = Int(get(row, "transaction_count", 0)),
            attributes = Dict(
                "legacy_adapter" => true,
                "stage" => "realized",
            ),
        )
        potential > 1.0e-12 && _cashflow_push_edge!(
            edges,
            "legacy:$prefix:capacity-counterfactual:$(row["id"])",
            row["source"],
            row["target"],
            potential;
            label = "Capacity-counterfactual business match",
            layer = "capacity_counterfactual",
            market = "business_goods",
            purpose = "business_inputs",
            measure_kind = "counterfactual_match",
            recognition = "capacity_counterfactual",
            evidence_basis = "transaction_event",
            aggregation =
                level == "firm" ?
                "exact_bilateral_matches" :
                "firm_matches_to_sector_pair",
            direction_semantics = "buyer_to_seller",
            valuation_basis = "seller_price",
            realization_index,
            level,
            category = "business",
            quantity =
                Float64(get(row, "potential_quantity", 0.0)),
            match_count =
                Int(get(row, "potential_match_count", 0)),
            explanation =
                "Second-pass unused-capacity match; excluded from cash totals.",
            attributes = Dict(
                "legacy_adapter" => true,
                "stage" => "capacity_counterfactual",
            ),
        )
        return nothing
    end

    for row in relationships
        push_legacy_relationship!(row, "firm", "business")
    end
    for row in sector_relationships
        push_legacy_relationship!(
            row,
            "sector",
            "sector-business",
        )
    end
    sort!(edges; by = edge -> String(edge["id"]))
    return edges
end

function _cashflow_filter_values(value)
    value === nothing && return nothing
    values = if value isa AbstractString
        split(value, ',')
    elseif value isa AbstractVector || value isa Tuple || value isa Set
        collect(value)
    else
        Any[value]
    end
    normalized = Set(
        strip(string(item)) for item in values if
            !isempty(strip(string(item)))
    )
    return isempty(normalized) ? nothing : normalized
end

function _cashflow_layer_filter_values(value)
    values = _cashflow_filter_values(value)
    values === nothing && return nothing
    return Set(
        _cashflow_semantic_layer(item; category = item) for
            item in values
    )
end

function _cashflow_level_rank(level::AbstractString)
    level == "macro" && return 1
    level == "sector" && return 2
    level == "firm" && return 3
    level == "all" && return typemax(Int)
    throw(ArgumentError("level must be macro, sector, firm, or all"))
end

function _cashflow_edge_in_level(edge, requested_level::AbstractString)
    requested_level == "all" && return true
    edge_level = String(get(edge, "level", "macro"))
    return _cashflow_level_rank(edge_level) <=
        _cashflow_level_rank(requested_level)
end

function _cashflow_edge_matches(
        edge;
        focus = nothing,
        parent_id = nothing,
        edge_id = nothing,
        layers = nothing,
        recognition = nothing,
        direction = nothing,
        min_amount::Real = 0.0,
        include_counterfactual::Bool = true,
        prepared_layer_filter = missing,
        prepared_recognition_filter = missing,
        prepared_focus_node = missing,
    )
    amount = abs(_cashflow_edge_value(edge))
    amount >= min_amount || return false
    edge_id !== nothing &&
        String(get(edge, "id", "")) != String(edge_id) && return false
    if parent_id !== nothing
        requested_parent = String(parent_id)
        rollup = get(edge, "rollup_id", nothing)
        parents = get(edge, "parent_ids", Any[])
        # `parent_id` always means one hierarchy hop. `rollup_id` is the
        # authoritative primary immediate parent when present. This also
        # safely reads early v2 artifacts whose `parent_ids` incorrectly
        # mixed the immediate parent with higher ancestors. Edges without a
        # rollup retain support for multiple direct parents via `parent_ids`.
        # Compare nested JSON3 arrays lazily to keep queries linear.
        immediate_parent_matches = if rollup !== nothing
            String(rollup) == requested_parent
        elseif parents isa AbstractString
            String(parents) == requested_parent
        else
            any(parent -> String(parent) == requested_parent, parents)
        end
        immediate_parent_matches || return false
    end
    edge_recognition = String(get(edge, "recognition", ""))
    !include_counterfactual &&
        edge_recognition == "capacity_counterfactual" && return false
    layer_filter = prepared_layer_filter === missing ?
        _cashflow_layer_filter_values(layers) : prepared_layer_filter
    edge_layer = _cashflow_semantic_layer(
        get(edge, "layer", "");
        category = get(edge, "category", ""),
        market = get(edge, "market", ""),
        purpose = get(edge, "purpose", ""),
    )
    layer_filter !== nothing &&
        !(edge_layer in layer_filter) &&
        return false
    recognition_filter = prepared_recognition_filter === missing ?
        _cashflow_filter_values(recognition) : prepared_recognition_filter
    recognition_filter !== nothing &&
        !(edge_recognition in recognition_filter) && return false

    focus_node = if prepared_focus_node !== missing
        prepared_focus_node
    elseif focus === nothing
        nothing
    else
        focus_text = string(focus)
        if tryparse(Int, focus_text) !== nothing
            "firm:$focus_text"
        else
            focus_text
        end
    end
    source = String(get(edge, "source", ""))
    target = String(get(edge, "target", ""))
    if focus_node !== nothing
        focus_node in (source, target) || return false
    end
    direction_value =
        direction === nothing ? "" : lowercase(String(direction))
    if direction_value in ("in", "incoming")
        focus_node === nothing &&
            throw(ArgumentError("incoming direction requires focus"))
        target == focus_node || return false
    elseif direction_value in ("out", "outgoing")
        focus_node === nothing &&
            throw(ArgumentError("outgoing direction requires focus"))
        source == focus_node || return false
    elseif direction_value in (
            "money",
            "product",
            "products",
            "goods",
            "physical",
        )
        nothing
    elseif !isempty(direction_value) &&
            direction_value != "both" &&
            direction_value !=
            lowercase(String(get(edge, "direction_semantics", "")))
        return false
    end
    return true
end

function _cashflow_edge_sort!(edges)
    sort!(
        edges;
        by = edge -> (
            -abs(_cashflow_edge_value(edge)),
            String(edge["id"]),
        ),
    )
    return edges
end

function _cashflow_fnv1a(value::AbstractString)
    hash = UInt64(0xcbf29ce484222325)
    for byte in codeunits(value)
        hash = (hash ⊻ UInt64(byte)) * UInt64(0x00000100000001b3)
    end
    return string(hash; base = 16, pad = 16)
end

function _cashflow_query_digest(identity, query)
    parts = String[String(identity)]
    for key in sort!(collect(keys(query)))
        value = query[key]
        normalized = if value isa AbstractVector || value isa Set ||
                value isa Tuple
            join(sort!(string.(collect(value))), ",")
        else
            string(value)
        end
        push!(parts, "$(String(key))=$normalized")
    end
    return _cashflow_fnv1a(join(parts, "\n"))
end

function _cashflow_decode_cursor(cursor, digest)
    cursor === nothing && return 0
    pieces = split(String(cursor), ':')
    length(pieces) == 3 && pieces[1] == "cf2" &&
        pieces[2] == digest ||
        throw(ArgumentError("cursor does not match this cash-flow query"))
    offset = tryparse(Int, pieces[3])
    offset !== nothing && offset >= 0 ||
        throw(ArgumentError("invalid cash-flow cursor offset"))
    return offset
end

function _cashflow_coverage_by_domain(total, matching, returned)
    # Coverage is requested on every graph query. Accumulate the three views in
    # one pass each instead of rescanning every edge once per measure domain.
    # The latter becomes quadratic in the number of domains on full traces.
    accumulators = Dict{String, Dict{String, Float64}}()
    function accumulate!(edges, count_key::String, amount_key::String)
        for edge in edges
            domain = _cashflow_edge_domain(edge)
            values = get!(accumulators, domain) do
                Dict{String, Float64}(
                    "count_total" => 0.0,
                    "count_matching" => 0.0,
                    "count_returned" => 0.0,
                    "amount_total" => 0.0,
                    "amount_matching" => 0.0,
                    "amount_returned" => 0.0,
                )
            end
            values[count_key] += 1.0
            values[amount_key] += abs(_cashflow_edge_value(edge))
        end
        return
    end
    accumulate!(total, "count_total", "amount_total")
    accumulate!(matching, "count_matching", "amount_matching")
    accumulate!(returned, "count_returned", "amount_returned")

    result = Dict{String, Any}()
    for domain in sort!(collect(keys(accumulators)))
        values = accumulators[domain]
        amount_total = values["amount_total"]
        amount_matching = values["amount_matching"]
        amount_returned = values["amount_returned"]
        result[domain] = Dict{String, Any}(
            "count_total" => Int(values["count_total"]),
            "count_matching" => Int(values["count_matching"]),
            "count_returned" => Int(values["count_returned"]),
            "amount_total" => amount_total,
            "amount_matching" => amount_matching,
            "amount_returned" => amount_returned,
            "amount_omitted" => max(0.0, amount_matching - amount_returned),
            "matching_fraction" =>
                amount_total > 0 ? amount_matching / amount_total : 1.0,
            "returned_fraction" =>
                amount_matching > 0 ? amount_returned / amount_matching : 1.0,
        )
    end
    return result
end

function _cashflow_apply_coverage(edges, coverage::Real)
    0 < coverage <= 1 ||
        throw(ArgumentError("coverage must be greater than 0 and at most 1"))
    coverage >= 1 && return copy(edges)
    by_domain = Dict{String, Vector{Any}}()
    for edge in edges
        push!(
            get!(by_domain, _cashflow_edge_domain(edge), Any[]),
            edge,
        )
    end
    selected_ids = Set{String}()
    for domain_edges in values(by_domain)
        total = sum(
            abs(_cashflow_edge_value(edge)) for edge in domain_edges
        )
        threshold = coverage * total
        cumulative = 0.0
        for edge in domain_edges
            cumulative >= threshold && break
            push!(selected_ids, String(edge["id"]))
            cumulative += abs(_cashflow_edge_value(edge))
        end
    end
    return [edge for edge in edges if String(edge["id"]) in selected_ids]
end

"""
    _cashflow_query_edges(edges; ...)

Pure deterministic filtering, compatible-domain coverage selection, and cursor
pagination. Cursor identity should include run, trace schema, and quarter.
"""
function _cashflow_query_edges(
        edges;
        level::AbstractString = "sector",
        focus = nothing,
        parent_id = nothing,
        edge_id = nothing,
        layers = nothing,
        recognition = nothing,
        direction = nothing,
        min_amount::Real = 0.0,
        coverage::Real = 1.0,
        page_size::Integer = 480,
        cursor = nothing,
        include_counterfactual::Bool = true,
        query_identity::AbstractString = "",
    )
    1 <= page_size <= 5000 ||
        throw(ArgumentError("page_size must be between 1 and 5000"))
    min_amount >= 0 ||
        throw(ArgumentError("min_amount must be non-negative"))
    base = [
        edge for edge in edges if
            _cashflow_edge_in_level(edge, level)
    ]
    prepared_layer_filter = _cashflow_layer_filter_values(layers)
    prepared_recognition_filter = _cashflow_filter_values(recognition)
    prepared_focus_node = if focus === nothing
        nothing
    else
        focus_text = string(focus)
        tryparse(Int, focus_text) !== nothing ?
            "firm:$focus_text" : focus_text
    end
    matching = [
        edge for edge in base if
            _cashflow_edge_matches(
                edge;
                focus,
                parent_id,
                edge_id,
                layers,
                recognition,
                direction,
                min_amount,
                include_counterfactual,
                prepared_layer_filter,
                prepared_recognition_filter,
                prepared_focus_node,
            )
    ]
    _cashflow_edge_sort!(matching)
    coverage_selected =
        _cashflow_apply_coverage(matching, coverage)
    query = Dict{String, Any}(
        "level" => level,
        "focus" => something(focus, ""),
        "parent_id" => something(parent_id, ""),
        "edge_id" => something(edge_id, ""),
        "layers" =>
            something(_cashflow_filter_values(layers), Set{String}()),
        "recognition" =>
            something(
            _cashflow_filter_values(recognition),
            Set{String}(),
        ),
        "direction" => something(direction, ""),
        "min_amount" => Float64(min_amount),
        "coverage" => Float64(coverage),
        "page_size" => Int(page_size),
        "include_counterfactual" => include_counterfactual,
    )
    digest = _cashflow_query_digest(query_identity, query)
    offset = _cashflow_decode_cursor(cursor, digest)
    offset <= length(coverage_selected) ||
        throw(ArgumentError("cursor offset exceeds matching edge count"))
    stop = min(length(coverage_selected), offset + Int(page_size))
    returned =
        offset == stop ? Any[] :
        coverage_selected[(offset + 1):stop]
    next_cursor =
        stop < length(coverage_selected) ?
        "cf2:$digest:$stop" : nothing
    return Dict{String, Any}(
        "edges" => returned,
        "coverage" =>
            _cashflow_coverage_by_domain(base, matching, returned),
        "count_total" => length(base),
        "count_matching" => length(matching),
        "count_selected_for_coverage" =>
            length(coverage_selected),
        "count_returned" => length(returned),
        "cursor" => cursor,
        "next_cursor" => next_cursor,
        "query_digest" => digest,
    )
end

function _cashflow_export_edges(
        edges;
        level::AbstractString = "all",
        focus = nothing,
        parent_id = nothing,
        edge_id = nothing,
        layers = nothing,
        recognition = nothing,
        direction = nothing,
        min_amount::Real = 0.0,
        include_counterfactual::Bool = true,
    )
    exported = [
        edge for edge in edges if
            _cashflow_edge_in_level(edge, level) &&
            _cashflow_edge_matches(
                edge;
                focus,
                parent_id,
                edge_id,
                layers,
                recognition,
                direction,
                min_amount,
                include_counterfactual,
            )
    ]
    return _cashflow_edge_sort!(exported)
end

const CASHFLOW_EDGE_ENCODING = "json-utf8.v1"
const CASHFLOW_EDGE_ENCODING_GZIP = "json-utf8-gzip.v1"
const CASHFLOW_ARTIFACT_CACHE_MAX_ENTRIES = 4
const _CASHFLOW_ARTIFACT_CACHE_LOCK = ReentrantLock()
const _CASHFLOW_ARTIFACT_CACHE = Dict{String, Any}()
const _CASHFLOW_ARTIFACT_CACHE_CLOCK = Ref{UInt64}(0)

"""
    _cashflow_compact_payload!(payload; drop_legacy_columns = true)

Encode the heterogeneous normalized edge dictionaries once as homogeneous UTF-8
bytes before JLD2 persistence. This avoids JLD2 datatype-reconstruction
ambiguities and lets its file-level compression operate on one compact array.
The in-memory payload is intentionally mutated only after run-wide scale-domain
collection has consumed `payload["edges"]`.
"""
function _cashflow_compact_payload!(
        payload;
        drop_legacy_columns::Bool = true,
    )
    edges = get(payload, "edges", Any[])
    payload["edge_count"] =
        Int(get(payload, "edge_count", length(edges)))
    payload["edge_encoding"] = CASHFLOW_EDGE_ENCODING_GZIP
    raw_bytes = Vector{UInt8}(codeunits(JSON3.write(edges)))
    payload["edge_uncompressed_bytes"] = length(raw_bytes)
    payload["edge_bytes"] = transcode(GzipCompressor(level = 1), raw_bytes)
    payload["edge_compressed_bytes"] = length(payload["edge_bytes"])
    haskey(payload, "edges") && delete!(payload, "edges")
    if drop_legacy_columns
        haskey(payload, "relationship_columns") &&
            delete!(payload, "relationship_columns")
        haskey(payload, "sector_relationship_columns") &&
            delete!(payload, "sector_relationship_columns")
        payload["legacy_relationship_columns_retained"] = false
    else
        payload["legacy_relationship_columns_retained"] = true
    end
    return payload
end

function _cashflow_complete_edges(payload)
    haskey(payload, "edges") && return collect(payload["edges"])
    if haskey(payload, "edge_bytes")
        encoding =
            String(get(payload, "edge_encoding", CASHFLOW_EDGE_ENCODING))
        encoding in (CASHFLOW_EDGE_ENCODING, CASHFLOW_EDGE_ENCODING_GZIP) ||
            throw(
            ArgumentError(
                "Unsupported cash-flow edge encoding: $encoding",
            ),
        )
        encoded_bytes = Vector{UInt8}(payload["edge_bytes"])
        raw_bytes = if encoding == CASHFLOW_EDGE_ENCODING_GZIP
            transcode(GzipDecompressor, encoded_bytes)
        else
            encoded_bytes
        end
        decoded = JSON3.read(String(raw_bytes))
        decoded isa AbstractVector ||
            throw(ArgumentError("Encoded cash-flow edges must be an array"))
        return collect(decoded)
    end
    relationship_columns =
        get(payload, "relationship_columns", nothing)
    sector_relationship_columns =
        get(payload, "sector_relationship_columns", nothing)
    relationships = Any[]
    sector_relationships = Any[]
    if relationship_columns !== nothing
        relationships, _ = _cashflow_materialize_relationships(
            relationship_columns;
            include_potential = true,
            limit = typemax(Int),
        )
    end
    if sector_relationship_columns !== nothing
        sector_relationships, _ =
            _cashflow_materialize_sector_relationships(
            sector_relationship_columns;
            include_potential = true,
            limit = typemax(Int),
        )
    end
    return _cashflow_adapt_legacy_edges(
        payload,
        relationships,
        sector_relationships,
    )
end

function _cashflow_artifact_signature(path::AbstractString)
    metadata = stat(path)
    return (
        path = abspath(path),
        size = metadata.size,
        mtime = metadata.mtime,
    )
end

"""
    _cashflow_cached_artifact(trace_path)

Load a persisted quarter once and retain a bounded set of decoded, immutable
edge tables. Each caller receives its own shallow metadata dictionary because
the response builder annotates and removes fields, while the cached edge vector
is only ever read. File size and modification time invalidate stale entries.
Four maximum Standard-profile quarters bound the server-side memory budget.
"""
function _cashflow_cached_artifact(trace_path::AbstractString)
    canonical_path = abspath(trace_path)
    signature = _cashflow_artifact_signature(canonical_path)
    return lock(_CASHFLOW_ARTIFACT_CACHE_LOCK) do
        _CASHFLOW_ARTIFACT_CACHE_CLOCK[] += 1
        access = _CASHFLOW_ARTIFACT_CACHE_CLOCK[]
        cached = get(_CASHFLOW_ARTIFACT_CACHE, canonical_path, nothing)
        if cached !== nothing && cached.signature == signature
            _CASHFLOW_ARTIFACT_CACHE[canonical_path] = merge(cached, (; access))
            return copy(cached.payload), cached.edges
        end

        raw_payload = load(canonical_path, "payload")
        edges = _cashflow_complete_edges(raw_payload)
        payload = Dict{String, Any}(
            String(key) => value for (key, value) in pairs(raw_payload)
        )
        haskey(payload, "edges") && delete!(payload, "edges")
        haskey(payload, "edge_bytes") && delete!(payload, "edge_bytes")
        _CASHFLOW_ARTIFACT_CACHE[canonical_path] =
            (; signature, payload, edges, access)

        while length(_CASHFLOW_ARTIFACT_CACHE) >
                CASHFLOW_ARTIFACT_CACHE_MAX_ENTRIES
            victim = first(
                sort!(
                    collect(keys(_CASHFLOW_ARTIFACT_CACHE));
                    by = path -> _CASHFLOW_ARTIFACT_CACHE[path].access,
                ),
            )
            delete!(_CASHFLOW_ARTIFACT_CACHE, victim)
        end
        return copy(payload), edges
    end
end

function _cashflow_clear_artifact_cache!()
    lock(_CASHFLOW_ARTIFACT_CACHE_LOCK) do
        empty!(_CASHFLOW_ARTIFACT_CACHE)
        _CASHFLOW_ARTIFACT_CACHE_CLOCK[] = 0
    end
    return nothing
end

function _cashflow_complete_edges(
        run_path::AbstractString;
        quarter,
    )
    manifest = _cashflow_manifest(run_path)
    quarter_index = Int(quarter)
    available = Int.(collect(manifest["quarters"]))
    quarter_index in available ||
        throw(ApiError(400, "Quarter is outside the available cash-flow trace"))
    trace_path =
        joinpath(run_path, "cashflow-$(quarter_index).jld2")
    isfile(trace_path) ||
        throw(ApiError(404, "Cash-flow quarter not ready"))
    _, edges = _cashflow_cached_artifact(trace_path)
    return edges
end

function _cashflow_export_payload(
        run_path::AbstractString;
        quarter,
        level::AbstractString = "all",
        focus = nothing,
        parent_id = nothing,
        edge_id = nothing,
        layers = nothing,
        recognition = nothing,
        direction = nothing,
        min_amount::Real = 0.0,
        include_counterfactual::Bool = true,
    )
    manifest = _cashflow_manifest(run_path)
    quarter_index = Int(quarter)
    available = Int.(collect(manifest["quarters"]))
    quarter_index in available ||
        throw(ApiError(400, "Quarter is outside the available cash-flow trace"))
    trace_path =
        joinpath(run_path, "cashflow-$(quarter_index).jld2")
    isfile(trace_path) ||
        throw(ApiError(404, "Cash-flow quarter not ready"))
    payload, complete_edges = _cashflow_cached_artifact(trace_path)
    exported = try
        _cashflow_export_edges(
            complete_edges;
            level,
            focus,
            parent_id,
            edge_id,
            layers,
            recognition,
            direction,
            min_amount,
            include_counterfactual,
        )
    catch error
        error isa ArgumentError || rethrow()
        throw(ApiError(400, error.msg))
    end
    trace_schema_version = String(
        get(
            payload,
            "trace_schema_version",
            get(
                payload,
                "schema_version",
                CASHFLOW_LEGACY_SCHEMA_VERSION,
            ),
        ),
    )
    return Dict{String, Any}(
        "trace_schema_version" => trace_schema_version,
        "api_schema_version" => CASHFLOW_API_SCHEMA_VERSION,
        "run_id" => String(get(payload, "run_id", basename(run_path))),
        "quarter_index" => quarter_index,
        "period" => String(get(payload, "period", "")),
        "capabilities" =>
            get(payload, "capabilities", Dict{String, Any}()),
        "count" => length(exported),
        "edges" => exported,
    )
end

function _cashflow_numeric_state!(state, path, value, seen)
    if value isa Bool
        state[path] = value
    elseif value isa Real
        state[path] = Float64(value)
    elseif value isa AbstractArray{Bool}
        state[path] = copy(value)
    elseif value isa AbstractArray{<:Real}
        state[path] = Float64.(value)
    elseif value isa AbstractDict
        for key in sort!(collect(keys(value)); by = string)
            _cashflow_numeric_state!(
                state,
                "$path[$(string(key))]",
                value[key],
                seen,
            )
        end
    elseif value isa NamedTuple
        for name in keys(value)
            _cashflow_numeric_state!(
                state,
                "$path.$(String(name))",
                getproperty(value, name),
                seen,
            )
        end
    elseif value isa Tuple || value isa AbstractArray
        for (index, child) in pairs(value)
            _cashflow_numeric_state!(
                state,
                "$path[$index]",
                child,
                seen,
            )
        end
    elseif !(
            value isa AbstractString || value isa Symbol ||
                value isa Function || value isa Module || value isa Type ||
                value === nothing
        ) && fieldcount(typeof(value)) > 0
        if Base.ismutabletype(typeof(value))
            haskey(seen, value) && return state
            seen[value] = nothing
        end
        for name in fieldnames(typeof(value))
            _cashflow_numeric_state!(
                state,
                "$path.$(String(name))",
                getfield(value, name),
                seen,
            )
        end
    end
    return state
end

"""
    _cashflow_numeric_state(model)

Capture all recursively reachable numeric model state. This is intended for
deterministic observer-neutrality tests, not serialization.
"""
function _cashflow_numeric_state(model)
    state = Dict{String, Any}()
    return _cashflow_numeric_state!(
        state,
        "model",
        model,
        IdDict{Any, Nothing}(),
    )
end

"""
    _cashflow_logger_neutrality(untraced_model, traced_model; atol, rtol)

Compare complete numeric model states after otherwise identical steps. Returns
a bounded mismatch report suitable for focused tests and diagnostics.
"""
function _cashflow_logger_neutrality(
        untraced_model,
        traced_model;
        atol::Real = 0.0,
        rtol::Real = 0.0,
    )
    left = _cashflow_numeric_state(untraced_model)
    right = _cashflow_numeric_state(traced_model)
    all_keys = sort!(collect(union(Set(keys(left)), Set(keys(right)))))
    mismatches = Vector{Any}()
    mismatch_count = 0
    max_abs_difference = 0.0
    for key in all_keys
        if !haskey(left, key) || !haskey(right, key)
            mismatch_count += 1
            length(mismatches) < 100 && push!(
                mismatches,
                Dict(
                    "path" => key,
                    "reason" => "missing_state",
                ),
            )
            continue
        end
        a, b = left[key], right[key]
        same = if a isa AbstractArray && b isa AbstractArray
            if size(a) != size(b)
                false
            elseif eltype(a) <: Bool || eltype(b) <: Bool
                a == b
            else
                differences = abs.(a .- b)
                isempty(differences) ||
                    (
                    max_abs_difference = max(
                        max_abs_difference,
                        maximum(differences),
                    )
                )
                all(isapprox.(a, b; atol, rtol))
            end
        elseif a isa Bool || b isa Bool
            a === b
        else
            difference = abs(Float64(a) - Float64(b))
            max_abs_difference = max(max_abs_difference, difference)
            isapprox(a, b; atol, rtol)
        end
        if !same
            mismatch_count += 1
            length(mismatches) < 100 && push!(
                mismatches,
                Dict(
                    "path" => key,
                    "left" => a,
                    "right" => b,
                ),
            )
        end
    end
    return Dict{String, Any}(
        "passed" => mismatch_count == 0,
        "atol" => Float64(atol),
        "rtol" => Float64(rtol),
        "max_abs_difference" => max_abs_difference,
        "mismatch_count" => mismatch_count,
        "mismatches" => mismatches,
    )
end

function _cashflow_manifest(run_path::AbstractString)
    path = joinpath(run_path, "cashflows-manifest.json")
    isfile(path) || throw(
        ApiError(
            404,
            "Exact cash-flow trace is unavailable for this run; rerun the simulation to collect it.",
        ),
    )
    return JSON3.read(read(path, String))
end

function _cashflow_api_payload(
        run_path::AbstractString;
        quarter = nothing,
        detail = "sector",
        limit = 240,
        sector_limit = 480,
        firm_id = nothing,
        include_potential = false,
        level = nothing,
        focus = nothing,
        parent_id = nothing,
        edge_id = nothing,
        layers = nothing,
        recognition = nothing,
        direction = nothing,
        min_amount = 0.0,
        coverage = 1.0,
        page_size = nothing,
        cursor = nothing,
    )
    manifest = _cashflow_manifest(run_path)
    quarter === nothing && return manifest

    quarter_index = Int(quarter)
    available = Int.(collect(manifest["quarters"]))
    quarter_index in available || throw(
        ApiError(
            400,
            "Quarter is outside the available cash-flow trace",
            (quarter = quarter_index, available = available),
        ),
    )
    detail in ("sector", "firm") ||
        throw(ApiError(400, "detail must be sector or firm"))
    1 <= limit <= 5000 ||
        throw(ApiError(400, "limit must be between 1 and 5000"))
    1 <= sector_limit <= 5000 ||
        throw(ApiError(400, "sector_limit must be between 1 and 5000"))
    requested_level =
        level === nothing ? String(detail) : String(level)
    try
        _cashflow_level_rank(requested_level)
    catch error
        error isa ArgumentError || rethrow()
        throw(ApiError(400, error.msg))
    end
    page_size === nothing &&
        (page_size = requested_level == "firm" ? limit : sector_limit)

    trace_path =
        joinpath(run_path, "cashflow-$(quarter_index).jld2")
    isfile(trace_path) || throw(ApiError(404, "Cash-flow quarter not ready"))
    payload, cached_complete_edges = _cashflow_cached_artifact(trace_path)
    trace_schema_version = String(
        get(
            payload,
            "trace_schema_version",
            get(
                payload,
                "schema_version",
                CASHFLOW_LEGACY_SCHEMA_VERSION,
            ),
        ),
    )
    native_v2 =
        trace_schema_version != CASHFLOW_LEGACY_SCHEMA_VERSION ||
        haskey(payload, "edges") ||
        haskey(payload, "edge_bytes")
    relationship_columns =
        get(payload, "relationship_columns", nothing)
    sector_relationship_columns =
        get(payload, "sector_relationship_columns", nothing)
    full_relationships = Any[]
    full_sector_relationships = Any[]
    if !native_v2 && relationship_columns !== nothing
        full_relationships, _ =
            _cashflow_materialize_relationships(
            relationship_columns;
            include_potential = true,
            limit = typemax(Int),
        )
    end
    if !native_v2 && sector_relationship_columns !== nothing
        full_sector_relationships, _ =
            _cashflow_materialize_sector_relationships(
            sector_relationship_columns;
            include_potential = true,
            limit = typemax(Int),
        )
    end
    relationships, matching_count = if native_v2
        Any[], 0
    else
        _cashflow_materialize_relationships(
            relationship_columns === nothing ?
                _cashflow_relationship_columns(Any[]) :
                relationship_columns;
            firm_id,
            include_potential,
            limit,
        )
    end
    payload["relationship_count_total"] =
        Int(get(payload, "relationship_count", length(full_relationships)))
    payload["relationship_count_matching"] = matching_count
    payload["relationships"] = relationships
    payload["relationship_count_returned"] = length(relationships)
    haskey(payload, "relationship_columns") &&
        delete!(payload, "relationship_columns")
    sector_relationships, sector_matching_count = if native_v2
        Any[], 0
    else
        _cashflow_materialize_sector_relationships(
            sector_relationship_columns === nothing ?
                _cashflow_sector_relationship_columns(Any[]) :
                sector_relationship_columns;
            include_potential,
            limit = sector_limit,
        )
    end
    payload["sector_relationship_count_total"] =
        Int(
        get(
            payload,
            "sector_relationship_count",
            length(full_sector_relationships),
        ),
    )
    payload["sector_relationship_count_matching"] =
        sector_matching_count
    payload["sector_relationships"] = sector_relationships
    payload["sector_relationship_count_returned"] =
        length(sector_relationships)
    haskey(payload, "sector_relationship_columns") &&
        delete!(payload, "sector_relationship_columns")

    complete_edges = if native_v2
        cached_complete_edges
    else
        _cashflow_adapt_legacy_edges(
            payload,
            full_relationships,
            full_sector_relationships,
        )
    end
    haskey(payload, "edge_bytes") && delete!(payload, "edge_bytes")
    if trace_schema_version == CASHFLOW_LEGACY_SCHEMA_VERSION
        legacy_capabilities = Dict{String, Any}(
            String(key) => value for
                (key, value) in pairs(
                    get(payload, "capabilities", Dict{String, Any}()),
                )
        )
        merge!(
            legacy_capabilities,
            Dict{String, Any}(
                "normalized_edges" => true,
                "normalized_edges_are_adapter" => true,
                "business_counterparties" => true,
                "final_demand_counterparties" => false,
                "institution_components" => false,
                "household_cohorts" => false,
                "node_stock_flow_reconciliation" => false,
                "opening_snapshot" => false,
                "stable_signed_direction" => false,
                "complete_valuation_basis" => false,
            ),
        )
        payload["capabilities"] = legacy_capabilities
    end
    effective_focus =
        focus === nothing && firm_id !== nothing ?
        "firm:$firm_id" : focus
    include_counterfactual = Bool(include_potential)
    recognition_values = _cashflow_filter_values(recognition)
    recognition_values !== nothing &&
        "capacity_counterfactual" in recognition_values &&
        (include_counterfactual = true)
    query_identity =
        "$(String(get(payload, "run_id", basename(run_path))))|" *
        "$trace_schema_version|$quarter_index"
    query_result = try
        _cashflow_query_edges(
            complete_edges;
            level = requested_level,
            focus = effective_focus,
            parent_id,
            edge_id,
            layers,
            recognition,
            direction,
            min_amount = Float64(min_amount),
            coverage = Float64(coverage),
            page_size = Int(page_size),
            cursor,
            include_counterfactual,
            query_identity,
        )
    catch error
        error isa ArgumentError || rethrow()
        throw(ApiError(400, error.msg))
    end
    payload["trace_schema_version"] = trace_schema_version
    payload["api_schema_version"] = CASHFLOW_API_SCHEMA_VERSION
    payload["edge_count_total"] = length(complete_edges)
    payload["edge_count_matching"] = query_result["count_matching"]
    payload["edge_count_returned"] = query_result["count_returned"]
    payload["edges"] = query_result["edges"]
    payload["coverage"] = query_result["coverage"]
    payload["next_cursor"] = query_result["next_cursor"]
    payload["query_digest"] = query_result["query_digest"]
    payload["query"] = Dict{String, Any}(
        "level" => requested_level,
        "focus" => effective_focus,
        "parent_id" => parent_id,
        "edge_id" => edge_id,
        "layers" => layers,
        "recognition" => recognition,
        "direction" => direction,
        "min_amount" => Float64(min_amount),
        "coverage" => Float64(coverage),
        "page_size" => Int(page_size),
        "include_counterfactual" => include_counterfactual,
    )
    detail == "sector" && (payload["firms"] = Any[])
    return payload
end
