defmodule StoryarnWeb.SheetLive.Handlers.AudioHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Assets
  alias Storyarn.Flows
  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    sheet = sheet_fixture(project, %{name: "Audio Sheet"})
    flow = flow_fixture(project, %{name: "Audio Flow"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => to_string(sheet.id),
          "text" => "<p>Line with audio</p>"
        }
      })

    url = ~p"/workspaces/#{project.workspace.slug}/projects/#{project.slug}/sheets/#{sheet.id}"

    %{flow: flow, node: node, project: project, sheet: sheet, url: url}
  end

  defp mount_sheet(conn, url) do
    {:ok, view, _html} = live(conn, url)
    await_async(view)
    view
  end

  defp data_url(content_type, data) do
    "data:#{content_type};base64," <> Base.encode64(data)
  end

  describe "upload_audio event" do
    test "uploads audio and attaches the created asset to the dialogue node", %{
      conn: conn,
      flow: flow,
      node: node,
      project: project,
      url: url
    } do
      view = mount_sheet(conn, url)

      render_hook(view, "upload_audio", %{
        "filename" => "line.mp3",
        "content_type" => "audio/mpeg",
        "data" => data_url("audio/mpeg", "fake audio data"),
        "node_id" => to_string(node.id)
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      asset_id = updated_node.data["audio_asset_id"]

      assert is_integer(asset_id)
      assert Assets.get_asset(project.id, asset_id).filename == "line.mp3"
    end

    test "rejects unsupported content types", %{conn: conn, flow: flow, node: node, url: url} do
      view = mount_sheet(conn, url)

      render_hook(view, "upload_audio", %{
        "filename" => "line.html",
        "content_type" => "text/html",
        "data" => data_url("text/html", "<script></script>"),
        "node_id" => to_string(node.id)
      })

      updated_node = Flows.get_node!(flow.id, node.id)
      refute Map.has_key?(updated_node.data, "audio_asset_id")
    end
  end
end
