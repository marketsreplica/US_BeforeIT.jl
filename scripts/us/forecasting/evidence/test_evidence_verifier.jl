#!/usr/bin/env julia

using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "USEvidenceVerifier.jl"))
using .USEvidenceVerifier
include(joinpath(@__DIR__, "..", "contracts", "USForecastProtocol.jl"))
using .USForecastProtocol

const PROTOCOL_HASH =
    "88519e5b04936f528396cf5243ff270844d0d38651fd84fc3b1c76fef997b584"

function write_bytes(path, bytes)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, bytes)
    end
    return file_sha256(path)
end

function write_toml(path, document)
    mkpath(dirname(path))
    open(path, "w") do io
        TOML.print(io, document; sorted = true)
    end
    return file_sha256(path)
end

function origin_rows(count)
    rows = Dict{String, Any}[]
    for index in 1:count
        year = 1999 + cld(index, 4)
        quarter = mod1(index, 4)
        month = 3 * quarter
        timestamp = Dates.format(
            DateTime(year, month, 28, 10, 0, 0),
            dateformat"yyyy-mm-ddTHH:MM:SSZ",
        )
        origin_id = "origin-$(lpad(string(index), 3, '0'))"
        push!(
            rows,
            Dict{String, Any}(
                "origin_id" => origin_id,
                "origin_timestamp_utc" => timestamp,
                "reference_key" => "$year-Q$quarter",
                "product_id" => "quarterly_unconditional",
                "origin_rule_id" => "quarterly-after-advance.v1-draft",
                "information_track" => "common_information",
                "protocol_eligible" => true,
                "origin_evidence_sha256" =>
                    bytes2hex(sha256(codeunits("evidence:$origin_id"))),
            ),
        )
    end
    return rows
end

function truth_value_bytes(target_id, layer_id, rows)
    ordered = sort(
        collect(rows);
        by = row -> (row["origin_id"], row["reference_key"]),
    )
    io = IOBuffer()
    println(
        io,
        "target_id\ttruth_layer_id\torigin_id\treference_key\tvalue",
    )
    for (index, row) in enumerate(ordered)
        println(
            io,
            join(
                (
                    target_id,
                    layer_id,
                    row["origin_id"],
                    row["reference_key"],
                    string(index),
                ),
                '\t',
            ),
        )
    end
    return take!(io)
end

function truth_reference(root, target_id, layer_id)
    return only(
        reference for reference in root["truth_manifests"] if
            reference["target_id"] == target_id &&
            reference["truth_layer_id"] == layer_id
    )
end

function operator_reference(root, target_id)
    return only(
        reference for reference in root["operator_manifests"] if
            reference["target_id"] == target_id
    )
end

function write_root!(bundle)
    stamp_content_sha256!(bundle.root)
    write_toml(bundle.path, bundle.root)
    return bundle
end

