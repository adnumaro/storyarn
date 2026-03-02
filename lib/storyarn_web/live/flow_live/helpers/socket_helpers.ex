defmodule StoryarnWeb.FlowLive.Helpers.SocketHelpers do
  @moduledoc """
  Shared socket helpers for the flow editor.

  Provides common operations used across multiple handler and helper modules:
  - `reload_flow_data/1` - Refreshes flow, flow_data, and flow_hubs assigns
  - `schedule_save_status_reset/0` - Schedules the save indicator reset

  Import this module in any flow_live handler or helper that needs these.
  """

  import Phoenix.Component, only: [assign: 3]
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Components.NodeTypeHelpers
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  @doc """
  Reloads flow data from the database and updates socket assigns.

  Refreshes `:flow`, `:flow_data`, `:flow_hubs`, `:flow_word_count`,
  `:flow_error_nodes`, and `:flow_info_nodes`.
  """
  @spec reload_flow_data(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def reload_flow_data(socket) do
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
    flow_data = Flows.serialize_for_canvas(flow)
    flow_hubs = Flows.list_hubs(flow.id)

    socket
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:flow_hubs, flow_hubs)
    |> assign_flow_stats(flow, flow_data)
  end

  @doc """
  Computes flow-level stats (word count, error/info nodes) and assigns them to the socket.
  """
  @spec assign_flow_stats(Phoenix.LiveView.Socket.t(), map(), map()) ::
          Phoenix.LiveView.Socket.t()
  def assign_flow_stats(socket, flow, flow_data) do
    word_count =
      flow.nodes
      |> Enum.filter(&(&1.type == "dialogue"))
      |> Enum.reduce(0, fn node, acc ->
        acc +
          NodeTypeHelpers.word_count(node.data["text"]) +
          NodeTypeHelpers.word_count(node.data["stage_directions"]) +
          response_word_count(node.data["responses"])
      end)

    error_nodes =
      flow_data.nodes
      |> Enum.filter(&node_has_errors?/1)
      |> Enum.map(fn n ->
        %{id: n.id, type: n.type, label: node_short_label(n)}
      end)

    info_nodes =
      flow_data.nodes
      |> Enum.filter(&node_has_info?/1)
      |> Enum.map(fn n ->
        %{id: n.id, type: n.type, label: node_short_label(n), reason: info_reason(n)}
      end)

    socket
    |> assign(:flow_word_count, word_count)
    |> assign(:flow_error_nodes, error_nodes)
    |> assign(:flow_info_nodes, info_nodes)
  end

  defp response_word_count(nil), do: 0

  defp response_word_count(responses) when is_list(responses) do
    Enum.reduce(responses, 0, fn r, acc ->
      acc + NodeTypeHelpers.word_count(r["text"])
    end)
  end

  defp node_has_errors?(%{data: data, type: type}) do
    data["has_stale_refs"] == true ||
      data["has_type_warnings"] == true ||
      (type == "subflow" && (data["stale_reference"] == true || !data["referenced_flow_id"])) ||
      (type == "scene" && !data["location_sheet_id"]) ||
      (type == "dialogue" && has_response_warnings?(data["responses"]))
  end

  defp node_has_info?(%{data: data}) do
    data["unreachable"] == true || data["dead_end"] == true
  end

  defp info_reason(%{data: data}) do
    cond do
      data["unreachable"] -> dgettext("flows", "Not reachable from any entry node")
      data["dead_end"] -> dgettext("flows", "No outgoing connection")
    end
  end

  defp has_response_warnings?(nil), do: false

  defp has_response_warnings?(responses) when is_list(responses) do
    Enum.any?(responses, &(&1["has_type_warnings"] == true))
  end

  defp node_short_label(%{id: id, type: type}) do
    dgettext("flows", "%{type} #%{id}", type: NodeTypeRegistry.label(type), id: id)
  end

  @doc """
  Schedules a message to reset the save status indicator after 2 seconds.
  """
  def schedule_save_status_reset do
    Process.send_after(self(), :reset_save_status, 2000)
  end

  @doc """
  Marks the save status as :saved and schedules the automatic reset.
  Convenience function that combines assign + schedule_save_status_reset.
  """
  def mark_saved(socket) do
    schedule_save_status_reset()
    assign(socket, :save_status, :saved)
  end
end
