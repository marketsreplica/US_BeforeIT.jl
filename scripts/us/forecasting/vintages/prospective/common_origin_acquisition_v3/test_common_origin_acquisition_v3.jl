using SHA
using Test
using TOML

const TEST_DIRECTORY = @__DIR__
const MODULE_PATH = joinpath(TEST_DIRECTORY, "USCommonOriginAcquisitionV3.jl")
const POLICY_PATH = joinpath(TEST_DIRECTORY, "common_origin_acquisition_v3_policy.toml")
const EXPECTED_MODULE_SHA256 =
    "b82c6ab5c2830b8f23ec92971ed3930790f60fd3d09e0beaf4c98a66938cdf57"
const EXPECTED_POLICY_SHA256 =
    "1cdd7834e76fb414761c41470319dfeded97f5dd5e9f0cf420893717d5f2d8ce"
const FORBIDDEN_MODULES = Set(
    ["BeforeIT", "CSV", "DataFrames", "Downloads", "HTTP", "JLD2", "JSON", "Pkg"],
)

function exact_regular_bytes(path)
    islink(path) && error("symbolic file is forbidden: $path")
    isfile(path) || error("missing regular file: $path")
    before = lstat(path)
    before.nlink == 1 || error("hard-linked file is forbidden: $path")
    bytes = read(path)
    after = lstat(path)
    (
        before.device,
        before.inode,
        before.mode,
        before.nlink,
        before.size,
        before.mtime,
        before.ctime,
    ) ==
        (
        after.device,
        after.inode,
        after.mode,
        after.nlink,
        after.size,
        after.mtime,
        after.ctime,
    ) || error("file changed during read: $path")
    return bytes
end

function loaded_module_names()
    return Set(String(nameof(value)) for value in values(Base.loaded_modules))
end

const BEFORE_INCLUDE_MODULES = loaded_module_names()
const MODULE_BYTES = exact_regular_bytes(MODULE_PATH)
const MODULE_TEXT = String(copy(MODULE_BYTES))

@testset "stdlib-only and inert-source boundary" begin
    @test bytes2hex(SHA.sha256(MODULE_BYTES)) == EXPECTED_MODULE_SHA256
    imports = [
        matched.captures[1] for matched in eachmatch(
                r"(?m)^\s*(?:using|import)\s+([A-Za-z][A-Za-z0-9_.]*)\s*$",
                MODULE_TEXT,
            )
    ]
    @test Set(imports) == Set(["Dates", "SHA", "TOML"])
    @test !occursin(r"\binclude\s*\(", MODULE_TEXT)
    @test !occursin(r"\b(?:eval|invokelatest|require)\s*\(", MODULE_TEXT)
    @test !occursin(
        r"\b(?:download|request|forecast|score|step!|filter_loglikelihood|fit!)\s*\(",
        MODULE_TEXT,
    )
    @test !occursin(r"\b(?:open|mkpath|mkdir|rm|cp|mv)\s*\(", MODULE_TEXT)
    @test !occursin(r"\b(?:CSV|DataFrames|Downloads|HTTP|JLD2|JSON|Pkg)\.", MODULE_TEXT)
end

include(MODULE_PATH)
const V3 = USCommonOriginAcquisitionV3

function expect_error(code, thunk)
    observed = nothing
    try
        thunk()
    catch error
        observed = error
    end
    @test observed isa V3.CommonOriginAcquisitionError
    observed isa V3.CommonOriginAcquisitionError && @test observed.code == code
    return observed
end

function artifact(schema, evidence_class)
    return Dict{String, Any}(
        "schema_version" => schema,
        "evidence_class" => evidence_class,
        "canonicalization" => V3.CANONICALIZATION,
        "content_sha256" => repeat("0", 64),
    )
end

function stamp!(document)
    document["artifact"]["content_sha256"] = V3.document_content_sha256(document)
    return document
end

function write_bytes(root, relative, bytes)
    path = joinpath(root, relative)
    mkpath(dirname(path))
    open(path, "w") do io
        write(io, bytes)
    end
    return bytes2hex(SHA.sha256(bytes))
end

function write_toml(root, relative, document)
    stamp!(document)
    io = IOBuffer()
    TOML.print(io, document; sorted = true)
    bytes = take!(io)
    return write_bytes(root, relative, bytes)
end

function approval_document(evidence_class, subject, role, signer, decision, signed_at)
    return Dict{String, Any}(
        "artifact" => artifact(
            "beforeit-us-profile-approval-attestation.v1",
            evidence_class,
        ),
        "attestation" => Dict{String, Any}(
            "subject_sha256" => subject,
            "role" => role,
            "signer_id" => signer,
            "decision" => decision,
            "signed_at_utc" => signed_at,
            "signature_scheme" => "EXTERNAL_SIGNATURE_REFERENCE_V1",
            "signature_value" => "fixture-signature-$signer-$subject",
        ),
    )
end

function approval_pair!(
        root,
        prefix,
        evidence_class,
        subject,
        decision;
        signed_at = "2026-08-20T13:45:00Z",
    )
    owner_id = "owner.$prefix"
    validator_id = "validator.$prefix"
    owner_path = "approvals/$prefix.owner.toml"
    validator_path = "approvals/$prefix.validator.toml"
    owner_hash = write_toml(
        root,
        owner_path,
        approval_document(
            evidence_class,
            subject,
            "MODEL_OWNER",
            owner_id,
            decision,
            signed_at,
        ),
    )
    validator_hash = write_toml(
        root,
        validator_path,
        approval_document(
            evidence_class,
            subject,
            "INDEPENDENT_VALIDATOR",
            validator_id,
            decision,
            signed_at,
        ),
    )
    return Dict{String, Any}(
        "evidence_subject_sha256" => subject,
        "owner_id" => owner_id,
        "owner_receipt_path" => owner_path,
        "owner_receipt_sha256" => owner_hash,
        "validator_id" => validator_id,
        "validator_receipt_path" => validator_path,
        "validator_receipt_sha256" => validator_hash,
    )
end

function domain_attestation(
        evidence_class,
        raw_hash,
        domain,
        backend,
        object_id,
        operator,
        attested_at,
    )
    return Dict{String, Any}(
        "artifact" => artifact(
            "beforeit-us-replica-domain-attestation.v1",
            evidence_class,
        ),
        "attestation" => Dict{String, Any}(
            "raw_sha256" => raw_hash,
            "storage_domain_id" => domain,
            "storage_backend_id" => backend,
            "object_id" => object_id,
            "custody_operator_id" => operator,
            "attested_at_utc" => attested_at,
            "signature_scheme" => "EXTERNAL_SIGNATURE_REFERENCE_V1",
            "signature_value" => "fixture-domain-signature-$object_id",
        ),
    )
end

function build_custody!(root, parent, evidence_class)
    subject = V3._custody_subject(parent)
    approvals = approval_pair!(
        root,
        "custody",
        evidence_class,
        subject,
        "APPROVED_FOR_CUSTODY_COVENANT_ONLY",
        signed_at = "2026-10-30T13:45:00Z",
    )
    document = Dict{String, Any}(
        "artifact" => artifact(V3.RETENTION_SCHEMA, evidence_class),
        "geometry" => Dict{String, Any}(
            "origin_reference_quarter" => "2026Q3",
            "maximum_horizon_quarters" => 12,
            "maximum_target_reference_quarter" => "2029Q3",
            "maximum_target_period_end_utc" => "2029-09-30T23:59:59Z",
            "mature_truth_lag_months" => 60,
            "mathematical_minimum_retain_until_utc" => "2034-09-30T23:59:59Z",
        ),
        "covenant" => Dict{String, Any}(
            "custody_policy_id" => "beforeit-us-retention-custody-v2.2026q3",
            "covered_subject_sha256" => subject,
            "minimum_durable_replica_count" => 2,
            "retain_origin_evidence_until_utc" => "2034-09-30T23:59:59Z",
            "mature_truth_receipt_preseal_state" => "FUTURE_NOT_LOADED_EXPECTED",
            "later_mature_receipt_completion_required" => true,
            "later_mature_receipt_external_timestamp_required" => true,
            "later_mature_receipt_durable_replication_required" => true,
            "post_receipt_independent_audit_required" => true,
            "deletion_release_rule" => V3.DELETION_RELEASE_RULE,
        ),
        "approvals" => approvals,
        "gates" => Dict{String, Any}(
            "truth_access_allowed" => false,
            "scoring_allowed" => false,
            "origin_admission_allowed" => false,
            "deletion_allowed_pre_maturity" => false,
        ),
    )
    path = "custody/retention_custody_v2.toml"
    return path, write_toml(root, path, document)