function build_complete_bundle(
        directory;
        origin_count = 40,
        evidence_class = "synthetic_test_only",
    )
    root = deepcopy(load_evidence_manifest())
    root["contract"]["evidence_class"] = evidence_class
    root["contract"]["created_at_utc"] = "2026-08-05T12:00:00Z"
    root["contract"]["availability_status"] = "candidate"
    root["contract"]["status_reason"] =
        "Hermetic synthetic verifier fixture; not empirical forecast evidence."
    rows = origin_rows(origin_count)

    for reference in root["truth_manifests"]
        target_id = reference["target_id"]
        layer_id = reference["truth_layer_id"]
        manifest_directory =
            joinpath(directory, "truth", target_id, layer_id)
        data_path = joinpath(manifest_directory, "truth_values.tsv")
        data_digest = write_bytes(
            data_path,
            truth_value_bytes(target_id, layer_id, rows),
        )
        document = Dict{String, Any}(
            "truth" => Dict{String, Any}(
                "schema_version" =>
                    "beforeit-us-truth-evidence-manifest.v1",
                "manifest_id" => "$target_id.$layer_id.truth.v1",
                "target_id" => target_id,
                "truth_layer_id" => layer_id,
                "protocol_id" =>
                    "beforeit-us-forecast-evaluation.v1-draft",
                "protocol_sha256" => PROTOCOL_HASH,
                "evidence_class" => evidence_class,
                "truth_artifact_format" =>
                    "beforeit-us-truth-values-tsv.v1",
                "truth_artifact_path" => "truth_values.tsv",
                "truth_artifact_sha256" => data_digest,
                "observation_count" => length(rows),
            ),
            "observations" => deepcopy(rows),
        )
        manifest_path = joinpath(manifest_directory, "manifest.toml")
        reference["status"] = "available"
        reference["manifest_path"] = relpath(manifest_path, directory)
        reference["manifest_sha256"] = write_toml(manifest_path, document)
    end

    for reference in root["operator_manifests"]
        target_id = reference["target_id"]
        operator_id = reference["operator_id"]
        manifest_directory = joinpath(directory, "operators", target_id)
        operator_artifact_path =
            joinpath(manifest_directory, "operator.jl")
        operator_artifact_sha256 = write_bytes(
            operator_artifact_path,
            codeunits("# synthetic operator for $target_id\n"),
        )
        validation_artifact_path =
            joinpath(manifest_directory, "validation.txt")
        validation_artifact_sha256 = write_bytes(
            validation_artifact_path,
            codeunits("synthetic validation evidence for $target_id\n"),
        )
        validation_receipt_document = Dict{String, Any}(
            "receipt" => Dict{String, Any}(
                "schema_version" =>
                    "beforeit-us-operator-validation-receipt.v1",
                "receipt_id" => "validation.$target_id.v1",
                "target_id" => target_id,
                "operator_id" => operator_id,
                "protocol_id" =>
                    "beforeit-us-forecast-evaluation.v1-draft",
                "protocol_sha256" => PROTOCOL_HASH,
                "evidence_class" => evidence_class,
                "operator_artifact_sha256" =>
                    operator_artifact_sha256,
                "validation_artifact_sha256" =>
                    validation_artifact_sha256,
                "decision" => "approved",
                "validator_id" => "validator-$target_id",
                "validator_role" => "independent_validation",
                "issued_at_utc" => "2026-08-05T10:00:00Z",
            ),
        )
        validation_receipt_path =
            joinpath(manifest_directory, "validation_receipt.toml")
        validation_receipt_sha256 =
            write_toml(validation_receipt_path, validation_receipt_document)
        signoff_receipt_document = Dict{String, Any}(
            "receipt" => Dict{String, Any}(
                "schema_version" =>
                    "beforeit-us-operator-signoff-receipt.v1",
                "receipt_id" => "signoff.$target_id.v1",
                "target_id" => target_id,
                "operator_id" => operator_id,
                "protocol_id" =>
                    "beforeit-us-forecast-evaluation.v1-draft",
                "protocol_sha256" => PROTOCOL_HASH,
                "evidence_class" => evidence_class,
                "operator_artifact_sha256" =>
                    operator_artifact_sha256,
                "validation_artifact_sha256" =>
                    validation_artifact_sha256,
                "validation_receipt_sha256" =>
                    validation_receipt_sha256,
                "decision" => "approved",
                "signatory_id" => "lead-$target_id",
                "signatory_role" => "research_lead",
                "issued_at_utc" => "2026-08-05T11:00:00Z",
            ),
        )
        signoff_receipt_path =
            joinpath(manifest_directory, "signoff_receipt.toml")
        signoff_receipt_sha256 =
            write_toml(signoff_receipt_path, signoff_receipt_document)
        operator_document = Dict{String, Any}(
            "operator" => Dict{String, Any}(
                "schema_version" =>
                    "beforeit-us-operator-evidence-manifest.v1",
                "manifest_id" => "$target_id.operator.v1",
                "target_id" => target_id,
                "operator_id" => operator_id,
                "protocol_id" =>
                    "beforeit-us-forecast-evaluation.v1-draft",
                "protocol_sha256" => PROTOCOL_HASH,
                "evidence_class" => evidence_class,
                "operator_artifact_path" => "operator.jl",
                "operator_artifact_sha256" =>
                    operator_artifact_sha256,
                "validation_artifact_path" => "validation.txt",
                "validation_artifact_sha256" =>
                    validation_artifact_sha256,
                "validation_receipt_path" => "validation_receipt.toml",
                "validation_receipt_sha256" =>
                    validation_receipt_sha256,
                "signoff_receipt_path" => "signoff_receipt.toml",
                "signoff_receipt_sha256" => signoff_receipt_sha256,
            ),
        )
        manifest_path = joinpath(manifest_directory, "manifest.toml")
        reference["status"] = "available"
        reference["manifest_path"] = relpath(manifest_path, directory)
        reference["manifest_sha256"] =
            write_toml(manifest_path, operator_document)
    end

    path = joinpath(directory, "evidence.toml")
    bundle = (; root, path, directory)
    return write_root!(bundle)
end

function mutate_truth_manifest!(bundle, target_id, layer_id, mutation)
    reference = truth_reference(bundle.root, target_id, layer_id)
    path = joinpath(bundle.directory, reference["manifest_path"])
    document = TOML.parsefile(path)
    mutation(document, dirname(path))
    reference["manifest_sha256"] = write_toml(path, document)
    write_root!(bundle)
    return document
end

mutate_truth_manifest!(mutation::Function, bundle, target_id, layer_id) =
    mutate_truth_manifest!(bundle, target_id, layer_id, mutation)

