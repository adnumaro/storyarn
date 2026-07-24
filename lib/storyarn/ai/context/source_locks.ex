defmodule Storyarn.AI.Context.SourceLocks do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.AI.Context.Entity
  alias Storyarn.AI.Context.EvidenceLoader
  alias Storyarn.AI.Operation
  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  @persisted_types ~w(flow flow_node flow_connection sheet sheet_block)
  @virtual_types ~w(dialogue_response structural_finding)
  @max_included_sources 500

  @type source_ids :: %{String.t() => MapSet.t(pos_integer())}

  @doc """
  Locks the aggregate roots and rows that produced a context package.

  Flow and sheet root locks prevent new children from passing their foreign-key
  checks while the apply transaction is open. Existing included children are
  locked in deterministic table/id order before the context is rebuilt.
  """
  @spec acquire(Operation.t()) :: :ok | {:error, :stale_context}
  def acquire(%Operation{context_hash: nil, context_manifest: nil, context_subject: nil}), do: :ok

  def acquire(%Operation{project_id_snapshot: project_id, context_hash: context_hash, context_manifest: %{} = manifest})
      when is_integer(project_id) and is_binary(context_hash) do
    with {:ok, source_ids} <- included_source_ids(manifest),
         :ok <- active_project(project_id),
         {:ok, roots} <- resolve_roots(project_id, source_ids),
         :ok <- lock_roots(project_id, roots),
         {:ok, locked_children} <- lock_children(source_ids, roots),
         :ok <- included_sources_locked(source_ids, roots, locked_children),
         :ok <- verify_structural_evidence(project_id, manifest) do
      :ok
    else
      _error -> {:error, :stale_context}
    end
  end

  def acquire(%Operation{}), do: {:error, :stale_context}

  defp included_source_ids(manifest) do
    case value(manifest, :included) do
      included when is_list(included) and length(included) <= @max_included_sources ->
        Enum.reduce_while(included, {:ok, empty_source_ids()}, &include_source/2)

      _invalid ->
        {:error, :invalid_manifest}
    end
  end

  defp include_source(%{} = item, {:ok, source_ids}) do
    type = value(item, :type)
    id = value(item, :id)

    cond do
      type in @persisted_types and positive_id?(id) ->
        {:cont, {:ok, Map.update!(source_ids, type, &MapSet.put(&1, id))}}

      type in @virtual_types and valid_virtual_id?(id) ->
        {:cont, {:ok, source_ids}}

      true ->
        {:halt, {:error, :invalid_manifest}}
    end
  end

  defp include_source(_item, _acc), do: {:halt, {:error, :invalid_manifest}}

  defp empty_source_ids do
    Map.new(@persisted_types, &{&1, MapSet.new()})
  end

  defp active_project(project_id) do
    if Repo.exists?(
         from(project in Storyarn.Projects.Project,
           where: project.id == ^project_id and is_nil(project.deleted_at)
         )
       ),
       do: :ok,
       else: {:error, :context_missing}
  end

  defp resolve_roots(project_id, source_ids) do
    with {:ok, node_parents} <-
           flow_node_parents(project_id, MapSet.to_list(source_ids["flow_node"])),
         {:ok, connection_parents} <-
           flow_connection_parents(
             project_id,
             MapSet.to_list(source_ids["flow_connection"])
           ),
         {:ok, block_parents} <-
           sheet_block_parents(project_id, MapSet.to_list(source_ids["sheet_block"])) do
      {:ok,
       %{
         flow_ids:
           source_ids["flow"]
           |> MapSet.union(MapSet.new(Map.values(node_parents)))
           |> MapSet.union(MapSet.new(Map.values(connection_parents.parents)))
           |> MapSet.to_list()
           |> Enum.sort(),
         sheet_ids:
           source_ids["sheet"]
           |> MapSet.union(MapSet.new(Map.values(block_parents)))
           |> MapSet.to_list()
           |> Enum.sort(),
         connection_endpoint_ids: connection_parents.endpoint_ids
       }}
    end
  end

  defp flow_node_parents(_project_id, []), do: {:ok, %{}}

  defp flow_node_parents(project_id, node_ids) do
    rows =
      Repo.all(
        from(node in FlowNode,
          join: flow in Flow,
          on: flow.id == node.flow_id,
          where:
            node.id in ^node_ids and flow.project_id == ^project_id and
              is_nil(node.deleted_at) and is_nil(flow.deleted_at),
          order_by: [asc: node.id],
          select: {node.id, node.flow_id}
        )
      )

    complete_parent_map(rows, node_ids)
  end

  defp flow_connection_parents(_project_id, []) do
    {:ok, %{parents: %{}, endpoint_ids: MapSet.new()}}
  end

  defp flow_connection_parents(project_id, connection_ids) do
    rows =
      Repo.all(
        from(connection in FlowConnection,
          join: flow in Flow,
          on: flow.id == connection.flow_id,
          join: source in FlowNode,
          on: source.id == connection.source_node_id,
          join: target in FlowNode,
          on: target.id == connection.target_node_id,
          where:
            connection.id in ^connection_ids and flow.project_id == ^project_id and
              is_nil(flow.deleted_at) and is_nil(source.deleted_at) and
              is_nil(target.deleted_at),
          order_by: [asc: connection.id],
          select: {connection.id, connection.flow_id, connection.source_node_id, connection.target_node_id}
        )
      )

    parents = Map.new(rows, fn {id, flow_id, _source_id, _target_id} -> {id, flow_id} end)

    if MapSet.new(Map.keys(parents)) == MapSet.new(connection_ids) do
      endpoint_ids =
        rows
        |> Enum.flat_map(fn {_id, _flow_id, source_id, target_id} ->
          [source_id, target_id]
        end)
        |> MapSet.new()

      {:ok, %{parents: parents, endpoint_ids: endpoint_ids}}
    else
      {:error, :context_missing}
    end
  end

  defp sheet_block_parents(_project_id, []), do: {:ok, %{}}

  defp sheet_block_parents(project_id, block_ids) do
    rows =
      Repo.all(
        from(block in Block,
          join: sheet in Sheet,
          on: sheet.id == block.sheet_id,
          where:
            block.id in ^block_ids and sheet.project_id == ^project_id and
              is_nil(block.deleted_at) and is_nil(sheet.deleted_at),
          order_by: [asc: block.id],
          select: {block.id, block.sheet_id}
        )
      )

    complete_parent_map(rows, block_ids)
  end

  defp complete_parent_map(rows, expected_ids) do
    parents = Map.new(rows)

    if MapSet.new(Map.keys(parents)) == MapSet.new(expected_ids),
      do: {:ok, parents},
      else: {:error, :context_missing}
  end

  defp lock_roots(project_id, %{flow_ids: flow_ids, sheet_ids: sheet_ids}) do
    with :ok <- lock_flow_roots(project_id, flow_ids) do
      lock_sheet_roots(project_id, sheet_ids)
    end
  end

  defp lock_flow_roots(_project_id, []), do: :ok

  defp lock_flow_roots(project_id, flow_ids) do
    locked_ids =
      Repo.all(
        from(flow in Flow,
          where:
            flow.id in ^flow_ids and flow.project_id == ^project_id and
              is_nil(flow.deleted_at),
          order_by: [asc: flow.id],
          select: flow.id,
          lock: "FOR UPDATE"
        )
      )

    exact_ids(locked_ids, flow_ids)
  end

  defp lock_sheet_roots(_project_id, []), do: :ok

  defp lock_sheet_roots(project_id, sheet_ids) do
    locked_ids =
      Repo.all(
        from(sheet in Sheet,
          where:
            sheet.id in ^sheet_ids and sheet.project_id == ^project_id and
              is_nil(sheet.deleted_at),
          order_by: [asc: sheet.id],
          select: sheet.id,
          lock: "FOR UPDATE"
        )
      )

    exact_ids(locked_ids, sheet_ids)
  end

  defp lock_children(source_ids, %{
         flow_ids: flow_ids,
         sheet_ids: sheet_ids,
         connection_endpoint_ids: connection_endpoint_ids
       }) do
    node_ids =
      source_ids["flow_node"]
      |> MapSet.union(connection_endpoint_ids)
      |> MapSet.to_list()

    connection_ids = MapSet.to_list(source_ids["flow_connection"])
    block_ids = MapSet.to_list(source_ids["sheet_block"])

    node_rows =
      Repo.all(
        from(node in FlowNode,
          where:
            node.id in ^node_ids and node.flow_id in ^flow_ids and
              is_nil(node.deleted_at),
          order_by: [asc: node.id],
          select: {node.id, node.flow_id},
          lock: "FOR UPDATE"
        )
      )

    connection_rows =
      Repo.all(
        from(connection in FlowConnection,
          where:
            connection.id in ^connection_ids and
              connection.flow_id in ^flow_ids,
          order_by: [asc: connection.id],
          select: {connection.id, connection.flow_id},
          lock: "FOR UPDATE"
        )
      )

    block_rows =
      Repo.all(
        from(block in Block,
          where:
            block.id in ^block_ids and block.sheet_id in ^sheet_ids and
              is_nil(block.deleted_at),
          order_by: [asc: block.id],
          select: {block.id, block.sheet_id},
          lock: "FOR UPDATE"
        )
      )

    {:ok,
     %{
       "flow_node" => MapSet.new(node_rows, &elem(&1, 0)),
       "flow_connection" => MapSet.new(connection_rows, &elem(&1, 0)),
       "sheet_block" => MapSet.new(block_rows, &elem(&1, 0))
     }}
  end

  defp included_sources_locked(source_ids, roots, locked_children) do
    checks = [
      MapSet.subset?(source_ids["flow"], MapSet.new(roots.flow_ids)),
      MapSet.subset?(source_ids["sheet"], MapSet.new(roots.sheet_ids)),
      MapSet.subset?(source_ids["flow_node"], locked_children["flow_node"]),
      MapSet.subset?(
        roots.connection_endpoint_ids,
        locked_children["flow_node"]
      ),
      MapSet.subset?(
        source_ids["flow_connection"],
        locked_children["flow_connection"]
      ),
      MapSet.subset?(source_ids["sheet_block"], locked_children["sheet_block"])
    ]

    if Enum.all?(checks), do: :ok, else: {:error, :context_missing}
  end

  defp verify_structural_evidence(project_id, manifest) do
    if value(manifest, :scope) == "structural_finding" do
      verify_evidence_entries(project_id, value(manifest, :included))
    else
      :ok
    end
  end

  defp verify_evidence_entries(project_id, included) do
    evidence_entries =
      Enum.filter(included, &(value(&1, :type) in @persisted_types))

    descriptors =
      Enum.map(evidence_entries, fn item ->
        %{"type" => value(item, :type), "id" => value(item, :id)}
      end)

    with {:ok, evidence} <- EvidenceLoader.load(project_id, descriptors),
         true <- length(evidence) == length(evidence_entries),
         :ok <- evidence_matches_manifest(evidence, evidence_entries) do
      :ok
    else
      _error -> {:error, :stale_context}
    end
  end

  defp evidence_matches_manifest(evidence, entries) do
    expected = Map.new(entries, &{{value(&1, :type), value(&1, :id)}, &1})

    if Enum.all?(evidence, &evidence_matches_entry?(&1, expected)) do
      :ok
    else
      {:error, :stale_context}
    end
  end

  defp evidence_matches_entry?(item, expected) do
    entity =
      Entity.new(item.type, item.id, item.content, revision: item.revision)

    case {entity, Map.get(expected, {item.type, item.id})} do
      {{:ok, entity}, %{} = manifest_entry} ->
        entity.hash == value(manifest_entry, :hash) and
          entity.revision == value(manifest_entry, :revision)

      _missing ->
        false
    end
  end

  defp exact_ids(locked_ids, expected_ids) do
    if locked_ids == Enum.sort(expected_ids),
      do: :ok,
      else: {:error, :context_missing}
  end

  defp positive_id?(value), do: is_integer(value) and value > 0
  defp valid_virtual_id?(value), do: positive_id?(value) or (is_binary(value) and byte_size(value) > 0)
  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
