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

  alias Storyarn.Pages.{Block, BlockCrud, Page, PageCrud, PageVersion, TreeOperations, Versioning}
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
  defdelegate list_pages_tree(project_id), to: PageCrud

  @doc """
  Gets a single page by ID within a project.
  Returns `nil` if the page doesn't exist or doesn't belong to the project.
  """
  @spec get_page(id(), id()) :: page() | nil
  defdelegate get_page(project_id, page_id), to: PageCrud

  @doc """
  Gets a single page by ID within a project.
  Raises `Ecto.NoResultsError` if not found.
  """
  @spec get_page!(id(), id()) :: page()
  defdelegate get_page!(project_id, page_id), to: PageCrud

  @doc """
  Gets a page with all its ancestors for breadcrumb.
  Returns a list starting from the root and ending with the page itself.
  """
  @spec get_page_with_ancestors(id(), id()) :: [page()] | nil
  defdelegate get_page_with_ancestors(project_id, page_id), to: PageCrud

  @doc """
  Gets a page with all descendants loaded recursively.
  """
  @spec get_page_with_descendants(id(), id()) :: page() | nil
  defdelegate get_page_with_descendants(project_id, page_id), to: PageCrud

  @doc """
  Gets the children of a page.
  """
  @spec get_children(id()) :: [page()]
  defdelegate get_children(page_id), to: PageCrud

  @doc """
  Lists all leaf pages (pages with no children) for a project.
  Useful for speaker selection in dialogue nodes.
  """
  @spec list_leaf_pages(id()) :: [page()]
  defdelegate list_leaf_pages(project_id), to: PageCrud

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
  defdelegate list_trashed_pages(project_id), to: PageCrud

  @doc """
  Gets a trashed page by ID.
  """
  @spec get_trashed_page(id(), id()) :: page() | nil
  defdelegate get_trashed_page(project_id, page_id), to: PageCrud

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
  Deletes a block.
  """
  @spec delete_block(block()) :: {:ok, block()} | {:error, changeset()}
  defdelegate delete_block(block), to: BlockCrud

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
  """
  @spec create_version(page(), Storyarn.Accounts.User.t() | integer() | nil) ::
          {:ok, version()} | {:error, changeset()}
  defdelegate create_version(page, user_or_id), to: Versioning

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
end
