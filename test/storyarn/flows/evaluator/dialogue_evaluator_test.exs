defmodule Storyarn.Flows.Evaluator.NodeEvaluators.DialogueEvaluatorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.NodeEvaluators.DialogueEvaluator
  alias Storyarn.Flows.Evaluator.State

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

  defp make_state(variables) do
    %State{
      start_node_id: 1,
      current_node_id: 1,
      variables: variables,
      initial_variables: variables
    }
  end

  defp make_node(responses) do
    %{
      id: 1,
      data: %{
        "responses" => responses,
        "label" => "Test Dialogue"
      }
    }
  end

  defp make_connection(source_node_id, source_pin, target_node_id) do
    %{
      id: 100,
      source_node_id: source_node_id,
      source_pin: source_pin,
      target_node_id: target_node_id,
      target_input: "input"
    }
  end

  describe "response instruction_assignments execution" do
    test "executes structured assignments when response auto-selected" do
      variables = %{"mc.jaime.health" => var(50, "number")}
      state = make_state(variables)

      responses = [
        %{
          "id" => "r1",
          "text" => "Only choice",
          "condition" => nil,
          "instruction" => nil,
          "instruction_assignments" => [
            %{
              "id" => "assign_1",
              "sheet" => "mc.jaime",
              "variable" => "health",
              "operator" => "add",
              "value" => "25",
              "value_type" => "literal",
              "value_sheet" => nil
            }
          ]
        }
      ]

      node = make_node(responses)
      connections = [make_connection(1, "r1", 2)]

      {:ok, new_state} = DialogueEvaluator.evaluate(node, state, connections)

      assert new_state.variables["mc.jaime.health"].value == 75.0
    end

    test "prefers instruction_assignments over legacy instruction string" do
      variables = %{"mc.jaime.health" => var(50, "number")}
      state = make_state(variables)

      responses = [
        %{
          "id" => "r1",
          "text" => "Only choice",
          "condition" => nil,
          "instruction" => "[]",
          "instruction_assignments" => [
            %{
              "id" => "assign_1",
              "sheet" => "mc.jaime",
              "variable" => "health",
              "operator" => "set",
              "value" => "999",
              "value_type" => "literal",
              "value_sheet" => nil
            }
          ]
        }
      ]

      node = make_node(responses)
      connections = [make_connection(1, "r1", 2)]

      {:ok, new_state} = DialogueEvaluator.evaluate(node, state, connections)

      # instruction_assignments takes priority
      assert new_state.variables["mc.jaime.health"].value == 999.0
    end

    test "falls back to legacy instruction string when no assignments" do
      variables = %{"mc.jaime.health" => var(50, "number")}
      state = make_state(variables)

      # Legacy format: JSON array of assignments stored as a string
      legacy_json =
        Jason.encode!([
          %{
            "id" => "assign_1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "set",
            "value" => "100",
            "value_type" => "literal",
            "value_sheet" => nil
          }
        ])

      responses = [
        %{
          "id" => "r1",
          "text" => "Only choice",
          "condition" => nil,
          "instruction" => legacy_json,
          "instruction_assignments" => []
        }
      ]

      node = make_node(responses)
      connections = [make_connection(1, "r1", 2)]

      {:ok, new_state} = DialogueEvaluator.evaluate(node, state, connections)

      assert new_state.variables["mc.jaime.health"].value == 100.0
    end

    test "does nothing when no instruction fields are set" do
      variables = %{"mc.jaime.health" => var(50, "number")}
      state = make_state(variables)

      responses = [
        %{
          "id" => "r1",
          "text" => "Only choice",
          "condition" => nil,
          "instruction" => nil,
          "instruction_assignments" => []
        }
      ]

      node = make_node(responses)
      connections = [make_connection(1, "r1", 2)]

      {:ok, new_state} = DialogueEvaluator.evaluate(node, state, connections)

      assert new_state.variables["mc.jaime.health"].value == 50
    end
  end
end
