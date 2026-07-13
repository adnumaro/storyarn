defmodule StoryarnWeb.ExportControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Localization
  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    %{project: project}
  end

  defp export_url(project, format, params \\ %{}) do
    base =
      ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/export/#{format}"

    if params == %{} do
      base
    else
      "#{base}?#{URI.encode_query(params)}"
    end
  end

  defp exportable_flow_fixture(project, attrs) do
    flow = flow_fixture(project, attrs)
    entry = Enum.find(Storyarn.Flows.list_nodes(flow.id), &(&1.type == "entry"))
    exit_node = node_fixture(flow, %{type: "exit", data: %{}})
    connection_fixture(flow, entry, exit_node)

    flow
  end

  defp unzip_response(conn) do
    assert {:ok, files} = :zip.unzip(conn.resp_body, [:memory])

    Map.new(files, fn {filename, content} ->
      {List.to_string(filename), content}
    end)
  end

  # ===========================================================================
  # Storyarn JSON format
  # ===========================================================================

  describe "GET storyarn format" do
    test "exports JSON with correct content-type", %{conn: conn, project: project} do
      conn = get(conn, export_url(project, "storyarn"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end

    test "sets content-disposition for download", %{conn: conn, project: project} do
      conn = get(conn, export_url(project, "storyarn"))

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert disposition =~ ".json"
    end

    test "produces valid JSON output", %{conn: conn, project: project} do
      conn = get(conn, export_url(project, "storyarn"))

      assert {:ok, data} = Jason.decode(conn.resp_body)
      assert data["storyarn_version"] == "1.0.0"
      assert data["project"]["name"] == project.name
    end

    test "includes sheets and flows in output", %{conn: conn, project: project} do
      sheet = sheet_fixture(project, %{name: "Test Sheet"})
      block_fixture(sheet, %{type: "text", config: %{"label" => "Name"}})
      flow_fixture(project, %{name: "Test Flow"})

      conn = get(conn, export_url(project, "storyarn"))

      assert {:ok, data} = Jason.decode(conn.resp_body)
      assert length(data["sheets"]) == 1
      assert length(data["flows"]) == 1
    end
  end

  # ===========================================================================
  # Ink format
  # ===========================================================================

  describe "GET ink format" do
    test "exports ink as zip with all generated files", %{conn: conn, project: project} do
      exportable_flow_fixture(project, %{name: "Main"})

      conn = get(conn, export_url(project, "ink"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "-ink.zip"

      files = unzip_response(conn)
      assert Enum.any?(Map.keys(files), &String.ends_with?(&1, ".ink"))
      assert Map.has_key?(files, "metadata.json")
    end
  end

  # ===========================================================================
  # Yarn format
  # ===========================================================================

  describe "GET yarn format" do
    test "exports yarn as zip with all generated files", %{conn: conn, project: project} do
      for index <- 1..6 do
        exportable_flow_fixture(project, %{name: "Flow #{index}"})
      end

      conn = get(conn, export_url(project, "yarn"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "-yarn.zip"

      files = unzip_response(conn)
      yarn_files = files |> Map.keys() |> Enum.filter(&String.ends_with?(&1, ".yarn"))
      assert length(yarn_files) == 6
      assert Map.has_key?(files, "metadata.json")
    end
  end

  # ===========================================================================
  # Godot Dialogic format
  # ===========================================================================

  describe "GET godot format" do
    test "exports godot as zip with dtl files and metadata", %{conn: conn, project: project} do
      exportable_flow_fixture(project, %{name: "Opening"})
      exportable_flow_fixture(project, %{name: "Ending"})

      conn = get(conn, export_url(project, "godot"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/zip"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "-godot.zip"

      files = unzip_response(conn)
      dtl_files = files |> Map.keys() |> Enum.filter(&String.ends_with?(&1, ".dtl"))
      assert length(dtl_files) == 2
      assert Map.has_key?(files, "metadata.json")
    end
  end

  # ===========================================================================
  # Error cases
  # ===========================================================================

  describe "error handling" do
    test "returns 400 for invalid format", %{conn: conn, project: project} do
      conn = get(conn, export_url(project, "nonexistent_format_xyz"))

      assert conn.status == 400
    end

    test "returns 404 for non-member project", %{conn: conn} do
      other_user = user_fixture()
      other_project = other_user |> project_fixture() |> Repo.preload(:workspace)

      conn =
        get(
          conn,
          ~p"/workspaces/#{other_project.workspace.slug}/projects/#{other_project.slug}/export/storyarn"
        )

      assert conn.status == 404
    end

    test "redirects unauthenticated user", %{project: project} do
      conn = build_conn()
      conn = get(conn, export_url(project, "storyarn"))

      assert conn.status == 302
      assert redirected_to(conn) =~ "/users/log-in"
    end
  end

  # ===========================================================================
  # Query params
  # ===========================================================================

  describe "query params" do
    test "validate=false skips validation and returns valid JSON", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "storyarn", %{"validate" => "false"}))

      assert conn.status == 200
      assert {:ok, _data} = Jason.decode(conn.resp_body)
    end

    test "pretty=false produces compact JSON", %{conn: conn, project: project} do
      conn = get(conn, export_url(project, "storyarn", %{"pretty" => "false"}))

      assert conn.status == 200
      # Compact JSON should not have indentation
      refute conn.resp_body =~ "  \""
    end

    test "sheets=false excludes sheets from output", %{conn: conn, project: project} do
      sheet_fixture(project, %{name: "Should be excluded"})

      conn = get(conn, export_url(project, "storyarn", %{"sheets" => "false"}))

      assert {:ok, data} = Jason.decode(conn.resp_body)
      refute Map.has_key?(data, "sheets")
    end

    test "flows=false excludes flows from output", %{conn: conn, project: project} do
      flow_fixture(project, %{name: "Should be excluded"})

      conn = get(conn, export_url(project, "storyarn", %{"flows" => "false"}))

      assert {:ok, data} = Jason.decode(conn.resp_body)
      refute Map.has_key?(data, "flows")
    end

    test "assets=embedded mode returns JSON with assets section", %{
      conn: conn,
      project: project
    } do
      conn = get(conn, export_url(project, "storyarn", %{"assets" => "embedded"}))

      assert conn.status == 200
      assert {:ok, data} = Jason.decode(conn.resp_body)
      assert Map.has_key?(data, "metadata")
    end

    test "localization_policy=preview includes draft translations excluded from release", %{
      conn: conn,
      project: project
    } do
      flow = flow_fixture(project, %{name: "Localized flow"})
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Hello", "responses" => []}})
      source_language_fixture(project, %{locale_code: "en", name: "English"})
      language_fixture(project, %{locale_code: "es", name: "Spanish"})

      [text] = Localization.get_texts_for_source("flow_node", node.id)
      assert {:ok, _text} = Localization.update_text(text, %{translated_text: "Hola", status: "draft"})

      release_conn =
        get(conn, export_url(project, "ink", %{"validate" => "false"}))

      release_files = unzip_response(release_conn)
      refute Map.has_key?(release_files, "localization.es.csv")

      preview_conn =
        get(
          conn,
          export_url(project, "ink", %{
            "validate" => "false",
            "localization_policy" => "preview"
          })
        )

      preview_files = unzip_response(preview_conn)
      assert preview_files["localization.es.csv"] =~ "Hola"
    end
  end
end
