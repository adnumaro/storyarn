defmodule StoryarnWeb.ProjectLive.Trash do
  @moduledoc false

  use StoryarnWeb, :live_view
  use StoryarnWeb.LiveHelpers.Authorize

  alias Storyarn.Pages
  alias Storyarn.Projects
  alias Storyarn.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.project
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      pages_tree={@pages_tree}
      current_path={~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/trash"}
    >
      <div class="max-w-3xl mx-auto">
        <.header>
          {gettext("Trash")}
          <:subtitle>
            {gettext("Deleted pages are kept for 30 days before being permanently removed.")}
          </:subtitle>
          <:actions>
            <.button
              :if={@can_manage && @trashed_pages != []}
              variant="error"
              phx-click={show_modal("empty-trash-confirm")}
            >
              <.icon name="trash-2" class="size-4 mr-2" />
              {gettext("Empty Trash")}
            </.button>
          </:actions>
        </.header>

        <div class="mt-8">
          <%= if @trashed_pages == [] do %>
            <.empty_state
              icon="trash-2"
              title={gettext("Trash is empty")}
            >
              {gettext("Deleted pages will appear here.")}
            </.empty_state>
          <% else %>
            <div class="space-y-2">
              <.trash_item
                :for={page <- @trashed_pages}
                page={page}
                can_manage={@can_manage}
              />
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Confirmation modals --%>
      <.confirm_modal
        id="delete-page-confirm"
        title={gettext("Delete permanently?")}
        message={gettext("This page will be permanently deleted. This action cannot be undone.")}
        confirm_text={gettext("Delete")}
        cancel_text={gettext("Cancel")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("confirm_delete_permanently")}
      />

      <.confirm_modal
        id="empty-trash-confirm"
        title={gettext("Empty trash?")}
        message={gettext("All items in trash will be permanently deleted. This action cannot be undone.")}
        confirm_text={gettext("Empty Trash")}
        cancel_text={gettext("Cancel")}
        confirm_variant="error"
        icon="alert-triangle"
        on_confirm={JS.push("empty_trash")}
      />
    </Layouts.project>
    """
  end

  attr :page, :map, required: true
  attr :can_manage, :boolean, default: false

  defp trash_item(assigns) do
    ~H"""
    <div class="flex items-center justify-between p-4 bg-base-200 rounded-lg">
      <div class="flex items-center gap-3 min-w-0">
        <div class="flex-shrink-0">
          <%= if @page.avatar_asset do %>
            <img
              src={@page.avatar_asset.url}
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
          <p class="font-medium truncate">{@page.name}</p>
          <p class="text-sm text-base-content/60">
            {gettext("Deleted %{time_ago}", time_ago: format_time_ago(@page.deleted_at))}
          </p>
        </div>
      </div>

      <div :if={@can_manage} class="flex items-center gap-2 flex-shrink-0">
        <button
          type="button"
          class="btn btn-ghost btn-sm"
          phx-click="restore_page"
          phx-value-id={@page.id}
        >
          <.icon name="undo-2" class="size-4 mr-1" />
          {gettext("Restore")}
        </button>
        <button
          type="button"
          class="btn btn-ghost btn-sm text-error hover:bg-error/10"
          phx-click={JS.push("show_delete_confirm", value: %{id: @page.id}) |> show_modal("delete-page-confirm")}
        >
          <.icon name="trash-2" class="size-4 mr-1" />
          {gettext("Delete")}
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
        gettext("just now")

      diff < 3600 ->
        minutes = div(diff, 60)

        ngettext("%{count} minute ago", "%{count} minutes ago", minutes, count: minutes)

      diff < 86_400 ->
        hours = div(diff, 3600)
        ngettext("%{count} hour ago", "%{count} hours ago", hours, count: hours)

      true ->
        days = div(diff, 86_400)
        ngettext("%{count} day ago", "%{count} days ago", days, count: days)
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
        pages_tree = Pages.list_pages_tree(project.id)
        trashed_pages = Pages.list_trashed_pages(project.id)
        can_manage = Projects.ProjectMembership.can?(membership.role, :edit_content)

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:current_workspace, project.workspace)
          |> assign(:pages_tree, pages_tree)
          |> assign(:trashed_pages, trashed_pages)
          |> assign(:can_manage, can_manage)
          |> assign(:page_to_delete, nil)

        {:ok, socket}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Project not found."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_event("restore_page", %{"id" => id}, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        do_restore_page(socket, id)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("show_delete_confirm", %{"id" => id}, socket) do
    {:noreply, assign(socket, :page_to_delete, id)}
  end

  def handle_event("confirm_delete_permanently", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        if socket.assigns.page_to_delete do
          do_delete_permanently(socket, socket.assigns.page_to_delete)
        else
          {:noreply, socket}
        end

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  def handle_event("empty_trash", _params, socket) do
    case authorize(socket, :edit_content) do
      :ok ->
        do_empty_trash(socket)

      {:error, :unauthorized} ->
        {:noreply,
         put_flash(socket, :error, gettext("You don't have permission to perform this action."))}
    end
  end

  defp do_restore_page(socket, id) do
    page = Pages.get_trashed_page(socket.assigns.project.id, id)

    if page do
      case Pages.restore_page(page) do
        {:ok, _page} ->
          trashed_pages = Pages.list_trashed_pages(socket.assigns.project.id)
          pages_tree = Pages.list_pages_tree(socket.assigns.project.id)

          socket =
            socket
            |> assign(:trashed_pages, trashed_pages)
            |> assign(:pages_tree, pages_tree)
            |> put_flash(:info, gettext("Page restored successfully."))

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to restore page."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Page not found."))}
    end
  end

  defp do_delete_permanently(socket, id) do
    page = Pages.get_trashed_page(socket.assigns.project.id, id)

    if page do
      case Pages.permanently_delete_page(page) do
        {:ok, _page} ->
          trashed_pages = Pages.list_trashed_pages(socket.assigns.project.id)

          socket =
            socket
            |> assign(:trashed_pages, trashed_pages)
            |> assign(:page_to_delete, nil)
            |> put_flash(:info, gettext("Page permanently deleted."))

          {:noreply, socket}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, gettext("Failed to delete page."))}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Page not found."))}
    end
  end

  defp do_empty_trash(socket) do
    project_id = socket.assigns.project.id
    trashed_pages = Pages.list_trashed_pages(project_id)

    results =
      Enum.map(trashed_pages, fn page ->
        Pages.permanently_delete_page(page)
      end)

    errors = Enum.count(results, fn result -> match?({:error, _}, result) end)

    socket =
      if errors == 0 do
        socket
        |> assign(:trashed_pages, [])
        |> put_flash(:info, gettext("Trash emptied successfully."))
      else
        trashed_pages = Pages.list_trashed_pages(project_id)

        socket
        |> assign(:trashed_pages, trashed_pages)
        |> put_flash(:error, gettext("Some pages could not be deleted."))
      end

    {:noreply, socket}
  end
end
