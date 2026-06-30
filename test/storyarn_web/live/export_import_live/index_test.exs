defmodule StoryarnWeb.ExportImportLive.IndexTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Repo

  defp get_settings_layout(view) do
    LiveVue.Test.get_vue(view, name: "live/layouts/settings/Layout")
  end

  defp get_export_vue(view) do
    LiveVue.Test.get_vue(view, name: "live/project/settings/export-import/ProjectSettingsExportImport")
  end

  defp export_config(view), do: get_export_vue(view).props["export-config"]
  defp format_config(view), do: export_config(view)["formatConfig"]
  defp selected_format(view), do: format_config(view)["selected"]
  defp format_extension(view), do: format_config(view)["extension"]
  defp visible_formats(view), do: format_config(view)["formats"]
  defp download_url(view), do: export_config(view)["downloadUrl"]
  defp validation_status(view), do: (export_config(view)["validation"] || %{})["status"]
  defp entity_counts(view), do: export_config(view)["sectionConfig"]["entityCounts"]

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp export_url(project) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/settings/export-import"
  end

  describe "export page" do
    test "renders as Export, not Import & Export", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, export_url(project))

      settings_layout = get_settings_layout(view)
      assert settings_layout.props["title"] == "Export"
      assert settings_layout.props["subtitle"] == "Export your project data."
      refute html =~ "Import & Export"
      refute html =~ "Export & Import"
    end

    test "does not expose the importer through props or hidden form", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, export_url(project))

      props = get_export_vue(view).props
      refute Map.has_key?(props, "import-state")
      refute Map.has_key?(props, "upload-config")
      refute Map.has_key?(props, "can-edit")
      refute html =~ "id=\"import-form\""
      refute html =~ "phx-submit=\"parse_import\""
    end

    test "does not expose Storyarn JSON as a visible export format", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, export_url(project))

      formats = visible_formats(view)
      assert is_list(formats)
      refute Enum.any?(formats, &(&1["format"] == "storyarn"))
      refute html =~ "Storyarn JSON"
    end

    test "defaults to the first visible engine format", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      assert selected_format(view) == "ink"
      assert format_extension(view) == "zip"
      assert download_url(view) =~ "/export/ink"
      refute download_url(view) =~ "/export/storyarn"
    end

    test "exposes supported content sections", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      section_config = export_config(view)["sectionConfig"]

      for section <- ~w(sheets flows scenes screenplays localization) do
        assert section in section_config["selected"]
      end
    end

    test "exposes the default export options", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      options = export_config(view)["options"]
      assert options["assetMode"] == "references"
      assert options["validateBeforeExport"] == true
      assert options["prettyPrint"] == true
      assert export_config(view)["validation"] == nil
    end
  end

  describe "format selection" do
    test "lists only public engine formats", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      labels = Enum.map(visible_formats(view), & &1["label"])

      assert "Ink (.ink)" in labels
      assert "Yarn Spinner (.yarn)" in labels
      assert "Unity Dialogue System (JSON)" in labels
      assert "Godot Dialogic (.dtl)" in labels
      assert "Unreal Engine (CSV)" in labels
      assert "articy:draft (XML)" in labels
      refute "Storyarn JSON" in labels
    end

    test "switching format updates the displayed download extension", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_format", %{"format" => "yarn"})

      assert selected_format(view) == "yarn"
      assert format_extension(view) == "zip"
      assert download_url(view) =~ "/export/yarn"

      render_click(view, "set_format", %{"format" => "unity"})

      assert selected_format(view) == "unity"
      assert format_extension(view) == "json"
      assert download_url(view) =~ "/export/unity"
    end

    test "invalid format is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_format", %{"format" => "nonexistent_format"})

      assert selected_format(view) == "ink"
      assert format_extension(view) == "zip"
    end

    test "hidden storyarn format is ignored by the page", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_format", %{"format" => "storyarn"})

      assert selected_format(view) == "ink"
      assert format_extension(view) == "zip"
      refute download_url(view) =~ "/export/storyarn"
    end
  end

  describe "export options" do
    test "toggling content sections updates selected sections", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "toggle_section", %{"section" => "sheets"})

      refute "sheets" in export_config(view)["sectionConfig"]["selected"]
      assert download_url(view) =~ "sheets=false"
    end

    test "toggling options builds the expected query string", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "toggle_option", %{"option" => "validate_before_export"})
      render_click(view, "toggle_option", %{"option" => "pretty_print"})
      render_click(view, "set_asset_mode", %{"mode" => "embedded"})

      url = download_url(view)
      assert url =~ "validate=false"
      assert url =~ "pretty=false"
      assert url =~ "assets=embedded"
    end

    test "invalid asset mode is ignored", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "set_asset_mode", %{"mode" => "invalid"})

      assert export_config(view)["options"]["assetMode"] == "references"
    end

    test "switching format clears validation result", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})
      assert validation_status(view)

      render_click(view, "set_format", %{"format" => "yarn"})
      assert export_config(view)["validation"] == nil
    end
  end

  describe "validation and counts" do
    test "validate_export produces a validation result", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, export_url(project))

      render_click(view, "validate_export", %{})

      assert validation_status(view) in ~w(passed warnings errors)
    end

    test "loads entity counts asynchronously", %{conn: conn, project: project} do
      import Storyarn.FlowsFixtures
      import Storyarn.SheetsFixtures

      _sheet = sheet_fixture(project)
      _flow = flow_fixture(project)

      {:ok, view, _html} = live(conn, export_url(project))
      _ = await_async(view)

      counts = entity_counts(view)
      assert counts["sheets"] >= 1
      assert counts["flows"] >= 1
    end
  end

  describe "authorization" do
    test "unauthenticated user gets redirected to login" do
      conn =
        build_conn()
        |> put_req_header("accept-language", "en")
        |> init_test_session(%{})

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
      project = other_user |> project_fixture() |> Repo.preload(:workspace)

      assert {:error, {:redirect, %{to: "/workspaces", flash: %{"error" => error_msg}}}} =
               live(conn, export_url(project))

      assert error_msg =~ "access"
    end

    test "viewer can access export without importer props", %{conn: conn} do
      viewer = user_fixture()
      conn = log_in_user(conn, viewer)

      owner = user_fixture()
      project = owner |> project_fixture() |> Repo.preload(:workspace)
      _membership = membership_fixture(project, viewer, "viewer")

      {:ok, view, html} = live(conn, export_url(project))

      assert html =~ "Export"
      refute Map.has_key?(get_export_vue(view).props, "upload-config")
      assert download_url(view) =~ "/export/ink"
    end
  end
end
