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
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Shared.WordCount
  alias StoryarnWeb.FlowLive.Helpers.HealthHelpers

  @doc """
  Reloads flow data from the database and updates socket assigns.

  Refreshes `:flow`, `:flow_data`, `:flow_hubs`, `:flow_word_count` and
  `:flow_health`.
  """
  @spec reload_flow_data(Socket.t(), keyword()) :: Socket.t()
  def reload_flow_data(socket, opts \\ []) do
    previous_flow = socket.assigns[:flow]
    flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)

    flow_data = Flows.serialize_for_canvas(flow)
    flow_hubs = Flows.list_hubs(flow.id)

    # Local graph mutations announce themselves project-wide so flows whose
    # subflow/exit pins derive from this one can stale their open analysis
    # snapshots. Remote-change receivers pass notify_project: false.
    if Keyword.get(opts, :notify_project, true) and exit_surface_changed?(previous_flow, flow) do
      Collaboration.broadcast_flow_graph_changed_from(self(), flow.project_id, flow.id)
    end

    socket
    |> assign(:flow, flow)
    |> assign(:flow_data, flow_data)
    |> assign(:flow_hubs, flow_hubs)
    |> assign_flow_stats(flow, flow_data)
  end

  # Other flows only ever derive from THIS flow's exit nodes: a subflow node
  # exposes one output pin per referenced-flow exit node
  # (`NodeCrud.batch_resolve_subflow_data/2` → `exit_<exit node id>`), and an
  # exit node in flow-reference mode resolves against the flow's existence.
  # Content-only edits (dialogue text, positions, connections inside this
  # flow) change nothing another flow can observe, so they must not stale
  # anyone else's snapshot. An unloaded association is treated as changed —
  # over-notifying is recoverable, missing a real pin change is not.
  defp exit_surface_changed?(previous_flow, flow) do
    case exit_node_ids(previous_flow) do
      nil -> true
      previous_ids -> previous_ids != exit_node_ids(flow)
    end
  end

  defp exit_node_ids(%{nodes: nodes}) when is_list(nodes) do
    for node <- nodes, node.type == "exit", into: MapSet.new(), do: node.id
  end

  defp exit_node_ids(_flow), do: nil

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
