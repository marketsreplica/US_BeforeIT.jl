using SHA
using Test
using TOML

const TEST_DIRECTORY = @__DIR__
const MODULE_PATH = joinpath(TEST_DIRECTORY, "USClassificationMapsProfileV1.jl")
include(MODULE_PATH)
using .USClassificationMapsProfileV1

const Candidate = USClassificationMapsProfileV1
const EXPECTED_MODULE_SHA256 =
    "f5890e959dc80c8fdda1507d73dba3658d4fa5720daaa3adc7cfb8e64732cfb1"
const EXPECTED_PROFILE_PHYSICAL_SHA256 =
    "abef7ace9ecc5799a0f09c060a3ee6371e45330b2d6dbac21a09c3b6f97598f8"
const EXPECTED_PROFILE_SEMANTIC_SHA256 =
    "1ea4517532226a4d7026fd5e2061f32a2866e057a73e1064351ffb55ac33c992"

bytes(value) = Vector{UInt8}(codeunits(value))

function error_code(callback)
    try
        callback()
        return nothing
    catch error
        error isa ClassificationMapError || rethrow()
        return error.code
    end
end

function xml_escape(value)
    return replace(
        string(value),
        '&' => "&amp;",
        '<' => "&lt;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&apos;",
    )
end

function column_name(number::Int)
    number > 0 || error("positive column required")
    output = ""
    value = number
    while value > 0
        value -= 1
        output = string(Char(Int('A') + value % 26)) * output
        value = div(value, 26)
    end
    return output
end

function worksheet_xml(rows)
    buffer = IOBuffer()
    write(buffer, "<worksheet><sheetData>")
    for (row_index, row) in enumerate(rows)
        write(buffer, "<row r=\"", string(row_index), "\">")
        for (column_index, value) in enumerate(row)
            reference = column_name(column_index) * string(row_index)
            write(
                buffer,
                "<c r=\"", reference,
                "\" t=\"inlineStr\"><is><t xml:space=\"preserve\">",
                xml_escape(value),
                "</t></is></c>",
            )
        end
        write(buffer, "</row>")
    end
    write(buffer, "</sheetData></worksheet>")
    return String(take!(buffer))
end

function fixture_object(rows)
    workbook =
        "<workbook><sheets><sheet name=\"ClassificationMap\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
    relationships =
        "<Relationships><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>"
    return Dict{String, Any}(
        "fixture_kind" => "SYNTHETIC_OOXML_PARTS",
        "fixture_origin" => "SYNTHETIC_NO_URL_ATTRIBUTION",
        "media_type" =>
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "parts" => Pair{String, Vector{UInt8}}[
            "xl/workbook.xml" => bytes(workbook),
            "xl/_rels/workbook.xml.rels" => bytes(relationships),
            "xl/worksheets/sheet1.xml" => bytes(worksheet_xml(rows)),
        ],
    )
end

function summary_rows(; drift = false)
    rows = [String["axis", "ordinal", "code", "title", "account_kind", "note"]]
    for axis in ("Industry", "Commodity")
        codes = axis == "Industry" ? collect(Candidate.SUMMARY_CODES) :
            [collect(Candidate.SUMMARY_CODES); "Other"; "Used"]
        for (ordinal, code) in enumerate(codes)
            title = code in ("Other", "Used") ?
                "Synthetic BEA special account: $code" : "Synthetic title & definition for $code"
            drift && axis == "Industry" && ordinal == 1 && (title *= " drift")
            kind = code in ("Other", "Used") ?
                "BEA_SPECIAL_ACCOUNT_NON_NAICS" : "ORDINARY_BEA_SUMMARY"
            note = ordinal == 2 ? "Synthetic note <preserved>" : ""
            push!(rows, [axis, string(ordinal), code, title, kind, note])
        end
    end
    return rows
end

function bea_rows()
    return [
        ["ordinal", "bea_axis", "bea_code", "bea_title", "naics_code", "naics_title", "note"],
        ["1", "Industry", "511", "Synthetic publishing industries", "513110", "Synthetic newspaper publishers", ""],
        ["2", "Industry", "511", "Synthetic publishing industries", "513120", "Synthetic periodical publishers", "split & preserved"],
        ["3", "Commodity", "311FT", "Synthetic food commodity", "311111", "Synthetic dog and cat food manufacturing", ""],
        ["4", "Industry", "441", "Synthetic retail source A", "44-45", "Synthetic retail trade range", "many-to-one witness"],
        ["5", "Industry", "445", "Synthetic retail source B", "44-45", "Synthetic retail trade range", ""],
        ["6", "Commodity", "324", "Synthetic petroleum commodity", "324110", "Synthetic petroleum refineries", ""],
    ]
