using Dates
using SHA
using TOML
using Test

const ARTIFACT_DIR = @__DIR__
const MODULE_PATH = joinpath(ARTIFACT_DIR, "USBEAFixedAssetsHMI11DiscoveryV1.jl")
const PROFILE_PATH =
    joinpath(ARTIFACT_DIR, "bea_fixed_assets_hmi11_discovery_profile_v1.toml")

include(MODULE_PATH)
const Discovery = USBEAFixedAssetsHMI11DiscoveryV1

const RELEASE_OLD =
    Discovery.INTERNAL_RELEASE_ROOT *
    "\\2097\\AnnualUpdate_September-2-2098"
const RELEASE_NEW =
    Discovery.INTERNAL_RELEASE_ROOT *
    "\\2098\\AnnualUpdate_September-1-2099"
const RELEASE_FUTURE =
    Discovery.INTERNAL_RELEASE_ROOT *
    "\\2099\\AnnualUpdate_September-3-2100"

function json_string(value)
    io = IOBuffer()
    write(io, '"')
    for character in String(value)
        if character == '"'
            write(io, "\\\"")
        elseif character == '\\'
            write(io, "\\\\")
        elseif character == '\n'
            write(io, "\\n")
        elseif character == '\r'
            write(io, "\\r")
        elseif character == '\t'
            write(io, "\\t")
        elseif iscntrl(character)
            print(io, "\\u", uppercase(string(Int(character); base = 16, pad = 4)))
        else
            print(io, character)
        end
    end
    write(io, '"')
    return String(take!(io))
end

json_array(values) = "[" * join(json_string.(values), ",") * "]"

function root_body(
        paths;
        main_name = "Fixed Asset",
        folder_pattern = "FA\\dataYear\\vintage_NewReleaseDate",
    )
    return "{" *
        "\"MainName\":" *
        json_string(main_name) *
        ",\"FolderPattern\":" *
        json_string(folder_pattern) *
        ",\"FileArray\":" *
        json_array(paths) *
        "}"
end

function id_body(directory_id = "4242")
    return "[{\"Notes\":null,\"Theid\":" *
        json_string(directory_id) *
        ",\"Thepath\":null,\"DescriptionLong\":null}]"
end

function reverse_body(path)
    return "[{\"Notes\":null,\"Theid\":null,\"Thepath\":" *
        json_string(path) *
        ",\"DescriptionLong\":null}]"
end

function files_body(paths; main_name = "Fixed Asset")
    return "{\"MainName\":" *
        json_string(main_name) *
        ",\"Filearray3\":" *
        json_array(paths) *
        "}"
end

function valid_file_paths(release = RELEASE_NEW)
    return [
        release * "\\ReadMe.txt",
        release * "\\UND\\Section3ALL_xls.xlsx",
        release * "\\Section3aLl_xls.xlsx",
        release * "\\section5ALL_XLS.XLSX",
        release * "\\SECTION7All_xls.XlSx",
    ]
end

response_bytes(body) = Vector{UInt8}(codeunits(String(body)))

function response_envelope(
        index,
        role,
        requested_uri,
        body,
        prior_sha256,
        selected_path,
        directory_id;
        final_effective_uri = requested_uri,
    )
    bytes = response_bytes(body)
    return Dict{String, Any}(
        "sequence_index" => index,
        "response_role" => role,
        "requested_uri" => requested_uri,
        "final_effective_uri" => final_effective_uri,
        "body" => bytes,
        "body_sha256" => Discovery.sha256_hex(bytes),
        "prior_response_body_sha256" => prior_sha256,
        "selected_release_internal_path" => selected_path,
        "directory_id" => directory_id,
    )
end

function valid_response_envelopes(; root = nothing, files = nothing)
    root === nothing &&
        (root = root_body([RELEASE_OLD, RELEASE_NEW, RELEASE_FUTURE]))
    release = Discovery.select_latest_release(
        Discovery.parse_release_directories(root),
        Date(2099, 12, 31),
    )
    id = id_body()
    reverse = reverse_body(release.internal_path)
    files === nothing && (files = files_body(valid_file_paths(release.internal_path)))
    root_envelope = response_envelope(
        1,
        Discovery.ROOT_RESPONSE_ROLE,
        Discovery.ROOT_DISCOVERY_URL,
        root,
        Discovery.GENESIS,
        Discovery.NOT_APPLICABLE,
        Discovery.NOT_APPLICABLE,
    )
    id_envelope = response_envelope(
        2,
        Discovery.ID_RESPONSE_ROLE,
        Discovery._directory_id_url(release),
        id,
        root_envelope["body_sha256"],
        release.internal_path,
        Discovery.NOT_APPLICABLE,
    )
    reverse_envelope = response_envelope(
        3,
        Discovery.REVERSE_RESPONSE_ROLE,
        Discovery._resolved_path_url("4242"),
        reverse,
        id_envelope["body_sha256"],
        release.internal_path,
        "4242",
    )
    files_envelope = response_envelope(
        4,
        Discovery.FILES_RESPONSE_ROLE,
        Discovery._release_files_url(release),
        files,
        reverse_envelope["body_sha256"],
        release.internal_path,
        "4242",
    )
    return [root_envelope, id_envelope, reverse_envelope, files_envelope]
