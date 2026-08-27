defmodule Storyarn.Flows.FormulaRuntimeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows

  defp variable(value, type, opts \\ []) do
    base = %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: type,
      block_id: 1,
      sheet_shortcut: "sheet",
      variable_name: "value",
      constraints: nil
    }

    case Keyword.get(opts, :formula) do
      nil -> base
      formula -> Map.put(base, :formula, formula)
    end
  end

  test "recomputes chained formulas using the Flow runtime contract" do
    variables = %{
      "sheet.table.row.base" => variable(10, "number"),
      "sheet.table.row.mid" =>
        variable(nil, "formula", formula: %{expression: "base * 2", bindings: %{"base" => "sheet.table.row.base"}}),
      "sheet.table.row.total" =>
        variable(nil, "formula", formula: %{expression: "mid + 5", bindings: %{"mid" => "sheet.table.row.mid"}})
    }

    result = Flows.recompute_formula_variables(variables)

    assert result["sheet.table.row.mid"].value == 20
    assert result["sheet.table.row.total"].value == 25
  end

  test "uses zero for missing references and nil for invalid expressions" do
    variables = %{
      "sheet.table.row.missing" =>
        variable(nil, "formula", formula: %{expression: "value + 5", bindings: %{"value" => "unknown"}}),
      "sheet.table.row.invalid" =>
        variable(nil, "formula", formula: %{expression: "value / value", bindings: %{"value" => "unknown"}})
    }

    result = Flows.recompute_formula_variables(variables)

    assert result["sheet.table.row.missing"].value == 5
    assert result["sheet.table.row.invalid"].value == nil
  end

  test "terminates circular formulas and evaluates each once with the zero fallback" do
    variables = %{
      "sheet.table.row.a" =>
        variable(nil, "formula", formula: %{expression: "b + 1", bindings: %{"b" => "sheet.table.row.b"}}),
      "sheet.table.row.b" =>
        variable(nil, "formula", formula: %{expression: "a + 1", bindings: %{"a" => "sheet.table.row.a"}})
    }

    result = Flows.recompute_formula_variables(variables)

    assert result |> Map.values() |> Enum.map(& &1.value) |> Enum.sort() == [1, 2]
  end

  test "translates same-row and explicit variable bindings" do
    bindings = %{
      "same" => %{"type" => "same_row", "column_slug" => "base"},
      "other" => %{"type" => "variable", "ref" => "other.value"}
    }

    assert Flows.translate_same_row_binding("sheet.table.row.total", bindings) == %{
             "same" => "sheet.table.row.base",
             "other" => "other.value"
           }
  end

  test "returns data unchanged when there are no formulas" do
    variables = %{"sheet.value" => variable(3, "number")}

    assert Flows.recompute_formula_variables(variables) == variables
    assert Flows.recompute_formula_variables(%{}) == %{}
  end
end
