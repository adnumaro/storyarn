defmodule StoryarnWeb.LocalizationExportControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.LocalizationFixtures

  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)

    # Add a target language (Spanish) so export has something to work with
    language = language_fixture(project, %{locale_code: "es", name: "Spanish"})

    %{project: project, language: language}
  end

  defp export_url(project, format, locale) do
    ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/localization/export/#{format}/#{locale}"
  end

  defp export_url(project, format, locale, params) do
    base = export_url(project, format, locale)
    query = URI.encode_query(params)
    "#{base}?#{query}"
  end

  # =========================================================================
  # CSV Export
  # =========================================================================

  describe "GET export CSV" do
    test "returns 200 with CSV content for valid project and locale", %{
      conn: conn,
      project: project
    } do
      # Create a localized text so the CSV has data
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Hello world"
      })

      conn = get(conn, export_url(project, "csv", "es"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/csv; charset=utf-8"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ ".csv"

      body = conn.resp_body
      assert body =~ "ID,Source Type,Source ID,Source Field,Locale"
      assert body =~ "Hello world"
      assert body =~ "flow_node"
    end

    test "returns CSV with headers only when no texts exist for locale", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "csv", "es"))

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "ID,Source Type,Source ID"
      # Only the header row, no data rows
      lines = String.split(body, "\n", trim: true)
      assert length(lines) == 1
    end

    test "filename is sanitized from project slug and locale", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "csv", "es"))

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "#{project.slug}_translations_es.csv"
    end
  end

  # =========================================================================
  # XLSX Export
  # =========================================================================

  describe "GET export XLSX" do
    test "returns 200 with XLSX binary for valid project and locale", %{
      conn: conn,
      project: project
    } do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Greetings"
      })

      conn = get(conn, export_url(project, "xlsx", "es"))

      assert conn.status == 200

      assert get_resp_header(conn, "content-type") == [
               "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet; charset=utf-8"
             ]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ ".xlsx"

      # XLSX files start with PK (zip format)
      assert <<0x50, 0x4B, _rest::binary>> = conn.resp_body
    end

    test "returns XLSX even when no texts exist (empty export)", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "xlsx", "es"))

      assert conn.status == 200
      assert <<0x50, 0x4B, _rest::binary>> = conn.resp_body
    end

    test "filename is sanitized from project slug and locale", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "xlsx", "es"))

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "#{project.slug}_translations_es.xlsx"
    end
  end

  # =========================================================================
  # Unsupported Format
  # =========================================================================

  describe "GET export unsupported format" do
    test "returns 400 bad request for unknown format", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "pdf", "es"))

      assert conn.status == 400
      assert json_response(conn, 400)["error"] =~ "Unsupported format"
    end

    test "returns 400 for json format", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "json", "es"))

      assert conn.status == 400
      assert json_response(conn, 400)["error"] =~ "Unsupported format"
    end
  end

  # =========================================================================
  # Project Not Found
  # =========================================================================

  describe "GET export with invalid project" do
    test "returns 404 when project does not exist", %{conn: conn, project: project} do
      url =
        ~p"/workspaces/#{project.workspace.slug}/projects/nonexistent-project/localization/export/csv/es"

      conn = get(conn, url)

      assert conn.status == 404
      assert json_response(conn, 404)["error"] =~ "Project not found"
    end

    test "returns 404 when workspace does not exist", %{conn: conn, project: project} do
      url =
        ~p"/workspaces/nonexistent-workspace/projects/#{project.slug}/localization/export/csv/es"

      conn = get(conn, url)

      assert conn.status == 404
      assert json_response(conn, 404)["error"] =~ "Project not found"
    end

    test "returns 404 for non-member user", %{conn: conn} do
      other_user = user_fixture()
      other_project = project_fixture(other_user) |> Repo.preload(:workspace)

      conn = get(conn, export_url(other_project, "csv", "es"))

      assert conn.status == 404
      assert json_response(conn, 404)["error"] =~ "Project not found"
    end
  end

  # =========================================================================
  # Optional Filters
  # =========================================================================

  describe "GET export with filters" do
    test "applies status filter param", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Pending text",
        status: "pending"
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Final text",
        status: "final"
      })

      conn = get(conn, export_url(project, "csv", "es", %{"status" => "final"}))

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "Final text"
      refute body =~ "Pending text"
    end

    test "applies source_type filter param", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Flow text"
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "block",
        source_text: "Block text"
      })

      conn = get(conn, export_url(project, "csv", "es", %{"source_type" => "block"}))

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "Block text"
      refute body =~ "Flow text"
    end

    test "empty string filters are ignored", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Some text"
      })

      conn =
        get(conn, export_url(project, "csv", "es", %{"status" => "", "source_type" => ""}))

      assert conn.status == 200
      body = conn.resp_body
      # Text should still appear since empty filters are ignored
      assert body =~ "Some text"
    end

    test "nil filters (missing params) are ignored", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Unfiltered text"
      })

      # No status or source_type params at all
      conn = get(conn, export_url(project, "csv", "es"))

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "Unfiltered text"
    end

    test "filters also work with xlsx format", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Flow text",
        status: "pending"
      })

      conn = get(conn, export_url(project, "xlsx", "es", %{"status" => "pending"}))

      assert conn.status == 200
      assert <<0x50, 0x4B, _rest::binary>> = conn.resp_body
    end
  end

  # =========================================================================
  # Multiple texts and CSV correctness
  # =========================================================================

  describe "CSV content correctness" do
    test "includes multiple texts in CSV output", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "First line"
      })

      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "Second line"
      })

      conn = get(conn, export_url(project, "csv", "es"))

      assert conn.status == 200
      body = conn.resp_body
      lines = String.split(body, "\n", trim: true)
      # Header + 2 data rows
      assert length(lines) == 3
      assert body =~ "First line"
      assert body =~ "Second line"
    end

    test "strips HTML from source text in CSV", %{conn: conn, project: project} do
      localized_text_fixture(project.id, %{
        locale_code: "es",
        source_type: "flow_node",
        source_text: "<p>Hello <strong>world</strong></p>"
      })

      conn = get(conn, export_url(project, "csv", "es"))

      assert conn.status == 200
      body = conn.resp_body
      assert body =~ "Hello world"
      refute body =~ "<p>"
      refute body =~ "<strong>"
    end
  end

  # =========================================================================
  # Authentication
  # =========================================================================

  describe "GET export without authentication" do
    test "redirects unauthenticated users", %{project: project} do
      conn = build_conn()
      conn = get(conn, export_url(project, "csv", "es"))

      assert redirected_to(conn) =~ "/users/log-in"
    end
  end
end
