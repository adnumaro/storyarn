defmodule Storyarn.Pages.PageQueries do
  @moduledoc """
  Read-only query functions for pages.

  Provides all page retrieval, listing, search, and tree traversal operations.
  Mutation operations remain in `PageCrud`.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Pages.Page
  alias Storyarn.Repo

  # =============================================================================
  # Tree Operations
  # =============================================================================

  @spec list_pages_tree(integer()) :: [Page.t()]
  def list_pages_tree(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and is_nil(p.parent_id) and is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name]
    )
    |> Repo.all()
    |> preload_children_recursive()
  end

  @spec get_page(integer(), integer()) :: Page.t() | nil
  def get_page(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> where([p], is_nil(p.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one()
  end

  @spec get_page!(integer(), integer()) :: Page.t()
  def get_page!(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> where([p], is_nil(p.deleted_at))
    |> preload([:blocks, :avatar_asset, :banner_asset])
    |> Repo.one!()
  end

  @spec get_page_with_ancestors(integer(), integer()) :: [Page.t()] | nil
  def get_page_with_ancestors(project_id, page_id) do
    case get_page(project_id, page_id) do
      nil -> nil
      page -> build_ancestor_chain(page, [page])
    end
  end

  @spec get_page_with_descendants(integer(), integer()) :: Page.t() | nil
  def get_page_with_descendants(project_id, page_id) do
    case get_page(project_id, page_id) do
      nil -> nil
      page -> page |> preload_children_recursive() |> List.wrap() |> List.first()
    end
  end

  @spec get_children(integer()) :: [Page.t()]
  def get_children(page_id) do
    from(p in Page,
      where: p.parent_id == ^page_id and is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec list_all_pages(integer()) :: [Page.t()]
  def list_all_pages(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and is_nil(p.deleted_at),
      order_by: [asc: p.position, asc: p.name],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec list_leaf_pages(integer()) :: [Page.t()]
  def list_leaf_pages(project_id) do
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
  # Search
  # =============================================================================

  @spec search_pages(integer(), String.t()) :: [Page.t()]
  def search_pages(project_id, query) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      from(p in Page,
        where: p.project_id == ^project_id and is_nil(p.deleted_at),
        order_by: [desc: p.updated_at],
        limit: 10
      )
      |> Repo.all()
    else
      search_term = "%#{query}%"

      from(p in Page,
        where: p.project_id == ^project_id and is_nil(p.deleted_at),
        where: ilike(p.name, ^search_term) or ilike(p.shortcut, ^search_term),
        order_by: [asc: p.name],
        limit: 10
      )
      |> Repo.all()
    end
  end

  @spec get_page_by_shortcut(integer(), String.t() | nil) :: Page.t() | nil
  def get_page_by_shortcut(project_id, shortcut) when is_binary(shortcut) do
    from(p in Page,
      where: p.project_id == ^project_id and p.shortcut == ^shortcut and is_nil(p.deleted_at),
      preload: [:blocks, :avatar_asset]
    )
    |> Repo.one()
  end

  def get_page_by_shortcut(_project_id, _shortcut), do: nil

  # =============================================================================
  # Variables
  # =============================================================================

  @spec list_project_variables(integer()) :: [map()]
  def list_project_variables(project_id) do
    alias Storyarn.Pages.Block

    variable_types = ~w(text rich_text number select multi_select boolean date)

    from(b in Block,
      join: p in Page,
      on: b.page_id == p.id,
      where:
        p.project_id == ^project_id and
          is_nil(p.deleted_at) and
          is_nil(b.deleted_at) and
          b.type in ^variable_types and
          not is_nil(b.variable_name) and
          b.variable_name != "" and
          b.is_constant == false,
      select: %{
        page_id: p.id,
        page_name: p.name,
        page_shortcut: coalesce(p.shortcut, fragment("CAST(? AS TEXT)", p.id)),
        block_id: b.id,
        variable_name: b.variable_name,
        block_type: b.type,
        config: b.config
      },
      order_by: [asc: p.name, asc: b.position]
    )
    |> Repo.all()
    |> Enum.map(fn var ->
      options =
        case var.block_type do
          type when type in ["select", "multi_select"] ->
            var.config["options"] || []

          _ ->
            nil
        end

      var
      |> Map.put(:options, options)
      |> Map.delete(:config)
    end)
  end

  # =============================================================================
  # Reference Validation
  # =============================================================================

  @spec validate_reference_target(String.t(), integer(), integer()) ::
          {:ok, Page.t() | Storyarn.Flows.Flow.t()} | {:error, :not_found | :invalid_type}
  def validate_reference_target(target_type, target_id, project_id) do
    case target_type do
      "page" ->
        case get_page(project_id, target_id) do
          nil -> {:error, :not_found}
          page -> {:ok, page}
        end

      "flow" ->
        case Storyarn.Flows.get_flow(project_id, target_id) do
          nil -> {:error, :not_found}
          flow -> {:ok, flow}
        end

      _ ->
        {:error, :invalid_type}
    end
  end

  # =============================================================================
  # Trash
  # =============================================================================

  @spec list_trashed_pages(integer()) :: [Page.t()]
  def list_trashed_pages(project_id) do
    from(p in Page,
      where: p.project_id == ^project_id and not is_nil(p.deleted_at),
      order_by: [desc: p.deleted_at],
      preload: [:avatar_asset]
    )
    |> Repo.all()
  end

  @spec get_trashed_page(integer(), integer()) :: Page.t() | nil
  def get_trashed_page(project_id, page_id) do
    Page
    |> where(project_id: ^project_id, id: ^page_id)
    |> where([p], not is_nil(p.deleted_at))
    |> preload([:avatar_asset])
    |> Repo.one()
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
end
