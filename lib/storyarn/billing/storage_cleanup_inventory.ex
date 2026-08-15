defmodule Storyarn.Billing.StorageCleanupInventory do
  @moduledoc false

  @doc "Returns the canonical digest for an exact storage cleanup inventory."
  @spec digest([String.t()]) :: String.t()
  def digest(storage_keys) when is_list(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn storage_key -> "#{byte_size(storage_key)}:#{storage_key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
