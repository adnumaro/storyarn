defmodule StoryarnWeb.ProjectSettingsLive.Trash do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Assets
  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
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
        id: Map.fetch!(item, :id),
        type: Map.fetch!(item, :type),
        name: Map.get(item, :name) || Map.get(item, :filename),
        deleted_at: serialize_datetime(Map.get(item, :deleted_at)),
        deletion_generation: Map.get(item, :deletion_generation),
        content_type: Map.get(item, :content_type),
        size: Map.get(item, :size),
        deletion_reason: Map.get(item, :deletion_reason),
        purge_at: serialize_datetime(Map.get(item, :purge_at))
      }
    end)
  end

  defp serialize_datetime(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp serialize_datetime(_datetime), do: nil

  @impl true
  def mount(_params, _session, socket) do
    %{project: project, membership: membership} = socket.assigns
    can_manage = Projects.can?(membership.role, :edit_content)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(
        Storyarn.PubSub,
        StoryarnWeb.Live.Shared.ProjectChromeHelpers.shell_topic(project.id)
      )
    end

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
  def handle_event("restore_item", %{"type" => type, "id" => id} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_restore_item(socket, type, id, params["generation"])
    end)
  end

  def handle_event("delete_item", %{"type" => type, "id" => id} = params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      do_delete_permanently(socket, type, id, params["generation"])
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

  @impl true
  def handle_info({:project_restored, _restore_id}, socket) do
    {:noreply, reload_trashed_items(socket)}
  end

  defp do_restore_item(socket, "asset", id, generation) do
    with {:ok, asset_id} <- parse_positive_integer(id),
         {:ok, expected_generation} <- parse_non_negative_integer(generation),
         {:ok, _restored} <-
           Assets.restore_trashed_asset(
             socket.assigns.project.id,
             asset_id,
             expected_generation,
             socket.assigns.current_scope.user.id
           ) do
      Collaboration.broadcast_change_from(
        self(),
        {:assets, socket.assigns.project.id},
        :asset_restored,
        %{}
      )

      {:noreply,
       socket
       |> reload_trashed_items()
       |> put_flash(:info, dgettext("projects", "Item restored successfully."))}
    else
      _reason ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Failed to restore item."))}
    end
  end

  defp do_restore_item(socket, type, id, _generation) do
    case fetch_trashed_item(socket.assigns.project.id, type, id) do
      {:ok, item} ->
        case restore_item(item) do
          {:ok, _restored} ->
            {:noreply,
             socket
             |> reload_trashed_items()
             |> put_flash(:info, dgettext("projects", "Item restored successfully."))}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, restore_error_message(reason))}
        end

      :error ->
        {:noreply, put_flash(socket, :error, dgettext("projects", "Item not found."))}
    end
  end

  defp do_delete_permanently(socket, "asset", id, generation) do
    with {:ok, asset_id} <- parse_positive_integer(id),
         {:ok, expected_generation} <- parse_non_negative_integer(generation),
         {:ok, _purged} <-
           Assets.purge_trashed_asset(
             socket.assigns.project.id,
             asset_id,
             expected_generation,
             socket.assigns.current_scope.user.id
           ) do
      {:noreply,
       socket
       |> reload_trashed_items()
       |> put_flash(:info, dgettext("projects", "Item permanently deleted."))}
    else
      reason ->
        {:noreply, put_flash(socket, :error, asset_purge_error_message(reason))}
    end
  end

  defp do_delete_permanently(socket, type, id, _generation) do
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
    actor_id = socket.assigns.current_scope.user.id

    other_results =
      project_id
      |> Projects.list_deleted_items()
      |> Enum.reject(&(&1.type == "asset"))
      |> Enum.map(&purge_listed_item(&1, project_id))

    # Asset purge checks every recoverable reference, including references
    # owned by trashed entities. Delete those owners first, then take a fresh
    # generation-fenced asset batch so one click can actually empty the trash.
    asset_results =
      project_id
      |> Projects.list_deleted_items(type: "asset")
      |> purge_asset_items(project_id, actor_id)

    results = other_results ++ asset_results

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

  defp fetch_trashed_item(_project_id, _type, _id), do: :error

  defp fetch_item(type, %{deleted_at: %DateTime{}} = item), do: {:ok, %{type: type, entity: item}}
  defp fetch_item(_type, _item), do: :error

  defp normalize_trash_type(type) when type in ["sheet", "flow", "scene", "asset"], do: type
  defp normalize_trash_type(_type), do: "all"

  defp parse_positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp parse_positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer > 0 -> {:ok, integer}
      _invalid -> {:error, :invalid_id}
    end
  end

  defp parse_positive_integer(_value), do: {:error, :invalid_id}

  defp parse_non_negative_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp parse_non_negative_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> {:ok, integer}
      _invalid -> {:error, :invalid_generation}
    end
  end

  defp parse_non_negative_integer(_value), do: {:error, :invalid_generation}

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

  defp restore_error_message({:invalid_project_reference, _context, _value}), do: unavailable_reference_message()

  defp restore_error_message(%Ecto.Changeset{errors: errors}) do
    if Enum.any?(errors, &unavailable_flow_reference_error?/1),
      do: unavailable_reference_message(),
      else: dgettext("projects", "Failed to restore item.")
  end

  defp restore_error_message(_reason), do: dgettext("projects", "Failed to restore item.")

  defp unavailable_flow_reference_error?({:parent_id, {"parent flow not found in project", _metadata}}), do: true
  defp unavailable_flow_reference_error?({:scene_id, {"map not found in project", _metadata}}), do: true
  defp unavailable_flow_reference_error?(_error), do: false

  defp unavailable_reference_message do
    dgettext(
      "projects",
      "This item references unavailable content. If any referenced items are in Trash, restore them first and try again."
    )
  end

  defp asset_purge_error_message({:error, reason}), do: asset_purge_error_message(reason)

  defp asset_purge_error_message(:asset_still_referenced) do
    dgettext(
      "projects",
      "This asset is still referenced by other content. Remove those references or permanently delete the referencing items from Trash, then try again."
    )
  end

  defp asset_purge_error_message(_reason), do: dgettext("projects", "Failed to delete item.")

  defp permanently_delete_item(%{type: :sheet, entity: sheet}), do: Sheets.permanently_delete_sheet(sheet)
  defp permanently_delete_item(%{type: :flow, entity: flow}), do: Flows.hard_delete_flow(flow)
  defp permanently_delete_item(%{type: :scene, entity: scene}), do: Scenes.hard_delete_scene(scene)

  defp purge_asset_items([], _project_id, _actor_id), do: []

  defp purge_asset_items(items, project_id, actor_id) do
    candidates = Enum.map(items, &{&1.id, &1.deletion_generation})
    [Assets.purge_trashed_assets(project_id, candidates, actor_id)]
  end

  defp purge_listed_item(item, project_id) do
    case fetch_trashed_item(project_id, item.type, item.id) do
      {:ok, trashed_item} -> permanently_delete_item(trashed_item)
      :error -> {:error, :not_found}
    end
  end
end
