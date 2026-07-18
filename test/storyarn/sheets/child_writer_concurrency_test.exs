defmodule Storyarn.Sheets.ChildWriterConcurrencyTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Storyarn.Accounts.User
  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.BlockGalleryImage
  alias Storyarn.Sheets.Sheet
  alias Storyarn.Sheets.SheetAvatar
  alias Storyarn.Workspaces.Workspace

  @task_timeout 15_000

  test "opposite default-avatar selections serialize instead of deadlocking" do
    unboxed_scenario(fn %{project: project, user: user} ->
      sheet = sheet_fixture(project)
      first_asset = image_asset_fixture(project, user)
      second_asset = image_asset_fixture(project, user)
      {:ok, first} = Sheets.add_avatar(sheet, first_asset.id)
      {:ok, second} = Sheets.add_avatar(sheet, second_asset.id)

      Enum.each(1..4, fn _attempt ->
        assert_concurrent_success(
          fn -> Sheets.set_avatar_default(first) end,
          fn -> Sheets.set_avatar_default(second) end
        )
      end)

      assert Enum.count(Sheets.list_avatars(sheet.id), & &1.is_default) == 1
    end)
  end

  test "inverse avatar reorders serialize instead of deadlocking" do
    unboxed_scenario(fn %{project: project, user: user} ->
      sheet = sheet_fixture(project)
      first_asset = image_asset_fixture(project, user)
      second_asset = image_asset_fixture(project, user)
      {:ok, first} = Sheets.add_avatar(sheet, first_asset.id)
      {:ok, second} = Sheets.add_avatar(sheet, second_asset.id)

      Enum.each(1..4, fn _attempt ->
        assert_concurrent_success(
          fn -> Sheets.reorder_avatars(sheet.id, [first.id, second.id]) end,
          fn -> Sheets.reorder_avatars(sheet.id, [second.id, first.id]) end
        )
      end)

      assert Enum.map(Sheets.list_avatars(sheet.id), & &1.position) == [0, 1]
    end)
  end

  test "inverse gallery-image reorders serialize instead of deadlocking" do
    unboxed_scenario(fn %{project: project, user: user} ->
      sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "gallery"})
      first_asset = image_asset_fixture(project, user)
      second_asset = image_asset_fixture(project, user)
      {:ok, first} = Sheets.add_gallery_image(block, first_asset.id)
      {:ok, second} = Sheets.add_gallery_image(block, second_asset.id)

      Enum.each(1..4, fn _attempt ->
        assert_concurrent_success(
          fn ->
            Sheets.reorder_gallery_images(block.id, [
              first.id,
              second.id
            ])
          end,
          fn ->
            Sheets.reorder_gallery_images(block.id, [
              second.id,
              first.id
            ])
          end
        )
      end)

      assert Enum.map(Sheets.list_gallery_images(block.id), & &1.position) == [0, 1]
    end)
  end

  defp assert_concurrent_success(first_writer, second_writer) do
    barrier = make_ref()
    first_task = concurrent_writer(self(), barrier, first_writer)
    second_task = concurrent_writer(self(), barrier, second_writer)

    assert_receive {^barrier, :ready, first_pid}, @task_timeout
    assert_receive {^barrier, :ready, second_pid}, @task_timeout
    assert MapSet.new([first_pid, second_pid]) == MapSet.new([first_task.pid, second_task.pid])

    send(first_task.pid, {barrier, :write})
    send(second_task.pid, {barrier, :write})

    assert {:ok, _result} = Task.await(first_task, @task_timeout)
    assert {:ok, _result} = Task.await(second_task, @task_timeout)
  end

  defp concurrent_writer(parent, barrier, writer) do
    Task.async(fn ->
      Sandbox.unboxed_run(Repo, fn ->
        send(parent, {barrier, :ready, self()})

        receive do
          {^barrier, :write} -> writer.()
        after
          @task_timeout -> exit(:writer_barrier_timeout)
        end
      end)
    end)
  end

  defp unboxed_scenario(test_fun) do
    Sandbox.unboxed_run(Repo, fn ->
      user =
        user_fixture(%{
          email: "sheet-child-writer-concurrency-#{Ecto.UUID.generate()}@example.com"
        })

      project = project_fixture(user)

      try do
        test_fun.(%{user: user, project: project})
      after
        sheet_ids =
          Repo.all(
            from(sheet in Sheet,
              where: sheet.project_id == ^project.id,
              select: sheet.id
            )
          )

        block_ids =
          Repo.all(
            from(block in Block,
              where: block.sheet_id in ^sheet_ids,
              select: block.id
            )
          )

        Repo.delete_all(from(image in BlockGalleryImage, where: image.block_id in ^block_ids))
        Repo.delete_all(from(avatar in SheetAvatar, where: avatar.sheet_id in ^sheet_ids))
        Repo.delete_all(from(workspace in Workspace, where: workspace.id == ^project.workspace_id))
        Repo.delete_all(from(user_row in User, where: user_row.id == ^user.id))
      end
    end)
  end
end
