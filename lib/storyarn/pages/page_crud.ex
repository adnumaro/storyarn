defmodule Storyarn.Pages.PageCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Pages.Page
  alias Storyarn.Projects.Project
  alias Storyarn.Repo

  # =============================================================================
  # Tree Operations
  # =============================================================================

  def list_pages_tree(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and is_nil(p.parent_id),
      order_by: [asc: p.position, asc: p.name]
    )
    |> Repo.all()
    |> preload_children_recursive()
  end

  def get_page(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> preload([:blocks, :avatar_asset])
    |> Repo.one()
  end

  def get_page!(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> preload([:blocks, :avatar_asset])
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
      where: p.parent_id == ^page_id,
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
    # Subquery to find all pages that are parents
    parent_ids_subquery =
      from(p in Page,
        where: p.project_id == ^project_id and not is_nil(p.parent_id),
        select: p.parent_id
      )

    from(p in Page,
      where: p.project_id == ^project_id and p.id not in subquery(parent_ids_subquery),
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

    %Page{project_id: project.id}
    |> Page.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_page(%Page{} = page, attrs) do
    page
    |> Page.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_page(%Page{} = page) do
    Repo.delete(page)
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

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
