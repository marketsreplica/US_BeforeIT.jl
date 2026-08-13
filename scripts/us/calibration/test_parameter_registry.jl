using JLD2
using Test
using TOML

include(joinpath(@__DIR__, "validate_parameter_registry.jl"))
using .ParameterRegistryValidator

const REGISTRY_PATH = joinpath(@__DIR__, "parameter_registry.toml")
const CONCEPT_PATH = joinpath(@__DIR__, "concept_dictionary.toml")
const BASELINE_PATH = normpath(
    joinpath(
        @__DIR__,
        "..",
        "..",
        "..",
        "data",
        "us",
        "baselines",
        "US_2024Q4_structural.jld2",
    ),
)

const BASELINE_PARAMETERS = JLD2.load(BASELINE_PATH, "parameters")
const BASELINE_KEYS = Set(keys(BASELINE_PARAMETERS))
const BASELINE_SHA256 = ParameterRegistryValidator.file_sha256(BASELINE_PATH)

function has_error(result, fragment)
    return any(error -> occursin(fragment, error), result.errors)
end

@testset "WS-2B installed registry" begin
    result = validate_registry(
        registry_path = REGISTRY_PATH,
        concept_path = CONCEPT_PATH,
        baseline_path = BASELINE_PATH,
    )

    @test result.schema_valid
    @test !result.gate_passed
    @test isempty(result.errors)
    @test result.registry.registry_count == 66
    @test result.registry.baseline_count == 66
    @test isempty(result.registry.missing_ids)
    @test isempty(result.registry.extra_ids)
    @test result.registry.unresolved_count == 43
    @test result.registry.provisional_count == 22
    @test result.registry.rejected_count == 1
    @test result.registry.open_review_count == 66
    @test get(result.registry.class_counts, "H", 0) == 0
    @test sum(values(result.registry.class_counts)) == 66
    installed_registry = TOML.parsefile(REGISTRY_PATH)
    inventory_bridge = only(
        row for row in installed_registry["parameter"]
            if row["parameter_id"] ==
            "use_commodity_balance_inventory"
    )
    @test inventory_bridge["review_status"] == "rejected"
    @test inventory_bridge["allowed_forecast_products"] ==
        ["research_only"]
    @test occursin(
        "not observed inventory investment",
        inventory_bridge["description"],
    )

    @test result.concepts.schema_valid
    @test !result.concepts.gate_passed
    @test result.concepts.concept_count == 17
    @test result.concepts.assumption_count == 5
    @test result.concepts.open_review_count > 0

    io = IOBuffer()
    ParameterRegistryValidator.print_report(io, result)
    report = String(take!(io))
    @test occursin("coverage = 66/66", report)
    @test occursin("gate_passed = false", report)
    @test occursin("GATE NOT PASSED", report)
    @test ParameterRegistryValidator.main(String[]) == 1
end

@testset "Deterministic canonical digest" begin
    registry = TOML.parsefile(REGISTRY_PATH)
    digest = registry_digest(registry)
    @test digest == registry_digest(deepcopy(registry))

    reordered = deepcopy(registry)
    reverse!(reordered["parameter"])
    @test digest == registry_digest(reordered)
    @test length(digest) == 64
    @test all(isxdigit, digest)
end

@testset "Registry validator fails closed" begin
    original = TOML.parsefile(REGISTRY_PATH)

    missing_field = deepcopy(original)
    delete!(missing_field["parameter"][1], "owner")
    result = validate_registry_data(
        missing_field,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test !result.gate_passed
    @test has_error(result, "missing required field 'owner'")

    unknown_field = deepcopy(original)
    unknown_field["parameter"][1]["anonymous_override"] = "forbidden"
    result = validate_registry_data(
        unknown_field,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "unknown field 'anonymous_override'")

    unknown_class = deepcopy(original)
    unknown_class["parameter"][1]["parameter_class"] = "Z"
    result = validate_registry_data(
        unknown_class,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "unknown parameter_class")

    class_h = deepcopy(original)
    class_h["parameter"][1]["parameter_class"] = "H"
    result = validate_registry_data(
        class_h,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "class-H publication parameters are forbidden")

    unknown_status = deepcopy(original)
    unknown_status["parameter"][1]["review_status"] = "DUBIOUS"
    result = validate_registry_data(
        unknown_status,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "unknown review_status")

    blank_uncertainty = deepcopy(original)
    blank_uncertainty["parameter"][1]["prior_or_uncertainty"] = " "
    result = validate_registry_data(
        blank_uncertainty,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "prior_or_uncertainty")

    unknown_product = deepcopy(original)
    unknown_product["parameter"][1]["allowed_forecast_products"] = ["secret_product"]
    result = validate_registry_data(
        unknown_product,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "unknown allowed_forecast_products")

    wrong_coverage = deepcopy(original)
    wrong_coverage["parameter"][1]["parameter_id"] = "not_a_baseline_key"
    result = validate_registry_data(
        wrong_coverage,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test !isempty(result.missing_ids)
    @test result.extra_ids == ["not_a_baseline_key"]

    duplicate_id = deepcopy(original)
    duplicate_id["parameter"][2]["parameter_id"] =
        duplicate_id["parameter"][1]["parameter_id"]
    result = validate_registry_data(
        duplicate_id,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "duplicate parameter IDs")

    wrong_hash = deepcopy(original)
    wrong_hash["schema"]["baseline_artifact_sha256"] = repeat("0", 64)
    result = validate_registry_data(
        wrong_hash,
        BASELINE_KEYS;
        baseline_sha256 = BASELINE_SHA256,
    )
    @test !result.schema_valid
    @test has_error(result, "does not match installed baseline")
end

@testset "Concept dictionary validator" begin
    original = TOML.parsefile(CONCEPT_PATH)
    result = validate_concept_dictionary_data(original)
    @test result.schema_valid
    @test !result.gate_passed

    missing_concept = deepcopy(original)
    filter!(
        concept -> concept["concept_id"] != "enterprise",
        missing_concept["concept"],
    )
    result = validate_concept_dictionary_data(missing_concept)
    @test !result.schema_valid
    @test has_error(result, "required concepts are missing")

    unknown_field = deepcopy(original)
    unknown_field["concept"][1]["silent_conversion"] = "forbidden"
    result = validate_concept_dictionary_data(unknown_field)
    @test !result.schema_valid
    @test has_error(result, "unknown field 'silent_conversion'")

    bad_dimensions = deepcopy(original)
    bad_dimensions["sector_contract"]["modeled_commodity_count"] = 71
    result = validate_concept_dictionary_data(bad_dimensions)
    @test !result.schema_valid
    @test has_error(result, "modeled_commodity_count must be 68")
end
