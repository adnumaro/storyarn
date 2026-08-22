defmodule StoryarnWeb.VersionViewerLive do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias StoryarnWeb.PrivateMedia

  require Logger

  @impl true
  def render(%{view_error: _} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/viewer/VersionViewerError"
        v-socket={@socket}
        v-inject="compare-layout"
        id="version-viewer-error"
        class="w-full h-full"
        reason={@view_error}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  def render(%{entity_type: :scene} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/scene/show/SceneCompactSurface"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"scene-version-viewer-#{@entity_id}-#{@version_number}"}
        class="h-full relative"
        surface={@surface}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  def render(%{entity_type: :sheet} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare
      socket={@socket}
      flash={@flash}
      content_class="h-full overflow-y-auto bg-background p-4"
    >
      <.vue
        v-component="live/sheet/show/SheetSurface"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"sheet-version-surface-#{@entity_id}-#{@version_number}"}
        class="contents"
        sheet={@sheet}
        can-edit={false}
        source-shortcut={nil}
        surface={@surface}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "id" => entity_id_str,
          "version_number" => version_number_str
        },
        _session,
        socket
      ) do
    entity_type = socket.assigns.live_action

    case load_version_view(socket, entity_type, workspace_slug, project_slug, entity_id_str, version_number_str) do
      {:ok, loaded_socket} ->
        {:ok, loaded_socket, layout: false}

      {:error, reason} ->
        # This view is embedded in the compare page's iframe. Redirecting away
        # would render an unrelated page inside the pane, so the failure has to
        # be shown in place — and logged, because the pane cannot show why.
        {:ok, assign_view_error(socket, entity_type, entity_id_str, version_number_str, reason), layout: false}
    end
  end

  defp load_version_view(socket, entity_type, workspace_slug, project_slug, entity_id_str, version_number_str) do
    with {:ok, entity_id} <- parse_id(entity_id_str, :invalid_entity_id),
         {:ok, version_number} <- parse_id(version_number_str, :invalid_version_number),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug),
         {:ok, entity} <- fetch_entity(entity_type, project.id, entity_id),
         {:ok, version} <- fetch_version(entity_type, entity_id, version_number),
         {:ok, snapshot} <- load_version_snapshot(entity_type, version) do
      {:ok,
       socket
       |> assign(:entity_type, entity_type)
       |> assign(:entity_id, entity_id)
       |> assign(:version_number, version_number)
       |> assign(:project, project)
       |> assign(:workspace, project.workspace)
       |> assign(:page_title, version_label(version))
       |> assign_viewer(entity_type, entity, snapshot)}
    end
  end

  defp assign_view_error(socket, entity_type, entity_id_str, version_number_str, reason) do
    kind = view_error_kind(reason)
    log_view_error(kind, entity_type, entity_id_str, version_number_str, reason)

    socket
    |> assign(:view_error, to_string(kind))
    |> assign(:page_title, view_error_title(kind))
  end

  defp view_error_kind({:invalid_expected_checksum, _}), do: :integrity
  defp view_error_kind({:checksum_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:compressed_size_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:invalid_expected_compressed_size, _}), do: :integrity
  defp view_error_kind(:entity_version_storage_key_mismatch), do: :integrity

  defp view_error_kind(reason)
       when reason in [
              :invalid_entity_id,
              :invalid_version_number,
              :entity_not_found,
              :version_not_found,
              :entity_version_not_found,
              :not_found
            ], do: :not_found

  defp view_error_kind(_reason), do: :unreadable

  defp log_view_error(:not_found, entity_type, entity_id_str, version_number_str, reason) do
    Logger.info("Version viewer: no #{entity_type} #{entity_id_str} v#{version_number_str} to show (#{inspect(reason)})")
  end

  defp log_view_error(kind, entity_type, entity_id_str, version_number_str, reason) do
    Logger.warning(
      "Version viewer: #{entity_type} #{entity_id_str} v#{version_number_str} is #{kind} (#{inspect(reason)})"
    )
  end

  defp view_error_title(:not_found), do: dgettext("versioning", "Version not found")
  defp view_error_title(_kind), do: dgettext("versioning", "Version unavailable")

  defp parse_id(value, error_reason) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> {:error, error_reason}
    end
  end

  defp fetch_entity(:scene, project_id, entity_id), do: fetch_present(Scenes.get_scene_brief(project_id, entity_id))
  defp fetch_entity(:sheet, project_id, entity_id), do: fetch_present(Sheets.get_sheet(project_id, entity_id))

  defp fetch_present(nil), do: {:error, :entity_not_found}
  defp fetch_present(entity), do: {:ok, entity}

  defp fetch_version(entity_type, entity_id, version_number) do
    case Versioning.get_version(to_string(entity_type), entity_id, version_number) do
      nil -> {:error, :version_not_found}
      version -> {:ok, version}
    end
  end

  defp load_version_snapshot(_entity_type, version), do: Versioning.load_version_snapshot(version)

  defp assign_viewer(socket, :scene, _scene, snapshot) do
    viewer = Versioning.serialize_scene(snapshot)

    assign(socket, :surface, scene_surface(socket.assigns, viewer))
  end

  defp assign_viewer(socket, :sheet, _sheet, snapshot) do
    blocks = Versioning.serialize_sheet(snapshot)

    socket
    |> assign(:sheet, sheet_header(snapshot, socket.assigns.project.id))
    |> assign(:surface, sheet_surface(socket.assigns, blocks))
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end

  defp scene_surface(assigns, viewer) do
    %{
      canvas: %{
        id: "scene-version-canvas-#{assigns.entity_id}-#{assigns.version_number}",
        sceneData: scene_data(viewer),
        pins: Enum.map(viewer.pins, &scene_pin/1),
        zones: Enum.map(viewer.zones, &scene_zone/1),
        connections: Enum.map(viewer.connections, &scene_connection/1),
        annotations: Enum.map(viewer.annotations, &scene_annotation/1),
        layers: Enum.map(viewer.layers, &scene_layer/1),
        activeTool: "select",
        editMode: false,
        canEdit: false,
        collaboration: %{userId: assigns.current_scope.user.id, locks: %{}}
      },
      dock: %{
        activeTool: "select",
        editMode: false,
        compact: true,
        pendingSheet: nil,
        projectSheets: [],
        workspaceSlug: assigns.workspace.slug,
        projectSlug: assigns.project.slug,
        sceneId: viewer.id
      }
    }
  end

  defp scene_data(viewer) do
    %{
      id: viewer.id,
      name: viewer.name,
      width: viewer.width,
      height: viewer.height,
      defaultZoom: viewer.default_zoom,
      defaultCenterX: viewer.default_center_x,
      defaultCenterY: viewer.default_center_y,
      scaleUnit: viewer.scale_unit,
      scaleValue: viewer.scale_value,
      fogColor: Map.get(viewer, :fog_color, "#000000"),
      fogOpacity: Map.get(viewer, :fog_opacity, 0.85),
      explorationDisplayMode: Map.get(viewer, :exploration_display_mode),
      backgroundUrl: viewer.background_url
    }
  end

  defp scene_layer(layer) do
    %{
      id: layer.id,
      name: layer.name,
      visible: layer.visible,
      isDefault: layer.is_default,
      position: layer.position,
      fogEnabled: layer.fog_enabled
    }
  end

  defp scene_pin(pin) do
    %{
      id: pin.id,
      positionX: pin.position_x,
      positionY: pin.position_y,
      pinType: pin.pin_type,
      icon: pin.icon,
      color: pin.color,
      opacity: pin.opacity,
      label: pin.label,
      shortcut: pin.shortcut,
      hidden: pin.hidden,
      tooltip: pin.tooltip,
      size: pin.size,
      position: pin.position,
      locked: pin.locked,
      condition: pin.condition,
      conditionEffect: pin.condition_effect,
      layerId: pin.layer_id,
      sheetId: pin.sheet_id,
      flowId: pin.flow_id,
      iconAssetId: pin.icon_asset_id,
      sheetAvatarUrl: nil,
      iconAssetUrl: pin.icon_asset_url
    }
  end

  defp scene_zone(zone) do
    %{
      id: zone.id,
      name: zone.name,
      shortcut: zone.shortcut,
      vertices: zone.vertices,
      fillColor: zone.fill_color,
      borderColor: zone.border_color,
      borderWidth: zone.border_width,
      borderStyle: zone.border_style,
      opacity: zone.opacity,
      targetType: zone.target_type,
      targetId: zone.target_id,
      tooltip: zone.tooltip,
      position: zone.position,
      locked: zone.locked,
      actionType: zone.action_type,
      actionData: zone.action_data,
      condition: zone.condition,
      conditionEffect: zone.condition_effect,
      hidden: zone.hidden,
      layerId: zone.layer_id
    }
  end

  defp scene_connection(conn) do
    %{
      id: conn.id,
      lineStyle: conn.line_style,
      lineWidth: conn.line_width,
      color: conn.color,
      label: conn.label,
      bidirectional: conn.bidirectional,
      showLabel: conn.show_label,
      waypoints: conn.waypoints,
      fromPinId: conn.from_pin_id,
      toPinId: conn.to_pin_id,
      fromStop: conn.from_stop,
      toStop: conn.to_stop,
      fromPauseMs: conn.from_pause_ms,
      toPauseMs: conn.to_pause_ms
    }
  end

  defp scene_annotation(annotation) do
    %{
      id: annotation.id,
      text: annotation.text,
      positionX: annotation.position_x,
      positionY: annotation.position_y,
      fontSize: annotation.font_size,
      color: annotation.color,
      position: annotation.position,
      locked: annotation.locked,
      layerId: annotation.layer_id
    }
  end

  defp sheet_header(snapshot, project_id) do
    %{
      id: snapshot["original_id"] || -1,
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      color: snapshot["color"],
      bannerUrl: snapshot_asset_url(snapshot["banner_asset_id"], snapshot, project_id),
      avatars: sheet_avatars(snapshot, project_id)
    }
  end

  defp sheet_avatars(snapshot, project_id) do
    case snapshot_asset_url(snapshot["avatar_asset_id"], snapshot, project_id) do
      nil -> []
      url -> [%{id: "snapshot-default-avatar", url: url, name: nil, is_default: true}]
    end
  end

  defp sheet_surface(assigns, blocks) do
    %{
      tabs: %{currentTab: "content", canEdit: false, compact: true},
      content: %{
        blocks: Enum.map(blocks, &sheet_layout_item/1),
        inheritedGroups: [],
        workspaceSlug: assigns.workspace.slug,
        projectSlug: assigns.project.slug,
        canEdit: false,
        formulaEditing: nil,
        blockLocks: %{},
        currentUserId: assigns.current_scope.user.id
      }
    }
  end

  defp sheet_layout_item(block), do: %{type: "full_width", block: sheet_block(block)}

  defp sheet_block(block) do
    %{
      id: block.id,
      type: block.type,
      position: block.position,
      is_constant: block.is_constant,
      variable_name: block.variable_name,
      scope: block.scope,
      inherited: false,
      detached: false,
      required: block.required,
      column_group_id: nil,
      column_index: 0,
      config: block.config,
      value: block.value,
      columns: block.table_columns,
      rows: block.table_rows,
      collapsed: get_in(block.config, ["collapsed"]) || false,
      gallery_images: [],
      reference_target: nil,
      can_reattach: false
    }
  end

  defp snapshot_asset_url(nil, _snapshot, _project_id), do: nil

  defp snapshot_asset_url(asset_id, snapshot, project_id) do
    metadata =
      snapshot
      |> Map.get("asset_metadata", %{})
      |> Map.get(to_string(asset_id), %{})

    PrivateMedia.project_snapshot_asset_url(project_id, metadata)
  end
end
