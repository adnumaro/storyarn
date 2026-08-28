defmodule Storyarn.Projects.Assets.Commands.AssetCommands do
  @moduledoc false

  alias Storyarn.Projects.Assets.AssetOperations

  defdelegate create_asset(project, user, attrs), to: AssetOperations
  defdelegate create_asset(project, attrs), to: AssetOperations
  defdelegate update_asset(asset, attrs), to: AssetOperations
  defdelegate delete_asset(asset), to: AssetOperations
  defdelegate change_asset(asset, attrs \\ %{}), to: AssetOperations
end
