defmodule Storyarn.Projects.Comments.SourceLifecycleTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.Persistence.FlowRecord

  test "hard deletion retains the discussion and never rebinds an identical reused ID" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    flow = flow_fixture(project)
    node = node_fixture(flow, %{data: %{"text" => "A source worth reviewing"}})
    attrs = %{body: "Please review this line", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}

    assert {:ok, detail} = Projects.create_flow_node_comment(scope, project.id, flow.id, node.id, attrs)
    Repo.delete!(node)

    # This persistence seam deliberately reconstructs the exact ID and timestamp;
    # ordinary authoring APIs must not offer a way to revive a tombstoned anchor.
    Repo.insert!(%FlowNode{
      id: node.id,
      flow_id: flow.id,
      type: "annotation",
      data: %{"text" => "A different source"},
      inserted_at: node.inserted_at,
      updated_at: node.updated_at
    })

    assert {:ok, unavailable} = Projects.get_comment_thread(scope, project.id, detail.thread.id)
    assert unavailable.thread.source.status == "unavailable"
    assert unavailable.thread.source.label == "A source worth reviewing"
    assert [%{body: "Please review this line"}] = unavailable.messages
    assert Repo.get!(Thread, detail.thread.id).flow_node_id == nil
  end

  test "restoring a Flow version preserves later discussion and does not rebind a rebuilt source" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    flow = flow_fixture(project, %{name: "Original flow"})
    node = node_fixture(flow, %{data: %{"text" => "Original dialogue"}})
    attrs = %{body: "Review this dialogue", client_request_id: Ecto.UUID.generate(), mention_user_ids: []}

    assert {:ok, original} = Projects.create_flow_node_comment(scope, project.id, flow.id, node.id, attrs)
    assert {:ok, version} = Flows.create_version(flow, owner.id, title: "Before discussion changes")
    assert {:ok, changed_flow} = Flows.update_flow(flow, %{name: "Changed flow"})

    reply = %{
      body: "Agreed after the snapshot",
      parent_id: original.thread.root_message_id,
      client_request_id: Ecto.UUID.generate(),
      mention_user_ids: []
    }

    assert {:ok, replied} = Projects.reply_to_comment_thread(scope, project.id, original.thread.id, reply)

    assert {:ok, resolved} =
             Projects.set_comment_thread_status(
               scope,
               project.id,
               original.thread.id,
               "resolved",
               replied.thread.revision
             )

    Repo.delete!(node)
    assert {:ok, restored_flow} = Flows.restore_version(changed_flow, version, user_id: owner.id)
    assert restored_flow.name == "Original flow"
    restored_node = Flows.get_node(flow.id, node.id)
    assert restored_node.id == node.id
    assert restored_node.data["text"] == "Original dialogue"

    assert {:ok, retained} = Projects.get_comment_thread(scope, project.id, original.thread.id)
    assert Enum.map(retained.messages, & &1.id) == Enum.map(replied.messages, & &1.id)
    assert Enum.map(retained.messages, & &1.body) == ["Review this dialogue", "Agreed after the snapshot"]
    assert retained.thread.status == "resolved"
    assert retained.thread.revision == resolved.revision
    assert retained.thread.resolved_at == resolved.resolved_at
    assert retained.thread.message_count == 2
    assert retained.thread.source.status == "unavailable"
    assert Repo.get!(Thread, original.thread.id).flow_node_id == nil
  end

  test "canvas discussions do not rebind when project reconstitution replaces the Flow row" do
    owner = user_fixture()
    scope = user_scope_fixture(owner)
    project = project_fixture(owner)
    flow = flow_fixture(project)
    attrs = %{body: "Keep this canvas discussion", client_request_id: Ecto.UUID.generate(), position: %{x: 5, y: 10}}
    assert {:ok, detail} = Projects.create_flow_canvas_comment(scope, project.id, flow.id, attrs)

    # The Project-owned materialization record models exact reconstitution;
    # Comments' own read-only source projection is never used as a writer.
    flow_record = Repo.get!(FlowRecord, flow.id)
    Repo.delete!(flow_record)

    Repo.insert!(%FlowRecord{
      id: flow.id,
      project_id: project.id,
      name: flow.name,
      shortcut: flow.shortcut,
      inserted_at: flow.inserted_at,
      updated_at: flow.updated_at
    })

    assert {:ok, retained} = Projects.get_comment_thread(scope, project.id, detail.thread.id)
    assert retained.thread.source.status == "unavailable"
    assert retained.thread.position == %{x: 5.0, y: 10.0}
    assert [%{body: "Keep this canvas discussion"}] = retained.messages
    assert Repo.get!(Thread, detail.thread.id).flow_canvas_id == nil
    assert {:ok, []} = Projects.list_flow_comment_pins(scope, project.id, flow.id)
    assert Projects.comment_destinations(scope, [detail.thread.root_message_id]) == %{}
  end
end
