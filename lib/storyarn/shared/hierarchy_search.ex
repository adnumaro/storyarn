defmodule Storyarn.Shared.HierarchySearch do
  @moduledoc """
  Bounded search for project-scoped hierarchical entities.

  The schema must expose `id`, `name`, `shortcut`, `position`, `parent_id`,
  `project_id`, and `deleted_at` fields. Sheets, flows, and scenes share this
  contract.

  Search syntax:

    * `main` searches names and shortcuts across the whole tree.
    * `main.` lists the direct children of the exact `main` shortcut.
    * `main.k` searches direct children whose name or shortcut starts with `k`.
    * `main.?k` searches the complete `main` subtree for names or shortcuts
      containing `k`.

  Nested anchors are resolved from their complete root-to-entity path, choosing
  the longest exact path prefix. This supports arbitrary depth while keeping a
  dot that belongs to an entity shortcut distinct from a hierarchy separator.
  """

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Shared.SearchHelpers

  @default_limit 25
  @max_limit 50

  @type relation :: :matches | :children | :descendants
  @type item(entity) :: %{
          entity: entity,
          has_children: boolean(),
          path: [String.t()]
        }
  @type result(entity) :: %{
          items: [item(entity)],
          truncated: boolean(),
          relation: relation(),
          anchor: entity | nil
        }

  @doc """
  Searches a hierarchical schema inside one project.

  Results include an active-child flag and the root-to-entity shortcut path.
  Both are loaded in batches, so rendering a page does not issue per-item
  queries.

  The `:limit` option defaults to #{@default_limit} and is capped at
  #{@max_limit}. One additional row is fetched to report `:truncated`.
  """
  @spec search(module(), pos_integer(), String.t(), keyword()) :: result(struct())
  def search(schema, project_id, query, opts \\ [])
      when is_atom(schema) and is_integer(project_id) and is_binary(query) and is_list(opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, @default_limit))
    query = query |> String.trim() |> String.downcase()

    case search_target(schema, project_id, query) do
      {:matches, nil, ""} ->
        result([], false, :matches, nil)

      {relation, nil, _term} when relation in [:children, :descendants] ->
        result([], false, relation, nil)

      {relation, anchor, term} ->
        entities =
          schema
          |> entity_query(project_id, relation, anchor, term, limit + 1)
          |> Repo.all()

        truncated = length(entities) > limit
        entities = Enum.take(entities, limit)

        result(
          decorate_items(schema, project_id, entities),
          truncated,
          relation,
          anchor
        )
    end
  end

  defp search_target(schema, project_id, query) do
    case resolve_anchor(schema, project_id, query) do
      nil -> target_without_anchor(query)
      %{entity: anchor, path: path} -> target_below_anchor(anchor, path, query)
    end
  end

  defp target_without_anchor(query) do
    if String.contains?(query, ".") do
      relation = if descendant_expression?(query), do: :descendants, else: :children
      {relation, nil, ""}
    else
      {:matches, nil, query}
    end
  end

  defp target_below_anchor(anchor, path, query) do
    term = String.replace_prefix(query, path <> ".", "")

    if String.starts_with?(term, "?") do
      {:descendants, anchor, String.replace_prefix(term, "?", "")}
    else
      {:children, anchor, term}
    end
  end

  defp entity_query(schema, project_id, :matches, nil, term, row_limit) do
    pattern = contains_pattern(term)

    from(entity in schema,
      where:
        entity.project_id == ^project_id and is_nil(entity.deleted_at) and
          (ilike(entity.name, ^pattern) or ilike(entity.shortcut, ^pattern)),
      order_by: [asc: fragment("LOWER(?)", entity.name), asc: entity.id],
      limit: ^row_limit
    )
  end

  defp entity_query(schema, project_id, :children, anchor, term, row_limit) do
    base_query =
      from(entity in schema,
        where:
          entity.project_id == ^project_id and entity.parent_id == ^anchor.id and
            is_nil(entity.deleted_at),
        order_by: [
          asc: entity.position,
          asc: fragment("LOWER(?)", entity.name),
          asc: entity.id
        ],
        limit: ^row_limit
      )

    case term do
      "" ->
        base_query

      _term ->
        pattern = prefix_pattern(term)

        from(entity in base_query,
          where: ilike(entity.name, ^pattern) or ilike(entity.shortcut, ^pattern)
        )
    end
  end

  defp entity_query(schema, project_id, :descendants, anchor, term, row_limit) do
    descendants =
      from(entity in schema,
        where:
          entity.project_id == ^project_id and entity.parent_id == ^anchor.id and
            is_nil(entity.deleted_at),
        select: %{id: entity.id, depth: 1}
      )

    recursion =
      from(entity in schema,
        join: descendant in "hierarchy_search_descendants",
        on: entity.parent_id == descendant.id,
        where: entity.project_id == ^project_id and is_nil(entity.deleted_at),
        select: %{id: entity.id, depth: descendant.depth + 1}
      )

    cte_query = union_all(descendants, ^recursion)
    pattern = contains_pattern(term)

    from(entity in schema,
      join: descendant in "hierarchy_search_descendants",
      on: entity.id == descendant.id,
      where:
        entity.project_id == ^project_id and is_nil(entity.deleted_at) and
          (ilike(entity.name, ^pattern) or ilike(entity.shortcut, ^pattern)),
      order_by: [
        asc: descendant.depth,
        asc: entity.position,
        asc: fragment("LOWER(?)", entity.name),
        asc: entity.id
      ],
      limit: ^row_limit
    )
    |> recursive_ctes(true)
    |> with_cte("hierarchy_search_descendants", as: ^cte_query)
  end

  defp resolve_anchor(schema, project_id, query) do
    roots =
      from(entity in schema,
        where:
          entity.project_id == ^project_id and is_nil(entity.deleted_at) and
            is_nil(entity.parent_id),
        select: %{
          id: entity.id,
          parent_id: entity.parent_id,
          path: coalesce(entity.shortcut, fragment("CAST(? AS TEXT)", entity.id)),
          depth: 0
        }
      )

    recursion =
      from(entity in schema,
        join: path in "hierarchy_search_anchor_paths",
        on: entity.parent_id == path.id,
        where: entity.project_id == ^project_id and is_nil(entity.deleted_at),
        select: %{
          id: entity.id,
          parent_id: entity.parent_id,
          path:
            fragment(
              "? || '.' || COALESCE(?, CAST(? AS TEXT))",
              path.path,
              entity.shortcut,
              entity.id
            ),
          depth: path.depth + 1
        }
      )

    cte_query = union_all(roots, ^recursion)

    from(entity in schema,
      join: path in "hierarchy_search_anchor_paths",
      on: path.id == entity.id,
      where:
        entity.project_id == ^project_id and is_nil(entity.deleted_at) and
          fragment("? LIKE (? || '.%')", ^query, path.path),
      order_by: [
        desc: fragment("CHAR_LENGTH(?)", path.path),
        desc: path.depth,
        asc: entity.id
      ],
      limit: 1,
      select: %{entity: entity, path: path.path}
    )
    |> recursive_ctes(true)
    |> with_cte("hierarchy_search_anchor_paths", as: ^cte_query)
    |> Repo.one()
  end

  defp descendant_expression?(query) do
    query
    |> String.split(".", trim: false)
    |> List.last()
    |> String.starts_with?("?")
  end

  defp decorate_items(_schema, _project_id, []), do: []

  defp decorate_items(schema, project_id, entities) do
    ids = Enum.map(entities, & &1.id)
    parents_with_children = parents_with_children(schema, project_id, ids)
    paths = paths_by_entity(schema, project_id, ids)

    Enum.map(entities, fn entity ->
      %{
        entity: entity,
        has_children: MapSet.member?(parents_with_children, entity.id),
        path: Map.get(paths, entity.id, List.wrap(entity.shortcut))
      }
    end)
  end

  defp parents_with_children(schema, project_id, parent_ids) do
    from(entity in schema,
      where:
        entity.project_id == ^project_id and entity.parent_id in ^parent_ids and
          is_nil(entity.deleted_at),
      distinct: true,
      select: entity.parent_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp paths_by_entity(schema, project_id, entity_ids) do
    paths =
      from(entity in schema,
        where:
          entity.project_id == ^project_id and entity.id in ^entity_ids and
            is_nil(entity.deleted_at),
        select: %{
          origin_id: entity.id,
          parent_id: entity.parent_id,
          shortcut: entity.shortcut,
          depth: 0
        }
      )

    recursion =
      from(entity in schema,
        join: path in "hierarchy_search_paths",
        on: entity.id == path.parent_id,
        where: entity.project_id == ^project_id and is_nil(entity.deleted_at),
        select: %{
          origin_id: path.origin_id,
          parent_id: entity.parent_id,
          shortcut: entity.shortcut,
          depth: path.depth + 1
        }
      )

    cte_query = union_all(paths, ^recursion)

    from(path in "hierarchy_search_paths",
      order_by: [asc: path.origin_id, asc: path.depth],
      select: {path.origin_id, path.shortcut}
    )
    |> recursive_ctes(true)
    |> with_cte("hierarchy_search_paths", as: ^cte_query)
    |> Repo.all()
    |> Enum.reduce(%{}, fn {origin_id, shortcut}, acc ->
      prepend_path_segment(acc, origin_id, shortcut)
    end)
  end

  defp prepend_path_segment(paths, _origin_id, shortcut) when not is_binary(shortcut), do: paths

  defp prepend_path_segment(paths, origin_id, shortcut) do
    Map.update(paths, origin_id, [shortcut], &[shortcut | &1])
  end

  defp contains_pattern(term), do: "%#{SearchHelpers.sanitize_like_query(term)}%"
  defp prefix_pattern(term), do: "#{SearchHelpers.sanitize_like_query(term)}%"

  defp normalize_limit(limit) when is_integer(limit), do: limit |> max(1) |> min(@max_limit)
  defp normalize_limit(_limit), do: @default_limit

  defp result(items, truncated, relation, anchor) do
    %{items: items, truncated: truncated, relation: relation, anchor: anchor}
  end
end
