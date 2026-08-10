import BeforeIT as Bit

using Random
using Test

@testset "test estimations actions" begin

    parameters, initial_conditions = Bit.AUSTRIA2010Q1.parameters, Bit.AUSTRIA2010Q1.initial_conditions
    model = Bit.Model(parameters, initial_conditions)

    @testset "test growth_expectations" begin
        # The specification flag defaults to off, so an unregistered calibration keeps the
        # legacy log-level AR(1) expectation exactly.
        @test model.prop.expectation_rw_drift == false

        p_on = deepcopy(parameters)
        p_on["expectation_rw_drift"] = true
        m_on = Bit.Model(p_on, deepcopy(initial_conditions))
        m_off = Bit.Model(deepcopy(parameters), deepcopy(initial_conditions))
        @test m_on.prop.expectation_rw_drift == true
        @test m_off.prop.expectation_rw_drift == false

        T_prime = Int(m_on.prop.T_prime)
        set_history!(m, series) = begin
            resize!(m.agg.Y, T_prime)
            m.agg.Y .= series
            m.agg.t = 1
        end

        # (1) On a noise-free log-linear trend the innovation is identically zero, so the
        #     drift specification must return the trend growth exactly.
        g = 0.006
        trend = [exp(g * t) for t in 1:T_prime]
        set_history!(m_on, trend)
        _, gamma_rw, _ = Bit.growth_inflation_expectations(m_on)
        @test isapprox(gamma_rw, exp(g) - 1, atol = 1.0e-10)

        # (2) On an exactly mean-reverting log series both estimators have zero residual
        #     variance, so the comparison is deterministic: the log-level AR(1) delivers
        #     only a fraction of the average past growth, which is the mis-specification
        #     this flag corrects.
        mu, alpha = 0.5, 0.97
        reverting = [exp(mu + (0.0 - mu) * alpha^t) for t in 1:T_prime]
        set_history!(m_on, reverting)
        set_history!(m_off, reverting)
        _, gamma_rw2, _ = Bit.growth_inflation_expectations(m_on)
        _, gamma_ar1, _ = Bit.growth_inflation_expectations(m_off)
        mean_growth = (log(reverting[end]) - log(reverting[1])) / (T_prime - 1)
        @test isapprox(gamma_rw2, exp(mean_growth) - 1, atol = 1.0e-10)
        @test gamma_ar1 < gamma_rw2

        # (3) A model that opts in still runs.
        Random.seed!(11)
        m_run = Bit.Model(p_on, deepcopy(initial_conditions))
        Bit.run!(m_run, 4; parallel = false)
        @test all(isfinite, m_run.data.real_gdp)
    end

    @testset "test growth_inflation_EA" begin
        # TODO
    end

    @testset "test inflation_priceindex" begin

        resize!(model.firms.P_i, 3); model.firms.P_i .= [1.0, 2.0, 3.0]
        resize!(model.firms.Y_i, 3); model.firms.Y_i .= [1.0, 2.0, 3.0]
        model.agg.P_bar = 2.0
        expected_inflation = log(14 / 12)
        expected_priceindex = 14 / 6
        inflation, priceindex = Bit.inflation_priceindex(model)
        @test isapprox(inflation, expected_inflation, atol = 1.0e-10)
    end

    @testset "test sector_specific_priceindex" begin
        resize!(model.firms.P_i, 3); model.firms.P_i .= [1.0, 2.0, 3.0]
        resize!(model.firms.Q_i, 3); model.firms.Q_i .= [1.0, 2.0, 3.0]
        resize!(model.firms.G_i, 3); model.firms.G_i .= [1, 1, 1]
        model.rotw.P_m[1] = 2.0
        model.rotw.Q_m[1] = 1.0
        G = model.prop.G
        expected_priceindex = 16 / 7
        priceindex = Bit.sector_specific_priceindex(model)
        @test isapprox(priceindex[1], expected_priceindex, atol = 1.0e-10)
    end

end
