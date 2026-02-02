defmodule StoryarnWeb.FlowLive.PreviewComponent do
  @moduledoc """
  LiveComponent for previewing dialogue flows.

  Walks through connected dialogue nodes, showing speaker, text, and response options.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Flows
  alias Storyarn.Pages

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal id="preview-modal" show={@show} on_cancel={hide_modal("preview-modal")}>
        <div :if={@current_node} class="space-y-4">
          <%!-- Header with speaker info --%>
          <div class="flex items-center gap-3">
            <div class="avatar placeholder">
              <div class="bg-primary text-primary-content rounded-full w-12">
                <span class="text-lg">{speaker_initials(@speaker)}</span>
              </div>
            </div>
            <div>
              <h3 class="font-semibold text-lg">{@speaker || gettext("Narrator")}</h3>
              <p class="text-xs text-base-content/60">
                {gettext("Node %{id}", id: @current_node.id)}
              </p>
            </div>
          </div>

          <%!-- Dialogue text --%>
          <div class="prose prose-sm max-w-none bg-base-200 rounded-lg p-4">
            {raw(interpolate_variables(@current_node.data["text"] || ""))}
          </div>

          <%!-- Response buttons --%>
          <div :if={@responses != []} class="space-y-2">
            <p class="text-sm font-medium text-base-content/70">{gettext("Responses:")}</p>
            <div class="flex flex-col gap-2">
              <button
                :for={response <- @responses}
                type="button"
                phx-click="select_response"
                phx-value-response-id={response["id"]}
                phx-target={@myself}
                class="btn btn-outline btn-sm justify-start text-left h-auto py-2"
              >
                <span class="flex-1">{interpolate_variables(response["text"])}</span>
                <span
                  :if={response["condition"]}
                  class="badge badge-warning badge-xs ml-2"
                  title={response["condition"]}
                >
                  ?
                </span>
              </button>
            </div>
          </div>

          <%!-- Continue button for dialogues without responses --%>
          <div :if={@responses == [] && @has_next} class="pt-2">
            <button
              type="button"
              phx-click="continue"
              phx-target={@myself}
              class="btn btn-primary btn-sm w-full"
            >
              {gettext("Continue")}
              <.icon name="arrow-right" class="size-4 ml-1" />
            </button>
          </div>

          <%!-- End of flow --%>
          <div :if={@responses == [] && !@has_next} class="pt-2">
            <div class="alert alert-info">
              <.icon name="info" class="size-5" />
              <span>{gettext("End of dialogue branch")}</span>
            </div>
          </div>

          <%!-- Navigation --%>
          <div class="flex justify-between pt-4 border-t border-base-300">
            <button
              :if={@history != []}
              type="button"
              phx-click="go_back"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="arrow-left" class="size-4 mr-1" />
              {gettext("Back")}
            </button>
            <div :if={@history == []}></div>

            <button
              type="button"
              phx-click="close_preview"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              {gettext("Close")}
            </button>
          </div>
        </div>

        <div :if={!@current_node && @show} class="text-center py-8">
          <p class="text-base-content/60">{gettext("No node selected for preview.")}</p>
        </div>
      </.modal>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    # Initialize state when starting preview
    socket =
      if assigns[:start_node] && assigns[:start_node] != socket.assigns[:start_node] do
        load_node(socket, assigns.start_node)
      else
        socket
      end

    # Ensure all assigns have defaults
    socket =
      socket
      |> assign_new(:current_node, fn -> nil end)
      |> assign_new(:speaker, fn -> nil end)
      |> assign_new(:responses, fn -> [] end)
      |> assign_new(:has_next, fn -> false end)
      |> assign_new(:history, fn -> [] end)
      |> assign_new(:show, fn -> false end)

    {:ok, socket}
  end

  @impl true
  def handle_event("select_response", %{"response-id" => response_id}, socket) do
    # Find the connection for this response
    current_node = socket.assigns.current_node
    connections = Flows.get_outgoing_connections(current_node.id)

    # Find connection with matching source_pin (response_id)
    next_connection = Enum.find(connections, fn conn -> conn.source_pin == response_id end)

    if next_connection do
      # Add current node to history
      history = [current_node.id | socket.assigns.history]
      next_node = Flows.get_node_by_id!(next_connection.target_node_id)

      socket =
        socket
        |> assign(:history, history)
        |> load_node(next_node)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("continue", _params, socket) do
    current_node = socket.assigns.current_node
    connections = Flows.get_outgoing_connections(current_node.id)

    # For dialogue without responses, follow the default "output" connection
    next_connection = Enum.find(connections, fn conn -> conn.source_pin == "output" end)

    if next_connection do
      history = [current_node.id | socket.assigns.history]
      next_node = Flows.get_node_by_id!(next_connection.target_node_id)

      socket =
        socket
        |> assign(:history, history)
        |> load_node(next_node)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("go_back", _params, socket) do
    case socket.assigns.history do
      [prev_node_id | rest] ->
        prev_node = Flows.get_node_by_id!(prev_node_id)

        socket =
          socket
          |> assign(:history, rest)
          |> load_node(prev_node)

        {:noreply, socket}

      [] ->
        {:noreply, socket}
    end
  end

  def handle_event("close_preview", _params, socket) do
    send(self(), {:close_preview})
    {:noreply, socket}
  end

  # Private functions

  defp load_node(socket, node) do
    if node.type == "dialogue" do
      load_dialogue_node(socket, node)
    else
      skip_to_next_dialogue(socket, node)
    end
  end

  defp load_dialogue_node(socket, node) do
    speaker_name = resolve_speaker(socket.assigns, node.data["speaker_page_id"])
    responses = node.data["responses"] || []
    connections = Flows.get_outgoing_connections(node.id)
    has_next = responses == [] && has_output_connection?(connections)

    assign(socket,
      current_node: node,
      speaker: speaker_name,
      responses: responses,
      has_next: has_next
    )
  end

  defp skip_to_next_dialogue(socket, node) do
    connections = Flows.get_outgoing_connections(node.id)

    case List.first(connections) do
      nil -> assign_empty_node(socket)
      next_conn -> load_node(socket, Flows.get_node_by_id!(next_conn.target_node_id))
    end
  end

  defp assign_empty_node(socket) do
    assign(socket,
      current_node: nil,
      speaker: nil,
      responses: [],
      has_next: false
    )
  end

  defp has_output_connection?(connections) do
    Enum.any?(connections, fn conn -> conn.source_pin == "output" end)
  end

  defp resolve_speaker(assigns, speaker_page_id) when is_integer(speaker_page_id) do
    # Try to get from pages_map first
    pages_map = Map.get(assigns, :pages_map, %{})
    page_info = Map.get(pages_map, to_string(speaker_page_id))

    if page_info do
      page_info.name
    else
      # Fallback to database lookup
      project_id = assigns.project.id

      case Pages.get_page(project_id, speaker_page_id) do
        nil -> nil
        page -> page.name
      end
    end
  end

  defp resolve_speaker(_assigns, _), do: nil

  defp speaker_initials(nil), do: "?"

  defp speaker_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp interpolate_variables(nil), do: ""

  defp interpolate_variables(text) when is_binary(text) do
    # Replace {var_name} with [var_name] placeholder
    Regex.replace(~r/\{(\w+)\}/, text, fn _, var_name ->
      "<span class=\"badge badge-ghost badge-sm font-mono\">[#{var_name}]</span>"
    end)
  end
end
