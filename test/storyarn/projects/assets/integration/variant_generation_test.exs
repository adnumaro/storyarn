defmodule Storyarn.Projects.Assets.VariantGenerationTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.Assets

  @test_png_path "test/fixtures/images/quadrant_map.png"
  @test_jpg_path "test/fixtures/images/test_image.jpg"

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{project: project, user: user}
  end

  describe "variant generation with purpose" do
    test "PNG upload with :gallery purpose triggers async variant", %{
      project: project,
      user: user
    } do
      unrelated_task = start_unrelated_task()
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "scene.png", content_type: "image/png", purpose: :gallery},
                 project,
                 user
               )

      assert asset.content_type == "image/png"
      assert asset.project_id == project.id

      await_asset_tasks()
      assert Process.alive?(unrelated_task)

      # Reload the asset to check if metadata was updated with web_url
      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"]
      assert updated.metadata["web_asset_id"]

      # Cleanup
      Assets.storage_delete(asset.key)
      variant = Assets.get_asset(project.id, updated.metadata["web_asset_id"])
      if variant, do: Assets.storage_delete(variant.key)
    end

    test "JPEG upload with :gallery purpose skips variant", %{project: project, user: user} do
      binary = File.read!(@test_jpg_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "photo.jpg", content_type: "image/jpeg", purpose: :gallery},
                 project,
                 user
               )

      # JPEG is already optimal for gallery — no variant
      await_asset_tasks()

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end

    test "upload without purpose does not generate variant", %{project: project, user: user} do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "raw.png", content_type: "image/png"},
                 project,
                 user
               )

      await_asset_tasks()

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end

    test "upload with skip_variants: true does not generate variant", %{
      project: project,
      user: user
    } do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{
                   filename: "skip.png",
                   content_type: "image/png",
                   purpose: :gallery,
                   skip_variants: true
                 },
                 project,
                 user
               )

      await_asset_tasks()

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end

    test "PNG upload with :avatar purpose generates cropped WebP variant", %{
      project: project,
      user: user
    } do
      binary = File.read!(@test_png_path)

      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 binary,
                 %{filename: "avatar.png", content_type: "image/png", purpose: :avatar},
                 project,
                 user
               )

      await_asset_tasks()

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"]

      variant = Assets.get_asset(project.id, updated.metadata["web_asset_id"])
      assert variant
      assert variant.content_type == "image/webp"
      assert variant.metadata["is_variant"] == true
      assert variant.metadata["original_asset_id"] == asset.id

      # Cleanup
      Assets.storage_delete(asset.key)
      Assets.storage_delete(variant.key)
    end

    test "non-image upload with purpose does not generate variant", %{
      project: project,
      user: user
    } do
      assert {:ok, asset} =
               Assets.upload_binary_and_create_asset(
                 "fake audio content",
                 %{filename: "sound.mp3", content_type: "audio/mpeg", purpose: :gallery},
                 project,
                 user
               )

      await_asset_tasks()

      updated = Assets.get_asset(project.id, asset.id)
      assert updated.metadata["web_url"] == nil

      Assets.storage_delete(asset.key)
    end
  end

  # Upload schedules the task before returning. A task absent from this snapshot
  # has already finished; only await tasks whose caller chain includes this test.
  # This module is synchronous because the task uses the shared SQL sandbox.
  defp await_asset_tasks do
    caller = self()
    deadline = System.monotonic_time(:millisecond) + 5_000

    monitors =
      Storyarn.TaskSupervisor
      |> Task.Supervisor.children()
      |> Enum.filter(&task_from_test?(&1, caller, deadline))
      |> Enum.map(&{&1, Process.monitor(&1)})

    for {pid, reference} <- monitors do
      assert_receive {:DOWN, ^reference, :process, ^pid, reason}, 5_000
      assert reason in [:normal, :noproc]
    end
  end

  defp task_from_test?(pid, caller, deadline) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} ->
        case Keyword.fetch(dictionary, :"$callers") do
          {:ok, callers} ->
            caller in callers

          :error ->
            # start_child returns before the task publishes its caller chain.
            # Retry only that initialization window, never the task's work.
            assert System.monotonic_time(:millisecond) < deadline,
                   "supervised task did not initialize its caller chain"

            Process.sleep(1)
            task_from_test?(pid, caller, deadline)
        end

      nil ->
        false
    end
  end

  defp start_unrelated_task do
    test_pid = self()

    # A raw process does not inherit the test's $callers chain. Its supervised
    # task stays alive until cleanup, so awaiting it would fail the upload test.
    spawn(fn ->
      {:ok, pid} =
        Task.Supervisor.start_child(Storyarn.TaskSupervisor, fn ->
          receive do
            :stop -> :ok
          end
        end)

      send(test_pid, {:unrelated_task, pid})
    end)

    assert_receive {:unrelated_task, pid}
    on_exit(fn -> Task.Supervisor.terminate_child(Storyarn.TaskSupervisor, pid) end)
    pid
  end
end
