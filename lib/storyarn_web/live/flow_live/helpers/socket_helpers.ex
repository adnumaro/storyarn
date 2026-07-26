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
  alias Storyarn.Shared.WordCount
  alias StoryarnWeb.FlowLive.Helpers.HealthHelpers

  @doc """
  Reloads flow data from the database and updates socket assigns.

  Refreshes `:flow`, `:flow_data`, `:flow_hubs`, `:flow_word_count` and
  `:flow_health`.
  """
  @spec reload_flow_data(Socket.t()) :: Socket.t()
  def reload_flow_data(socket) do
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)

    # Once the flow is loaded the socket already holds the FULL referenceable
    # set; omitting it made the serializer re-query it (8 queries / 49.7 ms vs
    # 4 / 18.7 ms). `nil` before the async load lands is fine and NOT a fallback
    # to a different vocabulary: `serialize_for_canvas/2` then computes the very
    # same `list_referenceable_variables/1` set, just at the cost of the query.
    flow_data =
      Flows.serialize_for_canvas(flow, project_variables: socket.assigns[:project_variables])

    flow_hubs = Flows.list_hubs(flow.id)

    socket
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:flow_hubs, flow_hubs)
    |> assign_flow_stats(flow, flow_data)
  end

  @doc """
  Computes flow-level stats and health findings grouped by severity.
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

    # ONE health surface, and the SAME composition point the dashboard calls, so
    # the two cannot disagree. Zero extra node queries: the serializer's output is
    # already resolved (from_serialized==DB parity is test-guarded).
    findings = Flows.flow_health_findings(flow_data, flow.project_id)

    socket
    |> assign(:flow_word_count, word_count)
    |> assign(:flow_health, HealthHelpers.health_payload(findings, flow.name))
  end
end
