defmodule Storyarn.Projects.References.VariableReferenceTracker do
  @moduledoc """
  Transactional writer for the Project-owned variable-reference projection.

  It replaces references after individual Flow or Scene edits and additively
  rebuilds missing rows for every active source in a project. Source extraction,
  target resolution, validation and read-side usage queries live in dedicated
  rules and query modules.
  """

  import Ecto.Query

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.References.Persistence.FlowNodeRecord
  alias Storyarn.Projects.References.Persistence.FlowRecord
  alias Storyarn.Projects.References.Persistence.SceneAmbientFlowRecord, as: SceneAmbientFlow
  alias Storyarn.Projects.References.Persistence.ScenePinRecord, as: ScenePin
  alias Storyarn.Projects.References.Persistence.SceneRecord, as: Scene
  alias Storyarn.Projects.References.Persistence.SceneZoneRecord, as: SceneZone
  alias Storyarn.Projects.References.VariableProjectionQueries
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Projects.References.VariableReferenceExtraction
  alias Storyarn.Projects.References.VariableReferenceResolutionQueries
  alias Storyarn.Repo

  @rebuild_batch_size 100

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
  Restores resolvable variable-reference rows from every active source.

  The rebuild is deliberately additive so stale rows remain available to the
  repair workflow. Its caller owns the outer transaction.
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

  defp extract_flow_node_variable_refs(%{flow_id: flow_id} = node) do
    case VariableReferenceResolutionQueries.flow_project_id(flow_id) do
      nil ->
        []

      project_id ->
        node
        |> VariableReferenceExtraction.flow_node_specs()
        |> resolve_specs(project_id)
    end
  end

  defp extract_zone_variable_refs(zone, project_id), do: extract_scene_element_variable_refs(zone, project_id)

  defp extract_pin_variable_refs(pin, project_id), do: extract_scene_element_variable_refs(pin, project_id)

  defp extract_ambient_flow_variable_refs(ambient_flow, project_id) do
    ambient_flow
    |> VariableReferenceExtraction.ambient_flow_specs()
    |> resolve_specs(project_id)
  end

  defp extract_scene_element_variable_refs(element, project_id) do
    element
    |> VariableReferenceExtraction.scene_element_specs()
    |> resolve_specs(project_id)
  end

  defp resolve_specs(specs, project_id) do
    resolved_block_ids =
      VariableReferenceResolutionQueries.resolve_reference_block_ids(project_id, specs)

    VariableReferenceExtraction.resolve_specs(specs, resolved_block_ids)
  end

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
