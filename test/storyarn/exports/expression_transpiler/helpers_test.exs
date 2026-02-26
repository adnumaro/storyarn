defmodule Storyarn.Exports.ExpressionTranspiler.HelpersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Exports.ExpressionTranspiler.Helpers

  # =============================================================================
  # format_var_ref/3
  # =============================================================================

  describe "format_var_ref/3" do
    test "underscore style converts dots to underscores" do
      assert Helpers.format_var_ref("mc.jaime", "health", :underscore) == "mc_jaime_health"
    end

    test "underscore style converts hyphens to underscores" do
      assert Helpers.format_var_ref("mc-jaime", "max-health", :underscore) ==
               "mc_jaime_max_health"
    end

    test "dollar_underscore style adds $ prefix" do
      assert Helpers.format_var_ref("mc.jaime", "health", :dollar_underscore) ==
               "$mc_jaime_health"
    end

    test "lua_dict style wraps in Variable[]" do
      assert Helpers.format_var_ref("mc.jaime", "health", :lua_dict) ==
               ~s(Variable["mc.jaime.health"])
    end

    test "dot style preserves dots" do
      assert Helpers.format_var_ref("mc.jaime", "health", :dot) == "mc.jaime.health"
    end

    test "sanitizes unsafe characters in all styles" do
      # Characters like quotes, semicolons, etc. are stripped
      assert Helpers.format_var_ref("mc.jaime", "health", :dot) == "mc.jaime.health"

      # Dot style strips non-identifier chars
      assert Helpers.format_var_ref("mc\";jaime", "health", :dot) == "mcjaime.health"

      # Lua dict style strips non-identifier chars
      assert Helpers.format_var_ref("mc\"];jaime", "health", :lua_dict) ==
               ~s(Variable["mcjaime.health"])
    end

    test "single-segment names work" do
      assert Helpers.format_var_ref("player", "hp", :underscore) == "player_hp"
      assert Helpers.format_var_ref("player", "hp", :dot) == "player.hp"
    end
  end

  # =============================================================================
  # format_literal/2
  # =============================================================================

  describe "format_literal/2" do
    test "nil returns null keyword" do
      assert Helpers.format_literal(nil, []) == "null"
      assert Helpers.format_literal(nil, null_keyword: "None") == "None"
      assert Helpers.format_literal(nil, null_keyword: "nil") == "nil"
    end

    test "booleans stay unquoted" do
      assert Helpers.format_literal(true, []) == "true"
      assert Helpers.format_literal(false, []) == "false"
    end

    test "integers stay unquoted" do
      assert Helpers.format_literal(42, []) == "42"
      assert Helpers.format_literal(0, []) == "0"
      assert Helpers.format_literal(-5, []) == "-5"
    end

    test "floats stay unquoted" do
      assert Helpers.format_literal(3.14, []) == "3.14"
      assert Helpers.format_literal(-0.5, []) == "-0.5"
    end

    test "boolean strings stay unquoted" do
      assert Helpers.format_literal("true", []) == "true"
      assert Helpers.format_literal("false", []) == "false"
    end

    test "numeric strings stay unquoted" do
      assert Helpers.format_literal("42", []) == "42"
      assert Helpers.format_literal("-5", []) == "-5"
      assert Helpers.format_literal("3.14", []) == "3.14"
    end

    test "empty string gets quoted" do
      assert Helpers.format_literal("", []) == ~s("")
    end

    test "regular strings get double-quoted" do
      assert Helpers.format_literal("hello", []) == ~s("hello")
      assert Helpers.format_literal("warrior", []) == ~s("warrior")
    end

    test "strings with quotes are escaped" do
      assert Helpers.format_literal(~s(say "hi"), []) == ~s("say \\"hi\\"")
    end

    test "strings with backslashes are escaped" do
      assert Helpers.format_literal("path\\to", []) == ~s("path\\\\to")
    end

    test "strings with newlines are escaped" do
      assert Helpers.format_literal("line1\nline2", []) == ~s("line1\\nline2")
    end

    test "strings with carriage returns are escaped" do
      assert Helpers.format_literal("line1\rline2", []) == ~s("line1\\rline2")
    end

    test "strings with null bytes are stripped" do
      assert Helpers.format_literal("test\0data", []) == ~s("testdata")
    end

    test "non-string non-standard types convert via to_string" do
      assert Helpers.format_literal(:atom, []) == "atom"
    end
  end

  # =============================================================================
  # join_with_logic/3
  # =============================================================================

  describe "join_with_logic/3" do
    test "all uses AND keyword" do
      assert Helpers.join_with_logic("all", ["a", "b"], and_keyword: " && ") == "a && b"
    end

    test "any uses OR keyword" do
      assert Helpers.join_with_logic("any", ["a", "b"], or_keyword: " || ") == "a || b"
    end

    test "single part returns no joiner" do
      assert Helpers.join_with_logic("all", ["a"], and_keyword: " AND ") == "a"
    end

    test "empty list returns empty string" do
      assert Helpers.join_with_logic("all", [], and_keyword: " AND ") == ""
    end

    test "defaults to and for unknown logic" do
      assert Helpers.join_with_logic("unknown", ["a", "b"], and_keyword: " and ") == "a and b"
    end
  end

  # =============================================================================
  # decode_condition/1
  # =============================================================================

  describe "decode_condition/1" do
    test "nil returns {:ok, nil}" do
      assert Helpers.decode_condition(nil) == {:ok, nil}
    end

    test "empty string returns {:ok, nil}" do
      assert Helpers.decode_condition("") == {:ok, nil}
    end

    test "flat condition map passes through" do
      condition = %{"logic" => "all", "rules" => []}
      assert Helpers.decode_condition(condition) == {:ok, condition}
    end

    test "block condition map passes through" do
      condition = %{"logic" => "all", "blocks" => []}
      assert Helpers.decode_condition(condition) == {:ok, condition}
    end

    test "JSON string with rules is decoded" do
      json = Jason.encode!(%{"logic" => "all", "rules" => [%{"op" => "eq"}]})
      {:ok, result} = Helpers.decode_condition(json)
      assert result["logic"] == "all"
      assert is_list(result["rules"])
    end

    test "JSON string with blocks is decoded" do
      json = Jason.encode!(%{"logic" => "all", "blocks" => [%{"type" => "block"}]})
      {:ok, result} = Helpers.decode_condition(json)
      assert result["logic"] == "all"
      assert is_list(result["blocks"])
    end

    test "valid JSON but wrong shape returns legacy error" do
      json = Jason.encode!(%{"foo" => "bar"})
      assert {:error, {:legacy_condition, ^json}} = Helpers.decode_condition(json)
    end

    test "invalid JSON returns legacy error" do
      assert {:error, {:legacy_condition, "not json"}} = Helpers.decode_condition("not json")
    end

    test "legacy expression string returns error" do
      assert {:error, {:legacy_condition, "health > 50"}} =
               Helpers.decode_condition("health > 50")
    end

    test "other types return {:ok, nil}" do
      assert Helpers.decode_condition(42) == {:ok, nil}
      assert Helpers.decode_condition(:atom) == {:ok, nil}
    end
  end

  # =============================================================================
  # extract_condition_structure/1
  # =============================================================================

  describe "extract_condition_structure/1" do
    test "flat condition returns {:flat, logic, rules}" do
      condition = %{"logic" => "any", "rules" => [%{"op" => "eq"}]}
      assert {:flat, "any", [%{"op" => "eq"}]} = Helpers.extract_condition_structure(condition)
    end

    test "block condition returns {:blocks, logic, groups}" do
      block = %{"type" => "block", "logic" => "all", "rules" => [%{"op" => "eq"}]}
      condition = %{"logic" => "any", "blocks" => [block]}
      {:blocks, "any", groups} = Helpers.extract_condition_structure(condition)
      assert length(groups) == 1
      assert {"all", [%{"op" => "eq"}]} = hd(groups)
    end

    test "group with nested blocks extracts recursively" do
      inner_block = %{"type" => "block", "logic" => "all", "rules" => [%{"op" => "eq"}]}
      group = %{"type" => "group", "logic" => "any", "blocks" => [inner_block]}
      condition = %{"logic" => "all", "blocks" => [group]}

      {:blocks, "all", groups} = Helpers.extract_condition_structure(condition)
      assert length(groups) == 1
      {"any", inner} = hd(groups)
      assert length(inner) == 1
    end

    test "malformed blocks are filtered out" do
      bad_block = %{"type" => "unknown"}
      good_block = %{"type" => "block", "logic" => "all", "rules" => [%{"op" => "eq"}]}
      condition = %{"logic" => "all", "blocks" => [bad_block, good_block]}

      {:blocks, "all", groups} = Helpers.extract_condition_structure(condition)
      assert length(groups) == 1
    end

    test "catchall returns empty flat" do
      assert {:flat, "all", []} = Helpers.extract_condition_structure(%{})
      assert {:flat, "all", []} = Helpers.extract_condition_structure(%{"logic" => "all"})
    end
  end

  # =============================================================================
  # unsupported_op_warning/3
  # =============================================================================

  describe "unsupported_op_warning/3" do
    test "returns structured warning map" do
      warning = Helpers.unsupported_op_warning("contains", "Ink", "mc.jaime.health")

      assert warning.type == :unsupported_operator
      assert warning.message =~ "contains"
      assert warning.message =~ "Ink"
      assert warning.details.operator == "contains"
      assert warning.details.engine == "Ink"
      assert warning.details.variable == "mc.jaime.health"
    end
  end
end
