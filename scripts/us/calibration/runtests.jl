using Test

@testset "U.S. calibration registry slice" begin
    include(joinpath(@__DIR__, "test_parameter_registry.jl"))
end
