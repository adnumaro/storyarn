defmodule Storyarn.Assets.StorageTest do
  use ExUnit.Case, async: false

  alias Storyarn.Assets.Storage

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
      assert Storage.adapter() == Storyarn.Assets.Storage.Local
    end

    test "returns R2 adapter when configured as :r2" do
      original = Application.get_env(:storyarn, :storage, [])
      Application.put_env(:storyarn, :storage, adapter: :r2)

      assert Storage.adapter() == Storyarn.Assets.Storage.R2

      Application.put_env(:storyarn, :storage, original)
    end

    test "defaults to Local adapter when no adapter configured" do
      Application.put_env(:storyarn, :storage, [])
      assert Storage.adapter() == Storyarn.Assets.Storage.Local
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
end
