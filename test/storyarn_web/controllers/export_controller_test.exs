defmodule StoryarnWeb.ExportControllerTest do
  use StoryarnWeb.ConnCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = project_fixture(user) |> Repo.preload(:workspace)
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
    test "exports ink with text/plain content-type", %{conn: conn, project: project} do
      flow = flow_fixture(project, %{name: "Main"})
      entry = Enum.find(Storyarn.Flows.list_nodes(flow.id), &(&1.type == "entry"))
      exit_node = node_fixture(flow, %{type: "exit", data: %{}})
      connection_fixture(flow, entry, exit_node)

      conn = get(conn, export_url(project, "ink"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ".ink"
    end
  end

  # ===========================================================================
  # Yarn format
  # ===========================================================================

  describe "GET yarn format" do
    test "exports yarn with text/plain content-type", %{conn: conn, project: project} do
      flow = flow_fixture(project, %{name: "Main"})
      entry = Enum.find(Storyarn.Flows.list_nodes(flow.id), &(&1.type == "entry"))
      exit_node = node_fixture(flow, %{type: "exit", data: %{}})
      connection_fixture(flow, entry, exit_node)

      conn = get(conn, export_url(project, "yarn"))

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

      [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ ".yarn"
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
      other_project = project_fixture(other_user) |> Repo.preload(:workspace)

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
  end
end
