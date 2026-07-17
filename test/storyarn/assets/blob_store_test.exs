defmodule Storyarn.Assets.BlobStoreTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.BlobStore
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation

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

    test "reports creation ownership without replacing existing bytes", %{project: project} do
      first = "first content"
      hash = BlobStore.compute_hash(first)

      assert {:ok, key, true} = BlobStore.ensure_blob_with_status(project.id, hash, "png", first)
      assert {:ok, ^key, false} = BlobStore.ensure_blob_with_status(project.id, hash, "png", "replacement")
      assert {:ok, ^first} = Storage.download(key)
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

    test "materializes a content-addressed blob in the destination project", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "portable template asset"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      metadata = %{
        "filename" => "template.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:ok, asset} =
               BlobStore.create_asset_from_blob(
                 destination_project.id,
                 user.id,
                 hash,
                 source_blob_key,
                 metadata
               )

      on_exit(fn ->
        Storage.delete(source_blob_key)
        Storage.delete(destination_blob_key)
        Storage.delete(asset.key)
      end)

      assert {:ok, ^content} = Storage.download(asset.key)
      assert {:ok, ^content} = Storage.download(destination_blob_key)
    end

    test "rejects source content that does not match the requested blob hash", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "tampered portable template asset"
      actual_hash = BlobStore.compute_hash(content)
      expected_hash = BlobStore.compute_hash("expected portable template asset")
      source_blob_key = BlobStore.blob_key(source_project.id, actual_hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, expected_hash, "png")

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, actual_hash, "png", content)

      on_exit(fn ->
        Storage.delete(source_blob_key)
        Storage.delete(destination_blob_key)
      end)

      metadata = %{
        "filename" => "tampered.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, :blob_hash_mismatch} =
               BlobStore.create_asset_from_blob(
                 destination_project.id,
                 user.id,
                 expected_hash,
                 source_blob_key,
                 metadata
               )

      refute Repo.exists?(
               from asset in Asset,
                 where:
                   asset.project_id == ^destination_project.id and
                     asset.blob_hash == ^expected_hash
             )

      assert {:error, _reason} = Storage.download(destination_blob_key)
    end

    test "rejects a corrupt pre-existing destination blob", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "verified portable template asset"
      corrupt_content = "corrupt destination bytes"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      assert {:ok, _url} = Storage.upload(destination_blob_key, corrupt_content, "image/png")

      on_exit(fn ->
        Storage.delete(source_blob_key)
        Storage.delete(destination_blob_key)
      end)

      metadata = %{
        "filename" => "corrupt.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, :blob_hash_mismatch} =
               BlobStore.create_asset_from_blob(
                 destination_project.id,
                 user.id,
                 hash,
                 source_blob_key,
                 metadata
               )

      assert {:ok, ^corrupt_content} = Storage.download(destination_blob_key)

      refute Repo.exists?(
               from asset in Asset,
                 where:
                   asset.project_id == ^destination_project.id and
                     asset.blob_hash == ^hash
             )
    end

    test "does not take cleanup ownership when the source is the project-local blob", %{
      project: project,
      user: user
    } do
      content = :binary.copy("streamed-local-blob-", 70_000)
      hash = BlobStore.compute_hash(content)
      blob_key = BlobStore.blob_key(project.id, hash, "png")
      tracker = StorageCompensation.new()

      assert {:ok, ^blob_key} = BlobStore.ensure_blob(project.id, hash, "png", content)

      metadata = %{
        "filename" => "local.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, {:forced_rollback, asset_key}} =
               Repo.transaction(fn ->
                 {:ok, asset} =
                   BlobStore.create_asset_from_blob(
                     project.id,
                     user.id,
                     hash,
                     blob_key,
                     metadata,
                     asset_copy_tracker: tracker
                   )

                 Repo.rollback({:forced_rollback, asset.key})
               end)

      on_exit(fn ->
        Storage.delete(blob_key)
        Storage.delete(asset_key)
      end)

      assert :ok = StorageCompensation.cleanup(tracker)
      assert {:error, _reason} = Storage.download(asset_key)
      assert {:ok, ^content} = Storage.download(blob_key)
    end

    test "tracks a newly materialized blob for rollback compensation", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "asset rolled back after template materialization"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")
      tracker = StorageCompensation.new()

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      metadata = %{
        "filename" => "rolled-back.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, {:forced_rollback, asset_key}} =
               Repo.transaction(fn ->
                 {:ok, asset} =
                   BlobStore.create_asset_from_blob(
                     destination_project.id,
                     user.id,
                     hash,
                     source_blob_key,
                     metadata,
                     asset_copy_tracker: tracker
                   )

                 Repo.rollback({:forced_rollback, asset.key})
               end)

      on_exit(fn ->
        Storage.delete(source_blob_key)
        Storage.delete(destination_blob_key)
        Storage.delete(asset_key)
      end)

      assert {:ok, ^content} = Storage.download(asset_key)
      assert {:ok, ^content} = Storage.download(destination_blob_key)
      assert :ok = StorageCompensation.cleanup(tracker)
      assert {:error, _reason} = Storage.download(asset_key)
      assert {:error, _reason} = Storage.download(destination_blob_key)
    end

    test "does not compensate a destination blob that already existed", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "shared content-addressed destination blob"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")
      tracker = StorageCompensation.new()

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      assert {:ok, ^destination_blob_key} =
               BlobStore.ensure_blob(destination_project.id, hash, "png", content)

      metadata = %{
        "filename" => "shared.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, {:forced_rollback, asset_key}} =
               Repo.transaction(fn ->
                 {:ok, asset} =
                   BlobStore.create_asset_from_blob(
                     destination_project.id,
                     user.id,
                     hash,
                     source_blob_key,
                     metadata,
                     asset_copy_tracker: tracker
                   )

                 Repo.rollback({:forced_rollback, asset.key})
               end)

      on_exit(fn ->
        Storage.delete(source_blob_key)
        Storage.delete(destination_blob_key)
        Storage.delete(asset_key)
      end)

      assert :ok = StorageCompensation.cleanup(tracker)
      assert {:error, _reason} = Storage.download(asset_key)
      assert {:ok, ^content} = Storage.download(destination_blob_key)
    end

    test "rejects legacy SVG blob metadata before copying a public asset", %{
      project: project,
      user: user
    } do
      content = ~S"""
      <svg xmlns="http://www.w3.org/2000/svg"><script>alert(document.domain)</script></svg>
      """

      hash = BlobStore.compute_hash(content)
      {:ok, blob_key} = BlobStore.ensure_blob(project.id, hash, "svg", content)
      asset_glob = asset_file_glob(project.id, "payload.svg")

      on_exit(fn ->
        Storage.delete(blob_key)
        asset_glob |> Path.wildcard() |> Enum.each(&File.rm/1)
      end)

      metadata = %{
        "filename" => "payload.svg",
        "content_type" => "image/svg+xml",
        "size" => byte_size(content)
      }

      assert {:error, changeset} =
               BlobStore.create_asset_from_blob(project.id, user.id, hash, blob_key, metadata)

      assert %{content_type: [_ | _]} = errors_on(changeset)
      refute Repo.exists?(from a in Asset, where: a.project_id == ^project.id and a.blob_hash == ^hash)
      assert Path.wildcard(asset_glob) == []
    end

    test "restores SVG blobs that were marked as sanitized", %{project: project, user: user} do
      content = ~S"""
      <svg xmlns="http://www.w3.org/2000/svg"><circle cx="4" cy="4" r="3"></circle></svg>
      """

      hash = BlobStore.compute_hash(content)
      {:ok, blob_key} = BlobStore.ensure_blob(project.id, hash, "svg", content)

      metadata = %{
        "filename" => "pin.svg",
        "content_type" => "image/svg+xml",
        "size" => byte_size(content),
        "sanitized_svg" => true
      }

      assert {:ok, new_asset} =
               BlobStore.create_asset_from_blob(project.id, user.id, hash, blob_key, metadata)

      on_exit(fn ->
        Storage.delete(blob_key)
        Storage.delete(new_asset.key)
      end)

      assert new_asset.content_type == "image/svg+xml"
      assert new_asset.metadata["sanitized_svg"] == true
      assert {:ok, ^content} = Storage.download(new_asset.key)
    end
  end

  defp asset_file_glob(project_id, filename) do
    upload_dir =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.fetch!(:upload_dir)
      |> Path.expand()

    Path.join([upload_dir, "projects", to_string(project_id), "assets", "*", filename])
  end
end