end

function naics_structure_rows(vintage::Int)
    if vintage == 2017
        return [
            ["ordinal", "level", "code", "title", "note"],
            ["1", "2", "31-33", "Synthetic Manufacturing", "range retained"],
            ["2", "3", "311", "Synthetic Food Manufacturing", ""],
            ["3", "4", "3111", "Synthetic Animal Food Manufacturing", ""],
            ["4", "5", "31111", "Synthetic Animal Food Manufacturing Detail", ""],
            ["5", "6", "311111", "Synthetic Dog and Cat Food Manufacturing", ""],
            ["6", "2", "44-45", "Synthetic Retail Trade", ""],
            ["7", "3", "453", "Synthetic Miscellaneous Store Retailers", ""],
            ["8", "4", "4533", "Synthetic Used Merchandise Stores", "Used in a title is valid"],
            ["9", "6", "453310", "Synthetic Used Merchandise Stores Detail", ""],
        ]
    end
    return [
        ["ordinal", "level", "code", "title", "note"],
        ["1", "2", "31-33", "Synthetic Manufacturing", "range retained"],
        ["2", "3", "311", "Synthetic Food Manufacturing", ""],
        ["3", "4", "3111", "Synthetic Animal Food Manufacturing", ""],
        ["4", "5", "31111", "Synthetic Animal Food Manufacturing Detail", ""],
        ["5", "6", "311111", "Synthetic Dog and Cat Food Manufacturing", ""],
        ["6", "2", "44-45", "Synthetic Retail Trade", ""],
        ["7", "3", "459", "Synthetic Sporting and Miscellaneous Retailers", ""],
        ["8", "4", "4595", "Synthetic Used Merchandise Retailers", "Used in a title is valid"],
        ["9", "6", "459510", "Synthetic Used Merchandise Retailers Detail", ""],
    ]
end

function naics_concordance_rows()
    return [
        ["ordinal", "2017_code", "2017_title", "2022_code", "2022_title", "note"],
        ["1", "111110", "Synthetic soybean farming 2017", "111110", "Synthetic soybean farming 2022", ""],
        ["2", "511110", "Synthetic newspaper publishers 2017", "513110", "Synthetic newspaper publishers 2022", "split row one"],
        ["3", "511110", "Synthetic newspaper publishers 2017", "513120", "Synthetic periodical publishers 2022", "split row two"],
        ["4", "519130", "Synthetic internet publishing 2017", "519290", "Synthetic web search portals 2022", "merge row one"],
        ["5", "519190", "Synthetic all other information 2017", "519290", "Synthetic web search portals 2022", ""],
    ]
end

function fixture_objects(; make_drift = false)
    return Pair{String, Any}[
        "bea_summary_use_2024" => fixture_object(summary_rows()),
        "bea_summary_make_2024" => fixture_object(summary_rows(; drift = make_drift)),
        "bea_industry_commodity_naics_concordance" => fixture_object(bea_rows()),
        "naics_2017_structure" => fixture_object(naics_structure_rows(2017)),
        "naics_2017_to_2022_concordance" => fixture_object(naics_concordance_rows()),
        "naics_2022_structure" => fixture_object(naics_structure_rows(2022)),
    ]
end

function replace_sheet!(objects, index, rows)
    objects[index].second["parts"][3] =
        "xl/worksheets/sheet1.xml" => bytes(worksheet_xml(rows))
    return objects
end

function restamp_profile!(profile)
    profile["artifact"]["content_sha256"] = repeat("0", 64)
    profile["artifact"]["content_sha256"] = profile_semantic_sha256(profile)
    return profile
end

function restamp_result!(result)
    result["artifact"]["content_sha256"] = repeat("0", 64)
    result["artifact"]["content_sha256"] =
        Candidate._canonical_sha256(result; exclude_artifact_hash = true)
    return result
end

