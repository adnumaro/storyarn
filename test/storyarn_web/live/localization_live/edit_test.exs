defmodule StoryarnWeb.LocalizationLive.EditTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  alias Storyarn.Repo

  describe "Edit translation page" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp edit_url(project, text) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
    end

    test "renders localization edit page with text info", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id, %{source_text: "Hello world", locale_code: "es"})

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Edit Translation"
      assert html =~ "Hello world"
      assert html =~ "es"
    end

    test "shows source text in read-only panel", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_text: "Welcome adventurer",
          locale_code: "es",
          word_count: 2
        })

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Source"
      assert html =~ "Welcome adventurer"
      assert html =~ "2 words"
    end

    test "shows translation form with textarea and status select", %{
      conn: conn,
      project: project
    } do
      text = localized_text_fixture(project.id)

      {:ok, view, html} = live(conn, edit_url(project, text))

      assert html =~ "Translation"
      assert html =~ "Status"
      assert html =~ "Save"
      assert has_element?(view, "#translation-form")
    end

    test "shows back link to localization index", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Back"
      assert html =~ "/localization"
    end

    test "shows source type and field metadata", %{conn: conn, project: project} do
      text =
        localized_text_fixture(project.id, %{
          source_type: "flow_node",
          source_field: "text"
        })

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "flow_node"
      assert html =~ "text"
    end

    test "shows status options in select dropdown", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Pending"
      assert html =~ "Draft"
      assert html =~ "In Progress"
      assert html =~ "Review"
      assert html =~ "Final"
    end

    test "shows translator notes field", %{conn: conn, project: project} do
      text = localized_text_fixture(project.id)

      {:ok, _view, html} = live(conn, edit_url(project, text))

      assert html =~ "Translator Notes"
    end
  end

  describe "Authentication and authorization" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/localization/1")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "user without project access gets redirected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      other_user = user_fixture()
      project = project_fixture(other_user) |> Repo.preload(:workspace)
      text = localized_text_fixture(project.id)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(
                 conn,
                 ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
               )

      assert error_msg =~ "not found"
    end

    test "member with viewer role can access the page", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")
      text = localized_text_fixture(project.id)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/#{text.id}"
        )

      assert html =~ "Edit Translation"
    end
  end
end
