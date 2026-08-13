using SHA
using TOML
using Test

const ARTIFACT_DIR = @__DIR__
const MODULE_PATH = joinpath(ARTIFACT_DIR, "USCensusStructuralProfileV1.jl")
const PROFILE_PATH = joinpath(ARTIFACT_DIR, "census_structural_profile_v1.toml")

include(MODULE_PATH)
const CensusProfile = USCensusStructuralProfileV1

function captured_error(function_to_run, expected_code = nothing)
    caught = try
        function_to_run()
        nothing
    catch error
        error
    end
    @test caught isa CensusProfile.CensusProfileError
    if caught isa CensusProfile.CensusProfileError && expected_code !== nothing
        @test caught.code == expected_code
    end
    return caught
end

function profile_document()
    return TOML.parsefile(PROFILE_PATH)
end

function profile_by_id(profile, profile_id)
    return only(entry for entry in profile["profiles"] if entry["profile_id"] == profile_id)
end

function aies_row(entry; naics = "31")
    row = Dict{String, String}(field => "" for field in entry["logical_fields"])
    row["GEO_ID"] = "0100000US"
    row["INDLEVEL"] = "2"
    row["NAICS"] = naics
    row["NAICS_LABEL"] = "Synthetic NAICS label"
    row["NAME"] = "Synthetic United States label"
    row["SECTOR"] = first(naics, min(2, length(naics)))
    row["YEAR"] = "2023"
    if haskey(row, "TAXSTAT")
        row["TAXSTAT"] = "00"
        row["TAXSTAT_LABEL"] = "Synthetic tax status"
    end
    if haskey(row, "TYPOP")
        row["TYPOP"] = "001"
        row["TYPOP_LABEL"] = "Synthetic type of operation"
    end
    haskey(row, "INDGROUP") && (row["INDGROUP"] = "44-45")
    haskey(row, "SUBSECTOR") && (row["SUBSECTOR"] = "44")
    for field in entry["measure_value_fields"]
        row[field] = "100"
    end
    for field in entry["measure_cv_fields"]
        row[field] = "2.5"
    end
    return row
end

const SIZE_VALUES = Dict(
    "01" => 210,
    "02" => 10,
    "03" => 20,
    "04" => 30,
    "05" => 60,
    "06" => 40,
    "07" => 50,
    "08" => 150,
    "09" => 60,
)

function susb_rows(; state = "00", naics = "311111")
    rows = Vector{Dict{String, String}}()
    for code in CensusProfile.SUSB_SIZE_CODES
        base = SIZE_VALUES[code]
        push!(
            rows,
            Dict{String, String}(
                "STATE" => state,
                "NAICS" => naics,
                "ENTRSIZE" => code,
                "FIRM" => string(base),
                "ESTB" => string(2 * base),
                "EMPL" => string(3 * base),
                "EMPLFL_R" => "",
                "EMPLFL_N" => "",
                "PAYR" => string(4 * base),
                "PAYRFL_N" => "",
                "RCPT" => string(5 * base),
                "RCPTFL_N" => "",
                "STATEDSCR" => "Synthetic state $state",
                "NAICSDSCR" => "Synthetic industry $naics",
                "ENTRSIZEDSCR" => "Synthetic size $code",
            ),
        )
    end
    return rows
end

function fixture_bytes(header, rows)
    lines = [join(header, '\t')]
    for row in rows
        push!(lines, join((row[field] for field in header), '\t'))
    end
    return Vector{UInt8}(codeunits(join(lines, '\n') * "\n"))
end

function fixtures_and_rows()
    profile = CensusProfile.load_profile()
    fixtures = Dict{String, Vector{UInt8}}()
    rows = Dict{String, Vector{Dict{String, String}}}()
    for entry in profile["profiles"]
        profile_id = entry["profile_id"]
        profile_rows = if profile_id == "susb_employer_enterprises"
            susb_rows()
        else
            [aies_row(entry; naics = entry["product_code"][5:6])]
        end
        rows[profile_id] = profile_rows
        fixtures[profile_id] = fixture_bytes(entry["logical_fields"], profile_rows)
    end
    return profile, fixtures, rows
end

function replace_fixture(fixtures, profile_id, entry, rows)
    copy = deepcopy(fixtures)
    copy[profile_id] = fixture_bytes(entry["logical_fields"], rows)
    return copy
end

function contains_forbidden_policy_container(value)
    value isa Regex && return true
    value isa AbstractArray && return true
    value isa AbstractDict && return true
    value isa AbstractSet && return true
    if value isa Tuple || value isa NamedTuple
        return any(contains_forbidden_policy_container, value)
    end
    return false
