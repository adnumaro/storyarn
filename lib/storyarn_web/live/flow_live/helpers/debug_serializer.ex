defmodule StoryarnWeb.FlowLive.Helpers.DebugSerializer do
  @moduledoc """
  Serializes `Storyarn.Flows.Evaluator.State` into a Vue-friendly map.

  Transforms that matter for JSON/LiveVue transport:
  - `breakpoints` (MapSet) → list
  - `pending_choices` (`%{responses: [...]} | nil`) → list of responses or nil
  - `variables.*` → adds `:changed` boolean (value != initial_value) so the Vue
    side doesn't have to compare arbitrary terms
  """

  @spec serialize(map() | nil) :: map() | nil
  def serialize(nil), do: nil

  def serialize(%_{} = state), do: state |> Map.from_struct() |> serialize()

  def serialize(state) when is_map(state) do
    %{
      status: state.status,
      current_node_id: state.current_node_id,
      start_node_id: state[:start_node_id],
      step_count: state.step_count,
      max_steps: state.max_steps,
      variables: serialize_variables(state.variables),
      console: state.console,
      history: state.history,
      execution_path: state.execution_path,
      execution_log: state.execution_log,
      snapshots: state.snapshots,
      breakpoints: MapSet.to_list(state.breakpoints || MapSet.new()),
      pending_choices: serialize_pending_choices(state.pending_choices),
      call_stack: state.call_stack
    }
  end

  defp serialize_variables(vars) when is_map(vars) do
    Map.new(vars, fn {key, var} ->
      changed = Map.get(var, :value) != Map.get(var, :initial_value)
      {key, Map.put(var, :changed, changed)}
    end)
  end

  defp serialize_variables(_), do: %{}

  defp serialize_pending_choices(%{responses: responses}), do: responses
  defp serialize_pending_choices(_), do: nil
end
