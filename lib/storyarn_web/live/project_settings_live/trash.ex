defmodule StoryarnWeb.ProjectSettingsLive.Trash do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Screenplays
  alias Storyarn.Sheets
  alias StoryarnWeb.Helpers.Authorize

  @page_size 25

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.SettingsLayout.settings
      flash={@flash}
      socket={@socket}
      current_scope={@current_scope}
      current_path={@current_path}
      workspace={@workspace}
      project={@project}
    >
      <:title>{dgettext("projects", "Trash")}</:title>
      <:subtitle>
        {dgettext("projects", "Restore deleted project items or remove them permanently.")}
      </:subtitle>

      <.vue
        v-component="live/project/settings/ProjectSettingsTrash"
        v-socket={@socket}
        v-inject="settings-layout"
        id="project-trash-vue"
        trashed-items={serialize_trashed_items(@trashed_items)}
        pagination={@trash_pagination}
        type-counts={@trash_type_counts}
        active-filter={@trash_type}
        search-query={@trash_search}
        can-manage={@can_manage}
      />
    </StoryarnWeb.Components.SettingsLayout.settings>
    """
  end

  defp serialize_trashed_items(items) do
    Enum.map(items, fn item ->
      %{
        id: item.id,
        type: item.type,
        name: item.name,
        deleted_at: item.deleted_at && DateTime.to_iso8601(item.deleted_at)
      }
    end)
  end

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns
    can_manage = Projects.can?(membership.role, :edit_content)

    {:ok,
     socket
     |> assign(:current_workspace, project.workspace)
     |> assign(:can_manage, can_manage)
     |> assign(:trash_page, 1)
     |> assign(:trash_page_size, @page_size)
     |> assign(:trash_search, "")
     |> assign(:trash_type, "all")
     |> load_trashed_items()}
  end

  @impl true
  def handle_params(_params, url, socket) do
    {:noreply,
     socket
     |> assign(:page_title, dgettext("projects", "Project Trash"))
     |> assign(:current_path, URI.parse(url).path)}
  end

  @impl true
  def handle_event("restore_item", %{"type" => type, "id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_restore_item(socket, type, id)
    end)
  end

  def handle_event("delete_item", %{"type" => type, "id" => id}, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_delete_permanently(socket, type, id)
    end)
  end

  def handle_event("empty_trash", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_empty_trash(socket)
    end)
  end

  def handle_event("set_trash_filter", %{"type" => type}, socket) do
    {:noreply,
     socket
     |> assign(:trash_type, normalize_trash_type(type))
     |> assign(:trash_page, 1)
     |> load_trashed_items()}
  end

  def handle_event("search_trash", %{"query" => query}, socket) do
    {:noreply,
     socket
     |> assign(:trash_search, String.trim(query || ""))
     |> assign(:trash_page, 1)
     |> load_trashed_items()}
  end

  def handle_event("change_trash_page", %{"page" => page}, socket) do
    {:noreply,
     socket
     |> assign(:trash_page, normalize_page(page))
     |> load_trashed_items()}
  end

  defp do_restore_item(socket, type, id) do
    case fetch_trashed_item(socket.assigns.project.id, type, id) do
      {:ok, item} ->
        case restore_item(item) do
          {:ok, _restored} ->
            {:noreply,
             socket
             |> reload_trashed_items()
             |> put_flash(:info, dgettext("projects", "Item restored successfully."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to restore item."))}
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Item not found."))}
    end
  end

  defp do_delete_permanently(socket, type, id) do
    case fetch_trashed_item(socket.assigns.project.id, type, id) do
      {:ok, item} ->
        case permanently_delete_item(item) do
          {:ok, _deleted} ->
            {:noreply,
             socket
             |> reload_trashed_items()
             |> put_flash(:info, dgettext("projects", "Item permanently deleted."))}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to delete item."))}
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Item not found."))}
    end
  end

  defp do_empty_trash(socket) do
    project_id = socket.assigns.project.id

    results =
      project_id
      |> Projects.list_deleted_items()
      |> Enum.map(fn item ->
        case fetch_trashed_item(project_id, item.type, item.id) do
          {:ok, trashed_item} -> permanently_delete_item(trashed_item)
          :error -> {:error, :not_found}
        end
      end)

    errors = Enum.count(results, fn result -> match?({:error, _}, result) end)

    socket =
      if errors == 0 do
        socket
        |> load_trashed_items()
        |> put_flash(:info, dgettext("projects", "Trash emptied successfully."))
      else
        socket
        |> reload_trashed_items()
        |> put_flash(:error, dgettext("projects", "Some items could not be deleted."))
      end

    {:noreply, socket}
  end

  defp reload_trashed_items(socket) do
    load_trashed_items(socket)
  end

  defp load_trashed_items(socket) do
    page =
      Projects.paginate_deleted_items(socket.assigns.project.id,
        page: socket.assigns.trash_page,
        per_page: socket.assigns.trash_page_size,
        search: socket.assigns.trash_search,
        type: socket.assigns.trash_type
      )

    socket
    |> assign(:trashed_items, page.items)
    |> assign(:trash_page, page.page)
    |> assign(:trash_pagination, %{
      page: page.page,
      pageSize: page.per_page,
      totalCount: page.total_count,
      totalPages: page.total_pages
    })
    |> assign(:trash_type_counts, page.type_counts)
  end

  defp fetch_trashed_item(project_id, "sheet", id), do: fetch_item(:sheet, Sheets.get_trashed_sheet(project_id, id))
  defp fetch_trashed_item(project_id, "flow", id), do: fetch_item(:flow, Flows.get_flow_including_deleted(project_id, id))

  defp fetch_trashed_item(project_id, "scene", id),
    do: fetch_item(:scene, Scenes.get_scene_including_deleted(project_id, id))

  defp fetch_trashed_item(project_id, "screenplay", id),
    do: fetch_item(:screenplay, Screenplays.get_screenplay_including_deleted(project_id, id))

  defp fetch_trashed_item(_project_id, _type, _id), do: :error

  defp fetch_item(type, %{deleted_at: %DateTime{}} = item), do: {:ok, %{type: type, entity: item}}
  defp fetch_item(_type, _item), do: :error

  defp normalize_trash_type(type) when type in ["sheet", "flow", "scene", "screenplay"], do: type
  defp normalize_trash_type(_type), do: "all"

  defp normalize_page(page) when is_integer(page) and page > 0, do: page

  defp normalize_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {integer, ""} when integer > 0 -> integer
      _ -> 1
    end
  end

  defp normalize_page(_page), do: 1

  defp restore_item(%{type: :sheet, entity: sheet}), do: Sheets.restore_sheet(sheet)
  defp restore_item(%{type: :flow, entity: flow}), do: Flows.restore_flow(flow)
  defp restore_item(%{type: :scene, entity: scene}), do: Scenes.restore_scene(scene)
  defp restore_item(%{type: :screenplay, entity: screenplay}), do: Screenplays.restore_screenplay(screenplay)

  defp permanently_delete_item(%{type: :sheet, entity: sheet}), do: Sheets.permanently_delete_sheet(sheet)
  defp permanently_delete_item(%{type: :flow, entity: flow}), do: Flows.hard_delete_flow(flow)
  defp permanently_delete_item(%{type: :scene, entity: scene}), do: Scenes.hard_delete_scene(scene)

  defp permanently_delete_item(%{type: :screenplay, entity: screenplay}),
    do: Screenplays.hard_delete_screenplay(screenplay)
end
