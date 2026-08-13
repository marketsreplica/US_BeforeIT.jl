#!/usr/bin/env julia

using TOML

include(joinpath(@__DIR__, "USHistoricalBackfillPlan.jl"))
using .USHistoricalBackfillPlan
include(joinpath(@__DIR__, "..", "contracts", "USForecastProtocol.jl"))
include(joinpath(@__DIR__, "..", "targets", "USTier1TargetCoverage.jl"))

const PLAN_PATH = joinpath(@__DIR__, "historical_backfill_plan.toml")
const INVENTORY_PATH = joinpath(@__DIR__, "current_inventory.toml")
const PROTOCOL_PATH = joinpath(@__DIR__, "..", "protocol.toml")
const TIER1_TARGETS_PATH =
    joinpath(@__DIR__, "..", "targets", "tier1_targets.toml")

plan = load_backfill_plan(PLAN_PATH)
inventory = TOML.parsefile(INVENTORY_PATH)
validate_inventory_alignment(plan, inventory)
validate_contract_alignment(
    plan,
    USForecastProtocol.protocol_sha256(
        USForecastProtocol.load_protocol(PROTOCOL_PATH),
    ),
    USTier1TargetCoverage.inventory_sha256(
        USTier1TargetCoverage.load_inventory(TIER1_TARGETS_PATH),
    ),
)
observed_at_utc = validate_prospective_capture_deadline(plan)
println(
    "prospective capture deadline guard passed at ",
    observed_at_utc,
    "Z",
)
