defmodule Storyarn.Sheets.ExpressionsTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Expressions
  alias Storyarn.Sheets.Logic, as: LegacyLogic

  test "keeps the legacy capability boundary while SQL predicates stay off Expressions" do
    assert Enum.sort(LegacyLogic.__info__(:functions)) ==
             Enum.sort(Expressions.__info__(:functions))

    assert LegacyLogic.clamp_to_constraints(12, %{"max" => 10}, "number") ==
             Expressions.clamp_to_constraints(12, %{"max" => 10}, "number")

    assert {:authoritative_namespace_owner?, 1} in LegacyLogic.__info__(:macros)
    refute {:authoritative_namespace_owner?, 1} in Expressions.__info__(:macros)
  end

  test "constraint dispatch preserves the root facade contract" do
    assert Expressions.clamp_to_constraints("abcdef", %{"max_length" => 3}, "text") == "abc"

    assert Expressions.clamp_to_constraints("<p>abcdef</p>", %{"max_length" => 3}, "rich_text") ==
             "<p>abcdef</p>"

    assert Expressions.clamp_to_constraints(12, %{"max" => 10}, "number") == 10
    assert Expressions.clamp_to_constraints(nil, %{"mode" => "tri_state"}, "boolean") == nil
  end

  test "formula binding operations are reachable through the capability boundary" do
    cells = %{
      "formula" => %{
        "expression" => "value",
        "bindings" => %{
          "value" => %{"type" => "variable", "ref" => "parent.stats.hp.current"}
        }
      }
    }

    assert Expressions.has_formula_variable_bindings?(cells)

    assert get_in(
             Expressions.rewrite_cells(cells, "parent", "child", %{"stats" => "stats_1"}),
             ["formula", "bindings", "value", "ref"]
           ) == "child.stats_1.hp.current"
  end
end