end

function capture_times(expected)
    if expected["completion_date"] == "2026-10-30"
        return (
            "2026-10-30T13:00:00Z",
            "2026-10-30T13:30:00Z",
            "2026-10-30T13:40:00Z",
        )
    elseif expected["completion_date"] == "2026-10-29"
        return (
            "2026-10-29T18:30:00Z",
            "2026-10-29T18:40:00Z",
            "2026-10-29T18:45:00Z",
        )
    end
    return (
        "2026-08-20T13:00:00Z",
        "2026-08-20T13:30:00Z",
        "2026-08-20T13:40:00Z",
    )
end

function build_leaf!(
        root,
        index,
        expected,
        dispatch,
        evidence_class,
    )
    tag = lpad(string(index), 3, '0') * "-" * expected["legacy_profile_id"]
    malicious = expected["legacy_profile_id"] == "beforeit_bea71_model_bridge"
    raw_path = malicious ? "raw/$tag.candidate.jl" : "raw/$tag.payload"
    raw_bytes = malicious ?
        Vector{UInt8}(codeunits("error(\"candidate verifier source executed\")\n")) :
        Vector{UInt8}(codeunits("fixture payload $tag\n"))
    raw_hash = write_bytes(root, raw_path, raw_bytes)
    raw_id = "raw.$tag"
    media_type = malicious ? "text/plain" : dispatch["permitted_media_types"][1]
    raw = Dict{String, Any}(
        "artifact_id" => raw_id,
        "path" => raw_path,
        "sha256" => raw_hash,
        "byte_count" => length(raw_bytes),
        "media_type" => media_type,
        "artifact_role" => "SOURCE_PAYLOAD",
    )
    replicas = Dict{String, Any}[]
    started_at, completed_at, issued_at = capture_times(expected)
    reference_period_end = min(completed_at[1:10], "2026-10-29")
    for replica_index in 1:2
        replica_path = "replicas/domain$replica_index/$tag.payload"
        replica_hash = write_bytes(root, replica_path, raw_bytes)
        domain = "domain.$replica_index.$tag"
        backend = "backend.$replica_index.$tag"
        object_id = "object.$replica_index.$tag"
        attestation_path = "replica-attestations/$tag.$replica_index.toml"
        attestation_hash = write_toml(
            root,
            attestation_path,
            domain_attestation(
                evidence_class,
                raw_hash,
                domain,
                backend,
                object_id,
                "operator.$replica_index.$tag",
                issued_at,
            ),
        )
        push!(
            replicas,
            Dict{String, Any}(
                "replica_id" => "replica.$replica_index.$tag",
                "raw_artifact_id" => raw_id,
                "path" => replica_path,
                "sha256" => replica_hash,
                "byte_count" => length(raw_bytes),
                "storage_domain_id" => domain,
                "storage_backend_id" => backend,
                "object_id" => object_id,
                "domain_attestation_path" => attestation_path,
                "domain_attestation_sha256" => attestation_hash,
            ),
        )
    end
    binding = Dict{String, Any}(
        "dispatch_id" => expected["dispatch_id"],
        "requirement_id" => expected["legacy_requirement_id"],
        "source_id" => expected["source_id"],
        "evidence_role" => dispatch["evidence_role"],
        "legacy_profile_id" => expected["legacy_profile_id"],
        "active_profile_id" => expected["active_profile_id"],
        "legacy_selector" => expected["legacy_selector"],
        "legacy_selector_sha256" => expected["legacy_selector_sha256"],
        "active_selector" => expected["active_selector"],
        "active_selector_sha256" => expected["active_selector_sha256"],
        "legacy_v2_module_sha256" => V3.LEGACY_V2_MODULE_SHA256,
        "legacy_v2_contract_sha256" => V3.LEGACY_V2_CONTRACT_SHA256,
        "legacy_v2_semantic_sha256" => V3.LEGACY_V2_SEMANTIC_SHA256,
    )
    selector_binding = Dict{String, Any}(
        key => binding[key] for key in [
                "requirement_id",
                "source_id",
                "active_profile_id",
                "active_selector",
                "active_selector_sha256",
            ]
    )
    catalog_path = "selectors/$tag.catalog.toml"
    catalog = Dict{String, Any}(
        "artifact" => artifact("beforeit-us-selector-candidate-catalog.v1", evidence_class),
        "receipt_completed_at_utc" => completed_at,
        "binding" => selector_binding,
        "selection" => Dict{String, Any}(
            "eligible_candidate_count" => 1,
            "selected_candidate_rank" => 1,
            "selected_candidate_id" => "candidate.$tag",
        ),
        "candidates" => [
            Dict{String, Any}(
                "candidate_id" => "candidate.$tag",
                "official_locator" => "https://example.invalid/$tag",
                "media_type" => media_type,
                "artifact_role" => "SOURCE_PAYLOAD",
                "eligible" => true,
                "rank" => 1,
                "raw_artifact_id" => raw_id,
                "raw_sha256" => raw_hash,
            ),
        ],
    )
    catalog_hash = write_toml(root, catalog_path, catalog)
    resolution_path = "selectors/$tag.resolution.toml"
    resolution = Dict{String, Any}(
        "artifact" => artifact("beforeit-us-selector-resolution.v1", evidence_class),
        "receipt_completed_at_utc" => completed_at,
        "binding" => selector_binding,
        "resolution" => Dict{String, Any}(
            "candidate_catalog_sha256" => catalog_hash,
            "selected_candidate_id" => "candidate.$tag",
            "selected_candidate_rank" => 1,
            "selected_raw_artifact_id" => raw_id,
            "selected_raw_sha256" => raw_hash,
            "reference_period_start" => "2000-01-01",
            "reference_period_end" => reference_period_end,
            "resolved_dimensions_complete" => true,
            "set_resolution_complete" => true,
        ),
    )
    resolution_hash = write_toml(root, resolution_path, resolution)
    release_id = "release.$tag"
    release_notice_path = "releases/$tag.toml"
    release_notice = Dict{String, Any}(
        "artifact" => artifact("beforeit-us-release-notice-evidence.v1", evidence_class),
        "binding" => Dict{String, Any}(
            "source_id" => expected["source_id"],
            "release_id" => release_id,
            "official_locator" => "https://example.invalid/$tag",
            "official_release_timestamp_utc" => "UNKNOWN_NOT_ASSERTED",
            "raw_artifact_ids" => [raw_id],
            "raw_artifact_hashes" => [raw_hash],
        ),
    )
    release_notice_hash = write_toml(root, release_notice_path, release_notice)
    receipt = Dict{String, Any}(
        "artifact" => artifact(V3.LEAF_SCHEMA, evidence_class),
        "binding" => binding,
        "selector" => Dict{String, Any}(
            "candidate_catalog_path" => catalog_path,
            "candidate_catalog_sha256" => catalog_hash,
            "resolution_path" => resolution_path,
            "resolution_sha256" => resolution_hash,
            "eligible_candidate_count" => 1,
            "selected_candidate_rank" => 1,
            "set_resolution_complete" => true,
        ),
        "capture" => Dict{String, Any}(
            "capture_id" => expected["capture_id"],
            "capture_started_at_utc" => started_at,
            "receipt_completed_at_utc" => completed_at,
            "availability_upper_bound_utc" => completed_at,
            "reference_period_start" => "2000-01-01",
            "reference_period_end" => reference_period_end,
        ),
        "release" => Dict{String, Any}(
            "release_id" => release_id,
            "official_locator" => "https://example.invalid/$tag",
            "official_release_timestamp_utc" => "UNKNOWN_NOT_ASSERTED",
            "release_notice_path" => release_notice_path,
            "release_notice_sha256" => release_notice_hash,
        ),
        "raw_artifacts" => [raw],
        "replicas" => replicas,
        "leaf_verification" => Dict{String, Any}(
            "verifier_id" => dispatch["leaf_verifier_id"],
            "verifier_version" => dispatch["leaf_verifier_version"],
            "verifier_source_path" => dispatch["leaf_verifier_source_path"],
            "verifier_source_sha256" => dispatch["leaf_verifier_source_sha256"],
            "verifier_test_path" => dispatch["leaf_verifier_test_path"],
            "verifier_test_sha256" => dispatch["leaf_verifier_test_sha256"],
            "verifier_qualified" => false,
            "result" => "NOT_QUALIFIED_FAIL_CLOSED",
            "result_receipt_path" => "NOT_APPLICABLE",
            "result_receipt_sha256" => "UNAVAILABLE",
            "independent_validation_receipt_schema_version" =>
                dispatch["independent_validation_receipt_schema_version"],
            "independent_validation_receipt_path" => "NOT_APPLICABLE",
            "independent_validation_receipt_sha256" => "UNAVAILABLE",
        ),
        "approvals" => Dict{String, Any}(),
        "external_timestamp" => Dict{String, Any}(),
        "retention" => Dict{String, Any}(
            "custody_policy_id" => "beforeit-us-retention-custody-v2.2026q3",
            "custody_schema_version" => V3.RETENTION_SCHEMA,
            "minimum_retain_until_utc" => V3.MINIMUM_RETAIN_UNTIL,
        ),
        "gates" => Dict{String, Any}(key => false for key in V3.GATE_KEYS),
    )
    subject = V3._receipt_subject(receipt)
    receipt["approvals"] = approval_pair!(
        root,
        "leaf-$tag",
        evidence_class,
        subject,
        "APPROVED_FOR_ORIGIN_INFORMATION_PROFILE_ONLY";
        signed_at = issued_at,
    )
    token_path = "timestamps/$tag.token"
    token_hash = write_bytes(root, token_path, Vector{UInt8}(codeunits("timestamp token $tag")))
    timestamp_path = "timestamps/$tag.toml"
    timestamp = Dict{String, Any}(
        "artifact" => artifact(
            "beforeit-us-external-timestamp-attestation.v1",
            evidence_class,
        ),
        "attestation" => Dict{String, Any}(
            "subject_sha256" => subject,
            "authority_id" => "external.timestamp.authority.$tag",
            "issued_at_utc" => issued_at,
            "token_path" => token_path,
            "token_sha256" => token_hash,
            "token_media_type" => "application/timestamp-reply",
        ),
    )
    timestamp_hash = write_toml(root, timestamp_path, timestamp)
    receipt["external_timestamp"] = Dict{String, Any}(
        "evidence_subject_sha256" => subject,
        "receipt_path" => timestamp_path,
        "receipt_sha256" => timestamp_hash,
    )
    receipt_path = "receipts/$tag.toml"
    receipt_hash = write_toml(root, receipt_path, receipt)
    return receipt_path, receipt_hash
