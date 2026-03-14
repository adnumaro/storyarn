defmodule StoryarnWeb.VersionLive.Viewer do
  @moduledoc """
  Readonly LiveView that renders a historical version snapshot for inspection.
  Used inside an iframe for the split-view comparison feature.

  Supports node/element selection with a property inspection panel,
  matching the editor UI for readonly browsing.
  """

  use StoryarnWeb, :live_view

  import StoryarnWeb.Components.BlockComponents, only: [block_component: 1]
  import StoryarnWeb.Components.ConditionBuilder
  import StoryarnWeb.Components.InstructionBuilder

  import StoryarnWeb.Components.SheetComponents

  alias Storyarn.Assets
  alias Storyarn.Projects
  alias Storyarn.Sheets
  alias Storyarn.Versioning
  alias StoryarnWeb.FlowLive.Helpers.HtmlSanitizer

  @valid_entity_types ~w(flow sheet scene)

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen w-screen overflow-hidden flex flex-col bg-base-100">
      <%!-- Content area with optional properties panel --%>
      <div class="flex-1 overflow-hidden flex">
        <%!-- Scene layer sidebar (read-only controls) --%>
        <div
          :if={@entity_type == "scene" && @layers != []}
          class="w-52 flex-shrink-0 border-r border-base-300 bg-base-200/50 overflow-y-auto"
        >
          <div class="px-3 py-2 border-b border-base-300">
            <span class="text-xs font-medium text-base-content/60 flex items-center gap-1.5">
              <.icon name="layers" class="size-3.5" />
              {dgettext("scenes", "Layers")}
            </span>
          </div>
          <div class="flex flex-col gap-0.5 p-1">
            <div :for={layer <- @layers} class="flex items-center group">
              <button
                type="button"
                phx-click="toggle_layer_visibility"
                phx-value-id={layer.id}
                class="btn btn-ghost btn-xs btn-square shrink-0"
                title={dgettext("scenes", "Toggle visibility")}
              >
                <.icon
                  name={if(layer.visible, do: "eye", else: "eye-off")}
                  class={"size-3 #{unless layer.visible, do: "opacity-40"}"}
                />
              </button>
              <span class={"flex-1 text-xs truncate px-1 #{unless layer.visible, do: "opacity-40 line-through"}"}>
                {layer.name}
              </span>
              <button
                type="button"
                phx-click="toggle_layer_fog"
                phx-value-id={layer.id}
                class={[
                  "btn btn-ghost btn-xs btn-square shrink-0",
                  !layer.fog_enabled && "opacity-0 group-hover:opacity-100 transition-opacity"
                ]}
                title={
                  if(layer.fog_enabled,
                    do: dgettext("scenes", "Disable Fog"),
                    else: dgettext("scenes", "Enable Fog")
                  )
                }
              >
                <.icon
                  name={if(layer.fog_enabled, do: "cloud-fog", else: "cloud")}
                  class={"size-3 #{if layer.fog_enabled, do: "text-warning", else: "opacity-50"}"}
                />
              </button>
            </div>
          </div>
        </div>

        <%!-- Canvas / content area --%>
        <div class="flex-1 overflow-hidden relative">
          <%= case @entity_type do %>
            <% "flow" -> %>
              <div
                id="snapshot-flow-canvas"
                phx-hook="FlowCanvas"
                phx-update="ignore"
                class="absolute inset-0"
                data-flow={Jason.encode!(@viewer_data)}
                data-sheets={Jason.encode!(@sheets_map)}
                data-locks={Jason.encode!(%{})}
                data-user-id={@current_scope.user.id}
                data-labels={Jason.encode!(%{})}
                data-readonly="true"
              >
              </div>
            <% "scene" -> %>
              <div
                id="snapshot-scene-canvas"
                phx-hook="SceneCanvas"
                phx-update="ignore"
                class="absolute inset-0"
                data-scene={Jason.encode!(@viewer_data)}
                data-i18n={Jason.encode!(scene_i18n())}
                data-current-user-id={@current_scope.user.id}
              >
                <div id="scene-canvas-container" class="h-full w-full"></div>
              </div>
            <% "sheet" -> %>
              <div class="h-full overflow-y-auto p-4">
                <div class="max-w-[950px] mx-auto bg-base-200 rounded-[20px] p-5">
                  <%!-- Banner --%>
                  <div
                    :if={@sheet_banner_url}
                    class="relative h-48 sm:h-56 lg:h-64 overflow-hidden rounded-2xl mb-6"
                  >
                    <img src={@sheet_banner_url} alt="" class="w-full h-full object-cover" />
                    <div class="absolute bottom-3 right-3 z-10">
                      <div class="flex items-center gap-1.5 px-2 py-1 rounded-lg bg-base-100/80 text-xs font-mono">
                        <span
                          class="size-3.5 rounded border border-base-content/20"
                          style={"background-color: #{safe_color(@sheet_color)}"}
                        />
                        {safe_color(@sheet_color)}
                      </div>
                    </div>
                  </div>
                  <div
                    :if={!@sheet_banner_url}
                    class="relative h-48 sm:h-56 lg:h-64 overflow-hidden rounded-2xl mb-6"
                    style={"background-color: #{safe_color(@sheet_color)}"}
                  >
                    <div class="absolute bottom-3 right-3 z-10">
                      <div class="flex items-center gap-1.5 px-2 py-1 rounded-lg bg-base-100/80 text-xs font-mono">
                        <span
                          class="size-3.5 rounded border border-base-content/20"
                          style={"background-color: #{safe_color(@sheet_color)}"}
                        />
                        {safe_color(@sheet_color)}
                      </div>
                    </div>
                  </div>

                  <%!-- Header: avatar + name --%>
                  <div class="flex items-start gap-4 mb-8">
                    <.sheet_avatar avatar_asset={@sheet_avatar} name={@sheet_name} size="xl" />
                    <div class="flex-1">
                      <h1 class="text-3xl font-bold px-2 -mx-2 py-1">{@sheet_name}</h1>
                      <div
                        :if={@sheet_shortcut}
                        class="text-sm text-base-content/50 px-2 -mx-2 mt-1"
                      >
                        <span class="text-base-content/50">#</span> {@sheet_shortcut}
                      </div>
                    </div>
                  </div>

                  <%!-- Blocks (clickable for inspection) --%>
                  <div class="flex flex-col gap-1">
                    <div
                      :for={block <- @viewer_data}
                      class={[
                        "cursor-pointer rounded-lg transition-colors",
                        @selected_element && @selected_element.block_id == block.id &&
                          "ring-2 ring-primary/50"
                      ]}
                      phx-click="select_block"
                      phx-value-id={block.id}
                    >
                      <.block_component
                        block={block}
                        can_edit={false}
                        editing_block_id={nil}
                        selected_block_id={nil}
                        table_data={@table_data}
                      />
                    </div>
                  </div>
                </div>
              </div>
          <% end %>
        </div>

        <%!-- Property inspection panel --%>
        <div
          :if={@selected_element}
          class="w-72 flex-shrink-0 border-l border-base-300 bg-base-100 overflow-y-auto"
        >
          <div class="flex items-center justify-between px-3 py-2 bg-base-200 border-b border-base-300">
            <span class="text-xs font-medium text-base-content/70">
              {gettext("Properties")}
            </span>
            <button
              type="button"
              class="btn btn-ghost btn-xs btn-square"
              phx-click="deselect"
              aria-label={gettext("Close")}
            >
              <.icon name="x" class="size-3.5" />
            </button>
          </div>
          <div class="p-3 space-y-3">
            <.property_panel element={@selected_element} variables={@variables} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Snapshot mode — loads a historical version for any entity type
  @impl true
  def mount(
        %{
          "workspace_slug" => workspace_slug,
          "project_slug" => project_slug,
          "entity_type" => entity_type,
          "entity_id" => entity_id_str,
          "version_number" => version_number_str
        },
        _session,
        socket
      ) do
    with true <- entity_type in @valid_entity_types,
         {entity_id, ""} <- Integer.parse(entity_id_str),
         {version_number, ""} <- Integer.parse(version_number_str),
         {:ok, project, _membership} <-
           Projects.get_project_by_slugs(
             socket.assigns.current_scope,
             workspace_slug,
             project_slug
           ),
         version when not is_nil(version) <-
           Versioning.get_version(entity_type, entity_id, version_number),
         true <- version.project_id == project.id,
         {:ok, snapshot} <- Versioning.load_version_snapshot(version) do
      viewer_data =
        entity_type
        |> serialize_snapshot(snapshot)
        |> maybe_resolve_scene_assets(entity_type, snapshot, project.id)

      element_index = build_element_index(entity_type, snapshot)
      table_data = build_table_data(entity_type, viewer_data)
      sheets_map = build_sheets_map(entity_type, snapshot, project.id)
      variables = build_variables(entity_type, project.id)

      version_label =
        if version.title do
          "v#{version.version_number} — #{version.title}"
        else
          "v#{version.version_number} — #{version.change_summary || gettext("Auto-snapshot")}"
        end

      sheet_header = sheet_header_from_snapshot(entity_type, snapshot, project.id)

      {:ok,
       socket
       |> assign(:entity_type, entity_type)
       |> assign(:viewer_data, viewer_data)
       |> assign(:version, version)
       |> assign(:version_label, version_label)
       |> assign(:page_title, version_label)
       |> assign(:selected_element, nil)
       |> assign(:element_index, element_index)
       |> assign(:table_data, table_data)
       |> assign(:sheets_map, sheets_map)
       |> assign(:variables, variables)
       |> assign(:layers, build_scene_layers(entity_type, viewer_data))
       |> assign(sheet_header)}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Version not found"))
         |> redirect(to: ~p"/workspaces")}
    end
  end

  # Catch-all for invalid params
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> put_flash(:error, gettext("Invalid version URL"))
     |> redirect(to: ~p"/workspaces")}
  end

  # ========== Selection Events ==========

  @impl true
  def handle_event("node_selected", %{"id" => id}, socket) do
    element = Map.get(socket.assigns.element_index, id)
    {:noreply, assign(socket, :selected_element, element)}
  end

  def handle_event("select_element", %{"type" => type, "id" => id}, socket)
      when type in ~w(pin zone annotation connection) do
    element = Map.get(socket.assigns.element_index, id)
    {:noreply, assign(socket, :selected_element, element)}
  end

  def handle_event("select_block", %{"id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        element = Map.get(socket.assigns.element_index, id)
        {:noreply, assign(socket, :selected_element, element)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("deselect", _params, socket) do
    {:noreply, assign(socket, :selected_element, nil)}
  end

  # ========== Scene Layer Events (local-only, no DB writes) ==========

  def handle_event("toggle_layer_visibility", %{"id" => id_str}, socket) do
    id = parse_layer_id(id_str)

    layers =
      Enum.map(socket.assigns.layers, fn layer ->
        if layer.id == id, do: %{layer | visible: !layer.visible}, else: layer
      end)

    layer = Enum.find(layers, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:layers, layers)
     |> push_event("layer_visibility_changed", %{id: id, visible: layer.visible})}
  end

  def handle_event("toggle_layer_fog", %{"id" => id_str}, socket) do
    id = parse_layer_id(id_str)

    layers =
      Enum.map(socket.assigns.layers, fn layer ->
        if layer.id == id, do: %{layer | fog_enabled: !layer.fog_enabled}, else: layer
      end)

    layer = Enum.find(layers, &(&1.id == id))

    {:noreply,
     socket
     |> assign(:layers, layers)
     |> push_event("layer_fog_changed", %{
       id: id,
       fog_enabled: layer.fog_enabled,
       fog_color: layer.fog_color,
       fog_opacity: layer.fog_opacity
     })}
  end

  # Ignore all other events — this is a readonly viewer
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  # ========== Private: Serialization ==========

  defp serialize_snapshot("flow", snapshot), do: Versioning.serialize_flow(snapshot)
  defp serialize_snapshot("scene", snapshot), do: Versioning.serialize_scene(snapshot)
  defp serialize_snapshot("sheet", snapshot), do: Versioning.serialize_sheet(snapshot)

  # For scene snapshots, re-resolve asset URLs using the robust resolver (handles
  # old snapshots missing "url" in asset_metadata by falling back to DB/blob lookup).
  defp maybe_resolve_scene_assets(viewer_data, "scene", snapshot, project_id) do
    metadata = snapshot["asset_metadata"] || %{}
    blob_hashes = snapshot["asset_blob_hashes"] || %{}

    background_url =
      resolve_snapshot_asset_url(
        snapshot["background_asset_id"],
        metadata,
        blob_hashes,
        project_id
      )

    pins =
      Enum.map(viewer_data.pins, fn pin ->
        icon_url =
          if pin.icon_asset_url == nil and pin[:icon_asset_id] do
            resolve_snapshot_asset_url(pin.icon_asset_id, metadata, blob_hashes, project_id)
          else
            pin.icon_asset_url
          end

        %{pin | icon_asset_url: icon_url}
      end)

    %{viewer_data | background_url: background_url, pins: pins}
  end

  defp maybe_resolve_scene_assets(viewer_data, _entity_type, _snapshot, _project_id),
    do: viewer_data

  # Build table_data map keyed by block ID, as BlockComponents.block_component expects
  defp build_table_data("sheet", blocks) when is_list(blocks) do
    Map.new(blocks, fn block ->
      {block.id, %{columns: block.table_columns, rows: block.table_rows}}
    end)
  end

  defp build_table_data(_entity_type, _data), do: %{}

  # ========== Private: Element Index ==========

  defp build_element_index("flow", snapshot) do
    nodes = snapshot["nodes"] || []

    nodes
    |> Enum.with_index()
    |> Map.new(fn {node, idx} ->
      id = -(idx + 1)

      {id,
       %{
         kind: :node,
         type: node["type"],
         data: node["data"] || %{},
         position_x: node["position_x"],
         position_y: node["position_y"],
         node_index_id: idx
       }}
    end)
  end

  defp build_element_index("scene", snapshot) do
    layers = snapshot["layers"] || []

    # Use the same global counter scheme as SnapshotViewer.serialize_scene_layers
    {_results, {index, _counter}} =
      layers
      |> Enum.with_index()
      |> Enum.map_reduce({%{}, 1}, fn {layer, layer_idx}, {acc, counter} ->
        layer_name = layer["name"] || ""

        {pin_entries, counter} = build_pin_entries(layer, layer_name, counter)
        {zone_entries, counter} = build_zone_entries(layer, layer_name, counter)
        {ann_entries, counter} = build_annotation_entries(layer, layer_name, counter)

        merged =
          acc
          |> Map.merge(pin_entries)
          |> Map.merge(zone_entries)
          |> Map.merge(ann_entries)

        {layer_idx, {merged, counter}}
      end)

    index
  end

  defp build_element_index("sheet", snapshot) do
    blocks = snapshot["blocks"] || []

    blocks
    |> Enum.with_index()
    |> Map.new(fn {block, idx} ->
      block_id = -(idx + 1)
      config = block["config"] || %{}
      {columns, rows} = enrich_table_data(block["table_data"])

      {block_id,
       %{
         kind: :block,
         block_id: block_id,
         type: block["type"],
         label: config["label"],
         variable_name: block["variable_name"],
         scope: block["scope"] || "self",
         required: block["required"] || false,
         is_constant: block["is_constant"] || false,
         value: block["value"],
         config: config,
         columns: columns,
         rows: rows,
         row_count: if(rows, do: length(rows), else: nil)
       }}
    end)
  end

  defp enrich_table_data(nil), do: {nil, nil}

  defp enrich_table_data(table_data) do
    cols = table_data["columns"] || []
    raw_rows = table_data["rows"] || []

    formula_slugs =
      cols |> Enum.filter(&(&1["type"] == "formula")) |> MapSet.new(& &1["slug"])

    enriched_cols =
      Enum.map(cols, fn col ->
        if MapSet.member?(formula_slugs, col["slug"]),
          do: Map.put(col, "_formula_groups", build_formula_groups(raw_rows, col["slug"])),
          else: col
      end)

    {enriched_cols, raw_rows}
  end

  defp build_formula_groups(rows, slug) do
    rows
    |> Enum.map(fn row ->
      cell = (row["cells"] || %{})[slug]

      %{
        row_name: row["name"],
        expression: if(is_map(cell), do: cell["expression"]),
        bindings: if(is_map(cell), do: cell["bindings"] || %{}, else: %{})
      }
    end)
    |> Enum.filter(&(&1.expression && &1.expression != ""))
    |> Enum.group_by(fn rf -> {rf.expression, rf.bindings} end)
    |> Enum.map(fn {{expr, bindings}, grouped_rows} ->
      %{
        expression: expr,
        bindings: bindings,
        row_names: Enum.map(grouped_rows, & &1.row_name),
        all_rows: length(grouped_rows) == length(rows)
      }
    end)
  end

  # Scene element index helpers (use same global counter scheme as SnapshotViewer)

  defp build_pin_entries(layer, layer_name, counter) do
    (layer["pins"] || [])
    |> Enum.map_reduce(counter, fn pin, c ->
      entry =
        {-c,
         %{
           kind: :pin,
           type: pin["pin_type"] || "location",
           label: pin["label"],
           tooltip: pin["tooltip"],
           icon: pin["icon"],
           color: pin["color"],
           size: pin["size"],
           layer_name: layer_name,
           position_x: pin["position_x"],
           position_y: pin["position_y"],
           action_type: pin["action_type"],
           locked: pin["locked"]
         }}

      {entry, c + 1}
    end)
    |> then(fn {entries, c} -> {Map.new(entries), c} end)
  end

  defp build_zone_entries(layer, layer_name, counter) do
    (layer["zones"] || [])
    |> Enum.map_reduce(counter, fn zone, c ->
      entry =
        {-c,
         %{
           kind: :zone,
           name: zone["name"],
           fill_color: zone["fill_color"],
           border_color: zone["border_color"],
           opacity: zone["opacity"],
           tooltip: zone["tooltip"],
           layer_name: layer_name,
           action_type: zone["action_type"],
           locked: zone["locked"]
         }}

      {entry, c + 1}
    end)
    |> then(fn {entries, c} -> {Map.new(entries), c} end)
  end

  defp build_annotation_entries(layer, layer_name, counter) do
    (layer["annotations"] || [])
    |> Enum.map_reduce(counter, fn ann, c ->
      entry =
        {-c,
         %{
           kind: :annotation,
           text: ann["text"],
           font_size: ann["font_size"],
           color: ann["color"],
           layer_name: layer_name
         }}

      {entry, c + 1}
    end)
    |> then(fn {entries, c} -> {Map.new(entries), c} end)
  end

  # ========== Private: Property Panel ==========

  attr :element, :map, required: true
  attr :variables, :list, default: []

  defp property_panel(%{element: %{kind: :node}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.prop_row label={gettext("Type")} value={@element.type} />
      <.prop_row
        :if={@element.data["technical_id"] && @element.data["technical_id"] != ""}
        label={gettext("Technical ID")}
        value={@element.data["technical_id"]}
      />
      <.prop_row
        :if={@element.data["text"] && @element.data["text"] != ""}
        label={gettext("Text")}
        rich_text={@element.data["text"]}
      />
      <.prop_row
        :if={@element.data["menu_text"] && @element.data["menu_text"] != ""}
        label={gettext("Menu Text")}
        value={@element.data["menu_text"]}
      />
      <.prop_row
        :if={@element.data["stage_directions"] && @element.data["stage_directions"] != ""}
        label={gettext("Stage Directions")}
        value={@element.data["stage_directions"]}
      />
      <.prop_row
        :if={@element.data["expression"] && @element.data["expression"] != ""}
        label={gettext("Expression")}
        value={@element.data["expression"]}
        mono
      />
      <%!-- Condition node: show condition builder read-only --%>
      <.node_condition_viewer
        :if={@element.type == "condition" && @element.data["condition"]}
        element={@element}
        variables={@variables}
        id={"node-cond-#{@element.node_index_id}"}
      />
      <%!-- Instruction node: show instruction builder read-only --%>
      <.node_instruction_viewer
        :if={@element.type == "instruction" && is_list(@element.data["assignments"])}
        element={@element}
        variables={@variables}
        id={"node-instr-#{@element.node_index_id}"}
      />
      <.prop_row
        :if={@element.data["color"]}
        label={gettext("Color")}
        value={@element.data["color"]}
      />
      <.prop_row
        :if={@element.data["name"] && @element.data["name"] != ""}
        label={gettext("Name")}
        value={@element.data["name"]}
      />
      <.responses_list
        :if={@element.data["responses"]}
        responses={@element.data["responses"]}
        variables={@variables}
        node_id={@element.node_index_id}
      />
      <.cases_list :if={@element.data["cases"]} cases={@element.data["cases"]} />
      <.prop_row
        label={gettext("Position")}
        value={"#{@element.position_x}, #{@element.position_y}"}
        mono
      />
    </div>
    """
  end

  defp property_panel(%{element: %{kind: :pin}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.prop_row label={gettext("Type")} value={@element.type} />
      <.prop_row :if={@element.label} label={gettext("Label")} value={@element.label} />
      <.prop_row :if={@element.tooltip} label={gettext("Tooltip")} value={@element.tooltip} />
      <.prop_row :if={@element.icon} label={gettext("Icon")} value={@element.icon} />
      <.prop_row :if={@element.color} label={gettext("Color")} value={@element.color} />
      <.prop_row :if={@element.size} label={gettext("Size")} value={@element.size} />
      <.prop_row label={gettext("Layer")} value={@element.layer_name} />
      <.prop_row
        label={gettext("Position")}
        value={"#{@element.position_x}, #{@element.position_y}"}
        mono
      />
      <.prop_row
        :if={@element.action_type && @element.action_type != "none"}
        label={gettext("Action")}
        value={@element.action_type}
      />
    </div>
    """
  end

  defp property_panel(%{element: %{kind: :zone}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.prop_row :if={@element.name} label={gettext("Name")} value={@element.name} />
      <.prop_row :if={@element.tooltip} label={gettext("Tooltip")} value={@element.tooltip} />
      <.prop_row
        :if={@element.fill_color}
        label={gettext("Fill Color")}
        value={@element.fill_color}
      />
      <.prop_row
        :if={@element.border_color}
        label={gettext("Border Color")}
        value={@element.border_color}
      />
      <.prop_row
        :if={@element.opacity}
        label={gettext("Opacity")}
        value={"#{@element.opacity}"}
      />
      <.prop_row
        :if={@element.action_type}
        label={gettext("Action")}
        value={@element.action_type}
      />
      <.prop_row :if={@element.locked} label={gettext("Locked")} value={gettext("Yes")} />
      <.prop_row label={gettext("Layer")} value={@element.layer_name} />
    </div>
    """
  end

  defp property_panel(%{element: %{kind: :annotation}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.prop_row :if={@element.text} label={gettext("Text")} value={@element.text} />
      <.prop_row :if={@element.color} label={gettext("Color")} value={@element.color} />
      <.prop_row label={gettext("Layer")} value={@element.layer_name} />
    </div>
    """
  end

  defp property_panel(%{element: %{kind: :block, columns: cols}} = assigns) when is_list(cols) do
    ~H"""
    <div class="space-y-3">
      <%!-- General --%>
      <div>
        <div class="text-[10px] font-semibold text-base-content/40 uppercase tracking-wider mb-1.5">
          {gettext("General")}
        </div>
        <div class="space-y-2">
          <.prop_row label={gettext("Type")} value={@element.type} />
          <.prop_row :if={@element.label} label={gettext("Label")} value={@element.label} />
          <.prop_row
            :if={@element.variable_name}
            label={if @element.is_constant, do: gettext("Slug"), else: gettext("Variable")}
            value={@element.variable_name}
            mono
          />
          <.prop_row label={gettext("Scope")} value={@element.scope} />
          <.prop_row :if={@element.is_constant} label={gettext("Constant")} value={gettext("Yes")} />
          <.prop_row :if={@element.required} label={gettext("Required")} value={gettext("Yes")} />
        </div>
      </div>

      <div class="border-t border-base-content/10" />

      <%!-- Table Properties --%>
      <div>
        <div class="text-[10px] font-semibold text-base-content/40 uppercase tracking-wider mb-1.5">
          {gettext("Table Properties")}
        </div>
        <.table_columns_panel columns={@element.columns} row_count={@element.row_count} />
      </div>
    </div>
    """
  end

  defp property_panel(%{element: %{kind: :block}} = assigns) do
    ~H"""
    <div class="space-y-2">
      <.prop_row label={gettext("Type")} value={@element.type} />
      <.prop_row :if={@element.label} label={gettext("Label")} value={@element.label} />
      <.prop_row
        :if={@element.variable_name}
        label={if @element.is_constant, do: gettext("Slug"), else: gettext("Variable")}
        value={@element.variable_name}
        mono
      />
      <.prop_row label={gettext("Scope")} value={@element.scope} />
      <.prop_row :if={@element.is_constant} label={gettext("Constant")} value={gettext("Yes")} />
      <.prop_row :if={@element.required} label={gettext("Required")} value={gettext("Yes")} />
      <.block_value_row :if={@element.value} value={@element.value} type={@element.type} />
      <.block_options_row
        :if={@element.type in ["select", "multi_select"] && is_list(@element.config["options"])}
        options={@element.config["options"]}
      />
    </div>
    """
  end

  defp property_panel(assigns) do
    ~H"""
    <p class="text-xs text-base-content/50 italic">{gettext("No properties available")}</p>
    """
  end

  # ========== Private: Property Row ==========

  attr :label, :string, required: true
  attr :value, :string, default: nil
  attr :rich_text, :string, default: nil
  attr :mono, :boolean, default: false

  defp prop_row(assigns) do
    assigns =
      if assigns.rich_text do
        assign(assigns, :sanitized, HtmlSanitizer.sanitize_html(assigns.rich_text))
      else
        assigns
      end

    ~H"""
    <div>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-0.5">
        {@label}
      </dt>
      <dd class={["text-xs text-base-content/80", @mono && "font-mono"]}>
        <%= if @rich_text do %>
          <div class="prose prose-xs max-w-none">
            {Phoenix.HTML.raw(@sanitized)}
          </div>
        <% else %>
          {@value || "—"}
        <% end %>
      </dd>
    </div>
    """
  end

  # ========== Private: Block Property Helpers ==========

  attr :value, :any, required: true
  attr :type, :string, required: true

  defp block_value_row(assigns) do
    assigns = assign(assigns, :display_value, format_block_value(assigns.value, assigns.type))

    ~H"""
    <.prop_row :if={@display_value} label={gettext("Value")} value={@display_value} />
    """
  end

  defp format_block_value(%{"text" => text}, _type) when is_binary(text) and text != "", do: text
  defp format_block_value(%{"number" => n}, _type) when not is_nil(n), do: to_string(n)
  defp format_block_value(%{"boolean" => b}, _type) when is_boolean(b), do: to_string(b)

  defp format_block_value(%{"selected" => sel}, _type) when is_binary(sel) and sel != "",
    do: sel

  defp format_block_value(%{"selected" => sel}, _type) when is_list(sel) and sel != [],
    do: Enum.join(sel, ", ")

  defp format_block_value(%{"date" => d}, _type) when is_binary(d) and d != "", do: d
  defp format_block_value(value, _type) when is_binary(value) and value != "", do: value
  defp format_block_value(_, _), do: nil

  attr :options, :list, required: true

  defp block_options_row(assigns) do
    ~H"""
    <div>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-1">
        {gettext("Options")}
      </dt>
      <div class="flex flex-wrap gap-1">
        <span
          :for={opt <- @options}
          class="text-[10px] px-1.5 py-0.5 rounded bg-base-200 text-base-content/70"
        >
          {opt["label"] || opt["value"]}
        </span>
      </div>
    </div>
    """
  end

  attr :columns, :list, required: true
  attr :row_count, :integer, required: true

  defp table_columns_panel(assigns) do
    ~H"""
    <div>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-1">
        {gettext("Columns")} ({length(@columns)})
      </dt>
      <div class="space-y-1.5">
        <div :for={col <- @columns} class="bg-base-200/50 rounded px-2 py-1.5">
          <div class="flex items-center justify-between">
            <span class="text-xs font-medium text-base-content/80">{col["name"]}</span>
            <span class="text-[10px] px-1.5 py-0.5 rounded bg-base-300/50 text-base-content/50">
              {col["type"]}
            </span>
          </div>
          <div :if={col["slug"]} class="text-[10px] font-mono text-base-content/40 mt-0.5">
            {col["slug"]}
          </div>
          <div class="flex gap-2 mt-0.5">
            <span :if={col["is_constant"]} class="text-[10px] text-base-content/40">
              {gettext("constant")}
            </span>
            <span :if={col["required"]} class="text-[10px] text-base-content/40">
              {gettext("required")}
            </span>
          </div>
          <%!-- Grouped formula details --%>
          <div :if={col["_formula_groups"]} class="mt-1.5 space-y-1.5">
            <div :for={group <- col["_formula_groups"]} class="border-l-2 border-info/30 pl-2">
              <div class="text-[10px] text-base-content/50">
                <%= if group.all_rows do %>
                  {gettext("all rows")}
                <% else %>
                  {Enum.join(group.row_names, ", ")}
                <% end %>
              </div>
              <div class="text-[10px] font-mono text-info/70 mt-0.5">{group.expression}</div>
              <div :if={group.bindings != %{}} class="mt-0.5 space-y-0.5">
                <div
                  :for={{symbol, binding} <- group.bindings}
                  class="flex items-center gap-1 text-[10px] text-base-content/40"
                >
                  <span class="font-mono text-info/60">{symbol}</span>
                  <span class="shrink-0">&rarr;</span>
                  <span class="font-mono">{format_binding(binding)}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="mt-2">
        <.prop_row label={gettext("Rows")} value={to_string(@row_count)} />
      </div>
    </div>
    """
  end

  defp format_binding(%{"type" => "same_row", "column_slug" => slug}) when is_binary(slug),
    do: slug

  defp format_binding(%{"type" => "variable", "ref" => ref}) when is_binary(ref), do: ref
  defp format_binding(_), do: "?"

  # ========== Private: Responses & Cases ==========

  attr :responses, :list, required: true
  attr :variables, :list, default: []
  attr :node_id, :any, required: true

  defp responses_list(assigns) do
    assigns = assign(assigns, :non_empty, Enum.reject(assigns.responses, &(&1["text"] == "")))

    ~H"""
    <div :if={@non_empty != []}>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-1">
        {gettext("Responses")}
      </dt>
      <div class="space-y-2">
        <div
          :for={{response, resp_idx} <- Enum.with_index(@non_empty)}
          class="text-xs text-base-content/80 bg-base-200/50 rounded px-2 py-1.5"
        >
          <div class="font-medium">{response["text"]}</div>
          <%!-- Response condition --%>
          <.response_condition_viewer
            :if={has_condition?(response)}
            condition={response["condition"]}
            variables={@variables}
            id={"resp-cond-#{@node_id}-#{resp_idx}"}
          />
          <%!-- Response instruction --%>
          <.response_instruction_viewer
            :if={has_instruction?(response)}
            assignments={response["instruction_assignments"] || []}
            variables={@variables}
            id={"resp-instr-#{@node_id}-#{resp_idx}"}
          />
        </div>
      </div>
    </div>
    """
  end

  attr :cases, :list, required: true

  defp cases_list(assigns) do
    ~H"""
    <div>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-1">
        {gettext("Cases")}
      </dt>
      <div class="space-y-1">
        <div
          :for={c <- @cases}
          class="text-xs text-base-content/80 bg-base-200/50 rounded px-2 py-1 font-mono"
        >
          {c["label"] || c["value"]}
        </div>
      </div>
    </div>
    """
  end

  # ========== Private: Condition/Instruction Viewers ==========

  attr :element, :map, required: true
  attr :variables, :list, default: []
  attr :id, :string, required: true

  defp node_condition_viewer(assigns) do
    ~H"""
    <div>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-1">
        {gettext("Condition")}
      </dt>
      <div class="mt-1">
        <.condition_builder
          id={@id}
          condition={@element.data["condition"]}
          variables={@variables}
          can_edit={false}
          switch_mode={@element.data["switch_mode"] || false}
        />
      </div>
    </div>
    """
  end

  attr :element, :map, required: true
  attr :variables, :list, default: []
  attr :id, :string, required: true

  defp node_instruction_viewer(assigns) do
    ~H"""
    <div>
      <dt class="text-[10px] font-medium text-base-content/50 uppercase tracking-wider mb-1">
        {gettext("Assignments")}
      </dt>
      <div class="mt-1">
        <.instruction_builder
          id={@id}
          assignments={@element.data["assignments"]}
          variables={@variables}
          can_edit={false}
        />
      </div>
    </div>
    """
  end

  attr :condition, :any, required: true
  attr :variables, :list, default: []
  attr :id, :string, required: true

  defp response_condition_viewer(assigns) do
    ~H"""
    <div class="mt-1.5 border-t border-base-content/10 pt-1.5">
      <div class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">
        {gettext("Condition")}
      </div>
      <.condition_builder
        id={@id}
        condition={@condition}
        variables={@variables}
        can_edit={false}
      />
    </div>
    """
  end

  attr :assignments, :list, required: true
  attr :variables, :list, default: []
  attr :id, :string, required: true

  defp response_instruction_viewer(assigns) do
    ~H"""
    <div class="mt-1.5 border-t border-base-content/10 pt-1.5">
      <div class="text-[10px] font-medium text-base-content/40 uppercase tracking-wider mb-1">
        {gettext("Instruction")}
      </div>
      <.instruction_builder
        id={@id}
        assignments={@assignments}
        variables={@variables}
        can_edit={false}
      />
    </div>
    """
  end

  defp has_condition?(response) do
    cond = response["condition"]
    cond && cond != "" && cond != %{}
  end

  defp has_instruction?(response) do
    assignments = response["instruction_assignments"]
    is_list(assignments) && assignments != []
  end

  # ========== Private: Variables ==========

  defp build_variables("flow", project_id) do
    Sheets.list_project_variables(project_id)
  end

  defp build_variables(_entity_type, _project_id), do: []

  # ========== Private: Flow Sheets Map ==========

  # Uses embedded sheet metadata from the snapshot when available (faithful to
  # the point-in-time state). Falls back to live DB lookup for old snapshots
  # created before referenced_sheets was persisted.
  defp build_sheets_map("flow", %{"referenced_sheets" => refs}, _project_id)
       when is_map(refs) and refs != %{} do
    Map.new(refs, fn {id, sheet} ->
      {to_string(id),
       %{
         id: sheet["id"],
         name: sheet["name"],
         color: sheet["color"],
         avatar_url: sheet["avatar_url"],
         banner_url: sheet["banner_url"],
         gallery_images: []
       }}
    end)
  end

  defp build_sheets_map("flow", snapshot, project_id) do
    sheet_ids =
      snapshot
      |> Map.get("nodes", [])
      |> Enum.flat_map(fn node ->
        data = node["data"] || %{}
        [data["speaker_sheet_id"], data["location_sheet_id"]]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if sheet_ids == [] do
      %{}
    else
      sheets = Sheets.list_sheets_by_ids(project_id, sheet_ids)

      Map.new(sheets, fn sheet ->
        {to_string(sheet.id),
         %{
           id: sheet.id,
           name: sheet.name,
           color: sheet.color,
           avatar_url: extract_asset_url(sheet.avatar_asset),
           banner_url: extract_asset_url(sheet.banner_asset),
           gallery_images: []
         }}
      end)
    end
  end

  defp build_sheets_map(_entity_type, _snapshot, _project_id), do: %{}

  defp extract_asset_url(%{url: url}) when is_binary(url), do: url
  defp extract_asset_url(_), do: nil

  # ========== Private: Sheet Helpers ==========

  # Extract sheet header fields from a snapshot for the full-layout rendering.
  # Returns a map to merge into socket assigns.
  defp sheet_header_from_snapshot("sheet", snapshot, project_id) do
    asset_metadata = snapshot["asset_metadata"] || %{}
    blob_hashes = snapshot["asset_blob_hashes"] || %{}

    %{
      sheet_name: snapshot["name"] || "",
      sheet_shortcut: snapshot["shortcut"],
      sheet_banner_url:
        resolve_snapshot_asset_url(
          snapshot["banner_asset_id"],
          asset_metadata,
          blob_hashes,
          project_id
        ),
      sheet_avatar:
        case resolve_snapshot_asset_url(
               snapshot["avatar_asset_id"],
               asset_metadata,
               blob_hashes,
               project_id
             ) do
          nil -> nil
          url -> %{url: url}
        end,
      sheet_color: snapshot["color"]
    }
  end

  defp sheet_header_from_snapshot(_entity_type, _snapshot, _project_id) do
    %{
      sheet_name: nil,
      sheet_shortcut: nil,
      sheet_banner_url: nil,
      sheet_avatar: nil,
      sheet_color: nil
    }
  end

  # Resolves an asset URL from the snapshot data.
  # Priority: 1) URL in metadata, 2) asset still in DB, 3) blob URL from hash
  defp resolve_snapshot_asset_url(nil, _metadata, _blob_hashes, _project_id), do: nil

  defp resolve_snapshot_asset_url(asset_id, metadata, blob_hashes, project_id) do
    id_str = to_string(asset_id)

    case Map.get(metadata, id_str) do
      %{"url" => url} when is_binary(url) ->
        url

      meta ->
        resolve_asset_fallback(asset_id, meta, id_str, blob_hashes, project_id)
    end
  end

  defp resolve_asset_fallback(asset_id, meta, id_str, blob_hashes, project_id) do
    case Assets.get_asset(project_id, asset_id) do
      %{url: url} when is_binary(url) ->
        url

      _ ->
        blob_hash = Map.get(blob_hashes, id_str)
        content_type = if is_map(meta), do: meta["content_type"]
        resolve_blob_url(blob_hash, content_type, project_id)
    end
  end

  defp resolve_blob_url(nil, _content_type, _project_id), do: nil
  defp resolve_blob_url(_hash, nil, _project_id), do: nil

  defp resolve_blob_url(blob_hash, content_type, project_id) do
    alias Storyarn.Assets.{BlobStore, Storage}
    ext = BlobStore.ext_from_content_type(content_type)
    key = BlobStore.blob_key(project_id, blob_hash, ext)
    Storage.get_url(key)
  end

  @default_sheet_color "#3b82f6"

  defp safe_color(nil), do: @default_sheet_color

  defp safe_color(color) when is_binary(color) do
    if Regex.match?(~r/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/, color),
      do: color,
      else: @default_sheet_color
  end

  defp safe_color(_), do: @default_sheet_color

  # ========== Private: Scene Layers ==========

  defp build_scene_layers("scene", viewer_data) do
    viewer_data.layers
  end

  defp build_scene_layers(_entity_type, _viewer_data), do: []

  defp parse_layer_id(id_str) when is_binary(id_str) do
    case Integer.parse(id_str) do
      {id, ""} -> id
      _ -> id_str
    end
  end

  defp parse_layer_id(id), do: id

  # ========== Private: Scene i18n ==========

  defp scene_i18n do
    %{
      edit_properties: dgettext("scenes", "Edit Properties"),
      connect_to: dgettext("scenes", "Connect To…"),
      edit_vertices: dgettext("scenes", "Edit Vertices"),
      duplicate: dgettext("scenes", "Duplicate"),
      bring_to_front: dgettext("scenes", "Bring to Front"),
      send_to_back: dgettext("scenes", "Send to Back"),
      lock: dgettext("scenes", "Lock"),
      unlock: dgettext("scenes", "Unlock"),
      delete: dgettext("scenes", "Delete"),
      add_pin: dgettext("scenes", "Add Pin Here"),
      add_annotation: dgettext("scenes", "Add Annotation Here"),
      create_child_scene: dgettext("scenes", "Create child scene"),
      name_zone_first: dgettext("scenes", "Name the zone first")
    }
  end
end
