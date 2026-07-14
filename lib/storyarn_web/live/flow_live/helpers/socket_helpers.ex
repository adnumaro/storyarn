defmodule StoryarnWeb.FlowLive.Helpers.SocketHelpers do
  @moduledoc """
  Shared socket helpers for the flow editor.

  Provides common operations used across multiple handler and helper modules:
  - `reload_flow_data/1` - Refreshes flow, flow_data, and flow_hubs assigns

  For save status, use `SaveStatusTimer.schedule_reset/1` instead.

  Import this module in any flow_live handler or helper that needs these.
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView.Socket
  alias Storyarn.Flows
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Shared.HtmlUtils
  alias Storyarn.Shared.WordCount
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  @doc """
  Reloads flow data from the database and updates socket assigns.

  Refreshes `:flow`, `:flow_data`, `:flow_hubs`, `:flow_word_count`,
  `:flow_error_nodes`, and `:flow_info_nodes`.
  """
  @spec reload_flow_data(Socket.t()) :: Socket.t()
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
  @spec assign_flow_stats(Socket.t(), map(), map()) ::
          Socket.t()
  def assign_flow_stats(socket, flow, flow_data) do
    localizable_node_types = SourceContract.localizable_flow_node_types()

    word_count =
      flow.nodes
      |> Enum.filter(&(&1.type in localizable_node_types))
      |> Enum.reduce(0, fn node, total ->
        total + WordCount.for_node_data(node.type, node.data)
      end)

    error_nodes =
      flow_data.nodes
      |> Enum.map(fn n -> node_health_payload(n, error_reasons(n)) end)
      |> Enum.reject(&is_nil/1)

    info_nodes =
      flow_data.nodes
      |> Enum.map(fn n -> node_health_payload(n, info_reasons(n)) end)
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:flow_word_count, word_count)
    |> assign(:flow_error_nodes, error_nodes)
    |> assign(:flow_info_nodes, info_nodes)
  end

  defp node_health_payload(_node, []), do: nil

  defp node_health_payload(node, reasons) do
    %{
      id: node.id,
      type: node.type,
      label: node_short_label(node),
      reason: Enum.join(reasons, " · "),
      reasons: reasons
    }
  end

  defp error_reasons(%{data: data, type: type}) do
    []
    |> maybe_add_reason(data["has_stale_refs"] == true, dgettext("flows", "Stale variable reference"))
    |> maybe_add_reason(data["has_type_warnings"] == true, dgettext("flows", "Variable type warning"))
    |> maybe_add_reason(
      type == "subflow" && data["stale_reference"] == true,
      dgettext("flows", "Stale subflow reference")
    )
    |> maybe_add_reason(
      type == "subflow" && !data["referenced_flow_id"],
      dgettext("flows", "Missing subflow reference")
    )
    |> maybe_add_reason(
      type == "dialogue" && dialogue_text_empty?(data),
      dgettext("flows", "Missing dialogue text")
    )
    |> maybe_add_reason(
      type == "dialogue" && has_response_warnings?(data["responses"]),
      dgettext("flows", "Response assignment type warning")
    )
  end

  defp info_reasons(%{data: data}) do
    []
    |> maybe_add_reason(data["unreachable"] == true, dgettext("flows", "Not reachable from any entry node"))
    |> maybe_add_reason(data["dead_end"] == true, dgettext("flows", "No outgoing connection"))
  end

  defp maybe_add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  defp dialogue_text_empty?(data) do
    data |> Map.get("text") |> HtmlUtils.strip_html() == ""
  end

  defp has_response_warnings?(nil), do: false

  defp has_response_warnings?(responses) when is_list(responses) do
    Enum.any?(responses, &(&1["has_type_warnings"] == true))
  end

  defp node_short_label(%{id: id, type: type}) do
    dgettext("flows", "%{type} #%{id}", type: NodeTypeRegistry.label(type), id: id)
  end
end
