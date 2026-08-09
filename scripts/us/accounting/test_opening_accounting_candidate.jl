using CSV
using DataFrames
using Dates
using JLD2
using Random
using SHA
using Test
using TOML

import BeforeIT as Bit

include(
    joinpath(
        @__DIR__,
        "build_opening_accounting_candidate.jl",
    ),
)
using .USOpeningAccountingCandidate

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))
const CONFIG_PATH =
    joinpath(@__DIR__, "opening_macro_candidates.toml")
const FIXTURE_PATH =
    joinpath(@__DIR__, "fixtures", "bea_t10105_2026-08-04")

file_sha256(path) = bytes2hex(SHA.sha256(read(path)))

function execution_envelope_probe(arguments)
    probe = """
    using TOML
    include($(repr(joinpath(@__DIR__, "USJuliaExecutionEnvelope.jl"))))
    using .USJuliaExecutionEnvelope
    config = TOML.parsefile($(repr(CONFIG_PATH)))
    validate_build_environment(config)
    """
    command = `$(Base.julia_cmd()) $arguments --project=$(joinpath(REPO_ROOT, "scripts", "us")) -e $probe`
    output = IOBuffer()
    process = run(
        pipeline(
            ignorestatus(
                addenv(
                    command,
                    "JULIA_NUM_THREADS" => "1",
                    "OPENBLAS_NUM_THREADS" => "1",
                ),
            );
            stdout = output,
            stderr = output,
        ),
    )
    return (; succeeded = success(process), output = String(take!(output)))
end

@testset "T10105 current-dollar control fixture" begin
    fixture =
        USOpeningAccountingCandidate.UST10105Controls.load_t10105_fixture(
        FIXTURE_PATH,
    )
    @test nrow(fixture.frame) == 119
    @test first(fixture.frame.period) == Date(1996, 12, 31)
    @test last(fixture.frame.period) == Date(2026, 6, 30)
    @test fixture.validation.maximum_expenditure_residual == 0.5
    @test fixture.validation.maximum_investment_residual == 0.25

    structural =
        USOpeningAccountingCandidate.UST10105Controls.opening_control(
        fixture.frame,
        Date(2024, 12, 31),
    )
    @test structural.nominal_gdp == 7_456_295.5
    @test structural.nominal_household_consumption == 5_087_823.0
    @test structural.nominal_gross_private_domestic_investment ==
        1_315_457.5
    @test structural.nominal_fixed_investment == 1_311_010.25
    @test structural.nominal_inventory_investment == 4_447.25
    @test structural.nominal_exports == 812_063.75
    @test structural.nominal_imports == 1_046_730.25
    @test structural.nominal_government_consumption_and_investment ==
        1_287_681.25

    nowcast =
        USOpeningAccountingCandidate.UST10105Controls.opening_control(
        fixture.frame,
        Date(2026, 3, 31),
    )
    @test nowcast.nominal_inventory_investment == -7_013.25
    @test nowcast.nominal_gross_private_domestic_investment ==
        nowcast.nominal_fixed_investment +
        nowcast.nominal_inventory_investment
    @test nowcast.nominal_gdp -
        nowcast.nominal_household_consumption -
        nowcast.nominal_gross_private_domestic_investment -
        nowcast.nominal_exports +
        nowcast.nominal_imports -
        nowcast.nominal_government_consumption_and_investment ==
        -0.5

    materialized =
        USOpeningAccountingCandidate.UST10105Controls.materialize_control_series(
        fixture.frame,
        fixture.frame.period,
    )
    @test Set(keys(materialized)) == Set(
        String(specification.field)
            for specification in
            USOpeningAccountingCandidate.UST10105Controls.CONTROL_SPECS
    )
    @test materialized["nominal_inventory_investment_quarterly"][
        findfirst(==(Date(2026, 3, 31)), fixture.frame.period),
    ] == -7_013.25

    mktempdir() do directory
        cp(
            fixture.manifest_path,
            joinpath(directory, "manifest.toml"),
        )
        controls_path =
            joinpath(directory, "quarterly_controls.csv")
        cp(fixture.cells_path, controls_path)
        open(controls_path, "a") do io
            println(io)
        end
        @test_throws ArgumentError USOpeningAccountingCandidate.UST10105Controls.load_t10105_fixture(
            directory,
        )
    end
