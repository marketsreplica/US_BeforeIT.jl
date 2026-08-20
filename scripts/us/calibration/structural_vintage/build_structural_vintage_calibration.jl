# =====================================================================================
# Driver for stage-2b workstream 2b-4: build an additional annual structural
# calibration of the US BeforeIT model for a historical reference year.
#
#   julia --project=scripts/us scripts/us/calibration/structural_vintage/build_structural_vintage_calibration.jl --golden-test
#   julia --project=scripts/us scripts/us/calibration/structural_vintage/build_structural_vintage_calibration.jl --year=2017
#   julia --project=scripts/us scripts/us/calibration/structural_vintage/build_structural_vintage_calibration.jl --year=2012
#
# --golden-test rebuilds the 2024 annual structure from the checked-in raw responses
# and compares it entry-by-entry against the shipped US_2024_calibration_object.jld2;
# it writes nothing. It must pass before any vintage build is trusted.
#
# --year=Y fetches the reference-year sources (archived under
# data/us/raw/structural_vintage/), builds the annual structure, copies every
# quarterly series from the shipped 2024 artifact, and writes
#   data/us/calibration/US_<Y>_calibration_object.jld2
#   data/us/calibration/US_<Y>_calibration_object.provenance.toml
# Existing artifacts are never overwritten.
# =====================================================================================

include(joinpath(@__DIR__, "StructuralVintageCalibration.jl"))
using .StructuralVintageCalibration
const SVC = StructuralVintageCalibration

function cli_flag(name)
    return any(argument -> argument == "--" * name, ARGS)
end

function cli_option(name, default)
    prefix = "--" * name * "="
    for argument in ARGS
        startswith(argument, prefix) && return argument[(length(prefix) + 1):end]
    end
    return default
end

if cli_flag("golden-test")
    println("="^100)
    println("GOLDEN TEST: rebuild the 2024 annual structure from checked-in raw inputs")
    println("="^100)
    passed, report = SVC.golden_test_2024()
    println(report)
    println(
        passed ? "\nGOLDEN TEST PASSED: the ingestion replication reproduces the shipped 2024 artifact." :
            "\nGOLDEN TEST FAILED"
    )
    passed || exit(1)
else
    year_text = cli_option("year", "")
    isempty(year_text) && error("Pass --year=2017, --year=2012, or --golden-test")
    year = parse(Int, year_text)
    out = cli_option("out", "")
    println("="^100)
    println("STRUCTURAL VINTAGE BUILD: reference year $year")
    println("="^100)
    result = SVC.build_vintage_calibration(year)
    artifact_path, toml_path = SVC.save_vintage_artifact(
        year, result; out_path = isempty(out) ? nothing : abspath(out),
    )
    println("\nwrote $artifact_path")
    println("wrote $toml_path")
    println("artifact sha256 $(SVC.sha256_file(artifact_path))")
end
