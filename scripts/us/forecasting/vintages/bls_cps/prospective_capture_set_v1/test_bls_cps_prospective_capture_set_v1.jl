using SHA
using Test
using TOML

const TEST_DIRECTORY = @__DIR__
const MODULE_PATH = joinpath(TEST_DIRECTORY, "USBLSCPSProspectiveCaptureSetV1.jl")
include(MODULE_PATH)
using .USBLSCPSProspectiveCaptureSetV1

const Candidate = USBLSCPSProspectiveCaptureSetV1
const EXPECTED_MODULE_SHA256 = "549b0001a41051d587d46ed2979345cb5a7897b9b6fe2d54d06f9e75bf0b0caa"
const MISSING_TEXT = "Data unavailable due to the 2025 lapse in appropriations."

bytes(text) = Vector{UInt8}(codeunits(text))

function error_code(callback)
    try
        callback()
        return nothing
    catch error
        error isa CaptureSetError || rethrow()
        return error.code
    end
end

function restamp_profile!(profile)
    profile["artifact"]["content_sha256"] = repeat("0", 64)
    profile["artifact"]["content_sha256"] = profile_semantic_sha256(profile)
    return profile
end

function json_escape(value::AbstractString)
    return replace(value, '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\t' => "\\t")
end

quoted(value) = "\"" * json_escape(string(value)) * "\""

function fixture_profile()
    return TOML.parsefile(PROFILE_PATH)
end

function catalog_objects(profile; seasonal_drift = false, unit_drift = false, frequency_drift = false, catalog_begin_override = nothing, catalog_terminal = "M09", duplicate_tsv = false, malformed_tsv = false, irrelevant_rows = true)
    objects = Dict{String, Vector{UInt8}}()
    seasonal_rows = ["provider_extra\tseasonal_code\tseasonal_text", "x\tU\tNot Seasonally Adjusted", "x\tS\tSeasonally Adjusted", "x\tQ\tIrrelevant seasonal code"]
    seasonal_drift && (seasonal_rows[2] = "x\tU\tUnknown")
    frequency_rows = ["periodicity_code\tperiodicity_text\tprovider_extra", "M\tMonthly\tx", "Q\tQuarterly\tx"]
    frequency_drift && (frequency_rows[2] = "M\tQuarterly\tx")
    unit_rows = ["provider_extra\ttdat_code\ttdat_text", "x\tN\tNumber in thousands", "x\tP\tPercent", "x\tX\tIrrelevant unit"]
    unit_drift && (unit_rows[2] = "x\tN\tNumber")
    objects["catalog_ln_seasonal"] = bytes(join(seasonal_rows, "\n") * "\n")
    objects["catalog_ln_periodicity"] = bytes(join(frequency_rows, "\n") * "\n")
    objects["catalog_ln_tdat"] = bytes(join(unit_rows, "\n") * "\n")
    objects["catalog_ln_footnote"] = bytes("footnote_code\tprovider_extra\tfootnote_text\n9\tx\t$(MISSING_TEXT)\n0\tx\tIrrelevant footnote\n")
    objects["catalog_ln_ages"] = bytes("provider_extra\tages_code\tages_text\nx\tA\t16 years and over\nx\tB\tIrrelevant age\n")
    objects["catalog_ln_lfst"] = bytes(
        "lfst_code\tlfst_text\tprovider_extra\n" *
            "E\tEmployed\tx\n" *
            "I\tNot in labor force\tx\n" *
            "L\tCivilian labor force\tx\n" *
            "C\tCivilian noninstitutional population\tx\n" *
            "U\tUnemployed\tx\n" *
            "R\tUnemployment rate\tx\n" *
            "X\tIrrelevant status\tx\n",
    )
    lfst_codes = ["E", "I", "L", "C", "U", "R"]
    header = join(vcat(["provider_extra_before"], Candidate.SERIES_HEADER, ["provider_extra_after"]), '\t')
    rows = [header]
    irrelevant_rows && push!(rows, join(vcat(["left"], ["LNU99999999", "Irrelevant series", "U", "M", "N", "X", "A", "1948", "M01", "2026", "M09"], ["right"]), '\t'))
    for (index, entry) in enumerate(profile["profiles"])
        begin_year = entry["expected_begin_year"]
        if catalog_begin_override !== nothing && index == 1
            begin_year = catalog_begin_override
        end
        push!(
            rows, join(
                vcat(
                    ["left"], [
                        entry["series_id"], entry["series_title"], index == 6 ? "S" : "U", "M",
                        index == 6 ? "P" : "N", lfst_codes[index], "A", string(begin_year), "M01",
                        "2026", catalog_terminal,
                    ], ["right"],
                ), '\t'
            )
        )
        irrelevant_rows && index == 3 && push!(rows, join(vcat(["left"], ["LNU88888888", "Another irrelevant series", "U", "M", "N", "X", "A", "1950", "M01", "2026", "M09"], ["right"]), '\t'))
    end
    duplicate_tsv && push!(rows, rows[2])
    series_text = join(rows, "\n") * "\n"
    malformed_tsv && (series_text = replace(series_text, '\n' => "\r\n"))
    objects["catalog_ln_series"] = bytes(series_text)
    objects["catalog_ln_txt"] = bytes("Labor Force Statistics from the Current Population Survey\nOffline synthetic validation fixture only.\n")
    return objects
