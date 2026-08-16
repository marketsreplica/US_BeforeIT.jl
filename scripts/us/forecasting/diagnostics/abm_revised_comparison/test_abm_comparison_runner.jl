#!/usr/bin/env julia

# Runner regression tests for the ABM comparison.
#
# These cover the failure modes an external review reproduced against the previous
# runner: a cache that could be silently reused under a different calibration, a
# truncated run that still called itself a complete comparison, an --also-score
# source admitted on its variant label alone, and an origin that lost paths but
# still counted as whole. Each test asserts the refusal, not merely the absence of
# a wrong answer.
#
# The last test re-scores the committed v2 headline cache and asserts its
# score_summaries.csv is byte-identical to the committed file, which is what makes
# the published numbers auditable from this suite.

using SHA
using Test
using TOML

const HERE = @__DIR__
const REPO_ROOT = normpath(joinpath(HERE, "..", "..", "..", "..", ".."))

const RUNNER = joinpath(HERE, "run_revised_data_abm_comparison.jl")

# The companion loader lives in the runner script, and the runner includes the
# comparison module and defines the ABM/BASE aliases. Including the runner here
# means these tests exercise the real entry path rather than a re-implementation
# of it; `main` does not execute because PROGRAM_FILE is this test file.
include(RUNNER)

const FIXTURE_DIRECTORY =
    normpath(joinpath(HERE, "..", "revised_data", "fixtures"))
const BASELINE_CALIBRATION =
    joinpath(REPO_ROOT, "data", "us", "calibration", "US_2024_calibration_object.jld2")
const RECONCILED_CALIBRATION = joinpath(
    REPO_ROOT,
    "data",
    "us",
    "calibration",
    "US_2024_calibration_object_reconciled.jld2",
)
const COMMITTED_V1_HEADLINE = joinpath(
    REPO_ROOT,
    "output",
    "us_forecasting",
    "abm_v2_comparison",
    "v1_headline",
)
const COMMITTED_V2_HEADLINE = joinpath(
    REPO_ROOT,
    "output",
    "us_forecasting",
    "abm_v2_comparison",
    "v2_headline",
)

load_panel() = BASE.load_revised_quarterly_panel(
    joinpath(FIXTURE_DIRECTORY, "quarterly_panel.csv"),
    joinpath(FIXTURE_DIRECTORY, "manifest.toml"),
)

"""
    tiny_origins(panel, count)

The first `count` scored origins, so a test cache costs seconds rather than hours.
"""
function tiny_origins(panel, count)
    all_origins = [
        (index, panel.periods[index]) for
            index in BASE.MINIMUM_TRAINING_QUARTERS:(length(panel.periods) - 1)
    ]
    return all_origins[1:count]
end

function generate_tiny_cache(directory, calibration_path; paths = 4, origins = 2)
    mkpath(directory)
    panel = load_panel()
    selected = tiny_origins(panel, origins)
    identity = ABM.build_cache_identity(
        ABM.HEADLINE_VARIANT,
        selected;
        paths = paths,
        calibration_path = calibration_path,
        panel = panel,
    )
    ABM.ACTIVE_CALIBRATION_PATH[] = calibration_path
    simulated = ABM.simulate_abm_ensembles(
        ABM.HEADLINE_VARIANT,
        selected;
        paths = paths,
        cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
        diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
        calibration_path = calibration_path,
        identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
        identity = identity,
        progress = false,
    )
    return (; panel, selected, identity, simulated)
end

