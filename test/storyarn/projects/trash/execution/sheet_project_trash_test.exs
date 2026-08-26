defmodule Storyarn.Projects.SheetProjectTrashTest do
  @moduledoc """
  Pins that the Project-owned Sheet trash lifecycle behaves exactly like the
  Sheet tool's own restore and purge, which it duplicates.
  """
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Persistence.SheetRecord
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Block
  alias Storyarn.Sheets.Sheet

  setup do
    user = user_fixture()
    project = project_fixture(user)
    %{user: user, project: project}
  end

  describe "get_trashed/2" do
    test "returns only trashed sheets of the project", %{project: project} do
      active = sheet_fixture(project)
      trashed = sheet_fixture(project)
      {:ok, _} = Sheets.trash_sheet(trashed)

      assert %SheetRecord{id: trashed_id} = Projects.get_trashed_sheet(project.id, trashed.id)
      assert trashed_id == trashed.id
      assert Projects.get_trashed_sheet(project.id, active.id) == nil

      other_project = project_fixture(user_fixture())
      assert Projects.get_trashed_sheet(other_project.id, trashed.id) == nil
    end
  end

  describe "restore/1" do
    test "clears deleted_at and reconciles blocks like the tool restore", %{project: project} do
      sheet = sheet_fixture(project)
      target = sheet_fixture(project, %{name: "Target"})

      _block =
        block_fixture(sheet, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => target.id}
        })

      {:ok, _trashed} = Sheets.trash_sheet(sheet)
      trashed_record = Projects.get_trashed_sheet(project.id, sheet.id)

      assert {:ok, %SheetRecord{deleted_at: nil}} = Projects.restore_trashed_sheet(trashed_record)
      assert Sheets.get_sheet(project.id, sheet.id)
    end

    test "rejects restore while a referenced target sits in trash, without mutating", %{project: project} do
      sheet = sheet_fixture(project, %{name: "Source"})
      target = sheet_fixture(project, %{name: "Target"})

      block_fixture(sheet, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => target.id}
      })

      {:ok, _} = Sheets.delete_sheet(sheet)
      {:ok, _} = Sheets.delete_sheet(target)

      trashed_record = Projects.get_trashed_sheet(project.id, sheet.id)

      assert {:error, _reason} = Projects.restore_trashed_sheet(trashed_record)
      assert %Sheet{deleted_at: %DateTime{}} = Repo.get!(Sheet, sheet.id)
    end

    test "does not restore independently deleted blocks", %{project: project} do
      sheet = sheet_fixture(project)
      block = block_fixture(sheet)

      {:ok, _} = Sheets.delete_block(block)
      assert Sheets.get_block(block.id) == nil

      {:ok, _trashed} = Sheets.trash_sheet(sheet)
      trashed_record = Projects.get_trashed_sheet(project.id, sheet.id)
      assert {:ok, _} = Projects.restore_trashed_sheet(trashed_record)

      assert Sheets.get_block(block.id) == nil
    end

    test "agrees with the tool restore on the same starting state", %{project: project} do
      tool_sheet = sheet_fixture(project, %{name: "Via tool"})
      project_sheet = sheet_fixture(project, %{name: "Via project"})
      block_fixture(tool_sheet, %{type: "text", config: %{"label" => "Name"}})
      block_fixture(project_sheet, %{type: "text", config: %{"label" => "Name"}})

      {:ok, _} = Sheets.trash_sheet(tool_sheet)
      {:ok, _} = Sheets.trash_sheet(project_sheet)

      {:ok, tool_restored} = Sheets.restore_sheet(Sheets.get_trashed_sheet(project.id, tool_sheet.id))

      {:ok, project_restored} =
        Projects.restore_trashed_sheet(Projects.get_trashed_sheet(project.id, project_sheet.id))

      assert tool_restored.deleted_at == nil
      assert project_restored.deleted_at == nil

      assert length(Sheets.list_blocks(tool_sheet.id)) ==
               length(Sheets.list_blocks(project_sheet.id))
    end
  end

  describe "hard_delete/1" do
    test "removes versions, localization rows, and inbound references", %{project: project, user: user} do
      sheet = sheet_fixture(project)
      block = block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      sheet_with_blocks = Repo.preload(sheet, :blocks, force: true)

      {:ok, version} = Sheets.create_version(sheet_with_blocks, user.id, title: "Kept until purge")

      referrer = sheet_fixture(project, %{name: "Referrer"})

      block_fixture(referrer, %{
        type: "reference",
        value: %{"target_type" => "sheet", "target_id" => sheet.id}
      })

      assert Sheets.count_backlinks("sheet", sheet.id) == 1

      {:ok, _} = Sheets.trash_sheet(sheet)
      trashed_record = Projects.get_trashed_sheet(project.id, sheet.id)

      assert {:ok, %SheetRecord{}} = Projects.permanently_delete_trashed_sheet(trashed_record)

      assert Repo.get(Sheet, sheet.id) == nil
      assert Repo.get(Block, block.id) == nil
      assert Sheets.get_version(sheet.id, version.version_number) == nil

      # References from still-active blocks are deliberately retained — the
      # editor shows them as "not found", exactly as the tool purge behaves.
      assert Sheets.count_backlinks("sheet", sheet.id) == 1
    end

    test "agrees with the tool purge on the same starting state", %{project: project, user: user} do
      tool_sheet = sheet_fixture(project, %{name: "Via tool"})
      project_sheet = sheet_fixture(project, %{name: "Via project"})

      for sheet <- [tool_sheet, project_sheet] do
        block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
        with_blocks = Repo.preload(sheet, :blocks, force: true)
        {:ok, _} = Sheets.create_version(with_blocks, user.id, title: "Kept until purge")

        referrer = sheet_fixture(project, %{name: "Referrer of #{sheet.name}"})

        block_fixture(referrer, %{
          type: "reference",
          value: %{"target_type" => "sheet", "target_id" => sheet.id}
        })

        {:ok, _} = Sheets.trash_sheet(sheet)
      end

      {:ok, _} = Sheets.permanently_delete_sheet(Sheets.get_trashed_sheet(project.id, tool_sheet.id))

      {:ok, _} =
        Projects.permanently_delete_trashed_sheet(Projects.get_trashed_sheet(project.id, project_sheet.id))

      for sheet <- [tool_sheet, project_sheet] do
        assert Repo.get(Sheet, sheet.id) == nil
        assert Sheets.count_versions(sheet.id) == 0
      end

      assert Sheets.count_backlinks("sheet", tool_sheet.id) ==
               Sheets.count_backlinks("sheet", project_sheet.id)
    end
  end
end
