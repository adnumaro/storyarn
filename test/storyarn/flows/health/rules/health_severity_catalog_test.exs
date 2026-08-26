defmodule Storyarn.Flows.HealthSeverityCatalogTest do
  @moduledoc """
  Freezes the Flow-owned health vocabulary exposed to the editor.

  The exact map makes every new, removed or reclassified Flow finding an
  explicit product decision without coupling that decision to another tool.
  """

  use ExUnit.Case, async: true

  alias Storyarn.Flows.HealthChecker

  test "every Flow health code is pinned to a supported severity" do
    expected = %{
      # Structural — detected from the graph.
      invalid_input_pins: :error,
      invalid_output_pins: :error,
      missing_entry: :error,
      missing_exit_flow_reference: :error,
      missing_jump_target: :error,
      missing_subflow_reference: :error,
      multiple_entries: :error,
      stale_exit_flow_reference: :error,
      stale_jump_target: :error,
      stale_subflow_reference: :error,
      isolated_node: :warning,
      missing_output_connections: :warning,
      no_outgoing_connection: :warning,
      orphan_hub: :warning,
      unreachable_node: :warning,
      # Editorial — detected from one node's own data.
      stale_variable_reference: :error,
      empty_dialogue_response: :warning,
      incomplete_condition: :warning,
      incomplete_instruction_assignment: :warning,
      incomplete_response_assignment: :warning,
      incomplete_response_condition: :warning,
      missing_dialogue_speaker: :warning,
      missing_dialogue_text: :warning,
      response_type_mismatch: :warning,
      variable_type_mismatch: :warning,
      empty_condition: :info,
      empty_instruction: :info
    }

    actual = Map.new(HealthChecker.codes(), &{&1, HealthChecker.severity_for(&1)})

    assert actual == expected
    assert map_size(expected) == length(HealthChecker.codes())
    assert Enum.all?(Map.values(actual), &(&1 in [:error, :warning, :info]))
    assert_raise KeyError, fn -> HealthChecker.severity_for(:a_code_that_was_never_declared) end
  end
end
