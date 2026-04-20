defmodule Storyarn.Flows.SequenceCrud do
  @moduledoc """
  CRUD for `Storyarn.Flows.Sequence`.

  Sequences scope to a flow (via `flow_id`) and track a `start_node_id` — the
  node the author right-clicked to create the Sequence. Downstream nodes inherit
  the Sequence at runtime via the `sequence_directive` pointer on their data.

  Soft delete supported via `deleted_at`.
  """

  import Ecto.Query

  alias Storyarn.Flows.Sequence
  alias Storyarn.Repo

  @doc """
  Lists active (non-deleted) sequences for a flow, ordered by insertion time.
  """
  @spec list_sequences(integer()) :: [Sequence.t()]
  def list_sequences(flow_id) do
    from(s in Sequence,
      where: s.flow_id == ^flow_id and is_nil(s.deleted_at),
      order_by: [asc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists soft-deleted sequences for a flow (for trash/restore UIs).
  """
  @spec list_deleted(integer()) :: [Sequence.t()]
  def list_deleted(flow_id) do
    from(s in Sequence,
      where: s.flow_id == ^flow_id and not is_nil(s.deleted_at),
      order_by: [desc: s.deleted_at]
    )
    |> Repo.all()
  end

  @doc """
  Fetches an active sequence by id scoped to a flow. Returns nil if absent or deleted.
  """
  @spec get_sequence(integer(), integer()) :: Sequence.t() | nil
  def get_sequence(flow_id, id) do
    from(s in Sequence,
      where: s.id == ^id and s.flow_id == ^flow_id and is_nil(s.deleted_at)
    )
    |> Repo.one()
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
  Soft-deletes a sequence.
  """
  @spec delete_sequence(Sequence.t()) :: {:ok, Sequence.t()} | {:error, Ecto.Changeset.t()}
  def delete_sequence(%Sequence{} = sequence) do
    sequence
    |> Sequence.soft_delete_changeset()
    |> Repo.update()
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
