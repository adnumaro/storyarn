defmodule StoryarnWeb.SnapshotDownloadController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects
  alias Storyarn.Shared.NameNormalizer
  alias Storyarn.Versioning
  alias Storyarn.Versioning.SnapshotStorage

  @doc """
  Download a project snapshot archive.

  Generates a presigned R2 URL and redirects the browser for direct download.
  Falls back to streaming through Phoenix for local storage.
  """
  def download(conn, %{
        "workspace_slug" => workspace_slug,
        "project_slug" => project_slug,
        "id" => snapshot_id_str
      }) do
    scope = conn.assigns.current_scope

    with {:ok, project, _membership} <-
           Projects.get_project_by_slugs(scope, workspace_slug, project_slug),
         {snapshot_id, ""} <- Integer.parse(snapshot_id_str),
         %{} = snapshot <- Versioning.get_project_snapshot(project.id, snapshot_id) do
      filename = build_filename(project.name, snapshot)

      case SnapshotStorage.presigned_download_url(snapshot.storage_key, filename: filename) do
        {:ok, url} ->
          redirect(conn, external: url)

        {:error, :not_supported} ->
          stream_download(conn, snapshot.storage_key, filename)
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> text(gettext("Project not found"))

      nil ->
        conn |> put_status(:not_found) |> text(gettext("Snapshot not found"))

      :error ->
        conn |> put_status(:bad_request) |> text(gettext("Invalid snapshot ID"))
    end
  end

  defp build_filename(project_name, snapshot) do
    slug = NameNormalizer.slugify(project_name)
    date = Calendar.strftime(snapshot.inserted_at, "%Y-%m-%d")
    "#{slug}-snapshot-v#{snapshot.version_number}-#{date}.json.gz"
  end

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp stream_download(conn, storage_key, filename) do
    case Storyarn.Assets.Storage.download(storage_key) do
      {:ok, data} ->
        conn
        |> put_resp_content_type("application/gzip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
        |> send_resp(200, data)

      {:error, _reason} ->
        conn |> put_status(:not_found) |> text(gettext("Snapshot file not found"))
    end
  end
end
