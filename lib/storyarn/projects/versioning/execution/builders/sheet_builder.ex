defmodule Storyarn.Projects.Versioning.Builders.SheetBuilder do
  @moduledoc """
  Snapshot builder for sheets.

  Captures sheet metadata (name, shortcut, avatars, banner) and all blocks
  with their type, config, value, position, variable settings, table data, and
  gallery images.
  """

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false
  import Storyarn.Projects.Versioning.MaterializationHelpers, only: [exact_materialization?: 1]

  alias Storyarn.Projects.Persistence.BlockGalleryImageRecord, as: BlockGalleryImage
  alias Storyarn.Projects.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.Persistence.SheetAvatarRecord, as: SheetAvatar
  alias Storyarn.Projects.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.Persistence.TableColumnRecord, as: TableColumn
  alias Storyarn.Projects.Persistence.TableRowRecord, as: TableRow
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.References
  alias Storyarn.Projects.Versioning.Adapters.Localization.VersionRestore, as: LocalizationVersionRestore
  alias Storyarn.Projects.Versioning.AssetMaterializationScope
  alias Storyarn.Projects.Versioning.Builders.AssetHashResolver
  alias Storyarn.Projects.Versioning.DiffHelpers
  alias Storyarn.Projects.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Projects.Versioning.MaterializationHelpers
  alias Storyarn.Projects.Versioning.SheetLocalizationSnapshotValidator
  alias Storyarn.Projects.WordCount
  alias Storyarn.Repo

  @sheet_snapshot_fields ~w(
    original_id name shortcut description avatar_asset_id avatars banner_asset_id color
    hidden_inherited_block_ids blocks asset_blob_hashes asset_metadata localization
    localization_manifest
  )
  @restored_optional_block_fields ~w(variable_name inherited_from_block_id column_group_id)
  @restored_optional_avatar_fields ~w(name notes)
  @restored_optional_gallery_image_fields ~w(label description)

  # ========== Build Snapshot ==========

  def build_snapshot(%Sheet{} = sheet) do
    build_snapshot(sheet, :strict)
  end

  @doc false
  @spec build_capture_snapshot(Sheet.t()) :: map()
  def build_capture_snapshot(%Sheet{} = sheet) do
    build_snapshot(sheet, :capture)
  end

  defp build_snapshot(%Sheet{} = sheet, mode) when mode in [:strict, :capture] do
    {:ok, snapshot} =
      Repo.transaction(
        fn ->
          :ok = lock_sheet_project_for_snapshot!(sheet.project_id)
          locked_sheet = lock_sheet_for_snapshot!(sheet)

          :ok = LocalizationVersionRestore.lock_inventory!(locked_sheet.project_id)
          do_build_snapshot(locked_sheet, mode)
        end,
        isolation: :repeatable_read
      )

    snapshot
  end

  defp lock_sheet_project_for_snapshot!(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      %Project{deleted_at: nil} ->
        :ok

      %Project{} ->
        raise ArgumentError, "cannot snapshot sheet under inactive project #{project_id}"

      nil ->
        raise ArgumentError, "cannot snapshot sheet under missing project #{project_id}"
    end
  end

  defp lock_sheet_for_snapshot!(%Sheet{id: sheet_id, project_id: project_id}) do
    case Repo.one(from(sheet in Sheet, where: sheet.id == ^sheet_id, lock: "FOR UPDATE")) do
      %Sheet{project_id: ^project_id, deleted_at: nil} = locked_sheet ->
        locked_sheet

      %Sheet{project_id: ^project_id} ->
        raise ArgumentError, "cannot snapshot inactive sheet #{sheet_id}"

      %Sheet{project_id: owner_project_id} ->
        raise ArgumentError,
              "sheet #{sheet_id} changed project ownership to #{owner_project_id} while building snapshot"

      nil ->
        raise ArgumentError, "cannot snapshot missing sheet #{sheet_id}"
    end
  end

  defp do_build_snapshot(%Sheet{} = sheet, mode) do
    active_blocks =
      from(b in Block,
        where: is_nil(b.deleted_at),
        order_by: [asc: b.position, asc: b.id]
      )

    sheet =
      Repo.preload(
        sheet,
        [blocks: {active_blocks, [:table_columns, :table_rows, gallery_images: :asset]}, avatars: :asset],
        force: true
      )

    avatar_snapshots =
      sheet.avatars
      |> sorted_avatars()
      |> Enum.map(&avatar_to_snapshot/1)
      |> maybe_normalize_avatar_snapshot_defaults(mode)

    block_snapshots = Enum.map(sheet.blocks, &block_to_snapshot(&1, mode))
    default_avatar_asset_id = default_avatar_asset_id(avatar_snapshots)
    target_locales = LocalizationSnapshotCodec.active_target_locales(sheet.project_id)

    localization =
      LocalizationSnapshotCodec.capture(
        sheet.project_id,
        %{
          "sheet" => [sheet.id],
          "block" => Enum.map(sheet.blocks, & &1.id)
        },
        target_locales: target_locales
      )

    {hash_map, metadata_map} =
      resolve_snapshot_assets(
        mode,
        sheet,
        avatar_snapshots,
        block_snapshots,
        localization
      )

    snapshot = %{
      "original_id" => sheet.id,
      "name" => sheet.name,
      "shortcut" => sheet.shortcut,
      "description" => sheet.description,
      "avatar_asset_id" => default_avatar_asset_id,
      "avatars" => avatar_snapshots,
      "banner_asset_id" => sheet.banner_asset_id,
      "color" => sheet.color,
      "hidden_inherited_block_ids" => snapshot_hidden_inherited_block_ids(sheet, mode),
      "blocks" => block_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map,
      "localization" => localization,
      "localization_manifest" => LocalizationSnapshotCodec.manifest(localization, target_locales)
    }

    case mode do
      :strict -> ensure_valid_built_sheet_snapshot!(sheet, snapshot, target_locales)
      :capture -> snapshot
    end
  end

  defp resolve_snapshot_assets(:strict, sheet, avatar_snapshots, block_snapshots, _localization) do
    asset_ids = [sheet.banner_asset_id | snapshot_asset_ids(avatar_snapshots, block_snapshots)]

    {hash_map, metadata_map} =
      AssetHashResolver.resolve_hashes_for_project!(asset_ids, sheet.project_id)

    {hash_map, metadata_map}
  end

  defp resolve_snapshot_assets(:capture, sheet, avatar_snapshots, block_snapshots, localization) do
    references =
      [
        {sheet.banner_asset_id, capture_context(:sheet, sheet.id, "banner_asset_id", sheet.id)}
      ] ++
        Enum.map(avatar_snapshots, fn avatar ->
          {avatar["asset_id"], capture_context(:sheet_avatar, avatar["original_id"], "asset_id", sheet.id)}
        end) ++
        Enum.flat_map(block_snapshots, fn block ->
          Enum.map(Map.get(block, "gallery_images", []), fn image ->
            {image["asset_id"],
             capture_context(
               :block_gallery_image,
               image["original_id"],
               "asset_id",
               sheet.id
             )}
          end)
        end) ++
        Enum.map(localization, fn row ->
          {row["vo_asset_id"],
           capture_context(
             row["source_type"],
             row["source_id"],
             "vo_asset_id",
             sheet.id
           )}
        end)

    AssetHashResolver.resolve_hashes_for_project_capture(references, sheet.project_id)
  end

  defp capture_context(entity_type, entity_id, source_field, sheet_id) do
    %{
      entity_type: entity_type,
      entity_id: entity_id,
      source_field: source_field,
      container_type: :sheet,
      container_id: sheet_id
    }
  end

  defp ensure_valid_built_sheet_snapshot!(sheet, snapshot, target_locales) do
    result =
      with {:ok, localization} <-
             SheetLocalizationSnapshotValidator.complete_missing_rows(
               snapshot["localization"],
               snapshot,
               target_locales
             ),
           snapshot =
             snapshot
             |> Map.put("localization", localization)
             |> Map.put(
               "localization_manifest",
               LocalizationSnapshotCodec.manifest(localization, target_locales)
             ),
           :ok <- validate_portable_sheet_snapshot(snapshot),
           :ok <- validate_sheet_block_reference_ownership(sheet.project_id, snapshot) do
        with :ok <-
               validate_effective_sheet_inheritance_graph(
                 sheet.project_id,
                 snapshot["blocks"],
                 forbidden_sheet_id: sheet.id
               ) do
          {:ok, snapshot}
        end
      end

    case result do
      {:ok, snapshot} ->
        snapshot

      {:error, reason} ->
        raise ArgumentError,
              "cannot build an internally inconsistent sheet snapshot: #{inspect(reason)}"
    end
  end

  defp snapshot_asset_ids(avatar_snapshots, block_snapshots) do
    avatar_ids = Enum.map(avatar_snapshots, & &1["asset_id"])

    gallery_ids =
      block_snapshots
      |> Enum.flat_map(&Map.get(&1, "gallery_images", []))
      |> Enum.map(& &1["asset_id"])

    avatar_ids ++ gallery_ids
  end

  defp avatar_to_snapshot(%SheetAvatar{} = avatar) do
    %{
      "original_id" => avatar.id,
      "asset_id" => avatar.asset_id,
      "name" => avatar.name,
      "notes" => avatar.notes,
      "position" => avatar.position,
      "is_default" => avatar.is_default
    }
  end

  defp block_to_snapshot(%Block{} = block, mode) do
    base = %{
      "original_id" => block.id,
      "type" => block.type,
      "position" => block.position,
      "config" => block.config,
      "value" => block.value,
      "is_constant" => block.is_constant,
      "variable_name" => block.variable_name,
      "scope" => block.scope,
      "inherited_from_block_id" => block.inherited_from_block_id,
      "detached" => block.detached,
      "required" => block.required,
      "column_group_id" => block.column_group_id,
      "column_index" => block.column_index
    }

    base
    |> maybe_put_table_data(block, mode)
    |> maybe_put_gallery_images(block, mode)
  end

  defp maybe_put_table_data(snapshot, %Block{type: "table"} = block, _mode) do
    put_table_data(snapshot, block)
  end

  defp maybe_put_table_data(snapshot, block, :capture) do
    if sequence_present?(block.table_columns) or sequence_present?(block.table_rows),
      do: put_table_data(snapshot, block),
      else: snapshot
  end

  defp maybe_put_table_data(snapshot, _block, _mode), do: snapshot

  defp put_table_data(snapshot, block) do
    Map.put(snapshot, "table_data", %{
      "columns" => block.table_columns |> sort_positioned() |> Enum.map(&column_to_snapshot/1),
      "rows" => block.table_rows |> sort_positioned() |> Enum.map(&row_to_snapshot/1)
    })
  end

  defp maybe_put_gallery_images(snapshot, %Block{type: "gallery"} = block, _mode) do
    put_gallery_images(snapshot, block)
  end

  defp maybe_put_gallery_images(snapshot, block, :capture) do
    if sequence_present?(block.gallery_images), do: put_gallery_images(snapshot, block), else: snapshot
  end

  defp maybe_put_gallery_images(snapshot, _block, _mode), do: snapshot

  defp sequence_present?(value), do: is_list(value) and value != []

  defp put_gallery_images(snapshot, block) do
    Map.put(
      snapshot,
      "gallery_images",
      Enum.map(sorted_gallery_images(block.gallery_images), &gallery_image_to_snapshot/1)
    )
  end

  defp snapshot_hidden_inherited_block_ids(sheet, :capture), do: sheet.hidden_inherited_block_ids
  defp snapshot_hidden_inherited_block_ids(sheet, :strict), do: sheet.hidden_inherited_block_ids || []

  defp gallery_image_to_snapshot(%BlockGalleryImage{} = image) do
    %{
      "original_id" => image.id,
      "asset_id" => image.asset_id,
      "label" => image.label,
      "description" => image.description,
      "position" => image.position
    }
  end

  defp column_to_snapshot(%TableColumn{} = col) do
    %{
      "original_id" => col.id,
      "name" => col.name,
      "slug" => col.slug,
      "type" => col.type,
      "is_constant" => col.is_constant,
      "required" => col.required,
      "position" => col.position,
      "config" => col.config || %{}
    }
  end

  defp row_to_snapshot(%TableRow{} = row) do
    %{
      "original_id" => row.id,
      "name" => row.name,
      "slug" => row.slug,
      "position" => row.position,
      "cells" => row.cells || %{}
    }
  end

  # ========== Restore Snapshot ==========

  @doc false
  @spec validate_portable_snapshot(term()) :: :ok | {:error, term()}
  def validate_portable_snapshot(snapshot), do: validate_portable_sheet_snapshot(snapshot)

  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    with :ok <- validate_sheet_instantiation_localization(project_id, snapshot, opts) do
      opts
      |> MaterializationHelpers.with_asset_copy_tracker(fn tracked_opts ->
        AssetMaterializationScope.run(
          tracked_opts,
          &instantiate_sheet_snapshot_transaction(project_id, snapshot, &1)
        )
      end)
      |> finalize_sheet_instantiation(project_id)
    end
  end

  defp instantiate_sheet_snapshot_transaction(project_id, snapshot, opts) do
    MaterializationHelpers.with_project_storage_lock(project_id, fn ->
      instantiate_sheet_snapshot(project_id, snapshot, opts)
    end)
  end

  defp validate_sheet_instantiation_localization(_project_id, snapshot, opts) when is_map(snapshot) do
    if exact_materialization?(opts), do: :ok, else: validate_portable_snapshot(snapshot)
  end

  defp validate_sheet_instantiation_localization(_project_id, snapshot, _opts),
    do: {:error, {:invalid_snapshot, {:expected_map, snapshot}}}

  defp validate_portable_sheet_snapshot(snapshot) when is_map(snapshot) do
    blocks = snapshot["blocks"]
    avatars = snapshot["avatars"]
    localization = snapshot["localization"]

    with :ok <-
           validate_present_fields(
             snapshot,
             @sheet_snapshot_fields,
             :sheet,
             snapshot["original_id"]
           ),
         :ok <-
           validate_snapshot_root_id(
             snapshot["original_id"],
             snapshot["original_id"]
           ),
         :ok <- validate_snapshot_root_payload(snapshot),
         :ok <- validate_sheet_root_payload(snapshot),
         :ok <-
           validate_plain_ids(
             snapshot["hidden_inherited_block_ids"],
             :hidden_inherited_block
           ),
         :ok <- validate_snapshot_collections(blocks, avatars, localization),
         :ok <-
           LocalizationSnapshotCodec.validate_manifest(
             localization,
             snapshot["localization_manifest"]
           ),
         :ok <- validate_optional_child_field_presence(blocks, avatars),
         :ok <- validate_identified_entries(blocks, :block),
         :ok <- validate_identified_entries(avatars, :avatar),
         :ok <- validate_nested_snapshot_ids(blocks),
         :ok <- validate_snapshot_reference_ids(snapshot, blocks, avatars),
         :ok <- validate_snapshot_inheritance_graph(blocks),
         :ok <- validate_snapshot_unique_fields(blocks, avatars),
         :ok <- validate_snapshot_payload_types(blocks, avatars),
         :ok <- validate_avatar_default_cardinality(avatars),
         :ok <- validate_block_payloads(blocks) do
      SheetLocalizationSnapshotValidator.validate(localization, snapshot)
    end
  end

  defp validate_portable_sheet_snapshot(snapshot), do: {:error, {:invalid_snapshot, {:expected_map, snapshot}}}

  defp instantiate_sheet_snapshot(project_id, snapshot, opts) do
    now = MaterializationHelpers.now()
    blocks = snapshot["blocks"] || []

    with %Project{deleted_at: nil} <-
           Repo.one(
             from(project in Project,
               where: project.id == ^project_id,
               lock: "FOR UPDATE"
             )
           ),
         {:ok, locked_external_block_ids} <-
           lock_materialized_sheet_block_references(project_id, snapshot, opts),
         :ok <-
           maybe_validate_materialized_sheet_inheritance_graph(
             project_id,
             snapshot,
             locked_external_block_ids,
             opts
           ),
         :ok <- LocalizationVersionRestore.lock_inventory!(project_id),
         avatar_entries = build_avatar_entries(snapshot, project_id, now, opts),
         {:ok, sheet_id} <-
           MaterializationHelpers.insert_one_returning_id(
             Repo,
             Sheet,
             sheet_snapshot_attrs(project_id, snapshot, opts, now)
           ),
         {:ok, avatar_id_map} <- insert_sheet_avatars(sheet_id, avatar_entries),
         {:ok, block_id_map} <- insert_sheet_blocks(sheet_id, blocks, now),
         :ok <-
           remap_sheet_block_inheritance(
             blocks,
             block_id_map,
             project_id,
             locked_external_block_ids,
             opts
           ),
         :ok <-
           remap_hidden_inherited_block_ids(
             sheet_id,
             snapshot["hidden_inherited_block_ids"],
             block_id_map,
             project_id,
             locked_external_block_ids,
             opts
           ),
         :ok <- restore_table_data(Repo, block_id_map, blocks, now),
         :ok <- restore_gallery_images(Repo, block_id_map, snapshot, project_id, now, opts) do
      complete_sheet_instantiation(
        project_id,
        snapshot,
        sheet_id,
        block_id_map,
        avatar_id_map,
        opts
      )
    else
      nil -> Repo.rollback({:project_not_found, project_id})
      %Project{} -> Repo.rollback({:project_not_active, project_id})
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  # Exact-mode selection is shared across snapshot materializers.
  defp maybe_validate_materialized_sheet_inheritance_graph(project_id, snapshot, locked_external_block_ids, opts) do
    if exact_materialization?(opts),
      do: :ok,
      else: validate_materialized_sheet_inheritance_graph(project_id, snapshot, locked_external_block_ids, opts)
  end

  defp sheet_snapshot_attrs(project_id, snapshot, opts, now) do
    Map.merge(
      %{
        project_id: project_id,
        name: snapshot["name"],
        shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
        description: snapshot["description"],
        color: snapshot["color"],
        hidden_inherited_block_ids: [],
        banner_asset_id:
          resolve_sheet_asset(
            snapshot["banner_asset_id"],
            snapshot,
            project_id,
            opts,
            :banner
          ),
        parent_id: MaterializationHelpers.root_parent_id(opts),
        position: MaterializationHelpers.root_position(opts)
      },
      MaterializationHelpers.timestamps(now)
    )
  end

  defp lock_materialized_sheet_block_references(project_id, snapshot, opts) do
    internal_ids = MapSet.new(snapshot["blocks"], & &1["original_id"])

    candidate_ids =
      snapshot["blocks"]
      |> Enum.map(& &1["inherited_from_block_id"])
      |> Enum.concat(snapshot["hidden_inherited_block_ids"] || [])
      |> Enum.reject(&(is_nil(&1) or MapSet.member?(internal_ids, &1)))
      |> Enum.map(&materialized_external_block_candidate(&1, opts))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    rows =
      Repo.all(
        from(block in Block,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            block.id in ^candidate_ids and sheet.project_id == ^project_id and is_nil(block.deleted_at) and
              is_nil(sheet.deleted_at),
          select: {block.id, sheet.id}
        )
      )

    block_ids = rows |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    sheet_ids = rows |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    locked_sheet_ids =
      Repo.all(
        from(sheet in Sheet,
          where: sheet.id in ^sheet_ids and is_nil(sheet.deleted_at),
          order_by: [asc: sheet.id],
          lock: "FOR UPDATE",
          select: sheet.id
        )
      )

    locked_block_ids =
      from(block in Block,
        where:
          block.id in ^block_ids and block.sheet_id in ^locked_sheet_ids and
            is_nil(block.deleted_at),
        order_by: [asc: block.id],
        lock: "FOR UPDATE",
        select: block.id
      )
      |> Repo.all()
      |> MapSet.new()

    {:ok, locked_block_ids}
  end

  defp materialized_external_block_candidate(source_id, opts) do
    remapped_id =
      opts
      |> Keyword.get(:external_id_maps, %{})
      |> Map.get(:block, %{})
      |> Map.get(source_id)

    cond do
      is_integer(remapped_id) -> remapped_id
      MaterializationHelpers.preserve_external_refs?(opts) -> source_id
      true -> nil
    end
  end

  defp validate_materialized_sheet_inheritance_graph(project_id, snapshot, locked_external_block_ids, opts) do
    internal_ids = MapSet.new(snapshot["blocks"], & &1["original_id"])

    external_root_ids =
      snapshot["blocks"]
      |> Enum.map(& &1["inherited_from_block_id"])
      |> Enum.reject(&(is_nil(&1) or MapSet.member?(internal_ids, &1)))
      |> Enum.map(&materialized_external_block_candidate(&1, opts))
      |> Enum.filter(&MapSet.member?(locked_external_block_ids, &1))
      |> Enum.uniq()

    validate_locked_effective_inheritance_graph(
      project_id,
      external_root_ids,
      %{},
      nil
    )
  end

  defp complete_sheet_instantiation(project_id, snapshot, sheet_id, block_id_map, avatar_id_map, opts) do
    sheet =
      Sheet
      |> Repo.get!(sheet_id)
      |> Repo.preload([:banner_asset, :blocks, avatars: :asset], force: true)

    id_maps = %{
      sheet: MaterializationHelpers.root_id_map(snapshot, sheet_id),
      block: block_id_map,
      avatar: avatar_id_map
    }

    if Keyword.get(opts, :restore_localization, true) do
      complete_sheet_instantiation_with_localization(sheet, project_id, snapshot, id_maps, opts)
    else
      finish_sheet_instantiation(sheet, id_maps, project_id, opts)
    end
  end

  defp complete_sheet_instantiation_with_localization(sheet, project_id, snapshot, id_maps, opts) do
    with :ok <- restore_instantiated_sheet_localization(project_id, snapshot, id_maps, opts),
         :ok <- LocalizationVersionRestore.extract_sheet(sheet.id),
         :ok <- LocalizationVersionRestore.sync_sheet_names(project_id) do
      finish_sheet_instantiation(sheet, id_maps, project_id, opts)
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp finish_sheet_instantiation(sheet, id_maps, project_id, opts) do
    case rebuild_instantiated_sheet_references(sheet, project_id, opts) do
      :ok -> {sheet, id_maps}
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp rebuild_instantiated_sheet_references(sheet, project_id, opts) do
    if Keyword.get(opts, :rebuild_references, true) do
      do_rebuild_instantiated_sheet_references(sheet, project_id)
    else
      :ok
    end
  end

  defp do_rebuild_instantiated_sheet_references(sheet, project_id) do
    with :ok <-
           validate_each(
             sheet.blocks,
             &rebuild_instantiated_block_references(&1, project_id)
           ) do
      References.rebuild_project_variable_references(project_id)
    end
  end

  defp rebuild_instantiated_block_references(block, project_id) do
    case References.update_block_references(block, project_id: project_id) do
      :ok -> :ok
      {:error, _reason} = error -> error
      result -> {:error, {:unexpected_reference_reconcile_result, result}}
    end
  end

  defp restore_instantiated_sheet_localization(project_id, snapshot, id_maps, opts) do
    if Keyword.get(opts, :restore_localization, true) do
      localization =
        LocalizationSnapshotCodec.active_target_rows(
          project_id,
          Map.get(snapshot, "localization", [])
        )

      LocalizationVersionRestore.restore_sheet(
        project_id,
        localization,
        id_maps
      )
    else
      :ok
    end
  end

  defp finalize_sheet_instantiation(result, _project_id) do
    case result do
      {:ok, {sheet, id_maps}} ->
        {:ok, sheet, id_maps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_snapshot_root_id(sheet_id, sheet_id) when is_integer(sheet_id) and sheet_id > 0, do: :ok

  defp validate_snapshot_root_id(sheet_id, id) when is_integer(id) and id > 0,
    do: {:error, {:invalid_snapshot, {:root_id_mismatch, sheet_id, id}}}

  defp validate_snapshot_root_id(_sheet_id, id), do: {:error, {:invalid_snapshot, {:invalid_original_id, :sheet, id}}}

  defp validate_snapshot_root_payload(snapshot) do
    checks = [
      {"name", non_empty_string?(snapshot["name"])},
      {"shortcut", optional_string?(snapshot["shortcut"])},
      {"description", optional_string?(snapshot["description"])},
      {"avatar_asset_id", optional_positive_integer?(snapshot["avatar_asset_id"])},
      {"banner_asset_id", optional_positive_integer?(snapshot["banner_asset_id"])},
      {"color", optional_string?(snapshot["color"])},
      {"asset_blob_hashes", is_map(snapshot["asset_blob_hashes"])},
      {"asset_metadata", is_map(snapshot["asset_metadata"])},
      {"localization_manifest", is_map(snapshot["localization_manifest"])}
    ]

    validate_payload_checks(snapshot, :sheet, snapshot["original_id"], checks)
  end

  defp validate_sheet_root_payload(snapshot) do
    changeset =
      Sheet.create_changeset(%Sheet{project_id: 1}, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        description: snapshot["description"],
        color: snapshot["color"],
        banner_asset_id: snapshot["banner_asset_id"],
        hidden_inherited_block_ids: snapshot["hidden_inherited_block_ids"]
      })

    if changeset.valid? do
      :ok
    else
      {:error,
       {:invalid_snapshot,
        {:invalid_root_payload, :sheet, snapshot["original_id"],
         Ecto.Changeset.traverse_errors(changeset, &format_changeset_error/1)}}}
    end
  end

  defp validate_snapshot_collections(blocks, avatars, localization) do
    with :ok <- validate_map_list(blocks, :blocks),
         :ok <- validate_map_list(avatars, :avatars),
         :ok <- validate_map_list(localization, :localization) do
      validate_each(blocks, &validate_block_collections/1)
    end
  end

  defp validate_optional_child_field_presence(blocks, avatars) do
    with :ok <-
           validate_present_fields_for_entries(
             blocks,
             @restored_optional_block_fields,
             :block
           ),
         :ok <-
           validate_present_fields_for_entries(
             avatars,
             @restored_optional_avatar_fields,
             :avatar
           ) do
      validate_present_fields_for_entries(
        gallery_images(blocks),
        @restored_optional_gallery_image_fields,
        :gallery_image
      )
    end
  end

  defp validate_present_fields_for_entries(entries, fields, kind) do
    validate_each(entries, fn entry ->
      validate_present_fields(entry, fields, kind, entry["original_id"])
    end)
  end

  defp validate_present_fields(entry, fields, kind, id) do
    case Enum.find(fields, &(not Map.has_key?(entry, &1))) do
      nil -> :ok
      field -> {:error, {:invalid_snapshot, {:missing_field, kind, id, field}}}
    end
  end

  defp validate_block_collections(block) do
    with :ok <- validate_table_collection(block) do
      validate_gallery_collection(block)
    end
  end

  defp validate_map_list(value, label) when is_list(value) do
    if Enum.all?(value, &is_map/1),
      do: :ok,
      else: {:error, {:invalid_snapshot, {:expected_map_entries, label}}}
  end

  defp validate_map_list(_value, label), do: {:error, {:invalid_snapshot, {:expected_list, label}}}

  defp validate_table_collection(%{"type" => "table", "table_data" => table_data}) when is_map(table_data) do
    with :ok <- validate_map_list(table_data["columns"], :table_columns) do
      validate_map_list(table_data["rows"], :table_rows)
    end
  end

  defp validate_table_collection(%{"type" => "table"}), do: {:error, {:invalid_snapshot, :missing_table_data}}

  defp validate_table_collection(_block), do: :ok

  defp validate_gallery_collection(%{"type" => "gallery"} = block) do
    validate_map_list(block["gallery_images"], :gallery_images)
  end

  defp validate_gallery_collection(_block), do: :ok

  defp validate_nested_snapshot_ids(blocks) do
    with :ok <- validate_identified_entries(table_columns(blocks), :table_column),
         :ok <- validate_identified_entries(table_rows(blocks), :table_row) do
      validate_identified_entries(gallery_images(blocks), :gallery_image)
    end
  end

  defp validate_identified_entries(entries, kind) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {entry, index}, {:ok, seen} ->
      id = entry["original_id"]

      cond do
        not (is_integer(id) and id > 0) ->
          {:halt, {:error, {:invalid_snapshot, {:invalid_original_id, kind, index, id}}}}

        MapSet.member?(seen, id) ->
          {:halt, {:error, {:invalid_snapshot, {:duplicate_original_id, kind, id}}}}

        true ->
          {:cont, {:ok, MapSet.put(seen, id)}}
      end
    end)
    |> case do
      {:ok, _seen} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_plain_ids(ids, kind) when is_list(ids) do
    ids
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, MapSet.new()}, fn {id, index}, {:ok, seen} ->
      cond do
        not (is_integer(id) and id > 0) ->
          {:halt, {:error, {:invalid_snapshot, {:invalid_id, kind, index, id}}}}

        MapSet.member?(seen, id) ->
          {:halt, {:error, {:invalid_snapshot, {:duplicate_id, kind, id}}}}

        true ->
          {:cont, {:ok, MapSet.put(seen, id)}}
      end
    end)
    |> case do
      {:ok, _seen} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_plain_ids(_ids, kind), do: {:error, {:invalid_snapshot, {:expected_id_list, kind}}}

  defp validate_snapshot_reference_ids(snapshot, blocks, avatars) do
    avatar_asset_ids = Enum.map(avatars, & &1["asset_id"])
    gallery_asset_ids = Enum.map(gallery_images(blocks), & &1["asset_id"])
    inherited_ids = blocks |> Enum.map(& &1["inherited_from_block_id"]) |> Enum.reject(&is_nil/1)

    with :ok <- validate_optional_id(snapshot["banner_asset_id"], :banner_asset),
         :ok <- validate_positive_ids(avatar_asset_ids, :avatar_asset),
         :ok <- validate_positive_ids(gallery_asset_ids, :gallery_asset) do
      validate_positive_ids(inherited_ids, :inherited_block)
    end
  end

  defp validate_snapshot_inheritance_graph(blocks) do
    ids = MapSet.new(blocks, & &1["original_id"])

    parent_by_id =
      Map.new(blocks, fn block ->
        parent_id = block["inherited_from_block_id"]
        {block["original_id"], if(MapSet.member?(ids, parent_id), do: parent_id)}
      end)

    case Enum.find(Map.keys(parent_by_id), &snapshot_inheritance_cycle?(&1, parent_by_id, MapSet.new())) do
      nil -> :ok
      block_id -> {:error, {:invalid_snapshot, {:inheritance_cycle, block_id}}}
    end
  end

  defp snapshot_inheritance_cycle?(nil, _parent_by_id, _seen), do: false

  defp snapshot_inheritance_cycle?(block_id, parent_by_id, seen) do
    if MapSet.member?(seen, block_id) do
      true
    else
      snapshot_inheritance_cycle?(
        Map.get(parent_by_id, block_id),
        parent_by_id,
        MapSet.put(seen, block_id)
      )
    end
  end

  defp validate_optional_id(nil, _kind), do: :ok
  defp validate_optional_id(id, _kind) when is_integer(id) and id > 0, do: :ok

  defp validate_optional_id(id, kind), do: {:error, {:invalid_snapshot, {:invalid_id, kind, id}}}

  defp validate_positive_ids(ids, kind) do
    case ids |> Enum.with_index() |> Enum.find(fn {id, _index} -> not (is_integer(id) and id > 0) end) do
      nil -> :ok
      {id, index} -> {:error, {:invalid_snapshot, {:invalid_id, kind, index, id}}}
    end
  end

  defp validate_snapshot_unique_fields(blocks, avatars) do
    with :ok <- validate_unique_values(blocks, "variable_name", :block_variable_name, true),
         :ok <- validate_unique_values(avatars, "asset_id", :avatar_asset_id, false) do
      validate_each(blocks, &validate_block_unique_fields/1)
    end
  end

  defp validate_block_unique_fields(%{"type" => "table"} = block) do
    table_data = block["table_data"]

    with :ok <-
           validate_unique_values(
             table_data["columns"],
             "slug",
             {:table_column_slug, block["original_id"]},
             false
           ) do
      validate_unique_values(
        table_data["rows"],
        "slug",
        {:table_row_slug, block["original_id"]},
        false
      )
    end
  end

  defp validate_block_unique_fields(%{"type" => "gallery"} = block) do
    validate_unique_values(
      block["gallery_images"],
      "asset_id",
      {:gallery_asset_id, block["original_id"]},
      false
    )
  end

  defp validate_block_unique_fields(_block), do: :ok

  defp validate_unique_values(entries, key, kind, allow_nil?) do
    entries
    |> Enum.reduce_while(MapSet.new(), fn entry, seen ->
      value = entry[key]

      cond do
        is_nil(value) and allow_nil? ->
          {:cont, seen}

        is_nil(value) ->
          {:halt, {:error, {:invalid_snapshot, {:missing_value, kind}}}}

        MapSet.member?(seen, value) ->
          {:halt, {:error, {:invalid_snapshot, {:duplicate_value, kind, value}}}}

        true ->
          {:cont, MapSet.put(seen, value)}
      end
    end)
    |> case do
      %MapSet{} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_snapshot_payload_types(blocks, avatars) do
    with :ok <- validate_entry_payloads(blocks, :block, &block_payload_checks/1),
         :ok <- validate_entry_payloads(avatars, :avatar, &avatar_payload_checks/1),
         :ok <- validate_entry_payloads(table_columns(blocks), :table_column, &column_payload_checks/1),
         :ok <- validate_entry_payloads(table_rows(blocks), :table_row, &row_payload_checks/1) do
      validate_entry_payloads(gallery_images(blocks), :gallery_image, &gallery_payload_checks/1)
    end
  end

  defp validate_entry_payloads(entries, kind, checks_fun) do
    validate_each(entries, &validate_entry_payload(&1, kind, checks_fun))
  end

  defp validate_entry_payload(entry, kind, checks_fun) do
    validate_payload_checks(entry, kind, entry["original_id"], checks_fun.(entry))
  end

  defp validate_payload_checks(entry, kind, id, checks) do
    case Enum.find(checks, fn {_field, valid?} -> not valid? end) do
      nil ->
        :ok

      {field, false} ->
        {:error, {:invalid_snapshot, {:invalid_payload, kind, id, field, entry[field]}}}
    end
  end

  defp validate_each(entries, validation_fun) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case validation_fun.(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp block_payload_checks(block) do
    [
      {"position", non_negative_integer?(block["position"])},
      {"config", is_map(block["config"])},
      {"value", is_map(block["value"])},
      {"is_constant", is_boolean(block["is_constant"])},
      {"variable_name", optional_string?(block["variable_name"])},
      {"scope", is_binary(block["scope"])},
      {"detached", is_boolean(block["detached"])},
      {"required", is_boolean(block["required"])},
      {"column_group_id", valid_optional_uuid?(block["column_group_id"])},
      {"column_index", block["column_index"] in 0..2}
    ]
  end

  defp avatar_payload_checks(avatar) do
    [
      {"name", optional_string?(avatar["name"])},
      {"notes", optional_string?(avatar["notes"])},
      {"position", non_negative_integer?(avatar["position"])},
      {"is_default", is_boolean(avatar["is_default"])}
    ]
  end

  defp validate_avatar_default_cardinality([]), do: :ok

  defp validate_avatar_default_cardinality(avatars) do
    default_count = Enum.count(avatars, &(&1["is_default"] == true))

    if default_count == 1 do
      :ok
    else
      {:error, {:invalid_snapshot, {:avatar_default_cardinality, 1, default_count}}}
    end
  end

  defp column_payload_checks(column) do
    [
      {"name", non_empty_string?(column["name"])},
      {"slug", non_empty_string?(column["slug"])},
      {"type", column["type"] in TableColumn.types()},
      {"is_constant", is_boolean(column["is_constant"])},
      {"required", is_boolean(column["required"])},
      {"position", non_negative_integer?(column["position"])},
      {"config", is_map(column["config"])}
    ]
  end

  defp row_payload_checks(row) do
    [
      {"name", non_empty_string?(row["name"])},
      {"slug", non_empty_string?(row["slug"])},
      {"position", non_negative_integer?(row["position"])},
      {"cells", is_map(row["cells"])}
    ]
  end

  defp gallery_payload_checks(image) do
    [
      {"label", optional_string?(image["label"])},
      {"description", optional_string?(image["description"])},
      {"position", non_negative_integer?(image["position"])}
    ]
  end

  defp optional_string?(value), do: is_nil(value) or is_binary(value)
  defp optional_positive_integer?(value), do: is_nil(value) or (is_integer(value) and value > 0)
  defp non_empty_string?(value), do: is_binary(value) and value != ""
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp valid_optional_uuid?(nil), do: true
  defp valid_optional_uuid?(value), do: match?({:ok, _uuid}, Ecto.UUID.cast(value))

  defp validate_block_payloads(blocks) do
    Enum.reduce_while(blocks, :ok, fn block_data, :ok ->
      changeset =
        Block.create_changeset(
          %Block{},
          block_restore_attrs(block_data)
        )

      if changeset.valid? do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          {:invalid_snapshot,
           {:invalid_block, block_data["original_id"],
            Ecto.Changeset.traverse_errors(changeset, &format_changeset_error/1)}}}}
      end
    end)
  end

  defp format_changeset_error({message, opts}) do
    Enum.reduce(opts, message, fn {key, value}, formatted ->
      replacement = if is_binary(value), do: value, else: inspect(value)
      String.replace(formatted, "%{#{key}}", replacement)
    end)
  end

  defp validate_sheet_block_reference_ownership(project_id, snapshot) do
    reference_ids =
      snapshot["blocks"]
      |> Enum.map(& &1["inherited_from_block_id"])
      |> Enum.concat(snapshot["hidden_inherited_block_ids"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    valid_ids =
      from(block in Block,
        join: owner_sheet in Sheet,
        on: owner_sheet.id == block.sheet_id,
        where:
          block.id in ^reference_ids and owner_sheet.project_id == ^project_id and
            is_nil(block.deleted_at) and is_nil(owner_sheet.deleted_at),
        select: block.id
      )
      |> Repo.all()
      |> MapSet.new()

    case Enum.find(reference_ids, &(not MapSet.member?(valid_ids, &1))) do
      nil -> :ok
      id -> {:error, {:invalid_snapshot, {:invalid_block_reference, id}}}
    end
  end

  defp validate_effective_sheet_inheritance_graph(project_id, blocks, opts) do
    proposed_parents =
      Map.new(blocks, fn block ->
        {block["original_id"], block["inherited_from_block_id"]}
      end)

    validate_locked_effective_inheritance_graph(
      project_id,
      Map.keys(proposed_parents),
      proposed_parents,
      Keyword.get(opts, :forbidden_sheet_id)
    )
  end

  defp validate_locked_effective_inheritance_graph(project_id, root_ids, proposed_parents, forbidden_sheet_id) do
    initial_state = %{
      complete: MapSet.new(),
      external_parents: %{}
    }

    root_ids
    |> Enum.sort()
    |> Enum.reduce_while({:ok, initial_state}, fn root_id, {:ok, state} ->
      case walk_effective_inheritance(
             root_id,
             project_id,
             proposed_parents,
             forbidden_sheet_id,
             MapSet.new(),
             state
           ) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, _state} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp walk_effective_inheritance(nil, _project_id, _proposed_parents, _forbidden_sheet_id, _path, state),
    do: {:ok, state}

  defp walk_effective_inheritance(block_id, project_id, proposed_parents, forbidden_sheet_id, path, state) do
    cond do
      MapSet.member?(path, block_id) ->
        {:error, {:invalid_snapshot, {:inheritance_cycle, block_id}}}

      MapSet.member?(state.complete, block_id) ->
        {:ok, state}

      true ->
        with {:ok, parent_id, state} <-
               effective_inheritance_parent(
                 block_id,
                 project_id,
                 proposed_parents,
                 forbidden_sheet_id,
                 state
               ),
             {:ok, state} <-
               walk_effective_inheritance(
                 parent_id,
                 project_id,
                 proposed_parents,
                 forbidden_sheet_id,
                 MapSet.put(path, block_id),
                 state
               ) do
          {:ok, %{state | complete: MapSet.put(state.complete, block_id)}}
        end
    end
  end

  defp effective_inheritance_parent(block_id, project_id, proposed_parents, forbidden_sheet_id, state) do
    case Map.fetch(proposed_parents, block_id) do
      {:ok, parent_id} ->
        {:ok, parent_id, state}

      :error ->
        locked_external_inheritance_parent(
          block_id,
          project_id,
          forbidden_sheet_id,
          state
        )
    end
  end

  defp locked_external_inheritance_parent(block_id, project_id, forbidden_sheet_id, state) do
    case Map.fetch(state.external_parents, block_id) do
      {:ok, parent_id} ->
        {:ok, parent_id, state}

      :error ->
        lock_external_inheritance_parent(
          block_id,
          project_id,
          forbidden_sheet_id,
          state
        )
    end
  end

  defp lock_external_inheritance_parent(block_id, project_id, forbidden_sheet_id, state) do
    row =
      Repo.one(
        from(block in Block,
          join: owner_sheet in Sheet,
          on: owner_sheet.id == block.sheet_id,
          where:
            block.id == ^block_id and owner_sheet.project_id == ^project_id and
              is_nil(block.deleted_at) and is_nil(owner_sheet.deleted_at),
          lock: "FOR UPDATE",
          select: {block.inherited_from_block_id, owner_sheet.id}
        )
      )

    case row do
      nil ->
        {:error, {:invalid_snapshot, {:invalid_block_reference, block_id}}}

      {_parent_id, ^forbidden_sheet_id} when not is_nil(forbidden_sheet_id) ->
        {:error, {:invalid_snapshot, {:same_sheet_external_block_reference, block_id}}}

      {parent_id, _owner_sheet_id} ->
        state = put_in(state, [:external_parents, block_id], parent_id)
        {:ok, parent_id, state}
    end
  end

  defp table_columns(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "table"))
    |> Enum.flat_map(&get_in(&1, ["table_data", "columns"]))
  end

  defp table_rows(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "table"))
    |> Enum.flat_map(&get_in(&1, ["table_data", "rows"]))
  end

  defp gallery_images(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "gallery"))
    |> Enum.flat_map(&Map.get(&1, "gallery_images", []))
  end

  defp block_restore_attrs(block_data) do
    %{
      type: block_data["type"],
      position: block_data["position"],
      config: block_data["config"],
      value: block_data["value"],
      word_count: WordCount.for_block(block_data["type"], block_data["value"]),
      is_constant: block_data["is_constant"],
      variable_name: block_data["variable_name"],
      scope: block_data["scope"],
      inherited_from_block_id: nil,
      detached: block_data["detached"],
      required: block_data["required"],
      column_group_id: block_data["column_group_id"],
      column_index: block_data["column_index"],
      deleted_at: nil
    }
  end

  defp restore_table_data(repo, block_id_map, blocks_data, now) do
    blocks_data
    |> Enum.filter(&(&1["type"] == "table" && is_map(&1["table_data"])))
    |> Enum.reduce_while(:ok, fn block_data, :ok ->
      case Map.fetch(block_id_map, block_data["original_id"]) do
        {:ok, block_id} ->
          insert_table_data(repo, block_id, block_data["table_data"], now)
          {:cont, :ok}

        :error ->
          {:halt, {:error, {:missing_materialized_block, block_data["original_id"]}}}
      end
    end)
  end

  defp insert_table_data(repo, block_id, table_data, now) do
    columns = Map.get(table_data, "columns", [])

    if columns != [] do
      column_entries =
        Enum.map(columns, fn col ->
          %{
            block_id: block_id,
            name: col["name"],
            slug: col["slug"],
            type: col["type"],
            is_constant: col["is_constant"] || false,
            required: col["required"] || false,
            position: col["position"] || 0,
            config: col["config"] || %{},
            inserted_at: now,
            updated_at: now
          }
        end)

      repo.insert_all(TableColumn, column_entries)
    end

    rows = Map.get(table_data, "rows", [])

    if rows != [] do
      row_entries =
        Enum.map(rows, fn row ->
          %{
            block_id: block_id,
            name: row["name"],
            slug: row["slug"],
            position: row["position"] || 0,
            cells: row["cells"] || %{},
            inserted_at: now,
            updated_at: now
          }
        end)

      repo.insert_all(TableRow, row_entries)
    end
  end

  defp restore_gallery_images(repo, block_id_map, snapshot, project_id, now, opts) do
    entries =
      snapshot
      |> Map.get("blocks", [])
      |> Enum.flat_map(fn block_data ->
        block_id = Map.get(block_id_map, block_data["original_id"])
        gallery_image_entries(block_id, block_data, snapshot, project_id, now, opts)
      end)

    MaterializationHelpers.insert_all(repo, BlockGalleryImage, entries)
  end

  defp gallery_image_entries(nil, _block_data, _snapshot, _project_id, _now, _opts), do: []

  defp gallery_image_entries(_block_id, %{"type" => type}, _snapshot, _project_id, _now, _opts) when type != "gallery",
    do: []

  defp gallery_image_entries(block_id, block_data, snapshot, project_id, now, opts) do
    block_data
    |> Map.get("gallery_images", [])
    |> Enum.map(fn image_data ->
      gallery_image_entry(image_data, block_id, snapshot, project_id, now, opts)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp gallery_image_entry(image_data, block_id, snapshot, project_id, now, opts) do
    case resolve_sheet_asset(
           image_data["asset_id"],
           snapshot,
           project_id,
           opts,
           :gallery_image
         ) do
      nil ->
        nil

      asset_id ->
        %{
          block_id: block_id,
          asset_id: asset_id,
          label: image_data["label"],
          description: image_data["description"],
          position: image_data["position"] || 0,
          inserted_at: now,
          updated_at: now
        }
    end
  end

  defp insert_sheet_blocks(_sheet_id, [], _now), do: {:ok, %{}}

  defp insert_sheet_blocks(sheet_id, blocks_data, now) do
    Enum.reduce_while(blocks_data, {:ok, %{}}, fn block_data, {:ok, block_id_map} ->
      case MaterializationHelpers.insert_one_returning_id(
             Repo,
             Block,
             materialized_block_entry(block_data, sheet_id, now)
           ) do
        {:ok, block_id} ->
          {:cont, {:ok, Map.put(block_id_map, block_data["original_id"], block_id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp materialized_block_entry(block_data, sheet_id, now) do
    Map.merge(
      %{
        sheet_id: sheet_id,
        type: block_data["type"],
        position: block_data["position"],
        config: block_data["config"] || %{},
        value: block_data["value"] || %{},
        word_count: WordCount.for_block(block_data["type"], block_data["value"] || %{}),
        is_constant: block_data["is_constant"] || false,
        variable_name: block_data["variable_name"],
        scope: block_data["scope"] || "self",
        # Insert with nil inheritance: cross-sheet `inherited_from_block_id`
        # references a block in another sheet whose new id isn't known yet
        # (the FK is non-deferrable and checked at insert). The correct value
        # is set afterward by remap_sheet_block_inheritance/4 and the global
        # remap_block_inheritance/2 in ProjectRecovery once every sheet's
        # blocks have new ids.
        inherited_from_block_id: nil,
        detached: block_data["detached"] || false,
        required: block_data["required"] || false,
        column_group_id: block_data["column_group_id"],
        column_index: block_data["column_index"] || 0
      },
      MaterializationHelpers.timestamps(now)
    )
  end

  defp remap_sheet_block_inheritance(blocks_data, block_id_map, project_id, locked_external_block_ids, opts) do
    Enum.reduce_while(blocks_data, :ok, fn block_data, :ok ->
      case remap_materialized_block_inheritance(
             block_data,
             block_id_map,
             project_id,
             locked_external_block_ids,
             opts
           ) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp remap_materialized_block_inheritance(block_data, block_id_map, project_id, locked_external_block_ids, opts) do
    with {:ok, block_id} <- fetch_materialized_block_id(block_data, block_id_map) do
      remapped =
        resolve_materialized_block_reference(
          block_data["inherited_from_block_id"],
          block_id_map,
          project_id,
          locked_external_block_ids,
          opts
        )

      update_inherited_from_block(block_id, remapped)
    end
  end

  defp fetch_materialized_block_id(block_data, block_id_map) do
    case Map.fetch(block_id_map, block_data["original_id"]) do
      {:ok, block_id} -> {:ok, block_id}
      :error -> {:error, {:missing_materialized_block, block_data["original_id"]}}
    end
  end

  defp remap_hidden_inherited_block_ids(sheet_id, source_ids, block_id_map, project_id, locked_external_block_ids, opts) do
    remapped_ids =
      if exact_materialization?(opts) and is_nil(source_ids) do
        nil
      else
        source_ids
        |> Enum.map(
          &resolve_materialized_block_reference(
            &1,
            block_id_map,
            project_id,
            locked_external_block_ids,
            opts
          )
        )
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
      end

    case Repo.update_all(
           from(sheet in Sheet, where: sheet.id == ^sheet_id),
           set: [hidden_inherited_block_ids: remapped_ids]
         ) do
      {1, _} -> :ok
      result -> {:error, {:sheet_hidden_inheritance_update_failed, result}}
    end
  end

  defp resolve_materialized_block_reference(nil, _block_id_map, _project_id, _locked_external_block_ids, _opts), do: nil

  defp resolve_materialized_block_reference(source_id, block_id_map, _project_id, locked_external_block_ids, opts) do
    case Map.fetch(block_id_map, source_id) do
      {:ok, block_id} ->
        block_id

      :error ->
        candidate_id =
          opts
          |> Keyword.get(:external_id_maps, %{})
          |> Map.get(:block, %{})
          |> Map.get(source_id)

        candidate_id =
          cond do
            is_integer(candidate_id) -> candidate_id
            MaterializationHelpers.preserve_external_refs?(opts) -> source_id
            true -> nil
          end

        if MapSet.member?(locked_external_block_ids, candidate_id), do: candidate_id
    end
  end

  defp resolve_sheet_asset(asset_id, snapshot, project_id, opts, asset_context) do
    case sheet_asset_mode(opts) do
      :drop ->
        nil

      asset_mode ->
        resolution_opts =
          opts
          |> MaterializationHelpers.asset_resolution_opts(asset_mode, project_id)
          |> Keyword.put(:expected_content_type_prefix, "image/")
          |> Keyword.put(:asset_context, asset_context)

        AssetHashResolver.resolve_asset_fk(
          asset_id,
          snapshot,
          project_id,
          Keyword.get(opts, :user_id),
          resolution_opts
        )
    end
  end

  defp sheet_asset_mode(opts) do
    Keyword.get(opts, :asset_mode, :reuse)
  end

  defp default_avatar_asset_id(avatars) when is_list(avatars) do
    case Enum.find(avatars, &(&1["is_default"] == true)) do
      %{"asset_id" => id} -> id
      _ -> nil
    end
  end

  defp default_avatar_asset_id(_), do: nil

  defp normalize_avatar_snapshot_defaults([]), do: []

  defp normalize_avatar_snapshot_defaults(avatars) do
    default =
      avatars
      |> Enum.filter(&(&1["is_default"] == true))
      |> case do
        [] -> Enum.min_by(avatars, &avatar_snapshot_order_key/1)
        defaults -> Enum.min_by(defaults, &avatar_snapshot_order_key/1)
      end

    Enum.map(avatars, &Map.put(&1, "is_default", &1["original_id"] == default["original_id"]))
  end

  defp maybe_normalize_avatar_snapshot_defaults(avatars, :strict), do: normalize_avatar_snapshot_defaults(avatars)

  defp maybe_normalize_avatar_snapshot_defaults(avatars, :capture), do: avatars

  defp avatar_snapshot_order_key(avatar) do
    {
      avatar["position"] || 0,
      avatar["original_id"] || 0,
      avatar["asset_id"] || 0
    }
  end

  defp sorted_avatars(avatars) when is_list(avatars) do
    Enum.sort_by(avatars, &{&1.position || 0, &1.id || 0})
  end

  defp sorted_avatars(_avatars), do: []

  defp sorted_gallery_images(images) when is_list(images) do
    Enum.sort_by(images, &{&1.position || 0, &1.id || 0})
  end

  defp sorted_gallery_images(_images), do: []

  defp sort_positioned(records) when is_list(records) do
    Enum.sort_by(records, &{&1.position || 0, &1.id || 0})
  end

  defp build_avatar_entries(snapshot, project_id, now, opts) do
    entries =
      snapshot
      |> avatar_snapshots()
      |> Enum.map(&avatar_entry(&1, snapshot, project_id, now, opts))
      |> Enum.reject(&is_nil/1)

    if exact_materialization?(opts), do: entries, else: ensure_default_avatar(entries)
  end

  defp avatar_snapshots(%{"avatars" => avatars}) when is_list(avatars) and avatars != [] do
    avatars
  end

  defp avatar_snapshots(%{"avatar_asset_id" => asset_id}) when not is_nil(asset_id) do
    [%{"asset_id" => asset_id, "position" => 0, "is_default" => true}]
  end

  defp avatar_snapshots(_snapshot), do: []

  defp avatar_entry(avatar_data, snapshot, project_id, now, opts) do
    case resolve_sheet_asset(
           avatar_data["asset_id"],
           snapshot,
           project_id,
           opts,
           :avatar
         ) do
      nil ->
        nil

      asset_id ->
        %{
          original_id: avatar_data["original_id"],
          asset_id: asset_id,
          name: avatar_data["name"],
          notes: avatar_data["notes"],
          position: avatar_data["position"] || 0,
          is_default: avatar_data["is_default"] || false,
          inserted_at: now,
          updated_at: now
        }
    end
  end

  defp ensure_default_avatar([]), do: []

  defp ensure_default_avatar(entries) do
    default_index =
      case Enum.find_index(entries, & &1.is_default) do
        nil -> 0
        index -> index
      end

    entries
    |> Enum.with_index()
    |> Enum.map(fn {entry, index} -> %{entry | is_default: index == default_index} end)
  end

  defp insert_sheet_avatars(_sheet_id, []), do: {:ok, %{}}

  defp insert_sheet_avatars(sheet_id, avatar_entries) do
    Enum.reduce_while(avatar_entries, {:ok, %{}}, fn entry, {:ok, id_map} ->
      {original_id, attrs} = Map.pop(entry, :original_id)
      attrs = Map.put(attrs, :sheet_id, sheet_id)

      case MaterializationHelpers.insert_one_returning_id(Repo, SheetAvatar, attrs) do
        {:ok, avatar_id} ->
          {:cont, {:ok, put_avatar_id_map(id_map, original_id, avatar_id)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp put_avatar_id_map(id_map, original_id, avatar_id) when is_integer(original_id) do
    Map.put(id_map, original_id, avatar_id)
  end

  defp put_avatar_id_map(id_map, _original_id, _avatar_id), do: id_map

  defp update_inherited_from_block(block_id, remapped) do
    case Repo.update_all(from(b in Block, where: b.id == ^block_id),
           set: [inherited_from_block_id: remapped]
         ) do
      {1, _} -> :ok
      _ -> {:error, :inheritance_remap_failed}
    end
  end

  # ========== Diff Snapshots ==========

  @block_compare_fields ~w(
    type config value is_constant variable_name scope required detached
    inherited_from_block_id column_group_id column_index table_data gallery_images
  )

  def diff_snapshots(old_snapshot, new_snapshot) do
    []
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "name",
      :property,
      dgettext("sheets", "Renamed sheet")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "shortcut",
      :property,
      dgettext("sheets", "Changed shortcut")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "description",
      :property,
      dgettext("sheets", "Changed description")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "color",
      :property,
      dgettext("sheets", "Changed color")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "avatar_asset_id",
      :property,
      dgettext("sheets", "Changed avatar")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "avatars",
      :property,
      dgettext("sheets", "Changed avatars")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "banner_asset_id",
      :property,
      dgettext("sheets", "Changed banner")
    )
    |> DiffHelpers.check_field_change(
      old_snapshot,
      new_snapshot,
      "hidden_inherited_block_ids",
      :property,
      dgettext("sheets", "Changed hidden inherited blocks")
    )
    |> diff_blocks(old_snapshot["blocks"] || [], new_snapshot["blocks"] || [])
    |> Enum.reverse()
  end

  defp diff_blocks(changes, old_blocks, new_blocks) do
    key_fns = [
      # Snapshot identity is authoritative for version restore and survives
      # variable renames and duplicate positions.
      & &1["original_id"]
    ]

    {matched, added, removed} = DiffHelpers.match_by_keys(old_blocks, new_blocks, key_fns)

    {modified, _unchanged} =
      DiffHelpers.find_modified(matched, fn old, new ->
        DiffHelpers.fields_differ?(old, new, @block_compare_fields)
      end)

    changes
    |> append_block_list(added, :added)
    |> append_block_list(removed, :removed)
    |> append_block_list_modified(modified)
  end

  defp append_block_list(changes, [], _action), do: changes

  defp append_block_list(changes, blocks, action) do
    Enum.reduce(blocks, changes, fn block, acc ->
      detail = block_detail(action, block)
      [%{category: :block, action: action, detail: detail} | acc]
    end)
  end

  defp append_block_list_modified(changes, []), do: changes

  defp append_block_list_modified(changes, modified_pairs) do
    Enum.reduce(modified_pairs, changes, fn {_old, new}, acc ->
      detail = block_detail(:modified, new)
      [%{category: :block, action: :modified, detail: detail} | acc]
    end)
  end

  defp block_detail(action, block) do
    type = block["type"] || "unknown"
    name = block["variable_name"]

    case {action, name} do
      {:added, nil} ->
        dgettext("sheets", "Added %{type} block", type: type)

      {:added, name} ->
        dgettext("sheets", "Added %{type} block \"%{name}\"", type: type, name: name)

      {:removed, nil} ->
        dgettext("sheets", "Removed %{type} block", type: type)

      {:removed, name} ->
        dgettext("sheets", "Removed %{type} block \"%{name}\"", type: type, name: name)

      {:modified, nil} ->
        dgettext("sheets", "Modified %{type} block", type: type)

      {:modified, name} ->
        dgettext("sheets", "Modified %{type} block \"%{name}\"", type: type, name: name)
    end
  end
end