end

function rehash_body!(envelope)
    envelope["body_sha256"] = Discovery.sha256_hex(envelope["body"])
    return envelope
end

function rechain!(envelopes)
    envelopes[1]["prior_response_body_sha256"] = Discovery.GENESIS
    for index in 2:length(envelopes)
        envelopes[index]["prior_response_body_sha256"] =
            envelopes[index - 1]["body_sha256"]
    end
    return envelopes
end

function captured_error(function_to_run)
    caught = try
        function_to_run()
        nothing
    catch error
        error
    end
    @test caught isa Discovery.DiscoveryError
    return caught
end

function profile_document()
    return TOML.parsefile(PROFILE_PATH)
end

@testset "Frozen profile and dependency identities" begin
    profile = Discovery.load_profile()
    @test profile["artifact"]["status"] == "CANNOT_RUN"
    @test profile["artifact"]["role"] == "DISCOVERY_MECHANICS_ONLY"
    @test profile["artifact"]["content_sha256"] ==
        "96d0f93b4bf538b45fac44843f47dfd0e8aa8ca4a8e9125cfd3861e2de9e6921"
    @test Discovery.profile_content_sha256(profile) ==
        profile["artifact"]["content_sha256"]
    @test Discovery.sha256_hex(read(PROFILE_PATH)) ==
        "656717ea525efd341004004f3f9be9d22ffccd7d36e5e84e90aabac9cad9d44c"
    @test profile["hmi11"]["main_name"] == "Fixed Asset"
    @test profile["hmi11"]["folder_pattern"] ==
        "FA\\dataYear\\vintage_NewReleaseDate"
    @test profile["contract"]["maximum_status"] == "CANNOT_RUN"
    @test profile["contract"]["permanent_nonadmitting"]
    @test profile["contract"][
        "source_binding_verification_mandatory_for_operational_build_and_replay",
    ]
    @test profile["contract"]["source_binding_bypass_keyword_forbidden"]
    @test profile["response_envelope"]["required_count"] == 4
    @test profile["response_envelope"]["required_roles"] ==
        collect(Discovery.RESPONSE_ROLES)
    @test profile["response_envelope"]["body_path_equality_alone_insufficient"]
    @test profile["response_envelope"]["metadata_lineage_replay_required"]
    @test length(profile["profiles"]) == 8
    @test count(item -> item["section_id"] == "3", profile["profiles"]) == 3
    @test count(item -> item["section_id"] == "5", profile["profiles"]) == 3
    @test count(item -> item["section_id"] == "7", profile["profiles"]) == 2
    @test all(value -> value === false, values(profile["gates"]))
    @test all(value -> value === false, values(profile["unresolved"]))
    @test profile["page_visible_observation"]["observation_status"] ==
        "PAGE_VISIBLE_UNPRESERVED_NOT_SOURCE_EVIDENCE"
    @test !profile["page_visible_observation"]["historical_member_names_resolved"]
    @test !profile["page_visible_observation"]["source_response_bytes_preserved"]
    @test !profile["page_visible_observation"]["artifact_bytes_preserved"]

    source_bindings = Dict(
        binding["binding_id"] => binding for binding in profile["source_bindings"]
    )
    @test source_bindings["legacy_v2_module"]["physical_sha256"] ==
        "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379"
    @test source_bindings["legacy_v2_contract"]["physical_sha256"] ==
        "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
    @test source_bindings["legacy_v2_contract"]["semantic_sha256"] ==
        "5d1e7f34eea0470877c7bed096d8b2fb26590f95bd06febb90813faf6063708a"
    @test source_bindings["common_origin_v3_module"]["physical_sha256"] ==
        "9654eb61b92b2655391b00952ed4cbee0e9fa58224339f1fb0440c51570e719e"
    @test source_bindings["common_origin_v3_policy"]["semantic_sha256"] ==
        "a69392029c2221ab5f490311c02d09a667e71982c486a1612100c1d6dcd96d13"
    @test source_bindings["current_inventory"]["physical_sha256"] ==
        "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
    @test source_bindings["scripts_us_project"]["physical_sha256"] ==
        "72cec6cb6dc64dc71b9e342890b78afbf8fd66cb97dd8603e4fe905ad137dc1c"
    @test source_bindings["scripts_us_manifest"]["physical_sha256"] ==
        "c2e596cf8452c5b890bb0ef66c05bc72a57fa25ab6f8fe790f8db4600b035263"
end