@testset "frozen profile, source pins, and closed public surface" begin
    profile = validate_profile()
    @test profile["artifact"]["status"] == "CANNOT_RUN"
    @test profile["artifact"]["content_sha256"] == EXPECTED_PROFILE_SEMANTIC_SHA256
    @test profile_semantic_sha256(profile) == EXPECTED_PROFILE_SEMANTIC_SHA256
    @test bytes2hex(sha256(read(PROFILE_PATH))) == EXPECTED_PROFILE_PHYSICAL_SHA256
    @test bytes2hex(sha256(read(MODULE_PATH))) == EXPECTED_MODULE_SHA256
    @test profile["scope"]["profile_count"] === 6
    @test profile["scope"]["object_count"] === 7
    @test profile["scope"]["official_workbook_count"] === 6
    @test profile["scope"]["current_qualified_count"] === 0
    @test profile["scope"]["official_workbook_bodies_present"] === false
    @test profile["scope"]["current_origin_receipts_present"] === false
    @test profile["scope"]["fixture_bytes_attributed_to_planned_locators"] === false
    @test profile["semantics"]["summary_special_accounts"] == ["Other", "Used"]
    @test profile["semantics"]["bea_concordance_direction"] == "BEA_TO_NAICS"
    @test profile["semantics"]["naics_concordance_direction"] ==
        "NAICS_2017_TO_NAICS_2022"
    @test length(profile["source_pins"]) == 8
    @test all(value === false for value in values(profile["gates"]))
    @test_throws MethodError validate_profile(false)
    @test_throws MethodError validate_object_set(fixture_objects(); verify_sources = false)
end

@testset "stable local source reads reject path aliases" begin
    source = Candidate._read_stable_source(
        "scripts/us/bea71.toml",
        :test_source,
        maximum_bytes = 1_048_576,
    )
    @test source.sha256 ==
        "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
    @test length(source.bytes) == 8_146
    @test source.path == joinpath(Candidate.REPOSITORY_ROOT, "scripts/us/bea71.toml")
    @test error_code(() -> Candidate._read_stable_source("../escape", :test_source)) ==
        :test_source

    mktempdir(TEST_DIRECTORY) do directory
        source_path = joinpath(directory, "source.txt")
        write(source_path, "stable synthetic source")
        relative_source = relpath(source_path, Candidate.REPOSITORY_ROOT)
        snapshot = Candidate._read_stable_source(relative_source, :test_source)
        @test String(snapshot.bytes) == "stable synthetic source"

        symlink_path = joinpath(directory, "source-link.txt")
        symlink(source_path, symlink_path)
        @test error_code(
            () -> Candidate._read_stable_source(
                relpath(symlink_path, Candidate.REPOSITORY_ROOT),
                :test_source,
            ),
        ) == :test_source

        hardlink_path = joinpath(directory, "source-hardlink.txt")
        Base.Filesystem.hardlink(source_path, hardlink_path)
        @test error_code(
            () -> Candidate._read_stable_source(
                relpath(hardlink_path, Candidate.REPOSITORY_ROOT),
                :test_source,
            ),
        ) == :test_source

        real_directory = joinpath(directory, "real")
        mkdir(real_directory)
        nested_source = joinpath(real_directory, "nested.txt")
        write(nested_source, "nested synthetic source")
        linked_directory = joinpath(directory, "linked")
        symlink(real_directory, linked_directory)
        aliased_source = joinpath(linked_directory, "nested.txt")
        @test error_code(
            () -> Candidate._read_stable_source(
                relpath(aliased_source, Candidate.REPOSITORY_ROOT),
                :test_source,
            ),
        ) == :test_source
    end
end

@testset "profile coordinated-restamp and schema attacks" begin
    for mutator in (
            profile -> reverse!(profile["profiles"]),
            profile -> profile["profiles"][2]["direction"] = "NAICS_TO_BEA",
            profile -> push!(profile["profiles"][5]["object_ids"], "naics_2022_structure"),
            profile -> profile["semantics"]["summary_special_accounts"] = ["Used", "Other"],
            profile -> profile["semantics"]["inverse_policy"] = "ALLOW_REVERSAL",
            profile -> profile["scope"]["current_qualified_count"] = 6,
            profile -> profile["gates"]["ready"] = true,
            profile -> profile["objects"][3]["official_body_present"] = true,
            profile -> profile["objects"][4]["official"] = true,
            profile -> profile["source_pins"][7]["sha256"] = repeat("0", 64),
            profile -> profile["extra"] = true,
        )
        profile = TOML.parsefile(PROFILE_PATH)
        mutator(profile)
        restamp_profile!(profile)
        @test error_code(() -> Candidate._validate_profile_document(profile)) !== nothing
    end
    profile = TOML.parsefile(PROFILE_PATH)
    profile["artifact"]["content_sha256"] = repeat("0", 64)
    @test error_code(() -> Candidate._validate_profile_document(profile)) ==
        :profile_semantic_hash
