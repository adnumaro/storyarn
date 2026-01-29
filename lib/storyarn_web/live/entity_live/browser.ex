defmodule StoryarnWeb.EntityLive.Browser do
  @moduledoc """
  Entity browser sidebar component.

  Displays a collapsible tree view of entities grouped by type,
  with search functionality. Designed to be embedded in the flow editor.
  """
  use StoryarnWeb, :live_component

  alias Storyarn.Entities

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full flex flex-col bg-base-200 border-r border-base-300">
      <div class="p-3 border-b border-base-300">
        <h2 class="font-semibold text-sm mb-2">{gettext("Entities")}</h2>
        <input
          type="text"
          placeholder={gettext("Search...")}
          class="input input-sm input-bordered w-full"
          value={@search}
          phx-keyup="search"
          phx-debounce="200"
          phx-target={@myself}
          name="search"
        />
      </div>

      <div class="flex-1 overflow-y-auto p-2">
        <div :for={{type, templates} <- @grouped_entities} class="mb-2">
          <button
            type="button"
            class="flex items-center gap-1 w-full p-1 hover:bg-base-300 rounded text-sm font-medium"
            phx-click="toggle_type"
            phx-value-type={type}
            phx-target={@myself}
          >
            <.icon
              name={if type in @expanded_types, do: "hero-chevron-down", else: "hero-chevron-right"}
              class="size-3"
            />
            {String.capitalize(type)}
            <span class="badge badge-xs badge-ghost ml-auto">
              {count_entities(templates)}
            </span>
          </button>

          <div :if={type in @expanded_types} class="ml-3 mt-1">
            <div :for={template <- templates} class="mb-1">
              <button
                type="button"
                class="flex items-center gap-1 w-full p-1 hover:bg-base-300 rounded text-xs"
                phx-click="toggle_template"
                phx-value-template-id={template.id}
                phx-target={@myself}
              >
                <.icon
                  name={
                    if template.id in @expanded_templates,
                      do: "hero-chevron-down",
                      else: "hero-chevron-right"
                  }
                  class="size-3"
                />
                <.icon name={template.icon} class="size-3" style={"color: #{template.color}"} />
                {template.name}
                <span class="badge badge-xs badge-ghost ml-auto">
                  {length(template.entities)}
                </span>
              </button>

              <div :if={template.id in @expanded_templates} class="ml-4 mt-1">
                <.link
                  :for={entity <- template.entities}
                  navigate={~p"/projects/#{@project_id}/entities/#{entity.id}"}
                  class={[
                    "flex items-center gap-1 p-1 hover:bg-base-300 rounded text-xs",
                    @selected_entity_id == entity.id && "bg-primary/10"
                  ]}
                >
                  <span
                    class="size-2 rounded-full"
                    style={"background-color: #{entity.color || template.color}"}
                  />
                  <span class="truncate">{entity.display_name}</span>
                </.link>
                <p
                  :if={template.entities == []}
                  class="text-xs text-base-content/50 italic p-1"
                >
                  {gettext("No entities")}
                </p>
              </div>
            </div>
          </div>
        </div>

        <div :if={@grouped_entities == []} class="text-center py-4 text-base-content/50 text-xs">
          {gettext("No entities found")}
        </div>
      </div>

      <div class="p-2 border-t border-base-300">
        <.link
          navigate={~p"/projects/#{@project_id}/entities"}
          class="btn btn-ghost btn-xs btn-block"
        >
          {gettext("Manage Entities")}
        </.link>
      </div>
    </div>
    """
  end

  defp count_entities(templates) do
    Enum.reduce(templates, 0, fn t, acc -> acc + length(t.entities) end)
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:search, fn -> "" end)
      |> assign_new(:expanded_types, fn -> MapSet.new() end)
      |> assign_new(:expanded_templates, fn -> MapSet.new() end)
      |> assign_new(:selected_entity_id, fn -> nil end)
      |> load_entities()

    {:ok, socket}
  end

  defp load_entities(socket) do
    project_id = socket.assigns.project_id
    search = socket.assigns.search

    templates = Entities.list_templates(project_id)

    filter_opts = if search && search != "", do: [search: search], else: []
    all_entities = Entities.list_entities(project_id, filter_opts)

    entities_by_template =
      Enum.group_by(all_entities, & &1.template_id)

    templates_with_entities =
      Enum.map(templates, fn template ->
        entities = Map.get(entities_by_template, template.id, [])
        Map.put(template, :entities, entities)
      end)

    grouped =
      templates_with_entities
      |> Enum.group_by(& &1.type)
      |> Enum.sort_by(fn {type, _} -> type end)

    assign(socket, :grouped_entities, grouped)
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket =
      socket
      |> assign(:search, search)
      |> load_entities()

    {:noreply, socket}
  end

  def handle_event("toggle_type", %{"type" => type}, socket) do
    expanded = socket.assigns.expanded_types

    expanded =
      if MapSet.member?(expanded, type) do
        MapSet.delete(expanded, type)
      else
        MapSet.put(expanded, type)
      end

    {:noreply, assign(socket, :expanded_types, expanded)}
  end

  def handle_event("toggle_template", %{"template-id" => template_id}, socket) do
    template_id = String.to_integer(template_id)
    expanded = socket.assigns.expanded_templates

    expanded =
      if MapSet.member?(expanded, template_id) do
        MapSet.delete(expanded, template_id)
      else
        MapSet.put(expanded, template_id)
      end

    {:noreply, assign(socket, :expanded_templates, expanded)}
  end
end
