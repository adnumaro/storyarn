defmodule Storyarn.Flows.Versioning.AssetStorageCompensationTest do
  use ExUnit.Case, async: true

  alias Storyarn.Flows.Versioning.AssetStorageCompensation

  @storage_key "projects/1/assets/550e8400-e29b-41d4-a716-446655440000/voice.mp3"

  test "hands a failed rollback deletion to durable persistence" do
    tracker = AssetStorageCompensation.new()
    :ok = AssetStorageCompensation.track(tracker, @storage_key)
    test_process = self()

    assert :ok =
             AssetStorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn storage_key ->
                 send(test_process, {:delete_attempted, storage_key})
                 {:error, :provider_unavailable}
               end,
               persist_fun: fn storage_keys ->
                 send(test_process, {:cleanup_persisted, storage_keys})
                 {:ok, %{storage_keys: storage_keys}}
               end
             )

    assert_received {:delete_attempted, @storage_key}
    assert_received {:cleanup_persisted, [@storage_key]}

    refute_cleanup_retried(tracker)
  end

  test "keeps cleanup ownership when neither deletion nor persistence succeeds" do
    tracker = AssetStorageCompensation.new()
    :ok = AssetStorageCompensation.track(tracker, @storage_key)

    assert {:error, {:storage_cleanup_not_persisted, cleanup_error}} =
             AssetStorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn _storage_key -> {:error, :provider_unavailable} end,
               persist_fun: fn _storage_keys -> {:error, :database_unavailable} end
             )

    assert cleanup_error == %{
             failed_keys: [@storage_key],
             persistence_error: :database_unavailable
           }

    test_process = self()

    assert :ok =
             AssetStorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn storage_key ->
                 send(test_process, {:delete_retried, storage_key})
                 :ok
               end
             )

    assert_received {:delete_retried, @storage_key}
  end

  defp refute_cleanup_retried(tracker) do
    test_process = self()

    assert :ok =
             AssetStorageCompensation.cleanup_after_rollback(tracker,
               delete_fun: fn storage_key ->
                 send(test_process, {:unexpected_delete_retry, storage_key})
                 :ok
               end
             )

    refute_received {:unexpected_delete_retry, _storage_key}
  end
end
