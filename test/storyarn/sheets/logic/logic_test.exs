defmodule Storyarn.Sheets.LogicTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Logic

  test "constraint dispatch preserves the root facade contract" do
    assert Logic.clamp_to_constraints("abcdef", %{"max_length" => 3}, "text") == "abc"

    assert Logic.clamp_to_constraints("<p>abcdef</p>", %{"max_length" => 3}, "rich_text") ==
             "<p>abcdef</p>"

    assert Logic.clamp_to_constraints(12, %{"max" => 10}, "number") == 10
    assert Logic.clamp_to_constraints(nil, %{"mode" => "tri_state"}, "boolean") == nil
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

    assert Logic.has_formula_variable_bindings?(cells)

    assert get_in(
             Logic.rewrite_cells(cells, "parent", "child", %{"stats" => "stats_1"}),
             ["formula", "bindings", "value", "ref"]
           ) == "child.stats_1.hp.current"
  end
end