function rewrite_truth_value_keys!(
        document,
        manifest_directory,
        replacements;
        append = nothing,
    )
    truth = document["truth"]
    path = joinpath(manifest_directory, truth["truth_artifact_path"])
    lines = readlines(path)
    header = popfirst!(lines)
    rows = [split(line, '\t'; keepempty = true) for line in lines]
    for (old_key, observation) in replacements
        index = findfirst(
            fields -> (fields[3], fields[4]) == old_key,
            rows,
        )
        index === nothing &&
            error("synthetic truth row $old_key was not found")
        rows[index][3] = observation["origin_id"]
        rows[index][4] = observation["reference_key"]
    end
    if append !== nothing
        observation, value = append
        push!(
            rows,
            [
                truth["target_id"],
                truth["truth_layer_id"],
                observation["origin_id"],
                observation["reference_key"],
                string(value),
            ],
        )
    end
    sort!(rows; by = fields -> (fields[3], fields[4]))
    bytes = codeunits(
        join(vcat([header], [join(fields, '\t') for fields in rows]), '\n') *
            "\n",
    )
    truth["truth_artifact_sha256"] = write_bytes(path, bytes)
    return document
end

function mutate_operator_manifest!(bundle, target_id, mutation)
    reference = operator_reference(bundle.root, target_id)
    path = joinpath(bundle.directory, reference["manifest_path"])
    document = TOML.parsefile(path)
    mutation(document, dirname(path))
    reference["manifest_sha256"] = write_toml(path, document)
    write_root!(bundle)
    return document
end

mutate_operator_manifest!(mutation::Function, bundle, target_id) =
    mutate_operator_manifest!(bundle, target_id, mutation)

function mutate_receipt!(
        operator_document,
        manifest_directory,
        kind,
        mutation;
        rebind_signoff = false,
    )
    operator = operator_document["operator"]
    path_key =
        kind == :validation ?
        "validation_receipt_path" : "signoff_receipt_path"
    hash_key =
        kind == :validation ?
        "validation_receipt_sha256" : "signoff_receipt_sha256"
    path = joinpath(manifest_directory, operator[path_key])
    receipt = TOML.parsefile(path)
    mutation(receipt)
    operator[hash_key] = write_toml(path, receipt)
    if kind == :validation && rebind_signoff
        signoff_path =
            joinpath(manifest_directory, operator["signoff_receipt_path"])
        signoff = TOML.parsefile(signoff_path)
        signoff["receipt"]["validation_receipt_sha256"] =
            operator["validation_receipt_sha256"]
        operator["signoff_receipt_sha256"] =
            write_toml(signoff_path, signoff)
    end
    return receipt
end

function mutate_receipt!(
        mutation::Function,
        operator_document,
        manifest_directory,
        kind;
        rebind_signoff = false,
    )
    return mutate_receipt!(
        operator_document,
        manifest_directory,
        kind,
        mutation;
        rebind_signoff,
    )
end

function restamped_copy(manifest, mutation)
    copy = deepcopy(manifest)
    mutation(copy)
    stamp_content_sha256!(copy)
    return copy
end

@testset "Checked-in unavailable evidence is explicit and fail-closed" begin
    schema = TOML.parsefile(joinpath(@__DIR__, "artifact_evidence.schema.toml"))
    protocol = TOML.parsefile(normpath(joinpath(@__DIR__, "..", "protocol.toml")))
    protocol_operators = Dict(
        target["target_id"] => target["operator_version"] for
            target in protocol["targets"]
    )
    @test schema["minimum_common_protocol_eligible_origins"] == 40
    @test schema["root_manifest"]["required_truth_manifest_references"] == 24
    @test schema["root_manifest"]["required_operator_manifest_references"] == 8
    @test protocol["protocol_id"] ==
        "beforeit-us-forecast-evaluation.v1-draft"
    @test protocol_sha256(load_protocol()) == PROTOCOL_HASH
    @test Set(keys(protocol_operators)) == Set(EXPECTED_TARGET_IDS)
    @test protocol_operators == EXPECTED_OPERATOR_IDS
    @test Set(REQUIRED_TRUTH_LAYER_IDS) ⊆ Set(keys(protocol["truth"]))

    manifest = load_evidence_manifest()
    validation = validate_evidence_manifest(manifest)
    result = verify_evidence()
    @test validation.sha256 ==
        "01fa10389150bc8c905ef502f583510649745b3bb38bea9b263975fb6662dc3f"
    @test validation.sha256 == evidence_manifest_sha256(manifest)
    @test validation.sha256 == computed_content_sha256(manifest)
    @test validation.evidence_class == "repository_audit"
    @test validation.availability_status == "unavailable"
    @test validation.available_truth_manifest_count == 0
    @test validation.available_operator_manifest_count == 0
    @test result.verified === false
    @test result.status == "NOT_VERIFIED"
    @test !occursin("READY", result.status)
    @test result.common_origin_count == 0
    @test isempty(result.common_origin_ids)
    @test length(result.blockers) == 33
    @test count(
        blocker -> occursin("truth manifest", blocker),
        result.blockers,
    ) == 24
    @test count(
        blocker -> occursin("operator manifest", blocker),
        result.blockers,
    ) == 8
    @test any(blocker -> occursin("0/40", blocker), result.blockers)
    @test_throws EvidenceError require_verified_evidence()
