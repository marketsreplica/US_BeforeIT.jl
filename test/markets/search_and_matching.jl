import BeforeIT as Bit

using Test, MAT, StatsBase, Random

@testset "search and matching" begin
    T = 1
    Random.seed!(1)

    parameters = Bit.AUSTRIA2010Q1.parameters
    initial_conditions = Bit.AUSTRIA2010Q1.initial_conditions

    function run_search_and_matching(parameters, initial_conditions, T, m)
        model = Bit.Model(parameters, initial_conditions)

        gov = model.gov         # government
        cb = model.cb           # central bank
        rotw = model.rotw       # rest of the world
        firms = model.firms     # firms
        bank = model.bank       # bank
        w_act = model.w_act     # active workers
        w_inact = model.w_inact # inactive workers
        agg = model.agg         # aggregates
        prop = model.prop       # model properties

        Bit.finance_insolvent_firms!(model)

        agg.Y_e, agg.gamma_e, agg.pi_e = Bit.growth_inflation_expectations(model)

        agg.epsilon_Y_EA, agg.epsilon_E, agg.epsilon_I = Bit.epsilon(prop.C)

        rotw.Y_EA, rotw.gamma_EA, rotw.pi_EA = Bit.growth_inflation_EA(model)

        cb.r_bar = Bit.central_bank_rate(model)

        bank.r = Bit.bank_rate(model)

        Q_s_i, I_d_i, DM_d_i, N_d_i, Pi_e_i, DL_d_i, K_e_i, L_e_i, P_i =
            Bit.firms_expectations_and_decisions(model)

        firms.Q_s_i .= Q_s_i
        firms.I_d_i .= I_d_i
        firms.DM_d_i .= DM_d_i
        firms.N_d_i .= N_d_i
        firms.Pi_e_i .= Pi_e_i
        firms.P_i .= P_i
        firms.DL_d_i .= DL_d_i
        firms.K_e_i .= K_e_i
        firms.L_e_i .= L_e_i

        Bit.search_and_matching_credit!(model)

        Bit.search_and_matching_labour!(model)

        firms.w_i .= Bit.firms_wages(model)
        firms.Y_i .= Bit.firms_production(model)

        Bit.update_workers_wages!(model)

        gov.sb_other, gov.sb_inact = Bit.gov_social_benefits(model)

        bank.Pi_e_k = Bit.bank_expected_profits(model)

        C_d_h, I_d_h = Bit.households_budget_act(model)
        w_act.C_d_h .= C_d_h
        w_act.I_d_h .= I_d_h
        C_d_h, I_d_h = Bit.households_budget_inact(model)
        w_inact.C_d_h .= C_d_h
        w_inact.I_d_h .= I_d_h
        C_d_h, I_d_h = Bit.households_budget_firms(model)
        firms.C_d_h .= C_d_h
        firms.I_d_h .= I_d_h
        bank.C_d_h, bank.I_d_h = Bit.households_budget_bank(model)

        C_G, C_d_j = Bit.gov_expenditure(model)
        gov.C_G = C_G
        gov.C_d_j .= C_d_j

        C_E, Y_I, C_d_l, Y_m, P_m = Bit.rotw_import_export(model)
        rotw.C_E = C_E
        rotw.Y_I = Y_I
        rotw.C_d_l .= C_d_l
        rotw.Y_m .= Y_m
        rotw.P_m .= P_m

        transactions = Any[]
        if m
            Bit.search_and_matching!(model; parallel = true)
        else
            Bit.search_and_matching!(
                model;
                parallel = false,
                transaction_logger =
                    transaction -> push!(transactions, transaction),
                transaction_markets = (:business_goods,),
            )
        end
        return bank, w_act, w_inact, firms, gov, rotw, transactions
    end

    # NOTE: as a test we use the expected values and standard deviations of the
    #       original implementation, with tolerance = 3*(standard deviation) for
    #       both single-threaded and multi-threaded execution
    for m in [true, false]
        bank, w_act, w_inact, firms, gov, rotw, transactions =
            run_search_and_matching(parameters, initial_conditions, T, m)
        @test isapprox(
            mean([bank.I_h, w_act.I_h..., w_inact.I_h..., firms.I_h...]),
            0.32975, atol = 3 * 0.0025351
        )
        @test isapprox(
            mean([bank.C_h, w_act.C_h..., w_inact.C_h..., firms.C_h...]),
            3.973, atol = 3 * 0.029366
        )
        @test isapprox(mean(firms.I_i), 20.5075, atol = 3 * 0.12763)
        @test isapprox(mean(firms.DM_i), 109.3163, atol = 3 * 0.68033)
        @test isapprox(mean(firms.P_bar_i), 1.0031, atol = 3 * 0.0044726)
        @test isapprox(mean(firms.P_CF_i), 1.0031, atol = 3 * 0.0044726)
        @test isapprox(gov.C_j, 14752.2413, atol = 3 * 126.7441)
        @test isapprox(rotw.C_l, 34188.1258, atol = 3 * 666.275)
        @test isapprox(mean(firms.Q_d_i), 216.2474, atol = 3 * 1.2275)
        @test isapprox(mean(rotw.Q_d_m), 535.7522, atol = 3 * 9.6082)
        if !m
            realized =
                sum(
                transaction.amount for transaction in transactions if
                    transaction.cash_recognized
            )
            business_purchases =
                sum(firms.DM_i .* firms.P_bar_i) +
                sum(firms.I_i .* firms.P_CF_i)
            @test !isempty(transactions)
            @test all(
                transaction.market == "business_goods" for
                    transaction in transactions
            )
            @test isapprox(
                realized,
                business_purchases;
                atol = 1.0e-8,
                rtol = 1.0e-12,
            )
        end
    end

    @testset "retail capacity counterfactual preserves realized demand" begin
        Random.seed!(4321)

        # One unit can be bought from current inventory. The two sellers have a
        # further five units of unused capacity, which is still insufficient to
        # satisfy the household's remaining demand of nine units. Capacity-only
        # matches must inform demand estimates without becoming cash purchases.
        I, H, L, J = 2, 1, 1, 1
        C_d_h = [10.0]
        I_d_h = [0.0]
        Q_d_i_g = zeros(I, 1)
        Q_d_m_g = zeros(0, 1)
        C_h = zeros(H)
        I_h = zeros(H)
        C_j_g = zeros(1)
        C_l_g = zeros(1)
        P_bar_h_g = zeros(1)
        P_bar_CF_h_g = zeros(1)
        P_j_g = zeros(1)
        P_l_g = zeros(1)
        S_fg = [1.0, 0.0]
        S_fg_ = [2.0, 3.0]

        Bit.perform_retail_market!(
            1,
            nothing,
            nothing,
            (; C_d_j = [0.0]),
            (; C_d_l = [0.0]),
            I,
            H,
            L,
            J,
            C_d_h,
            I_d_h,
            [1.0],
            [1.0],
            [1.0],
            [1.0],
            Q_d_i_g,
            Q_d_m_g,
            C_h,
            I_h,
            C_j_g,
            C_l_g,
            P_bar_h_g,
            P_bar_CF_h_g,
            P_j_g,
            P_l_g,
            S_fg,
            S_fg_,
            [1, 2],
            [1.0, 1.0],
            [3.0, 4.0],
            [1, 1],
            ReentrantLock(),
            false,
            String[],
            Int[],
            nothing,
        )

        @test S_fg_ == [0.0, 0.0]
        @test C_h == [1.0]
        @test I_h == [0.0]
    end
end
