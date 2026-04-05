defmodule StoryarnWeb.AssetLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view
  alias StoryarnWeb.Helpers.Authorize

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias Storyarn.Projects

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      socket={@socket}
      flash={@flash}
      current_scope={@current_scope}
      project={@project}
      workspace={@workspace}
      active_tool={:assets}
      has_tree={false}
      can_edit={@can_edit}
    >
      <:top_bar_extra_right :if={@can_edit}>
        <div class="flex items-center px-1.5 py-1 surface-panel">
          <label class={[
            "inline-flex items-center justify-center h-8 px-3 text-sm rounded-md hover:bg-accent transition-colors gap-1.5",
            @uploading && "btn-disabled"
          ]}>
            <.icon name="upload" class="size-4" />
            <span class="hidden xl:inline">
              {if @uploading,
                do: dgettext("assets", "Uploading..."),
                else: dgettext("assets", "Upload")}
            </span>
            <input
              type="file"
              accept="image/*,audio/*"
              class="hidden"
              id="asset-upload-input"
            />
          </label>
        </div>
      </:top_bar_extra_right>
      <.vue
        v-component="assets/AssetIndex"
        v-socket={@socket}
        id="asset-index"
        assets={serialize_assets(@assets)}
        filter={@filter}
        search={@search}
        type-counts={@type_counts}
        selected-asset={serialize_asset(@selected_asset)}
        asset-usages={serialize_usages(@asset_usages)}
        uploading={@uploading}
        can-edit={@can_edit}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
      />
    </Layouts.app>
    """
  end

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

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
        can_edit = Projects.can?(membership.role, :edit_content)
        type_counts = Assets.count_assets_by_type(project.id)

        if connected?(socket) do
          Collaboration.subscribe_changes({:assets, project.id})
        end

        socket =
          socket
          |> assign(:project, project)
          |> assign(:workspace, project.workspace)
          |> assign(:membership, membership)
          |> assign(:can_edit, can_edit)
          |> assign(:filter, "all")
          |> assign(:search, "")
          |> assign(:type_counts, type_counts)
          |> assign(:selected_asset, nil)
          |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})
          |> assign(:uploading, false)
          |> load_assets()

        {:ok, socket}

      {:error, _reason} ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("assets", "You don't have access to this project."))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:remote_change, _action, _payload}, socket) do
    type_counts = Assets.count_assets_by_type(socket.assigns.project.id)

    {:noreply,
     socket
     |> assign(:type_counts, type_counts)
     |> refresh_selected_asset()
     |> load_assets()}
  end

  # ===========================================================================
  # Event Handlers
  # ===========================================================================

  @impl true
  def handle_event("filter_assets", %{"type" => type}, socket)
      when type in ["all", "image", "audio"] do
    {:noreply,
     socket
     |> assign(:filter, type)
     |> load_assets()}
  end

  def handle_event("search_assets", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> load_assets()}
  end

  def handle_event("select_asset", %{"id" => id}, socket) do
    project_id = socket.assigns.project.id

    case Integer.parse(id) do
      {int_id, ""} -> handle_select_asset(socket, project_id, int_id)
      _ -> {:noreply, socket}
    end
  end

  def handle_event("deselect_asset", _params, socket) do
    {:noreply,
     socket
     |> assign(:selected_asset, nil)
     |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})}
  end

  def handle_event("confirm_delete_asset", _params, socket) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      delete_selected_asset(socket)
    end)
  end

  def handle_event("upload_started", _params, socket) do
    {:noreply, assign(socket, :uploading, true)}
  end

  def handle_event("upload_validation_error", %{"message" => message}, socket) do
    {:noreply,
     socket
     |> assign(:uploading, false)
     |> put_flash(:error, message)}
  end

  def handle_event(
        "upload_asset",
        %{"filename" => filename, "content_type" => content_type, "data" => data},
        socket
      ) do
    Authorize.with_authorization(socket, :edit_content, fn socket ->
      process_upload(socket, filename, content_type, data)
    end)
  end

  defp handle_select_asset(socket, project_id, int_id) do
    case Assets.get_asset(project_id, int_id) do
      nil ->
        {:noreply, socket}

      asset ->
        usages = Assets.get_asset_usages(project_id, asset.id)

        {:noreply,
         socket
         |> assign(:selected_asset, asset)
         |> assign(:asset_usages, usages)}
    end
  end

  # ===========================================================================
  # Private: Data Loading
  # ===========================================================================

  # base64 is ~4/3 ratio, so 20MB file ≈ 27MB base64
  @max_base64_size 28_000_000

  defp process_upload(socket, filename, content_type, data) do
    case String.split(data, ",", parts: 2) do
      [_header, base64_data] ->
        if byte_size(base64_data) > @max_base64_size do
          {:noreply,
           socket
           |> assign(:uploading, false)
           |> put_flash(:error, dgettext("assets", "File too large (max 20MB)."))}
        else
          decode_and_upload(socket, filename, content_type, base64_data)
        end

      _ ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, dgettext("assets", "Invalid file data."))}
    end
  end

  defp decode_and_upload(socket, filename, content_type, base64_data) do
    case Base.decode64(base64_data) do
      {:ok, binary_data} ->
        do_upload(socket, filename, content_type, binary_data)

      :error ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, dgettext("assets", "Invalid file data."))}
    end
  end

  defp do_upload(socket, filename, content_type, binary_data) do
    if Assets.allowed_content_type?(content_type) do
      project = socket.assigns.project
      user = socket.assigns.current_scope.user

      case Billing.can_upload_asset_for_project?(project, byte_size(binary_data)) do
        :ok ->
          do_upload_file(socket, project, user, filename, content_type, binary_data)

        {:error, :limit_reached, _details} ->
          {:noreply,
           socket
           |> assign(:uploading, false)
           |> put_flash(:error, dgettext("assets", "Storage limit reached. Upgrade your plan."))}
      end
    else
      {:noreply,
       socket
       |> assign(:uploading, false)
       |> put_flash(:error, dgettext("assets", "Unsupported file type."))}
    end
  end

  defp do_upload_file(socket, project, user, filename, content_type, binary_data) do
    case Assets.upload_binary_and_create_asset(
           binary_data,
           %{filename: filename, content_type: content_type},
           project,
           user
         ) do
      {:ok, asset} ->
        type_counts = Assets.count_assets_by_type(project.id)
        usages = Assets.get_asset_usages(project.id, asset.id)
        broadcast_asset_change(project.id, :asset_created)

        {:noreply,
         socket
         |> assign(:uploading, false)
         |> assign(:type_counts, type_counts)
         |> assign(:selected_asset, asset)
         |> assign(:asset_usages, usages)
         |> load_assets()
         |> put_flash(:info, dgettext("assets", "Asset uploaded successfully."))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:uploading, false)
         |> put_flash(:error, upload_error_message(reason))}
    end
  end

  defp upload_error_message(%Ecto.Changeset{}), do: dgettext("assets", "Could not save asset.")
  defp upload_error_message(_), do: dgettext("assets", "Upload failed. Please try again.")

  defp delete_selected_asset(socket) do
    case socket.assigns.selected_asset do
      nil ->
        {:noreply, socket}

      asset ->
        # Delete from storage (best-effort)
        Assets.storage_delete(asset.key)

        if thumbnail_key = asset.metadata["thumbnail_key"] do
          Assets.storage_delete(thumbnail_key)
        end

        case Assets.delete_asset(asset) do
          {:ok, _} ->
            type_counts = Assets.count_assets_by_type(socket.assigns.project.id)
            broadcast_asset_change(socket.assigns.project.id, :asset_deleted)

            {:noreply,
             socket
             |> assign(:selected_asset, nil)
             |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})
             |> assign(:type_counts, type_counts)
             |> load_assets()
             |> put_flash(:info, dgettext("assets", "Asset deleted."))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, dgettext("assets", "Could not delete asset."))}
        end
    end
  end

  defp load_assets(socket) do
    project_id = socket.assigns.project.id
    opts = filter_opts(socket.assigns.filter) ++ search_opts(socket.assigns.search)
    assign(socket, :assets, Assets.list_assets(project_id, opts))
  end

  defp filter_opts("all"), do: []
  defp filter_opts("image"), do: [content_type: "image/"]
  defp filter_opts("audio"), do: [content_type: "audio/"]

  defp search_opts(""), do: []
  defp search_opts(term), do: [search: term]

  # ===========================================================================
  # Private: View Helpers
  # ===========================================================================

  defp broadcast_asset_change(project_id, action) do
    Collaboration.broadcast_change_from(self(), {:assets, project_id}, action, %{})
  end

  defp refresh_selected_asset(socket) do
    case socket.assigns.selected_asset do
      nil ->
        socket

      asset ->
        case Assets.get_asset(socket.assigns.project.id, asset.id) do
          nil ->
            socket
            |> assign(:selected_asset, nil)
            |> assign(:asset_usages, %{flow_nodes: [], sheet_avatars: [], sheet_banners: []})

          refreshed ->
            assign(socket, :selected_asset, refreshed)
        end
    end
  end

  # ===========================================================================
  # Private: Serializers (Ecto → Vue props)
  # ===========================================================================

  defp serialize_assets(assets), do: Enum.map(assets, &serialize_asset/1)

  defp serialize_asset(nil), do: nil

  defp serialize_asset(asset) do
    %{
      id: asset.id,
      filename: asset.filename,
      contentType: asset.content_type,
      size: asset.size,
      url: asset.url,
      insertedAt: asset.inserted_at
    }
  end

  defp serialize_usages(usages) do
    %{
      flowNodes:
        Enum.map(usages.flow_nodes, fn u ->
          %{flowId: u.flow_id, flowName: u.flow_name}
        end),
      sheetAvatars:
        Enum.map(usages.sheet_avatars, fn s ->
          %{id: s.id, name: s.name}
        end),
      sheetBanners:
        Enum.map(usages.sheet_banners, fn s ->
          %{id: s.id, name: s.name}
        end)
    }
  end
end
