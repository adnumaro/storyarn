defmodule StoryarnWeb.ScreenplayExportControllerTest do
  use StoryarnWeb.ConnCase

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
    %{project: project}
  end

  defp export_url(project, screenplay) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}/export/fountain"
  end

  describe "GET fountain" do
    test "downloads .fountain file with correct headers and content", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "My Script"})

      element_fixture(screenplay, %{
        type: "scene_heading",
        content: "INT. OFFICE - DAY",
        position: 0
      })

      element_fixture(screenplay, %{type: "action", content: "A desk.", position: 1})

      conn = get(conn, export_url(project, screenplay))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ ".fountain"

      body = conn.resp_body
      assert body =~ "INT. OFFICE - DAY"
      assert body =~ "A desk."
    end

    test "returns 404 for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      screenplay = screenplay_fixture(project, %{name: "Private Script"})

      conn = get(conn, export_url(project, screenplay))

      assert conn.status == 404
    end

    test "skips interactive elements in export output", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Walk.", position: 0})

      element_fixture(screenplay, %{
        type: "conditional",
        content: "",
        position: 1,
        data: %{"condition" => %{"logic" => "all", "rules" => []}}
      })

      element_fixture(screenplay, %{type: "action", content: "Run.", position: 2})

      conn = get(conn, export_url(project, screenplay))

      body = conn.resp_body
      assert body =~ "Walk."
      assert body =~ "Run."
      refute body =~ "conditional"
    end

    test "title_page element appears as Fountain metadata block", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Title Test"})

      element_fixture(screenplay, %{
        type: "title_page",
        content: "",
        position: 0,
        data: %{
          "title" => "My Great Script",
          "author" => "Studio Dev",
          "draft_date" => "2025-01-01"
        }
      })

      element_fixture(screenplay, %{type: "action", content: "He walks.", position: 1})

      conn = get(conn, export_url(project, screenplay))

      body = conn.resp_body
      assert body =~ "Title: My Great Script"
      assert body =~ "Author: Studio Dev"
      assert body =~ "Draft date: 2025-01-01"
      assert body =~ "He walks."
    end

    test "filename is slugified from screenplay name", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project, %{name: "My Great Script!"})
      element_fixture(screenplay, %{type: "action", content: "Test."})

      conn = get(conn, export_url(project, screenplay))

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "my-great-script.fountain"
    end
  end
end
