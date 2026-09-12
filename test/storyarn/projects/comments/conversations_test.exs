defmodule Storyarn.Projects.CommentConversationsTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.IdeationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Projects
  alias Storyarn.Projects.Comments.Context
  alias Storyarn.Projects.Comments.Queries
  alias Storyarn.Projects.Comments.Thread
  alias Storyarn.Projects.ProjectMembership

  setup do
    ctx = ideation_fixture()

    Map.merge(ctx, %{
      flow: flow_fixture(ctx.project, %{name: "A branching dialogue"}),
      scene: scene_fixture(ctx.project, %{name: "The harbor"}),
      sheet: sheet_fixture(ctx.project, %{name: "Captain Selene"})
    })
  end

  test "aggregates authorized sources across tools and projects before limits and counts", ctx do
    expected = for tool <- ~w(flow sheet scene brainstorming), do: create_conversation(ctx, tool).thread.id
    other = ideation_fixture()
    create_conversation(other, "brainstorming", %{body: "A foreign newest conversation"})

    assert {:ok, %{threads: threads, counts: %{all: 4, open: 4, resolved: 0}}} =
             Projects.list_comment_conversations(ctx.peer, limit: 4)

    assert Enum.sort(Enum.map(threads, & &1.id)) == Enum.sort(expected)

    for thread <- threads do
      assert thread.project_id == ctx.project.id
      assert thread.project_name == ctx.project.name
      assert thread.project_slug == ctx.project.slug
      assert thread.workspace_id == ctx.project.workspace_id
      assert is_binary(thread.workspace_name)
      assert thread.destination.project_id == ctx.project.id
      assert thread.destination.thread_id == thread.id
    end

    assert {:ok, %{threads: [], counts: %{all: 0}}} =
             Projects.list_comment_conversations(user_scope_fixture(), search: "discussion", limit: 1)

    second_project = project_fixture(ctx.owner.user)
    membership_fixture(second_project, ctx.peer.user, "viewer")
    second_sheet = sheet_fixture(second_project)
    second = create_conversation(%{ctx | project: second_project, sheet: second_sheet, author: ctx.owner}, "sheet")

    assert {:ok, %{threads: [thread], counts: %{all: 1}}} =
             Projects.list_comment_conversations(ctx.peer, project_id: second_project.id)

    assert thread.id == second.thread.id
  end

  test "inherited workspace access works without a direct membership and revocation removes every projection", ctx do
    create_conversation(ctx, "sheet")
    create_conversation(ctx, "brainstorming")
    inherited = user_scope_fixture()
    project = Repo.preload(ctx.project, :workspace)

    membership =
      Storyarn.WorkspacesFixtures.workspace_membership_fixture(project.workspace, inherited.user, "viewer")

    assert {:ok, %{threads: threads, counts: %{all: 2}}} =
             Projects.list_comment_conversations(inherited, workspace_id: project.workspace.id)

    assert length(threads) == 2
    Repo.delete!(membership)
    assert {:ok, %{threads: [], counts: %{all: 0}}} = Projects.list_comment_conversations(inherited)
  end

  test "paginates tied activity without duplicates and status counts ignore the selected tab", ctx do
    first = create_conversation(ctx, "sheet")
    second = create_conversation(ctx, "flow")
    third = create_conversation(ctx, "scene")
    at = ~U[2026-09-12 12:00:00Z]
    Repo.update_all(from(t in Thread, where: t.project_id == ^ctx.project.id), set: [last_activity_at: at])

    assert {:ok, %{threads: [page_one], next_cursor: cursor}} =
             Projects.list_comment_conversations(ctx.peer, limit: 1)

    assert page_one.id == third.thread.id

    assert {:ok, %{threads: [page_two], next_cursor: second_cursor}} =
             Projects.list_comment_conversations(ctx.peer, limit: 1, cursor: cursor)

    assert page_two.id == second.thread.id

    assert {:ok, %{threads: [page_three], next_cursor: nil}} =
             Projects.list_comment_conversations(ctx.peer, limit: 1, cursor: second_cursor)

    assert page_three.id == first.thread.id

    assert {:ok, _} =
             Projects.set_comment_thread_status(
               ctx.author,
               ctx.project.id,
               second.thread.id,
               "resolved",
               second.thread.revision
             )

    assert {:ok, %{threads: [resolved], counts: %{all: 3, open: 2, resolved: 1}}} =
             Projects.list_comment_conversations(ctx.peer, status: "resolved")

    assert resolved.id == second.thread.id
    assert {:ok, %{threads: [flow], counts: %{all: 1}}} = Projects.list_comment_conversations(ctx.peer, tool: "flow")
    assert flow.id == second.thread.id
  end

  test "personal filters use messages and mentions across all tools before pagination", ctx do
    mentioned = create_conversation(ctx, "sheet", %{mention_user_ids: [ctx.peer.user.id]})
    other = create_conversation(ctx, "flow")

    assert {:ok, _} =
             Projects.reply_to_comment_thread(ctx.peer, ctx.project.id, other.thread.id, %{
               body: "A specific answer",
               parent_id: hd(other.messages).id,
               client_request_id: Ecto.UUID.generate()
             })

    assert {:ok, %{threads: [participated], counts: %{all: 1}}} =
             Projects.list_comment_conversations(ctx.peer, participated: true, limit: 1)

    assert participated.id == other.thread.id

    assert {:ok, %{threads: [thread], counts: %{all: 1}}} =
             Projects.list_comment_conversations(ctx.peer, mentioned: true, limit: 1)

    assert thread.id == mentioned.thread.id
    assert {:ok, %{threads: [], counts: %{all: 0}}} = Projects.list_comment_conversations(ctx.viewer, mentioned: true)
  end

  test "search finds current readable sources, contexts, project names and replies with literal text", ctx do
    block = block_fixture(ctx.sheet, %{config: %{"label" => "Secret motivation"}})
    sheet = create_conversation(ctx, "sheet", %{context: %{type: "sheet_block", id: block.id}})
    flow = create_conversation(ctx, "flow", %{body: "Use 100% of this branch"})
    create_conversation(ctx, "scene")

    assert_search(ctx, "CAPTAIN SELENE", sheet.thread.id)
    assert_search(ctx, "secret motivation", sheet.thread.id)
    assert_search(ctx, "%", flow.thread.id)

    assert {:ok, %{threads: [], counts: %{all: 0}}} = Projects.list_comment_conversations(ctx.peer, search: "_")

    ctx.sheet |> Ecto.Changeset.change(name: "Navigator Ada") |> Repo.update!()
    assert_search(ctx, "navigator ada", sheet.thread.id)
    assert {:ok, %{threads: []}} = Projects.list_comment_conversations(ctx.peer, search: "captain selene")

    block |> Ecto.Changeset.change(config: %{"label" => "Current motivation"}) |> Repo.update!()
    assert_search(ctx, "current motivation", sheet.thread.id)
    assert {:ok, %{threads: []}} = Projects.list_comment_conversations(ctx.peer, search: "secret motivation")

    assert {:ok, %{threads: threads, counts: %{all: 3}}} =
             Projects.list_comment_conversations(ctx.peer, search: ctx.project.name)

    assert length(threads) == 3
  end

  test "private Ideation sources never contribute previews, labels, counts or page positions", ctx do
    sheet = create_conversation(ctx, "sheet")
    idea = idea_fixture(ctx, %{title: "Shared lighthouse", visibility: :shared})
    idea_thread = create_conversation(ctx, "brainstorming", %{body: "A shared lighthouse discussion"}, idea.id)
    assert_search(ctx, "Idea ##{idea.id}", idea_thread.thread.id)
    assert_search(ctx, "shared lighthouse", idea_thread.thread.id)
    assert {:ok, session} = Storyarn.Ideation.get_session(ctx.facilitator, ctx.project.id, ctx.session.id)

    assert {:ok, _} =
             Storyarn.Ideation.set_private_mode(ctx.facilitator, ctx.project.id, session.id, session.revision, true)

    assert {:ok, %{threads: [thread], next_cursor: nil, counts: %{all: 1}}} =
             Projects.list_comment_conversations(ctx.peer, limit: 1)

    assert thread.id == sheet.thread.id

    assert {:ok, %{threads: [], counts: %{all: 0}}} =
             Projects.list_comment_conversations(ctx.peer, search: "lighthouse")

    assert {:ok, %{threads: [], counts: %{all: 0}}} =
             Projects.list_comment_conversations(ctx.peer, tool: "brainstorming")
  end

  test "pure contextual keywords search fixed Sheet parts and current Scene labels", ctx do
    title = create_conversation(ctx, "sheet", %{context: %{type: "sheet_title", id: ctx.sheet.id}})
    zone = zone_fixture(ctx.scene, %{"name" => "Old watchtower"})
    scene = create_conversation(ctx, "scene", %{context: %{type: "scene_zone", id: zone.id}})
    assert_search(ctx, "title", title.thread.id)
    assert_search(ctx, "watchtower", scene.thread.id)

    zone |> Ecto.Changeset.change(name: "Northern fort") |> Repo.update!()
    assert_search(ctx, "northern fort", scene.thread.id)
    assert {:ok, %{threads: []}} = Projects.list_comment_conversations(ctx.peer, search: "watchtower")
    Repo.delete!(zone)
    assert {:ok, %{threads: []}} = Projects.list_comment_conversations(ctx.peer, search: "northern fort")

    pin = pin_fixture(ctx.scene, %{"label" => nil})
    unnamed = create_conversation(ctx, "scene", %{context: %{type: "scene_pin", id: pin.id}})
    assert_search(ctx, "Pin ##{pin.id}", unnamed.thread.id)
  end

  test "every source and context search branch honors the caller's candidate relation", ctx do
    source_names = %{"flow" => ctx.flow.name, "sheet" => ctx.sheet.name, "scene" => ctx.scene.name}

    for {tool, type, target_id, text} <- searchable_contexts(ctx) do
      attrs = %{context: %{type: type, id: target_id}}
      allowed = create_conversation(ctx, tool, attrs)
      create_conversation(ctx, tool, attrs)
      candidates = from(t in Thread, where: t.id == ^allowed.thread.id)

      assert Repo.all(Context.matching_threads(text, candidates)) == [allowed.thread.id], type

      source_name = Map.fetch!(source_names, tool)
      assert Repo.all(Queries.matching_source_threads(source_name, candidates)) == [allowed.thread.id], type
    end
  end

  test "searched pages materialize only authorized prefiltered candidates without a page limit", ctx do
    for _ <- 1..3, do: create_conversation(ctx, "sheet", %{mention_user_ids: [ctx.peer.user.id]})
    create_conversation(ctx, "sheet")
    create_conversation(ctx, "flow", %{mention_user_ids: [ctx.peer.user.id]})

    other_project = project_fixture(ctx.owner.user)
    membership_fixture(other_project, ctx.peer.user, "viewer")
    other_sheet = sheet_fixture(other_project, %{name: ctx.sheet.name})
    other = %{ctx | project: other_project, sheet: other_sheet, author: ctx.owner}
    create_conversation(other, "sheet", %{mention_user_ids: [ctx.peer.user.id]})

    foreign = ideation_fixture()
    foreign = Map.put(foreign, :sheet, sheet_fixture(foreign.project, %{name: ctx.sheet.name}))
    create_conversation(foreign, "sheet")

    opts = [
      project_id: ctx.project.id,
      workspace_id: ctx.project.workspace_id,
      tool: "sheet",
      mentioned: true,
      search: ctx.sheet.name,
      limit: 1,
      include_counts: false
    ]

    {page, queries} = captured_page(ctx.peer, opts)
    assert length(page.threads) == 1
    assert page.next_cursor
    assert page.counts == nil

    [{query, params}] = Enum.filter(queries, fn {query, _} -> String.starts_with?(query, "WITH ") end)
    %{rows: [[[%{"Plan" => plan}]]]} = Repo.query!("EXPLAIN (ANALYZE, FORMAT JSON) " <> query, params)
    nodes = plan_nodes(plan)
    candidate_plan = Enum.find(nodes, &(&1["Subplan Name"] == "CTE comment_search_candidates"))
    assert candidate_plan["Actual Rows"] == 3
    assert candidate_plan["Actual Loops"] == 1
    assert Enum.any?(nodes, &(&1["CTE Name"] == "comment_search_candidates"))

    assert {:ok, next} = Projects.list_comment_conversations(ctx.peer, Keyword.put(opts, :cursor, page.next_cursor))
    assert length(next.threads) == 1
    refute hd(next.threads).id == hd(page.threads).id
  end

  test "a vanished context retains its conversation and a vanished surface has no destination", ctx do
    block = block_fixture(ctx.sheet, %{config: %{"label" => "Motivation"}})
    detail = create_conversation(ctx, "sheet", %{context: %{type: "sheet_block", id: block.id}})
    Repo.delete!(block)

    assert {:ok, %{threads: [context_missing]}} = Projects.list_comment_conversations(ctx.peer)
    assert context_missing.id == detail.thread.id
    assert context_missing.source.status == "available"
    assert context_missing.context.status == "unavailable"
    assert context_missing.destination.surface == "sheet"

    Repo.delete!(ctx.sheet)
    assert {:ok, %{threads: [source_missing], counts: %{all: 1}}} = Projects.list_comment_conversations(ctx.peer)
    assert source_missing.id == detail.thread.id
    assert source_missing.source.status == "unavailable"
    assert is_nil(source_missing.destination)
  end

  test "final authorization recheck removes canonical previews and counts after mid-read revocation", ctx do
    create_conversation(ctx, "sheet")
    create_conversation(ctx, "flow")
    marker = make_ref()
    Process.put(marker, true)

    :ok =
      :telemetry.attach(
        marker,
        [:storyarn, :repo, :query],
        &revoke_during_read/4,
        {self(), marker, ctx.project.id, ctx.peer.user.id}
      )

    try do
      assert {:ok, %{threads: [], next_cursor: nil, counts: %{all: 0}}} =
               Projects.list_comment_conversations(ctx.peer, limit: 1)

      refute Process.get(marker)
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  test "one user subscription receives identity-only changes from all tools, context moves and Ideation visibility",
       ctx do
    assert :ok = Projects.subscribe_comment_conversations(ctx.peer)
    assert :ok = Projects.subscribe_comment_conversations(ctx.peer)
    project_id = ctx.project.id

    for tool <- ~w(flow sheet scene brainstorming) do
      create_conversation(ctx, tool)
      assert_receive {:comment_conversations_changed, ^project_id}
      refute_receive {:comment_conversations_changed, ^project_id}
    end

    detail = create_conversation(ctx, "sheet")
    assert_receive {:comment_conversations_changed, ^project_id}

    assert {:ok, _} =
             Projects.move_comment_thread(
               ctx.author,
               project_id,
               detail.thread.id,
               %{x: 20, y: 250},
               detail.thread.revision
             )

    assert_receive {:comment_conversations_changed, ^project_id}
    Projects.invalidate_ideation_comment_sources(project_id)
    assert_receive {:comment_conversations_changed, ^project_id}

    other = ideation_fixture()
    create_conversation(other, "brainstorming")
    other_id = other.project.id
    refute_receive {:comment_conversations_changed, ^other_id}
  end

  test "rejects malformed filters and cursors before querying", ctx do
    for opts <- [
          nil,
          %{},
          [:bad],
          [project_id: "bad"],
          [project_id: nil],
          [workspace_id: nil],
          [tool: nil],
          [status: nil],
          [search: nil],
          [limit: nil],
          [workspace_id: -1],
          [limit: 0],
          [search: String.duplicate("x", 201)],
          [search: <<0>>],
          [search: <<255>>],
          [tool: "private"],
          [status: "hidden"],
          [participated: "yes"],
          [include_counts: nil],
          [include_counts: "false"],
          [surprise: true]
        ] do
      assert {:error, :invalid_options} = Projects.list_comment_conversations(ctx.peer, opts)
    end

    assert {:error, :invalid_cursor} = Projects.list_comment_conversations(ctx.peer, cursor: %{at: "bad", id: 1})
    assert {:ok, %{threads: [], next_cursor: nil}} = Projects.list_comment_conversations(ctx.peer, cursor: nil)
    assert {:error, :not_found} = Projects.list_comment_conversations(nil)
    assert {:error, :not_found} = Projects.subscribe_comment_conversations(nil)
  end

  test "page projection query count stays bounded as the number of conversations grows", ctx do
    create_conversation(ctx, "sheet")
    {small, queries} = counted_page(ctx.peer)
    assert length(small.threads) == 1
    for _ <- 1..8, do: create_conversation(ctx, "sheet")
    {large, large_queries} = counted_page(ctx.peer)
    assert length(large.threads) == 9
    assert large_queries == queries
  end

  test "subsequent pages can skip counts without changing the authorized rows or cursor", ctx do
    for _ <- 1..3, do: create_conversation(ctx, "sheet")
    opts = [tool: "sheet", search: ctx.sheet.name, limit: 1]
    assert {:ok, first} = Projects.list_comment_conversations(ctx.peer, opts)
    opts = Keyword.put(opts, :cursor, first.next_cursor)
    {counted, queries} = counted_page(ctx.peer, opts)
    {uncounted, fewer_queries} = counted_page(ctx.peer, Keyword.put(opts, :include_counts, false))

    assert counted.counts == %{all: 3, open: 3, resolved: 0}
    assert uncounted.counts == nil
    assert uncounted.threads == counted.threads
    assert uncounted.next_cursor == counted.next_cursor
    assert fewer_queries == queries - 1
  end

  defp counted_page(scope, opts \\ []) do
    marker = make_ref()
    Process.put(marker, 0)
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &count_query/4, {self(), marker})

    try do
      assert {:ok, page} = Projects.list_comment_conversations(scope, opts)
      {page, Process.get(marker)}
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp captured_page(scope, opts) do
    marker = make_ref()
    Process.put(marker, [])
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &capture_query/4, {self(), marker})

    try do
      assert {:ok, page} = Projects.list_comment_conversations(scope, opts)
      {page, Enum.reverse(Process.get(marker))}
    after
      :telemetry.detach(marker)
      Process.delete(marker)
    end
  end

  defp capture_query(_event, _measurements, %{query: query, params: params}, {pid, marker}) do
    if self() == pid, do: Process.put(marker, [{query, params} | Process.get(marker)])
  end

  defp plan_nodes(node), do: [node | Enum.flat_map(Map.get(node, "Plans", []), &plan_nodes/1)]

  defp searchable_contexts(ctx) do
    node = node_fixture(ctx.flow, %{data: %{"text" => "A scoped branch"}})
    block = block_fixture(ctx.sheet, %{config: %{"label" => "A scoped block"}})
    pin = pin_fixture(ctx.scene, %{"label" => "A scoped pin"})
    other_pin = pin_fixture(ctx.scene)
    zone = zone_fixture(ctx.scene, %{"name" => "A scoped zone"})
    annotation = annotation_fixture(ctx.scene, %{"text" => "A scoped annotation"})
    connection = Storyarn.ScenesFixtures.connection_fixture(ctx.scene, pin, other_pin, %{"label" => "A scoped road"})
    blocks = for _ <- 1..2, do: block_fixture(ctx.sheet)
    assert {:ok, group_id} = Storyarn.Sheets.create_column_group(ctx.sheet.id, Enum.map(blocks, & &1.id))

    [
      {"flow", "flow_node", node.id, "scoped branch"},
      {"sheet", "sheet_block", block.id, "scoped block"},
      {"scene", "scene_pin", pin.id, "scoped pin"},
      {"scene", "scene_zone", zone.id, "scoped zone"},
      {"scene", "scene_annotation", annotation.id, "scoped annotation"},
      {"scene", "scene_connection", connection.id, "scoped road"},
      {"sheet", "sheet_title", ctx.sheet.id, "title"},
      {"sheet", "sheet_header", ctx.sheet.id, "header"},
      {"sheet", "sheet_cover", ctx.sheet.id, "cover"},
      {"sheet", "sheet_column_group", group_id, "Row of 2 blocks"}
    ]
  end

  defp count_query(_event, _measurements, _metadata, {pid, marker}) do
    if self() == pid, do: Process.put(marker, Process.get(marker) + 1)
  end

  defp assert_search(ctx, text, id) do
    assert {:ok, %{threads: [thread], counts: %{all: 1}}} =
             Projects.list_comment_conversations(ctx.peer, search: text, limit: 1)

    assert thread.id == id
  end

  defp create_conversation(ctx, tool, overrides \\ %{}, anchor \\ nil) do
    attrs =
      Map.merge(
        %{body: "A discussion to review", client_request_id: Ecto.UUID.generate(), position: %{x: 40, y: 50}},
        overrides
      )

    result =
      case tool do
        "flow" -> Projects.create_flow_canvas_comment(ctx.author, ctx.project.id, ctx.flow.id, attrs)
        "sheet" -> Projects.create_sheet_canvas_comment(ctx.author, ctx.project.id, ctx.sheet.id, attrs)
        "scene" -> Projects.create_scene_canvas_comment(ctx.author, ctx.project.id, ctx.scene.id, attrs)
        "brainstorming" -> Projects.create_ideation_comment(ctx.author, ctx.project.id, ctx.session.id, anchor, attrs)
      end

    assert {:ok, detail} = result
    detail
  end

  defp revoke_during_read(_event, _measurements, %{query: query}, {pid, marker, project_id, user_id}) do
    if self() == pid and String.contains?(query, ~s(FROM "comment_messages")) and Process.delete(marker) do
      Repo.delete_all(from(m in ProjectMembership, where: m.project_id == ^project_id and m.user_id == ^user_id))
    end
  end
end
