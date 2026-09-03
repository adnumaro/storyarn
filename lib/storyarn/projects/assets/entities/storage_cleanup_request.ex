defmodule Storyarn.Projects.Assets.StorageCleanupRequest do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Assets.StorageCleanupMultipartUpload

  @provider_namespace_pattern ~r/\A[0-9a-f]{64}\z/
  @multipart_cleanup_phases ~w(
    discover
    abort
    delete
    quiet
    verify_inventory
    verify_references
    verify_objects
    verify_final_inventory
    confirmed
    blocked
  )
  @multipart_error_code_pattern ~r/\A[a-z][a-z0-9_]*\z/
  @legacy_unbound_error "legacy_multipart_identity_unbound"
  @max_storage_keys 30_001
  @multipart_internal_fields [
    :multipart_cleanup_phase,
    :multipart_cleanup_generation,
    :multipart_cleanup_cursor,
    :multipart_cleanup_residue_count,
    :multipart_cleanup_inventory_complete,
    :multipart_quiescence_started_at,
    :multipart_quiescence_not_before,
    :multipart_cleanup_claim_token,
    :multipart_cleanup_claim_expires_at,
    :multipart_cleanup_failure_count,
    :multipart_cleanup_next_attempt_at,
    :multipart_cleanup_last_error_code
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          storage_keys: [String.t()],
          owner_kind: String.t(),
          owner_token: Ecto.UUID.t() | nil,
          provider_namespace_fingerprint: String.t() | nil,
          multipart_quiescence_started_at: DateTime.t() | nil,
          multipart_quiescence_not_before: DateTime.t() | nil,
          multipart_cleanup_phase: String.t() | nil,
          multipart_cleanup_generation: non_neg_integer(),
          multipart_cleanup_cursor: non_neg_integer(),
          multipart_cleanup_residue_count: non_neg_integer(),
          multipart_cleanup_inventory_complete: boolean(),
          multipart_cleanup_claim_token: Ecto.UUID.t() | nil,
          multipart_cleanup_claim_expires_at: DateTime.t() | nil,
          multipart_cleanup_failure_count: non_neg_integer(),
          multipart_cleanup_next_attempt_at: DateTime.t() | nil,
          multipart_cleanup_last_error_code: String.t() | nil,
          multipart_uploads:
            [StorageCleanupMultipartUpload.t()]
            | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "storage_cleanup_requests" do
    field :storage_keys, {:array, :string}, default: []
    field :owner_kind, :string, default: "storage_compensation"
    field :owner_token, Ecto.UUID
    field :provider_namespace_fingerprint, :string
    field :multipart_quiescence_started_at, :utc_datetime
    field :multipart_quiescence_not_before, :utc_datetime
    field :multipart_cleanup_phase, :string
    field :multipart_cleanup_generation, :integer, default: 0
    field :multipart_cleanup_cursor, :integer, default: 0
    field :multipart_cleanup_residue_count, :integer, default: 0
    field :multipart_cleanup_inventory_complete, :boolean, default: false
    field :multipart_cleanup_claim_token, Ecto.UUID
    field :multipart_cleanup_claim_expires_at, :utc_datetime
    field :multipart_cleanup_failure_count, :integer, default: 0
    field :multipart_cleanup_next_attempt_at, :utc_datetime
    field :multipart_cleanup_last_error_code, :string

    has_many :multipart_uploads, StorageCleanupMultipartUpload, foreign_key: :cleanup_request_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(request, attrs) do
    request
    |> cast(attrs, [:storage_keys, :owner_kind, :owner_token, :provider_namespace_fingerprint])
    |> put_multipart_internal_fields(attrs)
    |> validate_required([
      :storage_keys,
      :owner_kind,
      :multipart_cleanup_generation,
      :multipart_cleanup_cursor,
      :multipart_cleanup_residue_count,
      :multipart_cleanup_inventory_complete,
      :multipart_cleanup_failure_count
    ])
    |> validate_length(:storage_keys, min: 1, max: @max_storage_keys)
    |> validate_inclusion(:owner_kind, ["storage_compensation", "snapshot_lifecycle"])
    |> validate_format(:provider_namespace_fingerprint, @provider_namespace_pattern)
    |> validate_multipart_cleanup()
    |> validate_owner()
    |> unique_constraint(:owner_token)
    |> unique_constraint(:multipart_cleanup_claim_token,
      name: :storage_cleanup_requests_multipart_claim_idx
    )
    |> check_constraint(:owner_kind, name: :storage_cleanup_requests_owner)
    |> check_constraint(:provider_namespace_fingerprint,
      name: :storage_cleanup_requests_provider_namespace
    )
    |> check_constraint(:multipart_quiescence_not_before,
      name: :storage_cleanup_requests_multipart_quiescence
    )
    |> check_constraint(:storage_keys, name: :storage_cleanup_requests_keys_bounded)
    |> multipart_cleanup_constraints()
  end

  @doc false
  def multipart_cleanup_changeset(request, attrs) when is_map(attrs) do
    request
    |> change()
    |> put_multipart_internal_fields(attrs)
    |> validate_required([
      :multipart_cleanup_generation,
      :multipart_cleanup_cursor,
      :multipart_cleanup_residue_count,
      :multipart_cleanup_inventory_complete,
      :multipart_cleanup_failure_count
    ])
    |> validate_format(:provider_namespace_fingerprint, @provider_namespace_pattern)
    |> validate_multipart_cleanup()
    |> validate_owner()
    |> unique_constraint(:multipart_cleanup_claim_token,
      name: :storage_cleanup_requests_multipart_claim_idx
    )
    |> multipart_cleanup_constraints()
  end

  @doc false
  def multipart_quiescence_changeset(request, started_at, not_before) do
    request
    |> change(
      multipart_quiescence_started_at: started_at,
      multipart_quiescence_not_before: not_before
    )
    |> validate_multipart_quiescence()
    |> check_constraint(:multipart_quiescence_not_before,
      name: :storage_cleanup_requests_multipart_quiescence
    )
  end

  defp validate_owner(changeset) do
    ownership =
      {
        get_field(changeset, :owner_kind),
        get_field(changeset, :owner_token),
        get_field(changeset, :provider_namespace_fingerprint),
        get_field(changeset, :multipart_cleanup_phase),
        get_field(changeset, :multipart_cleanup_last_error_code)
      }

    if valid_owner?(ownership),
      do: changeset,
      else: add_error(changeset, :owner_kind, "does not match its ownership token")
  end

  defp valid_owner?({"storage_compensation", nil, nil, nil, nil}), do: true

  defp valid_owner?({"storage_compensation", nil, fingerprint, phase, _error_code})
       when is_binary(fingerprint) and phase in @multipart_cleanup_phases, do: true

  defp valid_owner?({"storage_compensation", nil, nil, "blocked", @legacy_unbound_error}), do: true

  defp valid_owner?({"snapshot_lifecycle", token, fingerprint, nil, _error_code})
       when is_binary(token) and is_binary(fingerprint), do: true

  defp valid_owner?({"snapshot_lifecycle", token, fingerprint, phase, _error_code})
       when is_binary(token) and is_binary(fingerprint) and phase in @multipart_cleanup_phases, do: true

  defp valid_owner?(_ownership), do: false

  defp put_multipart_internal_fields(changeset, attrs) do
    Enum.reduce(@multipart_internal_fields, changeset, fn field, changeset ->
      case Map.fetch(attrs, field) do
        {:ok, value} -> put_change(changeset, field, value)
        :error -> changeset
      end
    end)
  end

  defp validate_multipart_cleanup(changeset) do
    changeset
    |> validate_inclusion(:multipart_cleanup_phase, @multipart_cleanup_phases)
    |> validate_number(:multipart_cleanup_generation, greater_than_or_equal_to: 0)
    |> validate_number(:multipart_cleanup_cursor, greater_than_or_equal_to: 0)
    |> validate_number(:multipart_cleanup_residue_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1000
    )
    |> validate_number(:multipart_cleanup_failure_count,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 1000
    )
    |> validate_length(:multipart_cleanup_last_error_code, count: :bytes, max: 100)
    |> validate_format(:multipart_cleanup_last_error_code, @multipart_error_code_pattern)
    |> validate_multipart_claim()
    |> validate_multipart_quiescence()
    |> validate_multipart_phase()
  end

  defp validate_multipart_claim(changeset) do
    case {
      get_field(changeset, :multipart_cleanup_claim_token),
      get_field(changeset, :multipart_cleanup_claim_expires_at)
    } do
      {nil, nil} -> changeset
      {token, %DateTime{}} when is_binary(token) -> changeset
      _partial -> add_error(changeset, :multipart_cleanup_claim_expires_at, "must be paired with its token")
    end
  end

  defp validate_multipart_phase(changeset) do
    state = %{
      phase: get_field(changeset, :multipart_cleanup_phase),
      generation: get_field(changeset, :multipart_cleanup_generation),
      cursor: get_field(changeset, :multipart_cleanup_cursor),
      residue_count: get_field(changeset, :multipart_cleanup_residue_count),
      inventory_complete?: get_field(changeset, :multipart_cleanup_inventory_complete),
      failure_count: get_field(changeset, :multipart_cleanup_failure_count),
      claim_token: get_field(changeset, :multipart_cleanup_claim_token),
      claim_expires_at: get_field(changeset, :multipart_cleanup_claim_expires_at),
      next_attempt_at: get_field(changeset, :multipart_cleanup_next_attempt_at),
      error_code: get_field(changeset, :multipart_cleanup_last_error_code),
      fingerprint: get_field(changeset, :provider_namespace_fingerprint)
    }

    if valid_multipart_phase?(state),
      do: changeset,
      else: add_error(changeset, :multipart_cleanup_phase, "has invalid durable state")
  end

  defp valid_multipart_phase?(%{
         phase: nil,
         generation: 0,
         cursor: 0,
         residue_count: 0,
         inventory_complete?: false,
         failure_count: 0,
         claim_token: nil,
         claim_expires_at: nil,
         next_attempt_at: nil,
         error_code: nil
       }), do: true

  defp valid_multipart_phase?(%{phase: phase, fingerprint: fingerprint})
       when phase in [
              "discover",
              "abort",
              "delete",
              "verify_inventory",
              "verify_references",
              "verify_objects",
              "verify_final_inventory"
            ] and is_binary(fingerprint), do: true

  defp valid_multipart_phase?(%{phase: "quiet", inventory_complete?: true, fingerprint: fingerprint})
       when is_binary(fingerprint), do: true

  defp valid_multipart_phase?(%{
         phase: "confirmed",
         inventory_complete?: true,
         fingerprint: fingerprint,
         claim_token: nil,
         claim_expires_at: nil,
         next_attempt_at: nil
       })
       when is_binary(fingerprint), do: true

  defp valid_multipart_phase?(%{
         phase: "blocked",
         error_code: error_code,
         claim_token: nil,
         claim_expires_at: nil,
         next_attempt_at: nil
       })
       when is_binary(error_code), do: true

  defp valid_multipart_phase?(_state), do: false

  defp multipart_cleanup_constraints(changeset) do
    changeset
    |> check_constraint(:multipart_cleanup_phase,
      name: :storage_cleanup_requests_multipart_state
    )
    |> check_constraint(:multipart_cleanup_claim_expires_at,
      name: :storage_cleanup_requests_multipart_claim
    )
    |> check_constraint(:multipart_cleanup_last_error_code,
      name: :storage_cleanup_requests_multipart_error
    )
    |> check_constraint(:provider_namespace_fingerprint,
      name: :storage_cleanup_requests_provider_namespace
    )
  end

  defp validate_multipart_quiescence(changeset) do
    started_at = get_field(changeset, :multipart_quiescence_started_at)
    not_before = get_field(changeset, :multipart_quiescence_not_before)

    case {started_at, not_before} do
      {nil, nil} ->
        changeset

      {%DateTime{} = started_at, %DateTime{} = not_before} ->
        if DateTime.compare(not_before, started_at) in [:eq, :gt],
          do: changeset,
          else: add_error(changeset, :multipart_quiescence_not_before, "must not precede its start")

      _partial ->
        add_error(changeset, :multipart_quiescence_not_before, "must be paired with its start")
    end
  end
end
