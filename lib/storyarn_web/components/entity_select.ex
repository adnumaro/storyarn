defmodule StoryarnWeb.Components.EntitySelect do
  @moduledoc """
  Self-contained LiveComponent for selecting project entities (sheets, flows, scenes).

  Loads entities lazily with server-side search and infinite scroll (load more).
  The selected entity name is resolved independently from the list.

  ## Communication

      send(self(), {:entity_selected, component_id, selected_id_or_nil})

  ## Usage

      <.live_component
        module={StoryarnWeb.Components.EntitySelect}
        id="pin-sheet-123"
        project_id={@project.id}
        entity_type={:sheet}
        selected_id={@pin.sheet_id}
        label={dgettext("scenes", "Sheet")}
        placeholder={dgettext("scenes", "Select sheet...")}
        disabled={!@can_edit}
      />
  """

  use StoryarnWeb, :live_component
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Flows
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  @page_size 20

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       entities: [],
       selected_name: nil,
       query: "",
       has_more: false,
       _source_key: nil
     )}
  end

  @impl true
  def update(assigns, socket) do
    # Track the data source key to avoid re-fetching on every parent re-render.
    # Only re-fetch when project_id or entity_type actually change.
    source_key = {assigns[:project_id], assigns[:entity_type]}
    prev_source_key = socket.assigns[:_source_key]
    prev_selected = socket.assigns[:selected_id]

    socket = assign(socket, assigns)

    socket =
      if source_key != prev_source_key do
        entities = search(assigns.entity_type, assigns.project_id, "", 0)
        has_more = length(entities) >= @page_size

        socket
        |> assign(:_source_key, source_key)
        |> assign(:entities, entities)
        |> assign(:query, "")
        |> assign(:has_more, has_more)
      else
        socket
      end

    socket =
      if assigns[:selected_id] != prev_selected do
        name = resolve_selected_name(socket.assigns)
        assign(socket, :selected_name, name)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:allow_none, fn -> true end)
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:label, fn -> nil end)
      |> assign_new(:placeholder, fn -> gettext("Select...") end)

    ~H"""
    <div>
      <label :if={@label} class="block text-xs font-medium text-base-content/60 mb-1">
        {@label}
      </label>
      <div
        id={@id}
        phx-hook="EntitySelect"
        data-phx-target={"##{@id}"}
        data-selected={if @selected_id, do: to_string(@selected_id), else: ""}
        data-active-class="bg-base-content/10 font-semibold text-primary"
        data-version={length(@entities)}
      >
        <button
          data-role="trigger"
          type="button"
          class="btn btn-ghost btn-sm w-full justify-between border border-base-300 bg-base-100 font-normal"
          disabled={@disabled}
        >
          <span class="min-w-0 truncate text-sm">
            {if @selected_name, do: @selected_name, else: @placeholder}
          </span>
          <.icon name="chevron-down" class="size-3 shrink-0 opacity-50" />
        </button>

        <%!-- Source div: LiveView patches this. Hook reads it on updated(). --%>
        <div data-role="popover-source" style="display:none">
          <div class="p-2 pb-1">
            <input
              data-role="search"
              type="text"
              placeholder={search_placeholder(@entity_type)}
              class="input input-xs input-bordered w-full"
              autocomplete="off"
            />
          </div>
          <div data-role="list" class="max-h-56 overflow-y-auto p-1">
            <button
              :if={@allow_none}
              type="button"
              data-event="select_entity"
              data-params={Jason.encode!(%{"id" => ""})}
              data-value=""
              data-search-text=""
              class="flex w-full items-center rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
            >
              {gettext("None")}
            </button>
            <button
              :for={entity <- @entities}
              type="button"
              data-event="select_entity"
              data-params={Jason.encode!(%{"id" => to_string(entity.id)})}
              data-value={to_string(entity.id)}
              data-search-text={String.downcase(entity.name)}
              class="flex w-full items-center rounded px-2 py-1.5 text-left text-xs hover:bg-base-content/10"
            >
              {entity.name}
            </button>
            <div
              :if={@has_more}
              data-role="sentinel"
              class="flex items-center justify-center py-2"
            >
              <span class="loading loading-spinner loading-xs text-base-content/30"></span>
            </div>
          </div>
          <div
            data-role="empty"
            class="px-3 py-2 text-xs italic text-base-content/40"
            style={if @entities != [] or @allow_none, do: "display:none"}
          >
            {gettext("No matches")}
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_entity", %{"id" => id}, socket) do
    parsed_id = if id == "", do: nil, else: String.to_integer(id)
    send(self(), {:entity_selected, socket.assigns.id, parsed_id})

    name =
      if parsed_id do
        find_in_list(socket.assigns.entities, parsed_id) ||
          get_entity_name(socket.assigns.entity_type, socket.assigns.project_id, parsed_id)
      end

    {:noreply, assign(socket, selected_id: parsed_id, selected_name: name)}
  end

  def handle_event("search_entities", %{"query" => query}, socket) do
    entities = search(socket.assigns.entity_type, socket.assigns.project_id, query, 0)
    has_more = length(entities) >= @page_size

    {:noreply,
     socket
     |> assign(:entities, entities)
     |> assign(:query, query)
     |> assign(:has_more, has_more)}
  end

  def handle_event("load_more", _params, socket) do
    offset = length(socket.assigns.entities)

    more =
      search(socket.assigns.entity_type, socket.assigns.project_id, socket.assigns.query, offset)

    has_more = length(more) >= @page_size

    {:noreply,
     socket
     |> assign(:entities, socket.assigns.entities ++ more)
     |> assign(:has_more, has_more)}
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp search(:sheet, project_id, query, offset) do
    Sheets.search_sheets(project_id, query, limit: @page_size, offset: offset)
  end

  defp search(:flow, project_id, query, offset) do
    Flows.search_flows(project_id, query, limit: @page_size, offset: offset)
  end

  defp search(:scene, project_id, query, offset) do
    Scenes.search_scenes(project_id, query, limit: @page_size, offset: offset)
  end

  defp get_entity_name(type, project_id, id) do
    import Ecto.Query, only: [from: 2]

    schema = entity_schema(type)

    from(e in schema,
      where: e.id == ^id and e.project_id == ^project_id and is_nil(e.deleted_at),
      select: e.name
    )
    |> Storyarn.Repo.one()
  end

  defp entity_schema(:sheet), do: Storyarn.Sheets.Sheet
  defp entity_schema(:flow), do: Storyarn.Flows.Flow
  defp entity_schema(:scene), do: Storyarn.Scenes.Scene

  defp find_in_list(entities, id) do
    case Enum.find(entities, &(&1.id == id)) do
      nil -> nil
      entity -> entity.name
    end
  end

  defp resolve_selected_name(%{selected_id: nil}), do: nil

  defp resolve_selected_name(%{entities: entities, selected_id: id} = assigns) do
    find_in_list(entities, id) ||
      get_entity_name(assigns.entity_type, assigns.project_id, id)
  end

  defp search_placeholder(:sheet), do: dgettext("scenes", "Search sheets...")
  defp search_placeholder(:flow), do: dgettext("scenes", "Search flows...")
  defp search_placeholder(:scene), do: dgettext("scenes", "Search scenes...")
  defp search_placeholder(_), do: gettext("Search...")
end