end

@testset "Forty common synthetic origins verify bundle integrity only" begin
    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        result = verify_evidence(bundle.path)
        required = require_integrity_verified(bundle.path)
        @test result.integrity_verified === true
        @test result.verified === false
        @test result.promotion_eligible === false
        @test result.status == "VERIFIED_TEST_FIXTURE"
        @test result.verification_scope ==
            "local_bundle_integrity_only"
        @test result.evidence_class == "synthetic_test_only"
        @test result.common_origin_count == 40
        @test result.common_origin_ids ==
            ["origin-$(lpad(string(index), 3, '0'))" for index in 1:40]
        @test result.available_truth_manifest_count == 24
        @test result.available_operator_manifest_count == 8
        @test isempty(result.integrity_blockers)
        @test length(result.blockers) == 4
        @test any(
            blocker -> occursin("not resolved", blocker),
            result.blockers,
        )
        @test_throws EvidenceError require_verified_evidence(bundle.path)
        @test length(result.truth_results) == 24
        @test length(result.operator_results) == 8
        @test required.evidence_manifest_sha256 ==
            evidence_manifest_sha256(TOML.parsefile(bundle.path))
        @test all(
            isfile(entry.truth_artifact_path) for entry in result.truth_results
        )
        @test all(
            isfile(entry.validation_receipt_path) &&
                isfile(entry.signoff_receipt_path) for
                entry in result.operator_results
        )
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory; origin_count = 41)
        @test verify_evidence(bundle.path).common_origin_count == 41
    end
end

@testset "Integrity verification cannot become promotion evidence" begin
    for (evidence_class, expected_status, expected_blocker_count) in (
            (
                "repository_audit",
                "BUNDLE_INTEGRITY_VERIFIED_AUDIT",
                4,
            ),
            (
                "retrospective_evaluation",
                "BUNDLE_INTEGRITY_VERIFIED",
                3,
            ),
        )
        mktempdir() do directory
            bundle = build_complete_bundle(
                directory;
                evidence_class,
            )
            result = verify_evidence(bundle.path)
            @test result.integrity_verified
            @test !result.verified
            @test !result.promotion_eligible
            @test result.status == expected_status
            @test length(result.blockers) == expected_blocker_count
            @test_throws EvidenceError require_verified_evidence(
                bundle.path,
            )
        end
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, manifest_directory
            truth = document["truth"]
            artifact_path =
                joinpath(manifest_directory, truth["truth_artifact_path"])
            truth["truth_artifact_sha256"] =
                write_bytes(artifact_path, UInt8[])
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, manifest_directory
            truth = document["truth"]
            artifact_path =
                joinpath(manifest_directory, truth["truth_artifact_path"])
            lines = readlines(artifact_path)
            fields = split(lines[2], '\t'; keepempty = true)
            fields[1] = "nominal_gdp"
            lines[2] = join(fields, '\t')
            truth["truth_artifact_sha256"] = write_bytes(
                artifact_path,
                codeunits(join(lines, '\n') * "\n"),
            )
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        aliased_hash = bytes2hex(sha256(codeunits("aliased-origin")))
        for target_id in EXPECTED_TARGET_IDS
            for layer_id in REQUIRED_TRUTH_LAYER_IDS
                mutate_truth_manifest!(
                    bundle,
                    target_id,
                    layer_id,
                ) do document, _
                    for observation in document["observations"]
                        observation["origin_timestamp_utc"] =
                            "2000-03-28T10:00:00Z"
                        observation["origin_evidence_sha256"] =
                            aliased_hash
                    end
                end
            end
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_operator_manifest!(
            bundle,
            "real_gdp",
        ) do document, manifest_directory
            operator = document["operator"]
            artifact_path =
                joinpath(
                manifest_directory,
                operator["operator_artifact_path"],
            )
            operator["operator_artifact_sha256"] =
                write_bytes(artifact_path, UInt8[])
            validation_path =
                joinpath(
                manifest_directory,
                operator["validation_receipt_path"],
            )
            validation = TOML.parsefile(validation_path)
            validation["receipt"]["operator_artifact_sha256"] =
                operator["operator_artifact_sha256"]
            operator["validation_receipt_sha256"] =
                write_toml(validation_path, validation)
            signoff_path =
                joinpath(
                manifest_directory,
                operator["signoff_receipt_path"],
            )
            signoff = TOML.parsefile(signoff_path)
            signoff["receipt"]["operator_artifact_sha256"] =
                operator["operator_artifact_sha256"]
            signoff["receipt"]["validation_receipt_sha256"] =
                operator["validation_receipt_sha256"]
            operator["signoff_receipt_sha256"] =
                write_toml(signoff_path, signoff)
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do bundle_directory
        bundle = build_complete_bundle(bundle_directory)
        mktempdir() do nominal_directory
            link_path = joinpath(nominal_directory, "evidence.toml")
            symlink(bundle.path, link_path)
            @test_throws EvidenceError verify_evidence(link_path)
        end
    end
