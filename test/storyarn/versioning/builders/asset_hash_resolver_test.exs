defmodule Storyarn.Versioning.Builders.AssetHashResolverTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Versioning.Builders.AssetHashResolver

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.AssetsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "resolve_hashes/1" do
    test "returns empty maps for empty input" do
      assert {%{}, %{}} = AssetHashResolver.resolve_hashes([])
    end

    test "returns empty maps for nil-only input" do
      assert {%{}, %{}} = AssetHashResolver.resolve_hashes([nil, nil])
    end

    test "returns hash and metadata for assets", %{project: project, user: user} do
      asset = asset_fixture(project, user, %{filename: "test.jpg", blob_hash: "abc123"})

      {hash_map, metadata_map} = AssetHashResolver.resolve_hashes([asset.id])

      id_str = to_string(asset.id)
      assert hash_map[id_str] == "abc123"
      assert metadata_map[id_str]["filename"] == "test.jpg"
      assert metadata_map[id_str]["content_type"] == "image/jpeg"
      assert metadata_map[id_str]["size"] == 12_345
    end
  end

  describe "resolve_asset_fk/4" do
    test "returns nil for nil input" do
      assert nil == AssetHashResolver.resolve_asset_fk(nil, %{}, 1)
    end

    test "returns ID when asset still exists", %{project: project, user: user} do
      asset = asset_fixture(project, user)

      result = AssetHashResolver.resolve_asset_fk(asset.id, %{}, project.id)
      assert result == asset.id
    end

    test "recreates asset from blob when deleted", %{project: project, user: user} do
      content = "audio content for versioning"
      hash = Storyarn.Assets.BlobStore.compute_hash(content)
      ext = "mp3"
      {:ok, _key} = Storyarn.Assets.BlobStore.ensure_blob(project.id, hash, ext, content)

      asset = asset_fixture(project, user, %{content_type: "audio/mpeg", filename: "track.mp3"})
      asset_id_str = to_string(asset.id)

      snapshot = %{
        "asset_blob_hashes" => %{asset_id_str => hash},
        "asset_metadata" => %{
          asset_id_str => %{
            "filename" => "track.mp3",
            "content_type" => "audio/mpeg",
            "size" => byte_size(content)
          }
        }
      }

      Storyarn.Repo.delete!(asset)

      new_id = AssetHashResolver.resolve_asset_fk(asset.id, snapshot, project.id, user.id)
      assert is_integer(new_id)
      refute new_id == asset.id

      new_asset = Storyarn.Repo.get!(Storyarn.Assets.Asset, new_id)
      assert new_asset.filename == "track.mp3"
      assert new_asset.content_type == "audio/mpeg"
      assert new_asset.blob_hash == hash
    end

    test "returns nil when asset deleted and no blob info in snapshot", %{
      project: project,
      user: user
    } do
      asset = asset_fixture(project, user)
      Storyarn.Repo.delete!(asset)

      snapshot = %{"asset_blob_hashes" => %{}, "asset_metadata" => %{}}
      result = AssetHashResolver.resolve_asset_fk(asset.id, snapshot, project.id)
      assert is_nil(result)
    end
  end
end
