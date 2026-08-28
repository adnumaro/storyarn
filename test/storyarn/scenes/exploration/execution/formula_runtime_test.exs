defmodule Storyarn.Scenes.FlowRuntime.FormulaRuntimeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Scenes.FlowRuntime.FormulaEngine
  alias Storyarn.Scenes.FlowRuntime.FormulaRuntime
  alias Storyarn.Sheets.FormulaEngine, as: PreviousFormulaEngine

  test "Scenes-owned formula engine preserves the exploration expression contract" do
    cases = [
      {"(base + 2) * multiplier", %{"base" => 3, "multiplier" => 4}},
      {"max(score, 10) - penalty", %{"score" => 7, "penalty" => 2}},
      {"1 / zero", %{"zero" => 0}},
      {"unknown(1)", %{}}
    ]

    for {expression, values} <- cases do
      assert FormulaEngine.parse(expression) == PreviousFormulaEngine.parse(expression)
      assert FormulaEngine.compute(expression, values) == PreviousFormulaEngine.compute(expression, values)
    end

    {:ok, ast} = FormulaEngine.parse("base + modifier * base")
    assert FormulaEngine.extract_symbols(ast) == PreviousFormulaEngine.extract_symbols(ast)
    assert FormulaEngine.to_latex(ast) == PreviousFormulaEngine.to_latex(ast)

    assert FormulaEngine.to_latex_substituted(ast, %{"base" => 2, "modifier" => 3}) ==
             PreviousFormulaEngine.to_latex_substituted(ast, %{"base" => 2, "modifier" => 3})
  end

  test "Scenes-owned formula runtime preserves chained, invalid, and empty recomputation" do
    chained = %{
      "sheet.table.row.base" => variable(10, "number"),
      "sheet.table.row.mid" =>
        variable(nil, "formula",
          formula: %{
            expression: "base * 2",
            bindings: %{"base" => "sheet.table.row.base"}
          }
        ),
      "sheet.table.row.total" =>
        variable(nil, "formula",
          formula: %{
            expression: "mid + 5",
            bindings: %{"mid" => "sheet.table.row.mid"}
          }
        )
    }

    result = FormulaRuntime.recompute_formulas(chained)
    assert result["sheet.table.row.base"].value == 10
    assert result["sheet.table.row.mid"].value == 20
    assert result["sheet.table.row.total"].value == 25

    invalid = %{
      "sheet.table.row.invalid" =>
        variable(nil, "formula", formula: %{expression: "value / value", bindings: %{"value" => "missing"}})
    }

    assert FormulaRuntime.recompute_formulas(invalid)["sheet.table.row.invalid"].value == nil

    ordinary = %{"sheet.value" => variable(3, "number")}
    assert FormulaRuntime.recompute_formulas(ordinary) == ordinary
    assert FormulaRuntime.recompute_formulas(%{}) == %{}
  end

  test "Scenes-owned runtime terminates circular formulas with its local fallback semantics" do
    variables = %{
      "sheet.table.row.a" =>
        variable(nil, "formula", formula: %{expression: "b + 1", bindings: %{"b" => "sheet.table.row.b"}}),
      "sheet.table.row.b" =>
        variable(nil, "formula", formula: %{expression: "a + 1", bindings: %{"a" => "sheet.table.row.a"}})
    }

    result = FormulaRuntime.recompute_formulas(variables)

    assert result |> Map.values() |> Enum.map(& &1.value) |> Enum.sort() == [1, 2]
  end

  test "Scenes-owned formula runtime preserves nil-bindings fallback" do
    variables = %{
      "sheet.table.row.total" => variable(7, "formula", formula: %{expression: "", bindings: nil})
    }

    # Pinned against the retired shared runtime's behavior: explicit nil
    # bindings fall back to no dependencies and the unparsable empty
    # expression clears the value. (The Flow copy diverges here — it predates
    # the shared module's nil guard — so this is a value pin, not a
    # comparison.)
    assert %{"sheet.table.row.total" => %{value: nil, source: :initial}} =
             FormulaRuntime.recompute_formulas(variables)
  end

  test "Scenes-owned runtime preserves same-row binding translation" do
    bindings = %{
      "same" => %{"type" => "same_row", "column_slug" => "base"},
      "other" => %{"type" => "variable", "ref" => "other.value"},
      "invalid" => %{"type" => "unknown"}
    }

    assert FormulaRuntime.translate_same_row("sheet.table.row.total", bindings) == %{
             "same" => "sheet.table.row.base",
             "other" => "other.value",
             "invalid" => nil
           }
  end

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
end
