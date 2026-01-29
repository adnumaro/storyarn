defmodule StoryarnWeb.EntityLive.IndexTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.EntitiesFixtures
  import Storyarn.ProjectsFixtures

  describe "Index" do
    setup :register_and_log_in_user

    test "renders entity list for project member", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Character", type: "character"})
      entity = entity_fixture(project, template, %{display_name: "John Doe"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/entities")

      assert html =~ "Entities"
      assert html =~ "John Doe"
      assert html =~ entity.technical_name
    end

    test "shows empty state when no entities", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/entities")

      assert html =~ "No entities yet"
    end

    test "filters entities by type", %{conn: conn, user: user} do
      project = project_fixture(user)
      char_template = template_fixture(project, %{name: "Character", type: "character"})
      loc_template = template_fixture(project, %{name: "Location", type: "location"})
      _char = entity_fixture(project, char_template, %{display_name: "Hero"})
      _loc = entity_fixture(project, loc_template, %{display_name: "Forest"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/entities")

      html = view |> element("select[name=type]") |> render_change(%{type: "location"})

      assert html =~ "Forest"
      refute html =~ "Hero"
    end

    test "searches entities by name", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      _entity1 = entity_fixture(project, template, %{display_name: "John Doe"})
      _entity2 = entity_fixture(project, template, %{display_name: "Jane Smith"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/entities")

      html = view |> element("input[name=search]") |> render_keyup(%{search: "Jane"})

      assert html =~ "Jane Smith"
      refute html =~ "John Doe"
    end

    test "shows new entity dropdown with templates", %{conn: conn, user: user} do
      project = project_fixture(user)
      _template = template_fixture(project, %{name: "Character", type: "character"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/entities")

      assert html =~ "New Entity"
      assert html =~ "Character"
    end

    test "navigates to new entity form when template selected", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Character", type: "character"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/entities/new?template_id=#{template.id}")

      assert html =~ "New Entity"
      assert html =~ "Character"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/projects/#{project.id}/entities")

      assert path == "/projects"
      assert flash["error"] =~ "access"
    end
  end

  describe "Create entity" do
    setup :register_and_log_in_user

    test "creates entity and redirects to show", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/entities/new?template_id=#{template.id}")

      view
      |> form("#entity-form", entity: %{display_name: "New Hero"})
      |> render_submit()

      {path, flash} = assert_redirect(view)
      assert path =~ ~r"/projects/#{project.id}/entities/\d+"
      assert flash["info"] =~ "created"
    end

    test "validates required fields", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/entities/new?template_id=#{template.id}")

      html =
        view
        |> form("#entity-form", entity: %{display_name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end
  end
end
