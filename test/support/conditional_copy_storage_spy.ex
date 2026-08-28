defmodule Storyarn.ConditionalCopyStorageSpy do
  @moduledoc false

  @delete_result_key {__MODULE__, :delete_result}

  def configure(opts \\ []) when is_list(opts) do
    Process.put(@delete_result_key, Keyword.get(opts, :delete_result, :ok))
    :ok
  end

  def delete(key) do
    send(self(), {:conditional_copy_delete, key})
    Process.get(@delete_result_key, :ok)
  end
end