end

function record_json(year, period; value = "100", bad_period_name = false)
    period_name = bad_period_name ? "September" : Candidate.PERIOD_NAMES[period]
    footnotes = value == "-" ? "[{\"code\":\"9\",\"text\":$(quoted(MISSING_TEXT))}]" : "[]"
    return "{\"year\":$(quoted(year)),\"period\":$(quoted(period)),\"periodName\":$(quoted(period_name)),\"value\":$(quoted(value)),\"footnotes\":$(footnotes)}"
end

function series_data(
        entry, start_year, end_year;
        stale_terminal = false, arbitrary_start = false, duplicate_period = false,
        omit_period = false, october_mode = :missing, m13_contamination = false,
        wrong_chunk = false
    )
    begin_year = entry["expected_begin_year"]
    low = max(begin_year, start_year)
    high = min(2026, end_year)
    low > high && return String[]
    output = String[]
    for year in high:-1:low
        if m13_contamination && year == min(high, 2024)
            push!(output, record_json(year, "M13"))
        end
        maximum_month = year == 2026 ? 9 : 12
        for month in maximum_month:-1:1
            stale_terminal && year == 2026 && month == 9 && entry["series_id"] == "LNU02000000" && continue
            arbitrary_start && year == begin_year && month == 1 && entry["series_id"] == "LNU02000000" && continue
            omit_period && year == 2000 && month == 2 && entry["series_id"] == "LNU02000000" && continue
            period = "M" * lpad(string(month), 2, '0')
            value = "100"
            if year == 2025 && month == 10
                value = october_mode == :missing ? "-" : october_mode == :zero ? "0" : "101"
            end
            row_year = wrong_chunk && year == high && month == maximum_month && entry["series_id"] == "LNU02000000" ? end_year + 1 : year
            push!(output, record_json(row_year, period; value))
            duplicate_period && year == 2000 && month == 2 && entry["series_id"] == "LNU02000000" && push!(output, record_json(year, period; value))
        end
    end
    return output
end

function api_object(
        profile, chunk;
        message = false, response_time = "1", missing_series = false,
        extra_series = false, duplicate_series = false, swap_series = false,
        stale_terminal = false, arbitrary_start = false, duplicate_period = false,
        omit_period = false, october_mode = :missing, m13_contamination = false,
        wrong_chunk = false
    )
    entries = String[]
    for entry in profile["profiles"]
        data = series_data(
            entry, chunk["start_year"], chunk["end_year"];
            stale_terminal, arbitrary_start, duplicate_period, omit_period,
            october_mode, m13_contamination, wrong_chunk
        )
        push!(entries, "{\"seriesID\":$(quoted(entry["series_id"])),\"data\":[" * join(data, ",") * "]}")
    end
    missing_series && pop!(entries)
    duplicate_series && (entries[end] = entries[1])
    swap_series && ((entries[1], entries[2]) = (entries[2], entries[1]))
    extra_series && push!(entries, "{\"seriesID\":\"EXTRA\",\"data\":[]}")
    messages = message ? "[\"warning\"]" : "[]"
    return bytes("{\"status\":\"REQUEST_SUCCEEDED\",\"responseTime\":$(response_time),\"message\":$(messages),\"Results\":{\"series\":[" * join(entries, ",") * "]}}")
