defmodule StoryarnWeb.FlowLive.Nodes.Exit.Node do
  @moduledoc """
  Exit node type definition.

  Represents a flow endpoint with outcome tags, color, and exit mode
  (terminal, flow_reference, or caller_return).
  """

  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  @valid_exit_modes ~w(terminal flow_reference caller_return)

  def type, do: "exit"
  def icon_name, do: "square"
  def label, do: dgettext("flows", "Exit")

  def default_data do
    %{
      "label" => "",
      "technical_id" => "",
      "outcome_tags" => [],
      "outcome_color" => "#22c55e",
      "exit_mode" => "terminal",
      "referenced_flow_id" => nil
    }
  end

  def extract_form_data(data) do
    %{
      "label" => data["label"] || "",
      "technical_id" => data["technical_id"] || "",
      "outcome_tags" => parse_outcome_tags(data["outcome_tags"]),
      "outcome_color" => validate_color(data["outcome_color"]),
      "exit_mode" => validate_exit_mode(data["exit_mode"]),
      "referenced_flow_id" => parse_referenced_flow_id(data["referenced_flow_id"])
    }
  end

  def on_select(node, socket) do
    project_id = socket.assigns.project.id
    flow_id = socket.assigns.flow.id

    existing_tags = Flows.list_outcome_tags_for_project(project_id)
    referencing_flows = Flows.list_nodes_referencing_flow(flow_id, project_id)

    socket =
      socket
      |> Phoenix.Component.assign(:outcome_tags_suggestions, existing_tags)
      |> Phoenix.Component.assign(:referencing_flows, referencing_flows)

    case node.data["exit_mode"] do
      "flow_reference" ->
        available_flows =
          Flows.list_flows(project_id)
          |> Enum.reject(&(&1.id == flow_id))

        Phoenix.Component.assign(socket, :available_flows, available_flows)

      _ ->
        socket
    end
  end

  def on_double_click(_node), do: :sidebar

  # -- Parsing helpers --

  defp parse_outcome_tags(tags) when is_list(tags), do: tags

  defp parse_outcome_tags(tags) when is_binary(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp parse_outcome_tags(_), do: []

  defp normalize_tag(tag) do
    tag
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
  end

  defp validate_color(color) when is_binary(color) do
    if String.match?(color, ~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/) do
      color
    else
      "#22c55e"
    end
  end

  defp validate_color(_), do: "#22c55e"

  defp validate_exit_mode(mode) when mode in @valid_exit_modes, do: mode
  defp validate_exit_mode(_), do: "terminal"

  defp parse_referenced_flow_id(nil), do: nil
  defp parse_referenced_flow_id(""), do: nil
  defp parse_referenced_flow_id(id) when is_integer(id), do: id

  defp parse_referenced_flow_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_referenced_flow_id(_), do: nil

  def duplicate_data_cleanup(data) do
    Map.put(data, "technical_id", "")
  end

  # -- Exit-specific event handlers --

  @doc "Updates exit mode (terminal, flow_reference, caller_return)."
  def handle_update_exit_mode(mode, socket) do
    node = socket.assigns.selected_node
    validated_mode = validate_exit_mode(mode)

    NodeHelpers.persist_node_update(socket, node.id, fn data ->
      data = Map.put(data, "exit_mode", validated_mode)

      # Clear referenced_flow_id when leaving flow_reference mode
      if validated_mode != "flow_reference" do
        Map.put(data, "referenced_flow_id", nil)
      else
        data
      end
    end)
    |> then(fn {:noreply, socket} ->
      # Load available flows when switching to flow_reference
      if validated_mode == "flow_reference" do
        project_id = socket.assigns.project.id
        current_flow_id = socket.assigns.flow.id

        available_flows =
          Flows.list_flows(project_id)
          |> Enum.reject(&(&1.id == current_flow_id))

        {:noreply, Phoenix.Component.assign(socket, :available_flows, available_flows)}
      else
        {:noreply, socket}
      end
    end)
  end

  @doc "Updates exit flow reference."
  def handle_update_exit_reference(flow_id_str, socket) do
    node = socket.assigns.selected_node

    case parse_referenced_flow_id(flow_id_str) do
      nil ->
        NodeHelpers.persist_node_update(socket, node.id, fn data ->
          Map.put(data, "referenced_flow_id", nil)
        end)

      flow_id ->
        do_update_exit_reference(flow_id, node, socket)
    end
  end

  defp do_update_exit_reference(flow_id, node, socket) do
    project_id = socket.assigns.project.id
    current_flow_id = socket.assigns.flow.id

    cond do
      flow_id == current_flow_id ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, dgettext("flows", "Cannot reference the current flow."))}

      Flows.has_circular_reference?(current_flow_id, flow_id) ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           dgettext("flows", "This would create a circular reference.")
         )}

      is_nil(Flows.get_flow_brief(project_id, flow_id)) ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, dgettext("flows", "Flow not found."))}

      true ->
        NodeHelpers.persist_node_update(socket, node.id, fn data ->
          Map.put(data, "referenced_flow_id", flow_id)
        end)
    end
  end

  @doc "Adds an outcome tag."
  def handle_add_outcome_tag(tag, socket) do
    normalized = normalize_tag(tag)

    if normalized == "" do
      {:noreply, socket}
    else
      node = socket.assigns.selected_node

      NodeHelpers.persist_node_update(socket, node.id, &add_tag_to_data(&1, normalized))
    end
  end

  defp add_tag_to_data(data, tag) do
    current_tags = data["outcome_tags"] || []
    if tag in current_tags, do: data, else: Map.put(data, "outcome_tags", current_tags ++ [tag])
  end

  @doc "Removes an outcome tag."
  def handle_remove_outcome_tag(tag, socket) do
    node = socket.assigns.selected_node

    NodeHelpers.persist_node_update(socket, node.id, fn data ->
      current_tags = data["outcome_tags"] || []
      Map.put(data, "outcome_tags", Enum.reject(current_tags, &(&1 == tag)))
    end)
  end

  @doc "Updates outcome color."
  def handle_update_outcome_color(color, socket) do
    node = socket.assigns.selected_node
    validated_color = validate_color(color)

    NodeHelpers.persist_node_update(socket, node.id, fn data ->
      Map.put(data, "outcome_color", validated_color)
    end)
  end

  @doc "Generates a technical ID for an exit node."
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node
    flow = socket.assigns.flow
    exit_count = count_exit_in_flow(flow, node.id)
    label = node.data["label"]
    technical_id = generate_exit_technical_id(flow.shortcut, label, exit_count)

    NodeHelpers.update_node_field(socket, node.id, "technical_id", technical_id)
  end

  # Private helpers

  defp count_exit_in_flow(flow, current_node_id) do
    flow = Repo.preload(flow, :nodes)

    exit_nodes =
      flow.nodes
      |> Enum.filter(&(&1.type == "exit"))
      |> Enum.sort_by(& &1.inserted_at)

    case Enum.find_index(exit_nodes, &(&1.id == current_node_id)) do
      nil -> length(exit_nodes) + 1
      index -> index + 1
    end
  end

  defp generate_exit_technical_id(flow_slug, label, exit_count) do
    flow_part = normalize_for_id(flow_slug || "")
    label_part = normalize_for_id(label || "")
    flow_part = if flow_part == "", do: "flow", else: flow_part
    label_part = if label_part == "", do: "exit", else: label_part
    "#{flow_part}_#{label_part}_#{exit_count}"
  end

  defp normalize_for_id(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp normalize_for_id(_), do: ""
end
