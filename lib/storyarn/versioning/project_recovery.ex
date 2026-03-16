defmodule Storyarn.Versioning.ProjectRecovery do
  @moduledoc """
  Creates a new project from a project snapshot with full ID remapping.

  Unlike `ProjectSnapshotBuilder.restore_snapshot/3` which restores into an
  existing project by matching entity IDs, this module creates brand new entities
  from snapshot data and remaps all internal cross-references to point to the
  new autoincrement IDs.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization.{GlossaryEntry, LocalizedText, ProjectLanguage}
  alias Storyarn.Projects.{Project, ProjectMembership}
  alias Storyarn.Repo
  alias Storyarn.Scenes.{ScenePin, SceneZone}
  alias Storyarn.Shared.{NameNormalizer, TimeHelpers}
  alias Storyarn.Sheets.{Block, Sheet}
  alias Storyarn.Versioning.Builders.{FlowBuilder, SceneBuilder, SheetBuilder}

  @recovery_id_map_keys [:sheet, :block, :flow, :node, :scene, :pin, :zone]

  @doc """
  Recovers a project from snapshot data by creating a new project with all entities.

  Creates fresh entities with new IDs and remaps all internal cross-references.
  Runs in a single transaction with a 5-minute timeout.

  ## Options
  - `:name` - Override the recovered project name (default: "{original} (Recovered)")
  """
  @spec recover_project(integer(), map(), integer(), keyword()) ::
          {:ok, Project.t()} | {:error, term()}
  def recover_project(workspace_id, snapshot_data, user_id, opts \\ []) do
    name = Keyword.get(opts, :name, "Recovered Project")

    Repo.transaction(
      fn ->
        case do_recover(workspace_id, snapshot_data, user_id, name) do
          {:ok, project} -> project
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: :timer.minutes(5)
    )
  end

  defp do_recover(workspace_id, snapshot_data, user_id, name) do
    now = TimeHelpers.now()

    with {:ok, project} <- create_project(workspace_id, user_id, name),
         {:ok, _membership} <- create_owner_membership(project, user_id),
         {:ok, sheet_maps} <- recover_sheets(project.id, snapshot_data),
         {:ok, scene_maps} <- recover_scenes(project.id, snapshot_data, sheet_maps.sheet),
         {:ok, flow_maps} <- recover_flows(project.id, snapshot_data, scene_maps.scene) do
      id_maps = merge_recovery_id_maps([sheet_maps, scene_maps, flow_maps])

      remap_sheet_refs(id_maps, snapshot_data)
      remap_flow_refs(id_maps, snapshot_data)
      remap_scene_refs(id_maps, snapshot_data)

      restore_tree_hierarchy(snapshot_data, id_maps)
      recover_localization(project.id, snapshot_data, id_maps, now)

      {:ok, project}
    end
  end

  # ========== Project Creation ==========

  defp create_project(workspace_id, user_id, name) do
    slug = NameNormalizer.generate_unique_slug(Project, [workspace_id: workspace_id], name)

    %Project{owner_id: user_id}
    |> Project.create_changeset(%{
      name: name,
      slug: slug,
      workspace_id: workspace_id
    })
    |> Repo.insert()
  end

  defp create_owner_membership(project, user_id) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project.id, user_id: user_id, role: "owner"})
    |> Repo.insert()
  end

  # ========== Phase A: Materialize Entities ==========

  defp recover_sheets(project_id, snapshot_data) do
    materialize_entities(snapshot_data["sheets"] || [], :sheet, fn snapshot ->
      SheetBuilder.instantiate_snapshot(project_id, snapshot, preserve_external_refs: false)
    end)
  end

  defp recover_scenes(project_id, snapshot_data, sheet_id_map) do
    materialize_entities(snapshot_data["scenes"] || [], :scene, fn snapshot ->
      SceneBuilder.instantiate_snapshot(project_id, snapshot,
        external_id_maps: %{sheet: sheet_id_map}
      )
    end)
  end

  defp recover_flows(project_id, snapshot_data, scene_id_map) do
    materialize_entities(snapshot_data["flows"] || [], :flow, fn snapshot ->
      FlowBuilder.instantiate_snapshot(project_id, snapshot,
        external_id_maps: %{scene: scene_id_map}
      )
    end)
  end

  defp materialize_entities(entries, entity_type, instantiate_fun) do
    entries
    |> Enum.reduce_while({:ok, empty_recovery_id_maps()}, fn entry, {:ok, id_maps} ->
      case instantiate_fun.(entry["snapshot"]) do
        {:ok, _entity, materialized_maps} ->
          {:cont, {:ok, merge_recovery_id_maps([id_maps, materialized_maps])}}

        {:error, reason} ->
          {:halt, {:error, {:materialization_failed, entity_type, entry["id"], reason}}}
      end
    end)
  end

  defp empty_recovery_id_maps do
    Map.new(@recovery_id_map_keys, &{&1, %{}})
  end

  defp merge_recovery_id_maps(id_maps_list) do
    Enum.reduce(id_maps_list, empty_recovery_id_maps(), fn id_maps, acc ->
      Enum.reduce(@recovery_id_map_keys, acc, fn key, merged ->
        Map.update!(merged, key, &Map.merge(&1, Map.get(id_maps, key, %{})))
      end)
    end)
  end

  # ========== Phase B: Remap Cross-Entity References ==========

  defp remap_sheet_refs(id_maps, snapshot_data) do
    Enum.each(snapshot_data["sheets"] || [], fn entry ->
      new_sheet_id = remap_id(entry["id"], id_maps.sheet)
      snapshot = entry["snapshot"]

      if new_sheet_id do
        remap_hidden_inherited_block_ids(new_sheet_id, snapshot, id_maps.block)
        remap_block_inheritance(snapshot["blocks"] || [], id_maps.block)
      end
    end)
  end

  defp remap_hidden_inherited_block_ids(sheet_id, snapshot, block_id_map) do
    hidden_ids =
      (snapshot["hidden_inherited_block_ids"] || [])
      |> Enum.map(&Map.get(block_id_map, &1))
      |> Enum.reject(&is_nil/1)

    from(s in Sheet, where: s.id == ^sheet_id)
    |> Repo.update_all(set: [hidden_inherited_block_ids: hidden_ids])
  end

  defp remap_block_inheritance(blocks_data, block_id_map) do
    Enum.each(blocks_data, fn block_data ->
      new_block_id = remap_id(block_data["original_id"], block_id_map)

      if new_block_id do
        remapped_parent = remap_id(block_data["inherited_from_block_id"], block_id_map)

        from(b in Block, where: b.id == ^new_block_id)
        |> Repo.update_all(set: [inherited_from_block_id: remapped_parent])
      end
    end)
  end

  defp remap_flow_refs(id_maps, snapshot_data) do
    Enum.each(snapshot_data["flows"] || [], &remap_single_flow_snapshot(&1, id_maps))
  end

  defp remap_single_flow_snapshot(entry, id_maps) do
    case remap_id(entry["id"], id_maps.flow) do
      nil ->
        :ok

      new_flow_id ->
        remap_flow_scene_id(new_flow_id, entry["snapshot"]["scene_id"], id_maps.scene)
        Enum.each(entry["snapshot"]["nodes"] || [], &remap_node_snapshot(&1, id_maps))
    end
  end

  defp remap_node_snapshot(node_data, id_maps) do
    case remap_id(node_data["original_id"], id_maps.node) do
      nil ->
        :ok

      new_node_id ->
        remap_single_node_data(new_node_id, node_data["data"] || %{}, id_maps)
    end
  end

  defp remap_flow_scene_id(_new_flow_id, nil, _scene_map), do: :ok

  defp remap_flow_scene_id(new_flow_id, old_scene_id, scene_map) do
    case Map.get(scene_map, old_scene_id) do
      nil ->
        :ok

      new_id ->
        from(f in Storyarn.Flows.Flow, where: f.id == ^new_flow_id)
        |> Repo.update_all(set: [scene_id: new_id])
    end
  end

  defp remap_single_node_data(node_id, data, id_maps) do
    new_data =
      data
      |> maybe_put_remapped("speaker_sheet_id", id_maps.sheet)
      |> maybe_put_remapped("location_sheet_id", id_maps.sheet)
      |> maybe_put_remapped("referenced_flow_id", id_maps.flow)

    if new_data != data do
      from(n in FlowNode, where: n.id == ^node_id)
      |> Repo.update_all(set: [data: new_data])
    end
  end

  defp maybe_put_remapped(data, key, id_map) do
    case Map.fetch(data, key) do
      {:ok, value} -> Map.put(data, key, remap_id(value, id_map))
      :error -> data
    end
  end

  defp remap_scene_refs(id_maps, snapshot_data) do
    Enum.each(snapshot_data["scenes"] || [], fn entry ->
      snapshot = entry["snapshot"]

      remap_scene_pin_refs(snapshot["orphan_pins"] || [], id_maps)
      remap_scene_zone_refs(snapshot["orphan_zones"] || [], id_maps)

      Enum.each(snapshot["layers"] || [], fn layer_data ->
        remap_scene_pin_refs(layer_data["pins"] || [], id_maps)
        remap_scene_zone_refs(layer_data["zones"] || [], id_maps)
      end)
    end)
  end

  defp remap_scene_pin_refs(pin_snapshots, id_maps) do
    Enum.each(pin_snapshots, &remap_single_scene_pin_ref(&1, id_maps))
  end

  defp remap_scene_zone_refs(zone_snapshots, id_maps) do
    Enum.each(zone_snapshots, &remap_single_scene_zone_ref(&1, id_maps))
  end

  defp remap_single_scene_pin_ref(pin_data, id_maps) do
    case remap_id(pin_data["original_id"], id_maps.pin) do
      nil ->
        :ok

      new_pin_id ->
        pin_data
        |> build_scene_pin_updates(id_maps)
        |> maybe_update_scene_pin(new_pin_id)
    end
  end

  defp build_scene_pin_updates(pin_data, id_maps) do
    []
    |> maybe_put_db_update(:sheet_id, pin_data["sheet_id"], id_maps.sheet)
    |> maybe_put_target_update(pin_data["target_type"], pin_data["target_id"], id_maps)
  end

  defp maybe_update_scene_pin([], _new_pin_id), do: :ok

  defp maybe_update_scene_pin(updates, new_pin_id) do
    from(p in ScenePin, where: p.id == ^new_pin_id)
    |> Repo.update_all(set: updates)
  end

  defp remap_single_scene_zone_ref(zone_data, id_maps) do
    case remap_id(zone_data["original_id"], id_maps.zone) do
      nil ->
        :ok

      new_zone_id ->
        zone_data
        |> build_scene_zone_updates(id_maps)
        |> maybe_update_scene_zone(new_zone_id)
    end
  end

  defp build_scene_zone_updates(zone_data, id_maps) do
    maybe_put_target_update([], zone_data["target_type"], zone_data["target_id"], id_maps)
  end

  defp maybe_update_scene_zone([], _new_zone_id), do: :ok

  defp maybe_update_scene_zone(updates, new_zone_id) do
    from(z in SceneZone, where: z.id == ^new_zone_id)
    |> Repo.update_all(set: updates)
  end

  defp maybe_put_db_update(updates, _field, nil, _id_map), do: updates

  defp maybe_put_db_update(updates, field, old_id, id_map) do
    Keyword.put(updates, field, remap_id(old_id, id_map))
  end

  defp maybe_put_target_update(updates, _type, nil, _id_maps), do: updates
  defp maybe_put_target_update(updates, _type, "", _id_maps), do: updates

  defp maybe_put_target_update(updates, type, old_id, id_maps) do
    case remap_target_id(type, old_id, id_maps) do
      nil -> updates
      new_id -> Keyword.put(updates, :target_id, new_id)
    end
  end

  defp remap_id(nil, _map), do: nil
  defp remap_id(old_id, map), do: Map.get(map, old_id)

  defp remap_target_id("sheet", old_id, id_maps), do: Map.get(id_maps.sheet, old_id)
  defp remap_target_id("flow", old_id, id_maps), do: Map.get(id_maps.flow, old_id)
  defp remap_target_id("scene", old_id, id_maps), do: Map.get(id_maps.scene, old_id)
  defp remap_target_id(_type, _old_id, _id_maps), do: nil

  # ========== Phase C: Tree Hierarchy ==========

  defp restore_tree_hierarchy(snapshot_data, id_maps) do
    case snapshot_data["tree"] do
      nil ->
        :ok

      tree ->
        remap_tree(tree["sheets"] || [], id_maps.sheet, Storyarn.Sheets.Sheet)
        remap_tree(tree["flows"] || [], id_maps.flow, Storyarn.Flows.Flow)
        remap_tree(tree["scenes"] || [], id_maps.scene, Storyarn.Scenes.Scene)
    end
  end

  defp remap_tree(tree_entries, id_map, schema) do
    Enum.each(tree_entries, fn entry ->
      new_id = Map.get(id_map, entry["id"])
      if new_id, do: apply_tree_position(schema, new_id, entry, id_map)
    end)
  end

  defp apply_tree_position(schema, new_id, entry, id_map) do
    new_parent_id = if entry["parent_id"], do: Map.get(id_map, entry["parent_id"])

    updates =
      if new_parent_id,
        do: [position: entry["position"] || 0, parent_id: new_parent_id],
        else: [position: entry["position"] || 0]

    from(e in schema, where: e.id == ^new_id)
    |> Repo.update_all(set: updates)
  end

  # ========== Phase D: Localization ==========

  defp recover_localization(project_id, snapshot_data, id_maps, now) do
    case snapshot_data["localization"] do
      nil ->
        :ok

      localization ->
        restore_languages(project_id, Map.get(localization, "languages", []), now)
        restore_texts(project_id, Map.get(localization, "texts", []), id_maps, now)
        restore_glossary(project_id, Map.get(localization, "glossary", []), now)
    end
  end

  defp restore_languages(_project_id, [], _now), do: :ok

  defp restore_languages(project_id, languages, now) do
    entries =
      Enum.map(languages, fn lang ->
        %{
          project_id: project_id,
          locale_code: lang["locale_code"],
          name: lang["name"],
          is_source: lang["is_source"] || false,
          position: lang["position"] || 0,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ProjectLanguage, entries)
  end

  defp restore_texts(_project_id, [], _id_maps, _now), do: :ok

  defp restore_texts(project_id, texts, id_maps, now) do
    texts
    |> Enum.map(fn text ->
      source_id = remap_source_id(text["source_type"], text["source_id"], id_maps)

      speaker_id =
        if text["speaker_sheet_id"], do: Map.get(id_maps.sheet, text["speaker_sheet_id"])

      %{
        project_id: project_id,
        source_type: text["source_type"],
        source_id: source_id,
        source_field: text["source_field"],
        source_text: text["source_text"],
        source_text_hash: text["source_text_hash"],
        locale_code: text["locale_code"],
        translated_text: text["translated_text"],
        status: text["status"] || "pending",
        vo_status: text["vo_status"] || "none",
        vo_asset_id: text["vo_asset_id"],
        translator_notes: text["translator_notes"],
        reviewer_notes: text["reviewer_notes"],
        speaker_sheet_id: speaker_id,
        word_count: text["word_count"],
        machine_translated: text["machine_translated"] || false,
        last_translated_at: text["last_translated_at"],
        last_reviewed_at: text["last_reviewed_at"],
        translated_by_id: nil,
        reviewed_by_id: nil,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(LocalizedText, chunk) end)
  end

  defp remap_source_id("flow_node", old_id, id_maps), do: Map.get(id_maps.node, old_id, old_id)
  defp remap_source_id("sheet", old_id, id_maps), do: Map.get(id_maps.sheet, old_id, old_id)
  defp remap_source_id("flow", old_id, id_maps), do: Map.get(id_maps.flow, old_id, old_id)
  defp remap_source_id("scene", old_id, id_maps), do: Map.get(id_maps.scene, old_id, old_id)
  defp remap_source_id(_type, old_id, _id_maps), do: old_id

  defp restore_glossary(_project_id, [], _now), do: :ok

  defp restore_glossary(project_id, glossary, now) do
    glossary
    |> Enum.map(fn entry ->
      %{
        project_id: project_id,
        source_term: entry["source_term"],
        source_locale: entry["source_locale"],
        target_term: entry["target_term"],
        target_locale: entry["target_locale"],
        context: entry["context"],
        do_not_translate: entry["do_not_translate"] || false,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(GlossaryEntry, chunk) end)
  end
end