@testset "Public operational APIs cannot bypass pinned source verification" begin
    public_functions = (
        Discovery.build_discovery_plan,
        Discovery.load_profile,
        Discovery.validate_discovery_plan,
        Discovery.validate_profile_document,
    )
    for public_function in public_functions
        keyword_names = reduce(
            vcat,
            (Base.kwarg_decl(method) for method in methods(public_function));
            init = Symbol[],
        )
        @test :verify_sources ∉ keyword_names
        @test :source_verifier ∉ keyword_names
    end
    @test reduce(
        vcat,
        (Base.kwarg_decl(method) for method in methods(Discovery.build_discovery_plan));
        init = Symbol[],
    ) == [:profile_path]
    @test reduce(
        vcat,
        (Base.kwarg_decl(method) for method in methods(Discovery.validate_discovery_plan));
        init = Symbol[],
    ) == [:profile_path]

    envelopes = valid_response_envelopes()
    cutoff = Date(2099, 12, 31)
    plan = Discovery.build_discovery_plan(envelopes, cutoff)
    builder_bypass_error = try
        Discovery.build_discovery_plan(envelopes, cutoff; verify_sources = false)
        nothing
    catch error
        error
    end
    @test builder_bypass_error isa MethodError
    replay_bypass_error = try
        Discovery.validate_discovery_plan(
            plan,
            envelopes,
            cutoff;
            verify_sources = false,
        )
        nothing
    catch error
        error
    end
    @test replay_bypass_error isa MethodError

    prior_probe = Discovery._SOURCE_VERIFICATION_TEST_PROBE[]
    probe_calls = Ref(0)
    try
        Discovery._SOURCE_VERIFICATION_TEST_PROBE[] = () -> begin
            probe_calls[] += 1
            Discovery.fail(
                :INJECTED_SOURCE_VERIFIER_FAILURE,
                "source_verifier",
                "synthetic mandatory-verifier regression",
            )
        end
        error = captured_error(
            () -> Discovery.build_discovery_plan(envelopes, cutoff),
        )
        @test error.code == :INJECTED_SOURCE_VERIFIER_FAILURE
        @test probe_calls[] == 1
        error = captured_error(
            () -> Discovery.validate_discovery_plan(
                plan,
                envelopes,
                cutoff,
            ),
        )
        @test error.code == :INJECTED_SOURCE_VERIFIER_FAILURE
        @test probe_calls[] == 2
    finally
        Discovery._SOURCE_VERIFICATION_TEST_PROBE[] = prior_probe
    end
end

@testset "Exact endpoint sequence is inert string construction" begin
    release = only(
        Discovery.parse_release_directories(root_body([RELEASE_NEW])),
    )
    @test Discovery.ROOT_DISCOVERY_URL ==
        "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/" *
        "?HistMainId=11&getFiles=false&getDirs=true"
    @test Discovery._directory_id_url(release) ==
        "https://apps.bea.gov/histdata/core/data/UrlPath_getID/" *
        "?UrlPath=%2FInetpub%2Fwwwroot%2Fwebsite%2Fwebsite%2FHistData%2F" *
        "Files%2FReleases%2FFA%5C2098%5CAnnualUpdate_September-1-2099"
    @test Discovery._resolved_path_url("4242") ==
        "https://apps.bea.gov/histdata/core/data/getPath/4242"
    @test Discovery._release_files_url(release) ==
        "https://apps.bea.gov/histdata/core/data/Fea_DisplayChildrenC/" *
        "?HistMainId=11&thePath=%2FInetpub%2Fwwwroot%2Fwebsite%2Fwebsite%2F" *
        "HistData%2FFiles%2FReleases%2FFA%5C2098%5C" *
        "AnnualUpdate_September-1-2099&getFiles=true&getDirs=false"
    error = captured_error(() -> Discovery._resolved_path_url("0042"))
    @test error.code == :NONCANONICAL_DIRECTORY_ID
end

@testset "URL and release boundaries replay the frozen HMI11 grammar" begin
    exported = Set(names(Discovery))
    for unsafe_name in (
            :directory_id_url,
            :official_file_url,
            :release_files_url,
            :resolved_path_url,
            :ReleaseDirectory,
            :DiscoveryPlan,
        )
        @test unsafe_name ∉ exported
    end

    release = only(
        Discovery.parse_release_directories(root_body([RELEASE_NEW])),
    )
    outside = captured_error(
        () -> Discovery._official_file_url(
            release,
            "/outside/Section3All_xls.xlsx",
        ),
    )
    @test outside.code == :INVALID_INTERNAL_PATH

    hmi7_path =
        "/Inetpub/wwwroot/website/website/HistData/Files/Releases/" *
        "GDP_and_PI\\2098\\Q3\\1. Advance_October-1-2098\\" *
        "Section3ALL_xls.xlsx"
    hmi7 = captured_error(
        () -> Discovery._official_file_url(release, hmi7_path),
    )
    @test hmi7.code == :INVALID_INTERNAL_PATH

    forged_release = Discovery.ReleaseDirectory(
        Discovery._CONSTRUCTION_TOKEN,
        RELEASE_NEW,
        2097,
        "AnnualUpdate_September-1-2099",
        "September-1-2099",
        Date(2099, 9, 1),
    )
    forged_url = captured_error(
        () -> Discovery._directory_id_url(forged_release),
    )
    @test forged_url.code == :FORGED_RELEASE_DIRECTORY
    forged_files = captured_error(
        () -> Discovery.parse_release_workbooks(
            files_body(valid_file_paths()),
            forged_release,
        ),
    )
    @test forged_files.code == :FORGED_RELEASE_DIRECTORY
