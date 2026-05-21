defmodule StoryarnWeb.SheetLive.Handlers.HeaderHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Header Sheet", shortcut: "header-sheet"})

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{project: project, sheet: sheet, url: url}
  end

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end

  describe "save_name event" do
    test "updates the sheet name", %{conn: conn, project: project, sheet: sheet, url: url} do
      view = mount_sheet(conn, url)

      render_click(view, "save_name", %{"name" => "Renamed Header Sheet"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.name == "Renamed Header Sheet"
    end
  end

  describe "save_shortcut event" do
    test "updates the sheet shortcut", %{conn: conn, project: project, sheet: sheet, url: url} do
      view = mount_sheet(conn, url)

      render_click(view, "save_shortcut", %{"shortcut" => "renamed-header"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.shortcut == "renamed-header"
    end

    test "normalizes an empty shortcut to nil", %{conn: conn, project: project, sheet: sheet, url: url} do
      view = mount_sheet(conn, url)

      render_click(view, "save_shortcut", %{"shortcut" => ""})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.shortcut == nil
    end

    test "keeps the current shortcut when the new shortcut is invalid", %{
      conn: conn,
      project: project,
      sheet: sheet,
      url: url
    } do
      view = mount_sheet(conn, url)

      render_click(view, "save_shortcut", %{"shortcut" => "Invalid Shortcut!"})

      updated_sheet = Sheets.get_sheet(project.id, sheet.id)
      assert updated_sheet.shortcut == "header-sheet"
    end
  end
end
