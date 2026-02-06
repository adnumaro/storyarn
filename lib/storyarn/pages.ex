defmodule Storyarn.Pages do
  @moduledoc """
  The Pages context.

  Manages pages (tree nodes) and blocks (dynamic content fields) within a project.
  Pages form a free hierarchy tree, and each page can contain multiple blocks.

  This module serves as a facade, delegating to specialized submodules:
  - `PageCrud` - CRUD operations for pages
  - `BlockCrud` - CRUD operations for blocks
  - `TreeOperations` - Tree reordering and movement operations
  """

  alias Storyarn.Pages.{
    Block,
    BlockCrud,
    Page,
    PageCrud,
    PageQueries,
    PageVersion,
    TreeOperations,
    Versioning
  }

  alias Storyarn.Projects.Project

  # =============================================================================
  # Type Definitions
  # =============================================================================

  @type page :: Page.t()
  @type block :: Block.t()
  @type id :: integer()
  @type changeset :: Ecto.Changeset.t()
  @type attrs :: map()

  @type validation_error ::
          :cannot_be_own_parent
          | :parent_not_found
          | :parent_different_project
          | :would_create_cycle

  # =============================================================================
  # Pages - Tree Operations
  # =============================================================================

  @doc """
  Lists all pages for a project as a tree structure.
  Returns root pages (no parent) with children preloaded recursively.
  """
  @spec list_pages_tree(id()) :: [page()]
  defdelegate list_pages_tree(project_id), to: PageQueries

  @doc """
  Gets a single page by ID within a project.
  Returns `nil` if the page doesn't exist or doesn't belong to the project.
  """
  @spec get_page(id(), id()) :: page() | nil
  defdelegate get_page(project_id, page_id), to: PageQueries

  @doc """
  Gets a single page by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_page!(id(), id()) :: page()
  defdelegate get_page!(project_id, page_id), to: PageQueries

  @doc """
  Gets a page with all its ancestors for breadcrumb.
  Returns a list starting from the root and ending with the page itself.
  """
  @spec get_page_with_ancestors(id(), id()) :: [page()] | nil
  defdelegate get_page_with_ancestors(project_id, page_id), to: PageQueries

  @doc """
  Gets a page with all descendants loaded recursively.
  """
  @spec get_page_with_descendants(id(), id()) :: page() | nil
  defdelegate get_page_with_descendants(project_id, page_id), to: PageQueries

  @doc """
  Gets the children of a page.
  """
  @spec get_children(id()) :: [page()]
  defdelegate get_children(page_id), to: PageQueries

  @doc """
  Lists all leaf pages (pages with no children) for a project.
  Useful for speaker selection in dialogue nodes.
  """
  @spec list_leaf_pages(id()) :: [page()]
  defdelegate list_leaf_pages(project_id), to: PageQueries

  @doc """
  Gets a page by its shortcut within a project.
  Returns nil if not found.
  """
  @spec get_page_by_shortcut(id(), String.t()) :: page() | nil
  defdelegate get_page_by_shortcut(project_id, shortcut), to: PageQueries

  @doc """
  Lists all variables (blocks that can be variables) across all pages in a project.
  Used for the condition builder to list available variables.
  """
  @spec list_project_variables(id()) :: [map()]
  defdelegate list_project_variables(project_id), to: PageQueries

  # =============================================================================
  # Pages - CRUD Operations
  # =============================================================================

  @doc """
  Creates a new page in a project.
  """
  @spec create_page(Project.t(), attrs()) :: {:ok, page()} | {:error, changeset()}
  defdelegate create_page(project, attrs), to: PageCrud

  @doc """
  Updates a page.
  """
  @spec update_page(page(), attrs()) :: {:ok, page()} | {:error, changeset()}
  defdelegate update_page(page, attrs), to: PageCrud

  @doc """
  Soft deletes a page (moves to trash).
  Also soft deletes all descendant pages.
  """
  @spec delete_page(page()) :: {:ok, page()} | {:error, changeset()}
  defdelegate delete_page(page), to: PageCrud

  @doc """
  Soft deletes a page and all its descendants (moves to trash).
  Alias for `delete_page/1`.
  """
  @spec trash_page(page()) :: {:ok, page()} | {:error, changeset()}
  defdelegate trash_page(page), to: PageCrud

  @doc """
  Restores a soft-deleted page from trash.
  Note: Does not automatically restore descendants.
  """
  @spec restore_page(page()) :: {:ok, page()} | {:error, changeset()}
  defdelegate restore_page(page), to: PageCrud

  @doc """
  Permanently deletes a page and all its descendants.
  Use with caution - this cannot be undone.
  """
  @spec permanently_delete_page(page()) :: {:ok, page()} | {:error, changeset()}
  defdelegate permanently_delete_page(page), to: PageCrud

  @doc """
  Lists all trashed (soft-deleted) pages for a project.
  """
  @spec list_trashed_pages(id()) :: [page()]
  defdelegate list_trashed_pages(project_id), to: PageQueries

  @doc """
  Gets a trashed page by ID.
  """
  @spec get_trashed_page(id(), id()) :: page() | nil
  defdelegate get_trashed_page(project_id, page_id), to: PageQueries

  @doc """
  Moves a page to a new parent.
  Returns `{:ok, page}` or `{:error, reason}`.
  """
  @spec move_page(page(), id() | nil, integer() | nil) ::
          {:ok, page()} | {:error, validation_error() | changeset()}
  defdelegate move_page(page, parent_id, position \\ nil), to: PageCrud

  @doc """
  Returns a changeset for tracking page changes.
  """
  @spec change_page(page(), attrs()) :: changeset()
  defdelegate change_page(page, attrs \\ %{}), to: PageCrud

  @doc """
  Validates if a parent_id is valid for a page.
  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  @spec validate_parent(page(), id() | nil) :: :ok | {:error, validation_error()}
  defdelegate validate_parent(page, parent_id), to: PageCrud

  # =============================================================================
  # Pages - Reordering
  # =============================================================================

  @doc """
  Reorders pages within a parent container.
  """
  @spec reorder_pages(id(), id() | nil, [id()]) :: {:ok, [page()]} | {:error, term()}
  defdelegate reorder_pages(project_id, parent_id, page_ids), to: TreeOperations

  @doc """
  Moves a page to a new parent at a specific position, reordering siblings as needed.
  """
  @spec move_page_to_position(page(), id() | nil, integer()) ::
          {:ok, page()} | {:error, validation_error() | term()}
  def move_page_to_position(%Page{} = page, new_parent_id, new_position) do
    with :ok <- PageCrud.validate_parent(page, new_parent_id) do
      TreeOperations.move_page_to_position(page, new_parent_id, new_position)
    end
  end

  # =============================================================================
  # Blocks - CRUD Operations
  # =============================================================================

  @doc """
  Lists all blocks for a page, ordered by position.
  """
  @spec list_blocks(id()) :: [block()]
  defdelegate list_blocks(page_id), to: BlockCrud

  @doc """
  Gets a single block by ID.
  """
  @spec get_block(id()) :: block() | nil
  defdelegate get_block(block_id), to: BlockCrud

  @doc """
  Gets a single block by ID.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_block!(id()) :: block()
  defdelegate get_block!(block_id), to: BlockCrud

  @doc """
  Gets a block by ID, ensuring it belongs to the specified project.
  Returns nil if not found or not in project.
  """
  @spec get_block_in_project(id(), id()) :: block() | nil
  defdelegate get_block_in_project(block_id, project_id), to: BlockCrud

  @doc """
  Gets a block by ID with project validation. Raises if not found.
  """
  @spec get_block_in_project!(id(), id()) :: block()
  defdelegate get_block_in_project!(block_id, project_id), to: BlockCrud

  @doc """
  Creates a new block in a page.
  """
  @spec create_block(page(), attrs()) :: {:ok, block()} | {:error, changeset()}
  defdelegate create_block(page, attrs), to: BlockCrud

  @doc """
  Updates a block.
  """
  @spec update_block(block(), attrs()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block(block, attrs), to: BlockCrud

  @doc """
  Updates only the value of a block.
  """
  @spec update_block_value(block(), map()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block_value(block, value), to: BlockCrud

  @doc """
  Updates only the config of a block.
  """
  @spec update_block_config(block(), map()) :: {:ok, block()} | {:error, changeset()}
  defdelegate update_block_config(block, config), to: BlockCrud

  @doc """
  Soft-deletes a block by setting deleted_at timestamp.
  """
  @spec delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate delete_block(block), to: BlockCrud

  @doc """
  Permanently deletes a block from the database.
  """
  @spec permanently_delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate permanently_delete_block(block), to: BlockCrud

  @doc """
  Restores a soft-deleted block.
  """
  @spec restore_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate restore_block(block), to: BlockCrud

  @doc """
  Reorders blocks within a page.
  Takes a list of block IDs in the desired order.
  """
  @spec reorder_blocks(id(), [id()]) :: {:ok, [block()]} | {:error, term()}
  defdelegate reorder_blocks(page_id, block_ids), to: BlockCrud

  @doc """
  Returns a changeset for tracking block changes.
  """
  @spec change_block(block(), attrs()) :: changeset()
  defdelegate change_block(block, attrs \\ %{}), to: BlockCrud

  # =============================================================================
  # Versioning
  # =============================================================================

  @type version :: PageVersion.t()

  @doc """
  Creates a new version snapshot of the given page.
  The snapshot includes page metadata and all blocks.

  ## Options
  - `:title` - Custom title for the version (for manual versions)
  - `:description` - Optional description of changes
  """
  @spec create_version(page(), Storyarn.Accounts.User.t() | integer() | nil, keyword()) ::
          {:ok, version()} | {:error, changeset()}
  defdelegate create_version(page, user_or_id, opts \\ []), to: Versioning

  @doc """
  Lists all versions for a page, ordered by version number descending.
  """
  @spec list_versions(id(), keyword()) :: [version()]
  defdelegate list_versions(page_id, opts \\ []), to: Versioning

  @doc """
  Gets a specific version by page_id and version_number.
  """
  @spec get_version(id(), integer()) :: version() | nil
  defdelegate get_version(page_id, version_number), to: Versioning

  @doc """
  Gets the latest version for a page.
  """
  @spec get_latest_version(id()) :: version() | nil
  defdelegate get_latest_version(page_id), to: Versioning

  @doc """
  Returns the total number of versions for a page.
  """
  @spec count_versions(id()) :: integer()
  defdelegate count_versions(page_id), to: Versioning

  @doc """
  Creates a version if enough time has passed since the last version (rate limited).
  Returns `{:ok, version}`, `{:skipped, :too_recent}`, or `{:error, changeset}`.
  """
  @spec maybe_create_version(page(), Storyarn.Accounts.User.t() | integer() | nil, keyword()) ::
          {:ok, version()} | {:skipped, :too_recent} | {:error, changeset()}
  defdelegate maybe_create_version(page, user_or_id, opts \\ []), to: Versioning

  @doc """
  Deletes a version.
  If the deleted version is the current_version of its page, clears the reference.
  """
  @spec delete_version(version()) :: {:ok, version()} | {:error, changeset()}
  defdelegate delete_version(version), to: Versioning

  @doc """
  Sets the current version for a page.
  This marks the version as "active" without modifying page content.
  """
  @spec set_current_version(page(), version() | nil) :: {:ok, page()} | {:error, changeset()}
  defdelegate set_current_version(page, version), to: Versioning

  @doc """
  Restores a page to a specific version.
  Applies the snapshot (metadata and blocks) and sets as current version.
  Does NOT create a new version.
  """
  @spec restore_version(page(), version()) :: {:ok, page()} | {:error, term()}
  defdelegate restore_version(page, version), to: Versioning

  # =============================================================================
  # Reference Search & Validation
  # =============================================================================

  @doc """
  Validates that a reference target exists and belongs to the project.
  Returns {:ok, target} or {:error, reason}.
  """
  @spec validate_reference_target(String.t(), id(), id()) ::
          {:ok, Page.t() | Storyarn.Flows.Flow.t()} | {:error, :not_found | :invalid_type}
  defdelegate validate_reference_target(target_type, target_id, project_id), to: PageQueries

  @doc """
  Searches for pages and flows that can be referenced.

  Returns a list of maps with :type, :id, :name, :shortcut keys.
  """
  @spec search_referenceable(id(), String.t(), [String.t()]) :: [map()]
  def search_referenceable(project_id, query, allowed_types \\ ["page", "flow"]) do
    query = String.trim(query)

    results = []

    results =
      if "page" in allowed_types do
        pages = PageQueries.search_pages(project_id, query)

        page_results =
          Enum.map(pages, fn page ->
            %{type: "page", id: page.id, name: page.name, shortcut: page.shortcut}
          end)

        results ++ page_results
      else
        results
      end

    results =
      if "flow" in allowed_types do
        flows = Storyarn.Flows.search_flows(project_id, query)

        flow_results =
          Enum.map(flows, fn flow ->
            %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
          end)

        results ++ flow_results
      else
        results
      end

    # Sort by name and limit to 20 results
    results
    |> Enum.sort_by(& &1.name)
    |> Enum.take(20)
  end

  @doc """
  Gets the reference target (page or flow) for display.
  Returns nil if not found.
  """
  @spec get_reference_target(String.t() | nil, id() | nil, id()) :: map() | nil
  def get_reference_target(nil, _target_id, _project_id), do: nil
  def get_reference_target(_target_type, nil, _project_id), do: nil

  def get_reference_target("page", target_id, project_id) do
    case PageQueries.get_page(project_id, target_id) do
      nil -> nil
      page -> %{type: "page", id: page.id, name: page.name, shortcut: page.shortcut}
    end
  end

  def get_reference_target("flow", target_id, project_id) do
    case Storyarn.Flows.get_flow(project_id, target_id) do
      nil -> nil
      flow -> %{type: "flow", id: flow.id, name: flow.name, shortcut: flow.shortcut}
    end
  end

  # =============================================================================
  # Reference Tracking (Backlinks)
  # =============================================================================

  alias Storyarn.Pages.ReferenceTracker

  @doc """
  Updates references from a block.
  Called after block content is saved to track mentions and references.
  """
  @spec update_block_references(block()) :: :ok
  defdelegate update_block_references(block), to: ReferenceTracker

  @doc """
  Deletes all references from a block.
  Called when a block is deleted.
  """
  @spec delete_block_references(id()) :: {integer(), nil}
  defdelegate delete_block_references(block_id), to: ReferenceTracker

  @doc """
  Gets backlinks for a target with resolved source information.
  """
  @spec get_backlinks_with_sources(String.t(), id(), id()) :: [map()]
  defdelegate get_backlinks_with_sources(target_type, target_id, project_id), to: ReferenceTracker

  @doc """
  Counts backlinks for a target.
  """
  @spec count_backlinks(String.t(), id()) :: integer()
  defdelegate count_backlinks(target_type, target_id), to: ReferenceTracker
end
