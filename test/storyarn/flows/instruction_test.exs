defmodule Storyarn.Flows.InstructionTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Instruction

  describe "new/0" do
    test "returns empty list" do
      assert Instruction.new() == []
    end
  end

  describe "add_assignment/1" do
    test "appends assignment with generated id and default fields" do
      assignments = Instruction.new()
      result = Instruction.add_assignment(assignments)

      assert length(result) == 1
      [assignment] = result

      assert String.starts_with?(assignment["id"], "assign_")
      assert assignment["sheet"] == nil
      assert assignment["variable"] == nil
      assert assignment["operator"] == "set"
      assert assignment["value"] == nil
      assert assignment["value_type"] == "literal"
      assert assignment["value_sheet"] == nil
    end

    test "appends to existing list" do
      assignments =
        Instruction.new()
        |> Instruction.add_assignment()
        |> Instruction.add_assignment()

      assert length(assignments) == 2
      # Each assignment has a unique id
      ids = Enum.map(assignments, & &1["id"])
      assert length(Enum.uniq(ids)) == 2
    end
  end

  describe "remove_assignment/2" do
    test "removes assignment by id" do
      assignments =
        Instruction.new()
        |> Instruction.add_assignment()
        |> Instruction.add_assignment()

      [first, second] = assignments
      result = Instruction.remove_assignment(assignments, first["id"])

      assert length(result) == 1
      assert hd(result)["id"] == second["id"]
    end

    test "returns empty list when removing last assignment" do
      assignments = Instruction.add_assignment([])
      [assignment] = assignments
      assert Instruction.remove_assignment(assignments, assignment["id"]) == []
    end
  end

  describe "update_assignment/4" do
    test "updates a field by assignment id" do
      assignments = Instruction.add_assignment([])
      [assignment] = assignments

      result = Instruction.update_assignment(assignments, assignment["id"], "sheet", "mc.jaime")
      [updated] = result

      assert updated["sheet"] == "mc.jaime"
      assert updated["id"] == assignment["id"]
    end

    test "clears value_sheet when value_type changes to literal" do
      assignments =
        Instruction.add_assignment([])
        |> then(fn [a] ->
          Instruction.update_assignment([a], a["id"], "value_type", "variable_ref")
        end)
        |> then(fn [a] ->
          Instruction.update_assignment([a], a["id"], "value_sheet", "global.quests")
        end)

      [with_ref] = assignments
      assert with_ref["value_sheet"] == "global.quests"

      result = Instruction.update_assignment(assignments, with_ref["id"], "value_type", "literal")
      [updated] = result

      assert updated["value_type"] == "literal"
      assert updated["value_sheet"] == nil
    end

    test "clears value when value_type changes to variable_ref" do
      assignments =
        Instruction.add_assignment([])
        |> then(fn [a] ->
          Instruction.update_assignment([a], a["id"], "value", "100")
        end)

      [with_val] = assignments
      assert with_val["value"] == "100"

      result =
        Instruction.update_assignment(assignments, with_val["id"], "value_type", "variable_ref")

      [updated] = result

      assert updated["value_type"] == "variable_ref"
      assert updated["value"] == nil
    end
  end

  describe "operators_for_type/1" do
    test "returns correct operators for number" do
      assert Instruction.operators_for_type("number") == ~w(set add subtract set_if_unset)
    end

    test "returns correct operators for boolean" do
      assert Instruction.operators_for_type("boolean") ==
               ~w(set_true set_false toggle set_if_unset)
    end

    test "returns correct operators for text" do
      assert Instruction.operators_for_type("text") == ~w(set clear set_if_unset)
    end

    test "returns correct operators for rich_text" do
      assert Instruction.operators_for_type("rich_text") == ~w(set clear set_if_unset)
    end

    test "returns correct operators for select" do
      assert Instruction.operators_for_type("select") == ~w(set set_if_unset)
    end

    test "returns correct operators for date" do
      assert Instruction.operators_for_type("date") == ~w(set set_if_unset)
    end

    test "returns text operators for unknown type" do
      assert Instruction.operators_for_type("unknown") == ~w(set clear set_if_unset)
    end
  end

  describe "operator_requires_value?/1" do
    test "returns false for set_true, set_false, toggle, clear" do
      refute Instruction.operator_requires_value?("set_true")
      refute Instruction.operator_requires_value?("set_false")
      refute Instruction.operator_requires_value?("toggle")
      refute Instruction.operator_requires_value?("clear")
    end

    test "returns true for set, add, subtract" do
      assert Instruction.operator_requires_value?("set")
      assert Instruction.operator_requires_value?("add")
      assert Instruction.operator_requires_value?("subtract")
    end
  end

  describe "valid_value_type?/1" do
    test "accepts literal and variable_ref" do
      assert Instruction.valid_value_type?("literal")
      assert Instruction.valid_value_type?("variable_ref")
    end

    test "rejects unknown types" do
      refute Instruction.valid_value_type?("unknown")
      refute Instruction.valid_value_type?("")
    end
  end

  describe "format_assignment_short/1" do
    test "formats literal value correctly" do
      assignment = %{
        "sheet" => "mc.jaime",
        "variable" => "health",
        "operator" => "add",
        "value" => "10",
        "value_type" => "literal"
      }

      assert Instruction.format_assignment_short(assignment) == "mc.jaime.health += 10"
    end

    test "formats variable_ref as sheet.variable" do
      assignment = %{
        "sheet" => "mc.link",
        "variable" => "hasMasterSword",
        "operator" => "set",
        "value_type" => "variable_ref",
        "value_sheet" => "global.quests",
        "value" => "swordDone"
      }

      assert Instruction.format_assignment_short(assignment) ==
               "mc.link.hasMasterSword = global.quests.swordDone"
    end

    test "formats no-value operators" do
      assert Instruction.format_assignment_short(%{
               "sheet" => "mc.jaime",
               "variable" => "alive",
               "operator" => "set_true"
             }) == "mc.jaime.alive = true"

      assert Instruction.format_assignment_short(%{
               "sheet" => "mc.jaime",
               "variable" => "alive",
               "operator" => "set_false"
             }) == "mc.jaime.alive = false"

      assert Instruction.format_assignment_short(%{
               "sheet" => "mc.jaime",
               "variable" => "alive",
               "operator" => "toggle"
             }) == "toggle mc.jaime.alive"

      assert Instruction.format_assignment_short(%{
               "sheet" => "mc.jaime",
               "variable" => "name",
               "operator" => "clear"
             }) == "clear mc.jaime.name"
    end

    test "returns empty string for incomplete assignments" do
      assert Instruction.format_assignment_short(%{}) == ""
      assert Instruction.format_assignment_short(%{"sheet" => "mc.jaime"}) == ""

      assert Instruction.format_assignment_short(%{"sheet" => "", "variable" => "health"}) ==
               ""
    end

    test "formats subtract correctly" do
      assignment = %{
        "sheet" => "mc.jaime",
        "variable" => "health",
        "operator" => "subtract",
        "value" => "20",
        "value_type" => "literal"
      }

      assert Instruction.format_assignment_short(assignment) == "mc.jaime.health -= 20"
    end
  end

  describe "complete_assignment?/1" do
    test "returns true for complete literal assignment" do
      assert Instruction.complete_assignment?(%{
               "sheet" => "mc.jaime",
               "variable" => "health",
               "operator" => "set",
               "value" => "100",
               "value_type" => "literal"
             })
    end

    test "returns true for complete variable_ref assignment" do
      assert Instruction.complete_assignment?(%{
               "sheet" => "mc.link",
               "variable" => "hasMasterSword",
               "operator" => "set",
               "value_type" => "variable_ref",
               "value_sheet" => "global.quests",
               "value" => "swordDone"
             })
    end

    test "returns true for no-value operators" do
      assert Instruction.complete_assignment?(%{
               "sheet" => "mc.jaime",
               "variable" => "alive",
               "operator" => "set_true"
             })
    end

    test "returns false for missing target" do
      refute Instruction.complete_assignment?(%{
               "sheet" => nil,
               "variable" => "health",
               "operator" => "set",
               "value" => "100"
             })
    end

    test "returns false for missing value when required" do
      refute Instruction.complete_assignment?(%{
               "sheet" => "mc.jaime",
               "variable" => "health",
               "operator" => "set",
               "value" => nil,
               "value_type" => "literal"
             })
    end
  end

  describe "has_assignments?/1" do
    test "returns false for nil" do
      refute Instruction.has_assignments?(nil)
    end

    test "returns false for empty list" do
      refute Instruction.has_assignments?([])
    end

    test "returns true when has complete assignment" do
      assert Instruction.has_assignments?([
               %{
                 "sheet" => "mc.jaime",
                 "variable" => "health",
                 "operator" => "set_true"
               }
             ])
    end
  end

  describe "sanitize/1" do
    test "keeps only known keys" do
      input = [
        %{
          "id" => "assign_1",
          "sheet" => "mc.jaime",
          "variable" => "health",
          "operator" => "set",
          "value" => "100",
          "value_type" => "literal",
          "value_sheet" => nil,
          "malicious_key" => "should_be_removed"
        }
      ]

      [sanitized] = Instruction.sanitize(input)

      assert Map.has_key?(sanitized, "id")
      assert Map.has_key?(sanitized, "sheet")
      refute Map.has_key?(sanitized, "malicious_key")
    end

    test "adds defaults for missing keys" do
      input = [%{"sheet" => "mc.jaime", "variable" => "health"}]
      [sanitized] = Instruction.sanitize(input)

      assert sanitized["operator"] == "set"
      assert sanitized["value_type"] == "literal"
      assert String.starts_with?(sanitized["id"], "assign_")
    end

    test "returns empty list for non-list input" do
      assert Instruction.sanitize(nil) == []
      assert Instruction.sanitize("invalid") == []
    end
  end

  describe "operators_for_type/1 — additional types" do
    test "returns select operators for multi_select" do
      assert Instruction.operators_for_type("multi_select") == ~w(set set_if_unset)
    end

    test "returns select operators for reference" do
      assert Instruction.operators_for_type("reference") == ~w(set set_if_unset)
    end
  end

  describe "operator_label/1 — all operators" do
    test "returns correct labels for all known operators" do
      assert Instruction.operator_label("set") == "="
      assert Instruction.operator_label("add") == "+="
      assert Instruction.operator_label("subtract") == "-="
      assert Instruction.operator_label("set_true") == "= true"
      assert Instruction.operator_label("set_false") == "= false"
      assert Instruction.operator_label("toggle") == "toggle"
      assert Instruction.operator_label("clear") == "clear"
    end

    test "returns the operator itself for unknown operators" do
      assert Instruction.operator_label("unknown_op") == "unknown_op"
    end
  end

  describe "valid_operator?/1" do
    test "returns true for all known operators" do
      for op <- Instruction.all_operators() do
        assert Instruction.valid_operator?(op), "Expected '#{op}' to be valid"
      end
    end

    test "returns false for unknown operators" do
      refute Instruction.valid_operator?("unknown")
      refute Instruction.valid_operator?("")
      refute Instruction.valid_operator?("SET")
    end
  end

  describe "all_operators/0" do
    test "returns a non-empty list of unique operators" do
      ops = Instruction.all_operators()
      assert [_ | _] = ops
      assert length(ops) == length(Enum.uniq(ops))
    end
  end

  describe "known_keys/0" do
    test "includes expected keys" do
      keys = Instruction.known_keys()
      assert "id" in keys
      assert "sheet" in keys
      assert "variable" in keys
      assert "operator" in keys
      assert "value" in keys
      assert "value_type" in keys
      assert "value_sheet" in keys
    end
  end

  describe "complete_assignment?/1 — edge cases" do
    test "returns false for non-map input" do
      refute Instruction.complete_assignment?("not a map")
      refute Instruction.complete_assignment?(nil)
      refute Instruction.complete_assignment?([])
    end

    test "returns false for incomplete variable_ref assignment" do
      refute Instruction.complete_assignment?(%{
               "sheet" => "mc.jaime",
               "variable" => "health",
               "operator" => "set",
               "value_type" => "variable_ref",
               "value_sheet" => "",
               "value" => "damage"
             })
    end
  end

  describe "has_assignments?/1 — edge cases" do
    test "returns false for non-list input" do
      refute Instruction.has_assignments?("not a list")
      refute Instruction.has_assignments?(42)
    end
  end

  describe "format_assignment_short/1 — edge cases" do
    test "shows ? when value is missing" do
      result =
        Instruction.format_assignment_short(%{
          "sheet" => "mc.jaime",
          "variable" => "health",
          "operator" => "set",
          "value_type" => "literal",
          "value" => nil
        })

      assert result == "mc.jaime.health = ?"
    end

    test "shows value when variable_ref has empty value_sheet" do
      result =
        Instruction.format_assignment_short(%{
          "sheet" => "mc.jaime",
          "variable" => "health",
          "operator" => "set",
          "value_type" => "variable_ref",
          "value_sheet" => "",
          "value" => "damage"
        })

      # Falls back to literal value display since value_sheet is empty
      assert result == "mc.jaime.health = damage"
    end

    test "shows ? when both value and value_sheet are nil" do
      result =
        Instruction.format_assignment_short(%{
          "sheet" => "mc.jaime",
          "variable" => "health",
          "operator" => "set",
          "value_type" => "variable_ref",
          "value_sheet" => nil,
          "value" => nil
        })

      assert result == "mc.jaime.health = ?"
    end
  end

  describe "set_if_unset operator" do
    test "is included in operators_for_type for all types" do
      for type <- ~w(number boolean text rich_text select multi_select date) do
        assert "set_if_unset" in Instruction.operators_for_type(type),
               "set_if_unset not in operators for #{type}"
      end
    end

    test "has correct label" do
      assert Instruction.operator_label("set_if_unset") == "?="
    end

    test "requires a value" do
      assert Instruction.operator_requires_value?("set_if_unset")
    end

    test "is in all_operators" do
      # Validate via complete_assignment? which checks @all_operators
      assert Instruction.complete_assignment?(%{
               "sheet" => "mc.jaime",
               "variable" => "health",
               "operator" => "set_if_unset",
               "value" => "100",
               "value_type" => "literal"
             })
    end

    test "formats correctly" do
      assignment = %{
        "sheet" => "mc.jaime",
        "variable" => "health",
        "operator" => "set_if_unset",
        "value" => "100",
        "value_type" => "literal"
      }

      assert Instruction.format_assignment_short(assignment) == "mc.jaime.health ?= 100"
    end
  end
end
