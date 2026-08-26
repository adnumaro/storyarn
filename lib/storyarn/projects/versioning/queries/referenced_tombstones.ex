defmodule Storyarn.Projects.Versioning.ReferencedTombstones do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.LocalizedTextRecord, as: LocalizedText
  alias Storyarn.Projects.Persistence.SceneAmbientFlowRecord, as: SceneAmbientFlow
  alias Storyarn.Projects.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Versioning.ReferencedTombstoneValidator
  alias Storyarn.Repo

  @format_version 1
  @entity_rank %{"sheet" => 0, "flow" => 1, "scene" => 2, "block" => 3, "flow_node" => 4}

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
  defdelegate validate(project, max_logical_entries), to: ReferencedTombstoneValidator

  @spec validate_complete(term(), non_neg_integer()) :: :ok | {:error, term()}
  defdelegate validate_complete(project, max_logical_entries), to: ReferencedTombstoneValidator

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
end