end

function parent_skeleton(context, evidence_class)
    rows = Dict{String, Any}[]
    for (index, expected) in enumerate(V3._expected_rows(context))
        tag = lpad(string(index), 3, '0') * "-" * expected["legacy_profile_id"]
        push!(
            rows,
            Dict{String, Any}(
                "legacy_requirement_id" => expected["legacy_requirement_id"],
                "legacy_profile_id" => expected["legacy_profile_id"],
                "active_profile_id" => expected["active_profile_id"],
                "dispatch_id" => expected["dispatch_id"],
                "receipt_path" => "receipts/$tag.toml",
                "receipt_sha256" => repeat("0", 64),
                "supersession_decision_sha256" =>
                    expected["supersession_required"] ?
                    "UNAVAILABLE_NOT_FROZEN" : "NOT_APPLICABLE",
            ),
        )
    end
    return Dict{String, Any}(
        "artifact" => artifact(V3.PARENT_SCHEMA, evidence_class),
        "origin" => Dict{String, Any}(
            "origin_id" => V3.ORIGIN_ID,
            "reference_quarter" => V3.ORIGIN_QUARTER,
            "origin_timestamp_utc" => V3.ORIGIN_TIMESTAMP,
            "origin_rule" => V3.ORIGIN_RULE,
        ),
        "baseline" => Dict{String, Any}(
            "policy_path" => V3.POLICY_RELATIVE_PATH,
            "policy_physical_sha256" => V3.POLICY_PHYSICAL_SHA256,
            "legacy_v2_module_sha256" => V3.LEGACY_V2_MODULE_SHA256,
            "legacy_v2_contract_sha256" => V3.LEGACY_V2_CONTRACT_SHA256,
            "legacy_v2_semantic_sha256" => V3.LEGACY_V2_SEMANTIC_SHA256,
            "legacy_profile_count" => 107,
            "legacy_requirement_count" => 21,
            "opaque_audit_tuple_sha256" => V3.OPAQUE_AUDIT_TUPLE_SHA256,
            "typed_length_tuple_sha256" => V3.TYPED_LENGTH_TUPLE_SHA256,
        ),
        "custody" => Dict{String, Any}(
            "receipt_path" => "custody/retention_custody_v2.toml",
            "receipt_sha256" => repeat("0", 64),
        ),
        "approvals" => Dict{String, Any}(),
        "gates" => Dict{String, Any}(key => false for key in V3.GATE_KEYS),
        "rows" => rows,
    )
end

function build_fixture!(root; evidence_class = "PROSPECTIVE_NONSYNTHETIC")
    context = V3._load_policy_context()
    parent = parent_skeleton(context, evidence_class)
    expected_rows = V3._expected_rows(context)
    for index in eachindex(expected_rows)
        expected = expected_rows[index]
        dispatch = context.dispatches[expected["dispatch_id"]]
        path, digest = build_leaf!(
            root,
            index,
            expected,
            dispatch,
            evidence_class,
        )
        parent["rows"][index]["receipt_path"] = path
        parent["rows"][index]["receipt_sha256"] = digest
    end
    custody_path, custody_hash = build_custody!(root, parent, evidence_class)
    parent["custody"]["receipt_path"] = custody_path
    parent["custody"]["receipt_sha256"] = custody_hash
    subject = V3._parent_material_subject(parent)
    parent["approvals"] = approval_pair!(
        root,
        "parent",
        evidence_class,
        subject,
        "APPROVED_FOR_ORIGIN_INFORMATION_SET_ONLY";
        signed_at = "2026-10-30T13:50:00Z",
    )
    parent_path = "parent/common_origin_acquisition_parent_v3.toml"
    write_toml(root, parent_path, parent)
    return parent_path, context
end

function read_toml(root, relative)
    return TOML.parse(String(read(joinpath(root, relative))))
end

function rewrite_parent_approvals!(
        root,
        parent,
        evidence_class;
        signed_at = "2026-10-30T13:50:00Z",
    )
    subject = V3._parent_material_subject(parent)
    parent["approvals"] = approval_pair!(
        root,
        "parent",
        evidence_class,
        subject,
        "APPROVED_FOR_ORIGIN_INFORMATION_SET_ONLY";
        signed_at = signed_at,
    )
    return parent