end

@testset "Strict duplicate-safe bounded JSON parser" begin
    parsed = Discovery.parse_exact_json(
        "{\"message\":\"\\ud83d\\ude00\",\"number\":-1.25e+2}",
    )
    @test parsed["message"] == "😀"
    @test parsed["number"] isa Discovery.ExactJSONNumber
    @test parsed["number"].lexeme == "-1.25e+2"

    escaped_duplicate =
        "{\"MainName\":\"Fixed Asset\",\"\\u004dainName\":\"other\"}"
    error = captured_error(() -> Discovery.parse_exact_json(escaped_duplicate))
    @test error.code == :DUPLICATE_JSON_MEMBER

    nested_duplicate = "{\"outer\":{\"a\":1,\"\\u0061\":2}}"
    error = captured_error(() -> Discovery.parse_exact_json(nested_duplicate))
    @test error.code == :DUPLICATE_JSON_MEMBER

    error = captured_error(
        () -> Discovery.parse_exact_json("{\"value\":\"\\ud800\"}"),
    )
    @test error.code == :INVALID_JSON_UNICODE
    error = captured_error(
        () -> Discovery.parse_exact_json("{\"value\":01}"),
    )
    @test error.code == :INVALID_JSON_NUMBER
    error = captured_error(
        () -> Discovery.parse_exact_json(
            repeat("[", Discovery.MAX_JSON_NESTING_DEPTH + 2) *
                "0" *
                repeat("]", Discovery.MAX_JSON_NESTING_DEPTH + 2),
        ),
    )
    @test error.code == :JSON_DEPTH_LIMIT_EXCEEDED
    error = captured_error(
        () -> Discovery.parse_exact_json(
            repeat(" ", Discovery.MAX_JSON_BODY_BYTES + 1),
        ),
    )
    @test error.code == :JSON_BODY_LIMIT_EXCEEDED
    error = captured_error(
        () -> Discovery.parse_exact_json(
            "[" *
                join(fill("0", Discovery.MAX_JSON_ARRAY_ITEMS + 1), ",") *
                "]",
        ),
    )
    @test error.code == :JSON_ARRAY_LIMIT_EXCEEDED
    error = captured_error(
        () -> Discovery.parse_exact_json(
            "{" *
                join(
                [
                    json_string("key$index") * ":null" for
                        index in 1:(Discovery.MAX_JSON_OBJECT_MEMBERS + 1)
                ],
                ",",
            ) *
                "}",
        ),
    )
    @test error.code == :JSON_OBJECT_LIMIT_EXCEEDED
    error = captured_error(
        () -> Discovery.parse_exact_json(
            json_string(repeat("x", Discovery.MAX_JSON_STRING_BYTES + 1)),
        ),
    )
    @test error.code == :JSON_STRING_LIMIT_EXCEEDED
    error = captured_error(
        () -> Discovery.parse_exact_json(
            repeat("1", Discovery.MAX_JSON_NUMBER_BYTES + 1),
        ),
    )
    @test error.code == :JSON_NUMBER_LIMIT_EXCEEDED
    error = captured_error(() -> Discovery.parse_exact_json(Dict("x" => 1)))
    @test error.code == :JSON_BODY_TYPE_MISMATCH
end

