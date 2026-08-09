import BeforeIT as Bit

using Test

@testset "test firms actions" begin

    @testset "test get_leontief_production" begin
        Q_s_i = [1.0, 2.0, 0.0]
        N_i = [1.0, 2.0, 3.0]
        alpha_i = [1.0, 2.0, 3.0]
        K_i = [1.0, 2.0, 3.0]
        kappa_i = [1.0, 0.0, 3.0]
        M_i = [1.0, 2.0, 3.0]
        beta_i = [1.0, 2.0, 3.0]
        expected_Y_i = [1.0, 0.0, 0.0]
        Y_i = Bit.leontief_production(Q_s_i, N_i, alpha_i, K_i, kappa_i, M_i, beta_i)
        @test Y_i == expected_Y_i
    end

    @testset "desired inputs apply capacity caps firm by firm" begin
        parameters = deepcopy(Bit.STEADY_STATE2010Q1.parameters)
        initial_conditions =
            deepcopy(Bit.STEADY_STATE2010Q1.initial_conditions)
        firms = Bit.Model(parameters, initial_conditions).firms
        firm_count = length(firms.K_i)

        desired_output = fill(10.0, firm_count)
        capacity = [isodd(index) ? 5.0 : 15.0 for index in 1:firm_count]
        firms.K_i .= capacity
        firms.kappa_i .= 1.0
        firms.delta_i .= 0.25
        firms.beta_i .= 2.0
        firms.alpha_bar_i .= 2.0

        investment, materials, employment =
            Bit.desired_capital_material_employment(
            firms,
            desired_output,
        )
        constrained_output = min.(desired_output, capacity)

        @test investment == 0.25 .* constrained_output
        @test materials == constrained_output ./ 2.0
        @test employment == max.(1.0, round.(constrained_output ./ 2.0))
        @test investment[1] < investment[2]
    end

    @testset "base model rejects growth-rate coefficients" begin
        parameters = deepcopy(Bit.STEADY_STATE2010Q1.parameters)
        parameters["use_growth_rate_ar1"] = true
        @test_throws ArgumentError Bit.Model(
            parameters,
            deepcopy(Bit.STEADY_STATE2010Q1.initial_conditions),
        )
    end

end
