module ParameterRegistryValidator

using JLD2
using SHA
using TOML

export registry_digest,
    validate_concept_dictionary_data,
    validate_registry,
    validate_registry_data

const PARAMETER_FIELDS = Set(
    [
        "parameter_id",
        "model_symbol",
        "description",
        "economic_unit",
        "frequency",
        "sector_dimension",
        "parameter_class",
        "source_series",
        "source_table_and_line",
        "reference_period",
        "release_vintage",
        "transformation",
        "estimator_or_identity",
        "admissible_range",
        "prior_or_uncertainty",
        "update_cadence",
        "allowed_forecast_products",
        "identification_targets",
        "sensitivity_result",
        "owner",
        "independent_validator",
        "review_status",
        "tests",
        "artifact_hash",
    ],
)

const ARRAY_PARAMETER_FIELDS = Set(
    [
        "source_series",
        "allowed_forecast_products",
        "identification_targets",
        "tests",
    ],
)

const SCHEMA_FIELDS = Set(
    [
        "registry_id",
        "schema_version",
        "baseline_artifact",
        "baseline_parameter_count",
        "baseline_artifact_sha256",
        "scope",
        "as_of",
        "gate_policy",
    ],
)

const TOP_LEVEL_FIELDS = Set(
    [
        "schema",
        "parameter_classes",
        "review_statuses",
        "forecast_products",
        "parameter",
    ],
)

const ALLOWED_CLASSES = Set(string.(collect('A':'H')))
const ALLOWED_STATUSES = Set(["approved", "provisional", "unresolved", "rejected"])
const ALLOWED_PRODUCTS = Set(
    [
        "raw_abm",
        "aggregate",
        "sector",
        "nowcast",
        "density",
        "scenario",
        "research_only",
    ],
)

const CONCEPT_TOP_LEVEL_FIELDS = Set(["schema", "sector_contract", "concept", "assumption"])
const CONCEPT_SCHEMA_FIELDS = Set(["dictionary_id", "schema_version", "scope", "as_of"])
const SECTOR_CONTRACT_FIELDS = Set(
    [
        "source_industry_count",
        "modeled_commodity_count",
        "source_dimension",
        "modeled_dimension",
        "aggregation",
        "concordance",
        "status",
        "price_basis",
        "domestic_boundary",
    ],
)
const CONCEPT_FIELDS = Set(
    [
        "concept_id",
        "definition",
        "canonical_unit",
        "frequency",
        "temporal_type",
        "price_basis",
        "seasonal_adjustment",
        "boundary",
        "conversion",
        "status",
        "tests",
    ],
)
const CONCEPT_ARRAY_FIELDS = Set(["tests"])
const ASSUMPTION_FIELDS = Set(
    [
        "assumption_id",
        "description",
        "affected_concepts",
        "treatment",
        "uncertainty",
        "review_status",
        "owner",
        "independent_validator",
        "tests",
    ],
)
const ASSUMPTION_ARRAY_FIELDS = Set(["affected_concepts", "tests"])
const REQUIRED_CONCEPT_IDS = Set(
    [
        "source_industry",
        "modeled_commodity",
        "enterprise",
        "establishment",
        "job",
        "person",
        "stock",
        "flow",
        "saar",
        "current_price",
        "chain_type_quantity",
        "basic_price",
        "purchasers_price",
        "domestic_economy",
        "domestic_export_process",
        "legacy_ea_policy_block",
        "rest_of_world_agent",
    ],
)

function file_sha256(path::AbstractString)
    return open(path, "r") do io
        bytes2hex(sha256(io))
    end
end

function canonical_write(io::IO, value)
    if value isa AbstractDict
        keys_sorted = sort!(String.(collect(keys(value))))
        print(io, "D", length(keys_sorted), ":")
        for key in keys_sorted
            canonical_write(io, key)
            canonical_write(io, value[key])
        end
    elseif value isa AbstractVector
        print(io, "A", length(value), ":")
        for item in value
            canonical_write(io, item)
        end
    elseif value isa AbstractString
        print(io, "S", ncodeunits(value), ":", value)
    elseif value isa Integer
        print(io, "I", value, ";")
    elseif value isa AbstractFloat
        print(io, "F", repr(value), ";")
    elseif value isa Bool
        print(io, value ? "B1;" : "B0;")
    else
        print(io, "X")
        canonical_write(io, string(value))
    end
    return nothing
