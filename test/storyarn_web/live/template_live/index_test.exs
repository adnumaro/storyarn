defmodule StoryarnWeb.TemplateLive.IndexTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.EntitiesFixtures
  import Storyarn.ProjectsFixtures

  describe "Index" do
    setup :register_and_log_in_user

    test "renders template list for project member", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Character", type: "character"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      assert html =~ "Entity Templates"
      assert html =~ "Character"
      assert html =~ template.type
    end

    test "shows empty state when no templates", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      assert html =~ "No templates yet"
      assert html =~ "Create Default Templates"
    end

    test "shows new template button for editor", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      assert html =~ "New Template"
    end

    test "hides new template button for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      refute html =~ "New Template"
    end

    test "shows entity count for each template", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      _entity1 = entity_fixture(project, template)
      _entity2 = entity_fixture(project, template)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      assert html =~ "2 entities"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/projects/#{project.id}/templates")

      assert path == "/projects"
      assert flash["error"] =~ "access"
    end
  end

  describe "Create template" do
    setup :register_and_log_in_user

    test "creates template from modal", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/templates/new")

      view
      |> form("#template-form",
        entity_template: %{name: "Hero", type: "character", description: "Main hero template"}
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/templates")

      html = render(view)
      assert html =~ "Hero"
      assert html =~ "created successfully"
    end

    test "validates required fields", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/templates/new")

      html =
        view
        |> form("#template-form", entity_template: %{name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "validates unique name", %{conn: conn, user: user} do
      project = project_fixture(user)
      _template = template_fixture(project, %{name: "Character"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/templates/new")

      html =
        view
        |> form("#template-form", entity_template: %{name: "Character", type: "character"})
        |> render_submit()

      assert html =~ "has already been taken"
    end
  end

  describe "Update template" do
    setup :register_and_log_in_user

    test "updates template from modal", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project, %{name: "Original"})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/templates/#{template.id}/edit")

      view
      |> form("#template-form", entity_template: %{name: "Updated"})
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/templates")

      html = render(view)
      assert html =~ "Updated"
      assert html =~ "updated successfully"
    end
  end

  describe "Delete template" do
    setup :register_and_log_in_user

    test "deletes template with no entities", %{conn: conn, user: user} do
      project = project_fixture(user)
      _template = template_fixture(project, %{name: "ToDelete"})

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      assert html =~ "ToDelete"

      view
      |> element("button[phx-click=\"delete\"]")
      |> render_click()

      html = render(view)
      refute html =~ "ToDelete"
      assert html =~ "deleted successfully"
    end

    test "hides delete button for templates with entities", %{conn: conn, user: user} do
      project = project_fixture(user)
      template = template_fixture(project)
      _entity = entity_fixture(project, template)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/templates")

      # The delete button should not be present for templates with entities
      refute html =~ ~r/phx-click="delete"[^>]*phx-value-id="#{template.id}"/
    end
  end

  describe "Create default templates" do
    setup :register_and_log_in_user

    test "creates default templates for all types", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/templates")

      view
      |> element("button", "Create Default Templates")
      |> render_click()

      html = render(view)
      assert html =~ "Character"
      assert html =~ "Location"
      assert html =~ "Item"
      assert html =~ "Custom"
      assert html =~ "created successfully"
    end
  end
end