end

@testset "successful offline object-set replay and claim ceiling" begin
    objects = fixture_objects()
    result = validate_object_set(objects)
    @test validate_compiled_result(result, objects) === result
    @test result["artifact"]["status"] == "CANNOT_RUN"
    @test result["artifact"]["claim_ceiling"] ==
        "OFFLINE_SYNTHETIC_PARSER_AND_LOCAL_FIXITY_RECEIPT_ONLY_NO_OFFICIAL_BODY_OR_CURRENT_ORIGIN"
    @test result["validation"]["qualified_profile_count"] === 0
    @test result["validation"]["official_body_count"] === 0
    @test result["validation"]["current_origin_receipt_count"] === 0
    @test result["validation"]["network_action_count"] === 0
    @test result["validation"]["filesystem_write_action_count"] === 0
    @test result["validation"]["official_fixture_url_attribution_count"] === 0
    @test result["object_order"] == collect(Candidate.RESULT_OBJECT_ORDER)
    @test length(result["object_set_manifest"]) == 7
    @test [row["ordinal"] for row in result["object_set_manifest"]] == collect(1:7)
    @test all(row["planned_locator_attributed_to_fixture"] === false for row in result["object_set_manifest"])
    @test all(row["official_body_claimed"] === false for row in result["object_set_manifest"])
    @test all(value === false for value in values(result["gates"]))
    @test result["blockers"] == collect(Candidate.RESULT_BLOCKERS)
    @test length(result["profile_projections"]) == 6

    summary = result["profile_projections"][1]
    @test summary["profile_id"] == "bea_summary_codes"
    @test summary["fixture_matches_across_use_make"] === true
    @test summary["industry_count"] === 71
    @test summary["commodity_count"] === 73
    @test summary["special_accounts"] == ["Other", "Used"]
    @test length(summary["fixture_rows"]) == 144
    @test summary["fixture_rows"][1]["title"] ==
        "Synthetic title & definition for 111CA"
    @test summary["fixture_rows"][2]["note"] == "Synthetic note <preserved>"
    @test summary["fixture_rows"][end - 1]["code"] == "Other"
    @test summary["fixture_rows"][end]["code"] == "Used"
    @test summary["fixture_rows"][end]["account_kind"] ==
        "BEA_SPECIAL_ACCOUNT_NON_NAICS"
    @test summary["parent_raw_bytes_replayed"] === false
    @test summary["physically_qualified"] === false

    bea = result["profile_projections"][2]
    @test bea["direction"] == "BEA_TO_NAICS"
    @test bea["inverse_generated"] === false
    @test bea["rows"][1]["relationship"] == "one_to_many"
    @test bea["rows"][2]["relationship"] == "one_to_many"
    @test bea["rows"][3]["relationship"] == "one_to_one"
    @test bea["rows"][4]["relationship"] == "many_to_one"
    @test bea["rows"][5]["relationship"] == "many_to_one"
    @test bea["rows"][1]["note"] == ""
    @test bea["rows"][2]["note"] == "split & preserved"

    bridge = result["profile_projections"][3]
    @test bridge["repository_path"] == "scripts/us/bea71.toml"
    @test bridge["repository_sha256"] ==
        "2e0fb0a6d8190e4488810653a2638edeff9ceae2a1ea463f28730106752b183f"
    @test bridge["repository_byte_count"] == 8_146
    @test bridge["sector_count"] === 68
    @test length(bridge["sectors"]) == 68
    @test bridge["sectors"][28]["code"] == "4A0"
    @test bridge["sectors"][36]["code"] == "493"
    @test bridge["sector_order_differs_from_model_codes"] === true
    @test bridge["sector_order_difference_positions"] == collect(28:36)
    @test bridge["industry_to_model"] ==
        Dict("441" => "4A0", "445" => "4A0", "452" => "4A0", "4A0" => "4A0")
    @test bridge["official_crosswalk"] === false
    @test bridge["prospective_receipt_present"] === false
    @test bridge["physically_qualified"] === false

    structure_2017 = result["profile_projections"][4]
    @test structure_2017["rows"][1]["code"] == "31-33"
    @test structure_2017["rows"][1]["level"] === 2
    @test structure_2017["rows"][8]["title"] ==
        "Synthetic Used Merchandise Stores"
    @test structure_2017["rows"][8]["note"] == "Used in a title is valid"
    concordance = result["profile_projections"][5]
    @test concordance["direction"] == "NAICS_2017_TO_NAICS_2022"
    @test concordance["inverse_generated"] === false
    @test concordance["rows"][2]["relationship"] == "one_to_many"
    @test concordance["rows"][4]["relationship"] == "many_to_one"
    @test concordance["rows"][5]["note"] == ""
    @test result["profile_projections"][6]["rows"][1]["vintage"] === 2022
