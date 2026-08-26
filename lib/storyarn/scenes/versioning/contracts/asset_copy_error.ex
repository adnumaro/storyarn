defmodule Storyarn.Scenes.Versioning.AssetCopyError do
  @moduledoc false

  defexception [:asset_id, :reason]

  @impl Exception
  def message(%__MODULE__{asset_id: asset_id}), do: "could not materialize Scene version asset #{asset_id}"
end
