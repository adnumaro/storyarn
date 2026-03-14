defmodule Storyarn.Versioning.Builders.SheetBuilder do
  @moduledoc """
  Snapshot builder for sheets.

  Captures sheet metadata (name, shortcut, avatar, banner) and all blocks
  with their type, config, value, position, and variable settings.
  """

  @behaviour Storyarn.Versioning.SnapshotBuilder

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Ecto.Multi
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Sheets.{Block, Sheet, TableColumn, TableRow}
  alias Storyarn.Versioning.Builders.AssetHashResolver

  # ========== Build Snapshot ==========

  @impl true
  def build_snapshot(%Sheet{} = sheet) do
    active_blocks = from(b in Block, where: is_nil(b.deleted_at), order_by: [asc: b.position])

    sheet =
      Repo.preload(sheet, [blocks: {active_blocks, [:table_columns, :table_rows]}], force: true)

    asset_ids = [sheet.avatar_asset_id, sheet.banner_asset_id]
    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    %{
      "name" => sheet.name,
      "shortcut" => sheet.shortcut,
      "avatar_asset_id" => sheet.avatar_asset_id,
      "banner_asset_id" => sheet.banner_asset_id,
      "color" => sheet.color,
      "blocks" => Enum.map(sheet.blocks, &block_to_snapshot/1),
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map
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

    if block.type == "table" do
      Map.put(base, "table_data", %{
        "columns" => Enum.map(block.table_columns, &column_to_snapshot/1),
        "rows" => Enum.map(block.table_rows, &row_to_snapshot/1)
      })
    else
      base
    end
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
  def restore_snapshot(%Sheet{} = sheet, snapshot, opts \\ []) do
    baseline_block_ids = Keyword.get(opts, :baseline_block_ids)

    Multi.new()
    |> Multi.update(:sheet, fn _changes ->
      Sheet.update_changeset(sheet, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        color: snapshot["color"],
        avatar_asset_id:
          AssetHashResolver.resolve_asset_fk(
            snapshot["avatar_asset_id"],
            snapshot,
            sheet.project_id
          ),
        banner_asset_id:
          AssetHashResolver.resolve_asset_fk(
            snapshot["banner_asset_id"],
            snapshot,
            sheet.project_id
          )
      })
    end)
    |> Multi.delete_all(:delete_blocks, fn _changes ->
      delete_blocks_query(sheet.id, baseline_block_ids)
    end)
    |> Multi.run(:restore_blocks, fn repo, _changes ->
      restore_blocks_from_snapshot(repo, sheet.id, snapshot["blocks"] || [], baseline_block_ids)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{sheet: updated_sheet}} ->
        {:ok, Repo.preload(updated_sheet, [:avatar_asset, :banner_asset, :blocks], force: true)}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  # Full replacement (version restore): delete all blocks
  defp delete_blocks_query(sheet_id, nil) do
    from(b in Block, where: b.sheet_id == ^sheet_id)
  end

  # Selective merge (draft merge): only delete blocks from the baseline
  # Blocks added to the original after draft creation are preserved
  defp delete_blocks_query(sheet_id, baseline_block_ids) do
    from(b in Block, where: b.sheet_id == ^sheet_id and b.id in ^baseline_block_ids)
  end

  defp restore_blocks_from_snapshot(_repo, _sheet_id, [], _baseline), do: {:ok, 0}

  defp restore_blocks_from_snapshot(repo, sheet_id, blocks_data, baseline_block_ids) do
    now = TimeHelpers.now()
    existing_source_ids = load_existing_source_ids(repo, blocks_data)

    # When doing selective merge, collect variable names from preserved blocks
    # (blocks not in the baseline that remain on the original)
    preserved_var_names = load_preserved_variable_names(repo, sheet_id, baseline_block_ids)

    sorted_data = Enum.sort_by(blocks_data, & &1["position"])

    blocks =
      sorted_data
      |> Enum.map(&snapshot_to_block_entry(&1, sheet_id, existing_source_ids, now))
      |> deduplicate_variable_names(preserved_var_names)

    {count, inserted} = repo.insert_all(Block, blocks, returning: [:id, :type, :position])
    restore_table_data(repo, inserted, sorted_data, now)
    {:ok, count}
  end

  # No preserved blocks in full replacement mode
  defp load_preserved_variable_names(_repo, _sheet_id, nil), do: MapSet.new()

  # Load variable names from blocks that will survive the merge (not in baseline)
  defp load_preserved_variable_names(repo, sheet_id, baseline_block_ids) do
    from(b in Block,
      where:
        b.sheet_id == ^sheet_id and
          b.id not in ^baseline_block_ids and
          is_nil(b.deleted_at) and
          not is_nil(b.variable_name),
      select: b.variable_name
    )
    |> repo.all()
    |> MapSet.new()
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

  defp resolve_inheritance(block_data, existing_source_ids) do
    inherited_from = block_data["inherited_from_block_id"]

    if inherited_from && !MapSet.member?(existing_source_ids, inherited_from) do
      {nil, true}
    else
      {inherited_from, block_data["detached"] || false}
    end
  end

  # ========== Diff Snapshots ==========

  alias Storyarn.Versioning.DiffHelpers

  @block_compare_fields ~w(type config value is_constant variable_name scope required detached inherited_from_block_id table_data)

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
    refs = []

    refs =
      refs
      |> maybe_add_ref(:asset, snapshot["avatar_asset_id"], dgettext("sheets", "Avatar image"))
      |> maybe_add_ref(:asset, snapshot["banner_asset_id"], dgettext("sheets", "Banner image"))

    (snapshot["blocks"] || [])
    |> Enum.with_index(1)
    |> Enum.reduce(refs, fn {block, idx}, acc ->
      maybe_add_ref(
        acc,
        :block,
        block["inherited_from_block_id"],
        dgettext("sheets", "Block #%{n} — inherited source", n: idx)
      )
    end)
  end

  defp maybe_add_ref(refs, _type, nil, _context), do: refs

  defp maybe_add_ref(refs, type, id, context),
    do: [%{type: type, id: id, context: context} | refs]
end
