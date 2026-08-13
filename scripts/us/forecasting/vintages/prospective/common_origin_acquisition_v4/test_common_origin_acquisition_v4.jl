using SHA
using Test
using TOML

const TEST_DIRECTORY = @__DIR__
const MODULE_PATH = joinpath(TEST_DIRECTORY, "USCommonOriginAcquisitionV4.jl")
const POLICY_PATH = joinpath(TEST_DIRECTORY, "common_origin_acquisition_v4_policy.toml")
const PROJECT_PATH = joinpath(TEST_DIRECTORY, "Project.toml")
const MANIFEST_PATH = joinpath(TEST_DIRECTORY, "Manifest.toml")
const EXPECTED_MODULE_SHA256 =
    "0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e"
const EXPECTED_POLICY_SHA256 =
    "84e74d236f0e0ac781a482b996be95fceefe56f2a349be089b51054c3edd8834"
const EXPECTED_PROJECT_SHA256 =
    "bce609ef93f95f71274999edbcb1616a353d3fa274fc058506c53ba884c17a96"
const EXPECTED_MANIFEST_SHA256 =
    "84363c46a921645ebbffa98c479916400741c549bb55dd0d6db8ec4a1c24d1d8"
const EXPECTED_SCHEMA_HASHES = Dict(
    "authenticated_decision_v1.schema.toml" =>
        "8c27844f8d8404ef671576c2cd789a32a1f400f49fc0fbbfc4f15c15e3d54943",
    "common_origin_parent_v4.schema.toml" =>
        "cc92052fb16906a8d8278029f8d7e6ce203cd04df62cf5837758e96b6891b195",
    "custody_operator_manifest_v1.schema.toml" =>
        "8baf14bebe0ac537f4b4a910518c445ef2c8253d74845aaa2a559b9c73e1d914",
    "independent_validation_result_v2.schema.toml" =>
        "6b5c2add09cc00f025abc7ceb9f215a825ad5a9161e261e30c76b43d64f2db40",
    "origin_evidence_closure_v1.schema.toml" =>
        "df926ef5ad27736bf4d3a99b4feaf21d019a420afbe7a9e86118d5ff3f685967",
    "profile_object_set_selection_v2.schema.toml" =>
        "e7307257315a13a8a45cdf988a24dad29899e7f908d601f34b4c3b6599380987",
    "qualified_leaf_verifier_result_v2.schema.toml" =>
        "51e24954dc6e1c1befa307e00868e71d462dbf6b334d429193f2701b086d750f",
    "raw_object_catalog_v1.schema.toml" =>
        "df534859a8f8293a9428fe3b7e2196e1194b369015b2e6508be7b991e3be9030",
    "retention_custody_v3.schema.toml" =>
        "c0aee6b8c2a1123ae929afb39cbdad51d70b4335aecb0af6b9711131fb331ef9",
    "rfc3161_evidence_v1.schema.toml" =>
        "5bbab2c422461d07488482847fb200b6da316da2c7c8d9dfcd4d6788455f13b2",
    "trust_bootstrap_reference_v1.schema.toml" =>
        "4153c35aa9415ac0839f7c5fe177cfffadf772b2739cb311b6f115e875df9581",
    "trust_key_registry_v1.schema.toml" =>
        "b40536feeff179ce469b80e23d0e19e76202119f834c1fb969e254b7f74a31d9",
    "verifier_release_manifest_v1.schema.toml" =>
        "4c253f6d4244d3355ae3e75b3eddc016daa1c2aed930262d57361b6cced40d62",
)

file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

const MODULE_TEXT = read(MODULE_PATH, String)

@testset "isolated dependency and inert source boundary" begin
    @test file_sha256(MODULE_PATH) == EXPECTED_MODULE_SHA256
    @test file_sha256(PROJECT_PATH) == EXPECTED_PROJECT_SHA256
    @test file_sha256(MANIFEST_PATH) == EXPECTED_MANIFEST_SHA256
    imports = [
        match.captures[1] for match in eachmatch(
                r"(?m)^using\s+([A-Za-z][A-Za-z0-9_]*)\s*$",
                MODULE_TEXT,
            )
    ]
    @test Set(imports) == Set(["SHA", "TOML"])
    @test !occursin(r"(?m)^using\s+OpenSSL_jll\s*$", MODULE_TEXT)
    @test !occursin(r"\b(?:Downloads|HTTP|Sockets|LibCURL|Pkg)\b", MODULE_TEXT)
    @test !occursin(r"\b(?:run|pipeline|download|request|sign|verify_signature)\s*\(", MODULE_TEXT)
    @test !occursin(r"\b(?:mkpath|mkdir|rm|cp|mv)\s*\(", MODULE_TEXT)
    project = TOML.parsefile(PROJECT_PATH)
    @test project["deps"] ==
        Dict("OpenSSL_jll" => "458c3c95-2e84-50aa-8efc-19380b2a3a95")
    @test project["compat"]["OpenSSL_jll"] == "=3.5.7"
    manifest = TOML.parsefile(MANIFEST_PATH)
    @test manifest["deps"]["OpenSSL_jll"][1]["version"] == "3.5.7+0"
    @test manifest["deps"]["OpenSSL_jll"][1]["git-tree-sha1"] ==
        "d8cce34295c55f47be683580f44791716045b8fe"
