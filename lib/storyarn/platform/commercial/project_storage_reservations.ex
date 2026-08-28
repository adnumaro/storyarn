defmodule Storyarn.Platform.ProjectStorageReservations do
  @moduledoc false

  alias Storyarn.Platform.Billing.StorageAccounting
  alias Storyarn.Platform.Billing.StorageReservation

  @receipt_fields StorageReservation.__schema__(:fields)

  @typedoc "Transport-neutral result of a Platform-owned reservation write."
  @type receipt :: %{
          required(:id) => pos_integer(),
          required(:workspace_id) => pos_integer() | nil,
          required(:project_id) => pos_integer() | nil,
          required(:project_snapshot_id) => pos_integer() | nil,
          required(:workspace_id_snapshot) => pos_integer(),
          required(:project_id_snapshot) => pos_integer(),
          required(:project_snapshot_id_snapshot) => pos_integer(),
          required(:idempotency_key) => String.t(),
          required(:kind) => String.t(),
          required(:status) => String.t(),
          required(:storage_namespace) => String.t(),
          required(:cleanup_object_prefix) => String.t(),
          required(:reserved_bytes) => non_neg_integer(),
          required(:actual_bytes) => non_neg_integer() | nil,
          required(:lease_token) => Ecto.UUID.t(),
          required(:generation) => pos_integer(),
          required(:expires_at) => DateTime.t(),
          required(:storage_started_at) => DateTime.t() | nil,
          required(:cleanup_inventory_digest) => String.t() | nil,
          required(:cleanup_inventory_count) => non_neg_integer() | nil,
          required(:cleanup_storage_keys) => [String.t()] | nil,
          required(:settled_at) => DateTime.t() | nil,
          required(:release_reason) => String.t() | nil,
          required(:cleanup_status) => String.t() | nil,
          required(:cleanup_reference) => String.t() | nil,
          required(:accounting_version) => pos_integer(),
          required(:accounting_measured_at) => DateTime.t(),
          required(:inserted_at) => DateTime.t(),
          required(:updated_at) => DateTime.t()
        }

  @type write_error :: {:error, term()} | {:error, term(), map()}
  @type reservation_result :: {:ok, receipt()} | write_error()
  @type commit_result :: {:ok, %{reservation: receipt(), result: term()}} | write_error()

  @spec reserve(map()) :: reservation_result()
  def reserve(attrs), do: attrs |> StorageAccounting.reserve() |> map_reservation_result()

  @spec acquire_snapshot_export_lease(map()) :: reservation_result()
  def acquire_snapshot_export_lease(attrs) do
    attrs
    |> StorageAccounting.acquire_snapshot_export_lease()
    |> map_reservation_result()
  end

  @spec renew_live(pos_integer(), Ecto.UUID.t(), pos_integer()) ::
          reservation_result()
  def renew_live(reservation_id, lease_token, expected_generation) do
    reservation_id
    |> StorageAccounting.renew_live_storage_reservation(
      lease_token,
      expected_generation
    )
    |> map_reservation_result()
  end

  @spec extend(pos_integer(), Ecto.UUID.t(), pos_integer(), non_neg_integer()) ::
          reservation_result()
  def extend(reservation_id, lease_token, expected_generation, target_bytes) do
    reservation_id
    |> StorageAccounting.extend_to(
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
    |> StorageAccounting.mark_storage_started(
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
          (receipt() -> term())
        ) :: commit_result()
  def commit(reservation_id, lease_token, expected_generation, actual_bytes, owner_fun) when is_function(owner_fun, 1) do
    reservation_id
    |> StorageAccounting.commit(
      lease_token,
      expected_generation,
      actual_bytes,
      fn reservation -> owner_fun.(to_receipt(reservation)) end
    )
    |> map_commit_result()
  end

  @spec commit_restore(
          pos_integer(),
          Ecto.UUID.t(),
          pos_integer(),
          non_neg_integer(),
          (map() -> {:ok, term()} | {:error, term()}),
          (receipt(), term() -> term())
        ) :: commit_result()
  def commit_restore(reservation_id, lease_token, expected_generation, actual_bytes, prelock_fun, owner_fun)
      when is_function(prelock_fun, 1) and is_function(owner_fun, 2) do
    reservation_id
    |> StorageAccounting.commit_project_snapshot_restore_reservation(
      lease_token,
      expected_generation,
      actual_bytes,
      prelock_fun,
      fn reservation, prelock_context ->
        owner_fun.(to_receipt(reservation), prelock_context)
      end
    )
    |> map_commit_result()
  end

  @spec release(pos_integer(), Ecto.UUID.t(), pos_integer(), map()) ::
          reservation_result()
  def release(reservation_id, lease_token, expected_generation, attrs) do
    reservation_id
    |> StorageAccounting.release(
      lease_token,
      expected_generation,
      attrs
    )
    |> map_reservation_result()
  end

  @spec object_prefixes(receipt()) :: {:ok, map()} | {:error, term()}
  def object_prefixes(receipt) when is_map(receipt) do
    receipt
    |> Map.take(@receipt_fields)
    |> then(&struct!(StorageReservation, &1))
    |> StorageAccounting.operation_object_prefixes()
  end

  defp map_reservation_result({:ok, %StorageReservation{} = reservation}) do
    {:ok, to_receipt(reservation)}
  end

  defp map_reservation_result(other), do: other

  defp map_commit_result({:ok, %{reservation: %StorageReservation{} = reservation, result: result}}) do
    {:ok, %{reservation: to_receipt(reservation), result: result}}
  end

  defp map_commit_result(other), do: other

  defp to_receipt(%StorageReservation{} = reservation) do
    reservation
    |> Map.from_struct()
    |> Map.take(@receipt_fields)
  end
end
