defmodule Storyarn.Scenes.Assets.Adapters.Storage.Hashing do
  @moduledoc false

  defdelegate sha256_chunks(chunks), to: Storyarn.Platform.ObjectStorage
end
