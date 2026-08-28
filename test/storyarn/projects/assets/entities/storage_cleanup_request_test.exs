defmodule Storyarn.Projects.Assets.StorageCleanupRequestTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets.StorageCleanupRequest

  describe "changeset/2" do
    test "binds snapshot lifecycle ownership to a valid provider namespace" do
      fingerprint = String.duplicate("a", 64)

      assert changeset(%{
               owner_kind: "snapshot_lifecycle",
               owner_token: Ecto.UUID.generate(),
               provider_namespace_fingerprint: fingerprint
             }).valid?

      refute changeset(%{
               owner_kind: "snapshot_lifecycle",
               owner_token: Ecto.UUID.generate()
             }).valid?

      refute changeset(%{
               owner_kind: "snapshot_lifecycle",
               owner_token: Ecto.UUID.generate(),
               provider_namespace_fingerprint: String.upcase(fingerprint)
             }).valid?
    end

    test "keeps ordinary compensation requests outside snapshot namespace ownership" do
      assert changeset(%{}).valid?

      refute changeset(%{
               provider_namespace_fingerprint: String.duplicate("b", 64)
             }).valid?
    end
  end

  defp changeset(attrs) do
    StorageCleanupRequest.changeset(
      %StorageCleanupRequest{},
      Map.put(attrs, :storage_keys, ["projects/1/blobs/#{String.duplicate("c", 64)}.bin"])
    )
  end
end
