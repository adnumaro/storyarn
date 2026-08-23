defmodule Storyarn.Sheets.Versioning.AssetCopyError do
  @moduledoc false

  defexception [:asset_id, :reason]

  @impl Exception
  def message(%__MODULE__{asset_id: asset_id}), do: "could not materialize Sheet version asset #{asset_id}"
end
