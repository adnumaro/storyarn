defmodule Storyarn.Drafts.BaselineIds do
  @moduledoc false

  @spec from_snapshot(String.t(), map()) :: map()
  def from_snapshot("sheet", snapshot) do
    block_ids =
      snapshot
      |> Map.get("blocks", [])
      |> Enum.map(& &1["original_id"])
      |> Enum.reject(&is_nil/1)

    %{"block_ids" => block_ids}
  end

  def from_snapshot(_entity_type, _snapshot), do: %{}
end