end

@testset "Opening-accounting candidate build" begin
    config = load_build_config(CONFIG_PATH; repo_root = REPO_ROOT)
    config_sha256 = file_sha256(CONFIG_PATH)
    canonical_envelope =
        current_execution_envelope() == config["execution_envelope"]
    if !canonical_envelope
        captured = try
            validate_build_environment(config)
            nothing
        catch error
            error
        end
        @test captured isa ExecutionEnvelopeMismatch
        if captured isa ExecutionEnvelopeMismatch
            @test captured.expected == config["execution_envelope"]
            @test captured.actual == current_execution_envelope()
            @test !isempty(captured.mismatches)
        end
    else
        protected_before = Dict(
            String(artifact["path"]) => file_sha256(
                    joinpath(REPO_ROOT, String(artifact["path"])),
                )
                for artifact in config["protected_artifact"]
        )
        expected = Dict(
            "structural_2024Q4_opening_accounting_v1" => (
                observed_residual = 0.25,
                latent_residual = -137_674.93989291706,
                inventory = 4_447.25,
                maximum_gap = 192_676.84386859543,
            ),
            "nowcast_2026Q1_opening_accounting_v1" => (
                observed_residual = -0.5,
                latent_residual = -147_094.19789356343,
                inventory = -7_013.25,
                maximum_gap = 182_460.51145266963,
            ),
        )

        built = Dict{String, Any}()
        for candidate in config["candidate"]
            result = build_candidate(
                config,
                candidate;
                repo_root = REPO_ROOT,
                config_sha256,
            )
            candidate_id = String(candidate["candidate_id"])
            built[candidate_id] = result
            expected_candidate = expected[candidate_id]
            reconciliation =
                result.metadata["opening_macro_reconciliation"]

            @test result.parameters["use_commodity_balance_inventory"] ===
                false
            @test isempty(
                intersect(
                    Set(keys(result.initial_conditions)),
                    USOpeningAccountingCandidate.REJECTED_INVENTORY_ALIAS_KEYS,
                ),
            )
            @test result.initial_conditions[
                "commodity_balance_closure_applied",
            ] === false
            @test sum(
                result.initial_conditions["unreconciled_commodity_gap_g"],
            ) ≈ -99_596.0625219554 atol = 1.0e-6
            @test reconciliation["observation_layer_gate"] ==
                "PASS_AT_SOURCE_ROUNDING"
            @test reconciliation["latent_state_reconciliation_gate"] ==
                "FAIL"
            @test reconciliation["structural_supply_use_gate"] == "FAIL"
            @test reconciliation["inventory_stock_gate"] ==
                "FAIL_MISSING_INDEPENDENT_QUARTER_END_STOCK"
            @test reconciliation["full_accounting_gate"] == "FAIL"
            @test reconciliation["forecast_promotion_gate"] == "FAIL"
            @test reconciliation["observed_expenditure_residual"] ==
                expected_candidate.observed_residual
            @test reconciliation["source_expenditure_residual"] ==
                expected_candidate.observed_residual
            @test reconciliation["model_implied_expenditure_residual"] ≈
                expected_candidate.latent_residual atol = 1.0e-6
            @test reconciliation["maximum_absolute_component_gap"] ≈
                expected_candidate.maximum_gap atol = 1.0e-6
            @test reconciliation["source_values"][
                "nominal_inventory_investment",
            ] == expected_candidate.inventory
            @test reconciliation["observed_values"][
                "nominal_inventory_investment",
            ] == expected_candidate.inventory
            @test reconciliation["model_implied_values"][
                "nominal_inventory_investment",
            ] == 0.0
            @test result.metadata["legacy_comparison"][
                "unaffected_parameters_bit_identical",
            ] === true
            @test result.metadata["legacy_comparison"][
                "unaffected_initial_conditions_bit_identical",
            ] === true
            @test Set(
                result.metadata["legacy_comparison"][
                    "removed_initial_condition_keys",
                ],
            ) ==
                USOpeningAccountingCandidate.REJECTED_INVENTORY_ALIAS_KEYS
            @test result.metadata["build_environment"][
                "julia_thread_count",
            ] == 1
            @test result.metadata["build_environment"][
                "blas_thread_count",
            ] == 1
            @test !isempty(
                result.metadata["build_environment"]["blas_vendor"],
            )
            @test result.metadata["build_environment"][
                "bounds_check_mode",
            ] == "auto"
            @test result.metadata["build_environment"][
                "bounds_check_code",
            ] == 0
            @test result.metadata["build_environment"]["opt_level"] == 2
            @test result.metadata["build_environment"][
                "fast_math_code",
            ] == 0
            @test result.metadata["build_environment"]["cpu_target"] ==
                "native"
            @test result.metadata["build_environment"][
                "startup_file_mode",
            ] == "no"
            @test result.metadata["build_environment"][
                "cross_machine_byte_determinism_claimed",
            ] === false
            @test result.metadata["build_environment"][
                "execution_validation_mode",
            ] == "CANONICAL_BYTE_BUILD"
            @test result.metadata["build_environment"][
                "canonical_execution_envelope_match",
            ] === true
            @test isempty(
                result.metadata["build_environment"][
                    "canonical_execution_envelope_mismatches",
                ],
            )
            @test result.metadata["build_environment"][
                "byte_identity_eligible",
            ] === true
            @test result.metadata["build_environment"][
                "supply_make_reader_sha256",
            ] == config["supply_make_reader_sha256"]
            @test result.metadata["build_environment"][
                "t10105_reader_sha256",
            ] == config["t10105_reader_sha256"]
            @test result.metadata["build_environment"][
                "runtime_source_tree_sha256",
            ] == config["runtime_source_tree_sha256"]
            @test result.metadata["build_environment"][
                "byte_reproducibility_scope",
            ] == "same_frozen_local_execution_envelope_only"
            @test result.metadata["simulated_accounting"]["gate"] ==
                "PASS_AFTER_OPENING"
            @test result.metadata["promotion_status"] ==
                "RESEARCH_ONLY_NOT_PROMOTED"
            @test result.metadata["forecast_origin_admissible"] === false
            @test validate_candidate(result) === result

            Random.seed!(Int(candidate["diagnostic_seed"]))
            model = Bit.Model(
                deepcopy(result.parameters),
                deepcopy(result.initial_conditions),
            )
            @test first(model.data.nominal_inventory_investment) ==
                expected_candidate.inventory
            @test first(
                Bit.get_accounting_residuals(
                    model.data,
                ).gdp_and_expenditure,
            ) == expected_candidate.observed_residual
            @test Bit.model_implied_opening_macro(model).expenditure_residual ≈
                expected_candidate.latent_residual atol = 1.0e-6
        end

        protected_after = Dict(
            String(artifact["path"]) => file_sha256(
                    joinpath(REPO_ROOT, String(artifact["path"])),
                )
                for artifact in config["protected_artifact"]
        )
        @test protected_after == protected_before

        deterministic_candidate =
            only(
            candidate for candidate in config["candidate"]
                if candidate["candidate_id"] ==
                "nowcast_2026Q1_opening_accounting_v1"
        )
        second_build = build_candidate(
            config,
            deterministic_candidate;
            repo_root = REPO_ROOT,
            config_sha256,
        )
        first_build = built["nowcast_2026Q1_opening_accounting_v1"]
        @test_throws ArgumentError build_candidate(
            config,
            deterministic_candidate;
            repo_root = REPO_ROOT,
            config_sha256 = "",
        )
        @test_throws ArgumentError build_candidate(
            config,
            deterministic_candidate;
            repo_root = REPO_ROOT,
            config_sha256 = repeat("0", 64),
        )
        @test_throws ArgumentError build_candidate(
            deepcopy(config),
            deterministic_candidate;
            repo_root = REPO_ROOT,
            config_sha256,
        )
        mutated_config =
            load_build_config(CONFIG_PATH; repo_root = REPO_ROOT)
        mutated_config["scale"] = nextfloat(Float64(mutated_config["scale"]))
        @test_throws ArgumentError build_candidate(
            mutated_config,
            deterministic_candidate;
            repo_root = REPO_ROOT,
            config_sha256,
        )
        @test second_build.semantic_sha256 ==
            first_build.semantic_sha256
        @test isequal(second_build.parameters, first_build.parameters)
        @test isequal(
            second_build.initial_conditions,
            first_build.initial_conditions,
        )
        @test isequal(second_build.metadata, first_build.metadata)

        mktempdir() do directory
            first_path = joinpath(directory, "first.jld2")
            second_path = joinpath(directory, "second.jld2")
            first_written = write_candidate(first_build, first_path)
            second_written = write_candidate(second_build, second_path)
            @test first_written.raw_sha256 ==
                second_written.raw_sha256
            @test read(first_path) == read(second_path)
            loaded = JLD2.load(first_path)
            loaded_result = (;
                parameters = loaded["parameters"],
                initial_conditions = loaded["initial_conditions"],
                metadata = loaded["metadata"],
                semantic_sha256 =
                    loaded["metadata"]["semantic_sha256"],
            )
            @test validate_candidate(loaded_result) === loaded_result
        end

        protected_path = joinpath(
            REPO_ROOT,
            first(config["protected_artifact"])["path"],
        )
        @test_throws ArgumentError write_candidate(
            first_build,
            protected_path;
            protected_paths = [protected_path],
        )
        @test_throws ArgumentError write_candidate(
            first_build,
            protected_path,
        )

        bad_config = deepcopy(config)
        bad_config["validation_manifest_path"] =
            first(bad_config["candidate"])["output_path"]
        temporary_config_path, temporary_config_io = mktemp()
        try
            TOML.print(temporary_config_io, bad_config; sorted = true)
            close(temporary_config_io)
            @test_throws ArgumentError load_build_config(
                temporary_config_path;
                repo_root = REPO_ROOT,
            )
        finally
            isopen(temporary_config_io) && close(temporary_config_io)
            isfile(temporary_config_path) && rm(temporary_config_path)
        end

        for hash_key in (
                "supply_make_reader_sha256",
                "t10105_reader_sha256",
                "runtime_source_tree_sha256",
            )
            bad_provenance = deepcopy(config)
            bad_provenance[hash_key] = repeat("0", 64)
            bad_path, bad_io = mktemp()
            try
                TOML.print(bad_io, bad_provenance; sorted = true)
                close(bad_io)
                @test_throws ArgumentError load_build_config(
                    bad_path;
                    repo_root = REPO_ROOT,
                )
            finally
                isopen(bad_io) && close(bad_io)
                isfile(bad_path) && rm(bad_path)
            end
        end

        for (key, value) in (
                ("bounds_check_mode", "yes"),
                ("bounds_check_code", 1),
                ("opt_level", 0),
                ("fast_math_code", 1),
                ("cpu_target", "generic"),
                ("platform_triplet", "x86_64-linux-gnu"),
                ("cpu_name", "unknown"),
            )
            bad_environment = deepcopy(config)
            bad_environment["execution_envelope"][key] = value
            @test_throws ArgumentError validate_build_environment(
                bad_environment,
            )
        end

        for arguments in (
                ["--check-bounds=yes"],
                ["-O0"],
                ["--math-mode=ieee"],
                ["--inline=no"],
                ["--cpu-target=generic"],
            )
            probe = execution_envelope_probe(arguments)
            @test !probe.succeeded
            @test occursin(
                "candidate build execution envelope mismatch",
                probe.output,
            )
        end
    end