end

function rebind_leaf_subject!(root, receipt)
    subject = V3._receipt_subject(receipt)
    receipt["approvals"]["evidence_subject_sha256"] = subject
    for role in ["owner", "validator"]
        path = receipt["approvals"]["$(role)_receipt_path"]
        document = read_toml(root, path)
        document["attestation"]["subject_sha256"] = subject
        receipt["approvals"]["$(role)_receipt_sha256"] = write_toml(root, path, document)
    end
    receipt["external_timestamp"]["evidence_subject_sha256"] = subject
    timestamp_path = receipt["external_timestamp"]["receipt_path"]
    timestamp = read_toml(root, timestamp_path)
    timestamp["attestation"]["subject_sha256"] = subject
    receipt["external_timestamp"]["receipt_sha256"] =
        write_toml(root, timestamp_path, timestamp)
    return receipt
end

function mutate_leaf_and_parent!(root, parent_path, index, mutator)
    parent = read_toml(root, parent_path)
    receipt_path = parent["rows"][index]["receipt_path"]
    receipt = read_toml(root, receipt_path)
    mutator(receipt)
    receipt_hash = write_toml(root, receipt_path, receipt)
    parent["rows"][index]["receipt_sha256"] = receipt_hash
    rewrite_parent_approvals!(root, parent, parent["artifact"]["evidence_class"])
    write_toml(root, parent_path, parent)
    return nothing
end

mutate_leaf_and_parent!(mutator::Function, root, parent_path, index) =
    mutate_leaf_and_parent!(root, parent_path, index, mutator)

function with_restored_files(root, paths, thunk)
    saved = Dict(path => read(joinpath(root, path)) for path in paths)
    try
        return thunk()
    finally
        for (path, bytes) in saved
            write_bytes(root, path, bytes)
        end
    end
end


with_restored_files(thunk::Function, root, paths) =
    with_restored_files(root, paths, thunk)

@testset "post-include boundary and immutable closed policy" begin
    after = loaded_module_names()
    @test isempty(intersect(setdiff(after, BEFORE_INCLUDE_MODULES), FORBIDDEN_MODULES))
    @test Set(names(V3; all = false)) == Set(
        [
            :CommonOriginAcquisitionError,
            :USCommonOriginAcquisitionV3,
            :canonical_sha256,
            :load_parent,
            :load_policy,
            :validate_result,
            :verify_parent,
        ],
    )
    @test bytes2hex(SHA.sha256(exact_regular_bytes(POLICY_PATH))) == EXPECTED_POLICY_SHA256
    policy = V3.load_policy()
    @test policy["artifact"]["status"] == "CANNOT_RUN"
    @test policy["artifact"]["content_sha256"] == V3.POLICY_CONTENT_SHA256
    @test length(policy["dispatch"]) == 21
    @test sum(length(item["allowed_profile_ids"]) for item in policy["dispatch"]) == 107
    @test all(item -> item["qualified"] === false, policy["dispatch"])
    @test length(
        Set(
            (
                    item["receipt_schema_version"],
                    item["requirement_id"],
                    item["source_id"],
                    item["evidence_role"],
                ) for item in policy["dispatch"]
        )
    ) == 21
    @test policy["legacy_baseline"]["opaque_audit_tuple_sha256"] ==
        V3.OPAQUE_AUDIT_TUPLE_SHA256
    @test policy["legacy_baseline"]["opaque_audit_tuple_serialization"] ==
        "UNRECOVERABLE_NOT_REDERIVED"
    @test policy["legacy_baseline"]["typed_length_tuple_sha256"] ==
        V3.TYPED_LENGTH_TUPLE_SHA256
    context = V3._load_policy_context()
    @test V3.canonical_sha256(V3._tuple_projection(context.legacy_rows)) ==
        V3.TYPED_LENGTH_TUPLE_SHA256

    restamped = deepcopy(policy)
    restamped["contract"]["current_expected_status"] =
        "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    stamp!(restamped)
    expect_error(:policy_content_hash_mismatch, () -> V3._validate_policy(restamped))

    unknown = deepcopy(policy)
    unknown["dispatch"][1]["receipt_schema_version"] = "unknown.receipt.v99"
    stamp!(unknown)
    expect_error(:policy_content_hash_mismatch, () -> V3._validate_policy(unknown))
end

@testset "EFFR semantic overlay stays fail-closed" begin
    policy = V3.load_policy()
    effr = policy["effr_supersession"]
    @test effr["status"] ==
        "ENDPOINT_PROFILE_PINNED_CANNOT_RUN_SUPERSESSION_UNFROZEN"
    @test effr["accepted_endpoint_profile_sha256"] ==
        "7de8e23e11d202a887e20d6e90616501562c9c3682db1200c753bb207ae4451b"
    @test effr["accepted_endpoint_profile_content_sha256"] ==
        "4ed9a0f99c6c8490da35c290ce87c6051a6a1bf08da5eb2ee8ac601f75a4eaa5"
    @test effr["restart_first_observation_count"] == 58
    @test effr["restart_later_observation_count"] == 57
    @test effr["restart_total_slot_count"] == 115
    @test effr["restart_complete_pair_count"] == 57
    @test effr["predecessor_august_7_revision_may_be_borrowed"] === false
    @test effr["candidate_84_date_history_satisfies_training_history"] === false
    @test effr["daily_history_start_justification_required"] === true
    @test effr["minimum_common_information_training_quarters"] == 60
    @test effr["core3_training_geometry_start"] == "2000Q3"
    @test effr["methodology_regime_boundary"] == "2016-03-01"
    @test effr["regime_treatment_approval_required"] === true
    @test all(
        effr[key] === false for key in [
                "first_public_claim_allowed",
                "current_state_claim_allowed",
                "final_daily_state_claim_allowed",
                "no_later_revision_claim_allowed",
            ]
    )
    @test Set(row["legacy_profile_id"] for row in effr["rows"]) ==
        Set(["effr_daily_history", "effr_first_state_manifest", "effr_revision_manifest"])
    @test all(row -> row["decision_status"] == "REQUIRED_NOT_FROZEN", effr["rows"])
end

@testset "full 21/107 metadata composition and unrelated cwd" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        result = V3.verify_parent(parent_path; evidence_root = root)
        @test V3.validate_result(result; evidence_root = root) === result
        @test result["verification"]["status"] == "CANNOT_RUN"
        @test result["verification"]["claim_ceiling"] == "CANNOT_RUN"
        @test result["verification"]["maximum_status"] ==
            "CANNOT_RUN"
        @test result["verification"]["successor_only_status"] ==
            "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
        @test result["verification"]["current_policy_ready_status_reachable"] === false
        @test result["verification"]["authenticated_trust_anchor_count"] == 0
        @test result["verification"]["same_user_path_race_resistance_attested"] === false
        @test result["verification"]["evidence_class"] == "PROSPECTIVE_NONSYNTHETIC"
        @test result["verification"]["legacy_requirement_count"] == 21
        @test result["verification"]["legacy_profile_count"] == 107
        @test result["verification"]["qualified_dispatch_count"] == 0
        @test result["verification"]["qualified_profile_count"] == 0
        @test length(result["profile_results"]) == 107
        @test all(item -> item["qualified"] === false, result["profile_results"])
        @test all(item -> item["raw_artifact_count"] == 1, result["profile_results"])
        @test all(item -> item["replica_count"] == 2, result["profile_results"])
        @test result["verification"]["blocking_reason_count"] == 49
        @test result["verification"]["limitation_count"] == 5
        @test any(
            item -> item["blocker_id"] == "effr_semantic_supersession_overlay_unfrozen",
            result["blocking_reasons"],
        )
        @test all(value -> value === false, values(result["scientific_gates"]))
        @test all(iszero, values(result["action_counts"]))
        @test result["verification"]["action_count_scope"] ==
            "COMMON_ORIGIN_ACQUISITION_V3_VERIFIER_INVOCATION_ONLY"
        @test any(
            item -> item["blocker_id"] == "current_v3_authenticated_trust_roots_absent",
            result["blocking_reasons"],
        )
        @test result["verification"]["origin_information_set_sha256"] ==
            bytes2hex(SHA.sha256(read(joinpath(root, parent_path))))
        @test length(V3.load_parent(parent_path; evidence_root = root)["rows"]) == 107
        parent = read_toml(root, parent_path)
        inert_index = findfirst(
            row -> row["legacy_profile_id"] == "beforeit_bea71_model_bridge",
            parent["rows"],
        )
        inert_receipt = read_toml(root, parent["rows"][inert_index]["receipt_path"])
        inert_path = inert_receipt["raw_artifacts"][1]["path"]
        @test endswith(inert_path, ".candidate.jl")
        @test occursin(
            "candidate verifier source executed",
            String(read(joinpath(root, inert_path))),
        )

        unrelated = mktempdir()
        cd(unrelated) do
            @test length(V3.load_policy()["dispatch"]) == 21
            repeated = V3.verify_parent(parent_path; evidence_root = root)
            @test repeated["artifact"]["content_sha256"] ==
                result["artifact"]["content_sha256"]
        end
    end
