defmodule StoryarnWeb.Live.Shared.NotificationHelpersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures
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

    assert {:ok, %{thread: thread, messages: [message]}} =
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
      comment_id: message.id,
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

  test "builds Scene conversation links from the source-family destination", context do
    scene = scene_fixture(context.project)

    assert {:ok, %{thread: thread}} =
             Projects.create_scene_canvas_comment(context.actor_scope, context.project.id, scene.id, %{
               body: "Review this Scene position",
               position: %{x: 25, y: 75},
               client_request_id: Ecto.UUID.generate(),
               mention_user_ids: [context.scope.user.id]
             })

    assert %{items: items, unreadCount: 2} = NotificationHelpers.client_state(context.scope)
    scene_notification = Enum.find(items, &String.contains?(&1.href || "", "/scenes/"))

    assert scene_notification.href ==
             "/workspaces/#{context.workspace.slug}/projects/#{context.project.slug}/scenes/#{scene.id}?thread=#{thread.id}"
  end

  test "builds Sheet conversation links from the source-family destination", context do
    sheet = sheet_fixture(context.project)

    assert {:ok, %{thread: thread}} =
             Projects.create_sheet_canvas_comment(
               context.actor_scope,
               context.project.id,
               sheet.id,
               %{
                 body: "Review this Sheet",
                 position: %{x: 25, y: 750},
                 client_request_id: Ecto.UUID.generate(),
                 mention_user_ids: [context.scope.user.id]
               }
             )

    assert %{items: items, unreadCount: 2} = NotificationHelpers.client_state(context.scope)
    sheet_notification = Enum.find(items, &String.contains?(&1.href || "", "/sheets/"))

    assert sheet_notification.href ==
             "/workspaces/#{context.workspace.slug}/projects/#{context.project.slug}/sheets/#{sheet.id}?thread=#{thread.id}"
  end

  test "removes the notification and its destination after recipient access is revoked", context do
    assert {:ok, _removed} =
             Projects.remove_member(context.actor_scope, context.project.id, context.membership.id)

    assert %{items: [], unreadCount: 0} = NotificationHelpers.client_state(context.scope)
  end

  test "resolves a larger inbox across projects without additional queries per notification", context do
    {single, single_queries} = measured_client_state(context.scope)
    assert length(single.items) == 1

    for index <- 1..4 do
      project = if index < 3, do: context.project, else: project_fixture(context.actor_scope.user)
      if project.id != context.project.id, do: membership_fixture(project, context.scope.user, "viewer")
      flow = flow_fixture(project)
      node = node_fixture(flow)

      assert {:ok, _comment} =
               Projects.create_flow_node_comment(context.actor_scope, project.id, flow.id, node.id, %{
                 body: "Another discussion",
                 client_request_id: Ecto.UUID.generate(),
                 mention_user_ids: [context.scope.user.id]
               })
    end

    {larger, larger_queries} = measured_client_state(context.scope)
    assert length(larger.items) == 5
    assert Enum.all?(larger.items, &is_binary(&1.href))
    assert larger_queries == single_queries
  end

  test "batch destinations recheck effective access and reject invalid or foreign identifiers", context do
    inherited_user = user_fixture()
    membership = workspace_membership_fixture(context.workspace, inherited_user, "viewer")
    inherited_scope = user_scope_fixture(inherited_user)
    key = {context.project.id, context.comment_id}
    ids = [context.comment_id, context.comment_id, 9_223_372_036_854_775_808, nil, "invalid"]

    assert %{^key => destination} = Projects.comment_destinations(inherited_scope, ids)
    assert destination.thread_id == context.thread.id
    assert destination.node_id == context.node.id
    assert destination.project_slug == context.project.slug
    assert destination.workspace_slug == context.workspace.slug
    assert map_size(Projects.comment_destinations(context.scope, ids)) == 1
    assert Projects.comment_destinations(user_scope_fixture(), ids) == %{}
    assert Projects.comment_destinations(%{user: nil}, ids) == %{}
    assert Projects.comment_destinations(context.scope, nil) == %{}

    Repo.delete!(membership)
    assert Projects.comment_destinations(inherited_scope, ids) == %{}

    assert {:ok, _removed} =
             Projects.remove_member(context.actor_scope, context.project.id, context.membership.id)

    assert Projects.comment_destinations(context.scope, ids) == %{}
  end

  defp measured_client_state(scope) do
    marker = make_ref()
    handler_id = "comment-inbox-queries-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler_id, [:storyarn, :repo, :query], &record_query/4, {self(), marker})

    try do
      state = NotificationHelpers.client_state(scope)
      {state, query_count(marker, 0)}
    after
      :telemetry.detach(handler_id)
    end
  end

  defp record_query(_event, _measurements, _metadata, {pid, marker}) do
    if self() == pid, do: send(pid, {marker, :query})
  end

  defp query_count(marker, count) do
    receive do
      {^marker, :query} -> query_count(marker, count + 1)
    after
      0 -> count
    end
  end
end
