defmodule Storyarn.Versioning.ReferencedTombstones do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @format_version 1
  @max_pg_bigint 9_223_372_036_854_775_807
  @entity_rank %{"sheet" => 0, "flow" => 1, "scene" => 2, "block" => 3, "flow_node" => 4}
  @entry_keys ~w(deleted_at entity_type id owner snapshot)

  @snapshot_fields %{
    "sheet" => ~w(name shortcut description color position hidden_inherited_block_ids)a,
    "flow" => ~w(name shortcut description position is_main settings)a,
    "scene" =>
      ~w(name shortcut description width height default_zoom default_center_x default_center_y position scale_unit scale_value fog_color fog_opacity exploration_display_mode)a,
    "block" =>
      ~w(type position config value is_constant variable_name scope detached required column_group_id column_index word_count)a,
    "flow_node" => ~w(type position_x position_y data word_count derivatives_fingerprint)a
  }

  @spec capture!(pos_integer()) :: map()
  def capture!(project_id) when is_integer(project_id) and project_id > 0 do
    if !Repo.in_transaction?() do
      raise ArgumentError, "referenced tombstone capture requires a database transaction"
    end

    direct_sheets = project_id |> sheet_targets() |> same_project_roots(project_id) |> deleted_only()
    direct_flows = project_id |> flow_targets() |> same_project_roots(project_id) |> deleted_only()
    direct_scenes = project_id |> scene_targets() |> same_project_roots(project_id) |> deleted_only()

    {blocks, block_owner_sheets} =
      project_id
      |> block_targets()
      |> same_project_children(project_id)
      |> deleted_children_and_owners()

    {flow_nodes, node_owner_flows} =
      project_id
      |> flow_node_targets()
      |> same_project_children(project_id)
      |> deleted_children_and_owners()

    entries =
      Enum.sort_by(
        Enum.map(dedupe(direct_sheets ++ block_owner_sheets), &entry("sheet", &1)) ++
          Enum.map(dedupe(direct_flows ++ node_owner_flows), &entry("flow", &1)) ++
          Enum.map(dedupe(direct_scenes), &entry("scene", &1)) ++
          Enum.map(dedupe(blocks), &entry("block", &1)) ++ Enum.map(dedupe(flow_nodes), &entry("flow_node", &1)),
        &sort_key/1
      )

    %{"format_version" => @format_version, "entries" => entries}
  end

  @spec validate(term(), non_neg_integer()) :: :ok | {:error, term()}
  def validate(project, max_logical_entries)

  def validate(
        %{"referenced_tombstones" => %{"format_version" => @format_version, "entries" => entries}} = project,
        max_logical_entries
      )
      when is_list(entries) and is_integer(max_logical_entries) and max_logical_entries >= 0 do
    with :ok <- exact_keys(project["referenced_tombstones"], ~w(entries format_version), :envelope),
         :ok <- validate_entries(entries),
         {:ok, inventory} <- active_inventory(project),
         :ok <- validate_catalog_limit(entries, max_logical_entries) do
      validate_owner_closure(entries, inventory)
    end
  end

  def validate(%{"referenced_tombstones" => %{"format_version" => version}}, _max) when version != @format_version,
    do: {:error, {:unsupported_referenced_tombstones_format, version}}

  def validate(%{"referenced_tombstones" => _invalid}, _max), do: {:error, :invalid_referenced_tombstones}

  def validate(project, _max) when is_map(project), do: :ok
  def validate(_project, _max), do: {:error, :invalid_project_object}

  @spec validate_complete(term(), non_neg_integer()) :: :ok | {:error, term()}
  def validate_complete(project, max_logical_entries) do
    with %{"referenced_tombstones" => %{"entries" => entries}} <- project,
         :ok <- validate(project, max_logical_entries),
         {:ok, inventory} <- active_inventory(project) do
      validate_minimal_catalog(entries, project, inventory)
    else
      %{"referenced_tombstones" => _invalid} -> {:error, :invalid_referenced_tombstones}
      %{} -> {:error, :missing_referenced_tombstones}
      {:error, _reason} = error -> error
      _invalid -> {:error, :invalid_project_object}
    end
  end

  defp entry(entity_type, entity) do
    %{
      "entity_type" => entity_type,
      "id" => entity.id,
      "deleted_at" => DateTime.to_iso8601(entity.deleted_at),
      "owner" => owner(entity_type, entity),
      "snapshot" => snapshot(entity_type, entity)
    }
  end

  defp owner(entity_type, _entity) when entity_type in ~w(sheet flow scene), do: %{"entity_type" => "project"}

  defp owner("block", block), do: %{"entity_type" => "sheet", "id" => block.sheet_id}
  defp owner("flow_node", node), do: %{"entity_type" => "flow", "id" => node.flow_id}

  defp snapshot(entity_type, entity) do
    Map.new(@snapshot_fields[entity_type], fn field ->
      {Atom.to_string(field), Map.fetch!(entity, field)}
    end)
  end

  defp sheet_targets(project_id) do
    Repo.all(
      from(pin in ScenePin,
        join: scene in Scene,
        on: scene.id == pin.scene_id,
        join: target in Sheet,
        on: target.id == pin.sheet_id,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        select: target
      )
    ) ++
      Repo.all(
        from(text in LocalizedText,
          join: target in Sheet,
          on: target.id == text.speaker_sheet_id,
          where: text.project_id == ^project_id and is_nil(text.archived_at),
          select: target
        )
      )
  end

  defp flow_targets(project_id) do
    Repo.all(
      from(pin in ScenePin,
        join: scene in Scene,
        on: scene.id == pin.scene_id,
        join: target in Flow,
        on: target.id == pin.flow_id,
        where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
        select: target
      )
    ) ++
      Repo.all(
        from(ambient in SceneAmbientFlow,
          join: scene in Scene,
          on: scene.id == ambient.scene_id,
          join: target in Flow,
          on: target.id == ambient.flow_id,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          select: target
        )
      )
  end

  defp scene_targets(project_id) do
    Repo.all(
      from(flow in Flow,
        join: target in Scene,
        on: target.id == flow.scene_id,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        select: target
      )
    ) ++
      Repo.all(
        from(scene in Scene,
          join: target in Scene,
          on: target.id == scene.parent_id,
          where: scene.project_id == ^project_id and is_nil(scene.deleted_at),
          select: target
        )
      )
  end

  defp block_targets(project_id) do
    Repo.all(
      from(block in Block,
        join: source_sheet in Sheet,
        on: source_sheet.id == block.sheet_id,
        join: target in Block,
        on: target.id == block.inherited_from_block_id,
        join: owner in Sheet,
        on: owner.id == target.sheet_id,
        where:
          source_sheet.project_id == ^project_id and is_nil(source_sheet.deleted_at) and
            is_nil(block.deleted_at),
        select: {target, owner}
      )
    )
  end

  defp flow_node_targets(project_id) do
    endpoint_targets(project_id, :source_node_id) ++ endpoint_targets(project_id, :target_node_id)
  end

  defp endpoint_targets(project_id, endpoint) do
    Repo.all(
      from(connection in FlowConnection,
        join: source_flow in Flow,
        on: source_flow.id == connection.flow_id,
        join: target in FlowNode,
        on: target.id == field(connection, ^endpoint),
        join: owner in Flow,
        on: owner.id == target.flow_id,
        where: source_flow.project_id == ^project_id and is_nil(source_flow.deleted_at),
        select: {target, owner}
      )
    )
  end

  defp same_project_roots(entities, project_id), do: Enum.filter(entities, &(&1.project_id == project_id))

  defp same_project_children(pairs, project_id),
    do: Enum.filter(pairs, fn {_child, owner} -> owner.project_id == project_id end)

  defp deleted_children_and_owners(pairs) do
    pairs
    |> Enum.filter(fn {child, _owner} -> not is_nil(child.deleted_at) end)
    |> Enum.unzip()
    |> then(fn {children, owners} -> {children, Enum.filter(owners, &(not is_nil(&1.deleted_at)))} end)
  end

  defp deleted_only(entities), do: Enum.filter(entities, &(not is_nil(&1.deleted_at)))
  defp dedupe(entities), do: entities |> Map.new(&{&1.id, &1}) |> Map.values()
  defp sort_key(%{"entity_type" => type, "id" => id}), do: {@entity_rank[type], id}

  defp validate_entries(entries) do
    with :ok <- reduce_ok(entries, &validate_entry/1),
         true <- entries == Enum.sort_by(entries, &sort_key/1),
         true <- Enum.uniq_by(entries, &{&1["entity_type"], &1["id"]}) == entries do
      :ok
    else
      false -> {:error, :noncanonical_referenced_tombstones}
      {:error, _reason} = error -> error
    end
  end

  defp validate_entry(
         %{"entity_type" => entity_type, "id" => id, "deleted_at" => deleted_at, "owner" => owner, "snapshot" => snapshot} =
           entry
       ) do
    with true <- Map.has_key?(@entity_rank, entity_type),
         :ok <- exact_keys(entry, @entry_keys, :entry),
         true <- valid_id?(id),
         true <- valid_deleted_at?(deleted_at),
         :ok <- validate_owner(entity_type, owner),
         :ok <- validate_snapshot(entity_type, snapshot) do
      :ok
    else
      false -> {:error, :invalid_referenced_tombstone_entry}
      {:error, _reason} = error -> error
    end
  end

  defp validate_entry(_entry), do: {:error, :invalid_referenced_tombstone_entry}

  defp validate_owner(entity_type, %{"entity_type" => "project"} = owner) when entity_type in ~w(sheet flow scene),
    do: exact_keys(owner, ~w(entity_type), :owner)

  defp validate_owner("block", %{"entity_type" => "sheet", "id" => id} = owner), do: validate_child_owner(owner, id)

  defp validate_owner("flow_node", %{"entity_type" => "flow", "id" => id} = owner), do: validate_child_owner(owner, id)

  defp validate_owner(_entity_type, _owner), do: {:error, :invalid_referenced_tombstone_owner}

  defp validate_child_owner(owner, id) do
    with :ok <- exact_keys(owner, ~w(entity_type id), :owner),
         true <- valid_id?(id) do
      :ok
    else
      false -> {:error, :invalid_referenced_tombstone_owner}
      {:error, _reason} = error -> error
    end
  end

  defp validate_snapshot(entity_type, snapshot) when is_map(snapshot) do
    keys = Enum.map(@snapshot_fields[entity_type], &Atom.to_string/1)

    with :ok <- exact_keys(snapshot, keys, :snapshot),
         true <- valid_snapshot_types?(entity_type, snapshot) do
      :ok
    else
      false -> {:error, {:invalid_referenced_tombstone_snapshot, entity_type}}
      {:error, _reason} = error -> error
    end
  end

  defp validate_snapshot(entity_type, _snapshot), do: {:error, {:invalid_referenced_tombstone_snapshot, entity_type}}

  defp valid_snapshot_types?("sheet", row) do
    required_string?(row["name"]) and optional_string?(row["shortcut"]) and
      optional_string?(row["description"]) and optional_string?(row["color"]) and
      optional_integer?(row["position"]) and optional_integer_list?(row["hidden_inherited_block_ids"])
  end

  defp valid_snapshot_types?("flow", row) do
    required_string?(row["name"]) and optional_string?(row["shortcut"]) and
      optional_string?(row["description"]) and optional_integer?(row["position"]) and
      is_boolean(row["is_main"]) and optional_map?(row["settings"])
  end

  defp valid_snapshot_types?("scene", row) do
    Enum.all?([
      required_string?(row["name"]),
      optional_string?(row["shortcut"]),
      optional_string?(row["description"]),
      optional_integer?(row["width"]),
      optional_integer?(row["height"]),
      optional_number?(row["default_zoom"]),
      optional_number?(row["default_center_x"]),
      optional_number?(row["default_center_y"]),
      optional_integer?(row["position"]),
      optional_string?(row["scale_unit"]),
      optional_number?(row["scale_value"]),
      optional_string?(row["fog_color"]),
      optional_number?(row["fog_opacity"]),
      required_string?(row["exploration_display_mode"])
    ])
  end

  defp valid_snapshot_types?("block", row) do
    Enum.all?([
      required_string?(row["type"]),
      optional_integer?(row["position"]),
      optional_map?(row["config"]),
      optional_map?(row["value"]),
      is_boolean(row["is_constant"]),
      optional_string?(row["variable_name"]),
      optional_string?(row["scope"]),
      optional_boolean?(row["detached"]),
      optional_boolean?(row["required"]),
      optional_string?(row["column_group_id"]),
      optional_integer?(row["column_index"]),
      is_integer(row["word_count"])
    ])
  end

  defp valid_snapshot_types?("flow_node", row) do
    required_string?(row["type"]) and number?(row["position_x"]) and number?(row["position_y"]) and
      optional_map?(row["data"]) and is_integer(row["word_count"]) and
      optional_string?(row["derivatives_fingerprint"])
  end

  defp active_inventory(project) do
    with {:ok, sheets, blocks} <- root_and_children(project["sheets"], "blocks"),
         {:ok, flows, flow_nodes} <- root_and_children(project["flows"], "nodes"),
         {:ok, scenes} <- root_ids(project["scenes"]) do
      {:ok,
       %{
         "sheet" => sheets,
         "flow" => flows,
         "scene" => scenes,
         "block" => blocks,
         "flow_node" => flow_nodes
       }}
    end
  end

  defp root_and_children(nil, _child_key), do: {:ok, MapSet.new(), MapSet.new()}

  defp root_and_children(entries, child_key) when is_list(entries) do
    with {:ok, roots} <- root_ids(entries),
         {:ok, children} <- collect_child_ids(entries, child_key) do
      {:ok, roots, children}
    end
  end

  defp root_and_children(_entries, _child_key), do: {:error, :invalid_referenced_tombstone_inventory}

  defp root_ids(nil), do: {:ok, MapSet.new()}

  defp root_ids(entries) when is_list(entries) do
    ids = Enum.map(entries, & &1["id"])
    if Enum.all?(ids, &valid_id?/1), do: {:ok, MapSet.new(ids)}, else: {:error, :invalid_referenced_tombstone_inventory}
  rescue
    _error -> {:error, :invalid_referenced_tombstone_inventory}
  end

  defp root_ids(_entries), do: {:error, :invalid_referenced_tombstone_inventory}

  defp collect_child_ids(entries, child_key) do
    ids =
      Enum.flat_map(entries, fn
        %{"snapshot" => snapshot} when is_map(snapshot) ->
          snapshot |> Map.get(child_key, []) |> Enum.map(& &1["original_id"])

        _entry ->
          []
      end)

    if Enum.all?(ids, &valid_id?/1), do: {:ok, MapSet.new(ids)}, else: {:error, :invalid_referenced_tombstone_inventory}
  rescue
    _error -> {:error, :invalid_referenced_tombstone_inventory}
  end

  defp validate_catalog_limit(entries, max) do
    if length(entries) <= max,
      do: :ok,
      else: {:error, {:collection_limit_exceeded, :referenced_tombstones, max}}
  end

  defp validate_owner_closure(entries, inventory) do
    catalog = MapSet.new(entries, &{&1["entity_type"], &1["id"]})

    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      owner_closure_result(entry["owner"], catalog, inventory)
    end)
  end

  defp owner_closure_result(%{"entity_type" => "project"}, _catalog, _inventory), do: {:cont, :ok}

  defp owner_closure_result(%{"entity_type" => owner_type, "id" => owner_id}, catalog, inventory) do
    if MapSet.member?(inventory[owner_type], owner_id) or MapSet.member?(catalog, {owner_type, owner_id}),
      do: {:cont, :ok},
      else: {:halt, {:error, {:missing_referenced_tombstone_owner, owner_type, owner_id}}}
  end

  defp validate_minimal_catalog(entries, project, inventory) do
    with {:ok, direct} <- direct_missing_references(project, inventory) do
      catalog = MapSet.new(entries, &{&1["entity_type"], &1["id"]})

      ownership =
        Enum.reduce(entries, MapSet.new(), &put_required_owner(&1["owner"], &2, inventory))

      expected = MapSet.union(direct, ownership)

      if catalog == expected,
        do: :ok,
        else: {:error, {:referenced_tombstone_catalog_mismatch, sorted_refs(expected), sorted_refs(catalog)}}
    end
  end

  defp put_required_owner(%{"entity_type" => owner_type, "id" => owner_id}, required, inventory) do
    if MapSet.member?(inventory[owner_type], owner_id),
      do: required,
      else: MapSet.put(required, {owner_type, owner_id})
  end

  defp put_required_owner(_project, required, _inventory), do: required

  defp direct_missing_references(project, inventory) do
    refs =
      flow_references(project["flows"]) ++
        sheet_references(project["sheets"]) ++
        scene_references(project["scenes"], project["tree"]) ++
        localization_references(project["localization"])

    if Enum.all?(refs, fn {type, id} -> Map.has_key?(@entity_rank, type) and valid_id?(id) end) do
      {:ok,
       Enum.reduce(refs, MapSet.new(), fn {type, id}, missing ->
         if MapSet.member?(inventory[type], id), do: missing, else: MapSet.put(missing, {type, id})
       end)}
    else
      {:error, :invalid_referenced_tombstone_reference}
    end
  rescue
    _error -> {:error, :invalid_referenced_tombstone_reference}
  end

  defp flow_references(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"snapshot" => snapshot} when is_map(snapshot) ->
        optional_ref("scene", snapshot["scene_id"]) ++
          Enum.flat_map(Map.get(snapshot, "connections", []), fn connection ->
            optional_ref("flow_node", connection["source_node_id"]) ++
              optional_ref("flow_node", connection["target_node_id"])
          end)

      _entry ->
        []
    end)
  end

  defp flow_references(_entries), do: []

  defp sheet_references(entries) when is_list(entries) do
    Enum.flat_map(entries, fn
      %{"snapshot" => snapshot} when is_map(snapshot) ->
        Enum.flat_map(Map.get(snapshot, "blocks", []), fn block ->
          optional_ref("block", block["inherited_from_block_id"])
        end)

      _entry ->
        []
    end)
  end

  defp sheet_references(_entries), do: []

  defp scene_references(entries, tree) when is_list(entries) do
    tree_refs =
      case tree do
        %{"scenes" => rows} when is_list(rows) -> Enum.flat_map(rows, &optional_ref("scene", &1["parent_id"]))
        _other -> []
      end

    entry_refs =
      Enum.flat_map(entries, fn
        %{"snapshot" => snapshot} when is_map(snapshot) ->
          pins =
            Map.get(snapshot, "orphan_pins", []) ++
              Enum.flat_map(Map.get(snapshot, "layers", []), &Map.get(&1, "pins", []))

          Enum.flat_map(pins, fn pin ->
            optional_ref("sheet", pin["sheet_id"]) ++ optional_ref("flow", pin["flow_id"])
          end) ++
            Enum.flat_map(Map.get(snapshot, "ambient_flows", []), &optional_ref("flow", &1["flow_id"]))

        _entry ->
          []
      end)

    tree_refs ++ entry_refs
  end

  defp scene_references(_entries, _tree), do: []

  defp localization_references(%{"texts" => texts}) when is_list(texts) do
    texts
    |> Enum.filter(&is_nil(&1["archived_at"]))
    |> Enum.flat_map(&optional_ref("sheet", &1["speaker_sheet_id"]))
  end

  defp localization_references(_localization), do: []

  defp optional_ref(_type, nil), do: []
  defp optional_ref(type, id), do: [{type, id}]

  defp sorted_refs(refs), do: Enum.sort_by(refs, fn {type, id} -> {@entity_rank[type], id} end)

  defp exact_keys(map, keys, label) when is_map(map) do
    if Enum.sort(Map.keys(map)) == Enum.sort(keys),
      do: :ok,
      else: {:error, {:invalid_referenced_tombstone_keys, label}}
  end

  defp exact_keys(_map, _keys, label), do: {:error, {:invalid_referenced_tombstone_keys, label}}

  defp reduce_ok(values, fun) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case fun.(value) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp valid_id?(id), do: is_integer(id) and id > 0 and id <= @max_pg_bigint

  defp optional_integer_list?(nil), do: true
  defp optional_integer_list?(ids) when is_list(ids), do: Enum.all?(ids, &is_integer/1)
  defp optional_integer_list?(_ids), do: false

  defp valid_deleted_at?(value) when is_binary(value) do
    String.ends_with?(value, "Z") and match?({:ok, _datetime, 0}, DateTime.from_iso8601(value))
  end

  defp valid_deleted_at?(_value), do: false
  defp required_string?(value), do: is_binary(value) and String.valid?(value)
  defp optional_string?(nil), do: true
  defp optional_string?(value), do: is_binary(value) and String.valid?(value)
  defp optional_map?(nil), do: true
  defp optional_map?(value), do: is_map(value)
  defp optional_boolean?(nil), do: true
  defp optional_boolean?(value), do: is_boolean(value)
  defp optional_integer?(nil), do: true
  defp optional_integer?(value), do: is_integer(value)
  defp number?(value), do: is_number(value)
  defp optional_number?(nil), do: true
  defp optional_number?(value), do: number?(value)
end
