defmodule Storyarn.Sheets.Versioning.SnapshotStorageTest do
  use ExUnit.Case, async: true

  alias Storyarn.Sheets.Versioning.SnapshotStorage

  test "never deletes a recoverable Project blob even when its tail is not a canonical hash filename" do
    assert {:error, :recoverable_blob} =
             SnapshotStorage.delete("projects/42/blobs/legacy/nested-object")
  end
end
