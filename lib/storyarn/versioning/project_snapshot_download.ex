defmodule Storyarn.Versioning.ProjectSnapshotDownload do
  @moduledoc """
  Authorizes one persisted snapshot archive and owns its durable download fence.

  A zero-byte `snapshot_export` reservation prevents lifecycle cleanup from
  deleting the published archive while a grant is usable. Grants for the same
  snapshot coalesce onto one generation-fenced lease. Every acquisition keeps
  that shared lease for the expiry reaper: releasing it from one request could
  invalidate a concurrent provider grant or local transfer.
  """

  alias Storyarn.Assets.Storage
  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotCrud
  alias Storyarn.Versioning.SnapshotArchiveStorage

  @archive_format_version 2
  @sha256_regex ~r/\A[0-9a-f]{64}\z/

  @type delivery :: %{
          snapshot: ProjectSnapshot.t(),
          storage_key: Storage.key(),
          size_bytes: pos_integer(),
          checksum: String.t()
        }
  @type lease_action(result) :: {:retain_lease, result} | {:release_lease, result}

  @doc """
  Revalidates and leases one scoped persisted ZIP, then yields its delivery data.

  The callback keeps the existing tagged result contract for the HTTP delivery
  boundary. Both tags retain the shared lease until bounded expiry; the tag is
  not cleanup authority because another request may already depend on the same
  lease generation.
  """
  @spec with_archive(Project.t(), pos_integer(), (delivery() -> lease_action(result))) ::
          result | {:error, term()}
        when result: term()
  def with_archive(%Project{id: project_id, deleted_at: nil} = project, snapshot_id, callback)
      when is_integer(project_id) and project_id > 0 and is_integer(snapshot_id) and snapshot_id > 0 and
             is_function(callback, 1) do
    with %ProjectSnapshot{} = snapshot <- ProjectSnapshotCrud.get_snapshot_by_id(project.id, snapshot_id),
         :ok <- validate_eligibility(snapshot),
         {:ok, delivery} <- delivery(snapshot),
         {:ok, lease} <- reserve_read_lease(project, snapshot) do
      invoke_delivery(callback, delivery, lease)
    else
      nil -> {:error, :snapshot_not_found}
      {:error, _reason} = error -> normalize_error(error)
    end
  end

  def with_archive(_project, _snapshot_id, _callback), do: {:error, :snapshot_not_found}

  defp validate_eligibility(%ProjectSnapshot{mode: "linked"}), do: {:error, :snapshot_export_linked}

  defp validate_eligibility(%ProjectSnapshot{mode: mode}) when mode != "full",
    do: {:error, {:snapshot_export_corrupt, :invalid_snapshot_mode}}

  defp validate_eligibility(%ProjectSnapshot{lifecycle_state: state}) when state != "ready",
    do: {:error, :snapshot_export_not_ready}

  defp validate_eligibility(%ProjectSnapshot{integrity_state: state}) when state != "verified",
    do: {:error, :snapshot_export_integrity_unavailable}

  defp validate_eligibility(%ProjectSnapshot{format_version: version}) when version != @archive_format_version,
    do: {:error, :snapshot_export_unsupported_format}

  defp validate_eligibility(%ProjectSnapshot{}), do: :ok

  defp delivery(%ProjectSnapshot{} = snapshot) do
    with key when is_binary(key) <- snapshot.archive_storage_key,
         true <- archive_key_for_snapshot?(snapshot, key),
         size when is_integer(size) and size > 0 <- snapshot.archive_size_bytes,
         checksum when is_binary(checksum) <- snapshot.archive_checksum,
         true <- Regex.match?(@sha256_regex, checksum) do
      {:ok,
       %{
         snapshot: snapshot,
         storage_key: key,
         size_bytes: size,
         checksum: checksum
       }}
    else
      _invalid -> {:error, {:snapshot_export_corrupt, :invalid_archive_metadata}}
    end
  end

  defp archive_key_for_snapshot?(%ProjectSnapshot{} = snapshot, key) do
    SnapshotArchiveStorage.ready_archive_key?(snapshot.project_id, snapshot.object_prefix, key)
  end

  defp reserve_read_lease(project, snapshot) do
    Billing.acquire_snapshot_export_lease(%{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id
    })
  end

  defp invoke_delivery(callback, delivery, lease) do
    delivery
    |> callback.()
    |> finish_delivery(lease)
  end

  defp finish_delivery({:retain_lease, result}, _lease), do: result
  defp finish_delivery({:release_lease, result}, _lease), do: result
  defp finish_delivery(_invalid, _lease), do: {:error, :snapshot_export_unavailable}

  defp normalize_error({:error, reason})
       when reason in [
              :snapshot_not_found,
              :snapshot_export_linked,
              :snapshot_export_not_ready,
              :snapshot_export_integrity_unavailable,
              :snapshot_export_unsupported_format
            ], do: {:error, reason}

  defp normalize_error({:error, {:snapshot_export_corrupt, _reason}} = error), do: error
  defp normalize_error({:error, _reason}), do: {:error, :snapshot_export_unavailable}
end
