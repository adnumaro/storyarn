defmodule Storyarn.Shared.FormulaRuntimeTest do
  use ExUnit.Case, async: true

  alias Storyarn.Shared.FormulaRuntime

  defp make_var(value, block_type, opts \\ []) do
    base = %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: 1,
      sheet_shortcut: "test",
      variable_name: "v",
      constraints: nil
    }

    case Keyword.get(opts, :formula) do
      nil -> base
      formula -> Map.put(base, :formula, formula)
    end
  end

  describe "recompute_formulas/1" do
    test "returns unchanged when no formulas exist" do
      variables = %{
        "s.health" => make_var(10, "number"),
        "s.name" => make_var("test", "text")
      }

      assert FormulaRuntime.recompute_formulas(variables) == variables
    end

    test "returns empty map unchanged" do
      assert FormulaRuntime.recompute_formulas(%{}) == %{}
    end

    test "computes simple formula from base variable" do
      variables = %{
        "s.t.r.value" => make_var(10, "number"),
        "s.t.r.modifier" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a - 3",
              bindings: %{"a" => "s.t.r.value"}
            }
          )
      }

      result = FormulaRuntime.recompute_formulas(variables)
      assert result["s.t.r.modifier"].value == 7
    end

    test "computes linear chain: C depends on B depends on A" do
      variables = %{
        "s.t.r.base" => make_var(10, "number"),
        "s.t.r.mid" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a * 2",
              bindings: %{"a" => "s.t.r.base"}
            }
          ),
        "s.t.r.top" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a + 5",
              bindings: %{"a" => "s.t.r.mid"}
            }
          )
      }

      result = FormulaRuntime.recompute_formulas(variables)
      assert result["s.t.r.mid"].value == 20
      assert result["s.t.r.top"].value == 25
    end

    test "handles circular dependency gracefully (evaluates with 0 fallback)" do
      variables = %{
        "s.t.r.a" =>
          make_var(nil, "formula",
            formula: %{
              expression: "b + 1",
              bindings: %{"b" => "s.t.r.b"}
            }
          ),
        "s.t.r.b" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a + 1",
              bindings: %{"a" => "s.t.r.a"}
            }
          )
      }

      # Should not crash — circular deps get evaluated with fallback 0
      result = FormulaRuntime.recompute_formulas(variables)
      assert is_map(result)
    end

    test "handles missing dependency with 0.0 fallback" do
      variables = %{
        "s.t.r.calc" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a + 5",
              bindings: %{"a" => "s.t.r.nonexistent"}
            }
          )
      }

      result = FormulaRuntime.recompute_formulas(variables)
      assert result["s.t.r.calc"].value == 5
    end

    test "preserves non-formula variables unchanged" do
      variables = %{
        "s.health" => make_var(42, "number"),
        "s.t.r.calc" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a + 1",
              bindings: %{"a" => "s.health"}
            }
          )
      }

      result = FormulaRuntime.recompute_formulas(variables)
      assert result["s.health"].value == 42
      assert result["s.t.r.calc"].value == 43
    end

    test "handles formula with multiple bindings" do
      variables = %{
        "s.t.r.str" => make_var(8, "number"),
        "s.t.r.dex" => make_var(6, "number"),
        "s.t.r.combined" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a + b",
              bindings: %{"a" => "s.t.r.str", "b" => "s.t.r.dex"}
            }
          )
      }

      result = FormulaRuntime.recompute_formulas(variables)
      assert result["s.t.r.combined"].value == 14
    end

    test "handles expression error returning nil" do
      variables = %{
        "s.t.r.zero" => make_var(0, "number"),
        "s.t.r.calc" =>
          make_var(nil, "formula",
            formula: %{
              expression: "a / b",
              bindings: %{"a" => "s.t.r.zero", "b" => "s.t.r.zero"}
            }
          )
      }

      result = FormulaRuntime.recompute_formulas(variables)
      assert result["s.t.r.calc"].value == nil
    end
  end

  describe "translate_same_row/2" do
    test "translates same_row bindings to full refs" do
      result =
        FormulaRuntime.translate_same_row(
          "seven.stats.con.modifier",
          %{"a" => %{"type" => "same_row", "column_slug" => "value"}}
        )

      assert result == %{"a" => "seven.stats.con.value"}
    end

    test "keeps variable bindings as-is" do
      result =
        FormulaRuntime.translate_same_row(
          "seven.stats.con.modifier",
          %{"a" => %{"type" => "variable", "ref" => "seven.health"}}
        )

      assert result == %{"a" => "seven.health"}
    end

    test "handles mixed bindings" do
      result =
        FormulaRuntime.translate_same_row(
          "s.t.r.formula",
          %{
            "a" => %{"type" => "same_row", "column_slug" => "base"},
            "b" => %{"type" => "variable", "ref" => "other.var"}
          }
        )

      assert result == %{"a" => "s.t.r.base", "b" => "other.var"}
    end

    test "handles empty bindings" do
      assert FormulaRuntime.translate_same_row("s.t.r.x", %{}) == %{}
    end

    test "handles non-map bindings" do
      assert FormulaRuntime.translate_same_row("s.t.r.x", nil) == %{}
    end
  end
end
