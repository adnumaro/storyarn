defmodule Storyarn.Assets.BlobStoreTest do
  use Storyarn.DataCase, async: true

  alias Storyarn.Assets.BlobStore

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "compute_hash/1" do
    test "returns consistent 64-char hex string" do
      data = "hello world"
      hash = BlobStore.compute_hash(data)

      assert is_binary(hash)
      assert byte_size(hash) == 64
      assert hash =~ ~r/^[0-9a-f]{64}$/

      # Deterministic
      assert BlobStore.compute_hash(data) == hash
    end

    test "different content produces different hashes" do
      refute BlobStore.compute_hash("abc") == BlobStore.compute_hash("def")
    end
  end

  describe "ext_from_content_type/1" do
    test "maps common MIME types" do
      assert BlobStore.ext_from_content_type("image/jpeg") == "jpg"
      assert BlobStore.ext_from_content_type("image/png") == "png"
      assert BlobStore.ext_from_content_type("audio/mpeg") == "mp3"
      assert BlobStore.ext_from_content_type("application/pdf") == "pdf"
    end
  end

  describe "blob_key/3" do
    test "generates correct format" do
      key = BlobStore.blob_key(42, "abc123", "png")
      assert key == "projects/42/blobs/abc123.png"
    end
  end

  describe "ensure_blob/4" do
    test "uploads blob and is idempotent", %{project: project} do
      data = "test binary content"
      hash = BlobStore.compute_hash(data)

      {:ok, key1} = BlobStore.ensure_blob(project.id, hash, "png", data)
      {:ok, key2} = BlobStore.ensure_blob(project.id, hash, "png", data)

      assert key1 == key2
      assert key1 == BlobStore.blob_key(project.id, hash, "png")
    end
  end

  describe "create_asset_from_blob/5" do
    test "creates a new asset from blob content", %{project: project, user: user} do
      content = "blob for restoration"
      hash = BlobStore.compute_hash(content)
      ext = "png"

      {:ok, blob_key} = BlobStore.ensure_blob(project.id, hash, ext, content)

      metadata = %{
        "filename" => "restored.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      {:ok, new_asset} =
        BlobStore.create_asset_from_blob(project.id, user.id, hash, blob_key, metadata)

      assert new_asset.filename == "restored.png"
      assert new_asset.content_type == "image/png"
      assert new_asset.size == byte_size(content)
      assert new_asset.blob_hash == hash
      assert new_asset.project_id == project.id
      assert new_asset.uploaded_by_id == user.id
    end
  end
end
