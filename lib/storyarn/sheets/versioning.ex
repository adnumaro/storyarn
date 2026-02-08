defmodule Storyarn.Sheets.Versioning do
  @moduledoc """
  Functions for managing sheet version history.

  Versions are snapshots of a sheet's state at a point in time,
  including name, shortcut, avatar, banner, and all blocks.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Ecto.Multi
  alias Storyarn.Accounts.User
  alias Storyarn.Sheets.{Block, Sheet, SheetVersion}
  alias Storyarn.Repo

  @doc """
  Creates a new version snapshot of the given sheet.

  ## Options
  - `:title` - Custom title for the version (for manual versions)
  - `:description` - Optional description of changes

  The snapshot includes:
  - Sheet metadata (name, shortcut, avatar_asset_id, banner_asset_id)
  - All blocks with their type, config, value, position, and variable settings

  Returns `{:ok, version}` or `{:error, changeset}`.
  """
  def create_version(sheet, user_or_id, opts \\ [])

  def create_version(%Sheet{} = sheet, %User{} = user, opts) do
    create_version(sheet, user.id, opts)
  end

  def create_version(%Sheet{} = sheet, user_id, opts) when is_integer(user_id) or is_nil(user_id) do
    # Ensure sheet has blocks loaded
    sheet = Repo.preload(sheet, :blocks)

    # Get next version number
    version_number = next_version_number(sheet.id)

    # Build snapshot
    snapshot = build_snapshot(sheet)

    # Custom title or auto-generated summary
    title = Keyword.get(opts, :title)
    description = Keyword.get(opts, :description)
    change_summary = if title, do: nil, else: generate_change_summary(sheet.id, snapshot)

    # Create version record
    %SheetVersion{}
    |> SheetVersion.changeset(%{
      sheet_id: sheet.id,
      version_number: version_number,
      title: title,
      description: description,
      snapshot: snapshot,
      changed_by_id: user_id,
      change_summary: change_summary
    })
    |> Repo.insert()
  end

  @doc """
  Lists all versions for a sheet, ordered by version number descending.

  ## Options

  - `:limit` - Maximum number of versions to return (default: 50)
  - `:offset` - Number of versions to skip (default: 0)
  """
  def list_versions(sheet_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    offset = Keyword.get(opts, :offset, 0)

    from(v in SheetVersion,
      where: v.sheet_id == ^sheet_id,
      order_by: [desc: v.version_number],
      limit: ^limit,
      offset: ^offset,
      preload: [:changed_by]
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific version by sheet_id and version_number.
  """
  def get_version(sheet_id, version_number) do
    Repo.get_by(SheetVersion, sheet_id: sheet_id, version_number: version_number)
  end

  @doc """
  Gets the latest version for a sheet.
  """
  def get_latest_version(sheet_id) do
    from(v in SheetVersion,
      where: v.sheet_id == ^sheet_id,
      order_by: [desc: v.version_number],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the total number of versions for a sheet.
  """
  def count_versions(sheet_id) do
    from(v in SheetVersion, where: v.sheet_id == ^sheet_id, select: count(v.id))
    |> Repo.one()
  end

  @doc """
  Creates a version if enough time has passed since the last version.
  Default minimum interval is 5 minutes.

  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, changeset}`.
  """
  # 5 minutes
  @min_version_interval_seconds 300

  def maybe_create_version(%Sheet{} = sheet, user_or_id, opts \\ []) do
    min_interval = Keyword.get(opts, :min_interval, @min_version_interval_seconds)

    case get_latest_version(sheet.id) do
      nil ->
        # No previous version, create first one
        create_version(sheet, user_or_id, opts)

      latest ->
        seconds_since_last =
          NaiveDateTime.diff(NaiveDateTime.utc_now(), latest.inserted_at, :second)

        if seconds_since_last >= min_interval do
          create_version(sheet, user_or_id, opts)
        else
          {:skipped, :too_recent}
        end
    end
  end

  @doc """
  Deletes a version.
  If the deleted version is the current_version of its sheet, clears the reference.
  """
  def delete_version(%SheetVersion{} = version) do
    Multi.new()
    |> Multi.run(:clear_current, fn repo, _changes ->
      # Clear current_version_id if this version is current
      sheet = repo.get!(Sheet, version.sheet_id)

      if sheet.current_version_id == version.id do
        sheet
        |> Sheet.version_changeset(%{current_version_id: nil})
        |> repo.update()
      else
        {:ok, sheet}
      end
    end)
    |> Multi.delete(:version, version)
    |> Repo.transaction()
    |> case do
      {:ok, %{version: version}} -> {:ok, version}
      {:error, _op, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Sets the current version for a sheet.
  This marks the version as "active" without modifying sheet content.
  """
  def set_current_version(%Sheet{} = sheet, %SheetVersion{} = version) do
    sheet
    |> Sheet.version_changeset(%{current_version_id: version.id})
    |> Repo.update()
  end

  def set_current_version(%Sheet{} = sheet, nil) do
    sheet
    |> Sheet.version_changeset(%{current_version_id: nil})
    |> Repo.update()
  end

  @doc """
  Restores a sheet to a specific version.

  This applies the version's snapshot to the sheet:
  - Updates sheet metadata (name, shortcut, avatar, banner)
  - Deletes all current blocks
  - Recreates blocks from the snapshot

  Sets the version as current and does NOT create a new version.

  Returns `{:ok, sheet}` or `{:error, reason}`.
  """
  def restore_version(%Sheet{} = sheet, %SheetVersion{} = version) do
    snapshot = version.snapshot

    Multi.new()
    |> Multi.update(:sheet, fn _changes ->
      Sheet.update_changeset(sheet, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        avatar_asset_id: snapshot["avatar_asset_id"],
        banner_asset_id: snapshot["banner_asset_id"]
      })
    end)
    |> Multi.delete_all(:delete_blocks, fn _changes ->
      from(b in Block, where: b.sheet_id == ^sheet.id)
    end)
    |> Multi.run(:restore_blocks, fn repo, _changes ->
      restore_blocks_from_snapshot(repo, sheet.id, snapshot["blocks"] || [])
    end)
    |> Multi.update(:set_current, fn %{sheet: updated_sheet} ->
      Sheet.version_changeset(updated_sheet, %{current_version_id: version.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{set_current: sheet}} ->
        {:ok,
         Repo.preload(sheet, [:avatar_asset, :banner_asset, :blocks, :current_version],
           force: true
         )}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_blocks_from_snapshot(_repo, _sheet_id, []), do: {:ok, 0}

  defp restore_blocks_from_snapshot(repo, sheet_id, blocks_data) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Collect all inherited_from_block_ids to validate in batch
    source_block_ids =
      blocks_data
      |> Enum.map(& &1["inherited_from_block_id"])
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    existing_source_ids =
      if source_block_ids == [] do
        MapSet.new()
      else
        from(b in Block, where: b.id in ^source_block_ids and is_nil(b.deleted_at), select: b.id)
        |> repo.all()
        |> MapSet.new()
      end

    blocks =
      blocks_data
      |> Enum.sort_by(& &1["position"])
      |> Enum.map(fn block_data ->
        inherited_from = block_data["inherited_from_block_id"]

        # If source block no longer exists, nilify reference and mark as detached
        {inherited_from, detached} =
          if inherited_from && !MapSet.member?(existing_source_ids, inherited_from) do
            {nil, true}
          else
            {inherited_from, block_data["detached"] || false}
          end

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
      end)

    {count, _} = repo.insert_all(Block, blocks)
    {:ok, count}
  end

  # ===========================================================================
  # Snapshot Building
  # ===========================================================================

  defp build_snapshot(%Sheet{} = sheet) do
    %{
      "name" => sheet.name,
      "shortcut" => sheet.shortcut,
      "avatar_asset_id" => sheet.avatar_asset_id,
      "banner_asset_id" => sheet.banner_asset_id,
      "blocks" => Enum.map(sheet.blocks, &block_to_snapshot/1)
    }
  end

  defp block_to_snapshot(%Block{} = block) do
    # Note: We intentionally exclude block.id from snapshots because
    # IDs become invalid after restore (new blocks are created with new IDs)
    %{
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
  end

  # ===========================================================================
  # Change Summary Generation
  # ===========================================================================

  defp generate_change_summary(sheet_id, current_snapshot) do
    case get_latest_version(sheet_id) do
      nil ->
        # First version
        block_count = length(current_snapshot["blocks"] || [])

        ngettext(
          "Initial version with %{count} block",
          "Initial version with %{count} blocks",
          block_count,
          count: block_count
        )

      previous ->
        diff_snapshots(previous.snapshot, current_snapshot)
    end
  end

  defp diff_snapshots(old_snapshot, new_snapshot) do
    changes =
      []
      |> check_field_change(old_snapshot, new_snapshot, "name", gettext("Renamed sheet"))
      |> check_field_change(old_snapshot, new_snapshot, "shortcut", gettext("Changed shortcut"))
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "avatar_asset_id",
        gettext("Changed avatar")
      )
      |> check_field_change(
        old_snapshot,
        new_snapshot,
        "banner_asset_id",
        gettext("Changed banner")
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
    |> maybe_add_added_blocks(added_count)
    |> maybe_add_removed_blocks(removed_count)
    |> maybe_add_modified_blocks(modified_count)
  end

  defp count_modified_blocks(old_blocks, new_blocks, old_positions, new_positions) do
    common_positions = MapSet.intersection(old_positions, new_positions)
    old_blocks_map = Map.new(old_blocks, &{&1["position"], &1})
    new_blocks_map = Map.new(new_blocks, &{&1["position"], &1})

    Enum.count(common_positions, fn pos ->
      old_blocks_map[pos] != new_blocks_map[pos]
    end)
  end

  defp maybe_add_added_blocks(changes, 0), do: changes

  defp maybe_add_added_blocks(changes, count) do
    [ngettext("Added %{count} block", "Added %{count} blocks", count, count: count) | changes]
  end

  defp maybe_add_removed_blocks(changes, 0), do: changes

  defp maybe_add_removed_blocks(changes, count) do
    [ngettext("Removed %{count} block", "Removed %{count} blocks", count, count: count) | changes]
  end

  defp maybe_add_modified_blocks(changes, 0), do: changes

  defp maybe_add_modified_blocks(changes, count) do
    [
      ngettext("Modified %{count} block", "Modified %{count} blocks", count, count: count)
      | changes
    ]
  end

  defp format_change_summary([]), do: gettext("No changes detected")
  defp format_change_summary(changes), do: changes |> Enum.reverse() |> Enum.join(", ")

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp next_version_number(sheet_id) do
    query =
      from(v in SheetVersion,
        where: v.sheet_id == ^sheet_id,
        select: max(v.version_number)
      )

    (Repo.one(query) || 0) + 1
  end
end
