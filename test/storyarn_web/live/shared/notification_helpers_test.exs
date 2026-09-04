defmodule StoryarnWeb.Live.Shared.NotificationHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.WorkspacesFixtures

  alias Storyarn.Flows
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias StoryarnWeb.Live.Shared.NotificationHelpers

  setup do
    actor = user_fixture()
    recipient = user_fixture()
    actor_scope = user_scope_fixture(actor)
    scope = user_scope_fixture(recipient)
    workspace = workspace_fixture(actor)
    project = project_fixture(actor, %{workspace: workspace})
    membership = membership_fixture(project, recipient, "viewer")
    flow = flow_fixture(project)
    node = node_fixture(flow)

    assert {:ok, %{thread: thread}} =
             Projects.create_flow_node_comment(actor_scope, project.id, flow.id, node.id, %{
               body: "Private discussion that must stay out of the inbox",
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: [recipient.id]
             })

    %{
      actor_scope: actor_scope,
      scope: scope,
      workspace: workspace,
      project: project,
      flow: flow,
      node: node,
      thread: thread,
      membership: membership
    }
  end

  test "builds an authorized conversation link using current project identity without comment content", context do
    renamed_project =
      context.project
      |> Ecto.Changeset.change(slug: "renamed-story")
      |> Repo.update!()

    assert %{items: [notification], unreadCount: 1} = NotificationHelpers.client_state(context.scope)
    assert notification.kind == "comment_mention"
    assert notification.entityType == "comment"
    assert notification.projectName == renamed_project.name
    assert is_nil(notification.entityName)
    refute Map.has_key?(notification, :body)

    assert notification.href ==
             "/workspaces/#{context.workspace.slug}/projects/renamed-story/flows/#{context.flow.id}?thread=#{context.thread.id}"
  end

  test "keeps a readable notification but removes navigation when its source is unavailable", context do
    assert {:ok, _deleted, _effects} = Flows.delete_node(context.node)

    assert %{items: [notification], unreadCount: 1} = NotificationHelpers.client_state(context.scope)
    assert notification.kind == "comment_mention"
    assert is_nil(notification.href)
  end

  test "removes the notification and its destination after recipient access is revoked", context do
    assert {:ok, _removed} =
             Projects.remove_member(context.actor_scope, context.project.id, context.membership.id)

    assert %{items: [], unreadCount: 0} = NotificationHelpers.client_state(context.scope)
  end
end
