defmodule Storyarn.Versioning.SnapshotObjectStorageTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Repo
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Versioning.SnapshotStorage

  describe "persist/4 and load_verified/4" do
    test "publishes an independently verified, retryable object set with one blob per hash" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "verified image bytes"
      hash = sha256(content)
      first_key = source_key(project_id, "first.png")
      second_key = source_key(project_id, "second.png")
      assert {:ok, _url} = Storage.upload(first_key, content, "image/png")
      assert {:ok, _url} = Storage.upload(second_key, content, "image/png")

      first = asset(101, project_id, "same-name.png", first_key, content, hash, %{"variant_asset_ids" => %{"web" => 102}})

      second =
        asset(102, project_id, "same-name.png", second_key, content, hash, %{
          "is_variant" => true,
          "original_asset_id" => 101,
          "variant_profile" => "web"
        })

      project = project_object([first, second])

      assert {:ok, stored} =
               SnapshotObjectStorage.persist(project_id, project, [first, second], token: token)

      assert stored.format_version == 1
      assert stored.asset_count == 2
      assert stored.blob_count == 1
      assert stored.object_count == 3
      assert stored.total_size_bytes > stored.manifest_size_bytes
      assert SnapshotObjectStorage.ready_manifest_key?(stored.manifest_storage_key)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      assert length(loaded.manifest["assets"]) == 2
      assert length(Enum.filter(loaded.manifest["objects"], &(&1["kind"] == "asset_blob"))) == 1
      refute get_in(loaded.project, ["asset_metadata", "101", "key"])
      refute get_in(loaded.project, ["asset_metadata", "101", "url"])
      refute get_in(loaded.project, ["asset_metadata", "101", "project_id"])

      assert {:ok, retried} =
               SnapshotObjectStorage.persist(project_id, project, [first, second], token: token)

      assert retried == stored

      staging_manifest =
        SnapshotObjectStorage.staging_prefix(project_id, token) <> "/manifest.json"

      refute SnapshotObjectStorage.ready_manifest_key?(staging_manifest)

      assert {:error, :invalid_ready_manifest_key} =
               SnapshotObjectStorage.load_verified(
                 staging_manifest,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [first_key, second_key])
    end

    test "detects a replaced snapshot-owned blob before returning project data" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "original verified bytes"
      hash = sha256(content)
      key = source_key(project_id, "tamper.png")
      assert {:ok, _url} = Storage.upload(key, content, "image/png")
      asset = asset(201, project_id, "tamper.png", key, content, hash)

      assert {:ok, stored} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      blob = Enum.find(loaded.manifest["objects"], &(&1["kind"] == "asset_blob"))
      blob_key = stored.object_prefix <> "/" <> blob["path"]
      assert {:ok, _url} = Storage.upload(blob_key, "replaced", "image/png")

      assert {:error, {:snapshot_object_size_mismatch, _, _, _}} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [key])
    end

    test "a failed source copy never publishes a ready manifest" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "missing source"

      asset =
        asset(
          301,
          project_id,
          "missing.png",
          source_key(project_id, "missing.png"),
          content,
          sha256(content)
        )

      assert {:error, _reason} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      ready_manifest = SnapshotObjectStorage.ready_prefix(project_id, token) <> "/manifest.json"
      assert {:error, _reason} = Storage.stat(ready_manifest)

      cleanup_keys = [
        SnapshotObjectStorage.staging_prefix(project_id, token) <> "/project.json",
        ready_manifest
      ]

      Enum.each(cleanup_keys, &Storage.delete/1)
    end

    test "rejects source content that does not match the captured SHA-256" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      captured_content = "captured bytes"
      replaced_content = "replaced bytes"
      assert byte_size(captured_content) == byte_size(replaced_content)
      key = source_key(project_id, "changed.png")
      assert {:ok, _url} = Storage.upload(key, replaced_content, "image/png")

      asset =
        asset(
          401,
          project_id,
          "changed.png",
          key,
          captured_content,
          sha256(captured_content)
        )

      assert {:error, {:snapshot_object_checksum_mismatch, _, _}} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      ready_manifest = SnapshotObjectStorage.ready_prefix(project_id, token) <> "/manifest.json"
      assert {:error, _reason} = Storage.stat(ready_manifest)

      _deleted = Storage.delete(key)
      _deleted = Storage.delete(SnapshotObjectStorage.staging_prefix(project_id, token) <> "/project.json")
    end

    test "hashes and decodes the same manifest and project byte buffers" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "single read verification"
      hash = sha256(content)
      source = source_key(project_id, "single-read.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(501, project_id, "single-read.png", source, content, hash)

      assert {:ok, stored} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      project_key = stored.project_storage_key

      replacements = %{
        stored.manifest_storage_key => String.duplicate(" ", stored.manifest_size_bytes),
        project_key => String.duplicate(" ", stored.project_size_bytes)
      }

      original_config = Application.get_env(:storyarn, :storage, [])
      {:ok, _pid} = SnapshotReadSwitchStorage.start_link(replacements)

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_config, :adapter, SnapshotReadSwitchStorage)
      )

      on_exit(fn ->
        Application.put_env(:storyarn, :storage, original_config)

        if Process.whereis(SnapshotReadSwitchStorage) do
          Agent.stop(SnapshotReadSwitchStorage)
        end
      end)

      SnapshotReadSwitchStorage.reset_counts()

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      assert loaded.project["format_version"] == 2
      assert SnapshotReadSwitchStorage.stream_count(stored.manifest_storage_key) == 1
      assert SnapshotReadSwitchStorage.stream_count(project_key) == 1

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "durably compensates a failed local staging write before returning" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "staging write cleanup"
      source = source_key(project_id, "staging.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(601, project_id, "staging.png", source, content, sha256(content))
      original_config = Application.get_env(:storyarn, :storage, [])

      write_partial = fn path, _data ->
        :ok = File.write(path, "partial", [:binary, :exclusive])
        {:error, :enospc}
      end

      Application.put_env(
        :storyarn,
        :storage,
        original_config
        |> Keyword.put(:put_if_absent_file_write, write_partial)
        |> Keyword.put(:failed_write_file_rm, fn _path -> {:error, :eacces} end)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_config) end)

      staging_project = SnapshotObjectStorage.staging_prefix(project_id, token) <> "/project.json"

      assert {:error, {:storage_write_cleanup_required, ^staging_project, :enospc, :eacces}} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      assert {:error, :enoent} = Storage.stat(staging_project)
      assert :ok = Storage.delete(source)
    end

    test "compensates a published snapshot object and pending conditional-copy key" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "conditional snapshot cleanup"
      hash = sha256(content)
      source = source_key(project_id, "conditional.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(701, project_id, "conditional.png", source, content, hash)
      original_config = Application.get_env(:storyarn, :storage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_config, :conditional_copy_file_rm, fn _path -> {:error, :ebusy} end)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_config) end)

      assert {:error, {:conditional_copy_cleanup_required, true, pending_cleanup_key, :ebusy}} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      staging_prefix = SnapshotObjectStorage.staging_prefix(project_id, token)
      staging_blob = staging_prefix <> "/blobs/#{hash}.png"
      assert {:error, :enoent} = Storage.stat(staging_blob)

      upload_dir =
        :storyarn
        |> Application.get_env(:storage, [])
        |> Keyword.get(:upload_dir, "priv/static/uploads")
        |> Path.expand()

      refute File.exists?(Path.join(upload_dir, pending_cleanup_key))

      assert :ok = Storage.delete(staging_prefix <> "/project.json")
      assert :ok = Storage.delete(source)
    end

    test "deferred compensation retains an object set adopted by a committed snapshot row" do
      user = user_fixture()
      project_record = project_fixture(user)
      project_id = project_record.id
      token = SnapshotStorage.unique_key_suffix()
      content = "adopted snapshot object"
      source = source_key(project_id, "adopted.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(801, project_id, "adopted.png", source, content, sha256(content))

      assert {:ok, stored} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      attrs = Map.merge(stored, %{project_id: project_id, version_number: 1})

      assert {:ok, _snapshot} =
               %ProjectSnapshot{}
               |> ProjectSnapshot.object_set_changeset(attrs)
               |> Repo.insert()

      tracker = StorageCompensation.new()
      :ok = StorageCompensation.track_force_delete(tracker, stored.project_storage_key)
      assert :ok = StorageCompensation.cleanup_after_rollback(tracker)
      assert {:ok, _stat} = Storage.stat(stored.project_storage_key)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end
  end

  defp project_object(assets) do
    assets = List.wrap(assets)

    metadata =
      Map.new(assets, fn asset ->
        {to_string(asset.id),
         %{
           "filename" => asset.filename,
           "content_type" => asset.content_type,
           "size" => asset.size,
           "key" => asset.key,
           "url" => asset.url,
           "project_id" => asset.project_id,
           "blob_key" => "projects/#{asset.project_id}/blobs/#{asset.blob_hash}.png"
         }}
      end)

    %{
      "format_version" => 2,
      "project" => %{"description" => "Self-contained"},
      "entity_counts" => %{},
      "asset_metadata" => metadata,
      "asset_blob_hashes" => Map.new(assets, &{to_string(&1.id), &1.blob_hash}),
      "sheets" => [],
      "flows" => [],
      "scenes" => [],
      "tree" => %{"sheets" => [], "flows" => [], "scenes" => []},
      "localization" => %{"languages" => [], "texts" => [], "glossary" => []}
    }
  end

  defp asset(id, project_id, filename, key, content, hash, metadata \\ %{}) do
    %Asset{
      id: id,
      project_id: project_id,
      filename: filename,
      content_type: "image/png",
      size: byte_size(content),
      blob_hash: hash,
      key: key,
      url: "/uploads/#{key}",
      metadata: metadata,
      inserted_at: DateTime.from_unix!(id)
    }
  end

  defp cleanup_object_set(project_id, token, manifest, source_keys) do
    prefixes = [
      SnapshotObjectStorage.staging_prefix(project_id, token),
      SnapshotObjectStorage.ready_prefix(project_id, token)
    ]

    relative_paths = ["manifest.json" | Enum.map(manifest["objects"], & &1["path"])]

    Enum.each(prefixes, fn prefix ->
      Enum.each(relative_paths, &Storage.delete(prefix <> "/" <> &1))
    end)

    Enum.each(source_keys, &Storage.delete/1)
  end

  defp source_key(project_id, filename) do
    "projects/#{project_id}/assets/#{Ecto.UUID.generate()}/#{filename}"
  end

  defp unique_project_id, do: System.unique_integer([:positive])

  defp sha256(data) do
    data
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