end

@testset "Root manifest schema rejects ambiguity and false declarations" begin
    unavailable = load_evidence_manifest()
    invalid_mutations = [
        manifest -> (manifest["unknown"] = "field"),
        manifest -> delete!(manifest, "operator_manifests"),
        manifest -> (manifest["artifact"]["schema_version"] = "wrong"),
        manifest -> (manifest["artifact"]["canonicalization"] = "wrong"),
        manifest -> (manifest["contract"]["contract_id"] = "wrong"),
        manifest -> (manifest["contract"]["protocol_id"] = "wrong"),
        manifest -> (manifest["contract"]["protocol_sha256"] = repeat("f", 64)),
        manifest -> (manifest["contract"]["evidence_class"] = "claimed_real"),
        manifest -> (manifest["contract"]["created_at_utc"] = "2026-08-05"),
        manifest -> (manifest["contract"]["availability_status"] = "candidate"),
        manifest -> (manifest["contract"]["required_target_count"] = 7),
        manifest -> (
            manifest["contract"]["required_truth_layers"] =
                ["mature", "near_mature", "first_release"]
        ),
        manifest -> (
            manifest["contract"]["minimum_common_protocol_eligible_origins"] = 39
        ),
        manifest -> (
            manifest["contract"]["eligible_product_id"] = "ragged_edge_nowcast"
        ),
        manifest -> (
            manifest["contract"]["eligible_origin_rule_id"] = "other"
        ),
        manifest -> (
            manifest["contract"]["eligible_information_track"] =
                "published_forecast"
        ),
        manifest -> push!(
            manifest["truth_manifests"],
            deepcopy(first(manifest["truth_manifests"])),
        ),
        manifest -> pop!(manifest["truth_manifests"]),
        manifest -> (
            manifest["truth_manifests"][1]["target_id"] = "renamed_gdp"
        ),
        manifest -> (
            manifest["truth_manifests"][1]["truth_layer_id"] = "latest"
        ),
        manifest -> (
            manifest["truth_manifests"][2] =
                deepcopy(manifest["truth_manifests"][1])
        ),
        manifest -> (
            manifest["truth_manifests"][1]["status"] = "available"
        ),
        manifest -> (
            manifest["truth_manifests"][1]["manifest_path"] = "claimed.toml"
        ),
        manifest -> (
            manifest["truth_manifests"][1]["manifest_sha256"] = repeat("a", 64)
        ),
        manifest -> push!(
            manifest["operator_manifests"],
            deepcopy(first(manifest["operator_manifests"])),
        ),
        manifest -> pop!(manifest["operator_manifests"]),
        manifest -> (
            manifest["operator_manifests"][1]["target_id"] = "renamed_gdp"
        ),
        manifest -> (
            manifest["operator_manifests"][1]["operator_id"] =
                "abm-to-wrong.v1"
        ),
        manifest -> (
            manifest["operator_manifests"][2] =
                deepcopy(manifest["operator_manifests"][1])
        ),
        manifest -> (
            manifest["operator_manifests"][1]["status"] = "available"
        ),
    ]
    for mutation in invalid_mutations
        candidate = restamped_copy(unavailable, mutation)
        @test_throws EvidenceError validate_evidence_manifest(candidate)
    end

    stale = deepcopy(unavailable)
    stale["contract"]["status_reason"] = "tampered without restamping"
    @test_throws EvidenceError validate_evidence_manifest(stale)

    mktempdir() do directory
        @test_throws EvidenceError load_evidence_manifest(
            joinpath(directory, "missing.toml"),
        )
        invalid_utf8 = joinpath(directory, "invalid_utf8.toml")
        write_bytes(invalid_utf8, UInt8[0xff, 0xfe])
        @test_throws EvidenceError load_evidence_manifest(invalid_utf8)
        malformed = joinpath(directory, "malformed.toml")
        write_bytes(malformed, codeunits("[broken\n"))
        @test_throws EvidenceError load_evidence_manifest(malformed)
    end

    reordered = deepcopy(unavailable)
    reverse!(reordered["truth_manifests"])
    stamp_content_sha256!(reordered)
    @test validate_evidence_manifest(reordered).sha256 ==
        computed_content_sha256(reordered)

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        first_reference = bundle.root["truth_manifests"][1]
        second_reference = bundle.root["truth_manifests"][2]
        second_reference["manifest_path"] = first_reference["manifest_path"]
        second_reference["manifest_sha256"] =
            first_reference["manifest_sha256"]
        stamp_content_sha256!(bundle.root)
        @test_throws EvidenceError validate_evidence_manifest(bundle.root)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        first_reference = bundle.root["operator_manifests"][1]
        second_reference = bundle.root["operator_manifests"][2]
        second_reference["manifest_path"] = first_reference["manifest_path"]
        second_reference["manifest_sha256"] =
            first_reference["manifest_sha256"]
        stamp_content_sha256!(bundle.root)
        @test_throws EvidenceError validate_evidence_manifest(bundle.root)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = first(bundle.root["truth_manifests"])
        reference["status"] = "unavailable"
        reference["manifest_path"] = "unavailable"
        reference["manifest_sha256"] = "unavailable"
        bundle.root["contract"]["availability_status"] = "partial"
        write_root!(bundle)
        result = verify_evidence(bundle.path)
        @test !result.verified
        @test result.available_truth_manifest_count == 23
        @test result.available_operator_manifest_count == 8
        @test result.common_origin_count == 0
        @test length(result.blockers) == 2
    end
