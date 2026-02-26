defmodule StoryarnWeb.SceneLive.FormTest do
  @moduledoc """
  Tests for the SceneLive.Form LiveComponent.

  Exercises update/2, validate event, save event (success + failure + can_edit guard),
  and the notify_parent callback.
  """

  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  alias Storyarn.Repo
  alias Storyarn.Scenes

  # =========================================================================
  # Helpers
  # =========================================================================

  defp scene_index_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes"
  end

  defp scene_new_path(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/scenes/new"
  end

  # =========================================================================
  # Render & update/2
  # =========================================================================

  describe "render" do
    setup :register_and_log_in_user

    test "renders form with title, name input, and description textarea", %{
      conn: conn,
      user: user
    } do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, _view, html} = live(conn, scene_new_path(project))

      assert html =~ "New Scene"
      assert html =~ "Name"
      assert html =~ "Description"
      assert html =~ "Create Scene"
      assert html =~ "Cancel"
    end

    test "cancel link patches back to scene index", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      assert has_element?(view, ~s(a[href="#{scene_index_path(project)}"]), "Cancel")
    end
  end

  # =========================================================================
  # Validate event
  # =========================================================================

  describe "validate" do
    setup :register_and_log_in_user

    test "validates scene params on change", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      # Send a valid name — should not show errors
      html =
        view
        |> form("#scene-form", scene: %{name: "Forest", description: "A dark forest"})
        |> render_change()

      refute html =~ "can&#39;t be blank"
    end

    test "shows validation error when name is blank", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      html =
        view
        |> form("#scene-form", scene: %{name: ""})
        |> render_change()

      assert html =~ "can&#39;t be blank"
    end

    test "shows validation error when name exceeds max length", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      long_name = String.duplicate("a", 201)

      html =
        view
        |> form("#scene-form", scene: %{name: long_name})
        |> render_change()

      assert html =~ "at most 200"
    end
  end

  # =========================================================================
  # Save event — success
  # =========================================================================

  describe "save (success)" do
    setup :register_and_log_in_user

    test "creates scene and sends :saved message to parent", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      view
      |> form("#scene-form", scene: %{name: "Tavern", description: "A cozy inn"})
      |> render_submit()

      # The parent (SceneLive.Index) receives {:saved, scene} and redirects
      # to the scene show page. Assert that a scene was created.
      scenes = Scenes.list_scenes(project.id)
      assert scenes != []
      assert Enum.any?(scenes, &(&1.name == "Tavern"))
    end

    test "redirects to scene show page after successful creation", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      view
      |> form("#scene-form", scene: %{name: "New World"})
      |> render_submit()

      # SceneLive.Index handle_info redirects to scene show
      {path, _flash} = assert_redirect(view)
      assert path =~ "/scenes/"
    end
  end

  # =========================================================================
  # Save event — validation error
  # =========================================================================

  describe "save (error)" do
    setup :register_and_log_in_user

    test "re-renders form with errors when name is blank", %{conn: conn, user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)

      {:ok, view, _html} = live(conn, scene_new_path(project))

      html =
        view
        |> form("#scene-form", scene: %{name: ""})
        |> render_submit()

      assert html =~ "can&#39;t be blank"

      # No scene should have been created
      assert Scenes.list_scenes(project.id) == []
    end
  end

  # =========================================================================
  # Save event — can_edit guard
  # =========================================================================

  describe "save (can_edit guard)" do
    setup :register_and_log_in_user

    test "viewer cannot see the new scene modal", %{conn: conn, user: user} do
      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, user, "viewer")

      # Viewers can access the index but the modal requires :new live_action + can_edit
      {:ok, _view, html} = live(conn, scene_new_path(project))

      # The modal is conditionally rendered: `:if={@live_action == :new and @can_edit}`
      # For a viewer, can_edit is false, so the form should NOT appear
      refute html =~ "scene-form"
    end
  end

  # =========================================================================
  # Authentication
  # =========================================================================

  describe "authentication" do
    test "unauthenticated user cannot access new scene form", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/scenes/new")

      assert {:redirect, %{to: path}} = redirect
      assert path == ~p"/users/log-in"
    end
  end
end
