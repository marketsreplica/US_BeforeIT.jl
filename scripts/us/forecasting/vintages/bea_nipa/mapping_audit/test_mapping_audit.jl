using Test
using TOML

include(joinpath(@__DIR__, "BEANIPAMappingAudit.jl"))
using .BEANIPAMappingAudit

const EXPECTED_PROFILE_RELEASES = Dict(
    "pre_december_2003_section7" => ["r2003q1_advance"],
    "december_2003_layout" =>
        ["r2003q3_final", "r2007q1_advance", "r2009q1_final"],
    "july_2009_pce_redesign" => ["r2009q2_advance"],
    "july_2010_core_line_25" =>
        ["r2010q2_advance", "r2013q1_advance", "r2013q1_third"],
    "july_2013_rebase" =>
        ["r2013q2_advance", "r2017q1_advance", "r2017q2_third"],
    "october_2017_modern_workbook" =>
        ["r2017q3_advance", "r2018q1_third"],
    "july_2018_rebase" =>
        ["r2018q2_advance", "r2020q1_advance", "r2023q2_second"],
    "september_2023_rebase" => ["r2023q2_third", "r2026q2_advance"],
)

const EXPECTED_MAPPING_FINGERPRINTS = [
    "december_2003_layout|core_pce_price_index|2|20304 Qtr|2.3.4|23|33|BA03RG3|quarterly|seasonally_adjusted|index|2000",
    "december_2003_layout|gdp_deflator|1|10109 Qtr|1.1.9|1|10|A191RD3|quarterly|seasonally_adjusted|index|2000",
    "december_2003_layout|nominal_gdp|1|10105 Qtr|1.1.5|1|10|A191RC1|quarterly|seasonally_adjusted_annual_rate|billions_of_dollars|not_applicable",
    "december_2003_layout|pce_price_index|2|20304 Qtr|2.3.4|1|10|B002RG3|quarterly|seasonally_adjusted|index|2000",
    "december_2003_layout|real_gdp|1|10106 Qtr|1.1.6|1|10|A191RX1|quarterly|seasonally_adjusted_annual_rate|billions_of_chained_dollars|2000",
    "july_2009_pce_redesign|core_pce_price_index|2|20304 Qtr|2.3.4|26|36|DPCCRG3|quarterly|seasonally_adjusted|index|2005",
    "july_2009_pce_redesign|gdp_deflator|1|10109 Qtr|1.1.9|1|10|A191RD3|quarterly|seasonally_adjusted|index|2005",
    "july_2009_pce_redesign|nominal_gdp|1|10105 Qtr|1.1.5|1|10|A191RC1|quarterly|seasonally_adjusted_annual_rate|billions_of_dollars|not_applicable",
    "july_2009_pce_redesign|pce_price_index|2|20304 Qtr|2.3.4|1|10|DPCERG3|quarterly|seasonally_adjusted|index|2005",
    "july_2009_pce_redesign|real_gdp|1|10106 Qtr|1.1.6|1|10|A191RX1|quarterly|seasonally_adjusted_annual_rate|billions_of_chained_dollars|2005",
    "july_2010_core_line_25|core_pce_price_index|2|20304 Qtr|2.3.4|25|35|DPCCRG3|quarterly|seasonally_adjusted|index|2005",
    "july_2010_core_line_25|gdp_deflator|1|10109 Qtr|1.1.9|1|10|A191RD3|quarterly|seasonally_adjusted|index|2005",
    "july_2010_core_line_25|nominal_gdp|1|10105 Qtr|1.1.5|1|10|A191RC1|quarterly|seasonally_adjusted_annual_rate|billions_of_dollars|not_applicable",
    "july_2010_core_line_25|pce_price_index|2|20304 Qtr|2.3.4|1|10|DPCERG3|quarterly|seasonally_adjusted|index|2005",
    "july_2010_core_line_25|real_gdp|1|10106 Qtr|1.1.6|1|10|A191RX1|quarterly|seasonally_adjusted_annual_rate|billions_of_chained_dollars|2005",
    "july_2013_rebase|core_pce_price_index|2|20304 Qtr|2.3.4|25|35|DPCCRG3|quarterly|seasonally_adjusted|index|2009",
    "july_2013_rebase|gdp_deflator|1|10109 Qtr|1.1.9|1|10|A191RD3|quarterly|seasonally_adjusted|index|2009",
    "july_2013_rebase|nominal_gdp|1|10105 Qtr|1.1.5|1|10|A191RC1|quarterly|seasonally_adjusted_annual_rate|billions_of_dollars|not_applicable",
    "july_2013_rebase|pce_price_index|2|20304 Qtr|2.3.4|1|10|DPCERG3|quarterly|seasonally_adjusted|index|2009",
    "july_2013_rebase|real_gdp|1|10106 Qtr|1.1.6|1|10|A191RX1|quarterly|seasonally_adjusted_annual_rate|billions_of_chained_dollars|2009",
    "july_2018_rebase|core_pce_price_index|2|T20304-Q|2.3.4|25|34|DPCCRG|quarterly|seasonally_adjusted|index|2012",
    "july_2018_rebase|gdp_deflator|1|T10109-Q|1.1.9|1|9|A191RD|quarterly|seasonally_adjusted|index|2012",
    "july_2018_rebase|nominal_gdp|1|T10105-Q|1.1.5|1|9|A191RC|quarterly|seasonally_adjusted_annual_rate|millions_of_dollars|not_applicable",
    "july_2018_rebase|pce_price_index|2|T20304-Q|2.3.4|1|9|DPCERG|quarterly|seasonally_adjusted|index|2012",
    "july_2018_rebase|real_gdp|1|T10106-Q|1.1.6|1|9|A191RX|quarterly|seasonally_adjusted_annual_rate|millions_of_chained_dollars|2012",
    "october_2017_modern_workbook|core_pce_price_index|2|T20304-Q|2.3.4|25|34|DPCCRG|quarterly|seasonally_adjusted|index|2009",
    "october_2017_modern_workbook|gdp_deflator|1|T10109-Q|1.1.9|1|9|A191RD|quarterly|seasonally_adjusted|index|2009",
    "october_2017_modern_workbook|nominal_gdp|1|T10105-Q|1.1.5|1|9|A191RC|quarterly|seasonally_adjusted_annual_rate|millions_of_dollars|not_applicable",
    "october_2017_modern_workbook|pce_price_index|2|T20304-Q|2.3.4|1|9|DPCERG|quarterly|seasonally_adjusted|index|2009",
    "october_2017_modern_workbook|real_gdp|1|T10106-Q|1.1.6|1|9|A191RX|quarterly|seasonally_adjusted_annual_rate|millions_of_chained_dollars|2009",
    "pre_december_2003_section7|core_pce_price_index|7|704 Qtr|7.4|46|59|BA03RG|quarterly|seasonally_adjusted|index|1996",
    "pre_december_2003_section7|gdp_deflator|7|701 Qtr|7.1|4|14|A191RD|quarterly|seasonally_adjusted|index|1996",
    "pre_december_2003_section7|nominal_gdp|1|101 Qtr|1.1|1|10|A191RC|quarterly|seasonally_adjusted_annual_rate|billions_of_dollars|not_applicable",
    "pre_december_2003_section7|pce_price_index|7|704 Qtr|7.4|24|36|B002RG|quarterly|seasonally_adjusted|index|1996",
    "pre_december_2003_section7|real_gdp|1|102 Qtr|1.2|1|10|A191RX|quarterly|seasonally_adjusted_annual_rate|billions_of_chained_dollars|1996",
    "september_2023_rebase|core_pce_price_index|2|T20304-Q|2.3.4|25|34|DPCCRG|quarterly|seasonally_adjusted|index|2017",
    "september_2023_rebase|gdp_deflator|1|T10109-Q|1.1.9|1|9|A191RD|quarterly|seasonally_adjusted|index|2017",
    "september_2023_rebase|nominal_gdp|1|T10105-Q|1.1.5|1|9|A191RC|quarterly|seasonally_adjusted_annual_rate|millions_of_dollars|not_applicable",
    "september_2023_rebase|pce_price_index|2|T20304-Q|2.3.4|1|9|DPCERG|quarterly|seasonally_adjusted|index|2017",
    "september_2023_rebase|real_gdp|1|T10106-Q|1.1.6|1|9|A191RX|quarterly|seasonally_adjusted_annual_rate|millions_of_chained_dollars|2017",
]

