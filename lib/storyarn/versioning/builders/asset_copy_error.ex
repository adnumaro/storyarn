defmodule Storyarn.Versioning.Builders.AssetCopyError do
  @moduledoc false

  defexception [:asset_id, :reason]

  @impl Exception
  def message(%__MODULE__{asset_id: asset_id}) do
    "could not copy template asset #{asset_id}"
  end
end
