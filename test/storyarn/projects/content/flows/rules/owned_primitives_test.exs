defmodule Storyarn.Projects.FlowOwnedPrimitivesTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.FlowFormulaEngine
  alias Storyarn.Projects.FlowWordCount
  alias Storyarn.Sheets.FormulaEngine, as: PreviousFormulaEngine

  test "Project-owned Flow word counts preserve the imported and repaired node contract" do
    cases = [
      {"dialogue",
       %{
         "text" => "One two",
         "menu_text" => "Choose now",
         "stage_directions" => "Walks away",
         "responses" => [%{"text" => "Not yet"}]
       }, 8},
      {"dialogue", %{text: "Atom keys", responses: [%{text: "Still count"}]}, 4},
      {"exit", %{"label" => "Leave now"}, 2},
      {"instruction", %{"text" => "Ignored"}, 0},
      {"dialogue", nil, 0}
    ]

    for {type, data, expected} <- cases do
      assert FlowWordCount.for_node_data(type, data) == expected
    end
  end

  test "Project-owned Flow formula parsing preserves reference extraction semantics" do
    expressions = [
      "base + modifier * 2",
      "max(score, 10) - penalty",
      "sqrt(total)",
      "unknown(",
      ""
    ]

    for expression <- expressions do
      assert FlowFormulaEngine.parse(expression) == PreviousFormulaEngine.parse(expression)
    end

    {:ok, ast} = FlowFormulaEngine.parse("base + modifier * base")
    assert FlowFormulaEngine.extract_symbols(ast) == ["base", "modifier"]
    assert FlowFormulaEngine.compute("base * 2", %{"base" => 4}) == {:ok, 8.0}
  end
end
