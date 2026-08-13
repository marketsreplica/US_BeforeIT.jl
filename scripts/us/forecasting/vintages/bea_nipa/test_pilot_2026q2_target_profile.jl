using SHA
using Test
using TOML

include(
    joinpath(
        @__DIR__,
        "receipts",
        "BEAWorkbookReceipts.jl",
    ),
)
using .BEAWorkbookReceipts

const PROFILE_PATH =
    joinpath(@__DIR__, "pilot_2026q2_target_profile.toml")
const INVENTORY_PATH =
    normpath(joinpath(@__DIR__, "..", "current_inventory.toml"))

@testset "2026Q2 exact production target profile" begin
    inventory_before = read(INVENTORY_PATH)
    profile_bytes = read(PROFILE_PATH)
    @test bytes2hex(SHA.sha256(profile_bytes)) ==
        "cd1b8ac0d98dafbafcce13a035573e9dec728b68de01c96b53f04a06f5bfba00"

    profile = TOML.parse(String(profile_bytes))
    result = validate_target_profile(profile)
    @test result.release_id == "r2026q2_advance"
    @test result.reference_period == "2026Q2"
    @test result.profile_id == "september_2023_rebase"
    @test result.scope == "EXACT_INSPECTED_WORKBOOK_TARGET_PROFILE"
    @test result.content_sha256 ==
        "e768bb45b11ced8ef3b8657aa2ffad1b2ae6465e15aa58967db155d2d39d474d"
    @test result.source_mapping_audit_file_sha256 ==
        "424e34febc2054a055f8f9495a94f08fd93d8229d035b0a349b0446f0e7c2b5f"
    @test result.target_ids == [
        "core_pce_price_index",
        "gdp_deflator",
        "nominal_gdp",
        "pce_price_index",
        "real_gdp",
    ]
    @test Set(keys(result.workbooks_by_section)) == Set(["1", "2"])
    @test result.workbooks_by_section["1"]["raw_sha256"] ==
        "ddcd0c5b693cb5d179198e67dda60f817e0e97196e6f1c158152971bbc80b136"
    @test result.workbooks_by_section["2"]["raw_sha256"] ==
        "1d5e3c6e177f6ba818bacf6361b3f21b7996e6cfdf55afb4d2a86a41bd2a4011"

    @test !profile["artifact"]["historical_release_availability_verified"]
    @test !profile["artifact"]["origin_admissible"]
    @test !profile["artifact"]["ready"]
    @test read(INVENTORY_PATH) == inventory_before
end
