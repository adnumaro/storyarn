defmodule StoryarnTest.Projects.ThrowingSnapshotArchiveReader do
  @moduledoc false

  def preflight_file(_path), do: throw({:archive_preflight_failed, %{sensitive: "must not be logged"}})
end
