module USOriginPackages

using Dates
using SHA
using TOML

export OriginValidationError,
    OriginReadinessResolver,
    REQUIRED_BLOCK_IDS,
    REQUIRED_GATE_IDS,
    REQUIRED_MAPPING_IDS,
    build_cannot_run_record,
    computed_content_sha256,
    load_toml_artifact,
    macro_control_sha256,
    mapping_gate,
    mapping_registry_sha256,
    origin_package_sha256,
    stamp_content_sha256!,
    validate_cannot_run_record,
    validate_macro_control,
    validate_mapping_registry,
    validate_origin_package

const CANONICALIZATION = "sorted_typed_v1_excluding_artifact_content_sha256"
const MACRO_SCHEMA = "beforeit-us-opening-macro-control.v1"
const MAPPING_SCHEMA = "beforeit-us-opening-macro-mapping.v1"
const ORIGIN_SCHEMA = "beforeit-us-origin-package.v1"
const CANNOT_RUN_SCHEMA = "beforeit-us-origin-cannot-run.v1"
const RFC3339_SECONDS_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS"
const MAPPING_GATE_RULE =
    "all_required_mappings_approved_with_evidence_and_independent_ownership"

const REQUIRED_CONTROL_IDS = (
    "nominal_gdp",
    "pce",
    "gpdi",
    "fixed_investment",
    "inventory_investment",
    "exports",
    "imports",
    "government_consumption_and_investment",
)

const REQUIRED_MAPPING_IDS = (
    "pce",
    "gpdi",
    "fixed_investment",
    "inventory_investment",
    "exports",
    "imports",
    "government_consumption_and_investment",
)

const REQUIRED_BLOCK_IDS = (
    "quarterly_vintages",
    "structural_inputs",
    "dynamic_parameters",
    "origin_state",
    "observation_operator",
    "model_variant",
    "parameter_registry",
    "forecast_registry",
)

const REQUIRED_GATE_IDS = (
    "vintage_firewall",
    "macro_control_identity",
    "accounting",
    "parameter_registry",
    "variant_manifest",
    "semantic_mapping",
    "observation_operator",
    "origin_state",
    "scale_convergence",
)

const EXPECTED_BLOCK_BASIS = Dict(
    "quarterly_vintages" => "release_timestamp",
    "structural_inputs" => "release_timestamp",
    "dynamic_parameters" => "origin_information_cutoff",
    "origin_state" => "origin_information_cutoff",
    "observation_operator" => "frozen_configuration",
    "model_variant" => "frozen_configuration",
    "parameter_registry" => "frozen_configuration",
    "forecast_registry" => "frozen_configuration",
)

const CONTROL_TO_MAPPING = Dict(
    "pce" => "pce",
    "gpdi" => "gpdi",
    "fixed_investment" => "fixed_investment",
    "inventory_investment" => "inventory_investment",
    "exports" => "exports",
    "imports" => "imports",
    "government_consumption_and_investment" =>
        "government_consumption_and_investment",
)

const PLACEHOLDERS =
    Set(["", "none", "pending", "tbd", "todo", "unassigned", "unknown"])
const BUILTIN_GATE_IDS =
    Set(["macro_control_identity", "semantic_mapping"])

struct OriginValidationError <: Exception
    message::String
end

struct OriginReadinessResolver
    artifact_paths::Dict{String, String}
    gate_validators::Dict{String, Function}
end

function OriginReadinessResolver(; artifact_paths, gate_validators)
    all(key -> key isa AbstractString, keys(artifact_paths)) ||
        fail("readiness_resolver.artifact_paths", "must use string keys")
    all(value -> value isa AbstractString, values(artifact_paths)) ||
        fail("readiness_resolver.artifact_paths", "must use string paths")
    all(key -> key isa AbstractString, keys(gate_validators)) ||
        fail("readiness_resolver.gate_validators", "must use string keys")
    all(value -> value isa Function, values(gate_validators)) ||
        fail(
        "readiness_resolver.gate_validators",
        "must contain callable validators",
    )
    return OriginReadinessResolver(
        Dict{String, String}(
            String(key) => String(value)
                for (key, value) in pairs(artifact_paths)
        ),
        Dict{String, Function}(
            String(key) => value
                for (key, value) in pairs(gate_validators)
        ),
    )
end

Base.showerror(io::IO, error::OriginValidationError) =
    print(io, error.message)

fail(location, message) =
    throw(OriginValidationError("$location: $message"))

file_sha256(path::AbstractString) =
    bytes2hex(SHA.sha256(read(path)))

function expect_table(value, location)
    value isa AbstractDict || fail(location, "must be a table")
    all(key -> key isa AbstractString, keys(value)) ||
        fail(location, "must use string keys")
    return value
end

function expect_exact_keys(value, expected, location)
    table = expect_table(value, location)
    actual = Set(String.(keys(table)))
    expected_set = Set(String.(expected))
    missing = sort!(collect(setdiff(expected_set, actual)))
    unknown = sort!(collect(setdiff(actual, expected_set)))
    isempty(missing) ||
        fail(location, "missing keys: $(join(missing, ", "))")
    isempty(unknown) ||
        fail(location, "unknown keys: $(join(unknown, ", "))")
    return table