end

@testset "exact object set, fixture attribution, and part envelope attacks" begin
    objects = fixture_objects()
    reversed = reverse(objects)
    @test error_code(() -> validate_object_set(reversed)) == :object_order

    duplicated = deepcopy(objects)
    duplicated[2] = deepcopy(duplicated[1])
    @test error_code(() -> validate_object_set(duplicated)) == :duplicate_object

    @test error_code(() -> validate_object_set(objects[1:5])) == :object_set_count
    extra = deepcopy(objects)
    push!(extra, "extra" => fixture_object(bea_rows()))
    @test error_code(() -> validate_object_set(extra)) == :object_set_count

    for (key, value, expected) in (
            ("fixture_origin", "https://www.bea.gov/example.xlsx", :fixture_origin),
            ("fixture_kind", "PROVIDER_OOXML", :fixture_kind),
            ("media_type", "application/octet-stream", :fixture_media),
        )
        attacked = deepcopy(objects)
        attacked[1].second[key] = value
        @test error_code(() -> validate_object_set(attacked)) == expected
    end
    attacked = deepcopy(objects)
    attacked[1].second["requested_url"] = "https://www.bea.gov/example.xlsx"
    @test error_code(() -> validate_object_set(attacked)) == :fixture_shape
    attacked = deepcopy(objects)
    mixed_keys = Dict{Any, Any}(attacked[1].second)
    mixed_keys[:fixture_kind] = "SYNTHETIC_OOXML_PARTS"
    attacked[1] = attacked[1].first => mixed_keys
    @test error_code(() -> validate_object_set(attacked)) == :fixture_shape

    attacked = deepcopy(objects)
    reverse!(attacked[1].second["parts"])
    @test error_code(() -> validate_object_set(attacked)) == :part_order
    attacked = deepcopy(objects)
    attacked[1].second["parts"][2] = deepcopy(attacked[1].second["parts"][1])
    @test error_code(() -> validate_object_set(attacked)) in (:part_order, :duplicate_part)
    attacked = deepcopy(objects)
    pop!(attacked[1].second["parts"])
    @test error_code(() -> validate_object_set(attacked)) == :part_count
    attacked = deepcopy(objects)
    attacked[1].second["parts"] = Any[
        "xl/workbook.xml" => Dict("not" => "bytes"),
        attacked[1].second["parts"][2],
        attacked[1].second["parts"][3],
    ]
    @test error_code(() -> validate_object_set(attacked)) == :part_payload
end

