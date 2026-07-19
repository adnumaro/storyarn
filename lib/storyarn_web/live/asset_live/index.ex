defmodule StoryarnWeb.AssetLive.Index do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Assets
  alias Storyarn.Billing
  alias Storyarn.Collaboration
  alias StoryarnWeb.Helpers.Authorize
  alias StoryarnWeb.Live.Shared.ProjectChromeHelpers
  alias StoryarnWeb.PrivateMedia

  @empty_asset_usages %{
    asset_metadata_links: [],
    flow_nodes: [],
    sequence_visual_layers: [],
    sequence_tracks: [],
    sheet_avatars: [],
    sheet_banners: [],
    scene_backgrounds: [],
    scene_pin_icons: [],
    scene_zone_icons: [],
    localized_voiceovers: [],
    gallery_images: []
  }

  @assets_per_page 48

  @impl true
  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.ProjectLayout.project
      socket={@socket}
      flash={@flash}
      project={@project}
      workspace={@workspace}
      current_scope={@current_scope}
      current_user={@current_user}
      urls={@urls}
      active_tool={:assets}
      is_super_admin={@is_super_admin}
      online_users={@online_users}
      sidebar_module={StoryarnWeb.AssetSidebarLive}
      sidebar_session={
        %{
          "project_id" => @project.id,
          "active_tool" => "assets",
          "dashboard_url" => ~p"/workspaces/#{@workspace.slug}/projects/#{@project.slug}/assets",
          "filter" => @filter,
          "search" => @search,
          "locale" => @locale
        }
      }
    >
      <.vue
        :if={@can_edit}
        v-component="live/assets/dashboard/AssetsHeaderActions"
        v-socket={@socket}
        v-inject:top-right="project-layout"
        id="asset-upload-button"
        uploading={@uploading}
      />

      <.vue
        v-component="live/assets/dashboard/AssetsDashboard"
        v-socket={@socket}
        v-inject="project-layout"
        id="asset-index"
        class="contents"
        assets={serialize_assets(@assets)}
        selected-asset={serialize_asset(@selected_asset)}
        asset-usages={serialize_usages(@asset_usages)}
        can-edit={@can_edit}
        workspace-slug={@workspace.slug}
        project-slug={@project.slug}
        page={@asset_page}
        total-pages={@asset_total_pages}
        total-count={@asset_total_count}
      />
    </StoryarnWeb.Components.ProjectLayout.project>
    """
  end

  # ===========================================================================
  # Lifecycle
  # ===========================================================================

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    type_counts = Assets.count_assets_by_type(project.id)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Storyarn.PubSub, ProjectChromeHelpers.shell_topic(project.id))
      Collaboration.subscribe_changes({:assets, project.id})
    end

    socket =
      socket
      |> assign(:filter, "all")
      |> assign(:search, "")
      |> assign(:asset_page, 1)
      |> assign(:asset_total_pages, 1)
      |> assign(:asset_total_count, 0)
      |> assign(:type_counts, type_counts)
      |> assign(:selected_asset, nil)
      |> assign(:asset_usages, @empty_asset_usages)
      |> assign(:uploading, false)
      |> assign(:online_users, ProjectChromeHelpers.initial_online_users(project.id))
      |> load_assets()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:online_users, users}, socket), do: {:noreply, assign(socket, :online_users, users)}

  def handle_info({:toolbar_event, _name, _params}, socket), do: {:noreply, socket}

  # Shell-topic sibling actives — broadcast by other tools sharing the topic.
  def handle_info({:active_sheet, _sheet_id}, socket), do: {:noreply, socket}
  def handle_info({:active_flow, _flow_id}, socket), do: {:noreply, socket}
  def handle_info({:active_scene, _scene_id}, socket), do: {:noreply, socket}
  def handle_info({:active_locale, _locale}, socket), do: {:noreply, socket}

  def handle_info({:asset_filters_changed, %{filter: filter, search: search}}, socket) do
    {:noreply,
     socket
     |> assign(:filter, filter)
     |> assign(:search, search)
     |> assign(:asset_page, 1)
     |> clear_selected_asset()
     |> load_assets()}
  end

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
  def handle_event("filter_assets", %{"type" => type}, socket) when type in ["all", "image", "audio", "file"] do
    {:noreply,
     socket
     |> assign(:filter, type)
     |> assign(:asset_page, 1)
     |> clear_selected_asset()
     |> load_assets()}
  end

  def handle_event("search_assets", %{"search" => search}, socket) do
    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:asset_page, 1)
     |> clear_selected_asset()
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
     |> assign(:asset_usages, @empty_asset_usages)}
  end

  def handle_event("change_asset_page", %{"page" => page}, socket) do
    page = parse_page(page)

    {:noreply,
     socket
     |> assign(:asset_page, page)
     |> clear_selected_asset()
     |> load_assets()}
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

  def handle_event("upload_asset", %{"filename" => filename, "content_type" => content_type, "data" => data}, socket) do
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
        case Assets.delete_asset(asset) do
          {:ok, _} ->
            delete_asset_files(asset)

            type_counts = Assets.count_assets_by_type(socket.assigns.project.id)
            broadcast_asset_change(socket.assigns.project.id, :asset_deleted)

            {:noreply,
             socket
             |> assign(:selected_asset, nil)
             |> assign(:asset_usages, @empty_asset_usages)
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
    total_count = Assets.count_assets(project_id, opts)
    total_pages = max(div(total_count + @assets_per_page - 1, @assets_per_page), 1)
    page = socket.assigns.asset_page |> max(1) |> min(total_pages)

    assets =
      Assets.list_assets(
        project_id,
        opts ++ [limit: @assets_per_page, offset: (page - 1) * @assets_per_page]
      )

    socket
    |> assign(:assets, assets)
    |> assign(:asset_page, page)
    |> assign(:asset_total_pages, total_pages)
    |> assign(:asset_total_count, total_count)
  end

  defp parse_page(page) when is_integer(page), do: page

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {parsed, ""} -> parsed
      _ -> 1
    end
  end

  defp parse_page(_page), do: 1

  defp delete_asset_files(asset) do
    Assets.storage_delete(asset.key)

    (asset.metadata || %{})
    |> Map.get("thumbnail_key")
    |> then(fn
      nil -> :ok
      thumbnail_key -> Assets.storage_delete(thumbnail_key)
    end)
  end

  defp filter_opts("all"), do: []
  defp filter_opts("image"), do: [content_type: "image/"]
  defp filter_opts("audio"), do: [content_type: "audio/"]
  defp filter_opts("file"), do: [content_type: "application/"]

  defp search_opts(""), do: []
  defp search_opts(term), do: [search: term]

  # ===========================================================================
  # Private: View Helpers
  # ===========================================================================

  defp broadcast_asset_change(project_id, action) do
    Collaboration.broadcast_change_from(self(), {:assets, project_id}, action, %{})
  end

  defp clear_selected_asset(socket) do
    socket
    |> assign(:selected_asset, nil)
    |> assign(:asset_usages, @empty_asset_usages)
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
            |> assign(:asset_usages, @empty_asset_usages)

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
      url: PrivateMedia.asset_url(asset),
      insertedAt: asset.inserted_at
    }
  end

  defp serialize_usages(usages) do
    %{
      assetMetadataLinks:
        Enum.map(usages.asset_metadata_links, fn asset ->
          %{
            id: asset.id,
            filename: asset.filename,
            relations: asset.relations
          }
        end),
      flowNodes:
        Enum.map(usages.flow_nodes, fn u ->
          %{
            nodeId: u.node_id,
            nodeType: u.node_type,
            flowId: u.flow_id,
            flowName: u.flow_name,
            trashed: u.trashed
          }
        end),
      sequenceVisualLayers:
        Enum.map(usages.sequence_visual_layers, fn layer ->
          %{
            id: layer.id,
            nodeId: layer.node_id,
            flowId: layer.flow_id,
            flowName: layer.flow_name,
            sequenceName: layer.sequence_name,
            label: layer.label,
            kind: layer.kind,
            trashed: layer.trashed
          }
        end),
      sequenceTracks:
        Enum.map(usages.sequence_tracks, fn track ->
          %{
            id: track.id,
            nodeId: track.node_id,
            flowId: track.flow_id,
            flowName: track.flow_name,
            sequenceName: track.sequence_name,
            kind: track.kind,
            trashed: track.trashed
          }
        end),
      sheetAvatars:
        Enum.map(usages.sheet_avatars, fn s ->
          %{id: s.id, name: s.name, trashed: s.trashed}
        end),
      sheetBanners:
        Enum.map(usages.sheet_banners, fn s ->
          %{id: s.id, name: s.name, trashed: s.trashed}
        end),
      sceneBackgrounds:
        Enum.map(usages.scene_backgrounds, fn s ->
          %{id: s.id, name: s.name, trashed: s.trashed}
        end),
      scenePinIcons:
        Enum.map(usages.scene_pin_icons, fn p ->
          %{
            pinId: p.pin_id,
            pinLabel: p.pin_label,
            sceneId: p.scene_id,
            sceneName: p.scene_name,
            trashed: p.trashed
          }
        end),
      sceneZoneIcons:
        Enum.map(usages.scene_zone_icons, fn zone ->
          %{
            zoneId: zone.zone_id,
            zoneName: zone.zone_name,
            sceneId: zone.scene_id,
            sceneName: zone.scene_name,
            trashed: zone.trashed
          }
        end),
      localizedVoiceovers:
        Enum.map(usages.localized_voiceovers, fn text ->
          %{
            id: text.id,
            localeCode: text.locale_code,
            sourceType: text.source_type,
            sourceId: text.source_id,
            sourceText: text.source_text,
            archived: not is_nil(text.archived_at)
          }
        end),
      galleryImages:
        Enum.map(usages.gallery_images, fn image ->
          %{
            id: image.id,
            blockId: image.block_id,
            sheetId: image.sheet_id,
            sheetName: image.sheet_name,
            label: image.label,
            trashed:
              not is_nil(image.block_deleted_at) or
                not is_nil(image.sheet_deleted_at)
          }
        end)
    }
  end
end