end

function expect_string(value, location)
    value isa AbstractString || fail(location, "must be a string")
    text = String(value)
    text == strip(text) || fail(location, "has surrounding whitespace")
    isempty(text) && fail(location, "must not be empty")
    return text
end

function expect_one_of(value, allowed, location)
    text = expect_string(value, location)
    text in allowed ||
        fail(location, "must be one of $(join(sort!(collect(allowed)), ", "))")
    return text
end

function expect_identifier(value, location)
    text = expect_string(value, location)
    occursin(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$", text) ||
        fail(location, "contains unsupported characters")
    return text
end

function expect_hash(value, location)
    text = expect_string(value, location)
    occursin(r"^[0-9a-f]{64}$", text) ||
        fail(location, "must be 64 lowercase hexadecimal characters")
    return text
end

function expect_timestamp(value, location)
    text = expect_string(value, location)
    occursin(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", text) ||
        fail(location, "must be an RFC3339 UTC timestamp at second precision")
    return try
        DateTime(text[1:(end - 1)], RFC3339_SECONDS_FORMAT)
    catch
        fail(location, "is not a valid timestamp")
    end
end

function expect_quarter(value, location)
    text = expect_string(value, location)
    occursin(r"^[0-9]{4}Q[1-4]$", text) ||
        fail(location, "must use YYYYQn")
    return text
end

function expect_number(value, location)
    value isa Real && !(value isa Bool) ||
        fail(location, "must be numeric")
    number = Float64(value)
    isfinite(number) || fail(location, "must be finite")
    return number
end

function expect_integer(value, location; minimum = typemin(Int))
    value isa Integer && !(value isa Bool) ||
        fail(location, "must be an integer")
    value >= minimum || fail(location, "must be at least $minimum")
    return Int(value)
end

function expect_string_array(value, location; allow_empty = false)
    value isa AbstractVector || fail(location, "must be an array")
    !allow_empty && isempty(value) &&
        fail(location, "must not be empty")
    return [
        expect_string(item, "$location[$index]")
            for (index, item) in enumerate(value)
    ]
end

function _canonical_write(io::IO, value)
    if value isa AbstractDict
        entries =
            sort!(collect(pairs(value)); by = pair -> String(first(pair)))
        print(io, "M", length(entries), "{")
        for (key, entry) in entries
            _canonical_write(io, String(key))
            _canonical_write(io, entry)
        end
        print(io, "}")
    elseif value isa AbstractVector
        print(io, "A", length(value), "[")
        for entry in value
            _canonical_write(io, entry)
        end
        print(io, "]")
    elseif value isa AbstractString
        text = String(value)
        print(io, "S", ncodeunits(text), ":", text)
    elseif value isa Bool
        print(io, value ? "B1" : "B0")
    elseif value isa Integer
        print(io, "I", value, ";")
    elseif value isa AbstractFloat
        number = Float64(value)
        isfinite(number) || fail("canonicalization", "nonfinite number")
        print(io, "F", bitstring(number), ";")
    else
        fail(
            "canonicalization",
            "unsupported value of type $(typeof(value))",
        )
    end
    return io
end

function computed_content_sha256(value)
    artifact = deepcopy(expect_table(value, "artifact root"))
    header = expect_table(
        get(artifact, "artifact", nothing),
        "artifact root.artifact",
    )
    pop!(header, "content_sha256", nothing)
    io = IOBuffer()
    _canonical_write(io, artifact)
    return bytes2hex(sha256(take!(io)))
end

function stamp_content_sha256!(value)
    artifact = expect_table(value, "artifact root")
    header = expect_table(
        get(artifact, "artifact", nothing),
        "artifact root.artifact",
    )
    header["content_sha256"] = computed_content_sha256(artifact)
    return artifact
end

function validate_root_header(root, expected_schema)
    header = expect_exact_keys(
        root["artifact"],
        ("schema_version", "canonicalization", "content_sha256"),
        "artifact",
    )
    expect_one_of(
        header["schema_version"],
        Set([expected_schema]),
        "artifact.schema_version",
    )
    expect_one_of(
        header["canonicalization"],
        Set([CANONICALIZATION]),
        "artifact.canonicalization",
    )
    declared =
        expect_hash(header["content_sha256"], "artifact.content_sha256")
    computed = computed_content_sha256(root)
    declared == computed ||
        fail(
        "artifact.content_sha256",
        "declared $declared does not match computed $computed",
    )
    return declared
end

function load_toml_artifact(path::AbstractString)
    isfile(path) || fail("artifact", "file does not exist: $(abspath(path))")
    return try
        TOML.parsefile(path)
    catch error
        fail("artifact", "could not parse TOML: $(sprint(showerror, error))")
    end
end

function validate_macro_control(control)
    root = expect_exact_keys(
        control,
        ("artifact", "control", "values", "identities"),
        "macro_control",
    )
    metadata = expect_exact_keys(
        root["control"],
        (
            "control_id",
            "reference_period",
            "availability_timestamp_utc",
            "availability_basis",
            "source_release_id",
            "source_artifact_sha256",
            "transformation_version",
            "unit",
        ),
        "macro_control.control",
    )
    expect_identifier(metadata["control_id"], "macro_control.control.control_id")
    expect_quarter(
        metadata["reference_period"],
        "macro_control.control.reference_period",
    )
    availability_timestamp = expect_timestamp(
        metadata["availability_timestamp_utc"],
        "macro_control.control.availability_timestamp_utc",
    )
    expect_one_of(
        metadata["availability_basis"],
        Set(["official_release_timestamp", "archive_retrieval_completion"]),
        "macro_control.control.availability_basis",
    )
    expect_identifier(
        metadata["source_release_id"],
        "macro_control.control.source_release_id",
    )
    expect_hash(
        metadata["source_artifact_sha256"],
        "macro_control.control.source_artifact_sha256",
    )
    expect_one_of(
        metadata["transformation_version"],
        Set(["bea-nipa-saar-to-quarter.v1"]),
        "macro_control.control.transformation_version",
    )
    expect_one_of(
        metadata["unit"],
        Set(["millions_current_usd_per_quarter"]),
        "macro_control.control.unit",
    )

    values = expect_exact_keys(
        root["values"],
        REQUIRED_CONTROL_IDS,
        "macro_control.values",
    )
    numbers = Dict(
        key => expect_number(values[key], "macro_control.values.$key")
            for key in REQUIRED_CONTROL_IDS
    )
    for key in setdiff(
            collect(REQUIRED_CONTROL_IDS),
            ["inventory_investment"],
        )
        numbers[key] > 0 ||
            fail("macro_control.values.$key", "must be strictly positive")
    end

    identities = expect_exact_keys(
        root["identities"],
        (
            "gdp_formula",
            "gdp_residual",
            "gdp_tolerance",
            "investment_formula",
            "investment_residual",
            "investment_tolerance",
        ),
        "macro_control.identities",
    )
    expect_one_of(
        identities["gdp_formula"],
        Set(["gdp-pce-gpdi-exports+imports-government"]),
        "macro_control.identities.gdp_formula",
    )
    expect_one_of(
        identities["investment_formula"],
        Set(["gpdi-fixed_investment-inventory_investment"]),
        "macro_control.identities.investment_formula",
    )
    gdp_residual =
        numbers["nominal_gdp"] -
        numbers["pce"] -
        numbers["gpdi"] -
        numbers["exports"] +
        numbers["imports"] -
        numbers["government_consumption_and_investment"]
    investment_residual =
        numbers["gpdi"] -
        numbers["fixed_investment"] -
        numbers["inventory_investment"]
    declared_gdp = expect_number(
        identities["gdp_residual"],
        "macro_control.identities.gdp_residual",
    )
    declared_investment = expect_number(
        identities["investment_residual"],
        "macro_control.identities.investment_residual",
    )
    isapprox(declared_gdp, gdp_residual; atol = 1.0e-9, rtol = 0.0) ||
        fail(
        "macro_control.identities.gdp_residual",
        "does not equal the residual implied by the controls",
    )
    isapprox(
        declared_investment,
        investment_residual;
        atol = 1.0e-9,
        rtol = 0.0,
    ) ||
        fail(
        "macro_control.identities.investment_residual",
        "does not equal the residual implied by the controls",
    )
    gdp_tolerance = expect_number(
        identities["gdp_tolerance"],
        "macro_control.identities.gdp_tolerance",
    )
    investment_tolerance = expect_number(
        identities["investment_tolerance"],
        "macro_control.identities.investment_tolerance",
    )
    0 < gdp_tolerance <= 1.0 ||
        fail(
        "macro_control.identities.gdp_tolerance",
        "must be in (0, 1] million dollars",
    )
    0 < investment_tolerance <= 0.5 ||
        fail(
        "macro_control.identities.investment_tolerance",
        "must be in (0, 0.5] million dollars",
    )
    abs(gdp_residual) <= gdp_tolerance ||
        fail(
        "macro_control.identities.gdp_residual",
        "exceeds the declared source-rounding tolerance",
    )
    abs(investment_residual) <= investment_tolerance ||
        fail(
        "macro_control.identities.investment_residual",
        "exceeds the declared source-rounding tolerance",
    )
    digest = validate_root_header(root, MACRO_SCHEMA)
    return (;
        control_id = String(metadata["control_id"]),
        reference_period = String(metadata["reference_period"]),
        availability_timestamp,
        gdp_residual,
        investment_residual,
        sha256 = digest,
    )
end

macro_control_sha256(control) = validate_macro_control(control).sha256

function validate_mapping_row(row, index)
    location = "mapping_registry.mapping[$index]"
    item = expect_exact_keys(
        row,
        (
            "mapping_id",
            "source_control_id",
            "model_concept",
            "model_fields",
            "status",
            "treatment",
            "evidence",
            "model_owner",
            "independent_validator",
        ),
        location,
    )
    mapping_id = expect_identifier(item["mapping_id"], "$location.mapping_id")
    source_control_id = expect_identifier(
        item["source_control_id"],
        "$location.source_control_id",
    )
    haskey(CONTROL_TO_MAPPING, mapping_id) ||
        fail("$location.mapping_id", "is not a required mapping")
    source_control_id == CONTROL_TO_MAPPING[mapping_id] ||
        fail(
        "$location.source_control_id",
        "does not match the required source control",
    )
    expect_string(item["model_concept"], "$location.model_concept")
    expect_string_array(item["model_fields"], "$location.model_fields")
    status = expect_one_of(
        item["status"],
        Set(["approved", "unresolved", "rejected"]),
        "$location.status",
    )
    expect_string(item["treatment"], "$location.treatment")
    evidence = expect_string_array(item["evidence"], "$location.evidence")
    owner = expect_string(item["model_owner"], "$location.model_owner")
    validator = expect_string(
        item["independent_validator"],
        "$location.independent_validator",
    )
    if status == "approved"
        lowercase(owner) in PLACEHOLDERS &&
            fail("$location.model_owner", "approved mapping needs an owner")
        lowercase(validator) in PLACEHOLDERS &&
            fail(
            "$location.independent_validator",
            "approved mapping needs an independent validator",
        )
        owner != validator ||
            fail(
            "$location.independent_validator",
            "must differ from the model owner",
        )
        any(entry -> lowercase(entry) in PLACEHOLDERS, evidence) &&
            fail("$location.evidence", "approved evidence is a placeholder")
    end
    return (; mapping_id, status)
end

function _mapping_gate(rows)
    open = sort!(
        [
            row.mapping_id for row in rows if row.status != "approved"
        ]
    )
    return (;
        status = isempty(open) ? "CLOSED" : "OPEN",
        open_mapping_ids = open,
    )
end

function validate_mapping_registry(registry)
    root = expect_exact_keys(
        registry,
        ("artifact", "gate", "mapping"),
        "mapping_registry",
    )
    mappings = root["mapping"]
    mappings isa AbstractVector ||
        fail("mapping_registry.mapping", "must be an array of tables")
    rows = [
        validate_mapping_row(row, index)
            for (index, row) in enumerate(mappings)
    ]
    ids = [row.mapping_id for row in rows]
    length(ids) == length(unique(ids)) ||
        fail("mapping_registry.mapping", "contains duplicate mapping IDs")
    Set(ids) == Set(REQUIRED_MAPPING_IDS) ||
        fail(
        "mapping_registry.mapping",
        "must contain exactly $(join(REQUIRED_MAPPING_IDS, ", "))",
    )
    result = _mapping_gate(rows)
    gate = expect_exact_keys(
        root["gate"],
        ("status", "rule"),
        "mapping_registry.gate",
    )
    expect_one_of(
        gate["rule"],
        Set([MAPPING_GATE_RULE]),
        "mapping_registry.gate.rule",
    )
    declared_status = expect_one_of(
        gate["status"],
        Set(["OPEN", "CLOSED"]),
        "mapping_registry.gate.status",
    )
    declared_status == result.status ||
        fail(
        "mapping_registry.gate.status",
        "declares $declared_status but computed status is $(result.status)",
    )
    digest = validate_root_header(root, MAPPING_SCHEMA)
    return (;
        status = result.status,
        open_mapping_ids = result.open_mapping_ids,
        sha256 = digest,
    )
end

mapping_registry_sha256(registry) =
    validate_mapping_registry(registry).sha256

mapping_gate(registry) = begin
    result = validate_mapping_registry(registry)
    return (;
        status = result.status,
        open_mapping_ids = result.open_mapping_ids,
    )
end

function validate_block(row, index, origin_timestamp)
    location = "origin_package.blocks[$index]"
    item = expect_exact_keys(
        row,
        (
            "block_id",
            "status",
            "eligibility_basis",
            "artifact_sha256",
            "as_of_timestamp_utc",
            "reason",
            "evidence",
        ),
        location,
    )
    block_id = expect_identifier(item["block_id"], "$location.block_id")
    haskey(EXPECTED_BLOCK_BASIS, block_id) ||
        fail("$location.block_id", "is not a required block")
    status = expect_one_of(
        item["status"],
        Set(["available", "missing", "rejected", "pending"]),
        "$location.status",
    )
    basis = expect_one_of(
        item["eligibility_basis"],
        Set(["release_timestamp", "origin_information_cutoff", "frozen_configuration"]),
        "$location.eligibility_basis",
    )
    basis == EXPECTED_BLOCK_BASIS[block_id] ||
        fail(
        "$location.eligibility_basis",
        "must be $(EXPECTED_BLOCK_BASIS[block_id]) for $block_id",
    )
    reason = expect_string(item["reason"], "$location.reason")
    evidence = expect_string_array(item["evidence"], "$location.evidence")
    artifact_sha256 = expect_string(
        item["artifact_sha256"],
        "$location.artifact_sha256",
    )
    as_of = expect_string(
        item["as_of_timestamp_utc"],
        "$location.as_of_timestamp_utc",
    )
    if status == "available"
        expect_hash(artifact_sha256, "$location.artifact_sha256")
        if basis == "frozen_configuration"
            as_of == "not_applicable" ||
                fail(
                "$location.as_of_timestamp_utc",
                "must be not_applicable for frozen configuration",
            )
        else
            timestamp =
                expect_timestamp(as_of, "$location.as_of_timestamp_utc")
            timestamp <= origin_timestamp ||
                fail(
                "$location.as_of_timestamp_utc",
                "postdates the forecast origin",
            )
        end
    else
        artifact_sha256 == "unavailable" ||
            fail(
            "$location.artifact_sha256",
            "must be unavailable when the block is not available",
        )
        as_of == "unavailable" ||
            fail(
            "$location.as_of_timestamp_utc",
            "must be unavailable when the block is not available",
        )
    end
    return (; block_id, status, reason, evidence, artifact_sha256)
end

function validate_gate(row, index)
    location = "origin_package.gates[$index]"
    item = expect_exact_keys(
        row,
        ("gate_id", "status", "reason", "evidence"),
        location,
    )
    gate_id = expect_identifier(item["gate_id"], "$location.gate_id")
    gate_id in REQUIRED_GATE_IDS ||
        fail("$location.gate_id", "is not a required gate")
    status = expect_one_of(
        item["status"],
        Set(["pass", "fail", "pending"]),
        "$location.status",
    )
    reason = expect_string(item["reason"], "$location.reason")
    evidence = expect_string_array(item["evidence"], "$location.evidence")
    return (; gate_id, status, reason, evidence)
end

function _validate_exact_id_set(rows, required, location, field)
    ids = [getproperty(row, field) for row in rows]
    length(ids) == length(unique(ids)) ||
        fail(location, "contains duplicate IDs")
    Set(ids) == Set(required) ||
        fail(location, "must contain exactly $(join(required, ", "))")
    return nothing
end

function _validate_readiness_artifacts(
        resolver::OriginReadinessResolver,
        origin,
        macro_control,
        blocks,
    )
    available_blocks =
        sort!(String[row.block_id for row in blocks if row.status == "available"])
    expected_path_ids =
        Set(vcat(["protocol", "environment", "macro_source"], available_blocks))
    actual_path_ids = Set(keys(resolver.artifact_paths))
    actual_path_ids == expected_path_ids ||
        fail(
        "readiness_resolver.artifact_paths",
        "must contain exactly $(join(sort!(collect(expected_path_ids)), ", "))",
    )

    macro_metadata = expect_table(
        expect_table(macro_control, "macro_control")["control"],
        "macro_control.control",
    )
    expected_hashes = Dict{String, String}(
        "protocol" => String(origin["protocol_sha256"]),
        "environment" => String(origin["environment_sha256"]),
        "macro_source" =>
            expect_hash(
            macro_metadata["source_artifact_sha256"],
            "macro_control.control.source_artifact_sha256",
        ),
    )
    for block in blocks
        block.status == "available" || continue
        expected_hashes[block.block_id] = block.artifact_sha256
    end

    observed_hashes = Dict{String, String}()
    for artifact_id in sort!(collect(expected_path_ids))
        location = "readiness_resolver.artifact_paths.$artifact_id"
        path = abspath(normpath(resolver.artifact_paths[artifact_id]))
        isfile(path) || fail(location, "file does not exist: $path")
        islink(path) && fail(location, "symbolic links are not admissible")
        observed = file_sha256(path)
        observed == expected_hashes[artifact_id] ||
            fail(
            location,
            "SHA-256 mismatch; expected $(expected_hashes[artifact_id]), got $observed",
        )
        observed_hashes[artifact_id] = observed
    end
    return observed_hashes
end

function _validate_gate_outcome(outcome, gate_id)
    location = "readiness_resolver.gate_validators.$gate_id"
    outcome isa NamedTuple ||
        fail(location, "must return a named tuple")
    Set(propertynames(outcome)) == Set((:status, :reason, :evidence)) ||
        fail(location, "must return exactly status, reason, and evidence")
    return (
        status = expect_one_of(
            outcome.status,
            Set(["pass", "fail", "pending"]),
            "$location.status",
        ),
        reason = expect_string(outcome.reason, "$location.reason"),
        evidence = expect_string_array(outcome.evidence, "$location.evidence"),
    )
end

function _validate_readiness_gates(
        resolver::OriginReadinessResolver,
        root,
        origin_timestamp,
        blocks,
        gate_by_id,
        observed_hashes,
    )
    external_gate_ids = setdiff(
        Set(String(gate_id) for gate_id in REQUIRED_GATE_IDS),
        BUILTIN_GATE_IDS,
    )
    Set(keys(resolver.gate_validators)) == external_gate_ids ||
        fail(
        "readiness_resolver.gate_validators",
        "must contain exactly $(join(sort!(collect(external_gate_ids)), ", "))",
    )
    context = (
        origin_package = deepcopy(root),
        origin_timestamp = origin_timestamp,
        blocks = deepcopy(blocks),
        artifact_paths = copy(resolver.artifact_paths),
        artifact_sha256 = copy(observed_hashes),
    )
    for gate_id in sort!(collect(external_gate_ids))
        validator = resolver.gate_validators[gate_id]
        raw_outcome = try
            validator(context)
        catch error
            fail(
                "readiness_resolver.gate_validators.$gate_id",
                "validator raised $(sprint(showerror, error))",
            )
        end
        outcome = _validate_gate_outcome(raw_outcome, gate_id)
        declared = gate_by_id[gate_id]
        outcome.status == declared.status ||
            fail(
            "origin_package.gates.$gate_id.status",
            "declared $(declared.status), validator derived $(outcome.status)",
        )
        outcome.reason == declared.reason ||
            fail(
            "origin_package.gates.$gate_id.reason",
            "does not match the validator-derived reason",
        )
        outcome.evidence == declared.evidence ||
            fail(
            "origin_package.gates.$gate_id.evidence",
            "does not match the validator-derived evidence",
        )
    end

    for (artifact_id, before_hash) in observed_hashes
        after_hash = file_sha256(resolver.artifact_paths[artifact_id])
        after_hash == before_hash ||
            fail(
            "readiness_resolver.artifact_paths.$artifact_id",
            "artifact changed while gate validators ran",
        )
    end
    return nothing
end

function validate_origin_package(
        package;
        macro_control,
        mapping_registry,
        readiness_resolver = nothing,
    )
    root = expect_exact_keys(
        package,
        ("artifact", "origin", "blocks", "gates"),
        "origin_package",
    )
    origin = expect_exact_keys(
        root["origin"],
        (
            "origin_id",
            "origin_kind",
            "origin_timestamp_utc",
            "reference_period",
            "created_at_utc",
            "protocol_sha256",
            "environment_sha256",
            "macro_control_sha256",
            "mapping_registry_sha256",
            "model_variant_sha256",
            "parameter_registry_sha256",
            "information_track",
            "evidence_class",
            "status",
        ),
        "origin_package.origin",
    )
    origin_id =
        expect_identifier(origin["origin_id"], "origin_package.origin.origin_id")
    origin_kind = expect_one_of(
        origin["origin_kind"],
        Set(["retrospective", "prospective", "current_diagnostic"]),
        "origin_package.origin.origin_kind",
    )
    origin_timestamp = expect_timestamp(
        origin["origin_timestamp_utc"],
        "origin_package.origin.origin_timestamp_utc",
    )
    reference_period = expect_quarter(
        origin["reference_period"],
        "origin_package.origin.reference_period",
    )
    created_at = expect_timestamp(
        origin["created_at_utc"],
        "origin_package.origin.created_at_utc",
    )
    created_at >= origin_timestamp ||
        fail(
        "origin_package.origin.created_at_utc",
        "must not predate the forecast origin",
    )
    for field in (
            "protocol_sha256",
            "environment_sha256",
            "macro_control_sha256",
            "mapping_registry_sha256",
            "model_variant_sha256",
            "parameter_registry_sha256",
        )
        expect_hash(origin[field], "origin_package.origin.$field")
    end
    information_track = expect_one_of(
        origin["information_track"],
        Set(["common_information", "revised_mixed_vintage_diagnostic"]),
        "origin_package.origin.information_track",
    )
    evidence_class = expect_one_of(
        origin["evidence_class"],
        Set(["vintage_clean_candidate", "diagnostic_only_no_promotion"]),
        "origin_package.origin.evidence_class",
    )
    if information_track == "common_information"
        evidence_class == "vintage_clean_candidate" ||
            fail(
            "origin_package.origin.evidence_class",
            "common-information origins must be vintage-clean candidates",
        )
    else
        evidence_class == "diagnostic_only_no_promotion" ||
            fail(
            "origin_package.origin.evidence_class",
            "mixed-vintage origins must be diagnostic-only",
        )
        origin_kind == "current_diagnostic" ||
            fail(
            "origin_package.origin.origin_kind",
            "mixed-vintage origin must be a current diagnostic",
        )
    end
    declared_status = expect_one_of(
        origin["status"],
        Set(["ready", "cannot_run"]),
        "origin_package.origin.status",
    )

    macro_result = validate_macro_control(macro_control)
    macro_result.sha256 == origin["macro_control_sha256"] ||
        fail(
        "origin_package.origin.macro_control_sha256",
        "does not match the supplied macro-control artifact",
    )
    macro_result.reference_period == reference_period ||
        fail(
        "origin_package.origin.reference_period",
        "does not match the macro-control reference period",
    )
    macro_result.availability_timestamp <= origin_timestamp ||
        fail(
        "macro_control.control.availability_timestamp_utc",
        "postdates the forecast origin",
    )
    mapping = validate_mapping_registry(mapping_registry)
    mapping.sha256 == origin["mapping_registry_sha256"] ||
        fail(
        "origin_package.origin.mapping_registry_sha256",
        "does not match the supplied mapping registry",
    )

    blocks_value = root["blocks"]
    blocks_value isa AbstractVector ||
        fail("origin_package.blocks", "must be an array of tables")
    blocks = [
        validate_block(row, index, origin_timestamp)
            for (index, row) in enumerate(blocks_value)
    ]
    _validate_exact_id_set(
        blocks,
        REQUIRED_BLOCK_IDS,
        "origin_package.blocks",
        :block_id,
    )
    block_by_id = Dict(row.block_id => row for row in blocks)
    for (block_id, metadata_field) in (
            ("model_variant", "model_variant_sha256"),
            ("parameter_registry", "parameter_registry_sha256"),
        )
        block = block_by_id[block_id]
        if block.status == "available"
            block.artifact_sha256 == origin[metadata_field] ||
                fail(
                "origin_package.origin.$metadata_field",
                "does not match the available $block_id block",
            )
        end
    end

    gates_value = root["gates"]
    gates_value isa AbstractVector ||
        fail("origin_package.gates", "must be an array of tables")
    gates = [
        validate_gate(row, index)
            for (index, row) in enumerate(gates_value)
    ]
    _validate_exact_id_set(
        gates,
        REQUIRED_GATE_IDS,
        "origin_package.gates",
        :gate_id,
    )
    gate_by_id = Dict(row.gate_id => row for row in gates)
    expected_mapping_gate = mapping.status == "CLOSED" ? "pass" : "fail"
    gate_by_id["semantic_mapping"].status == expected_mapping_gate ||
        fail(
        "origin_package.gates.semantic_mapping",
        "must be $expected_mapping_gate for the supplied mapping registry",
    )
    gate_by_id["macro_control_identity"].status == "pass" ||
        fail(
        "origin_package.gates.macro_control_identity",
        "must pass after the supplied macro control validates",
    )
    readiness_candidate =
        all(row -> row.status == "available", blocks) &&
        all(row -> row.status == "pass", gates) &&
        mapping.status == "CLOSED"
    if readiness_candidate
        readiness_resolver isa OriginReadinessResolver ||
            fail(
            "origin_package.readiness",
            "ready status requires an OriginReadinessResolver with actual artifact paths and gate validators",
        )
        observed_hashes = _validate_readiness_artifacts(
            readiness_resolver,
            origin,
            macro_control,
            blocks,
        )
        _validate_readiness_gates(
            readiness_resolver,
            root,
            origin_timestamp,
            blocks,
            gate_by_id,
            observed_hashes,
        )
    end
    computed_ready = readiness_candidate
    computed_status = computed_ready ? "ready" : "cannot_run"
    declared_status == computed_status ||
        fail(
        "origin_package.origin.status",
        "declares $declared_status but computed status is $computed_status",
    )
    digest = validate_root_header(root, ORIGIN_SCHEMA)
    return (;
        origin_id,
        origin_kind,
        origin_timestamp,
        reference_period,
        information_track,
        evidence_class,
        status = computed_status,
        blocks,
        gates,
        sha256 = digest,
    )
end

origin_package_sha256(
    package;
    macro_control,
    mapping_registry,
    readiness_resolver = nothing,
) =
    validate_origin_package(
    package;
    macro_control,
    mapping_registry,
    readiness_resolver,
).sha256

function _cannot_run_failures(package_result, mapping_registry)
    failures = Dict{String, Any}[]
    for block in package_result.blocks
        block.status == "available" && continue
        push!(
            failures,
            Dict{String, Any}(
                "failure_id" => "block:$(block.block_id)",
                "category" => "block",
                "status" => block.status,
                "reason" => block.reason,
                "evidence" => block.evidence,
            ),
        )
    end
    for gate in package_result.gates
        gate.status == "pass" && continue
        push!(
            failures,
            Dict{String, Any}(
                "failure_id" => "gate:$(gate.gate_id)",
                "category" => "gate",
                "status" => gate.status,
                "reason" => gate.reason,
                "evidence" => gate.evidence,
            ),
        )
    end
    mapping_rows = mapping_registry["mapping"]
    for row in mapping_rows
        row["status"] == "approved" && continue
        push!(
            failures,
            Dict{String, Any}(
                "failure_id" => "mapping:$(row["mapping_id"])",
                "category" => "mapping",
                "status" => String(row["status"]),
                "reason" => String(row["treatment"]),
                "evidence" => String.(row["evidence"]),
            ),
        )
    end
    sort!(failures; by = row -> row["failure_id"])
    return failures
end

function _build_cannot_run_record(
        package_result,
        mapping_registry;
        record_id,
        recorded_at_utc,
    )
    failures = _cannot_run_failures(package_result, mapping_registry)
    isempty(failures) &&
        fail("cannot_run_record.failures", "must not be empty")
    return Dict{String, Any}(
        "artifact" => Dict{String, Any}(
            "schema_version" => CANNOT_RUN_SCHEMA,
            "canonicalization" => CANONICALIZATION,
            "content_sha256" => repeat("0", 64),
        ),
        "record" => Dict{String, Any}(
            "record_id" => String(record_id),
            "origin_id" => package_result.origin_id,
            "origin_package_sha256" => package_result.sha256,
            "recorded_at_utc" => String(recorded_at_utc),
            "status" => "cannot_run",
            "information_track" => package_result.information_track,
            "evidence_class" => package_result.evidence_class,
            "failure_count" => length(failures),
        ),
        "failures" => failures,
    )
end

function build_cannot_run_record(
        package;
        macro_control,
        mapping_registry,
        record_id,
        recorded_at_utc,
        readiness_resolver = nothing,
    )
    package_result = validate_origin_package(
        package;
        macro_control,
        mapping_registry,
        readiness_resolver,
    )
    package_result.status == "cannot_run" ||
        fail(
        "origin_package.origin.status",
        "a ready origin cannot produce a cannot-run record",
    )
    expect_identifier(record_id, "cannot_run_record.record.record_id")
    recorded_at = expect_timestamp(
        recorded_at_utc,
        "cannot_run_record.record.recorded_at_utc",
    )
    recorded_at >= package_result.origin_timestamp ||
        fail(
        "cannot_run_record.record.recorded_at_utc",
        "must not predate the forecast origin",
    )
    record = _build_cannot_run_record(
        package_result,
        mapping_registry;
        record_id,
        recorded_at_utc,
    )
    stamp_content_sha256!(record)
    validate_cannot_run_record(
        record,
        package;
        macro_control,
        mapping_registry,
        readiness_resolver,
    )
    return record
end

function validate_cannot_run_record(
        record,
        package;
        macro_control,
        mapping_registry,
        readiness_resolver = nothing,
    )
    package_result = validate_origin_package(
        package;
        macro_control,
        mapping_registry,
        readiness_resolver,
    )
    package_result.status == "cannot_run" ||
        fail(
        "cannot_run_record",
        "cannot reference a ready origin package",
    )
    root = expect_exact_keys(
        record,
        ("artifact", "record", "failures"),
        "cannot_run_record",
    )
    metadata = expect_exact_keys(
        root["record"],
        (
            "record_id",
            "origin_id",
            "origin_package_sha256",
            "recorded_at_utc",
            "status",
            "information_track",
            "evidence_class",
            "failure_count",
        ),
        "cannot_run_record.record",
    )
    record_id = expect_identifier(
        metadata["record_id"],
        "cannot_run_record.record.record_id",
    )
    metadata["origin_id"] == package_result.origin_id ||
        fail(
        "cannot_run_record.record.origin_id",
        "does not match the origin package",
    )
    expect_hash(
        metadata["origin_package_sha256"],
        "cannot_run_record.record.origin_package_sha256",
    ) == package_result.sha256 ||
        fail(
        "cannot_run_record.record.origin_package_sha256",
        "does not match the origin package",
    )
    recorded_at = expect_timestamp(
        metadata["recorded_at_utc"],
        "cannot_run_record.record.recorded_at_utc",
    )
    recorded_at >= package_result.origin_timestamp ||
        fail(
        "cannot_run_record.record.recorded_at_utc",
        "must not predate the forecast origin",
    )
    expect_one_of(
        metadata["status"],
        Set(["cannot_run"]),
        "cannot_run_record.record.status",
    )
    metadata["information_track"] == package_result.information_track ||
        fail(
        "cannot_run_record.record.information_track",
        "does not match the origin package",
    )
    metadata["evidence_class"] == package_result.evidence_class ||
        fail(
        "cannot_run_record.record.evidence_class",
        "does not match the origin package",
    )
    failures = root["failures"]
    failures isa AbstractVector ||
        fail("cannot_run_record.failures", "must be an array of tables")
    failure_count = expect_integer(
        metadata["failure_count"],
        "cannot_run_record.record.failure_count";
        minimum = 1,
    )
    failure_count == length(failures) ||
        fail(
        "cannot_run_record.record.failure_count",
        "does not match the failure array",
    )
    for (index, failure) in enumerate(failures)
        location = "cannot_run_record.failures[$index]"
        item = expect_exact_keys(
            failure,
            ("failure_id", "category", "status", "reason", "evidence"),
            location,
        )
        expect_identifier(item["failure_id"], "$location.failure_id")
        expect_one_of(
            item["category"],
            Set(["block", "gate", "mapping"]),
            "$location.category",
        )
        expect_one_of(
            item["status"],
            Set(
                [
                    "missing",
                    "rejected",
                    "pending",
                    "fail",
                    "unresolved",
                ]
            ),
            "$location.status",
        )
        expect_string(item["reason"], "$location.reason")
        expect_string_array(item["evidence"], "$location.evidence")
    end
    expected = _build_cannot_run_record(
        package_result,
        mapping_registry;
        record_id,
        recorded_at_utc = metadata["recorded_at_utc"],
    )
    canonical_actual = deepcopy(root["failures"])
    canonical_expected = expected["failures"]
    io_actual = IOBuffer()
    io_expected = IOBuffer()
    _canonical_write(io_actual, canonical_actual)
    _canonical_write(io_expected, canonical_expected)
    take!(io_actual) == take!(io_expected) ||
        fail(
        "cannot_run_record.failures",
        "does not exactly enumerate the current blockers",
    )
    digest = validate_root_header(root, CANNOT_RUN_SCHEMA)
    return (;
        record_id,
        origin_id = package_result.origin_id,
        failure_count,
        sha256 = digest,
    )
end

end
