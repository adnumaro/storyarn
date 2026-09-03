defmodule Storyarn.Platform.ObjectStorage.Adapters.LocalTest do
  use ExUnit.Case, async: false

  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Platform.ObjectStorage.Adapters.Local.ConditionalCopyRegistry

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

    test "reports cleanup ownership when a failed exclusive write cannot be removed", %{
      test_key: key,
      test_dir: test_dir
    } do
      configure_put_if_absent_write(fn path, _data ->
        :ok = File.write(path, "partial", [:binary, :exclusive])
        {:error, :enospc}
      end)

      configure_failed_write_remove(fn _path -> {:error, :eacces} end)

      assert {:error, {:storage_write_cleanup_required, ^key, :enospc, :eacces}} =
               Local.put_if_absent(key, "complete", "text/plain")

      assert File.read!(Path.join(test_dir, key)) == "partial"
      assert :ok = Local.delete(key)
    end
  end

  describe "upload_stream/3" do
    test "writes bounded chunks without assembling a caller-side binary", %{
      test_key: key,
      test_dir: test_dir
    } do
      chunks = [{:ok, "first-"}, {:ok, "second-"}, {:ok, "third"}]
      expected_url = "/test-uploads/#{key}"

      assert {:ok, ^expected_url} = Local.upload_stream(key, chunks, "text/plain")
      assert File.read!(Path.join(test_dir, key)) == "first-second-third"
    end

    test "removes a partial object when the source stream fails", %{
      test_key: key,
      test_dir: test_dir
    } do
      chunks = [{:ok, "partial"}, {:error, :source_timeout}]

      assert {:error, :source_timeout} = Local.upload_stream(key, chunks, "text/plain")
      refute File.exists?(Path.join(test_dir, key))
    end

    test "reports cleanup ownership when partial stream removal fails", %{
      test_key: key,
      test_dir: test_dir
    } do
      configure_failed_write_remove(fn _path -> {:error, :ebusy} end)
      chunks = [{:ok, "partial"}, {:error, :source_timeout}]

      assert {:error, {:storage_write_cleanup_required, ^key, :source_timeout, :ebusy}} =
               Local.upload_stream(key, chunks, "text/plain")

      assert File.read!(Path.join(test_dir, key)) == "partial"
      assert :ok = Local.delete(key)
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

  describe "delete_if_matches/2" do
    test "deletes only the listed object identity", %{test_dir: test_dir} do
      prefix = "conditional-delete/"
      key = prefix <> "object.bin"
      assert {:ok, _url} = Local.upload(key, "first", "application/octet-stream")

      assert {:ok, %{objects: [%{identity: identity}], cursor: nil}} =
               Local.list_prefix(prefix, [])

      assert :ok = Local.delete_if_matches(key, identity)
      refute File.exists?(Path.join(test_dir, key))
      assert :ok = Local.delete_if_matches(key, identity)
    end

    test "preserves a same-size replacement", %{test_dir: test_dir} do
      prefix = "conditional-replacement/"
      key = prefix <> "object.bin"
      assert {:ok, _url} = Local.upload(key, "first", "application/octet-stream")

      assert {:ok, %{objects: [%{identity: identity}]}} = Local.list_prefix(prefix, [])
      assert {:ok, _url} = Local.upload(key, "other", "application/octet-stream")

      assert {:error, :object_changed} = Local.delete_if_matches(key, identity)
      assert File.read!(Path.join(test_dir, key)) == "other"
    end

    test "never follows an ancestor symlink outside the storage root", %{test_dir: test_dir} do
      contents = "external"
      external_dir = external_storage_dir()
      external_path = Path.join(external_dir, "object.bin")
      linked_directory = Path.join(test_dir, "projects/1")
      key = "projects/1/object.bin"
      identity = :sha256 |> :crypto.hash(contents) |> Base.encode16(case: :lower)

      File.mkdir_p!(external_dir)
      File.write!(external_path, contents)
      File.mkdir_p!(Path.dirname(linked_directory))
      assert :ok = File.ln_s(Path.expand(external_dir), linked_directory)
      on_exit(fn -> File.rm_rf(external_dir) end)

      assert {:error, :unsafe_storage_entry} = Local.delete_if_matches(key, identity)
      assert File.read!(external_path) == contents
    end
  end

  describe "namespace_fingerprint/0" do
    test "matches fingerprints persisted before the adapter module moved under Projects", %{
      test_dir: test_dir
    } do
      File.mkdir_p!(test_dir)

      assert Local.namespace_fingerprint() ==
               {:ok, legacy_local_namespace_fingerprint(test_dir)}
    end

    test "binds the absolute storage root", %{test_dir: test_dir} do
      assert {:ok, original} = Local.namespace_fingerprint()
      assert original =~ ~r/\A[0-9a-f]{64}\z/

      Application.put_env(:storyarn, :storage,
        upload_dir: test_dir <> "_other",
        public_path: "/test-uploads"
      )

      assert {:ok, changed} = Local.namespace_fingerprint()
      refute changed == original
    end

    test "accepts a missing root without resolving through an unsafe entry", %{test_dir: test_dir} do
      missing_root = Path.join(test_dir, "missing/nested")

      Application.put_env(:storyarn, :storage,
        upload_dir: missing_root,
        public_path: "/test-uploads"
      )

      assert {:ok, fingerprint} = Local.namespace_fingerprint()
      assert fingerprint =~ ~r/\A[0-9a-f]{64}\z/
    end

    test "rejects a symlinked root and a symlinked ancestor", %{test_dir: test_dir} do
      target = test_dir <> "_target"
      root_link = Path.join(test_dir, "root-link")
      ancestor_link = Path.join(test_dir, "ancestor-link")
      File.mkdir_p!(target)
      File.mkdir_p!(test_dir)
      assert :ok = File.ln_s(Path.expand(target), root_link)
      assert :ok = File.ln_s(Path.expand(target), ancestor_link)
      on_exit(fn -> File.rm_rf(target) end)

      Application.put_env(:storyarn, :storage,
        upload_dir: root_link,
        public_path: "/test-uploads"
      )

      assert {:error, :unsafe_storage_entry} = Local.namespace_fingerprint()

      Application.put_env(:storyarn, :storage,
        upload_dir: Path.join(ancestor_link, "nested-root"),
        public_path: "/test-uploads"
      )

      assert {:error, :unsafe_storage_entry} = Local.namespace_fingerprint()
    end

    test "changes when the directory at the same configured root is replaced", %{test_dir: test_dir} do
      preserved_root = test_dir <> "_preserved"
      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf(preserved_root) end)

      assert {:ok, original} = Local.namespace_fingerprint()

      File.rename!(test_dir, preserved_root)
      File.mkdir_p!(test_dir)

      assert {:ok, replacement} = Local.namespace_fingerprint()
      refute replacement == original
    end

    test "stays stable when an unrelated sibling changes under an ancestor", %{test_dir: test_dir} do
      sibling = test_dir <> "_unrelated-sibling"
      File.mkdir_p!(test_dir)
      on_exit(fn -> File.rm_rf(sibling) end)

      assert {:ok, original} = Local.namespace_fingerprint()

      File.mkdir_p!(sibling)
      assert {:ok, with_sibling} = Local.namespace_fingerprint()
      assert with_sibling == original

      File.rm_rf!(sibling)
      assert {:ok, after_sibling} = Local.namespace_fingerprint()
      assert after_sibling == original
    end
  end

  defp legacy_local_namespace_fingerprint(root) do
    root = Path.expand(root)
    ["/" | components] = Path.split(root)

    {_path, identities} =
      Enum.reduce(components, {"/", [directory_identity!("/")]}, fn component, {parent, identities} ->
        path = Path.join(parent, component)
        {path, [directory_identity!(path) | identities]}
      end)

    ["Elixir.Storyarn.Assets.Storage.Local", root, Enum.reverse(identities)]
    |> Jason.encode_to_iodata!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp directory_identity!(path) do
    stat = File.lstat!(path)
    assert stat.type == :directory
    ["directory", path, stat.major_device, stat.minor_device, stat.inode]
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

  describe "object_probe/1" do
    test "never follows an ancestor symlink outside the storage root", %{test_dir: test_dir} do
      contents = "external"
      external_dir = external_storage_dir()
      external_path = Path.join(external_dir, "object.bin")
      linked_directory = Path.join(test_dir, "projects/1")
      key = "projects/1/object.bin"

      File.mkdir_p!(external_dir)
      File.write!(external_path, contents)
      File.mkdir_p!(Path.dirname(linked_directory))
      assert :ok = File.ln_s(Path.expand(external_dir), linked_directory)
      on_exit(fn -> File.rm_rf(external_dir) end)

      assert {:error, :unsafe_storage_entry} = Local.object_probe(key)
      assert File.read!(external_path) == contents
    end
  end

  describe "list_prefix/2" do
    test "returns stable bounded pages from only the exact canonical prefix" do
      prefix = "projects/1/snapshots/archives/v2/ready/AbCdEfGhIjKlMnOp/"

      for {filename, contents} <- [{"snapshot.zip", "one"}, {"manifest.json", "two"}, {"unexpected.tmp", "three"}] do
        assert {:ok, _url} = Local.upload(prefix <> filename, contents, "application/octet-stream")
      end

      assert {:ok, _url} =
               Local.upload(
                 "projects/1/snapshots/archives/v2/ready/OtherToken123456/snapshot.zip",
                 "outside",
                 "application/json"
               )

      assert {:ok, %{objects: first_page, cursor: cursor}} = Local.list_prefix(prefix, limit: 2)
      assert length(first_page) == 2
      assert is_binary(cursor)
      assert Enum.all?(first_page, &String.starts_with?(&1.key, prefix))
      assert Enum.all?(first_page, &String.match?(&1.identity, ~r/\A[0-9a-f]{64}\z/))

      assert :ok = first_page |> List.first() |> Map.fetch!(:key) |> Local.delete()

      assert {:ok, %{objects: second_page, cursor: nil}} = Local.list_prefix(prefix, limit: 2, cursor: cursor)

      assert (first_page ++ second_page) |> Enum.map(& &1.key) |> Enum.sort() ==
               Enum.sort([prefix <> "snapshot.zip", prefix <> "manifest.json", prefix <> "unexpected.tmp"])

      assert {:error, :invalid_prefix} = Local.list_prefix("", [])
      assert {:error, :invalid_prefix} = Local.list_prefix(prefix <> "/", [])
      assert {:error, :invalid_limit} = Local.list_prefix(prefix, limit: "all")
      assert {:error, :invalid_cursor} = Local.list_prefix(prefix, cursor: "not-an-offset")
    end

    test "returns an empty page only when the prefix directory is absent" do
      prefix = "projects/1/snapshots/archives/v2/ready/MissingToken1234/"

      assert {:ok, %{objects: [], cursor: nil}} = Local.list_prefix(prefix, [])
    end

    test "fails closed when the prefix resolves to a regular file" do
      root_key = "projects/1/snapshots/archives/v2/ready/NotADirectory123"
      assert {:ok, _url} = Local.upload(root_key, "not-a-directory", "application/octet-stream")

      assert {:error, :invalid_prefix_target} = Local.list_prefix(root_key <> "/", [])
    end

    test "propagates traversal errors instead of returning a partial inventory", %{test_dir: test_dir} do
      prefix = "projects/1/snapshots/archives/v2/ready/UnreadableDir123/"
      unreadable = Path.join([test_dir, prefix, "blocked"])
      File.mkdir_p!(unreadable)
      File.chmod!(unreadable, 0o000)

      try do
        assert {:error, :eacces} = Local.list_prefix(prefix, [])
      after
        File.chmod!(unreadable, 0o700)
      end
    end

    test "rejects unsafe filesystem entries", %{test_dir: test_dir} do
      prefix = "projects/1/snapshots/archives/v2/ready/UnsafeEntry1234/"
      prefix_path = Path.join(test_dir, prefix)
      File.mkdir_p!(prefix_path)
      assert :ok = File.ln_s(Path.expand(test_dir), Path.join(prefix_path, "linked"))

      assert {:error, :unsafe_storage_entry} = Local.list_prefix(prefix, [])
    end

    test "never inventories through an ancestor symlink outside the storage root", %{
      test_dir: test_dir
    } do
      prefix = "projects/1/snapshots/archives/v2/ready/LinkedPrefix1234/"
      external_dir = external_storage_dir()
      external_prefix_path = Path.join(external_dir, "snapshots/archives/v2/ready/LinkedPrefix1234")
      linked_directory = Path.join(test_dir, "projects/1")

      File.mkdir_p!(external_prefix_path)
      File.write!(Path.join(external_prefix_path, "manifest.json"), "external")
      File.mkdir_p!(Path.dirname(linked_directory))
      assert :ok = File.ln_s(Path.expand(external_dir), linked_directory)
      on_exit(fn -> File.rm_rf(external_dir) end)

      assert {:error, :unsafe_storage_entry} = Local.list_prefix(prefix, [])
    end

    test "keeps cursor order stable across sibling files and directories" do
      prefix = "projects/1/snapshots/archives/v2/ready/LexicalOrder1234/"

      for filename <- ["a.txt", "a/z.bin", "b.txt"] do
        assert {:ok, _url} = Local.upload(prefix <> filename, filename, "application/octet-stream")
      end

      assert {:ok, %{objects: [first], cursor: first_cursor}} = Local.list_prefix(prefix, limit: 1)

      assert {:ok, %{objects: [second], cursor: second_cursor}} =
               Local.list_prefix(prefix, limit: 1, cursor: first_cursor)

      assert {:ok, %{objects: [third], cursor: nil}} =
               Local.list_prefix(prefix, limit: 1, cursor: second_cursor)

      assert Enum.map([first, second, third], & &1.key) ==
               Enum.map(["a.txt", "a/z.bin", "b.txt"], &(prefix <> &1))
    end
  end

  describe "list_prefix_metadata/2" do
    test "paginates after non-canonical keys while identity listing stays strict", %{test_dir: test_dir} do
      prefix = "projects/"
      unsafe_key = prefix <> "a\\rogue"
      canonical_key = prefix <> "b"

      for {key, contents} <- [{unsafe_key, "unsafe"}, {canonical_key, "canonical"}] do
        path = Path.join(test_dir, key)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, contents)
      end

      assert {:ok, %{objects: [%{key: ^unsafe_key}], cursor: ^unsafe_key}} =
               Local.list_prefix_metadata(prefix, limit: 1)

      assert {:ok, %{objects: [%{key: ^canonical_key}], cursor: nil}} =
               Local.list_prefix_metadata(prefix, limit: 1, cursor: unsafe_key)

      assert {:error, :invalid_cursor} =
               Local.list_prefix_metadata(prefix, cursor: "outside/prefix")

      assert {:error, :unsafe_storage_entry} = Local.list_prefix(prefix, limit: 1)
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
      corrupt_owner_key = "abandoned/.storyarn-copy/IIIIIIIIIIIIIIII"
      invalid_reserved_key = "abandoned/.storyarn-copy/not-generated"
      ordinary_key = "active/file.storyarn-copy-CCCCCCCCCCCCCCCC"

      write_internal_file!(test_dir, stale_key, "stale")
      write_internal_file!(test_dir, fresh_key, "fresh")
      write_internal_file!(test_dir, corrupt_owner_key, "partial")
      write_internal_file!(test_dir, "#{corrupt_owner_key}.owner", "not-an-owner")
      write_internal_file!(test_dir, invalid_reserved_key, "reserved-but-not-generated")
      assert {:ok, _url} = Local.upload(ordinary_key, "ordinary", "application/octet-stream")

      stale_path = Path.join(test_dir, stale_key)
      fresh_path = Path.join(test_dir, fresh_key)
      corrupt_owner_path = Path.join(test_dir, corrupt_owner_key)
      invalid_reserved_path = Path.join(test_dir, invalid_reserved_key)
      ordinary_path = Path.join(test_dir, ordinary_key)
      symlink_path = Path.join(test_dir, "links/.storyarn-copy/DDDDDDDDDDDDDDDD")
      owner_symlink_path = Path.join(test_dir, "links/.storyarn-copy/GGGGGGGGGGGGGGGG.owner")
      directory_path = Path.join(test_dir, "directories/.storyarn-copy/EEEEEEEEEEEEEEEE")
      external_dir = Path.join(System.tmp_dir!(), "storyarn-copy-external-#{System.unique_integer([:positive])}")
      external_stale_path = Path.join(external_dir, ".storyarn-copy/FFFFFFFFFFFFFFFF")
      external_symlink_path = Path.join(test_dir, "external-link")

      File.mkdir_p!(Path.dirname(symlink_path))
      assert :ok = File.ln_s(Path.expand(ordinary_path), symlink_path)
      assert :ok = File.ln_s(Path.expand(external_stale_path), owner_symlink_path)
      File.mkdir_p!(directory_path)
      write_internal_file!(external_dir, ".storyarn-copy/FFFFFFFFFFFFFFFF", "external")
      assert :ok = File.ln_s(Path.expand(external_dir), external_symlink_path)
      assert :ok = File.touch(stale_path, {{2000, 1, 1}, {0, 0, 0}})
      assert :ok = File.touch(corrupt_owner_path, {{2000, 1, 1}, {0, 0, 0}})
      assert :ok = File.touch("#{corrupt_owner_path}.owner", {{2000, 1, 1}, {0, 0, 0}})
      assert :ok = File.touch(external_stale_path, {{2000, 1, 1}, {0, 0, 0}})

      on_exit(fn -> File.rm_rf(external_dir) end)

      configure_conditional_copy_stale_after_seconds(3_600)

      assert :ok = Local.cleanup_stale_conditional_copies()
      refute File.exists?(stale_path)
      refute File.exists?(corrupt_owner_path)
      refute File.exists?("#{corrupt_owner_path}.owner")
      assert File.read!(fresh_path) == "fresh"
      assert File.read!(invalid_reserved_path) == "reserved-but-not-generated"
      assert File.read!(ordinary_path) == "ordinary"
      assert {:ok, %{type: :symlink}} = File.lstat(symlink_path)
      assert {:ok, %{type: :symlink}} = File.lstat(owner_symlink_path)
      assert File.dir?(directory_path)
      assert File.read!(external_stale_path) == "external"
    end

    test "keeps an active stale copy and removes it after its owner crashes",
         %{test_dir: test_dir} do
      active_key = "long-running/.storyarn-copy/AAAAAAAAAAAAAAAA"
      active_path = Path.expand(Path.join(test_dir, active_key))
      write_internal_file!(test_dir, active_key, "partial")
      assert :ok = File.touch(active_path, {{2000, 1, 1}, {0, 0, 0}})

      parent = self()

      owner =
        spawn(fn ->
          ConditionalCopyRegistry.with_active_copy(active_path, fn ->
            send(parent, {:copy_registered, self()})
            Process.sleep(:infinity)
          end)
        end)

      assert_receive {:copy_registered, ^owner}
      configure_conditional_copy_stale_after_seconds(0)

      assert :ok = Local.cleanup_stale_conditional_copies()
      assert File.read!(active_path) == "partial"

      monitor = Process.monitor(owner)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}

      assert_eventually(fn ->
        assert :ok = Local.cleanup_stale_conditional_copies()
        refute File.exists?(active_path)
      end)
    end

    test "owner marker protects an active copy if its registry entry is lost",
         %{test_dir: test_dir} do
      active_key = "registry-restart/.storyarn-copy/HHHHHHHHHHHHHHHH"
      active_path = Path.expand(Path.join(test_dir, active_key))
      write_internal_file!(test_dir, active_key, "partial")
      assert :ok = File.touch(active_path, {{2000, 1, 1}, {0, 0, 0}})

      parent = self()

      owner =
        spawn(fn ->
          ConditionalCopyRegistry.with_active_copy(active_path, fn ->
            Registry.unregister(ConditionalCopyRegistry, active_path)
            send(parent, {:registry_entry_dropped, self()})
            Process.sleep(:infinity)
          end)
        end)

      assert_receive {:registry_entry_dropped, ^owner}
      configure_conditional_copy_stale_after_seconds(0)

      assert :ok = Local.cleanup_stale_conditional_copies()
      assert File.read!(active_path) == "partial"

      monitor = Process.monitor(owner)
      Process.exit(owner, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :killed}

      assert_eventually(fn ->
        assert :ok = Local.cleanup_stale_conditional_copies()
        refute File.exists?(active_path)

        refute File.exists?(ConditionalCopyRegistry.owner_marker_path(active_path))
      end)
    end

    test "a failed contender does not remove the active owner's marker",
         %{test_dir: test_dir} do
      active_key = "contended/.storyarn-copy/JJJJJJJJJJJJJJJJ"
      active_path = Path.expand(Path.join(test_dir, active_key))
      File.mkdir_p!(Path.dirname(active_path))
      parent = self()

      owner =
        spawn(fn ->
          ConditionalCopyRegistry.with_active_copy(active_path, fn ->
            send(parent, {:copy_registered, self()})

            receive do
              :finish -> :ok
            end
          end)
        end)

      assert_receive {:copy_registered, ^owner}

      assert {:error, {:conditional_copy_owner_marker_failed, :eexist}} =
               ConditionalCopyRegistry.with_active_copy(active_path, fn -> flunk("copy must not run") end)

      assert File.exists?(ConditionalCopyRegistry.owner_marker_path(active_path))

      monitor = Process.monitor(owner)
      send(owner, :finish)
      assert_receive {:DOWN, ^monitor, :process, ^owner, :normal}
      refute File.exists?(ConditionalCopyRegistry.owner_marker_path(active_path))
    end

    test "expires stale markers left by a previous node incarnation",
         %{test_dir: test_dir} do
      stale_key = "previous-node/.storyarn-copy/KKKKKKKKKKKKKKKK"
      stale_path = Path.expand(Path.join(test_dir, stale_key))
      marker_path = ConditionalCopyRegistry.owner_marker_path(stale_path)

      write_internal_file!(test_dir, stale_key, "partial")
      File.write!(marker_path, :erlang.term_to_binary({:previous@node, self()}))
      assert :ok = File.touch(stale_path, {{2000, 1, 1}, {0, 0, 0}})
      assert :ok = File.touch(marker_path, {{2000, 1, 1}, {0, 0, 0}})
      configure_conditional_copy_stale_after_seconds(3_600)

      assert :ok = Local.cleanup_stale_conditional_copies()
      refute File.exists?(stale_path)
      refute File.exists?(marker_path)
    end
  end

  defp configure_conditional_copy_remove(remove) do
    config =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.put(:conditional_copy_file_rm, remove)

    Application.put_env(:storyarn, :storage, config)
  end

  defp configure_failed_write_remove(remove) do
    config =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.put(:failed_write_file_rm, remove)

    Application.put_env(:storyarn, :storage, config)
  end

  defp configure_put_if_absent_write(write) do
    config =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.put(:put_if_absent_file_write, write)

    Application.put_env(:storyarn, :storage, config)
  end

  defp configure_conditional_copy_stale_after_seconds(seconds) do
    config =
      :storyarn
      |> Application.get_env(:storage, [])
      |> Keyword.put(:conditional_copy_stale_after_seconds, seconds)

    Application.put_env(:storyarn, :storage, config)
  end

  defp external_storage_dir do
    Path.join(
      System.tmp_dir!(),
      "storyarn-local-storage-external-#{System.unique_integer([:positive])}"
    )
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

  defp assert_eventually(assertion, attempts \\ 20)

  defp assert_eventually(assertion, attempts) when attempts > 1 do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(5)
      assert_eventually(assertion, attempts - 1)
  end

  defp assert_eventually(assertion, 1), do: assertion.()

  # =============================================================================
  # presigned_upload_url/3
  # =============================================================================

  describe "presigned_upload_url/3" do
    test "returns error not_supported" do
      assert {:error, :not_supported} =
               Local.presigned_upload_url("key", "text/plain", [])
    end
  end

  describe "presigned_download_url/3" do
    test "keeps local private downloads on the authorized application route" do
      assert {:error, :not_supported} =
               Local.presigned_download_url("projects/1/archive.zip", "application/zip",
                 expires_in: 300,
                 filename: "snapshot.zip"
               )
    end
  end
end
