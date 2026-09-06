defmodule StoryarnWeb.FlowLive.SequenceVersioningTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Versioning.SnapshotStorage
  alias Storyarn.Projects
  alias Storyarn.Projects.Assets
  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture(%{auto_version_flows: true}) |> Repo.preload(:workspace)
    flow = flow_fixture(project)
    owner = node_fixture(flow)

    %{project: project, flow: flow, owner: owner}
  end

  test "composition-only edits debounce an automatic version containing the final geometry and order", ctx do
    image = uploaded_asset(ctx, "sequence.png", "sequence image", "image/png")
    view = mount_flow(ctx)

    first_token =
      schedule_edit(view, "create_sequence_visual_layer", %{
        "id" => ctx.owner.id,
        "asset_id" => image.id,
        "kind" => "character",
        "label" => "Character"
      })

    [character] = Flows.list_sequence_visual_layers(ctx.owner.id)

    schedule_edit(view, "create_sequence_visual_layer", %{
      "id" => ctx.owner.id,
      "asset_id" => image.id,
      "kind" => "overlay",
      "label" => "Foreground"
    })

    foreground = Enum.find(Flows.list_sequence_visual_layers(ctx.owner.id), &(&1.label == "Foreground"))

    schedule_edit(view, "update_sequence_visual_layer", %{
      "id" => ctx.owner.id,
      "layer_id" => character.id,
      "x" => -1.5,
      "y" => 2.2,
      "width" => 3.0,
      "height" => 4.0
    })

    order = [foreground.layer_key, character.layer_key]

    latest_token =
      schedule_edit(view, "reorder_sequence_visual_layers", %{
        "id" => ctx.owner.id,
        "layer_keys" => order
      })

    send(view.pid, {:try_auto_snapshot, first_token})
    assert socket_assigns(view).auto_snapshot_ref == latest_token
    assert Flows.list_versions(ctx.flow.id) == []

    snapshot = persist_scheduled_version(view, ctx.flow)
    owner = Enum.find(snapshot["nodes"], &(&1["original_id"] == ctx.owner.id))
    assert owner["data"]["composition_layer_order"] == order
    layer = Enum.find(owner["sequence_visual_layers"], &(&1["layer_key"] == character.layer_key))
    assert {layer["x"], layer["y"], layer["width"], layer["height"]} == {-1.5, 2.2, 3.0, 4.0}
    assert snapshot["asset_blob_hashes"][to_string(image.id)] == image.blob_hash
  end

  test "inheritance edits and undo each schedule a version without modifying the source", ctx do
    image = image_asset_fixture(ctx.project, ctx.user)
    source = node_fixture(ctx.flow)
    {:ok, layer} = Flows.create_sequence_visual_layer(source.id, %{asset_id: image.id, kind: "character"})
    {:ok, source_before} = Flows.capture_sequence_composition(source.id)
    {:ok, owner_before} = Flows.capture_sequence_composition(ctx.owner.id)
    view = mount_flow(ctx)

    schedule_edit(view, "set_composition_source", %{"id" => ctx.owner.id, "source_id" => source.id})
    assert Flows.get_node!(ctx.flow.id, ctx.owner.id).composition_source_id == source.id

    schedule_edit(view, "override_sequence_visual_layer", %{
      "id" => ctx.owner.id,
      "layer_key" => layer.layer_key,
      "x" => -0.4
    })

    assert Flows.get_sequence_visual_layer_by_key(ctx.owner.id, layer.layer_key).x == -0.4

    schedule_edit(view, "revert_sequence_visual_layer", %{
      "id" => ctx.owner.id,
      "layer_key" => layer.layer_key,
      "fields" => ["x"]
    })

    schedule_edit(view, "remove_sequence_visual_layer", %{"id" => ctx.owner.id, "layer_key" => layer.layer_key})
    assert Flows.get_sequence_visual_layer_by_key(ctx.owner.id, layer.layer_key).removed
    schedule_edit(view, "restore_sequence_visual_layer", %{"id" => ctx.owner.id, "layer_key" => layer.layer_key})

    {:ok, current} = Flows.capture_sequence_composition(ctx.owner.id)

    schedule_edit(view, "restore_sequence_composition", %{
      "id" => ctx.owner.id,
      "snapshot" => owner_before,
      "expected_current" => current
    })

    assert {:ok, ^owner_before} = Flows.capture_sequence_composition(ctx.owner.id)
    assert {:ok, ^source_before} = Flows.capture_sequence_composition(source.id)
  end

  test "sequence metadata and audio edits schedule versions including the track", ctx do
    audio = uploaded_asset(ctx, "ambience.mp3", "sequence ambience", "audio/mpeg")
    {:ok, sequence} = Flows.create_sequence(ctx.flow.id, %{"name" => "Original"})
    view = mount_flow(ctx)

    schedule_edit(view, "update_sequence_name", %{"id" => sequence.id, "name" => "Night scene"})
    schedule_edit(view, "update_sequence_config", %{"id" => sequence.id, "width" => 640.0, "height" => 360.0})

    schedule_edit(view, "upsert_sequence_track", %{
      "id" => sequence.id,
      "kind" => "ambience",
      "asset_id" => audio.id,
      "volume" => 0.35
    })

    snapshot = persist_scheduled_version(view, ctx.flow)
    saved = Enum.find(snapshot["nodes"], &(&1["original_id"] == sequence.id))
    assert saved["sequence_config"]["name"] == "Night scene"
    assert saved["sequence_config"]["width"] == 640.0
    assert saved["sequence_config"]["height"] == 360.0
    assert [%{"kind" => "ambience", "asset_id" => asset_id, "volume" => volume}] = saved["sequence_tracks"]
    assert Decimal.equal?(Decimal.new(volume), Decimal.new("0.35"))
    assert asset_id == audio.id

    schedule_edit(view, "clear_sequence_track", %{"id" => sequence.id, "kind" => "ambience"})
    assert Flows.list_sequence_tracks(sequence.id) == []
  end

  test "deleting a local layer schedules a version", ctx do
    image = image_asset_fixture(ctx.project, ctx.user)
    {:ok, layer} = Flows.create_sequence_visual_layer(ctx.owner.id, %{asset_id: image.id, kind: "prop"})
    view = mount_flow(ctx)

    schedule_edit(view, "delete_sequence_visual_layer", %{"id" => ctx.owner.id, "layer_id" => layer.id})

    assert Flows.list_sequence_visual_layers(ctx.owner.id) == []
  end

  test "invalid composition edits and stale undo do not schedule a version", ctx do
    image = image_asset_fixture(ctx.project, ctx.user)
    {:ok, layer} = Flows.create_sequence_visual_layer(ctx.owner.id, %{asset_id: image.id, kind: "character"})
    {:ok, before} = Flows.capture_sequence_composition(ctx.owner.id)
    view = mount_flow(ctx)

    for {event, params} <- [
          {"update_sequence_visual_layer", %{"id" => ctx.owner.id, "layer_id" => layer.id, "x" => 11.0}},
          {"reorder_sequence_visual_layers", %{"id" => ctx.owner.id, "layer_keys" => ["missing-layer"]}},
          {"set_composition_source", %{"id" => ctx.owner.id, "source_id" => ctx.owner.id}},
          {"restore_sequence_composition",
           %{"id" => ctx.owner.id, "snapshot" => before, "expected_current" => Map.put(before, "visual_layers", [])}}
        ] do
      render_hook(view, event, params)
      assert socket_assigns(view).auto_snapshot_ref == nil
      assert {:ok, ^before} = Flows.capture_sequence_composition(ctx.owner.id)
    end

    assert Flows.list_versions(ctx.flow.id) == []
  end

  test "viewers cannot mutate composition or schedule versions", ctx do
    viewer = Storyarn.AccountsFixtures.user_fixture()
    membership_fixture(ctx.project, viewer, "viewer")
    image = image_asset_fixture(ctx.project, ctx.user)
    {:ok, layer} = Flows.create_sequence_visual_layer(ctx.owner.id, %{asset_id: image.id, kind: "character"})
    {:ok, before} = Flows.capture_sequence_composition(ctx.owner.id)
    view = mount_flow(%{ctx | conn: log_in_user(ctx.conn, viewer)})

    for {event, params} <- [
          {"create_sequence_visual_layer", %{"id" => ctx.owner.id, "asset_id" => image.id, "kind" => "overlay"}},
          {"update_sequence_visual_layer", %{"id" => ctx.owner.id, "layer_id" => layer.id, "x" => -0.5}},
          {"reorder_sequence_visual_layers", %{"id" => ctx.owner.id, "layer_keys" => [layer.layer_key]}}
        ] do
      render_hook(view, event, params)
      assert socket_assigns(view).auto_snapshot_ref == nil
      assert {:ok, ^before} = Flows.capture_sequence_composition(ctx.owner.id)
    end

    assert Flows.list_versions(ctx.flow.id) == []
  end

  test "disabled automatic versioning does not persist a version after a composition edit", ctx do
    assert {:ok, _project} = Projects.update_project(ctx.scope, ctx.project.id, %{auto_version_flows: false})
    image = image_asset_fixture(ctx.project, ctx.user)
    view = mount_flow(ctx)

    token =
      schedule_edit(view, "create_sequence_visual_layer", %{
        "id" => ctx.owner.id,
        "asset_id" => image.id,
        "kind" => "character"
      })

    send(view.pid, {:try_auto_snapshot, token})
    assert socket_assigns(view).auto_snapshot_ref == nil
    assert Flows.list_versions(ctx.flow.id) == []
    assert [_layer] = Flows.list_sequence_visual_layers(ctx.owner.id)
  end

  defp mount_flow(ctx) do
    {:ok, view, _html} =
      live(ctx.conn, ~p"/workspaces/#{ctx.project.workspace.slug}/projects/#{ctx.project.slug}/flows/#{ctx.flow.id}")

    await_async(view)
    render_hook(view, "node_selected", %{"id" => ctx.owner.id})
    render_hook(view, "set_sequence_workspace", %{"open" => true})
    assert socket_assigns(view).auto_snapshot_ref == nil
    view
  end

  defp schedule_edit(view, event, params) do
    previous = socket_assigns(view).auto_snapshot_ref
    render_hook(view, event, params)
    assigns = socket_assigns(view)
    assert is_reference(assigns.auto_snapshot_ref), "#{event} did not schedule a version"
    refute assigns.auto_snapshot_ref == previous, "#{event} did not renew the debounce token"
    assert is_reference(assigns.auto_snapshot_timer)
    assert is_integer(Process.cancel_timer(assigns.auto_snapshot_timer))
    assigns.auto_snapshot_ref
  end

  defp persist_scheduled_version(view, flow) do
    token = socket_assigns(view).auto_snapshot_ref
    assert is_reference(token)
    send(view.pid, {:try_auto_snapshot, token})
    assert socket_assigns(view).auto_snapshot_ref == nil
    assert Flows.list_versions(flow.id) == []
    request = Repo.get_by!(Flows.Versioning.VersionRequest, flow_id: flow.id, status: "pending")
    assert :ok = Oban.Testing.perform_job(Storyarn.Workers.CreateFlowVersionWorker, %{request_id: request.id}, repo: Repo)
    assert [version] = Flows.list_versions(flow.id)
    assert version.is_auto
    on_exit(fn -> SnapshotStorage.delete(version.storage_key) end)
    assert {:ok, snapshot} = Flows.load_version_snapshot(version)
    snapshot
  end

  defp socket_assigns(view), do: :sys.get_state(view.pid).socket.assigns

  defp uploaded_asset(ctx, filename, content, content_type) do
    assert {:ok, asset} =
             Assets.upload_binary_and_create_asset(
               content,
               %{filename: filename, content_type: content_type},
               ctx.project,
               ctx.user
             )

    extension = if content_type == "image/png", do: "png", else: "mp3"

    on_exit(fn ->
      Assets.storage_delete(asset.key)
      delete_storage_blob("projects/#{ctx.project.id}/blobs/#{asset.blob_hash}.#{extension}")
    end)

    asset
  end
end
