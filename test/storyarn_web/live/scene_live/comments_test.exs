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
