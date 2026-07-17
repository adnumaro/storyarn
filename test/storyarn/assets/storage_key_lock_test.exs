defmodule Storyarn.Assets.StorageKeyLockTest do
  use Storyarn.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Assets.StorageKeyLock
  alias Storyarn.Repo

  test "recognizes project blob keys without classifying temporary hard links as blobs" do
    hash = String.duplicate("a", 64)
    blob_key = "projects/42/blobs/#{hash}.png"

    assert {:ok, 42} = StorageKeyLock.project_blob_id(blob_key)
    assert :error = StorageKeyLock.project_blob_id("#{blob_key}.storyarn-copy-random")
    assert :error = StorageKeyLock.project_blob_id("projects/42/assets/#{hash}.png")
    assert :error = StorageKeyLock.project_blob_id("projects/42/blobs/not-a-hash.png")
  end

  test "serializes concurrent owners of the same project blob key" do
    parent = self()
    hash = String.duplicate("b", 64)
    blob_key = "projects/42/blobs/#{hash}.png"

    first =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_project_blob_lock(blob_key, fn ->
            send(parent, {:lock_acquired, :first})

            receive do
              :release_first -> :ok
            end
          end)
        end)
      end)

    assert_receive {:lock_acquired, :first}

    second =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_project_blob_lock(blob_key, fn ->
            send(parent, {:lock_acquired, :second})
          end)
        end)
      end)

    refute_receive {:lock_acquired, :second}, 100
    send(first.pid, :release_first)

    assert :ok = Task.await(first)
    assert_receive {:lock_acquired, :second}
    assert {:lock_acquired, :second} = Task.await(second)
  end

  test "serializes cleanup behind the transaction adopting a unique asset key" do
    parent = self()
    asset_key = "projects/42/assets/#{Ecto.UUID.generate()}/portrait.png"

    writer =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(asset_key, fn ->
            send(parent, {:asset_lock_acquired, :writer})

            receive do
              :commit_writer -> :ok
            end
          end)
        end)
      end)

    assert_receive {:asset_lock_acquired, :writer}

    cleanup =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_storage_key_lock(asset_key, fn ->
            send(parent, {:asset_lock_acquired, :cleanup})
          end)
        end)
      end)

    refute_receive {:asset_lock_acquired, :cleanup}, 100
    send(writer.pid, :commit_writer)

    assert :ok = Task.await(writer)
    assert_receive {:asset_lock_acquired, :cleanup}
    assert {:asset_lock_acquired, :cleanup} = Task.await(cleanup)
  end

  test "session locks serialize long callbacks without wrapping them in a transaction" do
    parent = self()
    lock_name = "template-installation:#{System.unique_integer([:positive])}"

    first =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, {:session_lock_acquired, :first, Repo.in_transaction?()})

            receive do
              :release_first -> :ok
            end
          end)
        end)
      end)

    assert_receive {:session_lock_acquired, :first, false}

    second =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name, fn ->
            send(parent, {:session_lock_acquired, :second, Repo.in_transaction?()})
          end)
        end)
      end)

    independent =
      Task.async(fn ->
        Sandbox.unboxed_run(Repo, fn ->
          StorageKeyLock.with_session_lock(lock_name <> ":independent", fn ->
            send(parent, {:session_lock_acquired, :independent, Repo.in_transaction?()})
          end)
        end)
      end)

    refute_receive {:session_lock_acquired, :second, _in_transaction?}, 100
    assert_receive {:session_lock_acquired, :independent, false}
    assert {:session_lock_acquired, :independent, false} = Task.await(independent)

    send(first.pid, :release_first)

    assert :ok = Task.await(first)
    assert_receive {:session_lock_acquired, :second, false}
    assert {:session_lock_acquired, :second, false} = Task.await(second)
  end
end
