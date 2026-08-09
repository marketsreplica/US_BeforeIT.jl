using Dates
using SHA
using Test
using TOML

include(joinpath(@__DIR__, "BEANIPADiscovery.jl"))
include(joinpath(@__DIR__, "BEANIPAAcquisition.jl"))
using .BEANIPAAcquisition

const INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "current_inventory.toml"))
const MAPPING_AUDIT_PATH = joinpath(
    @__DIR__,
    "mapping_audit",
    "bea_nipa_mapping_audit.toml",
)

sha(bytes) = bytes2hex(SHA.sha256(bytes))

function synthetic_expectations()
    section_1_bytes =
        vcat(UInt8[0x50, 0x4b, 0x03, 0x04], codeunits("section-one"))
    section_2_bytes =
        vcat(UInt8[0x50, 0x4b, 0x03, 0x04], codeunits("section-two"))
    expectations = [
        ExpectedWorkbook(
            "synthetic_s1",
            PILOT_RELEASE_ID,
            "1",
            "https://apps.bea.gov/HistData/synthetic-section-1.xlsx",
            sha(section_1_bytes),
            length(section_1_bytes),
            Set(["gdp_deflator", "nominal_gdp", "real_gdp"]),
        ),
        ExpectedWorkbook(
            "synthetic_s2",
            PILOT_RELEASE_ID,
            "2",
            "https://apps.bea.gov/HistData/synthetic-section-2.xlsx",
            sha(section_2_bytes),
            length(section_2_bytes),
            Set(["core_pce_price_index", "pce_price_index"]),
        ),
    ]
    return expectations, [section_1_bytes, section_2_bytes]
end

function fetched(bytes, expectation; kwargs...)
    fields = Dict{Symbol, Any}(
        :raw_bytes => bytes,
        :http_status => 200,
        :content_type =>
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        :requested_locator => expectation.requested_locator,
        :effective_locator => expectation.requested_locator,
        :response_date => "Wed, 05 Aug 2026 22:41:15 GMT",
        :etag => "\"synthetic\"",
        :last_modified => "Thu, 30 Jul 2026 13:48:02 GMT",
        :content_length => string(length(bytes)),
        :acquisition_started_at_utc =>
            DateTime(2026, 8, 5, 22, 41, 14),
        :response_headers_at_utc =>
            DateTime(2026, 8, 5, 22, 41, 15),
        :acquisition_completed_at_utc =>
            DateTime(2026, 8, 5, 22, 41, 16),
    )
    merge!(fields, Dict(kwargs))
    return FetchedWorkbook(
        fields[:raw_bytes],
        fields[:http_status],
        fields[:content_type],
        fields[:requested_locator],
        fields[:effective_locator],
        fields[:response_date],
        fields[:etag],
        fields[:last_modified],
        fields[:content_length],
        fields[:acquisition_started_at_utc],
        fields[:response_headers_at_utc],
        fields[:acquisition_completed_at_utc],
    )
end

