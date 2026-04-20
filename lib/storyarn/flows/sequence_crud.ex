defmodule Storyarn.Flows.SequenceCrud do
  @moduledoc """
  CRUD for `Storyarn.Flows.Sequence`.

  Sequences scope to a flow (via `flow_id`) and track a `start_node_id` — the
  node the author right-clicked to create the Sequence. Downstream nodes inherit
  the Sequence at runtime via the `sequence_directive` pointer on their data.

  Soft delete supported via `deleted_at`.
  """

  import Ecto.Query

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.Sequence
  alias Storyarn.Repo

  @doc """
  Lists active (non-deleted) sequences for a flow, ordered by insertion time.
  """
  @spec list_sequences(integer()) :: [Sequence.t()]
  def list_sequences(flow_id) do
    Repo.all(from(s in Sequence, where: s.flow_id == ^flow_id and is_nil(s.deleted_at), order_by: [asc: s.inserted_at]))
  end

  @doc """
  Lists soft-deleted sequences for a flow (for trash/restore UIs).
  """
  @spec list_deleted(integer()) :: [Sequence.t()]
  def list_deleted(flow_id) do
    Repo.all(
      from(s in Sequence, where: s.flow_id == ^flow_id and not is_nil(s.deleted_at), order_by: [desc: s.deleted_at])
    )
  end

  @doc """
  Fetches an active sequence by id scoped to a flow. Returns nil if absent or deleted.
  """
  @spec get_sequence(integer(), integer()) :: Sequence.t() | nil
  def get_sequence(flow_id, id) do
    Repo.one(from(s in Sequence, where: s.id == ^id and s.flow_id == ^flow_id and is_nil(s.deleted_at)))
  end

  @doc """
  Fetches a sequence by id scoped to a flow. Raises if absent.
  """
  @spec get_sequence!(integer(), integer()) :: Sequence.t()
  def get_sequence!(flow_id, id) do
    Repo.get_by!(Sequence, id: id, flow_id: flow_id)
  end

  @doc """
  Creates a sequence for a given flow + start node.

  `attrs` should include at minimum `:name`. `:tracks` defaults to an empty map
  of the 5 fixed track keys if not provided.
  """
  @spec create_sequence(integer(), integer(), map()) ::
          {:ok, Sequence.t()} | {:error, Ecto.Changeset.t()}
  def create_sequence(flow_id, start_node_id, attrs) do
    attrs =
      attrs
      |> Map.put_new("flow_id", flow_id)
      |> Map.put_new("start_node_id", start_node_id)
      |> Map.put_new("tracks", Sequence.empty_tracks())

    %Sequence{}
    |> Sequence.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a sequence anchored at the given node AND sets that node's
  `sequence_directive` to point at the new sequence, atomically.

  This is the entry-point the UI uses for "Create sequence from here".
  If the node already had a `sequence_directive`, it is overwritten.

  `attrs` should include at minimum `:name` (or `"name"`).
  """
  @spec create_sequence_from_node(FlowNode.t(), map()) ::
          {:ok, Sequence.t()} | {:error, Ecto.Changeset.t()}
  def create_sequence_from_node(%FlowNode{} = node, attrs) do
    Repo.transaction(fn ->
      case create_sequence(node.flow_id, node.id, attrs) do
        {:ok, sequence} ->
          case set_node_sequence_directive(node, sequence.id) do
            {:ok, _updated_node} -> sequence
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp set_node_sequence_directive(%FlowNode{} = node, sequence_id) do
    new_data = Map.put(node.data || %{}, "sequence_directive", sequence_id)

    node
    |> FlowNode.data_changeset(%{data: new_data})
    |> Repo.update()
  end

  @doc """
  Updates a sequence's name and/or tracks. `flow_id` and `start_node_id` are immutable.
  """
  @spec update_sequence(Sequence.t(), map()) ::
          {:ok, Sequence.t()} | {:error, Ecto.Changeset.t()}
  def update_sequence(%Sequence{} = sequence, attrs) do
    sequence
    |> Sequence.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Soft-deletes a sequence and sweeps any `sequence_directive` pointers on nodes
  of the same flow that reference this sequence.

  The sweep is what keeps JSONB cross-refs consistent without a true FK —
  see `docs/audit/jsonb-cross-refs-lifecycle-hooks.md` for the rationale.

  Runs in a transaction so the sweep either lands with the soft-delete or
  neither does.
  """
  @spec delete_sequence(Sequence.t()) :: {:ok, Sequence.t()} | {:error, Ecto.Changeset.t()}
  def delete_sequence(%Sequence{} = sequence) do
    Repo.transaction(fn ->
      case sequence |> Sequence.soft_delete_changeset() |> Repo.update() do
        {:ok, deleted} ->
          clear_sequence_directive_pointers(deleted.flow_id, deleted.id)
          deleted

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # Nullifies `data["sequence_directive"]` on active nodes of `flow_id` that
  # currently point to `sequence_id`. The key is preserved (set to nil) for
  # consistency with the default_data shape in node type modules.
  defp clear_sequence_directive_pointers(flow_id, sequence_id) do
    seq_id_str = to_string(sequence_id)

    from(n in FlowNode,
      where:
        n.flow_id == ^flow_id and
          is_nil(n.deleted_at) and
          fragment("?->>'sequence_directive' = ?", n.data, ^seq_id_str)
    )
    |> Repo.all()
    |> Enum.each(fn node ->
      new_data = Map.put(node.data || %{}, "sequence_directive", nil)

      node
      |> FlowNode.data_changeset(%{data: new_data})
      |> Repo.update!()
    end)
  end

  @doc """
  Restores a soft-deleted sequence.
  """
  @spec restore_sequence(Sequence.t()) :: {:ok, Sequence.t()} | {:error, Ecto.Changeset.t()}
  def restore_sequence(%Sequence{} = sequence) do
    sequence
    |> Sequence.restore_changeset()
    |> Repo.update()
  end
end
