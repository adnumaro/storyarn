defmodule Storyarn.Platform.Billing.StorageCleanupInventoryTest do
  use ExUnit.Case, async: true

  alias Storyarn.Platform.Billing.StorageCleanupInventory

  test "digest is order-independent and preserves key boundaries" do
    digest = StorageCleanupInventory.digest(["second", "first"])

    assert digest == StorageCleanupInventory.digest(["first", "second"])
    assert byte_size(digest) == 64
    refute digest == StorageCleanupInventory.digest(["fir", "stsecond"])
  end
end
