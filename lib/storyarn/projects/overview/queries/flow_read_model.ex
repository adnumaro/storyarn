defmodule Storyarn.Projects.FlowReadModel do
  @moduledoc """
  Project-owned projection of Flow tables for project lifecycle, exports and dashboards.

  It deliberately shares PostgreSQL tables with the Flow context while owning its
  Ecto records, queries and export semantics.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Projects.FlowContentContract
  alias Storyarn.Projects.FlowInstruction
  alias Storyarn.Projects.FlowNodeLabel
  alias Storyarn.Projects.FlowSpeakerSheetId
  alias Storyarn.Projects.FlowStructuralAnalysis
  alias Storyarn.Projects.FlowStructuralAnalysis.Topology
  alias Storyarn.Projects.FlowVariableCatalog
  alias Storyarn.Projects.FlowVariableReferenceReadModel
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Repo

  require FlowSpeakerSheetId

  @spec list_flows(pos_integer()) :: [FlowRecord.t()]
  def list_flows(project_id) do
    Repo.all(
      from(flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        order_by: [asc: flow.position, asc: flow.name]
      )
    )
  end

  def get_flow_brief(project_id, flow_id) do
    Repo.one(
      from(flow in FlowRecord,
        where:
          flow.id == ^flow_id and flow.project_id == ^project_id and
            is_nil(flow.deleted_at)
      )
    )
  end

  def get_flow_including_deleted(project_id, flow_id) do
    Repo.one(
      from(flow in FlowRecord,
        where: flow.id == ^flow_id and flow.project_id == ^project_id
      )
    )
  end

  @spec list_flows_for_export(pos_integer(), keyword()) :: [FlowRecord.t()]
  def list_flows_for_export(project_id, opts \\ []) do
    nodes_query =
      from(node in FlowNodeRecord,
        where: is_nil(node.deleted_at),
        order_by: [asc: node.id],
        preload: [:sequence_config, :sequence_tracks, :sequence_visual_layers]
      )

    query =
      from(flow in FlowRecord,
        where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
        preload: [nodes: ^nodes_query, connections: []],
        order_by: [asc: flow.position, asc: flow.name]
      )

    case Keyword.get(opts, :filter_ids, :all) do
      :all -> Repo.all(query)
      ids when is_list(ids) -> Repo.all(from(flow in query, where: flow.id in ^ids))
    end
  end

  def count_flows(project_id) do
    Repo.aggregate(
      from(flow in FlowRecord, where: flow.project_id == ^project_id and is_nil(flow.deleted_at)),
      :count
    )
  end

  def count_nodes_for_project(project_id) do
    Repo.aggregate(
      from(node in FlowNodeRecord,
        join: flow in FlowRecord,
        on: node.flow_id == flow.id,
        where: flow.project_id == ^project_id and is_nil(node.deleted_at) and is_nil(flow.deleted_at)
      ),
      :count
    )
  end

  def flow_word_counts(project_id) do
    node_types = FlowContentContract.localizable_node_types()

    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: flow.id == node.flow_id,
      where:
        flow.project_id == ^project_id and is_nil(flow.deleted_at) and
          is_nil(node.deleted_at) and node.type in ^node_types,
      group_by: node.flow_id,
      select: {node.flow_id, coalesce(sum(node.word_count), 0)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def list_speaker_sheet_ids(project_id) do
    from(node in FlowNodeRecord,
      join: flow in FlowRecord,
      on: node.flow_id == flow.id,
      where: flow.project_id == ^project_id and is_nil(node.deleted_at) and is_nil(flow.deleted_at),
      where: not is_nil(FlowSpeakerSheetId.safe_query_value(node.data)),
      select: FlowSpeakerSheetId.safe_query_value(node.data)
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def list_shortcuts(project_id) do
    from(flow in FlowRecord,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
      select: flow.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def list_referenceable_variables(project_id), do: FlowVariableCatalog.list_referenceable(project_id)
  def variable_type_map(variables), do: FlowInstruction.variable_type_map(variables)
  def node_label(node), do: FlowNodeLabel.for_node(node)
  def node_specific_label(node), do: FlowNodeLabel.specific_for_node(node)

  def list_export_health_findings(project_id, flows, context \\ %{}) do
    topologies = Topology.from_loaded_many(flows)

    variable_types =
      context
      |> Map.get_lazy(:referenceable_variables, fn -> list_referenceable_variables(project_id) end)
      |> variable_type_map()

    stale_by_flow =
      Map.get_lazy(context, :stale_node_ids_by_flow, fn ->
        topologies
        |> Enum.map(& &1.flow_id)
        |> FlowVariableReferenceReadModel.list_stale_node_ids_by_flow()
      end)

    Enum.flat_map(topologies, fn topology ->
      stale_node_ids = Map.get(stale_by_flow, topology.flow_id, MapSet.new())
      nodes = add_health_flags(topology.nodes, stale_node_ids, variable_types)
      labels = Map.new(nodes, &{&1.id, node_specific_label(&1)})

      %{topology | nodes: nodes}
      |> FlowStructuralAnalysis.findings()
      |> Enum.map(fn finding ->
        details =
          finding.details
          |> Map.put(:flow_name, topology.flow_name)
          |> maybe_put_entity_label(finding.entity_id, labels)

        %{finding | details: details}
      end)
    end)
  end

  def list_dashboard_health_findings(project_id) do
    project_id
    |> list_flows_for_export()
    |> then(&list_export_health_findings(project_id, &1))
  end

  defp add_health_flags(nodes, stale_node_ids, variable_types) do
    Enum.map(nodes, fn node ->
      data =
        node.data
        |> maybe_add_stale_flag(node.id, stale_node_ids)
        |> maybe_add_type_warning_flag(node.type, variable_types)

      %{node | data: data}
    end)
  end

  defp maybe_add_type_warning_flag(data, "instruction", variable_types) do
    if FlowInstruction.has_type_warnings?(data["assignments"] || [], variable_types),
      do: Map.put(data, "has_type_warnings", true),
      else: data
  end

  defp maybe_add_type_warning_flag(data, "dialogue", variable_types) do
    responses =
      Enum.map(data["responses"] || [], fn response ->
        if FlowInstruction.has_type_warnings?(response["instruction_assignments"] || [], variable_types),
          do: Map.put(response, "has_type_warnings", true),
          else: response
      end)

    Map.put(data, "responses", responses)
  end

  defp maybe_add_type_warning_flag(data, _type, _variable_types), do: data

  defp maybe_add_stale_flag(data, node_id, stale_node_ids) do
    if MapSet.member?(stale_node_ids, node_id),
      do: Map.put(data, "has_stale_refs", true),
      else: data
  end

  defp maybe_put_entity_label(details, nil, _labels), do: details

  defp maybe_put_entity_label(details, entity_id, labels) do
    case Map.get(labels, entity_id) do
      nil -> details
      label -> Map.put(details, :entity_label, label)
    end
  end
end