end

include(MODULE_PATH)
const V4 = USCommonOriginAcquisitionV4

function expect_error(thunk, code)
    observed = nothing
    try
        thunk()
    catch error
        observed = error
    end
    @test observed isa V4.AuthenticatedEvidenceV4Error
    if observed isa V4.AuthenticatedEvidenceV4Error
        @test observed.code == code
    end
    return observed
end

function replica(raw_id, raw_hash, byte_count, replica_index, object_subject)
    suffix = replica_index == 1 ? "a" : "b"
    return Dict{String, Any}(
        "replica_id" => "$raw_id.replica.$suffix",
        "relative_path" => "synthetic/replicas/$raw_id.$suffix.bin",
        "sha256" => raw_hash,
        "byte_count" => byte_count,
        "storage_domain_id" => "synthetic.domain.$suffix",
        "storage_backend_id" => "synthetic.backend.$suffix",
        "storage_object_version" => "$raw_id.storage.version.$suffix",
        "custody_operator_key_id" => "synthetic.custody.operator.$suffix",
        "custody_attestation_id" => "$raw_id.attestation.$suffix",
        "catalog_object_subject_sha256" => object_subject,
    )
end

function raw_object(object_id, source_id, index)
    raw_hash = bytes2hex(SHA.sha256(Vector{UInt8}(codeunits("inert-$object_id"))))
    byte_count = 1_000 + index
    is_bea = startswith(object_id, "bea")
    request_uri = is_bea ?
        "https://synthetic.invalid/bea/fixed-assets/$object_id.xlsx" :
        "https://synthetic.invalid/bls/public-api/v2/timeseries/data/"
    raw = Dict{String, Any}(
        "object_id" => object_id,
        "source_id" => source_id,
        "artifact_role" => "synthetic.raw.object",
        "media_type" => is_bea ?
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" :
            "application/json",
        "request_method" => is_bea ? "GET" : "POST",
        "requested_uri" => request_uri,
        "final_effective_uri" => request_uri,
        "redirect_policy" => "FORBID_REDIRECTS_REQUIRE_URI_EQUALITY",
        "request_payload_sha256" => is_bea ?
            bytes2hex(SHA.sha256(UInt8[])) :
            bytes2hex(
                SHA.sha256(Vector{UInt8}(codeunits("synthetic-request-$object_id"))),
            ),
        "request_ordinal" => is_bea ? 1 : index - 3,
        "provider_object_version" => "$object_id.provider.version.v1",
        "relative_path" => "synthetic/raw/$object_id.bin",
        "sha256" => raw_hash,
        "byte_count" => byte_count,
    )
    raw["provider_object_subject_sha256"] = V4.provider_object_subject_sha256(raw)
    object_subject = V4.raw_object_subject_sha256(raw)
    raw["replicas"] = [
        replica(object_id, raw_hash, byte_count, 1, object_subject),
        replica(object_id, raw_hash, byte_count, 2, object_subject),
    ]
    return raw
end

function restamp_object_binding!(raw)
    object_subject = V4.raw_object_subject_sha256(raw)
    for replica in raw["replicas"]
        replica["catalog_object_subject_sha256"] = object_subject
    end
    return raw
end

function restamp_provider_and_object_binding!(raw)
    raw["provider_object_subject_sha256"] = V4.provider_object_subject_sha256(raw)
    return restamp_object_binding!(raw)
end

function valid_catalog()
    object_ids = [
        "bea-fixed-assets-section-3",
        "bea-fixed-assets-section-5",
        "bea-fixed-assets-section-7",
        "bls-cps-history-chunk-001",
        "bls-cps-history-chunk-002",
        "bls-cps-history-chunk-003",
    ]
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-raw-object-catalog.v1",
        "evidence_class" => "SYNTHETIC_INERT",
        "catalog_id" => "synthetic.catalog.fixed-assets-and-cps",
        "objects" => [
            raw_object(
                    object_id,
                    startswith(object_id, "bea") ? "bea.fixed.assets" : "bls.cps",
                    index,
                ) for (index, object_id) in enumerate(object_ids)
        ],
    )
end

function valid_selections()
    profile_to_objects = Dict(
        "faat301esi_net_stock" => ["bea-fixed-assets-section-3"],
        "faat304esi_depreciation" => ["bea-fixed-assets-section-3"],
        "faat307esi_investment" => ["bea-fixed-assets-section-3"],
        "faat501_residential_net_stock" => ["bea-fixed-assets-section-5"],
        "faat504_residential_depreciation" => ["bea-fixed-assets-section-5"],
        "faat507_residential_investment" => ["bea-fixed-assets-section-5"],
        "faat701_government_net_stock" => ["bea-fixed-assets-section-7"],
        "faat703_government_depreciation" => ["bea-fixed-assets-section-7"],
    )
    cps_chunks = [
        "bls-cps-history-chunk-001",
        "bls-cps-history-chunk-002",
        "bls-cps-history-chunk-003",
    ]
    for profile_id in (
            "cps_employed",
            "cps_inactive",
            "cps_labor_force",
            "cps_population",
            "cps_unemployed",
            "cps_unemployment_rate",
        )
        profile_to_objects[profile_id] = copy(cps_chunks)
    end
    return [
        let projection = V4.expected_profile_projection(profile_id)
                Dict{String, Any}(
                    "schema_version" => "beforeit-us-profile-object-set-selection.v2",
                    "profile_id" => profile_id,
                    "ordered_object_ids" => profile_to_objects[profile_id],
                    "projection" => projection,
                    "projection_subject_sha256" => V4.profile_projection_subject_sha256(
                        profile_id,
                        profile_to_objects[profile_id],
                        projection,
                    ),
                )
        end for profile_id in sort!(collect(keys(profile_to_objects)))
    ]
