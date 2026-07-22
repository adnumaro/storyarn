defmodule Storyarn.Versioning.Builders.SheetBuilder do
  @moduledoc """
  Snapshot builder for sheets.

  Captures sheet metadata (name, shortcut, avatars, banner) and all blocks
  with their type, config, value, position, variable settings, table data, and
  gallery images.
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  use Gettext, backend: Storyarn.Gettext

  import Ecto.Query, warn: false

  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizableWords
  alias Storyarn.Localization.TextCrud
  alias Storyarn.Projects.Project
  alias Storyarn.References
  alias Storyarn.References.AvatarIntegrity
  alias Storyarn.Repo
  alias Storyarn.Shared.WordCount
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.PropertyInheritance
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Versioning.AssetMaterializationScope
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.EntityVersion
  alias Storyarn.Versioning.LocalizationSnapshotCodec
  alias Storyarn.Versioning.MaterializationHelpers
  alias Storyarn.Versioning.ProjectRestoreAvatarIntegrity
  alias Storyarn.Versioning.RestorePolicy
  alias Storyarn.Versioning.SheetLocalizationSnapshotValidator

  @sheet_snapshot_fields ~w(
    original_id name shortcut description avatar_asset_id avatars banner_asset_id color
    hidden_inherited_block_ids blocks asset_blob_hashes asset_metadata localization
    localization_manifest
  )
  @restored_optional_block_fields ~w(variable_name inherited_from_block_id column_group_id)
  @restored_optional_avatar_fields ~w(name notes)
  @restored_optional_gallery_image_fields ~w(label description)

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Sheet{} = sheet) do
    {:ok, snapshot} =
      Repo.transaction(
        fn ->
          :ok = lock_sheet_project_for_snapshot!(sheet.project_id)
          locked_sheet = lock_sheet_for_snapshot!(sheet)

          :ok = LocalizableWords.lock_inventory!(locked_sheet.project_id)
          do_build_snapshot(locked_sheet)
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

  defp do_build_snapshot(%Sheet{} = sheet) do
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
      |> normalize_avatar_snapshot_defaults()

    block_snapshots = Enum.map(sheet.blocks, &block_to_snapshot/1)
    default_avatar_asset_id = default_avatar_asset_id(avatar_snapshots)
    asset_ids = [sheet.banner_asset_id | snapshot_asset_ids(avatar_snapshots, block_snapshots)]

    {hash_map, metadata_map} =
      AssetHashResolver.resolve_hashes_for_project!(asset_ids, sheet.project_id)

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

    snapshot = %{
      "original_id" => sheet.id,
      "name" => sheet.name,
      "shortcut" => sheet.shortcut,
      "description" => sheet.description,
      "avatar_asset_id" => default_avatar_asset_id,
      "avatars" => avatar_snapshots,
      "banner_asset_id" => sheet.banner_asset_id,
      "color" => sheet.color,
      "hidden_inherited_block_ids" => sheet.hidden_inherited_block_ids || [],
      "blocks" => block_snapshots,
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map,
      "localization" => localization,
      "localization_manifest" => LocalizationSnapshotCodec.manifest(localization, target_locales)
    }

    ensure_valid_built_sheet_snapshot!(sheet, snapshot)
  end

  defp ensure_valid_built_sheet_snapshot!(sheet, snapshot) do
    result =
      with :ok <- validate_portable_sheet_snapshot(snapshot),
           :ok <- validate_sheet_block_reference_ownership(sheet.project_id, snapshot) do
        validate_effective_sheet_inheritance_graph(
          sheet.project_id,
          snapshot["blocks"],
          forbidden_sheet_id: sheet.id
        )
      end

    case result do
      :ok ->
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

  defp block_to_snapshot(%Block{} = block) do
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
    |> maybe_put_table_data(block)
    |> maybe_put_gallery_images(block)
  end

  defp maybe_put_table_data(snapshot, %Block{type: "table"} = block) do
    Map.put(snapshot, "table_data", %{
      "columns" => block.table_columns |> sort_positioned() |> Enum.map(&column_to_snapshot/1),
      "rows" => block.table_rows |> sort_positioned() |> Enum.map(&row_to_snapshot/1)
    })
  end

  defp maybe_put_table_data(snapshot, _block), do: snapshot

  defp maybe_put_gallery_images(snapshot, %Block{type: "gallery"} = block) do
    Map.put(
      snapshot,
      "gallery_images",
      Enum.map(sorted_gallery_images(block.gallery_images), &gallery_image_to_snapshot/1)
    )
  end

  defp maybe_put_gallery_images(snapshot, _block), do: snapshot

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

  @impl true
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
    Repo.transaction(
      fn -> instantiate_sheet_snapshot(project_id, snapshot, opts) end,
      timeout: :infinity
    )
  end

  defp validate_sheet_instantiation_localization(_project_id, snapshot, _opts) when is_map(snapshot) do
    validate_portable_sheet_snapshot(snapshot)
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
           validate_materialized_sheet_inheritance_graph(
             project_id,
             snapshot,
             locked_external_block_ids,
             opts
           ),
         :ok <- LocalizableWords.lock_inventory!(project_id),
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

  defp sheet_snapshot_attrs(project_id, snapshot, opts, now) do
    Map.merge(
      %{
        project_id: project_id,
        name: snapshot["name"],
        shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
        description: snapshot["description"],
        color: snapshot["color"],
        hidden_inherited_block_ids: [],
        banner_asset_id: resolve_sheet_asset(snapshot["banner_asset_id"], snapshot, project_id, opts),
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
      |> Enum.concat(snapshot["hidden_inherited_block_ids"])
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
         :ok <- Localization.extract_sheet_blocks(sheet.id),
         :ok <- Localization.sync_sheet_names(project_id) do
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

      LocalizationSnapshotCodec.restore(
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

  @impl true
  def restore_snapshot(%Sheet{} = sheet, snapshot, opts \\ []) do
    with :ok <-
           RestorePolicy.ensure_builder_enabled(
             "sheet",
             Keyword.get(opts, :restore_action)
           ) do
      do_restore_snapshot(sheet, snapshot, opts)
    end
  end

  defp do_restore_snapshot(sheet, snapshot, opts) do
    opts
    |> MaterializationHelpers.with_asset_copy_tracker(fn tracked_opts ->
      AssetMaterializationScope.run(
        tracked_opts,
        &restore_sheet_snapshot_transaction(sheet, snapshot, &1)
      )
    end)
    |> finalize_sheet_restore(snapshot, opts)
  end

  defp restore_sheet_snapshot_transaction(sheet, snapshot, opts) do
    Repo.transaction(
      fn -> restore_sheet_snapshot_in_transaction(sheet, snapshot, opts) end,
      timeout: :infinity
    )
  end

  defp restore_sheet_snapshot_in_transaction(sheet, snapshot, opts) do
    with {:ok, _project} <- lock_sheet_project_for_restore(sheet.project_id),
         {:ok, locked_sheet} <- lock_sheet_for_restore(sheet),
         :ok <- lock_pre_restore_version_record(locked_sheet, opts),
         :ok <- LocalizableWords.lock_inventory!(locked_sheet.project_id),
         :ok <- verify_pre_restore_sheet_baseline(locked_sheet, opts),
         :ok <- validate_sheet_snapshot(locked_sheet, snapshot),
         {:ok, inheritance_plan} <-
           preflight_property_inheritance(locked_sheet, snapshot, opts),
         {:ok, updated_sheet} <- restore_sheet_fields(locked_sheet, snapshot, opts),
         {:ok, block_data} <-
           reconcile_sheet_blocks(locked_sheet, snapshot, opts, inheritance_plan),
         :ok <- reconcile_sheet_avatars(locked_sheet, snapshot, opts),
         :ok <- restore_sheet_localization_in_place(locked_sheet, snapshot, block_data),
         :ok <- rebuild_restored_block_references(block_data, locked_sheet.project_id, opts),
         :ok <-
           rebuild_inherited_instance_state(
             block_data.affected_inherited_instance_ids,
             locked_sheet.project_id,
             opts
           ),
         :ok <- References.rebuild_project_variable_references(locked_sheet.project_id),
         :ok <- verify_active_block_ids(locked_sheet.id, block_data.block_id_map) do
      {updated_sheet, block_data}
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp lock_sheet_project_for_restore(project_id) do
    case Repo.one(from(project in Project, where: project.id == ^project_id, lock: "FOR UPDATE")) do
      %Project{deleted_at: nil} = project -> {:ok, project}
      %Project{} -> {:error, {:project_not_active, project_id}}
      nil -> {:error, {:project_not_found, project_id}}
    end
  end

  defp lock_sheet_for_restore(%Sheet{} = sheet) do
    case Repo.one(from(s in Sheet, where: s.id == ^sheet.id, lock: "FOR UPDATE")) do
      %Sheet{project_id: project_id, deleted_at: nil} = locked
      when project_id == sheet.project_id ->
        {:ok, locked}

      %Sheet{project_id: project_id} when project_id == sheet.project_id ->
        {:error, {:sheet_not_active, sheet.id}}

      %Sheet{} ->
        {:error, {:sheet_project_mismatch, sheet.id}}

      nil ->
        {:error, {:sheet_not_found, sheet.id}}
    end
  end

  defp lock_pre_restore_version_record(sheet, opts) do
    case Keyword.fetch(opts, :pre_restore_version_identity) do
      {:ok, identity} ->
        lock_and_verify_pre_restore_version_record(
          sheet,
          Keyword.get(opts, :user_id),
          identity
        )

      :error ->
        # Product restores always supply this identity. It remains optional at
        # this internal builder boundary for isolated materialization tests and
        # trusted migrations.
        :ok
    end
  end

  defp lock_and_verify_pre_restore_version_record(sheet, user_id, identity) do
    with :ok <- ensure_valid_pre_restore_version_identity(sheet, user_id, identity),
         {:ok, version} <- fetch_locked_pre_restore_version(sheet, identity) do
      ensure_pre_restore_version_identity(version, identity)
    end
  end

  defp ensure_valid_pre_restore_version_identity(sheet, user_id, identity) do
    if valid_pre_restore_version_identity?(sheet, user_id, identity),
      do: :ok,
      else: {:error, :invalid_pre_restore_version_identity}
  end

  defp fetch_locked_pre_restore_version(sheet, identity) do
    version =
      Repo.one(
        from(candidate in EntityVersion,
          where:
            candidate.id == ^identity.id and
              candidate.entity_type == "sheet" and
              candidate.entity_id == ^sheet.id and
              candidate.project_id == ^sheet.project_id,
          lock: "FOR SHARE"
        )
      )

    if version,
      do: {:ok, version},
      else: {:error, :pre_restore_version_not_durable}
  end

  defp ensure_pre_restore_version_identity(version, identity) do
    if entity_version_identity(version) == identity,
      do: :ok,
      else: {:error, :pre_restore_version_identity_mismatch}
  end

  defp valid_pre_restore_version_identity?(sheet, user_id, %{
         id: version_id,
         entity_type: "sheet",
         entity_id: entity_id,
         project_id: project_id,
         created_by_id: identity_user_id,
         version_number: version_number,
         storage_key: storage_key,
         snapshot_size_bytes: snapshot_size_bytes,
         checksum: checksum
       }) do
    valid_pre_restore_version_scope?(
      sheet,
      user_id,
      entity_id,
      project_id,
      identity_user_id
    ) and
      valid_pre_restore_version_metadata?(
        version_id,
        version_number,
        storage_key,
        snapshot_size_bytes,
        checksum
      )
  end

  defp valid_pre_restore_version_identity?(_sheet, _user_id, _identity), do: false

  defp valid_pre_restore_version_scope?(sheet, user_id, entity_id, project_id, identity_user_id) do
    entity_id == sheet.id and project_id == sheet.project_id and
      identity_user_id == user_id
  end

  defp valid_pre_restore_version_metadata?(version_id, version_number, storage_key, snapshot_size_bytes, checksum) do
    is_integer(version_id) and version_id > 0 and is_integer(version_number) and
      version_number > 0 and is_binary(storage_key) and
      is_integer(snapshot_size_bytes) and snapshot_size_bytes >= 0 and
      is_binary(checksum)
  end

  defp entity_version_identity(%EntityVersion{} = version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end

  defp verify_pre_restore_sheet_baseline(sheet, opts) do
    case Keyword.get(opts, :restore_action) do
      {:entity_version_restore, "sheet"} ->
        verify_entity_version_restore_baseline(sheet, opts)

      _other_restore_action ->
        # Full-project restore verifies its canonical project-wide safety
        # snapshot before dispatching individual entity builders.
        :ok
    end
  end

  defp verify_entity_version_restore_baseline(sheet, opts) do
    case Keyword.fetch(opts, :pre_restore_snapshot) do
      {:ok, pre_restore_snapshot} when is_map(pre_restore_snapshot) ->
        safely_compare_pre_restore_sheet_baseline(sheet, pre_restore_snapshot)

      {:ok, _invalid_snapshot} ->
        {:error, :invalid_pre_restore_snapshot}

      :error ->
        :ok
    end
  end

  defp safely_compare_pre_restore_sheet_baseline(sheet, pre_restore_snapshot) do
    current_snapshot = do_build_snapshot(sheet)

    if current_snapshot == pre_restore_snapshot,
      do: :ok,
      else: {:error, :sheet_changed_since_pre_restore_snapshot}
  rescue
    error in ArgumentError ->
      {:error, {:pre_restore_snapshot_validation_failed, Exception.message(error)}}
  end

  defp validate_sheet_snapshot(%Sheet{} = sheet, snapshot) when is_map(snapshot) do
    blocks = snapshot["blocks"]
    avatars = snapshot["avatars"]

    with :ok <-
           validate_present_fields(
             snapshot,
             @sheet_snapshot_fields,
             :sheet,
             sheet.id
           ),
         :ok <- validate_portable_sheet_snapshot(snapshot),
         :ok <- validate_snapshot_root_id(sheet.id, snapshot["original_id"]),
         :ok <- validate_existing_snapshot_ownership(sheet, blocks, avatars),
         :ok <- validate_block_references(sheet, snapshot, blocks) do
      validate_effective_sheet_inheritance_graph(
        sheet.project_id,
        blocks,
        forbidden_sheet_id: sheet.id
      )
    end
  end

  defp validate_sheet_snapshot(_sheet, _snapshot), do: {:error, {:invalid_snapshot, :expected_map}}

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

  defp validate_existing_snapshot_ownership(sheet, blocks, avatars) do
    with :ok <-
           validate_existing_parentage(
             Block,
             Enum.map(blocks, &{&1, sheet.id}),
             :sheet_id,
             :block
           ),
         :ok <-
           validate_existing_parentage(
             SheetAvatar,
             Enum.map(avatars, &{&1, sheet.id}),
             :sheet_id,
             :avatar
           ),
         :ok <-
           validate_existing_parentage(
             TableColumn,
             nested_entries(blocks, "columns"),
             :block_id,
             :table_column
           ),
         :ok <-
           validate_existing_parentage(
             TableRow,
             nested_entries(blocks, "rows"),
             :block_id,
             :table_row
           ) do
      validate_existing_parentage(
        BlockGalleryImage,
        gallery_entries(blocks),
        :block_id,
        :gallery_image
      )
    end
  end

  defp validate_existing_parentage(_schema, [], _parent_field, _kind), do: :ok

  defp validate_existing_parentage(schema, entries, parent_field, kind) do
    expected = Map.new(entries, fn {entry, parent_id} -> {entry["original_id"], parent_id} end)
    ids = Map.keys(expected)

    mismatch =
      from(record in schema,
        where: record.id in ^ids,
        order_by: [asc: record.id],
        select: {record.id, field(record, ^parent_field)},
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Enum.find(fn {id, actual_parent_id} -> expected[id] != actual_parent_id end)

    case mismatch do
      nil ->
        :ok

      {id, actual_parent_id} ->
        {:error, {:snapshot_id_ownership_mismatch, kind, id, expected[id], actual_parent_id}}
    end
  end

  defp validate_block_references(sheet, snapshot, blocks) do
    target_ids = MapSet.new(blocks, & &1["original_id"])

    reference_ids =
      blocks
      |> Enum.map(& &1["inherited_from_block_id"])
      |> Enum.concat(snapshot["hidden_inherited_block_ids"] || [])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&MapSet.member?(target_ids, &1))

    with {:ok, valid_rows} <-
           validate_active_block_reference_rows(
             sheet.project_id,
             reference_ids,
             block_reference_rows(reference_ids)
           ),
         {:ok, locked_owner_sheet_ids} <- lock_block_reference_owner_sheets(valid_rows) do
      locked_block_rows =
        lock_block_reference_rows(reference_ids, locked_owner_sheet_ids)

      validate_locked_block_references(reference_ids, locked_block_rows, sheet.id)
    end
  end

  defp block_reference_rows(reference_ids) do
    Repo.all(
      from(block in Block,
        join: owner_sheet in Sheet,
        on: owner_sheet.id == block.sheet_id,
        where: block.id in ^reference_ids,
        select: {block.id, block.deleted_at, owner_sheet.id, owner_sheet.project_id, owner_sheet.deleted_at}
      )
    )
  end

  defp validate_active_block_reference_rows(project_id, reference_ids, reference_rows) do
    valid_rows =
      Enum.filter(reference_rows, fn {_block_id, block_deleted_at, _sheet_id, owner_project_id, sheet_deleted_at} ->
        owner_project_id == project_id and is_nil(block_deleted_at) and is_nil(sheet_deleted_at)
      end)

    valid_ids = MapSet.new(valid_rows, &elem(&1, 0))

    case Enum.find(reference_ids, &(not MapSet.member?(valid_ids, &1))) do
      nil -> {:ok, valid_rows}
      id -> {:error, {:invalid_snapshot, {:invalid_block_reference, id}}}
    end
  end

  defp lock_block_reference_owner_sheets(valid_rows) do
    owner_sheet_ids =
      valid_rows
      |> Enum.map(&elem(&1, 2))
      |> Enum.uniq()
      |> Enum.sort()

    locked_owner_sheet_ids =
      from(owner_sheet in Sheet,
        where: owner_sheet.id in ^owner_sheet_ids and is_nil(owner_sheet.deleted_at),
        order_by: [asc: owner_sheet.id],
        lock: "FOR UPDATE",
        select: owner_sheet.id
      )
      |> Repo.all()
      |> MapSet.new()

    if Enum.all?(owner_sheet_ids, &MapSet.member?(locked_owner_sheet_ids, &1)) do
      {:ok, locked_owner_sheet_ids}
    else
      {:error, {:invalid_snapshot, :inactive_inherited_block_owner}}
    end
  end

  defp lock_block_reference_rows(reference_ids, locked_owner_sheet_ids) do
    Repo.all(
      from(block in Block,
        where: block.id in ^Enum.sort(reference_ids) and is_nil(block.deleted_at),
        where: block.sheet_id in ^MapSet.to_list(locked_owner_sheet_ids),
        order_by: [asc: block.id],
        lock: "FOR UPDATE",
        select: {block.id, block.sheet_id}
      )
    )
  end

  defp validate_locked_block_references(reference_ids, locked_block_rows, restored_sheet_id) do
    locked_block_ids = MapSet.new(locked_block_rows, &elem(&1, 0))

    with nil <- Enum.find(reference_ids, &(not MapSet.member?(locked_block_ids, &1))),
         nil <- Enum.find(locked_block_rows, fn {_id, owner_sheet_id} -> owner_sheet_id == restored_sheet_id end) do
      :ok
    else
      {id, ^restored_sheet_id} ->
        {:error, {:invalid_snapshot, {:same_sheet_external_block_reference, id}}}

      id ->
        {:error, {:invalid_snapshot, {:invalid_block_reference, id}}}
    end
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

  defp nested_entries(blocks, child_key) do
    blocks
    |> Enum.filter(&(&1["type"] == "table"))
    |> Enum.flat_map(fn block ->
      Enum.map(get_in(block, ["table_data", child_key]), &{&1, block["original_id"]})
    end)
  end

  defp gallery_entries(blocks) do
    blocks
    |> Enum.filter(&(&1["type"] == "gallery"))
    |> Enum.flat_map(fn block ->
      Enum.map(Map.get(block, "gallery_images", []), &{&1, block["original_id"]})
    end)
  end

  defp preflight_property_inheritance(sheet, snapshot, opts) do
    target_blocks = snapshot["blocks"]
    current_blocks = lock_current_sheet_blocks(sheet.id)

    if Keyword.get(opts, :full_project_restore, false) do
      # Every active sheet and block is restored from the same project
      # snapshot. Cross-sheet propagation is deliberately deferred until the
      # complete graph and target tree exist; the project restore verifies the
      # resulting inheritance graph before commit.
      {:ok,
       %{
         extra_children_sources: [],
         restore_sources: [],
         sync_source_ids: [],
         sync_instance_ids: []
       }}
    else
      current_by_id = Map.new(current_blocks, &{&1.id, &1})
      instances_by_source = lock_external_instances(current_blocks, sheet)
      current_table_data = lock_current_table_data(current_blocks)

      with :ok <-
             validate_property_inheritance_targets(
               target_blocks,
               current_by_id,
               instances_by_source,
               current_table_data
             ) do
        {:ok,
         build_property_inheritance_plan(
           target_blocks,
           current_blocks,
           current_by_id,
           instances_by_source
         )}
      end
    end
  end

  defp lock_current_sheet_blocks(sheet_id) do
    Repo.all(
      from(block in Block,
        where: block.sheet_id == ^sheet_id,
        order_by: [asc: block.id],
        lock: "FOR UPDATE"
      )
    )
  end

  defp lock_external_instances(current_blocks, sheet) do
    source_ids = Enum.map(current_blocks, & &1.id)

    from(instance in Block,
      join: owner_sheet in Sheet,
      on: owner_sheet.id == instance.sheet_id,
      where:
        instance.inherited_from_block_id in ^source_ids and
          instance.sheet_id != ^sheet.id and
          owner_sheet.project_id == ^sheet.project_id and
          is_nil(owner_sheet.deleted_at),
      order_by: [asc: instance.id],
      lock: "FOR UPDATE",
      select: instance
    )
    |> Repo.all()
    |> Enum.group_by(& &1.inherited_from_block_id)
  end

  defp lock_current_table_data(current_blocks) do
    table_block_ids =
      current_blocks
      |> Enum.filter(&(&1.type == "table"))
      |> Enum.map(& &1.id)

    columns =
      from(column in TableColumn,
        where: column.block_id in ^table_block_ids,
        order_by: [asc: column.position, asc: column.id],
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Enum.group_by(& &1.block_id)

    rows =
      from(row in TableRow,
        where: row.block_id in ^table_block_ids,
        order_by: [asc: row.position, asc: row.id],
        lock: "FOR UPDATE"
      )
      |> Repo.all()
      |> Enum.group_by(& &1.block_id)

    Map.new(table_block_ids, fn block_id ->
      {block_id,
       table_structure_signature(
         Map.get(columns, block_id, []),
         Map.get(rows, block_id, [])
       )}
    end)
  end

  defp validate_property_inheritance_targets(target_blocks, current_by_id, instances_by_source, current_table_data) do
    validate_each(target_blocks, fn target ->
      current = Map.get(current_by_id, target["original_id"])
      instances = Map.get(instances_by_source, target["original_id"], [])

      validate_property_inheritance_target(
        current,
        target,
        instances,
        current_table_data
      )
    end)
  end

  defp validate_property_inheritance_target(
         nil,
         %{"original_id" => block_id, "scope" => "children"},
         _instances,
         _current_table_data
       ) do
    property_inheritance_conflict(
      block_id,
      :missing_historical_children_source,
      []
    )
  end

  defp validate_property_inheritance_target(nil, _target, _instances, _current_table_data), do: :ok

  defp validate_property_inheritance_target(current, target, instances, current_table_data) do
    target_scope = target["scope"]

    cond do
      current.scope != target_scope ->
        property_inheritance_conflict(
          current.id,
          {:scope_change, current.scope, target_scope},
          instances
        )

      current.scope == "children" and target_scope == "children" ->
        validate_children_definition_restore(
          current,
          target,
          restorable_active_instances(current, instances),
          current_table_data
        )

      true ->
        :ok
    end
  end

  defp validate_children_definition_restore(_current, _target, [], _current_table_data), do: :ok

  defp validate_children_definition_restore(current, target, active_instances, current_table_data) do
    cond do
      current.type != target["type"] ->
        property_inheritance_conflict(
          current.id,
          {:type_change, current.type, target["type"]},
          active_instances
        )

      table_structure_changed?(current, target, current_table_data) ->
        property_inheritance_conflict(
          current.id,
          :table_structure_change,
          active_instances
        )

      true ->
        :ok
    end
  end

  defp restorable_active_instances(%Block{deleted_at: nil}, instances) do
    Enum.filter(instances, &(not &1.detached and is_nil(&1.deleted_at)))
  end

  defp restorable_active_instances(%Block{deleted_at: deleted_at}, instances) do
    Enum.filter(instances, fn instance ->
      not instance.detached and
        (is_nil(instance.deleted_at) or cascade_deleted_instance?(instance, deleted_at))
    end)
  end

  defp cascade_deleted_instance?(%Block{deleted_at: nil}, _source_deleted_at), do: false

  defp cascade_deleted_instance?(%Block{deleted_at: instance_deleted_at}, source_deleted_at) do
    lower_bound = DateTime.add(source_deleted_at, -2, :second)
    upper_bound = DateTime.add(source_deleted_at, 2, :second)

    DateTime.compare(instance_deleted_at, lower_bound) != :lt and
      DateTime.compare(instance_deleted_at, upper_bound) != :gt
  end

  defp property_inheritance_conflict(block_id, reason, instances) do
    instance_ids = instances |> Enum.map(& &1.id) |> Enum.sort()

    {:error, {:property_inheritance_restore_conflict, block_id, reason, instance_ids}}
  end

  defp table_structure_changed?(
         %Block{type: "table", id: block_id},
         %{"type" => "table", "table_data" => target_table_data},
         current_table_data
       ) do
    Map.fetch!(current_table_data, block_id) !=
      table_structure_signature(
        target_table_data["columns"],
        target_table_data["rows"]
      )
  end

  defp table_structure_changed?(_current, _target, _current_table_data), do: false

  defp table_structure_signature(columns, rows) do
    %{
      columns:
        columns
        |> Enum.map(&table_column_signature/1)
        |> Enum.sort_by(&{&1["position"], &1["original_id"]}),
      rows:
        rows
        |> Enum.map(&table_row_signature/1)
        |> Enum.sort_by(&{&1["position"], &1["original_id"]})
    }
  end

  defp table_column_signature(%TableColumn{} = column), do: column_to_snapshot(column)

  defp table_column_signature(column) when is_map(column), do: column

  defp table_row_signature(%TableRow{} = row), do: row_to_snapshot(row)
  defp table_row_signature(row) when is_map(row), do: row

  defp build_property_inheritance_plan(target_blocks, current_blocks, current_by_id, instances_by_source) do
    target_id_set = MapSet.new(target_blocks, & &1["original_id"])

    sync_source_ids =
      target_blocks
      |> Enum.filter(fn target ->
        case Map.get(current_by_id, target["original_id"]) do
          %Block{scope: "children"} -> target["scope"] == "children"
          _current -> false
        end
      end)
      |> Enum.map(& &1["original_id"])

    %{
      extra_children_sources:
        current_blocks
        |> Enum.filter(fn block ->
          is_nil(block.deleted_at) and block.scope == "children" and
            not MapSet.member?(target_id_set, block.id)
        end)
        |> Enum.map(fn source ->
          %{
            source: source,
            active_instance_ids:
              instances_by_source
              |> Map.get(source.id, [])
              |> Enum.filter(&(not &1.detached and is_nil(&1.deleted_at)))
              |> Enum.map(& &1.id)
          }
        end),
      restore_sources:
        target_blocks
        |> Enum.filter(&(&1["scope"] == "children"))
        |> Enum.map(&Map.get(current_by_id, &1["original_id"]))
        |> Enum.reject(&(is_nil(&1) or is_nil(&1.deleted_at)))
        |> Enum.map(fn source ->
          %{
            source: source,
            instance_ids:
              instances_by_source
              |> Map.get(source.id, [])
              |> Enum.filter(&(not &1.detached and cascade_deleted_instance?(&1, source.deleted_at)))
              |> Enum.map(& &1.id)
          }
        end),
      sync_source_ids: sync_source_ids,
      sync_instance_ids:
        sync_source_ids
        |> Enum.flat_map(&Map.get(instances_by_source, &1, []))
        |> Enum.filter(&(not &1.detached and is_nil(&1.deleted_at)))
        |> Enum.map(& &1.id)
    }
  end

  defp restore_sheet_fields(sheet, snapshot, opts) do
    sheet
    |> Sheet.update_changeset(%{
      name: snapshot["name"],
      shortcut: snapshot["shortcut"],
      description: snapshot["description"],
      color: snapshot["color"],
      hidden_inherited_block_ids: snapshot["hidden_inherited_block_ids"] || [],
      banner_asset_id:
        resolve_sheet_asset(
          snapshot["banner_asset_id"],
          snapshot,
          sheet.project_id,
          opts
        )
    })
    |> Repo.update()
    |> normalize_restore_write(:sheet, sheet.id)
  end

  defp reconcile_sheet_blocks(sheet, snapshot, opts, inheritance_plan) do
    blocks = snapshot["blocks"]
    target_ids = Enum.map(blocks, & &1["original_id"])
    target_id_set = MapSet.new(target_ids)

    current_blocks =
      Repo.all(
        from(block in Block,
          where: block.sheet_id == ^sheet.id,
          select: block,
          lock: "FOR UPDATE"
        )
      )

    soft_deleted_ids =
      current_blocks
      |> Enum.filter(&(is_nil(&1.deleted_at) and not MapSet.member?(target_id_set, &1.id)))
      |> Enum.map(& &1.id)

    with :ok <-
           delete_extra_children_sources(inheritance_plan.extra_children_sources),
         :ok <- soft_delete_blocks(sheet.id, soft_deleted_ids),
         :ok <- clear_target_variable_names(sheet.id, target_ids),
         :ok <- upsert_snapshot_blocks(sheet.id, blocks),
         :ok <- restore_snapshot_inheritance(sheet.id, blocks),
         :ok <- reconcile_snapshot_table_data(blocks),
         :ok <- reconcile_snapshot_gallery_images(sheet, snapshot, blocks, opts),
         :ok <- restore_inherited_instances(inheritance_plan.restore_sources),
         :ok <- sync_inherited_definitions(inheritance_plan.sync_source_ids) do
      block_id_map = Map.new(target_ids, &{&1, &1})

      restored_inherited_instance_ids =
        Enum.flat_map(inheritance_plan.restore_sources, & &1.instance_ids)

      {:ok,
       %{
         count: length(blocks),
         block_id_map: block_id_map,
         soft_deleted_ids: soft_deleted_ids,
         affected_inherited_instance_ids: Enum.uniq(restored_inherited_instance_ids ++ inheritance_plan.sync_instance_ids)
       }}
    end
  end

  defp delete_extra_children_sources(sources) do
    validate_each(sources, &delete_extra_children_source/1)
  end

  defp delete_extra_children_source(%{source: source, active_instance_ids: active_instance_ids}) do
    Enum.each([source.id | active_instance_ids], &References.delete_block_references/1)

    TextCrud.archive_texts_for_sources(
      "block",
      [source.id | active_instance_ids],
      "source_deleted"
    )

    source
    |> PropertyInheritance.delete_inherited_instances()
    |> normalize_property_inheritance_result(
      source.id,
      :delete_inherited_instances
    )
  end

  defp restore_inherited_instances(sources) do
    validate_each(sources, &restore_inherited_instance_cascade/1)
  end

  defp restore_inherited_instance_cascade(%{instance_ids: []}), do: :ok

  defp restore_inherited_instance_cascade(%{source: source, instance_ids: instance_ids}) do
    now = MaterializationHelpers.now()

    case Repo.update_all(
           from(instance in Block,
             where:
               instance.id in ^instance_ids and
                 instance.inherited_from_block_id == ^source.id and
                 instance.detached == false and not is_nil(instance.deleted_at)
           ),
           set: [deleted_at: nil, updated_at: now]
         ) do
      {count, _} when count == length(instance_ids) ->
        :ok

      {count, _} ->
        {:error,
         {:property_inheritance_lifecycle_failed, source.id, :restore_inherited_instances,
          {:instance_restore_count_mismatch, length(instance_ids), count}}}
    end
  end

  defp sync_inherited_definitions(source_ids) do
    validate_each(source_ids, fn source_id ->
      Block
      |> Repo.get!(source_id)
      |> PropertyInheritance.sync_definition_change(active_owner_sheets_only: true)
      |> normalize_property_inheritance_result(
        source_id,
        :sync_definition_change
      )
    end)
  end

  defp normalize_property_inheritance_result({:ok, _count}, _source_id, _operation), do: :ok

  defp normalize_property_inheritance_result({:error, reason}, source_id, operation) do
    {:error, {:property_inheritance_lifecycle_failed, source_id, operation, reason}}
  end

  defp soft_delete_blocks(_sheet_id, []), do: :ok

  defp soft_delete_blocks(sheet_id, block_ids) do
    now = MaterializationHelpers.now()

    case Repo.update_all(
           from(block in Block,
             where:
               block.sheet_id == ^sheet_id and block.id in ^block_ids and
                 is_nil(block.deleted_at)
           ),
           set: [deleted_at: now, updated_at: now]
         ) do
      {count, _} when count == length(block_ids) -> :ok
      {count, _} -> {:error, {:block_soft_delete_count_mismatch, length(block_ids), count}}
    end
  end

  defp clear_target_variable_names(_sheet_id, []), do: :ok

  defp clear_target_variable_names(sheet_id, target_ids) do
    Repo.update_all(
      from(block in Block, where: block.sheet_id == ^sheet_id and block.id in ^target_ids),
      set: [variable_name: nil]
    )

    :ok
  end

  defp upsert_snapshot_blocks(sheet_id, blocks) do
    Enum.reduce_while(blocks, :ok, fn block_data, :ok ->
      id = block_data["original_id"]
      attrs = block_restore_attrs(block_data)

      result =
        case Repo.get(Block, id) do
          nil ->
            %Block{id: id, sheet_id: sheet_id}
            |> Ecto.Changeset.change(attrs)
            |> Ecto.Changeset.unique_constraint(:id, name: :blocks_pkey)
            |> Repo.insert()

          %Block{sheet_id: ^sheet_id} = block ->
            block
            |> Ecto.Changeset.change(attrs)
            |> Repo.update()

          %Block{sheet_id: actual_sheet_id} ->
            {:error, {:snapshot_id_ownership_mismatch, :block, id, sheet_id, actual_sheet_id}}
        end

      case normalize_restore_write(result, :block, id) do
        {:ok, _block} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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

  defp restore_snapshot_inheritance(sheet_id, blocks) do
    Enum.reduce_while(blocks, :ok, fn block_data, :ok ->
      id = block_data["original_id"]
      inherited_from_id = block_data["inherited_from_block_id"]

      case Repo.update_all(
             from(block in Block, where: block.id == ^id and block.sheet_id == ^sheet_id),
             set: [inherited_from_block_id: inherited_from_id]
           ) do
        {1, _} -> {:cont, :ok}
        {count, _} -> {:halt, {:error, {:block_inheritance_update_failed, id, count}}}
      end
    end)
  end

  defp reconcile_snapshot_table_data(blocks) do
    Enum.reduce_while(blocks, :ok, fn block_data, :ok ->
      block_id = block_data["original_id"]

      {columns, rows} =
        if block_data["type"] == "table" do
          table_data = block_data["table_data"]
          {Map.get(table_data, "columns", []), Map.get(table_data, "rows", [])}
        else
          {[], []}
        end

      with :ok <- reconcile_table_columns(block_id, columns),
           :ok <- reconcile_table_rows(block_id, rows) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reconcile_table_columns(block_id, columns) do
    target_ids = Enum.map(columns, & &1["original_id"])

    with :ok <- delete_missing_children(TableColumn, block_id, target_ids),
         :ok <- temporarily_replace_slugs(TableColumn, block_id, target_ids, "column") do
      upsert_table_columns(block_id, columns)
    end
  end

  defp reconcile_table_rows(block_id, rows) do
    target_ids = Enum.map(rows, & &1["original_id"])

    with :ok <- delete_missing_children(TableRow, block_id, target_ids),
         :ok <- temporarily_replace_slugs(TableRow, block_id, target_ids, "row") do
      upsert_table_rows(block_id, rows)
    end
  end

  defp delete_missing_children(schema, block_id, []) do
    Repo.delete_all(from(child in schema, where: field(child, :block_id) == ^block_id))
    :ok
  end

  defp delete_missing_children(schema, block_id, target_ids) do
    Repo.delete_all(
      from(child in schema,
        where: field(child, :block_id) == ^block_id and child.id not in ^target_ids
      )
    )

    :ok
  end

  defp temporarily_replace_slugs(_schema, _block_id, [], _prefix), do: :ok

  defp temporarily_replace_slugs(schema, block_id, target_ids, prefix) do
    Enum.each(target_ids, fn id ->
      Repo.update_all(
        from(child in schema,
          where: child.id == ^id and field(child, :block_id) == ^block_id
        ),
        set: [slug: "__version_restore_#{prefix}_#{id}"]
      )
    end)

    :ok
  end

  defp upsert_table_columns(block_id, columns) do
    Enum.reduce_while(columns, :ok, fn column_data, :ok ->
      id = column_data["original_id"]

      attrs = %{
        name: column_data["name"],
        slug: column_data["slug"],
        type: column_data["type"],
        is_constant: column_data["is_constant"],
        required: column_data["required"],
        position: column_data["position"],
        config: column_data["config"]
      }

      result =
        case Repo.get(TableColumn, id) do
          nil ->
            %TableColumn{id: id, block_id: block_id}
            |> Ecto.Changeset.change(attrs)
            |> Ecto.Changeset.unique_constraint(:id, name: :table_columns_pkey)
            |> Repo.insert()

          %TableColumn{block_id: ^block_id} = column ->
            column
            |> Ecto.Changeset.change(attrs)
            |> Repo.update()

          %TableColumn{block_id: actual_block_id} ->
            {:error, {:snapshot_id_ownership_mismatch, :table_column, id, block_id, actual_block_id}}
        end

      case normalize_restore_write(result, :table_column, id) do
        {:ok, _column} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_table_rows(block_id, rows) do
    Enum.reduce_while(rows, :ok, fn row_data, :ok ->
      id = row_data["original_id"]

      attrs = %{
        name: row_data["name"],
        slug: row_data["slug"],
        position: row_data["position"],
        cells: row_data["cells"]
      }

      result =
        case Repo.get(TableRow, id) do
          nil ->
            %TableRow{id: id, block_id: block_id}
            |> Ecto.Changeset.change(attrs)
            |> Ecto.Changeset.unique_constraint(:id, name: :table_rows_pkey)
            |> Repo.insert()

          %TableRow{block_id: ^block_id} = row ->
            row
            |> Ecto.Changeset.change(attrs)
            |> Repo.update()

          %TableRow{block_id: actual_block_id} ->
            {:error, {:snapshot_id_ownership_mismatch, :table_row, id, block_id, actual_block_id}}
        end

      case normalize_restore_write(result, :table_row, id) do
        {:ok, _row} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp reconcile_snapshot_gallery_images(sheet, snapshot, blocks, opts) do
    Enum.reduce_while(blocks, :ok, fn block_data, :ok ->
      block_id = block_data["original_id"]

      images =
        cond do
          sheet_asset_mode(opts) == :drop -> []
          block_data["type"] == "gallery" -> Map.get(block_data, "gallery_images", [])
          true -> []
        end

      target_ids = Enum.map(images, & &1["original_id"])

      with :ok <- delete_missing_children(BlockGalleryImage, block_id, target_ids),
           :ok <- upsert_gallery_images(sheet, snapshot, block_id, images, opts) do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_gallery_images(sheet, snapshot, block_id, images, opts) do
    validate_each(
      images,
      &upsert_gallery_image(sheet, snapshot, block_id, &1, opts)
    )
  end

  defp upsert_gallery_image(sheet, snapshot, block_id, image_data, opts) do
    with {:ok, asset_id} <- resolve_restore_asset(sheet, snapshot, image_data, opts),
         {:ok, _image} <- persist_gallery_image(block_id, image_data, asset_id) do
      :ok
    end
  end

  defp resolve_restore_asset(sheet, snapshot, image_data, opts) do
    case resolve_sheet_asset(image_data["asset_id"], snapshot, sheet.project_id, opts) do
      nil -> {:error, {:missing_restored_asset, :gallery_image, image_data["original_id"]}}
      asset_id -> {:ok, asset_id}
    end
  end

  defp persist_gallery_image(block_id, image_data, asset_id) do
    id = image_data["original_id"]

    attrs = %{
      asset_id: asset_id,
      label: image_data["label"],
      description: image_data["description"],
      position: image_data["position"]
    }

    result =
      case Repo.get(BlockGalleryImage, id) do
        nil ->
          %BlockGalleryImage{id: id, block_id: block_id}
          |> Ecto.Changeset.change(attrs)
          |> Ecto.Changeset.unique_constraint(:id, name: :block_gallery_images_pkey)
          |> Repo.insert()

        %BlockGalleryImage{block_id: ^block_id, asset_id: ^asset_id} = image ->
          image
          |> Ecto.Changeset.change(attrs)
          |> Repo.update()

        %BlockGalleryImage{block_id: ^block_id, asset_id: current_asset_id} ->
          {:error, {:asset_identity_mismatch, :gallery_image, id, current_asset_id, asset_id}}

        %BlockGalleryImage{block_id: actual_block_id} ->
          {:error, {:snapshot_id_ownership_mismatch, :gallery_image, id, block_id, actual_block_id}}
      end

    normalize_restore_write(result, :gallery_image, id)
  end

  defp reconcile_sheet_avatars(sheet, snapshot, opts) do
    with {:ok, avatar_entries} <- build_restore_avatar_entries(sheet, snapshot, opts),
         :ok <-
           delete_missing_avatars(
             sheet.id,
             sheet.project_id,
             Enum.map(avatar_entries, & &1.original_id),
             opts
           ) do
      upsert_sheet_avatars(sheet.id, avatar_entries)
    end
  end

  defp delete_missing_avatars(sheet_id, project_id, target_ids, opts) do
    candidates =
      SheetAvatar
      |> where([avatar], avatar.sheet_id == ^sheet_id)
      |> exclude_target_avatars(target_ids)
      |> order_by([avatar], asc: avatar.id)
      |> lock("FOR UPDATE")
      |> Repo.all()

    with :ok <- ensure_avatar_deletions_safe(candidates, project_id, opts) do
      delete_avatar_candidates(sheet_id, candidates)
    end
  end

  defp exclude_target_avatars(query, []), do: query

  defp exclude_target_avatars(query, target_ids) do
    where(query, [avatar], avatar.id not in ^target_ids)
  end

  defp ensure_avatar_deletions_safe(avatars, project_id, opts) do
    validate_each(avatars, &ensure_avatar_deletion_safe(&1, project_id, opts))
  end

  defp ensure_avatar_deletion_safe(%SheetAvatar{id: avatar_id} = avatar, project_id, opts) do
    with :ok <-
           ProjectRestoreAvatarIntegrity.detach_recoverable_refs(
             avatar,
             project_id,
             opts
           ) do
      case AvatarIntegrity.ensure_deletable(avatar_id) do
        :ok ->
          :ok

        {:error, {:avatar_in_use, ^avatar_id, details}} ->
          {:error, {:avatar_restore_conflict, avatar_id, details}}

        {:error, reason} ->
          {:error, {:avatar_restore_conflict, avatar_id, reason}}
      end
    end
  end

  defp delete_avatar_candidates(_sheet_id, []), do: :ok

  defp delete_avatar_candidates(sheet_id, candidates) do
    candidate_ids = Enum.map(candidates, & &1.id)

    case Repo.delete_all(
           from(avatar in SheetAvatar,
             where:
               avatar.sheet_id == ^sheet_id and
                 avatar.id in ^candidate_ids
           )
         ) do
      {count, _} when count == length(candidate_ids) ->
        :ok

      {count, _} ->
        {:error, {:avatar_delete_count_mismatch, sheet_id, length(candidate_ids), count}}
    end
  end

  defp build_restore_avatar_entries(sheet, snapshot, opts) do
    if sheet_asset_mode(opts) == :drop do
      {:ok, []}
    else
      do_build_restore_avatar_entries(sheet, snapshot, opts)
    end
  end

  defp do_build_restore_avatar_entries(sheet, snapshot, opts) do
    snapshot
    |> Map.get("avatars", [])
    |> Enum.reduce_while({:ok, []}, fn avatar_data, {:ok, entries} ->
      id = avatar_data["original_id"]

      case resolve_sheet_asset(avatar_data["asset_id"], snapshot, sheet.project_id, opts) do
        nil ->
          {:halt, {:error, {:missing_restored_asset, :avatar, id}}}

        asset_id ->
          entry = %{
            original_id: id,
            asset_id: asset_id,
            name: avatar_data["name"],
            notes: avatar_data["notes"],
            position: avatar_data["position"],
            is_default: avatar_data["is_default"]
          }

          {:cont, {:ok, [entry | entries]}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp upsert_sheet_avatars(sheet_id, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      id = entry.original_id
      attrs = Map.delete(entry, :original_id)

      result =
        case Repo.get(SheetAvatar, id) do
          nil ->
            %SheetAvatar{id: id, sheet_id: sheet_id}
            |> Ecto.Changeset.change(attrs)
            |> Ecto.Changeset.unique_constraint(:id, name: :sheet_avatars_pkey)
            |> Repo.insert()

          %SheetAvatar{sheet_id: ^sheet_id, asset_id: asset_id} = avatar
          when asset_id == entry.asset_id ->
            avatar
            |> Ecto.Changeset.change(attrs)
            |> Repo.update()

          %SheetAvatar{sheet_id: ^sheet_id, asset_id: current_asset_id} ->
            {:error, {:asset_identity_mismatch, :avatar, id, current_asset_id, entry.asset_id}}

          %SheetAvatar{sheet_id: actual_sheet_id} ->
            {:error, {:snapshot_id_ownership_mismatch, :avatar, id, sheet_id, actual_sheet_id}}
        end

      case normalize_restore_write(result, :avatar, id) do
        {:ok, _avatar} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp restore_sheet_localization_in_place(sheet, snapshot, block_data) do
    target_ids = Map.keys(block_data.block_id_map)

    TextCrud.archive_texts_for_active_target_locales(
      sheet.project_id,
      "block",
      target_ids,
      "version_replaced"
    )

    TextCrud.archive_texts_for_sources("block", block_data.soft_deleted_ids, "source_deleted")

    TextCrud.archive_texts_for_active_target_locales(
      sheet.project_id,
      "sheet",
      [sheet.id],
      "version_replaced"
    )

    id_maps = %{
      sheet: MaterializationHelpers.root_id_map(snapshot, sheet.id),
      block: block_data.block_id_map
    }

    localization =
      LocalizationSnapshotCodec.active_target_rows(
        sheet.project_id,
        Map.get(snapshot, "localization", [])
      )

    with :ok <-
           LocalizationSnapshotCodec.restore(
             sheet.project_id,
             localization,
             id_maps
           ),
         :ok <- reconcile_restored_block_localization(target_ids) do
      Localization.sync_sheet_names(sheet.project_id)
    end
  end

  defp reconcile_restored_block_localization(block_ids) do
    block_ids
    |> Enum.map(&Repo.get(Block, &1))
    |> Enum.reduce_while(:ok, fn block, :ok ->
      case Localization.extract_block(block) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp rebuild_restored_block_references(block_data, project_id, opts) do
    target_ids = Map.keys(block_data.block_id_map)

    Enum.each(Enum.uniq(target_ids ++ block_data.soft_deleted_ids), fn block_id ->
      References.delete_block_references(block_id)
    end)

    target_ids
    |> Enum.map(&Repo.get(Block, &1))
    |> validate_each(&reconcile_block_references(&1, project_id, opts))
  end

  defp rebuild_inherited_instance_state(instance_ids, project_id, opts) do
    validate_each(instance_ids, fn instance_id ->
      instance = Repo.get!(Block, instance_id)

      with :ok <- reconcile_block_references(instance, project_id, opts) do
        Localization.extract_block(instance)
      end
    end)
  end

  defp reconcile_block_references(block, project_id, opts) do
    update_references =
      Keyword.get(
        opts,
        :__update_block_references_fun,
        &References.update_block_references/2
      )

    case update_references.(block, project_id: project_id) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, {:block_reference_reconcile_failed, block.id, reason}}

      result ->
        {:error, {:unexpected_block_reference_reconcile_result, block.id, result}}
    end
  end

  defp verify_active_block_ids(sheet_id, block_id_map) do
    expected_ids = block_id_map |> Map.values() |> MapSet.new()

    actual_ids =
      from(block in Block,
        where: block.sheet_id == ^sheet_id and is_nil(block.deleted_at),
        select: block.id
      )
      |> Repo.all()
      |> MapSet.new()

    if MapSet.equal?(expected_ids, actual_ids),
      do: :ok,
      else: {:error, {:active_block_identity_mismatch, expected_ids, actual_ids}}
  end

  defp normalize_restore_write({:ok, struct}, _kind, _id), do: {:ok, struct}

  defp normalize_restore_write({:error, %Ecto.Changeset{} = changeset}, kind, id),
    do: {:error, {:restore_write_failed, kind, id, changeset}}

  defp normalize_restore_write({:error, reason}, _kind, _id), do: {:error, reason}

  defp finalize_sheet_restore(result, snapshot, opts) do
    case result do
      {:ok, {updated_sheet, block_data}} ->
        active_blocks =
          from(block in Block,
            where: is_nil(block.deleted_at),
            order_by: [asc: block.position, asc: block.id]
          )

        restored_sheet =
          Repo.preload(
            updated_sheet,
            [blocks: active_blocks, avatars: :asset, banner_asset: []],
            force: true
          )

        sheet_restore_result(
          restored_sheet,
          block_data,
          snapshot,
          Keyword.get(opts, :return_id_maps, false)
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp sheet_restore_result(restored_sheet, _block_data, _snapshot, false), do: {:ok, restored_sheet}

  defp sheet_restore_result(restored_sheet, block_data, snapshot, true) do
    id_maps = %{
      sheet: MaterializationHelpers.root_id_map(snapshot, restored_sheet.id),
      block: block_data.block_id_map
    }

    {:ok, restored_sheet, id_maps}
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
    case resolve_sheet_asset(image_data["asset_id"], snapshot, project_id, opts) do
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

  defp resolve_sheet_asset(asset_id, snapshot, project_id, opts) do
    case sheet_asset_mode(opts) do
      :drop ->
        nil

      asset_mode ->
        AssetHashResolver.resolve_asset_fk(
          asset_id,
          snapshot,
          project_id,
          Keyword.get(opts, :user_id),
          MaterializationHelpers.asset_resolution_opts(opts, asset_mode)
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
    snapshot
    |> avatar_snapshots()
    |> Enum.map(&avatar_entry(&1, snapshot, project_id, now, opts))
    |> Enum.reject(&is_nil/1)
    |> ensure_default_avatar()
  end

  defp avatar_snapshots(%{"avatars" => avatars}) when is_list(avatars) and avatars != [] do
    avatars
  end

  defp avatar_snapshots(%{"avatar_asset_id" => asset_id}) when not is_nil(asset_id) do
    [%{"asset_id" => asset_id, "position" => 0, "is_default" => true}]
  end

  defp avatar_snapshots(_snapshot), do: []

  defp avatar_entry(avatar_data, snapshot, project_id, now, opts) do
    case resolve_sheet_asset(avatar_data["asset_id"], snapshot, project_id, opts) do
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

  @impl true
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
      & &1["original_id"],
      # Legacy fallback: match snapshots captured before original_id existed.
      fn block ->
        vn = block["variable_name"]
        if vn && vn != "", do: vn
      end,
      # Fallback: match by position
      & &1["position"]
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

  # ========== Scan References ==========

  @impl true
  def scan_references(snapshot) do
    refs =
      []
      |> add_avatar_refs(snapshot)
      |> add_hidden_block_refs(snapshot)
      |> maybe_add_ref(:asset, snapshot["banner_asset_id"], dgettext("sheets", "Banner image"))

    (snapshot["blocks"] || [])
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {block, idx}, acc ->
      acc
      |> maybe_add_ref(
        :block,
        block["inherited_from_block_id"],
        dgettext("sheets", "Block #%{n} — inherited source", n: idx)
      )
      |> add_gallery_refs(block, idx)
    end)
  end

  defp add_avatar_refs(refs, %{"avatars" => avatars}) when is_list(avatars) and avatars != [] do
    Enum.reduce(avatars, refs, fn avatar, acc ->
      maybe_add_ref(acc, :asset, avatar["asset_id"], dgettext("sheets", "Avatar image"))
    end)
  end

  defp add_avatar_refs(refs, snapshot) do
    maybe_add_ref(refs, :asset, snapshot["avatar_asset_id"], dgettext("sheets", "Avatar image"))
  end

  defp add_hidden_block_refs(refs, snapshot) do
    Enum.reduce(snapshot["hidden_inherited_block_ids"] || [], refs, fn block_id, acc ->
      maybe_add_ref(
        acc,
        :block,
        block_id,
        dgettext("sheets", "Hidden inherited block")
      )
    end)
  end

  defp add_gallery_refs(refs, %{"gallery_images" => images}, block_index) when is_list(images) do
    Enum.reduce(images, refs, fn image, acc ->
      maybe_add_ref(acc, :asset, image["asset_id"], dgettext("sheets", "Block #%{n} gallery image", n: block_index))
    end)
  end

  defp add_gallery_refs(refs, _block, _block_index), do: refs

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]
end
