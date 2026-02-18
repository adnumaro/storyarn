defmodule StoryarnWeb.FlowLive.PreviewComponent do
  @moduledoc """
  LiveComponent for previewing dialogue flows.

  Walks through connected dialogue nodes, showing speaker, text, and response options.
  """

  use StoryarnWeb, :live_component

  alias Storyarn.Flows
  alias Storyarn.Sheets

  # Maximum traversal depth to prevent infinite loops in cyclic flows
  @max_traversal_depth 50

  # Allowed HTML tags from TipTap rich text editor output
  @allowed_tags ~w(p br b i em strong u s del a ul ol li h1 h2 h3 h4 h5 h6 blockquote pre code span div)

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
              <h3 class="font-semibold text-lg">{@speaker || dgettext("flows", "Narrator")}</h3>
              <p class="text-xs text-base-content/60">
                {dgettext("flows", "Node %{id}", id: @current_node.id)}
              </p>
            </div>
          </div>

          <%!-- Dialogue text --%>
          <div class="prose prose-sm max-w-none bg-base-200 rounded-lg p-4">
            {raw(sanitize_and_interpolate(@current_node.data["text"] || ""))}
          </div>

          <%!-- Response buttons --%>
          <div :if={@responses != []} class="space-y-2">
            <p class="text-sm font-medium text-base-content/70">{dgettext("flows", "Responses:")}</p>
            <div class="flex flex-col gap-2">
              <button
                :for={response <- @responses}
                type="button"
                phx-click="select_response"
                phx-value-response-id={response["id"]}
                phx-target={@myself}
                class="btn btn-outline btn-sm justify-start text-left h-auto py-2"
              >
                <span class="flex-1">{raw(sanitize_and_interpolate(response["text"] || ""))}</span>
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
              {dgettext("flows", "Continue")}
              <.icon name="arrow-right" class="size-4 ml-1" />
            </button>
          </div>

          <%!-- End of flow --%>
          <div :if={@responses == [] && !@has_next} class="pt-2">
            <div class="alert alert-info">
              <.icon name="info" class="size-5" />
              <span>{dgettext("flows", "End of dialogue branch")}</span>
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
              {dgettext("flows", "Back")}
            </button>
            <div :if={@history == []}></div>

            <button
              type="button"
              phx-click="close_preview"
              phx-target={@myself}
              class="btn btn-ghost btn-sm"
            >
              {dgettext("flows", "Close")}
            </button>
          </div>
        </div>

        <div :if={!@current_node && @show} class="text-center py-8">
          <p class="text-base-content/60">{dgettext("flows", "No node selected for preview.")}</p>
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
      skip_to_next_dialogue(socket, node, MapSet.new(), 0)
    end
  end

  defp load_dialogue_node(socket, node) do
    speaker_name = resolve_speaker(socket.assigns, node.data["speaker_sheet_id"])
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

  defp skip_to_next_dialogue(socket, _node, _visited, depth)
       when depth >= @max_traversal_depth do
    assign_empty_node(socket)
  end

  defp skip_to_next_dialogue(socket, %{type: "jump"} = node, visited, depth) do
    if MapSet.member?(visited, node.id) do
      assign_empty_node(socket)
    else
      visited = MapSet.put(visited, node.id)
      follow_jump_target(socket, node, visited, depth)
    end
  end

  defp skip_to_next_dialogue(socket, node, visited, depth) do
    if MapSet.member?(visited, node.id) do
      assign_empty_node(socket)
    else
      visited = MapSet.put(visited, node.id)
      follow_first_connection(socket, node, visited, depth)
    end
  end

  defp follow_jump_target(socket, node, visited, depth) do
    target_hub_id = node.data["target_hub_id"]

    if target_hub_id && target_hub_id != "" do
      case Flows.get_hub_by_hub_id(node.flow_id, target_hub_id) do
        nil -> assign_empty_node(socket)
        hub -> skip_to_next_dialogue(socket, hub, visited, depth + 1)
      end
    else
      assign_empty_node(socket)
    end
  end

  defp follow_first_connection(socket, node, visited, depth) do
    connections = Flows.get_outgoing_connections(node.id)

    case List.first(connections) do
      nil ->
        assign_empty_node(socket)

      next_conn ->
        next_node = Flows.get_node_by_id!(next_conn.target_node_id)
        load_or_skip(socket, next_node, visited, depth)
    end
  end

  defp load_or_skip(socket, %{type: "dialogue"} = node, _visited, _depth) do
    load_dialogue_node(socket, node)
  end

  defp load_or_skip(socket, node, visited, depth) do
    skip_to_next_dialogue(socket, node, visited, depth + 1)
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

  defp resolve_speaker(assigns, speaker_sheet_id)
       when is_integer(speaker_sheet_id) or is_binary(speaker_sheet_id) do
    sheet_id = parse_sheet_id(speaker_sheet_id)
    if sheet_id, do: lookup_speaker_name(assigns, sheet_id)
  end

  defp resolve_speaker(_assigns, _), do: nil

  defp parse_sheet_id(id) when is_integer(id), do: id

  defp parse_sheet_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp lookup_speaker_name(assigns, sheet_id) do
    sheets_map = Map.get(assigns, :sheets_map, %{})
    sheet_info = Map.get(sheets_map, to_string(sheet_id))

    if sheet_info do
      sheet_info.name
    else
      lookup_speaker_from_db(assigns.project.id, sheet_id)
    end
  end

  defp lookup_speaker_from_db(project_id, sheet_id) do
    case Sheets.get_sheet(project_id, sheet_id) do
      nil -> nil
      sheet -> sheet.name
    end
  end

  defp speaker_initials(nil), do: "?"

  defp speaker_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
  end

  defp sanitize_and_interpolate(""), do: ""

  defp sanitize_and_interpolate(text) when is_binary(text) do
    text
    |> sanitize_html()
    |> interpolate_variables()
  end

  defp sanitize_html(html) when is_binary(html) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        tree
        |> strip_unsafe_nodes()
        |> Floki.raw_html()

      _ ->
        Phoenix.HTML.html_escape(html) |> Phoenix.HTML.safe_to_string()
    end
  end

  defp strip_unsafe_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &strip_unsafe_node/1)
  end

  defp strip_unsafe_node({tag, attrs, children}) do
    if tag in @allowed_tags do
      safe_attrs = Enum.reject(attrs, fn {k, v} -> unsafe_attr?(k, v) end)
      [{tag, safe_attrs, strip_unsafe_nodes(children)}]
    else
      # Drop the tag but keep safe children (e.g., <script> is dropped, text inside kept for <div>)
      strip_unsafe_nodes(children)
    end
  end

  defp strip_unsafe_node(text) when is_binary(text), do: [text]
  defp strip_unsafe_node({:comment, _}), do: []
  defp strip_unsafe_node(_), do: []

  defp unsafe_attr?(name, _value) when is_binary(name) do
    downcased = String.downcase(name)
    String.starts_with?(downcased, "on") || downcased in ~w(srcdoc formaction)
  end

  defp unsafe_attr?(_name, value) when is_binary(value) do
    String.contains?(String.downcase(value), "javascript:")
  end

  defp unsafe_attr?(_name, _value), do: false

  defp interpolate_variables(text) when is_binary(text) do
    Regex.replace(~r/\{(\w+)\}/, text, fn _, var_name ->
      "<span class=\"badge badge-ghost badge-sm font-mono\">[#{var_name}]</span>"
    end)
  end
end
