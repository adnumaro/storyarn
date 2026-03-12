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
    sheet = Repo.preload(sheet, blocks: [:table_columns, :table_rows])

    asset_ids = [sheet.avatar_asset_id, sheet.banner_asset_id]
    {hash_map, metadata_map} = AssetHashResolver.resolve_hashes(asset_ids)

    %{
      "name" => sheet.name,
      "shortcut" => sheet.shortcut,
      "avatar_asset_id" => sheet.avatar_asset_id,
      "banner_asset_id" => sheet.banner_asset_id,
      "blocks" => Enum.map(sheet.blocks, &block_to_snapshot/1),
      "asset_blob_hashes" => hash_map,
      "asset_metadata" => metadata_map
    }
  end

  defp block_to_snapshot(%Block{} = block) do
    base = %{
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
  def restore_snapshot(%Sheet{} = sheet, snapshot, _opts \\ []) do
    Multi.new()
    |> Multi.update(:sheet, fn _changes ->
      Sheet.update_changeset(sheet, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
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
      from(b in Block, where: b.sheet_id == ^sheet.id)
    end)
    |> Multi.run(:restore_blocks, fn repo, _changes ->
      restore_blocks_from_snapshot(repo, sheet.id, snapshot["blocks"] || [])
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{sheet: updated_sheet}} ->
        {:ok, Repo.preload(updated_sheet, [:avatar_asset, :banner_asset, :blocks], force: true)}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_blocks_from_snapshot(_repo, _sheet_id, []), do: {:ok, 0}

  defp restore_blocks_from_snapshot(repo, sheet_id, blocks_data) do
    now = TimeHelpers.now()
    existing_source_ids = load_existing_source_ids(repo, blocks_data)

    sorted_data = Enum.sort_by(blocks_data, & &1["position"])

    blocks =
      Enum.map(sorted_data, &snapshot_to_block_entry(&1, sheet_id, existing_source_ids, now))

    {count, inserted} = repo.insert_all(Block, blocks, returning: [:id, :type, :position])
    restore_table_data(repo, inserted, sorted_data, now)
    {:ok, count}
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

  @impl true
  def diff_snapshots(old_snapshot, new_snapshot) do
    changes =
      []
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "name",
        dgettext("sheets", "Renamed sheet")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "shortcut",
        dgettext("sheets", "Changed shortcut")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "avatar_asset_id",
        dgettext("sheets", "Changed avatar")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "banner_asset_id",
        dgettext("sheets", "Changed banner")
      )
      |> append_block_changes(old_snapshot["blocks"] || [], new_snapshot["blocks"] || [])

    format_change_summary(changes)
  end

  defp check_field_change(changes, old_snapshot, new_snapshot, field, message) do
    if old_snapshot[field] != new_snapshot[field] do
      [message | changes]
    else
      changes
    end
  end

  defp append_block_changes(changes, old_blocks, new_blocks) do
    old_positions = MapSet.new(old_blocks, & &1["position"])
    new_positions = MapSet.new(new_blocks, & &1["position"])

    added_count = MapSet.difference(new_positions, old_positions) |> MapSet.size()
    removed_count = MapSet.difference(old_positions, new_positions) |> MapSet.size()
    modified_count = count_modified_blocks(old_blocks, new_blocks, old_positions, new_positions)

    changes
    |> maybe_add_count(
      added_count,
      &dngettext("sheets", "Added %{count} block", "Added %{count} blocks", &1, count: &1)
    )
    |> maybe_add_count(
      removed_count,
      &dngettext("sheets", "Removed %{count} block", "Removed %{count} blocks", &1, count: &1)
    )
    |> maybe_add_count(
      modified_count,
      &dngettext("sheets", "Modified %{count} block", "Modified %{count} blocks", &1, count: &1)
    )
  end

  defp count_modified_blocks(old_blocks, new_blocks, old_positions, new_positions) do
    common_positions = MapSet.intersection(old_positions, new_positions)
    old_blocks_map = Map.new(old_blocks, &{&1["position"], &1})
    new_blocks_map = Map.new(new_blocks, &{&1["position"], &1})

    Enum.count(common_positions, fn pos ->
      old_blocks_map[pos] != new_blocks_map[pos]
    end)
  end

  defp maybe_add_count(changes, 0, _msg_fn), do: changes
  defp maybe_add_count(changes, count, msg_fn), do: [msg_fn.(count) | changes]

  defp format_change_summary([]), do: dgettext("sheets", "No changes detected")
  defp format_change_summary(changes), do: changes |> Enum.reverse() |> Enum.join(", ")

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
