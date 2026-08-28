defmodule Storyarn.Projects.Assets.StorageKeyTest do
  use ExUnit.Case, async: true

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageKey

  @canonical_key_cases [
    {"projects/1/assets/asset-id/file.png", true},
    {"projects/1/snapshots/archives/v2/ready/snapshot.zip", true},
    {"project_templates/imports/template-id/snapshot.json.gz", true},
    {nil, false},
    {42, false},
    {"", false},
    {"/projects/1/assets/file.png", false},
    {"projects/1/assets/file.png/", false},
    {"projects//assets/file.png", false},
    {"projects/./assets/file.png", false},
    {"projects/../assets/file.png", false},
    {"projects/1/assets\\file.png", false},
    {"projects/1/assets/file.png" <> <<0>>, false},
    {<<255>>, false}
  ]

  @canonical_prefix_cases [
    {"projects/1/snapshots/", true},
    {"project_templates/imports/template-id/", true},
    {nil, false},
    {42, false},
    {"", false},
    {"projects/1/snapshots", false},
    {"projects/1/snapshots//", false},
    {"projects/../snapshots/", false},
    {"projects/1/snapshots\\", false}
  ]

  describe "canonical?/1" do
    test "accepts canonical segmented keys" do
      assert StorageKey.canonical?("projects/1/assets/asset-id/file.png")
    end

    test "rejects empty, relative, duplicate and unsafe segments" do
      refute StorageKey.canonical?(nil)
      refute StorageKey.canonical?("")
      refute StorageKey.canonical?("projects//assets/file.png")
      refute StorageKey.canonical?("projects/../assets/file.png")
      refute StorageKey.canonical?("projects/1/assets\\file.png")
      refute StorageKey.canonical?("projects/1/assets/file.png" <> <<0>>)
    end

    test "stays equivalent to the duplicated technical storage guard" do
      Enum.each(@canonical_key_cases, fn {key, expected} ->
        assert StorageKey.canonical?(key) == expected
        assert Storage.canonical_key?(key) == expected
      end)
    end
  end

  describe "canonical_prefix?/1" do
    test "requires one trailing slash after a canonical key" do
      assert StorageKey.canonical_prefix?("projects/1/snapshots/")
      refute StorageKey.canonical_prefix?("projects/1/snapshots")
      refute StorageKey.canonical_prefix?("projects/1/snapshots//")
      refute StorageKey.canonical_prefix?(nil)
    end

    test "stays equivalent to the duplicated technical storage guard" do
      Enum.each(@canonical_prefix_cases, fn {prefix, expected} ->
        assert StorageKey.canonical_prefix?(prefix) == expected
        assert Storage.canonical_prefix?(prefix) == expected
      end)
    end
  end

  describe "Project media namespaces" do
    test "accepts only non-empty asset and blob paths scoped to the requested Project" do
      assert StorageKey.project_asset_route_key?(7, "projects/7/assets/uuid/image.png")
      refute StorageKey.project_asset_route_key?(7, "projects/7/blobs/hash.png")

      assert StorageKey.project_media_route_key?(7, "projects/7/assets/uuid/image.png")
      assert StorageKey.project_media_route_key?(7, "projects/7/blobs/hash.png")
      refute StorageKey.project_media_route_key?(7, "projects/7/assets")
      refute StorageKey.project_media_route_key?(7, "projects/7/snapshots/project/1.json.gz")
      refute StorageKey.project_media_route_key?(7, "projects/8/assets/uuid/image.png")
      refute StorageKey.project_media_route_key?(7, "projects/7/assets/../snapshot.json.gz")
    end

    test "rejects malformed project identities and keys" do
      refute StorageKey.project_media_route_key?(nil, "projects/7/assets/image.png")
      refute StorageKey.project_media_route_key?(7, nil)
      refute StorageKey.project_media_route_key?(7, <<255>>)
    end
  end
end
