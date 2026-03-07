defmodule Storyarn.Sheets.FormulaBindingRewriterTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.FormulaBindingRewriter

  # =============================================================================
  # rewrite_cells/4 — Pure function tests (no DB)
  # =============================================================================

  describe "rewrite_cells/4" do
    test "non-formula cells pass through unchanged" do
      cells = %{
        "base" => 10,
        "name" => "hello",
        "flag" => true,
        "empty" => nil
      }

      result = FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats"})
      assert result == cells
    end

    test "same_row bindings are unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "a + 1",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => "base"}
          }
        }
      }

      result = FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats"})
      assert result == cells
    end

    test "cross-sheet binding referencing parent is rewritten to child shortcut" do
      cells = %{
        "formula" => %{
          "expression" => "a * b",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => "base"},
            "b" => %{"type" => "variable", "ref" => "main.stats.con.modifier"}
          }
        }
      }

      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats"})

      assert result["formula"]["bindings"]["a"] == %{
               "type" => "same_row",
               "column_slug" => "base"
             }

      assert result["formula"]["bindings"]["b"] == %{
               "type" => "variable",
               "ref" => "seven.stats.con.modifier"
             }
    end

    test "cross-sheet binding referencing a different sheet is unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "a + b",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => "base"},
            "b" => %{"type" => "variable", "ref" => "items.weapons.sword.damage"}
          }
        }
      }

      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats"})

      assert result["formula"]["bindings"]["b"]["ref"] == "items.weapons.sword.damage"
    end

    test "binding referencing non-propagated block stays unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "b * 2",
          "bindings" => %{
            "b" => %{"type" => "variable", "ref" => "main.inventory.weight.total"}
          }
        }
      }

      # "inventory" is not in the mapping — it wasn't propagated
      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats"})

      assert result["formula"]["bindings"]["b"]["ref"] == "main.inventory.weight.total"
    end

    test "variable name deduplication is handled (parent stats → child stats_1)" do
      cells = %{
        "formula" => %{
          "expression" => "b",
          "bindings" => %{
            "b" => %{"type" => "variable", "ref" => "main.stats.con.modifier"}
          }
        }
      }

      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats_1"})

      assert result["formula"]["bindings"]["b"]["ref"] == "seven.stats_1.con.modifier"
    end

    test "nil parent shortcut returns cells unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "b",
          "bindings" => %{"b" => %{"type" => "variable", "ref" => "main.stats.hp"}}
        }
      }

      assert FormulaBindingRewriter.rewrite_cells(cells, nil, "seven", %{"stats" => "stats"}) ==
               cells
    end

    test "nil child shortcut returns cells unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "b",
          "bindings" => %{"b" => %{"type" => "variable", "ref" => "main.stats.hp"}}
        }
      }

      assert FormulaBindingRewriter.rewrite_cells(cells, "main", nil, %{"stats" => "stats"}) ==
               cells
    end

    test "empty parent shortcut returns cells unchanged" do
      cells = %{"f" => %{"expression" => "b", "bindings" => %{}}}

      assert FormulaBindingRewriter.rewrite_cells(cells, "", "seven", %{"stats" => "stats"}) ==
               cells
    end

    test "same parent and child shortcut returns cells unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "b",
          "bindings" => %{"b" => %{"type" => "variable", "ref" => "main.stats.hp"}}
        }
      }

      assert FormulaBindingRewriter.rewrite_cells(cells, "main", "main", %{"stats" => "stats"}) ==
               cells
    end

    test "empty mapping returns cells unchanged" do
      cells = %{
        "formula" => %{
          "expression" => "b",
          "bindings" => %{"b" => %{"type" => "variable", "ref" => "main.stats.hp"}}
        }
      }

      assert FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{}) == cells
    end

    test "multiple bindings — only matching ones are rewritten" do
      cells = %{
        "formula" => %{
          "expression" => "a + b + c",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => "base"},
            "b" => %{"type" => "variable", "ref" => "main.stats.con.modifier"},
            "c" => %{"type" => "variable", "ref" => "items.weapons.sword.damage"}
          }
        }
      }

      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"stats" => "stats"})

      # a: same_row — unchanged
      assert result["formula"]["bindings"]["a"]["type"] == "same_row"
      # b: parent ref — rewritten
      assert result["formula"]["bindings"]["b"]["ref"] == "seven.stats.con.modifier"
      # c: different sheet — unchanged
      assert result["formula"]["bindings"]["c"]["ref"] == "items.weapons.sword.damage"
    end

    test "multiple formula cells in the same row are all rewritten" do
      cells = %{
        "col_a" => %{
          "expression" => "x",
          "bindings" => %{
            "x" => %{"type" => "variable", "ref" => "main.stats.str.modifier"}
          }
        },
        "col_b" => %{
          "expression" => "y",
          "bindings" => %{
            "y" => %{"type" => "variable", "ref" => "main.combat.ac.total"}
          }
        },
        "col_c" => 42
      }

      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "klark", %{
          "stats" => "stats",
          "combat" => "combat"
        })

      assert result["col_a"]["bindings"]["x"]["ref"] == "klark.stats.str.modifier"
      assert result["col_b"]["bindings"]["y"]["ref"] == "klark.combat.ac.total"
      assert result["col_c"] == 42
    end

    test "simple variable ref without table path segments" do
      cells = %{
        "formula" => %{
          "expression" => "b",
          "bindings" => %{
            "b" => %{"type" => "variable", "ref" => "main.health"}
          }
        }
      }

      result =
        FormulaBindingRewriter.rewrite_cells(cells, "main", "seven", %{"health" => "health"})

      assert result["formula"]["bindings"]["b"]["ref"] == "seven.health"
    end
  end

  # =============================================================================
  # has_formula_variable_bindings?/1
  # =============================================================================

  describe "has_formula_variable_bindings?/1" do
    test "returns false for nil" do
      refute FormulaBindingRewriter.has_formula_variable_bindings?(nil)
    end

    test "returns false for cells with no formulas" do
      refute FormulaBindingRewriter.has_formula_variable_bindings?(%{"a" => 1, "b" => "hello"})
    end

    test "returns false for formula with only same_row bindings" do
      cells = %{
        "f" => %{
          "expression" => "a + 1",
          "bindings" => %{"a" => %{"type" => "same_row", "column_slug" => "base"}}
        }
      }

      refute FormulaBindingRewriter.has_formula_variable_bindings?(cells)
    end

    test "returns true for formula with variable binding" do
      cells = %{
        "f" => %{
          "expression" => "b",
          "bindings" => %{"b" => %{"type" => "variable", "ref" => "main.stats.hp"}}
        }
      }

      assert FormulaBindingRewriter.has_formula_variable_bindings?(cells)
    end

    test "returns true when at least one binding is variable among mixed types" do
      cells = %{
        "f" => %{
          "expression" => "a + b",
          "bindings" => %{
            "a" => %{"type" => "same_row", "column_slug" => "x"},
            "b" => %{"type" => "variable", "ref" => "main.stats.hp"}
          }
        }
      }

      assert FormulaBindingRewriter.has_formula_variable_bindings?(cells)
    end
  end

  # =============================================================================
  # any_rows_have_formula_bindings?/1
  # =============================================================================

  describe "any_rows_have_formula_bindings?/1" do
    test "returns false for empty list" do
      refute FormulaBindingRewriter.any_rows_have_formula_bindings?([])
    end

    test "returns false when no rows have formula variable bindings" do
      rows = [
        %{cells: %{"a" => 1}},
        %{cells: %{"b" => "text"}}
      ]

      refute FormulaBindingRewriter.any_rows_have_formula_bindings?(rows)
    end

    test "returns true when at least one row has formula variable bindings" do
      rows = [
        %{cells: %{"a" => 1}},
        %{
          cells: %{
            "f" => %{
              "expression" => "b",
              "bindings" => %{"b" => %{"type" => "variable", "ref" => "main.stats.hp"}}
            }
          }
        }
      ]

      assert FormulaBindingRewriter.any_rows_have_formula_bindings?(rows)
    end
  end
end