const EXPECTED_BREAK_ENDPOINTS = Dict(
    "december_2003_table_redesign" =>
        ("r2003q3_preliminary", "r2003q3_final"),
    "july_2009_pce_redesign_and_rebase" =>
        ("r2009q1_final", "r2009q2_advance"),
    "july_2010_core_line_shift" => ("r2010q1_third", "r2010q2_advance"),
    "july_2013_rebase" => ("r2013q1_third", "r2013q2_advance"),
    "october_2017_workbook_modernization" =>
        ("r2017q2_third", "r2017q3_advance"),
    "july_2018_rebase" => ("r2018q1_third", "r2018q2_advance"),
    "september_2023_rebase" => ("r2023q2_second", "r2023q2_third"),
)

@testset "BEA NIPA ephemeral mapping audit" begin
    audit = load_mapping_audit()
    artifact = audit.artifact

    @test audit.sha256 == EXPECTED_AUDIT_SHA256
    @test audit.bytes > 0
    @test artifact["provenance_scope"] == "ephemeral_research_audit_only"
    @test artifact["raw_bytes_persisted"] === false
    @test artifact["historical_availability_verified"] === false
    @test artifact["origin_admissible"] === false
    @test artifact["ready"] === false
    @test artifact["uninspected_release_profile_assignment_allowed"] === false
    @test length(audit.workbooks_by_id) == 40
    @test length(audit.releases_by_id) == 20
    @test length(audit.profiles_by_id) == 8
    @test length(audit.breaks_by_id) == 7
    @test length(audit.gaps_by_id) == 9

    @test Set(keys(EXPECTED_PROFILE_RELEASES)) ==
        Set(keys(audit.profiles_by_id))
    for (profile_id, expected_releases) in EXPECTED_PROFILE_RELEASES
        profile = audit.profiles_by_id[profile_id]
        @test profile["inspected_release_ids"] == expected_releases
        @test profile["uninspected_release_assignment_allowed"] === false
        for release_id in expected_releases
            @test profile_for_release(audit, release_id) === profile
            @test audit.releases_by_id[release_id][
                "ephemeral_audit_profile_assignment_eligible",
            ] === true
            @test audit.releases_by_id[release_id]["origin_admissible"] === false
        end
    end

    actual_fingerprints = sort!(
        [
            mapping_fingerprint(profile["profile_id"], target) for
                profile in values(audit.profiles_by_id) for
                target in profile["targets"]
        ],
    )
    @test actual_fingerprints == sort(EXPECTED_MAPPING_FINGERPRINTS)

    @test Set(keys(EXPECTED_BREAK_ENDPOINTS)) == Set(keys(audit.breaks_by_id))
    for (break_id, endpoints) in EXPECTED_BREAK_ENDPOINTS
        break_record = audit.breaks_by_id[break_id]
        @test (
            break_record["older_release_id"],
            break_record["newer_release_id"],
        ) == endpoints
        @test break_record["adjacent_release_verified"] === true
        @test break_record["mapping_break_demonstrated"] === true
        @test break_record["historical_availability_verified"] === false
        @test break_record["origin_admissible"] === false
        @test break_record["ready"] === false
    end

    @test audit.workbooks_by_id["r2003q1_advance_s7"]["sha256"] ==
        "2e2fc39e8bee3ede0bdf08cbb01340021ac3c0f67a2d887b9d1a755e46704964"
    @test audit.workbooks_by_id["r2007q1_advance_s2"]["sha256"] ==
        "9243b9dfaf4fe141726bd6c47991069c00702e0c1247164140a928cb6cf80d77"
    @test audit.workbooks_by_id["r2026q2_advance_s2"]["retrieved_at_utc"] ==
        "2026-08-05T21:55:34.763259Z"
    @test audit.releases_by_id["r2020q1_advance"][
        "archive_label_date_matches_embedded_publication_date",
    ] === false

    @test_throws MappingAuditError profile_for_release(
        audit,
        "r2010q1_third",
    )
    @test_throws MappingAuditError profile_for_release(
        audit,
        "r2014q1_uninspected",
    )

    parsed = TOML.parsefile(AUDIT_ARTIFACT_PATH)
    mutations = [
        document ->
        document["artifact"]["raw_bytes_persisted"] = true,
        document ->
        document["artifact"]["provenance_scope"] = "acquisition",
        document ->
        document["artifact"]["historical_availability_verified"] = true,
        document ->
        document["artifact"]["origin_admissible"] = true,
        document ->
        document["artifact"]["ready"] = true,
        document -> document["artifact"][
            "uninspected_release_profile_assignment_allowed",
        ] = true,
        document ->
        document["workbooks"][1]["raw_bytes_persisted"] = true,
        document ->
        document["releases"][2][
            "ephemeral_audit_profile_assignment_eligible",
        ] = true,
        document ->
        document["profiles"][1]["uninspected_release_assignment_allowed"] =
            true,
        document ->
        document["breaks"][1]["historical_availability_verified"] = true,
        document ->
        pop!(document["evidence_gaps"]),
    ]
    for mutate! in mutations
        bad = deepcopy(parsed)
        mutate!(bad)
        @test_throws MappingAuditError validate_mapping_audit(bad)
    end

    mktemp() do path, io
        text = read(AUDIT_ARTIFACT_PATH, String)
        write(
            io,
            replace(
                text,
                "ephemeral_research_audit_only" =>
                    "ephemeral_research_audit_ONLY";
                count = 1,
            ),
        )
        close(io)
        @test_throws MappingAuditError validate_mapping_audit_file(path)
    end
end
