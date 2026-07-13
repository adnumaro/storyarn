defmodule Storyarn.Assets.StorageCompensationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Storyarn.Assets.StorageCompensation

  test "retries cleanup job persistence before returning an error" do
    {:ok, attempts} = Agent.start_link(fn -> 0 end)

    insert_fun = fn _storage_keys ->
      attempt = Agent.get_and_update(attempts, &{&1 + 1, &1 + 1})
      if attempt < 3, do: {:error, :database_unavailable}, else: {:ok, %{id: 1}}
    end

    log =
      capture_log(fn ->
        assert :ok =
                 StorageCompensation.enqueue_cleanup(
                   ["projects/1/assets/copy/file.png"],
                   insert_fun: insert_fun,
                   retry_delay_ms: 0
                 )
      end)

    assert Agent.get(attempts, & &1) == 3
    assert log =~ "retrying"
  end

  test "retains failed keys when neither deletion nor job persistence succeeds" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/file.png"
    :ok = StorageCompensation.track(tracker, storage_key)

    log =
      capture_log(fn ->
        assert {:error, {:storage_cleanup_not_persisted, :database_unavailable}} =
                 StorageCompensation.cleanup(tracker,
                   enqueue_fun: fn _keys -> {:error, :database_unavailable} end,
                   delete_fun: fn keys -> {:error, keys} end
                 )
      end)

    assert log =~ "could not be completed or persisted"

    parent = self()

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:retained_keys, keys})
                 :ok
               end,
               delete_fun: fn _keys -> :ok end
             )

    assert_receive {:retained_keys, [^storage_key]}
  end

  test "persists cleanup before attempting an opportunistic delete" do
    tracker = StorageCompensation.new()
    storage_key = "projects/1/assets/copy/file.png"
    :ok = StorageCompensation.track(tracker, storage_key)
    parent = self()

    assert :ok =
             StorageCompensation.cleanup(tracker,
               enqueue_fun: fn keys ->
                 send(parent, {:cleanup_persisted, keys})
                 :ok
               end,
               delete_fun: fn keys ->
                 send(parent, {:delete_attempted, keys})
                 {:error, keys}
               end
             )

    assert_receive {:cleanup_persisted, [^storage_key]}
    assert_receive {:delete_attempted, [^storage_key]}
  end
end