end

@testset "Frozen profile and exact source pins" begin
    profile = CensusProfile.load_profile()
    @test profile["artifact"]["status"] == "CANNOT_RUN"
    @test profile["artifact"]["role"] == "LOGICAL_SCHEMA_MECHANICS_ONLY"
    @test profile["artifact"]["content_sha256"] ==
        "c661bc84b0b9f9ee3c6ff28982721a9a9dacd14d6e73cc6859db54737429b491"
    @test CensusProfile.profile_content_sha256(profile) ==
        profile["artifact"]["content_sha256"]
    @test CensusProfile.sha256_hex(read(MODULE_PATH)) ==
        "e0a683586a44d0cba8129d7494c49e00e1606453c46e94b37f60d4804f450f68"
    @test CensusProfile.sha256_hex(read(PROFILE_PATH)) ==
        "512b35c1d80c9d6c8b387cdd68affd4a1ae92b1dc040c04aacae8545b47ef157"
    @test profile["contract"]["permanent_nonadmitting"]
    @test profile["contract"]["synthetic_fixtures_only"]
    @test !profile["contract"]["synthetic_fixture_attributed_to_provider"]
    @test profile["contract"]["resolved_logical_schema_count"] == 6
    @test profile["contract"]["qualified_physical_layout_count"] == 0
    @test all(value -> value === false, values(profile["gates"]))
    @test all(
        value -> value === false,
        (
            value for (key, value) in profile["physical_evidence"]
                if key != "status"
        ),
    )
    @test CensusProfile.EXPECTED_PROFILE_SPECS isa Tuple
    @test all(spec -> spec.logical_fields isa Tuple, CensusProfile.EXPECTED_PROFILE_SPECS)
    @test CensusProfile.EXPECTED_SOURCE_BINDINGS isa Tuple

    bindings = Dict(binding["binding_id"] => binding for binding in profile["source_bindings"])
    @test bindings["prospective_v2_module"]["physical_sha256"] ==
        "435df6c4b4de879c0f24d3f9bb9f7504fc6172ae34e94db8cb6ba84282d6e379"
    @test bindings["prospective_v2_contract"]["physical_sha256"] ==
        "b24ff0c40172d2a23991fbe75c2fe42c6ba6c6c1f5fd46d079ac6d51429bf98f"
    @test bindings["common_origin_v4_module"]["physical_sha256"] ==
        "0f4c248950ebee59d1e6b5882db6516cbb539f9e54c7dfbb6b53fe0f7a5f6b4e"
    @test bindings["common_origin_v4_policy"]["physical_sha256"] ==
        "84e74d236f0e0ac781a482b996be95fceefe56f2a349be089b51054c3edd8834"
    @test bindings["current_inventory"]["physical_sha256"] ==
        "110b4448db0b49e95cbc2fe1cf7019f6b877b3f391c6069a81c2e7c3c2a086ae"
    @test bindings["sources_toml"]["physical_sha256"] ==
        "41b2bf73b92fb0cf9d9e02ae836beb91d07cd6a3bd20ecf668882350c86f23c9"
    @test bindings["us_pipeline"]["physical_sha256"] ==
        "ce4d8138a1c07fdc9509d7560f307f226dc314eb0a4394270ef1e1014b9ca14d"
    @test CensusProfile._verify_source_bindings(profile["source_bindings"])
end

