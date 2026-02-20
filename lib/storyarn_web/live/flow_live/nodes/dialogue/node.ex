defmodule StoryarnWeb.FlowLive.Nodes.Dialogue.Node do
  @moduledoc """
  Dialogue node type definition.

  The primary conversation node. Supports speaker, text, stage directions,
  responses, audio, and technical fields.

  Also contains all dialogue-specific event handlers:
  - Response CRUD (add, remove, update text/condition/instruction)
  - Technical ID generation
  - Open screenplay mode
  """

  use Gettext, backend: StoryarnWeb.Gettext

  import Phoenix.Component, only: [assign: 3]

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Components.NodeTypeHelpers
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  # -- Type metadata --

  def type, do: "dialogue"
  def icon_name, do: "message-square"
  def label, do: dgettext("flows", "Dialogue")

  def default_data do
    %{
      "speaker_sheet_id" => nil,
      "text" => "",
      "stage_directions" => "",
      "menu_text" => "",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => generate_localization_id(),
      "responses" => []
    }
  end

  @form_defaults %{
    "speaker_sheet_id" => "",
    "text" => "",
    "stage_directions" => "",
    "menu_text" => "",
    "audio_asset_id" => nil,
    "technical_id" => "",
    "localization_id" => "",
    "responses" => []
  }

  def extract_form_data(data) do
    Map.merge(@form_defaults, Map.take(data, Map.keys(@form_defaults)), fn
      _key, default, nil -> default
      _key, _default, value -> value
    end)
  end

  def on_select(_node, socket), do: socket

  @doc "Dialogue nodes open fullscreen editor on double-click."
  def on_double_click(_node), do: :editor

  def duplicate_data_cleanup(data) do
    data
    |> Map.put("technical_id", "")
    |> Map.put("localization_id", generate_localization_id())
  end

  # -- Response event handlers --

  @doc "Adds a response to a dialogue node."
  def handle_add_response(%{"node-id" => node_id}, socket) do
    # Pre-read to check if we need to migrate connections
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []
    new_id = "r#{length(responses) + 1}_#{:erlang.unique_integer([:positive])}"

    # If this is the first response, migrate existing "output" connections to new response ID
    if responses == [] do
      migrate_node_output_connections(node.id, "output", new_id)
    end

    response_number = length(responses) + 1

    NodeHelpers.persist_node_update(socket, node_id, fn data ->
      default_text = Gettext.dgettext(StoryarnWeb.Gettext, "flows", "Response %{n}", n: response_number)

      new_response = %{
        "id" => new_id,
        "text" => default_text,
        "condition" => nil,
        "instruction" => nil
      }

      Map.update(data, "responses", [new_response], &(&1 ++ [new_response]))
    end)
  end

  @doc "Removes a response from a dialogue node."
  def handle_remove_response(%{"response-id" => response_id, "node-id" => node_id}, socket) do
    # Pre-read to handle connection cleanup
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []
    remaining = Enum.reject(responses, fn r -> r["id"] == response_id end)

    # Clean up connections from the deleted response pin
    if remaining == [] do
      migrate_node_output_connections(node.id, response_id, "output")
    else
      delete_node_output_connections(node.id, response_id)
    end

    NodeHelpers.persist_node_update(socket, node_id, fn data ->
      Map.update(data, "responses", [], fn resps ->
        Enum.reject(resps, &(&1["id"] == response_id))
      end)
    end)
  end

  @doc "Updates response text."
  def handle_update_response_text(
        %{"response-id" => response_id, "node-id" => node_id, "value" => text},
        socket
      ) do
    update_response_field(socket, node_id, response_id, "text", text)
  end

  @doc "Updates response condition."
  def handle_update_response_condition(
        %{"response-id" => response_id, "node-id" => node_id, "value" => condition},
        socket
      ) do
    value = if condition == "", do: nil, else: condition
    update_response_field(socket, node_id, response_id, "condition", value)
  end

  @doc "Updates response instruction."
  def handle_update_response_instruction(
        %{"response-id" => response_id, "node-id" => node_id, "value" => instruction},
        socket
      ) do
    value = if instruction == "", do: nil, else: instruction
    update_response_field(socket, node_id, response_id, "instruction", value)
  end

  # -- Technical ID generation --

  @doc "Generates a technical ID for a dialogue node."
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node
    flow = socket.assigns.flow
    speaker_sheet_id = node.data["speaker_sheet_id"]
    speaker_name = get_speaker_name(socket, speaker_sheet_id)
    speaker_count = count_speaker_in_flow(flow, speaker_sheet_id, node.id)
    technical_id = generate_technical_id(flow.shortcut, speaker_name, speaker_count)

    NodeHelpers.update_node_field(socket, node.id, "technical_id", technical_id)
  end

  @doc "Opens fullscreen editor for the selected dialogue node."
  def handle_open_screenplay(socket) do
    if socket.assigns.selected_node && socket.assigns.selected_node.type == "dialogue" do
      {:noreply, assign(socket, :editing_mode, :editor)}
    else
      {:noreply, socket}
    end
  end

  # -- Private helpers --

  defp update_response_field(socket, node_id, response_id, field, value) do
    NodeHelpers.persist_node_update(socket, node_id, fn data ->
      Map.update(data, "responses", [], &set_response_field(&1, response_id, field, value))
    end)
  end

  defp set_response_field(responses, response_id, field, value) do
    Enum.map(responses, fn
      %{"id" => ^response_id} = resp -> Map.put(resp, field, value)
      resp -> resp
    end)
  end

  defp migrate_node_output_connections(node_id, from_pin, to_pin) do
    node_id
    |> Flows.get_outgoing_connections()
    |> Enum.filter(fn conn -> conn.source_pin == from_pin end)
    |> Enum.each(fn conn ->
      Flows.update_connection(conn, %{source_pin: to_pin})
    end)
  end

  defp delete_node_output_connections(node_id, pin) do
    node_id
    |> Flows.get_outgoing_connections()
    |> Enum.filter(fn conn -> conn.source_pin == pin end)
    |> Enum.each(fn conn ->
      Flows.delete_connection(conn)
    end)
  end

  defp get_speaker_name(_socket, nil), do: nil

  defp get_speaker_name(socket, speaker_sheet_id) do
    Enum.find_value(socket.assigns.all_sheets, fn sheet ->
      if to_string(sheet.id) == to_string(speaker_sheet_id), do: sheet.name
    end)
  end

  defp count_speaker_in_flow(flow, speaker_sheet_id, current_node_id) do
    flow = if Ecto.assoc_loaded?(flow.nodes), do: flow, else: Repo.preload(flow, :nodes)

    same_speaker_nodes =
      flow.nodes
      |> Enum.filter(fn node ->
        node.type == "dialogue" &&
          to_string(node.data["speaker_sheet_id"]) == to_string(speaker_sheet_id)
      end)
      |> Enum.sort_by(& &1.inserted_at)

    case Enum.find_index(same_speaker_nodes, &(&1.id == current_node_id)) do
      nil -> length(same_speaker_nodes) + 1
      index -> index + 1
    end
  end

  defp generate_technical_id(flow_slug, speaker_name, speaker_count) do
    flow_part = NodeTypeHelpers.normalize_for_id(flow_slug || "")
    speaker_part = NodeTypeHelpers.normalize_for_id(speaker_name || "")
    flow_part = if flow_part == "", do: "dlg", else: flow_part
    speaker_part = if speaker_part == "", do: "narrator", else: speaker_part
    "#{flow_part}_#{speaker_part}_#{speaker_count}"
  end

  defp generate_localization_id do
    suffix =
      :erlang.unique_integer([:positive])
      |> Integer.to_string(16)
      |> String.downcase()
      |> String.slice(0, 6)

    "dialogue.#{suffix}"
  end

end
