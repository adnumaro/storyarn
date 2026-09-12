defmodule StoryarnWeb.SceneLive.CommentsTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Flows
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.Scene

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    scene = scene_fixture(project, %{name: "Reviewable map"})
    %{project: project, scene: scene, scope: user_scope_fixture(user)}
  end

  test "an editor creates, moves, replies to and resolves a canvas conversation", context do
    view = open_scene(context)

    render_hook(view, "comments_mode", %{active: true})
    assert panel(view)["placing"]

    render_hook(view, "comments_place", %{x: 25, y: 75})
    assert panel(view)["draftPosition"] == %{"x" => 25, "y" => 75}
    assert panel(view)["presentation"] == "canvas"
    refute panel(view)["placing"]

    render_hook(view, "comments_create", %{
      position: %{x: 25, y: 75},
      body: "Clarify what happens in this part of the map",
      client_request_id: Ecto.UUID.generate()
    })

    state = panel(view)
    thread = state["thread"]
    assert thread["source"]["type"] == "scene_canvas"
    assert thread["source"]["scene_id"] == context.scene.id
    assert [%{"body" => "Clarify what happens in this part of the map"}] = state["messages"]
    assert [%{"id" => thread_id, "position" => %{"x" => 25.0, "y" => 75.0}}] = canvas(view)["commentPins"]
    assert thread_id == thread["id"]
    assert canvas(view)["collaboration"]["locks"] == %{}

    render_hook(view, "comments_move", %{
      thread_id: thread["id"],
      x: 40,
      y: 60,
      expected_revision: thread["revision"]
    })

    moved = panel(view)["thread"]
    assert moved["position"] == %{"x" => 40.0, "y" => 60.0}
    assert [%{"position" => %{"x" => 40.0, "y" => 60.0}}] = canvas(view)["commentPins"]

    render_hook(view, "comments_reply", %{
      thread_id: moved["id"],
      parent_id: hd(panel(view)["messages"])["id"],
      body: "The updated position makes the reference clearer",
      client_request_id: Ecto.UUID.generate()
    })

    replied = panel(view)["thread"]
    assert replied["message_count"] == 2
    assert List.last(panel(view)["messages"])["body"] == "The updated position makes the reference clearer"

    render_hook(view, "comments_set_status", %{
      thread_id: replied["id"],
      status: "resolved",
      expected_revision: replied["revision"]
    })

    assert panel(view)["thread"]["status"] == "resolved"
    assert canvas(view)["commentPins"] == []
  end

  test "a deep link opens the spatial conversation and realtime invalidation refreshes it", context do
    detail = create_comment(context)
    view = open_scene(context, "?thread=#{detail.thread.id}")

    assert panel(view)["thread"]["id"] == detail.thread.id
    assert panel(view)["presentation"] == "canvas"
    assert canvas(view)["commentFocusThreadId"] == detail.thread.id
    assert [%{"id" => thread_id}] = canvas(view)["commentPins"]
    assert thread_id == detail.thread.id

    assert {:ok, _reply} =
             Projects.reply_to_comment_thread(context.scope, context.project.id, detail.thread.id, %{
               body: "Another window replied",
               parent_id: hd(detail.messages).id,
               client_request_id: Ecto.UUID.generate()
             })

    assert panel(view)["thread"]["message_count"] == 2
    assert List.last(panel(view)["messages"])["body"] == "Another window replied"
  end

  test "optional pin context persists through movement and can be detached", context do
    pin = pin_fixture(context.scene)
    view = open_scene(context)

    render_hook(view, "comments_create", %{
      position: %{x: 25, y: 75},
      context: %{type: "scene_pin", id: to_string(pin.id), offset: %{x: 2, y: 3}},
      body: "Review this map pin",
      client_request_id: Ecto.UUID.generate()
    })

    thread = panel(view)["thread"]
    assert thread["source"]["type"] == "scene_canvas"
    assert thread["context"]["id"] == to_string(pin.id)
    assert thread["context"]["status"] == "available"

    render_hook(view, "comments_move", %{
      thread_id: thread["id"],
      x: 40,
      y: 60,
      expected_revision: thread["revision"]
    })

    moved = panel(view)["thread"]
    assert moved["context"] == thread["context"]

    render_hook(view, "comments_move", %{
      thread_id: moved["id"],
      x: 45,
      y: 65,
      context: nil,
      expected_revision: moved["revision"]
    })

    detached = panel(view)["thread"]
    assert detached["context"] == nil
    assert detached["source"] == thread["source"]
    assert detached["position"] == %{"x" => 45.0, "y" => 65.0}
  end

  test "a magnetic draft moves between element contexts and persists without duplicating its thread", context do
    pin = pin_fixture(context.scene)
    zone = zone_fixture(context.scene)
    view = open_scene(context)
    reference = %{type: "scene_pin", id: to_string(pin.id), offset: %{x: 2, y: 3}}
    render_hook(view, "comments_place", %{x: 52, y: 53, context: reference})
    placed = panel(view)
    assert placed["draftContext"]["id"] == to_string(pin.id)

    expected_draft = %{
      id: placed["draftId"],
      position: %{x: 52, y: 53},
      context: %{type: "scene_pin", id: to_string(pin.id), offset: %{x: 2.0, y: 3.0}}
    }

    assert_reply(view, %{ok: true, draft: ^expected_draft})

    render_hook(view, "comments_place", %{
      x: 14,
      y: 15,
      moving_draft: true,
      draft_id: placed["draftId"],
      context: %{type: "scene_zone", id: to_string(zone.id), offset: %{x: 4, y: 5}}
    })

    moved = panel(view)
    assert moved["draftId"] == placed["draftId"]
    assert moved["draftContext"]["id"] == to_string(zone.id)

    attrs = %{
      position: moved["draftPosition"],
      context: moved["draftContext"],
      body: "Review the area",
      client_request_id: Ecto.UUID.generate()
    }

    render_hook(view, "comments_create", attrs)
    thread = panel(view)["thread"]
    assert thread["source"]["type"] == "scene_canvas"
    assert thread["source"]["id"] == context.scene.id
    assert thread["context"]["type"] == "scene_zone"
    assert thread["context"]["offset"] == %{"x" => 4.0, "y" => 5.0}
    assert panel(view)["draftContext"] == nil

    render_hook(view, "comments_create", attrs)
    assert panel(view)["thread"]["id"] == thread["id"]
    assert panel(view)["thread"]["message_count"] == 1
    reloaded = open_scene(context, "?thread=#{thread["id"]}")
    assert panel(reloaded)["thread"]["context"] == thread["context"]
  end

  test "canvas draft placement validates its context once without loading the hidden thread list", context do
    pin = pin_fixture(context.scene)
    view = open_scene(context)

    queries =
      capture_queries(view, fn ->
        render_hook(view, "comments_place", %{x: 25, y: 35, context: %{type: "scene_pin", id: pin.id}})
      end)

    assert Enum.count(queries, &(&1.source == "scene_pins")) == 1
    assert Enum.count(queries, &(&1.source == "comment_threads")) == 1
    assert panel(view)["draftContext"]["id"] == to_string(pin.id)

    refresh_queries = capture_queries(view, fn -> render_hook(view, "comments_refresh", %{}) end)
    assert Enum.count(refresh_queries, &(&1.source == "scene_pins")) == 1
    assert Enum.count(refresh_queries, &(&1.source == "comment_threads")) == 1
  end

  test "canvas refresh keeps mention membership fresh and opening the panel loads its threads", context do
    detail = create_comment(context)
    view = open_scene(context)
    render_hook(view, "comments_place", %{x: 25, y: 35})
    assert panel(view)["threads"] == []

    collaborator = user_fixture()
    membership = membership_fixture(context.project, collaborator)
    render_hook(view, "comments_refresh", %{})
    assert Enum.any?(panel(view)["members"], &(&1["id"] == collaborator.id))
    assert panel(view)["threads"] == []

    Repo.delete!(membership)
    render_hook(view, "comments_refresh", %{})
    refute Enum.any?(panel(view)["members"], &(&1["id"] == collaborator.id))

    render_hook(view, "comments_open", %{})
    assert [%{"id" => thread_id}] = panel(view)["threads"]
    assert thread_id == detail.thread.id
  end

  test "refresh removes a canvas draft and its data when the editor loses project access", context do
    editor = user_fixture()
    membership = membership_fixture(context.project, editor)
    pin = pin_fixture(context.scene)
    editor_context = %{context | conn: log_in_user(build_conn(), editor)}
    view = open_scene(editor_context)
    render_hook(view, "comments_place", %{x: 25, y: 35, context: %{type: "scene_pin", id: pin.id}})
    assert panel(view)["draftContext"]

    Repo.delete!(membership)
    render_hook(view, "comments_refresh", %{})

    assert %{
             "draftPosition" => nil,
             "draftContext" => nil,
             "draftId" => nil,
             "threads" => [],
             "members" => [],
             "canComment" => false
           } = panel(view)

    assert canvas(view)["commentPins"] == []
  end

  test "live element deletion detaches a draft without replacing its composer or position", context do
    from_pin = pin_fixture(context.scene)
    to_pin = pin_fixture(context.scene)
    connection = connection_fixture(context.scene, from_pin, to_pin)

    for {type, target, action} <- [
          {"scene_connection", connection, :connection_deleted},
          {"scene_pin", pin_fixture(context.scene), :pin_deleted},
          {"scene_zone", zone_fixture(context.scene), :zone_deleted},
          {"scene_annotation", annotation_fixture(context.scene), :annotation_deleted}
        ] do
      view = open_scene(context)
      render_hook(view, "comments_place", %{x: 25, y: 35, context: %{type: type, id: target.id}})
      placed = panel(view)
      render_hook(view, "comments_refresh", %{})
      assert panel(view)["draftContext"] == placed["draftContext"]
      Repo.delete!(target)
      send(view.pid, {:remote_change, action, %{id: target.id}})
      detached = panel(view)
      assert detached["open"]
      assert detached["draftId"] == placed["draftId"]
      assert detached["draftPosition"] == placed["draftPosition"]
      assert detached["draftContext"] == nil
      assert detached["error"] == nil
    end
  end

  test "local element deletion and undo keep the same conversation with its unavailable context", context do
    pin = pin_fixture(context.scene)
    view = open_scene(context)

    render_hook(view, "comments_create", %{
      position: %{x: 52, y: 53},
      context: %{type: "scene_pin", id: pin.id, offset: %{x: 2, y: 3}},
      body: "Discuss this marker",
      client_request_id: Ecto.UUID.generate()
    })

    thread = panel(view)["thread"]
    render_hook(view, "delete_pin", %{id: pin.id})
    assert panel(view)["thread"]["id"] == thread["id"]
    assert panel(view)["thread"]["context"]["status"] == "unavailable"
    assert panel(view)["thread"]["source"]["status"] == "available"
    assert [%{"body" => "Discuss this marker"}] = panel(view)["messages"]

    render_hook(view, "undo", %{})
    assert panel(view)["thread"]["id"] == thread["id"]
    assert panel(view)["thread"]["context"]["status"] == "unavailable"
    assert panel(view)["thread"]["message_count"] == 1
    assert [comment] = canvas(view)["commentPins"]
    assert comment["id"] == thread["id"]
  end

  test "create racing a context deletion reports the cause and can retry as free placement", context do
    pin = pin_fixture(context.scene)
    view = open_scene(context)
    render_hook(view, "comments_place", %{x: 52, y: 53, context: %{type: "scene_pin", id: pin.id}})
    placed = panel(view)

    attrs = %{
      position: placed["draftPosition"],
      context: placed["draftContext"],
      body: "Keep this draft",
      client_request_id: Ecto.UUID.generate()
    }

    Repo.delete!(pin)
    render_hook(view, "comments_create", attrs)

    assert_reply(view, %{
      ok: false,
      context_unavailable: true,
      error: "The comment context is no longer available. Review the pin's position and try again."
    })

    assert panel(view)["draftContext"] == nil
    assert panel(view)["draftId"] == placed["draftId"]
    assert panel(view)["draftPosition"] == placed["draftPosition"]
    render_hook(view, "comments_create", %{attrs | context: nil})
    assert_reply(view, %{ok: true})
    assert panel(view)["thread"]["context"] == nil
    assert [%{"body" => "Keep this draft"}] = panel(view)["messages"]
  end

  test "late draft moves cannot reopen a closed draft or replace another composer", context do
    pin = pin_fixture(context.scene)
    view = open_scene(context)
    reference = %{type: "scene_pin", id: pin.id}
    render_hook(view, "comments_place", %{x: 10, y: 20, context: reference})
    draft_id = panel(view)["draftId"]
    move = %{x: 30, y: 40, context: nil, moving_draft: true, draft_id: draft_id}
    render_hook(view, "comments_place", move)
    assert panel(view)["draftId"] == draft_id
    assert panel(view)["draftContext"] == nil
    assert_reply(view, %{ok: true, draft: %{id: ^draft_id, position: %{x: 30, y: 40}, context: nil}})
    render_hook(view, "comments_close", %{})
    render_hook(view, "comments_place", move)
    refute panel(view)["open"]
    assert panel(view)["draftPosition"] == nil
    render_hook(view, "comments_place", %{x: 60, y: 70, context: reference})
    current_id = panel(view)["draftId"]
    refute current_id == draft_id
    render_hook(view, "comments_place", move)
    render_hook(view, "comments_place", Map.delete(move, :draft_id))
    assert panel(view)["draftId"] == current_id
    assert panel(view)["draftPosition"] == %{"x" => 60, "y" => 70}
    assert panel(view)["draftContext"]["id"] == to_string(pin.id)
    render_hook(view, "comments_open", %{})
    assert panel(view)["draftContext"] == nil
  end

  test "draft placement validates foreign, deleted and malformed references before opening", context do
    pin = pin_fixture(context.scene)
    foreign_pin = context.project |> scene_fixture() |> pin_fixture()
    deleted_pin = pin_fixture(context.scene)
    Repo.delete!(deleted_pin)
    view = open_scene(context)

    for reference <- [
          %{type: "scene_pin", id: foreign_pin.id},
          %{type: "scene_pin", id: deleted_pin.id},
          %{type: "scene_pin", id: "invalid"},
          %{type: "flow_node", id: pin.id},
          %{type: "scene_pin", id: pin.id, offset: %{x: 10_000_001, y: 0}}
        ] do
      render_hook(view, "comments_place", %{x: 10, y: 20, context: reference})
      assert panel(view)["draftPosition"] == nil
      assert panel(view)["draftContext"] == nil
      assert is_binary(panel(view)["error"])
    end
  end

  test "viewers read conversations but forged comment mutations do not change them", context do
    detail = create_comment(context)
    viewer = user_fixture()
    membership_fixture(context.project, viewer, "viewer")

    view =
      context
      |> Map.put(:conn, log_in_user(build_conn(), viewer))
      |> open_scene("?thread=#{detail.thread.id}")

    assert panel(view)["thread"]["id"] == detail.thread.id
    refute panel(view)["canComment"]

    render_hook(view, "comments_mode", %{active: true})
    refute panel(view)["placing"]

    render_hook(view, "comments_place", %{x: 10, y: 20})
    assert panel(view)["draftPosition"] == nil

    render_hook(view, "comments_move", %{
      thread_id: detail.thread.id,
      x: 10,
      y: 20,
      expected_revision: detail.thread.revision
    })

    render_hook(view, "comments_reply", %{
      thread_id: detail.thread.id,
      parent_id: hd(detail.messages).id,
      body: "Forged viewer reply",
      client_request_id: Ecto.UUID.generate()
    })

    render_hook(view, "comments_set_status", %{
      thread_id: detail.thread.id,
      status: "resolved",
      expected_revision: detail.thread.revision
    })

    assert {:ok, unchanged} =
             Projects.get_comment_thread(context.scope, context.project.id, detail.thread.id)

    assert unchanged.thread.position == %{x: 20.0, y: 30.0}
    assert unchanged.thread.message_count == 1
    assert unchanged.thread.status == "open"
  end

  test "an unavailable Scene keeps its discussion readable and removes its spatial pin", context do
    detail = create_comment(context)
    view = open_scene(context, "?thread=#{detail.thread.id}")

    assert {:ok, _deleted_scene} = Scenes.delete_scene(context.scene)
    send(view.pid, {:scene_comments_changed, context.scene.id})

    state = panel(view)
    assert state["thread"]["id"] == detail.thread.id
    assert state["thread"]["source"]["status"] == "unavailable"
    assert [%{"body" => "Review this area"}] = state["messages"]
    assert state["presentation"] == "panel"
    assert canvas(view)["commentPins"] == []
    assert canvas(view)["commentFocusThreadId"] == nil
  end

  test "Scene comments cannot read or mutate a Flow conversation with the same numeric source ID", context do
    {flow, scene} = colliding_sources(context.project)

    assert {:ok, flow_detail} =
             Projects.create_flow_canvas_comment(context.scope, context.project.id, flow.id, %{
               body: "Flow-only conversation",
               position: %{x: 100, y: 200},
               client_request_id: Ecto.UUID.generate()
             })

    assert {:ok, scene_detail} =
             Projects.create_scene_canvas_comment(context.scope, context.project.id, scene.id, %{
               body: "Scene-only conversation",
               position: %{x: 35, y: 65},
               client_request_id: Ecto.UUID.generate()
             })

    collision_context = %{context | scene: scene}
    view = open_scene(collision_context, "?thread=#{flow_detail.thread.id}")

    assert panel(view)["thread"] == nil
    assert panel(view)["messages"] == []
    assert Enum.map(canvas(view)["commentPins"], & &1["id"]) == [scene_detail.thread.id]

    render_hook(view, "comments_reply", %{
      thread_id: flow_detail.thread.id,
      parent_id: hd(flow_detail.messages).id,
      body: "Wrong editor",
      client_request_id: Ecto.UUID.generate()
    })

    render_hook(view, "comments_move", %{
      thread_id: flow_detail.thread.id,
      x: 5,
      y: 10,
      expected_revision: flow_detail.thread.revision
    })

    assert {:ok, unchanged} =
             Projects.get_comment_thread(context.scope, context.project.id, flow_detail.thread.id)

    assert unchanged.thread.message_count == 1
    assert unchanged.thread.position == %{x: 100.0, y: 200.0}

    linked = open_scene(collision_context, "?thread=#{scene_detail.thread.id}")
    assert panel(linked)["thread"]["id"] == scene_detail.thread.id
    assert panel(linked)["thread"]["source"]["scene_id"] == scene.id
  end

  test "changing between compact and normal layouts reloads comment and collaboration state", context do
    detail = create_comment(context)
    pin = pin_fixture(context.scene)
    path = scene_path(context)

    {:ok, view, _html} = live(context.conn, path <> "?layout=compact")
    compact_canvas = compact_canvas(view)
    refute Map.has_key?(compact_canvas, "commentPins")
    refute Map.has_key?(compact_canvas, "comments")

    render_patch(view, path)
    assert panel(view)["canComment"]
    assert [%{"id" => thread_id}] = canvas(view)["commentPins"]
    assert thread_id == detail.thread.id

    render_hook(view, "select_element", %{"type" => "pin", "id" => pin.id})
    assert {:ok, _lock} = Collaboration.get_lock({:scene, context.scene.id}, pin.id)

    render_patch(view, path <> "?layout=compact")
    assert {:error, :not_locked} = Collaboration.get_lock({:scene, context.scene.id}, pin.id)
    refute Map.has_key?(compact_canvas(view), "commentPins")
  end

  test "a comment deep link to a missing Scene redirects instead of crashing", context do
    missing_scene_id = 9_000_000_000 + System.unique_integer([:positive])

    index_path =
      ~p"/workspaces/#{context.project.workspace.slug}/projects/#{context.project.slug}/scenes"

    assert {:error, {:live_redirect, %{to: ^index_path}}} =
             live(context.conn, "#{index_path}/#{missing_scene_id}?thread=1")
  end

  defp create_comment(context) do
    {:ok, detail} =
      Projects.create_scene_canvas_comment(context.scope, context.project.id, context.scene.id, %{
        body: "Review this area",
        position: %{x: 20, y: 30},
        client_request_id: Ecto.UUID.generate()
      })

    detail
  end

  defp capture_queries(view, fun) do
    marker = make_ref()
    :ok = :telemetry.attach(marker, [:storyarn, :repo, :query], &record_query/4, {self(), view.pid, marker})

    try do
      fun.()
      drain_queries(marker, [])
    after
      :telemetry.detach(marker)
    end
  end

  defp record_query(_event, _measurements, metadata, {recipient, live_view, marker}) do
    if self() == live_view, do: send(recipient, {marker, metadata})
  end

  defp drain_queries(marker, queries) do
    receive do
      {^marker, metadata} -> drain_queries(marker, [metadata | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp colliding_sources(project) do
    flow = flow_with_available_scene_id(project)

    scene =
      %Scene{id: flow.id, project_id: project.id}
      |> Scene.create_changeset(%{
        name: "Colliding Scene",
        shortcut: "colliding-scene-#{flow.id}"
      })
      |> Repo.insert!()

    {flow, scene}
  end

  defp flow_with_available_scene_id(project) do
    unique = System.unique_integer([:positive])
    {:ok, flow} = Flows.create_flow(project, %{name: "Colliding Flow #{unique}"})

    if Repo.get(Scene, flow.id) do
      flow_with_available_scene_id(project)
    else
      flow
    end
  end

  defp open_scene(context, query \\ "") do
    {:ok, view, _html} = live(context.conn, scene_path(context) <> query)
    render_async(view, 5000)
    view
  end

  defp scene_path(context) do
    ~p"/workspaces/#{context.project.workspace.slug}/projects/#{context.project.slug}/scenes/#{context.scene.id}"
  end

  defp panel(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/scene/show/ScenePanels").props["panels"]["comments"]
  end

  defp canvas(view) do
    render(view)
    LiveVue.Test.get_vue(view, name: "live/scene/show/SceneSurface").props["surface"]["canvas"]
  end

  defp compact_canvas(view) do
    render(view)

    LiveVue.Test.get_vue(view, name: "live/scene/show/SceneCompactSurface").props["surface"][
      "canvas"
    ]
  end
end
