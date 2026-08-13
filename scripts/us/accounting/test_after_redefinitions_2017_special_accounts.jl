using SHA
using Test
using TOML

include(
    joinpath(
        @__DIR__,
        "USAfterRedefinitions2017SpecialAccounts.jl",
    ),
)
using .USAfterRedefinitions2017SpecialAccounts

const SPECIAL2017_DIRECTORY = joinpath(
    @__DIR__,
    "fixtures",
    "bea_after_redefinitions_2017_special_accounts_vintage",
)
const SPECIAL2017_CELLS_PATH =
    joinpath(SPECIAL2017_DIRECTORY, "cells.csv")
const SPECIAL2017_MANIFEST_PATH =
    joinpath(SPECIAL2017_DIRECTORY, "manifest.toml")
const SPECIAL2017_FALLBACK_PATH = joinpath(
    @__DIR__,
    "extract_after_redefinitions_2017_special_accounts_values.py",
)
const SPECIAL2017_GENERATOR_PATH = joinpath(
    @__DIR__,
    "generate_after_redefinitions_2017_special_accounts_fixture.mjs",
)
const SPECIAL2017_COMPANION_MEMBERS = (
    "source_acquisition_receipt.json",
    "component_crosswalk.json",
    "generation_openpyxl.json",
    "generation_artifact_tool.json",
)

sha256_hex(bytes) = bytes2hex(SHA.sha256(bytes))

function copied_fixture()
    target = mktempdir()
    for filename in (
            "cells.csv",
            "manifest.toml",
            SPECIAL2017_COMPANION_MEMBERS...,
        )
        cp(
            joinpath(SPECIAL2017_DIRECTORY, filename),
            joinpath(target, filename),
        )
    end
    return target
end

function replace_once(path, source, replacement)
    text = read(path, String)
    length(findall(source, text)) == 1 ||
        error("test sentinel is not unique: $source")
    write(path, replace(text, source => replacement; count = 1))
    return path
end

function projection_mask_counts(projection)
    return (
        numeric = count(projection.numeric_mask),
        blank = count(projection.blank_mask),
        ellipsis = count(projection.ellipsis_mask),
        selected_zero =
            count(projection.selected_zero_not_shown_mask),
        negative = count(<(0.0), projection.values),
        explicit_numeric_zero = count(
            projection.numeric_mask .& iszero.(projection.values),
        ),
    )
end

function row_position(matrix, code)
    return something(findfirst(==(code), matrix.row_codes))
end

function column_position(matrix, code)
    codes = [
        isempty(summary) ? native : summary for
            (native, summary) in zip(
                matrix.column_codes,
                matrix.column_summary_industry_codes,
            )
    ]
    return something(findfirst(==(code), codes))
end