@testset "Root schema, annual-update grammar, and cutoff selection" begin
    paths = [
        Discovery.INTERNAL_RELEASE_ROOT,
        Discovery.INTERNAL_RELEASE_ROOT * "\\2097",
        RELEASE_OLD,
        RELEASE_OLD * "\\UND",
        RELEASE_OLD * "\\notes",
        Discovery.INTERNAL_RELEASE_ROOT *
            "\\2098\\SpecialUpdate_September-1-2099",
        Discovery.INTERNAL_RELEASE_ROOT *
            "\\2098\\AnnualUpdate_September-1-2099_notes",
        RELEASE_NEW,
        RELEASE_FUTURE,
    ]
    releases = Discovery.parse_release_directories(root_body(paths))
    @test [release.internal_path for release in releases] ==
        [RELEASE_OLD, RELEASE_NEW, RELEASE_FUTURE]
    @test [release.data_year for release in releases] == [2097, 2098, 2099]
    @test [release.archive_label_date for release in releases] ==
        [Date(2098, 9, 2), Date(2099, 9, 1), Date(2100, 9, 3)]
    selected = Discovery.select_latest_release(releases, Date(2099, 12, 31))
    @test selected.internal_path == RELEASE_NEW

    wrong_main = captured_error(
        () -> Discovery.parse_release_directories(
            root_body(paths; main_name = "Fixed Assets"),
        ),
    )
    @test wrong_main.code == :HMI_IDENTITY_MISMATCH
    wrong_pattern = captured_error(
        () -> Discovery.parse_release_directories(
            root_body(paths; folder_pattern = "FA\\year\\release"),
        ),
    )
    @test wrong_pattern.code == :HMI_IDENTITY_MISMATCH

    unknown_field = replace(
        root_body(paths),
        "}" => ",\"unexpected\":null}";
        count = 1,
    )
    error = captured_error(
        () -> Discovery.parse_release_directories(unknown_field),
    )
    @test error.code == :UNKNOWN_OR_MISSING_FIELDS
    error = captured_error(
        () -> Discovery.parse_release_directories(
            "{\"MainName\":true,\"FolderPattern\":" *
                json_string("FA\\dataYear\\vintage_NewReleaseDate") *
                ",\"FileArray\":[]}",
        ),
    )
    @test error.code == :TYPE_MISMATCH
    error = captured_error(
        () -> Discovery.parse_release_directories(
            "{\"MainName\":1.0,\"FolderPattern\":" *
                json_string("FA\\dataYear\\vintage_NewReleaseDate") *
                ",\"FileArray\":[]}",
        ),
    )
    @test error.code == :TYPE_MISMATCH
    error = captured_error(
        () -> Discovery.parse_release_directories(
            "{\"MainName\":\"Fixed Asset\",\"FolderPattern\":" *
                json_string("FA\\dataYear\\vintage_NewReleaseDate") *
                ",\"FileArray\":{}}",
        ),
    )
    @test error.code == :TYPE_MISMATCH
    error = captured_error(
        () -> Discovery.parse_release_directories(
            root_body([RELEASE_NEW, RELEASE_NEW]),
        ),
    )
    @test error.code == :DUPLICATE_RELEASE_PATH
    error = captured_error(
        () -> Discovery.parse_release_directories(
            root_body([RELEASE_NEW, lowercase(RELEASE_NEW)]),
        ),
    )
    @test error.code == :CASEFOLD_PATH_AMBIGUITY
    error = captured_error(
        () -> Discovery.parse_release_directories(
            root_body(
                [
                    Discovery.INTERNAL_RELEASE_ROOT *
                        "\\2098\\AnnualUpdate_February-30-2099",
                ]
            ),
        ),
    )
    @test error.code == :INVALID_RELEASE_DATE

    tie_path =
        Discovery.INTERNAL_RELEASE_ROOT *
        "\\2096\\AnnualUpdate_September-1-2099"
    tied = Discovery.parse_release_directories(
        root_body([tie_path, RELEASE_NEW]),
    )
    error = captured_error(
        () -> Discovery.select_latest_release(tied, Date(2099, 12, 31)),
    )
    @test error.code == :LATEST_RELEASE_TIE
    error = captured_error(
        () -> Discovery.select_latest_release(releases, Date(2090, 1, 1)),
    )
    @test error.code == :FUTURE_ONLY_RELEASE_CATALOG
end

@testset "Exact path-to-ID and ID-to-path round trip" begin
    @test Discovery.parse_directory_id(id_body()) == "4242"
    @test Discovery.parse_resolved_path(
        reverse_body(RELEASE_NEW),
        "4242",
        RELEASE_NEW,
    ) == RELEASE_NEW

    for bad_id in ("0", "0042", "42x", "-1", "")
        error = captured_error(() -> Discovery.parse_directory_id(id_body(bad_id)))
        @test error.code in (:NONCANONICAL_DIRECTORY_ID, :EMPTY_STRING)
    end
    error = captured_error(
        () -> Discovery.parse_directory_id(
            "[{\"Notes\":null,\"Theid\":true,\"Thepath\":null," *
                "\"DescriptionLong\":null}]",
        ),
    )
    @test error.code == :TYPE_MISMATCH
    error = captured_error(
        () -> Discovery.parse_directory_id(
            "[{\"Notes\":null,\"Theid\":42.0,\"Thepath\":null," *
                "\"DescriptionLong\":null}]",
        ),
    )
    @test error.code == :TYPE_MISMATCH
    error = captured_error(
        () -> Discovery.parse_directory_id(
            "[{\"Notes\":null,\"Theid\":\"42\",\"Thepath\":null," *
                "\"DescriptionLong\":null,\"extra\":null}]",
        ),
    )
    @test error.code == :UNKNOWN_OR_MISSING_FIELDS
    error = captured_error(
        () -> Discovery.parse_resolved_path(
            reverse_body(RELEASE_OLD),
            "4242",
            RELEASE_NEW,
        ),
    )
    @test error.code == :DIRECTORY_REVERSE_MISMATCH
