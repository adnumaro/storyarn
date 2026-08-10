defmodule Storyarn.LiveVueEncodersTest do
  use ExUnit.Case, async: true

  alias Storyarn.Accounts.User
  alias Storyarn.Assets.Asset

  test "asset encoding excludes internal trash state" do
    encoded =
      LiveVue.Encoder.encode(%Asset{
        id: 42,
        filename: "portrait.png",
        deleted_at: ~U[2026-08-10 10:00:00Z],
        deleted_by_id: 7,
        deleted_by: %User{id: 7},
        deletion_reason: "user",
        deletion_generation: 3
      })

    assert encoded.filename == "portrait.png"

    refute Map.has_key?(encoded, :deleted_at)
    refute Map.has_key?(encoded, :deleted_by_id)
    refute Map.has_key?(encoded, :deleted_by)
    refute Map.has_key?(encoded, :deletion_reason)
    refute Map.has_key?(encoded, :deletion_generation)
  end
end
