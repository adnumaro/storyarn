defmodule Storyarn.Projects.References.PortableVariableSnapshot do
  @moduledoc """
  Pure planning and rewrite rules for variable references embedded in portable
  and exact project snapshots.

  The module does not read or write persistence. Materialized formula rows are
  updated separately by the command that owns that transactional write.
  """

  alias Storyarn.Projects.FlowFormulaEngine, as: FormulaEngine
  alias Storyarn.Projects.References.VariableCatalog
  alias Storyarn.Projects.References.VariableReferenceExtraction

  @regular_variable_types VariableCatalog.regular_variable_types()
  @table_variable_types VariableCatalog.table_variable_types()
  @constant_table_variable_types VariableCatalog.constant_table_variable_types()

  @typedoc false
  @type portable_variable_resolution_key ::
          {:regular, String.t(), String.t()}
          | {:table, String.t(), String.t(), String.t(), String.t()}

  @typedoc false
  @type portable_project_snapshot_plan :: %{
          version: 1,
          sheet_ids: MapSet.t(pos_integer()),
          namespace_owners: %{String.t() => pos_integer()},
          rewritable_namespaces: %{String.t() => pos_integer()},
          qualified_targets: %{String.t() => portable_variable_resolution_key()},
          rewritable_qualified_targets: %{
            String.t() => portable_variable_resolution_key()
          }
        }

  @doc false
  @spec prepare_portable_project_snapshot(map()) ::
          {:ok, portable_project_snapshot_plan()} | {:error, term()}
  def prepare_portable_project_snapshot(%{} = project_snapshot) do
    with {:ok, catalog} <- portable_snapshot_variable_catalog(project_snapshot),
         {:ok, specs} <- portable_snapshot_reference_specs(project_snapshot),
         :ok <- validate_portable_snapshot_specs(specs, catalog.resolution_keys) do
      {:ok, portable_project_snapshot_plan(catalog)}
    end
  end

  def prepare_portable_project_snapshot(project_snapshot),
    do: {:error, {:invalid_portable_variable_project_snapshot, project_snapshot}}

  @doc false
  @spec prepare_exact_project_snapshot(map()) :: {:ok, portable_project_snapshot_plan()}
  def prepare_exact_project_snapshot(%{} = project_snapshot) do
    plan =
      case portable_snapshot_variable_catalog(project_snapshot) do
        {:ok, catalog} -> portable_project_snapshot_plan(catalog)
        {:error, _reason} -> exact_project_snapshot_fallback_plan(project_snapshot)
      end

    {:ok, plan}
  end

  def prepare_exact_project_snapshot(_project_snapshot), do: {:ok, exact_project_snapshot_fallback_plan(%{})}

  defp portable_project_snapshot_plan(catalog) do
    %{
      version: 1,
      sheet_ids: catalog.sheet_ids,
      namespace_owners: catalog.namespace_owners,
      rewritable_namespaces: catalog.rewritable_namespaces,
      qualified_targets: catalog.qualified_targets,
      rewritable_qualified_targets: catalog.rewritable_qualified_targets
    }
  end

  defp exact_project_snapshot_fallback_plan(project_snapshot) do
    entries = exact_variable_sheet_entries(project_snapshot)

    explicit_owners =
      entries
      |> Enum.reject(& &1.rewritable?)
      |> Map.new(&{&1.namespace, &1.sheet_id})

    fallback_owners = Map.new(entries, &{&1.namespace, &1.sheet_id})
    namespace_owners = Map.merge(fallback_owners, explicit_owners)

    rewritable_namespaces =
      entries
      |> Enum.filter(&(&1.rewritable? and Map.get(namespace_owners, &1.namespace) == &1.sheet_id))
      |> Map.new(&{&1.namespace, &1.sheet_id})

    {qualified_targets, rewritable_qualified_targets} =
      Enum.reduce(entries, {%{}, %{}}, &put_exact_qualified_targets(&1, &2, namespace_owners))

    %{
      version: 1,
      sheet_ids: MapSet.new(entries, & &1.sheet_id),
      namespace_owners: namespace_owners,
      rewritable_namespaces: rewritable_namespaces,
      qualified_targets: qualified_targets,
      rewritable_qualified_targets: rewritable_qualified_targets
    }
  end

  defp put_exact_qualified_targets(entry, acc, namespace_owners) do
    if Map.get(namespace_owners, entry.namespace) == entry.sheet_id,
      do: merge_exact_qualified_targets(entry, acc),
      else: acc
  end

  defp merge_exact_qualified_targets(entry, {qualified, rewritable}) do
    qualified = merge_qualified_targets(entry.qualified_targets, qualified)

    rewritable =
      if entry.rewritable?,
        do: merge_qualified_targets(entry.qualified_targets, rewritable),
        else: rewritable

    {qualified, rewritable}
  end

  defp merge_qualified_targets(left, right),
    do: Map.merge(left, right, fn _key, left_value, _right_value -> left_value end)

  defp exact_variable_sheet_entries(%{"sheets" => sheets}) when is_list(sheets) do
    Enum.flat_map(sheets, &exact_variable_sheet_entry/1)
  end

  defp exact_variable_sheet_entries(_project_snapshot), do: []

  defp exact_variable_sheet_entry(%{
         "id" => sheet_id,
         "snapshot" => %{"original_id" => sheet_id, "shortcut" => shortcut, "blocks" => blocks}
       })
       when is_integer(sheet_id) and sheet_id > 0 and (is_nil(shortcut) or is_binary(shortcut)) and is_list(blocks) do
    namespace = if is_nil(shortcut) or shortcut == "", do: Integer.to_string(sheet_id), else: shortcut

    [
      %{
        sheet_id: sheet_id,
        namespace: namespace,
        rewritable?: is_nil(shortcut) or shortcut == "",
        qualified_targets: exact_sheet_qualified_targets(blocks, namespace)
      }
    ]
  end

  defp exact_variable_sheet_entry(_invalid), do: []

  defp exact_sheet_qualified_targets(blocks, namespace) do
    blocks
    |> Enum.flat_map(&portable_block_variable_definitions_or_empty(&1, namespace))
    |> Map.new(&{&1.qualified_ref, &1.resolution_key})
  end

  defp portable_block_variable_definitions_or_empty(block, namespace) do
    case portable_block_variable_definitions(block, namespace) do
      {:ok, definitions} -> definitions
      {:error, _reason} -> []
    end
  end

  @doc false
  @spec rewrite_portable_project_snapshot(map(), portable_project_snapshot_plan(), map()) ::
          {:ok, map()} | {:error, term()}
  def rewrite_portable_project_snapshot(%{} = project_snapshot, plan, sheet_id_map)
      when is_map(plan) and is_map(sheet_id_map) do
    with {:ok, rewrites} <- portable_variable_rewrites(plan, sheet_id_map) do
      {:ok, rewrite_portable_project(project_snapshot, rewrites)}
    end
  end

  def rewrite_portable_project_snapshot(project_snapshot, plan, sheet_id_map),
    do: {:error, {:invalid_portable_variable_rewrite, project_snapshot, plan, sheet_id_map}}

  @doc false
  @spec portable_namespace_materialization_attempt_limit(portable_project_snapshot_plan()) ::
          {:ok, pos_integer()} | {:error, term()}
  def portable_namespace_materialization_attempt_limit(%{
        version: 1,
        namespace_owners: namespace_owners,
        rewritable_namespaces: rewritable_namespaces
      })
      when is_map(namespace_owners) and is_map(rewritable_namespaces) do
    if valid_portable_namespace_owners?(namespace_owners, rewritable_namespaces) do
      fixed_numeric_count =
        Enum.count(namespace_owners, fn {namespace, source_id} ->
          Map.get(rewritable_namespaces, namespace) != source_id and
            positive_postgres_bigint?(namespace)
        end)

      {:ok, fixed_numeric_count + 1}
    else
      {:error, :invalid_portable_variable_namespace_plan}
    end
  end

  def portable_namespace_materialization_attempt_limit(_plan), do: {:error, :invalid_portable_variable_namespace_plan}

  defp valid_portable_namespace_owners?(namespace_owners, rewritable_namespaces) do
    Enum.all?(namespace_owners, &valid_portable_namespace_owner?/1) and
      Enum.all?(rewritable_namespaces, fn {namespace, source_id} ->
        Map.get(namespace_owners, namespace) == source_id
      end)
  end

  defp valid_portable_namespace_owner?({namespace, source_id}) do
    is_binary(namespace) and namespace != "" and is_integer(source_id) and source_id > 0
  end

  defp positive_postgres_bigint?(namespace) do
    case Integer.parse(namespace) do
      {value, ""} when value > 0 and value <= 9_223_372_036_854_775_807 -> true
      _invalid -> false
    end
  end

  defp portable_snapshot_variable_catalog(%{"sheets" => sheets}) when is_list(sheets) do
    with {:ok, entries, sheet_ids} <- portable_variable_sheet_entries(sheets),
         {:ok, namespace_owners} <- portable_authoritative_namespace_owners(entries) do
      entries
      |> Enum.reduce_while(
        {:ok, empty_portable_variable_catalog()},
        &put_portable_authoritative_sheet_definitions(&1, &2, namespace_owners)
      )
      |> case do
        {:ok, catalog} -> {:ok, %{catalog | sheet_ids: sheet_ids}}
        {:error, _reason} = error -> error
      end
    end
  end

  defp portable_snapshot_variable_catalog(project_snapshot),
    do: {:error, {:invalid_portable_variable_catalog, project_snapshot}}

  defp empty_portable_variable_catalog do
    %{
      sheet_ids: MapSet.new(),
      namespace_owners: %{},
      rewritable_namespaces: %{},
      resolution_keys: MapSet.new(),
      qualified_targets: %{},
      rewritable_qualified_targets: %{}
    }
  end

  defp portable_variable_sheet_entries(sheets) do
    sheets
    |> Enum.reduce_while({:ok, [], MapSet.new()}, &put_portable_variable_sheet_entry/2)
    |> case do
      {:ok, entries, sheet_ids} -> {:ok, Enum.reverse(entries), sheet_ids}
      {:error, _reason} = error -> error
    end
  end

  defp put_portable_variable_sheet_entry(entry, {:ok, entries, sheet_ids}) do
    case portable_sheet_variable_definitions(entry) do
      {:ok, definitions, sheet_id, namespace, rewritable?} ->
        if MapSet.member?(sheet_ids, sheet_id) do
          {:halt, {:error, {:duplicate_portable_variable_sheet_identity, sheet_id}}}
        else
          {:cont, {:ok, [{definitions, sheet_id, namespace, rewritable?} | entries], MapSet.put(sheet_ids, sheet_id)}}
        end

      {:error, _reason} = error ->
        {:halt, error}
    end
  end

  defp portable_authoritative_namespace_owners(entries) do
    entries
    |> Enum.reduce_while({:ok, %{}, %{}}, fn
      {_definitions, sheet_id, namespace, true}, {:ok, fallback, explicit} ->
        {:cont, {:ok, Map.put(fallback, namespace, sheet_id), explicit}}

      {_definitions, sheet_id, namespace, false}, {:ok, fallback, explicit} ->
        case Map.fetch(explicit, namespace) do
          {:ok, namespace_owner} ->
            {:halt, {:error, {:ambiguous_portable_variable_namespace, namespace, namespace_owner, sheet_id}}}

          :error ->
            {:cont, {:ok, fallback, Map.put(explicit, namespace, sheet_id)}}
        end
    end)
    |> case do
      {:ok, fallback, explicit} -> {:ok, Map.merge(fallback, explicit)}
      {:error, _reason} = error -> error
    end
  end

  defp put_portable_authoritative_sheet_definitions(
         {definitions, sheet_id, namespace, rewritable?},
         {:ok, catalog},
         namespace_owners
       ) do
    if Map.fetch!(namespace_owners, namespace) == sheet_id do
      put_portable_sheet_definitions(catalog, definitions, sheet_id, namespace, rewritable?)
    else
      {:cont, {:ok, catalog}}
    end
  end

  defp portable_sheet_variable_definitions(%{
         "id" => sheet_id,
         "snapshot" => %{"original_id" => sheet_id, "shortcut" => shortcut, "blocks" => blocks}
       })
       when is_integer(sheet_id) and sheet_id > 0 and (is_nil(shortcut) or is_binary(shortcut)) and is_list(blocks) do
    namespace = if is_nil(shortcut), do: Integer.to_string(sheet_id), else: shortcut

    if namespace == "" do
      {:error, {:invalid_portable_variable_namespace, sheet_id, namespace}}
    else
      case portable_sheet_variable_definitions(blocks, namespace) do
        {:ok, definitions} -> {:ok, definitions, sheet_id, namespace, is_nil(shortcut)}
        {:error, _reason} = error -> error
      end
    end
  end

  defp portable_sheet_variable_definitions(entry), do: {:error, {:invalid_portable_variable_sheet, entry}}

  defp portable_sheet_variable_definitions(blocks, namespace) do
    Enum.reduce_while(blocks, {:ok, []}, fn block, {:ok, definitions} ->
      case portable_block_variable_definitions(block, namespace) do
        {:ok, block_definitions} -> {:cont, {:ok, definitions ++ block_definitions}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_block_variable_definitions(
         %{"original_id" => block_id, "type" => type, "is_constant" => false, "variable_name" => variable_name},
         namespace
       )
       when type in @regular_variable_types and is_binary(variable_name) and variable_name != "" do
    {:ok,
     [
       %{
         block_id: block_id,
         resolution_key: {:regular, namespace, variable_name},
         qualified_ref: Enum.join([namespace, variable_name], ".")
       }
     ]}
  end

  defp portable_block_variable_definitions(
         %{
           "original_id" => block_id,
           "type" => "table",
           "variable_name" => table_name,
           "table_data" => %{"columns" => columns, "rows" => rows}
         },
         namespace
       )
       when is_binary(table_name) and table_name != "" and is_list(columns) and is_list(rows) do
    with :ok <- validate_portable_table_entries(block_id, columns, rows) do
      variable_columns = Enum.filter(columns, &portable_variable_column?/1)

      definitions =
        for row <- rows,
            column <- variable_columns,
            is_binary(row["slug"]) and row["slug"] != "",
            is_binary(column["slug"]) and column["slug"] != "" do
          variable_name = Enum.join([table_name, row["slug"], column["slug"]], ".")

          %{
            block_id: block_id,
            resolution_key: {:table, namespace, table_name, row["slug"], column["slug"]},
            qualified_ref: Enum.join([namespace, variable_name], ".")
          }
        end

      {:ok, definitions}
    end
  end

  defp portable_block_variable_definitions(%{} = _block, _namespace), do: {:ok, []}

  defp portable_block_variable_definitions(block, _namespace), do: {:error, {:invalid_portable_variable_block, block}}

  defp portable_variable_column?(column) when is_map(column) do
    column["type"] in @table_variable_types and
      (column["is_constant"] == false or column["type"] in @constant_table_variable_types)
  end

  defp portable_variable_column?(_column), do: false

  defp put_portable_sheet_definitions(catalog, definitions, sheet_id, namespace, rewritable?) do
    namespace_owner = Map.get(catalog.namespace_owners, namespace)

    cond do
      MapSet.member?(catalog.sheet_ids, sheet_id) ->
        {:halt, {:error, {:duplicate_portable_variable_sheet_identity, sheet_id}}}

      definitions != [] and not is_nil(namespace_owner) ->
        {:halt, {:error, {:ambiguous_portable_variable_namespace, namespace, namespace_owner, sheet_id}}}

      true ->
        case put_portable_variable_definitions(catalog, definitions, rewritable?) do
          {:ok, catalog} ->
            {:cont,
             {:ok,
              put_portable_sheet_namespace(
                catalog,
                definitions,
                sheet_id,
                namespace,
                rewritable?
              )}}

          {:error, _reason} = error ->
            {:halt, error}
        end
    end
  end

  defp put_portable_sheet_namespace(catalog, definitions, sheet_id, namespace, rewritable?) do
    has_definitions? = definitions != []

    %{
      catalog
      | sheet_ids: MapSet.put(catalog.sheet_ids, sheet_id),
        namespace_owners:
          maybe_put_portable_namespace(
            catalog.namespace_owners,
            has_definitions?,
            namespace,
            sheet_id
          ),
        rewritable_namespaces:
          maybe_put_portable_namespace(
            catalog.rewritable_namespaces,
            rewritable? and has_definitions?,
            namespace,
            sheet_id
          )
    }
  end

  defp maybe_put_portable_namespace(namespaces, true, namespace, sheet_id), do: Map.put(namespaces, namespace, sheet_id)

  defp maybe_put_portable_namespace(namespaces, false, _namespace, _sheet_id), do: namespaces

  defp put_portable_variable_definitions(catalog, definitions, rewritable?) do
    Enum.reduce_while(definitions, {:ok, catalog}, fn definition, {:ok, acc} ->
      cond do
        MapSet.member?(acc.resolution_keys, definition.resolution_key) or
            MapSet.member?(acc.resolution_keys, {:qualified, definition.qualified_ref}) ->
          {:halt, {:error, {:ambiguous_portable_variable_definition, definition.resolution_key}}}

        Map.has_key?(acc.qualified_targets, definition.qualified_ref) ->
          {:halt, {:error, {:ambiguous_portable_variable_definition, definition.qualified_ref}}}

        true ->
          acc = %{
            acc
            | resolution_keys:
                acc.resolution_keys
                |> MapSet.put(definition.resolution_key)
                |> MapSet.put({:qualified, definition.qualified_ref}),
              qualified_targets:
                Map.put(
                  acc.qualified_targets,
                  definition.qualified_ref,
                  definition.resolution_key
                ),
              rewritable_qualified_targets:
                if(rewritable?,
                  do:
                    Map.put(
                      acc.rewritable_qualified_targets,
                      definition.qualified_ref,
                      definition.resolution_key
                    ),
                  else: acc.rewritable_qualified_targets
                )
          }

          {:cont, {:ok, acc}}
      end
    end)
  end

  defp portable_snapshot_reference_specs(project_snapshot) do
    with {:ok, sources} <- portable_snapshot_variable_sources(project_snapshot),
         {:ok, source_specs} <- strict_portable_snapshot_source_specs(sources),
         {:ok, formula_specs} <- portable_formula_binding_specs(project_snapshot) do
      {:ok, source_specs ++ formula_specs}
    end
  end

  defp portable_snapshot_variable_sources(%{"flows" => flows, "scenes" => scenes})
       when is_list(flows) and is_list(scenes) do
    with {:ok, flow_sources} <- portable_flow_variable_sources(flows),
         {:ok, scene_sources} <- portable_scene_variable_sources(scenes) do
      {:ok, flow_sources ++ scene_sources}
    end
  end

  defp portable_snapshot_variable_sources(project_snapshot),
    do: {:error, {:invalid_portable_variable_sources, project_snapshot}}

  defp portable_flow_variable_sources(flows) do
    Enum.reduce_while(flows, {:ok, []}, fn
      %{"snapshot" => %{"nodes" => nodes}}, {:ok, sources} when is_list(nodes) ->
        if Enum.all?(nodes, &is_map/1) do
          {:cont,
           {:ok,
            sources ++
              Enum.map(nodes, &VariableReferenceExtraction.flow_snapshot_source/1)}}
        else
          {:halt, {:error, :invalid_portable_flow_variable_sources}}
        end

      _entry, _acc ->
        {:halt, {:error, :invalid_portable_flow_variable_sources}}
    end)
  end

  defp portable_scene_variable_sources(scenes) do
    Enum.reduce_while(scenes, {:ok, []}, fn
      %{"snapshot" => snapshot}, {:ok, sources} when is_map(snapshot) ->
        case scene_snapshot_variable_source_collection(snapshot) do
          {:ok, scene_sources} -> {:cont, {:ok, sources ++ scene_sources}}
          {:error, _reason} = error -> {:halt, error}
        end

      _entry, _acc ->
        {:halt, {:error, :invalid_portable_scene_variable_sources}}
    end)
  end

  defp scene_snapshot_variable_source_collection(snapshot) do
    VariableReferenceExtraction.entity_snapshot_sources("scene", snapshot)
  end

  defp strict_portable_snapshot_source_specs(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, specs} ->
      case VariableReferenceExtraction.strict_snapshot_source_specs(source) do
        {:ok, source_type, source_specs} ->
          tagged = Enum.map(source_specs, &Map.put(&1, :source_type, source_type))
          {:cont, {:ok, specs ++ tagged}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp portable_formula_binding_specs(%{"sheets" => sheets}) when is_list(sheets) do
    Enum.reduce_while(sheets, {:ok, []}, fn entry, {:ok, specs} ->
      case portable_sheet_formula_binding_specs(entry) do
        {:ok, sheet_specs} -> {:cont, {:ok, specs ++ sheet_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_formula_binding_specs(project_snapshot),
    do: {:error, {:invalid_portable_formula_snapshot, project_snapshot}}

  defp portable_sheet_formula_binding_specs(%{"snapshot" => %{"blocks" => blocks}}) when is_list(blocks) do
    Enum.reduce_while(blocks, {:ok, []}, fn block, {:ok, specs} ->
      case portable_block_formula_binding_specs(block) do
        {:ok, block_specs} -> {:cont, {:ok, specs ++ block_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_sheet_formula_binding_specs(entry), do: {:error, {:invalid_portable_formula_sheet, entry}}

  defp portable_block_formula_binding_specs(%{
         "original_id" => block_id,
         "type" => "table",
         "table_data" => %{"columns" => columns, "rows" => rows}
       })
       when is_list(columns) and is_list(rows) do
    with :ok <- validate_portable_table_entries(block_id, columns, rows) do
      columns_by_slug = Map.new(columns, &{&1["slug"], &1})
      formula_columns = Enum.filter(columns, &(&1["type"] == "formula"))
      portable_formula_rows_specs(rows, block_id, formula_columns, columns_by_slug)
    end
  end

  defp portable_block_formula_binding_specs(%{} = _block), do: {:ok, []}

  defp portable_block_formula_binding_specs(block), do: {:error, {:invalid_portable_formula_block, block}}

  defp validate_portable_table_entries(block_id, columns, rows) do
    with :ok <- validate_portable_table_entry_maps(block_id, :column, columns) do
      validate_portable_table_entry_maps(block_id, :row, rows)
    end
  end

  defp validate_portable_table_entry_maps(block_id, kind, entries) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn
      {entry, _index}, :ok when is_map(entry) ->
        {:cont, :ok}

      {entry, index}, :ok ->
        {:halt, invalid_portable_table_entry(kind, block_id, index, entry)}
    end)
  end

  defp invalid_portable_table_entry(:column, block_id, index, entry),
    do: {:error, {:invalid_portable_table_column, block_id, index, entry}}

  defp invalid_portable_table_entry(:row, block_id, index, entry),
    do: {:error, {:invalid_portable_table_row, block_id, index, entry}}

  defp portable_formula_rows_specs(rows, block_id, formula_columns, columns_by_slug) do
    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, specs} ->
      case portable_formula_row_specs(block_id, row, formula_columns, columns_by_slug) do
        {:ok, row_specs} -> {:cont, {:ok, specs ++ row_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_formula_row_specs(
         block_id,
         %{"original_id" => row_id, "cells" => cells},
         formula_columns,
         columns_by_slug
       )
       when is_map(cells) do
    case cells |> Map.keys() |> Enum.sort() |> Enum.find(&(not Map.has_key?(columns_by_slug, &1))) do
      nil ->
        portable_formula_column_specs(
          formula_columns,
          block_id,
          row_id,
          cells,
          columns_by_slug
        )

      unknown_slug ->
        {:error, {:invalid_portable_table_cell_key, block_id, row_id, unknown_slug}}
    end
  end

  defp portable_formula_row_specs(block_id, row, _formula_columns, _columns_by_slug),
    do: {:error, {:invalid_portable_formula_row, block_id, row}}

  defp portable_formula_column_specs(formula_columns, block_id, row_id, cells, columns_by_slug) do
    Enum.reduce_while(formula_columns, {:ok, []}, fn column, {:ok, specs} ->
      case portable_formula_cell_specs(
             block_id,
             row_id,
             column,
             columns_by_slug,
             Map.get(cells, column["slug"])
           ) do
        {:ok, cell_specs} -> {:cont, {:ok, specs ++ cell_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_formula_cell_specs(_block_id, _row_id, _column, _columns_by_slug, nil), do: {:ok, []}

  defp portable_formula_cell_specs(
         block_id,
         row_id,
         %{"slug" => column_slug} = column,
         columns_by_slug,
         %{"expression" => expression, "bindings" => bindings} = cell
       )
       when is_binary(column_slug) and is_binary(expression) and is_map(bindings) do
    with true <- Enum.sort(Map.keys(cell)) == ["bindings", "expression"],
         symbols = portable_formula_symbols(expression),
         true <- MapSet.subset?(MapSet.new(Map.keys(bindings)), symbols),
         {:ok, specs} <-
           portable_formula_binding_specs(
             block_id,
             row_id,
             column,
             columns_by_slug,
             bindings
           ) do
      {:ok, specs}
    else
      _invalid -> {:error, {:invalid_portable_formula_cell, block_id, row_id, column_slug, cell}}
    end
  end

  defp portable_formula_cell_specs(block_id, row_id, column, _columns_by_slug, cell) do
    column_slug = if is_map(column), do: column["slug"]
    {:error, {:invalid_portable_formula_cell, block_id, row_id, column_slug, cell}}
  end

  defp portable_formula_symbols(expression) do
    case FormulaEngine.parse(expression) do
      {:ok, ast} -> ast |> FormulaEngine.extract_symbols() |> MapSet.new()
      {:error, _reason} -> MapSet.new()
    end
  end

  defp portable_formula_binding_specs(block_id, row_id, column, columns_by_slug, bindings) do
    Enum.reduce_while(bindings, {:ok, []}, fn {symbol, binding}, {:ok, specs} ->
      case portable_formula_binding_spec(
             block_id,
             row_id,
             column,
             columns_by_slug,
             symbol,
             binding
           ) do
        {:ok, nil} -> {:cont, {:ok, specs}}
        {:ok, spec} -> {:cont, {:ok, [spec | specs]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_formula_binding_spec(
         _block_id,
         _row_id,
         %{"slug" => column_slug},
         columns_by_slug,
         _symbol,
         %{"type" => "same_row", "column_slug" => referenced_slug} = binding
       )
       when is_binary(referenced_slug) and referenced_slug != "" do
    referenced_column = Map.get(columns_by_slug, referenced_slug)

    if Enum.sort(Map.keys(binding)) == ["column_slug", "type"] and
         referenced_slug != column_slug and is_map(referenced_column) and
         referenced_column["type"] in ["number", "formula"] do
      {:ok, nil}
    else
      {:error, :invalid_same_row_formula_binding}
    end
  end

  defp portable_formula_binding_spec(
         block_id,
         row_id,
         %{"slug" => column_slug},
         _columns_by_slug,
         symbol,
         %{"type" => "variable", "ref" => ref} = binding
       )
       when is_binary(symbol) and is_binary(ref) and ref != "" do
    case {
      Enum.sort(Map.keys(binding)),
      VariableReferenceExtraction.qualified_specs(row_id, "read", ref)
    } do
      {["ref", "type"], [spec]} ->
        {:ok,
         spec
         |> Map.put(:source_type, "table_formula")
         |> Map.put(:context, {:formula_binding, block_id, row_id, column_slug, symbol})}

      _invalid ->
        {:error, :invalid_variable_formula_binding}
    end
  end

  defp portable_formula_binding_spec(_block_id, _row_id, _column, _columns_by_slug, _symbol, _binding),
    do: {:error, :invalid_formula_binding}

  defp validate_portable_snapshot_specs(specs, resolution_keys) do
    case Enum.find(specs, &(not MapSet.member?(resolution_keys, &1.resolution_key))) do
      nil ->
        :ok

      %{source_type: "table_formula"} = spec ->
        {:error,
         {:unresolved_variable_reference, "table_formula", spec.source_id, spec.kind, spec.source_sheet,
          spec.source_variable}}

      spec ->
        {:error,
         {:unresolved_variable_reference, spec.source_type, spec.source_id, spec.kind, spec.source_sheet,
          spec.source_variable}}
    end
  end

  defp portable_variable_rewrites(
         %{
           version: 1,
           sheet_ids: %MapSet{} = sheet_ids,
           namespace_owners: namespace_owners,
           rewritable_namespaces: rewritable_namespaces,
           qualified_targets: qualified_targets,
           rewritable_qualified_targets: rewritable_qualified_targets
         },
         sheet_id_map
       )
       when is_map(namespace_owners) and is_map(rewritable_namespaces) and is_map(qualified_targets) and
              is_map(rewritable_qualified_targets) and is_map(sheet_id_map) do
    expected_ids = MapSet.new(Map.keys(sheet_id_map))

    with :ok <- validate_portable_sheet_id_map(sheet_ids, expected_ids, sheet_id_map),
         {:ok, namespace_rewrites} <-
           portable_destination_namespace_rewrites(
             namespace_owners,
             rewritable_namespaces,
             sheet_id_map
           ),
         {:ok, qualified_rewrites} <-
           portable_destination_qualified_rewrites(
             qualified_targets,
             namespace_rewrites
           ) do
      {:ok, %{namespace: namespace_rewrites, qualified: qualified_rewrites}}
    end
  end

  defp portable_variable_rewrites(plan, sheet_id_map),
    do: {:error, {:invalid_portable_variable_rewrite_plan, plan, sheet_id_map}}

  defp validate_portable_sheet_id_map(sheet_ids, expected_ids, sheet_id_map) do
    cond do
      expected_ids != sheet_ids or
          not Enum.all?(sheet_id_map, fn {source_id, destination_id} ->
            is_integer(source_id) and source_id > 0 and is_integer(destination_id) and
                destination_id > 0
          end) ->
        {:error,
         {:portable_variable_sheet_mapping_mismatch,
          %{
            expected: Enum.sort(sheet_ids),
            actual: Enum.sort(expected_ids)
          }}}

      map_size(sheet_id_map) != MapSet.size(MapSet.new(Map.values(sheet_id_map))) ->
        {:error, {:non_injective_portable_variable_sheet_mapping, sheet_id_map}}

      true ->
        :ok
    end
  end

  defp portable_destination_namespace_rewrites(namespace_owners, rewritable_namespaces, sheet_id_map) do
    namespace_owners
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}, %{}}, fn {old_namespace, source_id}, {:ok, rewrites, destination_owners} ->
      destination_namespace =
        if Map.get(rewritable_namespaces, old_namespace) == source_id do
          sheet_id_map |> Map.fetch!(source_id) |> Integer.to_string()
        else
          old_namespace
        end

      case Map.fetch(destination_owners, destination_namespace) do
        {:ok, other_source_id} ->
          {:halt,
           {:error, {:ambiguous_destination_variable_namespace, destination_namespace, other_source_id, source_id}}}

        :error ->
          {:cont,
           {:ok, Map.put(rewrites, old_namespace, destination_namespace),
            Map.put(destination_owners, destination_namespace, source_id)}}
      end
    end)
    |> case do
      {:ok, rewrites, _owners} -> {:ok, rewrites}
      {:error, _reason} = error -> error
    end
  end

  defp portable_destination_qualified_rewrites(qualified_targets, namespace_rewrites) do
    qualified_targets
    |> Enum.sort()
    |> Enum.reduce_while({:ok, %{}, %{}}, fn {old_ref, resolution_key}, {:ok, rewrites, destination_owners} ->
      destination_ref = rewritten_qualified_reference(resolution_key, namespace_rewrites)

      case Map.fetch(destination_owners, destination_ref) do
        {:ok, other_ref} ->
          {:halt, {:error, {:ambiguous_destination_variable_reference, destination_ref, other_ref, old_ref}}}

        :error ->
          {:cont,
           {:ok, Map.put(rewrites, old_ref, destination_ref), Map.put(destination_owners, destination_ref, old_ref)}}
      end
    end)
    |> case do
      {:ok, rewrites, _owners} -> {:ok, rewrites}
      {:error, _reason} = error -> error
    end
  end

  defp rewritten_qualified_reference({:regular, namespace, variable_name}, rewrites) do
    Enum.join([Map.fetch!(rewrites, namespace), variable_name], ".")
  end

  defp rewritten_qualified_reference({:table, namespace, table_name, row_slug, column_slug}, rewrites) do
    Enum.join(
      [Map.fetch!(rewrites, namespace), table_name, row_slug, column_slug],
      "."
    )
  end

  defp rewrite_portable_project(project_snapshot, rewrites) do
    project_snapshot
    |> Map.update("sheets", [], &Enum.map(&1, fn entry -> rewrite_portable_sheet_entry(entry, rewrites) end))
    |> Map.update("flows", [], &Enum.map(&1, fn entry -> rewrite_portable_flow_entry(entry, rewrites) end))
    |> Map.update("scenes", [], &Enum.map(&1, fn entry -> rewrite_portable_scene_entry(entry, rewrites) end))
  end

  defp rewrite_portable_sheet_entry(%{"snapshot" => snapshot} = entry, rewrites) do
    Map.put(entry, "snapshot", rewrite_portable_sheet_snapshot(snapshot, rewrites))
  end

  defp rewrite_portable_sheet_entry(entry, _rewrites), do: entry

  defp rewrite_portable_sheet_snapshot(%{"blocks" => blocks} = snapshot, rewrites) when is_list(blocks) do
    Map.put(snapshot, "blocks", Enum.map(blocks, &rewrite_portable_formula_block(&1, rewrites.qualified)))
  end

  defp rewrite_portable_sheet_snapshot(snapshot, _rewrites), do: snapshot

  defp rewrite_portable_formula_block(
         %{"type" => "table", "table_data" => %{"columns" => columns, "rows" => rows} = table_data} = block,
         qualified_rewrites
       )
       when is_list(columns) and is_list(rows) do
    formula_slugs =
      columns
      |> Enum.filter(&(is_map(&1) and &1["type"] == "formula" and is_binary(&1["slug"])))
      |> MapSet.new(& &1["slug"])

    rows = Enum.map(rows, &rewrite_portable_formula_row(&1, formula_slugs, qualified_rewrites))
    Map.put(block, "table_data", Map.put(table_data, "rows", rows))
  end

  defp rewrite_portable_formula_block(block, _qualified_rewrites), do: block

  defp rewrite_portable_formula_row(%{"cells" => cells} = row, formula_slugs, qualified_rewrites) when is_map(cells) do
    cells =
      Map.new(cells, fn {slug, value} ->
        if MapSet.member?(formula_slugs, slug) do
          {slug, rewrite_portable_formula_cell(value, qualified_rewrites)}
        else
          {slug, value}
        end
      end)

    Map.put(row, "cells", cells)
  end

  defp rewrite_portable_formula_row(row, _formula_slugs, _qualified_rewrites), do: row

  defp rewrite_portable_formula_cell(%{"bindings" => bindings} = cell, qualified_rewrites) when is_map(bindings) do
    bindings =
      Map.new(bindings, fn
        {symbol, %{"type" => "variable", "ref" => ref} = binding} ->
          {symbol, Map.put(binding, "ref", Map.get(qualified_rewrites, ref, ref))}

        pair ->
          pair
      end)

    Map.put(cell, "bindings", bindings)
  end

  defp rewrite_portable_formula_cell(cell, _qualified_rewrites), do: cell

  defp rewrite_portable_flow_entry(%{"snapshot" => snapshot} = entry, rewrites) do
    Map.put(entry, "snapshot", rewrite_portable_flow_snapshot(snapshot, rewrites))
  end

  defp rewrite_portable_flow_entry(entry, _rewrites), do: entry

  defp rewrite_portable_flow_snapshot(%{"nodes" => nodes} = snapshot, rewrites) when is_list(nodes) do
    nodes = Enum.map(nodes, &rewrite_portable_flow_node(&1, rewrites))

    Map.put(snapshot, "nodes", nodes)
  end

  defp rewrite_portable_flow_snapshot(snapshot, _rewrites), do: snapshot

  defp rewrite_portable_flow_node(%{"type" => "instruction", "data" => data} = node, rewrites) when is_map(data) do
    Map.put(node, "data", rewrite_assignments_in_payload(data, rewrites))
  end

  defp rewrite_portable_flow_node(%{"type" => "condition", "data" => data} = node, rewrites) when is_map(data) do
    Map.put(node, "data", rewrite_existing(data, "condition", &rewrite_condition(&1, rewrites)))
  end

  defp rewrite_portable_flow_node(%{"type" => "dialogue", "data" => data} = node, rewrites) when is_map(data) do
    data =
      rewrite_existing(data, "responses", fn responses ->
        Enum.map(responses, &rewrite_dialogue_response(&1, rewrites))
      end)

    Map.put(node, "data", data)
  end

  defp rewrite_portable_flow_node(node, _rewrites), do: node

  defp rewrite_dialogue_response(%{} = response, rewrites) do
    response =
      rewrite_existing(
        response,
        "condition",
        &rewrite_condition_encoding(&1, rewrites)
      )

    case Map.get(response, "instruction_assignments") do
      [_assignment | _rest] ->
        rewrite_existing(
          response,
          "instruction_assignments",
          &rewrite_assignments(&1, rewrites)
        )

      assignments when assignments in [nil, []] ->
        rewrite_existing(
          response,
          "instruction",
          &rewrite_instruction_encoding(&1, rewrites)
        )

      _invalid ->
        response
    end
  end

  defp rewrite_dialogue_response(response, _rewrites), do: response

  defp rewrite_condition_encoding(condition, rewrites) when is_binary(condition) do
    case Jason.decode(condition) do
      {:ok, %{} = decoded} ->
        rewritten = rewrite_condition(decoded, rewrites)
        if rewritten == decoded, do: condition, else: Jason.encode!(rewritten)

      _invalid ->
        condition
    end
  end

  defp rewrite_condition_encoding(condition, rewrites), do: rewrite_condition(condition, rewrites)

  defp rewrite_instruction_encoding(instruction, rewrites) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) ->
        rewritten = rewrite_assignments(assignments, rewrites)
        if rewritten == assignments, do: instruction, else: Jason.encode!(rewritten)

      _invalid ->
        instruction
    end
  end

  defp rewrite_instruction_encoding(instruction, _rewrites), do: instruction

  defp rewrite_portable_scene_entry(%{"snapshot" => snapshot} = entry, rewrites) do
    Map.put(entry, "snapshot", rewrite_portable_scene_snapshot(snapshot, rewrites))
  end

  defp rewrite_portable_scene_entry(entry, _rewrites), do: entry

  defp rewrite_portable_scene_snapshot(snapshot, rewrites) when is_map(snapshot) do
    snapshot
    |> rewrite_existing("layers", &rewrite_portable_scene_layers(&1, rewrites))
    |> rewrite_existing("orphan_pins", &rewrite_portable_scene_elements(&1, rewrites))
    |> rewrite_existing("orphan_zones", &rewrite_portable_scene_elements(&1, rewrites))
    |> rewrite_existing("ambient_flows", &rewrite_portable_ambient_flows(&1, rewrites))
  end

  defp rewrite_portable_scene_snapshot(snapshot, _rewrites), do: snapshot

  defp rewrite_portable_scene_layers(layers, rewrites) do
    Enum.map(layers, fn layer ->
      layer
      |> rewrite_existing("pins", &rewrite_portable_scene_elements(&1, rewrites))
      |> rewrite_existing("zones", &rewrite_portable_scene_elements(&1, rewrites))
    end)
  end

  defp rewrite_portable_scene_elements(elements, rewrites),
    do: Enum.map(elements, &rewrite_portable_scene_element(&1, rewrites))

  defp rewrite_portable_ambient_flows(ambient_flows, rewrites),
    do: Enum.map(ambient_flows, &rewrite_portable_ambient_flow(&1, rewrites))

  defp rewrite_portable_scene_element(element, rewrites) when is_map(element) do
    element
    |> rewrite_portable_scene_action(rewrites)
    |> rewrite_existing("condition", &rewrite_condition(&1, rewrites))
  end

  defp rewrite_portable_scene_element(element, _rewrites), do: element

  defp rewrite_portable_ambient_flow(%{"trigger_type" => "on_event", "trigger_config" => config} = ambient, rewrites)
       when is_map(config) do
    config =
      rewrite_existing(config, "variable_ref", fn ref ->
        if is_binary(ref), do: Map.get(rewrites.qualified, ref, ref), else: ref
      end)

    Map.put(ambient, "trigger_config", config)
  end

  defp rewrite_portable_ambient_flow(ambient, _rewrites), do: ambient

  defp rewrite_portable_scene_action(%{"action_type" => "action"} = element, rewrites) do
    rewrite_existing(element, "action_data", &rewrite_assignments_in_payload(&1, rewrites))
  end

  defp rewrite_portable_scene_action(%{"action_type" => "display"} = element, rewrites) do
    rewrite_existing(element, "action_data", &rewrite_portable_display_action(&1, rewrites))
  end

  defp rewrite_portable_scene_action(%{"action_type" => "collection"} = element, rewrites) do
    rewrite_existing(element, "action_data", &rewrite_portable_collection_action(&1, rewrites))
  end

  defp rewrite_portable_scene_action(element, _rewrites), do: element

  defp rewrite_portable_display_action(data, rewrites) do
    rewrite_existing(data, "variable_ref", &rewrite_qualified_variable_ref(&1, rewrites))
  end

  defp rewrite_qualified_variable_ref(ref, rewrites) when is_binary(ref), do: Map.get(rewrites.qualified, ref, ref)

  defp rewrite_qualified_variable_ref(ref, _rewrites), do: ref

  defp rewrite_portable_collection_action(data, rewrites) do
    rewrite_existing(data, "items", fn items ->
      Enum.map(items, &rewrite_portable_collection_item(&1, rewrites))
    end)
  end

  defp rewrite_portable_collection_item(%{} = item, rewrites) do
    item
    |> rewrite_existing("condition", &rewrite_condition(&1, rewrites))
    |> rewrite_existing("instruction", &rewrite_portable_collection_instruction(&1, rewrites))
  end

  defp rewrite_portable_collection_item(item, _rewrites), do: item

  defp rewrite_portable_collection_instruction(%{} = instruction, rewrites),
    do: rewrite_assignments_in_payload(instruction, rewrites)

  defp rewrite_portable_collection_instruction(instruction, _rewrites), do: instruction

  defp rewrite_assignments_in_payload(%{} = payload, rewrites) do
    rewrite_existing(payload, "assignments", &rewrite_assignments(&1, rewrites))
  end

  defp rewrite_assignments_in_payload(payload, _rewrites), do: payload

  defp rewrite_assignments(assignments, rewrites) when is_list(assignments) do
    Enum.map(assignments, &rewrite_assignment(&1, rewrites))
  end

  defp rewrite_assignments(assignments, _rewrites), do: assignments

  defp rewrite_assignment(%{} = assignment, rewrites) do
    assignment = rewrite_portable_sheet_field(assignment, "sheet", rewrites.namespace)

    if assignment["value_type"] == "variable_ref",
      do: rewrite_portable_sheet_field(assignment, "value_sheet", rewrites.namespace),
      else: assignment
  end

  defp rewrite_assignment(assignment, _rewrites), do: assignment

  defp rewrite_condition(%{} = condition, rewrites) do
    Map.new(condition, fn
      {"rules", rules} when is_list(rules) ->
        {"rules", Enum.map(rules, &rewrite_condition_rule(&1, rewrites))}

      {"blocks", blocks} when is_list(blocks) ->
        {"blocks", Enum.map(blocks, &rewrite_condition(&1, rewrites))}

      pair ->
        pair
    end)
  end

  defp rewrite_condition(condition, _rewrites), do: condition

  defp rewrite_condition_rule(%{} = rule, rewrites) do
    rewrite_portable_sheet_field(rule, "sheet", rewrites.namespace)
  end

  defp rewrite_condition_rule(rule, _rewrites), do: rule

  defp rewrite_portable_sheet_field(payload, field, rewrites) do
    case Map.fetch(payload, field) do
      {:ok, namespace} when is_binary(namespace) ->
        Map.put(payload, field, Map.get(rewrites, namespace, namespace))

      _missing_or_nonbinary ->
        payload
    end
  end

  defp rewrite_existing(payload, field, rewrite) when is_map(payload) and is_function(rewrite, 1) do
    case Map.fetch(payload, field) do
      {:ok, value} -> Map.put(payload, field, rewrite.(value))
      :error -> payload
    end
  end

  @doc false
  def variable_rewrites(plan, sheet_id_map), do: portable_variable_rewrites(plan, sheet_id_map)

  @doc false
  def rewrite_formula_row(row, formula_slugs, qualified_rewrites),
    do: rewrite_portable_formula_row(row, formula_slugs, qualified_rewrites)
end
