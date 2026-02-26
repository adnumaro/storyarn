defmodule Storyarn.Flows.Evaluator.NodeEvaluators.ConditionNodeEvaluatorTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.NodeEvaluators.ConditionNodeEvaluator
  alias Storyarn.Flows.Evaluator.State

  # =============================================================================
  # Helpers
  # =============================================================================

  defp make_state(variables \\ %{}) do
    %State{
      current_node_id: 1,
      status: :paused,
      variables: variables,
      console: [],
      execution_path: [1],
      execution_log: [],
      call_stack: []
    }
  end

  defp make_variable(value, opts \\ []) do
    %{
      value: value,
      initial_value: value,
      previous_value: nil,
      source: :initial,
      block_type: Keyword.get(opts, :type, "number"),
      block_id: 1,
      sheet_shortcut: Keyword.get(opts, :sheet, "mc"),
      variable_name: Keyword.get(opts, :name, "health"),
      constraints: nil
    }
  end

  defp make_node(id, data) do
    %{id: id, type: "condition", data: data}
  end

  defp make_connection(source_id, source_pin, target_id) do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id
    }
  end

  # =============================================================================
  # Boolean mode
  # =============================================================================

  describe "evaluate/3 boolean mode" do
    test "follows true branch when condition is true" do
      variables = %{
        "mc.health" => make_variable(100)
      }

      node =
        make_node(1, %{
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "r1",
                "sheet" => "mc",
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "50"
              }
            ]
          }
        })

      connections = [
        make_connection(1, "true", 10),
        make_connection(1, "false", 20)
      ]

      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 10
    end

    test "follows false branch when condition is false" do
      variables = %{
        "mc.health" => make_variable(30)
      }

      node =
        make_node(1, %{
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "r1",
                "sheet" => "mc",
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "50"
              }
            ]
          }
        })

      connections = [
        make_connection(1, "true", 10),
        make_connection(1, "false", 20)
      ]

      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 20
    end

    test "finishes when no connection for branch" do
      variables = %{
        "mc.health" => make_variable(30)
      }

      node =
        make_node(1, %{
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "r1",
                "sheet" => "mc",
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "50"
              }
            ]
          }
        })

      # Condition evaluates to false but there's no "false" connection
      connections = [make_connection(1, "true", 10)]
      state = make_state(variables)

      assert {:finished, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.status == :finished
      # Should have an error console entry about missing pin
      assert Enum.any?(result_state.console, fn entry ->
               entry.level == :error and String.contains?(entry.message, "No connection from pin")
             end)
    end

    test "adds console messages with condition result" do
      variables = %{
        "mc.health" => make_variable(100)
      }

      node =
        make_node(1, %{
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "r1",
                "sheet" => "mc",
                "variable" => "health",
                "operator" => "greater_than",
                "value" => "50"
              }
            ]
          }
        })

      connections = [make_connection(1, "true", 10)]
      state = make_state(variables)

      {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert length(result_state.console) > 0

      console_msg = hd(result_state.console)
      assert console_msg.message =~ "Condition"
    end

    test "handles nil data gracefully" do
      node = %{id: 1, type: "condition", data: nil}
      # Empty condition evaluates to true (all rules pass vacuously)
      connections = [make_connection(1, "true", 10), make_connection(1, "false", 20)]
      state = make_state()

      assert {status, _state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert status in [:ok, :finished]
    end
  end

  # =============================================================================
  # Switch mode (rules)
  # =============================================================================

  describe "evaluate/3 switch mode with rules" do
    test "follows first matching rule pin" do
      variables = %{
        "mc.class" => make_variable("warrior", type: "select", name: "class")
      }

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "case_mage",
                "sheet" => "mc",
                "variable" => "class",
                "operator" => "equals",
                "value" => "mage",
                "label" => "Mage"
              },
              %{
                "id" => "case_warrior",
                "sheet" => "mc",
                "variable" => "class",
                "operator" => "equals",
                "value" => "warrior",
                "label" => "Warrior"
              }
            ]
          }
        })

      connections = [
        make_connection(1, "case_mage", 10),
        make_connection(1, "case_warrior", 20),
        make_connection(1, "default", 30)
      ]

      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 20
    end

    test "follows default when no rule matches" do
      variables = %{
        "mc.class" => make_variable("rogue", type: "select", name: "class")
      }

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "case_mage",
                "sheet" => "mc",
                "variable" => "class",
                "operator" => "equals",
                "value" => "mage",
                "label" => "Mage"
              }
            ]
          }
        })

      connections = [
        make_connection(1, "case_mage", 10),
        make_connection(1, "default", 30)
      ]

      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 30

      # Should have a warning about default
      assert Enum.any?(result_state.console, fn entry ->
               entry.level == :warning and String.contains?(entry.message, "no case matched")
             end)
    end

    test "finishes when no matching pin and no default" do
      variables = %{
        "mc.class" => make_variable("rogue", type: "select", name: "class")
      }

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "rules" => [
              %{
                "id" => "case_mage",
                "sheet" => "mc",
                "variable" => "class",
                "operator" => "equals",
                "value" => "mage"
              }
            ]
          }
        })

      connections = [make_connection(1, "case_mage", 10)]
      state = make_state(variables)

      assert {:finished, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.status == :finished
    end
  end

  # =============================================================================
  # Switch mode (blocks)
  # =============================================================================

  describe "evaluate/3 switch mode with blocks" do
    test "follows first matching block pin" do
      variables = %{
        "mc.health" => make_variable(80)
      }

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "blocks" => [
              %{
                "id" => "block_low",
                "type" => "block",
                "logic" => "all",
                "label" => "Low HP",
                "rules" => [
                  %{
                    "id" => "r1",
                    "sheet" => "mc",
                    "variable" => "health",
                    "operator" => "less_than",
                    "value" => "50"
                  }
                ]
              },
              %{
                "id" => "block_high",
                "type" => "block",
                "logic" => "all",
                "label" => "High HP",
                "rules" => [
                  %{
                    "id" => "r2",
                    "sheet" => "mc",
                    "variable" => "health",
                    "operator" => "greater_than",
                    "value" => "60"
                  }
                ]
              }
            ]
          }
        })

      connections = [
        make_connection(1, "block_low", 10),
        make_connection(1, "block_high", 20),
        make_connection(1, "default", 30)
      ]

      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 20
    end

    test "follows default when no block matches" do
      variables = %{
        "mc.health" => make_variable(55)
      }

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "blocks" => [
              %{
                "id" => "block_low",
                "type" => "block",
                "logic" => "all",
                "label" => "Low HP",
                "rules" => [
                  %{
                    "id" => "r1",
                    "sheet" => "mc",
                    "variable" => "health",
                    "operator" => "less_than",
                    "value" => "50"
                  }
                ]
              },
              %{
                "id" => "block_high",
                "type" => "block",
                "logic" => "all",
                "label" => "High HP",
                "rules" => [
                  %{
                    "id" => "r2",
                    "sheet" => "mc",
                    "variable" => "health",
                    "operator" => "greater_than",
                    "value" => "60"
                  }
                ]
              }
            ]
          }
        })

      connections = [
        make_connection(1, "block_low", 10),
        make_connection(1, "block_high", 20),
        make_connection(1, "default", 30)
      ]

      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 30
    end

    test "falls back to default connection when specific pin not connected" do
      variables = %{
        "mc.health" => make_variable(80)
      }

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "blocks" => [
              %{
                "id" => "block_high",
                "type" => "block",
                "logic" => "all",
                "label" => "High HP",
                "rules" => [
                  %{
                    "id" => "r1",
                    "sheet" => "mc",
                    "variable" => "health",
                    "operator" => "greater_than",
                    "value" => "50"
                  }
                ]
              }
            ]
          }
        })

      # No connection for "block_high" pin, but there's a "default" fallback
      connections = [make_connection(1, "default", 30)]
      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 30
    end

    test "skips non-block entries in blocks list" do
      variables = %{}

      node =
        make_node(1, %{
          "switch_mode" => true,
          "condition" => %{
            "logic" => "all",
            "blocks" => [
              %{"type" => "invalid", "rules" => []}
            ]
          }
        })

      connections = [make_connection(1, "default", 30)]
      state = make_state(variables)

      assert {:ok, result_state} = ConditionNodeEvaluator.evaluate(node, state, connections)
      assert result_state.current_node_id == 30
    end
  end
end
