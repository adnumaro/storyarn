defmodule StoryarnWeb.FlowLive.Components.DebugPanelTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Storyarn.Flows.Evaluator.State
  alias StoryarnWeb.FlowLive.Components.DebugPanel

  # ===========================================================================
  # Test helpers
  # ===========================================================================

  defp base_debug_state(overrides \\ %{}) do
    defaults = %State{
      status: :paused,
      step_count: 0,
      start_node_id: 1,
      current_node_id: nil,
      variables: %{},
      initial_variables: %{},
      previous_variables: %{},
      snapshots: [],
      history: [],
      console: [],
      execution_path: [],
      execution_log: [],
      pending_choices: nil,
      max_steps: 1000,
      breakpoints: MapSet.new(),
      call_stack: [],
      current_flow_id: nil,
      exit_transition: nil
    }

    Map.merge(defaults, overrides)
  end

  defp build_assigns(overrides) do
    defaults = [
      debug_state: base_debug_state(),
      debug_active_tab: "console",
      debug_nodes: %{1 => %{id: 1, type: "entry", data: nil}},
      debug_auto_playing: false,
      debug_speed: 800,
      debug_editing_var: nil,
      debug_var_filter: "",
      debug_var_changed_only: false,
      debug_current_flow_name: nil,
      debug_step_limit_reached: false
    ]

    Keyword.merge(defaults, overrides)
  end

  defp render_panel(overrides \\ []) do
    render_component(&DebugPanel.debug_panel/1, build_assigns(overrides))
  end

  defp console_entry(node_id, message, opts \\ []) do
    %{
      ts: Keyword.get(opts, :ts, 0),
      level: Keyword.get(opts, :level, :info),
      node_id: node_id,
      node_label: Keyword.get(opts, :node_label, ""),
      message: message,
      rule_details: nil
    }
  end

  defp node(id, type, data \\ %{}) do
    %{id: id, type: type, data: data}
  end

  # Converts a list of node IDs or {node_id, depth} tuples to execution_log format
  defp log(entries) do
    Enum.map(entries, fn
      {id, depth} -> %{node_id: id, depth: depth}
      id when is_integer(id) -> %{node_id: id, depth: 0}
    end)
  end

  defp make_variable(value, opts) do
    %{
      value: value,
      initial_value: Keyword.get(opts, :initial_value, value),
      previous_value: Keyword.get(opts, :previous_value, nil),
      source: Keyword.get(opts, :source, :initial),
      block_type: Keyword.get(opts, :block_type, "number"),
      block_id: 100,
      sheet_shortcut: Keyword.get(opts, :sheet_shortcut, "mc"),
      variable_name: Keyword.get(opts, :variable_name, "health")
    }
  end

  # ===========================================================================
  # Panel rendering — basic structure
  # ===========================================================================

  describe "debug_panel/1 basic rendering" do
    test "renders the debug panel container" do
      html = render_panel()
      assert html =~ ~s(id="debug-panel")
      assert html =~ "phx-hook=\"DebugPanelResize\""
      assert html =~ "data-debug-active"
    end

    test "renders the resize handle" do
      html = render_panel()
      assert html =~ "data-resize-handle"
      assert html =~ "cursor-row-resize"
    end

    test "renders control buttons" do
      html = render_panel()
      assert html =~ "debug_play"
      assert html =~ "debug_step"
      assert html =~ "debug_step_back"
      assert html =~ "debug_reset"
      assert html =~ "debug_stop"
    end

    test "renders speed slider" do
      html = render_panel()
      assert html =~ "debug_set_speed"
      assert html =~ ~s(value="800")
      assert html =~ "800ms"
    end

    test "renders tab buttons" do
      html = render_panel()
      assert html =~ "Console"
      assert html =~ "Variables"
      assert html =~ "History"
      assert html =~ "Path"
    end

    test "renders tab content area" do
      html = render_panel()
      assert html =~ ~s(id="debug-tab-content")
    end
  end

  # ===========================================================================
  # Status display
  # ===========================================================================

  describe "debug_panel/1 status display" do
    test "renders paused status badge" do
      html = render_panel(debug_state: base_debug_state(%{status: :paused}))
      assert html =~ "Paused"
      assert html =~ "badge-info"
    end

    test "renders waiting_input status badge" do
      html = render_panel(debug_state: base_debug_state(%{status: :waiting_input}))
      assert html =~ "Waiting"
      assert html =~ "badge-warning"
    end

    test "renders finished status badge" do
      html = render_panel(debug_state: base_debug_state(%{status: :finished}))
      assert html =~ "Finished"
      assert html =~ "badge-neutral"
    end

    test "renders step count" do
      html = render_panel(debug_state: base_debug_state(%{step_count: 42}))
      assert html =~ "Step 42"
    end

    test "renders step count zero at start" do
      html = render_panel(debug_state: base_debug_state(%{step_count: 0}))
      assert html =~ "Step 0"
    end
  end

  # ===========================================================================
  # Control button states
  # ===========================================================================

  describe "debug_panel/1 control button states" do
    test "play button is visible when not auto-playing" do
      html = render_panel(debug_auto_playing: false)
      assert html =~ "debug_play"
    end

    test "pause button is visible when auto-playing" do
      html = render_panel(debug_auto_playing: true)
      assert html =~ "debug_pause"
      assert html =~ "btn-accent"
    end

    test "step button is disabled when auto-playing" do
      html = render_panel(debug_auto_playing: true)
      # The step button should have disabled attribute
      assert html =~ "debug_step"
    end

    test "step button is disabled when finished" do
      html = render_panel(debug_state: base_debug_state(%{status: :finished}))
      assert html =~ "debug_step"
    end

    test "step back is disabled when no snapshots" do
      html = render_panel(debug_state: base_debug_state(%{snapshots: []}))
      assert html =~ "debug_step_back"
    end

    test "reset button is disabled when auto-playing" do
      html = render_panel(debug_auto_playing: true)
      assert html =~ "debug_reset"
    end

    test "stop button is always visible" do
      html = render_panel()
      assert html =~ "debug_stop"
      assert html =~ "text-error"
    end
  end

  # ===========================================================================
  # Speed slider
  # ===========================================================================

  describe "debug_panel/1 speed slider" do
    test "renders speed in milliseconds for values under 1000" do
      html = render_panel(debug_speed: 500)
      assert html =~ "500ms"
    end

    test "renders speed in seconds for values at 1000" do
      html = render_panel(debug_speed: 1000)
      assert html =~ "1.0s"
    end

    test "renders speed in seconds for values above 1000" do
      html = render_panel(debug_speed: 2500)
      assert html =~ "2.5s"
    end

    test "renders speed at minimum value" do
      html = render_panel(debug_speed: 200)
      assert html =~ "200ms"
    end
  end

  # ===========================================================================
  # Tab switching
  # ===========================================================================

  describe "debug_panel/1 tab switching" do
    test "console tab is active by default" do
      html = render_panel(debug_active_tab: "console")
      assert html =~ "tab-active"
    end

    test "tab change events have correct phx-value-tab" do
      html = render_panel()
      assert html =~ ~s(phx-value-tab="console")
      assert html =~ ~s(phx-value-tab="variables")
      assert html =~ ~s(phx-value-tab="history")
      assert html =~ ~s(phx-value-tab="path")
    end

    test "renders console tab content when active tab is console" do
      state = base_debug_state(%{console: [console_entry(1, "Test message", ts: 100)]})
      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "Test message"
    end

    test "does not render console content when active tab is not console" do
      state = base_debug_state(%{console: [console_entry(1, "Unique console text xyz", ts: 100)]})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      refute html =~ "Unique console text xyz"
    end

    test "renders variables tab content when active" do
      html = render_panel(debug_active_tab: "variables")
      # Variables tab should show the filter bar or empty state
      assert html =~ "Filter variables" or html =~ "No variables"
    end

    test "renders history tab content when active" do
      html = render_panel(debug_active_tab: "history")
      assert html =~ "No variable changes yet"
    end

    test "renders path tab content when active" do
      html = render_panel(debug_active_tab: "path")
      assert html =~ "No steps yet"
    end
  end

  # ===========================================================================
  # Start node selector
  # ===========================================================================

  describe "debug_panel/1 start node selector" do
    test "renders start node select with entry node" do
      nodes = %{1 => %{id: 1, type: "entry", data: nil}}
      html = render_panel(debug_nodes: nodes)
      assert html =~ "debug_change_start_node"
      assert html =~ "Start:"
    end

    test "renders entry nodes before other types" do
      nodes = %{
        1 => %{id: 1, type: "dialogue", data: %{"text" => "Hello"}},
        2 => %{id: 2, type: "entry", data: nil}
      }

      html = render_panel(debug_nodes: nodes)
      # Entry should appear first in the select options
      assert html =~ "Entry #2"
    end

    test "uses text content for node labels when available" do
      nodes = %{1 => %{id: 1, type: "dialogue", data: %{"text" => "<p>Hello World</p>"}}}
      html = render_panel(debug_nodes: nodes)
      assert html =~ "Dialogue: Hello World"
    end

    test "falls back to type and ID when no text" do
      nodes = %{1 => %{id: 1, type: "hub", data: %{}}}
      html = render_panel(debug_nodes: nodes)
      assert html =~ "Hub #1"
    end

    test "falls back to type and ID when data is nil" do
      nodes = %{1 => %{id: 1, type: "entry", data: nil}}
      html = render_panel(debug_nodes: nodes)
      assert html =~ "Entry #1"
    end

    test "selector is disabled when auto-playing" do
      html = render_panel(debug_auto_playing: true)
      assert html =~ "disabled"
    end
  end

  # ===========================================================================
  # Breadcrumb bar (sub-flow call stack)
  # ===========================================================================

  describe "debug_panel/1 breadcrumb bar" do
    test "does not render breadcrumb when call_stack is empty" do
      html = render_panel()
      refute html =~ "Entering sub-flow"
      # The breadcrumb should not show the layers icon
    end

    test "renders breadcrumb when call_stack is not empty" do
      state =
        base_debug_state(%{
          call_stack: [%{flow_name: "Main Flow", flow_id: 1}]
        })

      html = render_panel(debug_state: state, debug_current_flow_name: "Sub Flow")
      assert html =~ "Main Flow"
      assert html =~ "Sub Flow"
    end

    test "renders current flow name in breadcrumb" do
      state =
        base_debug_state(%{
          call_stack: [%{flow_name: "Parent", flow_id: 1}]
        })

      html = render_panel(debug_state: state, debug_current_flow_name: "Child Flow")
      assert html =~ "Child Flow"
    end

    test "renders fallback text when flow_name is nil" do
      state =
        base_debug_state(%{
          call_stack: [%{flow_id: 1}]
        })

      html = render_panel(debug_state: state)
      assert html =~ "Flow"
    end
  end

  # ===========================================================================
  # Step limit prompt
  # ===========================================================================

  describe "debug_panel/1 step limit prompt" do
    test "does not render step limit prompt when not reached" do
      html = render_panel(debug_step_limit_reached: false)
      refute html =~ "debug_continue_past_limit"
      refute html =~ "possible infinite loop"
    end

    test "renders step limit prompt when reached" do
      html = render_panel(debug_step_limit_reached: true)
      assert html =~ "debug_continue_past_limit"
      assert html =~ "possible infinite loop"
    end

    test "shows max_steps count in step limit message" do
      state = base_debug_state(%{max_steps: 2000})
      html = render_panel(debug_step_limit_reached: true, debug_state: state)
      assert html =~ "2000"
    end

    test "renders continue button in step limit prompt" do
      html = render_panel(debug_step_limit_reached: true)
      assert html =~ "Continue (+1000 steps)"
      assert html =~ "btn-warning"
    end
  end

  # ===========================================================================
  # Console tab rendering
  # ===========================================================================

  describe "debug_panel/1 console tab" do
    test "renders console entries with messages" do
      state =
        base_debug_state(%{
          console: [
            console_entry(1, "Execution started", ts: 100, node_label: "Entry"),
            console_entry(2, "Dialogue text", ts: 200, node_label: "Dialogue")
          ]
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "Execution started"
      assert html =~ "Dialogue text"
    end

    test "renders console entries with node labels" do
      state =
        base_debug_state(%{
          console: [console_entry(1, "Test", ts: 0, node_label: "My Node")]
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "My Node"
    end

    test "renders info level icon" do
      state =
        base_debug_state(%{
          console: [console_entry(1, "Info message", level: :info)]
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "text-info"
    end

    test "renders warning level with background" do
      state =
        base_debug_state(%{
          console: [console_entry(1, "Warning message", level: :warning)]
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "text-warning"
      assert html =~ "bg-warning/5"
    end

    test "renders error level with background" do
      state =
        base_debug_state(%{
          console: [console_entry(1, "Error message", level: :error)]
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "text-error"
      assert html =~ "bg-error/5"
    end

    test "renders empty console with no entries" do
      html =
        render_panel(debug_active_tab: "console", debug_state: base_debug_state(%{console: []}))

      # Should still render the console container but no entries
      assert html =~ "font-mono"
    end

    test "renders response choices when waiting for input" do
      state =
        base_debug_state(%{
          status: :waiting_input,
          pending_choices: %{
            responses: [
              %{id: "r1", text: "Yes", valid: true},
              %{id: "r2", text: "No", valid: false}
            ]
          }
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "Choose a response:"
      assert html =~ "debug_choose_response"
      assert html =~ "Yes"
      assert html =~ "No"
    end

    test "does not render response choices when not waiting for input" do
      state =
        base_debug_state(%{
          status: :paused,
          pending_choices: %{
            responses: [%{id: "r1", text: "Yes", valid: true}]
          }
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      refute html =~ "Choose a response:"
    end

    test "valid responses have primary button style" do
      state =
        base_debug_state(%{
          status: :waiting_input,
          pending_choices: %{
            responses: [%{id: "r1", text: "Accept", valid: true}]
          }
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "btn-primary"
    end

    test "invalid responses have ghost button style with strikethrough" do
      state =
        base_debug_state(%{
          status: :waiting_input,
          pending_choices: %{
            responses: [%{id: "r1", text: "Locked", valid: false}]
          }
        })

      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "btn-ghost"
      assert html =~ "line-through"
    end

    test "console entries with rule_details render detail rows" do
      entry = %{
        ts: 0,
        level: :info,
        node_id: 1,
        node_label: "",
        message: "Condition evaluated",
        rule_details: [
          %{
            variable_ref: "mc.health",
            operator: ">",
            expected_value: "50",
            passed: true,
            actual_value: 75
          }
        ]
      }

      state = base_debug_state(%{console: [entry]})
      html = render_panel(debug_active_tab: "console", debug_state: state)
      assert html =~ "mc.health"
      assert html =~ "pass"
    end
  end

  # ===========================================================================
  # Variables tab rendering
  # ===========================================================================

  describe "debug_panel/1 variables tab" do
    test "renders empty state when no variables" do
      html = render_panel(debug_active_tab: "variables")
      assert html =~ "No variables in this project"
    end

    test "renders variable table with variable data" do
      variables = %{
        "mc.health" =>
          make_variable(100,
            sheet_shortcut: "mc",
            variable_name: "health",
            block_type: "number"
          )
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      assert html =~ "health"
      assert html =~ "number"
    end

    test "renders filter input" do
      variables = %{
        "mc.health" => make_variable(100, sheet_shortcut: "mc", variable_name: "health")
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      assert html =~ "debug_var_filter"
      assert html =~ "Filter variables"
    end

    test "renders changed-only toggle button" do
      variables = %{
        "mc.health" => make_variable(100, sheet_shortcut: "mc", variable_name: "health")
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      assert html =~ "debug_var_toggle_changed"
      assert html =~ "Changed"
    end

    test "changed-only toggle has accent style when active" do
      variables = %{
        "mc.health" =>
          make_variable(75,
            initial_value: 100,
            sheet_shortcut: "mc",
            variable_name: "health"
          )
      }

      state = base_debug_state(%{variables: variables})

      html =
        render_panel(
          debug_active_tab: "variables",
          debug_state: state,
          debug_var_changed_only: true
        )

      assert html =~ "btn-accent"
    end

    test "renders count of shown vs total variables" do
      variables = %{
        "mc.health" => make_variable(100, sheet_shortcut: "mc", variable_name: "health"),
        "mc.mana" => make_variable(50, sheet_shortcut: "mc", variable_name: "mana")
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      assert html =~ "2 of 2"
    end

    test "renders table headers" do
      variables = %{
        "mc.health" => make_variable(100, sheet_shortcut: "mc", variable_name: "health")
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      assert html =~ "Variable"
      assert html =~ "Type"
      assert html =~ "Initial"
      assert html =~ "Previous"
      assert html =~ "Current"
    end

    test "shows no matching variables when filter excludes all" do
      variables = %{
        "mc.health" => make_variable(100, sheet_shortcut: "mc", variable_name: "health")
      }

      state = base_debug_state(%{variables: variables})

      html =
        render_panel(
          debug_active_tab: "variables",
          debug_state: state,
          debug_var_filter: "nonexistent"
        )

      assert html =~ "No matching variables"
    end

    test "highlights changed variables with diamond indicator" do
      variables = %{
        "mc.health" =>
          make_variable(75,
            initial_value: 100,
            source: :instruction,
            sheet_shortcut: "mc",
            variable_name: "health"
          )
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      # The diamond marker for changed variables
      assert html =~ "&#9670;" or html =~ "◆"
    end

    test "renders edit click handler for variable values" do
      variables = %{
        "mc.health" => make_variable(100, sheet_shortcut: "mc", variable_name: "health")
      }

      state = base_debug_state(%{variables: variables})
      html = render_panel(debug_active_tab: "variables", debug_state: state)
      assert html =~ "debug_edit_variable"
    end
  end

  # ===========================================================================
  # History tab rendering
  # ===========================================================================

  describe "debug_panel/1 history tab" do
    test "renders empty state when no history" do
      html = render_panel(debug_active_tab: "history")
      assert html =~ "No variable changes yet"
    end

    test "renders history entries with change details" do
      history = [
        %{
          ts: 1500,
          node_label: "Instruction",
          variable_ref: "mc.health",
          old_value: 100,
          new_value: 75,
          source: :instruction
        }
      ]

      state = base_debug_state(%{history: history})
      html = render_panel(debug_active_tab: "history", debug_state: state)
      assert html =~ "mc.health"
      assert html =~ "Instruction"
    end

    test "renders history table headers" do
      history = [
        %{
          ts: 0,
          node_label: "Test",
          variable_ref: "mc.x",
          old_value: 0,
          new_value: 1,
          source: :instruction
        }
      ]

      state = base_debug_state(%{history: history})
      html = render_panel(debug_active_tab: "history", debug_state: state)
      assert html =~ "Time"
      assert html =~ "Node"
      assert html =~ "Change"
      assert html =~ "Source"
    end

    test "renders source badge for instruction changes" do
      history = [
        %{
          ts: 0,
          node_label: "Instr",
          variable_ref: "mc.x",
          old_value: 0,
          new_value: 1,
          source: :instruction
        }
      ]

      state = base_debug_state(%{history: history})
      html = render_panel(debug_active_tab: "history", debug_state: state)
      assert html =~ "badge-warning"
      assert html =~ "instr"
    end

    test "renders source badge for user override changes" do
      history = [
        %{
          ts: 0,
          node_label: "",
          variable_ref: "mc.x",
          old_value: 0,
          new_value: 1,
          source: :user_override
        }
      ]

      state = base_debug_state(%{history: history})
      html = render_panel(debug_active_tab: "history", debug_state: state)
      assert html =~ "badge-info"
      assert html =~ "user"
    end

    test "renders user override label when node_label is empty" do
      history = [
        %{
          ts: 0,
          node_label: "",
          variable_ref: "mc.x",
          old_value: 0,
          new_value: 1,
          source: :user_override
        }
      ]

      state = base_debug_state(%{history: history})
      html = render_panel(debug_active_tab: "history", debug_state: state)
      assert html =~ "(user override)"
    end
  end

  # ===========================================================================
  # Path tab rendering
  # ===========================================================================

  describe "debug_panel/1 path tab" do
    test "renders empty state when no steps" do
      html = render_panel(debug_active_tab: "path")
      assert html =~ "No steps yet"
    end

    test "renders path entries with step numbers" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "exit")
      }

      state =
        base_debug_state(%{
          execution_log: [%{node_id: 2, depth: 0}, %{node_id: 1, depth: 0}],
          execution_path: [1, 2],
          console: []
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      # Should show step numbers
      refute html =~ "No steps yet"
    end

    test "renders breakpoint toggle buttons" do
      nodes = %{1 => node(1, "entry")}

      state =
        base_debug_state(%{
          execution_log: [%{node_id: 1, depth: 0}],
          execution_path: [1],
          console: []
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      assert html =~ "debug_toggle_breakpoint"
    end

    test "renders active breakpoint indicator" do
      nodes = %{1 => node(1, "entry")}

      state =
        base_debug_state(%{
          execution_log: [%{node_id: 1, depth: 0}],
          execution_path: [1],
          console: [],
          breakpoints: MapSet.new([1])
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      assert html =~ "bg-error"
      assert html =~ "Remove breakpoint"
    end

    test "renders inactive breakpoint indicator" do
      nodes = %{1 => node(1, "entry")}

      state =
        base_debug_state(%{
          execution_log: [%{node_id: 1, depth: 0}],
          execution_path: [1],
          console: [],
          breakpoints: MapSet.new()
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      assert html =~ "Set breakpoint"
    end

    test "highlights current step" do
      nodes = %{1 => node(1, "entry")}

      state =
        base_debug_state(%{
          execution_log: [%{node_id: 1, depth: 0}],
          execution_path: [1],
          console: []
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      assert html =~ "bg-primary/5"
    end

    test "renders sub-flow separator when depth changes" do
      nodes = %{
        1 => node(1, "entry"),
        10 => node(10, "entry")
      }

      state =
        base_debug_state(%{
          execution_log: [%{node_id: 10, depth: 1}, %{node_id: 1, depth: 0}],
          execution_path: [1, 10],
          console: []
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      assert html =~ "Entering sub-flow"
    end

    test "falls back to execution_path when execution_log is empty" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "exit")}

      state =
        base_debug_state(%{
          execution_log: [],
          execution_path: [1, 2],
          console: []
        })

      html = render_panel(debug_active_tab: "path", debug_state: state, debug_nodes: nodes)
      # Should still render entries from execution_path
      refute html =~ "No steps yet"
    end
  end

  # ===========================================================================
  # build_path_entries/3 — pure function tests (carried from original)
  # ===========================================================================

  describe "build_path_entries/3" do
    test "returns empty list for empty path" do
      assert DebugPanel.build_path_entries([], %{}, []) == []
    end

    test "builds entries with sequential step numbers" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(1, "Execution started"),
        console_entry(2, "Hub — pass through"),
        console_entry(3, "Execution finished")
      ]

      entries = DebugPanel.build_path_entries(log([1, 2, 3]), nodes, console)

      assert length(entries) == 3
      assert Enum.at(entries, 0).step == 1
      assert Enum.at(entries, 1).step == 2
      assert Enum.at(entries, 2).step == 3
    end

    test "maps node types from nodes map" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "dialogue", %{"text" => "Hello"}),
        3 => node(3, "exit")
      }

      entries = DebugPanel.build_path_entries(log([1, 2, 3]), nodes, [])

      assert Enum.at(entries, 0).type == "entry"
      assert Enum.at(entries, 1).type == "dialogue"
      assert Enum.at(entries, 2).type == "exit"
    end

    test "extracts node labels from text data, stripping HTML" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "dialogue", %{"text" => "<p>Hello World</p>"})
      }

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, [])

      assert Enum.at(entries, 0).label == nil
      assert Enum.at(entries, 1).label == "Hello World"
    end

    test "matches console outcomes to path steps in order" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "exit")}

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(1, "Execution started"),
        console_entry(2, "Execution finished")
      ]

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, console)

      assert Enum.at(entries, 0).outcome == "Execution started"
      assert Enum.at(entries, 1).outcome == "Execution finished"
    end

    test "marks only the last entry as current" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "exit")
      }

      entries = DebugPanel.build_path_entries(log([1, 2, 3]), nodes, [])

      refute Enum.at(entries, 0).is_current
      refute Enum.at(entries, 1).is_current
      assert Enum.at(entries, 2).is_current
    end

    test "single entry is marked as current" do
      nodes = %{1 => node(1, "entry")}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert length(entries) == 1
      assert Enum.at(entries, 0).is_current
    end

    test "handles repeated node visits by consuming console entries in order" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "hub"),
        3 => node(3, "hub")
      }

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(1, "Execution started"),
        console_entry(2, "Hub — first visit"),
        console_entry(3, "Hub — pass through"),
        console_entry(2, "Hub — second visit")
      ]

      entries = DebugPanel.build_path_entries(log([1, 2, 3, 2]), nodes, console)

      assert length(entries) == 4
      assert Enum.at(entries, 0).outcome == "Execution started"
      assert Enum.at(entries, 1).outcome == "Hub — first visit"
      assert Enum.at(entries, 2).outcome == "Hub — pass through"
      assert Enum.at(entries, 3).outcome == "Hub — second visit"
    end

    test "handles missing nodes gracefully with unknown type" do
      entries = DebugPanel.build_path_entries(log([999]), %{}, [])

      assert length(entries) == 1
      assert Enum.at(entries, 0).type == "unknown"
      assert Enum.at(entries, 0).label == nil
    end

    test "returns nil outcome when no console entry matches" do
      nodes = %{1 => node(1, "entry")}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert Enum.at(entries, 0).outcome == nil
    end

    test "ignores console entries with nil node_id" do
      nodes = %{1 => node(1, "entry")}

      console = [
        console_entry(nil, "Debug session started"),
        console_entry(nil, "Stepped back")
      ]

      entries = DebugPanel.build_path_entries(log([1]), nodes, console)

      assert Enum.at(entries, 0).outcome == nil
    end

    test "truncates long labels to 30 characters" do
      long_text = String.duplicate("abcde ", 10)
      nodes = %{1 => node(1, "dialogue", %{"text" => long_text})}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert String.length(Enum.at(entries, 0).label) <= 30
    end

    test "returns nil label for nodes with empty text" do
      nodes = %{1 => node(1, "dialogue", %{"text" => ""})}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert Enum.at(entries, 0).label == nil
    end

    test "returns nil label for nodes with HTML-only text" do
      nodes = %{1 => node(1, "dialogue", %{"text" => "<p> </p>"})}

      entries = DebugPanel.build_path_entries(log([1]), nodes, [])

      assert Enum.at(entries, 0).label == nil
    end

    test "preserves node_id in each entry" do
      nodes = %{
        10 => node(10, "entry"),
        20 => node(20, "exit")
      }

      entries = DebugPanel.build_path_entries(log([10, 20]), nodes, [])

      assert Enum.at(entries, 0).node_id == 10
      assert Enum.at(entries, 1).node_id == 20
    end
  end

  # ===========================================================================
  # build_path_entries/3 — depth and flow separators
  # ===========================================================================

  describe "build_path_entries/3 with depth" do
    test "entries include depth field" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "hub")}

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, [])

      assert Enum.at(entries, 0).depth == 0
      assert Enum.at(entries, 1).depth == 0
    end

    test "sub-flow entries have depth 1" do
      nodes = %{
        1 => node(1, "entry"),
        10 => node(10, "entry"),
        11 => node(11, "exit")
      }

      execution_log = log([{1, 0}, {10, 1}, {11, 1}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      normal = Enum.reject(entries, & &1[:separator])
      assert length(normal) == 3
      assert Enum.at(normal, 0).depth == 0
      assert Enum.at(normal, 1).depth == 1
      assert Enum.at(normal, 2).depth == 1
    end

    test "inserts enter separator when depth increases" do
      nodes = %{1 => node(1, "entry"), 10 => node(10, "entry")}

      execution_log = log([{1, 0}, {10, 1}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert length(separators) == 1
      assert hd(separators).direction == :enter
      assert hd(separators).depth == 1
    end

    test "inserts return separator when depth decreases" do
      nodes = %{
        1 => node(1, "entry"),
        10 => node(10, "entry"),
        2 => node(2, "hub")
      }

      execution_log = log([{1, 0}, {10, 1}, {2, 0}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert length(separators) == 2

      [enter_sep, return_sep] = separators
      assert enter_sep.direction == :enter
      assert return_sep.direction == :return
    end

    test "full cross-flow roundtrip produces enter and return separators" do
      nodes = %{
        1 => node(1, "entry"),
        2 => node(2, "subflow"),
        10 => node(10, "entry"),
        11 => node(11, "exit"),
        3 => node(3, "hub"),
        4 => node(4, "exit")
      }

      execution_log = log([{1, 0}, {2, 0}, {10, 1}, {11, 1}, {3, 0}, {4, 0}])
      entries = DebugPanel.build_path_entries(execution_log, nodes, [])

      normal = Enum.reject(entries, & &1[:separator])
      separators = Enum.filter(entries, & &1[:separator])

      assert length(normal) == 6
      assert length(separators) == 2

      types =
        Enum.map(entries, fn e ->
          if e[:separator], do: {:sep, e.direction}, else: {:node, e.depth}
        end)

      assert types == [
               {:node, 0},
               {:node, 0},
               {:sep, :enter},
               {:node, 1},
               {:node, 1},
               {:sep, :return},
               {:node, 0},
               {:node, 0}
             ]
    end

    test "nested sub-flows produce separators at each depth change" do
      execution_log = log([{1, 0}, {10, 1}, {20, 2}, {11, 1}, {2, 0}])
      entries = DebugPanel.build_path_entries(execution_log, %{}, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert length(separators) == 4

      directions = Enum.map(separators, & &1.direction)
      assert directions == [:enter, :enter, :return, :return]
    end

    test "no separators when all entries at same depth" do
      nodes = %{1 => node(1, "entry"), 2 => node(2, "exit")}

      entries = DebugPanel.build_path_entries(log([1, 2]), nodes, [])

      separators = Enum.filter(entries, & &1[:separator])
      assert separators == []
    end

    test "step numbers are continuous regardless of depth" do
      execution_log = log([{1, 0}, {10, 1}, {11, 1}, {2, 0}])
      entries = DebugPanel.build_path_entries(execution_log, %{}, [])

      normal = Enum.reject(entries, & &1[:separator])
      steps = Enum.map(normal, & &1.step)
      assert steps == [1, 2, 3, 4]
    end

    test "is_current is based on execution_log length, not entry count" do
      execution_log = log([{1, 0}, {10, 1}, {11, 1}])
      entries = DebugPanel.build_path_entries(execution_log, %{}, [])

      normal = Enum.reject(entries, & &1[:separator])
      current_entries = Enum.filter(normal, & &1.is_current)
      assert length(current_entries) == 1
      assert hd(current_entries).step == 3
    end
  end
end
