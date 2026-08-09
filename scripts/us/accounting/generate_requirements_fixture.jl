#!/usr/bin/env julia

using CSV
using JSON
using SHA
using TOML

const APPROVED_TABLE_59_SHA256 =
    "f38f13ac18365fe4a68ad64fc9a6be6661b62893c3b714ee2d070cb7e0cc434d"
const APPROVED_METADATA_SHA256 =
    "1cc83c9eec20698bb5a31aaba81eb98dd176126c187399a4d78910c65cebf787"
const APPROVED_YEAR = 2024
const EXPECTED_CELL_COUNT = 5_402
const EXPECTED_API_PRODUCTION_TIME = "2026-08-06T00:40:11.567"

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function usage_error()
    error(
        "usage: julia --project=scripts/us scripts/us/accounting/" *
            "generate_requirements_fixture.jl TABLE_59_JSON " *
            "TABLE_59_METADATA_JSON OUTPUT_DIRECTORY",
    )
end

function bea_result(payload)
    root = payload["BEAAPI"]
    results = root["Results"]
    results isa AbstractVector ||
        error("BEA Table 59 Results must be an array")
    length(results) == 1 ||
        error("BEA Table 59 expected exactly one Results entry")
    result = only(results)
    haskey(result, "Error") &&
        error("BEA Table 59 payload contains an API error")
    return result
end

length(ARGS) == 3 || usage_error()
source_path, metadata_path, output_directory = ARGS

source_bytes = read(source_path)
metadata_bytes = read(metadata_path)
sha256_hex(source_bytes) == APPROVED_TABLE_59_SHA256 ||
    error("Table 59 raw SHA-256 does not match the approved diagnostic")
sha256_hex(metadata_bytes) == APPROVED_METADATA_SHA256 ||
    error("Table 59 metadata SHA-256 does not match the approved diagnostic")

metadata = JSON.parse(String(metadata_bytes))
metadata["sha256"] == APPROVED_TABLE_59_SHA256 ||
    error("Table 59 metadata does not bind the approved raw payload")
metadata["http_status"] == 200 ||
    error("Table 59 metadata does not record HTTP 200")
metadata["request"] == Dict(
    "method" => "GetData",
    "datasetname" => "InputOutput",
    "TableID" => "59",
    "Year" => "2024",
) || error("Table 59 metadata request differs from the approved query")

result = bea_result(JSON.parse(String(source_bytes)))
result["UTCProductionTime"] == EXPECTED_API_PRODUCTION_TIME ||
    error("Table 59 API production time differs from the approved payload")
rows = result["Data"]
length(rows) == EXPECTED_CELL_COUNT ||
    error("Table 59 approved payload must contain $EXPECTED_CELL_COUNT cells")

projected = NamedTuple[]
for (index, row) in enumerate(rows)
    String(row["TableID"]) == "59" ||
        error("Table 59 row $index has the wrong table ID")
    parse(Int, String(row["Year"])) == APPROVED_YEAR ||
        error("Table 59 row $index has the wrong year")
    String(row["RowType"]) == "Commodity" ||
        error("Table 59 row $index has the wrong row basis")
    String(row["ColType"]) == "Commodity" ||
        error("Table 59 row $index has the wrong column basis")
    value = parse(Float64, replace(String(row["DataValue"]), "," => ""))
    isfinite(value) ||
        error("Table 59 row $index contains a nonfinite value")
    push!(
        projected,
        (
            table_id = "59",
            year = APPROVED_YEAR,
            row_code = String(row["RowCode"]),
            row_type = "Commodity",
            column_code = String(row["ColCode"]),
            column_type = "Commodity",
            value,
        ),
    )
end
sort!(projected; by = row -> (row.row_code, row.column_code))

mkpath(output_directory)
cells_path = joinpath(output_directory, "cells.csv")
manifest_path = joinpath(output_directory, "manifest.toml")
CSV.write(cells_path, projected)
fixture_sha256 = sha256_hex(read(cells_path))

manifest = Dict{String, Any}(
    "schema_version" => "beforeit-us-total-requirements-fixture.v1",
    "fixture_sha256" => fixture_sha256,
    "fixture_cell_count" => length(projected),
    "table_id" => "59",
    "year" => APPROVED_YEAR,
    "coefficient_unit" =>
        "dollars of commodity output per dollar of commodity delivered to final use",
    "published_decimal_places" => 7,
    "projection" =>
        "Every numeric cell and both commodity-axis labels from the approved " *
        "BEA API payload; descriptions and other envelope metadata omitted.",
    "generation_policy" =>
        "Regeneration fails unless the raw payload and redacted acquisition " *
        "metadata match the approved current-vintage diagnostic hashes.",
    "source_sha256" => APPROVED_TABLE_59_SHA256,
    "source_metadata_sha256" => APPROVED_METADATA_SHA256,
    "source_locator" =>
        "https://apps.bea.gov/api/data/?method=GetData&DataSetName=InputOutput&TableID=59&Year=2024",
    "request_id" => "table_59-2024-diagnostic",
    "retrieved_at_utc" => String(metadata["retrieved_at"]) * "Z",
    "api_production_time_utc" => EXPECTED_API_PRODUCTION_TIME * "Z",
    "status" => "CURRENT_VINTAGE_DIAGNOSTIC_NOT_ORIGIN_ELIGIBLE",
    "promotion_status" => "RESEARCH_ONLY_NOT_PROMOTED",
    "forecast_origin_admissible" => false,
    "accounting_gate_effect" => "NONE",
)
open(manifest_path, "w") do io
    TOML.print(io, manifest; sorted = true)
    println(io)
end

println("wrote $(length(projected)) canonical Table 59 cells")
println("cells SHA-256: $fixture_sha256")
