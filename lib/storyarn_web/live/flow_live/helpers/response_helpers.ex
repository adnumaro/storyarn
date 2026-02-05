defmodule StoryarnWeb.FlowLive.Helpers.ResponseHelpers do
  @moduledoc """
  Response operation helpers for dialogue nodes in the flow editor.

  Handles add, remove, and field updates for dialogue responses.
  Returns `{:noreply, socket}` tuples.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Helpers.FormHelpers

  import StoryarnWeb.FlowLive.Helpers.SocketHelpers

  @doc """
  Adds a response to a dialogue node.
  Returns {:noreply, socket} tuple.
  """
  @spec add_response(Phoenix.LiveView.Socket.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def add_response(socket, node_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []

    new_id = "r#{length(responses) + 1}_#{:erlang.unique_integer([:positive])}"
    new_response = %{"id" => new_id, "text" => "", "condition" => nil, "instruction" => nil}
    updated_data = Map.put(node.data, "responses", responses ++ [new_response])

    # If this is the first response, migrate existing "output" connections to new response ID
    if responses == [] do
      migrate_node_output_connections(node.id, "output", new_id)
    end

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Removes a response from a dialogue node.
  Returns {:noreply, socket} tuple.
  """
  @spec remove_response(Phoenix.LiveView.Socket.t(), any(), String.t()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def remove_response(socket, node_id, response_id) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []
    updated_responses = Enum.reject(responses, fn r -> r["id"] == response_id end)
    updated_data = Map.put(node.data, "responses", updated_responses)

    # If removing the last response, migrate its connection back to "output"
    if updated_responses == [] do
      migrate_node_output_connections(node.id, response_id, "output")
    end

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node} ->
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> reload_flow_data()
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @doc """
  Updates a response field (text, condition, or instruction) in a dialogue node.
  Returns {:noreply, socket} tuple.
  """
  @spec update_response_field(Phoenix.LiveView.Socket.t(), any(), String.t(), String.t(), any()) ::
          {:noreply, Phoenix.LiveView.Socket.t()}
  def update_response_field(socket, node_id, response_id, field, value) do
    node = Flows.get_node!(socket.assigns.flow.id, node_id)
    responses = node.data["responses"] || []

    updated_responses = update_response_in_list(responses, response_id, field, value)
    updated_data = Map.put(node.data, "responses", updated_responses)

    case Flows.update_node_data(node, updated_data) do
      {:ok, updated_node} ->
        flow = Flows.get_flow!(socket.assigns.project.id, socket.assigns.flow.id)
        flow_data = Flows.serialize_for_canvas(flow)
        form = FormHelpers.node_data_to_form(updated_node)
        schedule_save_status_reset()

        {:noreply,
         socket
         |> assign(:flow, flow)
         |> assign(:flow_data, flow_data)
         |> assign(:selected_node, updated_node)
         |> assign(:node_form, form)
         |> assign(:save_status, :saved)
         |> push_event("node_updated", %{id: node_id, data: updated_node.data})}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Private functions

  defp update_response_in_list(responses, response_id, field, value) do
    Enum.map(responses, fn r ->
      if r["id"] == response_id, do: Map.put(r, field, value), else: r
    end)
  end

  # Migrates outgoing connections from one source_pin to another.
  # Used when adding/removing responses to keep connections valid.
  defp migrate_node_output_connections(node_id, from_pin, to_pin) do
    node_id
    |> Flows.get_outgoing_connections()
    |> Enum.filter(fn conn -> conn.source_pin == from_pin end)
    |> Enum.each(fn conn ->
      Flows.update_connection(conn, %{source_pin: to_pin})
    end)
  end
end
