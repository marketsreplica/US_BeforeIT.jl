#!/usr/bin/env julia

include(joinpath(@__DIR__, "USBEAInventoryStockDiagnostic.jl"))
using .USBEAInventoryStockDiagnostic

length(ARGS) == 3 ||
    error(
    "usage: julia --project=scripts/us scripts/us/accounting/" *
        "generate_bea_t50805b_fixture.jl SOURCE_REDACTED_JSON " *
        "SOURCE_METADATA_JSON OUTPUT_DIRECTORY",
)

result =
    write_bea_inventory_stock_fixture(ARGS[1], ARGS[2], ARGS[3])
println("wrote $(size(result.frame, 1)) canonical T50805B Q1 rows")
println("cells SHA-256: $(result.fixture_sha256)")
println("manifest SHA-256: $(result.manifest_sha256)")