end

@testset "Local path confinement and raw-byte hashes are mandatory" begin
    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = first(bundle.root["truth_manifests"])
        reference["manifest_path"] = "missing.toml"
        write_root!(bundle)
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    for bad_path in (
            "/absolute/manifest.toml",
            "../escape.toml",
            "truth/../escape.toml",
            "truth//manifest.toml",
            "truth\\manifest.toml",
        )
        mktempdir() do directory
            bundle = build_complete_bundle(directory)
            first(bundle.root["truth_manifests"])["manifest_path"] = bad_path
            write_root!(bundle)
            @test_throws EvidenceError verify_evidence(bundle.path)
        end
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = first(bundle.root["truth_manifests"])
        reference["manifest_sha256"] = repeat("f", 64)
        write_root!(bundle)
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = first(bundle.root["truth_manifests"])
        open(joinpath(directory, reference["manifest_path"]), "a") do io
            write(io, "\n")
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = first(bundle.root["truth_manifests"])
        path = joinpath(directory, reference["manifest_path"])
        reference["manifest_sha256"] = write_bytes(path, UInt8[0xff, 0xfe])
        write_root!(bundle)
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = first(bundle.root["truth_manifests"])
        path = joinpath(directory, reference["manifest_path"])
        reference["manifest_sha256"] =
            write_bytes(path, codeunits("[broken\n"))
        write_root!(bundle)
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        original = first(bundle.root["truth_manifests"])
        link_path = joinpath(directory, "linked_truth.toml")
        symlink(joinpath(directory, original["manifest_path"]), link_path)
        original["manifest_path"] = "linked_truth.toml"
        write_root!(bundle)
        @test_throws EvidenceError verify_evidence(bundle.path)
    end
end