@testset "Six exact logical schemas and ceilings" begin
    profile = CensusProfile.load_profile()
    profiles = Dict(entry["product_code"] => entry for entry in profile["profiles"])
    @test length(profiles) == 6
    @test length(profiles["AIES00INV"]["logical_fields"]) == 21
    @test length(profiles["AIES31INV"]["logical_fields"]) == 21
    @test length(profiles["AIES42INV"]["logical_fields"]) == 23
    @test length(profiles["AIES44INV"]["logical_fields"]) == 23
    @test length(profiles["AIES51INV"]["logical_fields"]) == 27
    @test profiles["AIES00INV"]["key_fields"] ==
        ["GEO_ID", "YEAR", "NAICS", "TYPOP", "TAXSTAT"]
    @test profiles["AIES42INV"]["key_fields"] ==
        ["GEO_ID", "YEAR", "NAICS", "TYPOP"]
    @test profiles["AIES51INV"]["key_fields"] ==
        ["GEO_ID", "YEAR", "NAICS", "TAXSTAT"]
    @test profiles["AIES31INV"]["key_fields"] == ["GEO_ID", "YEAR", "NAICS"]
    @test profiles["AIES44INV"]["key_fields"] == ["GEO_ID", "YEAR", "NAICS"]
    @test profiles["SUSB_2022_US_STATE_6DIGIT_NAICS"]["logical_fields"] ==
        collect(CensusProfile.SUSB_FIELDS)
    @test profiles["SUSB_2022_US_STATE_6DIGIT_NAICS"]["archive_filename"] ==
        "us_state_6digitnaics_2022.txt"
    @test profile["susb"]["all_published_size_codes"] == collect(CensusProfile.SUSB_SIZE_CODES)
    @test profile["susb"]["all_published_codes_means_retain_not_sum"]
    @test profile["susb"]["firm_interindustry_additivity"] ==
        "PROHIBITED_MULTI_INDUSTRY_ENTERPRISE_DOUBLE_COUNT_RISK"
    @test !profile["susb"]["complete_provider_flag_vocabulary_resolved"]
    @test !profile["susb"]["physical_2022_emplfl_r_column_presence_resolved"]
    @test Set(profile["aies"]["value_publication_flag_tokens"]) == Set(["", "D", "N", "S", "Z"])
    @test Set(profile["aies"]["cv_publication_flag_tokens"]) == Set(["", "v", "w"])
end

@testset "Mandatory source verification has no public bypass" begin
    profile, fixtures, _ = fixtures_and_rows()
    public_functions = (
        CensusProfile.load_profile,
        CensusProfile.validate_profile_document,
        CensusProfile.parse_logical_fixture,
        CensusProfile.build_structural_result,
        CensusProfile.validate_structural_result,
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
    bypass_build = try
        CensusProfile.build_structural_result(fixtures; verify_sources = false)
        nothing
    catch error
        error
    end
    @test bypass_build isa MethodError
    aies_id = "aies00inv_2023_economy_wide"
    bypass_parse = try
        CensusProfile.parse_logical_fixture(
            aies_id,
            fixtures[aies_id];
            verify_sources = false,
        )
        nothing
    catch error
        error
    end
    @test bypass_parse isa MethodError

    changed_binding = deepcopy(profile["source_bindings"])
    changed_binding[1]["physical_sha256"] = repeat("0", 64)
    captured_error(
        () -> CensusProfile._verify_source_bindings(changed_binding),
        :SOURCE_BINDING_DRIFT,
    )
end

@testset "Exported profile validation is recursively TOML-type exact" begin
    original = profile_document()
    semantic_hash = CensusProfile.profile_content_sha256(original)
    collisions = Any[]

    attacked = deepcopy(original)
    attacked["artifact"]["status"] = SubString("xCANNOT_RUN", 2)
    push!(collisions, attacked)

    attacked = deepcopy(original)
    attacked["profiles"] = view(attacked["profiles"], :)
    push!(collisions, attacked)

    push!(collisions, IdDict{String, Any}(original))

    attacked = deepcopy(original)
    attacked["aies"]["common_structural_fields"] =
        Any[attacked["aies"]["common_structural_fields"]...]
    push!(collisions, attacked)

    attacked = deepcopy(original)
    attacked["profiles"] = Dict{String, Any}[attacked["profiles"]...]
    push!(collisions, attacked)

    attacked = deepcopy(original)
    attacked["contract"]["resolved_logical_schema_count"] = Int128(6)
    push!(collisions, attacked)

    for collision in collisions
        @test CensusProfile.profile_content_sha256(collision) == semantic_hash
        captured_error(
            () -> CensusProfile.validate_profile_document(collision),
            :PROFILE_CONCRETE_TYPE,
        )
    end

    attacked = deepcopy(original)
    attacked["contract"]["resolved_logical_schema_count"] = true
    captured_error(
        () -> CensusProfile.validate_profile_document(attacked),
        :PROFILE_CONCRETE_TYPE,
    )

    attacked = deepcopy(original)
    attacked["contract"]["resolved_logical_schema_count"] = 6.0
    captured_error(
        () -> CensusProfile.validate_profile_document(attacked),
        :PROFILE_CONCRETE_TYPE,
    )

    attacked = deepcopy(original)
    attacked["contract"]["permanent_nonadmitting"] = 1
    captured_error(
        () -> CensusProfile.validate_profile_document(attacked),
        :PROFILE_CONCRETE_TYPE,
    )
end

@testset "Persistent policy resists ordinary Regex field swaps" begin
    module_values = [
        getfield(CensusProfile, name) for
            name in names(CensusProfile; all = true, imported = false) if isdefined(CensusProfile, name)
    ]
    @test !any(value -> value isa Regex, module_values)
    @test !any(value -> value isa AbstractArray, module_values)
    @test !any(value -> value isa AbstractDict, module_values)
    @test !any(value -> value isa AbstractSet, module_values)

    uppercase_policy_values = Any[]
    for name in names(CensusProfile; all = true, imported = false)
        text = String(name)
        bytes = codeunits(text)
        is_policy_name = !isempty(bytes) && all(bytes) do byte
            UInt8('A') <= byte <= UInt8('Z') || UInt8('0') <= byte <= UInt8('9') ||
                byte == UInt8('_')
        end
        is_policy_name && push!(uppercase_policy_values, getfield(CensusProfile, name))
    end
    @test !isempty(uppercase_policy_values)
    @test !any(contains_forbidden_policy_container, uppercase_policy_values)
    @test !isdefined(CensusProfile, :HASH_PATTERN)
    @test !isdefined(CensusProfile, :DECIMAL_PATTERN)
    @test !isdefined(CensusProfile, :NONNEGATIVE_DECIMAL_PATTERN)
    @test !isdefined(CensusProfile, :NONNEGATIVE_INTEGER_PATTERN)

    strict_matcher = r"^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"
    permissive_matcher = r".*"
    for field in fieldnames(Regex)
        strict_value = getfield(strict_matcher, field)
        permissive_value = getfield(permissive_matcher, field)
        setfield!(strict_matcher, field, permissive_value)
        setfield!(permissive_matcher, field, strict_value)
    end
    @test occursin(strict_matcher, "NaN")

    profile, fixtures, rows = fixtures_and_rows()
    profile_id = "aies31inv_2023_manufacturing_valuation"
    entry = profile_by_id(profile, profile_id)
    changed_rows = deepcopy(rows[profile_id])
    changed_rows[1][entry["measure_value_fields"][1]] = "NaN"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], changed_rows),
        ),
        :AIES_VALUE_TYPE,
    )
    @test CensusProfile.parse_logical_fixture(profile_id, fixtures[profile_id])["row_count"] == 1

    baseline = CensusProfile.build_structural_result(fixtures)
    poisoned = CensusProfile.build_structural_result(fixtures)
    poisoned["status"] = "READY"
    poisoned["gates"]["model_input_allowed"] = true
    poisoned["tables"][1]["rows"][1]["YEAR"] = "2024"
    poisoned["susb_national_total_projection"]["rows"][1]["FIRM"] = "999999"
    fresh = CensusProfile.build_structural_result(fixtures)
    @test CensusProfile._deep_exact(fresh, baseline)
    @test fresh !== baseline
    @test fresh["gates"] !== baseline["gates"]
    @test fresh["tables"] !== baseline["tables"]
    @test fresh["status"] == "CANNOT_RUN"
    @test all(value -> value === false, values(fresh["gates"]))
