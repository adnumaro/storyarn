defmodule Storyarn.Projects.Versioning.ProjectSnapshotDownload do
  @moduledoc """
  Authorizes one persisted snapshot archive and owns its durable download fence.

  A zero-byte `snapshot_export` reservation prevents lifecycle cleanup from
  deleting the published archive while a grant is usable. Grants for the same
  snapshot coalesce onto one generation-fenced lease. Every acquisition keeps
  that shared lease for the expiry reaper: releasing it from one request could
  invalidate a concurrent provider grant or local transfer.
  """

  alias Storyarn.Platform
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Memberships
  alias Storyarn.Projects.PlatformStorageReservations
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.Versioning.ProjectSnapshot
  alias Storyarn.Projects.Versioning.ProjectSnapshotCrud
  alias Storyarn.Projects.Versioning.ProjectSnapshotLeasePolicy
  alias Storyarn.Projects.Versioning.SnapshotArchiveStorage

  require Logger

  @sha256_regex ~r/\A[0-9a-f]{64}\z/
  @download_filename ~r/\A[A-Za-z0-9][A-Za-z0-9._-]{0,254}\z/

  @type delivery :: %{
          snapshot: ProjectSnapshot.t(),
          storage_key: Storage.key(),
          size_bytes: pos_integer(),
          checksum: String.t()
        }
  @type delivery_result(result) :: {:keep_lease, result}
  @type authorized_delivery ::
          %{
            delivery: :redirect,
            url: String.t(),
            size_bytes: pos_integer()
          }
          | %{
              delivery: :stream,
              storage_key: Storage.key(),
              content_type: String.t(),
              filename: String.t(),
              size_bytes: pos_integer()
            }

  @doc """
  Authorizes, leases and prepares one snapshot download without exposing a raw
  signing capability through the Projects facade.

  Provider-backed storage yields a bounded redirect grant. Local storage
  yields a scoped stream delivery whose key exists only inside this authorized
  callback.
  """
  @spec with_authorized_download(
          map(),
          pos_integer(),
          pos_integer(),
          (authorized_delivery() -> delivery_result(result))
        ) :: result | {:error, term()}
        when result: term()
  def with_authorized_download(scope, project_id, snapshot_id, callback)
      when is_integer(project_id) and project_id > 0 and is_integer(snapshot_id) and snapshot_id > 0 and
             is_function(callback, 1) do
    case Memberships.authorize(scope, project_id, :manage_project) do
      {:ok, project, _membership} ->
        project
        |> prepare_authorized_download(scope, snapshot_id)
        |> invoke_authorized_delivery(callback)

      {:error, _reason} ->
        {:error, :unauthorized}
    end
  end

  def with_authorized_download(_scope, _project_id, _snapshot_id, _callback), do: {:error, :snapshot_not_found}

  defp prepare_authorized_download(%Project{} = initially_authorized_project, scope, snapshot_id) do
    result =
      Platform.transact_with_workspace_lock(initially_authorized_project.workspace_id, fn _workspace ->
        with {:ok, project, _membership} <-
               Memberships.authorize_locked(scope, initially_authorized_project.id, :manage_project),
             true <- project.workspace_id == initially_authorized_project.workspace_id,
             %ProjectSnapshot{} = snapshot <- ProjectSnapshotCrud.get_snapshot_by_id(project.id, snapshot_id),
             :ok <- validate_eligibility(snapshot),
             {:ok, delivery} <- delivery(snapshot),
             {:ok, _lease} <- reserve_read_lease(project, snapshot) do
          # A failed provider grant must not roll back a newly-created or
          # renewed lease. The request may overlap another valid grant whose
          # archive still needs the same deletion fence.
          {:ok, prepare_authorized_delivery(delivery, download_filename(project, snapshot))}
        else
          false -> {:error, :unauthorized}
          nil -> {:error, :snapshot_not_found}
          {:error, :not_found} -> {:error, :unauthorized}
          {:error, _reason} = error -> normalize_error(error)
        end
      end)

    case result do
      {:ok, {:ok, authorized_delivery}} -> {:ok, authorized_delivery}
      {:ok, {:error, _reason} = error} -> error
      {:error, :workspace_not_found} -> {:error, :unauthorized}
      {:error, _reason} = error -> error
    end
  end

  defp invoke_authorized_delivery({:ok, authorized_delivery}, callback) do
    case callback.(authorized_delivery) do
      {:keep_lease, result} -> result
      _invalid -> {:error, :snapshot_export_unavailable}
    end
  end

  defp invoke_authorized_delivery({:error, _reason} = error, _callback), do: error

  @doc """
  Revalidates and leases one scoped persisted ZIP, then yields its delivery data.

  The callback must explicitly acknowledge that the shared lease remains active
  until bounded expiry. Request completion is not cleanup authority because
  another request may already depend on the same lease generation.
  """
  @spec with_archive(Project.t(), pos_integer(), (delivery() -> delivery_result(result))) ::
          result | {:error, term()}
        when result: term()
  def with_archive(%Project{id: project_id, deleted_at: nil} = project, snapshot_id, callback)
      when is_integer(project_id) and project_id > 0 and is_integer(snapshot_id) and snapshot_id > 0 and
             is_function(callback, 1) do
    with %ProjectSnapshot{} = snapshot <- ProjectSnapshotCrud.get_snapshot_by_id(project.id, snapshot_id),
         :ok <- validate_eligibility(snapshot),
         {:ok, delivery} <- delivery(snapshot),
         {:ok, _lease} <- reserve_read_lease(project, snapshot) do
      invoke_delivery(callback, delivery)
    else
      nil -> {:error, :snapshot_not_found}
      {:error, _reason} = error -> normalize_error(error)
    end
  end

  def with_archive(_project, _snapshot_id, _callback), do: {:error, :snapshot_not_found}

  defp prepare_authorized_delivery(delivery, filename) do
    case Storage.presigned_download_url(delivery.storage_key, "application/zip",
           expires_in: ProjectSnapshotLeasePolicy.download_signed_url_ttl_seconds(),
           filename: filename
         ) do
      {:ok, url} when is_binary(url) and url != "" ->
        {:ok, %{delivery: :redirect, url: url, size_bytes: delivery.size_bytes}}

      {:error, :not_supported} ->
        {:ok,
         %{
           delivery: :stream,
           storage_key: delivery.storage_key,
           content_type: "application/zip",
           filename: filename,
           size_bytes: delivery.size_bytes
         }}

      {:error, _reason} ->
        {:error, :snapshot_export_unavailable}

      _unexpected ->
        {:error, :snapshot_export_unavailable}
    end
  rescue
    exception ->
      Logger.warning(
        "Snapshot download grant failed project_id=#{delivery.snapshot.project_id} " <>
          "snapshot_id=#{delivery.snapshot.id} error_code=signing_exception " <>
          "exception_module=#{inspect(exception.__struct__)}"
      )

      {:error, :snapshot_export_unavailable}
  catch
    _kind, _reason -> {:error, :snapshot_export_unavailable}
  end

  defp download_filename(project, snapshot) do
    filename =
      "#{project.slug}-snapshot-v#{snapshot.version_number}.zip"
      |> String.replace(["\r", "\n", "\"", "\\", <<0>>], "_")
      |> String.replace(~r/[^A-Za-z0-9._-]/u, "_")
      |> String.slice(0, 255)

    if Regex.match?(@download_filename, filename),
      do: filename,
      else: "project-snapshot-v#{snapshot.version_number}.zip"
  end

  defp validate_eligibility(%ProjectSnapshot{mode: mode}) when mode != "full",
    do: {:error, {:snapshot_export_corrupt, :invalid_snapshot_mode}}

  defp validate_eligibility(%ProjectSnapshot{lifecycle_state: state}) when state != "ready",
    do: {:error, :snapshot_export_not_ready}

  defp validate_eligibility(%ProjectSnapshot{integrity_state: state}) when state != "verified",
    do: {:error, :snapshot_export_integrity_unavailable}

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
    PlatformStorageReservations.acquire_snapshot_export_lease(%{
      workspace_id: project.workspace_id,
      project_id: project.id,
      project_snapshot_id: snapshot.id
    })
  end

  defp invoke_delivery(callback, delivery) do
    case callback.(delivery) do
      {:keep_lease, result} -> result
      _invalid -> {:error, :snapshot_export_unavailable}
    end
  end

  defp normalize_error({:error, reason})
       when reason in [:snapshot_not_found, :snapshot_export_not_ready, :snapshot_export_integrity_unavailable],
       do: {:error, reason}

  defp normalize_error({:error, {:snapshot_export_corrupt, _reason}} = error), do: error
  defp normalize_error({:error, _reason}), do: {:error, :snapshot_export_unavailable}
end
