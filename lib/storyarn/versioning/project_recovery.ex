defmodule Storyarn.Versioning.ProjectRecovery do
  @moduledoc """
  Creates a new project from a project snapshot with full ID remapping.

  Unlike `ProjectSnapshotBuilder.restore_snapshot/3` which restores into an
  existing project by matching entity IDs, this module creates brand new entities
  from snapshot data and remaps all internal cross-references to point to the
  new autoincrement IDs.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.HubColors
  alias Storyarn.Localization.GlossaryEntry
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Localization.ProjectLanguage
  alias Storyarn.Localization.SourceContract
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.References
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Versioning.AssetMaterializationScope
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.FlowSnapshotNormalizer
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.RestorePolicy

  require Logger

  @recovery_id_map_keys [
    :sheet,
    :block,
    :avatar,
    :flow,
    :node,
    :connection,
    :scene,
    :pin,
    :zone
  ]
  @snapshot_format_version 2
  @snapshot_count_collections %{
    "sheets" => ["sheets"],
    "flows" => ["flows"],
    "scenes" => ["scenes"],
    "languages" => ["localization", "languages"],
    "localized_texts" => ["localization", "texts"],
    "glossary_entries" => ["localization", "glossary"]
  }

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
    with :ok <- ensure_recovery_enabled(opts) do
      snapshot_data
      |> FlowSnapshotNormalizer.normalize_project()
      |> recover_project_with_asset_scope(workspace_id, user_id, opts)
    end
  end

  defp recover_project_with_asset_scope(snapshot_data, workspace_id, user_id, opts) do
    with :ok <- validate_project_snapshot_envelope(snapshot_data),
         {:ok, tracker, owns_tracker?} <- asset_copy_tracker(opts) do
      run_project_recovery_scope(
        workspace_id,
        snapshot_data,
        user_id,
        Keyword.put(opts, :asset_copy_tracker, tracker),
        tracker,
        owns_tracker?
      )
    end
  end

  defp run_project_recovery_scope(workspace_id, snapshot_data, user_id, opts, tracker, owns_tracker?) do
    AssetMaterializationScope.run(opts, fn scoped_opts ->
      recover_project_with_tracker(
        workspace_id,
        snapshot_data,
        user_id,
        scoped_opts,
        tracker,
        owns_tracker?
      )
    end)
  end

  defp recover_project_with_tracker(workspace_id, snapshot_data, user_id, opts, tracker, owns_tracker?) do
    name = Keyword.get(opts, :name, "Recovered Project")

    try do
      result =
        Repo.transaction(
          fn ->
            case do_recover(workspace_id, snapshot_data, user_id, name, opts) do
              {:ok, project} ->
                case prepare_asset_cleanup_handoff(tracker, owns_tracker?) do
                  :ok -> project
                  {:error, reason} -> Repo.rollback({:storage_cleanup_handoff_failed, reason})
                end

              {:error, reason} ->
                Repo.rollback(reason)
            end
          end,
          timeout: to_timeout(minute: 5)
        )

      finalize_asset_copies(result, tracker, owns_tracker?)
    rescue
      error ->
        cleanup_owned_asset_copies(tracker, owns_tracker?)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        cleanup_owned_asset_copies(tracker, owns_tracker?)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp ensure_recovery_enabled(opts) do
    if template_clone?(opts) do
      :ok
    else
      RestorePolicy.ensure_enabled(:deleted_project_recovery)
    end
  end

  defp validate_project_snapshot_envelope(%{
         "format_version" => @snapshot_format_version,
         "entity_counts" => entity_counts,
         "project" => project,
         "sheets" => sheets,
         "flows" => flows,
         "scenes" => scenes,
         "tree" => tree,
         "localization" => localization,
         "asset_blob_hashes" => asset_blob_hashes,
         "asset_metadata" => asset_metadata
       })
       when is_map(entity_counts) and is_map(project) and is_list(sheets) and is_list(flows) and is_list(scenes) and
              is_map(tree) and is_map(localization) and is_map(asset_blob_hashes) and is_map(asset_metadata) do
    snapshot = %{
      "sheets" => sheets,
      "flows" => flows,
      "scenes" => scenes,
      "localization" => localization
    }

    with :ok <- validate_project_snapshot_entries(sheets, :sheet),
         :ok <- validate_project_snapshot_entries(flows, :flow),
         :ok <- validate_project_snapshot_entries(scenes, :scene) do
      validate_project_snapshot_counts(entity_counts, snapshot)
    end
  end

  defp validate_project_snapshot_envelope(%{"format_version" => version}) when version != @snapshot_format_version do
    {:error, {:unsupported_project_snapshot_format, version}}
  end

  defp validate_project_snapshot_envelope(%{"format_version" => @snapshot_format_version}) do
    {:error, :invalid_project_snapshot_envelope}
  end

  defp validate_project_snapshot_envelope(_snapshot_data) do
    {:error, :invalid_project_snapshot_envelope}
  end

  defp validate_project_snapshot_entries(entries, entity_type) do
    if Enum.all?(entries, fn
         %{"id" => id, "snapshot" => snapshot} ->
           is_integer(id) and id > 0 and is_map(snapshot)

         _entry ->
           false
       end) do
      :ok
    else
      {:error, {:invalid_project_snapshot_collection, entity_type}}
    end
  end

  defp validate_project_snapshot_counts(entity_counts, snapshot) do
    Enum.reduce_while(
      @snapshot_count_collections,
      :ok,
      fn {count_key, path}, :ok ->
        declared_count = entity_counts[count_key]
        collection = get_in(snapshot, path)

        cond do
          not (is_integer(declared_count) and declared_count >= 0) ->
            {:halt, {:error, {:invalid_project_snapshot_entity_count, count_key, declared_count}}}

          not is_list(collection) ->
            {:halt, {:error, {:invalid_project_snapshot_collection, count_key}}}

          declared_count != length(collection) ->
            {:halt, {:error, {:project_snapshot_entity_count_mismatch, count_key, declared_count, length(collection)}}}

          true ->
            {:cont, :ok}
        end
      end
    )
  end

  defp do_recover(workspace_id, snapshot_data, user_id, name, opts) do
    now = TimeHelpers.now()

    with {:ok, project} <- create_project(workspace_id, user_id, name, snapshot_data),
         {:ok, _membership} <- create_owner_membership(project, user_id),
         {:ok, sheet_maps} <- recover_sheets(project.id, snapshot_data, user_id, opts),
         {:ok, scene_maps} <- recover_scenes(project.id, snapshot_data, sheet_maps.sheet, user_id, opts),
         {:ok, flow_maps} <-
           recover_flows(
             project.id,
             snapshot_data,
             sheet_maps.sheet,
             scene_maps.scene,
             sheet_maps.avatar,
             user_id,
             opts
           ) do
      id_maps = merge_recovery_id_maps([sheet_maps, scene_maps, flow_maps])

      with :ok <- remap_sheet_refs(id_maps, snapshot_data),
           :ok <- validate_recovered_sheet_inheritance(project.id),
           :ok <- remap_flow_refs(id_maps, snapshot_data),
           :ok <- validate_recovered_flow_cycles(id_maps.flow),
           :ok <- remap_scene_refs(id_maps, snapshot_data),
           :ok <- restore_tree_hierarchy(snapshot_data, id_maps),
           :ok <- References.rebuild_project_entity_references(project.id),
           :ok <- References.rebuild_project_variable_references(project.id),
           :ok <-
             recover_localization(
               project.id,
               snapshot_data,
               id_maps,
               user_id,
               opts,
               now
             ) do
        {:ok, project}
      end
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
    builder_opts =
      materialization_opts(user_id, opts,
        preserve_external_refs: false,
        restore_localization: false,
        rebuild_references: false
      )

    materialize_entities(snapshot_data["sheets"] || [], :sheet, fn snapshot ->
      SheetBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp recover_scenes(project_id, snapshot_data, sheet_id_map, user_id, opts) do
    builder_opts =
      materialization_opts(user_id, opts,
        external_id_maps: %{sheet: sheet_id_map},
        rebuild_references: false
      )

    materialize_entities(snapshot_data["scenes"] || [], :scene, fn snapshot ->
      SceneBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp recover_flows(project_id, snapshot_data, sheet_id_map, scene_id_map, avatar_id_map, user_id, opts) do
    builder_opts =
      materialization_opts(user_id, opts,
        external_id_maps: %{
          sheet: sheet_id_map,
          avatar: avatar_id_map,
          scene: scene_id_map
        },
        restore_localization: false,
        rebuild_references: false
      )

    materialize_entities(snapshot_data["flows"] || [], :flow, fn snapshot ->
      FlowBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp materialization_opts(user_id, recovery_opts, builder_opts) do
    builder_opts =
      recovery_opts
      |> Keyword.take([
        :asset_copy_tracker,
        :asset_error_mode,
        :asset_materialization_cache,
        :asset_source_keys
      ])
      |> Keyword.merge(builder_opts)
      |> Keyword.put(:user_id, user_id)

    if template_clone?(recovery_opts) do
      Keyword.put(builder_opts, :asset_mode, :copy)
    else
      builder_opts
    end
  end

  defp materialize_entities(entries, entity_type, instantiate_fun) do
    Enum.reduce_while(entries, {:ok, empty_recovery_id_maps()}, fn entry, {:ok, id_maps} ->
      materialize_entity_entry(entry, entity_type, id_maps, instantiate_fun)
    end)
  end

  defp materialize_entity_entry(entry, entity_type, id_maps, instantiate_fun) do
    case instantiate_fun.(entry["snapshot"]) do
      {:ok, _entity, materialized_maps} ->
        merge_materialized_entity_maps(entry, entity_type, id_maps, materialized_maps)

      {:error, reason} ->
        halt_materialization(entry, entity_type, reason)
    end
  end

  defp merge_materialized_entity_maps(entry, entity_type, id_maps, materialized_maps) do
    with :ok <- validate_materialized_root_mapping(entry, entity_type, materialized_maps),
         {:ok, merged_maps} <- merge_materialized_id_maps(id_maps, materialized_maps) do
      {:cont, {:ok, merged_maps}}
    else
      {:error, reason} -> halt_materialization(entry, entity_type, reason)
    end
  end

  defp halt_materialization(entry, entity_type, reason) do
    {:halt, {:error, {:materialization_failed, entity_type, entry["id"], reason}}}
  end

  defp validate_materialized_root_mapping(entry, entity_type, materialized_maps) do
    entry_id = entry["id"]
    snapshot_id = get_in(entry, ["snapshot", "original_id"])
    materialized_id = materialized_maps |> Map.get(entity_type, %{}) |> Map.get(entry_id)

    cond do
      entry_id != snapshot_id ->
        {:error, {:project_snapshot_root_id_mismatch, entry_id, snapshot_id}}

      not is_integer(materialized_id) ->
        {:error, {:missing_materialized_root_mapping, entry_id}}

      true ->
        :ok
    end
  end

  defp merge_materialized_id_maps(existing_maps, incoming_maps) do
    Enum.reduce_while(@recovery_id_map_keys, {:ok, existing_maps}, fn key, {:ok, merged_maps} ->
      existing = Map.fetch!(merged_maps, key)
      incoming = Map.get(incoming_maps, key, %{})

      case conflicting_materialized_id(existing, incoming) do
        nil ->
          {:cont, {:ok, Map.put(merged_maps, key, Map.merge(existing, incoming))}}

        source_id ->
          {:halt, {:error, {:duplicate_project_snapshot_identity, key, source_id}}}
      end
    end)
  end

  defp conflicting_materialized_id(existing, incoming) do
    Enum.find(Map.keys(incoming), &Map.has_key?(existing, &1))
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
    Enum.reduce_while(snapshot_data["sheets"] || [], :ok, fn entry, :ok ->
      with {:ok, new_sheet_id} <-
             fetch_required_mapping(
               id_maps.sheet,
               entry["id"],
               {:sheet, entry["id"]}
             ),
           :ok <-
             remap_hidden_inherited_block_ids(
               new_sheet_id,
               entry["snapshot"],
               id_maps.block
             ),
           :ok <-
             remap_block_inheritance(
               entry["snapshot"]["blocks"] || [],
               id_maps.block
             ),
           :ok <-
             remap_sheet_block_payloads(
               entry["snapshot"]["blocks"] || [],
               id_maps
             ) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_recovered_sheet_inheritance(project_id) do
    parents =
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at),
        order_by: [asc: block.id],
        select: {block.id, block.inherited_from_block_id}
      )
      |> Repo.all()
      |> Map.new()

    parents
    |> Map.keys()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn block_id, {:ok, validated} ->
      case validate_recovered_inheritance_path(
             block_id,
             parents,
             validated,
             MapSet.new()
           ) do
        {:ok, validated} -> {:cont, {:ok, validated}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _validated} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp validate_recovered_inheritance_path(nil, _parents, validated, _path) do
    {:ok, validated}
  end

  defp validate_recovered_inheritance_path(block_id, parents, validated, path) do
    cond do
      MapSet.member?(validated, block_id) ->
        {:ok, validated}

      MapSet.member?(path, block_id) ->
        {:error, {:project_snapshot_inheritance_cycle, block_id}}

      true ->
        validate_recovered_inheritance_parent(block_id, parents, validated, path)
    end
  end

  defp validate_recovered_inheritance_parent(block_id, parents, validated, path) do
    case Map.fetch(parents, block_id) do
      {:ok, parent_id} ->
        validate_and_mark_recovered_inheritance(block_id, parent_id, parents, validated, path)

      :error ->
        {:error, {:missing_materialized_inheritance_parent, block_id}}
    end
  end

  defp validate_and_mark_recovered_inheritance(block_id, parent_id, parents, validated, path) do
    with {:ok, validated} <-
           validate_recovered_inheritance_path(
             parent_id,
             parents,
             validated,
             MapSet.put(path, block_id)
           ) do
      {:ok, MapSet.put(validated, block_id)}
    end
  end

  defp remap_hidden_inherited_block_ids(sheet_id, snapshot, block_id_map) do
    with {:ok, hidden_ids} <-
           remap_required_ids(
             snapshot["hidden_inherited_block_ids"] || [],
             block_id_map,
             {:sheet, snapshot["original_id"], "hidden_inherited_block_ids"}
           ),
         {1, _rows} <-
           Repo.update_all(
             from(sheet in Sheet, where: sheet.id == ^sheet_id),
             set: [hidden_inherited_block_ids: hidden_ids]
           ) do
      :ok
    else
      {:error, _reason} = error ->
        error

      {count, _rows} ->
        {:error, {:materialized_row_count_mismatch, :sheet, sheet_id, count}}
    end
  end

  defp remap_block_inheritance(blocks_data, block_id_map) do
    Enum.reduce_while(blocks_data, :ok, fn block_data, :ok ->
      with {:ok, new_block_id} <-
             fetch_required_mapping(
               block_id_map,
               block_data["original_id"],
               {:block, block_data["original_id"]}
             ),
           {:ok, remapped_parent} <-
             fetch_optional_mapping(
               block_id_map,
               block_data["inherited_from_block_id"],
               {:block, block_data["original_id"], "inherited_from_block_id"}
             ),
           {1, _rows} <-
             Repo.update_all(
               from(block in Block, where: block.id == ^new_block_id),
               set: [inherited_from_block_id: remapped_parent]
             ) do
        {:cont, :ok}
      else
        {:error, _reason} = error ->
          {:halt, error}

        {count, _rows} ->
          {:halt, {:error, {:materialized_row_count_mismatch, :block, block_data["original_id"], count}}}
      end
    end)
  end

  defp remap_sheet_block_payloads(blocks, id_maps) do
    Enum.reduce_while(blocks, :ok, fn block, :ok ->
      with {:ok, block_id} <-
             fetch_required_mapping(
               id_maps.block,
               block["original_id"],
               {:block, block["original_id"]}
             ),
           {:ok, value} <-
             remap_sheet_block_value(
               block["type"],
               block["value"],
               id_maps,
               block["original_id"]
             ),
           {1, _rows} <-
             Repo.update_all(
               from(materialized_block in Block,
                 where: materialized_block.id == ^block_id
               ),
               set: [value: value]
             ) do
        {:cont, :ok}
      else
        {:error, _reason} = error ->
          {:halt, error}

        {count, _rows} ->
          {:halt, {:error, {:materialized_row_count_mismatch, :block, block["original_id"], count}}}
      end
    end)
  end

  defp remap_sheet_block_value("reference", value, id_maps, block_id) when is_map(value) do
    with {:ok, value} <-
           remap_block_reference_target(
             value,
             id_maps,
             block_id
           ) do
      remap_embedded_mentions(value, id_maps, {:block, block_id})
    end
  end

  defp remap_sheet_block_value("reference", value, _id_maps, block_id) do
    {:error, {:invalid_project_snapshot_reference_block, block_id, value}}
  end

  defp remap_sheet_block_value(_block_type, value, id_maps, block_id) do
    remap_embedded_mentions(value, id_maps, {:block, block_id})
  end

  defp remap_block_reference_target(value, id_maps, block_id) do
    case {value["target_type"], value["target_id"]} do
      {nil, nil} ->
        {:ok, value}

      {target_type, source_target_id}
      when target_type in ["sheet", "flow"] and
             is_integer(source_target_id) ->
        id_map =
          if target_type == "sheet",
            do: id_maps.sheet,
            else: id_maps.flow

        with {:ok, target_id} <-
               fetch_required_mapping(
                 id_map,
                 source_target_id,
                 {:block, block_id, "target_id", target_type}
               ) do
          {:ok, Map.put(value, "target_id", target_id)}
        end

      {target_type, source_target_id} ->
        {:error, {:invalid_project_snapshot_typed_reference, {:block, block_id}, target_type, source_target_id}}
    end
  end

  defp remap_flow_refs(id_maps, snapshot_data) do
    flow_entries = snapshot_data["flows"] || []
    snapshot_node_index = build_flow_snapshot_node_index(flow_entries)

    Enum.reduce_while(flow_entries, :ok, fn entry, :ok ->
      case remap_single_flow_snapshot(entry, id_maps, snapshot_node_index) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_recovered_flow_cycles(flow_id_map) do
    flow_id_map
    |> Map.values()
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.reduce_while(:ok, fn flow_id, :ok ->
      case FlowBuilder.validate_materialized_reference_cycles(flow_id) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp build_flow_snapshot_node_index(flow_entries) do
    Enum.reduce(flow_entries, %{}, &index_flow_snapshot_nodes/2)
  end

  defp index_flow_snapshot_nodes(entry, index) do
    flow_id = normalize_recovery_id(entry["id"])

    Enum.reduce(
      entry["snapshot"]["nodes"] || [],
      index,
      &index_flow_snapshot_node(&1, &2, flow_id)
    )
  end

  defp index_flow_snapshot_node(node, index, flow_id) do
    case normalize_recovery_id(node["original_id"]) do
      nil ->
        index

      node_id ->
        Map.put(index, node_id, %{
          flow_id: flow_id,
          type: node["type"]
        })
    end
  end

  defp remap_single_flow_snapshot(entry, id_maps, snapshot_node_index) do
    with {:ok, new_flow_id} <-
           fetch_required_mapping(
             id_maps.flow,
             entry["id"],
             {:flow, entry["id"]}
           ),
         :ok <-
           remap_flow_scene_id(
             new_flow_id,
             entry["snapshot"]["scene_id"],
             id_maps.scene
           ),
         :ok <-
           remap_flow_nodes(
             entry["snapshot"]["nodes"] || [],
             new_flow_id,
             id_maps
           ) do
      remap_flow_dynamic_exit_pins(
        entry,
        new_flow_id,
        id_maps,
        snapshot_node_index
      )
    end
  end

  defp remap_flow_nodes(nodes, new_flow_id, id_maps) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case remap_node_snapshot(node, new_flow_id, id_maps) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_flow_dynamic_exit_pins(entry, new_flow_id, id_maps, snapshot_node_index) do
    snapshot = entry["snapshot"]
    nodes = snapshot["nodes"] || []

    Enum.reduce_while(snapshot["connections"] || [], :ok, fn connection, :ok ->
      source_node = Enum.at(nodes, connection["source_node_index"])

      case remap_recovered_dynamic_exit_pin(
             connection,
             source_node,
             new_flow_id,
             id_maps,
             snapshot_node_index
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_recovered_dynamic_exit_pin(
         %{"original_id" => connection_id, "source_pin" => "exit_" <> old_id_text = pin},
         %{"type" => "subflow"} = source_node,
         new_flow_id,
         id_maps,
         snapshot_node_index
       ) do
    with {old_exit_id, ""} <- Integer.parse(old_id_text),
         old_referenced_flow_id when is_integer(old_referenced_flow_id) <-
           normalize_recovery_id(get_in(source_node, ["data", "referenced_flow_id"])) do
      case Map.get(snapshot_node_index, old_exit_id) do
        %{flow_id: ^old_referenced_flow_id, type: "exit"} ->
          materialize_recovered_dynamic_exit_pin(
            connection_id,
            pin,
            old_exit_id,
            old_referenced_flow_id,
            source_node["original_id"],
            new_flow_id,
            id_maps
          )

        _missing_or_wrong_owner ->
          {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :exit_not_in_referenced_flow_snapshot}}
      end
    else
      _invalid_dynamic_pin ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :invalid_dynamic_exit_reference}}
    end
  end

  defp remap_recovered_dynamic_exit_pin(_connection, _source_node, _new_flow_id, _id_maps, _snapshot_node_index), do: :ok

  defp materialize_recovered_dynamic_exit_pin(
         connection_id,
         pin,
         old_exit_id,
         old_referenced_flow_id,
         old_source_node_id,
         new_flow_id,
         id_maps
       ) do
    with {:ok, new_referenced_flow_id} <-
           fetch_recovery_mapping(
             id_maps.flow,
             old_referenced_flow_id,
             connection_id,
             pin,
             :missing_referenced_flow_mapping
           ),
         {:ok, new_exit_id} <-
           fetch_recovery_mapping(
             id_maps.node,
             old_exit_id,
             connection_id,
             pin,
             :missing_exit_node_mapping
           ),
         {:ok, new_source_node_id} <-
           fetch_recovery_mapping(
             id_maps.node,
             old_source_node_id,
             connection_id,
             pin,
             :missing_source_node_mapping
           ),
         {:ok, new_connection_id} <-
           fetch_recovery_mapping(
             id_maps.connection,
             connection_id,
             connection_id,
             pin,
             :missing_connection_mapping
           ),
         :ok <-
           validate_recovered_exit_node(
             new_exit_id,
             new_referenced_flow_id,
             connection_id,
             pin
           ) do
      update_recovered_dynamic_exit_pin(
        new_connection_id,
        new_flow_id,
        new_source_node_id,
        connection_id,
        pin,
        "exit_#{new_exit_id}"
      )
    end
  end

  defp fetch_recovery_mapping(id_map, old_id, connection_id, pin, missing_reason) do
    case old_id |> remap_id(id_map) |> normalize_recovery_id() do
      nil ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, missing_reason}}

      new_id ->
        {:ok, new_id}
    end
  end

  defp validate_recovered_exit_node(new_exit_id, new_referenced_flow_id, connection_id, pin) do
    query =
      from(node in FlowNode,
        where:
          node.id == ^new_exit_id and node.flow_id == ^new_referenced_flow_id and
            node.type == "exit" and is_nil(node.deleted_at),
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      %FlowNode{} ->
        :ok

      nil ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :mapped_exit_not_in_referenced_flow}}
    end
  end

  defp update_recovered_dynamic_exit_pin(
         new_connection_id,
         new_flow_id,
         new_source_node_id,
         connection_id,
         old_pin,
         new_pin
       ) do
    query =
      from(connection in FlowConnection,
        where:
          connection.id == ^new_connection_id and connection.flow_id == ^new_flow_id and
            connection.source_node_id == ^new_source_node_id and
            connection.source_pin == ^old_pin,
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      %FlowConnection{} = connection ->
        case connection
             |> FlowConnection.update_changeset(%{source_pin: new_pin})
             |> Repo.update() do
          {:ok, _connection} ->
            :ok

          {:error, changeset} ->
            {:error,
             {:dynamic_exit_pin_not_materializable, connection_id, old_pin, {:connection_update_failed, changeset}}}
        end

      nil ->
        {:error, {:dynamic_exit_pin_not_materializable, connection_id, old_pin, :materialized_connection_not_found}}
    end
  end

  defp normalize_recovery_id(value) when is_integer(value) and value > 0, do: value

  defp normalize_recovery_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> id
      _invalid -> nil
    end
  end

  defp normalize_recovery_id(_value), do: nil

  defp remap_node_snapshot(node_data, new_flow_id, id_maps) do
    with {:ok, new_node_id} <-
           fetch_required_mapping(
             id_maps.node,
             node_data["original_id"],
             {:flow_node, node_data["original_id"]}
           ) do
      remap_single_node_data(
        new_node_id,
        new_flow_id,
        node_data["original_id"],
        node_data["type"],
        node_data["data"] || %{},
        id_maps
      )
    end
  end

  defp remap_flow_scene_id(_new_flow_id, nil, _scene_map), do: :ok

  defp remap_flow_scene_id(new_flow_id, old_scene_id, scene_map) do
    with {:ok, new_scene_id} <-
           fetch_required_mapping(
             scene_map,
             old_scene_id,
             {:flow, new_flow_id, "scene_id"}
           ),
         {1, _rows} <-
           Repo.update_all(
             from(flow in Flow, where: flow.id == ^new_flow_id),
             set: [scene_id: new_scene_id]
           ) do
      :ok
    else
      {:error, _reason} = error ->
        error

      {count, _rows} ->
        {:error, {:materialized_row_count_mismatch, :flow, new_flow_id, count}}
    end
  end

  defp remap_single_node_data(node_id, new_flow_id, source_node_id, node_type, data, id_maps) do
    original_data = data

    with {:ok, data} <-
           remap_node_data_reference(
             data,
             "speaker_sheet_id",
             id_maps.sheet,
             source_node_id
           ),
         {:ok, data} <-
           remap_node_data_reference(
             data,
             "location_sheet_id",
             id_maps.sheet,
             source_node_id
           ),
         {:ok, data} <-
           remap_node_data_reference(
             data,
             "referenced_flow_id",
             id_maps.flow,
             source_node_id
           ),
         {:ok, data} <-
           remap_node_data_reference(
             data,
             "avatar_id",
             id_maps.avatar,
             source_node_id
           ),
         {:ok, data} <-
           remap_node_typed_target(
             data,
             id_maps,
             source_node_id
           ),
         {:ok, data} <-
           remap_embedded_mentions(
             data,
             id_maps,
             {:flow_node, source_node_id}
           ),
         {:ok, new_data} <-
           AvatarIntegrity.lock_and_normalize_node_avatar(
             new_flow_id,
             node_type,
             normalize_hub_color(data, node_type)
           ) do
      persist_remapped_node_data(node_id, original_data, new_data)
    end
  end

  defp persist_remapped_node_data(_node_id, data, data), do: :ok

  defp persist_remapped_node_data(node_id, _original_data, new_data) do
    case Repo.update_all(
           from(node in FlowNode, where: node.id == ^node_id),
           set: [data: new_data]
         ) do
      {1, _rows} -> :ok
      {count, _rows} -> {:error, {:materialized_row_count_mismatch, :flow_node, node_id, count}}
    end
  end

  defp normalize_hub_color(data, "hub") do
    Map.put(data, "color", HubColors.resolve_legacy(data["color"]))
  end

  defp normalize_hub_color(data, _node_type), do: data

  defp remap_node_data_reference(data, key, id_map, source_node_id) do
    case Map.fetch(data, key) do
      {:ok, value} ->
        with {:ok, remapped_id} <-
               fetch_optional_mapping(
                 id_map,
                 value,
                 {:flow_node, source_node_id, key}
               ) do
          {:ok, Map.put(data, key, remapped_id)}
        end

      :error ->
        {:ok, data}
    end
  end

  defp remap_node_typed_target(data, id_maps, source_node_id) do
    case {data["target_type"], data["target_id"]} do
      {nil, nil} ->
        {:ok, data}

      {target_type, source_target_id}
      when target_type in ["flow", "scene"] and
             is_integer(source_target_id) ->
        id_map =
          if target_type == "flow",
            do: id_maps.flow,
            else: id_maps.scene

        with {:ok, target_id} <-
               fetch_required_mapping(
                 id_map,
                 source_target_id,
                 {:flow_node, source_node_id, "target_id", target_type}
               ) do
          {:ok, Map.put(data, "target_id", target_id)}
        end

      {target_type, source_target_id} ->
        source = {:flow_node, source_node_id}
        {:error, {:invalid_project_snapshot_typed_reference, source, target_type, source_target_id}}
    end
  end

  defp remap_scene_refs(id_maps, snapshot_data) do
    Enum.reduce_while(snapshot_data["scenes"] || [], :ok, fn entry, :ok ->
      case remap_single_scene_snapshot(entry, id_maps) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_single_scene_snapshot(entry, id_maps) do
    snapshot = entry["snapshot"]

    with {:ok, scene_id} <-
           fetch_required_mapping(
             id_maps.scene,
             entry["id"],
             {:scene, entry["id"]}
           ),
         :ok <- remap_scene_pin_refs(snapshot["orphan_pins"] || [], id_maps),
         :ok <- remap_scene_zone_refs(snapshot["orphan_zones"] || [], id_maps),
         :ok <-
           remap_scene_ambient_flows(
             scene_id,
             snapshot["ambient_flows"] || [],
             id_maps.flow
           ) do
      remap_scene_layer_refs(snapshot["layers"] || [], id_maps)
    end
  end

  defp remap_scene_layer_refs(layers, id_maps) do
    Enum.reduce_while(layers, :ok, fn layer, :ok ->
      with :ok <- remap_scene_pin_refs(layer["pins"] || [], id_maps),
           :ok <- remap_scene_zone_refs(layer["zones"] || [], id_maps) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_scene_ambient_flows(scene_id, ambient_flows, flow_id_map) do
    Enum.reduce_while(ambient_flows, :ok, fn ambient_flow, :ok ->
      with {:ok, flow_id} <-
             fetch_required_mapping(
               flow_id_map,
               ambient_flow["flow_id"],
               {:scene_ambient_flow, ambient_flow["original_id"], "flow_id"}
             ),
           {:ok, _ambient_flow} <-
             %SceneAmbientFlow{scene_id: scene_id}
             |> SceneAmbientFlow.changeset(%{
               flow_id: flow_id,
               trigger_type: ambient_flow["trigger_type"],
               trigger_config: ambient_flow["trigger_config"],
               priority: ambient_flow["priority"],
               enabled: ambient_flow["enabled"],
               position: ambient_flow["position"]
             })
             |> Repo.insert() do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp remap_scene_pin_refs(pin_snapshots, id_maps) do
    Enum.reduce_while(pin_snapshots, :ok, fn pin, :ok ->
      case remap_single_scene_pin_ref(pin, id_maps) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_scene_zone_refs(zone_snapshots, id_maps) do
    Enum.reduce_while(zone_snapshots, :ok, fn zone, :ok ->
      case remap_single_scene_zone_ref(zone, id_maps) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_single_scene_pin_ref(pin_data, id_maps) do
    with {:ok, new_pin_id} <-
           fetch_required_mapping(
             id_maps.pin,
             pin_data["original_id"],
             {:scene_pin, pin_data["original_id"]}
           ),
         {:ok, updates} <- build_scene_pin_updates(pin_data, id_maps) do
      maybe_update_scene_pin(updates, new_pin_id)
    end
  end

  defp build_scene_pin_updates(pin_data, id_maps) do
    with {:ok, sheet_id} <-
           fetch_optional_mapping(
             id_maps.sheet,
             pin_data["sheet_id"],
             {:scene_pin, pin_data["original_id"], "sheet_id"}
           ),
         {:ok, flow_id} <-
           fetch_optional_mapping(
             id_maps.flow,
             pin_data["flow_id"],
             {:scene_pin, pin_data["original_id"], "flow_id"}
           ) do
      {:ok, [sheet_id: sheet_id, flow_id: flow_id]}
    end
  end

  defp maybe_update_scene_pin(updates, new_pin_id) do
    case Repo.update_all(
           from(pin in ScenePin, where: pin.id == ^new_pin_id),
           set: updates
         ) do
      {1, _rows} -> :ok
      {count, _rows} -> {:error, {:materialized_row_count_mismatch, :scene_pin, new_pin_id, count}}
    end
  end

  defp remap_single_scene_zone_ref(zone_data, id_maps) do
    with {:ok, new_zone_id} <-
           fetch_required_mapping(
             id_maps.zone,
             zone_data["original_id"],
             {:scene_zone, zone_data["original_id"]}
           ),
         {:ok, updates} <- build_scene_zone_updates(zone_data, id_maps) do
      maybe_update_scene_zone(updates, new_zone_id)
    end
  end

  defp build_scene_zone_updates(zone_data, id_maps) do
    maybe_put_target_update(
      [],
      zone_data["target_type"],
      zone_data["target_id"],
      id_maps,
      zone_data["original_id"]
    )
  end

  defp maybe_update_scene_zone([], _new_zone_id), do: :ok

  defp maybe_update_scene_zone(updates, new_zone_id) do
    case Repo.update_all(
           from(zone in SceneZone, where: zone.id == ^new_zone_id),
           set: updates
         ) do
      {1, _rows} -> :ok
      {count, _rows} -> {:error, {:materialized_row_count_mismatch, :scene_zone, new_zone_id, count}}
    end
  end

  defp maybe_put_target_update(updates, _type, nil, _id_maps, _zone_id), do: {:ok, updates}
  defp maybe_put_target_update(updates, _type, "", _id_maps, _zone_id), do: {:ok, updates}

  defp maybe_put_target_update(updates, type, old_id, id_maps, zone_id) do
    case remap_target_id(type, old_id, id_maps) do
      nil ->
        {:error, {:missing_project_snapshot_reference, {:scene_zone, zone_id, "target_id", type}, old_id}}

      new_id ->
        {:ok,
         updates
         |> Keyword.put(:target_type, type)
         |> Keyword.put(:target_id, new_id)}
    end
  end

  defp remap_id(nil, _map), do: nil

  defp remap_id(old_id, map) when is_binary(old_id) do
    case Map.fetch(map, old_id) do
      {:ok, new_id} ->
        new_id

      :error ->
        case Integer.parse(old_id) do
          {integer_id, ""} -> Map.get(map, integer_id)
          _ -> nil
        end
    end
  end

  defp remap_id(old_id, map), do: Map.get(map, old_id)

  defp fetch_required_mapping(id_map, source_id, context) do
    case remap_id(source_id, id_map) do
      destination_id when is_integer(destination_id) ->
        {:ok, destination_id}

      _missing ->
        {:error, {:missing_project_snapshot_reference, context, source_id}}
    end
  end

  defp fetch_optional_mapping(_id_map, nil, _context), do: {:ok, nil}

  defp fetch_optional_mapping(id_map, source_id, context) do
    fetch_required_mapping(id_map, source_id, context)
  end

  defp remap_required_ids(source_ids, id_map, context) do
    source_ids
    |> Enum.reduce_while({:ok, []}, fn source_id, {:ok, destination_ids} ->
      case fetch_required_mapping(id_map, source_id, context) do
        {:ok, destination_id} ->
          {:cont, {:ok, [destination_id | destination_ids]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, destination_ids} -> {:ok, Enum.reverse(destination_ids)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_embedded_mentions(value, id_maps, context)

  defp remap_embedded_mentions(value, id_maps, context) when is_binary(value) do
    if mention_markup?(value) do
      with {:ok, document} <- Floki.parse_fragment(value),
           {:ok, document} <-
             remap_mention_nodes(
               document,
               id_maps,
               context
             ) do
        {:ok, Floki.raw_html(document)}
      else
        {:error, reason} ->
          {:error, {:invalid_project_snapshot_mention, context, reason}}
      end
    else
      {:ok, value}
    end
  end

  defp remap_embedded_mentions(value, id_maps, context) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, remapped} ->
      case remap_embedded_mentions(item, id_maps, context) do
        {:ok, item} -> {:cont, {:ok, [item | remapped]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remapped} -> {:ok, Enum.reverse(remapped)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_embedded_mentions(value, id_maps, context) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, remapped} ->
      case remap_embedded_mentions(item, id_maps, context) do
        {:ok, item} -> {:cont, {:ok, Map.put(remapped, key, item)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_embedded_mentions(value, _id_maps, _context), do: {:ok, value}

  defp mention_markup?(value) do
    Regex.match?(
      ~r/<[^>]+\bclass\s*=\s*["'][^"']*\bmention\b[^"']*["']/u,
      value
    )
  end

  defp remap_mention_nodes(nodes, id_maps, context) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, remapped} ->
      case remap_mention_node(node, id_maps, context) do
        {:ok, node} -> {:cont, {:ok, [node | remapped]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remapped} -> {:ok, Enum.reverse(remapped)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_mention_node({tag, attributes, children}, id_maps, context)
       when is_binary(tag) and is_list(attributes) and is_list(children) do
    with {:ok, attributes} <-
           remap_mention_attributes(
             attributes,
             id_maps,
             context
           ),
         {:ok, children} <-
           remap_mention_nodes(
             children,
             id_maps,
             context
           ) do
      {:ok, {tag, attributes, children}}
    end
  end

  defp remap_mention_node(node, _id_maps, _context), do: {:ok, node}

  defp remap_mention_attributes(attributes, id_maps, context) do
    remap_mention_attributes_by_kind(
      mention_attributes?(attributes),
      attributes,
      id_maps,
      context
    )
  end

  defp remap_mention_attributes_by_kind(false, attributes, _id_maps, _context), do: {:ok, attributes}

  defp remap_mention_attributes_by_kind(true, attributes, id_maps, context) do
    target_type = attribute_value(attributes, "data-type")
    source_id = attributes |> attribute_value("data-id") |> normalize_recovery_id()

    with {:ok, id_map} <- mention_target_id_map(target_type, id_maps),
         {:ok, source_id} <- validate_mention_source_id(source_id, attributes),
         {:ok, target_id} <-
           fetch_required_mapping(
             id_map,
             source_id,
             {:mention, context, target_type}
           ) do
      {:ok, put_attribute(attributes, "data-id", Integer.to_string(target_id))}
    end
  end

  defp mention_target_id_map("sheet", id_maps), do: {:ok, id_maps.sheet}
  defp mention_target_id_map("flow", id_maps), do: {:ok, id_maps.flow}
  defp mention_target_id_map(target_type, _id_maps), do: {:error, {:unsupported_mention_target_type, target_type}}

  defp validate_mention_source_id(nil, attributes) do
    {:error, {:invalid_mention_target_id, attribute_value(attributes, "data-id")}}
  end

  defp validate_mention_source_id(source_id, _attributes), do: {:ok, source_id}

  defp mention_attributes?(attributes) do
    attributes
    |> attribute_value("class")
    |> to_string()
    |> String.split()
    |> Enum.member?("mention")
  end

  defp attribute_value(attributes, name) do
    case List.keyfind(attributes, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp put_attribute(attributes, name, value) do
    case List.keytake(attributes, name, 0) do
      {{^name, _old_value}, remaining} -> [{name, value} | remaining]
      nil -> [{name, value} | attributes]
    end
  end

  defp remap_target_id("sheet", old_id, id_maps), do: remap_id(old_id, id_maps.sheet)
  defp remap_target_id("flow", old_id, id_maps), do: remap_id(old_id, id_maps.flow)
  defp remap_target_id("scene", old_id, id_maps), do: remap_id(old_id, id_maps.scene)
  defp remap_target_id(_type, _old_id, _id_maps), do: nil

  # ========== Phase C: Tree Hierarchy ==========

  defp restore_tree_hierarchy(%{"tree" => tree}, id_maps) when is_map(tree) do
    with :ok <- remap_tree(tree["sheets"], id_maps.sheet, Sheet, :sheet),
         :ok <- remap_tree(tree["flows"], id_maps.flow, Flow, :flow) do
      remap_tree(
        tree["scenes"],
        id_maps.scene,
        Storyarn.Scenes.Scene,
        :scene
      )
    end
  end

  defp restore_tree_hierarchy(_snapshot_data, _id_maps) do
    {:error, :missing_or_invalid_project_snapshot_tree}
  end

  defp remap_tree(tree_entries, id_map, schema, entity_type) when is_list(tree_entries) do
    with :ok <- validate_tree_entries(tree_entries, id_map, entity_type),
         :ok <- validate_tree_cycles(tree_entries, entity_type) do
      remap_tree_entries(tree_entries, id_map, schema, entity_type)
    end
  end

  defp remap_tree(_tree_entries, _id_map, _schema, entity_type) do
    {:error, {:invalid_project_snapshot_tree_collection, entity_type}}
  end

  defp remap_tree_entries(tree_entries, id_map, schema, entity_type) do
    Enum.reduce_while(tree_entries, :ok, fn entry, :ok ->
      remap_tree_entry(entry, id_map, schema, entity_type)
    end)
  end

  defp remap_tree_entry(entry, id_map, schema, entity_type) do
    with {:ok, new_id} <-
           fetch_required_mapping(
             id_map,
             entry["id"],
             {:tree, entity_type, entry["id"]}
           ),
         {:ok, new_parent_id} <-
           fetch_optional_mapping(
             id_map,
             entry["parent_id"],
             {:tree, entity_type, entry["id"], "parent_id"}
           ),
         :ok <-
           apply_tree_position(
             schema,
             entity_type,
             new_id,
             new_parent_id,
             entry["position"]
           ) do
      {:cont, :ok}
    else
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp validate_tree_entries(entries, id_map, entity_type) do
    source_ids = Enum.map(entries, &tree_entry_id/1)
    expected_ids = Map.keys(id_map)

    cond do
      Enum.any?(entries, &(not valid_tree_entry?(&1))) ->
        {:error, {:invalid_project_snapshot_tree_entry, entity_type}}

      length(source_ids) != MapSet.size(MapSet.new(source_ids)) ->
        {:error, {:duplicate_project_snapshot_tree_identity, entity_type}}

      not MapSet.equal?(MapSet.new(source_ids), MapSet.new(expected_ids)) ->
        {:error, {:project_snapshot_tree_coverage_mismatch, entity_type, Enum.sort(expected_ids), Enum.sort(source_ids)}}

      Enum.any?(entries, &invalid_tree_parent?(&1, id_map)) ->
        {:error, {:invalid_project_snapshot_tree_parent, entity_type}}

      true ->
        :ok
    end
  end

  defp tree_entry_id(entry) when is_map(entry), do: entry["id"]
  defp tree_entry_id(_entry), do: nil

  defp valid_tree_entry?(entry) when is_map(entry) do
    is_integer(entry["id"]) and entry["id"] > 0 and
      (is_nil(entry["parent_id"]) or
         (is_integer(entry["parent_id"]) and entry["parent_id"] > 0)) and
      is_integer(entry["position"]) and entry["position"] >= 0
  end

  defp valid_tree_entry?(_entry), do: false

  defp invalid_tree_parent?(entry, id_map) do
    parent_id = entry["parent_id"]

    not is_nil(parent_id) and
      (parent_id == entry["id"] or not Map.has_key?(id_map, parent_id))
  end

  defp validate_tree_cycles(entries, entity_type) do
    parents = Map.new(entries, &{&1["id"], &1["parent_id"]})

    Enum.reduce_while(Map.keys(parents), :ok, fn id, :ok ->
      case trace_tree_parent(id, parents, MapSet.new()) do
        :ok -> {:cont, :ok}
        :cycle -> {:halt, {:error, {:project_snapshot_tree_cycle, entity_type, id}}}
      end
    end)
  end

  defp trace_tree_parent(nil, _parents, _visited), do: :ok

  defp trace_tree_parent(id, parents, visited) do
    if MapSet.member?(visited, id) do
      :cycle
    else
      trace_tree_parent(
        Map.get(parents, id),
        parents,
        MapSet.put(visited, id)
      )
    end
  end

  defp apply_tree_position(schema, entity_type, new_id, new_parent_id, position) do
    case Repo.update_all(
           from(entity in schema, where: entity.id == ^new_id),
           set: [position: position, parent_id: new_parent_id]
         ) do
      {1, _rows} -> :ok
      {count, _rows} -> {:error, {:materialized_row_count_mismatch, entity_type, new_id, count}}
    end
  end

  # ========== Phase D: Localization ==========

  defp recover_localization(project_id, snapshot_data, id_maps, user_id, opts, now) do
    case snapshot_data["localization"] do
      nil ->
        :ok

      localization when is_map(localization) ->
        languages = Map.get(localization, "languages", [])
        texts = Map.get(localization, "texts", [])
        glossary = Map.get(localization, "glossary", [])

        with :ok <-
               validate_recovery_localization(
                 languages,
                 texts,
                 glossary,
                 id_maps,
                 snapshot_data
               ),
             :ok <- restore_languages(project_id, languages, now),
             :ok <-
               restore_texts(
                 project_id,
                 materializable_recovery_texts(texts, id_maps),
                 id_maps,
                 snapshot_data,
                 user_id,
                 opts,
                 now
               ) do
          restore_glossary(project_id, glossary, now)
        end

      _invalid ->
        {:error, :invalid_project_snapshot_localization}
    end
  end

  defp validate_recovery_localization(languages, texts, glossary, id_maps, snapshot_data)
       when is_list(languages) and is_list(texts) and is_list(glossary) do
    with {:ok, locale_codes} <- validate_recovery_languages(languages),
         :ok <- validate_recovery_texts(texts, locale_codes, id_maps),
         :ok <-
           validate_runtime_localization_inventory(
             languages,
             texts,
             snapshot_data
           ) do
      validate_recovery_glossary(glossary, locale_codes)
    end
  end

  defp validate_recovery_localization(_languages, _texts, _glossary, _id_maps, _snapshot_data) do
    {:error, :invalid_project_snapshot_localization_collections}
  end

  defp validate_recovery_languages([]), do: {:ok, MapSet.new()}

  defp validate_recovery_languages(languages) do
    locale_codes = Enum.map(languages, &recovery_language_locale/1)
    source_languages = Enum.count(languages, &recovery_source_language?/1)

    cond do
      Enum.any?(languages, &(not valid_recovery_language?(&1))) ->
        {:error, :invalid_project_snapshot_language}

      length(locale_codes) != MapSet.size(MapSet.new(locale_codes)) ->
        {:error, :duplicate_project_snapshot_language}

      source_languages > 1 ->
        {:error, {:invalid_project_snapshot_source_language_count, source_languages}}

      true ->
        {:ok, MapSet.new(locale_codes)}
    end
  end

  defp recovery_language_locale(language) when is_map(language), do: language["locale_code"]
  defp recovery_language_locale(_language), do: nil

  defp recovery_source_language?(%{"is_source" => true}), do: true
  defp recovery_source_language?(_language), do: false

  defp valid_recovery_language?(language) when is_map(language) do
    valid_recovery_language_identity?(language) and
      valid_recovery_language_state?(language)
  end

  defp valid_recovery_language?(_language), do: false

  defp valid_recovery_language_identity?(language) do
    nonempty_binary?(language["locale_code"]) and nonempty_binary?(language["name"])
  end

  defp valid_recovery_language_state?(language) do
    is_boolean(language["is_source"]) and
      valid_nonnegative_integer?(language["position"]) and
      valid_recovery_datetime?(language["archived_at"]) and
      valid_recovery_source_language_state?(language)
  end

  defp valid_recovery_source_language_state?(%{"is_source" => true, "archived_at" => archived_at}) do
    is_nil(archived_at)
  end

  defp valid_recovery_source_language_state?(_language), do: true

  defp nonempty_binary?(value), do: is_binary(value) and value != ""
  defp valid_nonnegative_integer?(value), do: is_integer(value) and value >= 0

  defp validate_recovery_texts(texts, locale_codes, id_maps) do
    if Enum.all?(texts, &is_map/1) do
      keys =
        Enum.map(
          texts,
          &{
            &1["source_type"],
            &1["source_id"],
            &1["source_field"],
            &1["locale_code"]
          }
        )

      if length(keys) == MapSet.size(MapSet.new(keys)) do
        validate_recovery_text_rows(texts, locale_codes, id_maps)
      else
        {:error, :duplicate_project_snapshot_localized_text}
      end
    else
      {:error, :invalid_project_snapshot_localized_text}
    end
  end

  defp validate_recovery_text_rows(texts, locale_codes, id_maps) do
    Enum.reduce_while(texts, :ok, fn text, :ok ->
      case validate_recovery_text(text, locale_codes, id_maps) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_recovery_text(text, locale_codes, id_maps) do
    metadata =
      SourceContract.field_metadata(
        text["source_type"],
        text["source_field"]
      )

    source_id =
      remap_source_id(
        text["source_type"],
        text["source_id"],
        id_maps
      )

    speaker_id =
      if is_nil(text["speaker_sheet_id"]) do
        nil
      else
        Map.get(id_maps.sheet, text["speaker_sheet_id"])
      end

    with {:ok, metadata} <- validate_recovery_text_metadata(text, metadata),
         :ok <- validate_recovery_text_source_hash(text),
         :ok <- validate_recovery_text_datetimes(text),
         :ok <- validate_recovery_text_locale(text, locale_codes),
         :ok <- validate_recovery_text_contract(text, metadata) do
      validate_recovery_text_relations(text, metadata, source_id, speaker_id)
    end
  end

  defp validate_recovery_text_metadata(text, nil) do
    {:error, {:unsupported_project_snapshot_localization_source, text["source_type"], text["source_field"]}}
  end

  defp validate_recovery_text_metadata(_text, metadata), do: {:ok, metadata}

  defp validate_recovery_text_source_hash(text) do
    if valid_recovery_source_hash?(text) do
      :ok
    else
      {:error,
       {:invalid_project_snapshot_localization_source_hash, text["source_type"], text["source_id"], text["source_field"]}}
    end
  end

  defp validate_recovery_text_datetimes(text) do
    valid? =
      Enum.all?(
        ~w(archived_at last_translated_at last_reviewed_at),
        &valid_recovery_datetime?(text[&1])
      )

    if valid? do
      :ok
    else
      {:error,
       {:invalid_project_snapshot_localization_datetime, text["source_type"], text["source_id"], text["source_field"]}}
    end
  end

  defp validate_recovery_text_locale(text, locale_codes) do
    if MapSet.member?(locale_codes, text["locale_code"]),
      do: :ok,
      else: {:error, {:missing_project_snapshot_localization_language, text["locale_code"]}}
  end

  defp validate_recovery_text_contract(text, metadata) do
    if text["content_role"] == metadata.content_role and
         text["vo_eligible"] == metadata.vo_eligible do
      :ok
    else
      {:error,
       {:invalid_project_snapshot_localization_contract, text["source_type"], text["source_id"], text["source_field"]}}
    end
  end

  defp validate_recovery_text_relations(text, metadata, source_id, speaker_id) do
    cond do
      deferred_archived_orphan?(text, source_id) ->
        :ok

      is_nil(source_id) ->
        {:error,
         {:missing_project_snapshot_localization_source, text["source_type"], text["source_id"], text["source_field"]}}

      not is_nil(text["speaker_sheet_id"]) and is_nil(speaker_id) ->
        {:error, {:missing_project_snapshot_localization_speaker, text["speaker_sheet_id"]}}

      not is_nil(text["speaker_sheet_id"]) and
          metadata.content_role not in ~w(dialogue response) ->
        {:error, {:invalid_project_snapshot_localization_speaker, text["source_type"], text["source_field"]}}

      true ->
        :ok
    end
  end

  defp materializable_recovery_texts(texts, id_maps) do
    Enum.reject(texts, fn text ->
      source_id =
        remap_source_id(
          text["source_type"],
          text["source_id"],
          id_maps
        )

      deferred_archived_orphan?(text, source_id)
    end)
  end

  defp deferred_archived_orphan?(text, nil) do
    not is_nil(text["archived_at"])
  end

  defp deferred_archived_orphan?(_text, _source_id), do: false

  defp validate_runtime_localization_inventory(languages, global_texts, snapshot_data) do
    active_target_locales =
      languages
      |> Enum.filter(fn language ->
        language["is_source"] == false and is_nil(language["archived_at"])
      end)
      |> MapSet.new(& &1["locale_code"])

    runtime_global_texts =
      Enum.filter(global_texts, fn text ->
        is_nil(text["archived_at"]) and
          MapSet.member?(active_target_locales, text["locale_code"])
      end)

    with {:ok, nested_texts} <-
           collect_nested_runtime_localization(snapshot_data),
         {:ok, global_index} <-
           index_runtime_localization(
             runtime_global_texts,
             :global
           ),
         {:ok, nested_index} <-
           index_runtime_localization(
             nested_texts,
             :nested
           ),
         :ok <-
           validate_runtime_localization_coverage(
             global_index,
             nested_index
           ) do
      validate_runtime_localization_rows(global_index, nested_index)
    end
  end

  defp collect_nested_runtime_localization(snapshot_data) do
    entries =
      (snapshot_data["sheets"] || []) ++
        (snapshot_data["flows"] || [])

    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, rows} ->
      entry
      |> get_in(["snapshot", "localization"])
      |> append_nested_localization(rows)
    end)
  end

  defp append_nested_localization(localization, rows) when is_list(localization) do
    if Enum.all?(localization, &is_map/1),
      do: {:cont, {:ok, rows ++ localization}},
      else: {:halt, {:error, :invalid_nested_project_snapshot_localization}}
  end

  defp append_nested_localization(_invalid, _rows) do
    {:halt, {:error, :invalid_nested_project_snapshot_localization}}
  end

  defp index_runtime_localization(rows, source) do
    Enum.reduce_while(rows, {:ok, %{}}, fn row, {:ok, index} ->
      key = runtime_localization_key(row)

      if Map.has_key?(index, key) do
        {:halt, {:error, {:duplicate_project_snapshot_runtime_localization, source, key}}}
      else
        {:cont, {:ok, Map.put(index, key, row)}}
      end
    end)
  end

  defp validate_runtime_localization_coverage(global_index, nested_index) do
    global_keys = global_index |> Map.keys() |> MapSet.new()
    nested_keys = nested_index |> Map.keys() |> MapSet.new()

    if MapSet.equal?(global_keys, nested_keys) do
      :ok
    else
      {:error,
       {:project_snapshot_runtime_localization_coverage_mismatch,
        %{
          missing:
            nested_keys
            |> MapSet.difference(global_keys)
            |> MapSet.to_list()
            |> Enum.sort(),
          unexpected:
            global_keys
            |> MapSet.difference(nested_keys)
            |> MapSet.to_list()
            |> Enum.sort()
        }}}
    end
  end

  defp validate_runtime_localization_rows(global_index, nested_index) do
    Enum.reduce_while(nested_index, :ok, fn {key, nested_row}, :ok ->
      global_row =
        global_index
        |> Map.fetch!(key)
        |> Map.drop(["content_role", "vo_eligible"])

      if global_row == nested_row do
        {:cont, :ok}
      else
        {:halt, {:error, {:project_snapshot_runtime_localization_row_mismatch, key}}}
      end
    end)
  end

  defp runtime_localization_key(row) do
    {
      row["source_type"],
      row["source_id"],
      row["source_field"],
      row["locale_code"]
    }
  end

  defp valid_recovery_source_hash?(%{"source_text" => source_text, "source_text_hash" => source_text_hash})
       when is_binary(source_text) and is_binary(source_text_hash) do
    secure_hash_equal?(source_text_hash, hash_source_text(source_text))
  end

  defp valid_recovery_source_hash?(_text), do: false

  defp secure_hash_equal?(left, right) when byte_size(left) == byte_size(right) do
    Plug.Crypto.secure_compare(left, right)
  end

  defp secure_hash_equal?(_left, _right), do: false

  defp hash_source_text(text) when is_binary(text) do
    :sha256
    |> :crypto.hash(text)
    |> Base.encode16(case: :lower)
  end

  defp valid_recovery_datetime?(nil), do: true
  defp valid_recovery_datetime?(%DateTime{}), do: true

  defp valid_recovery_datetime?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_recovery_datetime?(_value), do: false

  defp validate_recovery_glossary(glossary, locale_codes) do
    if Enum.all?(glossary, &valid_recovery_glossary_entry?/1) do
      keys =
        Enum.map(
          glossary,
          &{
            &1["source_term"],
            &1["source_locale"],
            &1["target_locale"]
          }
        )

      cond do
        length(keys) != MapSet.size(MapSet.new(keys)) ->
          {:error, :duplicate_project_snapshot_glossary_entry}

        Enum.any?(glossary, fn entry ->
          not MapSet.member?(locale_codes, entry["source_locale"]) or
              not MapSet.member?(locale_codes, entry["target_locale"])
        end) ->
          {:error, :missing_project_snapshot_glossary_language}

        true ->
          :ok
      end
    else
      {:error, :invalid_project_snapshot_glossary_entry}
    end
  end

  defp valid_recovery_glossary_entry?(entry) when is_map(entry) do
    is_binary(entry["source_term"]) and entry["source_term"] != "" and
      is_binary(entry["source_locale"]) and
      is_binary(entry["target_locale"]) and
      is_boolean(entry["do_not_translate"])
  end

  defp valid_recovery_glossary_entry?(_entry), do: false

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

    case Repo.insert_all(ProjectLanguage, entries) do
      {count, _rows} when count == length(entries) -> :ok
      result -> {:error, {:project_language_materialization_failed, result}}
    end
  end

  defp restore_texts(_project_id, [], _id_maps, _snapshot_data, _user_id, _opts, _now), do: :ok

  defp restore_texts(project_id, texts, id_maps, snapshot_data, user_id, opts, now) do
    context = %{project_id: project_id, snapshot_data: snapshot_data, user_id: user_id, opts: opts, now: now}

    case materialize_recovery_texts(texts, id_maps, context) do
      {:ok, entries} ->
        insert_recovery_text_entries(entries)

      {:error, _reason} = error ->
        error
    end
  end

  defp insert_recovery_text_entries(entries) do
    entries
    |> Enum.chunk_every(500)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      insert_recovery_text_chunk(chunk)
    end)
  end

  defp insert_recovery_text_chunk(chunk) do
    case Repo.insert_all(LocalizedText, chunk) do
      {count, _rows} when count == length(chunk) -> {:cont, :ok}
      result -> {:halt, {:error, {:localized_text_materialization_failed, result}}}
    end
  end

  defp materialize_recovery_texts(texts, id_maps, context) do
    texts
    |> Enum.reduce_while({:ok, []}, fn text, {:ok, entries} ->
      case recovered_text_map_for_snapshot(text, id_maps, context) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, _reason} = error -> error
    end
  end

  defp recovered_text_map_for_snapshot(text, id_maps, context) do
    with {:ok, text} <- remap_localization_mentions(text, id_maps) do
      metadata =
        SourceContract.field_metadata(
          text["source_type"],
          text["source_field"]
        )

      source_id =
        remap_source_id(
          text["source_type"],
          text["source_id"],
          id_maps
        )

      {:ok,
       recovered_text_map(
         text,
         metadata,
         source_id,
         id_maps,
         context
       )}
    end
  end

  defp remap_localization_mentions(text, id_maps) do
    old_source_hash = text["source_text_hash"]

    with {:ok, source_text} <-
           remap_embedded_mentions(
             text["source_text"],
             id_maps,
             {:localization, text["source_type"], text["source_id"], text["source_field"], "source_text"}
           ),
         {:ok, translated_text} <-
           remap_embedded_mentions(
             text["translated_text"],
             id_maps,
             {:localization, text["source_type"], text["source_id"], text["source_field"], "translated_text"}
           ) do
      source_hash = hash_source_text(source_text)

      translated_source_hash =
        if text["translated_source_hash"] == old_source_hash do
          source_hash
        else
          text["translated_source_hash"]
        end

      {:ok,
       text
       |> Map.put("source_text", source_text)
       |> Map.put("source_text_hash", source_hash)
       |> Map.put("translated_text", translated_text)
       |> Map.put("translated_source_hash", translated_source_hash)}
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

  defp recovered_speaker_id(text, %{content_role: content_role}, id_maps) when content_role in ~w(dialogue response) do
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
    asset_mode = if template_clone?(opts), do: :copy, else: :reuse

    opts
    |> Keyword.take([
      :asset_copy_tracker,
      :asset_error_mode,
      :asset_materialization_cache,
      :asset_source_keys
    ])
    |> Keyword.put(:asset_mode, asset_mode)
  end

  defp template_clone?(opts) do
    Keyword.get(opts, :template_clone, false) == true
  end

  defp asset_copy_tracker(opts) do
    case Keyword.get(opts, :asset_copy_tracker) do
      reference when is_reference(reference) ->
        {:ok, reference, false}

      _reference ->
        if Repo.in_transaction?(),
          do: {:error, :asset_copy_tracker_required_in_transaction},
          else: {:ok, StorageCompensation.new(), true}
    end
  end

  defp finalize_asset_copies({:ok, _project} = result, tracker, true) do
    StorageCompensation.discard(tracker)
    result
  end

  defp finalize_asset_copies({:error, _reason} = result, tracker, true) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok ->
        result

      {:error, cleanup_reason} ->
        {:error, {:asset_storage_cleanup_failed, result, cleanup_reason}}
    end
  end

  defp finalize_asset_copies(result, _tracker, false), do: result

  defp prepare_asset_cleanup_handoff(tracker, true), do: StorageCompensation.prepare_unretained_cleanup(tracker)

  defp prepare_asset_cleanup_handoff(_tracker, false), do: :ok

  defp cleanup_owned_asset_copies(tracker, true) do
    case StorageCompensation.cleanup_after_rollback(tracker) do
      :ok ->
        :ok

      {:error, cleanup_reason} ->
        Logger.error(
          "Project recovery asset cleanup failed while preserving the original exception: " <>
            inspect(cleanup_reason)
        )

        :ok
    end
  rescue
    cleanup_error ->
      Logger.error(
        "Project recovery asset cleanup raised while preserving the original exception: " <>
          Exception.format(:error, cleanup_error, __STACKTRACE__)
      )

      :ok
  catch
    kind, cleanup_reason ->
      Logger.error(
        "Project recovery asset cleanup threw while preserving the original exception: " <>
          inspect({kind, cleanup_reason})
      )

      :ok
  end

  defp cleanup_owned_asset_copies(_tracker, false), do: :ok

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
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case Repo.insert_all(GlossaryEntry, chunk) do
        {count, _rows} when count == length(chunk) -> {:cont, :ok}
        result -> {:halt, {:error, {:glossary_materialization_failed, result}}}
      end
    end)
  end
end