end

@testset "Valid synthetic logical fixture build and exact replay" begin
    profile, fixtures, _ = fixtures_and_rows()
    result = CensusProfile.build_structural_result(fixtures)
    @test CensusProfile.validate_structural_result(result, fixtures) === result
    @test result["status"] == "CANNOT_RUN"
    @test result["role"] == "LOGICAL_SCHEMA_MECHANICS_ONLY"
    @test result["profile_content_sha256"] == profile["artifact"]["content_sha256"]
    @test !result["synthetic_fixtures_attributed_to_provider"]
    @test result["profile_count"] == 6
    @test result["resolved_logical_schema_count"] == 6
    @test result["qualified_physical_layout_count"] == 0
    @test result["provider_physical_layouts_unresolved"]
    @test all(value -> value === false, values(result["gates"]))
    @test length(result["tables"]) == 6
    @test all(table -> !table["provider_physical_layout_claimed"], result["tables"])
    @test all(table -> !table["synthetic_fixture_attributed_to_provider"], result["tables"])
    @test length(result["susb_overlap_checks"]) == 15
    @test all(check -> check["status"] == "VERIFIED_EXACT", result["susb_overlap_checks"])
    @test result["susb_all_size_codes_retained"] == collect(CensusProfile.SUSB_SIZE_CODES)
    projection = result["susb_national_total_projection"]
    @test projection["selection"] == "STATE=00_AND_ENTRSIZE=01"
    @test projection["input_row_count"] == 9
    @test projection["projection_row_count"] == 1
    @test projection["rows"][1]["STATE"] == "00"
    @test projection["rows"][1]["ENTRSIZE"] == "01"
    @test projection["content_sha256"] == CensusProfile._canonical_sha256(
        Dict(key => value for (key, value) in projection if key != "content_sha256"),
    )
    @test result["content_sha256"] == CensusProfile._canonical_sha256(
        Dict(key => value for (key, value) in result if key != "content_sha256"),
    )
