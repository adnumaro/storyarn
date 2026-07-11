defmodule StoryarnWeb.PrivateMedia do
  @moduledoc """
  Builds same-origin URLs for private workspace and project media.

  The target controller authenticates the current user and authorizes access
  before issuing a short-lived storage URL.
  """

  use StoryarnWeb, :verified_routes

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage

  @spec asset_url(Asset.t() | map() | nil) :: String.t() | nil
  def asset_url(nil), do: nil

  def asset_url(%Asset{} = asset) do
    case preferred_asset_id(asset) do
      id when is_integer(id) -> ~p"/media/assets/#{id}"
      _ -> asset.url
    end
  end

  def asset_url(%{id: id}) when is_integer(id), do: ~p"/media/assets/#{id}"
  def asset_url(%{url: url}) when is_binary(url), do: url

  @spec project_file_url(integer(), String.t()) :: String.t()
  def project_file_url(project_id, key) when is_integer(project_id) and is_binary(key) do
    encoded_key = Base.url_encode64(key, padding: false)
    ~p"/media/projects/#{project_id}/files/#{encoded_key}"
  end

  @spec project_url_from_stored(integer(), String.t() | nil) :: String.t() | nil
  def project_url_from_stored(project_id, url) when is_integer(project_id) and is_binary(url) do
    with {:ok, key} <- Storage.key_from_url(url),
         true <- String.starts_with?(key, "projects/#{project_id}/") do
      project_file_url(project_id, key)
    else
      _ -> nil
    end
  end

  def project_url_from_stored(_project_id, _url), do: nil

  @spec project_snapshot_asset_url(integer(), map()) :: String.t() | nil
  def project_snapshot_asset_url(project_id, metadata) when is_integer(project_id) and is_map(metadata) do
    case project_url_from_key(project_id, metadata["key"]) do
      nil -> project_url_from_stored(project_id, metadata["url"])
      url -> url
    end
  end

  def project_snapshot_asset_url(_project_id, _metadata), do: nil

  @spec workspace_banner_url(map() | nil) :: String.t() | nil
  def workspace_banner_url(%{slug: slug, banner_url: banner_url})
      when is_binary(slug) and is_binary(banner_url) and banner_url != "" do
    ~p"/media/workspaces/#{slug}/banner"
  end

  def workspace_banner_url(_workspace), do: nil

  defp project_url_from_key(project_id, key) when is_binary(key) do
    if String.starts_with?(key, "projects/#{project_id}/") do
      project_file_url(project_id, key)
    end
  end

  defp project_url_from_key(_project_id, _key), do: nil

  defp preferred_asset_id(%Asset{metadata: %{"web_asset_id" => id}}) when is_integer(id), do: id
  defp preferred_asset_id(%Asset{id: id}), do: id
end
