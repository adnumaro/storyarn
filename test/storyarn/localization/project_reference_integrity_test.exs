defmodule Storyarn.Localization.ProjectReferenceIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization.Persistence.ProjectRecord
  alias Storyarn.Localization.ProjectReferenceIntegrity
  alias Storyarn.Repo

  test "requires an explicit transaction for project and reference locks" do
    project = project_fixture(user_fixture())

    assert_raise ArgumentError, ~r/explicit database transaction/, fn ->
      ProjectReferenceIntegrity.lock_active_project(project.id)
    end
  end

  test "locks local records and preserves normalized reference result shape" do
    user = user_fixture()
    project = project_fixture(user)
    asset = audio_asset_fixture(project, user)
    sheet = sheet_fixture(project)

    assert {:ok, :verified} =
             Repo.transaction(fn ->
               assert {:ok, %ProjectRecord{id: project_id}} =
                        ProjectReferenceIntegrity.lock_active_project(Integer.to_string(project.id), :update)

               assert project_id == project.id

               assert {:ok, [asset_id, sheet_id, nil]} =
                        ProjectReferenceIntegrity.lock_active_references(project.id, [
                          {:asset, :voiceover, Integer.to_string(asset.id)},
                          {:sheet, :speaker, sheet.id},
                          {:asset, :optional_portrait, ""}
                        ])

               assert asset_id == asset.id
               assert sheet_id == sheet.id

               assert :ok =
                        ProjectReferenceIntegrity.ensure_locked_asset_content_type(
                          project.id,
                          asset.id,
                          :voiceover,
                          "audio/%"
                        )

               :verified
             end)
  end

  test "rejects cross-project references with the original context and value" do
    project = project_fixture(user_fixture())
    foreign_project = project_fixture(user_fixture())
    foreign_sheet = sheet_fixture(foreign_project)

    assert {:ok, :verified} =
             Repo.transaction(fn ->
               assert {:error, {:invalid_project_reference, :speaker, value}} =
                        ProjectReferenceIntegrity.lock_active_references(project.id, [
                          {:sheet, :speaker, Integer.to_string(foreign_sheet.id)}
                        ])

               assert value == Integer.to_string(foreign_sheet.id)
               :verified
             end)
  end
end
