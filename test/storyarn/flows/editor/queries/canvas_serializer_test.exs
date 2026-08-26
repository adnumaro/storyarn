defmodule Storyarn.Flows.Editor.Queries.CanvasSerializerTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows.Editor

  test "serializes the complete active graph through the Editor boundary" do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project, %{name: "Opening"})
    source = node_fixture(flow, %{type: "dialogue", position_x: 100.0, position_y: 200.0})
    target = node_fixture(flow, %{type: "dialogue", position_x: 300.0, position_y: 200.0})
    connection = connection_fixture(flow, source, target)

    loaded_flow = Editor.get_flow!(project.id, flow.id)
    serialized = Editor.serialize_for_canvas(loaded_flow)

    assert serialized.id == flow.id
    assert serialized.name == "Opening"
    assert serialized == Storyarn.Flows.serialize_for_canvas(loaded_flow)
    assert Enum.any?(serialized.nodes, &(&1.id == source.id and &1.position == %{x: 100.0, y: 200.0}))

    assert Enum.any?(
             serialized.connections,
             &(&1.id == connection.id and &1.source_node_id == source.id and
                 &1.target_node_id == target.id)
           )
  end

  test "filters connections whose endpoint is no longer active" do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    source = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Continue"}})
    target = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Deleted"}})
    connection_fixture(flow, source, target)

    target
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:second))
    |> Storyarn.Repo.update!()

    serialized = project.id |> Editor.get_flow!(flow.id) |> Editor.serialize_for_canvas()
    source_payload = Enum.find(serialized.nodes, &(&1.id == source.id))

    refute Enum.any?(serialized.nodes, &(&1.id == target.id))
    refute Enum.any?(serialized.connections, &(&1.target_node_id == target.id))
    assert source_payload.data["dead_end"] == true
  end

  test "resolves Hub colors without involving the presentation layer" do
    assert %{"color" => "#8B5CF6", "color_hex" => "#8B5CF6"} =
             Editor.resolve_node_colors("hub", %{"color" => "#8B5CF6"})
  end
end