end

@testset "Case-preserving exact-child workbook catalog" begin
    release = only(
        Discovery.parse_release_directories(root_body([RELEASE_NEW])),
    )
    workbooks = Discovery.parse_release_workbooks(
        files_body(valid_file_paths()),
        release,
    )
    @test [workbook.section_id for workbook in workbooks] == ["3", "5", "7"]
    @test [workbook.filename for workbook in workbooks] == [
        "Section3aLl_xls.xlsx",
        "section5ALL_XLS.XLSX",
        "SECTION7All_xls.XlSx",
    ]
    @test all(workbook -> workbook.case_preserved, workbooks)
    @test all(workbook -> !workbook.source_bytes_accessed, workbooks)
    @test all(workbook -> !workbook.source_bytes_verified, workbooks)
    @test first(workbooks).official_locator ==
        "https://apps.bea.gov/HistData/Files/Releases/FA/2098/" *
        "AnnualUpdate_September-1-2099/Section3aLl_xls.xlsx"

    duplicate = valid_file_paths()
    push!(duplicate, RELEASE_NEW * "\\section3all_XLS.XLSX")
    error = captured_error(
        () -> Discovery.parse_release_workbooks(files_body(duplicate), release),
    )
    @test error.code == :CASEFOLD_FILENAME_AMBIGUITY

    missing = filter(path -> !occursin(r"(?i)section5", path), valid_file_paths())
    error = captured_error(
        () -> Discovery.parse_release_workbooks(files_body(missing), release),
    )
    @test error.code == :MISSING_MAIN_SECTION

    extra = valid_file_paths()
    push!(extra, RELEASE_NEW * "\\Section4All_xls.xlsx")
    error = captured_error(
        () -> Discovery.parse_release_workbooks(files_body(extra), release),
    )
    @test error.code == :EXTRA_MAIN_SECTION

    old_format = valid_file_paths()
    old_format[3] = RELEASE_NEW * "\\Section3ALL_xls.xls"
    error = captured_error(
        () -> Discovery.parse_release_workbooks(files_body(old_format), release),
    )
    @test error.code == :UNSUPPORTED_WORKBOOK_FORMAT

    traversal = valid_file_paths()
    traversal[3] = RELEASE_NEW * "\\..\\Section3All_xls.xlsx"
    error = captured_error(
        () -> Discovery.parse_release_workbooks(files_body(traversal), release),
    )
    @test error.code == :PATH_TRAVERSAL

    nested = valid_file_paths()
    nested[3] = RELEASE_NEW * "\\nested\\Section3All_xls.xlsx"
    error = captured_error(
        () -> Discovery.parse_release_workbooks(files_body(nested), release),
    )
    @test error.code == :NONEXACT_RELEASE_CHILD

    other_release = valid_file_paths(RELEASE_OLD)
    error = captured_error(
        () -> Discovery.parse_release_workbooks(
            files_body(other_release),
            release,
        ),
    )
    @test error.code == :NOT_SELECTED_RELEASE_CHILD

    unknown = replace(
        files_body(valid_file_paths()),
        "}" => ",\"unknown\":null}";
        count = 1,
    )
    error = captured_error(
        () -> Discovery.parse_release_workbooks(unknown, release),
    )
    @test error.code == :UNKNOWN_OR_MISSING_FIELDS

    error = captured_error(
        () -> Discovery._official_file_url(
            release,
            Discovery.INTERNAL_RELEASE_ROOT * "\\..\\escape.xlsx",
        ),
    )
    @test error.code == :PATH_TRAVERSAL
end

@testset "Closed selectors reject profile, table, line, and sheet drift" begin
    base = profile_document()
    mutations = [
        ("profile_id", "renamed_profile"),
        ("table_name", "FAAt999"),
        ("line_numbers", "1,2"),
        ("candidate_sheet_name", "FAAt301ESI"),
        ("selector", "BEA:FixedAssets:TableName=FAAt301ESI:Frequency=A:Year=2025:LineNumber=1"),
    ]
    for (field, replacement) in mutations
        changed = deepcopy(base)
        changed["profiles"][1][field] = replacement
        error = captured_error(
            () -> Discovery._validate_profiles(changed["profiles"]),
        )
        @test error.code == :PROFILE_MAPPING_DRIFT
    end

    extra_field = deepcopy(base)
    extra_field["profiles"][1]["unknown"] = "x"
    error = captured_error(
        () -> Discovery._validate_profiles(extra_field["profiles"]),
    )
    @test error.code == :UNKNOWN_OR_MISSING_FIELDS

    reordered = deepcopy(base)
    reordered["profiles"][1], reordered["profiles"][2] =
        reordered["profiles"][2], reordered["profiles"][1]
    error = captured_error(
        () -> Discovery._validate_profiles(reordered["profiles"]),
    )
    @test error.code == :PROFILE_MAPPING_DRIFT