end

@testset "AIES publication states remain typed and never zero-filled" begin
    profile, fixtures, rows = fixtures_and_rows()
    profile_id = "aies00inv_2023_economy_wide"
    entry = profile_by_id(profile, profile_id)
    value_field = entry["measure_value_fields"][1]
    flag_field = entry["measure_value_flag_fields"][1]
    for token in ("D", "N", "S", "Z")
        changed_rows = deepcopy(rows[profile_id])
        changed_rows[1][flag_field] = token
        changed_rows[1][value_field] = token in ("D", "N") ? "" : "0"
        bytes = fixture_bytes(entry["logical_fields"], changed_rows)
        table = CensusProfile.parse_logical_fixture(profile_id, bytes)
        state = table["row_states"][1][value_field]
        @test state["publication_state"] == "PUBLICATION_STATE_" * token
        @test !state["model_numeric_allowed"]
        @test state["zero_fill_forbidden"]
        @test state["raw_value"] == changed_rows[1][value_field]
    end
    cv_field = entry["measure_cv_fields"][1]
    cv_flag_field = entry["measure_cv_flag_fields"][1]
    for (token, value) in (("v", "30.0"), ("w", "60.9"))
        changed_rows = deepcopy(rows[profile_id])
        changed_rows[1][cv_flag_field] = token
        changed_rows[1][cv_field] = value
        bytes = fixture_bytes(entry["logical_fields"], changed_rows)
        table = CensusProfile.parse_logical_fixture(profile_id, bytes)
        state = table["row_states"][1][cv_field]
        @test state["publication_state"] == "PUBLICATION_STATE_" * token
        @test !state["model_numeric_allowed"]
        @test state["raw_value"] == value
    end

    bad_rows = deepcopy(rows[profile_id])
    bad_rows[1][flag_field] = "X"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], bad_rows),
        ),
        :AIES_VALUE_FLAG,
    )
    bad_rows = deepcopy(rows[profile_id])
    bad_rows[1][value_field] = "NaN"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], bad_rows),
        ),
        :AIES_VALUE_TYPE,
    )
    bad_rows = deepcopy(rows[profile_id])
    bad_rows[1][cv_field] = "-1"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], bad_rows),
        ),
        :AIES_CV_TYPE,
    )
end

@testset "AIES dimensions close key collisions" begin
    profile, fixtures, rows = fixtures_and_rows()
    for (profile_id, differentiating_field, changed_value) in (
            ("aies00inv_2023_economy_wide", "TAXSTAT", "01"),
            ("aies42inv_2023_wholesale_valuation", "TYPOP", "002"),
            ("aies51inv_2023_information_stages", "TAXSTAT", "01"),
        )
        entry = profile_by_id(profile, profile_id)
        two_rows = deepcopy(rows[profile_id])
        second = deepcopy(two_rows[1])
        second[differentiating_field] = changed_value
        label = differentiating_field * "_LABEL"
        haskey(second, label) && (second[label] = "Synthetic distinct label")
        push!(two_rows, second)
        table = CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], two_rows),
        )
        @test table["row_count"] == 2
        @test length(Set(table["row_key_sha256"])) == 2
    end

    profile_id = "aies31inv_2023_manufacturing_valuation"
    entry = profile_by_id(profile, profile_id)
    duplicate_rows = [deepcopy(rows[profile_id][1]), deepcopy(rows[profile_id][1])]
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], duplicate_rows),
        ),
        :FIXTURE_DUPLICATE_KEY,
    )
end

