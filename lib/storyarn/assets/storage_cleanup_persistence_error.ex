defmodule Storyarn.Assets.StorageCleanupPersistenceError do
  @moduledoc false

  defexception [:reason]

  @impl Exception
  def message(_exception) do
    "copied asset cleanup could not be completed or persisted"
  end
end
