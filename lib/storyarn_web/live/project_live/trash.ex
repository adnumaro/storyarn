defmodule StoryarnWeb.ProjectLive.Trash do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      socket={@socket}
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:sheets}
      has_tree={false}
    >
      <.vue
        v-component="modules/project-settings/Trash"
        v-socket={@socket}
        id="project-trash-vue"
        trashed-sheets={serialize_trashed_sheets(@trashed_sheets)}
        can-manage={@can_manage}
      />
    </Layouts.app>
    """
  end

  defp serialize_trashed_sheets(sheets) do
    Enum.map(sheets, fn sheet ->
      %{
        id: sheet.id,
        name: sheet.name,
        deleted_at: sheet.deleted_at && DateTime.to_iso8601(sheet.deleted_at)
      }
    end)
  end

  @impl true
  def mount(%{"workspace_slug" => workspace_slug, "project_slug" => project_slug}, _session, socket) do
    case Projects.get_project_by_slugs(
           socket.assigns.current_scope,
           workspace_slug,
           project_slug
         ) do
      {:ok, project, membership} ->
        trashed_sheets = Sheets.list_trashed_sheets(project.id)
        can_manage = Projects.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:current_workspace, project.workspace)
          |> assign(:trashed_sheets, trashed_sheets)
          |> assign(:can_manage, can_manage)
          |> assign(:sheet_to_delete, nil)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("projects", "Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_event("restore_sheet", %{"id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_restore_sheet(socket, id)
    end)
  end

  def handle_event("show_delete_confirm", %{"id" => id}, socket) do
    {:noreply, assign(socket, :sheet_to_delete, id)}
  end

  def handle_event("confirm_delete_permanently", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      if socket.assigns.sheet_to_delete do
        do_delete_permanently(socket, socket.assigns.sheet_to_delete)
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("empty_trash", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_empty_trash(socket)
    end)
  end

  defp do_restore_sheet(socket, id) do
    sheet = Sheets.get_trashed_sheet(socket.assigns.project.id, id)

    if sheet do
      case Sheets.restore_sheet(sheet) do
        {:ok, _sheet} ->
          trashed_sheets = Sheets.list_trashed_sheets(socket.assigns.project.id)

          socket =
            socket
            |> assign(:trashed_sheets, trashed_sheets)
            |> put_flash(:info, dgettext("projects", "Sheet restored successfully."))

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to restore sheet."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Sheet not found."))}
    end
  end

  defp do_delete_permanently(socket, id) do
    sheet = Sheets.get_trashed_sheet(socket.assigns.project.id, id)

    if sheet do
      case Sheets.permanently_delete_sheet(sheet) do
        {:ok, _sheet} ->
          trashed_sheets = Sheets.list_trashed_sheets(socket.assigns.project.id)

          socket =
            socket
            |> assign(:trashed_sheets, trashed_sheets)
            |> assign(:sheet_to_delete, nil)
            |> put_flash(:info, dgettext("projects", "Sheet permanently deleted."))

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete sheet."))}
      end
    else
      {:noreply, put_flash(socket, :error, dgettext("projects", "Sheet not found."))}
    end
  end

  defp do_empty_trash(socket) do
    project_id = socket.assigns.project.id
    trashed_sheets = Sheets.list_trashed_sheets(project_id)

    results =
      Enum.map(trashed_sheets, fn sheet ->
        Sheets.permanently_delete_sheet(sheet)
      end)

    errors = Enum.count(results, fn result -> match?({:error, _}, result) end)

    socket =
      if errors == 0 do
        socket
        |> assign(:trashed_sheets, [])
        |> put_flash(:info, dgettext("projects", "Trash emptied successfully."))
      else
        trashed_sheets = Sheets.list_trashed_sheets(project_id)

        socket
        |> assign(:trashed_sheets, trashed_sheets)
        |> put_flash(:error, dgettext("projects", "Some sheets could not be deleted."))
      end

    {:noreply, socket}
  end
end
