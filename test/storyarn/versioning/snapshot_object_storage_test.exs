defmodule Storyarn.Versioning.SnapshotObjectStorageTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.VersioningFixtures

  alias Storyarn.Assets.Asset
  alias Storyarn.Assets.Storage
  alias Storyarn.Assets.StorageCleanupRequest
  alias Storyarn.Assets.StorageCompensation
  alias Storyarn.Billing
  alias Storyarn.Billing.StorageReservation
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.SnapshotReadSwitchStorage
  alias Storyarn.Versioning.ProjectSnapshot
  alias Storyarn.Versioning.SnapshotObjectFormat
  alias Storyarn.Versioning.SnapshotObjectPublicationClaim
  alias Storyarn.Versioning.SnapshotObjectStorage
  alias Storyarn.Versioning.SnapshotStorage

  describe "persist/4 and load_verified/4" do
    test "inspection rejects malformed option lists without raising" do
      for opts <- [[:malformed], [{"start_index", 0}]] do
        assert {:error, :invalid_snapshot_inspection_request} =
                 SnapshotObjectStorage.inspect_ready_object_batch(
                   "invalid-manifest-key",
                   String.duplicate("a", 64),
                   0,
                   opts
                 )
      end
    end

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
               persist_authorized(project_id, project, [first, second], token: token)

      assert stored.format_version == 1
      assert stored.asset_count == 2
      assert stored.blob_count == 1
      assert stored.object_count == 3
      assert stored.mode == "full"
      assert stored.lifecycle_state == "ready"
      assert stored.integrity_state == "verified"
      assert stored.total_size_bytes > stored.manifest_size_bytes
      assert stored.accounted_size_bytes == stored.total_size_bytes

      assert stored.asset_blob_size_bytes ==
               stored.total_size_bytes - stored.project_size_bytes - stored.manifest_size_bytes

      assert stored.accounting_version == 1
      assert stored.staging_cleanup_request_id == nil
      refute Map.has_key?(stored, :accounting_measured_at)
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

      assert {:ok, first_inspection_page} =
               SnapshotObjectStorage.inspect_ready_object_batch(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes,
                 start_index: 0,
                 max_inspection_objects: 1,
                 max_inspection_bytes: 128 * 1024 * 1024
               )

      assert first_inspection_page.verified_objects == 1
      assert first_inspection_page.next_index == 1

      assert {:ok, final_inspection_page} =
               SnapshotObjectStorage.inspect_ready_object_batch(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes,
                 start_index: first_inspection_page.next_index,
                 max_inspection_objects: 1,
                 max_inspection_bytes: 128 * 1024 * 1024
               )

      assert final_inspection_page.verified_objects == 1
      assert final_inspection_page.next_index == nil

      assert {:ok, retried} =
               persist_authorized(project_id, project, [first, second], token: token)

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

    test "stages exact measurements and authorizes before copying any ready object" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "authorize before ready"
      source = source_key(project_id, "authorize.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(151, project_id, "authorize.png", source, content, sha256(content))
      test_process = self()

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset],
                 token: token,
                 on_progress: fn completed_bytes ->
                   send(test_process, {:stage_progress, completed_bytes})
                   :ok
                 end
               )

      assert_received {:stage_progress, project_bytes}
      assert project_bytes == staged.project_size_bytes
      assert_received {:stage_progress, payload_bytes}
      assert payload_bytes == staged.project_size_bytes + byte_size(content)
      assert_received {:stage_progress, ^payload_bytes}
      assert_received {:stage_progress, total_bytes}
      assert total_bytes == staged.total_size_bytes

      assert staged.lifecycle_state == "staged"
      assert staged.integrity_state == "verified"
      assert staged.total_size_bytes == staged.accounted_size_bytes
      assert staged.object_prefix == SnapshotObjectStorage.ready_prefix(project_id, token)
      assert staged.staging_prefix == SnapshotObjectStorage.staging_prefix(project_id, token)

      ready_keys =
        Enum.filter(staged.cleanup.storage_keys, &String.starts_with?(&1, staged.object_prefix <> "/"))

      staging_keys =
        Enum.filter(staged.cleanup.storage_keys, &String.starts_with?(&1, staged.staging_prefix <> "/"))

      assert Enum.all?(ready_keys, fn key -> match?({:error, _reason}, Storage.stat(key)) end)
      assert Enum.all?(staging_keys, fn key -> match?({:ok, _stat}, Storage.stat(key)) end)

      test_process = self()

      before_publish = fn exact ->
        ready_states = Enum.map(ready_keys, &Storage.stat/1)
        send(test_process, {:before_publish, exact, ready_states})
        persist_publication_authorization!(exact)
      end

      assert {:ok, stored} = SnapshotObjectStorage.publish(staged, before_publish)
      assert_received {:before_publish, ^staged, ready_states}
      assert Enum.all?(ready_states, &match?({:error, _reason}, &1))
      assert stored.lifecycle_state == "ready"
      assert stored.total_size_bytes == staged.total_size_bytes
      assert Enum.all?(ready_keys, fn key -> match?({:ok, _stat}, Storage.stat(key)) end)
      assert Enum.all?(staging_keys, fn key -> match?({:error, _reason}, Storage.stat(key)) end)
      assert stored.staging_cleanup_request_id == nil

      assert {:ok, ^stored} =
               SnapshotObjectStorage.publish(staged, fn _exact ->
                 flunk("an already published object set must not be authorized again")
               end)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "a rejected prepublication authorization fails closed with an idempotent cleanup scope" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "quota rejection"
      source = source_key(project_id, "quota.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(152, project_id, "quota.png", source, content, sha256(content))

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset], token: token)

      assert {:error, {:snapshot_publish_authorization_failed, {:storage_limit_exceeded, 42}, cleanup}} =
               SnapshotObjectStorage.publish(staged, fn exact ->
                 assert exact.total_size_bytes > 0
                 {:error, {:storage_limit_exceeded, 42}}
               end)

      assert Map.delete(cleanup, :cleanup_request_id) == staged.cleanup
      assert cleanup.project_id == project_id
      assert cleanup.token == token
      assert cleanup.staging_prefix == SnapshotObjectStorage.staging_prefix(project_id, token)
      assert cleanup.ready_prefix == SnapshotObjectStorage.ready_prefix(project_id, token)
      assert length(cleanup.storage_keys) == staged.object_count * 2
      assert length(Enum.uniq(cleanup.storage_keys)) == length(cleanup.storage_keys)

      assert %StorageCleanupRequest{storage_keys: persisted_keys} =
               Repo.get!(StorageCleanupRequest, cleanup.cleanup_request_id)

      assert MapSet.new(persisted_keys) == MapSet.new(cleanup.storage_keys)

      ready_keys =
        Enum.filter(cleanup.storage_keys, &String.starts_with?(&1, cleanup.ready_prefix <> "/"))

      staging_keys =
        Enum.filter(cleanup.storage_keys, &String.starts_with?(&1, cleanup.staging_prefix <> "/"))

      assert Enum.all?(ready_keys, fn key -> match?({:error, _reason}, Storage.stat(key)) end)
      assert Enum.all?(staging_keys, fn key -> match?({:ok, _stat}, Storage.stat(key)) end)

      assert {:error, :snapshot_object_namespace_cleanup_handed_off} =
               SnapshotObjectStorage.publish(staged, fn _exact ->
                 flunk("a namespace handed to cleanup must never be republished")
               end)

      Enum.each(cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "persists the complete planned inventory after an intermediate publish failure" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "intermediate publish failure"
      hash = sha256(content)
      source = source_key(project_id, "intermediate-publish.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(157, project_id, "intermediate-publish.png", source, content, hash)

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset], token: token)

      original_config = Application.get_env(:storyarn, :storage, [])
      {:ok, removals} = Agent.start_link(fn -> 0 end)

      remove_temporary_copy = fn path ->
        attempt = Agent.get_and_update(removals, &{&1 + 1, &1 + 1})
        if attempt == 1, do: File.rm(path), else: {:error, :ebusy}
      end

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_config, :conditional_copy_file_rm, remove_temporary_copy)
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_config) end)

      assert {:error,
              {:snapshot_object_publish_failed, {:conditional_copy_cleanup_required, true, pending_cleanup_key, :ebusy},
               cleanup}} =
               SnapshotObjectStorage.publish(staged, &persist_publication_authorization!/1)

      assert Agent.get(removals, & &1) == 2
      assert_persisted_cleanup(cleanup, staged.cleanup.storage_keys)
      assert {:ok, _stat} = Storage.stat(staged.project_storage_key)
      assert {:error, _reason} = Storage.stat(staged.manifest_storage_key)

      upload_dir =
        :storyarn
        |> Application.get_env(:storage, [])
        |> Keyword.get(:upload_dir, "priv/static/uploads")
        |> Path.expand()

      refute File.exists?(Path.join(upload_dir, pending_cleanup_key))

      Enum.each(staged.cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "persists only failed staging keys after a successful publication" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "deferred staging cleanup"
      source = source_key(project_id, "deferred-staging.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(153, project_id, "deferred-staging.png", source, content, sha256(content))

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset], token: token)

      staging_keys = keys_under_prefix(staged.cleanup.storage_keys, staged.staging_prefix)
      ready_keys = keys_under_prefix(staged.cleanup.storage_keys, staged.object_prefix)

      configure_snapshot_cleanup(
        delete_fun: fn keys ->
          assert MapSet.new(keys) == MapSet.new(staging_keys)
          {:error, keys}
        end
      )

      assert {:ok, stored} = SnapshotObjectStorage.publish(staged, &persist_publication_authorization!/1)
      assert is_integer(stored.staging_cleanup_request_id)

      assert %StorageCleanupRequest{storage_keys: persisted_keys} =
               Repo.get!(StorageCleanupRequest, stored.staging_cleanup_request_id)

      assert MapSet.new(persisted_keys) == MapSet.new(staging_keys)
      assert Enum.all?(persisted_keys, &String.starts_with?(&1, staged.staging_prefix <> "/"))
      assert Enum.all?(ready_keys, fn key -> match?({:ok, _stat}, Storage.stat(key)) end)
      assert Enum.all?(staging_keys, fn key -> match?({:ok, _stat}, Storage.stat(key)) end)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "fails closed without touching ready objects when staging cleanup cannot be persisted" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "unpersisted staging cleanup"
      source = source_key(project_id, "unpersisted-staging.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(154, project_id, "unpersisted-staging.png", source, content, sha256(content))

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset], token: token)

      staging_keys = keys_under_prefix(staged.cleanup.storage_keys, staged.staging_prefix)
      ready_keys = keys_under_prefix(staged.cleanup.storage_keys, staged.object_prefix)

      original_config =
        configure_snapshot_cleanup(
          delete_fun: fn keys -> {:error, keys} end,
          persist_fun: fn _keys -> {:error, :database_unavailable} end
        )

      assert {:error, {:snapshot_staging_cleanup_not_persisted, details}} =
               SnapshotObjectStorage.publish(staged, &persist_publication_authorization!/1)

      assert details.persistence_error == :database_unavailable
      assert details.staging_cleanup_request_id == nil
      assert MapSet.new(details.cleanup.storage_keys) == MapSet.new(staging_keys)
      assert Enum.all?(details.cleanup.storage_keys, &String.starts_with?(&1, staged.staging_prefix <> "/"))
      assert Enum.all?(ready_keys, fn key -> match?({:ok, _stat}, Storage.stat(key)) end)

      Application.put_env(:storyarn, SnapshotObjectStorage, original_config)

      assert {:ok, stored} =
               SnapshotObjectStorage.publish(staged, fn _exact ->
                 flunk("a retry of an already published object set must not authorize again")
               end)

      assert stored.staging_cleanup_request_id == nil
      assert Enum.all?(staging_keys, fn key -> match?({:error, _reason}, Storage.stat(key)) end)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "reports cleanup_not_persisted when a rejected publication cannot hand off cleanup" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "cleanup persistence failure"
      source = source_key(project_id, "cleanup-persistence.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(155, project_id, "cleanup-persistence.png", source, content, sha256(content))

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset], token: token)

      configure_snapshot_cleanup(persist_fun: fn _keys -> {:error, :database_unavailable} end)

      assert {:error, {:snapshot_object_cleanup_not_persisted, details}} =
               SnapshotObjectStorage.publish(staged, fn _exact -> {:error, :storage_limit_reached} end)

      assert details.phase == :authorization
      assert details.reason == :storage_limit_reached
      assert details.persistence_error == :database_unavailable
      assert details.cleanup == staged.cleanup
      assert {:error, _reason} = Storage.stat(staged.manifest_storage_key)

      Enum.each(staged.cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "persist requires authorization before writing the staging namespace" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "missing authorization"
      source = source_key(project_id, "unauthorized.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(156, project_id, "unauthorized.png", source, content, sha256(content))

      assert {:error, :snapshot_publish_authorization_required} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset], token: token)

      staging_project = SnapshotObjectStorage.staging_prefix(project_id, token) <> "/project.json"
      ready_manifest = SnapshotObjectStorage.ready_prefix(project_id, token) <> "/manifest.json"
      assert {:error, _reason} = Storage.stat(staging_project)
      assert {:error, _reason} = Storage.stat(ready_manifest)
      assert :ok = Storage.delete(source)
    end

    test "stage accepts only a durable reservation marker before the first write" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "durable preflight marker"
      source = source_key(project_id, "preflight.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(158, project_id, "preflight.png", source, content, sha256(content))
      reservation = stage_reservation!(project_id, token: token)

      assert {:error, {:snapshot_stage_authorization_failed, {:invalid_snapshot_stage_authorization_result, :ok}}} =
               SnapshotObjectStorage.stage(project_id, project_object(asset), [asset],
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn _plan -> :ok end
               )

      refute_cleanup_request_for_prefix(project_id, token)

      assert %StorageReservation{storage_started_at: nil, status: "active"} =
               Repo.get!(StorageReservation, reservation.id)

      refute Repo.get(SnapshotObjectPublicationClaim, SnapshotObjectStorage.ready_prefix(project_id, token))

      staging_project = SnapshotObjectStorage.staging_prefix(project_id, token) <> "/project.json"
      assert {:error, _reason} = Storage.stat(staging_project)

      assert :ok = Storage.delete(source)
    end

    test "stage binds an underestimated reservation before callback extension" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "extend exact stage reservation"
      source = source_key(project_id, "extend-stage.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(162, project_id, "extend-stage.png", source, content, sha256(content))

      assert {:ok, staged} =
               stage_authorized(project_id, project_object(asset), [asset],
                 token: token,
                 test_reserved_bytes: 1
               )

      assert %StorageReservation{
               id: reservation_id,
               storage_started_at: %DateTime{},
               reserved_bytes: reserved_bytes
             } = Repo.get!(StorageReservation, staged.storage_reservation_id)

      assert reservation_id == staged.storage_reservation_id
      assert reserved_bytes == staged.accounted_size_bytes

      assert %SnapshotObjectPublicationClaim{
               storage_reservation_id_snapshot: ^reservation_id,
               storage_reservation_lease_token: lease_token,
               status: "staged"
             } = Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

      assert lease_token == staged.storage_reservation_lease_token

      Enum.each(staged.cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "a callback failure after marking storage poisons the claim before cleanup handoff" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "marked then failed"
      source = source_key(project_id, "marked-failure.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(163, project_id, "marked-failure.png", source, content, sha256(content))
      reservation = stage_reservation!(project_id, token: token)

      assert {:error, {:snapshot_object_stage_failed, {:snapshot_stage_authorization_failed, :after_marker}, cleanup}} =
               SnapshotObjectStorage.stage(project_id, project_object(asset), [asset],
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn staged ->
                   assert {:ok, _reservation} = persist_stage_authorization!(reservation, staged)
                   {:error, :after_marker}
                 end
               )

      assert_persisted_cleanup(cleanup, cleanup.storage_keys)

      assert %SnapshotObjectPublicationClaim{status: "poisoned"} =
               Repo.get!(SnapshotObjectPublicationClaim, cleanup.ready_prefix)

      assert Enum.all?(cleanup.storage_keys, fn key -> match?({:error, _reason}, Storage.stat(key)) end)

      Enum.each(cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "publish requires the exact persisted reservation instead of callback success alone" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "persisted publish authorization"
      source = source_key(project_id, "publish-authorization.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(164, project_id, "publish-authorization.png", source, content, sha256(content))
      assert {:ok, staged} = stage_authorized(project_id, project_object(asset), [asset], token: token)
      invalid_authorization = {:invalid_snapshot_publish_authorization_result, :ok}

      assert {:error, {:snapshot_publish_authorization_failed, ^invalid_authorization, cleanup}} =
               SnapshotObjectStorage.publish(staged, fn _staged -> :ok end)

      assert_persisted_cleanup(cleanup, staged.cleanup.storage_keys)
      assert {:error, _reason} = Storage.stat(staged.manifest_storage_key)

      assert %SnapshotObjectPublicationClaim{status: "poisoned"} =
               Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

      Enum.each(cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "a namespace claim binds exact content, not only object paths" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "exact claim content"
      source = source_key(project_id, "exact.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(159, project_id, "exact.png", source, content, sha256(content))
      project = project_object(asset)

      assert {:ok, staged} = stage_authorized(project_id, project, [asset], token: token)

      changed_project = put_in(project, ["project", "description"], "different portable bytes")
      reservation = Repo.get!(StorageReservation, staged.storage_reservation_id)

      assert {:error, :snapshot_object_namespace_inventory_conflict} =
               SnapshotObjectStorage.stage(project_id, changed_project, [asset],
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn _plan -> flunk("a conflicting claim must not mark another reservation") end
               )

      Enum.each(staged.cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "an expired staging claim requires explicit reconciliation instead of takeover" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "expired staging writer"
      source = source_key(project_id, "expired-stage.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(167, project_id, "expired-stage.png", source, content, sha256(content))
      project = project_object(asset)
      reservation = stage_reservation!(project_id, token: token)
      parent = self()

      writer =
        Task.async(fn ->
          SnapshotObjectStorage.stage(project_id, project, [asset],
            token: token,
            storage_reservation: reservation,
            before_stage: fn exact ->
              authorization = persist_stage_authorization!(reservation, exact)
              send(parent, {:stage_authorized, exact})

              receive do
                :finish_stage -> authorization
              end
            end
          )
        end)

      assert_receive {:stage_authorized, staged}

      SnapshotObjectPublicationClaim
      |> Repo.get!(staged.object_prefix)
      |> SnapshotObjectPublicationClaim.status_changeset(
        "staging",
        DateTime.add(TimeHelpers.now(), -1, :second)
      )
      |> Repo.update!()

      assert {:error, :snapshot_object_stage_reconciliation_required} =
               SnapshotObjectStorage.stage(project_id, project, [asset],
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn _exact ->
                   flunk("an expired staging claim must not authorize a second writer")
                 end
               )

      refute_cleanup_request_for_prefix(project_id, token)

      assert %SnapshotObjectPublicationClaim{status: "staging"} =
               Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

      send(writer.pid, :finish_stage)
      assert {:ok, ^staged} = Task.await(writer)

      Enum.each(staged.cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "a retry recovers a valid ready set left behind by publication finalization" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "publication recovery"
      source = source_key(project_id, "recovery.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(160, project_id, "recovery.png", source, content, sha256(content))

      assert {:ok, staged} = stage_authorized(project_id, project_object(asset), [asset], token: token)

      SnapshotObjectPublicationClaim
      |> Repo.get!(staged.object_prefix)
      |> SnapshotObjectPublicationClaim.status_changeset(
        "publishing",
        DateTime.add(TimeHelpers.now(), 3600, :second)
      )
      |> Repo.update!()

      copy_staged_to_ready!(staged)

      assert {:ok, stored} =
               SnapshotObjectStorage.publish(staged, fn _exact ->
                 flunk("a verified ready manifest must recover without reauthorization")
               end)

      assert %SnapshotObjectPublicationClaim{status: "published", lease_expires_at: nil} =
               Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "persist retry adopts an already published set after its reservation commits" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "committed publication retry"
      source = source_key(project_id, "committed-retry.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(165, project_id, "committed-retry.png", source, content, sha256(content))

      assert {:ok, stored} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      reservation =
        Repo.get_by!(StorageReservation,
          cleanup_object_prefix: SnapshotObjectStorage.ready_prefix(project_id, token)
        )

      now = TimeHelpers.now()

      committed =
        reservation
        |> StorageReservation.commit_changeset(stored.accounted_size_bytes, %{
          generation: reservation.generation + 1,
          settled_at: now,
          accounting_version: 1,
          accounting_measured_at: now
        })
        |> Repo.update!()

      assert {:ok, retried} =
               SnapshotObjectStorage.persist(project_id, project_object(asset), [asset],
                 token: token,
                 storage_reservation: committed,
                 before_stage: fn _exact -> flunk("published retry must not restage") end,
                 before_publish: fn _exact -> flunk("published retry must not reauthorize") end
               )

      assert retried.manifest_storage_key == stored.manifest_storage_key
      assert retried.accounted_size_bytes == stored.accounted_size_bytes

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 retried.manifest_storage_key,
                 retried.manifest_checksum,
                 retried.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "only one concurrent publisher can authorize a staged namespace" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "exclusive publisher"
      source = source_key(project_id, "exclusive.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(161, project_id, "exclusive.png", source, content, sha256(content))
      assert {:ok, staged} = stage_authorized(project_id, project_object(asset), [asset], token: token)
      parent = self()

      publisher =
        Task.async(fn ->
          SnapshotObjectStorage.publish(staged, fn _exact ->
            send(parent, :publisher_authorized)

            receive do
              :finish_publication -> persist_publication_authorization!(staged)
            end
          end)
        end)

      assert_receive :publisher_authorized

      assert {:error, :snapshot_object_publication_in_progress} =
               SnapshotObjectStorage.publish(staged, fn _exact ->
                 flunk("the losing publisher must not authorize")
               end)

      send(publisher.pid, :finish_publication)
      assert {:ok, stored} = Task.await(publisher)

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "an expired publication claim never authorizes an online takeover" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "expired writer remains fenced"
      source = source_key(project_id, "expired-publisher.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(165, project_id, "expired-publisher.png", source, content, sha256(content))
      assert {:ok, staged} = stage_authorized(project_id, project_object(asset), [asset], token: token)

      SnapshotObjectPublicationClaim
      |> Repo.get!(staged.object_prefix)
      |> SnapshotObjectPublicationClaim.status_changeset(
        "publishing",
        DateTime.add(TimeHelpers.now(), -1, :second)
      )
      |> Repo.update!()

      assert {:error, :snapshot_object_publication_reconciliation_required} =
               SnapshotObjectStorage.publish(staged, fn _exact ->
                 flunk("an expired lease must not authorize a second writer")
               end)

      refute_cleanup_request_for_prefix(project_id, token)

      assert %SnapshotObjectPublicationClaim{status: "publishing"} =
               Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

      assert {:error, _reason} = Storage.stat(staged.manifest_storage_key)

      Enum.each(staged.cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "publication fails closed when configured verification limits drift" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "limit drift"
      source = source_key(project_id, "limit-drift.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(166, project_id, "limit-drift.png", source, content, sha256(content))
      assert {:ok, staged} = stage_authorized(project_id, project_object(asset), [asset], token: token)
      original_limits = Application.get_env(:storyarn, SnapshotObjectFormat, [])

      Application.put_env(
        :storyarn,
        SnapshotObjectFormat,
        Keyword.put(original_limits, :max_assets, staged.limits.max_assets - 1)
      )

      on_exit(fn -> Application.put_env(:storyarn, SnapshotObjectFormat, original_limits) end)

      assert {:error, {:snapshot_object_publish_failed, :staged_snapshot_object_limits_changed, cleanup}} =
               SnapshotObjectStorage.publish(staged, &persist_publication_authorization!/1)

      assert_persisted_cleanup(cleanup, staged.cleanup.storage_keys)
      assert {:error, _reason} = Storage.stat(staged.manifest_storage_key)

      assert %SnapshotObjectPublicationClaim{status: "poisoned"} =
               Repo.get!(SnapshotObjectPublicationClaim, staged.object_prefix)

      Enum.each(cleanup.storage_keys, &Storage.delete/1)
      assert :ok = Storage.delete(source)
    end

    test "stage rejects per-call limit overrides before claiming or writing" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "limit override"
      source = source_key(project_id, "limit-override.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(168, project_id, "limit-override.png", source, content, sha256(content))
      reservation = stage_reservation!(project_id, token: token)

      assert {:error, :snapshot_object_limit_overrides_not_supported} =
               SnapshotObjectStorage.stage(project_id, project_object(asset), [asset],
                 token: token,
                 storage_reservation: reservation,
                 before_stage: fn _exact -> flunk("limit overrides fail before authorization") end,
                 max_assets: 1
               )

      refute Repo.get(SnapshotObjectPublicationClaim, SnapshotObjectStorage.ready_prefix(project_id, token))
      assert %StorageReservation{storage_started_at: nil} = Repo.get!(StorageReservation, reservation.id)

      assert {:error, _reason} =
               Storage.stat(SnapshotObjectStorage.staging_prefix(project_id, token) <> "/project.json")

      assert :ok = Storage.delete(source)
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
               persist_authorized(project_id, project_object(asset), [asset], token: token)

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
      hash = sha256(content)

      asset =
        asset(
          301,
          project_id,
          "missing.png",
          source_key(project_id, "missing.png"),
          content,
          hash
        )

      assert {:error, {:snapshot_object_stage_failed, _reason, cleanup}} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      expected_cleanup_keys = object_set_cleanup_keys(project_id, token, ["blobs/#{hash}.png"])
      assert_persisted_cleanup(cleanup, expected_cleanup_keys)

      ready_manifest = SnapshotObjectStorage.ready_prefix(project_id, token) <> "/manifest.json"
      assert {:error, _reason} = Storage.stat(ready_manifest)

      Enum.each(expected_cleanup_keys, &Storage.delete/1)
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

      assert {:error, {:snapshot_object_stage_failed, {:snapshot_object_checksum_mismatch, _, _}, cleanup}} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      expected_cleanup_keys =
        object_set_cleanup_keys(project_id, token, ["blobs/#{sha256(captured_content)}.png"])

      assert_persisted_cleanup(cleanup, expected_cleanup_keys)

      ready_manifest = SnapshotObjectStorage.ready_prefix(project_id, token) <> "/manifest.json"
      assert {:error, _reason} = Storage.stat(ready_manifest)

      _deleted = Storage.delete(key)
      Enum.each(expected_cleanup_keys, &Storage.delete/1)
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
               persist_authorized(project_id, project_object(asset), [asset], token: token)

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

    test "inspects one exact manifest object with a single manifest read" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "exact object inspection"
      hash = sha256(content)
      source = source_key(project_id, "exact.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(511, project_id, "exact.png", source, content, hash)

      assert {:ok, stored} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      assert {:ok, %{manifest: manifest}} =
               SnapshotObjectStorage.inspect_ready_manifest(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      descriptor = Enum.find(manifest["objects"], &(&1["kind"] == "asset_blob"))
      target_key = stored.object_prefix <> "/" <> descriptor["path"]
      install_snapshot_read_switch_storage()
      SnapshotReadSwitchStorage.reset_counts()

      assert {:ok,
              %{
                descriptor: ^descriptor,
                manifest: ^manifest,
                ready_prefix: ready_prefix
              }} =
               SnapshotObjectStorage.inspect_ready_object(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes,
                 descriptor["path"]
               )

      assert ready_prefix == stored.object_prefix
      assert SnapshotReadSwitchStorage.stream_count(stored.manifest_storage_key) == 1
      assert SnapshotReadSwitchStorage.stream_count(target_key) == 1
      assert SnapshotReadSwitchStorage.stream_count(stored.project_storage_key) == 0

      cleanup_object_set(project_id, token, manifest, [source])
    end

    test "returns an explicit error when the exact path is absent from the manifest" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "missing descriptor inspection"
      hash = sha256(content)
      source = source_key(project_id, "missing-descriptor.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(512, project_id, "missing-descriptor.png", source, content, hash)

      assert {:ok, stored} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      assert {:ok, %{manifest: manifest}} =
               SnapshotObjectStorage.inspect_ready_manifest(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      install_snapshot_read_switch_storage()
      SnapshotReadSwitchStorage.reset_counts()

      assert {:error, :snapshot_inspection_object_not_found} =
               SnapshotObjectStorage.inspect_ready_object(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes,
                 "blobs/#{String.duplicate("f", 64)}.png"
               )

      assert SnapshotReadSwitchStorage.stream_count(stored.manifest_storage_key) == 1

      for descriptor <- manifest["objects"] do
        object_key = stored.object_prefix <> "/" <> descriptor["path"]
        assert SnapshotReadSwitchStorage.stream_count(object_key) == 0
      end

      cleanup_object_set(project_id, token, manifest, [source])
    end

    test "preserves the existing verification error for a corrupt exact object" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "corrupt exact object"
      hash = sha256(content)
      source = source_key(project_id, "corrupt-exact.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(513, project_id, "corrupt-exact.png", source, content, hash)

      assert {:ok, stored} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      assert {:ok, %{manifest: manifest}} =
               SnapshotObjectStorage.inspect_ready_manifest(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      descriptor = Enum.find(manifest["objects"], &(&1["kind"] == "asset_blob"))
      expected_index = Enum.find_index(manifest["objects"], &(&1 == descriptor))
      target_key = stored.object_prefix <> "/" <> descriptor["path"]
      corrupt_content = String.duplicate("x", byte_size(content))
      corrupt_hash = sha256(corrupt_content)
      assert {:ok, _url} = Storage.upload(target_key, corrupt_content, descriptor["content_type"])
      install_snapshot_read_switch_storage()
      SnapshotReadSwitchStorage.reset_counts()

      assert {:error,
              {:snapshot_inspection_object_failed,
               %{
                 failed_index: ^expected_index,
                 object_count: 2,
                 path: descriptor_path,
                 reason: {:snapshot_object_checksum_mismatch, ^hash, ^corrupt_hash},
                 verified_bytes: 0,
                 verified_objects: 0
               }}} =
               SnapshotObjectStorage.inspect_ready_object(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes,
                 descriptor["path"]
               )

      assert descriptor_path == descriptor["path"]
      assert SnapshotReadSwitchStorage.stream_count(stored.manifest_storage_key) == 1
      assert SnapshotReadSwitchStorage.stream_count(target_key) == 1
      assert SnapshotReadSwitchStorage.stream_count(stored.project_storage_key) == 0

      cleanup_object_set(project_id, token, manifest, [source])
    end

    test "fails closed when stored MIME metadata is missing or generic" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "strict mime verification"
      source = source_key(project_id, "strict-mime.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(502, project_id, "strict-mime.png", source, content, sha256(content))

      assert {:ok, stored} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

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

      SnapshotReadSwitchStorage.override_content_type(stored.manifest_storage_key, nil)

      assert {:error, {:snapshot_object_content_type_mismatch, "manifest.json", "application/json", nil}} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      SnapshotReadSwitchStorage.override_content_type(
        stored.manifest_storage_key,
        "application/octet-stream"
      )

      assert {:error,
              {:snapshot_object_content_type_mismatch, "manifest.json", "application/json", "application/octet-stream"}} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      SnapshotReadSwitchStorage.override_content_type(
        stored.manifest_storage_key,
        "application/json"
      )

      assert {:ok, loaded} =
               SnapshotObjectStorage.load_verified(
                 stored.manifest_storage_key,
                 stored.manifest_checksum,
                 stored.manifest_size_bytes
               )

      cleanup_object_set(project_id, token, loaded.manifest, [source])
    end

    test "accepts historical v1 provider MIME metadata for supported audio assets" do
      for {id, content_type, filename} <- [
            {503, "audio/ogg", "voice.ogg"},
            {504, "audio/webm", "voice.webm"}
          ] do
        project_id = unique_project_id()
        token = SnapshotStorage.unique_key_suffix()
        content = "historical #{content_type} bytes"
        source = source_key(project_id, filename)
        assert {:ok, _url} = Storage.upload(source, content, content_type)

        asset =
          id
          |> asset(project_id, filename, source, content, sha256(content))
          |> Map.put(:content_type, content_type)

        assert {:ok, stored} =
                 persist_authorized(project_id, project_object(asset), [asset], token: token)

        assert {:ok, loaded} =
                 SnapshotObjectStorage.load_verified(
                   stored.manifest_storage_key,
                   stored.manifest_checksum,
                   stored.manifest_size_bytes
                 )

        cleanup_object_set(project_id, token, loaded.manifest, [source])
      end
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

      assert {:error,
              {:snapshot_object_stage_failed, {:storage_write_cleanup_required, ^staging_project, :enospc, :eacces},
               cleanup}} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      expected_cleanup_keys =
        object_set_cleanup_keys(project_id, token, ["blobs/#{sha256(content)}.png"])

      assert_persisted_cleanup(cleanup, expected_cleanup_keys)

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

      assert {:error,
              {:snapshot_object_stage_failed, {:conditional_copy_cleanup_required, true, pending_cleanup_key, :ebusy},
               cleanup}} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      expected_cleanup_keys = object_set_cleanup_keys(project_id, token, ["blobs/#{hash}.png"])
      assert_persisted_cleanup(cleanup, expected_cleanup_keys)

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

    test "never returns a releasable canonical scope while a random copy temporary has no owner" do
      project_id = unique_project_id()
      token = SnapshotStorage.unique_key_suffix()
      content = "unowned conditional temporary"
      hash = sha256(content)
      source = source_key(project_id, "unowned-conditional.png")
      assert {:ok, _url} = Storage.upload(source, content, "image/png")
      asset = asset(702, project_id, "unowned-conditional.png", source, content, hash)
      original_storage_config = Application.get_env(:storyarn, :storage, [])

      Application.put_env(
        :storyarn,
        :storage,
        Keyword.put(original_storage_config, :conditional_copy_file_rm, fn _path -> {:error, :ebusy} end)
      )

      configure_snapshot_cleanup(
        compensation_delete_fun: fn keys -> {:error, keys} end,
        compensation_enqueue_fun: fn _keys -> {:error, :queue_unavailable} end,
        compensation_persist_fun: fn _keys -> {:error, :database_unavailable} end
      )

      on_exit(fn -> Application.put_env(:storyarn, :storage, original_storage_config) end)

      assert {:error,
              {:snapshot_object_cleanup_not_persisted,
               %{
                 phase: :stage,
                 cleanup: nil,
                 persistence_error: :temporary_object_has_no_durable_cleanup_owner,
                 reason:
                   {:snapshot_object_cleanup_not_persisted,
                    {:conditional_copy_cleanup_required, true, pending_cleanup_key, :ebusy},
                    {:storage_cleanup_not_persisted, _cleanup_failure}}
               }}} =
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      refute_cleanup_request_for_prefix(project_id, token)

      reservation =
        Repo.get_by!(StorageReservation,
          cleanup_object_prefix: SnapshotObjectStorage.ready_prefix(project_id, token)
        )

      assert {:error, :storage_reservation_cleanup_ownership_required} =
               Billing.release_storage_reservation(
                 reservation.id,
                 reservation.lease_token,
                 reservation.generation,
                 %{
                   reason: "stage failed",
                   cleanup_status: "not_required",
                   cleanup_proof: %{
                     type: "storage_not_started",
                     storage_namespace: reservation.storage_namespace
                   }
                 }
               )

      assert %SnapshotObjectPublicationClaim{status: "poisoned"} =
               Repo.get!(SnapshotObjectPublicationClaim, SnapshotObjectStorage.ready_prefix(project_id, token))

      Application.put_env(:storyarn, :storage, original_storage_config)
      assert :ok = Storage.delete(pending_cleanup_key)

      project_id
      |> object_set_cleanup_keys(token, ["blobs/#{hash}.png"])
      |> Enum.each(&Storage.delete/1)

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
               persist_authorized(project_id, project_object(asset), [asset], token: token)

      assert %ProjectSnapshot{} =
               full_project_snapshot_fixture(
                 project_record,
                 Map.put(stored, :version_number, 1)
               )

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

  defp persist_authorized(project_id, project, assets, opts) do
    reservation = stage_reservation!(project_id, opts)

    opts =
      opts
      |> Keyword.put(:storage_reservation, reservation)
      |> Keyword.put(:before_stage, &persist_stage_authorization!(reservation, &1))
      |> Keyword.put(:before_publish, &persist_publication_authorization!/1)

    SnapshotObjectStorage.persist(project_id, project, assets, opts)
  end

  defp stage_authorized(project_id, project, assets, opts) do
    reservation = stage_reservation!(project_id, opts)

    opts =
      opts
      |> Keyword.put(:storage_reservation, reservation)
      |> Keyword.put(:before_stage, &persist_stage_authorization!(reservation, &1))

    SnapshotObjectStorage.stage(project_id, project, assets, opts)
  end

  defp stage_reservation!(project_id, opts) do
    token = Keyword.fetch!(opts, :token)
    object_prefix = SnapshotObjectStorage.ready_prefix(project_id, token)

    case Repo.get_by(StorageReservation, cleanup_object_prefix: object_prefix) do
      %StorageReservation{} = reservation ->
        reservation

      nil ->
        insert_stage_reservation!(project_id, object_prefix, Keyword.get(opts, :test_reserved_bytes, 1_000_000_000))
    end
  end

  defp insert_stage_reservation!(project_id, object_prefix, reserved_bytes) do
    lease_token = Ecto.UUID.generate()
    now = TimeHelpers.now()

    Repo.insert!(%StorageReservation{
      workspace_id_snapshot: System.unique_integer([:positive]),
      project_id_snapshot: project_id,
      project_snapshot_id_snapshot: System.unique_integer([:positive]),
      idempotency_key: "snapshot-object-storage-test:#{Ecto.UUID.generate()}",
      kind: "snapshot_build",
      status: "active",
      storage_namespace: "projects/#{project_id}/storage-reservations/v1/snapshot-build/#{lease_token}",
      cleanup_object_prefix: object_prefix,
      reserved_bytes: reserved_bytes,
      lease_token: lease_token,
      generation: 1,
      expires_at: DateTime.add(now, 3600, :second),
      accounting_version: 1,
      accounting_measured_at: now,
      inserted_at: now,
      updated_at: now
    })
  end

  defp persist_stage_authorization!(reservation, staged) do
    reservation = Repo.get!(StorageReservation, reservation.id)
    now = TimeHelpers.now()

    reservation =
      reservation
      |> Ecto.Changeset.change(%{
        reserved_bytes: max(reservation.reserved_bytes, staged.accounted_size_bytes),
        storage_started_at: now,
        cleanup_inventory_digest: cleanup_inventory_digest(staged.cleanup.storage_keys),
        cleanup_inventory_count: length(staged.cleanup.storage_keys),
        accounting_measured_at: now
      })
      |> Repo.update!()

    {:ok, reservation}
  end

  defp persist_publication_authorization!(staged) do
    {:ok, Repo.get!(StorageReservation, staged.storage_reservation_id)}
  end

  defp cleanup_inventory_digest(storage_keys) do
    storage_keys
    |> Enum.sort()
    |> Enum.map_join(fn storage_key -> "#{byte_size(storage_key)}:#{storage_key}" end)
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp configure_snapshot_cleanup(opts) do
    original_config = Application.get_env(:storyarn, SnapshotObjectStorage, [])
    Application.put_env(:storyarn, SnapshotObjectStorage, opts)
    on_exit(fn -> Application.put_env(:storyarn, SnapshotObjectStorage, original_config) end)
    original_config
  end

  defp install_snapshot_read_switch_storage do
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
  end

  defp keys_under_prefix(storage_keys, prefix) do
    Enum.filter(storage_keys, &String.starts_with?(&1, prefix <> "/"))
  end

  defp copy_staged_to_ready!(staged) do
    staged.cleanup.storage_keys
    |> keys_under_prefix(staged.staging_prefix)
    |> Enum.sort_by(&String.ends_with?(&1, "/manifest.json"))
    |> Enum.each(fn staging_key ->
      relative_key = String.replace_prefix(staging_key, staged.staging_prefix <> "/", "")
      assert :ok = Storage.copy(staging_key, staged.object_prefix <> "/" <> relative_key)
    end)
  end

  defp object_set_cleanup_keys(project_id, token, blob_paths) do
    paths = ["project.json" | blob_paths] ++ ["manifest.json"]

    Enum.flat_map(
      [
        SnapshotObjectStorage.staging_prefix(project_id, token),
        SnapshotObjectStorage.ready_prefix(project_id, token)
      ],
      fn prefix -> Enum.map(paths, &(prefix <> "/" <> &1)) end
    )
  end

  defp refute_cleanup_request_for_prefix(project_id, token) do
    prefixes = [
      SnapshotObjectStorage.staging_prefix(project_id, token) <> "/",
      SnapshotObjectStorage.ready_prefix(project_id, token) <> "/"
    ]

    refute Enum.any?(Repo.all(StorageCleanupRequest), fn request ->
             Enum.any?(request.storage_keys, fn storage_key ->
               Enum.any?(prefixes, &String.starts_with?(storage_key, &1))
             end)
           end)
  end

  defp assert_persisted_cleanup(cleanup, expected_keys) do
    assert is_integer(cleanup.cleanup_request_id)
    assert MapSet.new(cleanup.storage_keys) == MapSet.new(expected_keys)

    assert %StorageCleanupRequest{storage_keys: persisted_keys} =
             Repo.get!(StorageCleanupRequest, cleanup.cleanup_request_id)

    assert MapSet.new(persisted_keys) == MapSet.new(expected_keys)
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
