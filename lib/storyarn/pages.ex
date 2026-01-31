defmodule Storyarn.Pages do
  @moduledoc """
  The Pages context.

  Manages pages (tree nodes) and blocks (dynamic content fields) within a project.
  Pages form a free hierarchy tree, and each page can contain multiple blocks.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Pages.{Block, Page, PageOperations}
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  # =============================================================================
  # Delegations
  # =============================================================================

  @doc """
  Reorders pages within a parent container.

  Takes a project_id, parent_id (nil for root level), and a list of page IDs
  in the desired order. Updates all positions in a single transaction.
  """
  defdelegate reorder_pages(project_id, parent_id, page_ids), to: PageOperations

  @doc """
  Moves a page to a new parent at a specific position, reordering siblings as needed.

  This function handles both same-parent reordering and cross-parent moves.
  It validates the parent to prevent cycles, then updates positions for all affected containers.
  """
  def move_page_to_position(%Page{} = page, new_parent_id, new_position) do
    with :ok <- validate_parent(page, new_parent_id) do
      PageOperations.move_page_to_position(page, new_parent_id, new_position)
    end
  end

  # =============================================================================
  # Pages - Tree Operations
  # =============================================================================

  @doc """
  Lists all pages for a project as a tree structure.

  Returns root pages (no parent) with children preloaded recursively.
  """
  def list_pages_tree(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and is_nil(p.parent_id),
      order_by: [asc: p.position, asc: p.name]
    )
    |> Repo.all()
    |> preload_children_recursive()
  end

  @doc """
  Gets a single page by ID within a project.

  Returns `nil` if the page doesn't exist or doesn't belong to the project.
  """
  def get_page(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> preload(:blocks)
    |> Repo.one()
  end

  @doc """
  Gets a single page by ID within a project.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_page!(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> preload(:blocks)
    |> Repo.one!()
  end

  @doc """
  Gets a page with all its ancestors for breadcrumb.

  Returns a list starting from the root and ending with the page itself.
  """
  def get_page_with_ancestors(project_id, page_id) do
    case get_page(project_id, page_id) do
      nil -> nil
      page -> build_ancestor_chain(page, [page])
    end
  end

  defp build_ancestor_chain(%Page{parent_id: nil}, chain), do: chain

  defp build_ancestor_chain(%Page{parent_id: parent_id, project_id: project_id}, chain) do
    parent = Repo.get!(Page, parent_id)

    if parent.project_id == project_id do
      build_ancestor_chain(parent, [parent | chain])
    else
      chain
    end
  end

  @doc """
  Gets a page with all descendants loaded recursively.
  """
  def get_page_with_descendants(project_id, page_id) do
    case get_page(project_id, page_id) do
      nil -> nil
      page -> page |> preload_children_recursive() |> List.wrap() |> List.first()
    end
  end

  # =============================================================================
  # Pages - CRUD Operations
  # =============================================================================

  @doc """
  Creates a new page in a project.
  """
  def create_page(%Project{} = project, attrs) do
    position = attrs[:position] || next_position(project.id, attrs[:parent_id])

    %Page{project_id: project.id}
    |> Page.create_changeset(Map.put(attrs, :position, position))
    |> Repo.insert()
  end

  @doc """
  Updates a page.
  """
  def update_page(%Page{} = page, attrs) do
    page
    |> Page.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a page and all its blocks.

  Children pages will have their parent_id set to nil (become root pages).
  """
  def delete_page(%Page{} = page) do
    Repo.delete(page)
  end

  @doc """
  Moves a page to a new parent.

  Returns `{:ok, page}` or `{:error, reason}`.
  """
  def move_page(%Page{} = page, parent_id, position \\ nil) do
    with :ok <- validate_parent(page, parent_id) do
      position = position || next_position(page.project_id, parent_id)

      page
      |> Page.move_changeset(%{parent_id: parent_id, position: position})
      |> Repo.update()
    end
  end

  @doc """
  Returns a changeset for tracking page changes.
  """
  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.update_changeset(page, attrs)
  end

  @doc """
  Gets the children of a page.
  """
  def get_children(page_id) do
    from(p in Page,
      where: p.parent_id == ^page_id,
      order_by: [asc: p.position, asc: p.name]
    )
    |> Repo.all()
  end

  # =============================================================================
  # Pages - Validation Helpers
  # =============================================================================

  @doc """
  Validates if a parent_id is valid for a page.

  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  def validate_parent(%Page{} = page, parent_id) do
    cond do
      is_nil(parent_id) ->
        :ok

      parent_id == page.id ->
        {:error, :cannot_be_own_parent}

      true ->
        case Repo.get(Page, parent_id) do
          nil ->
            {:error, :parent_not_found}

          parent ->
            validate_parent_page(page, parent)
        end
    end
  end

  defp validate_parent_page(page, parent) do
    cond do
      parent.project_id != page.project_id ->
        {:error, :parent_different_project}

      descendant?(parent.id, page.id) ->
        {:error, :would_create_cycle}

      true ->
        :ok
    end
  end

  # =============================================================================
  # Blocks - CRUD Operations
  # =============================================================================

  @doc """
  Lists all blocks for a page, ordered by position.
  """
  def list_blocks(page_id) do
    from(b in Block,
      where: b.page_id == ^page_id,
      order_by: [asc: b.position]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single block by ID.
  """
  def get_block(block_id) do
    Repo.get(Block, block_id)
  end

  @doc """
  Gets a single block by ID.

  Raises `Ecto.NoResultsError` if not found.
  """
  def get_block!(block_id) do
    Repo.get!(Block, block_id)
  end

  @doc """
  Creates a new block in a page.
  """
  def create_block(%Page{} = page, attrs) do
    position = attrs[:position] || next_block_position(page.id)

    config = attrs[:config] || Block.default_config(attrs[:type] || attrs["type"])
    value = attrs[:value] || Block.default_value(attrs[:type] || attrs["type"])

    %Block{page_id: page.id}
    |> Block.create_changeset(
      attrs
      |> Map.put(:position, position)
      |> Map.put_new(:config, config)
      |> Map.put_new(:value, value)
    )
    |> Repo.insert()
  end

  @doc """
  Updates a block.
  """
  def update_block(%Block{} = block, attrs) do
    block
    |> Block.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates only the value of a block.
  """
  def update_block_value(%Block{} = block, value) do
    block
    |> Block.value_changeset(%{value: value})
    |> Repo.update()
  end

  @doc """
  Updates only the config of a block.
  """
  def update_block_config(%Block{} = block, config) do
    block
    |> Block.config_changeset(%{config: config})
    |> Repo.update()
  end

  @doc """
  Deletes a block.
  """
  def delete_block(%Block{} = block) do
    Repo.delete(block)
  end

  @doc """
  Reorders blocks within a page.

  Takes a list of block IDs in the desired order.
  """
  def reorder_blocks(page_id, block_ids) when is_list(block_ids) do
    Repo.transaction(fn ->
      block_ids
      |> Enum.reject(&is_nil/1)
      |> Enum.with_index()
      |> Enum.each(fn {block_id, index} ->
        from(b in Block,
          where: b.id == ^block_id and b.page_id == ^page_id
        )
        |> Repo.update_all(set: [position: index])
      end)

      list_blocks(page_id)
    end)
  end

  @doc """
  Returns a changeset for tracking block changes.
  """
  def change_block(%Block{} = block, attrs \\ %{}) do
    Block.update_changeset(block, attrs)
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp preload_children_recursive(pages) when is_list(pages) do
    Enum.map(pages, &preload_children_recursive/1)
  end

  defp preload_children_recursive(%Page{} = page) do
    children =
      from(p in Page,
        where: p.parent_id == ^page.id,
        order_by: [asc: p.position, asc: p.name]
      )
      |> Repo.all()
      |> preload_children_recursive()

    %{page | children: children}
  end

  defp get_descendant_ids(page_id) do
    direct_children_ids =
      from(p in Page,
        where: p.parent_id == ^page_id,
        select: p.id
      )
      |> Repo.all()

    Enum.flat_map(direct_children_ids, fn child_id ->
      [child_id | get_descendant_ids(child_id)]
    end)
  end

  defp descendant?(potential_descendant_id, ancestor_id) do
    descendant_ids = get_descendant_ids(ancestor_id)
    potential_descendant_id in descendant_ids
  end

  defp next_position(project_id, parent_id) do
    query =
      from(p in Page,
        where: p.project_id == ^project_id,
        select: max(p.position)
      )

    query =
      if is_nil(parent_id) do
        where(query, [p], is_nil(p.parent_id))
      else
        where(query, [p], p.parent_id == ^parent_id)
      end

    (Repo.one(query) || -1) + 1
  end

  defp next_block_position(page_id) do
    query =
      from(b in Block,
        where: b.page_id == ^page_id,
        select: max(b.position)
      )

    (Repo.one(query) || -1) + 1
  end
end