end

@testset "Bool and Float aliases are rejected for integer controls" begin
    for alias in (true, false, 11.0)
        error = captured_error(
            () -> Discovery._expect_int(alias, "synthetic.integer"),
        )
        @test error.code == :TYPE_MISMATCH
    end

    profile = profile_document()
    for alias in (true, 11.0)
        changed = deepcopy(profile)
        changed["hmi11"]["history_main_id"] = alias
        Discovery.stamp_profile_content_sha256!(changed)
        error = captured_error(
            () -> Discovery.validate_profile_document(changed),
        )
        @test error.code in (:PROFILE_IDENTITY_CHANGED, :TYPE_MISMATCH)
    end
end

@testset "Coordinated self-restamps cannot raise or rewrite the contract" begin
    base = profile_document()

    elevated = deepcopy(base)
    elevated["artifact"]["status"] = "READY"
    Discovery.stamp_profile_content_sha256!(elevated)
    @test elevated["artifact"]["content_sha256"] !=
        base["artifact"]["content_sha256"]
    error = captured_error(
        () -> Discovery.validate_profile_document(elevated),
    )
    @test error.code in (:GATE_ELEVATION, :PROFILE_IDENTITY_CHANGED)

    rebound = deepcopy(base)
    rebound["source_bindings"][1]["physical_sha256"] = repeat("a", 64)
    Discovery.stamp_profile_content_sha256!(rebound)
    error = captured_error(
        () -> Discovery.validate_profile_document(rebound),
    )
    @test error.code in (:SOURCE_BINDING_DRIFT, :PROFILE_IDENTITY_CHANGED)

    gate = deepcopy(base)
    gate["gates"]["origin_admission_allowed"] = true
    Discovery.stamp_profile_content_sha256!(gate)
    error = captured_error(
        () -> Discovery.validate_profile_document(gate),
    )
    @test error.code in (:GATE_ELEVATION, :PROFILE_IDENTITY_CHANGED)
end

@testset "Response envelopes reject swaps, replays, and broken lineage" begin
    cutoff = Date(2099, 12, 31)

    missing = valid_response_envelopes()[1:3]
    error = captured_error(
        () -> Discovery.build_discovery_plan(missing, cutoff),
    )
    @test error.code == :RESPONSE_ENVELOPE_CARDINALITY_MISMATCH

    unknown = deepcopy(valid_response_envelopes())
    unknown[1]["unknown"] = nothing
    error = captured_error(
        () -> Discovery.build_discovery_plan(unknown, cutoff),
    )
    @test error.code == :UNKNOWN_OR_MISSING_FIELDS

    string_body = deepcopy(valid_response_envelopes())
    string_body[1]["body"] = String(string_body[1]["body"])
    error = captured_error(
        () -> Discovery.build_discovery_plan(string_body, cutoff),
    )
    @test error.code == :TYPE_MISMATCH

    bool_index = deepcopy(valid_response_envelopes())
    bool_index[1]["sequence_index"] = true
    error = captured_error(
        () -> Discovery.build_discovery_plan(bool_index, cutoff),
    )
    @test error.code == :TYPE_MISMATCH

    reordered = deepcopy(valid_response_envelopes())
    reordered[2], reordered[3] = reordered[3], reordered[2]
    error = captured_error(
        () -> Discovery.build_discovery_plan(reordered, cutoff),
    )
    @test error.code == :RESPONSE_ORDER_MISMATCH

    role_swap = deepcopy(valid_response_envelopes())
    role_swap[2]["response_role"], role_swap[3]["response_role"] =
        role_swap[3]["response_role"], role_swap[2]["response_role"]
    error = captured_error(
        () -> Discovery.build_discovery_plan(role_swap, cutoff),
    )
    @test error.code == :RESPONSE_ROLE_MISMATCH

    uri_swap = deepcopy(valid_response_envelopes())
    for key in ("requested_uri", "final_effective_uri")
        uri_swap[2][key], uri_swap[4][key] =
            uri_swap[4][key], uri_swap[2][key]
    end
    error = captured_error(
        () -> Discovery.build_discovery_plan(uri_swap, cutoff),
    )
    @test error.code == :REQUEST_URI_LINEAGE_MISMATCH

    final_uri_replay = deepcopy(valid_response_envelopes())
    final_uri_replay[4]["final_effective_uri"] =
        final_uri_replay[1]["final_effective_uri"]
    error = captured_error(
        () -> Discovery.build_discovery_plan(final_uri_replay, cutoff),
    )
    @test error.code == :FINAL_URI_LINEAGE_MISMATCH

    body_swap = deepcopy(valid_response_envelopes())
    body_swap[2]["body"], body_swap[3]["body"] =
        body_swap[3]["body"], body_swap[2]["body"]
    rehash_body!(body_swap[2])
    rehash_body!(body_swap[3])
    rechain!(body_swap)
    error = captured_error(
        () -> Discovery.build_discovery_plan(body_swap, cutoff),
    )
    @test error.code == :TYPE_MISMATCH

    body_replay = deepcopy(valid_response_envelopes())
    body_replay[4]["body"] = copy(body_replay[1]["body"])
    rehash_body!(body_replay[4])
    rechain!(body_replay)
    error = captured_error(
        () -> Discovery.build_discovery_plan(body_replay, cutoff),
    )
    @test error.code == :RESPONSE_BODY_REPLAY

    body_hash_mismatch = deepcopy(valid_response_envelopes())
    body_hash_mismatch[2]["body_sha256"] = repeat("a", 64)
    error = captured_error(
        () -> Discovery.build_discovery_plan(body_hash_mismatch, cutoff),
    )
    @test error.code == :RESPONSE_BODY_HASH_MISMATCH

    path_replay = deepcopy(valid_response_envelopes())
    path_replay[3]["selected_release_internal_path"] = RELEASE_OLD
    error = captured_error(
        () -> Discovery.build_discovery_plan(path_replay, cutoff),
    )
    @test error.code == :SELECTED_PATH_LINEAGE_MISMATCH

    id_replay = deepcopy(valid_response_envelopes())
    id_replay[4]["directory_id"] = "4241"
    error = captured_error(
        () -> Discovery.build_discovery_plan(id_replay, cutoff),
    )
    @test error.code == :DIRECTORY_ID_LINEAGE_MISMATCH

    chain_break = deepcopy(valid_response_envelopes())
    chain_break[4]["prior_response_body_sha256"] = repeat("b", 64)
    error = captured_error(
        () -> Discovery.build_discovery_plan(chain_break, cutoff),
    )
    @test error.code == :RESPONSE_CHAIN_MISMATCH
