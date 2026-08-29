defmodule Storyarn.Projects.StorageCleanupInventory do
  @moduledoc """
  Project-owned canonical digest for an exact snapshot cleanup inventory.

  This pure protocol rule is deliberately duplicated from Commercial Billing.
  Both contexts persist and verify the same digest without sharing business
  implementation code.
  """

  @spec digest([String.t()]) :: String.t()
  def digest(storage_keys) when is_list(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn storage_key -> "#{byte_size(storage_key)}:#{storage_key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