@testset "UTF-8, header, row-width, and type attacks fail closed" begin
    profile, fixtures, rows = fixtures_and_rows()
    profile_id = "aies31inv_2023_manufacturing_valuation"
    entry = profile_by_id(profile, profile_id)
    valid = fixtures[profile_id]

    invalid_utf8 = copy(valid)
    invalid_utf8[1] = 0xff
    captured_error(
        () -> CensusProfile.parse_logical_fixture(profile_id, invalid_utf8),
        :FIXTURE_UTF8,
    )
    captured_error(
        () -> CensusProfile.parse_logical_fixture(profile_id, vcat(UInt8[0xef, 0xbb, 0xbf], valid)),
        :FIXTURE_BOM,
    )
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            Vector{UInt8}(codeunits(replace(String(copy(valid)), "\n" => "\r\n"))),
        ),
        :FIXTURE_NEWLINE,
    )
    captured_error(
        () -> CensusProfile.parse_logical_fixture(profile_id, valid[1:(end - 1)]),
        :FIXTURE_TERMINATOR,
    )
    with_control = copy(valid)
    insert!(with_control, findfirst(==(0x0a), with_control) + 1, 0x00)
    captured_error(
        () -> CensusProfile.parse_logical_fixture(profile_id, with_control),
        :FIXTURE_CONTROL,
    )
    with_blank = Vector{UInt8}(codeunits(replace(String(copy(valid)), "\n" => "\n\n"; count = 1)))
    captured_error(
        () -> CensusProfile.parse_logical_fixture(profile_id, with_blank),
        :FIXTURE_BLANK_LINE,
    )

    duplicate_header = copy(entry["logical_fields"])
    duplicate_header[end] = duplicate_header[1]
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(duplicate_header, rows[profile_id]),
        ),
        :FIXTURE_DUPLICATE_HEADER,
    )
    reordered_header = copy(entry["logical_fields"])
    reordered_header[1], reordered_header[2] = reordered_header[2], reordered_header[1]
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(reordered_header, rows[profile_id]),
        ),
        :FIXTURE_HEADER,
    )
    extra_header = vcat(entry["logical_fields"], ["EXTRA"])
    extra_row = deepcopy(rows[profile_id][1])
    extra_row["EXTRA"] = "x"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(extra_header, [extra_row]),
        ),
        :FIXTURE_HEADER,
    )
    narrow_row = split(String(copy(valid)), '\n'; keepempty = true)
    cells = split(narrow_row[2], '\t'; keepempty = true)
    pop!(cells)
    narrow_row[2] = join(cells, '\t')
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            Vector{UInt8}(codeunits(join(narrow_row, '\n'))),
        ),
        :FIXTURE_ROW_WIDTH,
    )
    whitespace_rows = deepcopy(rows[profile_id])
    whitespace_rows[1]["NAICS_LABEL"] = " leading"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], whitespace_rows),
        ),
        :FIXTURE_FIELD_WHITESPACE,
    )
    control_rows = deepcopy(rows[profile_id])
    control_rows[1]["NAICS_LABEL"] = "Synthetic\u0085label"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], control_rows),
        ),
        :FIXTURE_FIELD_CONTROL,
    )
    year_rows = deepcopy(rows[profile_id])
    year_rows[1]["YEAR"] = "2023.0"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], year_rows),
        ),
        :AIES_YEAR,
    )
    dimension_rows = deepcopy(rows[profile_id])
    dimension_rows[1]["SECTOR"] = "三一"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], dimension_rows),
        ),
        :AIES_DIMENSION_TYPE,
    )
    numeric_size_rows = deepcopy(rows[profile_id])
    numeric_size_rows[1][entry["measure_value_fields"][1]] = repeat("9", 129)
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], numeric_size_rows),
        ),
        :NUMERIC_LEXEME_SIZE,
    )
    structural_flag_rows = deepcopy(rows[profile_id])
    structural_flag_rows[1]["GEO_ID_F"] = "X"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], structural_flag_rows),
        ),
        :AIES_STRUCTURAL_FLAG_UNRESOLVED,
    )
    caught_type = try
        CensusProfile.parse_logical_fixture(profile_id, codeunits(String(copy(valid))))
        nothing
    catch error
        error
    end
    @test caught_type isa CensusProfile.CensusProfileError
    @test caught_type.code == :FIXTURE_BYTES_TYPE
end