@testset "ABM comparison runner regressions" begin

    @testset "cache poisoning is refused, not silently reused" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            @test length(generated.simulated.diagnostics) == 2
            @test isfile(joinpath(directory, ABM.CACHE_IDENTITY_FILENAME))

            # Same variant, same origins, different calibration artifact: the run
            # that reused this cache previously reported "already cached".
            poisoned = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                calibration_path = RECONCILED_CALIBRATION,
                panel = generated.panel,
            )
            thrown = nothing
            try
                ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                    diagnostics_path =
                        joinpath(directory, "abm_origin_diagnostics.csv"),
                    calibration_path = RECONCILED_CALIBRATION,
                    identity_path =
                        joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = poisoned,
                    progress = false,
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            # Whichever calibration field is compared first, the refusal must name
            # the calibration, not fall through to a silent reuse.
            @test thrown.field in
                ("calibration_object_path", "calibration_object_sha256")
            message = sprint(showerror, thrown)
            @test occursin("cache identity mismatch", message)
            println("  refusal (cache poisoning): ", message)

            # A changed path count is refused on its own field.
            wrong_paths = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 8,
                calibration_path = BASELINE_CALIBRATION,
                panel = generated.panel,
            )
            path_error = nothing
            try
                ABM.validate_cache_identity(
                    wrong_paths,
                    ABM.read_cache_identity(
                        joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    ),
                )
            catch error
                path_error = error
            end
            @test path_error isa ABM.CacheIdentityError
            @test path_error.field == "paths_requested"
            println("  refusal (path count): ", sprint(showerror, path_error))
        end
    end

    @testset "an unauthenticated cache cannot be adopted by accident" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            rm(joinpath(directory, ABM.CACHE_IDENTITY_FILENAME))
            thrown = nothing
            try
                ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                    diagnostics_path =
                        joinpath(directory, "abm_origin_diagnostics.csv"),
                    calibration_path = BASELINE_CALIBRATION,
                    identity_path =
                        joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = generated.identity,
                    progress = false,
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test occursin("--adopt-cache-identity", sprint(showerror, thrown))
            println("  refusal (legacy cache): ", sprint(showerror, thrown))
        end
    end

    @testset "a truncated run is smoke-only and cannot be reported" begin
        panel = load_panel()
        canonical = ABM.canonical_origin_count(panel)
        @test canonical == 61

        # One origin's worth of coverage must never earn a ranking.
        smoke = ABM.comparison_weighted_scores(
            BASE.RelativeScore[],
            ["beforeit_abm_us_v1_mean"],
            "beforeit_var_p1_constant",
            BASE.DiagnosticFailure[];
            canonical_origins = canonical,
            observed_origins = 1,
            path_incomplete_origins = 0,
        )
        @test !isempty(smoke)
        @test all(row -> row.status == "INSUFFICIENT_ORIGINS_SMOKE_ONLY", smoke)
        @test all(row -> isnan(row.weighted_macro_average_cellwise_rmse_ratio), smoke)

        mktempdir() do directory
            open(joinpath(directory, "manifest.toml"), "w") do io
                println(io, "sample_is_canonical = false")
                println(io, "abm_observed_origin_count = 1")
                println(io, "abm_canonical_origin_count = $canonical")
            end
            report = joinpath(HERE, "report_v2_comparison.jl")
            output = IOBuffer()
            ok = try
                run(
                    pipeline(
                        `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(REPO_ROOT, "scripts", "us")) $report $directory`;
                        stdout = output,
                        stderr = output,
                    ),
                )
                true
            catch
                false
            end
            text = String(take!(output))
            @test !ok
            @test occursin("refusing to report", text)
            println(
                "  refusal (report on smoke run): ",
                first(split(strip(replace(text, "\n" => " ")), "Stacktrace")),
            )
        end
    end

    @testset "partial path loss makes an origin incomplete" begin
        panel = load_panel()
        canonical = ABM.canonical_origin_count(panel)
        degraded = ABM.comparison_weighted_scores(
            BASE.RelativeScore[],
            ["beforeit_abm_us_v1_mean"],
            "beforeit_var_p1_constant",
            BASE.DiagnosticFailure[];
            canonical_origins = canonical,
            observed_origins = canonical,
            path_incomplete_origins = 1,
        )
        @test all(row -> row.status == "INCOMPLETE_PATH_COVERAGE_NOT_RANKED", degraded)

        # The accounting helper is what the manifest and the status both read.
        whole = ABM.ABMOriginDiagnostic(
            "headline", 40, "2010Q2", "2010Q2", "2010-06-30", 0, 12, 40, 52,
            500, 500, 0, 0.0, 0.0,
        )
        lossy = ABM.ABMOriginDiagnostic(
            "headline", 41, "2010Q3", "2010Q3", "2010-09-30", 0, 12, 41, 53,
            500, 499, 1, 0.0, 0.0,
        )
        complete, incomplete, minimum_used =
            ABM.path_complete_origins([whole, lossy])
        @test complete == 1
        @test incomplete == 1
        @test minimum_used == 499
    end

    @testset "also-score integration: the real loader refuses each forgery" begin
        # These call load_extra_abm_column itself. The previous version of this
        # testset re-implemented a three-field comparison by hand and never touched
        # the loader, which is precisely why the holes below reached CI green.
        mktempdir() do root
            source = joinpath(root, "companion")
            generated = generate_tiny_cache(source, BASELINE_CALIBRATION)
            identity_path = joinpath(source, ABM.CACHE_IDENTITY_FILENAME)
            own = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = generated.panel,
            )
            own_origins = [entry[1] for entry in generated.selected]

            # Baseline: an honest companion is accepted.
            accepted = load_extra_abm_column(source, own, own_origins)
            @test accepted[1].name == "headline"
            @test length(accepted[4]) == length(own_origins)

            function refuse(mutate!, label)
                document = ABM.read_cache_identity(identity_path)
                mutate!(document)
                ABM.write_cache_identity(identity_path, document)
                thrown = nothing
                try
                    load_extra_abm_column(source, own, own_origins)
                catch error
                    thrown = error
                end
                @test thrown isa ABM.CacheIdentityError
                println("  refusal ($label): ", sprint(showerror, thrown))
                # restore
                ABM.write_cache_identity(identity_path, generated.identity)
                return thrown
            end

            forged_code = refuse(
                document -> document["comparison_code_sha256"] = repeat("a", 64),
                "forged comparison_code_sha256",
            )
            @test forged_code.field == "comparison_code_sha256"

            forged_julia = refuse(
                document -> document["julia_version"] = "1.11.0",
                "forged julia_version",
            )
            @test forged_julia.field == "julia_version"

            forged_runtime = refuse(
                document -> document["runtime_source_tree_sha256"] = repeat("b", 64),
                "forged runtime_source_tree_sha256",
            )
            @test forged_runtime.field == "runtime_source_tree_sha256"

            # Missing diagnostics: coverage and path accounting are unknowable.
            diagnostics_path = joinpath(source, "abm_origin_diagnostics.csv")
            saved = read(diagnostics_path)
            rm(diagnostics_path)
            missing_diagnostics = nothing
            try
                load_extra_abm_column(source, own, own_origins)
            catch error
                missing_diagnostics = error
            end
            @test missing_diagnostics isa ABM.CacheIdentityError
            @test missing_diagnostics.field == "abm_origin_diagnostics.csv"
            println(
                "  refusal (missing diagnostics): ",
                sprint(showerror, missing_diagnostics),
            )
            write(diagnostics_path, saved)

            # Incomplete companion paths: a smaller ensemble wearing the same label.
            rows = ABM.read_struct_csv(diagnostics_path, ABM.ABMOriginDiagnostic)
            degraded = [
                ABM.ABMOriginDiagnostic(
                        row.variant, row.origin_index, row.origin_period,
                        row.build_period, row.calibration_date, row.burn_in_quarters,
                        row.simulated_quarters, row.t_prime, row.t_max,
                        row.paths_requested, row.paths_requested - 1, 1,
                        row.calibration_seconds, row.simulation_seconds,
                    ) for row in rows
            ]
            rm(diagnostics_path)
            ABM.append_struct_csv(diagnostics_path, degraded, ABM.ABMOriginDiagnostic)
            incomplete = nothing
            try
                load_extra_abm_column(source, own, own_origins)
            catch error
                incomplete = error
            end
            @test incomplete isa ABM.CacheIdentityError
            @test incomplete.field == "paths_used"
            println("  refusal (incomplete paths): ", sprint(showerror, incomplete))
            rm(diagnostics_path)
            write(diagnostics_path, saved)
        end
    end

    @testset "the forged one-origin companion is refused" begin
        # The reviewer's exact scenario: a self-consistent companion covering ONE
        # origin, offered to a primary run covering more. Previously accepted, and
        # it produced COMPLETE_MATCHED with minimum_common_counts=[1].
        mktempdir() do root
            source = joinpath(root, "one_origin")
            generated = generate_tiny_cache(source, BASELINE_CALIBRATION; origins = 1)
            @test length(generated.simulated.diagnostics) == 1

            panel = load_panel()
            primary_selected = tiny_origins(panel, 2)
            own = ABM.build_cache_identity(
                ABM.HEADLINE_VARIANT,
                primary_selected;
                paths = 4,
                calibration_path = BASELINE_CALIBRATION,
                panel = panel,
            )
            thrown = nothing
            try
                load_extra_abm_column(
                    source,
                    own,
                    [entry[1] for entry in primary_selected],
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "origin_indices"
            message = sprint(showerror, thrown)
            @test occursin("must cover exactly the same origins", message)
            println("  refusal (forged one-origin companion): ", message)
        end
    end

    @testset "combined canonicality is the minimum over included columns" begin
        panel = load_panel()
        canonical = ABM.canonical_origin_count(panel)
        # A primary with canonical coverage plus a narrower companion must not be
        # ranked: the common cell set is the companion's, not the primary's.
        combined = ABM.comparison_weighted_scores(
            BASE.RelativeScore[],
            ["beforeit_abm_us_v2_mean"],
            "beforeit_var_p1_constant",
            BASE.DiagnosticFailure[];
            canonical_origins = canonical,
            observed_origins = 1,          # narrowest included column
            path_incomplete_origins = 0,
        )
        @test all(row -> row.status == "INSUFFICIENT_ORIGINS_SMOKE_ONLY", combined)
    end

    @testset "an interrupted cache is detected on resume" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            cache_path = joinpath(directory, "abm_ensemble_summaries.csv")
            lines = readlines(cache_path)
            # Drop three rows from the final origin: the ensemble append survived
            # partially before the process died.
            write(cache_path, join(lines[1:(end - 3)], "\n") * "\n")

            repaired = ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                cache_path = cache_path,
                diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
                calibration_path = BASELINE_CALIBRATION,
                identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                identity = generated.identity,
                progress = false,
            )
            # The truncated origin is regenerated, so every origin is whole again.
            counts = Dict{Int, Int}()
            for row in repaired.summaries
                counts[row.origin_index] = get(counts, row.origin_index, 0) + 1
            end
            @test all(==(ABM.ENSEMBLE_ROWS_PER_ORIGIN), values(counts))
            @test length(counts) == 2

            # Under no-repair the same cache is refused by named origin.
            write(cache_path, join(lines[1:(end - 3)], "\n") * "\n")
            thrown = nothing
            try
                ABM.simulate_abm_ensembles(
                    ABM.HEADLINE_VARIANT,
                    generated.selected;
                    paths = 4,
                    cache_path = cache_path,
                    diagnostics_path =
                        joinpath(directory, "abm_origin_diagnostics.csv"),
                    calibration_path = BASELINE_CALIBRATION,
                    identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                    identity = generated.identity,
                    progress = false,
                    allow_repair = false,
                )
            catch error
                thrown = error
            end
            @test thrown isa ABM.CacheIdentityError
            @test thrown.field == "ensemble_row_count"
            println("  refusal (interrupted cache): ", sprint(showerror, thrown))
        end
    end

    @testset "forced recompute removes every run-owned artifact" begin
        mktempdir() do directory
            generated = generate_tiny_cache(directory, BASELINE_CALIBRATION)
            failures_path = joinpath(directory, "abm_path_failures.log")
            write(failures_path, "stale failure from an earlier run\n")
            @test isfile(failures_path)

            ABM.simulate_abm_ensembles(
                ABM.HEADLINE_VARIANT,
                generated.selected;
                paths = 4,
                cache_path = joinpath(directory, "abm_ensemble_summaries.csv"),
                diagnostics_path = joinpath(directory, "abm_origin_diagnostics.csv"),
                calibration_path = BASELINE_CALIBRATION,
                path_failures_path = failures_path,
                identity_path = joinpath(directory, ABM.CACHE_IDENTITY_FILENAME),
                identity = generated.identity,
                force_recompute = true,
                progress = false,
            )
            # The stale log must not survive beside the regenerated cache.
            @test !isfile(failures_path) || isempty(read(failures_path, String))
            println("  forced recompute cleared the stale path-failure log")
        end
    end

    @testset "committed v2 headline cache validates and re-scores byte-identically" begin
        if !isdir(COMMITTED_V2_HEADLINE) || !isdir(COMMITTED_V1_HEADLINE)
            @info "committed v2 headline run absent; skipping"
            @test true
        else
            identity_path =
                joinpath(COMMITTED_V2_HEADLINE, ABM.CACHE_IDENTITY_FILENAME)
            stored = ABM.read_cache_identity(identity_path)
            @test stored["variant"] == "headline_v2"
            @test stored["paths_requested"] == 500
            @test stored["seed_contract_id"] == ABM.SEED_CONTRACT_ID

            panel = load_panel()
            @test stored["panel_sha256"] == panel.panel_sha256

            # The cache must still describe the artifact it claims.
            calibration =
                joinpath(REPO_ROOT, stored["calibration_object_path"])
            @test isfile(calibration)
            @test bytes2hex(SHA.sha256(read(calibration))) ==
                stored["calibration_object_sha256"]

            # And the committed score table must be exactly what this code produces
            # from that cache.
            # The committed table is a joint run: both ABM columns scored on
            # identical common cells, so the re-score must supply the v1 column too.
            committed = read(joinpath(COMMITTED_V2_HEADLINE, "score_summaries.csv"))
            mktempdir() do root
                directory = joinpath(root, "v2")
                companion = joinpath(root, "v1")
                mkpath(directory)
                mkpath(companion)
                for name in (
                        "abm_ensemble_summaries.csv",
                        "abm_origin_diagnostics.csv",
                        ABM.CACHE_IDENTITY_FILENAME,
                    )
                    cp(
                        joinpath(COMMITTED_V2_HEADLINE, name),
                        joinpath(directory, name),
                    )
                    cp(joinpath(COMMITTED_V1_HEADLINE, name), joinpath(companion, name))
                end
                output = IOBuffer()
                run(
                    pipeline(
                        `$(Base.julia_cmd()) --startup-file=no --project=$(joinpath(REPO_ROOT, "scripts", "us")) $RUNNER $directory 500 headline_v2 --also-score=$companion`;
                        stdout = output,
                        stderr = output,
                    ),
                )
                rescored = read(joinpath(directory, "score_summaries.csv"))
                @test rescored == committed
                println(
                    "  committed cache re-scored: score_summaries.csv byte-identical ",
                    "($(length(committed)) bytes)",
                )
            end
        end
    end

end
