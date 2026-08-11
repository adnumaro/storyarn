defmodule StoryarnWeb.SnapshotDownloadController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Assets.Storage
  alias Storyarn.Projects
  alias Storyarn.Versioning
  alias StoryarnWeb.PrivateDownload

  require Logger

  @download_stop_event [:storyarn, :snapshot, :download, :stop]
  @max_snapshot_id 9_223_372_036_854_775_807

  def download(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => snapshot_id_param}) do
    started_at = System.monotonic_time()

    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(
             conn.assigns.current_scope,
             workspace_slug,
             project_slug
           ),
         :ok <- authorize_download(membership),
         {:ok, snapshot_id} <- parse_snapshot_id(snapshot_id_param) do
      project
      |> Versioning.with_project_snapshot_archive(snapshot_id, fn delivery ->
        deliver_archive(conn, project, delivery)
      end)
      |> handle_result(conn, started_at, project.id, snapshot_id)
    else
      {:error, :not_found} -> request_error(conn, started_at, :project_not_found, &not_found/1)
      {:error, :unauthorized} -> request_error(conn, started_at, :unauthorized, &forbidden/1)
      {:error, :invalid_snapshot_id} -> request_error(conn, started_at, :invalid_snapshot_id, &not_found/1)
    end
  end

  def download(conn, _params) do
    request_error(conn, System.monotonic_time(), :invalid_request, &not_found/1)
  end

  defp authorize_download(%{role: role}) do
    if Projects.can?(role, :manage_project), do: :ok, else: {:error, :unauthorized}
  end

  defp authorize_download(_membership), do: {:error, :unauthorized}

  defp parse_snapshot_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {snapshot_id, ""} when snapshot_id > 0 and snapshot_id <= @max_snapshot_id ->
        {:ok, snapshot_id}

      _invalid ->
        {:error, :invalid_snapshot_id}
    end
  end

  defp parse_snapshot_id(_value), do: {:error, :invalid_snapshot_id}

  defp deliver_archive(conn, project, %{snapshot: snapshot} = delivery) do
    filename = sanitize_download_filename("#{project.slug}-snapshot-v#{snapshot.version_number}.zip")

    case sign_download_url(delivery.storage_key, filename, project.id, snapshot.id) do
      {:ok, signed_url} ->
        conn =
          conn
          |> put_redirect_headers()
          |> put_resp_header("location", signed_url)
          |> send_resp(:found, "")

        {:retain_lease, {:grant_issued, conn, delivery.size_bytes}}

      {:error, :not_supported} ->
        result =
          case PrivateDownload.send_tracked(put_private_download_headers(conn), delivery.storage_key,
                 content_type: "application/zip",
                 filename: filename
               ) do
            {:ok, conn, %{outcome: :delivered, bytes_sent: bytes_sent}} ->
              {:local_delivered, conn, bytes_sent, delivery.size_bytes}

            {:ok, conn, %{outcome: outcome, bytes_sent: bytes_sent}} ->
              {:local_incomplete, conn, bytes_sent, delivery.size_bytes, outcome}

            {:error, reason} ->
              {:local_failed, :snapshot_export_unavailable, delivery.size_bytes, local_preflight_error(reason)}
          end

        {:release_lease, result}

      {:error, _reason} ->
        {:release_lease, {:error, :snapshot_export_unavailable}}
    end
  end

  defp sign_download_url(storage_key, filename, project_id, snapshot_id) do
    Storage.presigned_download_url(storage_key, "application/zip",
      expires_in: Versioning.project_snapshot_download_signed_url_ttl_seconds(),
      filename: filename
    )
  rescue
    exception ->
      Logger.warning(
        "Snapshot download grant failed project_id=#{project_id} snapshot_id=#{snapshot_id} " <>
          "error_code=signing_exception exception_module=#{inspect(exception.__struct__)}"
      )

      {:error, :signing_exception}
  end

  defp handle_result({:grant_issued, %Plug.Conn{} = conn, artifact_bytes}, _conn, started_at, project_id, snapshot_id) do
    emit_download_stop(started_at, 0, artifact_bytes, :grant_issued, :redirect, :none, project_id, snapshot_id)
    conn
  end

  defp handle_result(
         {:local_delivered, %Plug.Conn{} = conn, bytes, artifact_bytes},
         _original_conn,
         started_at,
         project_id,
         snapshot_id
       ) do
    emit_download_stop(started_at, bytes, artifact_bytes, :delivered, :local, :none, project_id, snapshot_id)
    conn
  end

  defp handle_result({:local_failed, reason, artifact_bytes, error_code}, conn, started_at, project_id, snapshot_id) do
    emit_download_stop(started_at, 0, artifact_bytes, :failed, :local, error_code, project_id, snapshot_id)
    error_conn(reason, conn)
  end

  defp handle_result(
         {:local_incomplete, %Plug.Conn{} = conn, bytes, artifact_bytes, delivery_outcome},
         _original_conn,
         started_at,
         project_id,
         snapshot_id
       ) do
    {outcome, error_code} = local_delivery_metadata(delivery_outcome)
    emit_download_stop(started_at, bytes, artifact_bytes, outcome, :local, error_code, project_id, snapshot_id)
    conn
  end

  defp handle_result({:error, reason}, conn, started_at, project_id, snapshot_id) do
    {outcome, phase, error_code} = download_error_metadata(reason)
    emit_download_stop(started_at, 0, 0, outcome, phase, error_code, project_id, snapshot_id)
    error_conn(reason, conn)
  end

  defp local_delivery_metadata(:range_not_satisfiable), do: {:rejected, :range_not_satisfiable}
  defp local_delivery_metadata(:client_closed), do: {:interrupted, :client_closed}
  defp local_delivery_metadata(:stream_failed), do: {:failed, :stream_failed}
  defp local_delivery_metadata(_unexpected), do: {:failed, :unexpected_local_outcome}

  defp local_preflight_error({:storage_stat_failed, _reason}), do: :stat_unavailable
  defp local_preflight_error({:storage_stream_start_failed, _reason}), do: :stream_unavailable
  defp local_preflight_error(_reason), do: :unexpected_local_error

  defp sanitize_download_filename(filename) do
    String.replace(filename, ["\r", "\n", "\"", "\\", <<0>>], "_")
  end

  defp request_error(conn, started_at, error_code, response) do
    emit_download_stop(started_at, 0, 0, :rejected, :request, error_code, nil, nil)
    response.(conn)
  end

  defp download_error_metadata(:snapshot_not_found), do: {:rejected, :eligibility, :snapshot_not_found}
  defp download_error_metadata(:snapshot_export_not_ready), do: {:rejected, :eligibility, :not_ready}

  defp download_error_metadata(:snapshot_export_integrity_unavailable),
    do: {:rejected, :eligibility, :integrity_unavailable}

  defp download_error_metadata({:snapshot_export_corrupt, _reason}), do: {:rejected, :eligibility, :integrity_failed}

  defp download_error_metadata(:snapshot_export_unavailable), do: {:failed, :grant, :unavailable}

  defp download_error_metadata(_reason), do: {:failed, :grant, :unexpected_error}

  defp emit_download_stop(started_at, bytes, artifact_bytes, outcome, phase, error_code, project_id, snapshot_id) do
    :telemetry.execute(
      @download_stop_event,
      %{
        count: 1,
        duration: System.monotonic_time() - started_at,
        bytes: bytes,
        artifact_bytes: artifact_bytes
      },
      %{
        outcome: outcome,
        phase: phase,
        error_code: error_code,
        project_id: project_id,
        snapshot_id: snapshot_id
      }
    )
  end

  defp error_conn(:snapshot_not_found, conn), do: not_found(conn)
  defp error_conn(:snapshot_export_not_ready, conn), do: not_ready(conn)
  defp error_conn(:snapshot_export_integrity_unavailable, conn), do: integrity_unavailable(conn)
  defp error_conn({:snapshot_export_corrupt, _reason}, conn), do: integrity_unavailable(conn)
  defp error_conn(:snapshot_export_unavailable, conn), do: temporarily_unavailable(conn)
  defp error_conn(_reason, conn), do: temporarily_unavailable(conn)

  defp not_found(conn) do
    error_response(
      conn,
      :not_found,
      dgettext("projects", "Snapshot not found.")
    )
  end

  defp forbidden(conn) do
    error_response(
      conn,
      :forbidden,
      dgettext("projects", "You do not have permission to download this snapshot.")
    )
  end

  defp not_ready(conn) do
    error_response(
      conn,
      :conflict,
      dgettext("projects", "This snapshot is not ready to download.")
    )
  end

  defp integrity_unavailable(conn) do
    error_response(
      conn,
      :unprocessable_entity,
      dgettext(
        "projects",
        "This snapshot cannot be downloaded because its integrity could not be verified."
      )
    )
  end

  defp temporarily_unavailable(conn) do
    error_response(
      conn,
      :service_unavailable,
      dgettext("projects", "Snapshot download is temporarily unavailable.")
    )
  end

  defp error_response(conn, status, message) do
    conn
    |> put_private_download_headers()
    |> put_status(status)
    |> text(message)
  end

  defp put_private_download_headers(conn) do
    conn
    |> put_resp_header("cache-control", "private, no-store, no-transform")
    |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
    |> put_resp_header("cross-origin-resource-policy", "same-origin")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
  end

  defp put_redirect_headers(conn) do
    conn
    |> delete_resp_header("content-security-policy")
    |> delete_resp_header("cross-origin-resource-policy")
    |> put_resp_header("cache-control", "private, no-store, no-transform")
    |> put_resp_header("referrer-policy", "no-referrer")
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
