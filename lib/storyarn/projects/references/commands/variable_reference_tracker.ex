defmodule Storyarn.Projects.References.VariableReferenceTracker do
  @moduledoc """
  Tracks which sources read/write which variables (blocks).

  Handles ALL polymorphic variable reference sources:
  - **Flow nodes** — condition/dialogue rules → reads, instruction/dialogue assignments → writes
  - **Map zones** — action assignments → writes, display variable_ref → reads, condition → reads
  - **Map pins** — flow/display references and conditions → reads
  - **Scene ambient flows** — on-event variable_ref → reads

  Called after every Flow node, Scene pin/zone, or Scene ambient-flow save.
  Extracts references from the source's structured data and upserts them into
  `variable_references` with one of the four supported `source_type` values:
  `"flow_node"`, `"scene_pin"`, `"scene_zone"`, or
  `"scene_ambient_flow"`.

  Stores `source_sheet` and `source_variable` alongside each reference so that
  staleness detection and repair can be done with simple SQL comparisons
  instead of scanning JSON in Elixir.

  This is the transitional owner for the legacy cross-context projection. Each
  bounded context can consume the same table through its own record while the
  remaining Scene and Project lifecycle operations are migrated to their final
  owners.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.FlowFormulaEngine, as: FormulaEngine
  alias Storyarn.Projects.References.FlowCondition
  alias Storyarn.Projects.References.Persistence.BlockRecord, as: Block
  alias Storyarn.Projects.References.Persistence.FlowNodeRecord
  alias Storyarn.Projects.References.Persistence.FlowRecord
  alias Storyarn.Projects.References.Persistence.SceneAmbientFlowRecord, as: SceneAmbientFlow
  alias Storyarn.Projects.References.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.References.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.References.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.Projects.References.Persistence.SheetRecord, as: Sheet
  alias Storyarn.Projects.References.Persistence.TableColumnRecord, as: TableColumn
  alias Storyarn.Projects.References.Persistence.TableRowRecord, as: TableRow
  alias Storyarn.Projects.References.VariableCatalog
  alias Storyarn.Projects.References.VariableNamespaceResolver
  alias Storyarn.Projects.References.VariableProjectionQueries
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Repo

  require VariableNamespaceResolver

  @rebuild_batch_size 100
  @regular_variable_types VariableCatalog.regular_variable_types()
  @table_variable_types VariableCatalog.table_variable_types()
  @constant_table_variable_types VariableCatalog.constant_table_variable_types()

  @type rebuild_error ::
          {:invalid_project_id, term()}
          | {:project_variable_reference_rebuild_failed,
             %{
               project_id: integer(),
               source_type: String.t(),
               source_id: integer(),
               reason: term()
             }}

  @doc """
  Restores variable-reference rows that can be resolved from every active
  source in a project.

  Active sources are:

  * non-deleted nodes that belong to non-deleted flows
  * pins, zones, and ambient-flow links that belong to non-deleted scenes

  This operation is deliberately additive. Existing rows may represent stale
  references after a Sheet shortcut, block variable, or table slug changed;
  those rows must remain available to the stale-reference repair workflow.
  Replacing all rows here would destroy that recovery information.

  The caller is responsible for the outer transaction so the rebuild can be
  committed or rolled back with the operation that made it necessary.
  """
  @spec rebuild_project_variable_references(integer()) :: :ok | {:error, rebuild_error()}
  def rebuild_project_variable_references(project_id) when is_integer(project_id) and project_id > 0 do
    with :ok <-
           rebuild_sources(
             active_flow_nodes_query(project_id),
             project_id,
             "flow_node",
             &restore_missing_flow_node_references/1
           ),
         :ok <-
           rebuild_sources(
             active_scene_pins_query(project_id),
             project_id,
             "scene_pin",
             &restore_missing_scene_pin_references(&1, project_id)
           ),
         :ok <-
           rebuild_sources(
             active_scene_zones_query(project_id),
             project_id,
             "scene_zone",
             &restore_missing_scene_zone_references(&1, project_id)
           ) do
      rebuild_sources(
        active_scene_ambient_flows_query(project_id),
        project_id,
        "scene_ambient_flow",
        &restore_missing_scene_ambient_flow_references(&1, project_id)
      )
    end
  end

  def rebuild_project_variable_references(project_id), do: {:error, {:invalid_project_id, project_id}}

  @doc """
  Updates variable references for a node after its data changes.
  Dispatches to the correct extractor based on node type.
  """
  @spec update_references(map()) :: :ok | {:error, term()}
  def update_references(%{id: node_id, flow_id: flow_id, type: type, data: data} = node)
      when is_integer(node_id) and is_integer(flow_id) and is_binary(type) and is_map(data) do
    refs = extract_flow_node_variable_refs(node)

    replace_references("flow_node", node_id, refs, flow_node_id: node_id)
  end

  @doc false
  @spec flow_node_references_current_ids([map()], integer()) ::
          MapSet.t(integer())
  def flow_node_references_current_ids(nodes, project_id) when is_list(nodes) and is_integer(project_id) do
    valid_nodes =
      Enum.filter(nodes, fn
        %{id: node_id, data: data}
        when is_integer(node_id) and is_map(data) ->
          true

        _node ->
          false
      end)

    node_ids = Enum.map(valid_nodes, & &1.id)
    specs = Enum.flat_map(valid_nodes, &flow_node_reference_specs/1)
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)
    expected_by_node = expected_flow_node_reference_sets(specs, resolved_block_ids)
    actual_by_node = actual_flow_node_reference_sets(node_ids)

    Enum.reduce(valid_nodes, MapSet.new(), fn node, current_ids ->
      expected = Map.get(expected_by_node, node.id, MapSet.new())
      actual = Map.get(actual_by_node, node.id, MapSet.new())

      if expected == actual,
        do: MapSet.put(current_ids, node.id),
        else: current_ids
    end)
  end

  @doc """
  Validates that every complete variable reference embedded in Flow node data
  resolves to an active block in the project.

  This accepts both persisted `FlowNode` structs and snapshot node maps. It is
  intentionally stricter than the reference rebuild path: rebuilds preserve
  incomplete editor drafts and skip stale names, while an in-place historical
  restore must fail closed rather than persist a nominal reference that cannot
  be represented in `variable_references`.
  """
  @spec validate_flow_node_variable_targets([map() | struct()], integer()) ::
          :ok | {:error, term()}
  def validate_flow_node_variable_targets(nodes, project_id)
      when is_list(nodes) and is_integer(project_id) and project_id > 0 do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, specs} ->
      case strict_flow_node_reference_specs(node) do
        {:ok, node_specs} -> {:cont, {:ok, specs ++ node_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, "flow_node", specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_flow_node_variable_targets(nodes, project_id),
    do: {:error, {:invalid_variable_reference_validation_scope, "flow_node", project_id, nodes}}

  @doc """
  Validates complete variable references embedded in Scene pin or zone data.

  `source_type` must be `"scene_pin"` or `"scene_zone"`. Elements may be
  persisted structs or snapshot maps with string keys. This API lets restore
  builders share the exact resolver used by runtime reference tracking.
  """
  @spec validate_scene_element_variable_targets([map()], integer(), String.t()) ::
          :ok | {:error, term()}
  def validate_scene_element_variable_targets(elements, project_id, source_type)
      when is_list(elements) and is_integer(project_id) and project_id > 0 and source_type in ["scene_pin", "scene_zone"] do
    elements
    |> Enum.reduce_while({:ok, []}, fn element, {:ok, specs} ->
      case strict_scene_element_reference_specs(element, source_type) do
        {:ok, element_specs} -> {:cont, {:ok, specs ++ element_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, source_type, specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_scene_element_variable_targets(elements, project_id, source_type),
    do: {:error, {:invalid_variable_reference_validation_scope, source_type, project_id, elements}}

  @doc """
  Validates a mixed collection of snapshot variable-reference sources with one
  batched target resolution.

  Each source map must include `source_type` (`"flow_node"`, `"scene_pin"`,
  `"scene_zone"`, or `"scene_ambient_flow"`) and `source_id`. Flow sources
  also carry `type` and `data`; pin sources carry `condition`; zone sources
  carry `action_type`, `action_data`, and `condition`; ambient-flow sources
  carry `trigger_type` and `trigger_config`.
  """
  @spec validate_snapshot_variable_references(integer(), [map()]) ::
          :ok | {:error, term()}
  def validate_snapshot_variable_references(project_id, sources)
      when is_integer(project_id) and project_id > 0 and is_list(sources) do
    sources
    |> Enum.reduce_while({:ok, []}, fn source, {:ok, specs} ->
      case strict_snapshot_source_reference_specs(source) do
        {:ok, source_type, source_specs} ->
          tagged_specs = Enum.map(source_specs, &Map.put(&1, :source_type, source_type))
          {:cont, {:ok, specs ++ tagged_specs}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, specs} -> validate_resolvable_specs(project_id, nil, specs)
      {:error, _reason} = error -> error
    end
  end

  def validate_snapshot_variable_references(project_id, sources),
    do: {:error, {:invalid_variable_reference_validation_scope, :mixed, project_id, sources}}

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

  @doc false
  @spec rewrite_materialized_formula_bindings(
          pos_integer(),
          portable_project_snapshot_plan(),
          map()
        ) ::
          :ok | {:error, term()}
  def rewrite_materialized_formula_bindings(project_id, plan, sheet_id_map)
      when is_integer(project_id) and project_id > 0 and is_map(plan) and is_map(sheet_id_map) do
    with {:ok, rewrites} <- portable_variable_rewrites(plan, sheet_id_map),
         {:ok, formula_columns} <- materialized_formula_columns(project_id) do
      rewrite_materialized_formula_rows(project_id, formula_columns, rewrites.qualified)
    end
  end

  def rewrite_materialized_formula_bindings(project_id, plan, sheet_id_map),
    do: {:error, {:invalid_materialized_formula_rewrite, project_id, plan, sheet_id_map}}

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
          {:cont, {:ok, sources ++ Enum.map(nodes, &flow_snapshot_variable_source/1)}}
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
    with {:ok, layers} <- snapshot_reference_collection(snapshot, "scene", "layers"),
         {:ok, layer_pins} <- layer_snapshot_variable_sources(layers, "pins", "scene_pin"),
         {:ok, layer_zones} <- layer_snapshot_variable_sources(layers, "zones", "scene_zone"),
         {:ok, orphan_pins} <- snapshot_reference_collection(snapshot, "scene", "orphan_pins"),
         {:ok, orphan_zones} <- snapshot_reference_collection(snapshot, "scene", "orphan_zones"),
         {:ok, ambient_flows} <- snapshot_reference_collection(snapshot, "scene", "ambient_flows") do
      {:ok,
       layer_pins ++
         layer_zones ++
         scene_snapshot_variable_sources(orphan_pins, "scene_pin") ++
         scene_snapshot_variable_sources(orphan_zones, "scene_zone") ++
         Enum.map(ambient_flows, &scene_ambient_snapshot_variable_source/1)}
    end
  end

  defp strict_portable_snapshot_source_specs(sources) do
    Enum.reduce_while(sources, {:ok, []}, fn source, {:ok, specs} ->
      case strict_snapshot_source_reference_specs(source) do
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
    columns_by_slug = Map.new(columns, &{&1["slug"], &1})
    formula_columns = Enum.filter(columns, &(&1["type"] == "formula"))

    Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, specs} ->
      case portable_formula_row_specs(block_id, row, formula_columns, columns_by_slug) do
        {:ok, row_specs} -> {:cont, {:ok, specs ++ row_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp portable_block_formula_binding_specs(%{} = _block), do: {:ok, []}

  defp portable_block_formula_binding_specs(block), do: {:error, {:invalid_portable_formula_block, block}}

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
    case {Enum.sort(Map.keys(binding)), qualified_reference_specs(row_id, "read", ref)} do
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

  defp materialized_formula_columns(project_id) do
    columns =
      Repo.all(
        from(column in TableColumn,
          join: block in Block,
          on: block.id == column.block_id,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
              is_nil(block.deleted_at) and block.type == "table" and
              column.type == "formula",
          select: {column.block_id, column.slug}
        )
      )

    {:ok,
     Enum.reduce(columns, %{}, fn {block_id, slug}, acc ->
       Map.update(acc, block_id, MapSet.new([slug]), &MapSet.put(&1, slug))
     end)}
  end

  defp rewrite_materialized_formula_rows(_project_id, formula_columns, _qualified_rewrites)
       when map_size(formula_columns) == 0, do: :ok

  defp rewrite_materialized_formula_rows(project_id, formula_columns, qualified_rewrites) do
    block_ids = Map.keys(formula_columns)

    rows =
      Repo.all(
        from(row in TableRow,
          join: block in Block,
          on: block.id == row.block_id,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
              is_nil(block.deleted_at) and row.block_id in ^block_ids,
          order_by: [asc: row.id],
          lock: "FOR UPDATE"
        )
      )

    Enum.reduce_while(rows, :ok, fn row, :ok ->
      formula_slugs = Map.fetch!(formula_columns, row.block_id)
      cells = rewrite_portable_formula_row(%{"cells" => row.cells}, formula_slugs, qualified_rewrites)["cells"]

      rewrite_materialized_formula_row(row, cells)
    end)
  end

  defp rewrite_materialized_formula_row(row, cells) when cells == row.cells, do: {:cont, :ok}

  defp rewrite_materialized_formula_row(row, cells) do
    case row |> Ecto.Changeset.change(cells: cells) |> Repo.update() do
      {:ok, _row} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, {:materialized_formula_binding_rewrite_failed, row.id, reason}}}
    end
  end

  @doc """
  Extracts and validates every variable-reference surface from an entity
  snapshot.

  Flow snapshots contribute every node. Scene snapshots contribute every pin,
  zone, and ambient flow across layered and orphan children. The strict source
  parser accepts canonical sources without variable surfaces and rejects
  malformed ones exactly as restore does. Sheet snapshots have no
  variable-reference surfaces of their own.
  """
  @spec validate_entity_snapshot_variable_references(integer(), String.t(), map()) ::
          :ok | {:error, term()}
  def validate_entity_snapshot_variable_references(project_id, "flow", %{} = snapshot)
      when is_integer(project_id) and project_id > 0 do
    with {:ok, nodes} <- snapshot_reference_collection(snapshot, "flow", "nodes") do
      sources = Enum.map(nodes, &flow_snapshot_variable_source/1)

      validate_snapshot_variable_references(project_id, sources)
    end
  end

  def validate_entity_snapshot_variable_references(project_id, "scene", %{} = snapshot)
      when is_integer(project_id) and project_id > 0 do
    with {:ok, layers} <- snapshot_reference_collection(snapshot, "scene", "layers"),
         {:ok, layer_pins} <- layer_snapshot_variable_sources(layers, "pins", "scene_pin"),
         {:ok, layer_zones} <- layer_snapshot_variable_sources(layers, "zones", "scene_zone"),
         {:ok, orphan_pins} <- snapshot_reference_collection(snapshot, "scene", "orphan_pins"),
         {:ok, orphan_zones} <- snapshot_reference_collection(snapshot, "scene", "orphan_zones"),
         {:ok, ambient_flows} <- snapshot_reference_collection(snapshot, "scene", "ambient_flows") do
      sources =
        layer_pins ++
          layer_zones ++
          scene_snapshot_variable_sources(orphan_pins, "scene_pin") ++
          scene_snapshot_variable_sources(orphan_zones, "scene_zone") ++
          Enum.map(ambient_flows, &scene_ambient_snapshot_variable_source/1)

      validate_snapshot_variable_references(project_id, sources)
    end
  end

  def validate_entity_snapshot_variable_references(project_id, "sheet", %{})
      when is_integer(project_id) and project_id > 0, do: :ok

  def validate_entity_snapshot_variable_references(project_id, entity_type, snapshot) do
    {:error, {:invalid_variable_reference_entity_snapshot, project_id, entity_type, snapshot}}
  end

  # ---------------------------------------------------------------------------
  # Map zone variable references
  # ---------------------------------------------------------------------------

  @doc """
  Updates variable references for a map zone after its action_data changes.
  Extracts assignment write refs and display read refs.
  """
  @spec update_scene_zone_references(map(), keyword()) :: :ok | {:error, term()}
  def update_scene_zone_references(zone, opts \\ [])

  def update_scene_zone_references(%{id: zone_id, scene_id: scene_id} = zone, opts) do
    project_id = opts[:project_id] || VariableProjectionQueries.get_scene_project_id(scene_id)

    refs =
      if project_id do
        extract_zone_variable_refs(zone, project_id)
      else
        []
      end

    replace_references("scene_zone", zone_id, refs)
  end

  def update_scene_zone_references(_zone, _opts), do: :ok

  # ---------------------------------------------------------------------------
  # Map pin variable references
  # ---------------------------------------------------------------------------

  @doc """
  Updates variable references for a map pin after its action_data changes.
  Extracts assignment write refs and display read refs.
  """
  @spec update_scene_pin_references(map(), keyword()) :: :ok | {:error, term()}
  def update_scene_pin_references(pin, opts \\ [])

  def update_scene_pin_references(%{id: pin_id, scene_id: scene_id} = pin, opts) do
    project_id = opts[:project_id] || VariableProjectionQueries.get_scene_project_id(scene_id)

    refs =
      if project_id do
        extract_pin_variable_refs(pin, project_id)
      else
        []
      end

    replace_references("scene_pin", pin_id, refs)
  end

  def update_scene_pin_references(_pin, _opts), do: :ok

  @doc "Updates the read reference for an on-event Scene ambient-flow trigger."
  @spec update_scene_ambient_flow_references(map(), keyword()) :: :ok | {:error, term()}
  def update_scene_ambient_flow_references(ambient_flow, opts \\ [])

  def update_scene_ambient_flow_references(%{id: ambient_flow_id, scene_id: scene_id} = ambient_flow, opts) do
    project_id = opts[:project_id] || VariableProjectionQueries.get_scene_project_id(scene_id)

    refs =
      if project_id do
        extract_ambient_flow_variable_refs(ambient_flow, project_id)
      else
        []
      end

    replace_references("scene_ambient_flow", ambient_flow_id, refs)
  end

  def update_scene_ambient_flow_references(_ambient_flow, _opts), do: :ok

  @doc """
  Returns all variable references for a block, with source info.
  Includes Flow node, Scene zone/pin, and Scene ambient-flow sources.
  Used by the sheet editor's variable usage section.
  """
  @spec get_variable_usage(integer(), integer()) :: [map()]
  def get_variable_usage(block_id, project_id) do
    flow_refs = get_flow_node_variable_usage(block_id, project_id)
    zone_refs = get_scene_zone_variable_usage(block_id, project_id)
    pin_refs = get_scene_pin_variable_usage(block_id, project_id)
    ambient_flow_refs = get_scene_ambient_flow_variable_usage(block_id, project_id)
    flow_refs ++ zone_refs ++ pin_refs ++ ambient_flow_refs
  end

  defp get_flow_node_variable_usage(block_id, project_id) do
    Repo.all(
      from(vr in VariableReference,
        join: n in FlowNodeRecord,
        on: vr.source_type == "flow_node" and n.id == vr.source_id,
        join: f in FlowRecord,
        on: f.id == n.flow_id,
        where: vr.block_id == ^block_id,
        where: f.project_id == ^project_id,
        where: is_nil(f.deleted_at),
        where: is_nil(n.deleted_at),
        select: %{
          source_type: vr.source_type,
          kind: vr.kind,
          flow_id: f.id,
          flow_name: f.name,
          flow_shortcut: f.shortcut,
          node_id: n.id,
          node_type: n.type,
          node_data: n.data
        },
        order_by: [asc: vr.kind, asc: f.name]
      )
    )
  end

  defp get_scene_zone_variable_usage(block_id, project_id) do
    VariableProjectionQueries.get_scene_zone_variable_usage(block_id, project_id)
  end

  defp get_scene_pin_variable_usage(block_id, project_id) do
    VariableProjectionQueries.get_scene_pin_variable_usage(block_id, project_id)
  end

  defp get_scene_ambient_flow_variable_usage(block_id, project_id) do
    VariableProjectionQueries.get_scene_ambient_flow_variable_usage(block_id, project_id)
  end

  @doc """
  Counts variable references for a block, grouped by kind.
  Returns %{"read" => N, "write" => M}.
  """
  @spec count_variable_usage(integer()) :: map()
  def count_variable_usage(block_id) do
    from(vr in VariableReference,
      where: vr.block_id == ^block_id,
      group_by: vr.kind,
      select: {vr.kind, count(vr.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Returns a MapSet of block IDs that have at least one variable reference.
  Uses DISTINCT to avoid counting — just checks existence.
  """
  @spec referenced_block_ids([integer()]) :: MapSet.t()
  def referenced_block_ids([]), do: MapSet.new()

  def referenced_block_ids(block_ids) do
    from(vr in VariableReference,
      where: vr.block_id in ^block_ids,
      distinct: vr.block_id,
      select: vr.block_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc "Returns stale reference counts for many blocks in one grouped query."
  @spec count_stale_references([integer()], integer()) :: %{integer() => non_neg_integer()}
  def count_stale_references([], _project_id), do: %{}

  def count_stale_references(block_ids, project_id) do
    block_ids
    |> stale_reference_count_query(project_id)
    |> Repo.all()
    |> Map.new()
  end

  defp stale_reference_count_query(block_ids, project_id) do
    VariableReference
    |> join_stale_reference_sources()
    |> scope_stale_reference_sources(block_ids, project_id)
    |> filter_active_reference_sources(project_id)
    |> filter_stale_variable_references()
    |> group_stale_reference_counts()
  end

  defp join_stale_reference_sources(query) do
    from(reference in query,
      as: :reference,
      join: block in Block,
      as: :block,
      on: block.id == reference.block_id,
      join: sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id,
      left_join: node in FlowNodeRecord,
      as: :node,
      on: reference.source_type == "flow_node" and node.id == reference.source_id,
      left_join: flow in FlowRecord,
      as: :flow,
      on: flow.id == node.flow_id,
      left_join: zone in SceneZone,
      as: :zone,
      on: reference.source_type == "scene_zone" and zone.id == reference.source_id,
      left_join: zone_scene in Scene,
      as: :zone_scene,
      on: zone_scene.id == zone.scene_id,
      left_join: pin in ScenePin,
      as: :pin,
      on: reference.source_type == "scene_pin" and pin.id == reference.source_id,
      left_join: pin_scene in Scene,
      as: :pin_scene,
      on: pin_scene.id == pin.scene_id,
      left_join: ambient_flow in SceneAmbientFlow,
      as: :ambient_flow,
      on:
        reference.source_type == "scene_ambient_flow" and
          ambient_flow.id == reference.source_id,
      left_join: ambient_scene in Scene,
      as: :ambient_scene,
      on: ambient_scene.id == ambient_flow.scene_id
    )
  end

  defp scope_stale_reference_sources(query, block_ids, project_id) do
    from([reference: reference, block: block, sheet: sheet] in query,
      where:
        reference.block_id in ^block_ids and sheet.project_id == ^project_id and
          is_nil(sheet.deleted_at) and is_nil(block.deleted_at)
    )
  end

  defp filter_active_reference_sources(query, project_id) do
    from(
      [
        reference: reference,
        node: node,
        flow: flow,
        zone: zone,
        zone_scene: zone_scene,
        pin: pin,
        pin_scene: pin_scene,
        ambient_flow: ambient_flow,
        ambient_scene: ambient_scene
      ] in query,
      where:
        fragment(
          """
          (? = 'flow_node' AND ? IS NOT NULL AND ? IS NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_zone' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_pin' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          OR (? = 'scene_ambient_flow' AND ? IS NOT NULL AND ? = ? AND ? IS NULL)
          """,
          reference.source_type,
          node.id,
          node.deleted_at,
          flow.project_id,
          ^project_id,
          flow.deleted_at,
          reference.source_type,
          zone.id,
          zone_scene.project_id,
          ^project_id,
          zone_scene.deleted_at,
          reference.source_type,
          pin.id,
          pin_scene.project_id,
          ^project_id,
          pin_scene.deleted_at,
          reference.source_type,
          ambient_flow.id,
          ambient_scene.project_id,
          ^project_id,
          ambient_scene.deleted_at
        )
    )
  end

  defp filter_stale_variable_references(query) do
    from([reference: reference, block: block, sheet: sheet] in query,
      where:
        not VariableNamespaceResolver.authoritative_namespace_owner?(sheet) or
          fragment(
            """
            CASE WHEN ? = 'table' THEN
              ? != ? OR NOT EXISTS (
                SELECT 1 FROM table_rows tr
                JOIN table_columns tc ON tc.block_id = tr.block_id
                WHERE tr.block_id = ?
                  AND ? = ? || '.' || tr.slug || '.' || tc.slug
              )
            ELSE
              ? != ? OR ? != ?
            END
            """,
            block.type,
            reference.source_sheet,
            coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            block.id,
            reference.source_variable,
            block.variable_name,
            reference.source_sheet,
            coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
            reference.source_variable,
            block.variable_name
          )
    )
  end

  defp group_stale_reference_counts(query) do
    from([reference: reference] in query,
      group_by: reference.block_id,
      select: {reference.block_id, count(reference.id)}
    )
  end

  @doc """
  Returns variable usage for a block with stale detection.
  Each ref map gets an additional `:stale` boolean computed via SQL comparison
  of `source_sheet`/`source_variable` against the current sheet shortcut and
  block variable_name.

  Returns Flow-node, Scene-zone, Scene-pin, and Scene-ambient-flow sources.
  Each result includes a `:source_type` field to distinguish them.

  Filters out references whose sheet or block has been soft-deleted.
  """
  @spec check_stale_references(integer(), integer()) :: [map()]
  def check_stale_references(block_id, project_id) do
    flow_refs = check_stale_flow_node_references(block_id, project_id)
    zone_refs = check_stale_scene_zone_references(block_id, project_id)
    pin_refs = check_stale_scene_pin_references(block_id, project_id)
    ambient_flow_refs = check_stale_scene_ambient_flow_references(block_id, project_id)
    flow_refs ++ zone_refs ++ pin_refs ++ ambient_flow_refs
  end

  defp check_stale_flow_node_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_flow_node_variable_references(block_id, project_id)
  end

  defp check_stale_scene_zone_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_scene_zone_variable_references(block_id, project_id)
  end

  defp check_stale_scene_pin_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_scene_pin_variable_references(block_id, project_id)
  end

  defp check_stale_scene_ambient_flow_references(block_id, project_id) do
    VariableProjectionQueries.check_stale_scene_ambient_flow_variable_references(
      block_id,
      project_id
    )
  end

  @doc """
  Returns a MapSet of node IDs in a flow that have at least one stale reference.
  Uses pure SQL comparison — no JSON scanning in Elixir.
  """
  @spec list_stale_node_ids(integer()) :: MapSet.t()
  def list_stale_node_ids(flow_id) do
    regular_ids = list_stale_regular_node_ids(flow_id)
    table_ids = list_stale_table_node_ids(flow_id)
    MapSet.union(regular_ids, table_ids)
  end

  defp list_stale_regular_node_ids(flow_id) do
    VariableProjectionQueries.list_stale_regular_node_ids(flow_id)
  end

  defp list_stale_table_node_ids(flow_id) do
    VariableProjectionQueries.list_stale_table_node_ids(flow_id)
  end

  # -- Private --

  defp strict_flow_node_reference_specs(%FlowNodeRecord{id: source_id, type: type, data: data})
       when is_integer(source_id) and is_map(data) do
    case type do
      "instruction" ->
        strict_assignment_list_specs(
          "flow_node",
          source_id,
          Map.get(data, "assignments", [])
        )

      "condition" ->
        strict_condition_reference_specs(
          "flow_node",
          source_id,
          Map.get(data, "condition")
        )

      "dialogue" ->
        strict_dialogue_response_reference_specs(source_id, Map.get(data, "responses", []))

      _other ->
        {:ok, []}
    end
  end

  defp strict_flow_node_reference_specs(%{} = node) do
    source_id =
      Map.get(node, "original_id") || Map.get(node, :original_id) ||
        Map.get(node, "id") || Map.get(node, :id)

    type = Map.get(node, "type") || Map.get(node, :type)
    data = Map.get(node, "data") || Map.get(node, :data)

    if is_integer(source_id) and is_binary(type) and is_map(data) do
      strict_flow_node_reference_specs(%FlowNodeRecord{id: source_id, type: type, data: data})
    else
      {:error, {:invalid_variable_reference_source, "flow_node", source_id}}
    end
  end

  defp strict_flow_node_reference_specs(node), do: {:error, {:invalid_variable_reference_source, "flow_node", node}}

  defp strict_snapshot_source_reference_specs(%{} = source) do
    source_type = Map.get(source, :source_type) || Map.get(source, "source_type")
    source_id = Map.get(source, :source_id) || Map.get(source, "source_id")

    strict_snapshot_source_reference_specs(source, source_type, source_id)
  end

  defp strict_snapshot_source_reference_specs(source), do: {:error, {:invalid_variable_reference_source, :mixed, source}}

  defp strict_snapshot_source_reference_specs(source, "flow_node" = source_type, source_id) do
    node = %{
      "original_id" => source_id,
      "type" => Map.get(source, :type) || Map.get(source, "type"),
      "data" => Map.get(source, :data) || Map.get(source, "data")
    }

    tag_snapshot_reference_specs(strict_flow_node_reference_specs(node), source_type)
  end

  defp strict_snapshot_source_reference_specs(source, scene_type, source_id)
       when scene_type in ["scene_pin", "scene_zone"] do
    element = %{
      "original_id" => source_id,
      "action_type" => Map.get(source, :action_type) || Map.get(source, "action_type"),
      "action_data" => scene_element_action_data(source),
      "condition" => Map.get(source, :condition) || Map.get(source, "condition")
    }

    tag_snapshot_reference_specs(strict_scene_element_reference_specs(element, scene_type), scene_type)
  end

  defp strict_snapshot_source_reference_specs(source, "scene_ambient_flow" = source_type, source_id) do
    ambient_flow = %{
      "original_id" => source_id,
      "trigger_type" => Map.get(source, :trigger_type) || Map.get(source, "trigger_type"),
      "trigger_config" => Map.get(source, :trigger_config) || Map.get(source, "trigger_config") || %{}
    }

    tag_snapshot_reference_specs(strict_scene_ambient_flow_reference_specs(ambient_flow), source_type)
  end

  defp strict_snapshot_source_reference_specs(_source, invalid_type, source_id) do
    {:error, {:invalid_variable_reference_source_type, invalid_type, source_id}}
  end

  defp tag_snapshot_reference_specs({:ok, specs}, source_type), do: {:ok, source_type, specs}
  defp tag_snapshot_reference_specs({:error, _reason} = error, _source_type), do: error

  defp strict_dialogue_response_reference_specs(_source_id, []), do: {:ok, []}

  defp strict_dialogue_response_reference_specs(source_id, responses) when is_list(responses) do
    responses
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {response, index}, {:ok, specs} ->
      case strict_dialogue_response_reference_specs(source_id, response, index) do
        {:ok, response_specs} -> {:cont, {:ok, specs ++ response_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_dialogue_response_reference_specs(source_id, responses) do
    malformed_variable_reference("flow_node", source_id, :dialogue_responses, responses)
  end

  defp strict_dialogue_response_reference_specs(source_id, %{} = response, index) do
    with {:ok, condition_specs} <-
           strict_response_condition_specs(source_id, response["condition"], index),
         {:ok, assignment_specs} <- strict_response_assignment_specs(source_id, response, index) do
      {:ok, condition_specs ++ assignment_specs}
    end
  end

  defp strict_dialogue_response_reference_specs(source_id, response, index) do
    malformed_variable_reference("flow_node", source_id, {:dialogue_response, index}, response)
  end

  defp strict_response_condition_specs(_source_id, condition, _index) when condition in [nil, ""], do: {:ok, []}

  defp strict_response_condition_specs(source_id, %{} = condition, _index) do
    strict_condition_reference_specs("flow_node", source_id, condition)
  end

  defp strict_response_condition_specs(source_id, condition, index) when is_binary(condition) do
    case Jason.decode(condition) do
      {:ok, %{} = decoded} -> strict_condition_reference_specs("flow_node", source_id, decoded)
      _invalid -> malformed_variable_reference("flow_node", source_id, {:response_condition, index}, condition)
    end
  end

  defp strict_response_condition_specs(source_id, condition, index) do
    malformed_variable_reference("flow_node", source_id, {:response_condition, index}, condition)
  end

  defp strict_response_assignment_specs(source_id, response, index) do
    case Map.get(response, "instruction_assignments") do
      [_assignment | _rest] = assignments ->
        strict_assignment_list_specs("flow_node", source_id, assignments)

      assignments when assignments in [nil, []] ->
        strict_legacy_response_assignment_specs(source_id, response["instruction"], index)

      invalid ->
        malformed_variable_reference(
          "flow_node",
          source_id,
          {:response_instruction_assignments, index},
          invalid
        )
    end
  end

  defp strict_legacy_response_assignment_specs(_source_id, instruction, _index) when instruction in [nil, ""],
    do: {:ok, []}

  defp strict_legacy_response_assignment_specs(source_id, instruction, index) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) ->
        strict_assignment_list_specs("flow_node", source_id, assignments)

      _invalid ->
        malformed_variable_reference("flow_node", source_id, {:response_instruction, index}, instruction)
    end
  end

  defp strict_legacy_response_assignment_specs(source_id, instruction, index) do
    malformed_variable_reference("flow_node", source_id, {:response_instruction, index}, instruction)
  end

  defp strict_scene_ambient_flow_reference_specs(%{
         "original_id" => source_id,
         "trigger_type" => "on_event",
         "trigger_config" => %{} = config
       })
       when is_integer(source_id) do
    case config["variable_ref"] do
      value when value in [nil, ""] ->
        {:ok, []}

      value ->
        strict_qualified_variable_reference_specs(
          "scene_ambient_flow",
          source_id,
          value,
          :ambient_event_variable_ref
        )
    end
  end

  defp strict_scene_ambient_flow_reference_specs(%{"original_id" => source_id, "trigger_type" => trigger_type})
       when is_integer(source_id) and is_binary(trigger_type), do: {:ok, []}

  defp strict_scene_ambient_flow_reference_specs(ambient_flow) do
    source_id = if is_map(ambient_flow), do: ambient_flow["original_id"], else: ambient_flow
    {:error, {:invalid_variable_reference_source, "scene_ambient_flow", source_id}}
  end

  defp strict_scene_element_reference_specs(
         %{id: source_id, action_data: action_data, condition: condition} = element,
         source_type
       )
       when is_integer(source_id) and is_map(action_data) do
    with {:ok, action_specs} <- strict_scene_action_reference_specs(element, source_type),
         {:ok, condition_specs} <-
           strict_condition_reference_specs(
             source_type,
             source_id,
             condition
           ) do
      {:ok, action_specs ++ condition_specs}
    end
  end

  defp strict_scene_element_reference_specs(%{} = element, source_type) do
    source_id =
      Map.get(element, :id) || Map.get(element, "original_id") ||
        Map.get(element, :original_id) || Map.get(element, "id")

    action_data = scene_element_action_data(element)

    if is_integer(source_id) and is_map(action_data) do
      normalized = %{
        id: source_id,
        action_type: Map.get(element, :action_type) || Map.get(element, "action_type"),
        action_data: action_data,
        condition: Map.get(element, :condition) || Map.get(element, "condition")
      }

      strict_scene_element_reference_specs(normalized, source_type)
    else
      {:error, {:invalid_variable_reference_source, source_type, source_id}}
    end
  end

  defp strict_scene_element_reference_specs(element, source_type),
    do: {:error, {:invalid_variable_reference_source, source_type, element}}

  defp scene_element_action_data(element) do
    case Map.get(element, :action_data, Map.get(element, "action_data")) do
      nil -> %{}
      value -> value
    end
  end

  defp strict_scene_action_reference_specs(element, source_type) do
    case element.action_type do
      "action" ->
        strict_assignment_list_specs(
          source_type,
          element.id,
          Map.get(element.action_data, "assignments", [])
        )

      "display" ->
        strict_draftable_qualified_reference_specs(
          source_type,
          element.id,
          element.action_data["variable_ref"],
          :display_variable_ref
        )

      "collection" ->
        strict_collection_item_reference_specs(
          source_type,
          element.id,
          Map.get(element.action_data, "items")
        )

      _other ->
        {:ok, []}
    end
  end

  defp strict_collection_item_reference_specs(source_type, source_id, items) when is_list(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, specs} ->
      case strict_collection_item_reference_specs(source_type, source_id, item, index) do
        {:ok, item_specs} -> {:cont, {:ok, specs ++ item_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_collection_item_reference_specs(source_type, source_id, items) do
    malformed_variable_reference(source_type, source_id, :collection_items, items)
  end

  defp strict_collection_item_reference_specs(source_type, source_id, %{} = item, index) do
    with {:ok, condition_specs} <-
           strict_collection_item_condition_specs(
             source_type,
             source_id,
             Map.get(item, "condition"),
             index
           ),
         {:ok, instruction_specs} <-
           strict_collection_item_instruction_specs(
             source_type,
             source_id,
             Map.get(item, "instruction"),
             index
           ) do
      {:ok, condition_specs ++ instruction_specs}
    end
  end

  defp strict_collection_item_reference_specs(source_type, source_id, item, index) do
    malformed_variable_reference(source_type, source_id, {:collection_item, index}, item)
  end

  defp strict_collection_item_condition_specs(_source_type, _source_id, nil, _index), do: {:ok, []}

  defp strict_collection_item_condition_specs(_source_type, _source_id, condition, _index)
       when is_map(condition) and map_size(condition) == 0, do: {:ok, []}

  defp strict_collection_item_condition_specs(source_type, source_id, condition, index) do
    case strict_condition_reference_specs(source_type, source_id, condition) do
      {:error, {:malformed_variable_reference, ^source_type, ^source_id, :condition, _value}} ->
        malformed_variable_reference(
          source_type,
          source_id,
          {:collection_item_condition, index},
          condition
        )

      result ->
        result
    end
  end

  defp strict_collection_item_instruction_specs(_source_type, _source_id, nil, _index), do: {:ok, []}

  defp strict_collection_item_instruction_specs(source_type, source_id, %{} = instruction, index) do
    case strict_assignment_list_specs(
           source_type,
           source_id,
           Map.get(instruction, "assignments", [])
         ) do
      {:error, {:malformed_variable_reference, ^source_type, ^source_id, :assignments, _value}} ->
        malformed_variable_reference(
          source_type,
          source_id,
          {:collection_item_assignments, index},
          Map.get(instruction, "assignments")
        )

      result ->
        result
    end
  end

  defp strict_collection_item_instruction_specs(source_type, source_id, instruction, index) do
    malformed_variable_reference(
      source_type,
      source_id,
      {:collection_item_instruction, index},
      instruction
    )
  end

  defp strict_assignment_list_specs(_source_type, _source_id, []), do: {:ok, []}

  defp strict_assignment_list_specs(source_type, source_id, assignments) when is_list(assignments) do
    Enum.reduce_while(assignments, {:ok, []}, fn assignment, {:ok, specs} ->
      case strict_assignment_reference_specs(
             source_type,
             source_id,
             assignment
           ) do
        {:ok, assignment_specs} -> {:cont, {:ok, specs ++ assignment_specs}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp strict_assignment_list_specs(source_type, source_id, assignments) do
    malformed_variable_reference(source_type, source_id, :assignments, assignments)
  end

  defp strict_assignment_reference_specs(source_type, source_id, %{} = assignment) do
    with {:ok, write_specs} <-
           strict_draftable_reference_specs(
             source_type,
             source_id,
             "write",
             assignment["sheet"],
             assignment["variable"],
             :assignment_target
           ),
         {:ok, read_specs} <-
           strict_assignment_read_specs(source_type, source_id, assignment) do
      {:ok, write_specs ++ read_specs}
    end
  end

  defp strict_assignment_reference_specs(source_type, source_id, assignment) do
    malformed_variable_reference(source_type, source_id, :assignment, assignment)
  end

  defp strict_assignment_read_specs(source_type, source_id, %{"value_type" => "variable_ref"} = assignment) do
    strict_draftable_reference_specs(
      source_type,
      source_id,
      "read",
      assignment["value_sheet"],
      assignment["value"],
      :assignment_value
    )
  end

  defp strict_assignment_read_specs(_source_type, _source_id, _assignment), do: {:ok, []}

  defp strict_condition_reference_specs(_source_type, _source_id, nil), do: {:ok, []}

  defp strict_condition_reference_specs(source_type, source_id, %{} = condition) do
    case FlowCondition.validate(condition) do
      {:ok, valid_condition} ->
        valid_condition
        |> FlowCondition.extract_all_rules()
        |> strict_condition_rule_specs(source_type, source_id)

      {:error, _reason} ->
        malformed_variable_reference(source_type, source_id, :condition, condition)
    end
  end

  defp strict_condition_reference_specs(source_type, source_id, condition) do
    malformed_variable_reference(source_type, source_id, :condition, condition)
  end

  defp strict_condition_rule_specs(rules, source_type, source_id) do
    Enum.reduce_while(rules, {:ok, []}, fn rule, {:ok, specs} ->
      strict_condition_rule_spec(rule, specs, source_type, source_id)
    end)
  end

  defp strict_condition_rule_spec(rule, specs, source_type, source_id) do
    case strict_draftable_reference_specs(
           source_type,
           source_id,
           "read",
           rule["sheet"],
           rule["variable"],
           :condition_rule
         ) do
      {:ok, rule_specs} -> {:cont, {:ok, rule_specs ++ specs}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp strict_draftable_reference_specs(source_type, source_id, kind, sheet_shortcut, variable_name, context) do
    cond do
      nonempty_reference_part?(sheet_shortcut) and nonempty_reference_part?(variable_name) ->
        case strict_required_reference_spec(
               source_type,
               source_id,
               kind,
               sheet_shortcut,
               variable_name,
               context
             ) do
          {:ok, spec} -> {:ok, [spec]}
          {:error, _reason} = error -> error
        end

      draft_reference_pair?(sheet_shortcut, variable_name) ->
        {:ok, []}

      true ->
        malformed_variable_reference(
          source_type,
          source_id,
          context,
          {sheet_shortcut, variable_name}
        )
    end
  end

  defp nonempty_reference_part?(value), do: is_binary(value) and String.trim(value) != ""

  defp draft_reference_pair?(sheet_shortcut, variable_name) do
    (sheet_shortcut in [nil, ""] and variable_name in [nil, ""]) or
      (nonempty_reference_part?(sheet_shortcut) and variable_name in [nil, ""])
  end

  defp strict_required_reference_spec(source_type, source_id, kind, sheet_shortcut, variable_name, context) do
    case reference_specs(source_id, kind, sheet_shortcut, variable_name) do
      [spec] -> {:ok, spec}
      [] -> malformed_variable_reference(source_type, source_id, context, {sheet_shortcut, variable_name})
    end
  end

  defp strict_qualified_variable_reference_specs(source_type, source_id, value, context) when is_binary(value) do
    case qualified_reference_specs(source_id, "read", value) do
      [spec] -> {:ok, [spec]}
      [] -> malformed_variable_reference(source_type, source_id, context, value)
    end
  end

  defp strict_qualified_variable_reference_specs(source_type, source_id, value, context) do
    malformed_variable_reference(source_type, source_id, context, value)
  end

  defp strict_draftable_qualified_reference_specs(_source_type, _source_id, value, _context) when value in [nil, ""],
    do: {:ok, []}

  defp strict_draftable_qualified_reference_specs(source_type, source_id, value, context),
    do: strict_qualified_variable_reference_specs(source_type, source_id, value, context)

  defp snapshot_reference_collection(snapshot, entity_type, key) do
    case Map.fetch(snapshot, key) do
      {:ok, values} when is_list(values) ->
        if Enum.all?(values, &is_map/1) do
          {:ok, values}
        else
          {:error, {:invalid_variable_reference_snapshot_collection, entity_type, key, values}}
        end

      {:ok, value} ->
        {:error, {:invalid_variable_reference_snapshot_collection, entity_type, key, value}}

      :error ->
        {:error, {:missing_variable_reference_snapshot_collection, entity_type, key}}
    end
  end

  defp layer_snapshot_variable_sources(layers, child_key, source_type) do
    Enum.reduce_while(layers, {:ok, []}, fn layer, {:ok, sources} ->
      case snapshot_reference_collection(layer, "scene_layer", child_key) do
        {:ok, children} ->
          child_sources = scene_snapshot_variable_sources(children, source_type)
          {:cont, {:ok, sources ++ child_sources}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp scene_snapshot_variable_sources(elements, source_type) when is_list(elements) do
    Enum.map(elements, &scene_snapshot_variable_source(source_type, &1))
  end

  defp flow_snapshot_variable_source(node) do
    %{
      source_type: "flow_node",
      source_id: node["original_id"],
      type: node["type"],
      data: node["data"]
    }
  end

  defp scene_snapshot_variable_source(source_type, element) do
    %{
      source_type: source_type,
      source_id: element["original_id"],
      action_type: element["action_type"],
      action_data: element["action_data"],
      condition: element["condition"]
    }
  end

  defp scene_ambient_snapshot_variable_source(ambient_flow) do
    %{
      source_type: "scene_ambient_flow",
      source_id: ambient_flow["original_id"],
      trigger_type: ambient_flow["trigger_type"],
      trigger_config: ambient_flow["trigger_config"]
    }
  end

  defp malformed_variable_reference(source_type, source_id, context, value) do
    {:error, {:malformed_variable_reference, source_type, source_id, context, value}}
  end

  defp validate_resolvable_specs(_project_id, _source_type, []), do: :ok

  defp validate_resolvable_specs(project_id, source_type, specs) do
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)

    case Enum.find(specs, &(not Map.has_key?(resolved_block_ids, &1.resolution_key))) do
      nil ->
        :ok

      spec ->
        source_type = Map.get(spec, :source_type, source_type)

        {:error,
         {:unresolved_variable_reference, source_type, spec.source_id, spec.kind, spec.source_sheet, spec.source_variable}}
    end
  end

  defp flow_node_reference_specs(%{id: node_id, type: "instruction", data: data}) do
    data
    |> Map.get("assignments", [])
    |> list_value()
    |> Enum.flat_map(&assignment_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%{id: node_id, type: "condition", data: data}) do
    data
    |> Map.get("condition")
    |> FlowCondition.extract_all_rules()
    |> Enum.flat_map(&condition_rule_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%{id: node_id, type: "dialogue", data: data}) do
    data
    |> Map.get("responses", [])
    |> list_value()
    |> Enum.flat_map(&dialogue_response_reference_specs(node_id, &1))
  end

  defp flow_node_reference_specs(%{id: _node_id, type: _type, data: _data}), do: []

  defp dialogue_response_reference_specs(node_id, %{} = response) do
    response_condition_reference_specs(node_id, response["condition"]) ++
      response_assignment_reference_specs(node_id, response)
  end

  defp dialogue_response_reference_specs(_node_id, _response), do: []

  defp response_condition_reference_specs(node_id, condition) when is_binary(condition) do
    condition
    |> FlowCondition.parse()
    |> condition_reference_specs(node_id)
  end

  defp response_condition_reference_specs(node_id, condition), do: condition_reference_specs(condition, node_id)

  defp condition_reference_specs(condition, node_id) do
    condition
    |> FlowCondition.extract_all_rules()
    |> Enum.flat_map(&condition_rule_reference_specs(node_id, &1))
  end

  defp condition_rule_reference_specs(node_id, %{} = rule) do
    reference_specs(node_id, "read", rule["sheet"], rule["variable"])
  end

  defp condition_rule_reference_specs(_node_id, _rule), do: []

  defp response_assignment_reference_specs(node_id, response) do
    response
    |> response_assignments()
    |> list_value()
    |> Enum.flat_map(&assignment_reference_specs(node_id, &1))
  end

  defp response_assignments(%{"instruction_assignments" => [_assignment | _rest] = assignments}), do: assignments
  defp response_assignments(%{"instruction_assignments" => invalid}) when invalid not in [nil, []], do: invalid
  defp response_assignments(response), do: decode_legacy_response_assignments(response["instruction"])

  defp decode_legacy_response_assignments(instruction) when instruction in [nil, ""], do: []

  defp decode_legacy_response_assignments(instruction) when is_binary(instruction) do
    case Jason.decode(instruction) do
      {:ok, assignments} when is_list(assignments) -> assignments
      _invalid -> []
    end
  end

  defp decode_legacy_response_assignments(_instruction), do: []

  defp assignment_reference_specs(node_id, assignment) when is_map(assignment) do
    write_specs =
      reference_specs(
        node_id,
        "write",
        assignment["sheet"],
        assignment["variable"]
      )

    read_specs =
      if assignment["value_type"] == "variable_ref" do
        reference_specs(
          node_id,
          "read",
          assignment["value_sheet"],
          assignment["value"]
        )
      else
        []
      end

    write_specs ++ read_specs
  end

  defp assignment_reference_specs(_node_id, _assignment), do: []

  defp reference_specs(node_id, kind, sheet_shortcut, variable_name)
       when is_binary(sheet_shortcut) and sheet_shortcut != "" and is_binary(variable_name) and variable_name != "" do
    [
      %{
        source_id: node_id,
        kind: kind,
        source_sheet: sheet_shortcut,
        source_variable: variable_name,
        resolution_key: variable_resolution_key(sheet_shortcut, variable_name)
      }
    ]
  end

  defp reference_specs(_node_id, _kind, _sheet_shortcut, _variable_name), do: []

  defp qualified_reference_specs(source_id, kind, qualified_ref) when is_binary(qualified_ref) and qualified_ref != "" do
    if String.trim(qualified_ref) == "" do
      []
    else
      {source_sheet, source_variable} = qualified_reference_error_parts(qualified_ref)

      [
        %{
          source_id: source_id,
          kind: kind,
          source_sheet: source_sheet,
          source_variable: source_variable,
          resolution_key: {:qualified, qualified_ref}
        }
      ]
    end
  end

  defp qualified_reference_specs(_source_id, _kind, _qualified_ref), do: []

  defp qualified_reference_error_parts(qualified_ref) do
    parts = String.split(qualified_ref, ".")

    case List.pop_at(parts, -1) do
      {variable_name, sheet_parts} when sheet_parts != [] -> {Enum.join(sheet_parts, "."), variable_name}
      _invalid -> {qualified_ref, qualified_ref}
    end
  end

  defp variable_resolution_key(sheet_shortcut, variable_name) do
    case String.split(variable_name, ".", parts: 3) do
      [table_name, row_slug, column_slug] ->
        {:table, sheet_shortcut, table_name, row_slug, column_slug}

      _regular_variable ->
        {:regular, sheet_shortcut, variable_name}
    end
  end

  defp resolve_reference_block_ids(project_id, specs) do
    resolution_keys = MapSet.new(specs, & &1.resolution_key)

    regular_keys =
      for {:regular, _sheet, _variable} = key <- resolution_keys,
          do: key

    table_keys =
      for {:table, _sheet, _table, _row, _column} = key <-
            resolution_keys,
          do: key

    qualified_refs =
      for {:qualified, qualified_ref} <- resolution_keys,
          do: qualified_ref

    project_id
    |> resolve_regular_block_ids(regular_keys)
    |> Map.merge(resolve_table_block_ids(project_id, table_keys))
    |> Map.merge(resolve_qualified_reference_definitions(project_id, qualified_refs))
  end

  defp resolve_qualified_reference_definitions(_project_id, []), do: %{}

  defp resolve_qualified_reference_definitions(project_id, qualified_refs) do
    definitions =
      qualified_regular_reference_definitions(project_id, qualified_refs) ++
        qualified_table_reference_definitions(project_id, qualified_refs)

    Map.new(definitions, fn {qualified_ref, source_sheet, source_variable, block_id} ->
      {{:qualified, qualified_ref}, %{block_id: block_id, source_sheet: source_sheet, source_variable: source_variable}}
    end)
  end

  defp qualified_regular_reference_definitions(project_id, qualified_refs) do
    Repo.all(
      from(block in Block,
        join: sheet in Sheet,
        on: sheet.id == block.sheet_id,
        where:
          sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
            is_nil(block.deleted_at) and
            block.type in ^@regular_variable_types and
            block.is_constant == false and
            not is_nil(block.variable_name) and block.variable_name != "" and
            VariableNamespaceResolver.authoritative_namespace_owner?(sheet) and
            fragment(
              "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
              sheet.shortcut,
              sheet.id,
              block.variable_name
            ) in ^qualified_refs,
        select: {
          fragment(
            "COALESCE(?, CAST(? AS TEXT)) || '.' || ?",
            sheet.shortcut,
            sheet.id,
            block.variable_name
          ),
          coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
          block.variable_name,
          block.id
        }
      )
    )
  end

  defp qualified_table_reference_definitions(project_id, qualified_refs) do
    from(column in TableColumn, as: :column)
    |> join(:inner, [column: column], block in Block,
      as: :block,
      on: block.id == column.block_id
    )
    |> join(:inner, [block: block], sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRow,
      as: :row,
      on: row.block_id == block.id
    )
    |> where(
      [column: column, block: block, sheet: sheet, row: row],
      sheet.project_id == ^project_id and is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at) and not is_nil(block.variable_name) and
        block.variable_name != "" and
        VariableNamespaceResolver.authoritative_namespace_owner?(sheet) and
        fragment(
          "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
          sheet.shortcut,
          sheet.id,
          block.variable_name,
          row.slug,
          column.slug
        ) in ^qualified_refs
    )
    |> filter_table_variable_targets()
    |> select([column: column, block: block, sheet: sheet, row: row], {
      fragment(
        "COALESCE(?, CAST(? AS TEXT)) || '.' || ? || '.' || ? || '.' || ?",
        sheet.shortcut,
        sheet.id,
        block.variable_name,
        row.slug,
        column.slug
      ),
      coalesce(sheet.shortcut, fragment("CAST(? AS TEXT)", sheet.id)),
      fragment("? || '.' || ? || '.' || ?", block.variable_name, row.slug, column.slug),
      block.id
    })
    |> Repo.all()
  end

  defp filter_table_variable_targets(query) do
    from([column: column, block: block] in query,
      where:
        block.type == "table" and
          column.type in ^@table_variable_types and
          (column.is_constant == false or
             column.type in ^@constant_table_variable_types)
    )
  end

  defp resolve_regular_block_ids(_project_id, []), do: %{}

  defp resolve_regular_block_ids(project_id, keys) do
    namespaces =
      keys
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()

    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)

    variable_names =
      keys
      |> Enum.map(&elem(&1, 2))
      |> Enum.uniq()

    from(block in Block,
      join: sheet in Sheet,
      on: sheet.id == block.sheet_id,
      where:
        sheet.project_id == ^project_id and
          sheet.id in ^sheet_ids and
          block.variable_name in ^variable_names and
          block.type in ^@regular_variable_types and
          block.is_constant == false and
          is_nil(sheet.deleted_at) and
          is_nil(block.deleted_at),
      select: {sheet.id, block.variable_name, block.id}
    )
    |> Repo.all()
    |> Map.new(fn {sheet_id, variable_name, block_id} ->
      {{:regular, Map.fetch!(namespace_by_id, sheet_id), variable_name}, block_id}
    end)
  end

  defp resolve_table_block_ids(_project_id, []), do: %{}

  defp resolve_table_block_ids(project_id, keys) do
    namespaces = keys |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    namespace_ids = VariableNamespaceResolver.resolve_sheet_ids(project_id, namespaces)
    namespace_by_id = Map.new(namespace_ids, fn {namespace, id} -> {id, namespace} end)
    sheet_ids = Map.keys(namespace_by_id)
    table_names = keys |> Enum.map(&elem(&1, 2)) |> Enum.uniq()
    row_slugs = keys |> Enum.map(&elem(&1, 3)) |> Enum.uniq()
    column_slugs = keys |> Enum.map(&elem(&1, 4)) |> Enum.uniq()

    from(block in Block, as: :block)
    |> join(:inner, [block: block], sheet in Sheet,
      as: :sheet,
      on: sheet.id == block.sheet_id
    )
    |> join(:inner, [block: block], row in TableRow,
      as: :row,
      on: row.block_id == block.id
    )
    |> join(:inner, [block: block], column in TableColumn,
      as: :column,
      on: column.block_id == block.id
    )
    |> where(
      [block: block, sheet: sheet, row: row, column: column],
      sheet.project_id == ^project_id and
        sheet.id in ^sheet_ids and
        block.variable_name in ^table_names and
        row.slug in ^row_slugs and
        column.slug in ^column_slugs and
        is_nil(sheet.deleted_at) and
        is_nil(block.deleted_at)
    )
    |> filter_table_variable_targets()
    |> select([block: block, sheet: sheet, row: row, column: column], {
      sheet.id,
      block.variable_name,
      row.slug,
      column.slug,
      block.id
    })
    |> Repo.all()
    |> Map.new(fn {sheet_id, table_name, row_slug, column_slug, block_id} ->
      namespace = Map.fetch!(namespace_by_id, sheet_id)
      {{:table, namespace, table_name, row_slug, column_slug}, block_id}
    end)
  end

  defp expected_flow_node_reference_sets(specs, resolved_block_ids) do
    specs
    |> Enum.group_by(& &1.source_id)
    |> Map.new(fn {source_id, source_specs} ->
      references =
        source_specs
        |> Enum.flat_map(&resolved_flow_node_reference(&1, resolved_block_ids))
        |> Enum.uniq_by(fn reference ->
          {
            reference.block_id,
            reference.kind,
            reference.source_variable
          }
        end)
        |> MapSet.new(fn reference ->
          {
            reference.block_id,
            reference.kind,
            reference.source_sheet,
            reference.source_variable,
            source_id
          }
        end)

      {source_id, references}
    end)
  end

  defp resolved_flow_node_reference(spec, resolved_block_ids) do
    case Map.fetch(resolved_block_ids, spec.resolution_key) do
      {:ok, %{block_id: block_id, source_sheet: source_sheet, source_variable: source_variable}} ->
        [
          %{
            block_id: block_id,
            kind: spec.kind,
            source_sheet: source_sheet,
            source_variable: source_variable
          }
        ]

      {:ok, block_id} ->
        [
          %{
            block_id: block_id,
            kind: spec.kind,
            source_sheet: spec.source_sheet,
            source_variable: spec.source_variable
          }
        ]

      :error ->
        []
    end
  end

  defp extract_flow_node_variable_refs(%{flow_id: flow_id} = node) do
    case get_project_id(flow_id) do
      nil ->
        []

      project_id ->
        specs = flow_node_reference_specs(node)
        resolved_block_ids = resolve_reference_block_ids(project_id, specs)
        Enum.flat_map(specs, &resolved_flow_node_reference(&1, resolved_block_ids))
    end
  end

  defp actual_flow_node_reference_sets([]), do: %{}

  defp actual_flow_node_reference_sets(node_ids) do
    from(reference in VariableReference,
      where:
        reference.source_type == "flow_node" and
          reference.source_id in ^node_ids,
      select: {
        reference.source_id,
        reference.block_id,
        reference.kind,
        reference.source_sheet,
        reference.source_variable,
        reference.flow_node_id
      }
    )
    |> Repo.all()
    |> Enum.reduce(
      %{},
      fn
        {
          source_id,
          block_id,
          kind,
          source_sheet,
          source_variable,
          flow_node_id
        },
        references ->
          reference =
            {
              block_id,
              kind,
              source_sheet,
              source_variable,
              flow_node_id
            }

          Map.update(
            references,
            source_id,
            MapSet.new([reference]),
            &MapSet.put(&1, reference)
          )
      end
    )
  end

  defp list_value(value) when is_list(value), do: value
  defp list_value(_value), do: []

  defp get_project_id(flow_id) do
    Repo.one(from(f in FlowRecord, where: f.id == ^flow_id, select: f.project_id))
  end

  defp extract_zone_variable_refs(zone, project_id), do: extract_scene_element_variable_refs(zone, project_id)

  defp extract_pin_variable_refs(pin, project_id), do: extract_scene_element_variable_refs(pin, project_id)

  defp extract_ambient_flow_variable_refs(
         %{trigger_type: "on_event", trigger_config: %{"variable_ref" => variable_ref}},
         project_id
       ) do
    resolve_display_variable_ref(project_id, variable_ref)
  end

  defp extract_ambient_flow_variable_refs(_ambient_flow, _project_id), do: []

  defp extract_scene_element_variable_refs(element, project_id) do
    specs = scene_element_reference_specs(element)
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)
    Enum.flat_map(specs, &resolved_flow_node_reference(&1, resolved_block_ids))
  end

  defp scene_element_reference_specs(element) do
    source_id = Map.get(element, :id)

    scene_action_reference_specs(element, source_id) ++
      condition_reference_specs(Map.get(element, :condition), source_id)
  end

  # Shared extraction for action_type + action_data (zones and pins)
  defp scene_action_reference_specs(element, source_id) do
    action_data = scene_element_action_data(element)

    case Map.get(element, :action_type) do
      "action" ->
        action_data
        |> Map.get("assignments", [])
        |> list_value()
        |> Enum.flat_map(&assignment_reference_specs(source_id, &1))

      "display" ->
        qualified_reference_specs(source_id, "read", Map.get(action_data, "variable_ref"))

      "collection" ->
        action_data
        |> Map.get("items", [])
        |> list_value()
        |> Enum.flat_map(&collection_item_reference_specs(source_id, &1))

      _ ->
        []
    end
  end

  defp collection_item_reference_specs(source_id, %{} = item) do
    condition_specs = condition_reference_specs(Map.get(item, "condition"), source_id)

    assignment_specs =
      item
      |> Map.get("instruction")
      |> collection_instruction_assignments()
      |> Enum.flat_map(&assignment_reference_specs(source_id, &1))

    condition_specs ++ assignment_specs
  end

  defp collection_item_reference_specs(_source_id, _item), do: []

  defp collection_instruction_assignments(%{} = instruction) do
    instruction
    |> Map.get("assignments", [])
    |> list_value()
  end

  defp collection_instruction_assignments(_instruction), do: []

  defp resolve_display_variable_ref(_project_id, nil), do: []
  defp resolve_display_variable_ref(_project_id, ""), do: []

  defp resolve_display_variable_ref(project_id, variable_ref) when is_binary(variable_ref) do
    specs = qualified_reference_specs(0, "read", variable_ref)
    resolved_block_ids = resolve_reference_block_ids(project_id, specs)
    Enum.flat_map(specs, &resolved_flow_node_reference(&1, resolved_block_ids))
  end

  defp resolve_display_variable_ref(_project_id, _variable_ref), do: []

  defp replace_references(source_type, source_id, refs, opts \\ []) do
    result =
      Repo.transaction(fn ->
        Repo.delete_all(
          from(vr in VariableReference,
            where: vr.source_type == ^source_type and vr.source_id == ^source_id
          )
        )

        unique_refs = Enum.uniq_by(refs, fn ref -> {ref.block_id, ref.kind, ref.source_variable} end)
        now = TimeHelpers.now()

        entries =
          Enum.map(unique_refs, fn ref ->
            %{
              source_type: source_type,
              source_id: source_id,
              flow_node_id: Keyword.get(opts, :flow_node_id),
              block_id: ref.block_id,
              kind: ref.kind,
              source_sheet: ref.source_sheet,
              source_variable: ref.source_variable,
              inserted_at: now,
              updated_at: now
            }
          end)

        insert_reference_entries(entries)
      end)

    case result do
      {:ok, :ok} ->
        :ok

      {:error, reason} ->
        {:error, {:variable_reference_write_failed, source_type, source_id, reason}}
    end
  end

  defp restore_missing_flow_node_references(%FlowNodeRecord{} = node) do
    refs = extract_flow_node_variable_refs(node)

    insert_missing_references("flow_node", node.id, refs, flow_node_id: node.id)
  end

  defp restore_missing_scene_pin_references(pin, project_id) do
    insert_missing_references(
      "scene_pin",
      pin.id,
      extract_pin_variable_refs(pin, project_id)
    )
  end

  defp restore_missing_scene_zone_references(zone, project_id) do
    insert_missing_references(
      "scene_zone",
      zone.id,
      extract_zone_variable_refs(zone, project_id)
    )
  end

  defp restore_missing_scene_ambient_flow_references(ambient_flow, project_id) do
    insert_missing_references(
      "scene_ambient_flow",
      ambient_flow.id,
      extract_ambient_flow_variable_refs(ambient_flow, project_id)
    )
  end

  defp insert_missing_references(source_type, source_id, refs, opts \\ []) do
    entries = reference_entries(source_type, source_id, refs, opts)

    case Repo.insert_all(VariableReference, entries, on_conflict: :nothing) do
      {count, _} when count >= 0 and count <= length(entries) ->
        :ok

      result ->
        {:error, {:variable_reference_additive_insert_count_mismatch, source_type, source_id, length(entries), result}}
    end
  end

  defp reference_entries(source_type, source_id, refs, opts) do
    now = TimeHelpers.now()

    refs
    |> Enum.uniq_by(fn ref -> {ref.block_id, ref.kind, ref.source_variable} end)
    |> Enum.map(fn ref ->
      %{
        source_type: source_type,
        source_id: source_id,
        flow_node_id: Keyword.get(opts, :flow_node_id),
        block_id: ref.block_id,
        kind: ref.kind,
        source_sheet: ref.source_sheet,
        source_variable: ref.source_variable,
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  defp insert_reference_entries([]), do: :ok

  defp insert_reference_entries(entries) do
    case Repo.insert_all(VariableReference, entries, on_conflict: :nothing) do
      {count, _} when count == length(entries) ->
        :ok

      result ->
        Repo.rollback({:variable_reference_insert_count_mismatch, length(entries), result})
    end
  end

  defp active_flow_nodes_query(project_id) do
    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at)
    )
  end

  defp active_scene_pins_query(project_id) do
    from(pin in ScenePin,
      join: scene in Scene,
      on: scene.id == pin.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp active_scene_zones_query(project_id) do
    from(zone in SceneZone,
      join: scene in Scene,
      on: scene.id == zone.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp active_scene_ambient_flows_query(project_id) do
    from(ambient_flow in SceneAmbientFlow,
      join: scene in Scene,
      on: scene.id == ambient_flow.scene_id,
      where: scene.project_id == ^project_id and is_nil(scene.deleted_at)
    )
  end

  defp rebuild_sources(query, project_id, source_type, update_fun, after_id \\ 0) do
    sources =
      Repo.all(
        from(source in query,
          where: source.id > ^after_id,
          order_by: [asc: source.id],
          limit: ^@rebuild_batch_size
        )
      )

    case rebuild_source_batch(sources, project_id, source_type, update_fun) do
      :ok when length(sources) == @rebuild_batch_size ->
        rebuild_sources(query, project_id, source_type, update_fun, List.last(sources).id)

      result ->
        result
    end
  end

  defp rebuild_source_batch(sources, project_id, source_type, update_fun) do
    Enum.reduce_while(sources, :ok, fn source, :ok ->
      case update_fun.(source) do
        :ok ->
          {:cont, :ok}

        {:error, reason} ->
          {:halt,
           {:error,
            {:project_variable_reference_rebuild_failed,
             %{
               project_id: project_id,
               source_type: source_type,
               source_id: source.id,
               reason: reason
             }}}}

        result ->
          {:halt,
           {:error,
            {:project_variable_reference_rebuild_failed,
             %{
               project_id: project_id,
               source_type: source_type,
               source_id: source.id,
               reason: {:unexpected_result, result}
             }}}}
      end
    end)
  end
end
