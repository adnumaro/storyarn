defmodule StoryarnWeb.SnapshotDownloadController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects
  alias Storyarn.Versioning

  require Logger

  @max_snapshot_id 9_223_372_036_854_775_807

  def download(conn, %{"workspace_slug" => workspace_slug, "project_slug" => project_slug, "id" => snapshot_id_param}) do
    with {:ok, project, membership} <-
           Projects.get_project_by_slugs(
             conn.assigns.current_scope,
             workspace_slug,
             project_slug
           ),
         :ok <- authorize_download(membership),
         {:ok, snapshot_id} <- parse_snapshot_id(snapshot_id_param) do
      project.id
      |> Versioning.with_project_snapshot_zip(snapshot_id, fn plan ->
        send_zip(conn, project, plan)
      end)
      |> handle_result(conn)
    else
      {:error, :not_found} -> not_found(conn)
      {:error, :unauthorized} -> forbidden(conn)
      {:error, :invalid_snapshot_id} -> not_found(conn)
    end
  end

  def download(conn, _params), do: not_found(conn)

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

  defp handle_result(%Plug.Conn{} = conn, _original_conn), do: conn
  defp handle_result({:error, :snapshot_not_found}, conn), do: not_found(conn)
  defp handle_result({:error, :snapshot_export_linked}, conn), do: linked_snapshot(conn)
  defp handle_result({:error, :snapshot_export_not_ready}, conn), do: not_ready(conn)

  defp handle_result({:error, :snapshot_export_integrity_unavailable}, conn), do: integrity_unavailable(conn)

  defp handle_result({:error, {:snapshot_export_corrupt, _reason}}, conn), do: integrity_unavailable(conn)

  defp handle_result({:error, :snapshot_export_unsupported_format}, conn), do: unsupported_format(conn)

  defp handle_result({:error, :snapshot_export_limit_exceeded}, conn), do: export_too_large(conn)

  defp handle_result({:error, :snapshot_export_unavailable}, conn), do: temporarily_unavailable(conn)

  defp handle_result({:error, _reason}, conn), do: temporarily_unavailable(conn)

  defp send_zip(conn, project, %{snapshot: snapshot} = plan) do
    filename = sanitize_download_filename("#{project.slug}-snapshot-v#{snapshot.version_number}.zip")

    conn =
      conn
      |> put_private_download_headers()
      |> put_resp_content_type("application/zip", nil)
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_chunked(:ok)

    stream_zip(conn, plan)
  end

  defp sanitize_download_filename(filename) do
    String.replace(filename, ["\r", "\n", "\"", "\\"], "_")
  end

  defp stream_zip(conn, plan) do
    plan
    |> Versioning.stream_project_snapshot_zip()
    |> Enum.reduce_while(conn, &send_zip_chunk/2)
  rescue
    _exception ->
      Logger.warning("Snapshot ZIP response stream failed")
      halt(conn)
  end

  defp send_zip_chunk(data, conn) do
    with {:ok, binary} <- zip_chunk_binary(data),
         {:ok, conn} <- chunk(conn, binary) do
      {:cont, conn}
    else
      {:error, _reason} -> {:halt, halt(conn)}
    end
  end

  defp zip_chunk_binary(iodata) do
    {:ok, IO.iodata_to_binary(iodata)}
  rescue
    ArgumentError -> {:error, :invalid_zip_chunk}
  end

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

  defp linked_snapshot(conn) do
    error_response(
      conn,
      :conflict,
      dgettext(
        "projects",
        "Convert this linked snapshot to a full snapshot before downloading it."
      )
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

  defp unsupported_format(conn) do
    error_response(
      conn,
      :unprocessable_entity,
      dgettext("projects", "This snapshot format cannot be downloaded.")
    )
  end

  defp export_too_large(conn) do
    error_response(
      conn,
      :request_entity_too_large,
      dgettext("projects", "This snapshot exceeds the ZIP download limits.")
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
    |> put_resp_header("x-content-type-options", "nosniff")
  end
end
