defmodule StoryarnWeb.SheetLive.Handlers.AudioHandlersTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects.Assets
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

    test "rejects an allowed non-audio asset type before creating an asset", %{
      conn: conn,
      node: node,
      project: project,
      url: url
    } do
      view = mount_sheet(conn, url)
      before_ids = Assets.list_asset_ids(project.id)

      render_hook(view, "upload_audio", %{
        "filename" => "not-audio.png",
        "content_type" => "image/png",
        "data" => data_url("image/png", "fake image data"),
        "node_id" => to_string(node.id)
      })

      assert render(view) =~ "Unsupported file type."
      assert Assets.list_asset_ids(project.id) == before_ids
    end

    test "reports malformed upload payloads instead of crashing the LiveView", %{conn: conn, url: url} do
      view = mount_sheet(conn, url)

      render_hook(view, "upload_audio", %{"data" => %{"unexpected" => true}})

      assert render(view) =~ "Invalid file data."
    end

    test "reports when upload succeeds but the dialogue can no longer be attached", %{
      conn: conn,
      flow: flow,
      node: node,
      project: project,
      url: url
    } do
      view = mount_sheet(conn, url)
      assert {:ok, _deleted, _meta} = Flows.delete_node(node)

      render_hook(view, "upload_audio", %{
        "filename" => "orphaned-line.mp3",
        "content_type" => "audio/mpeg",
        "data" => data_url("audio/mpeg", "fake audio data"),
        "node_id" => to_string(node.id)
      })

      assert render(view) =~ "Audio uploaded, but it could not be attached"
      assert Enum.any?(Assets.list_assets(project.id), &(&1.filename == "orphaned-line.mp3"))
      assert Flows.get_node(flow.id, node.id) == nil
    end
  end

  describe "select_audio and remove_audio events" do
    test "assigns and clears an existing audio asset through the Sheet workspace", %{
      conn: conn,
      flow: flow,
      node: node,
      project: project,
      sheet: sheet,
      user: user,
      url: url
    } do
      audio = audio_asset_fixture(project, user)
      view = mount_sheet(conn, url)

      render_hook(view, "select_audio", %{
        "node-id" => to_string(node.id),
        "audio_asset_id" => to_string(audio.id)
      })

      assert Flows.get_node!(flow.id, node.id).data["audio_asset_id"] == audio.id
      assert Enum.any?(Storyarn.Sheets.list_dialogue_audio_lines(project.id, sheet.id), &(&1.id == node.id))

      render_hook(view, "remove_audio", %{"node-id" => to_string(node.id)})
      assert Flows.get_node!(flow.id, node.id).data["audio_asset_id"] == nil
    end

    test "shows a useful error for stale dialogue and invalid audio payloads", %{
      conn: conn,
      node: node,
      url: url
    } do
      view = mount_sheet(conn, url)

      render_hook(view, "select_audio", %{
        "node-id" => to_string(node.id),
        "audio_asset_id" => "not-an-id"
      })

      assert render(view) =~ "The selected audio is no longer available."

      render_hook(view, "remove_audio", %{"node-id" => "not-a-node"})

      assert render(view) =~ "This dialogue line is no longer available. Refresh and try again."

      render_hook(view, "select_audio", %{"audio_asset_id" => %{"unexpected" => true}})
      assert render(view) =~ "The selected audio is no longer available."
    end

    test "a viewer cannot forge select, upload, or remove mutations", %{
      conn: conn,
      flow: flow,
      node: node,
      project: project,
      sheet: sheet,
      user: owner,
      url: url
    } do
      viewer = user_fixture()
      membership_fixture(project, viewer, "viewer")
      view = conn |> log_in_user(viewer) |> mount_sheet(url)
      audio = audio_asset_fixture(project, owner)
      before_asset_ids = Assets.list_asset_ids(project.id)

      render_hook(view, "select_audio", %{
        "node-id" => to_string(node.id),
        "audio_asset_id" => to_string(audio.id)
      })

      refute Map.has_key?(Flows.get_node!(flow.id, node.id).data, "audio_asset_id")

      render_hook(view, "upload_audio", %{
        "filename" => "forged.mp3",
        "content_type" => "audio/mpeg",
        "data" => data_url("audio/mpeg", "forged audio"),
        "node_id" => to_string(node.id)
      })

      assert Assets.list_asset_ids(project.id) == before_asset_ids

      assert {:ok, _updated} =
               Storyarn.Sheets.update_dialogue_audio(project.id, sheet.id, node.id, audio.id)

      render_hook(view, "remove_audio", %{"node-id" => to_string(node.id)})
      assert Flows.get_node!(flow.id, node.id).data["audio_asset_id"] == audio.id
    end
  end
end
