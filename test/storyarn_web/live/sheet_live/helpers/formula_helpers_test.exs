defmodule StoryarnWeb.SheetLive.Helpers.FormulaHelpersTest do
  use ExUnit.Case, async: true

  alias StoryarnWeb.SheetLive.Helpers.FormulaHelpers

  # ===========================================================================
  # formula_symbols/1
  # ===========================================================================

  describe "formula_symbols/1" do
    test "extracts symbols from expression" do
      assert FormulaHelpers.formula_symbols("a + b") == ["a", "b"]
    end

    test "extracts unique symbols" do
      assert FormulaHelpers.formula_symbols("a + a * b") == ["a", "b"]
    end

    test "returns empty list for invalid expression" do
      assert FormulaHelpers.formula_symbols("+++") == []
    end

    test "returns empty list for nil" do
      assert FormulaHelpers.formula_symbols(nil) == []
    end

    test "returns empty list for empty string" do
      assert FormulaHelpers.formula_symbols("") == []
    end

    test "handles expression with functions" do
      symbols = FormulaHelpers.formula_symbols("floor(a) + ceil(b)")
      assert "a" in symbols
      assert "b" in symbols
    end
  end

  # ===========================================================================
  # formula_cell_expression/1
  # ===========================================================================

  describe "formula_cell_expression/1" do
    test "extracts expression from cell map" do
      assert FormulaHelpers.formula_cell_expression(%{"expression" => "a + b"}) == "a + b"
    end

    test "returns empty string for nil" do
      assert FormulaHelpers.formula_cell_expression(nil) == ""
    end

    test "returns empty string for non-map" do
      assert FormulaHelpers.formula_cell_expression(42) == ""
    end

    test "returns empty string for map without expression" do
      assert FormulaHelpers.formula_cell_expression(%{"other" => "val"}) == ""
    end
  end

  # ===========================================================================
  # formula_cell_result/1
  # ===========================================================================

  describe "formula_cell_result/1" do
    test "extracts __result from cell" do
      assert FormulaHelpers.formula_cell_result(%{"__result" => 42}) == 42
    end

    test "returns nil when no __result" do
      assert FormulaHelpers.formula_cell_result(%{"expression" => "a"}) == nil
    end

    test "returns nil for non-map" do
      assert FormulaHelpers.formula_cell_result(nil) == nil
    end
  end

  # ===========================================================================
  # formula_cell_binding/2
  # ===========================================================================

  describe "formula_cell_binding/2" do
    test "returns same_row binding as prefixed string" do
      cell = %{"bindings" => %{"a" => %{"type" => "same_row", "column_slug" => "value"}}}
      assert FormulaHelpers.formula_cell_binding(cell, "a") == "same_row:value"
    end

    test "returns variable binding as ref string" do
      cell = %{"bindings" => %{"b" => %{"type" => "variable", "ref" => "mc.stats.hp.value"}}}
      assert FormulaHelpers.formula_cell_binding(cell, "b") == "mc.stats.hp.value"
    end

    test "returns empty string for unknown symbol" do
      cell = %{"bindings" => %{"a" => %{"type" => "same_row", "column_slug" => "value"}}}
      assert FormulaHelpers.formula_cell_binding(cell, "z") == ""
    end

    test "returns empty string for nil cell" do
      assert FormulaHelpers.formula_cell_binding(nil, "a") == ""
    end

    test "returns empty string for cell without bindings" do
      assert FormulaHelpers.formula_cell_binding(%{"expression" => "a"}, "a") == ""
    end

    test "returns empty string for unrecognized binding type" do
      cell = %{"bindings" => %{"a" => %{"type" => "unknown"}}}
      assert FormulaHelpers.formula_cell_binding(cell, "a") == ""
    end
  end

  # ===========================================================================
  # formula_preview_from_cell/1
  # ===========================================================================

  describe "formula_preview_from_cell/1" do
    test "generates LaTeX preview from valid expression" do
      cell = %{"expression" => "a + b"}
      result = FormulaHelpers.formula_preview_from_cell(cell)
      assert is_binary(result)
      assert result != ""
    end

    test "returns em dash for nil cell" do
      assert FormulaHelpers.formula_preview_from_cell(nil) == "\u2014"
    end

    test "returns em dash for empty expression" do
      assert FormulaHelpers.formula_preview_from_cell(%{"expression" => ""}) == "\u2014"
    end

    test "returns error message for invalid expression" do
      result = FormulaHelpers.formula_preview_from_cell(%{"expression" => "+++"})
      assert String.starts_with?(result, "Error:")
    end
  end

  # ===========================================================================
  # format_formula_value/1
  # ===========================================================================

  describe "format_formula_value/1" do
    test "nil returns nil" do
      assert FormulaHelpers.format_formula_value(nil) == nil
    end

    test "whole float becomes integer string" do
      assert FormulaHelpers.format_formula_value(10.0) == "10"
    end

    test "decimal float formatted to 2 places" do
      assert FormulaHelpers.format_formula_value(3.14) == "3.14"
    end

    test "integer becomes string" do
      assert FormulaHelpers.format_formula_value(42) == "42"
    end

    test "other values converted to string" do
      assert FormulaHelpers.format_formula_value("hello") == "hello"
    end
  end

  # ===========================================================================
  # parse_binding_value/1
  # ===========================================================================

  describe "parse_binding_value/1" do
    test "empty string returns nil" do
      assert FormulaHelpers.parse_binding_value("") == nil
    end

    test "same_row prefix returns same_row binding" do
      assert FormulaHelpers.parse_binding_value("same_row:value") ==
               %{"type" => "same_row", "column_slug" => "value"}
    end

    test "variable ref returns variable binding" do
      assert FormulaHelpers.parse_binding_value("mc.stats.hp.value") ==
               %{"type" => "variable", "ref" => "mc.stats.hp.value"}
    end
  end

  # ===========================================================================
  # encode_bindings/1
  # ===========================================================================

  describe "encode_bindings/1" do
    test "encodes same_row binding to prefixed string" do
      bindings = %{"a" => %{"type" => "same_row", "column_slug" => "value"}}
      assert FormulaHelpers.encode_bindings(bindings) == %{"a" => "same_row:value"}
    end

    test "encodes variable binding to ref string" do
      bindings = %{"b" => %{"type" => "variable", "ref" => "mc.hp"}}
      assert FormulaHelpers.encode_bindings(bindings) == %{"b" => "mc.hp"}
    end

    test "encodes unknown binding type to empty string" do
      bindings = %{"x" => %{"type" => "unknown"}}
      assert FormulaHelpers.encode_bindings(bindings) == %{"x" => ""}
    end

    test "handles multiple bindings" do
      bindings = %{
        "a" => %{"type" => "same_row", "column_slug" => "base"},
        "b" => %{"type" => "variable", "ref" => "mc.mod"}
      }

      result = FormulaHelpers.encode_bindings(bindings)
      assert result == %{"a" => "same_row:base", "b" => "mc.mod"}
    end

    test "non-map returns empty map" do
      assert FormulaHelpers.encode_bindings(nil) == %{}
    end

    test "round-trips with parse_binding_value" do
      bindings = %{
        "a" => %{"type" => "same_row", "column_slug" => "value"},
        "b" => %{"type" => "variable", "ref" => "mc.stats.hp"}
      }

      encoded = FormulaHelpers.encode_bindings(bindings)

      restored =
        Map.new(encoded, fn {symbol, value} ->
          {symbol, FormulaHelpers.parse_binding_value(value)}
        end)

      assert restored == bindings
    end
  end

  # ===========================================================================
  # build_binding_options/2
  # ===========================================================================

  describe "build_binding_options/2" do
    test "builds same-row options from columns" do
      cols = [
        %{slug: "base", name: "Base Value"},
        %{slug: "mod", name: "Modifier"}
      ]

      options = FormulaHelpers.build_binding_options(cols, %{})

      assert [
               %{value: "same_row:base", label: "Base Value", group: "Same row"},
               %{value: "same_row:mod", label: "Modifier", group: "Same row"}
             ] == options
    end

    test "builds cross-sheet options from variables" do
      vars = %{
        "mc.jaime" => [
          %{variable_name: "health"},
          %{variable_name: "armor"}
        ]
      }

      options = FormulaHelpers.build_binding_options([], vars)

      assert [
               %{value: "mc.jaime.health", label: "health", group: "mc.jaime"},
               %{value: "mc.jaime.armor", label: "armor", group: "mc.jaime"}
             ] == options
    end

    test "combines same-row and cross-sheet, same-row first" do
      cols = [%{slug: "base", name: "Base"}]

      vars = %{
        "mc" => [%{variable_name: "hp"}]
      }

      options = FormulaHelpers.build_binding_options(cols, vars)
      assert length(options) == 2
      assert hd(options).group == "Same row"
      assert List.last(options).group == "mc"
    end

    test "sorts cross-sheet groups alphabetically" do
      vars = %{
        "zz.sheet" => [%{variable_name: "v1"}],
        "aa.sheet" => [%{variable_name: "v2"}]
      }

      options = FormulaHelpers.build_binding_options([], vars)
      groups = Enum.map(options, & &1.group)
      assert groups == ["aa.sheet", "zz.sheet"]
    end
  end

  # ===========================================================================
  # formula_binding_display/3
  # ===========================================================================

  describe "formula_binding_display/3" do
    test "shows column name for same_row binding" do
      cell = %{"bindings" => %{"a" => %{"type" => "same_row", "column_slug" => "base"}}}
      cols = [%{slug: "base", name: "Base Value"}]

      assert FormulaHelpers.formula_binding_display(cell, "a", cols) == "Base Value"
    end

    test "shows slug when column not found" do
      cell = %{"bindings" => %{"a" => %{"type" => "same_row", "column_slug" => "deleted"}}}
      assert FormulaHelpers.formula_binding_display(cell, "a", []) == "deleted"
    end

    test "shows ref path for variable binding" do
      cell = %{"bindings" => %{"b" => %{"type" => "variable", "ref" => "mc.stats.hp"}}}
      assert FormulaHelpers.formula_binding_display(cell, "b", []) == "mc.stats.hp"
    end

    test "returns empty string for unbound symbol" do
      cell = %{"bindings" => %{}}
      assert FormulaHelpers.formula_binding_display(cell, "x", []) == ""
    end

    test "returns empty string for nil cell" do
      assert FormulaHelpers.formula_binding_display(nil, "a", []) == ""
    end
  end
end
