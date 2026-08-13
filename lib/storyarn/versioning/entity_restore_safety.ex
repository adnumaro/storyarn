defmodule Storyarn.Versioning.EntityRestoreSafety do
  @moduledoc """
  Shared safety checks for in-place entity version restores.

  The restore entrypoint persists a pre-restore version before dispatching to a
  builder. Builders use this module, under their restore locks, to prove that
  the durable row still has the exact identity they received and that the
  locked entity still matches the pre-restore snapshot.
  """

  import Ecto.Query, warn: false

  alias Storyarn.Versioning.EntityVersion

  @doc false
  def lock_pre_restore_version(repo, entity_type, entity, user_id, opts) do
    case Keyword.fetch(opts, :pre_restore_version_identity) do
      {:ok, identity} ->
        lock_and_verify_pre_restore_version(
          repo,
          entity_type,
          entity,
          user_id,
          identity
        )

      :error ->
        # Product restores always supply this identity. It remains optional at
        # this internal builder boundary for isolated materialization tests and
        # trusted migrations.
        {:ok, :not_required}
    end
  end

  @doc false
  def verify_pre_restore_baseline(entity_type, entity, opts, build_snapshot, changed_reason) do
    case Keyword.get(opts, :restore_action) do
      {:entity_version_restore, ^entity_type} ->
        verify_entity_version_restore_baseline(
          entity,
          opts,
          build_snapshot,
          changed_reason
        )

      _other_restore_action ->
        # Full-project restore verifies its canonical project-wide safety
        # snapshot before dispatching individual entity builders.
        :ok
    end
  end

  defp lock_and_verify_pre_restore_version(repo, entity_type, entity, user_id, identity) do
    with :ok <- ensure_valid_pre_restore_version_identity(entity_type, entity, user_id, identity),
         {:ok, version} <- fetch_locked_pre_restore_version(repo, entity_type, entity, identity),
         :ok <- ensure_pre_restore_version_identity(version, identity) do
      {:ok, version}
    end
  end

  defp ensure_valid_pre_restore_version_identity(entity_type, entity, user_id, identity) do
    if valid_pre_restore_version_identity?(entity_type, entity, user_id, identity),
      do: :ok,
      else: {:error, :invalid_pre_restore_version_identity}
  end

  defp fetch_locked_pre_restore_version(repo, entity_type, entity, identity) do
    version =
      repo.one(
        from(candidate in EntityVersion,
          where:
            candidate.id == ^identity.id and
              candidate.entity_type == ^entity_type and
              candidate.entity_id == ^entity.id and
              candidate.project_id == ^entity.project_id,
          lock: "FOR SHARE"
        )
      )

    if version,
      do: {:ok, version},
      else: {:error, :pre_restore_version_not_durable}
  end

  defp ensure_pre_restore_version_identity(version, identity) do
    if entity_version_identity(version) == identity,
      do: :ok,
      else: {:error, :pre_restore_version_identity_mismatch}
  end

  defp valid_pre_restore_version_identity?(entity_type, entity, user_id, %{
         id: version_id,
         entity_type: identity_entity_type,
         entity_id: entity_id,
         project_id: project_id,
         created_by_id: identity_user_id,
         version_number: version_number,
         storage_key: storage_key,
         snapshot_size_bytes: snapshot_size_bytes,
         checksum: checksum
       }) do
    identity_entity_type == entity_type and
      entity_id == entity.id and
      project_id == entity.project_id and
      identity_user_id == user_id and
      valid_pre_restore_version_metadata?(
        version_id,
        version_number,
        storage_key,
        snapshot_size_bytes,
        checksum
      )
  end

  defp valid_pre_restore_version_identity?(_entity_type, _entity, _user_id, _identity), do: false

  defp valid_pre_restore_version_metadata?(version_id, version_number, storage_key, snapshot_size_bytes, checksum) do
    is_integer(version_id) and version_id > 0 and is_integer(version_number) and
      version_number > 0 and is_binary(storage_key) and
      is_integer(snapshot_size_bytes) and snapshot_size_bytes >= 0 and
      is_binary(checksum)
  end

  defp entity_version_identity(%EntityVersion{} = version) do
    %{
      id: version.id,
      entity_type: version.entity_type,
      entity_id: version.entity_id,
      project_id: version.project_id,
      created_by_id: version.created_by_id,
      version_number: version.version_number,
      storage_key: version.storage_key,
      snapshot_size_bytes: version.snapshot_size_bytes,
      checksum: version.checksum
    }
  end

  defp verify_entity_version_restore_baseline(entity, opts, build_snapshot, changed_reason) do
    case Keyword.fetch(opts, :pre_restore_snapshot) do
      {:ok, pre_restore_snapshot} when is_map(pre_restore_snapshot) ->
        safely_compare_pre_restore_baseline(
          entity,
          pre_restore_snapshot,
          build_snapshot,
          changed_reason
        )

      {:ok, _invalid_snapshot} ->
        {:error, :invalid_pre_restore_snapshot}

      :error ->
        :ok
    end
  end

  defp safely_compare_pre_restore_baseline(entity, pre_restore_snapshot, build_snapshot, changed_reason) do
    current_snapshot = entity |> build_snapshot.() |> normalize_snapshot!()
    pre_restore_snapshot = normalize_snapshot!(pre_restore_snapshot)

    if current_snapshot == pre_restore_snapshot,
      do: :ok,
      else: {:error, changed_reason}
  rescue
    error in ArgumentError ->
      {:error, {:pre_restore_snapshot_validation_failed, Exception.message(error)}}
  end

  defp normalize_snapshot!(snapshot) do
    snapshot
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
