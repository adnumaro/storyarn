defmodule StoryarnWeb.ScreenplayLive.ShowTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures

  alias Storyarn.Repo

  describe "Show" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp show_url(project, screenplay) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/screenplays/#{screenplay.id}"
    end

    # -------------------------------------------------------------------------
    # Rendering
    # -------------------------------------------------------------------------

    test "renders screenplay page container", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project, %{name: "My Script"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(id="screenplay-page")
      assert html =~ "screenplay-page"
    end

    test "renders element content when elements exist", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "He walks into the room."})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "He walks into the room."
    end

    test "shows empty state when no elements", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "Start typing or press / for commands"
    end

    test "elements have correct type CSS class", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY"})
      element_fixture(screenplay, %{type: "character", content: "JOHN"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "sp-scene_heading"
      assert html =~ "sp-character"
      assert html =~ "INT. OFFICE - DAY"
      assert html =~ "JOHN"
    end

    test "element renderer renders data attributes", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "She runs."})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(data-element-id="#{el.id}")
      assert html =~ ~s(data-element-type="action")
      assert html =~ ~s(data-position="#{el.position}")
    end

    test "interactive blocks render as stubs with type label", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "conditional", content: ""})
      element_fixture(screenplay, %{type: "instruction", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "sp-stub-badge"
      assert html =~ "Conditional"
      assert html =~ "Instruction"
    end

    test "page break renders as visual separator", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "page_break", content: ""})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ "sp-page_break"
      assert html =~ "sp-page-break-line"
    end

    test "elements render as contenteditable when user has edit permission", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      element_fixture(screenplay, %{type: "action", content: "Editable."})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(contenteditable="true")
      assert html =~ "ScreenplayElement"
    end

    test "toolbar renders screenplay name", %{conn: conn, project: project} do
      screenplay = screenplay_fixture(project, %{name: "My Great Script"})

      {:ok, _view, html} = live(conn, show_url(project, screenplay))

      assert html =~ ~s(id="screenplay-toolbar")
      assert html =~ "My Great Script"
      assert html =~ ~s(id="screenplay-title")
    end

    # -------------------------------------------------------------------------
    # Element content editing
    # -------------------------------------------------------------------------

    test "update_element_content persists content change to database", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Original."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_element_content", %{
        "id" => to_string(el.id),
        "content" => "Updated content."
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.content == "Updated content."
    end

    test "update_element_content auto-detects scene heading from content", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: ""})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_element_content", %{
        "id" => to_string(el.id),
        "content" => "INT. OFFICE - DAY"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.type == "scene_heading"
      assert updated.content == "INT. OFFICE - DAY"
    end

    test "update_element_content with malformed ID does not crash", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      _el = element_fixture(screenplay, %{type: "action", content: "Test."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_element_content", %{
        "id" => "not-a-number",
        "content" => "Hacked!"
      })

      assert render(view) =~ "screenplay-page"
    end

    # -------------------------------------------------------------------------
    # Element creation (Enter key)
    # -------------------------------------------------------------------------

    test "create_next_element creates element at correct position", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el1 = element_fixture(screenplay, %{type: "action", content: "First.", position: 0})
      _el2 = element_fixture(screenplay, %{type: "action", content: "Second.", position: 1})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_next_element", %{
        "after_id" => to_string(el1.id),
        "content" => ""
      })

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 3
      new_el = Enum.at(elements, 1)
      assert new_el.position == 1
      assert new_el.type == "action"
    end

    test "create_next_element after scene_heading creates action type", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "scene_heading", content: "INT. OFFICE - DAY"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_next_element", %{
        "after_id" => to_string(el.id),
        "content" => ""
      })

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      new_el = Enum.at(elements, 1)
      assert new_el.type == "action"
    end

    test "create_next_element after character creates dialogue type", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "character", content: "JOHN"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_next_element", %{
        "after_id" => to_string(el.id),
        "content" => ""
      })

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      new_el = Enum.at(elements, 1)
      assert new_el.type == "dialogue"
    end

    test "create_next_element computes type server-side (ignores client hint)", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "character", content: "SARAH"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      # Client sends wrong type "transition" — server should override to "dialogue"
      view
      |> render_click("create_next_element", %{
        "after_id" => to_string(el.id),
        "type" => "transition",
        "content" => ""
      })

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      new_el = Enum.at(elements, 1)
      assert new_el.type == "dialogue"
    end

    test "create_first_element creates action element on empty screenplay", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_first_element")

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
      [el] = elements
      assert el.type == "action"
      assert el.content == ""
      assert el.position == 0
    end

    # -------------------------------------------------------------------------
    # Element deletion & type cycling
    # -------------------------------------------------------------------------

    test "delete_element removes element and compacts positions", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el1 = element_fixture(screenplay, %{type: "action", content: "First.", position: 0})
      _el2 = element_fixture(screenplay, %{type: "action", content: "Second.", position: 1})
      _el3 = element_fixture(screenplay, %{type: "action", content: "Third.", position: 2})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el1.id)})

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 2
      assert Enum.map(elements, & &1.position) == [0, 1]
      assert Enum.map(elements, & &1.content) == ["Second.", "Third."]
    end

    test "delete_element of the last element leaves empty list", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Only."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert elements == []
      assert render(view) =~ "Start typing or press / for commands"
    end

    test "change_element_type changes type while preserving content", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "JOHN WALKS IN"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("change_element_type", %{
        "id" => to_string(el.id),
        "type" => "scene_heading"
      })

      updated = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert updated.type == "scene_heading"
      assert updated.content == "JOHN WALKS IN"
    end

    # -------------------------------------------------------------------------
    # Toolbar
    # -------------------------------------------------------------------------

    test "save_name event updates screenplay name and refreshes tree", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Old Name"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("save_name", %{"name" => "New Name"})

      updated = Storyarn.Screenplays.get_screenplay!(project.id, screenplay.id)
      assert updated.name == "New Name"
    end

    # -------------------------------------------------------------------------
    # Sidebar
    # -------------------------------------------------------------------------

    test "create_screenplay from sidebar creates and navigates", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Current"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("create_screenplay")

      {path, _flash} = assert_redirect(view)
      assert path =~ "/screenplays/"
    end

    test "delete_screenplay of another screenplay reloads tree", %{
      conn: conn,
      project: project
    } do
      current = screenplay_fixture(project, %{name: "Current"})
      other = screenplay_fixture(project, %{name: "Other"})

      {:ok, view, html} = live(conn, show_url(project, current))

      assert html =~ "Other"

      view |> render_click("delete_screenplay", %{"id" => to_string(other.id)})

      html = render(view)
      refute html =~ "Other"
      assert html =~ "Screenplay moved to trash"
    end

    test "delete_screenplay of current screenplay redirects to index", %{
      conn: conn,
      project: project
    } do
      screenplay = screenplay_fixture(project, %{name: "Self Delete"})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_screenplay", %{"id" => to_string(screenplay.id)})

      {path, flash} = assert_redirect(view)
      assert path =~ "/screenplays"
      assert flash["info"] =~ "trash"
    end

    # -------------------------------------------------------------------------
    # Authorization
    # -------------------------------------------------------------------------

    test "viewer cannot update element content", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Protected."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("update_element_content", %{
        "id" => to_string(el.id),
        "content" => "Hacked!"
      })

      assert render(view) =~ "permission"
      unchanged = Storyarn.Screenplays.list_elements(screenplay.id) |> hd()
      assert unchanged.content == "Protected."
    end

    test "viewer cannot create elements", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Protected."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view
      |> render_click("create_next_element", %{
        "after_id" => to_string(el.id),
        "content" => ""
      })

      assert render(view) =~ "permission"
      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
    end

    test "viewer cannot delete elements", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")
      screenplay = screenplay_fixture(project)
      el = element_fixture(screenplay, %{type: "action", content: "Protected."})

      {:ok, view, _html} = live(conn, show_url(project, screenplay))

      view |> render_click("delete_element", %{"id" => to_string(el.id)})

      assert render(view) =~ "permission"
      elements = Storyarn.Screenplays.list_elements(screenplay.id)
      assert length(elements) == 1
    end

    test "redirects non-members to /workspaces", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      screenplay = screenplay_fixture(project, %{name: "Private"})

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, show_url(project, screenplay))

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end
  end
end
