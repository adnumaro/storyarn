defmodule Storyarn.WorkspaceBannerStorageStub do
  @moduledoc false

  @behaviour Storyarn.Workspaces.Banner.Adapters.Storage.Port

  @state_key {__MODULE__, :state}
  @url_prefix "workspace-banner-test:///"

  def reset do
    Process.put(@state_key, %{calls: [], responses: %{}, upload_hook: nil})
    :ok
  end

  def respond(operation, response) when operation in [:upload, :delete] do
    update_state(fn state -> put_in(state, [:responses, operation], response) end)
  end

  def after_upload(fun) when is_function(fun, 0) do
    update_state(&Map.put(&1, :upload_hook, fun))
  end

  def calls(operation) do
    state().calls
    |> Enum.reverse()
    |> Enum.filter(&(elem(&1, 0) == operation))
  end

  def url_for(key), do: @url_prefix <> key

  @impl true
  def upload(key, binary, content_type) do
    record({:upload, key, binary, content_type})

    if hook = state().upload_hook do
      hook.()
    end

    response(:upload, {:ok, url_for(key)})
  end

  @impl true
  def delete(key) do
    record({:delete, key})
    response(:delete, :ok)
  end

  @impl true
  def key_from_url(@url_prefix <> key) when key != "", do: {:ok, key}
  def key_from_url(_url), do: {:error, :invalid_url}

  defp response(operation, default) do
    Map.get(state().responses, operation, default)
  end

  defp record(call) do
    update_state(&Map.update!(&1, :calls, fn calls -> [call | calls] end))
  end

  defp update_state(fun) do
    @state_key
    |> Process.get(%{calls: [], responses: %{}, upload_hook: nil})
    |> fun.()
    |> then(&Process.put(@state_key, &1))

    :ok
  end

  defp state do
    Process.get(@state_key, %{calls: [], responses: %{}, upload_hook: nil})
  end
end
