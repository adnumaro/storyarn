defmodule Storyarn.Projects.ProjectTrash do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Scenes.Scene
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Sheets.Sheet

  @item_types ~w(sheet flow scene screenplay)
  @default_per_page 25
  @max_per_page 100

  @type item_type :: String.t()

  @type deleted_item :: %{
          id: integer(),
          type: item_type(),
          name: String.t() | nil,
          deleted_at: DateTime.t(),
          project_id: integer()
        }

  @type page :: %{
          items: [deleted_item()],
          page: pos_integer(),
          per_page: pos_integer(),
          total_count: non_neg_integer(),
          total_pages: pos_integer(),
          type_counts: %{String.t() => non_neg_integer()}
        }

  @doc """
  Returns a DB-paginated project trash page across all project-level trash types.
  """
  @spec paginate_deleted_items(integer(), keyword()) :: page()
  def paginate_deleted_items(project_id, opts \\ []) do
    search = normalize_search(opts[:search])
    type = normalize_type(opts[:type])
    per_page = normalize_per_page(opts[:per_page])

    total_count = count_deleted_items(project_id, search: search, type: type)
    total_pages = total_pages(total_count, per_page)
    page = opts[:page] |> normalize_positive_integer(1) |> max(1) |> min(total_pages)

    items =
      list_deleted_items(project_id,
        search: search,
        type: type,
        limit: per_page,
        offset: (page - 1) * per_page
      )

    %{
      items: items,
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      type_counts: count_deleted_items_by_type(project_id, search: search)
    }
  end

  @doc """
  Lists project trash items across all project-level trash types.

  Supports `:search`, `:type`, `:limit`, and `:offset`.
  """
  @spec list_deleted_items(integer(), keyword()) :: [deleted_item()]
  def list_deleted_items(project_id, opts \\ []) do
    project_id
    |> filtered_deleted_items_query(opts)
    |> order_by([i], desc: i.deleted_at, asc: i.type, asc: i.id)
    |> maybe_limit(opts[:limit])
    |> maybe_offset(opts[:offset])
    |> select([i], %{
      id: i.id,
      type: i.type,
      name: i.name,
      deleted_at: i.deleted_at,
      project_id: i.project_id
    })
    |> Repo.all()
  end

  @doc """
  Lists one bounded keyset page of deleted project items for cleanup jobs.

  Use `:after` to continue from a prior page and `:through` to keep a stable
  high-water mark. The page size defaults to and is capped at 100 items.
  """
  @spec list_deleted_items_for_retention(keyword()) :: [map()]
  def list_deleted_items_for_retention(opts \\ []) do
    cursor = Keyword.get(opts, :after)
    through = Keyword.get(opts, :through)

    limit =
      opts
      |> Keyword.get(:limit, @max_per_page)
      |> normalize_positive_integer(@max_per_page)
      |> max(1)
      |> min(@max_per_page)

    Repo.all(
      from(i in deleted_items_query(),
        where: ^retention_cursor_filter(cursor),
        where: ^retention_cutoff_filter(through),
        order_by: [asc: i.deleted_at, asc: i.type, asc: i.id],
        limit: ^limit,
        select: %{
          id: i.id,
          type: i.type,
          name: i.name,
          deleted_at: i.deleted_at,
          project_id: i.project_id,
          project_settings: i.project_settings,
          workspace_id: i.workspace_id
        }
      )
    )
  end

  @doc """
  Returns the newest retention cursor visible at the start of a cleanup run.

  Passing this cursor back as `:through` gives a finite, stable keyset even if
  users keep moving more items to trash while the worker is running.
  """
  @spec deleted_items_retention_cutoff() :: {DateTime.t(), item_type(), integer()} | nil
  def deleted_items_retention_cutoff do
    Repo.one(
      from(i in deleted_items_query(),
        order_by: [desc: i.deleted_at, desc: i.type, desc: i.id],
        limit: 1,
        select: {i.deleted_at, i.type, i.id}
      )
    )
  end

  defp retention_cursor_filter(nil), do: dynamic(true)

  defp retention_cursor_filter({deleted_at, type, id}) do
    dynamic(
      [i],
      i.deleted_at > ^deleted_at or
        (i.deleted_at == ^deleted_at and i.type > ^type) or
        (i.deleted_at == ^deleted_at and i.type == ^type and i.id > ^id)
    )
  end

  defp retention_cutoff_filter(nil), do: dynamic(true)

  defp retention_cutoff_filter({deleted_at, type, id}) do
    dynamic(
      [i],
      i.deleted_at < ^deleted_at or
        (i.deleted_at == ^deleted_at and i.type < ^type) or
        (i.deleted_at == ^deleted_at and i.type == ^type and i.id <= ^id)
    )
  end

  @doc """
  Counts project trash items across all project-level trash types.
  """
  @spec count_deleted_items(integer(), keyword()) :: non_neg_integer()
  def count_deleted_items(project_id, opts \\ []) do
    Repo.one(
      from(i in filtered_deleted_items_query(project_id, opts),
        select: count(i.id)
      )
    )
  end

  @doc """
  Counts project trash items by type.
  """
  @spec count_deleted_items_by_type(integer(), keyword()) :: %{String.t() => non_neg_integer()}
  def count_deleted_items_by_type(project_id, opts \\ []) do
    counts =
      from(i in filtered_deleted_items_query(project_id, Keyword.put(opts, :type, nil)),
        group_by: i.type,
        select: {i.type, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    Map.merge(Map.new(@item_types, &{&1, 0}), counts)
  end

  defp filtered_deleted_items_query(project_id, opts) do
    project_id
    |> deleted_items_query()
    |> maybe_filter_type(normalize_type(opts[:type]))
    |> maybe_filter_search(normalize_search(opts[:search]))
  end

  defp deleted_items_query(project_id) do
    from(i in deleted_items_query(),
      where: i.project_id == ^project_id
    )
  end

  defp deleted_items_query do
    union_query =
      Sheet
      |> deleted_item_query("sheet")
      |> union_all(^deleted_item_query(Flow, "flow"))
      |> union_all(^deleted_item_query(Scene, "scene"))
      |> union_all(^deleted_item_query(Screenplay, "screenplay"))

    from(i in subquery(union_query))
  end

  defp deleted_item_query(schema, type) do
    from(item in schema,
      join: p in Project,
      on: p.id == item.project_id,
      where: not is_nil(item.deleted_at),
      select: %{
        id: item.id,
        type: type(^type, :string),
        name: item.name,
        deleted_at: item.deleted_at,
        project_id: item.project_id,
        workspace_id: p.workspace_id,
        project_settings: p.settings
      }
    )
  end

  defp maybe_filter_type(query, type) when type in @item_types do
    where(query, [i], i.type == ^type)
  end

  defp maybe_filter_type(query, _type), do: query

  defp maybe_filter_search(query, ""), do: query

  defp maybe_filter_search(query, search) do
    where(query, [i], ilike(i.name, ^"%#{search}%"))
  end

  defp maybe_limit(query, nil), do: query

  defp maybe_limit(query, limit) do
    limit = normalize_positive_integer(limit, @default_per_page)
    limit(query, ^min(limit, @max_per_page))
  end

  defp maybe_offset(query, nil), do: query

  defp maybe_offset(query, offset) do
    offset(query, ^max(normalize_positive_integer(offset, 0), 0))
  end

  defp normalize_type(type) when type in @item_types, do: type
  defp normalize_type(_type), do: nil

  defp normalize_search(search) when is_binary(search), do: String.trim(search)
  defp normalize_search(_search), do: ""

  defp normalize_per_page(per_page) do
    per_page
    |> normalize_positive_integer(@default_per_page)
    |> max(1)
    |> min(@max_per_page)
  end

  defp normalize_positive_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp normalize_positive_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} when integer >= 0 -> integer
      _ -> default
    end
  end

  defp normalize_positive_integer(_value, default), do: default

  defp total_pages(0, _per_page), do: 1
  defp total_pages(total_count, per_page), do: div(total_count + per_page - 1, per_page)
end
