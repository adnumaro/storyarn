defmodule Storyarn.Versioning.Builders.AssetHashResolverTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Repo
  alias Storyarn.Versioning.Builders.AssetCopyError
  alias Storyarn.Versioning.Builders.AssetHashResolver

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
      asset =
        asset_fixture(project, user, %{
          filename: "test.jpg",
          blob_hash: "abc123",
          metadata: %{"sanitized_svg" => true, "web_url" => "/uploads/stale.webp"}
        })

      {hash_map, metadata_map} = AssetHashResolver.resolve_hashes([asset.id])

      id_str = to_string(asset.id)
      assert hash_map[id_str] == "abc123"
      assert metadata_map[id_str]["filename"] == "test.jpg"
      assert metadata_map[id_str]["content_type"] == "image/jpeg"
      assert metadata_map[id_str]["size"] == 12_345
      assert metadata_map[id_str]["sanitized_svg"] == true
      refute Map.has_key?(metadata_map[id_str], "web_url")
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
      hash = BlobStore.compute_hash(content)
      ext = "mp3"
      {:ok, _key} = BlobStore.ensure_blob(project.id, hash, ext, content)

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

      Repo.delete!(asset)

      new_id = AssetHashResolver.resolve_asset_fk(asset.id, snapshot, project.id, user.id)
      assert is_integer(new_id)
      refute new_id == asset.id

      new_asset = Repo.get!(Asset, new_id)
      assert new_asset.filename == "track.mp3"
      assert new_asset.content_type == "audio/mpeg"
      assert new_asset.blob_hash == hash
    end

    test "returns nil when asset deleted and no blob info in snapshot", %{
      project: project,
      user: user
    } do
      asset = asset_fixture(project, user)
      Repo.delete!(asset)

      snapshot = %{"asset_blob_hashes" => %{}, "asset_metadata" => %{}}
      result = AssetHashResolver.resolve_asset_fk(asset.id, snapshot, project.id)
      assert is_nil(result)
    end

    test "returns nil for malformed snapshot asset metadata", %{project: project, user: user} do
      asset_id = 999_991

      snapshot = %{
        "asset_blob_hashes" => %{to_string(asset_id) => "abc123"},
        "asset_metadata" => %{
          to_string(asset_id) => %{"filename" => "broken.png", "content_type" => nil}
        }
      }

      assert nil ==
               AssetHashResolver.resolve_asset_fk(asset_id, snapshot, project.id, user.id, asset_mode: :copy)
    end

    test "raises the domain error for malformed metadata in strict mode", %{project: project, user: user} do
      asset_id = 999_992

      snapshot = %{
        "asset_blob_hashes" => %{to_string(asset_id) => "abc123"},
        "asset_metadata" => %{to_string(asset_id) => %{"content_type" => "image/png"}}
      }

      error =
        assert_raise AssetCopyError, fn ->
          AssetHashResolver.resolve_asset_fk(asset_id, snapshot, project.id, user.id,
            asset_mode: :copy,
            asset_error_mode: :strict
          )
        end

      assert error.asset_id == asset_id
      assert error.reason == :missing_asset_metadata
    end

    test "successive template clones keep a copyable project-local blob", %{
      project: source_project,
      user: user
    } do
      first_clone = project_fixture(user)
      second_clone = project_fixture(user)
      content = "avatar copied through two template generations"
      hash = BlobStore.compute_hash(content)

      assert {:ok, source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      source_asset =
        asset_fixture(source_project, user, %{
          filename: "avatar.png",
          content_type: "image/png",
          size: byte_size(content),
          blob_hash: hash
        })

      {first_hashes, first_metadata} = AssetHashResolver.resolve_hashes([source_asset.id])

      first_snapshot = %{
        "asset_blob_hashes" => first_hashes,
        "asset_metadata" => first_metadata
      }

      first_asset_id =
        AssetHashResolver.resolve_asset_fk(
          source_asset.id,
          first_snapshot,
          first_clone.id,
          user.id,
          asset_mode: :copy,
          asset_error_mode: :strict
        )

      first_asset = Repo.get!(Asset, first_asset_id)
      first_blob_key = BlobStore.blob_key(first_clone.id, hash, "png")
      assert {:ok, ^content} = Storage.download(first_blob_key)

      {second_hashes, second_metadata} = AssetHashResolver.resolve_hashes([first_asset.id])

      second_snapshot = %{
        "asset_blob_hashes" => second_hashes,
        "asset_metadata" => second_metadata
      }

      second_asset_id =
        AssetHashResolver.resolve_asset_fk(
          first_asset.id,
          second_snapshot,
          second_clone.id,
          user.id,
          asset_mode: :copy,
          asset_error_mode: :strict
        )

      second_asset = Repo.get!(Asset, second_asset_id)
      second_blob_key = BlobStore.blob_key(second_clone.id, hash, "png")

      on_exit(fn ->
        Enum.each(
          [
            source_blob_key,
            first_blob_key,
            second_blob_key,
            first_asset.key,
            second_asset.key
          ],
          &Storage.delete/1
        )
      end)

      assert {:ok, ^content} = Storage.download(second_asset.key)
      assert {:ok, ^content} = Storage.download(second_blob_key)
      assert second_asset.blob_hash == hash
    end
  end
end
