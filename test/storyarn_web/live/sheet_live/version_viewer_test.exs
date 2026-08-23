defmodule StoryarnWeb.SheetLive.VersionViewerTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Versioning.EntityVersionRecord

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Historical sheet"})

    _block =
      block_fixture(sheet, %{
        type: "text",
        config: %{"label" => "Bio", "placeholder" => "Enter text..."},
        value: %{"content" => "Archived biography"}
      })

    {:ok, version} = Sheets.create_version(sheet, user.id, title: "Review point")

    %{project: project, sheet: sheet, version: version}
  end

  describe "a readable version" do
    test "renders an immutable Sheet surface", %{conn: conn, project: project, sheet: sheet} do
      {:ok, view, _html} = live(conn, viewer_path(project, sheet, 1))

      vue = LiveVue.Test.get_vue(view, name: "live/sheet/show/SheetSurface")
      surface = vue.props["surface"]

      assert vue.component == "live/sheet/show/SheetSurface"
      assert surface["tabs"]["canEdit"] == false
      assert surface["tabs"]["compact"] == true
      assert surface["content"]["canEdit"] == false

      block_labels =
        Enum.map(surface["content"]["blocks"], fn item -> item["block"]["config"]["label"] end)

      assert "Bio" in block_labels

      header = vue.props["sheet"]
      assert header["name"] == "Historical sheet"
    end
  end

  describe "a version that cannot be shown" do
    test "reports a version number that does not exist inside the viewer pane", %{
      conn: conn,
      project: project,
      sheet: sheet
    } do
      assert {:ok, view, _html} = live(conn, viewer_path(project, sheet, 99))

      assert error_reason(view) == "not_found"
      refute render(view) =~ "SheetSurface"
    end

    test "keeps a checksum failure inside the viewer pane", %{
      conn: conn,
      project: project,
      sheet: sheet,
      version: version
    } do
      {1, nil} =
        Repo.update_all(from_version(version), set: [checksum: String.duplicate("a", 64)])

      assert {:ok, view, _html} = live(conn, viewer_path(project, sheet, 1))

      assert error_reason(view) == "integrity"
      refute render(view) =~ "SheetSurface"
    end

    test "keeps a compressed-size failure inside the viewer pane", %{
      conn: conn,
      project: project,
      sheet: sheet,
      version: version
    } do
      {1, nil} =
        Repo.update_all(
          from_version(version),
          set: [snapshot_size_bytes: version.snapshot_size_bytes + 1]
        )

      assert {:ok, view, _html} = live(conn, viewer_path(project, sheet, 1))

      assert error_reason(view) == "integrity"
      refute render(view) =~ "SheetSurface"
    end
  end

  describe "identity and ownership boundaries" do
    test "treats malformed Sheet and version identifiers as not found", %{
      conn: conn,
      project: project,
      sheet: sheet
    } do
      assert {:ok, sheet_error_view, _html} =
               live(conn, viewer_path(project, "not-a-sheet", 1))

      assert error_reason(sheet_error_view) == "not_found"
      refute render(sheet_error_view) =~ "SheetSurface"

      assert {:ok, version_error_view, _html} =
               live(conn, viewer_path(project, sheet, "not-a-version"))

      assert error_reason(version_error_view) == "not_found"
      refute render(version_error_view) =~ "SheetSurface"
    end

    test "treats zero and negative Sheet or version identifiers as not found", %{
      conn: conn,
      project: project,
      sheet: sheet
    } do
      invalid_identifiers = [
        {0, 1},
        {-1, 1},
        {sheet.id, 0},
        {sheet.id, -1}
      ]

      for {sheet_id, version_number} <- invalid_identifiers do
        assert {:ok, view, _html} = live(conn, viewer_path(project, sheet_id, version_number))
        assert error_reason(view) == "not_found"
        refute render(view) =~ "SheetSurface"
      end
    end

    test "does not resolve a Sheet owned by another project", %{
      conn: conn,
      user: user,
      project: project
    } do
      other_project = user |> project_fixture() |> Repo.preload(:workspace)
      other_sheet = sheet_fixture(other_project)
      {:ok, _version} = Sheets.create_version(other_sheet, user.id, title: "Other project")

      assert {:ok, view, _html} = live(conn, viewer_path(project, other_sheet, 1))

      assert error_reason(view) == "not_found"
      refute render(view) =~ "SheetSurface"
    end

    test "does not resolve a version belonging to another Sheet", %{
      conn: conn,
      user: user,
      project: project,
      sheet: sheet
    } do
      other_sheet = sheet_fixture(project)
      {:ok, _first_version} = Sheets.create_version(other_sheet, user.id, title: "First")
      {:ok, other_version} = Sheets.create_version(other_sheet, user.id, title: "Second")

      assert other_version.version_number == 2

      assert {:ok, view, _html} =
               live(conn, viewer_path(project, sheet, other_version.version_number))

      assert error_reason(view) == "not_found"
      refute render(view) =~ "SheetSurface"
    end

    test "redirects a user without project access before loading the Sheet version", %{
      conn: conn,
      project: project,
      sheet: sheet
    } do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_message}}}} =
               live(conn, viewer_path(project, sheet, 1))

      assert error_message =~ "access"
    end
  end

  defp viewer_path(project, sheet, version_number) do
    sheet_id = if is_struct(sheet), do: sheet.id, else: sheet

    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet_id}/versions/#{version_number}/viewer"
  end

  defp error_reason(view) do
    LiveVue.Test.get_vue(view, name: "live/versioning/viewer/VersionViewerError").props["reason"]
  end

  defp from_version(%EntityVersionRecord{id: id}) do
    import Ecto.Query, only: [from: 2]

    from(version in EntityVersionRecord, where: version.id == ^id)
  end
end
