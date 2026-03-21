defmodule StoryarnWeb.Helpers.EntitySearch do
  @moduledoc """
  Pure functions for searching and resolving entity names across types.

  Used by `EntitySelect` to compute MFA tuples for `SearchableSelect`.
  Can also be called directly for multi-type searches.
  """

  import Ecto.Query, only: [from: 2]

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  @type_schemas %{
    sheet: Storyarn.Sheets.Sheet,
    flow: Storyarn.Flows.Flow,
    scene: Storyarn.Scenes.Scene
  }

  @doc "Search entities of a single type. Delegates to the appropriate context."
  def search_entities(:sheet, project_id, query, opts),
    do: Sheets.search_sheets(project_id, query, opts)

  def search_entities(:flow, project_id, query, opts),
    do: Flows.search_flows(project_id, query, opts)

  def search_entities(:scene, project_id, query, opts),
    do: Scenes.search_scenes(project_id, query, opts)

  @doc """
  Search entities across multiple types.

  Fetches from each type, merges results sorted by name, then applies offset/limit.
  """
  def search_entities_multi(types, project_id, query, opts) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    per_type_limit = limit + offset

    types
    |> Enum.flat_map(fn type ->
      items = search_entities(type, project_id, query, limit: per_type_limit, offset: 0)
      Enum.map(items, &Map.put(&1, :_entity_type, type))
    end)
    |> Enum.sort_by(& &1.name)
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  @doc "Resolve a single entity name by type and ID."
  def get_entity_name(type, project_id, id) do
    schema = Map.fetch!(@type_schemas, type)

    from(e in schema,
      where: e.id == ^id and e.project_id == ^project_id and is_nil(e.deleted_at),
      select: e.name
    )
    |> Repo.one()
  end

  @doc "Resolve an entity name across multiple types (tries each until found)."
  def get_entity_name_multi(types, project_id, id) do
    Enum.find_value(types, fn type ->
      get_entity_name(type, project_id, id)
    end)
  end

  @doc """
  Search project variables with pagination.

  Returns items as `%{id: "sheet.var", name: "sheet.var", prefix: "sheet.", suffix: "var"}`.
  """
  def search_variables(project_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    q = String.downcase(query)

    Sheets.list_project_variables(project_id)
    |> Enum.map(fn v ->
      ref = "#{v.sheet_shortcut}.#{v.variable_name}"
      %{id: ref, name: ref, prefix: "#{v.sheet_shortcut}.", suffix: v.variable_name}
    end)
    |> Enum.filter(fn item -> q == "" or String.contains?(String.downcase(item.name), q) end)
    |> Enum.drop(offset)
    |> Enum.take(limit)
  end

  @doc "Resolve a variable ref name (identity — the ref IS the name)."
  def get_variable_name(_project_id, ref), do: ref
end
