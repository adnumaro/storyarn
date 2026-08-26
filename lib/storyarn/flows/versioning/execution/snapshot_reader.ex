defmodule Storyarn.Flows.Versioning.Execution.SnapshotReader do
  @moduledoc false

  alias Storyarn.Flows.Flow
  alias Storyarn.Flows.Versioning.EntityVersionRecord
  alias Storyarn.Flows.Versioning.FlowSnapshot
  alias Storyarn.Flows.Versioning.SnapshotStorage
  alias Storyarn.Repo

  @entity_type "flow"

  @spec load_version_snapshot(map()) :: {:ok, map()} | {:error, term()}
  def load_version_snapshot(%{
        id: id,
        entity_type: @entity_type,
        entity_id: entity_id,
        project_id: project_id,
        version_number: version_number
      }) do
    case Repo.get_by(EntityVersionRecord,
           id: id,
           entity_type: @entity_type,
           entity_id: entity_id,
           project_id: project_id,
           version_number: version_number
         ) do
      %EntityVersionRecord{} = persisted ->
        with {:ok, snapshot, _checksum} <- load_verified_version(persisted) do
          {:ok, snapshot}
        end

      nil ->
        {:error, :entity_version_not_found}
    end
  end

  def load_version_snapshot(_version), do: {:error, :entity_version_not_found}

  @doc false
  @spec load_verified_version(EntityVersionRecord.t()) ::
          {:ok, map(), String.t()} | {:error, term()}
  def load_verified_version(%EntityVersionRecord{} = version) do
    with :ok <- validate_storage_key(version) do
      load_verified(version)
    end
  end

  @doc false
  @spec validate_storage_key(EntityVersionRecord.t()) ::
          :ok | {:error, :entity_version_storage_key_mismatch}
  def validate_storage_key(%EntityVersionRecord{} = version) do
    if SnapshotStorage.entity_key?(
         version.storage_key,
         version.project_id,
         version.entity_id,
         version.version_number
       ) do
      :ok
    else
      {:error, :entity_version_storage_key_mismatch}
    end
  end

  @doc false
  def get_builder!(@entity_type), do: FlowSnapshot

  def get_builder!(entity_type), do: raise(ArgumentError, "unknown Flow version entity type: #{inspect(entity_type)}")

  @doc false
  def build_snapshot(%Flow{} = flow), do: FlowSnapshot.build(flow)

  @doc false
  def snapshot_has_changes?(previous, current), do: FlowSnapshot.diff(previous, current) != []

  @doc false
  def snapshot_has_changes?(@entity_type, previous, current), do: FlowSnapshot.diff(previous, current) != []

  def snapshot_has_changes?(_entity_type, _previous, _current), do: false

  defp load_verified(version) do
    SnapshotStorage.load_verified(
      version.storage_key,
      version.snapshot_size_bytes,
      version.checksum
    )
  end
end
