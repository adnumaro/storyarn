defmodule Storyarn.Projects.FlowImportPersistence do
  @moduledoc "Project-owned writer used only by project import/reconstitution."

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.MapUtils
  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.FlowHubColors
  alias Storyarn.Projects.FlowWordCount, as: WordCount
  alias Storyarn.Projects.Persistence.FlowConnectionRecord
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SequenceConfigRecord
  alias Storyarn.Repo

  def detect_shortcut_conflicts(_project_id, []), do: []

  def detect_shortcut_conflicts(project_id, shortcuts) do
    Repo.all(
      from(flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.shortcut in ^shortcuts and
            is_nil(flow.deleted_at),
        select: flow.shortcut
      )
    )
  end

  def list_shortcuts(project_id) do
    from(flow in FlowRecord,
      where: flow.project_id == ^project_id and is_nil(flow.deleted_at),
      select: flow.shortcut
    )
    |> Repo.all()
    |> MapSet.new()
  end

  def soft_delete_by_shortcut(project_id, shortcut) do
    Repo.update_all(
      from(flow in FlowRecord,
        where:
          flow.project_id == ^project_id and flow.shortcut == ^shortcut and
            is_nil(flow.deleted_at)
      ),
      set: [deleted_at: TimeHelpers.now()]
    )
  end

  def import_flow(project_id, attrs) do
    %FlowRecord{project_id: project_id}
    |> FlowRecord.create_changeset(attrs)
    |> Repo.insert()
  end

  def import_node(flow_id, attrs) do
    type = MapUtils.get_flexible(attrs, :type)
    data = MapUtils.get_flexible(attrs, :data)
    sequence_config = MapUtils.get_flexible(attrs, :sequence_config)

    Repo.transaction(fn ->
      validate_import_node_invariants!(flow_id, type, data)

      flow_id
      |> insert_import_node!(attrs, type, data)
      |> maybe_insert_sequence_config!(type, sequence_config)
    end)
  end

  def link_flow_parent(%FlowRecord{} = flow, parent_id) do
    flow
    |> Ecto.Changeset.change(%{parent_id: parent_id})
    |> Repo.update!()
  end

  def link_node_parent(%FlowNodeRecord{} = node, parent_id) do
    Repo.transaction(fn ->
      locked_node = lock_active_node!(node.id)
      parent = lock_active_sequence_parent!(locked_node.flow_id, parent_id)

      reject_cyclic_parent!(parent, locked_node.id)
      update_node_parent!(locked_node, parent.id)
    end)
  end

  def link_node_data(node_id, data) do
    Repo.update_all(from(node in FlowNodeRecord, where: node.id == ^node_id), set: [data: data])
  end

  def bulk_insert_connections(attrs_list, chunk_size \\ 500) do
    attrs_list
    |> Enum.chunk_every(chunk_size)
    |> Enum.flat_map(fn chunk ->
      {_count, inserted} = Repo.insert_all(FlowConnectionRecord, chunk, returning: [:id])
      inserted
    end)
  end

  def resolve_legacy_hub_color(color), do: FlowHubColors.resolve_legacy(color)

  defp validate_import_node_invariants!(flow_id, "entry", _data) do
    lock_flow!(flow_id)

    if Repo.exists?(
         from(node in FlowNodeRecord,
           where: node.flow_id == ^flow_id and node.type == "entry" and is_nil(node.deleted_at)
         )
       ) do
      Repo.rollback(:entry_node_exists)
    end
  end

  defp validate_import_node_invariants!(flow_id, "hub", data) do
    lock_flow!(flow_id)
    hub_id = if is_map(data), do: MapUtils.get_flexible(data, :hub_id)

    cond do
      not is_binary(hub_id) or String.trim(hub_id) == "" ->
        Repo.rollback(:hub_id_required)

      Repo.exists?(
        from(node in FlowNodeRecord,
          where:
            node.flow_id == ^flow_id and node.type == "hub" and
              is_nil(node.deleted_at) and fragment("?->>'hub_id' = ?", node.data, ^hub_id)
        )
      ) ->
        Repo.rollback(:hub_id_not_unique)

      true ->
        :ok
    end
  end

  defp validate_import_node_invariants!(_flow_id, _type, _data), do: :ok

  defp lock_flow!(flow_id) do
    Repo.one(from(flow in FlowRecord, where: flow.id == ^flow_id, lock: "FOR UPDATE")) ||
      Repo.rollback(:flow_not_found)
  end

  defp insert_import_node!(flow_id, attrs, type, data) do
    %FlowNodeRecord{flow_id: flow_id}
    |> FlowNodeRecord.create_changeset(attrs)
    |> Ecto.Changeset.put_change(:word_count, WordCount.for_node_data(type, data))
    |> Repo.insert()
    |> case do
      {:ok, node} -> node
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp maybe_insert_sequence_config!(node, "sequence", attrs) do
    attrs =
      attrs
      |> then(fn value -> if is_map(value), do: value, else: %{} end)
      |> MapUtils.stringify_keys()
      |> Map.put("flow_node_id", node.id)

    %SequenceConfigRecord{}
    |> SequenceConfigRecord.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, config} -> %{node | sequence_config: config}
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp maybe_insert_sequence_config!(node, _type, _attrs), do: node

  defp lock_active_node!(node_id) do
    Repo.one(
      from(candidate in FlowNodeRecord,
        where: candidate.id == ^node_id and is_nil(candidate.deleted_at),
        lock: "FOR UPDATE"
      )
    ) || Repo.rollback(:node_not_found)
  end

  defp lock_active_sequence_parent!(flow_id, parent_id) do
    Repo.one(
      from(candidate in FlowNodeRecord,
        where:
          candidate.id == ^parent_id and candidate.flow_id == ^flow_id and
            candidate.type == "sequence" and is_nil(candidate.deleted_at),
        lock: "FOR SHARE"
      )
    ) || Repo.rollback({:invalid_node_parent, parent_id})
  end

  defp reject_cyclic_parent!(parent, node_id) do
    if node_ancestor?(parent, node_id, MapSet.new()) do
      Repo.rollback(:cyclic_parent)
    end
  end

  defp update_node_parent!(node, parent_id) do
    node
    |> FlowNodeRecord.reparent_changeset(%{parent_id: parent_id})
    |> Repo.update()
    |> case do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp node_ancestor?(%FlowNodeRecord{id: id}, source_id, _visited) when id == source_id, do: true
  defp node_ancestor?(%FlowNodeRecord{parent_id: nil}, _source_id, _visited), do: false

  defp node_ancestor?(%FlowNodeRecord{parent_id: parent_id, flow_id: flow_id}, source_id, visited) do
    if MapSet.member?(visited, parent_id) do
      true
    else
      case Repo.one(
             from(node in FlowNodeRecord,
               where:
                 node.id == ^parent_id and node.flow_id == ^flow_id and
                   node.type == "sequence" and is_nil(node.deleted_at),
               lock: "FOR SHARE"
             )
           ) do
        nil -> false
        parent -> node_ancestor?(parent, source_id, MapSet.put(visited, parent_id))
      end
    end
  end
end