@testset "SUSB exact coverage, overlap identities, and suppression typing" begin
    profile, fixtures, rows = fixtures_and_rows()
    profile_id = "susb_employer_enterprises"
    entry = profile_by_id(profile, profile_id)
    table = CensusProfile.parse_logical_fixture(profile_id, fixtures[profile_id])
    @test table["row_count"] == 9
    @test Set(row["ENTRSIZE"] for row in table["rows"]) == Set(CensusProfile.SUSB_SIZE_CODES)

    missing_rows = deepcopy(rows[profile_id])
    pop!(missing_rows)
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], missing_rows),
        ),
        :SUSB_COVERAGE,
    )
    bad_code_rows = deepcopy(rows[profile_id])
    bad_code_rows[end]["ENTRSIZE"] = "10"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], bad_code_rows),
        ),
        :SUSB_SIZE_CODE,
    )
    duplicate_rows = deepcopy(rows[profile_id])
    duplicate_rows[end]["ENTRSIZE"] = "08"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], duplicate_rows),
        ),
        :FIXTURE_DUPLICATE_KEY,
    )
    mismatched_rows = deepcopy(rows[profile_id])
    mismatched_rows[5]["FIRM"] = "61"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], mismatched_rows),
        ),
        :SUSB_OVERLAP_IDENTITY,
    )

    suppressed_rows = deepcopy(rows[profile_id])
    suppressed_rows[2]["EMPL"] = "0"
    suppressed_rows[2]["EMPLFL_N"] = "S"
    suppressed_bytes = fixture_bytes(entry["logical_fields"], suppressed_rows)
    suppressed_table = CensusProfile.parse_logical_fixture(profile_id, suppressed_bytes)
    suppressed_state = suppressed_table["row_states"][2]["EMPL"]
    @test suppressed_state["publication_state"] ==
        "WITHHELD_UNKNOWN_INCLUDED_IN_BROADER_TOTALS"
    @test !suppressed_state["model_numeric_allowed"]
    @test !suppressed_state["overlap_identity_numeric_allowed"]
    suppressed_fixtures = deepcopy(fixtures)
    suppressed_fixtures[profile_id] = suppressed_bytes
    suppressed_result = CensusProfile.build_structural_result(suppressed_fixtures)
    relevant = only(
        check for check in suppressed_result["susb_overlap_checks"]
            if check["metric"] == "EMPL" && check["target_size_code"] == "05"
    )
    @test relevant["status"] == "UNVERIFIABLE_PUBLICATION_STATE_NOT_ZERO_FILLED"
    @test relevant["raw_values_target_then_components"][2] == "0"

    suppressed_nonzero = deepcopy(suppressed_rows)
    suppressed_nonzero[2]["EMPL"] = "1"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], suppressed_nonzero),
        ),
        :SUSB_SUPPRESSED_LEXEME,
    )
    historical_rows = deepcopy(rows[profile_id])
    historical_rows[2]["PAYRFL_N"] = "D"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], historical_rows),
        ),
        :SUSB_HISTORICAL_D_2022,
    )
    unknown_flag_rows = deepcopy(rows[profile_id])
    unknown_flag_rows[2]["RCPTFL_N"] = "K"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], unknown_flag_rows),
        ),
        :SUSB_FLAG,
    )
    discontinued_rows = deepcopy(rows[profile_id])
    discontinued_rows[2]["EMPLFL_R"] = "G"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], discontinued_rows),
        ),
        :SUSB_EMPLFL_R_2022,
    )
    negative_rows = deepcopy(rows[profile_id])
    negative_rows[2]["ESTB"] = "-1"
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], negative_rows),
        ),
        :SUSB_INTEGER_TYPE,
    )
    huge_rows = deepcopy(rows[profile_id])
    huge_rows[2]["FIRM"] = repeat("9", 129)
    captured_error(
        () -> CensusProfile.parse_logical_fixture(
            profile_id,
            fixture_bytes(entry["logical_fields"], huge_rows),
        ),
        :NUMERIC_LEXEME_SIZE,
    )
end

@testset "SUSB projection is separate and FIRM is never summed across NAICS" begin
    profile, fixtures, rows = fixtures_and_rows()
    profile_id = "susb_employer_enterprises"
    entry = profile_by_id(profile, profile_id)
    multiple_groups = vcat(deepcopy(rows[profile_id]), susb_rows(; naics = "322222"))
    changed_fixtures = replace_fixture(fixtures, profile_id, entry, multiple_groups)
    result = CensusProfile.build_structural_result(changed_fixtures)
    projection = result["susb_national_total_projection"]
    @test projection["input_row_count"] == 18
    @test projection["projection_row_count"] == 2
    @test all(row -> row["ENTRSIZE"] == "01", projection["rows"])
    @test projection["cross_naics_firm_sum_forbidden"]
    @test projection["firm_model_role"] ==
        "INDUSTRY_FIRM_PRESENCES_PROXY_ONLY_PENDING_VALIDATED_ALLOCATION_OR_DEDUPLICATION_ONTOLOGY"
    @test !haskey(projection, "firm_sum")
    @test result["susb_firm_interindustry_additivity"] ==
        "PROHIBITED_MULTI_INDUSTRY_ENTERPRISE_DOUBLE_COUNT_RISK"
    @test all(check -> !check["cross_naics_aggregation_performed"], result["susb_overlap_checks"])

    states_only = susb_rows(; state = "01")
    no_national = replace_fixture(fixtures, profile_id, entry, states_only)
    captured_error(
        () -> CensusProfile.build_structural_result(no_national),
        :SUSB_NATIONAL_COVERAGE,
    )
end

