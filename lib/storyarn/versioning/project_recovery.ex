defmodule Storyarn.Versioning.ProjectRecovery do
  @moduledoc """
  Materializes portable project snapshots with fresh entity identities.

  Template materialization creates a new project and copies its assets. Exact
  snapshot restore can reuse the same graph phases inside an existing project
  after the caller has materialized the archived assets.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.LocalizationSourceContract, as: SourceContract
  alias Storyarn.Projects.NameNormalizer
  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.FlowConnectionRecord, as: FlowConnection
  alias Storyarn.Projects.Persistence.FlowNodeRecord, as: FlowNode
  alias Storyarn.Projects.Persistence.FlowRecord, as: Flow
  alias Storyarn.Projects.Persistence.GlossaryEntryRecord, as: GlossaryEntry
  alias Storyarn.Projects.Persistence.LocalizedTextRecord, as: LocalizedText
  alias Storyarn.Projects.Persistence.ProjectLanguageRecord, as: ProjectLanguage
  alias Storyarn.Projects.Persistence.SceneAmbientFlowRecord, as: SceneAmbientFlow
  alias Storyarn.Projects.Persistence.SceneConnectionRecord, as: SceneConnection
  alias Storyarn.Projects.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Persistence.UserRecord, as: User
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.ProjectMembership
  alias Storyarn.References
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.References.RichTextMentions
  alias Storyarn.References.VariableReferenceTracker
  alias Storyarn.Repo
  alias Storyarn.Versioning.AssetMaterializationCache
  alias Storyarn.Versioning.AssetMaterializationScope
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.Builders.FlowBuilder
  alias Storyarn.Versioning.Builders.SceneBuilder
  alias Storyarn.Versioning.Builders.SheetBuilder
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Versioning.MaterializationHelpers
  alias Storyarn.Versioning.ReferencedTombstones
  alias Storyarn.Versioning.SnapshotObjectFormat

  require Logger

  @recovery_id_map_keys [
    :sheet,
    :block,
    :avatar,
    :flow,
    :node,
    :flow_connection,
    :scene,
    :scene_connection,
    :pin,
    :zone
  ]
  @snapshot_format_version 2
  @localization_actor_fields ~w(translated_by_id reviewed_by_id)
  @localization_actor_mode_key :project_recovery_localization_actor_mode
  @preserved_localization_actor_ids_key :preserved_localization_actor_ids
  @materialization_mode_key :materialization_mode
  @snapshot_import_asset_catalog_fun_key :snapshot_import_asset_catalog_fun
  @snapshot_import_asset_id_map_key :snapshot_import_asset_id_map
  @snapshot_import_project_id_key :snapshot_import_project_id
  @snapshot_import_tombstone_nodes_fun_key :snapshot_import_tombstone_nodes_fun
  @snapshot_import_external_tombstone_node_map_key :snapshot_import_external_tombstone_node_map
  @snapshot_count_collections %{
    "sheets" => ["sheets"],
    "flows" => ["flows"],
    "scenes" => ["scenes"],
    "languages" => ["localization", "languages"],
    "localized_texts" => ["localization", "texts"],
    "glossary_entries" => ["localization", "glossary"]
  }

  @doc """
  Materializes a portable template snapshot as a new project.

  Creates fresh entities with new IDs and remaps all internal cross-references.
  Referenced assets are always copied and failures are strict by default. The
  caller must authorize the template operation before invoking this function.
  Localization translator and reviewer identities are discarded because a
  portable template may be installed into a different workspace.

  ## Options
  - `:name` - Name for the materialized project (default: "Recovered Project")
  - `:asset_copy_tracker` - External compensation tracker when the caller owns
    a surrounding transaction
  - `:asset_source_keys` - Verified portable-bundle object keys
  """
  @spec materialize_template(integer(), map(), integer(), keyword()) ::
          {:ok, Project.t()} | {:error, term()}
  def materialize_template(workspace_id, snapshot_data, user_id, opts \\ []) do
    opts = Keyword.put(opts, @localization_actor_mode_key, :discard)
    recover_project_with_asset_scope(snapshot_data, workspace_id, user_id, opts)
  end

  @doc """
  Materializes an exact project snapshot as a new project.

  This is the recovery entry point for a verified standalone snapshot archive.
  It creates fresh database identities while preserving the captured project
  settings and content. The caller must reserve a fresh project ID, stage the
  complete verified asset catalog before the final transaction and provide
  `:snapshot_import_asset_catalog_fun`; that callback adopts the staged catalog
  inside the transaction and returns the historical-to-new asset ID map.
  """
  @spec materialize_snapshot_import(integer(), map(), integer(), keyword()) ::
          {:ok, Project.t()} | {:error, term()}
  def materialize_snapshot_import(workspace_id, snapshot_data, user_id, opts \\ []) do
    name = get_in(snapshot_data, ["project", "name"])

    with :ok <- validate_snapshot_import(snapshot_data),
         :ok <- validate_snapshot_import_asset_catalog_fun(opts),
         :ok <- validate_snapshot_import_project_id(opts) do
      opts =
        opts
        |> Keyword.put(:materialization_mode, :exact)
        |> Keyword.put(:name, name)

      materialize_template(workspace_id, snapshot_data, user_id, opts)
    end
  end

  @doc false
  @spec validate_snapshot_import(map()) :: :ok | {:error, term()}
  def validate_snapshot_import(snapshot_data) when is_map(snapshot_data) do
    with :ok <-
           ReferencedTombstones.validate_complete(
             snapshot_data,
             SnapshotObjectFormat.hard_limits().max_objects
           ) do
      validate_materialization_snapshot(snapshot_data, :exact)
    end
  end

  def validate_snapshot_import(_snapshot_data), do: {:error, :invalid_project_snapshot_envelope}

  @doc false
  @spec validate_materialization_snapshot(map()) :: :ok | {:error, term()}
  def validate_materialization_snapshot(snapshot_data) when is_map(snapshot_data) do
    with :ok <- validate_project_snapshot_envelope(snapshot_data),
         :ok <- validate_portable_entity_snapshots(snapshot_data),
         :ok <- validate_active_materialization_localization(snapshot_data),
         :ok <- validate_recovery_localization_actor_references(snapshot_data),
         :ok <- SnapshotObjectFormat.validate_project(snapshot_data),
         {:ok, id_maps} <- preflight_identity_maps(snapshot_data),
         :ok <- validate_preflight_tree(snapshot_data, id_maps),
         :ok <- validate_preflight_references(snapshot_data, id_maps),
         {:ok, _variable_plan} <-
           VariableReferenceTracker.prepare_portable_project_snapshot(snapshot_data) do
      validate_materialization_localization(snapshot_data, id_maps)
    end
  end

  def validate_materialization_snapshot(_snapshot_data), do: {:error, :invalid_project_snapshot_envelope}

  defp validate_materialization_snapshot(snapshot_data, :portable), do: validate_materialization_snapshot(snapshot_data)

  defp validate_materialization_snapshot(snapshot_data, :exact) do
    with :ok <- validate_project_snapshot_envelope(snapshot_data),
         :ok <- SnapshotObjectFormat.validate_project(snapshot_data),
         {:ok, _id_maps} <- preflight_identity_maps(snapshot_data) do
      :ok
    end
  end

  @doc false
  @spec lock_materializable_localization_actors(map(), keyword()) ::
          {:ok, MapSet.t(pos_integer())} | {:error, term()}
  def lock_materializable_localization_actors(snapshot_data, opts \\ [])

  def lock_materializable_localization_actors(snapshot_data, opts) when is_map(snapshot_data) and is_list(opts) do
    with :ok <- validate_materialization_transaction(),
         true <- Keyword.keyword?(opts),
         {:ok, texts} <- localization_actor_rows(snapshot_data),
         :ok <- validate_localization_actor_shapes(texts),
         {:ok, required_actor_ids} <- localization_actor_lock_ids(opts, :required_actor_ids),
         {:ok, additional_actor_ids} <- localization_actor_lock_ids(opts, :additional_actor_ids) do
      actor_ids =
        texts
        |> localization_actor_ids()
        |> Kernel.++(required_actor_ids)
        |> Kernel.++(additional_actor_ids)
        |> Enum.uniq()
        |> Enum.sort()

      lock_existing_localization_actors(actor_ids)
    else
      false -> {:error, :invalid_project_materialization_localization_actor_prelock_options}
      {:error, _reason} = error -> error
    end
  end

  def lock_materializable_localization_actors(_snapshot_data, _opts),
    do: {:error, :invalid_project_materialization_localization_actor_prelock_options}

  defp validate_portable_entity_snapshots(snapshot_data) do
    Enum.reduce_while(
      [
        {:sheet, snapshot_data["sheets"], &SheetBuilder.validate_portable_snapshot/1},
        {:flow, snapshot_data["flows"], &FlowBuilder.validate_portable_snapshot/1},
        {:scene, snapshot_data["scenes"], &SceneBuilder.validate_portable_snapshot/1}
      ],
      :ok,
      fn {entity_type, entries, validator}, :ok ->
        case validate_portable_entity_collection(entries, entity_type, validator) do
          :ok -> {:cont, :ok}
          {:error, _reason} = error -> {:halt, error}
        end
      end
    )
  end

  defp validate_portable_entity_collection(entries, entity_type, validator) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case validate_portable_entity_entry(entry, entity_type, validator) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_portable_entity_entry(entry, entity_type, validator) do
    entry_id = entry["id"]
    snapshot = entry["snapshot"]

    if snapshot["original_id"] == entry_id,
      do: validate_portable_entity_payload(snapshot, entity_type, entry_id, validator),
      else: {:error, {:project_snapshot_root_id_mismatch, entity_type, entry_id, snapshot["original_id"]}}
  end

  defp validate_portable_entity_payload(snapshot, entity_type, entry_id, validator) do
    case validator.(snapshot) do
      :ok -> :ok
      {:error, reason} -> {:error, {:invalid_project_snapshot_entity, entity_type, entry_id, reason}}
    end
  end

  @doc """
  Materializes a canonical project snapshot into an existing project.

  This function only creates the archived project graph. It does not create or
  update the project, create memberships, remove current roots, or perform
  storage I/O. The caller must authorize the operation, open the final restore
  transaction, lock the active project row, and materialize every archived
  asset before invoking it. The caller also owns rollback when this function
  returns an error.

  `source_id_map` is the exact `%{historical_asset_id => destination_asset_id}`
  mapping returned by the snapshot asset materializer. Its keys must cover the
  snapshot's `asset_catalog_refs` exactly.

  ## Options

  - `:localization_scope` - required to be `:active`; exact restore never
    materializes archived localization rows
  - `:asset_materialization_cache` - optional caller-owned cache shared with
    the asset staging phase
  - `:preserved_localization_actor_ids` - required caller-resolved `MapSet` of
    actor IDs protected before the restore operation row is locked

  Exact in-situ restore preserves captured localization translator and reviewer
  identities that still exist. Identities deleted after capture are normalized
  to `nil`, matching the live foreign-key deletion contract.
  """
  @spec materialize_into_project(Project.t(), map(), integer(), map(), keyword()) ::
          {:ok, %{project: Project.t(), id_maps: map()}} | {:error, term()}
  def materialize_into_project(project, snapshot_data, user_id, source_id_map, opts \\ []) do
    opts = Keyword.put(opts, @localization_actor_mode_key, :preserve)

    with :ok <- validate_materialization_target(project),
         :ok <- validate_materialization_actor(user_id),
         :ok <- validate_materialization_options(opts),
         :ok <- validate_materialization_transaction(),
         :ok <- validate_materialization_snapshot(snapshot_data, materialization_mode(opts)),
         {:ok, source_id_map} <- source_id_map(snapshot_data, source_id_map),
         {:ok, cache, owns_cache?} <- materialization_cache(opts) do
      try do
        materialize_existing_project(
          project,
          snapshot_data,
          user_id,
          source_id_map,
          cache,
          opts
        )
      after
        AssetMaterializationCache.discard_if_owned(cache, owns_cache?)
      end
    end
  end

  defp validate_materialization_target(%Project{id: project_id, deleted_at: nil})
       when is_integer(project_id) and project_id > 0, do: :ok

  defp validate_materialization_target(_project), do: {:error, :invalid_project_materialization_target}

  defp validate_materialization_actor(user_id) when is_integer(user_id) and user_id > 0, do: :ok
  defp validate_materialization_actor(_user_id), do: {:error, :invalid_project_materialization_actor}

  defp validate_materialization_options(opts) when is_list(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, :invalid_project_materialization_options}

      Keyword.get(opts, :localization_scope) != :active ->
        {:error, :project_materialization_requires_active_localization}

      materialization_mode(opts) not in [:portable, :exact] ->
        {:error, :invalid_project_materialization_mode}

      true ->
        :ok
    end
  end

  defp validate_materialization_options(_opts), do: {:error, :invalid_project_materialization_options}

  defp materialization_mode(opts), do: Keyword.get(opts, @materialization_mode_key, :portable)

  defp validate_materialization_transaction do
    if Repo.in_transaction?(), do: :ok, else: {:error, :project_materialization_requires_transaction}
  end

  defp materialize_existing_project(project, snapshot_data, user_id, source_id_map, cache, opts) do
    with {:ok, variable_plan} <- prepare_materialization_variable_plan(snapshot_data, opts),
         :ok <-
           AssetHashResolver.preload_materialized_assets(
             snapshot_data,
             source_id_map,
             project.id,
             cache
           ) do
      recovery_opts =
        opts
        |> Keyword.take([
          :asset_materialization_cache,
          @localization_actor_mode_key,
          @preserved_localization_actor_ids_key,
          @materialization_mode_key
        ])
        |> Keyword.put(:asset_materialization_cache, cache)
        |> Keyword.put(:pre_materialized_assets, true)
        |> maybe_put_portable_variable_plan(variable_plan)

      materialize_project_graph_with_receipt(
        project,
        snapshot_data,
        user_id,
        recovery_opts
      )
    end
  rescue
    error in AssetCopyError ->
      {:error, {:asset_materialization_failed, error.asset_id, error.reason}}
  end

  defp prepare_materialization_variable_plan(snapshot_data, opts) when is_list(opts) do
    if MaterializationHelpers.exact_materialization?(opts) do
      VariableReferenceTracker.prepare_exact_project_snapshot(snapshot_data)
    else
      VariableReferenceTracker.prepare_portable_project_snapshot(snapshot_data)
    end
  end

  defp maybe_put_portable_variable_plan(opts, nil), do: opts

  defp maybe_put_portable_variable_plan(opts, variable_plan),
    do: Keyword.put(opts, :portable_variable_plan, variable_plan)

  defp source_id_map(snapshot_data, source_id_map) do
    case Map.fetch(snapshot_data, "asset_catalog_refs") do
      {:ok, source_refs} ->
        with :ok <- validate_source_id_map(source_id_map),
             :ok <- validate_materialized_asset_coverage(source_refs, source_id_map) do
          {:ok, source_id_map}
        end

      :error ->
        {:error, :missing_asset_catalog_refs}
    end
  end

  defp validate_source_id_map(source_id_map) when is_map(source_id_map) do
    if Enum.all?(source_id_map, fn {source_id, destination_id} ->
         is_integer(source_id) and source_id > 0 and is_integer(destination_id) and destination_id > 0
       end) and MapSet.size(MapSet.new(Map.values(source_id_map))) == map_size(source_id_map),
       do: :ok,
       else: {:error, :invalid_snapshot_asset_source_id_map}
  end

  defp validate_source_id_map(_source_id_map), do: {:error, :invalid_snapshot_asset_source_id_map}

  defp validate_materialized_asset_coverage(source_refs, destination_ids) do
    expected = source_refs |> Map.keys() |> MapSet.new(&String.to_integer/1)
    actual = destination_ids |> Map.keys() |> MapSet.new()

    if expected == actual do
      :ok
    else
      {:error,
       {:materialized_asset_mapping_mismatch,
        %{
          missing: expected |> MapSet.difference(actual) |> Enum.sort(),
          unexpected: actual |> MapSet.difference(expected) |> Enum.sort()
        }}}
    end
  end

  defp materialization_cache(opts) do
    case Keyword.fetch(opts, :asset_materialization_cache) do
      :error -> {:ok, AssetMaterializationCache.new(), true}
      {:ok, cache} when is_reference(cache) -> {:ok, cache, false}
      {:ok, _cache} -> {:error, :invalid_asset_materialization_cache}
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
        Billing.with_storage_accounting_lock(
          workspace_id,
          fn _workspace ->
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

  defp preflight_identity_maps(snapshot_data) do
    with {:ok, sheet_ids} <- preflight_collection_ids(snapshot_data["sheets"]),
         {:ok, block_ids} <- preflight_nested_ids(snapshot_data["sheets"], "blocks"),
         {:ok, avatar_ids} <- preflight_nested_ids(snapshot_data["sheets"], "avatars"),
         {:ok, flow_ids} <- preflight_collection_ids(snapshot_data["flows"]),
         {:ok, node_ids} <- preflight_nested_ids(snapshot_data["flows"], "nodes"),
         {:ok, flow_connection_ids} <-
           preflight_nested_ids(snapshot_data["flows"], "connections"),
         {:ok, scene_ids} <- preflight_collection_ids(snapshot_data["scenes"]),
         {:ok, scene_connection_ids} <-
           preflight_nested_ids(snapshot_data["scenes"], "connections"),
         {:ok, pin_ids} <- preflight_scene_child_ids(snapshot_data["scenes"], "pins"),
         {:ok, zone_ids} <- preflight_scene_child_ids(snapshot_data["scenes"], "zones") do
      {:ok,
       %{
         sheet: identity_map(sheet_ids),
         block: identity_map(block_ids),
         avatar: identity_map(avatar_ids),
         flow: identity_map(flow_ids),
         node: identity_map(node_ids),
         flow_connection: identity_map(flow_connection_ids),
         scene: identity_map(scene_ids),
         scene_connection: identity_map(scene_connection_ids),
         pin: identity_map(pin_ids),
         zone: identity_map(zone_ids)
       }}
    end
  end

  defp preflight_collection_ids(entries) when is_list(entries) do
    preflight_ids(entries)
  end

  defp preflight_collection_ids(_entries), do: {:error, :invalid_project_snapshot_envelope}

  defp preflight_nested_ids(entries, collection_key) when is_list(entries) do
    with {:ok, nested_entries} <- collect_preflight_nested_entries(entries, collection_key) do
      preflight_ids(nested_entries, "original_id")
    end
  end

  defp preflight_scene_child_ids(entries, child_key) when is_list(entries) do
    with {:ok, children} <- collect_preflight_scene_children(entries, child_key) do
      preflight_ids(children, "original_id")
    end
  end

  defp preflight_scene_child_ids(_entries, _child_key), do: {:error, :invalid_project_snapshot_entity_identity}

  defp collect_preflight_scene_children(entries, child_key) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, collected} ->
      snapshot = entry["snapshot"]

      with %{} <- snapshot,
           layers when is_list(layers) <- snapshot["layers"],
           orphan_children when is_list(orphan_children) <- snapshot["orphan_#{child_key}"],
           {:ok, layered_children} <- collect_preflight_layer_children(layers, child_key) do
        {:cont, {:ok, layered_children ++ orphan_children ++ collected}}
      else
        _invalid -> {:halt, {:error, :invalid_project_snapshot_entity_identity}}
      end
    end)
  end

  defp collect_preflight_layer_children(layers, child_key) do
    Enum.reduce_while(layers, {:ok, []}, fn layer, {:ok, collected} ->
      case layer[child_key] do
        children when is_list(children) -> {:cont, {:ok, children ++ collected}}
        _invalid -> {:halt, {:error, :invalid_project_snapshot_entity_identity}}
      end
    end)
  end

  defp collect_preflight_nested_entries(entries, collection_key) do
    Enum.reduce_while(entries, {:ok, []}, fn entry, {:ok, collected} ->
      case get_in(entry, ["snapshot", collection_key]) do
        nested when is_list(nested) -> {:cont, {:ok, nested ++ collected}}
        _invalid -> {:halt, {:error, :invalid_project_snapshot_entity_identity}}
      end
    end)
  end

  defp preflight_ids(entries, key \\ "id") do
    ids =
      Enum.map(entries, fn
        entry when is_map(entry) -> entry[key]
        _invalid -> nil
      end)

    if Enum.all?(ids, &(is_integer(&1) and &1 > 0)) and length(ids) == MapSet.size(MapSet.new(ids)),
      do: {:ok, ids},
      else: {:error, :invalid_project_snapshot_entity_identity}
  end

  defp identity_map(ids), do: Map.new(ids, &{&1, &1})

  defp validate_preflight_tree(snapshot_data, id_maps) do
    case snapshot_data["tree"] do
      %{} = tree ->
        with :ok <- validate_preflight_tree_collection(tree["sheets"], id_maps.sheet, :sheet),
             :ok <- validate_preflight_tree_collection(tree["flows"], id_maps.flow, :flow) do
          validate_preflight_tree_collection(tree["scenes"], id_maps.scene, :scene)
        end

      _invalid ->
        {:error, :missing_or_invalid_project_snapshot_tree}
    end
  end

  defp validate_preflight_tree_collection(entries, id_map, entity_type) when is_list(entries) do
    with :ok <- validate_tree_entries(entries, id_map, entity_type) do
      validate_tree_cycles(entries, entity_type)
    end
  end

  defp validate_preflight_tree_collection(_entries, _id_map, entity_type),
    do: {:error, {:invalid_project_snapshot_tree_collection, entity_type}}

  defp validate_preflight_references(snapshot_data, id_maps) do
    with {:ok, asset_ids} <- preflight_asset_ids(snapshot_data),
         {:ok, block_owners} <- preflight_child_owners(snapshot_data["sheets"], "blocks"),
         {:ok, avatar_owners} <- preflight_child_owners(snapshot_data["sheets"], "avatars"),
         {:ok, node_owners} <- preflight_child_owners(snapshot_data["flows"], "nodes"),
         :ok <- validate_preflight_reference_scans(snapshot_data, id_maps, asset_ids, avatar_owners),
         :ok <- validate_preflight_sheet_inheritance(snapshot_data, id_maps.block, block_owners),
         :ok <- validate_preflight_flow_cycles(snapshot_data),
         :ok <- validate_preflight_dynamic_exits(snapshot_data, node_owners) do
      validate_preflight_global_root_contracts(snapshot_data)
    end
  end

  defp preflight_asset_ids(%{"asset_catalog_refs" => source_refs}) when is_map(source_refs) do
    Enum.reduce_while(Map.keys(source_refs), {:ok, MapSet.new()}, fn source_ref, {:ok, ids} ->
      case Integer.parse(source_ref) do
        {id, ""} when id > 0 -> {:cont, {:ok, MapSet.put(ids, id)}}
        _invalid -> {:halt, {:error, :invalid_asset_source_refs}}
      end
    end)
  end

  defp preflight_asset_ids(_snapshot_data), do: {:error, :missing_asset_catalog_refs}

  defp preflight_child_owners(entries, collection_key) when is_list(entries) do
    Enum.reduce_while(entries, {:ok, %{}}, fn entry, {:ok, owners} ->
      put_preflight_entry_child_owners(entry, collection_key, owners)
    end)
  end

  defp preflight_child_owners(_entries, _collection_key), do: {:error, :invalid_project_snapshot_entity_identity}

  defp put_preflight_entry_child_owners(entry, collection_key, owners) do
    case get_in(entry, ["snapshot", collection_key]) do
      children when is_list(children) ->
        continue_preflight_child_owners(children, entry["id"], owners)

      _invalid ->
        {:halt, {:error, :invalid_project_snapshot_entity_identity}}
    end
  end

  defp continue_preflight_child_owners(children, owner_id, owners) do
    case put_preflight_child_owners(children, owner_id, owners) do
      {:ok, owners} -> {:cont, {:ok, owners}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp put_preflight_child_owners(children, owner_id, owners) do
    Enum.reduce_while(children, {:ok, owners}, fn child, {:ok, acc} ->
      child_id = child["original_id"]

      if is_integer(child_id) and child_id > 0 and not Map.has_key?(acc, child_id),
        do: {:cont, {:ok, Map.put(acc, child_id, owner_id)}},
        else: {:halt, {:error, :invalid_project_snapshot_entity_identity}}
    end)
  end

  defp validate_preflight_reference_scans(snapshot_data, id_maps, asset_ids, avatar_owners) do
    scanners = [
      {:sheet, snapshot_data["sheets"], &SheetBuilder.scan_references/1},
      {:flow, snapshot_data["flows"], &FlowBuilder.scan_references/1},
      {:scene, snapshot_data["scenes"], &SceneBuilder.scan_references/1}
    ]

    Enum.reduce_while(scanners, :ok, fn {entity_type, entries, scanner}, :ok ->
      case validate_preflight_entity_references(
             entity_type,
             entries,
             scanner,
             id_maps,
             asset_ids,
             avatar_owners
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_preflight_entity_references(entity_type, entries, scanner, id_maps, asset_ids, avatar_owners) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      references = scanner.(entry["snapshot"])

      case validate_preflight_entry_references(
             references,
             entity_type,
             entry["id"],
             id_maps,
             asset_ids,
             avatar_owners
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_preflight_entry_references(references, entity_type, entry_id, id_maps, asset_ids, avatar_owners) do
    Enum.reduce_while(references, :ok, fn reference, :ok ->
      case validate_preflight_reference(reference, id_maps, asset_ids, avatar_owners) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt, {:error, {:missing_project_snapshot_reference, {entity_type, entry_id, reference.context}, reason}}}
      end
    end)
  end

  defp validate_preflight_reference(%{type: :asset, id: id}, _id_maps, asset_ids, _avatar_owners) do
    if MapSet.member?(asset_ids, normalize_recovery_id(id)), do: :ok, else: {:error, id}
  end

  defp validate_preflight_reference(%{type: :avatar, id: id} = reference, id_maps, _asset_ids, avatar_owners) do
    avatar_id = normalize_recovery_id(id)
    speaker_id = normalize_recovery_id(reference[:speaker_sheet_id])

    cond do
      is_nil(avatar_id) or not Map.has_key?(id_maps.avatar, avatar_id) -> {:error, id}
      is_nil(speaker_id) -> :ok
      Map.get(avatar_owners, avatar_id) == speaker_id -> :ok
      true -> {:error, {:avatar_speaker_mismatch, avatar_id, Map.get(avatar_owners, avatar_id), speaker_id}}
    end
  end

  defp validate_preflight_reference(%{type: type, id: id}, id_maps, _asset_ids, _avatar_owners)
       when type in [:sheet, :flow, :scene, :block] do
    normalized_id = normalize_recovery_id(id)

    if Map.has_key?(Map.fetch!(id_maps, type), normalized_id),
      do: :ok,
      else: {:error, id}
  end

  defp validate_preflight_reference(%{type: type, id: id}, _id_maps, _asset_ids, _avatar_owners),
    do: {:error, {:unsupported_reference, type, id}}

  defp validate_preflight_sheet_inheritance(snapshot_data, block_id_map, _block_owners) do
    blocks = Enum.flat_map(snapshot_data["sheets"], &get_in(&1, ["snapshot", "blocks"]))

    parents = Map.new(blocks, &{&1["original_id"], &1["inherited_from_block_id"]})

    with :ok <- validate_preflight_inheritance_parents(parents, block_id_map) do
      validate_preflight_parent_cycles(parents, :block)
    end
  end

  defp validate_preflight_inheritance_parents(parents, block_id_map) do
    case Enum.find(parents, fn {_block_id, parent_id} ->
           not is_nil(parent_id) and not Map.has_key?(block_id_map, parent_id)
         end) do
      nil -> :ok
      {block_id, parent_id} -> {:error, {:invalid_project_snapshot_inheritance, block_id, parent_id}}
    end
  end

  defp validate_preflight_flow_cycles(snapshot_data) do
    parents =
      Map.new(snapshot_data["flows"], fn entry ->
        targets =
          entry["snapshot"]["nodes"]
          |> Enum.flat_map(&preflight_flow_reference_targets/1)
          |> Enum.map(&normalize_recovery_id/1)
          |> Enum.reject(&is_nil/1)

        {entry["id"], targets}
      end)

    validate_preflight_graph_cycles(parents, :flow)
  end

  defp preflight_flow_reference_targets(%{"type" => "subflow", "data" => %{"referenced_flow_id" => target}}), do: [target]

  defp preflight_flow_reference_targets(%{
         "type" => "exit",
         "data" => %{"exit_mode" => "flow_reference", "referenced_flow_id" => target}
       }), do: [target]

  defp preflight_flow_reference_targets(_node), do: []

  defp validate_preflight_parent_cycles(parents, entity_type) do
    graph = Map.new(parents, fn {id, parent_id} -> {id, if(is_nil(parent_id), do: [], else: [parent_id])} end)
    validate_preflight_graph_cycles(graph, entity_type)
  end

  defp validate_preflight_graph_cycles(graph, entity_type) do
    indegrees =
      Enum.reduce(graph, Map.new(graph, fn {id, _targets} -> {id, 0} end), fn {_id, targets}, acc ->
        Enum.reduce(targets, acc, fn target, acc -> Map.update(acc, target, 1, &(&1 + 1)) end)
      end)

    queue =
      Enum.reduce(indegrees, :queue.new(), fn
        {id, 0}, queue -> :queue.in(id, queue)
        {_id, _indegree}, queue -> queue
      end)

    case drain_preflight_graph(queue, graph, indegrees, 0) do
      {_indegrees, count} when count == map_size(indegrees) ->
        :ok

      {remaining, _count} ->
        {id, _indegree} = Enum.find(remaining, fn {_id, indegree} -> indegree > 0 end)
        {:error, {:project_snapshot_reference_cycle, entity_type, id}}
    end
  end

  defp drain_preflight_graph(queue, graph, indegrees, count) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        {indegrees, count}

      {{:value, id}, queue} ->
        {queue, indegrees} =
          Enum.reduce(Map.get(graph, id, []), {queue, indegrees}, fn target, {queue, indegrees} ->
            indegrees = Map.update!(indegrees, target, &(&1 - 1))
            enqueue_preflight_target(queue, indegrees, target)
          end)

        drain_preflight_graph(queue, graph, indegrees, count + 1)
    end
  end

  defp enqueue_preflight_target(queue, indegrees, target) do
    if indegrees[target] == 0,
      do: {:queue.in(target, queue), indegrees},
      else: {queue, indegrees}
  end

  defp validate_preflight_dynamic_exits(snapshot_data, node_owners) do
    node_types =
      snapshot_data["flows"]
      |> Enum.flat_map(&get_in(&1, ["snapshot", "nodes"]))
      |> Map.new(&{&1["original_id"], &1["type"]})

    Enum.reduce_while(snapshot_data["flows"], :ok, fn entry, :ok ->
      nodes = entry["snapshot"]["nodes"]

      case validate_preflight_flow_dynamic_exits(
             entry["snapshot"]["connections"],
             nodes,
             node_types,
             node_owners
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp validate_preflight_flow_dynamic_exits(connections, nodes, node_types, node_owners) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      source = Enum.at(nodes, connection["source_node_index"])

      case preflight_dynamic_exit(connection, source, node_types, node_owners) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp preflight_dynamic_exit(
         %{"source_pin" => "exit_" <> id_text} = connection,
         %{"type" => "subflow", "data" => data},
         node_types,
         node_owners
       ) do
    with {exit_id, ""} when exit_id > 0 <- Integer.parse(id_text),
         referenced_flow_id when is_integer(referenced_flow_id) <-
           normalize_recovery_id(data["referenced_flow_id"]),
         "exit" <- Map.get(node_types, exit_id),
         ^referenced_flow_id <- Map.get(node_owners, exit_id) do
      :ok
    else
      _invalid ->
        {:error,
         {:dynamic_exit_pin_not_materializable, connection["original_id"], connection["source_pin"],
          :exit_not_in_referenced_flow_snapshot}}
    end
  end

  defp preflight_dynamic_exit(_connection, _source, _node_types, _node_owners), do: :ok

  defp validate_preflight_global_root_contracts(snapshot_data) do
    with :ok <- validate_preflight_unique_root_field(snapshot_data["sheets"], "shortcut", :sheet),
         :ok <- validate_preflight_unique_root_field(snapshot_data["flows"], "shortcut", :flow),
         :ok <- validate_preflight_unique_root_field(snapshot_data["scenes"], "shortcut", :scene),
         :ok <- validate_preflight_main_flow(snapshot_data["flows"]) do
      validate_preflight_dialogue_localization_ids(snapshot_data["flows"])
    end
  end

  defp validate_preflight_unique_root_field(entries, field, entity_type) do
    values = entries |> Enum.map(&get_in(&1, ["snapshot", field])) |> Enum.reject(&is_nil/1)

    if length(values) == MapSet.size(MapSet.new(values)),
      do: :ok,
      else: {:error, {:duplicate_project_snapshot_root_field, entity_type, field}}
  end

  defp validate_preflight_main_flow(flows) do
    count = Enum.count(flows, &(get_in(&1, ["snapshot", "is_main"]) == true))
    if count <= 1, do: :ok, else: {:error, {:invalid_project_snapshot_main_flow_count, count}}
  end

  defp validate_preflight_dialogue_localization_ids(flows) do
    ids =
      flows
      |> Enum.flat_map(&get_in(&1, ["snapshot", "nodes"]))
      |> Enum.flat_map(fn
        %{"type" => "dialogue", "data" => %{"localization_id" => id}} -> [id]
        _node -> []
      end)

    if length(ids) == MapSet.size(MapSet.new(ids)),
      do: :ok,
      else: {:error, :duplicate_project_snapshot_dialogue_localization_id}
  end

  defp validate_materialization_localization(snapshot_data, id_maps) do
    case snapshot_data["localization"] do
      localization when is_map(localization) ->
        validate_recovery_localization(
          Map.get(localization, "languages", []),
          Map.get(localization, "texts", []),
          Map.get(localization, "glossary", []),
          id_maps,
          snapshot_data
        )

      _invalid ->
        {:error, :invalid_project_snapshot_localization}
    end
  end

  defp validate_active_materialization_localization(snapshot_data) do
    with {:ok, languages, texts} <- active_materialization_localization(snapshot_data),
         :ok <-
           validate_active_localization_rows(
             languages,
             :archived_project_snapshot_language_not_materializable
           ) do
      validate_active_localization_rows(
        texts,
        :archived_project_snapshot_localized_text_not_materializable
      )
    end
  end

  defp active_materialization_localization(%{"localization" => %{"languages" => languages, "texts" => texts}})
       when is_list(languages) and is_list(texts), do: {:ok, languages, texts}

  defp active_materialization_localization(_snapshot_data),
    do: {:error, :invalid_project_snapshot_localization_collections}

  defp validate_active_localization_rows(rows, error) do
    if Enum.all?(rows, &active_localization_row?/1), do: :ok, else: {:error, error}
  end

  defp active_localization_row?(row) when is_map(row), do: is_nil(row["archived_at"])
  defp active_localization_row?(_row), do: false

  defp validate_recovery_localization_actor_references(snapshot_data) do
    with {:ok, texts} <- localization_actor_rows(snapshot_data),
         do: validate_localization_actor_shapes(texts)
  end

  defp validate_recovery_localization_actor_references(snapshot_data, opts) when is_list(opts) do
    case Keyword.get(opts, @localization_actor_mode_key) do
      :discard -> validate_recovery_localization_actor_references(snapshot_data)
      :preserve -> validate_recovery_localization_actor_references(snapshot_data)
      _invalid -> {:error, :invalid_project_recovery_localization_actor_mode}
    end
  end

  defp localization_actor_rows(%{"localization" => %{"texts" => texts}}) when is_list(texts) do
    if Enum.all?(texts, &is_map/1),
      do: {:ok, texts},
      else: {:error, :invalid_project_snapshot_localized_text}
  end

  defp localization_actor_rows(_snapshot_data), do: {:error, :invalid_project_snapshot_localization_collections}

  defp validate_localization_actor_shapes(texts) do
    case invalid_localization_actor_shape(texts) do
      nil -> :ok
      {field, id} -> {:error, {:localization_reference_not_materializable, field, id}}
    end
  end

  defp invalid_localization_actor_shape(texts) do
    texts
    |> localization_actor_references()
    |> Enum.find(fn
      {_field, nil} -> false
      {_field, id} when is_integer(id) and id > 0 -> false
      {_field, _id} -> true
    end)
  end

  defp localization_actor_ids(texts) do
    texts
    |> localization_actor_references()
    |> Enum.map(&elem(&1, 1))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp localization_actor_lock_ids(opts, key) do
    case Keyword.get(opts, key, []) do
      actor_ids when is_list(actor_ids) ->
        if Enum.all?(actor_ids, &(is_integer(&1) and &1 > 0)),
          do: {:ok, actor_ids},
          else: {:error, :invalid_project_materialization_localization_actor_prelock_options}

      _invalid ->
        {:error, :invalid_project_materialization_localization_actor_prelock_options}
    end
  end

  defp localization_actor_references(texts) do
    Enum.flat_map(texts, fn text ->
      Enum.map(@localization_actor_fields, &{&1, text[&1]})
    end)
  end

  defp do_recover(workspace_id, snapshot_data, user_id, name, opts) do
    with {:ok, project} <- create_project(workspace_id, user_id, name, snapshot_data, opts),
         {:ok, _membership} <- create_owner_membership(project, user_id),
         {:ok, opts} <- materialize_snapshot_import_asset_catalog(project, snapshot_data, user_id, opts) do
      materialize_project_graph(project, snapshot_data, user_id, opts)
    end
  end

  defp validate_snapshot_import_asset_catalog_fun(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         {:ok, _fun} <- snapshot_import_asset_catalog_fun(opts) do
      :ok
    else
      _missing_or_invalid -> {:error, :snapshot_import_asset_catalog_materializer_required}
    end
  end

  defp validate_snapshot_import_asset_catalog_fun(_opts),
    do: {:error, :snapshot_import_asset_catalog_materializer_required}

  defp validate_snapshot_import_project_id(opts) when is_list(opts) do
    case Keyword.get(opts, @snapshot_import_project_id_key) do
      project_id when is_integer(project_id) and project_id > 0 -> :ok
      _missing_or_invalid -> {:error, :snapshot_import_project_id_required}
    end
  end

  defp validate_snapshot_import_project_id(_opts), do: {:error, :snapshot_import_project_id_required}

  defp materialize_snapshot_import_asset_catalog(project, snapshot_data, user_id, opts) do
    if MaterializationHelpers.exact_materialization?(opts) do
      with {:ok, fun} <- snapshot_import_asset_catalog_fun(opts),
           {:ok, cache} <- snapshot_import_asset_materialization_cache(opts),
           {:ok, materialized_asset_ids} <- fun.(project, snapshot_data, user_id, opts),
           {:ok, materialized_asset_ids} <- source_id_map(snapshot_data, materialized_asset_ids),
           :ok <-
             AssetHashResolver.preload_materialized_assets(
               snapshot_data,
               materialized_asset_ids,
               project.id,
               cache
             ) do
        {:ok,
         opts
         |> Keyword.put(:pre_materialized_assets, true)
         |> Keyword.put(@snapshot_import_asset_id_map_key, materialized_asset_ids)}
      else
        {:error, _reason} = error -> error
      end
    else
      {:ok, opts}
    end
  end

  defp snapshot_import_asset_catalog_fun(opts) do
    case Keyword.get(opts, @snapshot_import_asset_catalog_fun_key) do
      fun when is_function(fun, 4) -> {:ok, fun}
      _missing_or_invalid -> {:error, :snapshot_import_asset_catalog_materializer_required}
    end
  end

  defp snapshot_import_asset_materialization_cache(opts) do
    case Keyword.get(opts, :asset_materialization_cache) do
      cache when is_reference(cache) -> {:ok, cache}
      _missing_or_invalid -> {:error, :snapshot_import_asset_materialization_cache_required}
    end
  end

  defp materialize_project_graph(project, snapshot_data, user_id, opts) do
    with {:ok, %{project: project}} <-
           materialize_project_graph_with_receipt(project, snapshot_data, user_id, opts) do
      {:ok, project}
    end
  end

  defp materialize_project_graph_with_receipt(project, snapshot_data, user_id, opts) do
    now = TimeHelpers.now()

    with :ok <- validate_recovery_localization_actor_references(snapshot_data, opts),
         {:ok, opts, preserved_actor_ids} <-
           prepare_recovery_localization_actors(snapshot_data, opts),
         {:ok, root_tombstone_maps} <-
           materialize_snapshot_import_root_tombstones(project.id, snapshot_data, opts, now),
         {:ok, detached_node_tombstone_maps} <-
           materialize_detached_snapshot_import_node_tombstones(
             snapshot_data,
             root_tombstone_maps.flow,
             opts,
             now
           ),
         {:ok, {sheet_maps, snapshot_data}} <-
           recover_sheets_with_portable_namespaces(project.id, snapshot_data, user_id, opts),
         {:ok, block_tombstone_maps} <-
           materialize_snapshot_import_block_tombstones(
             snapshot_data,
             Map.merge(root_tombstone_maps.sheet, sheet_maps.sheet),
             opts,
             now
           ),
         {:ok, scene_maps} <-
           recover_scenes(project.id, snapshot_data, sheet_maps.sheet, user_id, opts),
         {:ok, flow_maps} <-
           recover_flows(
             project.id,
             snapshot_data,
             sheet_maps.sheet,
             scene_maps.scene,
             sheet_maps.avatar,
             Map.put(root_tombstone_maps, :node, detached_node_tombstone_maps.node),
             user_id,
             opts
           ) do
      active_id_maps = merge_recovery_id_maps([sheet_maps, scene_maps, flow_maps])

      tombstone_id_maps =
        [
          root_tombstone_maps,
          block_tombstone_maps,
          detached_node_tombstone_maps
        ]
        |> merge_recovery_id_maps()
        |> Map.put(
          :node,
          Map.merge(
            detached_node_tombstone_maps.node,
            Map.get(flow_maps, :referenced_tombstone_node, %{})
          )
        )

      with :ok <- validate_materialized_id_map_coverage(snapshot_data, active_id_maps),
           {:ok, id_maps} <- merge_materialized_id_maps(active_id_maps, tombstone_id_maps),
           :ok <- remap_snapshot_import_tombstone_payloads(snapshot_data, id_maps, opts),
           :ok <- remap_sheet_refs(project.id, id_maps, snapshot_data, opts),
           :ok <- maybe_validate_recovered_sheet_inheritance(project.id, opts),
           :ok <- remap_flow_refs(project.id, id_maps, snapshot_data, opts),
           :ok <- maybe_validate_recovered_flow_cycles(id_maps.flow, opts),
           :ok <- remap_scene_refs(project.id, id_maps, snapshot_data, opts),
           :ok <- restore_tree_hierarchy(project.id, snapshot_data, id_maps, opts),
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
        {:ok,
         %{
           project: project,
           id_maps: id_maps,
           preserved_localization_actor_ids: preserved_actor_ids
         }}
      end
    end
  end

  defp prepare_recovery_localization_actors(_snapshot_data, opts) do
    case Keyword.get(opts, @localization_actor_mode_key) do
      :discard ->
        preserved_actor_ids = MapSet.new()

        {:ok, Keyword.put(opts, @preserved_localization_actor_ids_key, preserved_actor_ids), preserved_actor_ids}

      :preserve ->
        opts
        |> Keyword.fetch(@preserved_localization_actor_ids_key)
        |> prepare_preserved_localization_actors(opts)
    end
  end

  defp prepare_preserved_localization_actors({:ok, %MapSet{} = actor_ids}, opts) do
    if Enum.all?(actor_ids, &(is_integer(&1) and &1 > 0)),
      do: {:ok, opts, actor_ids},
      else: {:error, :invalid_project_materialization_localization_actor_prelock}
  end

  defp prepare_preserved_localization_actors({:ok, _invalid}, _opts),
    do: {:error, :invalid_project_materialization_localization_actor_prelock}

  defp prepare_preserved_localization_actors(:error, _opts),
    do: {:error, :project_materialization_localization_actor_prelock_required}

  defp lock_existing_localization_actors(actor_ids) do
    if actor_ids == [] do
      {:ok, MapSet.new()}
    else
      locked_actor_ids =
        User
        |> where([user], user.id in ^actor_ids)
        |> order_by([user], asc: user.id)
        |> lock("FOR KEY SHARE SKIP LOCKED")
        |> select([user], user.id)
        |> Repo.all()
        |> MapSet.new()

      busy_actor_ids =
        actor_ids
        |> Enum.reject(&MapSet.member?(locked_actor_ids, &1))
        |> existing_localization_actor_ids()

      if busy_actor_ids == [],
        do: {:ok, locked_actor_ids},
        else: {:error, {:project_materialization_localization_actors_busy, busy_actor_ids}}
    end
  end

  defp existing_localization_actor_ids([]), do: []

  defp existing_localization_actor_ids(actor_ids) do
    User
    |> where([user], user.id in ^actor_ids)
    |> order_by([user], asc: user.id)
    |> select([user], user.id)
    |> Repo.all()
  end

  defp actor_id_if_present(actor_id, preserved_actor_ids) do
    if MapSet.member?(preserved_actor_ids, actor_id), do: actor_id
  end

  defp recover_sheets_with_portable_namespaces(project_id, snapshot_data, user_id, opts) do
    with {:ok, attempt_limit} <- portable_namespace_attempt_limit(opts) do
      recover_sheets_with_portable_namespaces(
        project_id,
        snapshot_data,
        user_id,
        opts,
        attempt_limit
      )
    end
  end

  defp recover_sheets_with_portable_namespaces(project_id, snapshot_data, user_id, opts, 1) do
    recover_and_rewrite_sheets(project_id, snapshot_data, user_id, opts)
  end

  defp recover_sheets_with_portable_namespaces(project_id, snapshot_data, user_id, opts, attempts_left)
       when attempts_left > 1 do
    result =
      with_sheet_materialization_savepoint(fn ->
        recover_and_rewrite_sheets(project_id, snapshot_data, user_id, opts)
      end)

    case result do
      {:error, {:ambiguous_destination_variable_namespace, _namespace, _left, _right}} ->
        recover_sheets_with_portable_namespaces(
          project_id,
          snapshot_data,
          user_id,
          opts,
          attempts_left - 1
        )

      result ->
        result
    end
  end

  @sheet_materialization_savepoint "project_restore_sheet_materialization"
  @begin_sheet_materialization_savepoint "SAVEPOINT " <> @sheet_materialization_savepoint
  @rollback_sheet_materialization_savepoint "ROLLBACK TO SAVEPOINT " <>
                                              @sheet_materialization_savepoint
  @release_sheet_materialization_savepoint "RELEASE SAVEPOINT " <>
                                             @sheet_materialization_savepoint

  defp with_sheet_materialization_savepoint(fun) when is_function(fun, 0) do
    Repo.query!(@begin_sheet_materialization_savepoint)

    finish_sheet_materialization_savepoint(fun.())
  end

  defp finish_sheet_materialization_savepoint({:ok, _result} = result) do
    Repo.query!(@release_sheet_materialization_savepoint)
    result
  end

  defp finish_sheet_materialization_savepoint(
         {:error, {:ambiguous_destination_variable_namespace, _namespace, _left, _right}} = error
       ) do
    Repo.query!(@rollback_sheet_materialization_savepoint)
    Repo.query!(@release_sheet_materialization_savepoint)
    error
  end

  # Sheet builders can return expected errors through a nested Repo.rollback/1.
  # That leaves DBConnection rolling back until the caller rolls back the outer
  # transaction, so issuing savepoint SQL here would mask the original error.
  defp finish_sheet_materialization_savepoint({:error, _reason} = error), do: error

  defp recover_and_rewrite_sheets(project_id, snapshot_data, user_id, opts) do
    with {:ok, sheet_maps} <- recover_sheets(project_id, snapshot_data, user_id, opts),
         {:ok, rewritten_snapshot} <-
           rewrite_snapshot_variable_namespaces(snapshot_data, sheet_maps.sheet, opts),
         :ok <-
           rewrite_materialized_formula_namespaces(project_id, sheet_maps.sheet, opts) do
      {:ok, {sheet_maps, rewritten_snapshot}}
    end
  end

  defp portable_namespace_attempt_limit(opts) do
    case Keyword.fetch(opts, :portable_variable_plan) do
      {:ok, plan} -> VariableReferenceTracker.portable_namespace_materialization_attempt_limit(plan)
      :error -> {:ok, 1}
    end
  end

  defp rewrite_snapshot_variable_namespaces(snapshot_data, sheet_id_map, opts) do
    case Keyword.fetch(opts, :portable_variable_plan) do
      {:ok, plan} ->
        VariableReferenceTracker.rewrite_portable_project_snapshot(
          snapshot_data,
          plan,
          sheet_id_map
        )

      :error ->
        {:ok, snapshot_data}
    end
  end

  defp rewrite_materialized_formula_namespaces(project_id, sheet_id_map, opts) do
    case Keyword.fetch(opts, :portable_variable_plan) do
      {:ok, plan} ->
        VariableReferenceTracker.rewrite_materialized_formula_bindings(
          project_id,
          plan,
          sheet_id_map
        )

      :error ->
        :ok
    end
  end

  # ========== Project Creation ==========

  defp create_project(workspace_id, user_id, name, snapshot_data, opts) do
    slug = NameNormalizer.generate_unique_slug(Project, [workspace_id: workspace_id], name)
    project = snapshot_import_project(user_id, opts)

    changeset =
      project_creation_changeset(
        project,
        recovered_project_attrs(workspace_id, name, slug, snapshot_data, opts),
        opts
      )

    Repo.insert(changeset)
  end

  defp snapshot_import_project(user_id, opts) do
    case Keyword.get(opts, @snapshot_import_project_id_key) do
      project_id when is_integer(project_id) and project_id > 0 ->
        %Project{id: project_id, owner_id: user_id}

      _not_snapshot_import ->
        %Project{owner_id: user_id}
    end
  end

  defp project_creation_changeset(project, attrs, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: Project.snapshot_import_changeset(project, attrs),
      else: Project.create_changeset(project, attrs)
  end

  defp recovered_project_attrs(workspace_id, name, slug, snapshot_data, opts) do
    snapshot_project = snapshot_data["project"] || %{}

    if MaterializationHelpers.exact_materialization?(opts) do
      %{
        name: name,
        slug: slug,
        workspace_id: workspace_id,
        description: snapshot_project["description"],
        project_type: snapshot_project["project_type"],
        project_subtype: snapshot_project["project_subtype"],
        project_type_other: snapshot_project["project_type_other"],
        settings: snapshot_project["settings"],
        auto_version_flows: snapshot_project["auto_version_flows"],
        auto_version_scenes: snapshot_project["auto_version_scenes"],
        auto_version_sheets: snapshot_project["auto_version_sheets"]
      }
    else
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

  defp materialize_snapshot_import_root_tombstones(project_id, snapshot_data, opts, now) do
    if snapshot_import_materialization?(opts) do
      snapshot_data
      |> snapshot_import_tombstone_entries()
      |> Enum.filter(&(&1["entity_type"] in ~w(sheet flow scene)))
      |> Enum.reduce_while(
        {:ok, empty_recovery_id_maps()},
        &reduce_snapshot_import_root_tombstone(&1, &2, project_id, now)
      )
    else
      {:ok, empty_recovery_id_maps()}
    end
  end

  defp reduce_snapshot_import_root_tombstone(entry, {:ok, id_maps}, project_id, now) do
    case insert_snapshot_import_root_tombstone(project_id, entry, now) do
      {:ok, kind, source_id, destination_id} ->
        {:cont, {:ok, put_in(id_maps, [kind, source_id], destination_id)}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp insert_snapshot_import_root_tombstone(project_id, entry, now) do
    source_id = entry["id"]
    deleted_at = snapshot_import_tombstone_deleted_at!(entry)
    snapshot = entry["snapshot"]

    {kind, schema, attrs} =
      case entry["entity_type"] do
        "sheet" -> {:sheet, Sheet, snapshot_import_sheet_tombstone_attrs(snapshot)}
        "flow" -> {:flow, Flow, snapshot_import_flow_tombstone_attrs(snapshot)}
        "scene" -> {:scene, Scene, snapshot_import_scene_tombstone_attrs(snapshot)}
      end

    attrs =
      attrs
      |> Map.put(:project_id, project_id)
      |> Map.put(:deleted_at, deleted_at)
      |> Map.merge(MaterializationHelpers.timestamps(now))

    case MaterializationHelpers.insert_one_returning_id(Repo, schema, attrs) do
      {:ok, destination_id} -> {:ok, kind, source_id, destination_id}
      {:error, reason} -> {:error, {:snapshot_import_tombstone_insert_failed, kind, source_id, reason}}
    end
  end

  defp snapshot_import_sheet_tombstone_attrs(snapshot) do
    %{
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      description: snapshot["description"],
      color: snapshot["color"],
      position: snapshot["position"],
      hidden_inherited_block_ids: snapshot["hidden_inherited_block_ids"],
      parent_id: nil,
      banner_asset_id: nil
    }
  end

  defp snapshot_import_flow_tombstone_attrs(snapshot) do
    %{
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      description: snapshot["description"],
      position: snapshot["position"],
      is_main: snapshot["is_main"],
      settings: snapshot["settings"],
      parent_id: nil,
      scene_id: nil
    }
  end

  defp snapshot_import_scene_tombstone_attrs(snapshot) do
    snapshot
    |> Map.take(~w(
      name shortcut description width height default_zoom default_center_x default_center_y
      position scale_unit scale_value fog_color fog_opacity exploration_display_mode
    ))
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Map.merge(%{parent_id: nil, background_asset_id: nil})
  end

  defp materialize_snapshot_import_block_tombstones(snapshot_data, sheet_id_map, opts, now) do
    entries =
      if snapshot_import_materialization?(opts),
        do: Enum.filter(snapshot_import_tombstone_entries(snapshot_data), &(&1["entity_type"] == "block")),
        else: []

    Enum.reduce_while(entries, {:ok, empty_recovery_id_maps()}, fn entry, {:ok, id_maps} ->
      owner_id = get_in(entry, ["owner", "id"])

      with {:ok, sheet_id} <- fetch_required_mapping(sheet_id_map, owner_id, {:tombstone_block_owner, entry["id"]}),
           {:ok, block_id} <- insert_snapshot_import_block_tombstone(entry, sheet_id, now) do
        {:cont, {:ok, put_in(id_maps, [:block, entry["id"]], block_id)}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp insert_snapshot_import_block_tombstone(entry, sheet_id, now) do
    snapshot = entry["snapshot"]

    attrs =
      snapshot
      |> Map.take(~w(
        type position config value is_constant variable_name scope detached required
        column_group_id column_index word_count
      ))
      |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
      |> Map.merge(%{
        sheet_id: sheet_id,
        inherited_from_block_id: nil,
        deleted_at: snapshot_import_tombstone_deleted_at!(entry)
      })
      |> Map.merge(MaterializationHelpers.timestamps(now))

    case MaterializationHelpers.insert_one_returning_id(Repo, Block, attrs) do
      {:ok, block_id} -> {:ok, block_id}
      {:error, reason} -> {:error, {:snapshot_import_tombstone_insert_failed, :block, entry["id"], reason}}
    end
  end

  defp materialize_detached_snapshot_import_node_tombstones(snapshot_data, tombstone_flow_map, opts, now) do
    entries =
      if snapshot_import_materialization?(opts),
        do: snapshot_import_tombstone_entries(snapshot_data),
        else: []

    Enum.reduce_while(
      tombstone_flow_map,
      {:ok, empty_recovery_id_maps()},
      fn {source_flow_id, flow_id}, {:ok, id_maps} ->
        reduce_detached_snapshot_import_nodes(entries, source_flow_id, flow_id, id_maps, now)
      end
    )
  end

  defp reduce_detached_snapshot_import_nodes(entries, source_flow_id, flow_id, id_maps, now) do
    with {:ok, node_map} <-
           insert_snapshot_import_node_tombstones(entries, source_flow_id, flow_id, now),
         nil <- conflicting_materialized_id(id_maps.node, node_map) do
      {:cont, {:ok, Map.put(id_maps, :node, Map.merge(id_maps.node, node_map))}}
    else
      source_id when is_integer(source_id) ->
        {:halt, {:error, {:duplicate_project_snapshot_identity, :node, source_id}}}

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp insert_snapshot_import_node_tombstones(entries, source_flow_id, flow_id, now) do
    entries
    |> Enum.filter(fn entry ->
      entry["entity_type"] == "flow_node" and get_in(entry, ["owner", "id"]) == source_flow_id
    end)
    |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, node_map} ->
      attrs = snapshot_import_node_tombstone_attrs(entry, flow_id, now)

      case MaterializationHelpers.insert_one_returning_id(Repo, FlowNode, attrs) do
        {:ok, node_id} -> {:cont, {:ok, Map.put(node_map, entry["id"], node_id)}}
        {:error, reason} -> {:halt, {:error, {:snapshot_import_tombstone_insert_failed, :node, entry["id"], reason}}}
      end
    end)
  end

  defp snapshot_import_node_tombstone_attrs(entry, flow_id, now) do
    entry["snapshot"]
    |> Map.take(~w(type position_x position_y data word_count derivatives_fingerprint))
    |> Map.new(fn {key, value} -> {String.to_existing_atom(key), value} end)
    |> Map.merge(%{
      flow_id: flow_id,
      parent_id: nil,
      deleted_at: snapshot_import_tombstone_deleted_at!(entry)
    })
    |> Map.merge(MaterializationHelpers.timestamps(now))
  end

  defp snapshot_import_tombstone_deleted_at!(entry) do
    {:ok, deleted_at, 0} = DateTime.from_iso8601(entry["deleted_at"])
    DateTime.truncate(deleted_at, :second)
  end

  defp snapshot_import_tombstone_entries(snapshot_data),
    do: get_in(snapshot_data, ["referenced_tombstones", "entries"]) || []

  defp remap_snapshot_import_tombstone_payloads(snapshot_data, id_maps, opts) do
    if snapshot_import_materialization?(opts) do
      id_maps = Map.put(id_maps, :asset, Keyword.fetch!(opts, @snapshot_import_asset_id_map_key))

      snapshot_data
      |> snapshot_import_tombstone_entries()
      |> remap_snapshot_import_tombstone_entries(id_maps, opts)
    else
      :ok
    end
  end

  defp remap_snapshot_import_tombstone_entries(entries, id_maps, opts) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case remap_snapshot_import_tombstone_payload(entry, id_maps, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_snapshot_import_tombstone_payload(
         %{"entity_type" => "block", "id" => source_id, "snapshot" => snapshot},
         id_maps,
         opts
       ) do
    remap_sheet_block_payloads([Map.put(snapshot, "original_id", source_id)], id_maps, opts)
  end

  defp remap_snapshot_import_tombstone_payload(
         %{"entity_type" => "flow_node", "id" => source_id, "owner" => %{"id" => source_flow_id}, "snapshot" => snapshot},
         id_maps,
         opts
       ) do
    with {:ok, flow_id} <-
           fetch_required_mapping(id_maps.flow, source_flow_id, {:tombstone_flow_node_owner, source_id}) do
      remap_flow_nodes([Map.put(snapshot, "original_id", source_id)], flow_id, id_maps, opts)
    end
  end

  defp remap_snapshot_import_tombstone_payload(_entry, _id_maps, _opts), do: :ok

  defp snapshot_import_materialization?(opts) do
    case Keyword.get(opts, @snapshot_import_project_id_key) do
      project_id when is_integer(project_id) and project_id > 0 -> true
      _not_snapshot_import -> false
    end
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

  defp recover_flows(project_id, snapshot_data, sheet_id_map, scene_id_map, avatar_id_map, tombstone_maps, user_id, opts) do
    builder_opts =
      user_id
      |> materialization_opts(opts,
        external_id_maps: %{
          sheet: Map.merge(tombstone_maps.sheet, sheet_id_map),
          avatar: avatar_id_map,
          scene: Map.merge(tombstone_maps.scene, scene_id_map),
          flow: tombstone_maps.flow
        },
        restore_localization: false,
        rebuild_references: false
      )
      |> maybe_put_snapshot_import_tombstone_nodes_fun(snapshot_data, tombstone_maps, opts)

    materialize_entities(snapshot_data["flows"] || [], :flow, fn snapshot ->
      snapshot = remap_snapshot_import_flow_scene(snapshot, tombstone_maps.scene, opts)
      FlowBuilder.instantiate_snapshot(project_id, snapshot, builder_opts)
    end)
  end

  defp maybe_put_snapshot_import_tombstone_nodes_fun(builder_opts, snapshot_data, tombstone_maps, opts) do
    if snapshot_import_materialization?(opts) do
      entries = snapshot_import_tombstone_entries(snapshot_data)

      builder_opts
      |> Keyword.put(
        @snapshot_import_tombstone_nodes_fun_key,
        fn flow_id, flow_snapshot, _active_node_id_map, now ->
          insert_snapshot_import_node_tombstones(entries, flow_snapshot["original_id"], flow_id, now)
        end
      )
      |> Keyword.put(
        @snapshot_import_external_tombstone_node_map_key,
        Map.get(tombstone_maps, :node, %{})
      )
    else
      builder_opts
    end
  end

  defp remap_snapshot_import_flow_scene(snapshot, tombstone_scene_map, opts) do
    if snapshot_import_materialization?(opts) do
      case Map.get(tombstone_scene_map, snapshot["scene_id"]) do
        scene_id when is_integer(scene_id) -> Map.put(snapshot, "scene_id", scene_id)
        _not_tombstone -> snapshot
      end
    else
      snapshot
    end
  end

  defp materialization_opts(user_id, recovery_opts, builder_opts) do
    builder_opts =
      recovery_opts
      |> Keyword.take([
        :asset_copy_tracker,
        :asset_materialization_cache,
        :asset_source_keys,
        :pre_materialized_assets,
        @materialization_mode_key
      ])
      |> Keyword.merge(builder_opts)
      |> Keyword.put(:user_id, user_id)

    Keyword.put(builder_opts, :asset_mode, recovery_asset_mode(recovery_opts))
  end

  defp recovery_asset_mode(opts) do
    if Keyword.get(opts, :pre_materialized_assets) == true, do: :reuse, else: :copy
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
    materialized_maps = namespace_connection_id_map(materialized_maps, entity_type)

    with :ok <- validate_materialized_root_mapping(entry, entity_type, materialized_maps),
         {:ok, merged_maps} <- merge_materialized_id_maps(id_maps, materialized_maps),
         {:ok, merged_maps} <- merge_tombstone_node_maps(merged_maps, materialized_maps) do
      {:cont, {:ok, merged_maps}}
    else
      {:error, reason} -> halt_materialization(entry, entity_type, reason)
    end
  end

  defp namespace_connection_id_map(materialized_maps, :flow) do
    materialized_maps
    |> Map.put(:flow_connection, Map.get(materialized_maps, :connection, %{}))
    |> Map.delete(:connection)
  end

  defp namespace_connection_id_map(materialized_maps, :scene) do
    materialized_maps
    |> Map.put(:scene_connection, Map.get(materialized_maps, :connection, %{}))
    |> Map.delete(:connection)
  end

  defp namespace_connection_id_map(materialized_maps, _entity_type), do: materialized_maps

  defp merge_tombstone_node_maps(id_maps, materialized_maps) do
    existing = Map.get(id_maps, :referenced_tombstone_node, %{})
    incoming = Map.get(materialized_maps, :referenced_tombstone_node, %{})

    case conflicting_materialized_id(existing, incoming) do
      nil -> {:ok, Map.put(id_maps, :referenced_tombstone_node, Map.merge(existing, incoming))}
      source_id -> {:error, {:duplicate_project_snapshot_identity, :node, source_id}}
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

  defp validate_materialized_id_map_coverage(snapshot_data, id_maps) do
    case preflight_identity_maps(snapshot_data) do
      {:ok, captured_maps} -> validate_materialized_id_maps(captured_maps, id_maps)
      {:error, _reason} = error -> error
    end
  end

  defp validate_materialized_id_maps(captured_maps, id_maps) do
    Enum.reduce_while(@recovery_id_map_keys, :ok, fn kind, :ok ->
      validate_materialized_id_map(kind, captured_maps, id_maps)
    end)
  end

  defp validate_materialized_id_map(kind, captured_maps, id_maps) do
    captured_ids = captured_maps |> Map.fetch!(kind) |> Map.keys() |> MapSet.new()
    materialized_ids = id_maps |> Map.fetch!(kind) |> Map.keys() |> MapSet.new()

    if MapSet.equal?(captured_ids, materialized_ids) do
      {:cont, :ok}
    else
      {:halt,
       {:error,
        {:materialized_id_map_coverage_mismatch, kind,
         %{
           missing: captured_ids |> MapSet.difference(materialized_ids) |> Enum.sort(),
           unexpected: materialized_ids |> MapSet.difference(captured_ids) |> Enum.sort()
         }}}}
    end
  end

  # ========== Phase B: Remap Cross-Entity References ==========

  defp remap_sheet_refs(project_id, id_maps, snapshot_data, opts) do
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
               id_maps.block,
               opts
             ),
           :ok <-
             remap_block_inheritance(
               project_id,
               entry["snapshot"]["blocks"] || [],
               id_maps.block,
               opts
             ),
           :ok <-
             remap_sheet_block_payloads(
               entry["snapshot"]["blocks"] || [],
               id_maps,
               opts
             ) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp maybe_validate_recovered_sheet_inheritance(project_id, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: :ok,
      else: validate_recovered_sheet_inheritance(project_id)
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

  defp remap_hidden_inherited_block_ids(sheet_id, snapshot, block_id_map, opts) do
    with {:ok, hidden_ids} <-
           remap_authored_ids(
             snapshot["hidden_inherited_block_ids"],
             block_id_map,
             {:sheet, snapshot["original_id"], "hidden_inherited_block_ids"},
             opts
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

  defp remap_block_inheritance(project_id, blocks_data, block_id_map, opts) do
    Enum.reduce_while(blocks_data, :ok, fn block_data, :ok ->
      with {:ok, new_block_id} <-
             fetch_required_mapping(
               block_id_map,
               block_data["original_id"],
               {:block, block_data["original_id"]}
             ),
           {:ok, remapped_parent} <-
             fetch_optional_materialized_fk_mapping(
               block_id_map,
               block_data["inherited_from_block_id"],
               Block,
               project_id,
               {:block, block_data["original_id"], "inherited_from_block_id"},
               {:exact_snapshot_fk_not_materializable, :block, :inherited_from_block_id,
                block_data["inherited_from_block_id"]},
               opts
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

  defp remap_sheet_block_payloads(blocks, id_maps, opts) do
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
               block["original_id"],
               opts
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

  defp remap_sheet_block_value("reference", value, id_maps, block_id, opts) when is_map(value) do
    remap_block_reference_target(value, id_maps, block_id, opts)
  end

  defp remap_sheet_block_value("reference", value, _id_maps, block_id, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: {:ok, value},
      else: {:error, {:invalid_project_snapshot_reference_block, block_id, value}}
  end

  defp remap_sheet_block_value("rich_text", value, id_maps, block_id, opts) do
    remap_embedded_mentions(value, id_maps, {:block, block_id}, opts)
  end

  defp remap_sheet_block_value(_block_type, value, _id_maps, _block_id, _opts), do: {:ok, value}

  defp remap_block_reference_target(value, id_maps, block_id, opts) do
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
               fetch_authored_json_mapping(
                 id_map,
                 source_target_id,
                 {:block, block_id, "target_id", target_type},
                 opts
               ) do
          {:ok, Map.put(value, "target_id", target_id)}
        end

      {target_type, source_target_id} ->
        if MaterializationHelpers.exact_materialization?(opts),
          do: {:ok, value},
          else: {:error, {:invalid_project_snapshot_typed_reference, {:block, block_id}, target_type, source_target_id}}
    end
  end

  defp remap_flow_refs(project_id, id_maps, snapshot_data, opts) do
    flow_entries = snapshot_data["flows"] || []
    snapshot_node_index = build_flow_snapshot_node_index(flow_entries)

    Enum.reduce_while(flow_entries, :ok, fn entry, :ok ->
      case remap_single_flow_snapshot(entry, project_id, id_maps, snapshot_node_index, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp maybe_validate_recovered_flow_cycles(flow_id_map, opts) do
    if MaterializationHelpers.exact_materialization?(opts), do: :ok, else: validate_recovered_flow_cycles(flow_id_map)
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

  defp remap_single_flow_snapshot(entry, project_id, id_maps, snapshot_node_index, opts) do
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
             id_maps.scene,
             project_id,
             opts
           ),
         :ok <-
           remap_flow_nodes(
             entry["snapshot"]["nodes"] || [],
             new_flow_id,
             id_maps,
             opts
           ),
         :ok <-
           remap_flow_connection_endpoints(
             entry["snapshot"],
             new_flow_id,
             project_id,
             id_maps,
             opts
           ) do
      remap_flow_dynamic_exit_pins(
        entry,
        new_flow_id,
        id_maps,
        snapshot_node_index,
        opts
      )
    end
  end

  defp remap_flow_connection_endpoints(snapshot, new_flow_id, project_id, id_maps, opts) do
    nodes = snapshot["nodes"] || []

    Enum.reduce_while(snapshot["connections"] || [], :ok, fn connection, :ok ->
      case remap_single_flow_connection_endpoints(
             connection,
             nodes,
             new_flow_id,
             project_id,
             id_maps,
             opts
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_single_flow_connection_endpoints(connection, nodes, new_flow_id, project_id, id_maps, opts) do
    with {:ok, new_connection_id} <-
           fetch_required_mapping(
             id_maps.flow_connection,
             connection["original_id"],
             {:flow_connection, connection["original_id"]}
           ),
         {:ok, source_node_id} <-
           remap_flow_connection_endpoint(connection, nodes, :source, project_id, id_maps, opts),
         {:ok, target_node_id} <-
           remap_flow_connection_endpoint(connection, nodes, :target, project_id, id_maps, opts) do
      case Repo.update_all(
             from(flow_connection in FlowConnection,
               where:
                 flow_connection.id == ^new_connection_id and
                   flow_connection.flow_id == ^new_flow_id
             ),
             set: [source_node_id: source_node_id, target_node_id: target_node_id]
           ) do
        {1, _rows} -> :ok
        {count, _rows} -> {:error, {:materialized_row_count_mismatch, :flow_connection, new_connection_id, count}}
      end
    end
  end

  defp remap_flow_connection_endpoint(connection, nodes, endpoint, project_id, id_maps, opts) do
    index_key = if endpoint == :source, do: "source_node_index", else: "target_node_index"
    id_key = if endpoint == :source, do: "source_node_id", else: "target_node_id"
    error_field = if endpoint == :source, do: :source_node_id, else: :target_node_id

    indexed_node =
      if is_integer(connection[index_key]),
        do: Enum.at(nodes, connection[index_key])

    source_id =
      case indexed_node do
        %{"original_id" => original_id} -> original_id
        _missing_index -> connection[id_key]
      end

    fetch_optional_materialized_fk_mapping(
      id_maps.node,
      source_id,
      FlowNode,
      project_id,
      {:flow_connection, connection["original_id"], id_key},
      {:exact_snapshot_fk_not_materializable, :flow_connection, error_field, source_id},
      opts
    )
  end

  defp remap_flow_nodes(nodes, new_flow_id, id_maps, opts) do
    Enum.reduce_while(nodes, :ok, fn node, :ok ->
      case remap_node_snapshot(node, new_flow_id, id_maps, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_flow_dynamic_exit_pins(entry, new_flow_id, id_maps, snapshot_node_index, opts) do
    snapshot = entry["snapshot"]
    nodes = snapshot["nodes"] || []

    Enum.reduce_while(snapshot["connections"] || [], :ok, fn connection, :ok ->
      source_node =
        if is_integer(connection["source_node_index"]),
          do: Enum.at(nodes, connection["source_node_index"])

      case remap_recovered_dynamic_exit_pin(
             connection,
             source_node,
             new_flow_id,
             id_maps,
             snapshot_node_index,
             opts
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
         snapshot_node_index,
         opts
       ) do
    with {old_exit_id, ""} <- Integer.parse(old_id_text),
         old_referenced_flow_id when is_integer(old_referenced_flow_id) <-
           normalize_recovery_id(get_in(source_node, ["data", "referenced_flow_id"])) do
      case Map.get(snapshot_node_index, old_exit_id) do
        %{flow_id: ^old_referenced_flow_id, type: "exit"} ->
          maybe_preserve_exact_dynamic_pin(
            materialize_recovered_dynamic_exit_pin(
              connection_id,
              pin,
              old_exit_id,
              old_referenced_flow_id,
              source_node["original_id"],
              new_flow_id,
              id_maps
            ),
            opts
          )

        _missing_or_wrong_owner ->
          maybe_preserve_exact_dynamic_pin(
            {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :exit_not_in_referenced_flow_snapshot}},
            opts
          )
      end
    else
      _invalid_dynamic_pin ->
        maybe_preserve_exact_dynamic_pin(
          {:error, {:dynamic_exit_pin_not_materializable, connection_id, pin, :invalid_dynamic_exit_reference}},
          opts
        )
    end
  end

  defp remap_recovered_dynamic_exit_pin(_connection, _source_node, _new_flow_id, _id_maps, _snapshot_node_index, _opts),
    do: :ok

  defp maybe_preserve_exact_dynamic_pin({:error, reason}, opts) do
    if MaterializationHelpers.exact_materialization?(opts), do: :ok, else: {:error, reason}
  end

  defp maybe_preserve_exact_dynamic_pin(result, _opts), do: result

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
             id_maps.flow_connection,
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

  defp remap_node_snapshot(node_data, new_flow_id, id_maps, opts) do
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
        id_maps,
        opts
      )
    end
  end

  defp remap_flow_scene_id(_new_flow_id, nil, _scene_map, _project_id, _opts), do: :ok

  defp remap_flow_scene_id(new_flow_id, old_scene_id, scene_map, project_id, opts) do
    with {:ok, new_scene_id} <-
           fetch_optional_materialized_fk_mapping(
             scene_map,
             old_scene_id,
             Scene,
             project_id,
             {:flow, new_flow_id, "scene_id"},
             {:exact_snapshot_fk_not_materializable, :flow, :scene_id, old_scene_id},
             opts
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

  defp remap_single_node_data(node_id, new_flow_id, source_node_id, node_type, data, id_maps, opts) do
    original_data = data

    with {:ok, data} <- remap_authored_node_data(source_node_id, data, id_maps, opts),
         {:ok, new_data} <- maybe_normalize_recovered_node_avatar(new_flow_id, node_type, data, opts) do
      persist_remapped_node_data(node_id, original_data, new_data)
    end
  end

  defp remap_authored_node_data(source_node_id, data, id_maps, opts) do
    with {:ok, data} <-
           remap_node_data_reference(data, "speaker_sheet_id", id_maps.sheet, source_node_id, opts),
         {:ok, data} <-
           remap_node_data_reference(data, "location_sheet_id", id_maps.sheet, source_node_id, opts),
         {:ok, data} <-
           remap_node_data_reference(data, "referenced_flow_id", id_maps.flow, source_node_id, opts),
         {:ok, data} <- remap_node_data_reference(data, "avatar_id", id_maps.avatar, source_node_id, opts),
         {:ok, data} <- remap_node_asset_reference(data, source_node_id, id_maps, opts),
         {:ok, data} <- remap_node_typed_target(data, id_maps, source_node_id, opts) do
      remap_embedded_mentions(data, id_maps, {:flow_node, source_node_id}, opts)
    end
  end

  defp remap_node_asset_reference(data, source_node_id, %{asset: asset_ids}, opts),
    do: remap_node_data_reference(data, "audio_asset_id", asset_ids, source_node_id, opts)

  defp remap_node_asset_reference(data, _source_node_id, _id_maps, _opts), do: {:ok, data}

  defp maybe_normalize_recovered_node_avatar(flow_id, node_type, data, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: {:ok, data},
      else: AvatarIntegrity.lock_and_normalize_node_avatar(flow_id, node_type, data)
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

  defp remap_node_data_reference(data, key, id_map, source_node_id, opts) do
    case Map.fetch(data, key) do
      {:ok, value} ->
        with {:ok, remapped_id} <-
               fetch_optional_authored_json_mapping(
                 id_map,
                 value,
                 {:flow_node, source_node_id, key},
                 opts
               ) do
          {:ok, Map.put(data, key, remapped_id)}
        end

      :error ->
        {:ok, data}
    end
  end

  defp remap_node_typed_target(data, id_maps, source_node_id, opts) do
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
               fetch_authored_json_mapping(
                 id_map,
                 source_target_id,
                 {:flow_node, source_node_id, "target_id", target_type},
                 opts
               ) do
          {:ok, Map.put(data, "target_id", target_id)}
        end

      {target_type, source_target_id} ->
        if MaterializationHelpers.exact_materialization?(opts) do
          {:ok, data}
        else
          source = {:flow_node, source_node_id}
          {:error, {:invalid_project_snapshot_typed_reference, source, target_type, source_target_id}}
        end
    end
  end

  defp remap_scene_refs(project_id, id_maps, snapshot_data, opts) do
    Enum.reduce_while(snapshot_data["scenes"] || [], :ok, fn entry, :ok ->
      case remap_single_scene_snapshot(entry, project_id, id_maps, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_single_scene_snapshot(entry, project_id, id_maps, opts) do
    snapshot = entry["snapshot"]

    with {:ok, scene_id} <-
           fetch_required_mapping(
             id_maps.scene,
             entry["id"],
             {:scene, entry["id"]}
           ),
         :ok <- remap_scene_pin_refs(snapshot["orphan_pins"] || [], project_id, id_maps, opts),
         :ok <- remap_scene_zone_refs(snapshot["orphan_zones"] || [], id_maps, opts),
         :ok <- remap_scene_connection_refs(snapshot["connections"] || [], project_id, id_maps, opts),
         :ok <-
           remap_scene_ambient_flows(
             scene_id,
             snapshot["ambient_flows"] || [],
             id_maps.flow,
             project_id,
             opts
           ) do
      remap_scene_layer_refs(snapshot["layers"] || [], project_id, id_maps, opts)
    end
  end

  defp remap_scene_layer_refs(layers, project_id, id_maps, opts) do
    Enum.reduce_while(layers, :ok, fn layer, :ok ->
      with :ok <- remap_scene_pin_refs(layer["pins"] || [], project_id, id_maps, opts),
           :ok <- remap_scene_zone_refs(layer["zones"] || [], id_maps, opts) do
        {:cont, :ok}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_scene_ambient_flows(scene_id, ambient_flows, flow_id_map, project_id, opts) do
    Enum.reduce_while(ambient_flows, :ok, fn ambient_flow, :ok ->
      with {:ok, flow_id} <-
             fetch_optional_materialized_fk_mapping(
               flow_id_map,
               ambient_flow["flow_id"],
               Flow,
               project_id,
               {:scene_ambient_flow, ambient_flow["original_id"], "flow_id"},
               {:exact_snapshot_fk_not_materializable, :scene_ambient_flow, :flow_id, ambient_flow["flow_id"]},
               opts
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

  defp remap_scene_pin_refs(pin_snapshots, project_id, id_maps, opts) do
    Enum.reduce_while(pin_snapshots, :ok, fn pin, :ok ->
      case remap_single_scene_pin_ref(pin, project_id, id_maps, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_scene_zone_refs(zone_snapshots, id_maps, opts) do
    Enum.reduce_while(zone_snapshots, :ok, fn zone, :ok ->
      case remap_single_scene_zone_ref(zone, id_maps, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_single_scene_pin_ref(pin_data, project_id, id_maps, opts) do
    with {:ok, new_pin_id} <-
           fetch_required_mapping(
             id_maps.pin,
             pin_data["original_id"],
             {:scene_pin, pin_data["original_id"]}
           ),
         {:ok, updates} <- build_scene_pin_updates(pin_data, project_id, id_maps, opts) do
      maybe_update_scene_pin(updates, new_pin_id)
    end
  end

  defp build_scene_pin_updates(pin_data, project_id, id_maps, opts) do
    with {:ok, sheet_id} <-
           fetch_optional_materialized_fk_mapping(
             id_maps.sheet,
             pin_data["sheet_id"],
             Sheet,
             project_id,
             {:scene_pin, pin_data["original_id"], "sheet_id"},
             {:exact_snapshot_fk_not_materializable, :scene_pin, :sheet_id, pin_data["sheet_id"]},
             opts
           ),
         {:ok, flow_id} <-
           fetch_optional_materialized_fk_mapping(
             id_maps.flow,
             pin_data["flow_id"],
             Flow,
             project_id,
             {:scene_pin, pin_data["original_id"], "flow_id"},
             {:exact_snapshot_fk_not_materializable, :scene_pin, :flow_id, pin_data["flow_id"]},
             opts
           ) do
      {:ok, [sheet_id: sheet_id, flow_id: flow_id]}
    end
  end

  defp remap_scene_connection_refs(connections, project_id, id_maps, opts) do
    Enum.reduce_while(connections, :ok, fn connection, :ok ->
      case remap_single_scene_connection_ref(connection, project_id, id_maps, opts) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_single_scene_connection_ref(connection, project_id, id_maps, opts) do
    with {:ok, new_connection_id} <-
           fetch_required_mapping(
             id_maps.scene_connection,
             connection["original_id"],
             {:scene_connection, connection["original_id"]}
           ),
         {:ok, from_pin_id} <-
           remap_scene_connection_endpoint(connection, :from, project_id, id_maps, opts),
         {:ok, to_pin_id} <-
           remap_scene_connection_endpoint(connection, :to, project_id, id_maps, opts) do
      case Repo.update_all(
             from(scene_connection in SceneConnection,
               where: scene_connection.id == ^new_connection_id
             ),
             set: [from_pin_id: from_pin_id, to_pin_id: to_pin_id]
           ) do
        {1, _rows} -> :ok
        {count, _rows} -> {:error, {:materialized_row_count_mismatch, :scene_connection, new_connection_id, count}}
      end
    end
  end

  defp remap_scene_connection_endpoint(connection, endpoint, project_id, id_maps, opts) do
    field = if endpoint == :from, do: "from_pin_original_id", else: "to_pin_original_id"
    error_field = if endpoint == :from, do: :from_pin_original_id, else: :to_pin_original_id
    source_id = connection[field]

    fetch_optional_materialized_fk_mapping(
      id_maps.pin,
      source_id,
      ScenePin,
      project_id,
      {:scene_connection, connection["original_id"], field},
      {:exact_snapshot_fk_not_materializable, :scene_connection, error_field, source_id},
      opts
    )
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

  defp remap_single_scene_zone_ref(zone_data, id_maps, opts) do
    with {:ok, new_zone_id} <-
           fetch_required_mapping(
             id_maps.zone,
             zone_data["original_id"],
             {:scene_zone, zone_data["original_id"]}
           ),
         {:ok, updates} <- build_scene_zone_updates(zone_data, id_maps, opts) do
      maybe_update_scene_zone(updates, new_zone_id)
    end
  end

  defp build_scene_zone_updates(zone_data, id_maps, opts) do
    with {:ok, updates} <-
           maybe_put_target_update(
             [],
             zone_data["target_type"],
             zone_data["target_id"],
             id_maps,
             zone_data["original_id"],
             opts
           ),
         {:ok, action_data} <- remap_scene_zone_action_data(zone_data, id_maps, opts) do
      {:ok, Keyword.put(updates, :action_data, action_data)}
    end
  end

  defp remap_scene_zone_action_data(
         %{"action_type" => "collection", "action_data" => %{"items" => items} = action_data},
         id_maps,
         opts
       )
       when is_list(items) do
    items
    |> Enum.reduce_while({:ok, []}, fn
      %{} = item, {:ok, remapped_items} ->
        case fetch_optional_authored_json_mapping(
               id_maps.sheet,
               item["sheet_id"],
               {:scene_zone, "collection", "sheet_id"},
               opts
             ) do
          {:ok, sheet_id} ->
            {:cont, {:ok, [Map.put(item, "sheet_id", sheet_id) | remapped_items]}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      item, {:ok, remapped_items} ->
        if MaterializationHelpers.exact_materialization?(opts),
          do: {:cont, {:ok, [item | remapped_items]}},
          else: {:halt, {:error, {:invalid_project_snapshot_scene_zone_collection_item, item}}}
    end)
    |> case do
      {:ok, remapped_items} -> {:ok, Map.put(action_data, "items", Enum.reverse(remapped_items))}
      {:error, _reason} = error -> error
    end
  end

  defp remap_scene_zone_action_data(zone_data, _id_maps, _opts) do
    {:ok, zone_data["action_data"] || %{}}
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

  defp maybe_put_target_update(updates, _type, nil, _id_maps, _zone_id, _opts), do: {:ok, updates}
  defp maybe_put_target_update(updates, _type, "", _id_maps, _zone_id, _opts), do: {:ok, updates}

  defp maybe_put_target_update(updates, type, old_id, id_maps, zone_id, opts) do
    case remap_target_id(type, old_id, id_maps) do
      nil ->
        if MaterializationHelpers.exact_materialization?(opts),
          do:
            {:ok,
             updates
             |> Keyword.put(:target_type, type)
             |> Keyword.put(:target_id, old_id)},
          else: {:error, {:missing_project_snapshot_reference, {:scene_zone, zone_id, "target_id", type}, old_id}}

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

  defp fetch_authored_json_mapping(id_map, source_id, context, opts) do
    case fetch_required_mapping(id_map, source_id, context) do
      {:error, reason} when is_list(opts) ->
        if MaterializationHelpers.exact_materialization?(opts), do: {:ok, source_id}, else: {:error, reason}

      result ->
        result
    end
  end

  defp fetch_optional_authored_json_mapping(_id_map, nil, _context, _opts), do: {:ok, nil}

  defp fetch_optional_authored_json_mapping(id_map, source_id, context, opts) do
    fetch_authored_json_mapping(id_map, source_id, context, opts)
  end

  defp fetch_optional_materialized_fk_mapping(_id_map, nil, _schema, _project_id, _context, _exact_error, _opts),
    do: {:ok, nil}

  defp fetch_optional_materialized_fk_mapping(id_map, source_id, schema, project_id, context, exact_error, opts) do
    case fetch_required_mapping(id_map, source_id, context) do
      {:ok, destination_id} ->
        {:ok, destination_id}

      {:error, _reason} = error ->
        recover_existing_materialized_fk(error, source_id, schema, project_id, exact_error, opts)
    end
  end

  defp recover_existing_materialized_fk(error, source_id, schema, project_id, exact_error, opts) do
    if MaterializationHelpers.exact_materialization?(opts) do
      preserve_existing_materialized_fk(source_id, schema, project_id, exact_error)
    else
      error
    end
  end

  defp preserve_existing_materialized_fk(source_id, schema, project_id, exact_error) do
    source_id = normalize_recovery_id(source_id)

    if is_integer(source_id) and materialized_fk_owned_by_project?(schema, source_id, project_id),
      do: {:ok, source_id},
      else: {:error, exact_error}
  end

  defp materialized_fk_owned_by_project?(schema, source_id, project_id) when schema in [Sheet, Flow, Scene] do
    Repo.exists?(
      from(record in schema,
        where: record.id == ^source_id and record.project_id == ^project_id
      )
    )
  end

  defp materialized_fk_owned_by_project?(Block, source_id, project_id) do
    Repo.exists?(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where: block.id == ^source_id and sheet.project_id == ^project_id
      )
    )
  end

  defp materialized_fk_owned_by_project?(FlowNode, source_id, project_id) do
    Repo.exists?(
      from(node in FlowNode,
        join: flow in Flow,
        on: flow.id == node.flow_id,
        where: node.id == ^source_id and flow.project_id == ^project_id
      )
    )
  end

  defp materialized_fk_owned_by_project?(ScenePin, source_id, project_id) do
    Repo.exists?(
      from(pin in ScenePin,
        join: scene in Scene,
        on: scene.id == pin.scene_id,
        where: pin.id == ^source_id and scene.project_id == ^project_id
      )
    )
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

  defp remap_authored_ids(nil, _id_map, _context, opts) do
    if MaterializationHelpers.exact_materialization?(opts), do: {:ok, nil}, else: {:ok, []}
  end

  defp remap_authored_ids(source_ids, id_map, context, opts) when is_list(source_ids) do
    source_ids
    |> Enum.reduce_while({:ok, []}, fn source_id, {:ok, destination_ids} ->
      case fetch_authored_json_mapping(id_map, source_id, context, opts) do
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

  defp remap_authored_ids(source_ids, id_map, context, _opts) do
    remap_required_ids(source_ids, id_map, context)
  end

  defp remap_embedded_mentions(value, id_maps, context, opts)

  defp remap_embedded_mentions(value, id_maps, context, opts) when is_binary(value) do
    if mention_markup?(value) do
      remap_embedded_mention_markup(value, id_maps, context, opts)
    else
      {:ok, value}
    end
  end

  defp remap_embedded_mentions(value, id_maps, context, opts) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, remapped} ->
      case remap_embedded_mentions(item, id_maps, context, opts) do
        {:ok, item} -> {:cont, {:ok, [item | remapped]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remapped} -> {:ok, Enum.reverse(remapped)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_embedded_mentions(value, id_maps, context, opts) when is_map(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, remapped} ->
      case remap_embedded_mentions(item, id_maps, context, opts) do
        {:ok, item} -> {:cont, {:ok, Map.put(remapped, key, item)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_embedded_mentions(value, _id_maps, _context, _opts), do: {:ok, value}

  defp remap_embedded_mention_markup(value, id_maps, context, opts) do
    with {:ok, document} <- Floki.parse_fragment(value),
         {:ok, document} <- remap_mention_nodes(document, id_maps, context, opts) do
      {:ok, Floki.raw_html(document)}
    else
      {:error, reason} -> recover_invalid_embedded_mention(value, context, reason, opts)
    end
  end

  defp recover_invalid_embedded_mention(value, context, reason, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: {:ok, value},
      else: {:error, {:invalid_project_snapshot_mention, context, reason}}
  end

  defp mention_markup?(value) do
    RichTextMentions.html_candidates(value) != []
  end

  defp remap_mention_nodes(nodes, id_maps, context, opts) when is_list(nodes) do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, remapped} ->
      case remap_mention_node(node, id_maps, context, opts) do
        {:ok, node} -> {:cont, {:ok, [node | remapped]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, remapped} -> {:ok, Enum.reverse(remapped)}
      {:error, _reason} = error -> error
    end
  end

  defp remap_mention_node({tag, attributes, children}, id_maps, context, opts)
       when is_binary(tag) and is_list(attributes) and is_list(children) do
    with {:ok, attributes} <-
           remap_mention_attributes(
             attributes,
             id_maps,
             context,
             opts
           ),
         {:ok, children} <-
           remap_mention_nodes(
             children,
             id_maps,
             context,
             opts
           ) do
      {:ok, {tag, attributes, children}}
    end
  end

  defp remap_mention_node(node, _id_maps, _context, _opts), do: {:ok, node}

  defp remap_mention_attributes(attributes, id_maps, context, opts) do
    remap_mention_attributes_by_kind(
      mention_attributes?(attributes),
      attributes,
      id_maps,
      context,
      opts
    )
  end

  defp remap_mention_attributes_by_kind(false, attributes, _id_maps, _context, _opts), do: {:ok, attributes}

  defp remap_mention_attributes_by_kind(true, attributes, id_maps, context, opts) do
    target_type = attribute_value(attributes, "data-type")
    source_id = attributes |> attribute_value("data-id") |> normalize_recovery_id()

    result =
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

    case result do
      {:error, _reason} when is_list(opts) ->
        if MaterializationHelpers.exact_materialization?(opts), do: {:ok, attributes}, else: result

      _result ->
        result
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

  defp restore_tree_hierarchy(project_id, %{"tree" => tree}, id_maps, opts) when is_map(tree) do
    with :ok <- remap_tree(tree["sheets"], id_maps.sheet, Sheet, project_id, :sheet, opts),
         :ok <- remap_tree(tree["flows"], id_maps.flow, Flow, project_id, :flow, opts) do
      remap_tree(
        tree["scenes"],
        id_maps.scene,
        Scene,
        project_id,
        :scene,
        opts
      )
    end
  end

  defp restore_tree_hierarchy(_project_id, _snapshot_data, _id_maps, _opts) do
    {:error, :missing_or_invalid_project_snapshot_tree}
  end

  defp remap_tree(tree_entries, id_map, schema, project_id, entity_type, opts) when is_list(tree_entries) do
    if MaterializationHelpers.exact_materialization?(opts) do
      remap_tree_entries(tree_entries, id_map, schema, project_id, entity_type, opts)
    else
      with :ok <- validate_tree_entries(tree_entries, id_map, entity_type),
           :ok <- validate_tree_cycles(tree_entries, entity_type) do
        remap_tree_entries(tree_entries, id_map, schema, project_id, entity_type, opts)
      end
    end
  end

  defp remap_tree(_tree_entries, _id_map, _schema, _project_id, entity_type, _opts) do
    {:error, {:invalid_project_snapshot_tree_collection, entity_type}}
  end

  defp remap_tree_entries(tree_entries, id_map, schema, project_id, entity_type, opts) do
    Enum.reduce_while(tree_entries, :ok, fn entry, :ok ->
      remap_tree_entry(entry, id_map, schema, project_id, entity_type, opts)
    end)
  end

  defp remap_tree_entry(entry, id_map, schema, project_id, entity_type, opts) do
    with {:ok, new_id} <-
           fetch_required_mapping(
             id_map,
             entry["id"],
             {:tree, entity_type, entry["id"]}
           ),
         {:ok, new_parent_id} <-
           fetch_optional_materialized_fk_mapping(
             id_map,
             entry["parent_id"],
             schema,
             project_id,
             {:tree, entity_type, entry["id"], "parent_id"},
             {:exact_snapshot_fk_not_materializable, entity_type, :parent_id, entry["parent_id"]},
             opts
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
               validate_recovery_localization_for_mode(
                 languages,
                 texts,
                 glossary,
                 id_maps,
                 snapshot_data,
                 opts
               ),
             :ok <- restore_languages(project_id, languages, opts, now),
             :ok <-
               restore_texts(
                 project_id,
                 recovery_texts_for_mode(texts, id_maps, opts),
                 id_maps,
                 snapshot_data,
                 user_id,
                 opts,
                 now
               ) do
          restore_glossary(project_id, glossary, opts, now)
        end

      _invalid ->
        {:error, :invalid_project_snapshot_localization}
    end
  end

  defp validate_recovery_localization_for_mode(languages, texts, glossary, id_maps, snapshot_data, opts) do
    if MaterializationHelpers.exact_materialization?(opts) do
      validate_exact_recovery_localization(languages, texts, glossary)
    else
      validate_recovery_localization(languages, texts, glossary, id_maps, snapshot_data)
    end
  end

  defp validate_exact_recovery_localization(languages, texts, glossary)
       when is_list(languages) and is_list(texts) and is_list(glossary) do
    if Enum.all?(languages ++ texts ++ glossary, &is_map/1),
      do: :ok,
      else: {:error, :invalid_project_snapshot_localization_entry}
  end

  defp validate_exact_recovery_localization(_languages, _texts, _glossary) do
    {:error, :invalid_project_snapshot_localization_collections}
  end

  defp recovery_texts_for_mode(texts, id_maps, opts) do
    if MaterializationHelpers.exact_materialization?(opts),
      do: texts,
      else: materializable_recovery_texts(texts, id_maps)
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
      validate_recovery_glossary(glossary)
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

  defp validate_recovery_glossary(glossary) do
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

      if length(keys) == MapSet.size(MapSet.new(keys)) do
        :ok
      else
        {:error, :duplicate_project_snapshot_glossary_entry}
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

  defp restore_languages(_project_id, [], _opts, _now), do: :ok

  defp restore_languages(project_id, languages, opts, now) do
    entries =
      Enum.map(languages, fn lang ->
        %{
          project_id: project_id,
          locale_code: lang["locale_code"],
          name: lang["name"],
          is_source: materialized_default(lang["is_source"], false, opts),
          position: materialized_default(lang["position"], 0, opts),
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
    context = %{
      project_id: project_id,
      snapshot_data: snapshot_data,
      user_id: user_id,
      opts: opts,
      now: now,
      mention_block_ids: rich_text_block_ids(snapshot_data)
    }

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
    result =
      Repo.insert_all(LocalizedText, chunk,
        on_conflict: LocalizationSnapshotCodec.restore_conflict_query(),
        conflict_target: [:source_type, :source_id, :source_field, :locale_code]
      )

    case result do
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
    with {:ok, text} <- remap_localization_mentions(text, id_maps, context.mention_block_ids, context.opts) do
      recovered_text_map_for_mode(text, id_maps, context)
    end
  end

  defp recovered_text_map_for_mode(text, id_maps, context) do
    if MaterializationHelpers.exact_materialization?(context.opts) do
      exact_recovered_text_map(text, id_maps, context)
    else
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

      {:ok, recovered_text_map(text, metadata, source_id, id_maps, context)}
    end
  end

  defp exact_recovered_text_map(text, id_maps, context) do
    with {:ok, source_id} <- exact_recovered_source_id(text, id_maps),
         {:ok, speaker_sheet_id} <-
           exact_recovered_speaker_id(text, id_maps, context.project_id, context.opts),
         {:ok, vo_asset_id} <- exact_recovered_vo_asset_id(text, context) do
      {:ok,
       %{
         project_id: context.project_id,
         source_type: text["source_type"],
         source_id: source_id,
         source_field: text["source_field"],
         source_text: text["source_text"],
         source_text_hash: text["source_text_hash"],
         translated_source_hash: text["translated_source_hash"],
         locale_code: text["locale_code"],
         translated_text: text["translated_text"],
         status: text["status"],
         vo_status: text["vo_status"],
         vo_asset_id: vo_asset_id,
         translator_notes: text["translator_notes"],
         reviewer_notes: text["reviewer_notes"],
         speaker_sheet_id: speaker_sheet_id,
         word_count: text["word_count"],
         content_role: text["content_role"],
         vo_eligible: text["vo_eligible"],
         machine_translated: text["machine_translated"],
         last_translated_at: parse_datetime(text["last_translated_at"]),
         last_reviewed_at: parse_datetime(text["last_reviewed_at"]),
         translated_by_id: recovered_localization_actor_id(text, "translated_by_id", context.opts),
         reviewed_by_id: recovered_localization_actor_id(text, "reviewed_by_id", context.opts),
         archived_at: parse_datetime(text["archived_at"]),
         archive_reason: text["archive_reason"],
         inserted_at: context.now,
         updated_at: context.now
       }}
    end
  end

  defp exact_recovered_source_id(text, id_maps) do
    case remap_source_id(text["source_type"], text["source_id"], id_maps) do
      nil ->
        preserve_authored_localization_source_id(text)

      destination_id ->
        {:ok, destination_id}
    end
  end

  defp preserve_authored_localization_source_id(text) do
    source_type = text["source_type"]
    source_id = normalize_recovery_id(text["source_id"])

    if is_integer(source_id) do
      {:ok, source_id}
    else
      {:error,
       {:exact_snapshot_reference_not_materializable, :localized_text, :source_id, source_type, text["source_id"]}}
    end
  end

  defp exact_recovered_speaker_id(%{"speaker_sheet_id" => nil}, _id_maps, _project_id, _opts), do: {:ok, nil}

  defp exact_recovered_speaker_id(%{"speaker_sheet_id" => source_id}, id_maps, project_id, opts) do
    fetch_optional_materialized_fk_mapping(
      id_maps.sheet,
      source_id,
      Sheet,
      project_id,
      {:localized_text, "speaker_sheet_id"},
      {:exact_snapshot_fk_not_materializable, :localized_text, :speaker_sheet_id, source_id},
      opts
    )
  end

  defp exact_recovered_speaker_id(_text, _id_maps, _project_id, _opts), do: {:ok, nil}

  defp exact_recovered_vo_asset_id(%{"vo_asset_id" => nil}, _context), do: {:ok, nil}

  defp exact_recovered_vo_asset_id(%{"vo_asset_id" => source_id}, context) do
    case remap_vo_asset_id(
           source_id,
           context.snapshot_data,
           context.project_id,
           context.user_id,
           context.opts
         ) do
      nil -> {:error, {:exact_snapshot_fk_not_materializable, :localized_text, :vo_asset_id, source_id}}
      destination_id -> {:ok, destination_id}
    end
  end

  defp exact_recovered_vo_asset_id(_text, _context), do: {:ok, nil}

  defp remap_localization_mentions(text, id_maps, mention_block_ids, opts) do
    if mention_capable_localization?(text, mention_block_ids) do
      remap_localization_mention_text(text, id_maps, opts)
    else
      {:ok, text}
    end
  end

  defp remap_localization_mention_text(text, id_maps, opts) do
    old_source_hash = text["source_text_hash"]

    with {:ok, source_text} <-
           remap_embedded_mentions(
             text["source_text"],
             id_maps,
             {:localization, text["source_type"], text["source_id"], text["source_field"], "source_text"},
             opts
           ),
         {:ok, translated_text} <-
           remap_embedded_mentions(
             text["translated_text"],
             id_maps,
             {:localization, text["source_type"], text["source_id"], text["source_field"], "translated_text"},
             opts
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

  defp rich_text_block_ids(snapshot_data) do
    snapshot_data["sheets"]
    |> Enum.flat_map(&get_in(&1, ["snapshot", "blocks"]))
    |> Enum.filter(&(&1["type"] == "rich_text"))
    |> MapSet.new(& &1["original_id"])
  end

  defp mention_capable_localization?(%{"source_type" => "flow_node"}, _block_ids), do: true

  defp mention_capable_localization?(
         %{"source_type" => "block", "source_id" => source_id, "source_field" => "value.content"},
         block_ids
       ) do
    MapSet.member?(block_ids, source_id)
  end

  defp mention_capable_localization?(_text, _block_ids), do: false

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
      translated_by_id: recovered_localization_actor_id(text, "translated_by_id", context.opts),
      reviewed_by_id: recovered_localization_actor_id(text, "reviewed_by_id", context.opts),
      archived_at: parse_datetime(text["archived_at"]),
      archive_reason: recovered_archive_reason(text["archive_reason"]),
      inserted_at: context.now,
      updated_at: context.now
    }
  end

  defp recovered_localization_actor_id(text, field, opts) do
    case Keyword.get(opts, @localization_actor_mode_key) do
      :preserve ->
        actor_id_if_present(
          text[field],
          Keyword.fetch!(opts, @preserved_localization_actor_ids_key)
        )

      :discard ->
        nil
    end
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

  defp materialized_default(value, default, opts) do
    if MaterializationHelpers.exact_materialization?(opts), do: value, else: value || default
  end

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
    opts
    |> Keyword.take([
      :asset_copy_tracker,
      :asset_materialization_cache,
      :asset_source_keys,
      :pre_materialized_assets,
      @materialization_mode_key
    ])
    |> Keyword.put(:asset_mode, recovery_asset_mode(opts))
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

  defp restore_glossary(_project_id, [], _opts, _now), do: :ok

  defp restore_glossary(project_id, glossary, opts, now) do
    glossary
    |> Enum.map(fn entry ->
      %{
        project_id: project_id,
        source_term: entry["source_term"],
        source_locale: entry["source_locale"],
        target_term: entry["target_term"],
        target_locale: entry["target_locale"],
        context: entry["context"],
        do_not_translate: materialized_default(entry["do_not_translate"], false, opts),
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
