defmodule StoryarnWeb.PrivateMediaController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Projects
  alias Storyarn.Workspaces
  alias StoryarnWeb.PrivateDownload
  alias StoryarnWeb.PrivateMedia

  def asset(conn, %{"id" => asset_id_param}) do
    with {:ok, asset_id} <- parse_positive_integer(asset_id_param),
         {:ok, %{key: key, content_type: content_type}} <-
           Projects.authorize_asset_download(conn.assigns.current_scope, asset_id) do
      deliver(conn, key, content_type)
    else
      _ -> not_found(conn)
    end
  end

  def project_file(conn, %{"project_id" => project_id_param, "encoded_key" => encoded_key}) do
    with {:ok, project_id} <- parse_positive_integer(project_id_param),
         {:ok, _project, _membership} <-
           Projects.get_project(conn.assigns.current_scope, project_id),
         {:ok, key} <- decode_project_key(encoded_key, project_id) do
      deliver(conn, key, MIME.from_path(key))
    else
      _ -> not_found(conn)
    end
  end

  def workspace_banner(conn, %{"workspace_slug" => workspace_slug}) do
    case Workspaces.get_workspace_banner(conn.assigns.current_scope, workspace_slug) do
      {:ok, %{key: key, content_type: content_type}} -> deliver(conn, key, content_type)
      _ -> not_found(conn)
    end
  end

  defp deliver(conn, key, content_type) do
    case PrivateDownload.send(conn, key, content_type: content_type) do
      {:ok, conn} ->
        conn

      {:error, _reason} ->
        not_found(conn)
    end
  end

  defp decode_project_key(encoded_key, project_id) do
    with {:ok, key} <- Base.url_decode64(encoded_key, padding: false),
         true <- PrivateMedia.project_media_key?(project_id, key) do
      {:ok, key}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp parse_positive_integer(value) do
    case Integer.parse(value) do
      {id, ""} when id > 0 -> {:ok, id}
      _ -> {:error, :invalid_id}
    end
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> text(gettext("Media not found"))
  end
end
