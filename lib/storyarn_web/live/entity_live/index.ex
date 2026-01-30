defmodule StoryarnWeb.EntityLive.Index do
  use StoryarnWeb, :live_view

  alias Storyarn.Entities
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} workspaces={@workspaces}>
      <div class="mb-8">
        <.back navigate={~p"/projects/#{@project.id}"}>{gettext("Back to project")}</.back>
      </div>

      <div class="text-center mb-8">
        <.header>
          {gettext("Entities")}
          <:subtitle>
            {gettext("Manage characters, locations, items, and custom entities")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <div class="dropdown dropdown-end">
              <div tabindex="0" role="button" class="btn btn-primary">
                <.icon name="hero-plus" class="size-4 mr-2" />
                {gettext("New Entity")}
              </div>
              <ul
                tabindex="0"
                class="dropdown-content z-[1] menu p-2 shadow bg-base-100 rounded-box w-52"
              >
                <li :for={template <- @templates}>
                  <.link patch={~p"/projects/#{@project.id}/entities/new?template_id=#{template.id}"}>
                    <.icon name={template.icon} class="size-4" style={"color: #{template.color}"} />
                    {template.name}
                  </.link>
                </li>
                <li :if={@templates == []}>
                  <.link
                    navigate={~p"/projects/#{@project.id}/templates"}
                    class="text-base-content/70"
                  >
                    {gettext("Create a template first")}
                  </.link>
                </li>
              </ul>
            </div>
          </:actions>
        </.header>
      </div>

      <div class="flex gap-4 mb-6">
        <div class="form-control flex-1">
          <input
            type="text"
            placeholder={gettext("Search entities...")}
            class="input input-bordered w-full"
            value={@search}
            phx-keyup="search"
            phx-debounce="300"
            name="search"
          />
        </div>
        <select
          class="select select-bordered"
          phx-change="filter_type"
          name="type"
        >
          <option value="">{gettext("All Types")}</option>
          <option
            :for={type <- Entities.EntityTemplate.types()}
            value={type}
            selected={@filter_type == type}
          >
            {String.capitalize(type)}
          </option>
        </select>
      </div>

      <.empty_state :if={@entities == []} icon="hero-cube-transparent">
        {gettext("No entities yet. Create your first entity to get started.")}
      </.empty_state>

      <div :if={@entities != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.entity_card
          :for={entity <- @entities}
          entity={entity}
          project={@project}
        />
      </div>

      <.modal
        :if={@live_action == :new}
        id="new-entity-modal"
        show
        on_cancel={JS.patch(~p"/projects/#{@project.id}/entities")}
      >
        <.live_component
          module={StoryarnWeb.EntityLive.Form}
          id="new-entity-form"
          project={@project}
          template={@selected_template}
          title={gettext("New Entity")}
          action={:new}
          can_edit={@can_edit}
          navigate={~p"/projects/#{@project.id}/entities"}
        />
      </.modal>
    </Layouts.app>
    """
  end

  attr :entity, :map, required: true
  attr :project, :map, required: true

  defp entity_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/projects/#{@project.id}/entities/#{@entity.id}"}
      class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow"
    >
      <div class="card-body">
        <div class="flex items-start justify-between gap-2">
          <div class="flex items-center gap-2">
            <.icon
              name={@entity.template.icon}
              class="size-5"
              style={"color: #{@entity.color || @entity.template.color}"}
            />
            <h3 class="card-title text-lg">{@entity.display_name}</h3>
          </div>
          <span class="badge badge-sm badge-ghost">
            {@entity.template.type}
          </span>
        </div>
        <p class="text-xs text-base-content/50 font-mono">{@entity.technical_name}</p>
        <p :if={@entity.description} class="text-sm text-base-content/70 line-clamp-2">
          {@entity.description}
        </p>
      </div>
    </.link>
    """
  end

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    case Projects.authorize(socket.assigns.current_scope, project_id, :view) do
      {:ok, project, membership} ->
        templates = Entities.list_templates(project.id)
        entities = Entities.list_entities(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:templates, templates)
          |> assign(:entities, entities)
          |> assign(:search, "")
          |> assign(:filter_type, nil)
          |> assign(:selected_template, nil)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, params) do
    template_id = params["template_id"]

    selected_template =
      if template_id do
        Entities.get_template(socket.assigns.project.id, template_id)
      else
        Enum.at(socket.assigns.templates, 0)
      end

    assign(socket, :selected_template, selected_template)
  end

  defp apply_action(socket, _action, _params) do
    socket
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    socket = filter_entities(socket, search: search)
    {:noreply, socket}
  end

  def handle_event("filter_type", %{"type" => type}, socket) do
    type = if type == "", do: nil, else: type
    socket = filter_entities(socket, type: type)
    {:noreply, socket}
  end

  defp filter_entities(socket, opts) do
    search = Keyword.get(opts, :search, socket.assigns.search)
    type = Keyword.get(opts, :type, socket.assigns.filter_type)

    filter_opts =
      []
      |> then(fn opts ->
        if search && search != "", do: [{:search, search} | opts], else: opts
      end)
      |> then(fn opts -> if type, do: [{:type, type} | opts], else: opts end)

    entities = Entities.list_entities(socket.assigns.project.id, filter_opts)

    socket
    |> assign(:entities, entities)
    |> assign(:search, search)
    |> assign(:filter_type, type)
  end

  @impl true
  def handle_info({StoryarnWeb.EntityLive.Form, {:saved, entity}}, socket) do
    socket =
      socket
      |> put_flash(:info, gettext("Entity created successfully."))
      |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/entities/#{entity.id}")

    {:noreply, socket}
  end
end
