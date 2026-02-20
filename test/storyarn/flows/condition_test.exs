defmodule Storyarn.Flows.ConditionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Condition

  # =============================================================================
  # Helpers
  # =============================================================================

  defp make_rule(sheet, variable, operator, value \\ nil) do
    %{
      "id" => "rule_1",
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator,
      "value" => value
    }
  end

  defp make_flat(logic, rules) do
    %{"logic" => logic, "rules" => rules}
  end

  defp make_block(id, logic, rules, opts \\ []) do
    base = %{"id" => id, "type" => "block", "logic" => logic, "rules" => rules}
    if label = Keyword.get(opts, :label), do: Map.put(base, "label", label), else: base
  end

  defp make_group(id, logic, inner_blocks) do
    %{"id" => id, "type" => "group", "logic" => logic, "blocks" => inner_blocks}
  end

  defp make_block_condition(logic, blocks) do
    %{"logic" => logic, "blocks" => blocks}
  end

  # =============================================================================
  # Flat format — parse
  # =============================================================================

  describe "parse/1 flat format" do
    test "nil returns nil" do
      assert Condition.parse(nil) == nil
    end

    test "empty string returns nil" do
      assert Condition.parse("") == nil
    end

    test "valid JSON flat condition" do
      json = Jason.encode!(make_flat("all", [make_rule("mc", "hp", "equals", "50")]))
      result = Condition.parse(json)
      assert %{"logic" => "all", "rules" => [%{"sheet" => "mc"}]} = result
    end

    test "invalid JSON returns :legacy" do
      assert Condition.parse("not json") == :legacy
    end

    test "wrong structure returns :legacy" do
      assert Condition.parse(Jason.encode!(%{"foo" => "bar"})) == :legacy
    end
  end

  # =============================================================================
  # Block format — parse
  # =============================================================================

  describe "parse/1 block format" do
    test "parses block-format condition from JSON" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      condition = make_block_condition("any", [block])
      json = Jason.encode!(condition)

      result = Condition.parse(json)
      assert %{"logic" => "any", "blocks" => [%{"type" => "block", "id" => "b1"}]} = result
    end

    test "parses group inside blocks" do
      inner = make_block("b2", "all", [make_rule("mc", "hp", "greater_than", "10")])
      group = make_group("g1", "all", [inner])
      condition = make_block_condition("any", [group])
      json = Jason.encode!(condition)

      result = Condition.parse(json)
      assert %{"blocks" => [%{"type" => "group", "blocks" => [%{"type" => "block"}]}]} = result
    end

    test "strips nested groups inside groups" do
      inner_group = make_group("g_inner", "all", [])
      outer_group = make_group("g1", "all", [inner_group])
      condition = make_block_condition("all", [outer_group])
      json = Jason.encode!(condition)

      result = Condition.parse(json)
      # Inner group should be stripped (only blocks allowed in groups)
      assert %{"blocks" => [%{"type" => "group", "blocks" => []}]} = result
    end
  end

  # =============================================================================
  # to_json
  # =============================================================================

  describe "to_json/1" do
    test "flat format roundtrip" do
      condition = make_flat("all", [make_rule("mc", "hp", "equals", "50")])
      json = Condition.to_json(condition)
      assert is_binary(json)
      assert %{"logic" => "all", "rules" => [_]} = Jason.decode!(json)
    end

    test "block format roundtrip" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      condition = make_block_condition("any", [block])
      json = Condition.to_json(condition)
      assert is_binary(json)
      assert %{"logic" => "any", "blocks" => [_]} = Jason.decode!(json)
    end

    test "nil returns nil" do
      assert Condition.to_json(nil) == nil
    end

    test "empty flat rules returns nil" do
      assert Condition.to_json(%{"rules" => []}) == nil
    end

    test "empty blocks returns nil" do
      assert Condition.to_json(%{"blocks" => []}) == nil
    end
  end

  # =============================================================================
  # sanitize
  # =============================================================================

  describe "sanitize/1 flat format" do
    test "sanitizes flat condition" do
      result = Condition.sanitize(%{"logic" => "all", "rules" => [%{"sheet" => "mc", "variable" => "hp", "operator" => "equals", "value" => "10", "evil_key" => "bad"}]})
      assert %{"logic" => "all", "rules" => [rule]} = result
      refute Map.has_key?(rule, "evil_key")
    end

    test "invalid logic defaults to all" do
      result = Condition.sanitize(%{"logic" => "INVALID", "rules" => []})
      assert result["logic"] == "all"
    end

    test "non-map input defaults to empty flat" do
      assert Condition.sanitize("bad") == %{"logic" => "all", "rules" => []}
    end
  end

  describe "sanitize/1 block format" do
    test "sanitizes block-format condition" do
      block = Map.put(make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")]), "evil", "bad")
      condition = make_block_condition("any", [block])

      result = Condition.sanitize(condition)
      assert %{"logic" => "any", "blocks" => [sanitized_block]} = result
      assert sanitized_block["type"] == "block"
      refute Map.has_key?(sanitized_block, "evil")
    end

    test "preserves labels on blocks" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")], label: "Case A")
      condition = make_block_condition("all", [block])

      result = Condition.sanitize(condition)
      assert %{"blocks" => [%{"label" => "Case A"}]} = result
    end

    test "strips nested groups inside groups" do
      inner_group = make_group("g_bad", "all", [])
      outer_group = make_group("g1", "all", [inner_group])
      condition = make_block_condition("all", [outer_group])

      result = Condition.sanitize(condition)
      assert %{"blocks" => [%{"type" => "group", "blocks" => []}]} = result
    end

    test "removes invalid block types" do
      bad_block = %{"type" => "unknown", "data" => "bad"}
      condition = make_block_condition("all", [bad_block])

      result = Condition.sanitize(condition)
      assert %{"blocks" => []} = result
    end
  end

  # =============================================================================
  # validate
  # =============================================================================

  describe "validate/1" do
    test "valid flat condition" do
      condition = make_flat("all", [make_rule("mc", "hp", "equals", "50")])
      assert {:ok, _} = Condition.validate(condition)
    end

    test "invalid flat condition" do
      condition = make_flat("all", [%{"bad" => true}])
      assert {:error, "Invalid rule structure"} = Condition.validate(condition)
    end

    test "valid block condition" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      condition = make_block_condition("any", [block])
      assert {:ok, _} = Condition.validate(condition)
    end

    test "invalid block condition" do
      bad_block = %{"type" => "block", "rules" => [%{"bad" => true}]}
      condition = make_block_condition("all", [bad_block])
      assert {:error, "Invalid block structure"} = Condition.validate(condition)
    end

    test "invalid structure" do
      assert {:error, "Invalid condition structure"} = Condition.validate("bad")
    end
  end

  # =============================================================================
  # has_rules?
  # =============================================================================

  describe "has_rules?/1" do
    test "nil returns false" do
      refute Condition.has_rules?(nil)
    end

    test "flat with valid rules returns true" do
      condition = make_flat("all", [make_rule("mc", "hp", "equals", "50")])
      assert Condition.has_rules?(condition)
    end

    test "flat with empty rules returns false" do
      refute Condition.has_rules?(make_flat("all", []))
    end

    test "block with valid rules returns true" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      condition = make_block_condition("all", [block])
      assert Condition.has_rules?(condition)
    end

    test "block with empty rules returns false" do
      block = make_block("b1", "all", [])
      condition = make_block_condition("all", [block])
      refute Condition.has_rules?(condition)
    end

    test "group with rules in inner blocks returns true" do
      inner = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      group = make_group("g1", "all", [inner])
      condition = make_block_condition("all", [group])
      assert Condition.has_rules?(condition)
    end

    test "group with empty inner blocks returns false" do
      inner = make_block("b1", "all", [])
      group = make_group("g1", "all", [inner])
      condition = make_block_condition("all", [group])
      refute Condition.has_rules?(condition)
    end
  end

  # =============================================================================
  # upgrade
  # =============================================================================

  describe "upgrade/1" do
    test "upgrades flat condition to block format" do
      flat = make_flat("any", [make_rule("mc", "hp", "equals", "50")])
      result = Condition.upgrade(flat)

      assert %{"logic" => "all", "blocks" => [block]} = result
      assert block["type"] == "block"
      assert block["logic"] == "any"
      assert length(block["rules"]) == 1
    end

    test "passes through block-format unchanged" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      block_cond = make_block_condition("any", [block])

      assert Condition.upgrade(block_cond) == block_cond
    end

    test "nil returns empty block condition" do
      result = Condition.upgrade(nil)
      assert %{"logic" => "all", "blocks" => []} = result
    end

    test "invalid input returns empty block condition" do
      result = Condition.upgrade("bad")
      assert %{"logic" => "all", "blocks" => []} = result
    end

    test "preserves rules and logic from flat format" do
      rule1 = make_rule("mc", "hp", "greater_than", "50")
      rule2 = make_rule("mc", "alive", "is_true")
      flat = make_flat("any", [rule1, rule2])
      result = Condition.upgrade(flat)

      assert %{"blocks" => [%{"logic" => "any", "rules" => rules}]} = result
      assert length(rules) == 2
    end
  end

  # =============================================================================
  # new_block_condition
  # =============================================================================

  describe "new_block_condition/1" do
    test "creates empty block condition with default logic" do
      result = Condition.new_block_condition()
      assert result == %{"logic" => "all", "blocks" => []}
    end

    test "creates with specified logic" do
      result = Condition.new_block_condition("any")
      assert result == %{"logic" => "any", "blocks" => []}
    end
  end

  # =============================================================================
  # extract_all_rules
  # =============================================================================

  describe "extract_all_rules/1" do
    test "nil returns empty" do
      assert Condition.extract_all_rules(nil) == []
    end

    test "flat format extracts rules" do
      rules = [make_rule("mc", "hp", "equals", "50"), make_rule("mc", "alive", "is_true")]
      condition = make_flat("all", rules)
      assert length(Condition.extract_all_rules(condition)) == 2
    end

    test "block format extracts rules from blocks" do
      block1 = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      block2 = make_block("b2", "all", [make_rule("mc", "alive", "is_true")])
      condition = make_block_condition("any", [block1, block2])
      assert length(Condition.extract_all_rules(condition)) == 2
    end

    test "extracts rules from groups" do
      inner1 = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      inner2 = make_block("b2", "all", [make_rule("mc", "alive", "is_true")])
      group = make_group("g1", "all", [inner1, inner2])
      condition = make_block_condition("all", [group])
      assert length(Condition.extract_all_rules(condition)) == 2
    end

    test "extracts rules from mixed blocks and groups" do
      standalone = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      inner = make_block("b2", "all", [make_rule("mc", "alive", "is_true"), make_rule("mc", "class", "equals", "warrior")])
      group = make_group("g1", "all", [inner])
      condition = make_block_condition("any", [standalone, group])
      assert length(Condition.extract_all_rules(condition)) == 3
    end

    test "empty condition returns empty" do
      assert Condition.extract_all_rules(%{"blocks" => []}) == []
      assert Condition.extract_all_rules(%{"rules" => []}) == []
    end

    test "invalid input returns empty" do
      assert Condition.extract_all_rules("bad") == []
    end
  end

  # =============================================================================
  # Backwards compatibility roundtrips
  # =============================================================================

  describe "backwards compatibility" do
    test "flat format parse → to_json roundtrip" do
      original = make_flat("all", [make_rule("mc", "hp", "equals", "50")])
      json = Condition.to_json(original)
      parsed = Condition.parse(json)
      assert parsed["logic"] == "all"
      assert length(parsed["rules"]) == 1
    end

    test "block format parse → to_json roundtrip" do
      block = make_block("b1", "all", [make_rule("mc", "hp", "equals", "50")])
      original = make_block_condition("any", [block])
      json = Condition.to_json(original)
      parsed = Condition.parse(json)
      assert parsed["logic"] == "any"
      assert length(parsed["blocks"]) == 1
    end

    test "upgrade flat → to_json → parse roundtrip" do
      flat = make_flat("any", [make_rule("mc", "hp", "equals", "50")])
      upgraded = Condition.upgrade(flat)
      json = Condition.to_json(upgraded)
      parsed = Condition.parse(json)
      assert Map.has_key?(parsed, "blocks")
      assert length(parsed["blocks"]) == 1
    end

    test "existing flat-format functions still work" do
      # add_rule, remove_rule, update_rule, set_logic should be unchanged
      condition = Condition.new()
      assert condition == %{"logic" => "all", "rules" => []}

      with_rule = Condition.add_rule(condition)
      assert length(with_rule["rules"]) == 1

      rule_id = hd(with_rule["rules"])["id"]
      updated = Condition.update_rule(with_rule, rule_id, "sheet", "mc")
      assert hd(updated["rules"])["sheet"] == "mc"

      removed = Condition.remove_rule(updated, rule_id)
      assert removed["rules"] == []

      logic_changed = Condition.set_logic(Condition.new(), "any")
      assert logic_changed["logic"] == "any"
    end
  end

  # =============================================================================
  # Edge cases
  # =============================================================================

  describe "edge cases" do
    test "condition with both 'rules' and 'blocks' keys — blocks take precedence in sanitize" do
      # If JS sends both (shouldn't happen), blocks format wins
      mixed = %{"logic" => "all", "blocks" => [], "rules" => []}
      result = Condition.sanitize(mixed)
      assert Map.has_key?(result, "blocks")
    end

    test "malformed block types are rejected" do
      bad = %{"type" => "bad_type", "rules" => []}
      condition = %{"logic" => "all", "blocks" => [bad]}
      result = Condition.sanitize(condition)
      assert result["blocks"] == []
    end

    test "block without id gets one generated" do
      block = %{"type" => "block", "logic" => "all", "rules" => []}
      condition = %{"logic" => "all", "blocks" => [block]}
      result = Condition.sanitize(condition)
      assert is_binary(hd(result["blocks"])["id"])
    end
  end
end