end

@testset "parent bijection, order, narrowing, and path rejection" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        original = read_toml(root, parent_path)
        cases = [
            (
                "missing.toml",
                parent -> pop!(parent["rows"]),
                :parent_bijection,
            ),
            (
                "extra.toml",
                parent -> push!(parent["rows"], deepcopy(parent["rows"][end])),
                :parent_bijection,
            ),
            (
                "duplicate.toml",
                parent -> (parent["rows"][2] = deepcopy(parent["rows"][1])),
                :parent_order_or_binding,
            ),
            (
                "reordered.toml",
                parent -> reverse!(parent["rows"]),
                :parent_order_or_binding,
            ),
            (
                "narrowed.toml",
                parent -> (parent["rows"][1]["active_profile_id"] = "narrowed_profile"),
                :parent_order_or_binding,
            ),
            (
                "wrong-dispatch.toml",
                parent -> (parent["rows"][1]["dispatch_id"] = parent["rows"][9]["dispatch_id"]),
                :parent_order_or_binding,
            ),
            (
                "traversal.toml",
                parent -> (parent["rows"][1]["receipt_path"] = "../outside.toml"),
                :unsafe_path,
            ),
            (
                "extra-field.toml",
                parent -> (parent["rows"][1]["unknown"] = "forbidden"),
                :invalid_schema,
            ),
            (
                "arbitrary-effr-supersession.toml",
                parent -> begin
                    index = findfirst(
                        row -> row["legacy_profile_id"] == "effr_daily_history",
                        parent["rows"],
                    )
                    parent["rows"][index]["supersession_decision_sha256"] = repeat("a", 64)
                end,
                :effr_supersession_unavailable,
            ),
        ]
        for (name, mutate!, code) in cases
            document = deepcopy(original)
            mutate!(document)
            relative = "parent/mutation-$name"
            write_toml(root, relative, document)
            expect_error(code, () -> V3.verify_parent(relative; evidence_root = root))
        end
    end
end

@testset "receipt source, selector, capture, type, and timing attacks" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        parent = read_toml(root, parent_path)
        receipt_path = parent["rows"][1]["receipt_path"]
        restore_paths = [
            parent_path,
            receipt_path,
            parent["approvals"]["owner_receipt_path"],
            parent["approvals"]["validator_receipt_path"],
        ]
        cases = [
            (
                :leaf_binding_mismatch,
                receipt -> (receipt["binding"]["source_id"] = "wrong_source"),
            ),
            (
                :leaf_binding_mismatch,
                receipt -> (receipt["binding"]["active_selector"] *= ":narrowed=true"),
            ),
            (
                :binding_mismatch,
                receipt -> (receipt["capture"]["capture_id"] = "wrong_capture"),
            ),
            (
                :post_origin_evidence,
                receipt -> begin
                    receipt["capture"]["receipt_completed_at_utc"] =
                        "2026-10-30T14:00:00Z"
                    receipt["capture"]["availability_upper_bound_utc"] =
                        "2026-10-30T14:00:00Z"
                end,
            ),
            (
                :binding_mismatch,
                receipt ->
                (receipt["artifact"]["schema_version"] = "unknown.receipt.v99"),
            ),
            (
                :invalid_schema,
                receipt -> (receipt["unknown_root_member"] = true),
            ),
        ]
        for (code, mutate!) in cases
            with_restored_files(root, restore_paths) do
                mutate_leaf_and_parent!(root, parent_path, 1, mutate!)
                expect_error(code, () -> V3.verify_parent(parent_path; evidence_root = root))
            end
        end
    end
end

