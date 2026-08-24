defmodule Storyarn.Projects.Assets.StorageTest do
  use ExUnit.Case, async: false

  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.Storage.Local

  defmodule NoMultipartInventoryAdapter do
    @moduledoc false
  end

  @test_dir "test/tmp/storage_dispatch"

  setup do
    original_config = Application.get_env(:storyarn, :storage, [])

    Application.put_env(:storyarn, :storage,
      adapter: :local,
      upload_dir: @test_dir,
      public_path: "/dispatch-uploads"
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_config)
      File.rm_rf(@test_dir)
    end)

    %{}
  end

  # =============================================================================
  # adapter/0
  # =============================================================================

  describe "adapter/0" do
    test "returns Local adapter when configured as :local" do
      Application.put_env(:storyarn, :storage, adapter: :local)
      assert Storage.adapter() == Local
    end

    test "returns R2 adapter when configured as :r2" do
      original = Application.get_env(:storyarn, :storage, [])
      Application.put_env(:storyarn, :storage, adapter: :r2)

      assert Storage.adapter() == Storyarn.Projects.Assets.Storage.R2

      Application.put_env(:storyarn, :storage, original)
    end

    test "defaults to Local adapter when no adapter configured" do
      Application.put_env(:storyarn, :storage, [])
      assert Storage.adapter() == Local
    end
  end

  describe "multipart cleanup policy" do
    test "covers the UploadPart deadline after second-precision clock truncation" do
      deadline_ms = Storage.multipart_upload_part_deadline_ms()
      quiescence_ms = Storage.multipart_cleanup_quiescence_seconds() * 1_000

      assert quiescence_ms >= deadline_ms + 1_000
    end

    test "recognizes only exact restore-reservation blob upload keys" do
      lease_token = "3abf435a-c086-4801-9b91-5a49a440f917"
      hash = String.duplicate("a", 64)
      key = "projects/42/storage-reservations/v1/restore-staging/#{lease_token}/blobs/#{hash}.png"

      assert Storage.multipart_cleanup_key?(key)

      refute Storage.multipart_cleanup_key?(
               "projects/42/storage-reservations/v1/snapshot-build/#{lease_token}/blobs/#{hash}.png"
             )

      refute Storage.multipart_cleanup_key?(
               "projects/42/storage-reservations/v1/restore-staging/#{lease_token}/project.json"
             )

      refute Storage.multipart_cleanup_key?(key <> "/extra")
      refute Storage.multipart_cleanup_key?(String.replace(key, lease_token, String.upcase(lease_token)))
      refute Storage.multipart_cleanup_key?(String.replace(key, "projects/42", "projects/0"))
    end
  end

  describe "canonical_prefix?/1" do
    test "requires exactly one trailing slash" do
      assert Storage.canonical_prefix?("projects/1/snapshots/")
      refute Storage.canonical_prefix?("projects/1/snapshots")
      refute Storage.canonical_prefix?("projects/1/snapshots//")

      assert {:error, :invalid_prefix} =
               Storage.list_prefix("projects/1/snapshots//")
    end
  end

  # =============================================================================
  # upload/3
  # =============================================================================

  describe "upload/3" do
    test "delegates to configured adapter and returns URL" do
      key = "dispatch_test_#{System.unique_integer([:positive])}/file.txt"
      assert {:ok, url} = Storage.upload(key, "test data", "text/plain")
      assert url == "/dispatch-uploads/#{key}"

      # Verify the file was actually written
      path = Path.join(@test_dir, key)
      assert File.exists?(path)
      assert File.read!(path) == "test data"
    end

    test "handles binary content types" do
      key = "dispatch_binary_#{System.unique_integer([:positive])}/image.png"
      binary = <<137, 80, 78, 71, 13, 10, 26, 10>>
      assert {:ok, _url} = Storage.upload(key, binary, "image/png")

      path = Path.join(@test_dir, key)
      assert File.read!(path) == binary
    end
  end

  describe "copy_if_absent/2" do
    test "delegates conditional copies and preserves the first destination bytes" do
      source_key = "dispatch_copy/source.txt"
      destination_key = "dispatch_copy/destination.txt"

      assert {:ok, _url} = Storage.upload(source_key, "first", "text/plain")
      assert {:ok, true} = Storage.copy_if_absent(source_key, destination_key)

      assert {:ok, _url} = Storage.upload(source_key, "second", "text/plain")
      assert {:ok, false} = Storage.copy_if_absent(source_key, destination_key)
      assert {:ok, "first"} = Storage.download(destination_key)
    end
  end

  describe "abort_incomplete_multipart_uploads/2" do
    test "treats a non-multipart adapter as an empty exact inventory" do
      assert {:ok, 0} =
               Storage.abort_incomplete_multipart_uploads(
                 "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
               )
    end

    test "rejects unsafe keys and options before dispatch" do
      assert {:error, :invalid_multipart_cleanup_request} =
               Storage.abort_incomplete_multipart_uploads("projects/1/../snapshot.zip")

      assert {:error, :invalid_multipart_cleanup_request} =
               Storage.abort_incomplete_multipart_uploads("projects/1/snapshot.zip", %{limit: 1})
    end
  end

  describe "incomplete_multipart_upload_count/2" do
    test "fails closed when the configured adapter has no multipart inventory" do
      Application.put_env(:storyarn, :storage, adapter: NoMultipartInventoryAdapter)

      assert {:error, :multipart_inventory_not_supported} =
               Storage.incomplete_multipart_upload_count(
                 "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
               )
    end

    test "treats the local non-multipart backend as an exact empty inventory" do
      assert {:ok, 0} =
               Storage.incomplete_multipart_upload_count(
                 "projects/1/snapshots/archives/v2/staging/AbCdEfGhIjKlMnOp/snapshot.zip"
               )
    end

    test "rejects unsafe keys and options before dispatch" do
      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_count("projects/1/../snapshot.zip")

      assert {:error, :invalid_multipart_inventory_request} =
               Storage.incomplete_multipart_upload_count("projects/1/snapshot.zip", %{limit: 1})
    end
  end

  # =============================================================================
  # delete/1
  # =============================================================================

  describe "delete/1" do
    test "delegates to configured adapter and deletes file" do
      key = "dispatch_delete_#{System.unique_integer([:positive])}/file.txt"
      {:ok, _} = Storage.upload(key, "content", "text/plain")

      assert :ok = Storage.delete(key)

      path = Path.join(@test_dir, key)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file" do
      assert :ok = Storage.delete("nonexistent/key.txt")
    end

    test "blocks deletion of recoverable blobs" do
      key = "projects/1/blobs/hash.png"
      {:ok, _url} = Storage.upload(key, "recoverable", "image/png")

      assert {:error, :recoverable_blob} = Storage.delete(key)
      assert File.read!(Path.join(@test_dir, key)) == "recoverable"
    end

    test "rejects non-canonical keys before the adapter can normalize them" do
      canonical_key = "projects/1/blobs/hash.png"
      {:ok, _url} = Storage.upload(canonical_key, "recoverable", "image/png")

      invalid_keys = [
        "projects/1/blobs//hash.png",
        "projects/1//blobs/hash.png",
        "projects//1/blobs/hash.png",
        "projects/1/blobs/hash.png/",
        "/projects/1/blobs/hash.png",
        "projects/1/blobs/./hash.png",
        "projects/1/assets/../blobs/hash.png",
        "projects/1/blobs\\hash.png",
        "projects/1/blobs/hash.png" <> <<0>>
      ]

      for invalid_key <- invalid_keys do
        assert {:error, :invalid_key} = Storage.delete(invalid_key)
      end

      assert File.read!(Path.join(@test_dir, canonical_key)) == "recoverable"
    end
  end

  # =============================================================================
  # get_url/1
  # =============================================================================

  describe "get_url/1" do
    test "delegates to configured adapter and returns public URL" do
      assert Storage.get_url("project/asset.png") == "/dispatch-uploads/project/asset.png"
    end

    test "handles nested paths" do
      assert Storage.get_url("a/b/c/d.txt") == "/dispatch-uploads/a/b/c/d.txt"
    end
  end

  # =============================================================================
  # presigned_upload_url/3
  # =============================================================================

  describe "presigned_upload_url/3" do
    test "delegates to configured adapter" do
      # Local adapter returns :not_supported
      assert {:error, :not_supported} = Storage.presigned_upload_url("key", "text/plain")
    end

    test "accepts optional opts parameter" do
      assert {:error, :not_supported} =
               Storage.presigned_upload_url("key", "text/plain", max_size: 1024)
    end
  end

  describe "presigned_download_url/3" do
    test "uses the adapter only for a bounded canonical attachment request" do
      assert {:error, :not_supported} =
               Storage.presigned_download_url(
                 "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/snapshot.zip",
                 "application/zip",
                 expires_in: 300,
                 filename: "snapshot.zip"
               )
    end

    test "rejects unsafe keys, metadata, filenames, and expiry before delegation" do
      invalid_requests = [
        ["projects/1/../secret", "application/zip", [filename: "snapshot.zip"]],
        ["projects/1/archive.zip", "application/zip\r\ntext/html", [filename: "snapshot.zip"]],
        ["projects/1/archive.zip", "application/zip", [filename: "bad\r\nname.zip"]],
        ["projects/1/archive.zip", "application/zip", [filename: "snapshot.zip", expires_in: 0]],
        ["projects/1/archive.zip", "application/zip", [filename: "snapshot.zip", expires_in: 301]]
      ]

      for [key, content_type, opts] <- invalid_requests do
        assert {:error, :invalid_presigned_download_request} =
                 Storage.presigned_download_url(key, content_type, opts)
      end
    end
  end
end
