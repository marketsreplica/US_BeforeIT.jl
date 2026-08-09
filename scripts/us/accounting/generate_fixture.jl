#!/usr/bin/env julia

using CSV
using SHA
using TOML

include(joinpath(@__DIR__, "USSupplyMakeDiagnostics.jl"))
using .USSupplyMakeDiagnostics

const APPROVED_TABLE_259_SHA256 =
    "2bdd65f04e1bf31fd66d1e642afd0fb9dda2fd9bb5ba3bacf8db83431be1e918"
const APPROVED_TABLE_262_SHA256 =
    "91d6686dce15fe1d96f35f1752382bf1d47d274c067f52febc60ae40014406e8"
const APPROVED_YEAR = 2024

function usage_error()
    error(
        "usage: julia --project=scripts/us scripts/us/accounting/" *
            "generate_fixture.jl TABLE_259_JSON TABLE_262_JSON OUTPUT_DIRECTORY",
    )
end

length(ARGS) == 3 || usage_error()
use_path, supply_path, output_directory = ARGS

use = load_bea_json(
    use_path;
    expected_sha256 = APPROVED_TABLE_259_SHA256,
    expected_table_id = "259",
    expected_year = APPROVED_YEAR,
)
supply = load_bea_json(
    supply_path;
    expected_sha256 = APPROVED_TABLE_262_SHA256,
    expected_table_id = "262",
    expected_year = APPROVED_YEAR,
)

mkpath(output_directory)
cells_path = joinpath(output_directory, "cells.csv")
manifest_path = joinpath(output_directory, "manifest.toml")

rows = NamedTuple[]
for table in (use, supply)
    for cell in values(table.cells)
        push!(
            rows,
            (
                table_id = cell.table_id,
                year = cell.year,
                row_code = cell.row_code,
                row_type = cell.row_type,
                column_code = cell.column_code,
                column_type = cell.column_type,
                value = cell.value,
            ),
        )
    end
end
sort!(rows; by = row -> (row.table_id, row.row_code, row.column_code))
CSV.write(cells_path, rows)

fixture_sha256 = bytes2hex(SHA.sha256(read(cells_path)))
manifest = Dict{String, Any}(
    "schema_version" => "beforeit-us-supply-make-fixture.v1",
    "fixture_sha256" => fixture_sha256,
    "fixture_cell_count" => length(rows),
    "economic_unit" => "millions of current U.S. dollars",
    "projection" =>
        "Every numeric cell and both axis type labels from the approved " *
        "BEA API payloads; descriptions and API envelope metadata omitted.",
    "generation_policy" =>
        "Regeneration fails unless both raw payload SHA-256 values match " *
        "the approved accounting-gate artifacts.",
    "sources" => [
        Dict{String, Any}(
            "table_id" => use.table_id,
            "year" => use.year,
            "source_sha256" => use.source_sha256,
            "cell_count" => length(use.cells),
            "request_id" => "table_259-2024",
            "status" => "APPROVED_ARCHIVED",
        ),
        Dict{String, Any}(
            "table_id" => supply.table_id,
            "year" => supply.year,
            "source_sha256" => supply.source_sha256,
            "cell_count" => length(supply.cells),
            "request_id" => "table_262-2024",
            "status" => "APPROVED_ARCHIVED",
        ),
    ],
)
open(manifest_path, "w") do io
    TOML.print(io, manifest; sorted = true)
    println(io)
end

println("wrote $(length(rows)) canonical cells")
println("cells SHA-256: $fixture_sha256")