end

function fixture_objects(;
        target_chunk = 8, message = false, response_time = "1",
        missing_series = false, extra_series = false, duplicate_series = false,
        swap_series = false, stale_terminal = false, arbitrary_start = false,
        duplicate_period = false, omit_period = false, october_mode = :missing,
        m13_contamination = false, wrong_chunk = false, seasonal_drift = false,
        unit_drift = false, frequency_drift = false, catalog_begin_override = nothing,
        catalog_terminal = "M09", duplicate_tsv = false, malformed_tsv = false,
        irrelevant_rows = true
    )
    profile = fixture_profile()
    objects = catalog_objects(
        profile;
        seasonal_drift, unit_drift, frequency_drift, catalog_begin_override,
        catalog_terminal, duplicate_tsv, malformed_tsv, irrelevant_rows
    )
    for (index, chunk) in enumerate(profile["chunks"])
        active = index == target_chunk
        objects[chunk["object_id"]] = api_object(
            profile, chunk;
            message = active && message,
            response_time = active ? response_time : "1",
            missing_series = active && missing_series,
            extra_series = active && extra_series,
            duplicate_series = active && duplicate_series,
            swap_series = active && swap_series,
            stale_terminal = active && stale_terminal,
            arbitrary_start = active && arbitrary_start,
            duplicate_period = active && duplicate_period,
            omit_period = active && omit_period,
            october_mode = active ? october_mode : :missing,
            m13_contamination = active && m13_contamination,
            wrong_chunk = active && wrong_chunk,
        )
    end
    return objects
end

@testset "frozen profile, pins, and request plan" begin
    profile = validate_profile()
    @test profile["artifact"]["content_sha256"] == "68e8d7a1a366c9409e4a29f83dfa90864fbcb0024fcbd91aa53cc16dcbd04e8b"
    @test bytes2hex(sha256(read(PROFILE_PATH))) == "d6bad6ffc6279cacee09ae3fcdec688df1b460515e12ffc2f17d918b40ae7081"
    @test bytes2hex(sha256(read(MODULE_PATH))) == EXPECTED_MODULE_SHA256
    @test length(profile["source_pins"]) == 11
    @test [entry["series_id"] for entry in profile["profiles"]] == ["LNU02000000", "LNU05000000", "LNU01000000", "LNU00000000", "LNU03000000", "LNS14000000"]
    @test [(chunk["start_year"], chunk["end_year"]) for chunk in profile["chunks"]] == [(1948, 1957), (1958, 1967), (1968, 1977), (1978, 1987), (1988, 1997), (1998, 2007), (2008, 2017), (2018, 2026)]
    @test all(!occursin("registration", lowercase(body)) for body in canonical_post_bodies(profile))
    @test profile["release"]["scheduled_release_timestamp_utc"] == "2026-10-02T12:30:00Z"
    @test profile["release"]["public_api_documented_lag_days"] === 1
    @test profile["release"]["single_release_time_api_capture_sufficient"] === false
    @test profile["scope"]["current_qualified_count"] === 0
    @test profile["scope"]["catalog_provider_layout_evidenced"] === false
    @test profile["limits"]["max_ln_series_bytes"] == 33_554_432
    @test profile["limits"]["max_ln_series_bytes"] > 15_288_538
    @test profile["coverage"]["annual_period_policy"] == "REJECT_NOT_REQUIRED_FOR_MONTHLY_PROJECTIONS"
end

