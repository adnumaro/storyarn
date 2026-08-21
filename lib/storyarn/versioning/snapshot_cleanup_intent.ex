defmodule Storyarn.Versioning.SnapshotCleanupIntent do
  @moduledoc """
  Durable ownership handoff for deleting one snapshot object namespace.

  Identity and the original exact inventory are immutable. Only the remaining
  inventory and forward-only processing state may change, so project/workspace
  cascades cannot erase what storage cleanup still owns.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshot

  @statuses ~w(pending processing retrying completed terminal)
  @reasons ~w(user_delete retention expired_build abandoned_import project_hard_delete workspace_hard_delete)
  @origins ~w(user daily pre_restore post_restore)
  @v2_ready_prefix ~r|\Aprojects/[1-9]\d*/snapshots/archives/v2/ready/[A-Za-z0-9_-]{16}\z|
  @provider_namespace_pattern ~r/\A[0-9a-f]{64}\z/

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_snapshot_id: integer() | nil,
          cleanup_request_id: integer(),
          workspace_id_snapshot: integer(),
          project_id_snapshot: integer(),
          project_snapshot_id_snapshot: integer(),
          deletion_generation: pos_integer(),
          mode: String.t(),
          origin: String.t(),
          reason: String.t(),
          authority_kind: String.t(),
          authority_actor_id: integer() | nil,
          ready_prefix: String.t(),
          staging_prefix: String.t(),
          storage_keys: [String.t()],
          remaining_storage_keys: [String.t()],
          inventory_digest: String.t(),
          object_count: pos_integer(),
          estimated_cleanup_bytes: non_neg_integer(),
          status: String.t(),
          retry_count: non_neg_integer(),
          required_delete_passes: pos_integer(),
          completed_delete_passes: non_neg_integer(),
          processing_generation: non_neg_integer(),
          provider_namespace_fingerprint: String.t(),
          next_delete_pass_at: DateTime.t() | nil,
          last_error_code: String.t() | nil,
          requested_at: DateTime.t(),
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          terminal_at: DateTime.t() | nil
        }

  schema "snapshot_cleanup_intents" do
    field :workspace_id_snapshot, :integer
    field :project_id_snapshot, :integer
    field :project_snapshot_id_snapshot, :integer
    field :deletion_generation, :integer
    field :mode, :string
    field :origin, :string
    field :reason, :string
    field :authority_kind, :string
    field :authority_actor_id, :integer
    field :ready_prefix, :string
    field :staging_prefix, :string
    field :storage_keys, {:array, :string}, default: []
    field :remaining_storage_keys, {:array, :string}, default: []
    field :inventory_digest, :string
    field :object_count, :integer
    field :estimated_cleanup_bytes, :integer
    field :status, :string
    field :retry_count, :integer, default: 0
    field :required_delete_passes, :integer, default: 1
    field :completed_delete_passes, :integer, default: 0
    field :processing_generation, :integer, default: 0
    field :provider_namespace_fingerprint, :string
    field :next_delete_pass_at, :utc_datetime
    field :last_error_code, :string
    field :requested_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime
    field :terminal_at, :utc_datetime

    belongs_to :project_snapshot, ProjectSnapshot
    belongs_to :cleanup_request, StorageCleanupRequest

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(intent, attrs) do
    attrs =
      attrs
      |> Map.put_new(:status, "pending")
      |> Map.put_new(:retry_count, 0)
      |> Map.put_new(:processing_generation, 0)
      |> Map.put_new(:requested_at, TimeHelpers.now())
      |> put_delete_pass_policy()
      |> put_remaining_inventory()

    intent
    |> cast(attrs, [
      :project_snapshot_id,
      :cleanup_request_id,
      :workspace_id_snapshot,
      :project_id_snapshot,
      :project_snapshot_id_snapshot,
      :deletion_generation,
      :mode,
      :origin,
      :reason,
      :authority_kind,
      :authority_actor_id,
      :ready_prefix,
      :staging_prefix,
      :storage_keys,
      :remaining_storage_keys,
      :inventory_digest,
      :object_count,
      :estimated_cleanup_bytes,
      :status,
      :retry_count,
      :required_delete_passes,
      :completed_delete_passes,
      :processing_generation,
      :provider_namespace_fingerprint,
      :next_delete_pass_at,
      :requested_at
    ])
    |> validate_required([
      :project_snapshot_id,
      :cleanup_request_id,
      :workspace_id_snapshot,
      :project_id_snapshot,
      :project_snapshot_id_snapshot,
      :deletion_generation,
      :mode,
      :origin,
      :reason,
      :authority_kind,
      :ready_prefix,
      :staging_prefix,
      :storage_keys,
      :remaining_storage_keys,
      :inventory_digest,
      :object_count,
      :estimated_cleanup_bytes,
      :status,
      :retry_count,
      :required_delete_passes,
      :completed_delete_passes,
      :processing_generation,
      :provider_namespace_fingerprint,
      :requested_at
    ])
    |> validate_inclusion(:mode, ["full"])
    |> validate_inclusion(:origin, @origins)
    |> validate_inclusion(:reason, @reasons)
    |> validate_inclusion(:authority_kind, ["user", "system"])
    |> validate_inclusion(:status, ["pending"])
    |> validate_number(:workspace_id_snapshot, greater_than: 0)
    |> validate_number(:project_id_snapshot, greater_than: 0)
    |> validate_number(:project_snapshot_id_snapshot, greater_than: 0)
    |> validate_number(:deletion_generation, greater_than: 0)
    |> validate_number(:object_count, greater_than: 0)
    |> validate_number(:estimated_cleanup_bytes, greater_than_or_equal_to: 0)
    |> validate_number(:retry_count, equal_to: 0)
    |> validate_number(:completed_delete_passes, equal_to: 0)
    |> validate_number(:processing_generation, equal_to: 0)
    |> validate_format(:provider_namespace_fingerprint, @provider_namespace_pattern)
    |> validate_delete_pass_policy()
    |> validate_authority()
    |> validate_inventory()
    |> foreign_key_constraint(:project_snapshot_id)
    |> foreign_key_constraint(:cleanup_request_id)
    |> unique_constraint(:project_snapshot_id_snapshot)
    |> unique_constraint(:cleanup_request_id)
    |> check_constraint(:status, name: :snapshot_cleanup_intents_identity)
    |> check_constraint(:provider_namespace_fingerprint,
      name: :snapshot_cleanup_intents_provider_namespace
    )
  end

  @doc false
  def processing_changeset(%__MODULE__{} = intent, now \\ TimeHelpers.now()) do
    intent
    |> change(
      status: "processing",
      processing_generation: intent.processing_generation + 1,
      started_at: intent.started_at || now,
      last_error_code: nil
    )
    |> state_constraints()
  end

  @doc false
  def retry_changeset(%__MODULE__{} = intent, remaining_keys, error_code, now \\ TimeHelpers.now()) do
    intent
    |> change(
      status: "retrying",
      remaining_storage_keys: remaining_keys,
      retry_count: intent.retry_count + 1,
      last_error_code: error_code,
      started_at: intent.started_at || now
    )
    |> validate_remaining_inventory(intent)
    |> state_constraints()
  end

  @doc false
  def progress_changeset(%__MODULE__{} = intent, remaining_keys) do
    intent
    |> change(status: "retrying", remaining_storage_keys: remaining_keys)
    |> validate_remaining_inventory(intent)
    |> state_constraints()
  end

  @doc false
  def completed_changeset(%__MODULE__{} = intent, now \\ TimeHelpers.now()) do
    intent
    |> change(
      status: "completed",
      remaining_storage_keys: [],
      completed_delete_passes: intent.required_delete_passes,
      last_error_code: nil,
      completed_at: now,
      terminal_at: nil
    )
    |> state_constraints()
  end

  @doc false
  def next_delete_pass_changeset(%__MODULE__{} = intent) do
    intent
    |> change(
      status: "retrying",
      remaining_storage_keys: intent.storage_keys,
      completed_delete_passes: intent.completed_delete_passes + 1,
      # The database trigger replaces this marker with its own clock-derived
      # boundary. Application time is never the quarantine authority.
      next_delete_pass_at: TimeHelpers.now(),
      last_error_code: nil
    )
    |> validate_remaining_inventory(intent)
    |> state_constraints()
  end

  @doc false
  def terminal_changeset(%__MODULE__{} = intent, remaining_keys, error_code, now \\ TimeHelpers.now()) do
    intent
    |> change(
      status: "terminal",
      remaining_storage_keys: remaining_keys,
      retry_count: intent.retry_count + 1,
      last_error_code: error_code,
      terminal_at: now
    )
    |> validate_remaining_inventory(intent)
    |> state_constraints()
  end

  @doc false
  def terminal_predelete_changeset(%__MODULE__{} = intent, error_code, now \\ TimeHelpers.now()) do
    intent
    |> change(
      status: "terminal",
      retry_count: intent.retry_count + 1,
      last_error_code: error_code,
      started_at: intent.started_at || now,
      completed_at: nil,
      terminal_at: now
    )
    |> state_constraints()
  end

  @doc false
  @spec validate_persisted_inventory(t()) :: :ok | {:error, :invalid_snapshot_cleanup_inventory}
  def validate_persisted_inventory(%__MODULE__{} = intent) do
    valid? =
      valid_original_inventory?(
        intent.storage_keys,
        intent.object_count,
        intent.ready_prefix,
        intent.staging_prefix,
        intent.inventory_digest
      ) and
        valid_remaining_inventory?(intent.remaining_storage_keys, intent.storage_keys) and
        valid_remaining_state?(intent.status, intent.remaining_storage_keys) and
        valid_delete_pass_state?(intent) and
        is_integer(intent.processing_generation) and intent.processing_generation >= 0 and
        is_binary(intent.provider_namespace_fingerprint) and
        Regex.match?(@provider_namespace_pattern, intent.provider_namespace_fingerprint)

    if valid?, do: :ok, else: {:error, :invalid_snapshot_cleanup_inventory}
  end

  defp put_remaining_inventory(attrs) do
    if Map.has_key?(attrs, :remaining_storage_keys) or Map.has_key?(attrs, "remaining_storage_keys") do
      attrs
    else
      storage_keys = Map.get(attrs, :storage_keys, Map.get(attrs, "storage_keys", []))
      Map.put(attrs, :remaining_storage_keys, storage_keys)
    end
  end

  defp put_delete_pass_policy(attrs) do
    reason = Map.get(attrs, :reason, Map.get(attrs, "reason"))
    required_delete_passes = if reason == "expired_build", do: 2, else: 1

    attrs
    |> Map.put_new(:required_delete_passes, required_delete_passes)
    |> Map.put_new(:completed_delete_passes, 0)
  end

  defp validate_authority(changeset) do
    case {get_field(changeset, :authority_kind), get_field(changeset, :authority_actor_id)} do
      {"user", actor_id} when is_integer(actor_id) and actor_id > 0 -> changeset
      {"system", nil} -> changeset
      _invalid -> add_error(changeset, :authority_kind, "does not prove a scoped actor")
    end
  end

  defp validate_delete_pass_policy(changeset) do
    reason = get_field(changeset, :reason)
    required_delete_passes = get_field(changeset, :required_delete_passes)
    expected_delete_passes = if reason == "expired_build", do: 2, else: 1

    if required_delete_passes == expected_delete_passes,
      do: changeset,
      else: add_error(changeset, :required_delete_passes, "does not match the cleanup reason")
  end

  defp validate_inventory(changeset) do
    keys = get_field(changeset, :storage_keys)
    remaining = get_field(changeset, :remaining_storage_keys)
    count = get_field(changeset, :object_count)
    ready_prefix = get_field(changeset, :ready_prefix)
    staging_prefix = get_field(changeset, :staging_prefix)
    digest = get_field(changeset, :inventory_digest)

    valid? =
      valid_original_inventory?(keys, count, ready_prefix, staging_prefix, digest) and
        remaining == keys

    if valid?, do: changeset, else: add_error(changeset, :storage_keys, "is not an exact canonical inventory")
  end

  defp validate_remaining_inventory(changeset, intent) do
    remaining = get_field(changeset, :remaining_storage_keys)

    if valid_remaining_inventory?(remaining, intent.storage_keys),
      do: changeset,
      else: add_error(changeset, :remaining_storage_keys, "can only shrink within the original inventory")
  end

  defp valid_original_inventory?(keys, count, ready_prefix, staging_prefix, digest) do
    is_list(keys) and keys != [] and Enum.all?(keys, &(is_binary(&1) and String.valid?(&1))) and
      keys == Enum.uniq(keys) and count == length(keys) and
      valid_prefix_pair?(ready_prefix, staging_prefix) and
      valid_storage_keys?(keys, ready_prefix, staging_prefix) and
      digest == inventory_digest(keys)
  end

  defp valid_remaining_inventory?(remaining, original_keys) do
    if is_list(remaining) and is_list(original_keys) do
      original = MapSet.new(original_keys)

      remaining == Enum.uniq(remaining) and
        Enum.all?(remaining, &(is_binary(&1) and String.valid?(&1) and MapSet.member?(original, &1)))
    else
      false
    end
  end

  defp valid_remaining_state?("completed", remaining), do: remaining == []
  defp valid_remaining_state?(status, remaining) when status in @statuses, do: remaining != []
  defp valid_remaining_state?(_status, _remaining), do: false

  defp valid_delete_pass_state?(intent) do
    required = if intent.reason == "expired_build", do: 2, else: 1

    intent.required_delete_passes == required and
      is_integer(intent.completed_delete_passes) and
      intent.completed_delete_passes >= 0 and
      intent.completed_delete_passes <= required and
      valid_delete_pass_status?(
        intent.status,
        intent.completed_delete_passes,
        required,
        intent.next_delete_pass_at
      )
  end

  defp valid_delete_pass_status?("completed", completed, required, _next_at), do: completed == required

  defp valid_delete_pass_status?(status, completed, required, next_at) when status in @statuses do
    completed < required and
      if(completed == 0, do: is_nil(next_at), else: match?(%DateTime{}, next_at))
  end

  defp valid_delete_pass_status?(_status, _completed, _required, _next_at), do: false

  defp valid_prefix_pair?(ready_prefix, staging_prefix) do
    is_binary(ready_prefix) and is_binary(staging_prefix) and
      Storage.canonical_key?(ready_prefix) and Storage.canonical_key?(staging_prefix) and
      ready_prefix != staging_prefix and
      String.replace(ready_prefix, "/ready/", "/staging/", global: false) == staging_prefix and
      Regex.match?(@v2_ready_prefix, ready_prefix)
  end

  defp valid_storage_keys?(keys, ready_prefix, staging_prefix) do
    grouped = Enum.group_by(keys, &key_prefix(&1, ready_prefix, staging_prefix))
    ready_paths = relative_paths(grouped[:ready] || [], ready_prefix)
    staging_paths = relative_paths(grouped[:staging] || [], staging_prefix)

    valid_storage_path_pair?(grouped, ready_paths, staging_paths) and
      valid_storage_paths_for_prefix?(ready_prefix, ready_paths)
  end

  defp valid_storage_path_pair?(grouped, ready_paths, staging_paths) do
    (grouped[:invalid] || []) == [] and ready_paths != [] and
      MapSet.new(ready_paths) == MapSet.new(staging_paths)
  end

  defp valid_storage_paths_for_prefix?(ready_prefix, ready_paths) do
    Regex.match?(@v2_ready_prefix, ready_prefix) and valid_v2_storage_paths?(ready_paths)
  end

  defp valid_v2_storage_paths?(paths), do: MapSet.new(paths) == MapSet.new(["manifest.json", "snapshot.zip"])

  defp key_prefix(key, ready_prefix, staging_prefix) when is_binary(key) do
    cond do
      String.starts_with?(key, ready_prefix <> "/") -> :ready
      String.starts_with?(key, staging_prefix <> "/") -> :staging
      true -> :invalid
    end
  end

  defp key_prefix(_key, _ready_prefix, _staging_prefix), do: :invalid

  defp relative_paths(keys, prefix), do: Enum.map(keys, &String.replace_prefix(&1, prefix <> "/", ""))

  defp inventory_digest(keys) do
    keys
    |> Enum.sort()
    |> Enum.map_join(fn key -> "#{byte_size(key)}:#{key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp state_constraints(changeset) do
    changeset
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:retry_count, greater_than_or_equal_to: 0)
    |> validate_number(:required_delete_passes, greater_than_or_equal_to: 1, less_than_or_equal_to: 2)
    |> validate_number(:completed_delete_passes,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: get_field(changeset, :required_delete_passes)
    )
    |> validate_number(:processing_generation, greater_than_or_equal_to: 0)
    |> check_constraint(:status, name: :snapshot_cleanup_intents_identity)
  end
end