@testset "BEA NIPA acquisition transport contract" begin
    @test length(PILOT_EXPECTATIONS) == 2
    @test Set(row.section_id for row in PILOT_EXPECTATIONS) ==
        Set(["1", "2"])
    @test union((row.target_ids for row in PILOT_EXPECTATIONS)...) ==
        PILOT_TARGET_IDS
    @test sum(row.expected_byte_count for row in PILOT_EXPECTATIONS) ==
        8_927_142
    @test bundle_sha256() ==
        "9f4152937f58d777feb0f6562c1b1ca3681b0e51c1aa03b486fd5d29d1e794ff"

    audit = TOML.parsefile(MAPPING_AUDIT_PATH)
    audit_workbooks = Dict(
        row["workbook_id"] => row for row in audit["workbooks"]
    )
    for expectation in PILOT_EXPECTATIONS
        @test haskey(audit_workbooks, expectation.workbook_id)
        row = audit_workbooks[expectation.workbook_id]
        @test row["release_id"] == expectation.release_id
        @test row["section_id"] == expectation.section_id
        @test row["url"] == expectation.requested_locator
        @test row["sha256"] == expectation.expected_sha256
        @test !row["raw_bytes_persisted"]
    end
    audit_release = only(
        filter(
            row -> row["release_id"] == PILOT_RELEASE_ID,
            audit["releases"],
        ),
    )
    @test audit_release["profile_id"] == PILOT_MAPPING_PROFILE_ID
    @test !audit_release["historical_availability_verified"]
    @test !audit_release["origin_admissible"]
    @test !audit_release["ready"]

    expectations, bytes = synthetic_expectations()
    fetched_pair = [
        fetched(bytes[index], expectations[index]) for
            index in eachindex(expectations)
    ]
    validations = validate_fetched_pair(fetched_pair, expectations)
    @test [row.workbook_id for row in validations] ==
        ["synthetic_s1", "synthetic_s2"]
    @test [row.raw_sha256 for row in validations] ==
        [row.expected_sha256 for row in expectations]
    @test bundle_sha256(expectations) ==
        bundle_sha256(reverse(expectations))

    inventory_before = read(INVENTORY_PATH)
    mktempdir() do directory
        raw_root = joinpath(directory, "raw")
        result = persist_raw_bundle(
            raw_root,
            fetched_pair;
            expectations,
        )
        @test isdir(result.bundle_path)
        @test startswith(result.bundle_path, abspath(raw_root))
        @test Set(keys(result.workbook_paths)) ==
            Set(["synthetic_s1", "synthetic_s2"])
        @test all(isfile, values(result.workbook_paths))
        @test read(result.workbook_paths["synthetic_s1"]) == bytes[1]
        @test read(result.workbook_paths["synthetic_s2"]) == bytes[2]
        @test !result.historical_availability_verified
        @test !result.origin_admissible
        @test !result.ready

        repeated = persist_raw_bundle(
            raw_root,
            fetched_pair;
            expectations,
        )
        @test repeated.bundle_path == result.bundle_path

        open(result.workbook_paths["synthetic_s1"], "w") do io
            write(io, "tampered")
        end
        @test_throws AcquisitionError persist_raw_bundle(
            raw_root,
            fetched_pair;
            expectations,
        )
    end
    @test read(INVENTORY_PATH) == inventory_before

    mktempdir() do directory
        bad_bytes = copy(bytes[2])
        bad_bytes[end] = xor(bad_bytes[end], 0x01)
        bad_pair = [
            fetched_pair[1],
            fetched(bad_bytes, expectations[2]),
        ]
        raw_root = joinpath(directory, "raw")
        @test_throws AcquisitionError persist_raw_bundle(
            raw_root,
            bad_pair;
            expectations,
        )
        @test !ispath(raw_root)
    end

    @test_throws AcquisitionError validate_fetched_pair(
        fetched_pair[1:1],
        expectations,
    )
    @test_throws AcquisitionError validate_fetched_pair(
        fetched_pair,
        expectations[1:1],
    )
    @test_throws AcquisitionError validate_fetched_pair(
        [
            fetched(
                bytes[1],
                expectations[1];
                http_status = 404,
            ),
            fetched_pair[2],
        ],
        expectations,
    )
    @test_throws AcquisitionError validate_fetched_pair(
        [
            fetched(
                bytes[1],
                expectations[1];
                content_type = "text/html",
            ),
            fetched_pair[2],
        ],
        expectations,
    )
    @test_throws AcquisitionError validate_fetched_pair(
        [
            fetched(
                bytes[1],
                expectations[1];
                effective_locator =
                    "https://apps.bea.gov/HistData/other.xlsx",
            ),
            fetched_pair[2],
        ],
        expectations,
    )
    @test_throws AcquisitionError validate_fetched_pair(
        [
            fetched(
                bytes[1],
                expectations[1];
                content_length = "NOT_PROVIDED",
            ),
            fetched_pair[2],
        ],
        expectations,
    )
    @test_throws AcquisitionError validate_fetched_pair(
        [
            fetched(
                bytes[1],
                expectations[1];
                content_length = string(length(bytes[1]) + 1),
            ),
            fetched_pair[2],
        ],
        expectations,
    )
    @test_throws AcquisitionError validate_fetched_pair(
        [
            fetched(
                bytes[1],
                expectations[1];
                response_headers_at_utc =
                    DateTime(2026, 8, 5, 22, 41, 13),
            ),
            fetched_pair[2],
        ],
        expectations,
    )

    non_zip = copy(bytes[1])
    non_zip[1] = 0x00
    @test_throws AcquisitionError validate_fetched_pair(
        [fetched(non_zip, expectations[1]), fetched_pair[2]],
        expectations,
    )

    overlapped = [
        expectations[1],
        ExpectedWorkbook(
            expectations[2].workbook_id,
            expectations[2].release_id,
            expectations[2].section_id,
            expectations[2].requested_locator,
            expectations[2].expected_sha256,
            expectations[2].expected_byte_count,
            Set(
                [
                    "core_pce_price_index",
                    "nominal_gdp",
                    "pce_price_index",
                ],
            ),
        ),
    ]
    @test_throws AcquisitionError validate_fetched_pair(
        fetched_pair,
        overlapped,
    )

    mktempdir() do directory
        target = joinpath(directory, "target")
        mkdir(target)
        link = joinpath(directory, "raw")
        symlink(target, link)
        @test_throws AcquisitionError persist_raw_bundle(
            link,
            fetched_pair;
            expectations,
        )
    end
end
