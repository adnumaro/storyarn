defmodule Storyarn.WorkspaceBannerCleanupQueueStub do
  @moduledoc false

  @behaviour Storyarn.Workspaces.BannerCleanupQueue

  @state_key {__MODULE__, :state}

  def reset do
    Process.put(@state_key, %{calls: [], response: {:ok, :queued}})
    :ok
  end

  def respond(response) do
    update_state(&Map.put(&1, :response, response))
  end

  def calls do
    Enum.reverse(state().calls)
  end

  @impl true
  def enqueue(workspace_slug, storage_key) do
    update_state(&Map.update!(&1, :calls, fn calls -> [{workspace_slug, storage_key} | calls] end))
    state().response
  end

  defp update_state(fun) do
    @state_key
    |> Process.get(%{calls: [], response: {:ok, :queued}})
    |> fun.()
    |> then(&Process.put(@state_key, &1))

    :ok
  end

  defp state do
    Process.get(@state_key, %{calls: [], response: {:ok, :queued}})
  end
end
