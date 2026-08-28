defmodule Storyarn.Projects.Assets.BlobStoreTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Platform.Billing
  alias Storyarn.Platform.ObjectStorage.Adapters.Local
  alias Storyarn.Projects.Assets
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Assets.BlobStore
  alias Storyarn.Projects.Assets.Storage
  alias Storyarn.Projects.Assets.StorageCompensation
  alias Storyarn.Projects.Project
  alias Storyarn.SnapshotReadSwitchStorage

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

  describe "compatible_content_type?/2" do
    test "accepts exact metadata and the two historical v1 audio mappings" do
      assert BlobStore.compatible_content_type?("image/png", "image/png")
      assert BlobStore.compatible_content_type?("application/octet-stream", "audio/ogg")
      assert BlobStore.compatible_content_type?("video/webm", "audio/webm")

      refute BlobStore.compatible_content_type?("application/octet-stream", "application/json")
      refute BlobStore.compatible_content_type?(nil, nil)
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
      assert {:ok, ^key, false} = BlobStore.ensure_blob_with_status(project.id, hash, "png", first)
      assert {:ok, ^first} = Storage.download(key)
    end

    test "rejects bytes that do not match the requested content hash", %{project: project} do
      expected_hash = BlobStore.compute_hash("expected")

      assert {:error, :blob_hash_mismatch} =
               BlobStore.ensure_blob_with_status(project.id, expected_hash, "png", "different")

      assert {:error, :enoent} =
               Storage.download(BlobStore.blob_key(project.id, expected_hash, "png"))
    end

    test "persists canonical audio metadata instead of the generic extension MIME", %{
      project: project,
      user: user
    } do
      original_config = Application.get_env(:storyarn, :storage, [])
      {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})

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

      content = "ogg upload bytes"

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "voice.ogg", content_type: "audio/ogg"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "ogg")
      assert SnapshotReadSwitchStorage.put_content_type(blob_key) == "audio/ogg"

      webm = "webm upload bytes"
      webm_hash = BlobStore.compute_hash(webm)

      assert {:ok, webm_key, true} =
               BlobStore.ensure_blob_with_status(project.id, webm_hash, "webm", webm)

      assert SnapshotReadSwitchStorage.put_content_type(webm_key) == "audio/webm"
    end
  end

  describe "ensure_asset_blob/1" do
    test "accepts a verified canonical blob before consulting a legacy source key", %{
      project: project,
      user: user
    } do
      content = "canonical bytes survive legacy key drift"

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "legacy-key.png", content_type: "image/png"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
      legacy_asset = %{asset | key: "legacy/noncanonical/#{asset.id}.png"}

      on_exit(fn ->
        Storage.delete(asset.key)
        delete_storage_blob(blob_key)
      end)

      assert {:ok, ^blob_key, :present} = BlobStore.ensure_asset_blob(legacy_asset)
      assert {:ok, ^content} = Storage.download(blob_key)
    end

    test "reconstructs a missing canonical blob from the verified original", %{
      project: project,
      user: user
    } do
      content = "legacy asset bytes"

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "legacy.png", content_type: "image/png"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
      assert :ok = delete_storage_blob(blob_key)

      on_exit(fn ->
        Storage.delete(asset.key)
        delete_storage_blob(blob_key)
      end)

      assert {:ok, ^blob_key, :repaired} = BlobStore.ensure_asset_blob(asset)
      assert {:ok, ^content} = Storage.download(blob_key)
      assert {:ok, ^blob_key, :present} = BlobStore.ensure_asset_blob(asset)
    end

    test "replaces a checksum-corrupt canonical blob only after verifying the original", %{
      project: project,
      user: user
    } do
      content = "verified-canonical-bytes"
      corrupt = "corrupt!-canonical-bytes"
      assert byte_size(content) == byte_size(corrupt)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "corrupt-canonical.png", content_type: "image/png"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
      assert {:ok, _url} = Storage.upload(blob_key, corrupt, "image/png")

      on_exit(fn ->
        Storage.delete(asset.key)
        delete_storage_blob(blob_key)
      end)

      assert {:ok, ^blob_key, :repaired} = BlobStore.ensure_asset_blob(asset)
      assert {:ok, ^content} = Storage.download(blob_key)
    end

    test "preserves a valid canonical replacement that wins after corrupt bytes are observed", %{
      project: project,
      user: user
    } do
      content = "concurrent-valid-bytes"
      corrupt = "concurrent-bad!!-bytes"
      assert byte_size(content) == byte_size(corrupt)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "concurrent-canonical.png", content_type: "image/png"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
      assert {:ok, _url} = Storage.upload(blob_key, corrupt, "image/png")

      original_config = Application.get_env(:storyarn, :storage, [])
      {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})
      destination_reads = :atomics.new(1, signed: false)

      SnapshotReadSwitchStorage.set_stream_result(fn key, offset, length, opts ->
        if key == blob_key and :atomics.add_get(destination_reads, 1, 1) == 2 do
          assert {:ok, _url} = Local.upload(blob_key, content, "image/png")
        end

        Local.stream(key, offset, length, opts)
      end)

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

        Storage.delete(asset.key)
        delete_storage_blob(blob_key)
      end)

      assert {:ok, ^blob_key, :present} = BlobStore.ensure_asset_blob(asset)
      assert {:ok, ^content} = Local.download(blob_key)
    end

    test "retries then repairs when a concurrent copy winner has invalid content type", %{
      project: project,
      user: user
    } do
      content = "concurrent-mime-winner"

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "concurrent-mime.png", content_type: "image/png"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
      assert :ok = delete_storage_blob(blob_key)

      original_config = Application.get_env(:storyarn, :storage, [])
      {:ok, _pid} = SnapshotReadSwitchStorage.start_link(%{})
      destination_stats = :atomics.new(1, signed: false)

      SnapshotReadSwitchStorage.set_stat_result(fn key ->
        if key == blob_key and :atomics.add_get(destination_stats, 1, 1) == 1 do
          assert {:ok, _url} = Local.upload(blob_key, content, "image/png")
          {:error, :enoent}
        else
          case Local.stat(key) do
            {:ok, stat} when key == blob_key -> {:ok, %{stat | content_type: "application/pdf"}}
            result -> result
          end
        end
      end)

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

        Storage.delete(asset.key)
        delete_storage_blob(blob_key)
      end)

      assert {:error, :asset_blob_replacement_pending} = BlobStore.ensure_asset_blob(asset)
      assert {:ok, %{content_type: "application/pdf"}} = Storage.stat(blob_key)

      second_round_stats = :atomics.new(1, signed: false)

      SnapshotReadSwitchStorage.set_stat_result(fn key ->
        case Local.stat(key) do
          {:ok, stat} when key == blob_key ->
            if :atomics.add_get(second_round_stats, 1, 1) == 1,
              do: {:ok, %{stat | content_type: "application/pdf"}},
              else: {:ok, stat}

          result ->
            result
        end
      end)

      assert {:ok, ^blob_key, :repaired} = BlobStore.ensure_asset_blob(asset)
      assert {:ok, %{content_type: "image/png"}} = Local.stat(blob_key)
      assert {:ok, ^content} = Local.download(blob_key)
    end

    test "refuses to reconstruct from original bytes that do not match the persisted hash", %{
      project: project,
      user: user
    } do
      content = "expected-source"
      tampered = "tampered-source"
      assert byte_size(content) == byte_size(tampered)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "tampered.png", content_type: "image/png"},
                 project,
                 user
               )

      blob_key = BlobStore.blob_key(project.id, asset.blob_hash, "png")
      assert :ok = delete_storage_blob(blob_key)
      assert {:ok, _url} = Storage.upload(asset.key, tampered, "image/png")

      on_exit(fn ->
        Storage.delete(asset.key)
        delete_storage_blob(blob_key)
      end)

      assert {:error, :blob_hash_mismatch} = BlobStore.ensure_asset_blob(asset)
      assert {:error, :enoent} = Storage.download(blob_key)
    end

    test "repairs each unique blob once and falls back across equivalent originals", %{
      project: project,
      user: user
    } do
      content = "shared legacy asset bytes"

      assert {:ok, first} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "first.png", content_type: "image/png"},
                 project,
                 user
               )

      assert {:ok, second} =
               Assets.upload_binary_and_create_asset(
                 content,
                 %{filename: "second.png", content_type: "image/png"},
                 project,
                 user
               )

      assert first.blob_hash == second.blob_hash
      blob_key = BlobStore.blob_key(project.id, first.blob_hash, "png")
      assert :ok = delete_storage_blob(blob_key)
      assert :ok = Storage.delete(first.key)

      on_exit(fn ->
        Storage.delete(second.key)
        delete_storage_blob(blob_key)
      end)

      assert {:ok, summary} = Assets.ensure_active_asset_blobs(project.id)

      assert summary == %{
               asset_count: 2,
               blob_count: 1,
               repaired_blob_count: 1
             }

      assert {:ok, ^content} = Storage.download(blob_key)
    end
  end

  describe "create_asset_from_blob/5" do
    test "requires the canonical workspace lock inside an existing transaction", %{
      project: project,
      user: user
    } do
      content = "transactional asset restore"
      hash = BlobStore.compute_hash(content)
      blob_key = BlobStore.blob_key(project.id, hash, "png")
      tracker = StorageCompensation.new()

      assert {:ok, ^blob_key} = BlobStore.ensure_blob(project.id, hash, "png", content)

      metadata = %{
        "filename" => "restored.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:ok, {:error, :asset_materialization_requires_workspace_lock}} =
               Repo.transaction(fn ->
                 BlobStore.create_asset_from_blob(
                   project.id,
                   user.id,
                   hash,
                   blob_key,
                   metadata,
                   asset_copy_tracker: tracker
                 )
               end)

      on_exit(fn -> delete_storage_blob(blob_key) end)

      assert :ok = StorageCompensation.discard(tracker)
    end

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
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
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
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
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
      expected_size = byte_size(content)
      corrupt_size = byte_size(corrupt_content)
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      assert {:ok, _url} = Storage.upload(destination_blob_key, corrupt_content, "image/png")

      on_exit(fn ->
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
      end)

      metadata = %{
        "filename" => "corrupt.png",
        "content_type" => "image/png",
        "size" => expected_size
      }

      assert {:error, {:asset_blob_size_mismatch, ^expected_size, ^corrupt_size}} =
               BlobStore.create_asset_from_blob(
                 destination_project.id,
                 user.id,
                 hash,
                 source_blob_key,
                 metadata
               )

      assert {:error, :enoent} = Storage.download(destination_blob_key)

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
               Billing.with_storage_accounting_lock(project.workspace_id, fn _workspace ->
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
        delete_storage_blob(blob_key)
        Storage.delete(asset_key)
      end)

      assert :ok = StorageCompensation.cleanup(tracker)
      assert :ok = StorageCompensation.delete_storage_keys([asset_key])
      assert {:error, _reason} = Storage.download(asset_key)
      assert {:ok, ^content} = Storage.download(blob_key)
    end

    test "tracks a newly materialized blob for rollback compensation", %{
      project: source_project,
      user: user
    } do
      content = "asset rolled back after template materialization"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      tracker = StorageCompensation.new()

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      metadata = %{
        "filename" => "rolled-back.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, {:forced_rollback, destination_project_id, destination_blob_key, asset_key}} =
               Billing.with_storage_accounting_lock(source_project.workspace_id, fn workspace ->
                 destination_project = project_fixture(user, %{workspace: workspace})
                 destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")

                 {:ok, asset} =
                   BlobStore.create_asset_from_blob(
                     destination_project.id,
                     user.id,
                     hash,
                     source_blob_key,
                     metadata,
                     asset_copy_tracker: tracker
                   )

                 Repo.rollback({:forced_rollback, destination_project.id, destination_blob_key, asset.key})
               end)

      on_exit(fn ->
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
        Storage.delete(asset_key)
      end)

      assert {:ok, ^content} = Storage.download(asset_key)
      assert {:ok, ^content} = Storage.download(destination_blob_key)
      refute Repo.get(Project, destination_project_id)
      assert :ok = StorageCompensation.cleanup(tracker)
      assert :ok = StorageCompensation.delete_storage_keys([asset_key, destination_blob_key])
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
               Billing.with_storage_accounting_lock(destination_project.workspace_id, fn _workspace ->
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
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
        Storage.delete(asset_key)
      end)

      assert :ok = StorageCompensation.cleanup(tracker)
      assert :ok = StorageCompensation.delete_storage_keys([asset_key])
      assert {:error, _reason} = Storage.download(asset_key)
      assert {:ok, ^content} = Storage.download(destination_blob_key)
    end

    test "compensates a published blob and its temporary hard link when local cleanup fails", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "conditional copy with pending local cleanup"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")
      tracker = StorageCompensation.new()

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      configure_conditional_copy_remove_failure(:eacces)

      metadata = %{
        "filename" => "pending-cleanup.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, {:conditional_copy_cleanup_required, true, pending_cleanup_key, :eacces}} =
               BlobStore.create_asset_from_blob(
                 destination_project.id,
                 user.id,
                 hash,
                 source_blob_key,
                 metadata,
                 asset_copy_tracker: tracker
               )

      on_exit(fn ->
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
        delete_storage_blob(pending_cleanup_key)
      end)

      assert {:error, _reason} = Storage.download(destination_blob_key)
      assert {:error, _reason} = Storage.download(pending_cleanup_key)
      assert :ok = StorageCompensation.cleanup(tracker)
    end

    test "preserves a pre-existing destination while compensating its temporary hard link", %{
      project: source_project,
      user: user
    } do
      destination_project = project_fixture(user)
      content = "pre-existing conditional-copy destination"
      hash = BlobStore.compute_hash(content)
      source_blob_key = BlobStore.blob_key(source_project.id, hash, "png")
      destination_blob_key = BlobStore.blob_key(destination_project.id, hash, "png")

      assert {:ok, ^source_blob_key} =
               BlobStore.ensure_blob(source_project.id, hash, "png", content)

      assert {:ok, ^destination_blob_key} =
               BlobStore.ensure_blob(destination_project.id, hash, "png", content)

      configure_conditional_copy_remove_failure(:ebusy)

      metadata = %{
        "filename" => "existing-destination.png",
        "content_type" => "image/png",
        "size" => byte_size(content)
      }

      assert {:error, {:conditional_copy_cleanup_required, false, pending_cleanup_key, :ebusy}} =
               BlobStore.create_asset_from_blob(
                 destination_project.id,
                 user.id,
                 hash,
                 source_blob_key,
                 metadata
               )

      on_exit(fn ->
        delete_storage_blob(source_blob_key)
        delete_storage_blob(destination_blob_key)
        delete_storage_blob(pending_cleanup_key)
      end)

      assert {:ok, ^content} = Storage.download(destination_blob_key)
      assert {:error, _reason} = Storage.download(pending_cleanup_key)
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
        delete_storage_blob(blob_key)
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
        delete_storage_blob(blob_key)
        Storage.delete(new_asset.key)
      end)

      assert new_asset.content_type == "image/svg+xml"
      assert new_asset.metadata["sanitized_svg"] == true
      assert {:ok, ^content} = Storage.download(new_asset.key)
    end

    test "rejects materialization before copying when workspace capacity is exhausted", %{
      project: project,
      user: user
    } do
      limit = Billing.plan_limit("free", :storage_bytes_per_workspace)

      Repo.insert!(%Asset{
        project_id: project.id,
        filename: "existing.pdf",
        content_type: "application/pdf",
        size: limit,
        key: Assets.generate_key(project, "existing.pdf")
      })

      content = "cannot fit"
      hash = BlobStore.compute_hash(content)
      blob_key = BlobStore.blob_key(project.id, hash, "png")
      assert {:ok, ^blob_key} = BlobStore.ensure_blob(project.id, hash, "png", content)

      on_exit(fn -> delete_storage_blob(blob_key) end)

      assert {:error, {:limit_reached, details}} =
               BlobStore.create_asset_from_blob(project.id, user.id, hash, blob_key, %{
                 "filename" => "restored.png",
                 "content_type" => "image/png",
                 "size" => byte_size(content)
               })

      assert details.required == byte_size(content)
      assert details.available == 0
      assert Repo.aggregate(from(asset in Asset, where: asset.project_id == ^project.id), :count) == 1
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

  defp configure_conditional_copy_remove_failure(reason) do
    original_config = Application.get_env(:storyarn, :storage, [])

    Application.put_env(
      :storyarn,
      :storage,
      Keyword.put(original_config, :conditional_copy_file_rm, fn _path -> {:error, reason} end)
    )

    on_exit(fn -> Application.put_env(:storyarn, :storage, original_config) end)
  end
end
