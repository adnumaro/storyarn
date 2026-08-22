defmodule Storyarn.Flows.Versioning.AssetStorageCompensationPersistenceTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query, warn: false

  alias Storyarn.Flows.Persistence.StorageCleanupRequestRecord
  alias Storyarn.Flows.Versioning.AssetStorageCompensation
  alias Storyarn.Repo

  @storage_key "projects/1/assets/550e8400-e29b-41d4-a716-446655440000/voice.mp3"

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
end