end

function canonical_registry(registry::AbstractDict)
    normalized = deepcopy(registry)
    if haskey(normalized, "parameter") && normalized["parameter"] isa AbstractVector
        sort!(normalized["parameter"]; by = row -> get(row, "parameter_id", ""))
    end
    return normalized
end

function registry_digest(registry::AbstractDict)
    io = IOBuffer()
    canonical_write(io, canonical_registry(registry))
    return bytes2hex(sha256(take!(io)))
end

function populated_string(value)
    return value isa AbstractString && !isempty(strip(value))
end

function populated_string_array(value)
    return value isa AbstractVector &&
        !isempty(value) &&
        all(populated_string, value)
end

function check_exact_fields!(
        errors::Vector{String},
        item::AbstractDict,
        expected::Set{String},
        label::String,
    )
    actual = Set(String.(keys(item)))
    for field in sort!(collect(setdiff(expected, actual)))
        push!(errors, "$label is missing required field '$field'")
    end
    for field in sort!(collect(setdiff(actual, expected)))
        push!(errors, "$label has unknown field '$field'")
    end
    return nothing
end

function validate_string_fields!(
        errors::Vector{String},
        item::AbstractDict,
        expected::Set{String},
        array_fields::Set{String},
        label::String,
    )
    for field in expected
        haskey(item, field) || continue
        valid = field in array_fields ?
            populated_string_array(item[field]) :
            populated_string(item[field])
        valid || push!(errors, "$label field '$field' must be nonempty text$(field in array_fields ? "[]" : "")")
    end
    return nothing
end

function count_values(rows, field::String)
    counts = Dict{String, Int}()
    for row in rows
        value = get(row, field, "<missing>")
        key = value isa AbstractString ? value : "<invalid>"
        counts[key] = get(counts, key, 0) + 1
    end
    return counts
end

function validate_definitions!(
        errors::Vector{String},
        registry::AbstractDict,
    )
    for (field, allowed) in (
            ("parameter_classes", ALLOWED_CLASSES),
            ("review_statuses", ALLOWED_STATUSES),
            ("forecast_products", ALLOWED_PRODUCTS),
        )
        definitions = get(registry, field, nothing)
        if !(definitions isa AbstractDict)
            push!(errors, "top-level '$field' must be a table")
            continue
        end
        actual = Set(String.(keys(definitions)))
        actual == allowed ||
            push!(
            errors,
            "top-level '$field' definitions must equal $(join(sort!(collect(allowed)), ",")); got $(join(sort!(collect(actual)), ","))",
        )
        for (key, value) in definitions
            populated_string(value) ||
                push!(errors, "definition '$field.$key' must be nonempty text")
        end
    end
    return nothing
end

