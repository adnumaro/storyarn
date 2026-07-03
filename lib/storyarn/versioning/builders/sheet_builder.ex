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

  alias Ecto.Multi
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Sheets.TableColumn
  alias Storyarn.Sheets.TableRow
  alias Storyarn.Versioning.Builders.AssetHashResolver
  alias Storyarn.Versioning.DiffHelpers
  alias Storyarn.Versioning.MaterializationHelpers

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Sheet{} = sheet) do
    active_blocks = from(b in Block, where: is_nil(b.deleted_at), order_by: [asc: b.position])

    sheet =
      Repo.preload(
        sheet,
        [blocks: {active_blocks, [:table_columns, :table_rows, gallery_images: :asset]}, avatars: :asset],
        force: true
      )

    avatar_snapshots = Enum.map(sorted_avatars(sheet.avatars), &avatar_to_snapshot/1)
    block_snapshots = Enum.map(sheet.blocks, &block_to_snapshot/1)
    default_avatar_asset_id = default_avatar_asset_id(sheet)
    asset_ids = [sheet.banner_asset_id | snapshot_asset_ids(avatar_snapshots, block_snapshots)]
    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    %{
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
      "asset_metadata" => metadata_map
    }
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
      "required" => block.required
    }

    base
    |> maybe_put_table_data(block)
    |> maybe_put_gallery_images(block)
  end

  defp maybe_put_table_data(snapshot, %Block{type: "table"} = block) do
    Map.put(snapshot, "table_data", %{
      "columns" => Enum.map(block.table_columns, &column_to_snapshot/1),
      "rows" => Enum.map(block.table_rows, &row_to_snapshot/1)
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
      "name" => row.name,
      "slug" => row.slug,
      "position" => row.position,
      "cells" => row.cells || %{}
    }
  end

  # ========== Restore Snapshot ==========

  @impl true
  def instantiate_snapshot(project_id, snapshot, opts \\ []) do
    fn ->
      now = MaterializationHelpers.now()
      preserve_external_refs? = MaterializationHelpers.preserve_external_refs?(opts)
      avatar_entries = build_avatar_entries(snapshot, project_id, now, opts)

      sheet_attrs =
        Map.merge(
          %{
            project_id: project_id,
            name: snapshot["name"],
            shortcut: MaterializationHelpers.root_shortcut(snapshot, opts),
            description: snapshot["description"],
            color: snapshot["color"],
            hidden_inherited_block_ids: snapshot["hidden_inherited_block_ids"] || [],
            banner_asset_id: resolve_sheet_asset(snapshot["banner_asset_id"], snapshot, project_id, opts),
            parent_id: MaterializationHelpers.root_parent_id(opts),
            position: MaterializationHelpers.root_position(opts)
          },
          MaterializationHelpers.timestamps(now)
        )

      with {:ok, sheet_id} <-
             MaterializationHelpers.insert_one_returning_id(Repo, Sheet, sheet_attrs),
           :ok <- insert_sheet_avatars(sheet_id, avatar_entries),
           {:ok, inserted_blocks, block_id_map} <-
             insert_sheet_blocks(sheet_id, snapshot["blocks"] || [], now),
           :ok <-
             remap_sheet_block_inheritance(
               inserted_blocks,
               snapshot["blocks"] || [],
               block_id_map,
               preserve_external_refs?
             ),
           :ok <- restore_table_data(Repo, inserted_blocks, snapshot["blocks"] || [], now),
           :ok <- restore_gallery_images(Repo, inserted_blocks, snapshot, project_id, now, opts) do
        sheet =
          Sheet
          |> Repo.get!(sheet_id)
          |> Repo.preload([:banner_asset, :blocks, avatars: :asset], force: true)

        id_maps = %{
          sheet: MaterializationHelpers.root_id_map(snapshot, sheet_id),
          block: block_id_map
        }

        {sheet, id_maps}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end
    |> Repo.transaction()
    |> case do
      {:ok, {sheet, id_maps}} -> {:ok, sheet, id_maps}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def restore_snapshot(%Sheet{} = sheet, snapshot, opts \\ []) do
    avatar_entries = build_avatar_entries(snapshot, sheet.project_id, MaterializationHelpers.now(), opts)

    Multi.new()
    |> Multi.update(:sheet, fn _changes ->
      Sheet.update_changeset(sheet, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        color: snapshot["color"],
        banner_asset_id:
          resolve_sheet_asset(
            snapshot["banner_asset_id"],
            snapshot,
            sheet.project_id,
            opts
          )
      })
    end)
    |> Multi.delete_all(:delete_avatars, fn _changes ->
      from(sa in SheetAvatar, where: sa.sheet_id == ^sheet.id)
    end)
    |> Multi.run(:restore_avatar, fn _repo, _changes ->
      case insert_sheet_avatars(sheet.id, avatar_entries) do
        :ok -> {:ok, length(avatar_entries)}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Multi.delete_all(:delete_blocks, fn _changes ->
      from(b in Block, where: b.sheet_id == ^sheet.id)
    end)
    |> Multi.run(:restore_blocks, fn repo, _changes ->
      restore_blocks_from_snapshot(repo, sheet.id, sheet.project_id, snapshot, opts)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{sheet: updated_sheet}} ->
        {:ok, Repo.preload(updated_sheet, [:banner_asset, :blocks, avatars: :asset], force: true)}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_blocks_from_snapshot(repo, sheet_id, project_id, snapshot, opts) do
    blocks_data = snapshot["blocks"] || []

    if blocks_data == [] do
      {:ok, 0}
    else
      now = MaterializationHelpers.now()
      existing_source_ids = load_existing_source_ids(repo, blocks_data)

      sorted_data = Enum.sort_by(blocks_data, & &1["position"])

      blocks =
        sorted_data
        |> Enum.map(&snapshot_to_block_entry(&1, sheet_id, existing_source_ids, now))
        |> deduplicate_variable_names(MapSet.new())

      {count, inserted} = repo.insert_all(Block, blocks, returning: [:id, :type, :position])

      with :ok <- restore_table_data(repo, inserted, sorted_data, now),
           :ok <- restore_gallery_images(repo, inserted, snapshot, project_id, now, opts) do
        {:ok, count}
      end
    end
  end

  defp load_existing_source_ids(repo, blocks_data) do
    source_block_ids =
      blocks_data
      |> Enum.map(& &1["inherited_from_block_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if source_block_ids == [] do
      MapSet.new()
    else
      from(b in Block, where: b.id in ^source_block_ids and is_nil(b.deleted_at), select: b.id)
      |> repo.all()
      |> MapSet.new()
    end
  end

  # Ensure variable_name is unique per sheet — append _2, _3 etc. for duplicates.
  # `initial_seen` contains variable names from preserved blocks (selective merge).
  defp deduplicate_variable_names(blocks, initial_seen) do
    {deduped, _seen} =
      Enum.map_reduce(blocks, initial_seen, fn block, seen ->
        vn = block[:variable_name]

        if vn && MapSet.member?(seen, vn) do
          new_vn = find_unique_name(vn, seen, 2)
          {%{block | variable_name: new_vn}, MapSet.put(seen, new_vn)}
        else
          {block, if(vn, do: MapSet.put(seen, vn), else: seen)}
        end
      end)

    deduped
  end

  defp find_unique_name(base, seen, n) do
    candidate = "#{base}_#{n}"
    if MapSet.member?(seen, candidate), do: find_unique_name(base, seen, n + 1), else: candidate
  end

  defp snapshot_to_block_entry(block_data, sheet_id, existing_source_ids, now) do
    {inherited_from, detached} = resolve_inheritance(block_data, existing_source_ids)

    %{
      sheet_id: sheet_id,
      type: block_data["type"],
      position: block_data["position"],
      config: block_data["config"] || %{},
      value: block_data["value"] || %{},
      is_constant: block_data["is_constant"] || false,
      variable_name: block_data["variable_name"],
      scope: block_data["scope"] || "self",
      inherited_from_block_id: inherited_from,
      detached: detached,
      required: block_data["required"] || false,
      inserted_at: now,
      updated_at: now
    }
  end

  defp restore_table_data(_repo, [], _sorted_data, _now), do: :ok

  defp restore_table_data(repo, inserted_blocks, sorted_data, now) do
    inserted_by_position = Map.new(inserted_blocks, &{&1.position, &1})

    sorted_data
    |> Enum.filter(&(&1["type"] == "table" && is_map(&1["table_data"])))
    |> Enum.each(fn block_data ->
      case Map.get(inserted_by_position, block_data["position"]) do
        nil -> :skip
        block -> insert_table_data(repo, block.id, block_data["table_data"], now)
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

  defp restore_gallery_images(_repo, [], _snapshot, _project_id, _now, _opts), do: :ok

  defp restore_gallery_images(repo, inserted_blocks, snapshot, project_id, now, opts) do
    inserted_by_position = Map.new(inserted_blocks, &{&1.position, &1.id})

    entries =
      snapshot
      |> Map.get("blocks", [])
      |> Enum.flat_map(fn block_data ->
        block_id = Map.get(inserted_by_position, block_data["position"])
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

  defp insert_sheet_blocks(_sheet_id, [], _now), do: {:ok, [], %{}}

  defp insert_sheet_blocks(sheet_id, blocks_data, now) do
    sorted_data = Enum.sort_by(blocks_data, & &1["position"])

    entries =
      Enum.map(sorted_data, fn block_data ->
        Map.merge(
          %{
            sheet_id: sheet_id,
            type: block_data["type"],
            position: block_data["position"],
            config: block_data["config"] || %{},
            value: block_data["value"] || %{},
            is_constant: block_data["is_constant"] || false,
            variable_name: block_data["variable_name"],
            scope: block_data["scope"] || "self",
            inherited_from_block_id: block_data["inherited_from_block_id"],
            detached: block_data["detached"] || false,
            required: block_data["required"] || false
          },
          MaterializationHelpers.timestamps(now)
        )
      end)

    case MaterializationHelpers.insert_all_returning(Repo, Block, entries, [:id, :position]) do
      {:ok, inserted_blocks} ->
        {:ok, inserted_blocks, MaterializationHelpers.build_id_map(sorted_data, inserted_blocks)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remap_sheet_block_inheritance(inserted_blocks, blocks_data, block_id_map, preserve_external_refs?) do
    inserted_by_position = Map.new(inserted_blocks, &{&1.position, &1.id})

    Enum.reduce_while(blocks_data, :ok, fn block_data, :ok ->
      inherited_from = block_data["inherited_from_block_id"]

      case Map.get(inserted_by_position, block_data["position"]) do
        nil ->
          {:halt, {:error, :missing_inserted_block}}

        block_id ->
          remapped =
            MaterializationHelpers.remap_reference(
              inherited_from,
              block_id_map,
              preserve_external_refs?
            )

          update_inherited_from_block(block_id, remapped)
      end
    end)
  end

  defp resolve_sheet_asset(asset_id, snapshot, project_id, opts) do
    case sheet_asset_mode(opts) do
      :drop ->
        nil

      asset_mode ->
        AssetHashResolver.resolve_asset_fk(asset_id, snapshot, project_id, Keyword.get(opts, :user_id),
          asset_mode: asset_mode
        )
    end
  end

  defp sheet_asset_mode(opts) do
    cond do
      mode = Keyword.get(opts, :asset_mode) ->
        mode

      MaterializationHelpers.preserve_external_refs?(opts) ->
        :reuse

      true ->
        :drop
    end
  end

  defp default_avatar_asset_id(%{avatars: avatars}) when is_list(avatars) do
    case Enum.find(avatars, & &1.is_default) || List.first(avatars) do
      %{asset_id: id} -> id
      _ -> nil
    end
  end

  defp default_avatar_asset_id(_), do: nil

  defp sorted_avatars(avatars) when is_list(avatars) do
    Enum.sort_by(avatars, &{&1.position || 0, &1.id || 0})
  end

  defp sorted_avatars(_avatars), do: []

  defp sorted_gallery_images(images) when is_list(images) do
    Enum.sort_by(images, &{&1.position || 0, &1.id || 0})
  end

  defp sorted_gallery_images(_images), do: []

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
    if Enum.any?(entries, & &1.is_default) do
      entries
    else
      [first | rest] = entries
      [%{first | is_default: true} | rest]
    end
  end

  defp insert_sheet_avatars(_sheet_id, []), do: :ok

  defp insert_sheet_avatars(sheet_id, avatar_entries) do
    entries = Enum.map(avatar_entries, &Map.put(&1, :sheet_id, sheet_id))
    MaterializationHelpers.insert_all(Repo, SheetAvatar, entries)
  end

  defp update_inherited_from_block(block_id, remapped) do
    case Repo.update_all(from(b in Block, where: b.id == ^block_id),
           set: [inherited_from_block_id: remapped]
         ) do
      {1, _} -> {:cont, :ok}
      _ -> {:halt, {:error, :inheritance_remap_failed}}
    end
  end

  defp resolve_inheritance(block_data, existing_source_ids) do
    inherited_from = block_data["inherited_from_block_id"]

    if inherited_from && !MapSet.member?(existing_source_ids, inherited_from) do
      {nil, true}
    else
      {inherited_from, block_data["detached"] || false}
    end
  end

  # ========== Diff Snapshots ==========

  @block_compare_fields ~w(type config value is_constant variable_name scope required detached inherited_from_block_id table_data gallery_images)

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
    |> diff_blocks(old_snapshot["blocks"] || [], new_snapshot["blocks"] || [])
    |> Enum.reverse()
  end

  defp diff_blocks(changes, old_blocks, new_blocks) do
    key_fns = [
      # Primary: match by variable_name (stable identifier for most blocks)
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

  defp add_gallery_refs(refs, %{"gallery_images" => images}, block_index) when is_list(images) do
    Enum.reduce(images, refs, fn image, acc ->
      maybe_add_ref(acc, :asset, image["asset_id"], dgettext("sheets", "Block #%{n} gallery image", n: block_index))
    end)
  end

  defp add_gallery_refs(refs, _block, _block_index), do: refs

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context), do: [%{type: type, id: id, context: context} | refs]
end