@testset "successful synthetic offline validation" begin
    objects = fixture_objects()
    result = validate_capture_set(objects)
    @test validate_compiled_result(result, objects) === result
    @test result["artifact"]["status"] == "CANNOT_RUN"
    @test length(result["object_set_manifest"]) == 16
    @test length(result["profile_projections"]) == 6
    @test [entry["object_id"] for entry in result["object_set_manifest"]][1:8] == ["api_1948_1957", "api_1958_1967", "api_1968_1977", "api_1978_1987", "api_1988_1997", "api_1998_2007", "api_2008_2017", "api_2018_2026"]
    @test all(projection["provider_end"] == "2026-M09" for projection in result["profile_projections"])
    @test result["profile_projections"][2]["provider_begin"] == "1975-M01"
    @test result["profile_projections"][6]["seasonal_text"] == "Seasonally Adjusted"
    @test result["profile_projections"][6]["unit_text"] == "Percent"
    @test all(projection["annual_m13_count"] === 0 for projection in result["profile_projections"])
    @test all(projection["annual_m13_policy"] == "REJECT_NOT_REQUIRED_FOR_MONTHLY_PROJECTIONS" for projection in result["profile_projections"])
    @test all(projection["explicit_missing_count"] == 1 for projection in result["profile_projections"])
    @test all(value === false for value in values(result["gates"]))
    @test result["validation"]["network_action_count"] === 0
    @test result["validation"]["filesystem_write_action_count"] === 0
    @test result["validation"]["current_v3_integration"] === false
    @test result["validation"]["provider_catalog_layout_evidenced"] === false
    @test result["validation"]["catalog_projection_operational"] === false
    @test result["object_order"] == [entry["object_id"] for entry in result["object_set_manifest"]]
    @test [entry["ordinal"] for entry in result["object_set_manifest"]] == collect(1:16)
    @test all(entry["planned_url_bytes_claimed"] === false for entry in result["object_set_manifest"])
    receipt = result["catalog_projection_receipt"]
    @test receipt["artifact"]["status"] == "CANNOT_RUN_UNVERIFIED_PROVIDER_LAYOUT"
    @test receipt["ln_series_irrelevant_row_count"] == 2
    @test length(receipt["selected_series_rows"]) == 6
    @test receipt["raw_catalog_bindings"][1]["full_raw_sha256"] == bytes2hex(sha256(objects["catalog_ln_series"]))
    @test all(projection["catalog_projection_receipt_sha256"] == receipt["artifact"]["content_sha256"] for projection in result["profile_projections"])
end

@testset "request body, series order, and chunk attacks" begin
    for mutator in (
            profile -> profile["chunks"][1]["body"] *= " ",
            profile -> reverse!(profile["chunks"]),
            profile -> profile["chunks"][1]["end_year"] = 1958,
            profile -> reverse!(profile["profiles"]),
            profile -> profile["routes"]["api_registration_key_present"] = true,
        )
        profile = fixture_profile()
        mutator(profile)
        restamp_profile!(profile)
        @test error_code(() -> Candidate._validate_profile_document_unit(profile)) !== nothing
    end
    @test error_code(() -> validate_capture_set(fixture_objects(wrong_chunk = true))) == :api_wrong_chunk
end

@testset "duplicate-safe bounded JSON" begin
    @test error_code(() -> parse_json_strict(bytes("{\"status\":1,\"\\u0073tatus\":2}"))) == :json_duplicate_member
    @test error_code(() -> parse_json_strict(bytes("{\"x\":1,\"x\":2}"))) == :json_duplicate_member
    @test error_code(() -> parse_json_strict(bytes("[[[0]]]"), max_depth = 2)) == :json_depth_limit
    @test error_code(() -> parse_json_strict(bytes("[0,1,2]"), max_nodes = 3)) == :json_node_limit
    @test error_code(() -> parse_json_strict(bytes("\"1234\""), max_string_bytes = 3)) == :json_string_limit
    @test error_code(() -> parse_json_strict(bytes("{\"x\":1}"), max_bytes = 3)) == :json_size_limit
    @test error_code(() -> parse_json_strict(bytes("{\"x\":01}"))) == :json_invalid
    @test error_code(() -> parse_json_strict(UInt8[0x7b, 0x22, 0x78, 0x22, 0x3a, 0x22, 0xff, 0x22, 0x7d])) == :json_invalid_utf8
end

@testset "API success is still fail-closed on messages and aliases" begin
    @test error_code(() -> validate_capture_set(fixture_objects(message = true))) == :api_message
    @test error_code(() -> validate_capture_set(fixture_objects(response_time = "1.0"))) == :api_response_time
    @test error_code(() -> validate_capture_set(fixture_objects(response_time = "true"))) == :api_response_time
