defmodule Storyarn.Flows.Versioning.AssetStorageCompensationPersistenceTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query, warn: false
  import ExUnit.CaptureLog

  alias Storyarn.Flows.Versioning.AssetStorageCompensation
  alias Storyarn.Flows.Versioning.Entities.StorageCleanupRequestRecord
  alias Storyarn.Repo

  @storage_key "projects/1/assets/550e8400-e29b-41d4-a716-446655440000/voice.mp3"
  @recoverable_blob_key "projects/1/blobs/#{String.duplicate("a", 64)}.bin"
  @recoverable_delete_event [:storyarn, :assets, :storage, :recoverable_blob_delete_blocked]

  test "persists the real durable cleanup handoff when provider deletion fails" do
    tracker = AssetStorageCompensation.new()
    :ok = AssetStorageCompensation.track(tracker, @storage_key)

    assert :ok =
             AssetStorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn _storage_key -> {:error, :provider_unavailable} end
             )

    assert [%StorageCleanupRequestRecord{storage_keys: [@storage_key], owner_kind: "storage_compensation"}] =
             Repo.all(
               from(request in StorageCleanupRequestRecord,
                 where: fragment("? = ANY(?)", ^@storage_key, request.storage_keys)
               )
             )
  end

  test "a recoverable blob keeps durable cleanup ownership and emits the blocked-delete signal" do
    handler_id = {__MODULE__, self()}

    assert :ok =
             :telemetry.attach(
               handler_id,
               @recoverable_delete_event,
               fn event, measurements, metadata, owner ->
                 send(owner, {:recoverable_delete_blocked, event, measurements, metadata})
               end,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    tracker = AssetStorageCompensation.new()
    :ok = AssetStorageCompensation.track(tracker, @recoverable_blob_key)

    log =
      capture_log(fn ->
        assert :ok = AssetStorageCompensation.cleanup_after_rollback(tracker)
      end)

    assert log =~ "Blocked deletion of a recoverable versioning blob"

    assert_received {:recoverable_delete_blocked, @recoverable_delete_event, %{count: 1}, %{}}

    assert [
             %StorageCleanupRequestRecord{
               storage_keys: [@recoverable_blob_key],
               owner_kind: "storage_compensation"
             }
           ] =
             Repo.all(
               from(request in StorageCleanupRequestRecord,
                 where: fragment("? = ANY(?)", ^@recoverable_blob_key, request.storage_keys)
               )
             )
  end
end
