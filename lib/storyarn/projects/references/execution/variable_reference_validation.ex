defmodule Storyarn.Projects.References.VariableReferenceValidation do
  @moduledoc """
  Validates normalized Flow and Scene variable references against the active
  Project-owned Sheet projection.

  Pure source parsing lives in `VariableReferenceExtraction`; this module owns
  the read-side resolution needed by restore and projection consistency checks.
  """

  alias Storyarn.Projects.References.VariableReferenceExtraction
  alias Storyarn.Projects.References.VariableReferenceResolutionQueries

  @doc false
  @spec flow_node_references_current_ids([map()], integer()) :: MapSet.t(integer())
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
    specs = Enum.flat_map(valid_nodes, &VariableReferenceExtraction.flow_node_specs/1)

    resolved_block_ids =
      VariableReferenceResolutionQueries.resolve_reference_block_ids(project_id, specs)

    expected_by_node =
      VariableReferenceExtraction.expected_flow_node_reference_sets(specs, resolved_block_ids)

    actual_by_node =
      VariableReferenceResolutionQueries.actual_flow_node_reference_sets(node_ids)

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

  This accepts both persisted Flow-node structs and snapshot maps. It is
  intentionally stricter than the additive reference rebuild: an in-place
  historical restore must fail closed instead of persisting a reference that
  cannot be represented by the projection.
  """
  @spec validate_flow_node_variable_targets([map() | struct()], integer()) ::
          :ok | {:error, term()}
  def validate_flow_node_variable_targets(nodes, project_id)
      when is_list(nodes) and is_integer(project_id) and project_id > 0 do
    nodes
    |> Enum.reduce_while({:ok, []}, fn node, {:ok, specs} ->
      case VariableReferenceExtraction.strict_flow_node_specs(node) do
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
  persisted structs or snapshot maps with string keys.
  """
  @spec validate_scene_element_variable_targets([map()], integer(), String.t()) ::
          :ok | {:error, term()}
  def validate_scene_element_variable_targets(elements, project_id, source_type)
      when is_list(elements) and is_integer(project_id) and project_id > 0 and source_type in ["scene_pin", "scene_zone"] do
    elements
    |> Enum.reduce_while({:ok, []}, fn element, {:ok, specs} ->
      case VariableReferenceExtraction.strict_scene_element_specs(element, source_type) do
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

  Each source declares its type and identity plus the Flow or Scene payload
  from which strict reference specs are extracted.
  """
  @spec validate_snapshot_variable_references(integer(), [map()]) ::
          :ok | {:error, term()}
  def validate_snapshot_variable_references(project_id, sources)
      when is_integer(project_id) and project_id > 0 and is_list(sources) do
    sources
    |> Enum.reduce_while({:ok, []}, fn source, {:ok, specs} ->
      case VariableReferenceExtraction.strict_snapshot_source_specs(source) do
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

  @doc """
  Extracts and validates every variable-reference surface from an entity
  snapshot.

  Flow snapshots contribute nodes; Scene snapshots contribute pins, zones and
  ambient flows; Sheet snapshots have no variable-reference surfaces of their
  own.
  """
  @spec validate_entity_snapshot_variable_references(integer(), String.t(), map()) ::
          :ok | {:error, term()}
  def validate_entity_snapshot_variable_references(project_id, entity_type, %{} = snapshot)
      when is_integer(project_id) and project_id > 0 and entity_type in ["flow", "scene", "sheet"] do
    with {:ok, sources} <- VariableReferenceExtraction.entity_snapshot_sources(entity_type, snapshot) do
      validate_snapshot_variable_references(project_id, sources)
    end
  end

  def validate_entity_snapshot_variable_references(project_id, entity_type, snapshot) do
    {:error, {:invalid_variable_reference_entity_snapshot, project_id, entity_type, snapshot}}
  end

  defp validate_resolvable_specs(_project_id, _source_type, []), do: :ok

  defp validate_resolvable_specs(project_id, source_type, specs) do
    resolved_block_ids =
      VariableReferenceResolutionQueries.resolve_reference_block_ids(project_id, specs)

    case Enum.find(specs, &(not Map.has_key?(resolved_block_ids, &1.resolution_key))) do
      nil ->
        :ok

      spec ->
        source_type = Map.get(spec, :source_type, source_type)

        {:error,
         {:unresolved_variable_reference, source_type, spec.source_id, spec.kind, spec.source_sheet, spec.source_variable}}
    end
  end
end
