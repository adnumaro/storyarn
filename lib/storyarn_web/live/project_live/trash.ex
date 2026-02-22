defmodule StoryarnWeb.ProjectLive.Trash do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.Helpers.Authorize

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
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/trash"}
    >
      <div class="max-w-3xl mx-auto">
        <.header>
          {dgettext("projects", "Trash")}
          <:subtitle>
            {dgettext(
              "projects",
              "Deleted sheets are kept for 30 days before being permanently removed."
            )}
          </:subtitle>
          <:actions>
            <.button
              :if={@can_manage && @trashed_sheets != []}
              variant="error"
              phx-click={show_modal("empty-trash-confirm")}
            >
              <.icon name="trash-2" class="size-4 mr-2" />
              {dgettext("projects", "Empty Trash")}
            </.button>
          </:actions>
        </.header>

        <div class="mt-8">
          <%= if @trashed_sheets == [] do %>
            <.empty_state
              icon="trash-2"
              title={dgettext("projects", "Trash is empty")}
            >
              {dgettext("projects", "Deleted sheets will appear here.")}
            </.empty_state>
          <% else %>
            <div class="space-y-2">
              <.trash_item
                :for={sheet <- @trashed_sheets}
                sheet={sheet}
                can_manage={@can_manage}
              />
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Confirmation modals --%>
      <.confirm_modal
        id="delete-sheet-confirm"
        title={dgettext("projects", "Delete permanently?")}
        message={
          dgettext(
            "projects",
            "This sheet will be permanently deleted. This action cannot be undone."
          )
        }
        confirm_text={dgettext("projects", "Delete")}
        cancel_text={dgettext("projects", "Cancel")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_permanently")}
      />

      <.confirm_modal
        id="empty-trash-confirm"
        title={dgettext("projects", "Empty trash?")}
        message={
          dgettext(
            "projects",
            "All items in trash will be permanently deleted. This action cannot be undone."
          )
        }
        confirm_text={dgettext("projects", "Empty Trash")}
        cancel_text={dgettext("projects", "Cancel")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("empty_trash")}
      />
    </Layouts.project>
    """
  end

  attr :sheet, :map, required: true
  attr :can_manage, :boolean, default: false

  defp trash_item(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 bg-base-200 rounded-lg">
      <div class="flex items-center gap-3 min-w-0">
        <div class="flex-shrink-0">
          <%= if @sheet.avatar_asset do %>
            <img
              src={@sheet.avatar_asset.url}
              alt=""
              class="size-10 rounded object-cover"
            />
          <% else %>
            <div class="size-10 rounded bg-base-300 flex items-center justify-center">
              <.icon name="file-text" class="size-5 text-base-content/50" />
            </div>
          <% end %>
        </div>
        <div class="min-w-0">
          <p class="font-medium truncate">{@sheet.name}</p>
          <p class="text-sm text-base-content/60">
            {dgettext("projects", "Deleted %{time_ago}", time_ago: format_time_ago(@sheet.deleted_at))}
          </p>
        </div>
      </div>

      <div :if={@can_manage} class="flex items-center gap-2 flex-shrink-0">
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="restore_sheet"
          phx-value-id={@sheet.id}
        >
          <.icon name="undo-2" class="size-4 mr-1" />
          {dgettext("projects", "Restore")}
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-sm text-error hover:bg-error/10"
          phx-click={
            JS.push("show_delete_confirm", value: %{id: @sheet.id})
            |> show_modal("delete-sheet-confirm")
          }
        >
          <.icon name="trash-2" class="size-4 mr-1" />
          {dgettext("projects", "Delete")}
        </button>
      </div>
    </div>
    """
  end

  defp format_time_ago(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 ->
        dgettext("projects", "just now")

      diff < 3600 ->
        minutes = div(diff, 60)

        dngettext("projects", "%{count} minute ago", "%{count} minutes ago", minutes,
          count: minutes
        )

      diff < 86_400 ->
        hours = div(diff, 3600)
        dngettext("projects", "%{count} hour ago", "%{count} hours ago", hours, count: hours)

      true ->
        days = div(diff, 86_400)
        dngettext("projects", "%{count} day ago", "%{count} days ago", days, count: days)
    end
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
        trashed_sheets = Sheets.list_trashed_sheets(project.id)
        can_manage = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:current_workspace, project.workspace)
          |> assign(:sheets_tree, sheets_tree)
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
    with_authorization(socket, :edit_content, fn socket ->
      do_restore_sheet(socket, id)
    end)
  end

  def handle_event("show_delete_confirm", %{"id" => id}, socket) do
    {:noreply, assign(socket, :sheet_to_delete, id)}
  end

  def handle_event("confirm_delete_permanently", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      if socket.assigns.sheet_to_delete do
        do_delete_permanently(socket, socket.assigns.sheet_to_delete)
      else
        {:noreply, socket}
      end
    end)
  end

  def handle_event("empty_trash", _params, socket) do
    with_authorization(socket, :edit_content, fn socket ->
      do_empty_trash(socket)
    end)
  end

  defp do_restore_sheet(socket, id) do
    sheet = Sheets.get_trashed_sheet(socket.assigns.project.id, id)

    if sheet do
      case Sheets.restore_sheet(sheet) do
        {:ok, _sheet} ->
          trashed_sheets = Sheets.list_trashed_sheets(socket.assigns.project.id)
          sheets_tree = Sheets.list_sheets_tree(socket.assigns.project.id)

          socket =
            socket
            |> assign(:trashed_sheets, trashed_sheets)
            |> assign(:sheets_tree, sheets_tree)
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
