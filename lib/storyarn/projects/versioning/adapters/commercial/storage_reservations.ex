defmodule Storyarn.Projects.CommercialStorageReservations do
  @moduledoc """
  Anti-corruption layer between Project snapshot workflows and Commercial's
  authoritative storage-reservation writer.

  Commercial exposes transport-neutral receipts through its public facade. This
  module translates those receipts into the Project-owned read model used by
  snapshot and restore code; a Commercial Ecto schema never crosses the boundary.
  """

  alias Storyarn.Commercial
  alias Storyarn.Projects.Persistence.StorageReservationRecord

  @receipt_fields StorageReservationRecord.__schema__(:fields)

  @type write_error :: {:error, term()} | {:error, term(), map()}
  @type reservation_result :: {:ok, StorageReservationRecord.t()} | write_error()
  @type commit_result ::
          {:ok, %{reservation: StorageReservationRecord.t(), result: term()}} | write_error()

  @spec reserve(map()) :: reservation_result()
  def reserve(attrs), do: attrs |> Commercial.reserve_project_storage() |> map_reservation_result()

  @spec acquire_snapshot_export_lease(map()) ::
          reservation_result()
  def acquire_snapshot_export_lease(attrs) do
    attrs
    |> Commercial.acquire_project_snapshot_export_lease()
    |> map_reservation_result()
  end

  @spec renew_live(pos_integer(), Ecto.UUID.t(), pos_integer()) ::
          reservation_result()
  def renew_live(reservation_id, lease_token, expected_generation) do
    reservation_id
    |> Commercial.renew_project_storage_reservation(
      lease_token,
      expected_generation
    )
    |> map_reservation_result()
  end

  @spec extend(pos_integer(), Ecto.UUID.t(), pos_integer(), non_neg_integer()) ::
          reservation_result()
  def extend(reservation_id, lease_token, expected_generation, target_bytes) do
    reservation_id
    |> Commercial.extend_project_storage_reservation(
      lease_token,
      expected_generation,
      target_bytes
    )
    |> map_reservation_result()
  end

  @spec mark_started(pos_integer(), Ecto.UUID.t(), pos_integer(), map()) ::
          reservation_result()
  def mark_started(reservation_id, lease_token, expected_generation, cleanup_plan) do
    reservation_id
    |> Commercial.mark_project_storage_reservation_started(
      lease_token,
      expected_generation,
      cleanup_plan
    )
    |> map_reservation_result()
  end

  @spec commit(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer(),
          (StorageReservationRecord.t() -> term())
        ) :: commit_result()
  def commit(reservation_id, lease_token, expected_generation, actual_bytes, owner_fun) when is_function(owner_fun, 1) do
    reservation_id
    |> Commercial.commit_project_storage_reservation(
      lease_token,
      expected_generation,
      actual_bytes,
      fn receipt -> owner_fun.(from_receipt(receipt)) end
    )
    |> map_commit_result()
  end

  @spec commit_restore(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer(),
          (map() -> {:ok, term()} | {:error, term()}),
          (StorageReservationRecord.t(), term() -> term())
        ) :: commit_result()
  def commit_restore(reservation_id, lease_token, expected_generation, actual_bytes, prelock_fun, owner_fun)
      when is_function(prelock_fun, 1) and is_function(owner_fun, 2) do
    reservation_id
    |> Commercial.commit_project_snapshot_restore_storage_reservation(
      lease_token,
      expected_generation,
      actual_bytes,
      prelock_fun,
      fn receipt, prelock_context ->
        owner_fun.(from_receipt(receipt), prelock_context)
      end
    )
    |> map_commit_result()
  end

  @spec release(pos_integer(), Ecto.UUID.t(), pos_integer(), map()) ::
          reservation_result()
  def release(reservation_id, lease_token, expected_generation, attrs) do
    reservation_id
    |> Commercial.release_project_storage_reservation(
      lease_token,
      expected_generation,
      attrs
    )
    |> map_reservation_result()
  end

  @spec object_prefixes(StorageReservationRecord.t()) ::
          {:ok, %{optional(atom()) => String.t()}} | {:error, term()}
  def object_prefixes(%StorageReservationRecord{} = reservation) do
    reservation
    |> to_receipt()
    |> Commercial.project_storage_reservation_object_prefixes()
  end

  defp map_reservation_result({:ok, receipt}), do: {:ok, from_receipt(receipt)}
  defp map_reservation_result(other), do: other

  defp map_commit_result({:ok, %{reservation: receipt, result: result}}) do
    {:ok, %{reservation: from_receipt(receipt), result: result}}
  end

  defp map_commit_result(other), do: other

  defp from_receipt(receipt) when is_map(receipt) do
    struct!(StorageReservationRecord, Map.take(receipt, @receipt_fields))
  end

  defp to_receipt(%StorageReservationRecord{} = reservation) do
    reservation
    |> Map.from_struct()
    |> Map.take(@receipt_fields)
  end
end
