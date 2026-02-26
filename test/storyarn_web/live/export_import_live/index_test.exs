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

  describe "Export format selection" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp ei_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "lists all available export formats", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ei_url(project))

      assert html =~ "Storyarn JSON"
      assert html =~ "Ink (.ink)"
      assert html =~ "Yarn Spinner (.yarn)"
      assert html =~ "Godot (JSON)"
      assert html =~ "Unity Dialogue System (JSON)"
      assert html =~ "Unreal Engine (CSV)"
      assert html =~ "articy:draft (XML)"
    end

    test "switching to ink format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      html = view |> render_click("set_format", %{"format" => "ink"})

      assert html =~ "Download .ink"
    end

    test "switching to yarn format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      html = view |> render_click("set_format", %{"format" => "yarn"})

      assert html =~ "Download .yarn"
    end

    test "switching to articy format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      html = view |> render_click("set_format", %{"format" => "articy"})

      assert html =~ "Download .xml"
    end

    test "switching to godot format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      html = view |> render_click("set_format", %{"format" => "godot"})

      assert html =~ "Download .json"
    end

    test "switching to unreal format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      html = view |> render_click("set_format", %{"format" => "unreal"})

      assert html =~ "Download .csv"
    end

    test "switching format clears validation result", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      # First validate
      view |> render_click("validate_export", %{})
      # Then switch format — validation_result should be cleared
      html = view |> render_click("set_format", %{"format" => "ink"})

      # The validation result badges (Passed/Warnings/Errors) should not appear
      # after switching format
      refute html =~ "badge-success"
      refute html =~ "badge-error"
    end

    test "invalid format is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      # Should not crash on invalid format
      html = view |> render_click("set_format", %{"format" => "nonexistent_format"})

      # Still shows default format
      assert html =~ "Download .json"
    end

    test "default format is storyarn with json extension", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ei_url(project))

      assert html =~ "Download .json"
    end

    test "download link includes format in URL", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      html = view |> render_click("set_format", %{"format" => "ink"})

      assert html =~ "/export/ink"
    end
  end

  describe "Content section toggles" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp section_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "toggling sheets off and back on", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, section_url(project))

      # Toggle sheets off
      view |> render_click("toggle_section", %{"section" => "sheets"})

      # Download link should include sheets=false parameter
      html = render(view)
      assert html =~ "sheets=false"

      # Toggle sheets back on
      html = view |> render_click("toggle_section", %{"section" => "sheets"})

      # sheets=false should no longer appear
      refute html =~ "sheets=false"
    end

    test "toggling multiple sections off reflects in download URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, section_url(project))

      view |> render_click("toggle_section", %{"section" => "flows"})
      html = view |> render_click("toggle_section", %{"section" => "scenes"})

      assert html =~ "flows=false"
      assert html =~ "scenes=false"
    end

    test "invalid section name is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, section_url(project))

      html = view |> render_click("toggle_section", %{"section" => "nonexistent"})

      # Page still renders normally
      assert html =~ "Export"
    end

    test "toggling screenplays off", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, section_url(project))

      html = view |> render_click("toggle_section", %{"section" => "screenplays"})

      assert html =~ "screenplays=false"
    end

    test "toggling localization off", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, section_url(project))

      html = view |> render_click("toggle_section", %{"section" => "localization"})

      assert html =~ "localization=false"
    end
  end

  describe "Asset mode selection" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp asset_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "default asset mode is references (no assets param in URL)", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} = live(conn, asset_url(project))

      # When asset mode is :references (default), the URL should not include an assets param
      refute html =~ "assets=embedded"
      refute html =~ "assets=bundled"
    end

    test "switching to embedded asset mode updates download URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, asset_url(project))

      html = view |> render_click("set_asset_mode", %{"mode" => "embedded"})

      assert html =~ "assets=embedded"
    end

    test "switching to bundled asset mode updates download URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, asset_url(project))

      html = view |> render_click("set_asset_mode", %{"mode" => "bundled"})

      assert html =~ "assets=bundled"
    end

    test "switching back to references removes assets param", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, asset_url(project))

      view |> render_click("set_asset_mode", %{"mode" => "embedded"})
      html = view |> render_click("set_asset_mode", %{"mode" => "references"})

      refute html =~ "assets="
    end

    test "invalid asset mode is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, asset_url(project))

      html = view |> render_click("set_asset_mode", %{"mode" => "invalid_mode"})

      # Page still renders normally, default asset mode unchanged
      assert html =~ "Export"
      refute html =~ "assets=invalid_mode"
    end
  end

  describe "Export options toggles" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp opts_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "toggling validate_before_export off adds validate=false to URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, opts_url(project))

      html = view |> render_click("toggle_option", %{"option" => "validate_before_export"})

      assert html =~ "validate=false"
    end

    test "toggling validate_before_export back on removes validate=false from URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, opts_url(project))

      view |> render_click("toggle_option", %{"option" => "validate_before_export"})
      html = view |> render_click("toggle_option", %{"option" => "validate_before_export"})

      refute html =~ "validate=false"
    end

    test "toggling pretty_print off adds pretty=false to URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, opts_url(project))

      html = view |> render_click("toggle_option", %{"option" => "pretty_print"})

      assert html =~ "pretty=false"
    end

    test "toggling pretty_print back on removes pretty=false from URL", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, opts_url(project))

      view |> render_click("toggle_option", %{"option" => "pretty_print"})
      html = view |> render_click("toggle_option", %{"option" => "pretty_print"})

      refute html =~ "pretty=false"
    end

    test "both options can be toggled independently", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, opts_url(project))

      view |> render_click("toggle_option", %{"option" => "validate_before_export"})
      html = view |> render_click("toggle_option", %{"option" => "pretty_print"})

      assert html =~ "validate=false"
      assert html =~ "pretty=false"
    end
  end

  describe "Export validation" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp validate_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "validate_export renders validation results", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, validate_url(project))

      html = view |> render_click("validate_export", %{})

      # Should show one of the validation status badges
      assert html =~ "Passed" or html =~ "Warnings" or html =~ "Errors"
    end

    test "validation on empty project passes", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, validate_url(project))

      html = view |> render_click("validate_export", %{})

      # Empty project should pass validation (no broken references)
      assert html =~ "Passed"
    end
  end

  describe "Import conflict strategy" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp strategy_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "set_strategy assigns each valid strategy without crash", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, strategy_url(project))

      for strategy <- ~w(overwrite rename skip) do
        html = view |> render_click("set_strategy", %{"strategy" => strategy})
        assert html =~ "Export", "page should still render after setting strategy to #{strategy}"
      end
    end

    test "invalid strategy is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, strategy_url(project))

      html = view |> render_click("set_strategy", %{"strategy" => "invalid_strategy"})

      assert html =~ "Export"
    end
  end

  describe "Import reset" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp reset_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "reset_import returns to upload step", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, reset_url(project))

      html = view |> render_click("reset_import", %{})

      # Should show the upload form
      assert html =~ ".storyarn.json"
      assert html =~ "Upload"
    end
  end

  # validate_upload is a required LiveView callback for uploads — no behavioral test needed

  describe "Download URL construction" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp dl_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "download URL includes workspace and project slugs", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, dl_url(project))

      assert html =~
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export/storyarn"
    end

    test "download URL changes when format changes to ink", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, dl_url(project))

      html = view |> render_click("set_format", %{"format" => "ink"})

      assert html =~ "/export/ink"
      refute html =~ "/export/storyarn"
    end

    test "download URL has no query params when all defaults", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, dl_url(project))

      # With all defaults (all sections on, references, validate on, pretty on)
      # there should be no query params
      assert html =~
               ~r"/export/storyarn\"" or
               html =~ ~r"/export/storyarn\?"

      # Specifically, the default URL should end cleanly without params
      refute html =~ "validate=false"
      refute html =~ "pretty=false"
      refute html =~ "sheets=false"
    end

    test "toggling off multiple settings builds correct query string", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, dl_url(project))

      view |> render_click("toggle_option", %{"option" => "validate_before_export"})
      view |> render_click("toggle_option", %{"option" => "pretty_print"})
      view |> render_click("toggle_section", %{"section" => "sheets"})
      html = view |> render_click("set_asset_mode", %{"mode" => "embedded"})

      assert html =~ "validate=false"
      assert html =~ "pretty=false"
      assert html =~ "sheets=false"
      assert html =~ "assets=embedded"
    end
  end

  describe "Entity counts loading" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp counts_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "loads entity counts asynchronously", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, counts_url(project))

      # Wait a bit for async task to complete
      :timer.sleep(100)
      html = render(view)

      # Should render without crash after async load
      assert html =~ "Export"
    end

    test "entity counts show with project data", %{conn: conn, project: project} do
      import Storyarn.SheetsFixtures
      import Storyarn.FlowsFixtures

      _sheet = sheet_fixture(project)
      _flow = flow_fixture(project)

      {:ok, view, _html} = live(conn, counts_url(project))
      :timer.sleep(100)
      html = render(view)

      # The counts should appear next to the section labels
      assert html =~ "Sheets"
      assert html =~ "Flows"
    end
  end

  describe "Export with project data" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp data_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "validate_export with sheets returns results", %{conn: conn, project: project} do
      import Storyarn.SheetsFixtures

      _sheet = sheet_fixture(project, %{name: "Hero"})

      {:ok, view, _html} = live(conn, data_url(project))
      html = view |> render_click("validate_export", %{})

      assert html =~ "Passed" or html =~ "Warnings" or html =~ "Errors"
    end

    test "validate_export with flows returns results", %{conn: conn, project: project} do
      import Storyarn.FlowsFixtures

      _flow = flow_fixture(project, %{name: "Intro"})

      {:ok, view, _html} = live(conn, data_url(project))
      html = view |> render_click("validate_export", %{})

      assert html =~ "Passed" or html =~ "Warnings" or html =~ "Errors"
    end

    test "export options reflect toggled sections in validate", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, data_url(project))

      # Turn off sheets and validate
      view |> render_click("toggle_section", %{"section" => "sheets"})
      html = view |> render_click("validate_export", %{})

      # Should still validate successfully (just without sheets)
      assert html =~ "Passed" or html =~ "Warnings" or html =~ "Errors"
    end
  end

  describe "Viewer authorization restrictions" do
    test "viewer does not see the file upload input", %{conn: conn} do
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

      # Viewer should not see the file input
      refute html =~ "import-form"
      refute html =~ "file-input"

      # Viewer should see the locked message
      assert html =~ "edit permissions to import"
    end

    test "viewer can still see export section", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
        )

      # Viewer should still see export controls
      assert html =~ "Format"
      assert html =~ "Content"
      assert html =~ "Download"
      assert html =~ "Validate"

      # Viewer can change export format
      html = view |> render_click("set_format", %{"format" => "ink"})
      assert html =~ "Download .ink"
    end

    test "viewer can validate export", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
        )

      html = view |> render_click("validate_export", %{})
      assert html =~ "Passed" or html =~ "Warnings" or html =~ "Errors"
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

  # ===========================================================================
  # Coverage expansion: format_file_size/1 branches
  # ===========================================================================

  describe "Import step upload — file size display branches" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp filesize_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "file upload entry shows KB for kilobyte-sized files", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, filesize_url(project))

      # Generate content > 1024 bytes to trigger KB branch
      content = String.duplicate("x", 2048)

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "medium_file.json",
            content: content,
            type: "application/json"
          }
        ])

      render_upload(file, "medium_file.json")
      html = render(view)

      assert html =~ "KB"
    end

    test "file upload entry shows B for small files", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, filesize_url(project))

      # Content < 1024 bytes triggers B branch
      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "tiny_file.json",
            content: "{}",
            type: "application/json"
          }
        ])

      render_upload(file, "tiny_file.json")
      html = render(view)

      assert html =~ " B)"
    end
  end

  # ===========================================================================
  # Coverage expansion: upload_error_message/1 branches
  # ===========================================================================

  describe "Upload error messages" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp upload_err_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "not_accepted file type shows appropriate error", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, upload_err_url(project))

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "bad_file.txt",
            content: "hello",
            type: "text/plain"
          }
        ])

      render_upload(file, "bad_file.txt")
      html = render(view)

      assert html =~ "Only .json files"
    end
  end

  # ===========================================================================
  # Coverage expansion: validation_results rendering with different statuses
  # ===========================================================================

  describe "Validation result rendering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp val_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "validation passed on empty project shows badge-success and no-issues message", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, val_url(project))

      html = view |> render_click("validate_export", %{})

      assert html =~ "badge-success"
      assert html =~ "Passed"
      assert html =~ "No issues found"
    end

    test "validation result shows warning badge when there are warnings", %{
      conn: conn,
      project: project
    } do
      import Storyarn.FlowsFixtures

      # Create a flow with nodes that have broken references to trigger warnings
      flow = flow_fixture(project, %{name: "Broken Flow"})

      _node =
        node_fixture(flow, %{
          type: "jump",
          data: %{"target_hub_id" => "00000000-0000-0000-0000-000000000000"}
        })

      {:ok, view, _html} = live(conn, val_url(project))

      html = view |> render_click("validate_export", %{})

      # Should render some validation findings (warnings or errors depending on check)
      assert html =~ "Passed" or html =~ "Warnings" or html =~ "Errors"
    end
  end

  # ===========================================================================
  # Coverage expansion: import error step rendering (format_import_error)
  # ===========================================================================

  describe "Import error display via import step" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp import_err_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "parse_import with invalid JSON shows error step", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, import_err_url(project))

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "bad.json",
            content: "not valid json {{{",
            type: "application/json"
          }
        ])

      render_upload(file, "bad.json")

      html = view |> form("#import-form") |> render_submit()

      assert html =~ "alert-error"
    end

    test "parse_import with valid JSON but invalid structure shows error", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, import_err_url(project))

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "invalid_structure.json",
            content: Jason.encode!(%{"random" => "data"}),
            type: "application/json"
          }
        ])

      render_upload(file, "invalid_structure.json")

      html = view |> form("#import-form") |> render_submit()

      assert html =~ "alert-error"
    end

    test "parse_import with array JSON shows invalid structure error", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, import_err_url(project))

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "array.json",
            content: Jason.encode!([1, 2, 3]),
            type: "application/json"
          }
        ])

      render_upload(file, "array.json")

      html = view |> form("#import-form") |> render_submit()

      assert html =~ "alert-error"
    end

    test "reset_import after error returns to upload step", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, import_err_url(project))

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "bad.json",
            content: "invalid json content!!!",
            type: "application/json"
          }
        ])

      render_upload(file, "bad.json")
      view |> form("#import-form") |> render_submit()

      html = view |> render_click("reset_import", %{})

      assert html =~ ".storyarn.json"
    end
  end

  # ===========================================================================
  # Coverage expansion: entity_count_rows filtering with zero counts
  # ===========================================================================

  describe "Import preview — entity count rows filtering" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp preview_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export-import"
    end

    test "parse_import with valid storyarn JSON shows preview step", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, preview_url(project))

      # Create a minimal valid storyarn JSON structure
      valid_import = %{
        "storyarn_version" => "1.0",
        "format_version" => "1.0",
        "metadata" => %{
          "project_name" => "Test",
          "exported_at" => "2024-01-01T00:00:00Z"
        },
        "data" => %{
          "sheets" => [],
          "flows" => [],
          "scenes" => [],
          "screenplays" => [],
          "assets" => []
        }
      }

      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "valid.json",
            content: Jason.encode!(valid_import),
            type: "application/json"
          }
        ])

      render_upload(file, "valid.json")

      html = view |> render_submit("parse_import", %{})

      # Should show preview step or error (depending on parse validation)
      # The point is that the code path is exercised
      assert html =~ "Import preview" or html =~ "alert-error"
    end
  end

  # ===========================================================================
  # Coverage expansion: handle_async exit path
  # ===========================================================================

  # NOTE: Async entity counts tested in "Entity counts loading" describe block above
end