function validate_registry_data(
        registry::AbstractDict,
        baseline_keys;
        baseline_sha256::Union{Nothing, AbstractString} = nothing,
    )
    errors = String[]
    baseline_set = Set(String.(collect(baseline_keys)))

    actual_top = Set(String.(keys(registry)))
    for field in sort!(collect(setdiff(TOP_LEVEL_FIELDS, actual_top)))
        push!(errors, "registry is missing top-level field '$field'")
    end
    for field in sort!(collect(setdiff(actual_top, TOP_LEVEL_FIELDS)))
        push!(errors, "registry has unknown top-level field '$field'")
    end

    schema = get(registry, "schema", Dict{String, Any}())
    if schema isa AbstractDict
        check_exact_fields!(errors, schema, SCHEMA_FIELDS, "schema")
        for field in setdiff(SCHEMA_FIELDS, Set(["baseline_parameter_count"]))
            haskey(schema, field) && !populated_string(schema[field]) &&
                push!(errors, "schema field '$field' must be nonempty text")
        end
        count_value = get(schema, "baseline_parameter_count", nothing)
        count_value isa Integer ||
            push!(errors, "schema field 'baseline_parameter_count' must be an integer")
        count_value isa Integer && count_value != length(baseline_set) &&
            push!(
            errors,
            "schema baseline_parameter_count=$count_value but installed baseline has $(length(baseline_set)) keys",
        )
        declared_hash = get(schema, "baseline_artifact_sha256", nothing)
        if baseline_sha256 !== nothing && declared_hash != baseline_sha256
            push!(
                errors,
                "schema baseline_artifact_sha256 does not match installed baseline: declared=$(repr(declared_hash)) installed=$baseline_sha256",
            )
        end
    else
        push!(errors, "top-level 'schema' must be a table")
    end

    validate_definitions!(errors, registry)

    rows = get(registry, "parameter", Any[])
    if !(rows isa AbstractVector)
        push!(errors, "top-level 'parameter' must be an array of tables")
        rows = Any[]
    end

    ids = String[]
    for (index, row) in enumerate(rows)
        label = "parameter[$index]"
        if !(row isa AbstractDict)
            push!(errors, "$label must be a table")
            continue
        end
        id = get(row, "parameter_id", nothing)
        id isa AbstractString && !isempty(strip(id)) && (label = "parameter '$id'")
        check_exact_fields!(errors, row, PARAMETER_FIELDS, label)
        validate_string_fields!(
            errors,
            row,
            PARAMETER_FIELDS,
            ARRAY_PARAMETER_FIELDS,
            label,
        )
        populated_string(id) && push!(ids, id)

        class = get(row, "parameter_class", nothing)
        class in ALLOWED_CLASSES ||
            push!(errors, "$label has unknown parameter_class $(repr(class))")
        class == "H" &&
            push!(errors, "$label is class H but class-H publication parameters are forbidden in raw parameters")

        status = get(row, "review_status", nothing)
        status in ALLOWED_STATUSES ||
            push!(errors, "$label has unknown review_status $(repr(status))")

        products = get(row, "allowed_forecast_products", Any[])
        if products isa AbstractVector
            unknown_products = setdiff(Set(String.(products)), ALLOWED_PRODUCTS)
            isempty(unknown_products) ||
                push!(
                errors,
                "$label has unknown allowed_forecast_products $(join(sort!(collect(unknown_products)), ","))",
            )
        end

        if baseline_sha256 !== nothing
            expected_artifact_hash = "sha256:$baseline_sha256"
            get(row, "artifact_hash", nothing) == expected_artifact_hash ||
                push!(errors, "$label artifact_hash does not identify the installed raw baseline")
        end
    end

    duplicate_ids = sort!([id for id in unique(ids) if count(==(id), ids) > 1])
    isempty(duplicate_ids) ||
        push!(errors, "duplicate parameter IDs: $(join(duplicate_ids, ","))")

    registry_set = Set(ids)
    missing = sort!(collect(setdiff(baseline_set, registry_set)))
    extra = sort!(collect(setdiff(registry_set, baseline_set)))
    isempty(missing) ||
        push!(errors, "registry is missing installed baseline keys: $(join(missing, ","))")
    isempty(extra) ||
        push!(errors, "registry contains IDs absent from installed baseline: $(join(extra, ","))")

    status_counts = count_values(rows, "review_status")
    class_counts = count_values(rows, "parameter_class")
    unresolved_count = get(status_counts, "unresolved", 0)
    provisional_count = get(status_counts, "provisional", 0)
    rejected_count = get(status_counts, "rejected", 0)
    schema_valid = isempty(errors)
    gate_passed = schema_valid &&
        unresolved_count == 0 &&
        provisional_count == 0 &&
        rejected_count == 0 &&
        get(status_counts, "approved", 0) == length(rows)

    return (
        schema_valid = schema_valid,
        gate_passed = gate_passed,
        errors = errors,
        baseline_count = length(baseline_set),
        registry_count = length(rows),
        missing_ids = missing,
        extra_ids = extra,
        status_counts = status_counts,
        class_counts = class_counts,
        unresolved_count = unresolved_count,
        provisional_count = provisional_count,
        rejected_count = rejected_count,
        open_review_count = unresolved_count + provisional_count + rejected_count,
        registry_sha256 = registry_digest(registry),
    )
end