end


function restamp_projection!(selection)
    selection["projection_subject_sha256"] = V4.profile_projection_subject_sha256(
        selection["profile_id"],
        selection["ordered_object_ids"],
        selection["projection"],
    )
    return selection
end

function all_false_gates()
    return Dict{String, Any}(
        "network_allowed" => false,
        "raw_access_allowed" => false,
        "signing_allowed" => false,
        "timestamp_submission_allowed" => false,
        "origin_admission_allowed" => false,
        "model_access_allowed" => false,
        "truth_access_allowed" => false,
        "scoring_allowed" => false,
        "inventory_mutation_allowed" => false,
        "worklog_mutation_allowed" => false,
    )
end

function valid_parent()
    return Dict{String, Any}(
        "schema_version" => "beforeit-us-common-origin-parent.v4",
        "evidence_class" => "SYNTHETIC_INERT",
        "candidate_status" => "CANNOT_RUN",
        "maximum_status" => "CANNOT_RUN",
        "claim_ceiling" =>
            "SYNTHETIC_SCHEMA_AND_FAIL_CLOSED_LOGIC_ONLY_NO_AUTHENTICATED_ORIGIN",
        "raw_object_catalog" => valid_catalog(),
        "profile_selections" => valid_selections(),
        "trust_bootstrap" => Dict{String, Any}(
            "schema_version" => "beforeit-us-trust-bootstrap-reference.v1",
            "state" => "ABSENT_NOT_PROVISIONED",
            "out_of_evidence_anchor_ids" => Any[],
        ),
        "key_registry" => Dict{String, Any}(
            "schema_version" => "beforeit-us-trust-key-registry.v1",
            "state" => "ABSENT_NOT_PROVISIONED",
            "role_keys" => Any[],
            "revocations" => Any[],
            "rotations" => Any[],
        ),
        "rfc3161_evidence" => Dict{String, Any}(
            "schema_version" => "beforeit-us-rfc3161-evidence.v1",
            "state" => "ABSENT_NOT_REQUESTED",
            "requests" => Any[],
            "responses" => Any[],
        ),
        "custody_manifest" => Dict{String, Any}(
            "schema_version" => "beforeit-us-custody-operator-manifest.v1",
            "state" => "SYNTHETIC_DECLARATIONS_ONLY",
            "external_domain_attestations" => Any[],
            "owner_decisions" => Any[],
            "validator_decisions" => Any[],
        ),
        "verifier_release_manifest" => Dict{String, Any}(
            "schema_version" => "beforeit-us-verifier-release-manifest.v1",
            "state" => "UNAUTHENTICATED_SYNTHETIC_PIN",
            "source_sha256" => EXPECTED_MODULE_SHA256,
            "project_sha256" => EXPECTED_PROJECT_SHA256,
            "manifest_sha256" => EXPECTED_MANIFEST_SHA256,
            "owner_signature_ids" => Any[],
            "validator_signature_ids" => Any[],
            "timestamp_evidence_ids" => Any[],
        ),
        "gates" => all_false_gates(),
    )
end

@testset "policy and schema pins" begin
    @test file_sha256(POLICY_PATH) == EXPECTED_POLICY_SHA256
    policy = V4.load_policy()
    @test policy["artifact"]["candidate_status"] == "CANNOT_RUN"
    @test policy["artifact"]["maximum_status"] == "CANNOT_RUN"
    @test policy["implementation"]["module_sha256"] == EXPECTED_MODULE_SHA256
    @test policy["implementation"]["project_sha256"] == EXPECTED_PROJECT_SHA256
    @test policy["implementation"]["manifest_sha256"] == EXPECTED_MANIFEST_SHA256
    @test policy["implementation"]["persistent_policy_collections_immutable"] == true
    @test policy["implementation"]["canonical_domain_stored_as_immutable_string"] == true
    @test policy["implementation"]["canonical_domain_bytes_fresh_per_call"] == true
    @test policy["implementation"]["validation_regex_state_fresh_per_call"] == true
    @test policy["implementation"]["result_blocker_vectors_fresh_per_call"] == true
    @test policy["implementation"]["projection_tables_fresh_per_call"] == true
    @test policy["openssl_dependency"]["version"] == "3.5.7+0"
    @test policy["openssl_dependency"]["fips_provider_present"] == false
    @test policy["openssl_dependency"]["fips_conformance_claimed"] == false
    for (filename, expected_hash) in EXPECTED_SCHEMA_HASHES
        path = joinpath(TEST_DIRECTORY, filename)
        @test file_sha256(path) == expected_hash
        @test TOML.parsefile(path)["artifact"]["evidence_class"] == "SYNTHETIC_INERT"
    end
    unrelated = tempname() * ".toml"
    expect_error("policy_path_not_exact") do
        V4.load_policy(unrelated)
    end