end

@testset "exact six-series objects" begin
    @test error_code(() -> validate_capture_set(fixture_objects(missing_series = true))) == :api_series_count
    @test error_code(() -> validate_capture_set(fixture_objects(extra_series = true))) == :api_series_count
    @test error_code(() -> validate_capture_set(fixture_objects(duplicate_series = true))) in (:api_series_order, :api_duplicate_series)
    @test error_code(() -> validate_capture_set(fixture_objects(swap_series = true))) == :api_series_order
end

@testset "complete monthly coverage and M13 rejection" begin
    @test error_code(() -> validate_capture_set(fixture_objects(stale_terminal = true))) == :monthly_coverage
    @test error_code(() -> validate_capture_set(fixture_objects(target_chunk = 1, arbitrary_start = true))) == :monthly_coverage
    @test error_code(() -> validate_capture_set(fixture_objects(target_chunk = 6, omit_period = true))) == :monthly_coverage
    @test error_code(() -> validate_capture_set(fixture_objects(target_chunk = 6, duplicate_period = true))) in (:api_period_order, :api_duplicate_period)
    @test error_code(() -> validate_capture_set(fixture_objects(target_chunk = 8, m13_contamination = true))) == :api_m13_forbidden
end

@testset "October 2025 explicit missing is not zero or interpolation" begin
    @test error_code(() -> validate_capture_set(fixture_objects(october_mode = :zero))) == :october_2025_not_missing
    @test error_code(() -> validate_capture_set(fixture_objects(october_mode = :interpolated))) == :october_2025_not_missing
    objects = fixture_objects()
    chunk_id = "api_2018_2026"
    text = String(objects[chunk_id])
    objects[chunk_id] = bytes(replace(text, "Data unavailable due to the 2025 lapse in appropriations." => "Missing"; count = 1))
    @test error_code(() -> validate_capture_set(objects)) == :october_2025_footnote
end

@testset "catalog and strict TSV drift" begin
    @test error_code(() -> validate_capture_set(fixture_objects(seasonal_drift = true))) == :catalog_seasonal_drift
    @test error_code(() -> validate_capture_set(fixture_objects(unit_drift = true))) == :catalog_unit_drift
    @test error_code(() -> validate_capture_set(fixture_objects(frequency_drift = true))) == :catalog_frequency_drift
    @test error_code(() -> validate_capture_set(fixture_objects(catalog_begin_override = 1949))) == :catalog_begin_drift
    @test error_code(() -> validate_capture_set(fixture_objects(catalog_terminal = "M08"))) == :catalog_terminal_drift
    @test error_code(() -> validate_capture_set(fixture_objects(duplicate_tsv = true))) == :catalog_duplicate_series
    @test error_code(() -> validate_capture_set(fixture_objects(irrelevant_rows = false))) == :catalog_full_object_required
    @test error_code(() -> validate_capture_set(fixture_objects(malformed_tsv = true))) == :tsv_malformed
    @test error_code(() -> parse_tsv_strict(bytes("a\ta\n1\t2\n"))) == :tsv_duplicate_header
    @test error_code(() -> parse_tsv_strict(bytes("a\tb\n1\n"))) == :tsv_malformed
    @test error_code(() -> parse_tsv_strict(bytes("a\n1\n2\n"), max_lines = 2)) == :tsv_line_limit
    @test error_code(() -> parse_tsv_strict(bytes("a\tb\n"), max_columns = 1)) == :tsv_column_limit
    @test error_code(() -> parse_tsv_strict(bytes("abcd\n"), max_field_bytes = 3)) == :tsv_field_limit
    @test error_code(() -> parse_tsv_strict(bytes("a\n"), max_bytes = 1)) == :tsv_size_limit
    @test error_code(() -> parse_tsv_strict(UInt8[0x61, 0x0a, 0xff, 0x0a])) == :tsv_invalid_utf8
    objects = fixture_objects()
    objects["catalog_ln_txt"] = UInt8[0xff]
    @test error_code(() -> validate_capture_set(objects)) == :text_invalid_utf8
end

