defmodule StoryarnWeb.SceneLive.VersionViewer do
  @moduledoc """
  Read-only Scene version surface embedded by the comparison view.

  Scene identity and version storage are resolved through the public Scenes
  facade. The Vue-facing snapshot mapping remains in StoryarnWeb.
  """

  use StoryarnWeb, :live_view

  alias Storyarn.Scenes
  alias StoryarnWeb.SceneLive.VersionSnapshotSerializer

  require Logger

  @not_found_error_reasons [
    :invalid_entity_id,
    :invalid_version_number,
    :entity_version_not_found,
    :not_found
  ]

  @impl true
  def render(%{view_error: _error} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/versioning/viewer/VersionViewerError"
        v-socket={@socket}
        v-inject="compare-layout"
        id="scene-version-viewer-error"
        class="w-full h-full"
        reason={@view_error}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  def render(assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/scene/show/SceneCompactSurface"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"scene-version-viewer-#{@scene.id}-#{@version_number}"}
        class="h-full relative"
        surface={@surface}
      />
    </StoryarnWeb.Components.CompareLayout.compare>
    """
  end

  @impl true
  def mount(%{"id" => scene_id_string, "version_number" => version_number_string}, _session, socket) do
    case load_version_view(socket, scene_id_string, version_number_string) do
      {:ok, loaded_socket} ->
        {:ok, loaded_socket, layout: false}

      {:error, reason} ->
        {:ok, assign_view_error(socket, scene_id_string, version_number_string, reason), layout: false}
    end
  end

  defp load_version_view(socket, scene_id_string, version_number_string) do
    project = socket.assigns.project

    with {:ok, scene_id} <- parse_id(scene_id_string, :invalid_entity_id),
         {:ok, version_number} <- parse_id(version_number_string, :invalid_version_number),
         scene when not is_nil(scene) <- Scenes.get_scene_brief(project.id, scene_id),
         version when not is_nil(version) <- Scenes.get_version(scene_id, version_number),
         {:ok, snapshot} <- Scenes.load_version_snapshot(version) do
      viewer = VersionSnapshotSerializer.serialize(snapshot, project.id)

      loaded_socket =
        socket
        |> assign(:scene, scene)
        |> assign(:version_number, version_number)
        |> assign(:page_title, version_label(version))

      {:ok, assign(loaded_socket, :surface, scene_surface(loaded_socket.assigns, viewer))}
    else
      nil -> {:error, :not_found}
      {:error, _reason} = error -> error
    end
  end

  defp assign_view_error(socket, scene_id_string, version_number_string, reason) do
    kind = view_error_kind(reason)
    log_view_error(kind, scene_id_string, version_number_string, reason)

    socket
    |> assign(:view_error, to_string(kind))
    |> assign(:page_title, view_error_title(kind))
  end

  defp view_error_kind({:invalid_expected_checksum, _value}), do: :integrity
  defp view_error_kind({:checksum_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:compressed_size_mismatch, _expected, _actual}), do: :integrity
  defp view_error_kind({:invalid_expected_compressed_size, _value}), do: :integrity
  defp view_error_kind(:entity_version_storage_key_mismatch), do: :integrity
  defp view_error_kind(reason) when reason in @not_found_error_reasons, do: :not_found
  defp view_error_kind(_reason), do: :unreadable

  defp log_view_error(:not_found, scene_id_string, version_number_string, reason) do
    Logger.info("Version viewer: no scene #{scene_id_string} v#{version_number_string} to show (#{inspect(reason)})")
  end

  defp log_view_error(kind, scene_id_string, version_number_string, reason) do
    Logger.warning("Version viewer: scene #{scene_id_string} v#{version_number_string} is #{kind} (#{inspect(reason)})")
  end

  defp view_error_title(:not_found), do: dgettext("versioning", "Version not found")
  defp view_error_title(_kind), do: dgettext("versioning", "Version unavailable")

  defp parse_id(value, error_reason) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _invalid -> {:error, error_reason}
    end
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
        id: "scene-version-canvas-#{assigns.scene.id}-#{assigns.version_number}",
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
      labelMode: zone.label_mode,
      labelFontSize: zone.label_font_size,
      labelFontFamily: zone.label_font_family,
      labelFontWeight: zone.label_font_weight,
      labelFontStyle: zone.label_font_style,
      labelIconAssetId: zone.label_icon_asset_id,
      labelIconAssetUrl: zone.label_icon_asset_url,
      condition: zone.condition,
      conditionEffect: zone.condition_effect,
      isWalkable: zone.is_walkable,
      hidden: zone.hidden,
      layerId: zone.layer_id
    }
  end

  defp scene_connection(connection) do
    %{
      id: connection.id,
      lineStyle: connection.line_style,
      lineWidth: connection.line_width,
      color: connection.color,
      label: connection.label,
      bidirectional: connection.bidirectional,
      showLabel: connection.show_label,
      waypoints: connection.waypoints,
      fromPinId: connection.from_pin_id,
      toPinId: connection.to_pin_id,
      fromStop: connection.from_stop,
      toStop: connection.to_stop,
      fromPauseMs: connection.from_pause_ms,
      toPauseMs: connection.to_pause_ms
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
end
