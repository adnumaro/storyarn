defmodule Storyarn.Pages.Versioning do
  @moduledoc """
  Functions for managing page version history.

  Versions are snapshots of a page's state at a point in time,
  including name, shortcut, avatar, banner, and all blocks.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Accounts.User
  alias Storyarn.Pages.{Block, Page, PageVersion}
  alias Storyarn.Repo

  @doc """
  Creates a new version snapshot of the given page.

  The snapshot includes:
  - Page metadata (name, shortcut, avatar_asset_id, banner_asset_id)
  - All blocks with their type, config, value, position, and variable settings

  Returns `{:ok, version}` or `{:error, changeset}`.
  """
  def create_version(%Page{} = page, %User{} = user) do
    create_version(page, user.id)
  end

  def create_version(%Page{} = page, user_id) when is_integer(user_id) or is_nil(user_id) do
    # Ensure page has blocks loaded
    page = Repo.preload(page, :blocks)

    # Get next version number
    version_number = next_version_number(page.id)

    # Build snapshot
    snapshot = build_snapshot(page)

    # Generate change summary by comparing with previous version
    change_summary = generate_change_summary(page.id, snapshot)

    # Create version record
    %PageVersion{}
    |> PageVersion.changeset(%{
      page_id: page.id,
      version_number: version_number,
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
        ngettext("Initial version with %{count} block", "Initial version with %{count} blocks", block_count, count: block_count)

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
        [ngettext("Added %{count} block", "Added %{count} blocks", added_count, count: added_count) | changes]
      else
        changes
      end

    changes =
      if removed_count > 0 do
        [ngettext("Removed %{count} block", "Removed %{count} blocks", removed_count, count: removed_count) | changes]
      else
        changes
      end

    changes =
      if modified_count > 0 do
        [ngettext("Modified %{count} block", "Modified %{count} blocks", modified_count, count: modified_count) | changes]
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
