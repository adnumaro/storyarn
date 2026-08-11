defmodule Storyarn.Billing.StorageReservation do
  @moduledoc """
  Durable workspace storage capacity held by one idempotent operation.

  Reservations retain immutable workspace and project identifiers after their
  live foreign keys are cleared. Terminal release requires either proof that no
  cleanup is needed or a durable cleanup owner reference.
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Project
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Workspaces.Workspace

  @kinds ~w(snapshot_build linked_to_full_conversion restore_staging snapshot_export)
  @statuses ~w(active committed released)
  @cleanup_statuses ~w(not_required owned)

  schema "workspace_storage_reservations" do
    field :workspace_id_snapshot, :integer
    field :project_id_snapshot, :integer
    field :project_snapshot_id_snapshot, :integer
    field :idempotency_key, :string
    field :kind, :string
    field :status, :string
    field :storage_namespace, :string
    field :cleanup_object_prefix, :string
    field :source_asset_count, :integer
    field :reserved_bytes, :integer
    field :actual_bytes, :integer
    field :lease_token, Ecto.UUID
    field :generation, :integer
    field :expires_at, :utc_datetime
    field :storage_started_at, :utc_datetime
    field :cleanup_inventory_digest, :string
    field :cleanup_inventory_count, :integer
    field :settled_at, :utc_datetime
    field :release_reason, :string
    field :cleanup_status, :string
    field :cleanup_reference, :string
    field :accounting_version, :integer
    field :accounting_measured_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :project, Project
    belongs_to :project_snapshot, ProjectSnapshot

    timestamps(type: :utc_datetime)
  end

  @doc "Creates an active reservation with immutable workspace and project attribution."
  def create_changeset(reservation, attrs) do
    reservation
    |> cast(attrs, [
      :idempotency_key,
      :kind,
      :storage_namespace,
      :cleanup_object_prefix,
      :reserved_bytes,
      :lease_token,
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> put_change(:status, "active")
    |> put_identity_fields(attrs)
    |> validate_required([
      :workspace_id,
      :project_id,
      :workspace_id_snapshot,
      :project_id_snapshot,
      :project_snapshot_id,
      :project_snapshot_id_snapshot,
      :idempotency_key,
      :kind,
      :status,
      :storage_namespace,
      :cleanup_object_prefix,
      :reserved_bytes,
      :lease_token,
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_common_fields()
    |> validate_inclusion(:status, ["active"])
    |> unique_constraint([:workspace_id_snapshot, :idempotency_key],
      name: :workspace_storage_reservations_workspace_idempotency_idx
    )
    |> unique_constraint(:project_snapshot_id_snapshot,
      name: :workspace_storage_reservations_active_snapshot_operation_idx
    )
    |> unique_constraint(:cleanup_object_prefix,
      name: :workspace_storage_reservations_ready_prefix_idx
    )
    |> unique_constraint(:lease_token)
    |> storage_constraints()
  end

  @doc "Extends an active reservation and advances its generation/accounting metadata."
  def extend_changeset(reservation, reserved_bytes, attrs) do
    previous_reserved_bytes = reservation.reserved_bytes
    previous_generation = reservation.generation

    reservation
    |> change()
    |> require_active()
    |> cast(attrs, [
      :lease_token,
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> put_change(:reserved_bytes, reserved_bytes)
    |> validate_required([
      :reserved_bytes,
      :lease_token,
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_common_fields()
    |> validate_extension(previous_reserved_bytes, previous_generation)
    |> storage_constraints()
  end

  @doc "Renews an active reservation without changing its reserved capacity."
  def renew_changeset(reservation, attrs) do
    previous_generation = reservation.generation
    previous_expires_at = reservation.expires_at

    reservation
    |> change()
    |> require_active()
    |> cast(attrs, [
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_required([
      :reserved_bytes,
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_common_fields()
    |> validate_strict_increase(:generation, previous_generation)
    |> validate_datetime_increase(:expires_at, previous_expires_at)
    |> storage_constraints()
  end

  @doc """
  Renews the exact live snapshot-build owner and rebases its expiry window.

  Unlike a general reservation renewal, the new expiry may be earlier than a
  legacy 24-hour lease. The caller must hold the workspace lock and prove the
  exact executing Oban owner before using this generation-fenced changeset.
  """
  def live_owner_renew_changeset(reservation, attrs) do
    previous_generation = reservation.generation

    reservation
    |> change()
    |> require_active()
    |> validate_inclusion(:kind, ["snapshot_build"])
    |> cast(attrs, [
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_required([
      :reserved_bytes,
      :generation,
      :expires_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_common_fields()
    |> validate_strict_increase(:generation, previous_generation)
    |> storage_constraints()
  end

  @doc "Commits verified actual bytes for the reservation's immutable snapshot target."
  def commit_changeset(reservation, actual_bytes, attrs) do
    previous_generation = reservation.generation

    reservation
    |> change()
    |> require_active()
    |> cast(attrs, [:generation, :settled_at, :accounting_version, :accounting_measured_at])
    |> put_change(:status, "committed")
    |> put_change(:actual_bytes, actual_bytes)
    |> put_change(:release_reason, nil)
    |> put_change(:cleanup_status, nil)
    |> put_change(:cleanup_reference, nil)
    |> validate_required([
      :status,
      :actual_bytes,
      :generation,
      :storage_started_at,
      :settled_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_allocated_bytes(:actual_bytes)
    |> validate_inclusion(:accounting_version, [1])
    |> validate_actual_within_reservation()
    |> validate_strict_increase(:generation, previous_generation)
    |> storage_constraints()
  end

  @doc "Marks that the operation may begin writing beneath its immutable namespace."
  def storage_started_changeset(reservation, measured_at, inventory_digest, inventory_count) do
    reservation
    |> change()
    |> require_active()
    |> validate_storage_start_allowed()
    |> put_change(:storage_started_at, measured_at)
    |> put_change(:cleanup_inventory_digest, inventory_digest)
    |> put_change(:cleanup_inventory_count, inventory_count)
    |> put_change(:accounting_measured_at, measured_at)
    |> validate_required([
      :storage_started_at,
      :cleanup_inventory_digest,
      :cleanup_inventory_count
    ])
    |> validate_format(:cleanup_inventory_digest, ~r/\A[0-9a-f]{64}\z/)
    |> validate_number(:cleanup_inventory_count, greater_than: 0)
    |> storage_constraints()
  end

  @doc "Releases an active reservation after cleanup ownership has been made durable."
  def release_changeset(reservation, reason, attrs) do
    previous_generation = reservation.generation

    reservation
    |> change()
    |> require_active()
    |> cast(attrs, [
      :generation,
      :settled_at,
      :cleanup_status,
      :cleanup_reference,
      :accounting_version,
      :accounting_measured_at
    ])
    |> put_change(:status, "released")
    |> put_change(:actual_bytes, nil)
    |> put_change(:release_reason, reason)
    |> validate_required([
      :status,
      :release_reason,
      :cleanup_status,
      :generation,
      :settled_at,
      :accounting_version,
      :accounting_measured_at
    ])
    |> validate_inclusion(:cleanup_status, @cleanup_statuses)
    |> validate_length(:release_reason, max: 255)
    |> validate_length(:cleanup_reference, max: 500)
    |> validate_inclusion(:accounting_version, [1])
    |> validate_strict_increase(:generation, previous_generation)
    |> validate_cleanup_reference()
    |> storage_constraints()
  end

  defp put_identity_fields(changeset, attrs) do
    workspace_id = get_attr(attrs, :workspace_id)
    project_id = get_attr(attrs, :project_id)

    changeset
    |> put_change(:workspace_id, workspace_id)
    |> put_change(:project_id, project_id)
    |> put_change(
      :workspace_id_snapshot,
      get_attr(attrs, :workspace_id_snapshot, workspace_id)
    )
    |> put_change(:project_id_snapshot, get_attr(attrs, :project_id_snapshot, project_id))
    |> put_change(:source_asset_count, get_attr(attrs, :source_asset_count))
    |> put_change(:project_snapshot_id, get_attr(attrs, :project_snapshot_id))
    |> put_change(
      :project_snapshot_id_snapshot,
      get_attr(attrs, :project_snapshot_id_snapshot, get_attr(attrs, :project_snapshot_id))
    )
  end

  defp get_attr(attrs, field, default \\ nil) do
    case fetch_attr(attrs, field) do
      {:ok, value} -> value
      :error -> default
    end
  end

  defp fetch_attr(attrs, field) do
    case Map.fetch(attrs, field) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(attrs, Atom.to_string(field))
    end
  end

  defp require_active(changeset) do
    if get_field(changeset, :status) == "active",
      do: changeset,
      else: add_error(changeset, :status, "must be active")
  end

  defp validate_common_fields(changeset) do
    changeset
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(
      :storage_namespace,
      ~r<\Aprojects/[1-9]\d*/storage-reservations/v1/(snapshot-build|linked-to-full-conversion|restore-staging|snapshot-export)/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z>
    )
    |> validate_allocated_bytes(:reserved_bytes)
    |> validate_number(:generation, greater_than: 0)
    |> validate_inclusion(:accounting_version, [1])
    |> validate_length(:idempotency_key, max: 255)
    |> validate_source_inventory()
    |> validate_expiry_after_measurement()
    |> validate_storage_namespace_identity()
    |> validate_cleanup_object_prefix()
  end

  defp validate_source_inventory(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :source_asset_count)} do
      {"linked_to_full_conversion", count} when is_integer(count) ->
        validate_number(changeset, :source_asset_count, greater_than_or_equal_to: 0)

      {"linked_to_full_conversion", _count} ->
        add_error(changeset, :source_asset_count, "can't be blank for a linked conversion")

      {_kind, nil} ->
        changeset

      {_kind, _count} ->
        add_error(changeset, :source_asset_count, "must be empty outside a linked conversion")
    end
  end

  defp validate_allocated_bytes(changeset, field) do
    case {get_field(changeset, :kind), get_field(changeset, :source_asset_count)} do
      {"linked_to_full_conversion", source_asset_count} when is_integer(source_asset_count) ->
        validate_number(changeset, field, greater_than_or_equal_to: 0)

      {"snapshot_export", _source_asset_count} when field == :reserved_bytes ->
        validate_number(changeset, field, greater_than_or_equal_to: 0)

      {_kind, _source_asset_count} ->
        validate_number(changeset, field, greater_than: 0)
    end
  end

  defp validate_storage_start_allowed(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :reserved_bytes)} do
      {"snapshot_export", 0} ->
        add_error(changeset, :storage_started_at, "cannot be set for a zero-byte export lease")

      {_kind, _reserved_bytes} ->
        changeset
    end
  end

  defp validate_storage_namespace_identity(changeset) do
    project_id = get_field(changeset, :project_id_snapshot)
    kind = get_field(changeset, :kind)
    lease_token = get_field(changeset, :lease_token)
    namespace = get_field(changeset, :storage_namespace)

    expected_namespace =
      if is_integer(project_id) and project_id > 0 and kind in @kinds and is_binary(lease_token) do
        normalized_kind = String.replace(kind, "_", "-")
        "projects/#{project_id}/storage-reservations/v1/#{normalized_kind}/#{lease_token}"
      end

    if is_binary(expected_namespace) and namespace == expected_namespace,
      do: changeset,
      else: add_error(changeset, :storage_namespace, "must match the immutable operation identity")
  end

  defp validate_cleanup_object_prefix(changeset) do
    case {get_field(changeset, :kind), get_field(changeset, :cleanup_object_prefix)} do
      {"snapshot_build", prefix} when is_binary(prefix) ->
        validate_format(
          changeset,
          :cleanup_object_prefix,
          ~r<\Aprojects/[1-9]\d*/snapshots/(?:object-sets/v1|archives/v2)/ready/[A-Za-z0-9_-]{16}\z>
        )

      {"linked_to_full_conversion", prefix} when is_binary(prefix) ->
        validate_format(
          changeset,
          :cleanup_object_prefix,
          ~r<\Aprojects/[1-9]\d*/snapshots/object-sets/v1/ready/[A-Za-z0-9_-]{16}\z>
        )

      {kind, _prefix} when kind in ["snapshot_build", "linked_to_full_conversion"] ->
        add_error(changeset, :cleanup_object_prefix, "can't be blank for an operation with a ready target")

      {kind, prefix} when kind in @kinds and kind != "snapshot_build" ->
        if prefix == get_field(changeset, :storage_namespace),
          do: changeset,
          else: add_error(changeset, :cleanup_object_prefix, "must equal the immutable temporary namespace")

      {_kind, _prefix} ->
        add_error(changeset, :cleanup_object_prefix, "must identify an owned operation namespace")
    end
  end

  defp validate_expiry_after_measurement(changeset) do
    expires_at = get_field(changeset, :expires_at)
    measured_at = get_field(changeset, :accounting_measured_at)

    if match?(%DateTime{}, expires_at) and match?(%DateTime{}, measured_at) and
         DateTime.after?(expires_at, measured_at),
       do: changeset,
       else: add_error(changeset, :expires_at, "must be after the accounting measurement")
  end

  defp validate_cleanup_reference(changeset) do
    case {get_field(changeset, :cleanup_status), get_field(changeset, :cleanup_reference)} do
      {"owned", reference} when is_binary(reference) ->
        if Regex.match?(~r/\Astorage_cleanup_request:[1-9]\d*\z/, reference) do
          changeset
        else
          add_error(changeset, :cleanup_reference, "must identify a durable cleanup request")
        end

      {"owned", _reference} ->
        add_error(changeset, :cleanup_reference, "can't be blank when cleanup is owned")

      {"not_required", reference} when is_binary(reference) ->
        expected_reference = "storage_not_started:#{get_field(changeset, :storage_namespace)}"

        if is_nil(get_field(changeset, :storage_started_at)) and reference == expected_reference,
          do: changeset,
          else: add_error(changeset, :cleanup_reference, "must prove the operation namespace was never started")

      {"not_required", _reference} ->
        add_error(changeset, :cleanup_reference, "can't be blank without a no-write proof")

      {_status, _reference} ->
        changeset
    end
  end

  defp validate_actual_within_reservation(changeset) do
    actual_bytes = get_field(changeset, :actual_bytes)
    reserved_bytes = get_field(changeset, :reserved_bytes)

    if is_integer(actual_bytes) and is_integer(reserved_bytes) and actual_bytes > reserved_bytes,
      do: add_error(changeset, :actual_bytes, "cannot exceed reserved bytes"),
      else: changeset
  end

  defp validate_extension(changeset, previous_reserved_bytes, previous_generation) do
    changeset
    |> validate_strict_increase(:reserved_bytes, previous_reserved_bytes)
    |> validate_strict_increase(:generation, previous_generation)
  end

  defp validate_strict_increase(changeset, field, previous_value) do
    current_value = get_field(changeset, field)

    if is_integer(current_value) and is_integer(previous_value) and current_value <= previous_value,
      do: add_error(changeset, field, "must increase"),
      else: changeset
  end

  defp validate_datetime_increase(changeset, field, %DateTime{} = previous_value) do
    case get_field(changeset, field) do
      %DateTime{} = current_value ->
        if DateTime.after?(current_value, previous_value),
          do: changeset,
          else: add_error(changeset, field, "must increase")

      _current_value ->
        changeset
    end
  end

  defp validate_datetime_increase(changeset, _field, _previous_value), do: changeset

  defp storage_constraints(changeset) do
    changeset
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:project_snapshot_id)
    |> unique_constraint(:storage_namespace)
    |> check_constraint(:kind, name: :workspace_storage_reservations_kind)
    |> check_constraint(:status, name: :workspace_storage_reservations_status)
    |> check_constraint(:reserved_bytes,
      name: :workspace_storage_reservations_positive_values
    )
    |> check_constraint(:source_asset_count,
      name: :workspace_storage_reservations_source_inventory
    )
    |> check_constraint(:workspace_id_snapshot,
      name: :workspace_storage_reservations_identity
    )
    |> check_constraint(:cleanup_inventory_digest,
      name: :workspace_storage_reservations_cleanup_inventory_commitment
    )
    |> check_constraint(:storage_started_at,
      name: :workspace_storage_reservations_zero_byte_snapshot_export_lease
    )
    |> check_constraint(:storage_namespace,
      name: :workspace_storage_reservations_namespace
    )
    |> check_constraint(:cleanup_object_prefix,
      name: :workspace_storage_reservations_cleanup_object_prefix
    )
    |> check_constraint(:status, name: :workspace_storage_reservations_terminal_fields)
    |> check_constraint(:cleanup_reference,
      name: :workspace_storage_reservations_cleanup_reference
    )
  end
end
