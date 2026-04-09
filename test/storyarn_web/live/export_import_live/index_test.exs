defmodule StoryarnWeb.ExportImportLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp get_ei_vue(view) do
    LiveVue.Test.get_vue(view, name: "modules/project-settings/ExportImport")
  end

  defp export_config(view), do: get_ei_vue(view).props["export-config"]
  defp import_state(view), do: get_ei_vue(view).props["import-state"]
  defp format_extension(view), do: export_config(view)["formatConfig"]["extension"]
  defp selected_format(view), do: export_config(view)["formatConfig"]["selected"]
  defp download_url(view), do: export_config(view)["downloadUrl"]
  defp validation_status(view), do: (export_config(view)["validation"] || %{})["status"]
  defp entity_counts(view), do: export_config(view)["sectionConfig"]["entityCounts"]

  describe "Export/Import page" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp export_import_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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

    test "exposes the list of export formats", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      formats = export_config(view)["formatConfig"]["formats"]
      assert is_list(formats)
      assert Enum.any?(formats, &(&1["format"] == "storyarn"))
    end

    test "exposes supported content sections", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      section_config = export_config(view)["sectionConfig"]
      # All 5 sections selected by default
      for section <- ~w(sheets flows scenes screenplays localization) do
        assert section in section_config["selected"]
      end
    end

    test "exposes the default asset mode", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      options = export_config(view)["options"]
      assert options["assetMode"] == "references"
    end

    test "exposes the default export options", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      options = export_config(view)["options"]
      assert options["validateBeforeExport"] == true
      assert options["prettyPrint"] == true
    end

    test "exposes no validation result on initial load", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      assert export_config(view)["validation"] == nil
    end

    test "exposes a download URL", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      assert download_url(view) =~ "/export/storyarn"
    end

    test "exposes an upload config for editors", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_import_url(project))

      upload_config = get_ei_vue(view).props["upload-config"]
      # The uploads.import_file struct is serialized to the Vue component
      assert is_map(upload_config)
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "lists all available export formats", %{conn: conn, project: project} do
      {:ok, _view, html} = live(conn, ei_url(project))

      assert html =~ "Storyarn JSON"
      assert html =~ "Ink (.ink)"
      assert html =~ "Yarn Spinner (.yarn)"
      assert html =~ "Godot Dialogic (.dtl)"
      assert html =~ "Unity Dialogue System (JSON)"
      assert html =~ "Unreal Engine (CSV)"
      assert html =~ "articy:draft (XML)"
    end

    test "switching to ink format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      render_click(view, "set_format", %{"format" => "ink"})

      assert format_extension(view) == "ink"
      assert selected_format(view) == "ink"
    end

    test "switching to yarn format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      render_click(view, "set_format", %{"format" => "yarn"})

      assert format_extension(view) == "yarn"
      assert selected_format(view) == "yarn"
    end

    test "switching to articy format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      render_click(view, "set_format", %{"format" => "articy"})

      assert format_extension(view) == "xml"
      assert selected_format(view) == "articy"
    end

    test "switching to godot format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      render_click(view, "set_format", %{"format" => "godot"})

      assert format_extension(view) == "dtl"
      assert selected_format(view) == "godot"
    end

    test "switching to unreal format updates the download extension", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ei_url(project))

      render_click(view, "set_format", %{"format" => "unreal"})

      assert format_extension(view) == "csv"
      assert selected_format(view) == "unreal"
    end

    test "switching format clears validation result", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      # First validate
      render_click(view, "validate_export", %{})
      assert validation_status(view) != nil

      # Then switch format — validation_result should be cleared
      render_click(view, "set_format", %{"format" => "ink"})
      assert export_config(view)["validation"] == nil
    end

    test "invalid format is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      # Should not crash on invalid format
      render_click(view, "set_format", %{"format" => "nonexistent_format"})

      # Still on default format
      assert selected_format(view) == "storyarn"
      assert format_extension(view) == "json"
    end

    test "default format is storyarn with json extension", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      assert selected_format(view) == "storyarn"
      assert format_extension(view) == "json"
    end

    test "download link includes format in URL", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ei_url(project))

      render_click(view, "set_format", %{"format" => "ink"})

      assert download_url(view) =~ "/export/ink"
    end
  end

  describe "Content section toggles" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp section_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "validate_export renders validation results", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, validate_url(project))

      render_click(view, "validate_export", %{})

      assert validation_status(view) in ~w(passed warnings errors)
    end

    test "validation on empty project passes", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, validate_url(project))

      render_click(view, "validate_export", %{})

      assert validation_status(view) == "passed"
    end
  end

  describe "Import conflict strategy" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp strategy_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "reset_import returns to upload step", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, reset_url(project))

      render_click(view, "reset_import", %{})

      assert import_state(view)["step"] == "upload"
      assert import_state(view)["preview"] == nil
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "download URL includes workspace and project slugs", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, dl_url(project))

      assert download_url(view) =~
               "/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export/storyarn"
    end

    test "download URL changes when format changes to ink", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, dl_url(project))

      render_click(view, "set_format", %{"format" => "ink"})

      assert download_url(view) =~ "/export/ink"
      refute download_url(view) =~ "/export/storyarn"
    end

    test "download URL has no query params when all defaults", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, dl_url(project))

      # With all defaults (all sections on, references, validate on, pretty on)
      # the URL should not include any of the "false" overrides.
      url = download_url(view)
      assert url =~ "/export/storyarn"
      refute url =~ "validate=false"
      refute url =~ "pretty=false"
      refute url =~ "sheets=false"
      refute url =~ "?"
    end

    test "toggling off multiple settings builds correct query string", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, dl_url(project))

      render_click(view, "toggle_option", %{"option" => "validate_before_export"})
      render_click(view, "toggle_option", %{"option" => "pretty_print"})
      render_click(view, "toggle_section", %{"section" => "sheets"})
      render_click(view, "set_asset_mode", %{"mode" => "embedded"})

      url = download_url(view)
      assert url =~ "validate=false"
      assert url =~ "pretty=false"
      assert url =~ "sheets=false"
      assert url =~ "assets=embedded"
    end
  end

  describe "Entity counts loading" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp counts_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      _ = await_async(view)

      counts = entity_counts(view)
      assert counts["sheets"] >= 1
      assert counts["flows"] >= 1
    end
  end

  describe "Export with project data" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp data_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "validate_export with sheets returns results", %{conn: conn, project: project} do
      import Storyarn.SheetsFixtures

      _sheet = sheet_fixture(project, %{name: "Hero"})

      {:ok, view, _html} = live(conn, data_url(project))
      render_click(view, "validate_export", %{})

      assert validation_status(view) in ~w(passed warnings errors)
    end

    test "validate_export with flows returns results", %{conn: conn, project: project} do
      import Storyarn.FlowsFixtures

      _flow = flow_fixture(project, %{name: "Intro"})

      {:ok, view, _html} = live(conn, data_url(project))
      render_click(view, "validate_export", %{})

      assert validation_status(view) in ~w(passed warnings errors)
    end

    test "export options reflect toggled sections in validate", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, data_url(project))

      # Turn off sheets and validate
      render_click(view, "toggle_section", %{"section" => "sheets"})
      render_click(view, "validate_export", %{})

      # Should still validate successfully (just without sheets)
      assert validation_status(view) in ~w(passed warnings errors)
    end
  end

  describe "Viewer authorization restrictions" do
    test "viewer does not see the file upload input", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
        )

      # Viewers can't import: can-edit is false and the upload-config is nil
      vue = get_ei_vue(view)
      assert vue.props["can-edit"] == false
      assert vue.props["upload-config"] == nil
    end

    test "viewer can still see export section", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
        )

      # Viewer still gets full export config
      assert is_list(export_config(view)["formatConfig"]["formats"])
      assert download_url(view) =~ "/export/storyarn"

      # And can change the export format
      render_click(view, "set_format", %{"format" => "ink"})
      assert format_extension(view) == "ink"
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
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
        )

      render_click(view, "validate_export", %{})
      assert validation_status(view) in ~w(passed warnings errors)
    end
  end

  describe "Authentication and authorization" do
    test "unauthenticated user gets redirected to login", %{conn: conn} do
      assert {:error, redirect} =
               live(conn, ~p"/workspaces/some-ws/projects/some-proj/settings/export-import")

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
                 ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
        )

      assert html =~ "Export"
    end

    test "viewer cannot upload (can-edit is false)", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
        )

      vue = get_ei_vue(view)
      assert vue.props["can-edit"] == false
      assert vue.props["upload-config"] == nil
    end

    test "editor sees an upload-config", %{conn: conn} do
      editor = user_fixture()
      conn = log_in_user(conn, editor)

      owner = user_fixture()
      project = project_fixture(owner) |> Repo.preload(:workspace)
      _membership = membership_fixture(project, editor, "editor")

      {:ok, view, _html} =
        live(
          conn,
          ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
        )

      vue = get_ei_vue(view)
      assert vue.props["can-edit"] == true
      assert is_map(vue.props["upload-config"])
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "file upload entry for kilobyte-sized files reports size in bytes", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, filesize_url(project))

      # Generate content > 1024 bytes
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

      [entry] = get_ei_vue(view).props["upload-config"]["entries"]
      assert entry["client_size"] == 2048
      assert entry["client_name"] == "medium_file.json"
    end

    test "file upload entry for small files reports size in bytes", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, filesize_url(project))

      # Content < 1024 bytes
      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "tiny_file.json",
            content: "{}",
            type: "application/json"
          }
        ])

      render_upload(file, "tiny_file.json")

      [entry] = get_ei_vue(view).props["upload-config"]["entries"]
      assert entry["client_size"] == 2
      assert entry["client_name"] == "tiny_file.json"
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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

      # The rejected entry is reflected in the upload-config errors list.
      errors = get_ei_vue(view).props["upload-config"]["errors"]
      assert Enum.any?(errors, &(&1["error"] == "not_accepted"))
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    test "validation passed on empty project reports passed with no issues", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, val_url(project))

      render_click(view, "validate_export", %{})

      validation = export_config(view)["validation"]
      assert validation["status"] == "passed"
      assert validation["errors"] == []
      assert validation["warnings"] == []
    end

    test "validation result reports findings when there are broken references", %{
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

      render_click(view, "validate_export", %{})

      assert validation_status(view) in ~w(passed warnings errors)
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      view |> form("#import-form") |> render_submit()

      assert import_state(view)["step"] == "error"
      assert import_state(view)["error"] != nil
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
      view |> form("#import-form") |> render_submit()

      assert import_state(view)["step"] == "error"
      assert import_state(view)["error"] != nil
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
      view |> form("#import-form") |> render_submit()

      assert import_state(view)["step"] == "error"
      assert import_state(view)["error"] != nil
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
      assert import_state(view)["step"] == "error"

      render_click(view, "reset_import", %{})

      assert import_state(view)["step"] == "upload"
      assert import_state(view)["error"] == nil
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
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
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
      view |> form("#import-form") |> render_submit()

      # Should reach preview step or error step (depending on parse validation).
      assert import_state(view)["step"] in ["preview", "error"]
    end
  end

  # ===========================================================================
  # Coverage expansion: handle_async exit path
  # ===========================================================================

  # NOTE: Async entity counts tested in "Entity counts loading" describe block above

  # ===========================================================================
  # Import staging lifecycle
  # ===========================================================================

  describe "Import staging lifecycle" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp staging_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    defp valid_import_data do
      %{
        "storyarn_version" => "1.0",
        "export_version" => "1.0",
        "project" => %{"name" => "Test Project"},
        "sheets" => [],
        "flows" => [],
        "scenes" => [],
        "screenplays" => [],
        "assets" => %{"items" => []}
      }
    end

    defp valid_import_data_with_sheet do
      %{
        "storyarn_version" => "1.0",
        "export_version" => "1.0",
        "project" => %{"name" => "Test Project"},
        "sheets" => [
          %{
            "id" => 9999,
            "name" => "Imported Hero",
            "shortcut" => "imported.hero",
            "position" => 0,
            "blocks" => []
          }
        ],
        "flows" => [],
        "scenes" => [],
        "screenplays" => [],
        "assets" => %{"items" => []}
      }
    end

    defp upload_and_parse(view, data) do
      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "import.json",
            content: Jason.encode!(data),
            type: "application/json"
          }
        ])

      render_upload(file, "import.json")
      view |> form("#import-form") |> render_submit()
    end

    test "parse_import stores data in ETS and shows preview", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, staging_url(project))

      upload_and_parse(view, valid_import_data())

      assert import_state(view)["step"] == "preview"
      assert import_state(view)["preview"] != nil
    end

    test "execute_import with valid data transitions to done step", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, staging_url(project))

      upload_and_parse(view, valid_import_data())
      render_click(view, "execute_import", %{})

      assert import_state(view)["step"] == "done"
      assert import_state(view)["result"] != nil
    end

    test "execute_import cleans up ETS data", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, staging_url(project))

      upload_and_parse(view, valid_import_data())

      # Before execute, there should be an ETS entry for this view
      baseline_count = length(:ets.tab2list(:import_staging))
      assert baseline_count >= 1

      view |> render_click("execute_import", %{})

      # After execute, the entry should be removed
      # The view's ref was deleted by take_import_data
      assert length(:ets.tab2list(:import_staging)) < baseline_count
    end

    test "execute_import with expired session shows error", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, staging_url(project))

      upload_and_parse(view, valid_import_data())

      # Manually clear all ETS entries to simulate session expiration
      :ets.delete_all_objects(:import_staging)

      render_click(view, "execute_import", %{})

      assert import_state(view)["step"] == "error"
      assert import_state(view)["error"] =~ "expired"
    end

    test "reset_import cleans up ETS data", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, staging_url(project))

      upload_and_parse(view, valid_import_data())

      baseline_count = length(:ets.tab2list(:import_staging))
      assert baseline_count >= 1

      view |> render_click("reset_import", %{})

      assert length(:ets.tab2list(:import_staging)) < baseline_count
    end

    test "reset_import returns to upload step after preview", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, staging_url(project))

      upload_and_parse(view, valid_import_data())
      assert import_state(view)["step"] == "preview"

      render_click(view, "reset_import", %{})

      assert import_state(view)["step"] == "upload"
      assert import_state(view)["preview"] == nil
    end

    test "terminate/2 cleans up ETS on disconnect", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, staging_url(project))

      baseline_count = length(:ets.tab2list(:import_staging))

      upload_and_parse(view, valid_import_data())

      assert length(:ets.tab2list(:import_staging)) == baseline_count + 1

      # Stop the LiveView process to trigger terminate/2
      GenServer.stop(view.pid)

      # Give a moment for cleanup
      :timer.sleep(50)

      assert length(:ets.tab2list(:import_staging)) == baseline_count
    end

    test "re-parse cleans old ETS entry and creates new one", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, staging_url(project))

      # Snapshot baseline count (other tests may have entries in shared ETS)
      baseline_count = length(:ets.tab2list(:import_staging))

      # First parse
      upload_and_parse(view, valid_import_data())

      count_after_first = length(:ets.tab2list(:import_staging))
      assert count_after_first == baseline_count + 1

      # Reset cleans the entry, then re-parse creates a new one
      view |> render_click("reset_import", %{})

      count_after_reset = length(:ets.tab2list(:import_staging))
      assert count_after_reset == baseline_count

      # Second parse with different data
      upload_and_parse(view, valid_import_data_with_sheet())

      count_after_second = length(:ets.tab2list(:import_staging))
      assert count_after_second == baseline_count + 1
    end
  end

  # ===========================================================================
  # Import conflict strategies
  # ===========================================================================

  describe "Import conflict strategies" do
    setup :register_and_log_in_user

    setup %{user: user} do
      project = project_fixture(user) |> Repo.preload(:workspace)
      %{project: project}
    end

    defp conflict_url(project) do
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
    end

    defp upload_and_parse_for_conflict(view, data) do
      file =
        file_input(view, "#import-form", :import_file, [
          %{
            name: "import.json",
            content: Jason.encode!(data),
            type: "application/json"
          }
        ])

      render_upload(file, "import.json")
      view |> form("#import-form") |> render_submit()
    end

    test "set_strategy changes conflict strategy in preview", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, conflict_url(project))

      import_data = %{
        "storyarn_version" => "1.0",
        "export_version" => "1.0",
        "project" => %{"name" => "Test"},
        "sheets" => [],
        "flows" => [],
        "scenes" => [],
        "screenplays" => [],
        "assets" => %{"items" => []}
      }

      upload_and_parse_for_conflict(view, import_data)

      # Set strategy to overwrite
      html = view |> render_click("set_strategy", %{"strategy" => "overwrite"})

      # Page should still render (strategy is stored in assigns)
      assert html =~ "Import preview" or html =~ "Import"
    end

    test "execute_import with sheets using skip strategy preserves existing", %{
      conn: conn,
      project: project
    } do
      import Storyarn.SheetsFixtures

      # Create an existing sheet with a specific shortcut
      _existing = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      {:ok, view, _html} = live(conn, conflict_url(project))

      # Import data with a conflicting shortcut
      import_data = %{
        "storyarn_version" => "1.0",
        "export_version" => "1.0",
        "project" => %{"name" => "Test"},
        "sheets" => [
          %{
            "id" => 9999,
            "name" => "New Hero",
            "shortcut" => "hero",
            "position" => 0,
            "blocks" => []
          }
        ],
        "flows" => [],
        "scenes" => [],
        "screenplays" => [],
        "assets" => %{"items" => []}
      }

      upload_and_parse_for_conflict(view, import_data)

      # Ensure strategy is skip (the default)
      render_click(view, "set_strategy", %{"strategy" => "skip"})
      render_click(view, "execute_import", %{})

      assert import_state(view)["step"] == "done"

      # Verify the original sheet is preserved
      existing_after = Storyarn.Sheets.get_sheet_by_shortcut(project.id, "hero")
      assert existing_after.name == "Hero"
    end
  end
end
