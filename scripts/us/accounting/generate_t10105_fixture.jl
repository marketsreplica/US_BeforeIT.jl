#!/usr/bin/env julia

include(joinpath(@__DIR__, "UST10105Controls.jl"))
using .UST10105Controls

length(ARGS) == 3 ||
    error(
    "usage: julia --project=scripts/us scripts/us/accounting/" *
        "generate_t10105_fixture.jl SOURCE_JSON SOURCE_METADATA_JSON " *
        "OUTPUT_DIRECTORY",
)

result = write_t10105_fixture(ARGS[1], ARGS[2], ARGS[3])
println("Wrote ", result.cells_path)
println("Wrote ", result.manifest_path)
