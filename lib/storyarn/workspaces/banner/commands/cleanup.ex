defmodule Storyarn.Workspaces.Banner.Commands.Cleanup do
  @moduledoc false

  alias Storyarn.Workspaces.Banner.Adapters.Cleanup.Queue
  alias Storyarn.Workspaces.Banner.Adapters.Storage.ResilientStorage
  alias Storyarn.Workspaces.Banner.Rules.StorageKey

  require Logger

  @spec prepare_hard_delete(map(), keyword()) :: :ok | {:error, term()}
  def prepare_hard_delete(workspace_or_snapshot, opts \\ [])

  def prepare_hard_delete(%{slug: workspace_slug, banner_url: previous_banner_url}, opts) when is_list(opts) do
    schedule_previous(
      %{workspace_slug: workspace_slug, previous_banner_url: previous_banner_url},
      nil,
      opts
    )
  end

  def prepare_hard_delete(%{workspace_slug: workspace_slug, previous_banner_url: previous_banner_url}, opts)
      when is_list(opts) do
    schedule_previous(
      %{workspace_slug: workspace_slug, previous_banner_url: previous_banner_url},
      nil,
      opts
    )
  end

  @spec perform_cleanup(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def perform_cleanup(workspace_slug, storage_key, opts \\ [])

  def perform_cleanup(workspace_slug, storage_key, opts)
      when is_binary(workspace_slug) and is_binary(storage_key) and is_list(opts) do
    if StorageKey.owned?(workspace_slug, storage_key),
      do: ResilientStorage.delete(storage_key, opts),
      else: {:error, :invalid_banner_key}
  end

  def perform_cleanup(_workspace_slug, _storage_key, _opts), do: {:error, :invalid_banner_key}

  @spec schedule_previous(map(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def schedule_previous(%{slug: workspace_slug, banner_url: previous_banner_url}, current_key, opts) do
    schedule_previous(
      %{workspace_slug: workspace_slug, previous_banner_url: previous_banner_url},
      current_key,
      opts
    )
  end

  def schedule_previous(%{workspace_slug: workspace_slug, previous_banner_url: previous_banner_url}, current_key, opts) do
    case stored_key(workspace_slug, previous_banner_url, opts) do
      {:ok, ^current_key} ->
        :ok

      {:ok, previous_key} ->
        case Queue.enqueue(workspace_slug, previous_key, opts) do
          :ok -> :ok
          {:error, reason} -> {:error, {:workspace_banner_cleanup_enqueue_failed, reason}}
        end

      {:error, :no_banner} ->
        :ok

      {:error, reason} ->
        Logger.warning("Workspace banner cleanup skipped for an untrusted stored URL: #{inspect(reason)}")
        :ok
    end
  end

  defp stored_key(_workspace_slug, nil, _opts), do: {:error, :no_banner}
  defp stored_key(_workspace_slug, "", _opts), do: {:error, :no_banner}

  defp stored_key(workspace_slug, url, opts) when is_binary(url) do
    with {:ok, key} <- ResilientStorage.key_from_url(url, opts),
         true <- StorageKey.owned?(workspace_slug, key) do
      {:ok, key}
    else
      _ -> {:error, :invalid_banner_url}
    end
  end

  defp stored_key(_workspace_slug, _url, _opts), do: {:error, :invalid_banner_url}
end
