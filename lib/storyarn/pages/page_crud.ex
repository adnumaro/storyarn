defmodule Storyarn.Pages.PageCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Pages.Page
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shortcuts

  # =============================================================================
  # Tree Operations
  # =============================================================================

  def list_pages_tree(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and is_nil(p.parent_id) and is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name]
    )
    |> Repo.all()
    |> preload_children_recursive()
  end

  def get_page(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> where([p], is_nil(p.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one()
  end

  def get_page!(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> where([p], is_nil(p.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one!()
  end

  def get_page_with_ancestors(project_id, page_id) do
    case get_page(project_id, page_id) do
      nil -> nil
      page -> build_ancestor_chain(page, [page])
    end
  end

  def get_page_with_descendants(project_id, page_id) do
    case get_page(project_id, page_id) do
      nil -> nil
      page -> page |> preload_children_recursive() |> List.wrap() |> List.first()
    end
  end

  def get_children(page_id) do
    from(p in Page,
      where: p.parent_id == ^page_id and is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @doc """
  Lists all leaf pages (pages with no children) for a project.
  Useful for speaker selection in dialogue nodes.
  """
  def list_leaf_pages(project_id) do
    # Subquery to find all pages that are parents (excluding deleted children)
    parent_ids_subquery =
      from(p in Page,
        where: p.project_id == ^project_id and not is_nil(p.parent_id) and is_nil(p.deleted_at),
        select: p.parent_id
      )

    from(p in Page,
      where:
        p.project_id == ^project_id and p.id not in subquery(parent_ids_subquery) and
          is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  def create_page(%Project{} = project, attrs) do
    # Normalize keys to strings for changeset
    attrs = stringify_keys(attrs)
    parent_id = attrs["parent_id"]
    position = attrs["position"] || next_position(project.id, parent_id)

    # Auto-generate shortcut from name if not provided
    attrs = maybe_generate_shortcut(attrs, project.id, nil)

    %Page{project_id: project.id}
    |> Page.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_page(%Page{} = page, attrs) do
    # Auto-generate shortcut if page has no shortcut and name is being updated
    attrs = maybe_generate_shortcut_on_update(page, attrs)

    page
    |> Page.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft deletes a page (moves to trash).
  Also soft deletes all descendant pages.
  """
  def delete_page(%Page{} = page) do
    trash_page(page)
  end

  @doc """
  Soft deletes a page and all its descendants (moves to trash).
  """
  def trash_page(%Page{} = page) do
    Repo.transaction(fn ->
      # Get all descendant IDs before deleting
      descendant_ids = get_descendant_ids(page.id)

      # Soft delete all descendants
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      if descendant_ids != [] do
        from(p in Page, where: p.id in ^descendant_ids)
        |> Repo.update_all(set: [deleted_at: now])
      end

      # Soft delete the page itself
      page
      |> Page.delete_changeset()
      |> Repo.update!()
    end)
  end

  @doc """
  Restores a soft-deleted page from trash.
  Note: Does not automatically restore descendants.
  """
  def restore_page(%Page{} = page) do
    page
    |> Page.restore_changeset()
    |> Repo.update()
  end

  @doc """
  Permanently deletes a page and all its descendants.
  Use with caution - this cannot be undone.
  """
  def permanently_delete_page(%Page{} = page) do
    Repo.delete(page)
  end

  @doc """
  Lists all trashed (soft-deleted) pages for a project.
  """
  def list_trashed_pages(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and not is_nil(p.deleted_at),
      order_by: [desc: p.deleted_at],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @doc """
  Gets a trashed page by ID.
  """
  def get_trashed_page(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> where([p], not is_nil(p.deleted_at))
    |> preload([:avatar_asset])
    |> Repo.one()
  end

  def move_page(%Page{} = page, parent_id, position \\ nil) do
    with :ok <- validate_parent(page, parent_id) do
      position = position || next_position(page.project_id, parent_id)

      page
      |> Page.move_changeset(%{parent_id: parent_id, position: position})
      |> Repo.update()
    end
  end

  def change_page(%Page{} = page, attrs \\ %{}) do
    Page.update_changeset(page, attrs)
  end

  # =============================================================================
  # Validation
  # =============================================================================

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

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp build_ancestor_chain(%Page{parent_id: nil}, chain), do: chain

  defp build_ancestor_chain(%Page{parent_id: parent_id, project_id: project_id}, chain) do
    parent =
      Page
      |> Repo.get!(parent_id)
      |> Repo.preload(:avatar_asset)

    if parent.project_id == project_id do
      build_ancestor_chain(parent, [parent | chain])
    else
      chain
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

  defp preload_children_recursive(pages) when is_list(pages) do
    Enum.map(pages, &preload_children_recursive/1)
  end

  defp preload_children_recursive(%Page{} = page) do
    page = Repo.preload(page, :avatar_asset)

    children =
      from(p in Page,
        where: p.parent_id == ^page.id and is_nil(p.deleted_at),
        order_by: [asc: p.position, asc: p.name]
      )
      |> Repo.all()
      |> preload_children_recursive()

    %{page | children: children}
  end

  defp get_descendant_ids(page_id) do
    direct_children_ids =
      from(p in Page,
        where: p.parent_id == ^page_id and is_nil(p.deleted_at),
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
        where: p.project_id == ^project_id and is_nil(p.deleted_at),
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

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp maybe_generate_shortcut(attrs, project_id, exclude_page_id) do
    # Only generate if shortcut is not provided and name is available
    has_shortcut = Map.has_key?(attrs, "shortcut") || Map.has_key?(attrs, :shortcut)
    name = attrs["name"] || attrs[:name]

    if has_shortcut || is_nil(name) || name == "" do
      attrs
    else
      shortcut = Shortcuts.generate_page_shortcut(name, project_id, exclude_page_id)
      Map.put(attrs, "shortcut", shortcut)
    end
  end

  defp maybe_generate_shortcut_on_update(%Page{} = page, attrs) do
    attrs = stringify_keys(attrs)

    # If attrs explicitly set shortcut, use that
    if Map.has_key?(attrs, "shortcut") do
      attrs
    else
      # If name is changing, regenerate shortcut from new name
      new_name = attrs["name"]

      if new_name && new_name != "" && new_name != page.name do
        shortcut = Shortcuts.generate_page_shortcut(new_name, page.project_id, page.id)
        Map.put(attrs, "shortcut", shortcut)
      else
        # If page has no shortcut yet, generate one from current name
        if is_nil(page.shortcut) || page.shortcut == "" do
          name = page.name

          if name && name != "" do
            shortcut = Shortcuts.generate_page_shortcut(name, page.project_id, page.id)
            Map.put(attrs, "shortcut", shortcut)
          else
            attrs
          end
        else
          attrs
        end
      end
    end
  end
end
