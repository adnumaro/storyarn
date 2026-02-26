defmodule Storyarn.Assets.Storage.LocalTest do
  use ExUnit.Case, async: true

  alias Storyarn.Assets.Storage.Local

  @test_dir "test/tmp/uploads"

  setup do
    # Create a unique subdirectory for each test to avoid conflicts
    test_key = "test_#{System.unique_integer([:positive])}/file.txt"

    # Configure local storage for test
    original_config = Application.get_env(:storyarn, :storage, [])

    Application.put_env(:storyarn, :storage,
      upload_dir: @test_dir,
      public_path: "/test-uploads"
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_config)
      File.rm_rf!(@test_dir)
    end)

    %{test_key: test_key}
  end

  # =============================================================================
  # upload/3
  # =============================================================================

  describe "upload/3" do
    test "writes file to disk and returns URL", %{test_key: key} do
      data = "Hello, World!"
      assert {:ok, url} = Local.upload(key, data, "text/plain")
      assert url == "/test-uploads/#{key}"

      # Verify file was written
      path = Path.join(@test_dir, key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates intermediate directories", %{test_key: _key} do
      nested_key = "deep/nested/dir/file.txt"
      assert {:ok, _url} = Local.upload(nested_key, "content", "text/plain")

      path = Path.join(@test_dir, nested_key)
      assert File.exists?(path)
    end

    test "handles binary data" do
      key = "test_binary_#{System.unique_integer([:positive])}/image.png"
      # Small PNG header bytes
      data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      assert {:ok, _url} = Local.upload(key, data, "image/png")

      path = Path.join(@test_dir, key)
      assert File.read!(path) == data
    end
  end

  # =============================================================================
  # delete/1
  # =============================================================================

  describe "delete/1" do
    test "deletes existing file" do
      key = "delete_test_#{System.unique_integer([:positive])}/file.txt"
      {:ok, _} = Local.upload(key, "content", "text/plain")

      assert :ok = Local.delete(key)

      path = Path.join(@test_dir, key)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file (enoent)" do
      key = "nonexistent/file.txt"
      assert :ok = Local.delete(key)
    end
  end

  # =============================================================================
  # get_url/1
  # =============================================================================

  describe "get_url/1" do
    test "returns URL with configured public_path" do
      assert Local.get_url("project/asset.png") == "/test-uploads/project/asset.png"
    end

    test "handles keys with subdirectories" do
      assert Local.get_url("a/b/c/file.txt") == "/test-uploads/a/b/c/file.txt"
    end
  end

  # =============================================================================
  # presigned_upload_url/3
  # =============================================================================

  describe "presigned_upload_url/3" do
    test "returns error not_supported" do
      assert {:error, :not_supported} =
               Local.presigned_upload_url("key", "text/plain", [])
    end
  end
end
