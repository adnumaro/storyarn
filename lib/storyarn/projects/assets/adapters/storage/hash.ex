defmodule Storyarn.Projects.Assets.StorageHash do
  @moduledoc false

  defdelegate sha256_chunks(chunks), to: Storyarn.Platform.ObjectStorage
end
