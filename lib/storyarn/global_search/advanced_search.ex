defmodule Storyarn.GlobalSearch.AdvancedSearch do
  @moduledoc """
  Authorized coordinator for the command palette's explicit advanced-search
  prefixes.

  The raw input is parsed again here. The client may decide when to request a
  search, but it cannot select a project, widen a mode, or bypass the
  submit-only fence for the intentionally expensive `*` search.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.GlobalSearch.Destinations
  alias Storyarn.GlobalSearch.FlowSearch
  alias Storyarn.GlobalSearch.Persistence.FlowRecord
  alias Storyarn.GlobalSearch.Persistence.SceneRecord
  alias Storyarn.GlobalSearch.Persistence.SheetRecord, as: Sheet
  alias Storyarn.GlobalSearch.SceneSearch
  alias Storyarn.GlobalSearch.SheetSearch
  alias Storyarn.GlobalSearch.VariableSearch
  alias Storyarn.Platform.Shared.HierarchySearch

  @default_limit 25
  @max_limit 50
  # Qualified table references combine sheet, table, row and column slugs.
  # Keeping the palette payload bounded must not reject valid authored paths.
  @max_query_length 399
  @deep_minimum_length 3

  @type mode :: :variables | :sheets | :flows | :scenes | :all
  @type page :: %{
          optional(:fallback) => :qualified_references,
          mode: mode(),
          items: [map()],
          truncated: boolean()
        }
  @type error_reason :: :unauthorized | :invalid_request | :not_submitted

  @prefixes %{
    "$" => :variables,
    "#" => :sheets,
    ">" => :flows,
    "@" => :scenes,
    "*" => :all
  }

  @spec search(Scope.t(), integer(), String.t(), keyword()) ::
          {:ok, page()} | {:error, error_reason()}
  def search(%{user: _} = scope, project_id, raw_query, opts \\ []) do
    with :ok <- validate_project_id(project_id),
         {:ok, mode, query} <- parse_prefix(raw_query),
         :ok <- validate_execution(mode, query, opts),
         {:ok, %{project: project}} <- Destinations.viewable_project(scope, project_id) do
      {:ok, run(project.id, mode, query, opts)}
    else
      {:error, :unauthorized} = error -> error
      {:error, :not_submitted} = error -> error
      _invalid -> {:error, :invalid_request}
    end
  end

  @doc false
  def parse_prefix(raw_query) when is_binary(raw_query) and byte_size(raw_query) <= 400 do
    case String.next_grapheme(raw_query) do
      {prefix, query} when is_map_key(@prefixes, prefix) ->
        query = String.trim(query)

        if String.length(query) <= @max_query_length do
          {:ok, Map.fetch!(@prefixes, prefix), query}
        else
          {:error, :invalid_request}
        end

      _other ->
        {:error, :invalid_request}
    end
  end

  def parse_prefix(_raw_query), do: {:error, :invalid_request}

  defp validate_execution(:all, query, opts) do
    cond do
      String.length(query) < @deep_minimum_length -> {:error, :invalid_request}
      Keyword.get(opts, :submitted, false) != true -> {:error, :not_submitted}
      true -> :ok
    end
  end

  defp validate_execution(_mode, "", _opts), do: {:error, :invalid_request}
  defp validate_execution(_mode, _query, _opts), do: :ok

  defp run(project_id, :variables, query, opts) do
    VariableSearch.search(project_id, query, limit: bounded_limit(opts))
  end

  defp run(project_id, :sheets, query, opts) do
    hierarchy_page(Sheet, :sheet, "#", project_id, query, opts)
  end

  defp run(project_id, :flows, query, opts) do
    hierarchy_page(FlowRecord, :flow, ">", project_id, query, opts)
  end

  defp run(project_id, :scenes, query, opts) do
    hierarchy_page(SceneRecord, :scene, "@", project_id, query, opts)
  end

  defp run(project_id, :all, query, opts) do
    limit = bounded_limit(opts)
    fetch_limit = limit + 1

    candidates =
      [
        {:sheet, SheetSearch.search_deep(project_id, query, limit: fetch_limit)},
        {:flow, FlowSearch.search_deep(project_id, query, limit: fetch_limit)},
        {:scene, SceneSearch.search_deep(project_id, query, limit: fetch_limit)}
      ]

    items =
      candidates
      |> Enum.flat_map(fn {type, entities} ->
        Enum.map(entities, &navigation_hit(type, &1, :all))
      end)
      |> Enum.sort_by(&{String.downcase(&1.label), to_string(&1.type), &1.id})

    %{
      mode: :all,
      items: Enum.take(items, limit),
      truncated: length(items) > limit
    }
  end

  defp hierarchy_page(schema, type, prefix, project_id, query, opts) do
    page = HierarchySearch.search(schema, project_id, query, limit: bounded_limit(opts))

    items =
      Enum.map(page.items, fn result ->
        entity = Map.fetch!(result, :entity)
        context = hierarchy_context(result)

        if Map.get(result, :has_children, false) do
          %{
            id: "#{type}:#{entity.id}",
            group: type,
            kind: :hierarchy,
            type: type,
            label: entity.name,
            context: context,
            action: %{kind: :complete, value: hierarchy_completion(prefix, result)},
            meta: %{shortcut: entity.shortcut, relation: page.relation}
          }
        else
          navigation_hit(type, entity, type, context)
        end
      end)

    %{mode: hierarchy_mode(type), items: items, truncated: page.truncated}
  end

  defp navigation_hit(type, entity, group, context \\ nil) do
    %{
      id: "#{type}:#{entity.id}",
      group: group,
      kind: :entity,
      type: type,
      label: entity.name,
      context: context,
      action: %{
        kind: :navigate,
        destination: %{type: type, id: entity.id}
      },
      meta: %{shortcut: entity.shortcut}
    }
  end

  defp hierarchy_context(%{path: path}) when is_list(path) and path != [] do
    Enum.join(path, " › ")
  end

  defp hierarchy_context(_result), do: nil

  defp hierarchy_completion(prefix, %{entity: entity, path: path}) do
    shortcuts =
      case path do
        path when is_list(path) and path != [] -> path
        _missing_path -> [entity_shortcut(entity)]
      end

    "#{prefix}#{Enum.join(shortcuts, ".")}."
  end

  defp entity_shortcut(%{shortcut: shortcut, id: _id}) when is_binary(shortcut) and shortcut != "", do: shortcut

  defp entity_shortcut(%{id: id}), do: Integer.to_string(id)

  defp hierarchy_mode(:sheet), do: :sheets
  defp hierarchy_mode(:flow), do: :flows
  defp hierarchy_mode(:scene), do: :scenes

  defp validate_project_id(id) do
    if is_integer(id) and id > 0, do: :ok, else: {:error, :invalid_request}
  end

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end
end
