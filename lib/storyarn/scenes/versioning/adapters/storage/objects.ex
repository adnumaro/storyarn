defmodule Storyarn.Scenes.Versioning.Adapters.Storage.Objects do
  @moduledoc false

  alias Storyarn.Projects.Assets.Storage

  defdelegate canonical_key?(key), to: Storage
  defdelegate stat(key), to: Storage
end