@testset "Truth identity, unique keys, and common-origin intersection" begin
    semantic_mutations = [
        document -> (document["extra"] = Dict("x" => 1)),
        document -> (document["truth"]["schema_version"] = "wrong"),
        document -> (document["truth"]["manifest_id"] = "wrong"),
        document -> (document["truth"]["target_id"] = "nominal_gdp"),
        document -> (document["truth"]["truth_layer_id"] = "mature"),
        document -> (document["truth"]["protocol_id"] = "wrong"),
        document -> (document["truth"]["protocol_sha256"] = repeat("f", 64)),
        document -> (document["truth"]["evidence_class"] = "repository_audit"),
        document -> (document["truth"]["observation_count"] = 39),
        document -> (document["truth"]["observation_count"] = 0),
        document -> (document["observations"][1]["origin_id"] = "bad id"),
        document -> (
            document["observations"][1]["origin_timestamp_utc"] =
                "2000-01-01"
        ),
        document -> (
            document["observations"][1]["reference_key"] = "2000Q1"
        ),
        document -> (
            document["observations"][1]["product_id"] =
                "ragged_edge_nowcast"
        ),
        document -> (
            document["observations"][1]["origin_rule_id"] = "other"
        ),
        document -> (
            document["observations"][1]["information_track"] =
                "published_forecast"
        ),
        document -> (
            document["observations"][1]["protocol_eligible"] = "true"
        ),
        document -> (
            document["observations"][1]["origin_evidence_sha256"] =
                repeat("A", 64)
        ),
        document -> begin
            document["observations"][1]["protocol_eligible"] = false
            document["observations"][1]["origin_evidence_sha256"] =
                repeat("a", 64)
        end,
        document -> push!(
            document["observations"],
            deepcopy(first(document["observations"])),
        ),
    ]
    for mutation in semantic_mutations
        mktempdir() do directory
            bundle = build_complete_bundle(directory)
            mutate_truth_manifest!(
                bundle,
                "real_gdp",
                "first_release",
                (document, _) -> mutation(document),
            )
            @test_throws EvidenceError verify_evidence(bundle.path)
        end
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, _
            push!(
                document["observations"],
                deepcopy(first(document["observations"])),
            )
            document["truth"]["observation_count"] += 1
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, _
            duplicate = deepcopy(first(document["observations"]))
            duplicate["reference_key"] = "2099-Q4"
            duplicate["origin_timestamp_utc"] = "2001-01-01T10:00:00Z"
            push!(document["observations"], duplicate)
            document["truth"]["observation_count"] += 1
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, manifest_directory
            duplicate = deepcopy(first(document["observations"]))
            duplicate["reference_key"] = "2099-Q4"
            push!(document["observations"], duplicate)
            document["truth"]["observation_count"] += 1
            rewrite_truth_value_keys!(
                document,
                manifest_directory,
                Pair[];
                append = (duplicate, 41),
            )
        end
        result = verify_evidence(bundle.path)
        @test result.integrity_verified
        @test result.common_origin_count == 40
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, manifest_directory
            row = last(document["observations"])
            old_key = (row["origin_id"], row["reference_key"])
            row["origin_id"] = "origin-outsider"
            row["origin_timestamp_utc"] = "2010-12-28T10:00:00Z"
            row["reference_key"] = "2010-Q4"
            row["origin_evidence_sha256"] =
                bytes2hex(sha256(codeunits("evidence:origin-outsider")))
            rewrite_truth_value_keys!(
                document,
                manifest_directory,
                [old_key => row],
            )
        end
        result = verify_evidence(bundle.path)
        @test result.verified === false
        @test result.common_origin_count == 39
        @test any(blocker -> occursin("39/40", blocker), result.blockers)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        for target_id in EXPECTED_TARGET_IDS
            for layer_id in REQUIRED_TRUTH_LAYER_IDS
                mutate_truth_manifest!(
                    bundle,
                    target_id,
                    layer_id,
                ) do document, _
                    row = last(document["observations"])
                    row["protocol_eligible"] = false
                    row["origin_evidence_sha256"] = "unavailable"
                end
            end
        end
        result = verify_evidence(bundle.path)
        @test result.common_origin_count == 39
        @test !result.verified
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_truth_manifest!(
            bundle,
            "real_gdp",
            "first_release",
        ) do document, _
            document["observations"][1]["origin_timestamp_utc"] =
                "2000-03-28T10:00:01Z"
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    for mutation in (
            (document, _) -> (
                document["truth"]["truth_artifact_sha256"] = repeat("f", 64)
            ),
            (document, _) -> (
                document["truth"]["truth_artifact_path"] = "missing.bin"
            ),
            (document, _) -> (
                document["truth"]["truth_artifact_path"] = "../escape.bin"
            ),
        )
        mktempdir() do directory
            bundle = build_complete_bundle(directory)
            mutate_truth_manifest!(
                bundle,
                "real_gdp",
                "first_release",
                mutation,
            )
            @test_throws EvidenceError verify_evidence(bundle.path)
        end
    end
end

