defmodule Storyarn.Flows.Evaluator.EngineHelpers do
  @moduledoc """
  Shared internal helpers for the flow evaluator engine and node evaluator sub-modules.

  Provides state-mutating helpers (add_console, advance_to, etc.) and
  pure utilities (find_connection, format_rule_summary) that are used by
  both Engine and the per-node-type evaluator modules.
  """

  alias Storyarn.Flows.Evaluator.Helpers
  alias Storyarn.Flows.Evaluator.State

  @doc """
  Advance execution to the given target node, updating execution path and log.
  """
  def advance_to(state, target_node_id) do
    log_entry = %{node_id: target_node_id, depth: length(state.call_stack)}

    {:ok,
     %{
       state
       | current_node_id: target_node_id,
         status: :paused,
         pending_choices: nil,
         execution_path: [target_node_id | state.execution_path],
         execution_log: [log_entry | state.execution_log]
     }}
  end

  @doc """
  Follow the default/output pin from a node, finishing if no connection exists.
  """
  def follow_output(state, node_id, label, connections) do
    conn = find_connection(connections, node_id, "default")

    case conn do
      nil ->
        state = add_console(state, :error, node_id, label, "No outgoing connection")
        {:finished, %{state | status: :finished}}

      conn ->
        advance_to(state, conn.target_node_id)
    end
  end

  @doc """
  Find a connection by source node and pin.
  """
  def find_connection(connections, source_node_id, source_pin) do
    Enum.find(connections, fn conn ->
      conn.source_node_id == source_node_id and conn.source_pin == source_pin
    end)
  end

  @doc """
  Finds the parent-flow connection to follow after returning from a subflow.

  Subflow nodes can expose dynamic outputs keyed by the returned exit node
  (`exit_<id>`). Older/simple subflow connections use `output` or `default`, so
  those remain fallbacks.
  """
  def find_return_connection(connections, return_node_id, returned_exit_node_id) do
    exit_pin = if returned_exit_node_id, do: "exit_#{returned_exit_node_id}"

    Enum.find(connections, &matches_source_pin?(&1, return_node_id, exit_pin)) ||
      Enum.find(connections, &matches_source_pin?(&1, return_node_id, "output")) ||
      Enum.find(connections, &matches_source_pin?(&1, return_node_id, "default"))
  end

  defp matches_source_pin?(_conn, _return_node_id, nil), do: false

  defp matches_source_pin?(conn, return_node_id, pin) do
    conn.source_node_id == return_node_id and conn.source_pin == pin
  end

  @doc """
  Add a console entry to the state.
  """
  def add_console(%State{} = state, level, node_id, node_label, message) do
    entry = %{
      ts: elapsed_ms(state),
      level: level,
      node_id: node_id,
      node_label: node_label || "",
      message: message,
      rule_details: nil
    }

    %{state | console: [entry | state.console]}
  end

  @doc """
  Add a console entry with rule details (used for condition evaluation).
  """
  def add_console_with_rules(%State{} = state, level, node_id, node_label, message, rule_details) do
    entry = %{
      ts: elapsed_ms(state),
      level: level,
      node_id: node_id,
      node_label: node_label || "",
      message: message,
      rule_details: rule_details
    }

    %{state | console: [entry | state.console]}
  end

  @doc """
  Add variable change entries to the history log.
  """
  def add_history_entries(state, _node_id, _node_label, [], _source), do: state

  def add_history_entries(state, node_id, node_label, changes, source) do
    entries =
      Enum.map(changes, fn change ->
        %{
          ts: elapsed_ms(state),
          node_id: node_id,
          node_label: node_label || "",
          variable_ref: change.variable_ref,
          old_value: change.old_value,
          new_value: change.new_value,
          source: source
        }
      end)

    %{state | history: Enum.reverse(entries, state.history)}
  end

  @doc """
  Format a summary of rule evaluation results for console output.
  """
  def format_rule_summary([]), do: ""

  def format_rule_summary(results) do
    failed_count = Enum.count(results, &(!&1.passed))
    total = length(results)

    if failed_count > 0 do
      " (#{total - failed_count} of #{total} rules passed)"
    else
      " (all #{total} rules passed)"
    end
  end

  @doc """
  Extract a display label from a node's data.
  """
  def node_label(%{data: %{"text" => text}}) when is_binary(text) and text != "" do
    Helpers.strip_html(text, 40)
  end

  def node_label(_node), do: nil

  @doc """
  Format a value for display in console/history.
  """
  def format_value(value), do: Helpers.format_value(value)

  defp elapsed_ms(%{started_at: nil}), do: 0

  defp elapsed_ms(%{started_at: started_at}) do
    System.monotonic_time(:millisecond) - started_at
  end
end
