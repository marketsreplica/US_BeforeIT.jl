using Test
using BeforeITWeb

function _hierarchy_test_edge(
        id,
        level,
        signed_value;
        rollup_id = nothing,
        parent_ids = String[],
        ancestor_ids = String[],
    )
    return BeforeITWeb._cashflow_normalized_edge(
        id,
        "test:payer:$id",
        "test:recipient:$id",
        signed_value;
        label = "Hierarchy fixture $id",
        layer = "products",
        market = "hierarchy_fixture",
        purpose = "deep_link_reconciliation",
        measure_kind = "cash_transaction",
        recognition = "realized_cash",
        evidence_basis = "test_fixture",
        aggregation =
            level == "macro" ? "sector_to_macro_exact_sum" :
            level == "sector" ? "firm_to_sector_exact_sum" : "none",
        level,
        category = "products",
        rollup_id,
        parent_ids,
        ancestor_ids,
    )
end

@testset "Hierarchy deep links select one immediate aggregation level" begin
    macro_id = "macro:test-products"
    sector_a_id = "sector-rollup:test-products:1"
    sector_b_id = "sector-rollup:test-products:2"

    macro_edge = _hierarchy_test_edge(macro_id, "macro", 6.0)
    sector_edges = [
        _hierarchy_test_edge(
            sector_a_id,
            "sector",
            10.0;
            rollup_id = macro_id,
            parent_ids = [macro_id],
        ),
        _hierarchy_test_edge(
            sector_b_id,
            "sector",
            -4.0;
            rollup_id = macro_id,
            parent_ids = [macro_id],
        ),
    ]
    firm_edges = [
        _hierarchy_test_edge(
            "firm-flow:a:1",
            "firm",
            4.0;
            rollup_id = sector_a_id,
            parent_ids = [sector_a_id],
            ancestor_ids = [macro_id],
        ),
        _hierarchy_test_edge(
            "firm-flow:a:2",
            "firm",
            6.0;
            rollup_id = sector_a_id,
            parent_ids = [sector_a_id],
            ancestor_ids = [macro_id],
        ),
        _hierarchy_test_edge(
            "firm-flow:b:1",
            "firm",
            -1.0;
            rollup_id = sector_b_id,
            parent_ids = [sector_b_id],
            ancestor_ids = [macro_id],
        ),
        _hierarchy_test_edge(
            "firm-flow:b:2",
            "firm",
            -3.0;
            rollup_id = sector_b_id,
            parent_ids = [sector_b_id],
            ancestor_ids = [macro_id],
        ),
    ]
    edges = Any[macro_edge; sector_edges; firm_edges]

    @test all(length(edge["parent_ids"]) == 1 for edge in firm_edges)
    @test all(edge["ancestor_ids"] == [macro_id] for edge in firm_edges)
    @test all(
        !(macro_id in edge["parent_ids"]) for edge in firm_edges
    )

    # Reproduce the audited deep link at the broadest requested detail. The
    # selected rows must still be the macro edge's immediate sector children,
    # never those sectors plus their firm descendants.
    macro_children = BeforeITWeb._cashflow_query_edges(
        edges;
        level = "firm",
        parent_id = macro_id,
        coverage = 1.0,
        page_size = 5000,
        query_identity = "hierarchy-macro-to-sector",
    )
    @test Set(String(edge["id"]) for edge in macro_children["edges"]) ==
        Set([sector_a_id, sector_b_id])
    @test all(edge["level"] == "sector" for edge in macro_children["edges"])
    @test sum(
        Float64(edge["signed_value"]) for edge in macro_children["edges"]
    ) == Float64(macro_edge["signed_value"])

    for sector_edge in sector_edges
        sector_id = String(sector_edge["id"])
        firm_children = BeforeITWeb._cashflow_query_edges(
            edges;
            level = "firm",
            parent_id = sector_id,
            coverage = 1.0,
            page_size = 5000,
            query_identity = "hierarchy-sector-to-firm:$sector_id",
        )
        @test !isempty(firm_children["edges"])
        @test all(
            edge["level"] == "firm" &&
                edge["rollup_id"] == sector_id &&
                edge["parent_ids"] == [sector_id] for
                edge in firm_children["edges"]
        )
        @test sum(
            Float64(edge["signed_value"]) for
                edge in firm_children["edges"]
        ) == Float64(sector_edge["signed_value"])
    end

    # Early v2 artifacts placed every ancestor in `parent_ids`. The primary
    # immediate `rollup_id` now disambiguates those persisted rows as well.
    legacy_expanded_edges = deepcopy(edges)
    legacy_firm = only(
        edge for edge in legacy_expanded_edges if
            edge["id"] == "firm-flow:a:1"
    )
    push!(legacy_firm["parent_ids"], macro_id)
    legacy_macro_children = BeforeITWeb._cashflow_query_edges(
        legacy_expanded_edges;
        level = "firm",
        parent_id = macro_id,
        coverage = 1.0,
        page_size = 5000,
        query_identity = "hierarchy-legacy-expanded-parent-list",
    )
    @test Set(
        String(edge["id"]) for edge in legacy_macro_children["edges"]
    ) == Set([sector_a_id, sector_b_id])
    @test sum(
        Float64(edge["signed_value"]) for
            edge in legacy_macro_children["edges"]
    ) == Float64(macro_edge["signed_value"])

    @test_throws ArgumentError _hierarchy_test_edge(
        "invalid-parent-contract",
        "firm",
        1.0;
        rollup_id = sector_a_id,
        parent_ids = [macro_id],
        ancestor_ids = [sector_a_id],
    )
end
