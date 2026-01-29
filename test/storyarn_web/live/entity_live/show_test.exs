defmodule StoryarnWeb.EntityLive.ShowTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.EntitiesFixtures
  import Storyarn.ProjectsFixtures

  describe "Show" do
    setup :register_and_log_in_user

    test "renders entity details", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Character", type: "character"})

      entity =
        entity_fixture(project, template, %{
          display_name: "John Doe",
          description: "The main hero"
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}")

      assert html =~ "John Doe"
      assert html =~ entity.technical_name
      assert html =~ "The main hero"
      assert html =~ "Character"
    end

    test "shows edit and delete buttons for editor", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      entity = entity_fixture(project, template)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}")

      assert html =~ "Edit"
      assert html =~ "Delete"
    end

    test "hides edit and delete buttons for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner)
      template = template_fixture(project)
      entity = entity_fixture(project, template)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}")

      refute html =~ "hero-pencil"
      refute html =~ "hero-trash"
    end

    test "renders edit modal", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      entity = entity_fixture(project, template, %{display_name: "Original"})

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}/edit")

      assert html =~ "Edit Entity"
      assert html =~ "Original"
    end

    test "updates entity from edit modal", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      entity = entity_fixture(project, template, %{display_name: "Original"})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}/edit")

      view
      |> form("#entity-form", entity: %{display_name: "Updated"})
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/entities/#{entity.id}")

      html = render(view)
      assert html =~ "Updated"
      assert html =~ "updated successfully"
    end

    test "deletes entity", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      entity = entity_fixture(project, template)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}")

      view
      |> element("button", "Delete")
      |> render_click()

      {path, flash} = assert_redirect(view)
      assert path == "/projects/#{project.id}/entities"
      assert flash["info"] =~ "deleted"
    end

    test "redirects for non-existent entity", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/projects/#{project.id}/entities/999999")

      assert path == "/projects/#{project.id}/entities"
      assert flash["error"] =~ "not found"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)
      template = template_fixture(project)
      entity = entity_fixture(project, template)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/projects/#{project.id}/entities/#{entity.id}")

      assert path == "/projects"
      assert flash["error"] =~ "access"
    end
  end
end
