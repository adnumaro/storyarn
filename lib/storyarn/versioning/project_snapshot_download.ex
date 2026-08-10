defmodule Storyarn.Versioning.ProjectSnapshotDownload do
  @moduledoc """
  Owns the short-lived lifecycle fence for one direct snapshot ZIP download.

  The ZIP itself is never persisted. A zero-byte `snapshot_export` reservation
  acts only as a durable read lease, so snapshot deletion cannot hand the
  canonical object set to cleanup while the request is verifying or streaming
  it. The lease is renewed before expiry and released with an exact no-write
  proof on every normal, error, and client-disconnect path.
  """

  alias Storyarn.Billing
  alias Storyarn.Projects.Project
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.ProjectSnapshotCrud
  alias Storyarn.Versioning.ProjectSnapshotZip

  require Logger

  @renewal_safety_seconds 3 * 60 * 60

  @doc """
  Revalidates and leases one scoped snapshot, then yields its preflighted ZIP.

  The callback result is returned unchanged. No response bytes should be sent
  until this function invokes the callback, because ZIP preparation performs
  the complete physical integrity preflight first.
  """
  @spec with_zip(pos_integer(), pos_integer(), (map() -> result)) :: result | {:error, term()}
        when result: term()
  def with_zip(project_id, snapshot_id, callback)
      when is_integer(project_id) and project_id > 0 and is_integer(snapshot_id) and snapshot_id > 0 and
             is_function(callback, 1) do
    with %ProjectSnapshot{} = snapshot <- ProjectSnapshotCrud.get_snapshot_by_id(project_id, snapshot_id),
         :ok <- validate_downloadable(snapshot),
         %Project{} = project <- Repo.get(Project, project_id),
         {:ok, lease} <- reserve_read_lease(project, snapshot) do
      with_lease(lease, &prepare_and_deliver(snapshot, &1, callback))
    else
      nil -> {:error, :snapshot_not_found}
      {:error, _reason} = error -> normalize_error(error)
    end
  end

  def with_zip(_project_id, _snapshot_id, _callback), do: {:error, :snapshot_not_found}

  defp validate_downloadable(%ProjectSnapshot{format_version: version}) when version != 1,
    do: {:error, :snapshot_export_unsupported_format}

  defp validate_downloadable(%ProjectSnapshot{mode: "linked"}), do: {:error, :snapshot_export_linked}

  defp validate_downloadable(%ProjectSnapshot{mode: mode}) when mode != "full",
    do: {:error, :snapshot_export_unsupported_format}

  defp validate_downloadable(%ProjectSnapshot{lifecycle_state: state}) when state != "ready",
    do: {:error, :snapshot_export_not_ready}

  defp validate_downloadable(%ProjectSnapshot{integrity_state: state}) when state != "verified",
    do: {:error, :snapshot_export_integrity_unavailable}

  defp validate_downloadable(%ProjectSnapshot{}), do: :ok

  defp reserve_read_lease(project, snapshot) do
    Billing.reserve_storage(%{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id,
      idempotency_key: "snapshot-download:#{Ecto.UUID.generate()}",
      kind: "snapshot_export",
      reserved_bytes: 0
    })
  end

  defp prepare_and_deliver(snapshot, heartbeat, callback) do
    case prepare_zip(snapshot, heartbeat) do
      {:ok, plan} -> callback.(plan)
      {:error, _reason} = error -> error
    end
  end

  # Keep the rescue boundary narrower than the caller callback: preflight
  # failures still become a private 503, while delivery exceptions retain their
  # original semantics and are handled by the response-stream boundary.
  defp prepare_zip(snapshot, heartbeat) do
    case ProjectSnapshotZip.prepare(snapshot, heartbeat: heartbeat) do
      {:ok, %ProjectSnapshotZip{} = plan} -> {:ok, plan}
      {:error, _reason} = error -> error
      _unexpected -> {:error, :snapshot_export_unavailable}
    end
  rescue
    _exception ->
      Logger.warning("Snapshot ZIP preflight failed unexpectedly")
      {:error, :snapshot_export_unavailable}
  end

  defp with_lease(lease, callback) do
    lease_key = {__MODULE__, make_ref()}
    Process.put(lease_key, lease)

    try do
      callback.(fn -> renew_if_needed(lease_key) end)
    after
      release_lease(lease_key)
    end
  end

  defp renew_if_needed(lease_key) do
    case Process.get(lease_key) do
      %{expires_at: expires_at} = lease ->
        if DateTime.diff(expires_at, TimeHelpers.now(), :second) <= @renewal_safety_seconds do
          renew_lease(lease_key, lease)
        else
          :ok
        end

      _missing ->
        {:error, :snapshot_export_lease_lost}
    end
  end

  defp renew_lease(lease_key, lease) do
    case Billing.extend_storage_reservation(lease.id, lease.lease_token, lease.generation, 0) do
      {:ok, renewed} ->
        Process.put(lease_key, renewed)
        :ok

      {:error, reason} ->
        {:error, {:snapshot_export_lease_renewal_failed, reason}}
    end
  end

  defp release_lease(lease_key) do
    lease = Process.delete(lease_key)

    if lease do
      attrs = %{
        reason: "snapshot download finished",
        cleanup_status: "not_required",
        cleanup_proof: %{
          type: "storage_not_started",
          storage_namespace: lease.storage_namespace
        }
      }

      case Billing.release_storage_reservation(lease.id, lease.lease_token, lease.generation, attrs) do
        {:ok, _released} ->
          :ok

        {:error, reason} ->
          Logger.warning("Snapshot download lease release deferred reason=#{inspect(reason)}")
      end
    end
  end

  defp normalize_error({:error, reason})
       when reason in [
              :snapshot_not_found,
              :snapshot_export_linked,
              :snapshot_export_not_ready,
              :snapshot_export_integrity_unavailable,
              :snapshot_export_unsupported_format,
              :snapshot_export_limit_exceeded
            ], do: {:error, reason}

  defp normalize_error({:error, {:snapshot_export_corrupt, _reason}} = error), do: error
  defp normalize_error({:error, _reason}), do: {:error, :snapshot_export_unavailable}
end