end

@testset "domain-separated typed-length canonical subjects" begin
    first = Dict{String, Any}("z" => [1, true, "x"], "a" => Dict("k" => "v"))
    second = Dict{String, Any}("a" => Dict("k" => "v"), "z" => [1, true, "x"])
    @test V4.canonical_subject_bytes("decision", first) ==
        V4.canonical_subject_bytes("decision", second)
    @test V4.canonical_subject_sha256("decision", first) ==
        V4.canonical_subject_sha256("decision", second)
    @test V4.canonical_subject_sha256("decision", first) !=
        V4.canonical_subject_sha256("release", first)
    @test V4.canonical_subject_sha256("decision", [1, 2]) !=
        V4.canonical_subject_sha256("decision", [2, 1])
    @test V4.canonical_subject_sha256("decision", true) !=
        V4.canonical_subject_sha256("decision", 1)
    @test V4.canonical_subject_sha256("decision", "1") !=
        V4.canonical_subject_sha256("decision", 1)
    @test V4.canonical_subject_sha256("test", Dict("x" => 1, "y" => [true, "z"])) ==
        "e3de26a0cc2d28fe631ee98ea0cf0e2960cf285e9655dc524b99172b86356b0d"
    expect_error("canonical_unsupported_type") do
        V4.canonical_subject_bytes("decision", 1.0)
    end
    expect_error("canonical_key_type") do
        V4.canonical_subject_bytes("decision", Dict(1 => "x"))
    end
    expect_error("invalid_identifier") do
        V4.canonical_subject_bytes("Decision With Spaces", Dict("x" => 1))
    end
    nested = Any[1]
    for _ in 1:40
        nested = Any[nested]
    end
    expect_error("canonical_depth_limit") do
        V4.canonical_subject_bytes("decision", nested)
    end
end

@testset "immutable persistent validation policy and fresh results" begin
    policy_tuples = (
        V4.EXPECTED_BLOCKERS,
        V4.ALLOWED_MEDIA_TYPES,
        V4.BEA_PROFILE_BINDINGS,
        V4.BLS_PROFILES,
        V4.BLS_OBJECT_SET,
        V4.BLS_PROFILE_BINDINGS,
        V4.REQUIRED_DEMONSTRATION_PROFILES,
        V4.REQUIRED_CATALOG_OBJECTS,
    )
    @test all(value -> value isa Tuple, policy_tuples)
    @test all(isimmutable, policy_tuples)

    @test !applicable(empty!, V4.EXPECTED_BLOCKERS)
    @test_throws MethodError empty!(V4.EXPECTED_BLOCKERS)
    first_result = V4.verify_parent(valid_parent())
    empty!(first_result["blockers"])
    @test isempty(first_result["blockers"])
    second_result = V4.verify_parent(valid_parent())
    @test second_result["blockers"] == collect(V4.EXPECTED_BLOCKERS)
    @test length(second_result["blockers"]) == 14
    @test first_result["blockers"] !== second_result["blockers"]

    expected_bls_order = collect(V4.BLS_OBJECT_SET)
    @test !applicable(reverse!, V4.BLS_OBJECT_SET)
    @test_throws MethodError reverse!(V4.BLS_OBJECT_SET)
    @test collect(V4.BLS_OBJECT_SET) == expected_bls_order

    first_bea_binding = V4.BEA_PROFILE_BINDINGS[1]
    fictitious_bea_binding = merge(first_bea_binding, (table_id = "FAAt999",))
    @test !applicable(
        setindex!,
        V4.BEA_PROFILE_BINDINGS,
        fictitious_bea_binding,
        1,
    )
    @test_throws MethodError setindex!(
        V4.BEA_PROFILE_BINDINGS,
        fictitious_bea_binding,
        1,
    )
    returned_projection = V4.expected_profile_projection("faat301esi_net_stock")
    returned_projection["sheet_or_series_id"] = "FAAt999"
    returned_projection["table_or_formula_id"] = "FAAt999"
    fresh_projection = V4.expected_profile_projection("faat301esi_net_stock")
    @test fresh_projection["sheet_or_series_id"] == "FAAt301ESI"
    @test fresh_projection["table_or_formula_id"] == "FAAt301ESI"
    @test returned_projection !== fresh_projection

    fictitious_projection_parent = valid_parent()
    bea_index = findfirst(
        row -> row["profile_id"] == "faat301esi_net_stock",
        fictitious_projection_parent["profile_selections"],
    )
    bea_selection = fictitious_projection_parent["profile_selections"][bea_index]
    bea_selection["projection"]["sheet_or_series_id"] = "FAAt999"
    bea_selection["projection"]["table_or_formula_id"] = "FAAt999"
    restamp_projection!(bea_selection)
    expect_error("invalid_literal") do
        V4.validate_parent(fictitious_projection_parent)
    end

    @test V4.SUBJECT_DOMAIN isa String
    @test !applicable(setindex!, V4.SUBJECT_DOMAIN, 'X', 1)
    @test_throws MethodError setindex!(V4.SUBJECT_DOMAIN, 'X', 1)
    canonical_value = Dict{String, Any}("policy" => "immutable")
    expected_bytes = V4.canonical_subject_bytes("state-check", canonical_value)
    attacked_bytes = V4.canonical_subject_bytes("state-check", canonical_value)
    attacked_bytes[1] = xor(attacked_bytes[1], 0xff)
    @test attacked_bytes != expected_bytes
    @test V4.canonical_subject_bytes("state-check", canonical_value) == expected_bytes

    @test V4.HEX64_PATTERN isa String
    @test V4.IDENTIFIER_PATTERN isa String
    @test V4.RELATIVE_PATH_PATTERN isa String
    @test V4.HTTPS_URI_PATTERN isa String
    @test V4.validate_parent(valid_parent())
