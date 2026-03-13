defmodule Storyarn.Drafts.CloneEngine do
  @moduledoc """
  Deep clones entities for draft creation.

  Each clone function creates a copy of the root entity (with `draft_id` set)
  and all children with new IDs, remapping internal references.
  External references (speaker_sheet_id, referenced_flow_id, etc.) are preserved as-is.

  Note: `Repo.insert_all/3` with `returning: [:id]` relies on PostgreSQL's
  guarantee that `INSERT ... RETURNING` preserves input order. The returned IDs
  are zipped with the original list to build old→new ID maps.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.{Flow, FlowConnection, FlowNode}
  alias Storyarn.Repo
  alias Storyarn.Scenes.{Scene, SceneAnnotation, SceneConnection, SceneLayer, ScenePin, SceneZone}
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Clones the source entity and all its children, setting draft_id on the root.
  Returns `{:ok, cloned_entity}` or `{:error, reason}`.
  Must be called within a transaction.
  """
  def clone("sheet", project_id, source_id, draft_id) do
    clone_sheet(project_id, source_id, draft_id)
  end

  def clone("flow", project_id, source_id, draft_id) do
    clone_flow(project_id, source_id, draft_id)
  end

  def clone("scene", project_id, source_id, draft_id) do
    clone_scene(project_id, source_id, draft_id)
  end

  @doc """
  Returns the IDs of child entities that existed in the source at clone time.
  Used to track which entities the draft is "responsible for" during merge.
  """
  def get_baseline_entity_ids("sheet", project_id, source_id) do
    block_ids =
      from(b in Block,
        where: b.sheet_id == ^source_id and is_nil(b.deleted_at),
        select: b.id
      )
      |> Repo.all()

    # Also capture the sheet's project_id to verify it belongs to the project
    if Repo.exists?(
         from(s in Sheet,
           where: s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at)
         )
       ) do
      %{"block_ids" => block_ids}
    else
      %{}
    end
  end

  def get_baseline_entity_ids(_type, _project_id, _source_id), do: %{}

  @doc """
  Returns the name of the source entity, or nil if not found.
  """
  def get_source_name("sheet", project_id, source_id) do
    from(s in Sheet,
      where:
        s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at) and
          is_nil(s.draft_id),
      select: s.name
    )
    |> Repo.one()
  end

  def get_source_name("flow", project_id, source_id) do
    from(f in Flow,
      where:
        f.id == ^source_id and f.project_id == ^project_id and is_nil(f.deleted_at) and
          is_nil(f.draft_id),
      select: f.name
    )
    |> Repo.one()
  end

  def get_source_name("scene", project_id, source_id) do
    from(s in Scene,
      where:
        s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at) and
          is_nil(s.draft_id),
      select: s.name
    )
    |> Repo.one()
  end

  @doc """
  Gets the cloned entity for a draft.
  """
  def get_draft_entity("sheet", draft_id) do
    from(s in Sheet,
      where: s.draft_id == ^draft_id,
      preload: [:blocks, :avatar_asset, :banner_asset]
    )
    |> Repo.one()
  end

  def get_draft_entity("flow", draft_id) do
    active_nodes =
      from(n in FlowNode, where: is_nil(n.deleted_at), order_by: [asc: n.inserted_at])

    from(f in Flow,
      where: f.draft_id == ^draft_id,
      preload: [:connections, nodes: ^active_nodes]
    )
    |> Repo.one()
  end

  def get_draft_entity("scene", draft_id) do
    from(s in Scene,
      where: s.draft_id == ^draft_id,
      preload: [
        :layers,
        :zones,
        [pins: [:icon_asset, sheet: :avatar_asset]],
        :annotations,
        :background_asset,
        connections: [:from_pin, :to_pin]
      ]
    )
    |> Repo.one()
  end

  @doc """
  Deletes the cloned entity for a draft (hard delete).
  """
  def delete_draft_entity("sheet", draft_id) do
    from(s in Sheet, where: s.draft_id == ^draft_id) |> Repo.delete_all()
  end

  def delete_draft_entity("flow", draft_id) do
    from(f in Flow, where: f.draft_id == ^draft_id) |> Repo.delete_all()
  end

  def delete_draft_entity("scene", draft_id) do
    from(s in Scene, where: s.draft_id == ^draft_id) |> Repo.delete_all()
  end

  # ===========================================================================
  # Sheet Cloning
  # ===========================================================================

  defp clone_sheet(project_id, source_id, draft_id) do
    active_blocks = from(b in Block, where: is_nil(b.deleted_at), order_by: [asc: b.position])

    source =
      from(s in Sheet,
        where:
          s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at) and
            is_nil(s.draft_id),
        preload: [blocks: ^active_blocks]
      )
      |> Repo.one()

    with_source(source, Sheet, fn now ->
      new_id =
        insert_root(Sheet, %{
          project_id: project_id,
          draft_id: draft_id,
          name: source.name,
          shortcut: nil,
          description: source.description,
          color: source.color,
          position: 0,
          parent_id: nil,
          avatar_asset_id: source.avatar_asset_id,
          banner_asset_id: source.banner_asset_id,
          hidden_inherited_block_ids: source.hidden_inherited_block_ids,
          inserted_at: now,
          updated_at: now
        })

      clone_blocks(source.blocks, new_id, now)
      new_id
    end)
  end

  defp clone_blocks([], _sheet_id, _now), do: :ok

  defp clone_blocks(blocks, sheet_id, now) do
    # Preserve inherited_from_block_id as-is (cross-sheet references stay valid).
    # Intra-sheet references will be remapped below to point to the cloned blocks.
    block_entries =
      Enum.map(blocks, fn b ->
        %{
          sheet_id: sheet_id,
          type: b.type,
          position: b.position,
          config: b.config,
          value: b.value,
          is_constant: b.is_constant,
          variable_name: b.variable_name,
          scope: b.scope,
          inherited_from_block_id: b.inherited_from_block_id,
          detached: b.detached,
          required: b.required,
          deleted_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, inserted} = Repo.insert_all(Block, block_entries, returning: [:id])

    # Build old_id -> new_id map for intra-sheet inheritance remapping
    old_new_map =
      blocks
      |> Enum.zip(inserted)
      |> Map.new(fn {old, new} -> {old.id, new.id} end)

    # Remap intra-sheet inherited_from_block_id to point to cloned blocks.
    # Cross-sheet references (not in old_new_map) are left as-is.
    blocks
    |> Enum.zip(inserted)
    |> Enum.each(fn {old, new} ->
      remap_inheritance(old, new, old_new_map)
    end)

    # Clone table data for table blocks
    blocks
    |> Enum.zip(inserted)
    |> Enum.filter(fn {old, _new} -> old.type == "table" end)
    |> Enum.each(fn {old, new} -> clone_table_data(old.id, new.id, now) end)

    :ok
  end

  defp remap_inheritance(%{inherited_from_block_id: nil}, _new, _map), do: :ok

  defp remap_inheritance(old, new, old_new_map) do
    case Map.get(old_new_map, old.inherited_from_block_id) do
      nil ->
        :ok

      new_ref ->
        from(b in Block, where: b.id == ^new.id)
        |> Repo.update_all(set: [inherited_from_block_id: new_ref])
    end
  end

  defp clone_table_data(old_block_id, new_block_id, now) do
    columns = from(tc in TableColumn, where: tc.block_id == ^old_block_id) |> Repo.all()

    if columns != [] do
      entries =
        Enum.map(columns, fn col ->
          %{
            block_id: new_block_id,
            name: col.name,
            slug: col.slug,
            type: col.type,
            is_constant: col.is_constant,
            required: col.required,
            position: col.position,
            config: col.config,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableColumn, entries)
    end

    rows = from(tr in TableRow, where: tr.block_id == ^old_block_id) |> Repo.all()

    if rows != [] do
      entries =
        Enum.map(rows, fn row ->
          %{
            block_id: new_block_id,
            name: row.name,
            slug: row.slug,
            position: row.position,
            cells: row.cells,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(TableRow, entries)
    end
  end

  # ===========================================================================
  # Flow Cloning
  # ===========================================================================

  defp clone_flow(project_id, source_id, draft_id) do
    active_nodes = from(n in FlowNode, where: is_nil(n.deleted_at))

    source =
      from(f in Flow,
        where:
          f.id == ^source_id and f.project_id == ^project_id and is_nil(f.deleted_at) and
            is_nil(f.draft_id),
        preload: [:connections, nodes: ^active_nodes]
      )
      |> Repo.one()

    with_source(source, Flow, fn now ->
      new_id =
        insert_root(Flow, %{
          project_id: project_id,
          draft_id: draft_id,
          name: source.name,
          shortcut: nil,
          description: source.description,
          is_main: false,
          settings: source.settings,
          scene_id: source.scene_id,
          position: 0,
          parent_id: nil,
          inserted_at: now,
          updated_at: now
        })

      node_id_map = clone_nodes(source.nodes, new_id, now)
      clone_connections(source.connections, new_id, node_id_map, now)
      new_id
    end)
  end

  defp clone_nodes([], _flow_id, _now), do: %{}

  defp clone_nodes(nodes, flow_id, now) do
    entries =
      Enum.map(nodes, fn n ->
        %{
          flow_id: flow_id,
          type: n.type,
          position_x: n.position_x,
          position_y: n.position_y,
          data: n.data,
          word_count: n.word_count,
          source: n.source,
          deleted_at: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, inserted} = Repo.insert_all(FlowNode, entries, returning: [:id])

    # Build old_id -> new_id map
    nodes
    |> Enum.zip(inserted)
    |> Map.new(fn {old, new} -> {old.id, new.id} end)
  end

  defp clone_connections([], _flow_id, _node_id_map, _now), do: :ok

  defp clone_connections(connections, flow_id, node_id_map, now) do
    entries =
      connections
      |> Enum.map(fn c ->
        new_source = Map.get(node_id_map, c.source_node_id)
        new_target = Map.get(node_id_map, c.target_node_id)

        if new_source && new_target do
          %{
            flow_id: flow_id,
            source_node_id: new_source,
            target_node_id: new_target,
            source_pin: c.source_pin,
            target_pin: c.target_pin,
            label: c.label,
            inserted_at: now,
            updated_at: now
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    if entries != [] do
      Repo.insert_all(FlowConnection, entries)
    end

    :ok
  end

  # ===========================================================================
  # Scene Cloning
  # ===========================================================================

  defp clone_scene(project_id, source_id, draft_id) do
    source =
      from(s in Scene,
        where:
          s.id == ^source_id and s.project_id == ^project_id and is_nil(s.deleted_at) and
            is_nil(s.draft_id),
        preload: [:layers, :zones, :pins, :connections, :annotations]
      )
      |> Repo.one()

    with_source(source, Scene, fn now ->
      new_scene_id =
        insert_root(Scene, %{
          project_id: project_id,
          draft_id: draft_id,
          name: source.name,
          shortcut: nil,
          description: source.description,
          width: source.width,
          height: source.height,
          default_zoom: source.default_zoom,
          default_center_x: source.default_center_x,
          default_center_y: source.default_center_y,
          scale_unit: source.scale_unit,
          scale_value: source.scale_value,
          position: 0,
          parent_id: nil,
          background_asset_id: source.background_asset_id,
          inserted_at: now,
          updated_at: now
        })

      layer_id_map = clone_layers(source.layers, new_scene_id, now)
      pin_id_map = clone_pins(source.pins, new_scene_id, layer_id_map, now)
      clone_zones(source.zones, new_scene_id, layer_id_map, now)
      clone_annotations(source.annotations, new_scene_id, layer_id_map, now)
      clone_scene_connections(source.connections, new_scene_id, pin_id_map, now)
      new_scene_id
    end)
  end

  defp clone_layers([], _scene_id, _now), do: %{}

  defp clone_layers(layers, scene_id, now) do
    entries =
      Enum.map(layers, fn l ->
        %{
          scene_id: scene_id,
          name: l.name,
          is_default: l.is_default,
          position: l.position,
          visible: l.visible,
          fog_enabled: l.fog_enabled,
          fog_color: l.fog_color,
          fog_opacity: l.fog_opacity,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, inserted} = Repo.insert_all(SceneLayer, entries, returning: [:id])

    layers
    |> Enum.zip(inserted)
    |> Map.new(fn {old, new} -> {old.id, new.id} end)
  end

  defp clone_pins([], _scene_id, _layer_map, _now), do: %{}

  defp clone_pins(pins, scene_id, layer_id_map, now) do
    entries =
      Enum.map(pins, fn p ->
        %{
          scene_id: scene_id,
          layer_id: Map.get(layer_id_map, p.layer_id),
          position_x: p.position_x,
          position_y: p.position_y,
          pin_type: p.pin_type,
          icon: p.icon,
          color: p.color,
          opacity: p.opacity,
          label: p.label,
          target_type: p.target_type,
          target_id: p.target_id,
          tooltip: p.tooltip,
          size: p.size,
          position: p.position,
          locked: p.locked,
          action_type: p.action_type,
          action_data: p.action_data,
          condition: p.condition,
          condition_effect: p.condition_effect,
          sheet_id: p.sheet_id,
          icon_asset_id: p.icon_asset_id,
          inserted_at: now,
          updated_at: now
        }
      end)

    {_count, inserted} = Repo.insert_all(ScenePin, entries, returning: [:id])

    pins
    |> Enum.zip(inserted)
    |> Map.new(fn {old, new} -> {old.id, new.id} end)
  end

  defp clone_zones([], _scene_id, _layer_map, _now), do: :ok

  defp clone_zones(zones, scene_id, layer_id_map, now) do
    entries =
      Enum.map(zones, fn z ->
        %{
          scene_id: scene_id,
          layer_id: Map.get(layer_id_map, z.layer_id),
          name: z.name,
          vertices: z.vertices,
          fill_color: z.fill_color,
          border_color: z.border_color,
          border_width: z.border_width,
          border_style: z.border_style,
          opacity: z.opacity,
          target_type: z.target_type,
          target_id: z.target_id,
          tooltip: z.tooltip,
          position: z.position,
          locked: z.locked,
          action_type: z.action_type,
          action_data: z.action_data,
          condition: z.condition,
          condition_effect: z.condition_effect,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [], do: Repo.insert_all(SceneZone, entries)

    :ok
  end

  defp clone_annotations([], _scene_id, _layer_map, _now), do: :ok

  defp clone_annotations(annotations, scene_id, layer_id_map, now) do
    entries =
      Enum.map(annotations, fn a ->
        %{
          scene_id: scene_id,
          layer_id: Map.get(layer_id_map, a.layer_id),
          text: a.text,
          position_x: a.position_x,
          position_y: a.position_y,
          font_size: a.font_size,
          color: a.color,
          position: a.position,
          locked: a.locked,
          inserted_at: now,
          updated_at: now
        }
      end)

    if entries != [], do: Repo.insert_all(SceneAnnotation, entries)

    :ok
  end

  defp clone_scene_connections([], _scene_id, _pin_map, _now), do: :ok

  defp clone_scene_connections(connections, scene_id, pin_id_map, now) do
    entries =
      connections
      |> Enum.map(fn c ->
        new_from = Map.get(pin_id_map, c.from_pin_id)
        new_to = Map.get(pin_id_map, c.to_pin_id)

        if new_from && new_to do
          %{
            scene_id: scene_id,
            from_pin_id: new_from,
            to_pin_id: new_to,
            line_style: c.line_style,
            line_width: c.line_width,
            color: c.color,
            label: c.label,
            bidirectional: c.bidirectional,
            show_label: c.show_label,
            waypoints: c.waypoints,
            inserted_at: now,
            updated_at: now
          }
        end
      end)
      |> Enum.reject(&is_nil/1)

    if entries != [], do: Repo.insert_all(SceneConnection, entries)

    :ok
  end

  # ===========================================================================
  # Shared Helpers
  # ===========================================================================

  defp with_source(nil, _schema, _fun), do: {:error, :source_not_found}

  defp with_source(_source, schema, fun) do
    now = TimeHelpers.now()
    new_id = fun.(now)
    {:ok, Repo.get!(schema, new_id)}
  end

  defp insert_root(schema, attrs) do
    {1, [%{id: new_id}]} = Repo.insert_all(schema, [attrs], returning: [:id])
    new_id
  end
end
