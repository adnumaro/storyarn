defmodule StoryarnWeb.PrivateMediaController do
  @moduledoc false

  use StoryarnWeb, :controller

  alias Storyarn.Assets
  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Projects
  alias Storyarn.Workspaces

  @signed_url_ttl_seconds 60

  def asset(conn, %{"id" => asset_id_param}) do
    with {:ok, asset_id} <- parse_positive_integer(asset_id_param),
         %Asset{} = asset <- Assets.get_asset(asset_id),
         {:ok, _project, _membership} <-
           Projects.get_project(conn.assigns.current_scope, asset.project_id) do
      deliver(conn, asset.key, asset.content_type)
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
    with {:ok, workspace, _membership} <-
           Workspaces.get_workspace_by_slug(conn.assigns.current_scope, workspace_slug),
         banner_url when is_binary(banner_url) <- workspace.banner_url,
         {:ok, key} <- Storage.key_from_url(banner_url),
         :ok <- validate_workspace_banner_key(key, workspace.slug) do
      deliver(conn, key, MIME.from_path(key))
    else
      _ -> not_found(conn)
    end
  end

  defp deliver(conn, key, content_type) do
    case Storage.presigned_download_url(key,
           expires_in: @signed_url_ttl_seconds,
           cache_control: "private, no-store"
         ) do
      {:ok, url} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> redirect(external: url)

      {:error, :not_supported} ->
        stream_local(conn, key, content_type)

      {:error, _reason} ->
        not_found(conn)
    end
  end

  # sobelow_skip ["XSS.ContentType", "XSS.SendResp"]
  defp stream_local(conn, key, content_type) do
    case Storage.download(key) do
      {:ok, data} ->
        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> put_resp_content_type(content_type)
        |> send_resp(:ok, data)

      {:error, _reason} ->
        not_found(conn)
    end
  end

  defp decode_project_key(encoded_key, project_id) do
    with {:ok, key} <- Base.url_decode64(encoded_key, padding: false),
         true <- valid_storage_key?(key),
         true <- String.starts_with?(key, "projects/#{project_id}/") do
      {:ok, key}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp validate_workspace_banner_key(key, workspace_slug) do
    if valid_storage_key?(key) and
         String.starts_with?(key, "workspaces/#{workspace_slug}/banner/") do
      :ok
    else
      {:error, :invalid_key}
    end
  end

  defp valid_storage_key?(key) when is_binary(key) do
    key != "" and
      not String.contains?(key, [<<0>>, "\\"]) and
      Enum.all?(String.split(key, "/"), &(&1 not in ["", ".", ".."]))
  end

  defp valid_storage_key?(_key), do: false

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