end

@testset "shared raw-object catalog and ordered set selections" begin
    parent = valid_parent()
    @test V4.validate_parent(parent)
    object_index = V4.validate_raw_object_catalog(parent["raw_object_catalog"])
    @test length(object_index) == 6
    first_object = parent["raw_object_catalog"]["objects"][1]
    @test first_object["provider_object_version"] ==
        "bea-fixed-assets-section-3.provider.version.v1"
    @test all(!haskey(replica, "provider_object_version") for replica in first_object["replicas"])
    @test first_object["replicas"][1]["storage_object_version"] !=
        first_object["replicas"][2]["storage_object_version"]
    @test all(
        replica["catalog_object_subject_sha256"] == V4.raw_object_subject_sha256(first_object) for
            replica in first_object["replicas"]
    )
    @test first_object["media_type"] ==
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    @test first_object["request_payload_sha256"] ==
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    bls_objects = filter(
        object -> startswith(object["object_id"], "bls-"),
        parent["raw_object_catalog"]["objects"],
    )
    @test length(unique(object["requested_uri"] for object in bls_objects)) == 1
    @test length(unique(object["final_effective_uri"] for object in bls_objects)) == 1
    @test all(
        object["requested_uri"] == object["final_effective_uri"] for object in bls_objects
    )
    @test [object["request_ordinal"] for object in bls_objects] == [1, 2, 3]
    @test all(object["request_method"] == "POST" for object in bls_objects)
    @test all(object["media_type"] == "application/json" for object in bls_objects)
    @test length(unique(object["request_payload_sha256"] for object in bls_objects)) == 3
    @test length(unique(V4.provider_request_subject_sha256.(bls_objects))) == 3
    @test length(unique(V4.provider_object_subject_sha256.(bls_objects))) == 3
    @test "text/tab-separated-values" in V4.ALLOWED_MEDIA_TYPES
    @test "text/plain" in V4.ALLOWED_MEDIA_TYPES
    counts = V4.validate_profile_selections(
        parent["profile_selections"],
        parent["raw_object_catalog"],
    )
    @test counts["bea-fixed-assets-section-3"] == 3
    @test counts["bea-fixed-assets-section-5"] == 3
    @test counts["bea-fixed-assets-section-7"] == 2
    @test counts["bls-cps-history-chunk-001"] == 6
    @test counts["bls-cps-history-chunk-002"] == 6
    @test counts["bls-cps-history-chunk-003"] == 6
    @test parent["profile_selections"][1]["ordered_object_ids"] ==
        parent["profile_selections"][2]["ordered_object_ids"]
    cps_rows = filter(
        row -> startswith(row["profile_id"], "cps_"),
        parent["profile_selections"],
    )
    @test length(cps_rows) == 6
    @test all(length(row["ordered_object_ids"]) == 3 for row in cps_rows)
    @test all(row["ordered_object_ids"] == cps_rows[1]["ordered_object_ids"] for row in cps_rows)
    @test length(unique(row["projection_subject_sha256"] for row in cps_rows)) == 6

    stale_projection_subject = deepcopy(parent)
    stale_projection_subject["profile_selections"][1]["projection_subject_sha256"] =
        repeat("0", 64)
    expect_error("projection_subject_mismatch") do
        V4.validate_parent(stale_projection_subject)
    end

    swapped_bea_projections = deepcopy(parent)
    bea_first = findfirst(
        row -> row["profile_id"] == "faat301esi_net_stock",
        swapped_bea_projections["profile_selections"],
    )
    bea_second = findfirst(
        row -> row["profile_id"] == "faat304esi_depreciation",
        swapped_bea_projections["profile_selections"],
    )
    swapped_bea_projections["profile_selections"][bea_first]["projection"],
        swapped_bea_projections["profile_selections"][bea_second]["projection"] =
        swapped_bea_projections["profile_selections"][bea_second]["projection"],
        swapped_bea_projections["profile_selections"][bea_first]["projection"]
    restamp_projection!(swapped_bea_projections["profile_selections"][bea_first])
    restamp_projection!(swapped_bea_projections["profile_selections"][bea_second])
    expect_error("invalid_literal") do
        V4.validate_parent(swapped_bea_projections)
    end

    swapped_bls_projections = deepcopy(parent)
    bls_first = findfirst(
        row -> row["profile_id"] == "cps_employed",
        swapped_bls_projections["profile_selections"],
    )
    bls_second = findfirst(
        row -> row["profile_id"] == "cps_unemployed",
        swapped_bls_projections["profile_selections"],
    )
    swapped_bls_projections["profile_selections"][bls_first]["projection"],
        swapped_bls_projections["profile_selections"][bls_second]["projection"] =
        swapped_bls_projections["profile_selections"][bls_second]["projection"],
        swapped_bls_projections["profile_selections"][bls_first]["projection"]
    restamp_projection!(swapped_bls_projections["profile_selections"][bls_first])
    restamp_projection!(swapped_bls_projections["profile_selections"][bls_second])
    expect_error("invalid_literal") do
        V4.validate_parent(swapped_bls_projections)
    end

    duplicate_selection = deepcopy(parent)
    duplicate_selection["profile_selections"][1]["ordered_object_ids"] = [
        "bls-cps-history-chunk-001",
        "bls-cps-history-chunk-001",
    ]
    expect_error("duplicate_within_selection") do
        V4.validate_parent(duplicate_selection)
    end

    reordered_chunks = deepcopy(parent)
    cps_index = findfirst(
        row -> row["profile_id"] == "cps_employed",
        reordered_chunks["profile_selections"],
    )
    reverse!(reordered_chunks["profile_selections"][cps_index]["ordered_object_ids"])
    expect_error("selection_semantics") do
        V4.validate_parent(reordered_chunks)
    end

    unknown_object = deepcopy(parent)
    unknown_object["profile_selections"][1]["ordered_object_ids"] = ["unknown-object"]
    expect_error("unknown_catalog_object") do
        V4.validate_parent(unknown_object)
    end

    duplicate_raw_id = deepcopy(parent)
    duplicate_raw_id["raw_object_catalog"]["objects"][2]["object_id"] =
        duplicate_raw_id["raw_object_catalog"]["objects"][1]["object_id"]
    restamp_object_binding!(duplicate_raw_id["raw_object_catalog"]["objects"][2])
    expect_error("global_identity_collision") do
        V4.validate_parent(duplicate_raw_id)
    end

    duplicate_replica_id = deepcopy(parent)
    duplicate_replica_id["raw_object_catalog"]["objects"][2]["replicas"][1]["replica_id"] =
        duplicate_replica_id["raw_object_catalog"]["objects"][1]["replicas"][1]["replica_id"]
    expect_error("global_identity_collision") do
        V4.validate_parent(duplicate_replica_id)
    end

    shared_pair_domain = deepcopy(parent)
    shared_pair_domain["raw_object_catalog"]["objects"][1]["replicas"][2]["storage_domain_id"] =
        shared_pair_domain["raw_object_catalog"]["objects"][1]["replicas"][1]["storage_domain_id"]
    expect_error("replica_independence") do
        V4.validate_parent(shared_pair_domain)
    end

    shared_pair_storage_version = deepcopy(parent)
    shared_pair_storage_version["raw_object_catalog"]["objects"][1]["replicas"][2]["storage_object_version"] =
        shared_pair_storage_version["raw_object_catalog"]["objects"][1]["replicas"][1]["storage_object_version"]
    expect_error("replica_independence") do
        V4.validate_parent(shared_pair_storage_version)
    end

    global_storage_version_collision = deepcopy(parent)
    global_storage_version_collision["raw_object_catalog"]["objects"][2]["replicas"][1]["storage_object_version"] =
        global_storage_version_collision["raw_object_catalog"]["objects"][1]["replicas"][1]["storage_object_version"]
    expect_error("global_identity_collision") do
        V4.validate_parent(global_storage_version_collision)
    end

    bad_replica_hash = deepcopy(parent)
    bad_replica_hash["raw_object_catalog"]["objects"][1]["replicas"][1]["sha256"] =
        repeat("0", 64)
    expect_error("replica_hash_mismatch") do
        V4.validate_parent(bad_replica_hash)
    end

    wrong_object_binding = deepcopy(parent)
    wrong_object_binding["raw_object_catalog"]["objects"][1]["replicas"][1]["catalog_object_subject_sha256"] =
        repeat("0", 64)
    expect_error("replica_object_binding_mismatch") do
        V4.validate_parent(wrong_object_binding)
    end

    changed_provider_version = deepcopy(parent)
    changed_provider_version["raw_object_catalog"]["objects"][1]["provider_object_version"] =
        "changed.provider.version"
    changed_provider_version["raw_object_catalog"]["objects"][1]["provider_object_subject_sha256"] =
        V4.provider_object_subject_sha256(
        changed_provider_version["raw_object_catalog"]["objects"][1],
    )
    expect_error("replica_object_binding_mismatch") do
        V4.validate_parent(changed_provider_version)
    end

    stale_provider_subject = deepcopy(parent)
    stale_provider_subject["raw_object_catalog"]["objects"][1]["provider_object_subject_sha256"] =
        repeat("0", 64)
    expect_error("provider_object_subject_mismatch") do
        V4.validate_parent(stale_provider_subject)
    end

    repeated_request_subject = deepcopy(parent)
    repeated_request_first = repeated_request_subject["raw_object_catalog"]["objects"][4]
    repeated_request_second = repeated_request_subject["raw_object_catalog"]["objects"][5]
    for field in (
            "source_id",
            "request_method",
            "requested_uri",
            "final_effective_uri",
            "redirect_policy",
            "request_payload_sha256",
            "request_ordinal",
        )
        repeated_request_second[field] = repeated_request_first[field]
    end
    restamp_provider_and_object_binding!(repeated_request_second)
    expect_error("global_identity_collision") do
        V4.validate_parent(repeated_request_subject)
    end

    unsupported_media = deepcopy(parent)
    unsupported_media["raw_object_catalog"]["objects"][1]["media_type"] =
        "application/octet-stream"
    expect_error("invalid_media_type") do
        V4.validate_parent(unsupported_media)
    end

    named_source_wrong_media = deepcopy(parent)
    named_source_wrong_media["raw_object_catalog"]["objects"][4]["media_type"] = "text/csv"
    restamp_provider_and_object_binding!(named_source_wrong_media["raw_object_catalog"]["objects"][4])
    expect_error("source_geometry") do
        V4.validate_parent(named_source_wrong_media)
    end

    invalid_uri = deepcopy(parent)
    invalid_uri["raw_object_catalog"]["objects"][1]["requested_uri"] =
        "http://synthetic.invalid/not-https"
    expect_error("invalid_https_uri") do
        V4.validate_parent(invalid_uri)
    end

    invalid_method = deepcopy(parent)
    invalid_method["raw_object_catalog"]["objects"][1]["request_method"] = "PATCH"
    expect_error("invalid_request_method") do
        V4.validate_parent(invalid_method)
    end

    redirected_get = deepcopy(parent)
    redirected_get["raw_object_catalog"]["objects"][1]["final_effective_uri"] =
        "https://synthetic.invalid/bea/fixed-assets/redirected.xlsx"
    restamp_provider_and_object_binding!(redirected_get["raw_object_catalog"]["objects"][1])
    expect_error("redirect_uri_mismatch") do
        V4.validate_parent(redirected_get)
    end

    swapped_requested_uri = deepcopy(parent)
    swapped_requested_uri["raw_object_catalog"]["objects"][1]["requested_uri"] =
        swapped_requested_uri["raw_object_catalog"]["objects"][2]["requested_uri"]
    restamp_provider_and_object_binding!(
        swapped_requested_uri["raw_object_catalog"]["objects"][1],
    )
    expect_error("redirect_uri_mismatch") do
        V4.validate_parent(swapped_requested_uri)
    end

    nonempty_get_payload = deepcopy(parent)
    nonempty_get_payload["raw_object_catalog"]["objects"][1]["request_payload_sha256"] =
        bytes2hex(SHA.sha256(Vector{UInt8}(codeunits("not-empty"))))
    restamp_provider_and_object_binding!(
        nonempty_get_payload["raw_object_catalog"]["objects"][1],
    )
    expect_error("get_payload_not_empty") do
        V4.validate_parent(nonempty_get_payload)
    end

    ordinal_bool = deepcopy(parent)
    ordinal_bool["raw_object_catalog"]["objects"][1]["request_ordinal"] = true
    expect_error("invalid_type") do
        V4.validate_parent(ordinal_bool)
    end

    bad_replica_count = deepcopy(parent)
    pop!(bad_replica_count["raw_object_catalog"]["objects"][1]["replicas"])
    expect_error("replica_count") do
        V4.validate_parent(bad_replica_count)
    end

    wrong_integer = deepcopy(parent)
    wrong_integer["raw_object_catalog"]["objects"][1]["byte_count"] = 1001.0
    expect_error("invalid_type") do
        V4.validate_parent(wrong_integer)
    end

    bool_integer_alias = deepcopy(parent)
    bool_integer_alias["raw_object_catalog"]["objects"][1]["byte_count"] = true
    expect_error("invalid_type") do
        V4.validate_parent(bool_integer_alias)
    end

    object_too_large = deepcopy(parent)
    object_too_large["raw_object_catalog"]["objects"][1]["byte_count"] = 536_870_913
    expect_error("object_byte_limit") do
        V4.validate_parent(object_too_large)
    end

    aggregate_too_large = deepcopy(parent)
    for raw in aggregate_too_large["raw_object_catalog"]["objects"]
        raw["byte_count"] = 400_000_000
        for replica in raw["replicas"]
            replica["byte_count"] = 400_000_000
        end
        restamp_provider_and_object_binding!(raw)
    end
    expect_error("catalog_byte_limit") do
        V4.validate_parent(aggregate_too_large)
    end

    expect_error("byte_count_overflow") do
        V4.checked_byte_total([typemax(Int), 1]; maximum = typemax(Int))
    end
