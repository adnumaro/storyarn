defmodule Storyarn.Pages.Versioning do
  @moduledoc """
  Functions for managing page version history.

  Versions are snapshots of a page's state at a point in time,
  including name, shortcut, avatar, banner, and all blocks.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Ecto.Multi
  alias Storyarn.Accounts.User
  alias Storyarn.Pages.{Block, Page, PageVersion}
  alias Storyarn.Repo

  @doc """
  Creates a new version snapshot of the given page.

  ## Options
  - `:title` - Custom title for the version (for manual versions)
  - `:description` - Optional description of changes

  The snapshot includes:
  - Page metadata (name, shortcut, avatar_asset_id, banner_asset_id)
  - All blocks with their type, config, value, position, and variable settings

  Returns `{:ok, version}` or `{:error, changeset}`.
  """
  def create_version(page, user_or_id, opts \\ [])

  def create_version(%Page{} = page, %User{} = user, opts) do
    create_version(page, user.id, opts)
  end

  def create_version(%Page{} = page, user_id, opts) when is_integer(user_id) or is_nil(user_id) do
    # Ensure page has blocks loaded
    page = Repo.preload(page, :blocks)

    # Get next version number
    version_number = next_version_number(page.id)

    # Build snapshot
    snapshot = build_snapshot(page)

    # Custom title or auto-generated summary
    title = Keyword.get(opts, :title)
    description = Keyword.get(opts, :description)
    change_summary = if title, do: nil, else: generate_change_summary(page.id, snapshot)

    # Create version record
    %PageVersion{}
    |> PageVersion.changeset(%{
      page_id: page.id,
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
  Lists all versions for a page, ordered by version number descending.
  """
  def list_versions(page_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(v in PageVersion,
      where: v.page_id == ^page_id,
      order_by: [desc: v.version_number],
      limit: ^limit,
      preload: [:changed_by]
    )
    |> Repo.all()
  end

  @doc """
  Gets a specific version by page_id and version_number.
  """
  def get_version(page_id, version_number) do
    Repo.get_by(PageVersion, page_id: page_id, version_number: version_number)
  end

  @doc """
  Gets the latest version for a page.
  """
  def get_latest_version(page_id) do
    from(v in PageVersion,
      where: v.page_id == ^page_id,
      order_by: [desc: v.version_number],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Returns the total number of versions for a page.
  """
  def count_versions(page_id) do
    from(v in PageVersion, where: v.page_id == ^page_id, select: count(v.id))
    |> Repo.one()
  end

  @doc """
  Creates a version if enough time has passed since the last version.
  Default minimum interval is 5 minutes.

  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, changeset}`.
  """
  # 5 minutes
  @min_version_interval_seconds 300

  def maybe_create_version(%Page{} = page, user_or_id, opts \\ []) do
    min_interval = Keyword.get(opts, :min_interval, @min_version_interval_seconds)

    case get_latest_version(page.id) do
      nil ->
        # No previous version, create first one
        create_version(page, user_or_id, opts)

      latest ->
        seconds_since_last =
          NaiveDateTime.diff(NaiveDateTime.utc_now(), latest.inserted_at, :second)

        if seconds_since_last >= min_interval do
          create_version(page, user_or_id, opts)
        else
          {:skipped, :too_recent}
        end
    end
  end

  @doc """
  Deletes a version.
  If the deleted version is the current_version of its page, clears the reference.
  """
  def delete_version(%PageVersion{} = version) do
    Multi.new()
    |> Multi.run(:clear_current, fn repo, _changes ->
      # Clear current_version_id if this version is current
      page = repo.get!(Page, version.page_id)

      if page.current_version_id == version.id do
        page
        |> Page.version_changeset(%{current_version_id: nil})
        |> repo.update()
      else
        {:ok, page}
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
  Sets the current version for a page.
  This marks the version as "active" without modifying page content.
  """
  def set_current_version(%Page{} = page, %PageVersion{} = version) do
    page
    |> Page.version_changeset(%{current_version_id: version.id})
    |> Repo.update()
  end

  def set_current_version(%Page{} = page, nil) do
    page
    |> Page.version_changeset(%{current_version_id: nil})
    |> Repo.update()
  end

  @doc """
  Restores a page to a specific version.

  This applies the version's snapshot to the page:
  - Updates page metadata (name, shortcut, avatar, banner)
  - Deletes all current blocks
  - Recreates blocks from the snapshot

  Sets the version as current and does NOT create a new version.

  Returns `{:ok, page}` or `{:error, reason}`.
  """
  def restore_version(%Page{} = page, %PageVersion{} = version) do
    snapshot = version.snapshot

    Multi.new()
    |> Multi.update(:page, fn _changes ->
      Page.update_changeset(page, %{
        name: snapshot["name"],
        shortcut: snapshot["shortcut"],
        avatar_asset_id: snapshot["avatar_asset_id"],
        banner_asset_id: snapshot["banner_asset_id"]
      })
    end)
    |> Multi.delete_all(:delete_blocks, fn _changes ->
      from(b in Block, where: b.page_id == ^page.id)
    end)
    |> Multi.run(:restore_blocks, fn repo, _changes ->
      restore_blocks_from_snapshot(repo, page.id, snapshot["blocks"] || [])
    end)
    |> Multi.update(:set_current, fn %{page: updated_page} ->
      Page.version_changeset(updated_page, %{current_version_id: version.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{set_current: page}} ->
        {:ok,
         Repo.preload(page, [:avatar_asset, :banner_asset, :blocks, :current_version],
           force: true
         )}

      {:error, _op, reason, _changes} ->
        {:error, reason}
    end
  end

  defp restore_blocks_from_snapshot(_repo, _page_id, []), do: {:ok, 0}

  defp restore_blocks_from_snapshot(repo, page_id, blocks_data) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    blocks =
      blocks_data
      |> Enum.sort_by(& &1["position"])
      |> Enum.map(fn block_data ->
        %{
          page_id: page_id,
          type: block_data["type"],
          position: block_data["position"],
          config: block_data["config"] || %{},
          value: block_data["value"] || %{},
          is_constant: block_data["is_constant"] || false,
          variable_name: block_data["variable_name"],
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

  defp build_snapshot(%Page{} = page) do
    %{
      "name" => page.name,
      "shortcut" => page.shortcut,
      "avatar_asset_id" => page.avatar_asset_id,
      "banner_asset_id" => page.banner_asset_id,
      "blocks" => Enum.map(page.blocks, &block_to_snapshot/1)
    }
  end

  defp block_to_snapshot(%Block{} = block) do
    %{
      "id" => block.id,
      "type" => block.type,
      "position" => block.position,
      "config" => block.config,
      "value" => block.value,
      "is_constant" => block.is_constant,
      "variable_name" => block.variable_name
    }
  end

  # ===========================================================================
  # Change Summary Generation
  # ===========================================================================

  defp generate_change_summary(page_id, current_snapshot) do
    case get_latest_version(page_id) do
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
    changes = []

    # Check name change
    changes =
      if old_snapshot["name"] != new_snapshot["name"] do
        [gettext("Renamed page") | changes]
      else
        changes
      end

    # Check shortcut change
    changes =
      if old_snapshot["shortcut"] != new_snapshot["shortcut"] do
        [gettext("Changed shortcut") | changes]
      else
        changes
      end

    # Check avatar change
    changes =
      if old_snapshot["avatar_asset_id"] != new_snapshot["avatar_asset_id"] do
        [gettext("Changed avatar") | changes]
      else
        changes
      end

    # Check banner change
    changes =
      if old_snapshot["banner_asset_id"] != new_snapshot["banner_asset_id"] do
        [gettext("Changed banner") | changes]
      else
        changes
      end

    # Check blocks changes
    old_blocks = old_snapshot["blocks"] || []
    new_blocks = new_snapshot["blocks"] || []

    old_block_ids = MapSet.new(old_blocks, & &1["id"])
    new_block_ids = MapSet.new(new_blocks, & &1["id"])

    added_count = MapSet.difference(new_block_ids, old_block_ids) |> MapSet.size()
    removed_count = MapSet.difference(old_block_ids, new_block_ids) |> MapSet.size()

    # Check for modified blocks (same id, different content)
    common_ids = MapSet.intersection(old_block_ids, new_block_ids)
    old_blocks_map = Map.new(old_blocks, &{&1["id"], &1})
    new_blocks_map = Map.new(new_blocks, &{&1["id"], &1})

    modified_count =
      Enum.count(common_ids, fn id ->
        old_blocks_map[id] != new_blocks_map[id]
      end)

    changes =
      if added_count > 0 do
        [
          ngettext("Added %{count} block", "Added %{count} blocks", added_count,
            count: added_count
          )
          | changes
        ]
      else
        changes
      end

    changes =
      if removed_count > 0 do
        [
          ngettext("Removed %{count} block", "Removed %{count} blocks", removed_count,
            count: removed_count
          )
          | changes
        ]
      else
        changes
      end

    changes =
      if modified_count > 0 do
        [
          ngettext("Modified %{count} block", "Modified %{count} blocks", modified_count,
            count: modified_count
          )
          | changes
        ]
      else
        changes
      end

    case changes do
      [] -> gettext("No changes detected")
      _ -> Enum.reverse(changes) |> Enum.join(", ")
    end
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp next_version_number(page_id) do
    query =
      from(v in PageVersion,
        where: v.page_id == ^page_id,
        select: max(v.version_number)
      )

    (Repo.one(query) || 0) + 1
  end
end
