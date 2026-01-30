defmodule StoryarnWeb.VariableLive.IndexTest do
  use StoryarnWeb.ConnCase

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.EntitiesFixtures
  import Storyarn.ProjectsFixtures

  describe "Index" do
    setup :register_and_log_in_user

    test "renders variable list for project member", %{conn: conn, user: user} do
      project = project_fixture(user)

      variable =
        variable_fixture(project, %{
          name: "player_health",
          type: "integer",
          default_value: "100",
          category: "player"
        })

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/variables")

      assert html =~ "Variables"
      assert html =~ variable.name
      assert html =~ "integer"
      assert html =~ "100"
      assert html =~ "player"
    end

    test "shows empty state when no variables", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/variables")

      assert html =~ "No variables yet"
    end

    test "groups variables by category", %{conn: conn, user: user} do
      project = project_fixture(user)
      _var1 = variable_fixture(project, %{name: "health", category: "player"})
      _var2 = variable_fixture(project, %{name: "score", category: "game"})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/variables")

      assert html =~ "player"
      assert html =~ "game"
    end

    test "shows new variable button for editor", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/variables")

      assert html =~ "New Variable"
    end

    test "hides new variable button for viewer", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner)
      _membership = membership_fixture(project, user, "viewer")

      {:ok, _view, html} = live(conn, ~p"/projects/#{project.id}/variables")

      refute html =~ "New Variable"
    end

    test "redirects for non-member", %{conn: conn} do
      owner = user_fixture()
      project = project_fixture(owner)

      {:error, {:redirect, %{to: path, flash: flash}}} =
        live(conn, ~p"/projects/#{project.id}/variables")

      assert path == "/workspaces"
      assert flash["error"] =~ "access"
    end
  end

  describe "Create variable" do
    setup :register_and_log_in_user

    test "creates variable from modal", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/variables/new")

      view
      |> form("#variable-form",
        variable: %{
          name: "player_score",
          type: "integer",
          default_value: "0",
          category: "player"
        }
      )
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/variables")

      html = render(view)
      assert html =~ "player_score"
      assert html =~ "created successfully"
    end

    test "validates name format", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/variables/new")

      html =
        view
        |> form("#variable-form", variable: %{name: "Invalid Name", type: "boolean"})
        |> render_change()

      assert html =~ "must start with a letter"
    end

    test "validates default value matches type", %{conn: conn, user: user} do
      project = project_fixture(user)

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/variables/new")

      # Submit invalid data to trigger validation
      html =
        view
        |> form("#variable-form",
          variable: %{name: "test_var", type: "integer", default_value: "not_a_number"}
        )
        |> render_submit()

      assert html =~ "must be a valid integer"
    end

    test "validates unique name", %{conn: conn, user: user} do
      project = project_fixture(user)
      _variable = variable_fixture(project, %{name: "existing"})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/variables/new")

      html =
        view
        |> form("#variable-form", variable: %{name: "existing", type: "boolean"})
        |> render_submit()

      assert html =~ "has already been taken"
    end
  end

  describe "Update variable" do
    setup :register_and_log_in_user

    test "updates variable from modal", %{conn: conn, user: user} do
      project = project_fixture(user)
      variable = variable_fixture(project, %{name: "original", description: ""})

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/variables/#{variable.id}/edit")

      view
      |> form("#variable-form", variable: %{description: "Updated description"})
      |> render_submit()

      assert_patch(view, ~p"/projects/#{project.id}/variables")

      html = render(view)
      assert html =~ "updated successfully"
    end
  end

  describe "Delete variable" do
    setup :register_and_log_in_user

    test "deletes variable", %{conn: conn, user: user} do
      project = project_fixture(user)
      variable = variable_fixture(project, %{name: "to_delete"})

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/variables")

      assert html =~ "to_delete"

      view
      |> element(~s|button[phx-click="delete"][phx-value-id="#{variable.id}"]|)
      |> render_click()

      html = render(view)
      refute html =~ "to_delete"
      assert html =~ "deleted successfully"
    end
  end
end