end

@testset "permanent fail-closed trust ceiling" begin
    parent = valid_parent()
    result = V4.verify_parent(parent)
    @test result["status"] == "CANNOT_RUN"
    @test result["maximum_status"] == "CANNOT_RUN"
    @test result["blockers"] == collect(V4.EXPECTED_BLOCKERS)
    @test result["object_count"] == 6
    @test result["profile_count"] == 14
    @test result["selection_reference_count"] == 26
    @test result["unique_object_byte_count"] == sum(1001:1006)
    @test result["authenticated_signature_count"] == 0
    @test result["rfc3161_response_count"] == 0
    @test result["external_custody_attestation_count"] == 0
    @test result["network_action_count"] == 0
    @test result["raw_read_action_count"] == 0
    @test result["signing_action_count"] == 0
    @test result["timestamp_submission_action_count"] == 0
    @test result["model_action_count"] == 0
    @test result["truth_action_count"] == 0
    @test result["scoring_action_count"] == 0
    @test result["inventory_mutation_count"] == 0
    @test result["worklog_mutation_count"] == 0
    @test result["openssl_subprocess_count"] == 0
    @test result["fips_conformance_claimed"] == false
    @test V4.validate_result(parent, result)
    @test result["parent_subject_sha256"] ==
        V4.canonical_subject_sha256("common-origin-parent", parent)

    omitted_field_mutations = [
        mutated -> (mutated["maximum_status"] = "DIFFERENT"),
        mutated -> (mutated["claim_ceiling"] = "DIFFERENT"),
        mutated -> (mutated["gates"]["network_allowed"] = true),
        mutated -> (
            mutated["verifier_release_manifest"]["source_sha256"] = repeat("0", 64)
        ),
        mutated -> push!(mutated["key_registry"]["revocations"], "synthetic-restamp"),
    ]
    for mutate! in omitted_field_mutations
        mutated = deepcopy(parent)
        mutate!(mutated)
        @test V4.parent_subject(mutated) != result["parent_subject_sha256"]
    end

    coordinated_restamp = deepcopy(parent)
    coordinated_restamp["verifier_release_manifest"]["source_sha256"] = repeat("0", 64)
    coordinated_result = deepcopy(result)
    coordinated_result["parent_subject_sha256"] = V4.parent_subject(coordinated_restamp)
    expect_error("invalid_literal") do
        V4.validate_result(coordinated_restamp, coordinated_result)
    end

    forged_result = deepcopy(result)
    forged_result["status"] = "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    expect_error("result_replay_mismatch") do
        V4.validate_result(parent, forged_result)
    end

    ready_parent = deepcopy(parent)
    ready_parent["candidate_status"] = "READY_FOR_FORECAST_SEAL_NO_TRUTH_LOADED"
    expect_error("invalid_literal") do
        V4.verify_parent(ready_parent)
    end

    anchor_injection = deepcopy(parent)
    push!(anchor_injection["trust_bootstrap"]["out_of_evidence_anchor_ids"], "anchor.one")
    expect_error("trust_material_forbidden") do
        V4.verify_parent(anchor_injection)
    end

    key_injection = deepcopy(parent)
    push!(key_injection["key_registry"]["role_keys"], Dict("key_id" => "self.asserted"))
    expect_error("trust_material_forbidden") do
        V4.verify_parent(key_injection)
    end

    timestamp_injection = deepcopy(parent)
    push!(timestamp_injection["rfc3161_evidence"]["responses"], UInt8[0x30, 0x00])
    expect_error("timestamp_material_forbidden") do
        V4.verify_parent(timestamp_injection)
    end

    decision_injection = deepcopy(parent)
    push!(decision_injection["custody_manifest"]["owner_decisions"], "self-signed")
    expect_error("authenticated_decision_forbidden") do
        V4.verify_parent(decision_injection)
    end

    release_injection = deepcopy(parent)
    push!(release_injection["verifier_release_manifest"]["owner_signature_ids"], "sig.one")
    expect_error("release_authentication_forbidden") do
        V4.verify_parent(release_injection)
    end

    release_restamp = deepcopy(parent)
    release_restamp["verifier_release_manifest"]["source_sha256"] = repeat("0", 64)
    expect_error("invalid_literal") do
        V4.verify_parent(release_restamp)
    end

    network_gate = deepcopy(parent)
    network_gate["gates"]["network_allowed"] = true
    expect_error("gate_must_be_false") do
        V4.verify_parent(network_gate)
    end

    numeric_gate = deepcopy(parent)
    numeric_gate["gates"]["network_allowed"] = 0
    expect_error("invalid_type") do
        V4.verify_parent(numeric_gate)
    end

    extra_signature_field = deepcopy(parent)
    extra_signature_field["trust_bootstrap"]["signature"] = "self-asserted"
    expect_error("unexpected_keys") do
        V4.verify_parent(extra_signature_field)
    end
