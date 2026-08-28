defmodule Storyarn.Workspaces.Banner.Commands.Upload do
  @moduledoc false

  alias Storyarn.Workspaces.Banner.Adapters.Cleanup.Queue
  alias Storyarn.Workspaces.Banner.Adapters.Storage.ResilientStorage
  alias Storyarn.Workspaces.Banner.Commands.Change
  alias Storyarn.Workspaces.Banner.Rules.StorageKey
  alias Storyarn.Workspaces.Banner.Rules.UploadPolicy
  alias Storyarn.Workspaces.Memberships

  require Logger

  @spec execute(map(), pos_integer(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(scope, workspace_id, attrs, opts \\ [])

  def execute(%{user: %{id: user_id}} = scope, workspace_id, attrs, opts)
      when is_integer(user_id) and is_integer(workspace_id) and workspace_id > 0 and is_map(attrs) and is_list(opts) do
    with {:ok, workspace, _membership} <- Memberships.authorize(scope, workspace_id, :manage_workspace),
         {:ok, upload} <- UploadPolicy.validate(attrs),
         key = StorageKey.new(workspace.slug, upload.filename),
         {:ok, url} <- upload_to_owned_key(key, upload.binary, upload.content_type, opts) do
      persist_uploaded_banner(scope, workspace_id, key, url, opts)
    end
  end

  def execute(_scope, _workspace_id, _attrs, _opts), do: {:error, :unauthorized}

  defp upload_to_owned_key(key, binary, content_type, opts) do
    case ResilientStorage.upload(key, binary, content_type, opts) do
      {:ok, url} when is_binary(url) and url != "" ->
        validate_uploaded_url(url, key, opts)

      {:error, reason} ->
        {:error, {:workspace_banner_storage_failed, reason}}

      result ->
        {:error, {:workspace_banner_storage_failed, {:unexpected_result, result}}}
    end
  end

  defp validate_uploaded_url(url, key, opts) do
    case ResilientStorage.key_from_url(url, opts) do
      {:ok, ^key} ->
        {:ok, url}

      result ->
        cleanup_uploaded_key(key, {:invalid_uploaded_url, result}, opts)
    end
  end

  defp persist_uploaded_banner(scope, workspace_id, key, url, opts) do
    case Change.persist(scope, workspace_id, url, key, opts) do
      {:ok, workspace} ->
        {:ok, workspace}

      {:error, reason} ->
        compensate_failed_update(key, reason, opts)
    end
  end

  defp compensate_failed_update(key, reason, opts) do
    case ResilientStorage.delete(key, opts) do
      :ok ->
        {:error, reason}

      {:error, cleanup_reason} ->
        defer_failed_cleanup(key, reason, cleanup_reason, opts)

      result ->
        defer_failed_cleanup(key, reason, {:unexpected_result, result}, opts)
    end
  end

  defp cleanup_uploaded_key(key, reason, opts) do
    case ResilientStorage.delete(key, opts) do
      :ok ->
        {:error, {:workspace_banner_storage_failed, reason}}

      {:error, cleanup_reason} ->
        defer_failed_cleanup(key, {:workspace_banner_storage_failed, reason}, cleanup_reason, opts)

      result ->
        defer_failed_cleanup(
          key,
          {:workspace_banner_storage_failed, reason},
          {:unexpected_result, result},
          opts
        )
    end
  end

  defp defer_failed_cleanup(key, reason, cleanup_reason, opts) do
    with {:ok, workspace_slug} <- StorageKey.workspace_slug(key),
         :ok <- Queue.enqueue(workspace_slug, key, opts) do
      {:error, {:workspace_banner_cleanup_deferred, reason, cleanup_reason}}
    else
      {:error, queue_reason} ->
        Logger.error(
          "Workspace banner cleanup could not be persisted " <>
            "object=#{inspect(Path.basename(key))} reason=#{inspect(queue_reason)}"
        )

        {:error,
         {:workspace_banner_update_failed_with_cleanup_required, reason, key,
          %{delete: cleanup_reason, enqueue: queue_reason}}}
    end
  end
end
