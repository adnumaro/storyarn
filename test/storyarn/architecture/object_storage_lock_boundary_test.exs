defmodule Storyarn.Architecture.ObjectStorageLockBoundaryTest do
  use Storyarn.DataCase, async: false

  import ExUnit.CaptureLog

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Flows.Versioning.Adapters.Storage.Locks, as: FlowLocks
  alias Storyarn.Flows.Versioning.Adapters.Storage.Objects, as: FlowObjects
  alias Storyarn.Projects.Assets.StorageKeyLock, as: ProjectLocks
  alias Storyarn.Repo
  alias Storyarn.Scenes.Assets.Adapters.Storage.Locks, as: SceneLocks
  alias Storyarn.Scenes.Assets.Adapters.Storage.Objects, as: SceneAssetObjects
  alias Storyarn.Scenes.Versioning.Adapters.Storage.Objects, as: SceneVersionObjects
  alias Storyarn.Sheets.Assets.Adapters.Storage.Locks, as: SheetLocks
  alias Storyarn.Sheets.Assets.Adapters.Storage.Objects, as: SheetAssetObjects
  alias Storyarn.Sheets.Versioning.Adapters.Storage.Objects, as: SheetVersionObjects

  @timeout 5_000
  @hash String.duplicate("a", 64)
  @max_project_id 9_223_372_036_854_775_807
  @invalid_delete_event [:storyarn, :assets, :storage, :invalid_delete_blocked]
  @recoverable_delete_event [:storyarn, :assets, :storage, :recoverable_blob_delete_blocked]

  test "consumer wrappers preserve the canonical and recoverable deletion contract" do
    handler_id = {__MODULE__, self()}

    assert :ok =
             :telemetry.attach_many(
               handler_id,
               [@invalid_delete_event, @recoverable_delete_event],
               fn event, measurements, metadata, owner ->
                 send(owner, {:storage_delete_blocked, event, measurements, metadata})
               end,
               self()
             )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    invalid_keys = [
      "projects/42/blobs/#{@hash}.bin" <> <<0>>,
      "projects/42/blobs\\#{@hash}.bin",
      <<"projects/42/blobs/", 255>>
    ]

    for {wrapper, delete} <- deletion_wrappers(), key <- invalid_keys do
      assert_delete_rejection(
        wrapper,
        delete,
        key,
        :invalid_key,
        @invalid_delete_event,
        "Blocked deletion for a non-canonical storage key"
      )
    end

    recoverable_key = "projects/42/blobs/#{@hash}.bin"

    for {wrapper, delete} <- deletion_wrappers() do
      assert_delete_rejection(
        wrapper,
        delete,
        recoverable_key,
        :recoverable_blob,
        @recoverable_delete_event,
        "Blocked deletion of a recoverable versioning blob"
      )
    end
  end

  test "every consumer wrapper accepts and rejects the same project-blob keys" do
    cases = [
      {"projects/1/blobs/#{@hash}.bin", {:ok, 1, @hash}},
      {"projects/#{@max_project_id}/blobs/#{@hash}.webp", {:ok, @max_project_id, @hash}},
      {"projects/0/blobs/#{@hash}.bin", :error},
      {"projects/01/blobs/#{@hash}.bin", :error},
      {"projects/#{@max_project_id + 1}/blobs/#{@hash}.bin", :error},
      {"projects/1/blobs/#{String.upcase(@hash)}.bin", :error},
      {"projects/1/blobs/#{String.slice(@hash, 0, 63)}.bin", :error},
      {"projects/1/blobs/#{@hash}.bin.storyarn-copy-abcdefghijklmnop", :error},
      {"projects/1/blobs/#{@hash}.", :error},
      {"projects/1/blobs/#{@hash}.nested/path", :error}
    ]

    for {wrapper, parser} <- identity_parsers(), {storage_key, expected} <- cases do
      assert parser.(storage_key) == expected,
             "#{inspect(wrapper)} disagreed for #{inspect(storage_key)}"
    end
  end

  test "every consumer wrapper contends on the same neutral project-blob lock" do
    wrappers = lock_wrappers()

    wrappers
    |> Enum.zip(tl(wrappers) ++ [hd(wrappers)])
    |> Enum.with_index()
    |> Enum.each(fn {{owner, contender}, index} ->
      assert_wrappers_contend(owner, contender, index)
    end)
  end

  defp assert_wrappers_contend(owner, contender, index) do
    parent = self()
    hash = :sha256 |> :crypto.hash("cross-context-lock-#{index}") |> Base.encode16(case: :lower)
    storage_key = "projects/42/blobs/#{hash}.bin"
    hold_fun = fn -> hold_lock(parent, index) end

    owner_task = Task.async(fn -> run_unboxed_lock(owner, storage_key, hold_fun, []) end)

    assert_receive {:object_storage_lock_acquired, ^index, owner_pid}, @timeout

    reject_fun = fn -> flunk("contending wrapper must not enter while the shared lock is held") end

    assert {:error, :storage_key_lock_timeout} =
             run_unboxed_lock(contender, storage_key, reject_fun, acquisition_timeout: 50)

    send(owner_pid, {:release_object_storage_lock, index})
    assert :released = Task.await(owner_task, @timeout)
  end

  defp run_unboxed_lock(wrapper, storage_key, fun, opts) do
    Sandbox.unboxed_run(Repo, fn -> wrapper.(storage_key, fun, opts) end)
  end

  defp assert_delete_rejection(wrapper, delete, key, reason, event, message) do
    log =
      capture_log(fn ->
        assert delete.(key) == {:error, reason},
               "#{inspect(wrapper)} changed the rejection for #{inspect(key)}"
      end)

    assert log =~ message
    assert_receive {:storage_delete_blocked, ^event, %{count: 1}, %{}}
  end

  defp hold_lock(parent, index) do
    send(parent, {:object_storage_lock_acquired, index, self()})

    receive do
      {:release_object_storage_lock, ^index} -> :released
    after
      @timeout -> flunk("owner lock was not released")
    end
  end

  defp identity_parsers do
    [
      {ProjectLocks, &ProjectLocks.project_blob_identity/1},
      {FlowLocks, &FlowLocks.project_blob_identity/1},
      {SheetLocks, &SheetLocks.project_blob_identity/1},
      {SceneLocks, &SceneLocks.project_blob_identity/1}
    ]
  end

  defp lock_wrappers do
    [
      &ProjectLocks.with_project_blob_lock/3,
      &FlowLocks.with_project_blob_lock/3,
      &SheetLocks.with_project_blob_lock/3,
      &SceneLocks.with_project_blob_lock/3
    ]
  end

  defp deletion_wrappers do
    [
      {FlowObjects, &FlowObjects.delete/1},
      {SheetAssetObjects, &SheetAssetObjects.delete/1},
      {SheetVersionObjects, &SheetVersionObjects.delete/1},
      {SceneAssetObjects, &SceneAssetObjects.delete/1},
      {SceneVersionObjects, &SceneVersionObjects.delete/1}
    ]
  end
end
