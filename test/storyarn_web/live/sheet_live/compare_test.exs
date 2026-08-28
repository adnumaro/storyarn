defmodule StoryarnWeb.SheetLive.CompareTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup :register_and_log_in_user

  test "loads Sheet comparison and exposes adjacent version navigation", %{
    conn: conn,
    user: user
  } do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Main character"})

    {:ok, first} = Sheets.create_version(sheet, user.id, title: "First draft")
    {:ok, middle} = Sheets.create_version(sheet, user.id, title: "Review point")
    {:ok, latest} = Sheets.create_version(sheet, user.id, title: "Published sheet")

    path = compare_path(project, sheet, middle.version_number)
    {:ok, view, _html} = live(conn, path)

    compare = LiveVue.Test.get_vue(view, name: "live/versioning/compare/VersioningCompare")

    assert compare.props["version-label"] == "v2 — Review point"
    assert compare.props["back-url"] == sheet_path(project, sheet)
    assert compare.props["prev-version-url"] == compare_path(project, sheet, first.version_number)
    assert compare.props["next-version-url"] == compare_path(project, sheet, latest.version_number)

    assert compare.props["current-url"] ==
             sheet_path(project, sheet) <> "?layout=compact"

    assert compare.props["version-url"] == viewer_path(project, sheet, middle.version_number)
  end

  defp sheet_path(project, sheet) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"
  end

  defp compare_path(project, sheet, version_number) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/compare/#{version_number}"
  end

  defp viewer_path(project, sheet, version_number) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}/versions/#{version_number}/viewer"
  end
end
