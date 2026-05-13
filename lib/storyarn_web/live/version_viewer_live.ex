defmodule StoryarnWeb.VersionViewerLive do
  @moduledoc false

  use StoryarnWeb, :live_view

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Scenes
  alias Storyarn.Sheets
  alias Storyarn.Versioning

  @impl true
  def render(%{entity_type: :flow} = assigns) do
    ~H"""
    <StoryarnWeb.Components.CompareLayout.compare socket={@socket} flash={@flash}>
      <.vue
        v-component="live/flow/show/FlowCanvas"
        v-socket={@socket}
        v-inject="compare-layout"
        id={"flow-version-viewer-#{@entity_id}-#{@version_number}"}
        class="w-full h-full"
        flow-data={Jason.encode!(@flow_data)}
        variable-map={Jason.encode!(@variable_map)}
        loading={false}
        readonly={true}
        user-id={@current_scope.user.id}
        user-color={Collaboration.user_color(@current_scope.user.id)}
        canvas-id={"flow-version-canvas-#{@entity_id}-#{@version_number}"}
        toolbar-data={Jason.encode!(@toolbar_data)}
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

    with {:ok, entity_id} <- parse_id(entity_id_str),
         {:ok, version_number} <- parse_id(version_number_str),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(socket.assigns.current_scope, workspace_slug, project_slug),
         {:ok, entity} <- fetch_entity(entity_type, project.id, entity_id),
         version when not is_nil(version) <-
           Versioning.get_version(to_string(entity_type), entity_id, version_number),
         {:ok, snapshot} <- Versioning.load_version_snapshot(version) do
      socket =
        socket
        |> assign(:entity_type, entity_type)
        |> assign(:entity_id, entity_id)
        |> assign(:version_number, version_number)
        |> assign(:project, project)
        |> assign(:workspace, project.workspace)
        |> assign(:page_title, version_label(version))
        |> assign_viewer(entity_type, entity, snapshot)

      {:ok, socket, layout: false}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, dgettext("versioning", "Version not found"))
         |> redirect(to: ~p"/workspaces"), layout: false}
    end
  end

  defp parse_id(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  defp fetch_entity(:flow, project_id, entity_id), do: fetch_present(Flows.get_flow_brief(project_id, entity_id))
  defp fetch_entity(:scene, project_id, entity_id), do: fetch_present(Scenes.get_scene_brief(project_id, entity_id))
  defp fetch_entity(:sheet, project_id, entity_id), do: fetch_present(Sheets.get_sheet(project_id, entity_id))

  defp fetch_present(nil), do: :error
  defp fetch_present(entity), do: {:ok, entity}

  defp assign_viewer(socket, :flow, _flow, snapshot) do
    referenced_sheets = snapshot["referenced_sheets"] || %{}

    socket
    |> assign(:flow_data, Versioning.serialize_flow(snapshot))
    |> assign(:variable_map, flow_variable_map(referenced_sheets))
    |> assign(:toolbar_data, flow_toolbar_data(referenced_sheets))
  end

  defp assign_viewer(socket, :scene, _scene, snapshot) do
    viewer = Versioning.serialize_scene(snapshot)

    assign(socket, :surface, scene_surface(socket.assigns, viewer))
  end

  defp assign_viewer(socket, :sheet, _sheet, snapshot) do
    blocks = Versioning.serialize_sheet(snapshot)

    socket
    |> assign(:sheet, sheet_header(snapshot))
    |> assign(:surface, sheet_surface(socket.assigns, blocks))
  end

  defp version_label(version) do
    if version.title do
      "v#{version.version_number} — #{version.title}"
    else
      "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
    end
  end

  defp flow_variable_map(referenced_sheets) do
    Map.new(referenced_sheets, fn {id, sheet} ->
      {to_string(id),
       %{
         id: sheet["id"],
         name: sheet["name"],
         avatar_url: sheet["avatar_url"],
         banner_url: sheet["banner_url"],
         color: sheet["color"],
         avatars: [],
         gallery_images: []
       }}
    end)
  end

  defp flow_toolbar_data(referenced_sheets) do
    %{
      hubs: [],
      projectFlows: [],
      sheetAvatars:
        Enum.map(referenced_sheets, fn {_id, sheet} ->
          %{id: sheet["id"], name: sheet["name"], color: sheet["color"], avatars: []}
        end),
      subflowExits: [],
      referencingJumps: [],
      referencingFlows: []
    }
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
      fogEnabled: layer.fog_enabled,
      fogColor: layer.fog_color,
      fogOpacity: layer.fog_opacity
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
      toPinId: conn.to_pin_id
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

  defp sheet_header(snapshot) do
    %{
      id: snapshot["original_id"] || -1,
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      color: snapshot["color"],
      bannerUrl: snapshot_asset_url(snapshot["banner_asset_id"], snapshot),
      avatars: sheet_avatars(snapshot)
    }
  end

  defp sheet_avatars(snapshot) do
    case snapshot_asset_url(snapshot["avatar_asset_id"], snapshot) do
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

  defp snapshot_asset_url(nil, _snapshot), do: nil

  defp snapshot_asset_url(asset_id, snapshot) do
    snapshot
    |> Map.get("asset_metadata", %{})
    |> Map.get(to_string(asset_id), %{})
    |> Map.get("url")
  end
end
