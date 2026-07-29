defmodule Storyarn.GlobalSearch.ReferenceSearch do
  @moduledoc """
  Authorized coordinator for current-project reference lookup.

  Every public call re-resolves the project from the caller's fresh account
  scope. Client payloads identify only the selected variable/entity/flow; they
  can never select a project or workspace.
  """

  alias Storyarn.Accounts.Scope
  alias Storyarn.Flows
  alias Storyarn.GlobalSearch.Destinations
  alias Storyarn.GlobalSearch.ReferencePattern
  alias Storyarn.References
  alias Storyarn.Scenes
  alias Storyarn.Sheets

  @default_limit 25
  @max_limit 50
  @max_query_length 100
  @max_pg_bigint 9_223_372_036_854_775_807
  @sources [:sheet_variables, :reference_entities, :flows]
  @operation_ids ~w(variable_definition variable_usages entity_usages flow_callers)
  @scope_keys [
    :project_id,
    :workspace_id,
    :project_slug,
    :workspace_slug,
    "project_id",
    "projectId",
    "workspace_id",
    "workspaceId",
    "project_slug",
    "projectSlug",
    "workspace_slug",
    "workspaceSlug"
  ]

  @type page(item) :: %{items: [item], truncated: boolean()}
  @type error_reason :: :unauthorized | :not_found | :invalid_request

  @spec options(Scope.t(), integer(), atom(), String.t(), keyword()) ::
          {:ok, page(map())} | {:error, error_reason()}
  def options(%Scope{} = scope, project_id, source, query, opts \\ []) do
    with :ok <- validate_project_id(project_id),
         :ok <- validate_query(query),
         true <- source in @sources,
         {:ok, %{project: project}} <- Destinations.viewable_project(scope, project_id) do
      {:ok, option_page(project.id, source, String.trim(query), opts)}
    else
      {:error, :unauthorized} = error -> error
      _invalid -> {:error, :invalid_request}
    end
  end

  @spec execute(Scope.t(), integer(), String.t(), map(), keyword()) ::
          {:ok, page(map())} | {:error, error_reason()}
  def execute(%Scope{} = scope, project_id, operation_id, params, opts \\ []) do
    with :ok <- validate_project_id(project_id),
         true <- operation_id in @operation_ids,
         :ok <- validate_params(params),
         {:ok, %{project: project}} <- Destinations.viewable_project(scope, project_id) do
      execute_operation(project.id, operation_id, params, opts)
    else
      {:error, :unauthorized} = error -> error
      _invalid -> {:error, :invalid_request}
    end
  end

  @spec pattern(Scope.t(), integer(), String.t(), keyword()) ::
          {:ok, page(map())} | {:error, error_reason()}
  def pattern(%Scope{} = scope, project_id, pattern, opts \\ []) do
    with :ok <- validate_project_id(project_id),
         {:ok, filter} <- ReferencePattern.parse(pattern),
         {:ok, %{project: project}} <- Destinations.viewable_project(scope, project_id) do
      page =
        project.id
        |> Sheets.list_reference_variable_definitions(filter, limit: bounded_limit(opts))
        |> map_page(&definition_hit/1)

      {:ok, page}
    else
      {:error, :unauthorized} = error -> error
      _invalid -> {:error, :invalid_request}
    end
  end

  defp option_page(project_id, :sheet_variables, query, opts) do
    project_id
    |> Sheets.list_reference_variable_definitions({:contains, query}, limit: bounded_limit(opts))
    |> map_page(&variable_option/1)
  end

  defp option_page(project_id, :flows, query, opts) do
    limit = bounded_limit(opts)

    project_id
    |> Flows.search_flows(query, limit: limit + 1)
    |> page_from_items(limit, &flow_option/1)
  end

  defp option_page(project_id, :reference_entities, query, opts) do
    limit = bounded_limit(opts)
    fetch_limit = limit + 1

    items =
      [
        {:sheet, Sheets.search_sheets(project_id, query, limit: fetch_limit)},
        {:flow, Flows.search_flows(project_id, query, limit: fetch_limit)},
        {:scene, Scenes.search_scenes(project_id, query, limit: fetch_limit)}
      ]
      |> Enum.flat_map(fn {type, entities} ->
        Enum.map(entities, &entity_option(type, &1))
      end)
      |> Enum.sort_by(&{String.downcase(&1.label), to_string(&1.value.type), &1.value.id})

    %{items: Enum.take(items, limit), truncated: length(items) > limit}
  end

  defp execute_operation(project_id, operation_id, params, opts)
       when operation_id in ~w(variable_definition variable_usages) do
    with {:ok, block_id} <- fetch_database_id(params, "block_id"),
         {:ok, qualified_ref} <- fetch_string(params, "qualified_ref"),
         %{} = definition <-
           Sheets.get_reference_variable_definition(project_id, block_id, qualified_ref) do
      case operation_id do
        "variable_definition" ->
          {:ok, %{items: [definition_hit(definition)], truncated: false}}

        "variable_usages" ->
          page =
            project_id
            |> References.list_variable_usages(definition, limit: bounded_limit(opts))
            |> map_page(&variable_usage_hit/1)

          {:ok, page}
      end
    else
      nil -> {:error, :not_found}
      _invalid -> {:error, :invalid_request}
    end
  end

  defp execute_operation(project_id, "entity_usages", params, opts) do
    with {:ok, type} <- fetch_entity_type(params),
         {:ok, id} <- fetch_database_id(params, "id"),
         %{} <- get_entity(type, project_id, id) do
      page =
        type
        |> Atom.to_string()
        |> References.list_entity_usages(id, project_id, limit: bounded_limit(opts))
        |> map_page(&entity_usage_hit/1)

      {:ok, page}
    else
      nil -> {:error, :not_found}
      _invalid -> {:error, :invalid_request}
    end
  end

  defp execute_operation(project_id, "flow_callers", params, opts) do
    with {:ok, id} <- fetch_database_id(params, "id"),
         %{} <- Flows.get_flow(project_id, id) do
      page =
        id
        |> Flows.list_flow_callers(project_id, limit: bounded_limit(opts))
        |> map_page(&flow_caller_hit/1)

      {:ok, page}
    else
      nil -> {:error, :not_found}
      _invalid -> {:error, :invalid_request}
    end
  end

  defp variable_option(definition) do
    %{
      id: "variable:#{definition.block_id}:#{definition.qualified_ref}",
      label: definition.qualified_ref,
      context: definition_context(definition),
      value: %{block_id: definition.block_id, qualified_ref: definition.qualified_ref},
      meta: %{type: definition.block_type}
    }
  end

  defp flow_option(flow) do
    %{
      id: "flow:#{flow.id}",
      label: flow.name,
      context: nil,
      value: %{id: flow.id},
      meta: optional(%{type: :flow}, :shortcut, flow.shortcut)
    }
  end

  defp entity_option(type, entity) do
    %{
      id: "#{type}:#{entity.id}",
      label: entity.name,
      context: nil,
      value: %{type: type, id: entity.id},
      meta: optional(%{type: type}, :shortcut, entity.shortcut)
    }
  end

  defp definition_hit(definition) do
    %{
      id: "variable-definition:#{definition.block_id}:#{definition.row_id || 0}:#{definition.column_id || 0}",
      kind: :definition,
      label: definition.qualified_ref,
      context: definition_context(definition),
      destination: %{
        type: :sheet,
        id: definition.sheet_id,
        focus: definition_focus(definition)
      },
      meta: %{variable_type: definition.block_type}
    }
  end

  defp variable_usage_hit(usage) do
    %{
      id: "variable-usage:#{usage.reference_id}",
      kind: usage_kind(usage),
      label: source_label(usage),
      context: usage.container_name,
      destination: %{
        type: usage.container_type,
        id: usage.container_id,
        focus: usage_focus(usage)
      },
      meta: %{
        source_type: usage.source_type,
        source_kind: usage.source_kind,
        stale: usage.stale
      }
    }
  end

  defp entity_usage_hit(usage) do
    %{
      id: "entity-usage:#{usage.reference_id}",
      kind: :entity_usage,
      label: source_label(usage),
      context: usage.container_name,
      destination: %{
        type: usage.container_type,
        id: usage.container_id,
        focus: usage_focus(usage)
      },
      meta: %{
        source_type: usage.source_type,
        source_kind: usage.source_kind,
        reference_context: usage.reference_context
      }
    }
  end

  defp flow_caller_hit(caller) do
    %{
      id: "flow-caller:#{caller.node_id}",
      kind: :flow_caller,
      label: "#{caller.flow_name} · #{humanize(caller.node_type)}",
      context: caller.flow_name,
      destination: %{
        type: :flow,
        id: caller.flow_id,
        focus: %{type: :node, id: caller.node_id}
      },
      meta: %{source_type: :flow_node, source_kind: caller.node_type}
    }
  end

  defp definition_context(%{table_name: nil} = definition), do: definition.sheet_name

  defp definition_context(definition) do
    "#{definition.sheet_name} · #{definition.table_name} · #{definition.row_name} · #{definition.column_name}"
  end

  defp definition_focus(%{table_name: nil, block_id: block_id}), do: %{type: :block, id: block_id}

  defp definition_focus(definition) do
    %{
      type: :cell,
      block_id: definition.block_id,
      row_id: definition.row_id,
      column_id: definition.column_id
    }
  end

  defp usage_focus(%{source_type: :flow_node, source_id: id}), do: %{type: :node, id: id}
  defp usage_focus(%{source_type: :scene_pin, source_id: id}), do: %{type: :pin, id: id}
  defp usage_focus(%{source_type: :scene_zone, source_id: id}), do: %{type: :zone, id: id}

  defp usage_focus(%{source_type: :table_formula} = usage) do
    %{
      type: :cell,
      block_id: usage.block_id,
      row_id: usage.row_id,
      column_id: usage.column_id
    }
  end

  defp usage_focus(%{source_type: :block, source_id: id}), do: %{type: :block, id: id}

  defp source_label(%{source_label: label}) when is_binary(label) and label != "", do: label
  defp source_label(usage), do: "#{usage.container_name} · #{humanize(usage.source_kind)}"

  defp usage_kind(%{source_type: :table_formula}), do: :formula_read
  defp usage_kind(%{kind: "read"}), do: :read
  defp usage_kind(%{kind: "write"}), do: :write

  defp humanize(value) do
    value
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp get_entity(:sheet, project_id, id), do: Sheets.get_sheet(project_id, id)
  defp get_entity(:flow, project_id, id), do: Flows.get_flow(project_id, id)
  defp get_entity(:scene, project_id, id), do: Scenes.get_scene(project_id, id)

  defp map_page(%{items: items, truncated: truncated}, mapper) do
    %{items: Enum.map(items, mapper), truncated: truncated}
  end

  defp page_from_items(items, limit, mapper) do
    %{items: items |> Enum.take(limit) |> Enum.map(mapper), truncated: length(items) > limit}
  end

  defp validate_project_id(id) do
    if valid_database_id?(id), do: :ok, else: {:error, :invalid_request}
  end

  defp validate_query(query) when is_binary(query) do
    if String.length(query) <= @max_query_length, do: :ok, else: {:error, :invalid_request}
  end

  defp validate_query(_query), do: {:error, :invalid_request}

  defp validate_params(params) when is_map(params) do
    if Enum.any?(@scope_keys, &Map.has_key?(params, &1)),
      do: {:error, :invalid_request},
      else: :ok
  end

  defp validate_params(_params), do: {:error, :invalid_request}

  defp fetch_database_id(params, key) do
    case fetch_param(params, key) do
      {:ok, id} ->
        if valid_database_id?(id), do: {:ok, id}, else: {:error, :invalid_request}

      :error ->
        {:error, :invalid_request}
    end
  end

  defp fetch_string(params, key) do
    case fetch_param(params, key) do
      {:ok, value}
      when is_binary(value) and value != "" and byte_size(value) <= 400 ->
        {:ok, value}

      _invalid ->
        {:error, :invalid_request}
    end
  end

  defp fetch_entity_type(params) do
    case fetch_param(params, "type") do
      {:ok, "sheet"} -> {:ok, :sheet}
      {:ok, "flow"} -> {:ok, :flow}
      {:ok, "scene"} -> {:ok, :scene}
      {:ok, :sheet} -> {:ok, :sheet}
      {:ok, :flow} -> {:ok, :flow}
      {:ok, :scene} -> {:ok, :scene}
      _invalid -> {:error, :invalid_request}
    end
  end

  defp fetch_param(params, key) do
    case Map.fetch(params, key) do
      :error -> Map.fetch(params, String.to_existing_atom(key))
      value -> value
    end
  end

  defp valid_database_id?(id), do: is_integer(id) and id > 0 and id <= @max_pg_bigint

  defp bounded_limit(opts) do
    opts
    |> Keyword.get(:limit, @default_limit)
    |> max(1)
    |> min(@max_limit)
  end

  defp optional(map, _key, nil), do: map
  defp optional(map, key, value), do: Map.put(map, key, value)
end
