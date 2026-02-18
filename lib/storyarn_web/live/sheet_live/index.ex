defmodule StoryarnWeb.SheetLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.SheetComponents

  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Sheets

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      sheets_tree={@sheets_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets"}
      can_edit={@can_edit}
    >
      <div class="text-center mb-8">
        <.header>
          {dgettext("sheets", "Sheets")}
          <:subtitle>
            {dgettext("sheets", "Create and organize your project's content")}
          </:subtitle>
          <:actions :if={@can_edit}>
            <button type="button" class="btn btn-primary" phx-click="create_sheet">
              <.icon name="plus" class="size-4 mr-2" />
              {dgettext("sheets", "New Sheet")}
            </button>
          </:actions>
        </.header>
      </div>

      <.empty_state :if={@sheets_tree == []} icon="file-text">
        {dgettext("sheets", "No sheets yet. Create your first sheet to get started.")}
      </.empty_state>

      <div :if={@sheets_tree != []} class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.sheet_card
          :for={sheet <- @sheets_tree}
          sheet={sheet}
          project={@project}
          workspace={@workspace}
        />
      </div>
    </Layouts.project>
    """
  end

  attr :sheet, :map, required: true
  attr :project, :map, required: true
  attr :workspace, :map, required: true

  defp sheet_card(assigns) do
    children_count = length(Map.get(assigns.sheet, :children, []))

    assigns = assign(assigns, :children_count, children_count)

    ~H"""
    <.link
      navigate={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/sheets/#{@sheet.id}"}
      class="card bg-base-100 border border-base-300 shadow-sm hover:shadow-md transition-shadow"
    >
      <div class="card-body">
        <div class="flex items-center gap-3">
          <.sheet_avatar avatar_asset={@sheet.avatar_asset} name={@sheet.name} size="lg" />
          <div>
            <h3 class="card-title text-lg">{@sheet.name}</h3>
            <p :if={@children_count > 0} class="text-sm text-base-content/50">
              {dngettext("sheets", "%{count} subsheet", "%{count} subsheets", @children_count)}
            </p>
          </div>
        </div>
      </div>
    </.link>
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
        sheets_tree = Sheets.list_sheets_tree(project.id)
        can_edit = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:sheets_tree, sheets_tree)

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("sheets", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("create_sheet", _params, socket) do
    if socket.assigns.can_edit do
      attrs = %{name: dgettext("sheets", "Untitled")}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          {:noreply,
           push_navigate(socket,
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("sheets", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("delete_sheet", %{"id" => sheet_id}, socket) do
    if socket.assigns.can_edit do
      sheet = Sheets.get_sheet!(socket.assigns.project.id, sheet_id)

      case Sheets.delete_sheet(sheet) do
        {:ok, _} ->
          sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

          {:noreply,
           socket
           |> put_flash(:info, dgettext("sheets", "Sheet deleted successfully."))
           |> assign(:sheets_tree, sheets_tree)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not delete sheet."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("sheets", "You don't have permission to perform this action."))}
    end
  end

  def handle_event(
        "move_sheet",
        %{"sheet_id" => sheet_id, "parent_id" => parent_id, "position" => position},
        socket
      ) do
    if socket.assigns.can_edit do
      sheet = Sheets.get_sheet!(socket.assigns.project.id, sheet_id)
      parent_id = normalize_parent_id(parent_id)
      position = parse_int(position) || 0

      case Sheets.move_sheet_to_position(sheet, parent_id, position) do
        {:ok, _sheet} ->
          sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)
          {:noreply, assign(socket, :sheets_tree, sheets_tree)}

        {:error, :would_create_cycle} ->
          {:noreply,
           put_flash(socket, :error, dgettext("sheets", "Cannot move a sheet into its own children."))}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not move sheet."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("sheets", "You don't have permission to perform this action."))}
    end
  end

  def handle_event("create_child_sheet", %{"parent-id" => parent_id}, socket) do
    if socket.assigns.can_edit do
      attrs = %{name: dgettext("sheets", "New Sheet"), parent_id: parent_id}

      case Sheets.create_sheet(socket.assigns.project, attrs) do
        {:ok, new_sheet} ->
          sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

          {:noreply,
           socket
           |> assign(:sheets_tree, sheets_tree)
           |> push_navigate(
             to:
               ~p"/workspaces/#{socket.assigns.workspace.slug}/projects/#{socket.assigns.project.slug}/sheets/#{new_sheet.id}"
           )}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, dgettext("sheets", "Could not create sheet."))}
      end
    else
      {:noreply,
       put_flash(socket, :error, dgettext("sheets", "You don't have permission to perform this action."))}
    end
  end
end
