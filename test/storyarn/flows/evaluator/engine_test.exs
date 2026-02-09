defmodule Storyarn.Flows.Evaluator.EngineTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Evaluator.Engine

  # =============================================================================
  # Test helpers
  # =============================================================================

  defp var(value, block_type, opts \\ []) do
    %{
      value: value,
      initial_value: value,
      previous_value: value,
      source: :initial,
      block_type: block_type,
      block_id: Keyword.get(opts, :block_id, 1),
      sheet_shortcut: Keyword.get(opts, :sheet, "test"),
      variable_name: Keyword.get(opts, :name, "var")
    }
  end

  defp node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  defp conn(source_id, source_pin, target_id, target_pin \\ "input") do
    %{
      source_node_id: source_id,
      source_pin: source_pin,
      target_node_id: target_id,
      target_pin: target_pin
    }
  end

  defp console_messages(state) do
    Enum.map(state.console, & &1.message)
  end

  # =============================================================================
  # init/2
  # =============================================================================

  describe "init/2" do
    test "creates initial state" do
      vars = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(vars, 1)

      assert state.current_node_id == 1
      assert state.start_node_id == 1
      assert state.status == :paused
      assert state.variables == vars
      assert state.initial_variables == vars
      assert state.execution_path == [1]
      assert state.step_count == 0
      assert state.snapshots == []
      assert length(state.console) == 1
      assert hd(state.console).message == "Debug session started"
    end
  end

  # =============================================================================
  # Linear flow: entry → exit
  # =============================================================================

  describe "simple linear flow" do
    setup do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "exit")
      }

      connections = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state: state, nodes: nodes, connections: connections}
    end

    test "step through entry → exit", %{state: state, nodes: nodes, connections: conns} do
      # Step 1: evaluate entry node → moves to exit
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 2
      assert state.execution_path == [1, 2]

      # Step 2: evaluate exit node → finished
      {:finished, state} = Engine.step(state, nodes, conns)
      assert state.status == :finished
      assert "Execution finished" in console_messages(state)
    end

    test "stepping a finished state returns finished", %{
      state: state,
      nodes: nodes,
      connections: conns
    } do
      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)
      {:finished, _state} = Engine.step(state, nodes, conns)
    end
  end

  # =============================================================================
  # Entry with no connection
  # =============================================================================

  describe "entry with no connection" do
    test "ends with error" do
      nodes = %{1 => node(1, "entry")}
      state = Engine.init(%{}, 1)

      {:finished, state} = Engine.step(state, nodes, [])
      assert state.status == :finished
      assert Enum.any?(state.console, &(&1.message =~ "No outgoing connection"))
    end
  end

  # =============================================================================
  # Hub pass-through
  # =============================================================================

  describe "hub node" do
    test "passes through to next node" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub", %{"hub_id" => "hub_1", "color" => "red"}),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 2

      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3

      {:finished, _state} = Engine.step(state, nodes, conns)
    end
  end

  # =============================================================================
  # Scene pass-through
  # =============================================================================

  describe "scene node" do
    test "passes through to next node" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "scene"),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3
    end
  end

  # =============================================================================
  # Jump node → target hub (same flow)
  # =============================================================================

  describe "jump node" do
    test "jumps to target hub within same flow" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "jump", %{"target_hub_id" => "h1"}),
        3 => node(3, "hub", %{"hub_id" => "h1"}),
        4 => node(4, "exit")
      }

      conns = [conn(1, "default", 2), conn(3, "default", 4)]
      state = Engine.init(%{}, 1)

      # entry → jump
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 2

      # jump → hub (via target_hub_id lookup)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3
      assert Enum.any?(state.console, &(&1.message =~ "Jump → hub \"h1\""))

      # hub → exit
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 4

      # exit → finished
      {:finished, _state} = Engine.step(state, nodes, conns)
    end

    test "finishes with error when target_hub_id is missing" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "jump", %{})
      }

      conns = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)
      assert state.status == :finished
      assert Enum.any?(state.console, &(&1.message =~ "no target_hub_id"))
    end

    test "finishes with error when target hub not found" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "jump", %{"target_hub_id" => "nonexistent"})
      }

      conns = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)
      assert state.status == :finished
      assert Enum.any?(state.console, &(&1.message =~ "not found in this flow"))
    end
  end

  # =============================================================================
  # Subflow node — ends execution (Phase 1)
  # =============================================================================

  describe "subflow node" do
    test "ends execution with info" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow")
      }

      conns = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)
      assert Enum.any?(state.console, &(&1.message =~ "Subflow"))
    end
  end

  # =============================================================================
  # Dialogue — no responses
  # =============================================================================

  describe "dialogue without responses" do
    test "follows output connection" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "dialogue", %{"text" => "<p>Hello there</p>", "responses" => []}),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 2

      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3
      assert Enum.any?(state.console, &(&1.message =~ "no responses"))
    end
  end

  # =============================================================================
  # Dialogue — with responses
  # =============================================================================

  describe "dialogue with responses" do
    setup do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "What do you want?",
            "responses" => [
              %{"id" => "r1", "text" => "Fight", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "Flee", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "exit"),
        4 => node(4, "exit")
      }

      conns = [
        conn(1, "default", 2),
        conn(2, "r1", 3),
        conn(2, "r2", 4)
      ]

      state = Engine.init(%{}, 1)

      {:ok, state: state, nodes: nodes, connections: conns}
    end

    test "presents choices and waits", %{state: state, nodes: nodes, connections: conns} do
      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      assert state.status == :waiting_input
      refute is_nil(state.pending_choices)
      assert length(state.pending_choices.responses) == 2
      assert Enum.all?(state.pending_choices.responses, & &1.valid)
    end

    test "stepping while waiting returns waiting_input", %{
      state: state,
      nodes: nodes,
      connections: conns
    } do
      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)
      {:waiting_input, _state} = Engine.step(state, nodes, conns)
    end

    test "choose_response advances to next node", %{
      state: state,
      nodes: nodes,
      connections: conns
    } do
      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      {:ok, state} = Engine.choose_response(state, "r1", conns)
      assert state.current_node_id == 3
      assert state.status == :paused

      {:finished, _state} = Engine.step(state, nodes, conns)
    end

    test "choose_response with resp_ prefix pin", ctx do
      # Some flows might use "resp_r1" as pin name
      conns = [
        conn(1, "default", 2),
        conn(2, "resp_r1", 3),
        conn(2, "resp_r2", 4)
      ]

      {:ok, state} = Engine.step(ctx.state, ctx.nodes, conns)
      {:waiting_input, state} = Engine.step(state, ctx.nodes, conns)

      {:ok, state} = Engine.choose_response(state, "r1", conns)
      assert state.current_node_id == 3
    end

    test "choose_response with no connection ends execution", %{
      state: state,
      nodes: nodes,
      connections: conns
    } do
      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      {:error, state, :no_connection} = Engine.choose_response(state, "nonexistent", conns)
      assert state.status == :finished
    end

    test "choose_response when not waiting returns error", %{state: state, connections: conns} do
      {:error, _state, :not_waiting_input} = Engine.choose_response(state, "r1", conns)
    end
  end

  # =============================================================================
  # Dialogue — response conditions
  # =============================================================================

  describe "dialogue response conditions" do
    test "evaluates response conditions and reports validity" do
      condition_json =
        Jason.encode!(%{
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule1",
              "sheet" => "mc.jaime",
              "variable" => "health",
              "operator" => "greater_than",
              "value" => "50"
            }
          ]
        })

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Strong choice", "condition" => condition_json, "instruction" => ""},
              %{"id" => "r2", "text" => "Always available", "condition" => "", "instruction" => ""}
            ]
          })
      }

      conns = [conn(1, "default", 2)]
      variables = %{"mc.jaime.health" => var(80, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      responses = state.pending_choices.responses
      assert Enum.find(responses, &(&1.id == "r1")).valid == true
      assert Enum.find(responses, &(&1.id == "r2")).valid == true
    end

    test "marks response as invalid when condition fails" do
      condition_json =
        Jason.encode!(%{
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule1",
              "sheet" => "mc.jaime",
              "variable" => "health",
              "operator" => "greater_than",
              "value" => "100"
            }
          ]
        })

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Needs 100+ health", "condition" => condition_json, "instruction" => ""},
              %{"id" => "r2", "text" => "Always available", "condition" => "", "instruction" => ""},
              %{"id" => "r3", "text" => "Also available", "condition" => "", "instruction" => ""}
            ]
          })
      }

      conns = [conn(1, "default", 2)]
      variables = %{"mc.jaime.health" => var(80, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      responses = state.pending_choices.responses
      assert Enum.find(responses, &(&1.id == "r1")).valid == false
      assert Enum.find(responses, &(&1.id == "r2")).valid == true
    end
  end

  # =============================================================================
  # Dialogue — response instruction execution
  # =============================================================================

  describe "dialogue response instruction" do
    test "executes instruction on response selection" do
      instruction_json =
        Jason.encode!([
          %{
            "id" => "a1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "subtract",
            "value" => "10",
            "value_type" => "literal",
            "value_sheet" => nil
          }
        ])

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Take damage", "condition" => "", "instruction" => instruction_json},
              %{"id" => "r2", "text" => "No damage", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "r1", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.choose_response(state, "r1", conns)

      # 100 - 10 = 90 (response instruction subtracts 10)
      assert state.variables["mc.jaime.health"].value == 90.0
    end

    test "auto-selects and executes instruction for single valid response" do
      instruction_json =
        Jason.encode!([
          %{
            "id" => "a1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "subtract",
            "value" => "10",
            "value_type" => "literal",
            "value_sheet" => nil
          }
        ])

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Take damage", "condition" => "", "instruction" => instruction_json}
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "r1", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      # Single response auto-selected — goes directly to :ok, no waiting_input
      {:ok, state} = Engine.step(state, nodes, conns)

      assert state.variables["mc.jaime.health"].value == 90.0
      assert state.current_node_id == 3
    end
  end

  # =============================================================================
  # Dialogue — input_condition and output_instruction
  # =============================================================================

  describe "dialogue input_condition" do
    test "logs warning when input condition fails" do
      condition_json =
        Jason.encode!(%{
          "logic" => "all",
          "rules" => [
            %{
              "id" => "rule1",
              "sheet" => "mc.jaime",
              "variable" => "health",
              "operator" => "greater_than",
              "value" => "200"
            }
          ]
        })

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Guarded dialogue",
            "input_condition" => condition_json,
            "responses" => []
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(80, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      assert Enum.any?(state.console, &(&1.message =~ "Input condition failed"))
    end
  end

  describe "dialogue output_instruction" do
    test "executes output instruction and mutates variables" do
      instruction_json =
        Jason.encode!([
          %{
            "id" => "a1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "subtract",
            "value" => "20",
            "value_type" => "literal",
            "value_sheet" => nil
          }
        ])

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "With instruction",
            "output_instruction" => instruction_json,
            "responses" => []
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      assert state.variables["mc.jaime.health"].value == 80.0
      assert Enum.any?(state.console, &(&1.message =~ "Output instruction"))
    end
  end

  # =============================================================================
  # Condition node — boolean mode
  # =============================================================================

  describe "condition node (boolean)" do
    setup do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "rule1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "condition", %{"condition" => condition, "switch_mode" => false}),
        3 => node(3, "exit"),
        4 => node(4, "exit")
      }

      conns = [
        conn(1, "default", 2),
        conn(2, "true", 3),
        conn(2, "false", 4)
      ]

      {:ok, nodes: nodes, connections: conns}
    end

    test "follows true branch when condition passes", %{nodes: nodes, connections: conns} do
      state = Engine.init(%{"mc.jaime.health" => var(80, "number")}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3
      assert Enum.any?(state.console, &(&1.message =~ "Condition → true"))
    end

    test "follows false branch when condition fails", %{nodes: nodes, connections: conns} do
      state = Engine.init(%{"mc.jaime.health" => var(30, "number")}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 4
      assert Enum.any?(state.console, &(&1.message =~ "Condition → false"))
    end

    test "logs rule details", %{nodes: nodes, connections: conns} do
      state = Engine.init(%{"mc.jaime.health" => var(80, "number")}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      condition_entry = Enum.find(state.console, &(&1.message =~ "Condition →"))
      assert condition_entry.rule_details != nil
      assert length(condition_entry.rule_details) == 1
      assert hd(condition_entry.rule_details).passed == true
    end

    test "ends when no matching pin connection" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "condition", %{
            "condition" => %{"logic" => "all", "rules" => []},
            "switch_mode" => false
          })
      }

      # No "true" connection
      conns = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)
      assert Enum.any?(state.console, &(&1.message =~ "No connection from pin"))
    end
  end

  # =============================================================================
  # Condition node — switch mode
  # =============================================================================

  describe "condition node (switch)" do
    test "follows first matching case" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "case_1",
            "label" => "Warrior",
            "sheet" => "mc.jaime",
            "variable" => "class",
            "operator" => "equals",
            "value" => "warrior"
          },
          %{
            "id" => "case_2",
            "label" => "Mage",
            "sheet" => "mc.jaime",
            "variable" => "class",
            "operator" => "equals",
            "value" => "mage"
          }
        ]
      }

      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "condition", %{"condition" => condition, "switch_mode" => true}),
        3 => node(3, "exit"),
        4 => node(4, "exit"),
        5 => node(5, "exit")
      }

      conns = [
        conn(1, "default", 2),
        conn(2, "case_1", 3),
        conn(2, "case_2", 4),
        conn(2, "default", 5)
      ]

      state = Engine.init(%{"mc.jaime.class" => var("warrior", "select")}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3
    end

    test "follows default when no case matches" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "case_1",
            "label" => "Warrior",
            "sheet" => "mc.jaime",
            "variable" => "class",
            "operator" => "equals",
            "value" => "warrior"
          }
        ]
      }

      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "condition", %{"condition" => condition, "switch_mode" => true}),
        3 => node(3, "exit"),
        4 => node(4, "exit")
      }

      conns = [
        conn(1, "default", 2),
        conn(2, "case_1", 3),
        conn(2, "default", 4)
      ]

      state = Engine.init(%{"mc.jaime.class" => var("thief", "select")}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 4
      assert Enum.any?(state.console, &(&1.message =~ "no case matched"))
    end
  end

  # =============================================================================
  # Instruction node
  # =============================================================================

  describe "instruction node" do
    test "executes assignments and follows output" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "30",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      assert state.variables["mc.jaime.health"].value == 70.0
      assert state.current_node_id == 3
      assert Enum.any?(state.console, &(&1.message =~ "100 → 70.0"))
    end

    test "with no assignments logs info" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "instruction", %{"assignments" => []}),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert Enum.any?(state.console, &(&1.message =~ "no assignments"))
    end
  end

  # =============================================================================
  # Step back (undo)
  # =============================================================================

  describe "step_back/1" do
    test "restores previous state" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "30",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      # Step to instruction
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 2

      # Step through instruction (mutates variable)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.variables["mc.jaime.health"].value == 70.0
      assert state.current_node_id == 3

      # Step back — should restore to before instruction executed
      {:ok, state} = Engine.step_back(state)
      assert state.current_node_id == 2
      assert state.variables["mc.jaime.health"].value == 100
    end

    test "multiple step backs" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 3

      {:ok, state} = Engine.step_back(state)
      assert state.current_node_id == 2

      {:ok, state} = Engine.step_back(state)
      assert state.current_node_id == 1
    end

    test "step back with no history returns error" do
      state = Engine.init(%{}, 1)
      {:error, :no_history} = Engine.step_back(state)
    end

    test "step back from waiting_input restores dialogue" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Option A", "condition" => "", "instruction" => ""},
              %{"id" => "r2", "text" => "Option B", "condition" => "", "instruction" => ""}
            ]
          })
      }

      conns = [conn(1, "default", 2)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)
      assert state.status == :waiting_input

      {:ok, state} = Engine.step_back(state)
      # Restored to before dialogue was evaluated
      assert state.current_node_id == 2
      assert state.status == :paused
      assert state.pending_choices == nil
    end
  end

  # =============================================================================
  # Reset
  # =============================================================================

  describe "reset/1" do
    test "restores to initial state" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "0",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.variables["mc.jaime.health"].value == 0.0

      state = Engine.reset(state)
      assert state.current_node_id == 1
      assert state.variables["mc.jaime.health"].value == 100
      assert state.step_count == 0
      assert state.snapshots == []
      assert state.execution_path == [1]
    end
  end

  # =============================================================================
  # Breakpoints
  # =============================================================================

  describe "breakpoints" do
    test "toggle_breakpoint adds a breakpoint" do
      state = Engine.init(%{}, 1)
      state = Engine.toggle_breakpoint(state, 5)

      assert Engine.has_breakpoint?(state, 5)
      assert MapSet.size(state.breakpoints) == 1
    end

    test "toggle_breakpoint removes an existing breakpoint" do
      state = Engine.init(%{}, 1)
      state = Engine.toggle_breakpoint(state, 5)
      state = Engine.toggle_breakpoint(state, 5)

      refute Engine.has_breakpoint?(state, 5)
      assert MapSet.size(state.breakpoints) == 0
    end

    test "has_breakpoint? returns false for non-breakpoint node" do
      state = Engine.init(%{}, 1)
      refute Engine.has_breakpoint?(state, 99)
    end

    test "at_breakpoint? checks current_node_id against breakpoints" do
      state = Engine.init(%{}, 1)
      state = Engine.toggle_breakpoint(state, 1)

      assert Engine.at_breakpoint?(state)

      state = Engine.toggle_breakpoint(state, 1)
      refute Engine.at_breakpoint?(state)
    end

    test "reset preserves breakpoints" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)
      state = Engine.toggle_breakpoint(state, 3)
      state = Engine.toggle_breakpoint(state, 7)

      state = Engine.reset(state)

      assert Engine.has_breakpoint?(state, 3)
      assert Engine.has_breakpoint?(state, 7)
      assert state.current_node_id == 1
      assert state.step_count == 0
    end
  end

  # =============================================================================
  # Max steps (infinite loop protection)
  # =============================================================================

  describe "max steps" do
    test "stops after max_steps" do
      nodes = %{
        1 => node(1, "hub"),
        2 => node(2, "hub")
      }

      # Circular: 1 → 2 → 1
      conns = [conn(1, "default", 2), conn(2, "default", 1)]
      state = Engine.init(%{}, 1)
      state = %{state | max_steps: 5}

      # Step until max
      {result, state} =
        Enum.reduce_while(1..10, {:ok, state}, fn _i, {_status, s} ->
          case Engine.step(s, nodes, conns) do
            {:ok, new_s} -> {:cont, {:ok, new_s}}
            {:error, new_s, :max_steps} -> {:halt, {:max_steps, new_s}}
            other -> {:halt, other}
          end
        end)

      assert result == :max_steps
      assert state.status == :finished
      assert Enum.any?(state.console, &(&1.message =~ "Max steps"))
    end
  end

  # =============================================================================
  # Missing node
  # =============================================================================

  describe "missing node" do
    test "returns error when current node not found" do
      state = Engine.init(%{}, 999)
      {:error, state, :node_not_found} = Engine.step(state, %{}, [])
      assert state.status == :finished
    end
  end

  # =============================================================================
  # Execution path tracking
  # =============================================================================

  describe "execution path" do
    test "tracks all visited nodes" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3), conn(3, "default", 4)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)

      assert state.execution_path == [1, 2, 3, 4]
    end
  end

  # =============================================================================
  # Full flow integration
  # =============================================================================

  describe "full flow: entry → instruction → condition → dialogue → exit" do
    test "complete flow with variable mutations and branching" do
      condition = %{
        "logic" => "all",
        "rules" => [
          %{
            "id" => "rule1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "greater_than",
            "value" => "50"
          }
        ]
      }

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "20",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "condition", %{"condition" => condition, "switch_mode" => false}),
        4 =>
          node(4, "dialogue", %{
            "text" => "You survived!",
            "responses" => [
              %{"id" => "r1", "text" => "Continue", "condition" => "", "instruction" => ""}
            ]
          }),
        5 => node(5, "exit"),
        6 => node(6, "exit")
      }

      conns = [
        conn(1, "default", 2),
        conn(2, "default", 3),
        conn(3, "true", 4),
        conn(3, "false", 6),
        conn(4, "r1", 5)
      ]

      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      # Entry → instruction
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 2

      # Instruction: health 100 → 80
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.variables["mc.jaime.health"].value == 80.0
      assert state.current_node_id == 3

      # Condition: 80 > 50 → true
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 4

      # Dialogue: single response auto-selected, advances to exit
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.current_node_id == 5

      # Exit
      {:finished, state} = Engine.step(state, nodes, conns)
      assert state.execution_path == [1, 2, 3, 4, 5]
    end
  end

  # =============================================================================
  # History tracking
  # =============================================================================

  describe "history" do
    test "instruction node populates history entries" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "30",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      assert state.history == []

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      assert length(state.history) == 1
      [entry] = state.history
      assert entry.variable_ref == "mc.jaime.health"
      assert entry.old_value == 100
      assert entry.new_value == 70.0
      assert entry.source == :instruction
      assert entry.node_id == 2
      assert is_integer(entry.ts)
    end

    test "multiple assignments create multiple history entries" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "10",
                "value_type" => "literal",
                "value_sheet" => nil
              },
              %{
                "id" => "a2",
                "sheet" => "world",
                "variable" => "quest_started",
                "operator" => "set_true",
                "value" => "",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]

      variables = %{
        "mc.jaime.health" => var(100, "number"),
        "world.quest_started" => var(false, "boolean")
      }

      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      assert length(state.history) == 2
      refs = Enum.map(state.history, & &1.variable_ref)
      assert "mc.jaime.health" in refs
      assert "world.quest_started" in refs
    end

    test "dialogue output_instruction populates history" do
      instruction_json =
        Jason.encode!([
          %{
            "id" => "a1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "subtract",
            "value" => "20",
            "value_type" => "literal",
            "value_sheet" => nil
          }
        ])

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "With output instruction",
            "output_instruction" => instruction_json,
            "responses" => []
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)

      assert length(state.history) == 1
      [entry] = state.history
      assert entry.variable_ref == "mc.jaime.health"
      assert entry.old_value == 100
      assert entry.new_value == 80.0
      assert entry.source == :instruction
    end

    test "response instruction populates history" do
      instruction_json =
        Jason.encode!([
          %{
            "id" => "a1",
            "sheet" => "mc.jaime",
            "variable" => "health",
            "operator" => "subtract",
            "value" => "10",
            "value_type" => "literal",
            "value_sheet" => nil
          }
        ])

      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "dialogue", %{
            "text" => "Choose",
            "responses" => [
              %{"id" => "r1", "text" => "Damage", "condition" => "", "instruction" => instruction_json},
              %{"id" => "r2", "text" => "No damage", "condition" => "", "instruction" => ""}
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "r1", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:waiting_input, state} = Engine.step(state, nodes, conns)

      assert state.history == []

      {:ok, state} = Engine.choose_response(state, "r1", conns)

      assert length(state.history) == 1
      [entry] = state.history
      assert entry.variable_ref == "mc.jaime.health"
      assert entry.new_value == 90.0
      assert entry.source == :instruction
    end

    test "step_back restores history to previous state" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "subtract",
                "value" => "30",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      # Step through entry
      {:ok, state} = Engine.step(state, nodes, conns)
      assert state.history == []

      # Step through instruction — adds history
      {:ok, state} = Engine.step(state, nodes, conns)
      assert length(state.history) == 1

      # Step back — restores history to before instruction
      {:ok, state} = Engine.step_back(state)
      assert state.history == []
    end

    test "reset clears history" do
      nodes = %{
        1 => node(1, "entry"),
        2 =>
          node(2, "instruction", %{
            "assignments" => [
              %{
                "id" => "a1",
                "sheet" => "mc.jaime",
                "variable" => "health",
                "operator" => "set",
                "value" => "50",
                "value_type" => "literal",
                "value_sheet" => nil
              }
            ]
          }),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      assert length(state.history) == 1

      state = Engine.reset(state)
      assert state.history == []
    end

    test "nodes without mutations produce no history" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      conns = [conn(1, "default", 2), conn(2, "default", 3)]
      state = Engine.init(%{}, 1)

      {:ok, state} = Engine.step(state, nodes, conns)
      {:ok, state} = Engine.step(state, nodes, conns)
      {:finished, state} = Engine.step(state, nodes, conns)

      assert state.history == []
    end
  end

  # =============================================================================
  # set_variable/3
  # =============================================================================

  describe "set_variable/3" do
    test "updates variable value and sets source to :user_override" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.set_variable(state, "mc.jaime.health", 75)

      assert state.variables["mc.jaime.health"].value == 75
      assert state.variables["mc.jaime.health"].source == :user_override
      assert state.variables["mc.jaime.health"].previous_value == 100
    end

    test "adds console entry for user override" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.set_variable(state, "mc.jaime.health", 75)

      messages = console_messages(state)
      assert Enum.any?(messages, &String.contains?(&1, "User override"))
      assert Enum.any?(messages, &String.contains?(&1, "mc.jaime.health"))
    end

    test "adds history entry with source :user_override" do
      variables = %{"mc.jaime.health" => var(100, "number")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.set_variable(state, "mc.jaime.health", 75)

      assert length(state.history) == 1
      [entry] = state.history
      assert entry.variable_ref == "mc.jaime.health"
      assert entry.old_value == 100
      assert entry.new_value == 75
      assert entry.source == :user_override
    end

    test "returns error for unknown variable" do
      state = Engine.init(%{}, 1)

      assert {:error, :not_found} = Engine.set_variable(state, "unknown.var", 42)
    end

    test "preserves other variable fields" do
      variables = %{"mc.jaime.health" => var(100, "number", sheet: "mc.jaime", name: "health")}
      state = Engine.init(variables, 1)

      {:ok, state} = Engine.set_variable(state, "mc.jaime.health", 50)

      var = state.variables["mc.jaime.health"]
      assert var.block_type == "number"
      assert var.sheet_shortcut == "mc.jaime"
      assert var.variable_name == "health"
      assert var.initial_value == 100
    end
  end
end