end

@testset "opaque successor crypto declarations without loading" begin
    before_modules = Set(String(nameof(value)) for value in values(Base.loaded_modules))
    report = V4.declared_successor_crypto_runtime()
    after_modules = Set(String(nameof(value)) for value in values(Base.loaded_modules))
    @test report["dependency"] == "OpenSSL_jll"
    @test report["declared_version"] == "3.5.7+0"
    @test report["package_tree_sha1"] == "d8cce34295c55f47be683580f44791716045b8fe"
    @test report["artifact_tree_sha1"] == "5ffc993d703fa0051405cb562c49d46328b8d5f3"
    @test report["target"] == "aarch64-apple-darwin"
    @test report["product_sha256"]["openssl"] ==
        "00292fe08c00550afd97d692c47a2a4a41ee56b136f52f3f63124df97db928c4"
    @test report["product_sha256"]["libcrypto"] ==
        "b40cc0d4fd13fc9a32849fedf18d2fde97694efb5ac19573bd1ba5c40d941644"
    @test report["product_sha256"]["libssl"] ==
        "b8ecb15e077227cf89a5a077335395c9db4bbea978253b7f6d96329f634f30fc"
    @test report["pins_authenticated"] == false
    @test report["runtime_loaded"] == false
    @test report["products_opened"] == false
    @test report["products_validated"] == false
    @test report["subprocess_executed"] == false
    @test report["cryptographic_validation_executed"] == false
    @test report["fips_conformance_claimed"] == false
    @test before_modules == after_modules
    @test !("OpenSSL_jll" in after_modules)
end