@testset "strict UTF-8 and XML structural attacks" begin
    cases = Function[
        objects -> (objects[1].second["parts"][1] = "xl/workbook.xml" => UInt8[0xff]),
        objects -> (objects[1].second["parts"][1] = "xl/workbook.xml" => bytes("\ufeff<workbook/>")),
        objects -> (objects[1].second["parts"][1] = "xl/workbook.xml" => bytes("<!DOCTYPE workbook><workbook/>")),
        objects -> (objects[1].second["parts"][1] = "xl/workbook.xml" => bytes("<?xml version=\"1.0\"?><workbook/>")),
        objects -> (objects[1].second["parts"][1] = "xl/workbook.xml" => bytes("<workbook><sheets><sheet name=\"ClassificationMap\" name=\"ClassificationMap\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>")),
        objects -> (objects[1].second["parts"][2] = "xl/_rels/workbook.xml.rels" => bytes("<Relationships><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"../evil.xml\"/></Relationships>")),
    ]
    expected = (:xml_utf8, :xml_bom, :xml_declaration, :xml_declaration, :xml_tag, :relationship_target)
    for (index, mutator) in enumerate(cases)
        objects = fixture_objects()
        mutator(objects)
        @test error_code(() -> validate_object_set(objects)) == expected[index]
    end

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(sheet, "<row r=\"2\">" => "<row r=\"3\">"; count = 1)
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :row_order

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(sheet, "<c r=\"B1\"" => "<c r=\"A1\""; count = 1)
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :duplicate_cell

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(sheet, " t=\"inlineStr\"" => " t=\"s\""; count = 1)
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :cell_type

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(sheet, " xml:space=\"preserve\"" => ""; count = 1)
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :text_attributes

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(
        sheet,
        "Synthetic title &amp; definition for 111CA" => "Synthetic raw ]]> text";
        count = 1,
    )
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :xml_text

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(
        sheet,
        "Synthetic title &amp; definition for 111CA" => "Synthetic literal \ufffe text";
        count = 1,
    )
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :xml_scalar

    objects = fixture_objects()
    sheet = String(objects[1].second["parts"][3].second)
    attacked_sheet = replace(
        sheet,
        "Synthetic title &amp; definition for 111CA" => "Synthetic &#xFFFE; text";
        count = 1,
    )
    objects[1].second["parts"][3] = "xl/worksheets/sheet1.xml" => bytes(attacked_sheet)
    @test error_code(() -> validate_object_set(objects)) == :xml_text
end

@testset "direction, cardinality, order, blank, and special-account attacks" begin
    @test error_code(() -> validate_object_set(fixture_objects(; make_drift = true))) ==
        :shared_axis_mismatch

    objects = fixture_objects()
    rows = bea_rows()
    rows[1] = ["ordinal", "bea_axis", "naics_code", "naics_title", "bea_code", "bea_title", "note"]
    replace_sheet!(objects, 3, rows)
    @test error_code(() -> validate_object_set(objects)) == :bea_concordance_header

    objects = fixture_objects()
    rows = naics_concordance_rows()
    rows[1] = ["ordinal", "2022_code", "2022_title", "2017_code", "2017_title", "note"]
    replace_sheet!(objects, 5, rows)
    @test error_code(() -> validate_object_set(objects)) == :naics_concordance_header

    objects = fixture_objects()
    rows = bea_rows()
    rows[2][5] = "Other"
    replace_sheet!(objects, 3, rows)
    @test error_code(() -> validate_object_set(objects)) == :special_account_as_naics

    objects = fixture_objects()
    rows = naics_structure_rows(2017)
    rows[2][3] = "Used"
    replace_sheet!(objects, 4, rows)
    @test error_code(() -> validate_object_set(objects)) == :special_account_as_naics

    objects = fixture_objects()
    rows = bea_rows()
    rows[3][4] = "Conflicting source title"
    replace_sheet!(objects, 3, rows)
    @test error_code(() -> validate_object_set(objects)) == :bea_title_conflict

    objects = fixture_objects()
    rows = naics_concordance_rows()
    rows[6][5] = "Conflicting target title"
    replace_sheet!(objects, 5, rows)
    @test error_code(() -> validate_object_set(objects)) == :naics_2022_title_conflict

    objects = fixture_objects()
    rows = bea_rows()
    push!(rows, deepcopy(rows[2]))
    rows[end][1] = string(length(rows) - 1)
    replace_sheet!(objects, 3, rows)
    @test error_code(() -> validate_object_set(objects)) == :duplicate_mapping_row

    objects = fixture_objects()
    rows = naics_structure_rows(2022)
    rows[2][2] = "3"
    replace_sheet!(objects, 6, rows)
    @test error_code(() -> validate_object_set(objects)) == :naics_level

    objects = fixture_objects()
    rows = naics_structure_rows(2022)
    rows[3][3] = rows[2][3]
    rows[3][2] = rows[2][2]
    replace_sheet!(objects, 6, rows)
    @test error_code(() -> validate_object_set(objects)) == :duplicate_naics_code
end

