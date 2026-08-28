defmodule StoryarnWeb.FlowLive.Nodes.Dialogue.Node do
  @moduledoc """
  Dialogue node type definition.

  The primary conversation node. Supports speaker, text, stage directions,
  responses, audio, and technical fields.

  Also contains all dialogue-specific event handlers:
  - Response CRUD (add, remove, update text/condition/instruction)
  - Technical ID generation
  - Open the dialogue editor panel
  """

  use Gettext, backend: Storyarn.Gettext

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.NodeHelpers

  # -- Type metadata --

  def type, do: "dialogue"
  def icon_name, do: "message-square"
  def label, do: dgettext("flows", "Dialogue")
  def description, do: dgettext("flows", "Character speech and player responses")

  def default_data, do: Flows.default_node_data(type())
  def extract_form_data(data), do: Flows.node_form_data(type(), data)

  def on_select(_node, socket), do: socket

  @doc "Dialogue nodes open the dialogue panel on double-click."
  def on_double_click(_node), do: :dialogue_panel

  def duplicate_data_cleanup(data), do: Flows.duplicate_node_data(type(), data)

  # -- Response event handlers --

  @doc "Adds a response to a dialogue node."
  def handle_add_response(%{"node-id" => node_id}, socket) do
    NodeHelpers.persist_node_update(socket, node_id, :append_dialogue_response)
  end

  @doc "Removes a response from a dialogue node."
  def handle_remove_response(%{"response-id" => response_id, "node-id" => node_id}, socket) do
    NodeHelpers.persist_node_update(socket, node_id, :remove_dialogue_response, %{
      response_id: response_id
    })
  end

  @doc "Updates response text."
  def handle_update_response_text(%{"response-id" => response_id, "node-id" => node_id, "value" => text}, socket) do
    update_response(socket, node_id, :put_response_text, response_id, text)
  end

  @doc "Updates response condition."
  def handle_update_response_condition(
        %{"response-id" => response_id, "node-id" => node_id, "value" => condition},
        socket
      ) do
    update_response(socket, node_id, :put_response_condition, response_id, condition)
  end

  @doc "Updates response instruction (legacy plain text)."
  def handle_update_response_instruction(
        %{"response-id" => response_id, "node-id" => node_id, "value" => instruction},
        socket
      ) do
    update_response(socket, node_id, :put_response_instruction, response_id, instruction)
  end

  @doc "Updates response instruction assignments (structured builder data)."
  def handle_update_response_instruction_builder(
        %{"assignments" => assignments, "response-id" => response_id, "node-id" => node_id},
        socket
      ) do
    update_response(socket, node_id, :put_response_assignments, response_id, assignments)
  end

  # -- Technical ID generation --

  @doc "Generates a technical ID for a dialogue node."
  def handle_generate_technical_id(socket) do
    node = socket.assigns.selected_node
    NodeHelpers.persist_node_update(socket, node.id, :generate_technical_id)
  end

  @doc """
  Opens the dialogue panel for a dialogue node.

  Uses `selected_node` if it's already the correct node. Falls back to looking
  up the node by `params["id"]` — needed when `close_editor` was called between
  the last selection and this event (race condition via context menu / shortcut).
  """
  def handle_open_dialogue_panel(params, socket) do
    node =
      cond do
        socket.assigns.selected_node &&
            socket.assigns.selected_node.type == "dialogue" ->
          socket.assigns.selected_node

        is_binary(params["id"]) ->
          Flows.get_node(socket.assigns.flow.id, params["id"])

        true ->
          nil
      end

    if node && node.type == "dialogue" do
      socket =
        socket
        |> assign(:selected_node, node)
        |> assign(:editing_mode, :dialogue_panel)
        |> assign(
          :dialogue_panel_data,
          StoryarnWeb.FlowLive.Handlers.GenericNodeHandlers.build_dialogue_panel_data(
            socket,
            node
          )
        )
        |> push_event("center_on_node", %{id: node.id})

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  # -- Private helpers --

  defp update_response(socket, node_id, operation, response_id, value) do
    NodeHelpers.persist_node_update(socket, node_id, operation, %{
      response_id: response_id,
      value: value
    })
  end
end
