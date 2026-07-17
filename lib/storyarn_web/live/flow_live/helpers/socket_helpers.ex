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
  alias Storyarn.Flows.HealthChecker
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Shared.WordCount
  alias StoryarnWeb.FlowLive.NodeTypeRegistry

  @doc """
  Reloads flow data from the database and updates socket assigns.

  Refreshes `:flow`, `:flow_data`, `:flow_hubs`, `:flow_word_count`,
  `:flow_error_nodes`, `:flow_warning_nodes`, and `:flow_info_nodes`.
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

    findings = HealthChecker.check(flow_data)

    socket
    |> assign(:flow_word_count, word_count)
    |> assign(:flow_error_nodes, health_payloads(findings, :error))
    |> assign(:flow_warning_nodes, health_payloads(findings, :warning))
    |> assign(:flow_info_nodes, health_payloads(findings, :info))
  end

  defp health_payloads(findings, severity) do
    findings
    |> Enum.filter(&(&1.severity == severity))
    |> Enum.chunk_by(&{&1.node_id, &1.node_type})
    |> Enum.map(&health_payload/1)
  end

  defp health_payload([finding | _] = findings) do
    reasons = Enum.map(findings, &finding_message/1)

    %{
      id: finding.node_id,
      type: finding.node_type || "flow",
      label: health_label(finding),
      reason: Enum.join(reasons, " · "),
      reasons: reasons
    }
  end

  defp health_label(%{node_id: nil}), do: dgettext("flows", "Flow")

  defp health_label(%{node_id: id, node_type: type}) do
    dgettext("flows", "%{type} #%{id}", type: NodeTypeRegistry.label(type), id: id)
  end

  defp finding_message(%{code: :missing_entry}), do: dgettext("flows", "Missing entry node")

  defp finding_message(%{code: :multiple_entries, details: %{count: count}}),
    do: dgettext("flows", "Flow has %{count} entry nodes", count: count)

  defp finding_message(%{code: :stale_variable_reference}), do: dgettext("flows", "Stale variable reference")

  defp finding_message(%{code: :missing_subflow_reference}), do: dgettext("flows", "Missing subflow reference")

  defp finding_message(%{code: :stale_subflow_reference}), do: dgettext("flows", "Stale subflow reference")

  defp finding_message(%{code: :missing_jump_target}), do: dgettext("flows", "Missing jump target")
  defp finding_message(%{code: :stale_jump_target}), do: dgettext("flows", "Jump target does not exist")

  defp finding_message(%{code: :missing_exit_flow_reference}), do: dgettext("flows", "Missing exit flow reference")

  defp finding_message(%{code: :stale_exit_flow_reference}), do: dgettext("flows", "Exit flow reference does not exist")

  defp finding_message(%{code: :invalid_output_pins, details: %{pins: pins}}),
    do: dgettext("flows", "Invalid output connection pin(s): %{pins}", pins: Enum.join(pins, ", "))

  defp finding_message(%{code: :invalid_input_pins, details: %{pins: pins}}),
    do: dgettext("flows", "Invalid input connection pin(s): %{pins}", pins: Enum.join(pins, ", "))

  defp finding_message(%{code: :variable_type_mismatch}), do: dgettext("flows", "Variable type warning")

  defp finding_message(%{code: :response_type_mismatch}), do: dgettext("flows", "Response assignment type warning")

  defp finding_message(%{code: :missing_dialogue_text}), do: dgettext("flows", "Missing dialogue text")

  defp finding_message(%{code: :missing_dialogue_speaker}), do: dgettext("flows", "Missing dialogue speaker")

  defp finding_message(%{code: :empty_dialogue_response}), do: dgettext("flows", "Empty dialogue response")

  defp finding_message(%{code: :incomplete_response_condition}), do: dgettext("flows", "Incomplete response condition")

  defp finding_message(%{code: :incomplete_response_assignment}), do: dgettext("flows", "Incomplete response assignment")

  defp finding_message(%{code: :incomplete_condition}), do: dgettext("flows", "Incomplete condition")

  defp finding_message(%{code: :incomplete_instruction_assignment}),
    do: dgettext("flows", "Incomplete instruction assignment")

  defp finding_message(%{code: :unreachable_node}), do: dgettext("flows", "Not reachable from any entry node")

  defp finding_message(%{code: :no_outgoing_connection}), do: dgettext("flows", "No outgoing connection")

  defp finding_message(%{code: :missing_output_connections, details: %{pins: pins}}),
    do: dgettext("flows", "Output(s) without connection: %{pins}", pins: Enum.join(pins, ", "))

  defp finding_message(%{code: :empty_instruction}), do: dgettext("flows", "No instruction assignments")

  defp finding_message(%{code: :empty_condition}), do: dgettext("flows", "Condition has no rules")
end
