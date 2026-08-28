defmodule Storyarn.Workspaces.Banner.Adapters.Cleanup.Queue do
  @moduledoc """
  Technical outbox port for Workspace-owned banner cleanup.

  Enqueueing happens in the same database transaction that changes or deletes
  the Workspace, so persistence cannot commit without a durable cleanup intent.
  """

  @type workspace_slug :: String.t()
  @type storage_key :: String.t()

  @callback enqueue(workspace_slug(), storage_key()) :: {:ok, term()} | {:error, term()}

  @spec enqueue(workspace_slug(), storage_key(), keyword()) :: :ok | {:error, term()}
  def enqueue(workspace_slug, storage_key, opts \\ []) do
    adapter =
      Keyword.get_lazy(opts, :cleanup_queue, fn ->
        :storyarn
        |> Application.fetch_env!(__MODULE__)
        |> Keyword.fetch!(:adapter)
      end)

    case adapter.enqueue(workspace_slug, storage_key) do
      {:ok, _intent} -> :ok
      {:error, _reason} = error -> error
      result -> {:error, {:unexpected_cleanup_queue_result, result}}
    end
  rescue
    error -> {:error, {:cleanup_queue_exception, error}}
  end
end
