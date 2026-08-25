defmodule Storyarn.Workspaces.Banner.Queries.Get do
  @moduledoc false

  alias Storyarn.Workspaces.Banner.Adapters.Storage.Safe
  alias Storyarn.Workspaces.Banner.Rules.StorageKey
  alias Storyarn.Workspaces.Banner.Rules.UploadPolicy
  alias Storyarn.Workspaces.Memberships

  @spec execute(map(), String.t(), keyword()) ::
          {:ok, %{key: String.t(), content_type: String.t()}} | {:error, :not_found}
  def execute(scope, workspace_slug, opts \\ [])

  def execute(%{user: %{id: user_id}} = scope, workspace_slug, opts)
      when is_integer(user_id) and is_binary(workspace_slug) and workspace_slug != "" and is_list(opts) do
    with {:ok, workspace, _membership} <- Memberships.get_workspace_by_slug(scope, workspace_slug),
         {:ok, key} <- stored_key(workspace.slug, workspace.banner_url, opts),
         content_type when is_binary(content_type) <- MIME.from_path(key),
         true <- UploadPolicy.accepted_content_type?(content_type) do
      {:ok, %{key: key, content_type: content_type}}
    else
      _ -> {:error, :not_found}
    end
  end

  def execute(_scope, _workspace_slug, _opts), do: {:error, :not_found}

  defp stored_key(_workspace_slug, nil, _opts), do: {:error, :no_banner}
  defp stored_key(_workspace_slug, "", _opts), do: {:error, :no_banner}

  defp stored_key(workspace_slug, url, opts) when is_binary(url) do
    with {:ok, key} <- Safe.key_from_url(url, opts),
         true <- StorageKey.owned?(workspace_slug, key) do
      {:ok, key}
    else
      _ -> {:error, :invalid_banner_url}
    end
  end

  defp stored_key(_workspace_slug, _url, _opts), do: {:error, :invalid_banner_url}
end