@testset "Fixture-set coverage and exact result replay resist tampering" begin
    profile, fixtures, rows = fixtures_and_rows()
    result = CensusProfile.build_structural_result(fixtures)
    missing = deepcopy(fixtures)
    delete!(missing, "aies00inv_2023_economy_wide")
    captured_error(
        () -> CensusProfile.build_structural_result(missing),
        :FIXTURE_SET_COVERAGE,
    )
    extra = deepcopy(fixtures)
    extra["unplanned"] = UInt8[0x0a]
    captured_error(
        () -> CensusProfile.build_structural_result(extra),
        :FIXTURE_SET_COVERAGE,
    )

    mutations = Function[
        value -> (value["status"] = "READY"),
        value -> (value["qualified_physical_layout_count"] = 6),
        value -> (value["gates"]["model_input_allowed"] = true),
        value -> (value["tables"][1]["rows"][1]["YEAR"] = "2024"),
        value -> (value["tables"][1]["row_states"][1][first(keys(value["tables"][1]["row_states"][1]))]["model_numeric_allowed"] = false),
        value -> (value["susb_national_total_projection"]["content_sha256"] = repeat("0", 64)),
        value -> (value["susb_overlap_checks"][1]["status"] = "SKIPPED"),
        value -> (value["content_sha256"] = repeat("0", 64)),
        value -> (value["extra"] = false),
        value -> (value["profile_count"] = true),
    ]
    for mutate! in mutations
        changed = deepcopy(result)
        mutate!(changed)
        captured_error(
            () -> CensusProfile.validate_structural_result(changed, fixtures),
            :RESULT_REPLAY,
        )
    end

    changed_fixtures = deepcopy(fixtures)
    changed_profile_id = "aies31inv_2023_manufacturing_valuation"
    changed_entry = profile_by_id(profile, changed_profile_id)
    changed_rows = deepcopy(rows[changed_profile_id])
    changed_rows[1][changed_entry["measure_value_fields"][1]] = "101"
    changed_fixtures[changed_profile_id] =
        fixture_bytes(changed_entry["logical_fields"], changed_rows)
    captured_error(
        () -> CensusProfile.validate_structural_result(result, changed_fixtures),
        :RESULT_REPLAY,
    )
end

@testset "Coordinated profile restamps and physical aliases fail" begin
    document = profile_document()
    changed = deepcopy(document)
    changed["physical_evidence"]["provider_bodies_preserved"] = true
    CensusProfile._stamp_profile_content_sha256!(changed)
    captured_error(
        () -> CensusProfile.validate_profile_document(changed),
        :PROFILE_FROZEN_CONTENT_HASH,
    )

    changed = deepcopy(document)
    changed["profiles"][3]["key_fields"] = ["GEO_ID", "YEAR", "NAICS"]
    CensusProfile._stamp_profile_content_sha256!(changed)
    captured_error(
        () -> CensusProfile.validate_profile_document(changed),
        :PROFILE_FROZEN_CONTENT_HASH,
    )

    mktempdir() do directory
        tampered_path = joinpath(directory, "profile.toml")
        write(tampered_path, replace(read(PROFILE_PATH, String), "CANNOT_RUN" => "READY"; count = 1))
        captured_error(
            () -> CensusProfile.load_profile(tampered_path),
            :PROFILE_FROZEN_PHYSICAL_HASH,
        )

        symlink_path = joinpath(directory, "profile-link.toml")
        symlink(PROFILE_PATH, symlink_path)
        captured_error(
            () -> CensusProfile.load_profile(symlink_path),
            :SYMLINK_FILE,
        )

        hardlink_path = joinpath(directory, "profile-hardlink.toml")
        Base.Filesystem.hardlink(PROFILE_PATH, hardlink_path)
        captured_error(
            () -> CensusProfile.load_profile(hardlink_path),
            :HARDLINK_FILE,
        )
    end
end

@testset "Unknown IDs and empty tables fail closed" begin
    profile, fixtures, _ = fixtures_and_rows()
    captured_error(
        () -> CensusProfile.parse_logical_fixture("unknown", UInt8[0x0a]),
        :UNKNOWN_PROFILE,
    )
    profile_id = "aies44inv_2023_retail_valuation"
    entry = profile_by_id(profile, profile_id)
    header_only = Vector{UInt8}(codeunits(join(entry["logical_fields"], '\t') * "\n"))
    captured_error(
        () -> CensusProfile.parse_logical_fixture(profile_id, header_only),
        :FIXTURE_ROWS,
    )
    @test CensusProfile.build_structural_result(fixtures)["status"] == "CANNOT_RUN"
end