function validate_concept_dictionary_data(dictionary::AbstractDict)
    errors = String[]
    actual_top = Set(String.(keys(dictionary)))
    for field in sort!(collect(setdiff(CONCEPT_TOP_LEVEL_FIELDS, actual_top)))
        push!(errors, "concept dictionary is missing top-level field '$field'")
    end
    for field in sort!(collect(setdiff(actual_top, CONCEPT_TOP_LEVEL_FIELDS)))
        push!(errors, "concept dictionary has unknown top-level field '$field'")
    end

    schema = get(dictionary, "schema", Dict{String, Any}())
    if schema isa AbstractDict
        check_exact_fields!(errors, schema, CONCEPT_SCHEMA_FIELDS, "concept schema")
        validate_string_fields!(
            errors,
            schema,
            CONCEPT_SCHEMA_FIELDS,
            Set{String}(),
            "concept schema",
        )
    else
        push!(errors, "concept dictionary 'schema' must be a table")
    end

    contract = get(dictionary, "sector_contract", Dict{String, Any}())
    if contract isa AbstractDict
        check_exact_fields!(errors, contract, SECTOR_CONTRACT_FIELDS, "sector_contract")
        for field in setdiff(
                SECTOR_CONTRACT_FIELDS,
                Set(["source_industry_count", "modeled_commodity_count"]),
            )
            haskey(contract, field) && !populated_string(contract[field]) &&
                push!(errors, "sector_contract field '$field' must be nonempty text")
        end
        get(contract, "source_industry_count", nothing) == 71 ||
            push!(errors, "sector_contract source_industry_count must be 71")
        get(contract, "modeled_commodity_count", nothing) == 68 ||
            push!(errors, "sector_contract modeled_commodity_count must be 68")
    else
        push!(errors, "concept dictionary 'sector_contract' must be a table")
    end

    concepts = get(dictionary, "concept", Any[])
    if !(concepts isa AbstractVector)
        push!(errors, "concept dictionary 'concept' must be an array of tables")
        concepts = Any[]
    end
    concept_ids = String[]
    for (index, concept) in enumerate(concepts)
        label = "concept[$index]"
        if !(concept isa AbstractDict)
            push!(errors, "$label must be a table")
            continue
        end
        id = get(concept, "concept_id", nothing)
        populated_string(id) && (label = "concept '$id'"; push!(concept_ids, id))
        check_exact_fields!(errors, concept, CONCEPT_FIELDS, label)
        validate_string_fields!(
            errors,
            concept,
            CONCEPT_FIELDS,
            CONCEPT_ARRAY_FIELDS,
            label,
        )
        status = get(concept, "status", nothing)
        status in ALLOWED_STATUSES ||
            push!(errors, "$label has unknown status $(repr(status))")
    end
    duplicate_concepts = sort!(
        [id for id in unique(concept_ids) if count(==(id), concept_ids) > 1],
    )
    isempty(duplicate_concepts) ||
        push!(errors, "duplicate concept IDs: $(join(duplicate_concepts, ","))")
    missing_concepts = sort!(collect(setdiff(REQUIRED_CONCEPT_IDS, Set(concept_ids))))
    isempty(missing_concepts) ||
        push!(errors, "required concepts are missing: $(join(missing_concepts, ","))")

    assumptions = get(dictionary, "assumption", Any[])
    if !(assumptions isa AbstractVector)
        push!(errors, "concept dictionary 'assumption' must be an array of tables")
        assumptions = Any[]
    end
    assumption_ids = String[]
    for (index, assumption) in enumerate(assumptions)
        label = "assumption[$index]"
        if !(assumption isa AbstractDict)
            push!(errors, "$label must be a table")
            continue
        end
        id = get(assumption, "assumption_id", nothing)
        populated_string(id) && (label = "assumption '$id'"; push!(assumption_ids, id))
        check_exact_fields!(errors, assumption, ASSUMPTION_FIELDS, label)
        validate_string_fields!(
            errors,
            assumption,
            ASSUMPTION_FIELDS,
            ASSUMPTION_ARRAY_FIELDS,
            label,
        )
        status = get(assumption, "review_status", nothing)
        status in ALLOWED_STATUSES ||
            push!(errors, "$label has unknown review_status $(repr(status))")
    end
    duplicate_assumptions = sort!(
        [id for id in unique(assumption_ids) if count(==(id), assumption_ids) > 1],
    )
    isempty(duplicate_assumptions) ||
        push!(errors, "duplicate assumption IDs: $(join(duplicate_assumptions, ","))")

    status_counts = count_values(concepts, "status")
    assumption_status_counts = count_values(assumptions, "review_status")
    open_count =
        sum(get(status_counts, status, 0) for status in ("provisional", "unresolved", "rejected")) +
        sum(
        get(assumption_status_counts, status, 0) for
            status in ("provisional", "unresolved", "rejected")
    )
    return (
        schema_valid = isempty(errors),
        gate_passed = isempty(errors) && open_count == 0,
        errors = errors,
        concept_count = length(concepts),
        assumption_count = length(assumptions),
        status_counts = status_counts,
        assumption_status_counts = assumption_status_counts,
        open_review_count = open_count,
        dictionary_sha256 = registry_digest(dictionary),
    )
