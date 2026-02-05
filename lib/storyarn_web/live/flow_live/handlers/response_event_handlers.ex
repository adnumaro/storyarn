defmodule StoryarnWeb.FlowLive.Handlers.ResponseEventHandlers do
  @moduledoc """
  Handles dialogue response events for the flow editor LiveView.

  Responsible for: add, remove, and update response text/condition/instruction.
  Delegates to NodeHelpers. Returns `{:noreply, socket}`.
  """

  alias StoryarnWeb.FlowLive.Helpers.ResponseHelpers

  @spec handle_add_response(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_add_response(%{"node-id" => node_id}, socket) do
    ResponseHelpers.add_response(socket, node_id)
  end

  @spec handle_remove_response(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_remove_response(%{"response-id" => response_id, "node-id" => node_id}, socket) do
    ResponseHelpers.remove_response(socket, node_id, response_id)
  end

  @spec handle_update_response_text(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_response_text(
        %{"response-id" => response_id, "node-id" => node_id, "value" => text},
        socket
      ) do
    ResponseHelpers.update_response_field(socket, node_id, response_id, "text", text)
  end

  @spec handle_update_response_condition(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_response_condition(
        %{"response-id" => response_id, "node-id" => node_id, "value" => condition},
        socket
      ) do
    value = if condition == "", do: nil, else: condition
    ResponseHelpers.update_response_field(socket, node_id, response_id, "condition", value)
  end

  @spec handle_update_response_instruction(map(), Phoenix.LiveView.Socket.t()) :: {:noreply, Phoenix.LiveView.Socket.t()}
  def handle_update_response_instruction(
        %{"response-id" => response_id, "node-id" => node_id, "value" => instruction},
        socket
      ) do
    value = if instruction == "", do: nil, else: instruction
    ResponseHelpers.update_response_field(socket, node_id, response_id, "instruction", value)
  end
end