@testset "2017 after-redefinitions special-account evidence" begin
    fixture = load_after_redefinitions_2017_special_accounts(
        SPECIAL2017_DIRECTORY,
    )
    report =
        build_after_redefinitions_2017_special_accounts_diagnostic(
        SPECIAL2017_DIRECTORY,
    )
    manifest = TOML.parsefile(SPECIAL2017_MANIFEST_PATH)
    p = fixture.projections

    @testset "byte-pinned vintage and extraction provenance" begin
        @test strip(
            read(
                `node $SPECIAL2017_GENERATOR_PATH --self-test`,
                String,
            ),
        ) == "sourceCell native-kind self-test passed"
        @test sha256_hex(read(SPECIAL2017_CELLS_PATH)) ==
            "bb871c471b5bdc3dfea709749359717705167eff7e929bd9a2cc9071a21751e1"
        @test sha256_hex(read(SPECIAL2017_MANIFEST_PATH)) ==
            "2432fecb0aa9ada6fe1dfc33aa51d17888df66676290c34a14bdb97e1aa3c31f"
        @test sha256_hex(read(SPECIAL2017_FALLBACK_PATH)) ==
            "91cbb1d62bb4c55963616b70eb4e2d8667c2917fedec1b708fc4c281dd529b01"
        @test manifest["schema_version"] ==
            "beforeit-us-after-redefinitions-2017-special-accounts-fixture.v2"
        @test manifest["classification"] ==
            "2017_BENCHMARK_CURRENT_ARCHIVE_SNAPSHOT_NOT_ORIGIN_ELIGIBLE"
        @test manifest["artifact_role"] ==
            "VINTAGE_SPECIFIC_SPECIAL_ACCOUNT_RECONSTRUCTION_EVIDENCE_ONLY"
        @test manifest["promotion_status"] ==
            "RESEARCH_ONLY_NOT_PROMOTED"
        @test manifest["year"] == 2017
        @test manifest["benchmark_year"] == 2017
        @test manifest["source_zip_sha256"] ==
            "c93326b3e4ba3bc2024165448800acb89e9b549090b6b4e0c0c0db27c0eea7da"
        @test manifest["source_metadata_sha256"] ==
            "8be9fbef6e2c18a7388cd61bd14312159fc3984d4dbc2c60158e977ee7f0e878"
        @test manifest["detail_use_workbook_sha256"] ==
            "ee0f977ccc6b884d3e3b912596e39c1036f513880531dda33be947e68fb03fe4"
        @test manifest["summary_use_workbook_sha256"] ==
            "9e3791d657909843ce202161bae00cf8a425d7e1bf866cc8a0462810f0ae00c7"
        @test manifest["detail_make_workbook_sha256"] ==
            "96fb70a032e3ab81514231f49c2eae888b7ef8b741b00f352f2fc0fa8776db67"
        @test manifest["summary_make_workbook_sha256"] ==
            "073b87c7e52e76fb78ad7ddafb0c2e60f9188fc5a4e56dc0094f4a7ae3f529c6"
        @test manifest["generator_sha256"] ==
            sha256_hex(read(SPECIAL2017_GENERATOR_PATH))
        @test manifest["component_crosswalk_pinned"]
        @test manifest["component_crosswalk_source_printed_page"] == 15
        @test manifest["component_crosswalk_source_pdf_index"] == 14
        @test manifest["accepted_reader_contracts"] ==
            ["openpyxl=3.1.5", "artifact_tool=2.8.39"]
        @test manifest["openpyxl_fallback_sha256"] ==
            sha256_hex(read(SPECIAL2017_FALLBACK_PATH))
        @test sha256_hex(
            read(
                joinpath(
                    SPECIAL2017_DIRECTORY,
                    "source_acquisition_receipt.json",
                ),
            ),
        ) == manifest["source_metadata_sha256"]
        @test sha256_hex(
            read(
                joinpath(
                    SPECIAL2017_DIRECTORY,
                    "component_crosswalk.json",
                ),
            ),
        ) == manifest["component_crosswalk_sha256"]
        @test sha256_hex(
            read(
                joinpath(
                    SPECIAL2017_DIRECTORY,
                    "generation_openpyxl.json",
                ),
            ),
        ) ==
            "42c1d577b4b6b647592d6ab3c909538cb9f50b25a27c8dfcf212fae5e0f57f63"
        @test sha256_hex(
            read(
                joinpath(
                    SPECIAL2017_DIRECTORY,
                    "generation_artifact_tool.json",
                ),
            ),
        ) ==
            "4b121193e3099e1cf53e1e87908890b5ed54636cc286d38a84e56a12d11e26fa"
        @test manifest["fixture_cell_count"] == 3_644
        @test manifest["native_blank_count"] == 2_748
        @test manifest["ellipsis_not_shown_count"] == 188
        @test length(manifest["projection"]) == 10
        @test all(
            length(projection["projection_sha256"]) == 64 for
                projection in manifest["projection"]
        )
        @test manifest["reconstruction_scope"] ==
            "CODE_KEYED_FINAL_USE_AND_AGGREGATE_CONTROLS_ONLY"
    end

    @testset "complete signed cells and explicit masks" begin
        expected_shapes = Dict(
            "detail_use_intermediate_2017" => (4, 402),
            "detail_use_final_2017" => (4, 20),
            "detail_use_controls_2017" => (4, 3),
            "summary_use_intermediate_2017" => (2, 71),
            "summary_use_final_2017" => (2, 20),
            "summary_use_controls_2017" => (2, 3),
            "detail_make_components_2017" => (402, 4),
            "detail_make_output_2017" => (1, 4),
            "summary_make_components_2017" => (71, 2),
            "summary_make_output_2017" => (1, 2),
        )
        @test Set(keys(p)) == Set(keys(expected_shapes))
        for (projection_id, shape) in expected_shapes
            projection = p[projection_id]
            @test size(projection.values) == shape
            @test size(projection.numeric_mask) == shape
            @test size(projection.blank_mask) == shape
            @test size(projection.ellipsis_mask) == shape
            @test size(projection.selected_zero_not_shown_mask) ==
                shape
            @test all(
                projection.numeric_mask .+
                    projection.blank_mask .+
                    projection.ellipsis_mask .== 1,
            )
            @test projection.selected_zero_not_shown_mask ==
                projection.blank_mask .| projection.ellipsis_mask
            @test all(
                projection.values[
                    projection.selected_zero_not_shown_mask,
                ] .== 0.0,
            )
            @test length(unique(vec(projection.source_addresses))) ==
                prod(shape)
            @test projection.year == 2017
        end

        counts = map(projection_mask_counts, values(p))
        @test sum(count.numeric for count in counts) == 708
        @test sum(count.blank for count in counts) == 2_748
        @test sum(count.ellipsis for count in counts) == 188
        @test sum(count.selected_zero for count in counts) == 2_936
        @test sum(count.explicit_numeric_zero for count in counts) == 50
        @test sum(count.negative for count in counts) == 36
        @test minimum(
            p["detail_use_final_2017"].values,
        ) == -260_421.0

        detail_final = p["detail_use_final_2017"]
        s009 = row_position(detail_final, "S00900")
        f050 = column_position(detail_final, "F050")
        @test detail_final.values[s009, f050] == 26.0
        @test detail_final.numeric_mask[s009, f050]
        @test detail_final.source_addresses[s009, f050] == "OW408"
        @test detail_final.column_codes[f050] == "F05000"
        @test detail_final.column_summary_industry_codes[f050] == "F050"

        detail_intermediate = p["detail_use_intermediate_2017"]
        @test detail_intermediate.values[1, 1] == 0.0
        @test detail_intermediate.selected_zero_not_shown_mask[1, 1]
        @test detail_intermediate.blank_mask[1, 1]
        @test !detail_intermediate.ellipsis_mask[1, 1]
        @test !detail_intermediate.numeric_mask[1, 1]
        @test detail_intermediate.source_addresses[1, 1] == "C405"

        summary_intermediate = p["summary_use_intermediate_2017"]
        ellipsis_index = only(
            findall(==("E79"), summary_intermediate.source_addresses),
        )
        @test summary_intermediate.ellipsis_mask[ellipsis_index]
        @test !summary_intermediate.blank_mask[ellipsis_index]
        @test summary_intermediate.values[ellipsis_index] == 0.0

        numeric_zero = only(
            Iterators.take(
                findall(
                    summary_intermediate.numeric_mask .&
                        iszero.(summary_intermediate.values),
                ),
                1,
            ),
        )
        @test !summary_intermediate.blank_mask[numeric_zero]
        @test !summary_intermediate.ellipsis_mask[numeric_zero]
        @test !summary_intermediate.selected_zero_not_shown_mask[numeric_zero]
    end

    @testset "code-keyed final-use and exact-control reconstruction" begin
        @test report.final_use.account_codes == ["Used", "Other"]
        @test report.final_use.column_codes == String.(
            manifest["final_use_codes"],
        )
        expected_final_residuals = zeros(2, 20)
        expected_final_residuals[1, 1] = -1.0
        expected_final_residuals[1, 7] = -1.0
        expected_final_residuals[2, 8] = 1.0
        @test report.final_use.residuals == expected_final_residuals
        @test maximum(abs, report.final_use.residuals) == 1.0

        @test report.final_use.reconstructed[1, 1] == 81_329.0
        @test report.final_use.observed[1, 1] == 81_328.0
        @test report.final_use.reconstructed[1, 7] == 20_933.0
        @test report.final_use.observed[1, 7] == 20_932.0
        @test report.final_use.reconstructed[2, 8] == -260_395.0
        @test report.final_use.observed[2, 8] == -260_394.0
        @test report.final_use.reconstructed[2, 1] == -90_776.0
        @test report.final_use.observed[2, 1] == -90_776.0

        @test report.use_controls.reconstructed == [
            58_047.0 -47_284.0 10_763.0
            142_489.0 -139_021.0 3_468.0
        ]
        @test report.use_controls.observed ==
            report.use_controls.reconstructed
        @test all(iszero, report.use_controls.residuals)
        @test report.make_output.reconstructed ==
            reshape([10_763.0, 3_468.0], 2, 1)
        @test report.make_output.observed ==
            report.make_output.reconstructed
        @test all(iszero, report.make_output.residuals)

        @test report.detail_use_row_identity_residuals == [
            -1.0 0.0 0.0
            -1.0 3.0 0.0
            8.0 0.0 0.0
            0.0 0.0 0.0
        ]
        @test report.summary_use_row_identity_residuals == [
            0.0 1.0 0.0
            2.0 1.0 0.0
        ]
        @test report.detail_make_identity_residuals ==
            [-2.0, 0.0, 0.0, 0.0]
        @test report.summary_make_identity_residuals == [0.0, 0.0]
        @test all(
            iszero,
            report.detail_use_row_identity_residuals[:, 3],
        )
        @test all(
            iszero,
            report.summary_use_row_identity_residuals[:, 3],
        )
    end

    @testset "make placements are source accounting, not agents" begin
        @test length(report.detail_make_placements) == 80
        @test count(
            placement -> placement.account_code == "S00401",
            report.detail_make_placements,
        ) == 79
        @test count(
            placement -> placement.account_code == "S00402",
            report.detail_make_placements,
        ) == 0
        @test count(
            placement -> placement.account_code == "S00300",
            report.detail_make_placements,
        ) == 0
        detail_s009 = only(
            filter(
                placement -> placement.account_code == "S00900",
                report.detail_make_placements,
            ),
        )
        @test detail_s009.source_level == :detail
        @test detail_s009.industry_code == "S00600"
        @test detail_s009.account_code == "S00900"
        @test detail_s009.amount == 3_468.0
        @test detail_s009.source_address == "ON399"

        @test length(report.summary_make_placements) == 15
        @test count(
            placement -> placement.account_code == "Used",
            report.summary_make_placements,
        ) == 14
        summary_other = only(
            filter(
                placement -> placement.account_code == "Other",
                report.summary_make_placements,
            ),
        )
        @test summary_other.source_level == :summary
        @test summary_other.industry_code == "GFGN"
        @test summary_other.amount == 3_468.0
        @test summary_other.source_address == "BW75"

        @test !report.detail_to_summary_industry_crosswalk_pinned
        @test report.component_crosswalk_pinned
        @test !report.intermediate_cellwise_reconstruction_claimed
        @test !report.make_cellwise_reconstruction_claimed
        @test !report.runtime_materialization_selected
        @test !report.producer_agent_inference
        @test !report.government_producer_inference
        @test !report.zero_cash_inference
        @test !report.current_vintage_weight_inference
        @test !report.forecast_origin_admissible
        @test !report.model_state_write
        @test report.accounting_gate_effect == :none
        @test isempty(manifest["emitted_runtime_keys"])
        @test_throws ArgumentError materialize_after_redefinitions_2017_special_accounts_model_state(
            report,
        )
        @test after_redefinitions_2017_special_accounts_controls_pass(
            SPECIAL2017_DIRECTORY,
        )
    end

    @testset "source-aware adversarial failures" begin
        @test !(
            :report_controls_pass in names(
                USAfterRedefinitions2017SpecialAccounts;
                all = false,
            )
        )

        dropped = copied_fixture()
        dropped_path = joinpath(dropped, "cells.csv")
        dropped_lines = readlines(dropped_path; keep = true)
        deleteat!(
            dropped_lines,
            something(
                findfirst(
                    line -> occursin(
                        "detail_use_final_2017,2017,detail",
                        line,
                    ),
                    dropped_lines,
                ),
            ),
        )
        write(dropped_path, join(dropped_lines))
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            dropped,
        )
        @test_throws ArgumentError load_after_redefinitions_2017_special_accounts(
            dropped,
        )

        merged = copied_fixture()
        replace_once(
            joinpath(merged, "cells.csv"),
            ",C406,2,S00402,Used and secondhand goods,",
            ",C406,2,S00401,Used and secondhand goods,",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            merged,
        )

        clipped = copied_fixture()
        replace_once(
            joinpath(clipped, "cells.csv"),
            ",-116054,numeric",
            ",116054,numeric",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            clipped,
        )

        mask_changed = copied_fixture()
        replace_once(
            joinpath(mask_changed, "cells.csv"),
            ",C405,1,S00401,Scrap,DetailedSpecialCommodity,,1,1111A0,Oilseed farming,Industry,,0,blank",
            ",C405,1,S00401,Scrap,DetailedSpecialCommodity,,1,1111A0,Oilseed farming,Industry,,0,numeric",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            mask_changed,
        )

        paired_swap = copied_fixture()
        paired_path = joinpath(paired_swap, "cells.csv")
        replace_once(
            paired_path,
            ",OP405,1,S00401,Scrap,DetailedSpecialCommodity,,1,F01000,Personal consumption expenditures,FinalUse,F010,-12990,numeric",
            ",OP405,1,S00401,Scrap,DetailedSpecialCommodity,,1,F01000,Personal consumption expenditures,FinalUse,F010,-12989,numeric",
        )
        replace_once(
            paired_path,
            ",OP406,2,S00402,Used and secondhand goods,DetailedSpecialCommodity,,1,F01000,Personal consumption expenditures,FinalUse,F010,94319,numeric",
            ",OP406,2,S00402,Used and secondhand goods,DetailedSpecialCommodity,,1,F01000,Personal consumption expenditures,FinalUse,F010,94318,numeric",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            paired_swap,
        )

        government_agent = copied_fixture()
        replace_once(
            joinpath(government_agent, "manifest.toml"),
            "government_producer_inference = false",
            "government_producer_inference = true",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            government_agent,
        )

        zero_cash = copied_fixture()
        replace_once(
            joinpath(zero_cash, "manifest.toml"),
            "zero_cash_inference = false",
            "zero_cash_inference = true",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            zero_cash,
        )

        current_weight = copied_fixture()
        replace_once(
            joinpath(current_weight, "manifest.toml"),
            "current_vintage_weight_inference = false",
            "current_vintage_weight_inference = true",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            current_weight,
        )

        wrong_vintage = copied_fixture()
        replace_once(
            joinpath(wrong_vintage, "manifest.toml"),
            "year = 2017\nbenchmark_year = 2017",
            "year = 2024\nbenchmark_year = 2017",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            wrong_vintage,
        )

        source_hash = copied_fixture()
        replace_once(
            joinpath(source_hash, "manifest.toml"),
            manifest["detail_use_workbook_sha256"],
            repeat("0", 64),
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            source_hash,
        )

        source_receipt = copied_fixture()
        replace_once(
            joinpath(source_receipt, "source_acquisition_receipt.json"),
            "\"http_status\":200",
            "\"http_status\":201",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            source_receipt,
        )

        component_crosswalk = copied_fixture()
        replace_once(
            joinpath(component_crosswalk, "component_crosswalk.json"),
            "\"S00402\"",
            "\"S00300\"",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            component_crosswalk,
        )

        unpinned_component_crosswalk = copied_fixture()
        replace_once(
            joinpath(unpinned_component_crosswalk, "manifest.toml"),
            "component_crosswalk_pinned = true",
            "component_crosswalk_pinned = false",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            unpinned_component_crosswalk,
        )

        reader_receipt = copied_fixture()
        replace_once(
            joinpath(reader_receipt, "generation_openpyxl.json"),
            "\"reader_version\":\"3.1.5\"",
            "\"reader_version\":\"3.1.4\"",
        )
        @test !after_redefinitions_2017_special_accounts_controls_pass(
            reader_receipt,
        )
    end
end