@testset "repository bridge strict type, duplicate, and schema attacks" begin
    document = TOML.parsefile(joinpath(Candidate.REPOSITORY_ROOT, "scripts/us/bea71.toml"))
    projection = Candidate._validate_bridge_document(document)
    @test projection["sector_count"] === 68
    @test projection["model_codes"] == collect(Candidate.MODEL_CODES)
    @test projection["sector_codes"] == collect(Candidate.SECTOR_CODES)
    @test Set(projection["model_codes"]) == Set(projection["sector_codes"])
    @test projection["sectors"][1]["qcew_2022"] == ["111", "112"]
    @test projection["sectors"][63]["qcew_2022"] == String[]
    @test projection["special"]["government_allocation_status"] == "DUBIOUS"

    for (mutator, expected) in (
            (doc -> doc["model"]["year"] = true, :bridge_year),
            (doc -> doc["model"]["codes"][2] = doc["model"]["codes"][1], :bridge_model_code),
            (doc -> reverse!(doc["sector"]), :bridge_sector_order),
            (doc -> doc["sector"][1]["qcew_2022"] = ["Other"], :special_account_as_naics),
            (doc -> doc["sector"][1]["fixed_asset_lines"] = [true], :bridge_fixed_assets),
            (doc -> doc["sector"][1]["extra"] = true, :bridge_sector_shape),
            (doc -> delete!(doc["special"], "farm_firms_source"), :bridge_special_shape),
        )
        attacked = deepcopy(document)
        mutator(attacked)
        @test error_code(() -> Candidate._validate_bridge_document(attacked)) == expected
    end
    @test_throws TOML.ParserError TOML.parse("x = 1\nx = 1\n")
end

@testset "compiled-result replay rejects restamped privilege and evidence changes" begin
    objects = fixture_objects()
    original = validate_object_set(objects)
    for mutator in (
            result -> result["artifact"]["status"] = "READY",
            result -> empty!(result["blockers"]),
            result -> result["gates"]["ready"] = true,
            result -> result["validation"]["qualified_profile_count"] = 6,
            result -> result["object_set_manifest"][1]["planned_locator_attributed_to_fixture"] = true,
            result -> result["profile_projections"][2]["direction"] = "NAICS_TO_BEA",
            result -> result["profile_projections"][5]["inverse_generated"] = true,
            result -> result["profile_projections"][1]["special_accounts"] = ["Used", "Other"],
        )
        attacked = deepcopy(original)
        mutator(attacked)
        restamp_result!(attacked)
        @test error_code(() -> validate_compiled_result(attacked, objects)) in
            (:result_replay, :result_status)
    end

    stale = validate_object_set(objects)
    changed_objects = fixture_objects()
    rows = bea_rows()
    rows[7][7] = "changed synthetic note"
    replace_sheet!(changed_objects, 3, rows)
    @test error_code(() -> validate_compiled_result(stale, changed_objects)) == :result_replay

    first = validate_object_set(objects)
    empty!(first["blockers"])
    first["profile_projections"][1]["fixture_rows"][1]["title"] = "mutated"
    second = validate_object_set(objects)
    @test second["blockers"] == collect(Candidate.RESULT_BLOCKERS)
    @test second["profile_projections"][1]["fixture_rows"][1]["title"] ==
        "Synthetic title & definition for 111CA"
end

@testset "compiled-result replay is recursively type exact before hashing" begin
    objects = fixture_objects()
    original = validate_object_set(objects)

    for mutator in (
            result -> (result["validation"]["profile_count"] = Int128(6)),
            result -> (result["object_order"] = Tuple(result["object_order"])),
            result -> (result["object_order"] = Any[result["object_order"]...]),
        )
        attacked = deepcopy(original)
        mutator(attacked)
        @test Candidate._canonical_sha256(attacked) == Candidate._canonical_sha256(original)
        @test error_code(() -> validate_compiled_result(attacked, objects)) == :result_replay
    end

    for mutator in (
            result -> (result["validation"]["profile_count"] = true),
            result -> (result["validation"]["profile_count"] = 6.0),
            result -> (result["validation"]["profile_count"] = Int8(6)),
        )
        attacked = deepcopy(original)
        mutator(attacked)
        @test error_code(() -> validate_compiled_result(attacked, objects)) == :result_replay
    end
end
