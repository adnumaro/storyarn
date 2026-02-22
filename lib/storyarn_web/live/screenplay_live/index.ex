defmodule StoryarnWeb.ScreenplayLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Screenplays

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      screenplays_tree={@screenplays_tree}
      active_tool={:screenplays}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays"}
      can_edit={@can_edit}
    >
      <div class="max-w-4xl mx-auto">
        <.header>
          {dgettext("screenplays", "Screenplays")}
          <:subtitle>
            {dgettext("screenplays", "Write and format screenplays with industry-standard formatting")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <.link
              patch={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/new"}
              class="btn btn-primary"
            >
              <.icon name="plus" class="size-4 mr-2" />
              {dgettext("screenplays", "New Screenplay")}
            </.link>
          </:actions>
        </.header>

        <.empty_state :if={@screenplays == []} icon="scroll-text">
          {dgettext("screenplays", "No screenplays yet. Create your first screenplay to get started.")}
        </.empty_state>

        <div :if={@screenplays != []} class="mt-6 space-y-2">
          <.screenplay_card
            :for={screenplay <- @screenplays}
            screenplay={screenplay}
            project={@project}
            workspace={@workspace}
            can_edit={@can_edit}
          />
        </div>

        <.modal
          :if={@live_action == :new and @can_edit}
          id="new-screenplay-modal"
          show
          on_cancel={
            JS.patch(~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays")
          }
        >
          <.live_component
            module={StoryarnWeb.ScreenplayLive.Form}
            id="new-screenplay-form"
            project={@project}
            title={dgettext("screenplays", "New Screenplay")}
            navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays"}
          />
        </.modal>

        <.confirm_modal
          :if={@can_edit}
          id="delete-screenplay-confirm"
          title={dgettext("screenplays", "Delete screenplay?")}
          message={dgettext("screenplays", "Are you sure you want to delete this screenplay?")}
          confirm_text={dgettext("screenplays", "Delete")}
          confirm_variant="error"
          icon="alert-triangle"
          on_confirm={JS.push("confirm_delete")}
        />
      </div>
    </Layouts.project>
    """
  end

  attr :screenplay, :map, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true
  attr :can_edit, :boolean, default: false

  defp screenplay_card(assigns) do
    ~H"""
    <div class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow">
      <div class="card-body p-4">
        <div class="flex items-center justify-between">
          <.link
            navigate={
              ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/screenplays/#{@screenplay.id}"
            }
            class="flex items-center gap-3 flex-1 min-w-0"
          >
            <div class="rounded-lg bg-primary/10 p-2">
              <.icon name="scroll-text" class="size-5 text-primary" />
            </div>
            <div class="flex-1 min-w-0">
              <h3 class="font-medium truncate">
                {@screenplay.name}
              </h3>
              <p :if={@screenplay.description} class="text-sm text-base-content/60 truncate">
                {@screenplay.description}
              </p>
            </div>
          </.link>
          <div :if={@can_edit} class="dropdown dropdown-end">
            <button
              type="button"
              tabindex="0"
              class="btn btn-ghost btn-sm btn-square"
              onclick="event.stopPropagation();"
            >
              <.icon name="more-horizontal" class="size-4" />
            </button>
            <ul
              tabindex="0"
              class="dropdown-content menu menu-sm bg-base-100 rounded-box shadow-lg border border-base-300 w-40 z-50"
            >
              <li>
                <button
                  type="button"
                  class="text-error"
                  phx-click={
                    JS.push("set_pending_delete", value: %{id: @screenplay.id})
                    |> show_modal("delete-screenplay-confirm")
                  }
                  onclick="event.stopPropagation();"
                >
                  <.icon name="trash-2" class="size-4" />
                  {dgettext("screenplays", "Delete")}
                </button>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(
        %{"workspace_slug" => workspace_slug, "project_slug" => project_slug},
        _session,
        socket
      ) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        project = Repo.preload(project, :workspace)
        screenplays = Screenplays.list_screenplays(project.id)
        screenplays_tree = Screenplays.list_screenplays_tree(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:screenplays, screenplays)
          |> assign(:screenplays_tree, screenplays_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("screenplays", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({StoryarnWeb.ScreenplayLive.Form, {:saved, screenplay}}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, dgettext("screenplays", "Screenplay created successfully."))
     |> push_navigate(
       to:
         ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{screenplay.id}"
     )}
  end

  @impl true
  def handle_event("set_pending_delete", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("set_pending_delete_screenplay", %{"id" => id}, socket) do
    {:noreply, assign(socket, :pending_delete_id, id)}
  end

  def handle_event("confirm_delete", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("confirm_delete_screenplay", _params, socket) do
    if id = socket.assigns[:pending_delete_id] do
      handle_event("delete", %{"id" => id}, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("delete", %{"id" => screenplay_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      screenplay = Screenplays.get_screenplay!(socket.assigns.project.id, screenplay_id)

      case Screenplays.delete_screenplay(screenplay) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(:info, dgettext("screenplays", "Screenplay moved to trash."))
           |> reload_screenplays()}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, dgettext("screenplays", "Could not delete screenplay."))}
      end
    end)
  end

  def handle_event("delete_screenplay", %{"id" => screenplay_id}, socket) do
    handle_event("delete", %{"id" => screenplay_id}, socket)
  end

  def handle_event("create_screenplay", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      case Screenplays.create_screenplay(socket.assigns.project, %{
             name: dgettext("screenplays", "Untitled")
           }) do
        {:ok, new_screenplay} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{new_screenplay.id}"
           )}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, dgettext("screenplays", "Could not create screenplay."))}
      end
    end)
  end

  def handle_event("create_child_screenplay", %{"parent-id" => parent_id}, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      attrs = %{name: dgettext("screenplays", "Untitled"), parent_id: parent_id}

      case Screenplays.create_screenplay(socket.assigns.project, attrs) do
        {:ok, new_screenplay} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/screenplays/#{new_screenplay.id}"
           )}

        {:error, _changeset} ->
          {:noreply,
           put_flash(socket, :error, dgettext("screenplays", "Could not create screenplay."))}
      end
    end)
  end

  def handle_event(
        "move_to_parent",
        %{"item_id" => item_id, "new_parent_id" => new_parent_id, "position" => position},
        socket
      ) do
    with_authorization(socket, :edit_content, fn socket ->
      screenplay = Screenplays.get_screenplay!(socket.assigns.project.id, item_id)
      new_parent_id = parse_int(new_parent_id)
      position = parse_int(position) || 0

      case Screenplays.move_screenplay_to_position(screenplay, new_parent_id, position) do
        {:ok, _} ->
          {:noreply, reload_screenplays(socket)}

        {:error, _} ->
          {:noreply,
           put_flash(socket, :error, dgettext("screenplays", "Could not move screenplay."))}
      end
    end)
  end

  defp parse_int(""), do: nil
  defp parse_int(nil), do: nil
  defp parse_int(val) when is_integer(val), do: val

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp reload_screenplays(socket) do
    project_id = socket.assigns.project.id

    socket
    |> assign(:screenplays, Screenplays.list_screenplays(project_id))
    |> assign(:screenplays_tree, Screenplays.list_screenplays_tree(project_id))
  end
end
