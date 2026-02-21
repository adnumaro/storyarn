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
