defmodule Storyarn.Versioning.ProjectRecovery do
  @moduledoc """
  Creates a new project from a project snapshot with full ID remapping.

  Unlike `ProjectSnapshotBuilder.restore_snapshot/3` which restores into an
  existing project by matching entity IDs, this module creates brand new entities
  from snapshot data and remaps all internal cross-references to point to the
  new autoincrement IDs.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.Repo
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder

  @recovery_id_map_keys [:sheet, :block, :flow, :node, :scene, :pin, :zone]

  @doc """
  Recovers a project from snapshot data by creating a new project with all entities.

  Creates fresh entities with new IDs and remaps all internal cross-references.
  Runs in a single transaction with a 5-minute timeout.

  ## Options
  - `:name` - Override the recovered project name (default: "{original} (Recovered)")
  - `:template_clone` - Copy snapshot assets into the new project instead of
    reusing source project asset IDs.
  """
  @spec recover_project(integer(), map(), integer(), keyword()) ::
          {:ok, Project.t()} | {:error, term()}
  def recover_project(workspace_id, snapshot_data, user_id, opts \\ []) do
    name = Keyword.get(opts, :name, "Recovered Project")

    Repo.transaction(
      fn ->
        case do_recover(workspace_id, snapshot_data, user_id, name, opts) do
          {:ok, project} -> project
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: to_timeout(minute: 5)
    )
  end

  defp do_recover(workspace_id, snapshot_data, user_id, name, opts) do
    now = TimeHelpers.now()

    with {:ok, project} <- create_project(workspace_id, user_id, name, snapshot_data),
         {:ok, _membership} <- create_owner_membership(project, user_id),
         {:ok, sheet_maps} <- recover_sheets(project.id, snapshot_data, user_id, opts),
         {:ok, scene_maps} <- recover_scenes(project.id, snapshot_data, sheet_maps.sheet, user_id, opts),
         {:ok, flow_maps} <- recover_flows(project.id, snapshot_data, scene_maps.scene, user_id, opts) do
      id_maps = merge_recovery_id_maps([sheet_maps, scene_maps, flow_maps])

      remap_sheet_refs(id_maps, snapshot_data)
      remap_flow_refs(id_maps, snapshot_data)
      remap_scene_refs(id_maps, snapshot_data)

      restore_tree_hierarchy(snapshot_data, id_maps)
      recover_localization(project.id, snapshot_data, id_maps, user_id, opts, now)

      {:ok, project}
    end
  end

  # ========== Project Creation ==========

  defp create_project(workspace_id, user_id, name, snapshot_data) do
    slug = NameNormalizer.generate_unique_slug(Project, [workspace_id: workspace_id], name)

    %Project{owner_id: user_id}
    |> Project.create_changeset(recovered_project_attrs(workspace_id, name, slug, snapshot_data))
    |> Repo.insert()
  end

  defp recovered_project_attrs(workspace_id, name, slug, snapshot_data) do
    snapshot_project = snapshot_data["project"] || %{}
    project_type = snapshot_project["project_type"] || "game"

    %{
      name: name,
      slug: slug,
      workspace_id: workspace_id,
      project_type: project_type,
      project_subtype: recovered_project_subtype(project_type, snapshot_project),
      project_type_other: recovered_project_type_other(project_type, snapshot_project)
    }
  end

  defp recovered_project_subtype("game", snapshot_project), do: snapshot_project["project_subtype"] || "rpg"
  defp recovered_project_subtype("film", snapshot_project), do: snapshot_project["project_subtype"] || "feature_film"
  defp recovered_project_subtype("novel", snapshot_project), do: snapshot_project["project_subtype"] || "fantasy"
  defp recovered_project_subtype(_project_type, snapshot_project), do: snapshot_project["project_subtype"]

  defp recovered_project_type_other("other", snapshot_project) do
    snapshot_project["project_type_other"] || "Recovered project"
  end

  defp recovered_project_type_other(_project_type, snapshot_project), do: snapshot_project["project_type_other"]

  defp create_owner_membership(project, user_id) do
    %ProjectMembership{}
    |> ProjectMembership.changeset(%{project_id: project.id, user_id: user_id, role: "owner"})
    |> Repo.insert()
  end

  # ========== Phase A: Materialize Entities ==========

  defp recover_sheets(project_id, snapshot_data, user_id, opts) do
    builder_opts = materialization_opts(user_id, opts, preserve_external_refs: false)

    materialize_entities(snapshot_data["sheets"] || [], :sheet, fn snapshot ->
      SheetBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp recover_scenes(project_id, snapshot_data, sheet_id_map, user_id, opts) do
    builder_opts =
      materialization_opts(user_id, opts, external_id_maps: %{sheet: sheet_id_map})

    materialize_entities(snapshot_data["scenes"] || [], :scene, fn snapshot ->
      SceneBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp recover_flows(project_id, snapshot_data, scene_id_map, user_id, opts) do
    builder_opts =
      materialization_opts(user_id, opts, external_id_maps: %{scene: scene_id_map})

    materialize_entities(snapshot_data["flows"] || [], :flow, fn snapshot ->
      FlowBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp materialization_opts(user_id, recovery_opts, builder_opts) do
    builder_opts = Keyword.put(builder_opts, :user_id, user_id)

    if Keyword.get(recovery_opts, :template_clone, false) do
      Keyword.put(builder_opts, :asset_mode, :copy)
    else
      builder_opts
    end
  end

  defp materialize_entities(entries, entity_type, instantiate_fun) do
    Enum.reduce_while(entries, {:ok, empty_recovery_id_maps()}, fn entry, {:ok, id_maps} ->
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

    Repo.update_all(from(s in Sheet, where: s.id == ^sheet_id), set: [hidden_inherited_block_ids: hidden_ids])
  end

  defp remap_block_inheritance(blocks_data, block_id_map) do
    Enum.each(blocks_data, fn block_data ->
      new_block_id = remap_id(block_data["original_id"], block_id_map)

      if new_block_id do
        remapped_parent = remap_id(block_data["inherited_from_block_id"], block_id_map)

        Repo.update_all(from(b in Block, where: b.id == ^new_block_id), set: [inherited_from_block_id: remapped_parent])
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
        Repo.update_all(from(f in Flow, where: f.id == ^new_flow_id), set: [scene_id: new_id])
    end
  end

  defp remap_single_node_data(node_id, data, id_maps) do
    new_data =
      data
      |> maybe_put_remapped("speaker_sheet_id", id_maps.sheet)
      |> maybe_put_remapped("location_sheet_id", id_maps.sheet)
      |> maybe_put_remapped("referenced_flow_id", id_maps.flow)

    if new_data != data do
      Repo.update_all(from(n in FlowNode, where: n.id == ^node_id), set: [data: new_data])
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
    |> maybe_put_db_update(:flow_id, pin_data["flow_id"], id_maps.flow)
  end

  defp maybe_update_scene_pin([], _new_pin_id), do: :ok

  defp maybe_update_scene_pin(updates, new_pin_id) do
    Repo.update_all(from(p in ScenePin, where: p.id == ^new_pin_id), set: updates)
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
    Repo.update_all(from(z in SceneZone, where: z.id == ^new_zone_id), set: updates)
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
        remap_tree(tree["sheets"] || [], id_maps.sheet, Sheet)
        remap_tree(tree["flows"] || [], id_maps.flow, Flow)
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

    Repo.update_all(from(e in schema, where: e.id == ^new_id), set: updates)
  end

  # ========== Phase D: Localization ==========

  defp recover_localization(project_id, snapshot_data, id_maps, user_id, opts, now) do
    case snapshot_data["localization"] do
      nil ->
        :ok

      localization ->
        restore_languages(project_id, Map.get(localization, "languages", []), now)
        restore_texts(project_id, Map.get(localization, "texts", []), id_maps, snapshot_data, user_id, opts, now)
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
          archived_at: parse_datetime(lang["archived_at"]),
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ProjectLanguage, entries)
  end

  defp restore_texts(_project_id, [], _id_maps, _snapshot_data, _user_id, _opts, _now), do: :ok

  defp restore_texts(project_id, texts, id_maps, snapshot_data, user_id, opts, now) do
    context = %{project_id: project_id, snapshot_data: snapshot_data, user_id: user_id, opts: opts, now: now}

    texts
    |> Enum.flat_map(&recovered_text_attrs(&1, id_maps, context))
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk -> Repo.insert_all(LocalizedText, chunk) end)
  end

  defp recovered_text_attrs(text, id_maps, context) do
    metadata = SourceContract.field_metadata(text["source_type"], text["source_field"])
    source_id = remap_source_id(text["source_type"], text["source_id"], id_maps)

    if is_nil(metadata) or is_nil(source_id) do
      []
    else
      [recovered_text_map(text, metadata, source_id, id_maps, context)]
    end
  end

  defp recovered_text_map(text, metadata, source_id, id_maps, context) do
    translated_source_hash = translated_source_hash(text)
    vo_asset_id = recovered_vo_asset_id(text, metadata, context)

    %{
      project_id: context.project_id,
      source_type: text["source_type"],
      source_id: source_id,
      source_field: text["source_field"],
      source_text: text["source_text"],
      source_text_hash: text["source_text_hash"],
      translated_source_hash: translated_source_hash,
      locale_code: text["locale_code"],
      translated_text: text["translated_text"],
      status: recovered_status(text, translated_source_hash),
      vo_status: recovered_vo_status(text, metadata, vo_asset_id),
      vo_asset_id: vo_asset_id,
      translator_notes: text["translator_notes"],
      reviewer_notes: text["reviewer_notes"],
      speaker_sheet_id: recovered_speaker_id(text, metadata, id_maps),
      word_count: text["word_count"],
      content_role: metadata.content_role,
      vo_eligible: metadata.vo_eligible,
      machine_translated: text["machine_translated"] || false,
      last_translated_at: parse_datetime(text["last_translated_at"]),
      last_reviewed_at: parse_datetime(text["last_reviewed_at"]),
      translated_by_id: nil,
      reviewed_by_id: nil,
      archived_at: parse_datetime(text["archived_at"]),
      archive_reason: recovered_archive_reason(text["archive_reason"]),
      inserted_at: context.now,
      updated_at: context.now
    }
  end

  defp recovered_vo_status(_text, %{vo_eligible: false}, _asset_id), do: "none"

  defp recovered_vo_status(text, %{vo_eligible: true}, asset_id) do
    status = text["vo_status"] || "none"

    cond do
      is_nil(asset_id) and status in ~w(recorded approved) -> "needed"
      status in ~w(none needed recorded approved) -> status
      true -> "none"
    end
  end

  defp recovered_vo_asset_id(text, %{vo_eligible: true}, context) do
    remap_vo_asset_id(
      text["vo_asset_id"],
      context.snapshot_data,
      context.project_id,
      context.user_id,
      context.opts
    )
  end

  defp recovered_vo_asset_id(_text, %{vo_eligible: false}, _context), do: nil

  defp recovered_speaker_id(text, %{content_role: "dialogue"}, id_maps) do
    Map.get(id_maps.sheet, text["speaker_sheet_id"])
  end

  defp recovered_speaker_id(_text, _metadata, _id_maps), do: nil

  defp remap_source_id("block", old_id, id_maps), do: Map.get(id_maps.block, old_id)
  defp remap_source_id("sheet", old_id, id_maps), do: Map.get(id_maps.sheet, old_id)
  defp remap_source_id("flow_node", old_id, id_maps), do: Map.get(id_maps.node, old_id)
  defp remap_source_id(_type, _old_id, _id_maps), do: nil

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = datetime), do: datetime

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp translated_source_hash(%{"translated_source_hash" => hash}) when is_binary(hash), do: hash

  defp translated_source_hash(text) do
    if is_binary(text["translated_text"]) and String.trim(text["translated_text"]) != "" do
      text["source_text_hash"]
    end
  end

  defp recovered_status(%{"status" => "final"} = text, translated_hash) do
    if present_translation?(text["translated_text"]) and not is_nil(text["source_text_hash"]) and
         translated_hash == text["source_text_hash"] do
      "final"
    else
      if(present_translation?(text["translated_text"]), do: "review", else: "pending")
    end
  end

  defp recovered_status(text, _translated_hash) do
    case text["status"] do
      status when status in ~w(pending draft in_progress review final) -> status
      _status -> if(present_translation?(text["translated_text"]), do: "draft", else: "pending")
    end
  end

  defp recovered_archive_reason(reason)
       when reason in ["source_deleted", "source_field_removed", "source_not_runtime", "version_replaced"], do: reason

  defp recovered_archive_reason(_reason), do: nil

  defp present_translation?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_translation?(_value), do: false

  defp remap_vo_asset_id(nil, _snapshot_data, _project_id, _user_id, _opts), do: nil

  defp remap_vo_asset_id(asset_id, snapshot_data, project_id, user_id, opts) do
    AssetHashResolver.resolve_asset_fk(asset_id, snapshot_data, project_id, user_id, localization_asset_opts(opts))
  end

  defp localization_asset_opts(opts) do
    if Keyword.get(opts, :template_clone, false), do: [asset_mode: :copy], else: []
  end

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
