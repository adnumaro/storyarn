defmodule Storyarn.Assets.Storage.LocalTest do
  use ExUnit.Case, async: false

  alias Storyarn.Assets.Storage.Local

  setup do
    # Each test gets its own unique directory to avoid async race conditions
    unique_id = System.unique_integer([:positive])
    test_dir = "test/tmp/uploads_#{unique_id}"
    test_key = "test_#{unique_id}/file.txt"

    original_config = Application.get_env(:storyarn, :storage, [])

    Application.put_env(:storyarn, :storage,
      upload_dir: test_dir,
      public_path: "/test-uploads"
    )

    on_exit(fn ->
      Application.put_env(:storyarn, :storage, original_config)
      File.rm_rf(test_dir)
    end)

    %{test_key: test_key, test_dir: test_dir}
  end

  # =============================================================================
  # upload/3
  # =============================================================================

  describe "upload/3" do
    test "writes file to disk and returns URL", %{test_key: key, test_dir: test_dir} do
      data = "Hello, World!"
      assert {:ok, url} = Local.upload(key, data, "text/plain")
      assert url == "/test-uploads/#{key}"

      # Verify file was written
      path = Path.join(test_dir, key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates intermediate directories", %{test_dir: test_dir} do
      nested_key = "deep/nested/dir/file.txt"
      assert {:ok, _url} = Local.upload(nested_key, "content", "text/plain")

      path = Path.join(test_dir, nested_key)
      assert File.exists?(path)
    end

    test "handles binary data", %{test_dir: test_dir} do
      key = "test_binary_#{System.unique_integer([:positive])}/image.png"
      # Small PNG header bytes
      data = <<137, 80, 78, 71, 13, 10, 26, 10>>
      assert {:ok, _url} = Local.upload(key, data, "image/png")

      path = Path.join(test_dir, key)
      assert File.read!(path) == data
    end

    test "rejects traversal and absolute keys", %{test_dir: test_dir} do
      refute File.exists?(Path.join(Path.dirname(test_dir), "escaped.txt"))

      assert {:error, :invalid_key} = Local.upload("../escaped.txt", "content", "text/plain")
      assert {:error, :invalid_key} = Local.upload("/tmp/escaped.txt", "content", "text/plain")
      assert {:error, :invalid_key} = Local.upload("nested\\escaped.txt", "content", "text/plain")
      assert {:error, :invalid_key} = Local.upload(<<255>>, "content", "text/plain")

      refute File.exists?(Path.join(Path.dirname(test_dir), "escaped.txt"))
    end
  end

  describe "put_if_absent/3" do
    test "creates once without overwriting an existing object", %{test_key: key, test_dir: test_dir} do
      expected_url = "/test-uploads/#{key}"
      assert {:ok, ^expected_url, true} = Local.put_if_absent(key, "first", "text/plain")

      assert {:ok, ^expected_url, false} = Local.put_if_absent(key, "second", "text/plain")

      assert File.read!(Path.join(test_dir, key)) == "first"
    end
  end

  # =============================================================================
  # delete/1
  # =============================================================================

  describe "delete/1" do
    test "deletes existing file", %{test_dir: test_dir} do
      key = "delete_test_#{System.unique_integer([:positive])}/file.txt"
      {:ok, _} = Local.upload(key, "content", "text/plain")

      assert :ok = Local.delete(key)

      path = Path.join(test_dir, key)
      refute File.exists?(path)
    end

    test "returns :ok for non-existent file (enoent)" do
      key = "nonexistent/file.txt"
      assert :ok = Local.delete(key)
    end

    test "rejects traversal keys" do
      assert {:error, :invalid_key} = Local.delete("../escaped.txt")
    end
  end

  describe "download/1" do
    test "rejects traversal keys" do
      assert {:error, :invalid_key} = Local.download("../escaped.txt")
    end
  end

  describe "stat/1 and stream/4" do
    test "returns object metadata and streams only the requested byte range", %{test_key: key} do
      assert {:ok, _url} = Local.upload(key, "0123456789", "text/plain")

      assert {:ok, %{size: 10, etag: nil, content_type: "text/plain"}} = Local.stat(key)
      assert {:ok, stream} = Local.stream(key, 2, 4, [])
      assert Enum.to_list(stream) == [{:ok, "2345"}]
    end

    test "reports an unexpected length instead of reading past the file", %{test_key: key} do
      assert {:ok, _url} = Local.upload(key, "0123456789", "text/plain")
      assert {:ok, stream} = Local.stream(key, 8, 4, [])

      assert Enum.to_list(stream) == [{:error, {:unexpected_length, 2, 4}}]
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

    test "raises for traversal keys" do
      assert_raise ArgumentError, "invalid storage key", fn ->
        Local.get_url("../escaped.txt")
      end
    end
  end

  describe "key_from_url/1" do
    test "extracts a valid key from a persisted local URL" do
      assert Local.key_from_url("/test-uploads/project/image.png") ==
               {:ok, "project/image.png"}
    end

    test "rejects another path and traversal" do
      assert Local.key_from_url("/other/project/image.png") == {:error, :invalid_url}
      assert Local.key_from_url("/test-uploads/../private.txt") == {:error, :invalid_url}
    end
  end

  describe "copy/2" do
    test "rejects traversal destination keys", %{test_key: key} do
      assert {:ok, _url} = Local.upload(key, "content", "text/plain")
      assert {:error, :invalid_key} = Local.copy(key, "../escaped.txt")
    end
  end

  describe "copy_if_absent/2" do
    test "copies a large source once without replacing the destination", %{test_dir: test_dir} do
      source_key = "copy/source.bin"
      destination_key = "copy/destination.bin"
      source = :binary.copy("bounded-copy-", 200_000)

      assert byte_size(source) > 2_000_000
      assert {:ok, _url} = Local.upload(source_key, source, "application/octet-stream")
      assert {:ok, true} = Local.copy_if_absent(source_key, destination_key)

      assert {:ok, _url} = Local.upload(source_key, "replacement", "application/octet-stream")
      assert {:ok, false} = Local.copy_if_absent(source_key, destination_key)
      assert File.read!(Path.join(test_dir, destination_key)) == source

      assert conditional_copy_paths(test_dir, destination_key) == []
    end

    test "claims destination ownership for exactly one concurrent caller", %{test_dir: test_dir} do
      first_source_key = "race/first.bin"
      second_source_key = "race/second.bin"
      destination_key = "race/destination.bin"

      assert {:ok, _url} = Local.upload(first_source_key, "first", "application/octet-stream")
      assert {:ok, _url} = Local.upload(second_source_key, "second", "application/octet-stream")

      results =
        [first_source_key, second_source_key]
        |> Task.async_stream(&Local.copy_if_absent(&1, destination_key),
          max_concurrency: 2,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.count(results, &(&1 == {:ok, true})) == 1
      assert Enum.count(results, &(&1 == {:ok, false})) == 1
      assert File.read!(Path.join(test_dir, destination_key)) in ["first", "second"]

      assert conditional_copy_paths(test_dir, destination_key) == []
    end

    test "reports a durable cleanup key when a published temporary link cannot be removed",
         %{test_dir: test_dir} do
      source_key = "cleanup/source.bin"
      destination_key = "cleanup/destination.bin"
      configure_conditional_copy_remove(fn _path -> {:error, :eacces} end)

      assert {:ok, _url} = Local.upload(source_key, "source", "application/octet-stream")

      assert {:error, {:conditional_copy_cleanup_required, true, temporary_key, :eacces}} =
               Local.copy_if_absent(source_key, destination_key)

      assert Path.dirname(temporary_key) ==
               Path.join(Path.dirname(destination_key), ".storyarn-copy")

      assert Path.basename(temporary_key) =~ ~r/\A[A-Za-z0-9_-]{16}\z/
      assert File.read!(Path.join(test_dir, destination_key)) == "source"
      assert File.read!(Path.join(test_dir, temporary_key)) == "source"

      assert :ok = Local.delete(temporary_key)
      refute File.exists?(Path.join(test_dir, temporary_key))
      assert File.read!(Path.join(test_dir, destination_key)) == "source"
    end

    test "does not claim an existing destination when temporary cleanup is pending",
         %{test_dir: test_dir} do
      source_key = "cleanup-existing/source.bin"
      destination_key = "cleanup-existing/destination.bin"
      configure_conditional_copy_remove(fn _path -> {:error, :ebusy} end)

      assert {:ok, _url} = Local.upload(source_key, "source", "application/octet-stream")
      assert {:ok, _url} = Local.upload(destination_key, "existing", "application/octet-stream")

      assert {:error, {:conditional_copy_cleanup_required, false, temporary_key, :ebusy}} =
               Local.copy_if_absent(source_key, destination_key)

      assert File.read!(Path.join(test_dir, destination_key)) == "existing"
      assert File.read!(Path.join(test_dir, temporary_key)) == "source"

      assert :ok = Local.delete(temporary_key)
      assert File.read!(Path.join(test_dir, destination_key)) == "existing"
    end

    test "does not create a destination when the source is missing", %{test_dir: test_dir} do
      destination_key = "missing/destination.bin"

      assert {:error, :enoent} = Local.copy_if_absent("missing/source.bin", destination_key)
      refute File.exists?(Path.join(test_dir, destination_key))
    end

    test "rejects traversal in either key", %{test_key: key} do
      assert {:ok, _url} = Local.upload(key, "content", "text/plain")
      assert {:error, :invalid_key} = Local.copy_if_absent("../source.txt", "safe/destination.txt")
      assert {:error, :invalid_key} = Local.copy_if_absent(key, "../destination.txt")
    end

    test "reserves the conditional-copy namespace from ordinary storage writes" do
      reserved_key = "ordinary/.storyarn-copy/AAAAAAAAAAAAAAAA"

      assert {:error, :invalid_key} =
               Local.upload(reserved_key, "content", "application/octet-stream")

      assert {:error, :invalid_key} =
               Local.put_if_absent(reserved_key, "content", "application/octet-stream")

      assert {:error, :invalid_key} = Local.download(reserved_key)
    end

    test "sweeps stale conditional-copy files left by a terminated process",
         %{test_dir: test_dir} do
      stale_key = "abandoned/.storyarn-copy/AAAAAAAAAAAAAAAA"
      fresh_key = "active/.storyarn-copy/BBBBBBBBBBBBBBBB"
      invalid_reserved_key = "abandoned/.storyarn-copy/not-generated"
      ordinary_key = "active/file.storyarn-copy-CCCCCCCCCCCCCCCC"

      write_internal_file!(test_dir, stale_key, "stale")
      write_internal_file!(test_dir, fresh_key, "fresh")
      write_internal_file!(test_dir, invalid_reserved_key, "reserved-but-not-generated")
      assert {:ok, _url} = Local.upload(ordinary_key, "ordinary", "application/octet-stream")

      stale_path = Path.join(test_dir, stale_key)
      fresh_path = Path.join(test_dir, fresh_key)
      invalid_reserved_path = Path.join(test_dir, invalid_reserved_key)
      ordinary_path = Path.join(test_dir, ordinary_key)
      symlink_path = Path.join(test_dir, "links/.storyarn-copy/DDDDDDDDDDDDDDDD")
      directory_path = Path.join(test_dir, "directories/.storyarn-copy/EEEEEEEEEEEEEEEE")
      external_dir = Path.join(System.tmp_dir!(), "storyarn-copy-external-#{System.unique_integer([:positive])}")
      external_stale_path = Path.join(external_dir, ".storyarn-copy/FFFFFFFFFFFFFFFF")
      external_symlink_path = Path.join(test_dir, "external-link")

      File.mkdir_p!(Path.dirname(symlink_path))
      assert :ok = File.ln_s(Path.expand(ordinary_path), symlink_path)
      File.mkdir_p!(directory_path)
      write_internal_file!(external_dir, ".storyarn-copy/FFFFFFFFFFFFFFFF", "external")
      assert :ok = File.ln_s(Path.expand(external_dir), external_symlink_path)
      assert :ok = File.touch(stale_path, {{2000, 1, 1}, {0, 0, 0}})
      assert :ok = File.touch(external_stale_path, {{2000, 1, 1}, {0, 0, 0}})

      on_exit(fn -> File.rm_rf(external_dir) end)

      configure_conditional_copy_stale_after_seconds(3_600)

      assert :ok = Local.cleanup_stale_conditional_copies()
      refute File.exists?(stale_path)
      assert File.read!(fresh_path) == "fresh"
      assert File.read!(invalid_reserved_path) == "reserved-but-not-generated"
      assert File.read!(ordinary_path) == "ordinary"
      assert {:ok, %{type: :symlink}} = File.lstat(symlink_path)
      assert File.dir?(directory_path)
      assert File.read!(external_stale_path) == "external"
    end
  end

  defp configure_conditional_copy_remove(remove) do
    config =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.put(:conditional_copy_file_rm, remove)

    Application.put_env(:storyarn, :storage, config)
  end

  defp configure_conditional_copy_stale_after_seconds(seconds) do
    config =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.put(:conditional_copy_stale_after_seconds, seconds)

    Application.put_env(:storyarn, :storage, config)
  end

  defp conditional_copy_paths(test_dir, destination_key) do
    test_dir
    |> Path.join(Path.dirname(destination_key))
    |> Path.join(".storyarn-copy/*")
    |> Path.wildcard(match_dot: true)
  end

  defp write_internal_file!(root, key, contents) do
    path = Path.join(root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
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
