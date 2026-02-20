defmodule Storyarn.Flows.Evaluator.InstructionExecTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.InstructionExec

  # Helper to build a variable entry
  defp var(value, block_type) do
    %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: 1,
      sheet_shortcut: "test",
      variable_name: "var"
    }
  end

  defp make_assignment(sheet, variable, operator, value \\ nil, opts \\ []) do
    base = %{
      "id" => "assign_1",
      "sheet" => sheet,
      "variable" => variable,
      "operator" => operator,
      "value" => value,
      "value_type" => Keyword.get(opts, :value_type, "literal"),
      "value_sheet" => Keyword.get(opts, :value_sheet)
    }

    base
  end

  # =============================================================================
  # Edge cases
  # =============================================================================

  describe "execute/2 edge cases" do
    test "empty assignments list" do
      assert {:ok, %{}, [], []} = InstructionExec.execute([], %{})
    end

    test "nil assignments" do
      assert {:ok, %{}, [], []} = InstructionExec.execute(nil, %{})
    end

    test "incomplete assignments are skipped" do
      assignments = [
        %{
          "id" => "a1",
          "sheet" => "mc",
          "variable" => nil,
          "operator" => "set",
          "value" => "x",
          "value_type" => "literal",
          "value_sheet" => nil
        }
      ]

      assert {:ok, %{}, [], []} = InstructionExec.execute(assignments, %{})
    end

    test "missing variable produces error" do
      assignments = [make_assignment("mc.jaime", "health", "set", "50")]

      assert {:ok, vars, [], [error]} = InstructionExec.execute(assignments, %{})
      assert vars == %{}
      assert error.variable_ref == "mc.jaime.health"
      assert error.reason =~ "not found"
    end
  end

  # =============================================================================
  # Number operators
  # =============================================================================

  describe "number operators" do
    setup do
      {:ok, variables: %{"mc.jaime.health" => var(100, "number")}}
    end

    test "set", %{variables: v} do
      assignments = [make_assignment("mc.jaime", "health", "set", "50")]
      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, v)

      assert new_vars["mc.jaime.health"].value == 50.0
      assert new_vars["mc.jaime.health"].source == :instruction
      assert new_vars["mc.jaime.health"].previous_value == 100
      assert [%{old_value: 100, new_value: 50.0, operator: "set"}] = changes
    end

    test "add", %{variables: v} do
      assignments = [make_assignment("mc.jaime", "health", "add", "20")]
      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, v)

      assert new_vars["mc.jaime.health"].value == 120
      assert [%{old_value: 100, new_value: 120.0, operator: "add"}] = changes
    end

    test "subtract", %{variables: v} do
      assignments = [make_assignment("mc.jaime", "health", "subtract", "30")]
      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, v)

      assert new_vars["mc.jaime.health"].value == 70
      assert [%{old_value: 100, new_value: 70.0, operator: "subtract"}] = changes
    end

    test "add with nil old value defaults to 0" do
      variables = %{"mc.jaime.health" => var(nil, "number")}
      assignments = [make_assignment("mc.jaime", "health", "add", "20")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 20
    end

    test "add with non-numeric value defaults to 0" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      assignments = [make_assignment("mc.jaime", "health", "add", "not_a_number")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 100
    end
  end

  # =============================================================================
  # Boolean operators
  # =============================================================================

  describe "boolean operators" do
    test "set_true" do
      variables = %{"mc.jaime.alive" => var(false, "boolean")}
      assignments = [make_assignment("mc.jaime", "alive", "set_true")]
      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.alive"].value == true
      assert [%{old_value: false, new_value: true, operator: "set_true"}] = changes
    end

    test "set_false" do
      variables = %{"mc.jaime.alive" => var(true, "boolean")}
      assignments = [make_assignment("mc.jaime", "alive", "set_false")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.alive"].value == false
    end

    test "toggle from true" do
      variables = %{"mc.jaime.alive" => var(true, "boolean")}
      assignments = [make_assignment("mc.jaime", "alive", "toggle")]
      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.alive"].value == false
      assert [%{operator: "toggle"}] = changes
    end

    test "toggle from false" do
      variables = %{"mc.jaime.alive" => var(false, "boolean")}
      assignments = [make_assignment("mc.jaime", "alive", "toggle")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.alive"].value == true
    end
  end

  # =============================================================================
  # Text operators
  # =============================================================================

  describe "text operators" do
    test "set" do
      variables = %{"mc.jaime.name" => var("old name", "text")}
      assignments = [make_assignment("mc.jaime", "name", "set", "Jaime Lannister")]
      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.name"].value == "Jaime Lannister"
      assert [%{old_value: "old name", new_value: "Jaime Lannister"}] = changes
    end

    test "clear" do
      variables = %{"mc.jaime.name" => var("Jaime", "text")}
      assignments = [make_assignment("mc.jaime", "name", "clear")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.name"].value == nil
    end

    test "rich_text set" do
      variables = %{"mc.jaime.bio" => var("old bio", "rich_text")}
      assignments = [make_assignment("mc.jaime", "bio", "set", "<p>New bio</p>")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.bio"].value == "<p>New bio</p>"
    end

    test "rich_text clear" do
      variables = %{"mc.jaime.bio" => var("<p>Bio</p>", "rich_text")}
      assignments = [make_assignment("mc.jaime", "bio", "clear")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.bio"].value == nil
    end
  end

  # =============================================================================
  # Select / date operators
  # =============================================================================

  describe "select operators" do
    test "set" do
      variables = %{"mc.jaime.class" => var("warrior", "select")}
      assignments = [make_assignment("mc.jaime", "class", "set", "mage")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.class"].value == "mage"
    end
  end

  describe "date operators" do
    test "set" do
      variables = %{"world.date" => var("2024-01-01", "date")}
      assignments = [make_assignment("world", "date", "set", "2024-12-31")]
      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["world.date"].value == "2024-12-31"
    end
  end

  # =============================================================================
  # Variable references
  # =============================================================================

  describe "variable_ref" do
    test "resolve value from another variable" do
      variables = %{
        "mc.jaime.health" => var(80, "number"),
        "mc.jaime.max_health" => var(100, "number")
      }

      assignments = [
        make_assignment("mc.jaime", "health", "set", "max_health",
          value_type: "variable_ref",
          value_sheet: "mc.jaime"
        )
      ]

      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 100
      assert [%{old_value: 80, new_value: 100}] = changes
    end

    test "missing referenced variable produces error" do
      variables = %{"mc.jaime.health" => var(80, "number")}

      assignments = [
        make_assignment("mc.jaime", "health", "set", "missing_var",
          value_type: "variable_ref",
          value_sheet: "mc.jaime"
        )
      ]

      {:ok, vars, [], [error]} = InstructionExec.execute(assignments, variables)

      # Variable unchanged
      assert vars["mc.jaime.health"].value == 80
      assert error.reason =~ "not found"
    end

    test "incomplete variable reference is filtered by complete_assignment? check" do
      variables = %{"mc.jaime.health" => var(80, "number")}

      # nil value_sheet + nil value fails Instruction.complete_assignment?/1
      # so the assignment is silently skipped (never reaches execution)
      assignments = [
        make_assignment("mc.jaime", "health", "set", nil,
          value_type: "variable_ref",
          value_sheet: nil
        )
      ]

      {:ok, vars, [], []} = InstructionExec.execute(assignments, variables)
      assert vars["mc.jaime.health"].value == 80
    end
  end

  # =============================================================================
  # Multiple assignments
  # =============================================================================

  describe "multiple assignments" do
    test "executes in order, each sees previous changes" do
      variables = %{
        "mc.jaime.health" => var(100, "number"),
        "mc.jaime.alive" => var(true, "boolean")
      }

      assignments = [
        make_assignment("mc.jaime", "health", "subtract", "120"),
        make_assignment("mc.jaime", "alive", "set_false")
      ]

      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == -20
      assert new_vars["mc.jaime.alive"].value == false
      assert length(changes) == 2
    end

    test "error in one assignment does not stop others" do
      variables = %{"mc.jaime.health" => var(100, "number")}

      assignments = [
        make_assignment("mc.jaime", "missing", "set", "50"),
        make_assignment("mc.jaime", "health", "set", "50")
      ]

      {:ok, new_vars, changes, errors} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 50.0
      assert length(changes) == 1
      assert length(errors) == 1
    end

    test "chained operations on same variable" do
      variables = %{"mc.jaime.health" => var(100, "number")}

      assignments = [
        make_assignment("mc.jaime", "health", "subtract", "30"),
        %{make_assignment("mc.jaime", "health", "add", "10") | "id" => "assign_2"}
      ]

      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 80
      assert length(changes) == 2
      assert Enum.at(changes, 0).new_value == 70
      assert Enum.at(changes, 1).new_value == 80
    end
  end

  # =============================================================================
  # execute_string/2
  # =============================================================================

  describe "execute_string/2" do
    test "nil string" do
      assert {:ok, %{}, [], []} = InstructionExec.execute_string(nil, %{})
    end

    test "empty string" do
      assert {:ok, %{}, [], []} = InstructionExec.execute_string("", %{})
    end

    test "valid JSON assignments" do
      variables = %{"mc.jaime.health" => var(100, "number")}

      json =
        Jason.encode!([
          %{
            "id" => "a1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "subtract",
            "value" => "20",
            "value_type" => "literal"
          }
        ])

      {:ok, new_vars, [change], []} = InstructionExec.execute_string(json, variables)

      assert new_vars["mc.jaime.health"].value == 80
      assert change.operator == "subtract"
    end

    test "invalid JSON string" do
      assert {:ok, %{}, [], []} = InstructionExec.execute_string("not json", %{})
    end
  end

  # =============================================================================
  # Source tracking
  # =============================================================================

  describe "source tracking" do
    test "source is set to :instruction after mutation" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      assignments = [make_assignment("mc.jaime", "health", "set", "50")]

      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].source == :instruction
    end

    test "previous_value is updated" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      assignments = [make_assignment("mc.jaime", "health", "set", "50")]

      {:ok, new_vars, _, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].previous_value == 100
    end
  end

  describe "set_if_unset operator" do
    test "sets value when current is nil" do
      variables = %{"mc.jaime.health" => var(nil, "number")}
      assignments = [make_assignment("mc.jaime", "health", "set_if_unset", "100")]

      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 100.0
      assert length(changes) == 1
    end

    test "does not overwrite existing value" do
      variables = %{"mc.jaime.health" => var(50, "number")}
      assignments = [make_assignment("mc.jaime", "health", "set_if_unset", "100")]

      {:ok, new_vars, _changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.health"].value == 50
    end

    test "sets string value when nil" do
      variables = %{"mc.jaime.class" => var(nil, "select")}
      assignments = [make_assignment("mc.jaime", "class", "set_if_unset", "warrior")]

      {:ok, new_vars, changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.class"].value == "warrior"
      assert length(changes) == 1
    end

    test "does not overwrite existing string" do
      variables = %{"mc.jaime.class" => var("mage", "select")}
      assignments = [make_assignment("mc.jaime", "class", "set_if_unset", "warrior")]

      {:ok, new_vars, _changes, []} = InstructionExec.execute(assignments, variables)

      assert new_vars["mc.jaime.class"].value == "mage"
    end
  end
end
