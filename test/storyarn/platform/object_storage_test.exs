defmodule Storyarn.Platform.ObjectStorageTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.ObjectStorage
  alias Storyarn.Platform.ObjectStorage.Adapters.Local.ConditionalCopyRegistry
  alias Storyarn.Platform.ObjectStorage.Adapters.Local.ConditionalCopySweeper

  test "contributes the exact local conditional-copy supervision tree" do
    assert ObjectStorage.child_specs() == [ConditionalCopyRegistry, ConditionalCopySweeper]

    for child <- ObjectStorage.child_specs() do
      assert child |> Process.whereis() |> is_pid()
    end
  end
end