@testset "object set, restamps, and permanent gates" begin
    objects = fixture_objects()
    delete!(objects, "api_1948_1957")
    @test error_code(() -> validate_capture_set(objects)) == :object_set_cardinality
    objects = fixture_objects()
    objects["extra"] = UInt8[]
    @test error_code(() -> validate_capture_set(objects)) == :object_set_cardinality
    string_objects = fixture_objects()
    untyped_objects = Dict{Any, Any}(string_objects)
    untyped_objects[:api_1948_1957] = pop!(untyped_objects, "api_1948_1957")
    @test error_code(() -> validate_capture_set(untyped_objects)) == :object_key_type

    objects = fixture_objects()
    result = validate_capture_set(objects)
    result["gates"]["origin_admissible"] = true
    result["artifact"]["content_sha256"] = repeat("0", 64)
    result["artifact"]["content_sha256"] = Candidate._canonical_sha256(result; exclude_artifact_hash = true)
    @test error_code(() -> validate_compiled_result(result, objects)) == :result_replay_mismatch

    objects = fixture_objects()
    result = validate_capture_set(objects)
    result["catalog_projection_receipt"]["selected_series_rows"][1]["physical_row_ordinal"] += 1
    result["catalog_projection_receipt"]["artifact"]["content_sha256"] = Candidate._canonical_sha256(result["catalog_projection_receipt"]; exclude_artifact_hash = true)
    result["artifact"]["content_sha256"] = Candidate._canonical_sha256(result; exclude_artifact_hash = true)
    @test error_code(() -> validate_compiled_result(result, objects)) == :result_replay_mismatch

    for mutator in (
            profile -> profile["artifact"]["status"] = "READY",
            profile -> profile["scope"]["network_action_count"] = 1,
            profile -> profile["scope"]["network_action_count"] = 0.0,
            profile -> profile["scope"]["network_action_count"] = false,
            profile -> profile["scope"]["current_qualified_count"] = 1,
            profile -> profile["scope"]["current_v3_integration"] = true,
            profile -> profile["gates"]["qualified_leaf"] = true,
            profile -> profile["release"]["single_release_time_api_capture_sufficient"] = true,
            profile -> profile["limits"]["max_ln_series_bytes"] = 67_108_864,
            profile -> profile["prohibited_actions"] = reverse(profile["prohibited_actions"]),
            profile -> profile["source_pins"][2]["binding_id"] = profile["source_pins"][1]["binding_id"],
            profile -> profile["routes"]["planned_catalog_base_url"] = "https://example.invalid/",
            profile -> profile["profiles"][1]["expected_begin_year"] = 1949,
        )
        profile = fixture_profile()
        mutator(profile)
        restamp_profile!(profile)
        @test error_code(() -> Candidate._validate_profile_document_unit(profile)) !== nothing
    end
end

@testset "operational source verification has no bypass" begin
    @test Candidate._validate_profile_document_unit(fixture_profile()) === nothing

    verifier_call_count = Ref(0)
    failing_verifier = function (profile)
        verifier_call_count[] += 1
        @test profile["source_pins"] == fixture_profile()["source_pins"]
        throw(CaptureSetError(:injected_source_verifier_failure, "test sentinel"))
    end
    @test error_code(() -> Candidate._validate_profile_with_source_verifier(PROFILE_PATH, failing_verifier)) == :injected_source_verifier_failure
    @test verifier_call_count[] == 1

    objects = fixture_objects()
    result = validate_capture_set(objects)
    @test_throws MethodError validate_profile(; verify_sources = false)
    @test_throws MethodError validate_capture_set(objects; verify_sources = false)
    @test_throws MethodError validate_compiled_result(result, objects; verify_sources = false)
    @test all(:verify_sources ∉ Base.kwarg_decl(method) for method in methods(validate_profile))
    @test all(:verify_sources ∉ Base.kwarg_decl(method) for method in methods(validate_capture_set))
    @test all(:verify_sources ∉ Base.kwarg_decl(method) for method in methods(validate_compiled_result))
end

@testset "no ambient working-directory dependency" begin
    @test isabspath(PROFILE_PATH)
    @test validate_profile() isa Dict
    @test error_code(() -> validate_profile("/private/tmp/alternate-profile.toml")) == :profile_path
    @test pwd() != TEST_DIRECTORY || true
end