end

function validate_registry(;
        registry_path::AbstractString = joinpath(@__DIR__, "parameter_registry.toml"),
        concept_path::AbstractString = joinpath(@__DIR__, "concept_dictionary.toml"),
        baseline_path::AbstractString = normpath(
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
        ),
    )
    isfile(registry_path) || error("Parameter registry is not installed: $registry_path")
    isfile(concept_path) || error("Concept dictionary is not installed: $concept_path")
    isfile(baseline_path) || error("Raw structural baseline is not installed: $baseline_path")

    registry = TOML.parsefile(registry_path)
    dictionary = TOML.parsefile(concept_path)
    parameters = JLD2.load(baseline_path, "parameters")
    baseline_sha256 = file_sha256(baseline_path)
    registry_result = validate_registry_data(
        registry,
        keys(parameters);
        baseline_sha256 = baseline_sha256,
    )
    concept_result = validate_concept_dictionary_data(dictionary)
    errors = vcat(registry_result.errors, concept_result.errors)
    schema_valid = isempty(errors)
    gate_passed =
        schema_valid && registry_result.gate_passed && concept_result.gate_passed

    return (
        schema_valid = schema_valid,
        gate_passed = gate_passed,
        errors = errors,
        baseline_sha256 = baseline_sha256,
        registry = registry_result,
        concepts = concept_result,
    )
end

function print_report(io::IO, result)
    println(io, "WS-2B parameter registry validation")
    println(io, "schema_valid = ", result.schema_valid)
    println(io, "gate_passed = ", result.gate_passed)
    println(
        io,
        "coverage = ",
        result.registry.registry_count,
        "/",
        result.registry.baseline_count,
    )
    println(io, "class_counts = ", result.registry.class_counts)
    println(io, "review_status_counts = ", result.registry.status_counts)
    println(io, "unresolved_parameters = ", result.registry.unresolved_count)
    println(io, "provisional_parameters = ", result.registry.provisional_count)
    println(io, "rejected_parameters = ", result.registry.rejected_count)
    println(io, "open_concept_reviews = ", result.concepts.open_review_count)
    println(io, "registry_sha256 = ", result.registry.registry_sha256)
    println(io, "concept_dictionary_sha256 = ", result.concepts.dictionary_sha256)
    if isempty(result.errors)
        result.gate_passed ||
            println(
            io,
            "GATE NOT PASSED: schema/coverage checks pass, but open reviews remain.",
        )
    else
        println(io, "validation_errors = ", length(result.errors))
        for error in result.errors
            println(io, "  - ", error)
        end
    end
    return nothing
end

function main(args)
    registry_path = length(args) >= 1 ? args[1] : joinpath(@__DIR__, "parameter_registry.toml")
    concept_path = length(args) >= 2 ? args[2] : joinpath(@__DIR__, "concept_dictionary.toml")
    baseline_path = length(args) >= 3 ?
        args[3] :
        normpath(
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
    result = validate_registry(
        registry_path = registry_path,
        concept_path = concept_path,
        baseline_path = baseline_path,
    )
    print_report(stdout, result)
    return result.schema_valid ? (result.gate_passed ? 0 : 1) : 2
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main(ARGS))
end

end
