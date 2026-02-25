defmodule StoryarnWeb.ExportImportLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  describe "Export/Import page" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp export_import_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "renders export/import page", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Export &amp; Import"
      assert html =~ "Export your project data or import from a file."
    end

    test "shows export section heading", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Export"
    end

    test "shows import section heading", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Import"
    end

    test "shows format selection options", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Format"
      # At minimum the StoryarnJSON format should be listed
      assert html =~ "storyarn"
    end

    test "shows content section checkboxes", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Content"
      assert html =~ "Sheets"
      assert html =~ "Flows"
      assert html =~ "Scenes"
      assert html =~ "Screenplays"
      assert html =~ "Localization"
    end

    test "shows asset mode options", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Assets"
      assert html =~ "References only"
      assert html =~ "Embedded"
      assert html =~ "Bundled"
    end

    test "shows export options (validate and pretty print)", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Options"
      assert html =~ "Validate before export"
      assert html =~ "Pretty print output"
    end

    test "shows validate button", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Validate"
    end

    test "shows download button", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ "Download"
    end

    test "shows file upload section for editors", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, export_import_url(project))

      assert html =~ ".storyarn.json"
      assert html =~ "Upload"
    end

    test "toggling a content section updates the UI", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      # Toggle sheets off
      html = view |> render_click("toggle_section", %{"section" => "sheets"})

      # Page still renders (no crash)
      assert html =~ "Export"
    end

    test "changing format updates the page", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      # Set format to storyarn (the default; just verify it doesn't crash)
      html = view |> render_click("set_format", %{"format" => "storyarn"})

      assert html =~ "Export"
    end
  end

  describe "Authentication and authorization" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/export-import")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "user without project access gets redirected", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      other_user = user_fixture()
      project = project_fixture(other_user) |> Repo.preload(:workspace)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(
                 conn,
                 ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
               )

      assert error_msg =~ "not found"
    end

    test "viewer can access the page", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
        )

      assert html =~ "Export"
    end

    test "viewer sees import locked message", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
        )

      assert html =~ "edit permissions to import"
    end

    test "editor can see the upload form", %{conn: conn} do
      editor = user_fixture()
      conn = log_in_user(conn, editor)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, editor, "editor")

      {:ok, _view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
        )

      assert html =~ ".storyarn.json"
      refute html =~ "edit permissions to import"
    end
  end
end