@testset "approval, timestamp, selector-catalog, receipt-restamp, and replica attacks" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        parent = read_toml(root, parent_path)
        receipt_path = parent["rows"][1]["receipt_path"]
        receipt = read_toml(root, receipt_path)
        base_restore = [
            parent_path,
            receipt_path,
            parent["approvals"]["owner_receipt_path"],
            parent["approvals"]["validator_receipt_path"],
        ]

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                document["approvals"]["validator_id"] = document["approvals"]["owner_id"]
            end
            expect_error(
                :approval_independence,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        timestamp_path = receipt["external_timestamp"]["receipt_path"]
        replica_attestation_path = receipt["replicas"][2]["domain_attestation_path"]
        with_restored_files(root, vcat(base_restore, [timestamp_path])) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                timestamp = read_toml(root, timestamp_path)
                timestamp["attestation"]["subject_sha256"] = repeat("f", 64)
                document["external_timestamp"]["receipt_sha256"] =
                    write_toml(root, timestamp_path, timestamp)
            end
            expect_error(
                :binding_mismatch,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        catalog_path = receipt["selector"]["candidate_catalog_path"]
        with_restored_files(root, vcat(base_restore, [catalog_path])) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                catalog = read_toml(root, catalog_path)
                catalog["selection"]["eligible_candidate_count"] = 0
                document["selector"]["candidate_catalog_sha256"] =
                    write_toml(root, catalog_path, catalog)
            end
            expect_error(
                :binding_mismatch,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        release_notice_path = receipt["release"]["release_notice_path"]
        with_restored_files(root, vcat(base_restore, [release_notice_path])) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                new_locator = "https://restamped.invalid/release"
                notice = read_toml(root, release_notice_path)
                notice["binding"]["official_locator"] = new_locator
                document["release"]["official_locator"] = new_locator
                document["release"]["release_notice_sha256"] =
                    write_toml(root, release_notice_path, notice)
            end
            expect_error(
                :release_binding,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        attestation_path = receipt["replicas"][2]["domain_attestation_path"]
        with_restored_files(root, vcat(base_restore, [attestation_path])) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                first_domain = document["replicas"][1]["storage_domain_id"]
                attestation = read_toml(root, attestation_path)
                attestation["attestation"]["storage_domain_id"] = first_domain
                document["replicas"][2]["storage_domain_id"] = first_domain
                document["replicas"][2]["domain_attestation_sha256"] =
                    write_toml(root, attestation_path, attestation)
            end
            expect_error(
                :replica_independence,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end


        raw_path = receipt["raw_artifacts"][1]["path"]
        with_restored_files(root, vcat(base_restore, [raw_path])) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                replacement = Vector{UInt8}(codeunits("coordinated raw restamp attempt\n"))
                replacement_hash = write_bytes(root, raw_path, replacement)
                document["raw_artifacts"][1]["sha256"] = replacement_hash
                document["raw_artifacts"][1]["byte_count"] = length(replacement)
            end
            expect_error(
                :replica_independence,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end
    end
end

@testset "typed numeric controls and complete child-evidence chronology" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        parent = read_toml(root, parent_path)
        receipt_path = parent["rows"][1]["receipt_path"]
        receipt = read_toml(root, receipt_path)
        catalog_path = receipt["selector"]["candidate_catalog_path"]
        resolution_path = receipt["selector"]["resolution_path"]
        timestamp_path = receipt["external_timestamp"]["receipt_path"]
        replica_attestation_path = receipt["replicas"][2]["domain_attestation_path"]
        custody_path = parent["custody"]["receipt_path"]
        custody = read_toml(root, custody_path)
        base_restore = [
            parent_path,
            receipt_path,
            catalog_path,
            resolution_path,
            timestamp_path,
            replica_attestation_path,
            custody_path,
            parent["approvals"]["owner_receipt_path"],
            parent["approvals"]["validator_receipt_path"],
            receipt["approvals"]["owner_receipt_path"],
            receipt["approvals"]["validator_receipt_path"],
            custody["approvals"]["owner_receipt_path"],
            custody["approvals"]["validator_receipt_path"],
        ]

        for invalid_value in (true, 1.0)
            with_restored_files(root, base_restore) do
                mutate_leaf_and_parent!(root, parent_path, 1) do document
                    document["selector"]["eligible_candidate_count"] = invalid_value
                end
                expect_error(
                    :invalid_schema,
                    () -> V3.verify_parent(parent_path; evidence_root = root),
                )
            end

            with_restored_files(root, base_restore) do
                document = read_toml(root, parent_path)
                document["baseline"]["legacy_profile_count"] = invalid_value
                write_toml(root, "parent/invalid-baseline-$(repr(invalid_value)).toml", document)
                expect_error(
                    :invalid_schema,
                    () -> V3.verify_parent(
                        "parent/invalid-baseline-$(repr(invalid_value)).toml";
                        evidence_root = root,
                    ),
                )
            end
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                document["capture"]["reference_period_end"] = "2026-08-21"
            end
            expect_error(
                :capture_timing,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                catalog_document = read_toml(root, catalog_path)
                catalog_document["selection"]["selected_candidate_rank"] = true
                catalog_hash = write_toml(root, catalog_path, catalog_document)
                document["selector"]["candidate_catalog_sha256"] = catalog_hash
            end
            expect_error(
                :invalid_schema,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                resolution_document = read_toml(root, resolution_path)
                resolution_document["resolution"]["selected_candidate_rank"] = 1.0
                document["selector"]["resolution_sha256"] =
                    write_toml(root, resolution_path, resolution_document)
            end
            expect_error(
                :invalid_schema,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                catalog_document = read_toml(root, catalog_path)
                resolution_document = read_toml(root, resolution_path)
                catalog_document["receipt_completed_at_utc"] = "2026-08-20T13:41:00Z"
                resolution_document["receipt_completed_at_utc"] = "2026-08-20T13:41:00Z"
                catalog_hash = write_toml(root, catalog_path, catalog_document)
                document["selector"]["candidate_catalog_sha256"] = catalog_hash
                resolution_document["resolution"]["candidate_catalog_sha256"] = catalog_hash
                document["selector"]["resolution_sha256"] =
                    write_toml(root, resolution_path, resolution_document)
                rebind_leaf_subject!(root, document)
            end
            expect_error(
                :timestamp_binding,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                attestation = read_toml(root, replica_attestation_path)
                attestation["attestation"]["attested_at_utc"] = "2026-08-20T13:41:00Z"
                document["replicas"][2]["domain_attestation_sha256"] =
                    write_toml(root, replica_attestation_path, attestation)
                rebind_leaf_subject!(root, document)
            end
            expect_error(
                :timestamp_binding,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            document = read_toml(root, parent_path)
            custody_document = read_toml(root, custody_path)
            custody_document["geometry"]["maximum_horizon_quarters"] = true
            document["custody"]["receipt_sha256"] =
                write_toml(root, custody_path, custody_document)
            rewrite_parent_approvals!(root, document, document["artifact"]["evidence_class"])
            write_toml(root, parent_path, document)
            expect_error(
                :invalid_schema,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                catalog_document = read_toml(root, catalog_path)
                catalog_document["receipt_completed_at_utc"] = "2026-08-20T13:29:59Z"
                document["selector"]["candidate_catalog_sha256"] =
                    write_toml(root, catalog_path, catalog_document)
            end
            expect_error(
                :selector_closure,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                resolution_document = read_toml(root, resolution_path)
                resolution_document["receipt_completed_at_utc"] = "2026-08-20T13:29:59Z"
                document["selector"]["resolution_sha256"] =
                    write_toml(root, resolution_path, resolution_document)
            end
            expect_error(
                :selector_closure,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        for issued_at in ["2026-08-20T13:39:59Z", "2026-10-30T14:00:00Z"]
            with_restored_files(root, base_restore) do
                mutate_leaf_and_parent!(root, parent_path, 1) do document
                    timestamp_document = read_toml(root, timestamp_path)
                    timestamp_document["attestation"]["issued_at_utc"] = issued_at
                    document["external_timestamp"]["receipt_sha256"] =
                        write_toml(root, timestamp_path, timestamp_document)
                end
                expected_code = issued_at < "2026-10-30T14:00:00Z" ?
                    :timestamp_binding : :post_origin_evidence
                expect_error(
                    expected_code,
                    () -> V3.verify_parent(parent_path; evidence_root = root),
                )
            end
        end

        with_restored_files(root, base_restore) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                for role in ["owner", "validator"]
                    path = document["approvals"]["$(role)_receipt_path"]
                    approval = read_toml(root, path)
                    approval["attestation"]["signed_at_utc"] = "2026-08-20T13:39:59Z"
                    document["approvals"]["$(role)_receipt_sha256"] =
                        write_toml(root, path, approval)
                end
            end
            expect_error(
                :approval_attestation,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        for signed_at in ["2026-10-30T13:39:59Z", "2026-10-30T14:00:00Z"]
            with_restored_files(root, base_restore) do
                document = read_toml(root, parent_path)
                rewrite_parent_approvals!(
                    root,
                    document,
                    document["artifact"]["evidence_class"];
                    signed_at = signed_at,
                )
                write_toml(root, parent_path, document)
                expected_code = signed_at < "2026-10-30T14:00:00Z" ?
                    :approval_attestation : :post_origin_evidence
                expect_error(
                    expected_code,
                    () -> V3.verify_parent(parent_path; evidence_root = root),
                )
            end
        end

        with_restored_files(root, base_restore) do
            document = read_toml(root, parent_path)
            custody_document = read_toml(root, custody_path)
            custody_document["approvals"] = approval_pair!(
                root,
                "custody",
                custody_document["artifact"]["evidence_class"],
                custody_document["covenant"]["covered_subject_sha256"],
                "APPROVED_FOR_CUSTODY_COVENANT_ONLY";
                signed_at = "2026-10-30T13:39:59Z",
            )
            document["custody"]["receipt_sha256"] =
                write_toml(root, custody_path, custody_document)
            rewrite_parent_approvals!(root, document, document["artifact"]["evidence_class"])
            write_toml(root, parent_path, document)
            expect_error(
                :approval_attestation,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end
    end
end

@testset "links, hardlinks, traversal, physical restamps, and race states" begin
    mktempdir() do root
        root = realpath(root)
        digest = write_bytes(root, "plain/source.bin", UInt8[0x01, 0x02, 0x03])
        @test V3._safe_read(root, "plain/source.bin"; expected_hash = digest)[2] == digest
        symlink("source.bin", joinpath(root, "plain", "symbolic.bin"))
        expect_error(
            :unsafe_path,
            () -> V3._safe_read(root, "plain/symbolic.bin"; expected_hash = digest),
        )
        mkpath(joinpath(root, "linked-target"))
        write_bytes(root, "linked-target/value.bin", UInt8[0x04])
        symlink(joinpath(root, "linked-target"), joinpath(root, "internal-link"))
        expect_error(:unsafe_path, () -> V3._safe_read(root, "internal-link/value.bin"))
        Base.Filesystem.hardlink(
            joinpath(root, "plain", "source.bin"),
            joinpath(root, "plain", "hard.bin"),
        )
        expect_error(:unsafe_path, () -> V3._safe_read(root, "plain/source.bin"))
        expect_error(:unsafe_path, () -> V3._safe_read(root, "../outside.bin"))
        expect_error(:unsafe_path, () -> V3._safe_read(root, joinpath(root, "plain", "source.bin")))
        expect_error(
            :file_race,
            () -> V3._require_stable((1, 2, 3), (1, 2, 4), "race fixture"),
        )
    end

    policy = V3.load_policy()
    restamped = deepcopy(policy)
    restamped["source_bindings"][1]["sha256"] = repeat("1", 64)
    stamp!(restamped)
    expect_error(:policy_content_hash_mismatch, () -> V3._validate_policy(restamped))
end

@testset "frozen resource ceilings, global replica identity, and root races" begin
    mktempdir() do root
        root = realpath(root)
        oversized_path = joinpath(root, "oversized.sparse")
        open(oversized_path, "w") do io
            truncate(io, V3.MAXIMUM_RAW_OR_REPLICA_FILE_BYTES + 1)
        end
        for maximum_bytes in [
                V3.MAXIMUM_METADATA_FILE_BYTES,
                V3.MAXIMUM_TIMESTAMP_TOKEN_BYTES,
                V3.MAXIMUM_RAW_OR_REPLICA_FILE_BYTES,
            ]
            expect_error(
                :resource_limit,
                () -> V3._safe_read(
                    root,
                    "oversized.sparse";
                    maximum_bytes = maximum_bytes,
                ),
            )
        end
        expect_error(
            :resource_limit,
            () -> V3._validate_relative_path(repeat("a", V3.MAXIMUM_RELATIVE_PATH_BYTES + 1)),
        )
        expect_error(
            :resource_limit,
            () -> V3._expect_vector(
                fill(nothing, V3.MAXIMUM_CATALOG_CANDIDATES_PER_PROFILE + 1),
                "oversized catalog";
                maximum_items = V3.MAXIMUM_CATALOG_CANDIDATES_PER_PROFILE,
            ),
        )
        expect_error(
            :resource_limit,
            () -> V3._bounded_add(
                V3.MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE,
                1,
                V3.MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE,
                "raw aggregate test",
            ),
        )
        expect_error(
            :resource_limit,
            () -> V3._bounded_add(
                V3.MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT,
                1,
                V3.MAXIMUM_TOTAL_REPLICA_BYTES_PER_PARENT,
                "parent aggregate test",
            ),
        )

        parent_path, _ = build_fixture!(root)
        parent = read_toml(root, parent_path)
        receipt_path = parent["rows"][1]["receipt_path"]
        restore_paths = [
            parent_path,
            receipt_path,
            parent["approvals"]["owner_receipt_path"],
            parent["approvals"]["validator_receipt_path"],
        ]
        with_restored_files(root, restore_paths) do
            mutate_leaf_and_parent!(root, parent_path, 1) do document
                document["raw_artifacts"][1]["path"] = "raw/does-not-exist.payload"
                document["raw_artifacts"][1]["byte_count"] =
                    V3.MAXIMUM_RAW_OR_REPLICA_FILE_BYTES + 1
            end
            expect_error(
                :resource_limit,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        result = V3.verify_parent(parent_path; evidence_root = root)
        oversized_result = deepcopy(result)
        oversized_result["profile_results"][1]["active_profile_id"] =
            repeat("x", V3.MAXIMUM_STRING_BYTES + 1)
        expect_error(
            :resource_limit,
            () -> V3.validate_result(oversized_result; evidence_root = root),
        )

        overflow_result = deepcopy(result)
        overflow_result["profile_results"][1]["raw_artifact_bytes"] = typemax(Int)
        overflow_result["profile_results"][1]["replica_bytes"] = typemax(Int)
        stamp!(overflow_result)
        expect_error(
            :resource_limit,
            () -> V3.validate_result(overflow_result; evidence_root = root),
        )

        negative_total = deepcopy(result)
        negative_total["verification"]["total_raw_artifact_bytes"] = -1
        stamp!(negative_total)
        expect_error(
            :resource_limit,
            () -> V3.validate_result(negative_total; evidence_root = root),
        )
    end

    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        parent = read_toml(root, parent_path)
        inflated_profile_count =
            div(V3.MAXIMUM_TOTAL_RAW_BYTES_PER_PARENT, V3.MAXIMUM_TOTAL_RAW_BYTES_PER_PROFILE) + 1
        for index in 1:inflated_profile_count
            receipt_path = parent["rows"][index]["receipt_path"]
            receipt = read_toml(root, receipt_path)
            original_raw = receipt["raw_artifacts"][1]
            raw_entries = Dict{String, Any}[]
            for raw_index in 1:2
                raw = deepcopy(original_raw)
                raw["artifact_id"] = "preflight.raw.$index.$raw_index"
                raw["path"] = "missing/preflight-raw-$index-$raw_index"
                raw["byte_count"] = V3.MAXIMUM_RAW_OR_REPLICA_FILE_BYTES
                push!(raw_entries, raw)
            end
            replicas = Dict{String, Any}[]
            for (raw_index, raw) in enumerate(raw_entries), replica_index in 1:2
                tag = "$index.$raw_index.$replica_index"
                push!(
                    replicas,
                    Dict{String, Any}(
                        "replica_id" => "preflight.replica.$tag",
                        "raw_artifact_id" => raw["artifact_id"],
                        "path" => "missing/preflight-replica-$tag",
                        "sha256" => raw["sha256"],
                        "byte_count" => V3.MAXIMUM_RAW_OR_REPLICA_FILE_BYTES,
                        "storage_domain_id" => "preflight.domain.$tag",
                        "storage_backend_id" => "preflight.backend.$tag",
                        "object_id" => "preflight.object.$tag",
                        "domain_attestation_path" => "missing/preflight-attestation-$tag.toml",
                        "domain_attestation_sha256" => repeat(string(mod(index, 10)), 64),
                    ),
                )
            end
            receipt["raw_artifacts"] = raw_entries
            receipt["replicas"] = replicas
            parent["rows"][index]["receipt_sha256"] =
                write_toml(root, receipt_path, receipt)
        end
        write_toml(root, parent_path, parent)
        expect_error(
            :resource_limit,
            () -> V3.verify_parent(parent_path; evidence_root = root),
        )
    end

    raw_hash = repeat("a", 64)
    raw_by_id = Dict{String, Dict{String, Any}}(
        "raw.one" => Dict("path" => "raw/one", "sha256" => raw_hash, "byte_count" => 1),
        "raw.two" => Dict("path" => "raw/two", "sha256" => raw_hash, "byte_count" => 1),
    )
    raw_states = Dict{String, Any}(
        "raw.one" => (UInt64(1), UInt64(1), 0, 1, 1, 0.0, 0.0),
        "raw.two" => (UInt64(1), UInt64(2), 0, 1, 1, 0.0, 0.0),
    )
    make_replica = function (index, raw_id; replica_id = "replica.$index", object_id = "object.$index")
        return Dict{String, Any}(
            "replica_id" => replica_id,
            "raw_artifact_id" => raw_id,
            "path" => "replicas/$index",
            "sha256" => raw_hash,
            "byte_count" => 1,
            "storage_domain_id" => "domain.$index",
            "storage_backend_id" => "backend.$index",
            "object_id" => object_id,
            "domain_attestation_path" => "attestations/$index.toml",
            "domain_attestation_sha256" => repeat(string(mod(index, 10)), 64),
        )
    end
    duplicate_id_replicas = [
        make_replica(1, "raw.one"),
        make_replica(2, "raw.one"),
        make_replica(3, "raw.two"; replica_id = "replica.1"),
        make_replica(4, "raw.two"),
    ]
    expect_error(
        :replica_independence,
        () -> V3._validate_replicas(
            pwd(),
            duplicate_id_replicas,
            raw_by_id,
            raw_states,
            "SYNTHETIC_TEST_ONLY",
            V3._parse_rfc3339("2026-08-20T13:30:00Z", "test completion"),
        ),
    )
    duplicate_object_replicas = [
        make_replica(1, "raw.one"),
        make_replica(2, "raw.one"),
        make_replica(3, "raw.two"; object_id = "object.1"),
        make_replica(4, "raw.two"),
    ]
    expect_error(
        :replica_independence,
        () -> V3._validate_replicas(
            pwd(),
            duplicate_object_replicas,
            raw_by_id,
            raw_states,
            "SYNTHETIC_TEST_ONLY",
            V3._parse_rfc3339("2026-08-20T13:30:00Z", "test completion"),
        ),
    )

    mktempdir() do base
        base = realpath(base)
        root = joinpath(base, "evidence")
        mkpath(root)
        _, states = V3._snapshot_safe_root(root)
        write_bytes(base, "unrelated-sibling.bin", UInt8[0x01])
        @test V3._recheck_path_states(states, "ancestor sibling mutation") === states

        _, root_states = V3._snapshot_safe_root(root)
        write_bytes(root, "root-mutation.bin", UInt8[0x02])
        expect_error(
            :file_race,
            () -> V3._recheck_path_states(root_states, "evidence-root mutation"),
        )

        link_path = joinpath(base, "evidence-link")
        symlink(root, link_path)
        expect_error(:unsafe_root, () -> V3._snapshot_safe_root(link_path))
    end

    mktempdir() do base
        base = realpath(base)
        ancestor = joinpath(base, "ancestor")
        root = joinpath(ancestor, "evidence")
        mkpath(root)
        _, states = V3._snapshot_safe_root(root)
        mv(ancestor, ancestor * ".old")
        mkpath(root)
        expect_error(
            :file_race,
            () -> V3._recheck_path_states(states, "ancestor replacement"),
        )
    end
end

@testset "retention geometry and status-ceiling validation" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        parent = read_toml(root, parent_path)
        custody_path = parent["custody"]["receipt_path"]
        restore_paths = [
            parent_path,
            custody_path,
            parent["approvals"]["owner_receipt_path"],
            parent["approvals"]["validator_receipt_path"],
        ]
        with_restored_files(root, restore_paths) do
            custody = read_toml(root, custody_path)
            custody["geometry"]["mathematical_minimum_retain_until_utc"] =
                "2031-10-30T14:00:00Z"
            parent["custody"]["receipt_sha256"] = write_toml(root, custody_path, custody)
            rewrite_parent_approvals!(
                root,
                parent,
                parent["artifact"]["evidence_class"],
            )
            write_toml(root, parent_path, parent)
            expect_error(
                :binding_mismatch,
                () -> V3.verify_parent(parent_path; evidence_root = root),
            )
        end

        result = V3.verify_parent(parent_path; evidence_root = root)
        elevated = deepcopy(result)
        elevated["verification"]["status"] = "READY_TO_SCORE"
        elevated["verification"]["claim_ceiling"] = "READY_TO_SCORE"
        stamp!(elevated)
        expect_error(
            :gate_elevation,
            () -> V3.validate_result(elevated; evidence_root = root),
        )

        synthetic_ready = deepcopy(result)
        synthetic_ready["verification"]["status"] =
            "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
        synthetic_ready["verification"]["claim_ceiling"] =
            "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
        synthetic_ready["verification"]["evidence_class"] = "SYNTHETIC_TEST_ONLY"
        empty!(synthetic_ready["blocking_reasons"])
        synthetic_ready["verification"]["blocking_reason_count"] = 0
        synthetic_ready["verification"]["qualified_dispatch_count"] = 21
        synthetic_ready["verification"]["qualified_profile_count"] = 107
        stamp!(synthetic_ready)
        expect_error(
            :gate_elevation,
            () -> V3.validate_result(synthetic_ready; evidence_root = root),
        )
    end
end

@testset "custody child closure, coordinated restamps, and result replay" begin
    mktempdir() do root
        root = realpath(root)
        parent_path, _ = build_fixture!(root)
        original_result = V3.verify_parent(parent_path; evidence_root = root)
        parent = read_toml(root, parent_path)
        receipt_path = parent["rows"][1]["receipt_path"]
        receipt_bytes = read(joinpath(root, receipt_path))
        changed_receipt_hash = write_bytes(
            root,
            receipt_path,
            vcat(receipt_bytes, Vector{UInt8}(codeunits("\n"))),
        )
        parent["rows"][1]["receipt_sha256"] = changed_receipt_hash
        rewrite_parent_approvals!(root, parent, parent["artifact"]["evidence_class"])
        write_toml(root, parent_path, parent)
        expect_error(
            :binding_mismatch,
            () -> V3.verify_parent(parent_path; evidence_root = root),
        )

        parent = read_toml(root, parent_path)
        custody_path, custody_hash =
            build_custody!(root, parent, parent["artifact"]["evidence_class"])
        parent["custody"]["receipt_path"] = custody_path
        parent["custody"]["receipt_sha256"] = custody_hash
        rewrite_parent_approvals!(root, parent, parent["artifact"]["evidence_class"])
        write_toml(root, parent_path, parent)
        coordinated = V3.verify_parent(parent_path; evidence_root = root)
        @test coordinated["verification"]["status"] == "CANNOT_RUN"
        @test coordinated["verification"]["maximum_status"] == "CANNOT_RUN"
        @test coordinated["verification"]["authenticated_trust_anchor_count"] == 0
        @test any(
            item -> item["blocker_id"] == "current_v3_authenticated_trust_roots_absent",
            coordinated["blocking_reasons"],
        )

        expect_error(
            :result_replay_mismatch,
            () -> V3.validate_result(original_result; evidence_root = root),
        )

        forged = deepcopy(coordinated)
        forged["profile_results"][1]["active_profile_id"] = "forged.active.profile"
        stamp!(forged)
        expect_error(
            :result_replay_mismatch,
            () -> V3.validate_result(forged; evidence_root = root),
        )

        forged_rows = deepcopy(coordinated)
        forged_rows["profile_results"] =
            [Dict{String, Any}("forged" => index) for index in 1:107]
        stamp!(forged_rows)
        expect_error(
            :invalid_schema,
            () -> V3.validate_result(forged_rows; evidence_root = root),
        )

        missing_parent = deepcopy(coordinated)
        missing_parent["verification"]["parent_path"] = "parent/does-not-exist.toml"
        stamp!(missing_parent)
        expect_error(
            :missing_file,
            () -> V3.validate_result(missing_parent; evidence_root = root),
        )

        missing_scope = deepcopy(coordinated)
        pop!(missing_scope["verification"], "action_count_scope")
        stamp!(missing_scope)
        expect_error(
            :invalid_schema,
            () -> V3.validate_result(missing_scope; evidence_root = root),
        )

        ready_restamp = deepcopy(coordinated)
        ready_restamp["verification"]["status"] =
            "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
        ready_restamp["verification"]["claim_ceiling"] =
            "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
        empty!(ready_restamp["blocking_reasons"])
        ready_restamp["verification"]["blocking_reason_count"] = 0
        stamp!(ready_restamp)
        expect_error(
            :gate_elevation,
            () -> V3.validate_result(ready_restamp; evidence_root = root),
        )
    end
end
