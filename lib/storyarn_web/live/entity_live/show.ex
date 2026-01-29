defmodule StoryarnWeb.EntityLive.Show do
  use StoryarnWeb, :live_view

  alias Storyarn.Entities
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mb-8">
        <.back navigate={~p"/projects/#{@project.id}/entities"}>{gettext("Back to entities")}</.back>
      </div>

      <div class="text-center mb-8">
        <.header>
          <span class="flex items-center justify-center gap-2">
            <.icon
              name={@entity.template.icon}
              class="size-6"
              style={"color: #{@entity.color || @entity.template.color}"}
            />
            {@entity.display_name}
          </span>
          <:subtitle>
            <span class="font-mono text-sm">{@entity.technical_name}</span>
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link
              patch={~p"/projects/#{@project.id}/entities/#{@entity.id}/edit"}
              class="btn btn-ghost btn-sm"
            >
              <.icon name="hero-pencil" class="size-4 mr-1" />
              {gettext("Edit")}
            </.link>
            <button
              type="button"
              class="btn btn-ghost btn-sm text-error"
              phx-click="delete"
              data-confirm={gettext("Are you sure you want to delete this entity?")}
            >
              <.icon name="hero-trash" class="size-4 mr-1" />
              {gettext("Delete")}
            </button>
          </:actions>
        </.header>
      </div>

      <div class="max-w-2xl mx-auto">
        <div class="card bg-base-100 border border-base-300">
          <div class="card-body">
            <div class="flex items-center gap-2 mb-4">
              <span
                class="badge"
                style={"background-color: #{@entity.template.color}; color: white;"}
              >
                <.icon name={@entity.template.icon} class="size-3 mr-1" />
                {@entity.template.name}
              </span>
              <span class="badge badge-ghost">{@entity.template.type}</span>
            </div>

            <div :if={@entity.description} class="mb-6">
              <h3 class="text-sm font-medium text-base-content/70 mb-1">{gettext("Description")}</h3>
              <p class="whitespace-pre-wrap">{@entity.description}</p>
            </div>

            <div :if={@entity.data != %{}} class="mb-6">
              <h3 class="text-sm font-medium text-base-content/70 mb-2">
                {gettext("Custom Fields")}
              </h3>
              <dl class="grid grid-cols-2 gap-2">
                <div :for={{key, value} <- @entity.data} class="flex flex-col">
                  <dt class="text-xs text-base-content/50">{humanize_key(key)}</dt>
                  <dd class="font-medium">{format_value(value)}</dd>
                </div>
              </dl>
            </div>

            <div class="text-xs text-base-content/50 mt-4 pt-4 border-t border-base-300">
              <span>
                {gettext("Created")} {Calendar.strftime(@entity.inserted_at, "%b %d, %Y at %H:%M")}
              </span>
              <span class="mx-2">|</span>
              <span>
                {gettext("Updated")} {Calendar.strftime(@entity.updated_at, "%b %d, %Y at %H:%M")}
              </span>
            </div>
          </div>
        </div>
      </div>

      <.modal
        :if={@live_action == :edit}
        id="edit-entity-modal"
        show
        on_cancel={JS.patch(~p"/projects/#{@project.id}/entities/#{@entity.id}")}
      >
        <.live_component
          module={StoryarnWeb.EntityLive.Form}
          id="edit-entity-form"
          project={@project}
          template={@entity.template}
          entity={@entity}
          title={gettext("Edit Entity")}
          action={:edit}
          navigate={~p"/projects/#{@project.id}/entities/#{@entity.id}"}
        />
      </.modal>
    </Layouts.app>
    """
  end

  defp humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_value(value) when is_boolean(value), do: if(value, do: "Yes", else: "No")
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: inspect(value)

  @impl true
  def mount(%{"project_id" => project_id, "id" => entity_id}, _session, socket) do
    case Projects.authorize(socket.assigns.current_scope, project_id, :view) do
      {:ok, project, membership} ->
        case Entities.get_entity(project.id, entity_id) do
          nil ->
            {:ok,
             socket
             |> put_flash(:error, gettext("Entity not found."))
             |> redirect(to: ~p"/projects/#{project_id}/entities")}

          entity ->
            can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

            socket =
              socket
              |> assign(:project, project)
              |> assign(:entity, entity)
              |> assign(:can_edit, can_edit)

            {:ok, socket}
        end

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You don't have access to this project."))
         |> redirect(to: ~p"/projects")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Entities.delete_entity(socket.assigns.entity) do
      {:ok, _entity} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Entity deleted successfully."))
         |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/entities")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete entity."))}
    end
  end

  @impl true
  def handle_info({StoryarnWeb.EntityLive.Form, {:saved, entity}}, socket) do
    entity = Entities.get_entity!(socket.assigns.project.id, entity.id)

    socket =
      socket
      |> assign(:entity, entity)
      |> put_flash(:info, gettext("Entity updated successfully."))
      |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/entities/#{entity.id}")

    {:noreply, socket}
  end
end