end

@testset "Installed candidate manifest" begin
    manifest_path =
        joinpath(REPO_ROOT, "data", "us", "validation", "OPENING_MACRO_CANDIDATES.toml")
    manifest = TOML.parsefile(manifest_path)
    config = load_build_config(CONFIG_PATH; repo_root = REPO_ROOT)
    config_sha256 = file_sha256(CONFIG_PATH)
    @test manifest["schema_version"] ==
        USOpeningAccountingCandidate.MANIFEST_SCHEMA
    @test manifest["classification"] ==
        "REVISED_CURRENT_VINTAGE_DIAGNOSTIC"
    @test manifest["forecast_origin_admissible"] === false
    @test manifest["promotion_status"] ==
        "RESEARCH_ONLY_NOT_PROMOTED"
    @test manifest["legacy_artifacts_unchanged"] === true
    @test Int(manifest["candidate_count"]) == 2
    @test config_sha256 == manifest["build_contract_sha256"]
    @test manifest["execution_envelope"] ==
        config["execution_envelope"]
    @test manifest["byte_reproducibility_scope"] ==
        "same_frozen_local_execution_envelope_only"
    @test manifest["cross_machine_byte_determinism_claimed"] ===
        false
    for (path_key, hash_key) in (
            ("builder_path", "builder_sha256"),
            (
                "execution_envelope_module_path",
                "execution_envelope_module_sha256",
            ),
            ("supply_make_reader_path", "supply_make_reader_sha256"),
            ("t10105_reader_path", "t10105_reader_sha256"),
            ("julia_project_path", "julia_project_sha256"),
            ("julia_manifest_path", "julia_manifest_sha256"),
        )
        @test file_sha256(
            joinpath(REPO_ROOT, String(manifest[path_key])),
        ) == manifest[hash_key]
    end
    runtime_digest = source_tree_digest(
        joinpath(REPO_ROOT, String(manifest["runtime_source_tree_path"])),
    )
    @test runtime_digest.algorithm ==
        manifest["runtime_source_tree_digest_algorithm"]
    @test runtime_digest.file_count ==
        manifest["runtime_source_tree_file_count"]
    @test runtime_digest.sha256 ==
        manifest["runtime_source_tree_sha256"]

    for candidate in manifest["candidate"]
        artifact_path =
            joinpath(REPO_ROOT, String(candidate["artifact_path"]))
        @test file_sha256(artifact_path) ==
            candidate["artifact_sha256"]
        payload = JLD2.load(artifact_path)
        installed = (;
            parameters = payload["parameters"],
            initial_conditions = payload["initial_conditions"],
            metadata = payload["metadata"],
            semantic_sha256 = payload["metadata"]["semantic_sha256"],
        )
        @test validate_candidate(installed) === installed
        @test payload["metadata"]["semantic_sha256"] ==
            candidate["semantic_sha256"]
        @test candidate["opening_macro_control_identity"] ==
            "PASS_AT_SOURCE_ROUNDING"
        @test candidate["latent_state_reconciliation"] == "FAIL"
        @test candidate["structural_supply_use"] == "FAIL"
        @test candidate["overall_accounting_promotion"] == "FAIL"
        @test candidate["origin_admissible"] === false
    end

    if current_execution_envelope() == config["execution_envelope"]
        config_candidates = Dict(
            String(candidate["candidate_id"]) => candidate
                for candidate in config["candidate"]
        )
        mktempdir() do directory
            for candidate in manifest["candidate"]
                artifact_path =
                    joinpath(REPO_ROOT, String(candidate["artifact_path"]))
                candidate_id = String(candidate["candidate_id"])
                rebuilt = build_candidate(
                    config,
                    config_candidates[candidate_id];
                    repo_root = REPO_ROOT,
                    config_sha256,
                )
                @test rebuilt.semantic_sha256 ==
                    candidate["semantic_sha256"]
                rebuilt_path =
                    joinpath(directory, candidate_id * ".jld2")
                written = write_candidate(rebuilt, rebuilt_path)
                @test written.raw_sha256 ==
                    candidate["artifact_sha256"]
                @test read(rebuilt_path) == read(artifact_path)
            end
        end
    else
        captured = try
            validate_build_environment(config)
            nothing
        catch error
            error
        end
        @test captured isa ExecutionEnvelopeMismatch
        if captured isa ExecutionEnvelopeMismatch
            @test captured.expected == config["execution_envelope"]
            @test captured.actual == current_execution_envelope()
            @test !isempty(captured.mismatches)
        end
    end
end