@testset "Operator bytes and validation/signoff receipt bindings" begin
    operator_mutations = [
        document -> (document["extra"] = Dict("x" => 1)),
        document -> (document["operator"]["schema_version"] = "wrong"),
        document -> (document["operator"]["manifest_id"] = "wrong"),
        document -> (document["operator"]["target_id"] = "nominal_gdp"),
        document -> (document["operator"]["operator_id"] = "wrong"),
        document -> (document["operator"]["protocol_id"] = "wrong"),
        document -> (
            document["operator"]["protocol_sha256"] = repeat("f", 64)
        ),
        document -> (
            document["operator"]["evidence_class"] = "repository_audit"
        ),
        document -> (
            document["operator"]["operator_artifact_sha256"] = repeat("f", 64)
        ),
        document -> (
            document["operator"]["validation_artifact_sha256"] =
                repeat("f", 64)
        ),
        document -> (
            document["operator"]["validation_receipt_sha256"] =
                repeat("f", 64)
        ),
        document -> (
            document["operator"]["signoff_receipt_sha256"] =
                repeat("f", 64)
        ),
        document -> (
            document["operator"]["operator_artifact_path"] = "../escape.jl"
        ),
    ]
    for mutation in operator_mutations
        mktempdir() do directory
            bundle = build_complete_bundle(directory)
            mutate_operator_manifest!(
                bundle,
                "real_gdp",
                (document, _) -> mutation(document),
            )
            @test_throws EvidenceError verify_evidence(bundle.path)
        end
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_operator_manifest!(
            bundle,
            "real_gdp",
        ) do document, _
            operator = document["operator"]
            operator["validation_artifact_path"] =
                operator["operator_artifact_path"]
            operator["validation_artifact_sha256"] =
                operator["operator_artifact_sha256"]
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    validation_mutations = [
        receipt -> (receipt["extra"] = Dict("x" => 1)),
        receipt -> (receipt["receipt"]["schema_version"] = "wrong"),
        receipt -> (receipt["receipt"]["receipt_id"] = "bad id"),
        receipt -> (receipt["receipt"]["target_id"] = "nominal_gdp"),
        receipt -> (receipt["receipt"]["operator_id"] = "wrong"),
        receipt -> (receipt["receipt"]["protocol_id"] = "wrong"),
        receipt -> (
            receipt["receipt"]["protocol_sha256"] = repeat("f", 64)
        ),
        receipt -> (
            receipt["receipt"]["evidence_class"] = "repository_audit"
        ),
        receipt -> (
            receipt["receipt"]["operator_artifact_sha256"] = repeat("f", 64)
        ),
        receipt -> (
            receipt["receipt"]["validation_artifact_sha256"] =
                repeat("f", 64)
        ),
        receipt -> (receipt["receipt"]["decision"] = "rejected"),
        receipt -> (receipt["receipt"]["validator_role"] = "research_lead"),
        receipt -> (receipt["receipt"]["issued_at_utc"] = "not-a-time"),
    ]
    for mutation in validation_mutations
        mktempdir() do directory
            bundle = build_complete_bundle(directory)
            mutate_operator_manifest!(
                bundle,
                "real_gdp",
            ) do document, manifest_directory
                mutate_receipt!(
                    document,
                    manifest_directory,
                    :validation,
                    mutation,
                )
            end
            @test_throws EvidenceError verify_evidence(bundle.path)
        end
    end

    signoff_mutations = [
        receipt -> (receipt["extra"] = Dict("x" => 1)),
        receipt -> (receipt["receipt"]["schema_version"] = "wrong"),
        receipt -> (receipt["receipt"]["receipt_id"] = "bad id"),
        receipt -> (receipt["receipt"]["target_id"] = "nominal_gdp"),
        receipt -> (receipt["receipt"]["operator_id"] = "wrong"),
        receipt -> (receipt["receipt"]["protocol_id"] = "wrong"),
        receipt -> (
            receipt["receipt"]["protocol_sha256"] = repeat("f", 64)
        ),
        receipt -> (
            receipt["receipt"]["evidence_class"] = "repository_audit"
        ),
        receipt -> (
            receipt["receipt"]["operator_artifact_sha256"] = repeat("f", 64)
        ),
        receipt -> (
            receipt["receipt"]["validation_artifact_sha256"] =
                repeat("f", 64)
        ),
        receipt -> (
            receipt["receipt"]["validation_receipt_sha256"] =
                repeat("f", 64)
        ),
        receipt -> (receipt["receipt"]["decision"] = "rejected"),
        receipt -> (
            receipt["receipt"]["signatory_role"] = "independent_validation"
        ),
        receipt -> (receipt["receipt"]["issued_at_utc"] = "not-a-time"),
    ]
    for mutation in signoff_mutations
        mktempdir() do directory
            bundle = build_complete_bundle(directory)
            mutate_operator_manifest!(
                bundle,
                "real_gdp",
            ) do document, manifest_directory
                mutate_receipt!(
                    document,
                    manifest_directory,
                    :signoff,
                    mutation,
                )
            end
            @test_throws EvidenceError verify_evidence(bundle.path)
        end
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_operator_manifest!(
            bundle,
            "real_gdp",
        ) do document, manifest_directory
            mutate_receipt!(
                document,
                manifest_directory,
                :signoff,
            ) do receipt
                receipt["receipt"]["receipt_id"] =
                    "validation.real_gdp.v1"
            end
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_operator_manifest!(
            bundle,
            "real_gdp",
        ) do document, manifest_directory
            mutate_receipt!(
                document,
                manifest_directory,
                :signoff,
            ) do receipt
                receipt["receipt"]["signatory_id"] =
                    "validator-real_gdp"
            end
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_operator_manifest!(
            bundle,
            "real_gdp",
        ) do document, manifest_directory
            mutate_receipt!(
                document,
                manifest_directory,
                :validation,
                receipt -> (
                    receipt["receipt"]["issued_at_utc"] =
                        "2026-08-05T12:00:00Z"
                );
                rebind_signoff = true,
            )
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        mutate_operator_manifest!(
            bundle,
            "pce_price_index",
        ) do document, manifest_directory
            mutate_receipt!(
                document,
                manifest_directory,
                :validation,
                receipt -> (
                    receipt["receipt"]["receipt_id"] =
                        "validation.real_gdp.v1"
                );
                rebind_signoff = true,
            )
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = operator_reference(bundle.root, "real_gdp")
        manifest_path =
            joinpath(bundle.directory, reference["manifest_path"])
        operator = TOML.parsefile(manifest_path)["operator"]
        open(
            joinpath(dirname(manifest_path), operator["operator_artifact_path"]),
            "a",
        ) do io
            write(io, "tamper")
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end

    mktempdir() do directory
        bundle = build_complete_bundle(directory)
        reference = operator_reference(bundle.root, "real_gdp")
        manifest_path =
            joinpath(bundle.directory, reference["manifest_path"])
        operator = TOML.parsefile(manifest_path)["operator"]
        open(
            joinpath(
                dirname(manifest_path),
                operator["validation_artifact_path"],
            ),
            "a",
        ) do io
            write(io, "tamper")
        end
        @test_throws EvidenceError verify_evidence(bundle.path)
    end
end