end

@testset "Full plan replay rejects a forged READY result" begin
    cutoff = Date(2099, 12, 31)
    envelopes = valid_response_envelopes()
    plan = Discovery.build_discovery_plan(envelopes, cutoff)
    forged_gates = copy(plan.gates)
    forged_gates["origin_admission_allowed"] = true
    forged = Discovery.DiscoveryPlan(
        Discovery._CONSTRUCTION_TOKEN,
        "READY",
        plan.role,
        plan.capture_cutoff,
        plan.release,
        plan.directory_id,
        true,
        copy(plan.response_bindings),
        copy(plan.workbooks),
        copy(plan.profiles),
        forged_gates,
        true,
        true,
    )
    error = captured_error(
        () -> Discovery.validate_discovery_plan(
            forged,
            envelopes,
            cutoff,
        ),
    )
    @test error.code == :PLAN_REPLAY_MISMATCH
end

@testset "Synthetic end-to-end plan remains permanently nonadmitting" begin
    envelopes = valid_response_envelopes()
    plan = Discovery.build_discovery_plan(
        envelopes,
        Date(2099, 12, 31),
    )
    replayed = Discovery.validate_discovery_plan(
        plan,
        envelopes,
        Date(2099, 12, 31),
    )
    @test plan.status == "CANNOT_RUN"
    @test plan.role == "DISCOVERY_MECHANICS_ONLY"
    @test plan.capture_cutoff == Date(2099, 12, 31)
    @test plan.release.internal_path == RELEASE_NEW
    @test plan.directory_id == "4242"
    @test plan.metadata_response_lineage_replayed
    @test length(plan.response_bindings) == 4
    @test [binding.sequence_index for binding in plan.response_bindings] ==
        collect(1:4)
    @test [binding.response_role for binding in plan.response_bindings] ==
        collect(Discovery.RESPONSE_ROLES)
    @test plan.response_bindings[2].prior_response_body_sha256 ==
        plan.response_bindings[1].response_body_sha256
    @test plan.response_bindings[3].selected_release_internal_path ==
        RELEASE_NEW
    @test plan.response_bindings[3].directory_id == "4242"
    @test length(plan.workbooks) == 3
    @test length(plan.profiles) == 8
    @test count(profile -> profile.section_id == "3", plan.profiles) == 3
    @test count(profile -> profile.section_id == "5", plan.profiles) == 3
    @test count(profile -> profile.section_id == "7", plan.profiles) == 2
    @test all(profile -> !profile.sheet_verified, plan.profiles)
    @test all(profile -> !profile.contents_verified, plan.profiles)
    @test all(profile -> !profile.units_verified, plan.profiles)
    @test all(profile -> !profile.bytes_verified, plan.profiles)
    @test all(value -> value === false, values(plan.gates))
    @test !plan.origin_admissible
    @test !plan.ready
    @test replayed.status == plan.status
end
