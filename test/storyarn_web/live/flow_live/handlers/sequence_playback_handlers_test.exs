defmodule StoryarnWeb.FlowLive.Handlers.SequencePlaybackHandlersTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias StoryarnWeb.FlowLive.Handlers.SequencePlaybackHandlers

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flow: flow,
        project: project,
        all_sheets: [],
        can_edit: false,
        selected_node: nil,
        sequence_stage: %{status: "empty"},
        sequence_playback_session: nil,
        sequence_playback: nil,
        debug_state: %{marker: :independent},
        debug_session_id: "unrelated-debug-session"
      }
    }

    %{user: user, project: project, flow: flow, socket: socket}
  end

  test "plays from the chosen intervention, evaluates conditions and waits for a response", ctx do
    first = dialogue(ctx.flow, "First")

    condition =
      node_fixture(ctx.flow, %{
        type: "condition",
        data: %{"condition" => %{"logic" => "all", "rules" => []}}
      })

    choice = dialogue(ctx.flow, "Choose", [response("left"), response("right")])
    ending = node_fixture(ctx.flow, %{type: "exit"})
    connection_fixture(ctx.flow, first, condition)
    connection_fixture(ctx.flow, condition, choice, %{source_pin: "true"})
    connection_fixture(ctx.flow, choice, ending, %{source_pin: "right"})

    started = event(ctx.socket, "start", %{"id" => to_string(first.id)})
    assert started.assigns.sequence_playback.slide.node_id == first.id
    assert started.assigns.sequence_playback.showContinue
    refute started.assigns.sequence_playback.canGoBack

    waiting = event(started, "continue")
    assert waiting.assigns.sequence_playback.slide.node_id == choice.id
    assert Enum.map(waiting.assigns.sequence_playback.slide.responses, & &1.id) == ["left", "right"]
    refute waiting.assigns.sequence_playback.showContinue
    assert event(waiting, "continue").assigns == waiting.assigns

    invalid = event(waiting, "choose", %{"response_id" => "missing"})
    assert invalid.assigns.sequence_playback.error == "invalid_response"
    assert invalid.assigns.sequence_playback_session == waiting.assigns.sequence_playback_session

    finished = event(waiting, "choose", %{"response_id" => "right"})
    assert finished.assigns.sequence_playback.isFinished
    assert finished.assigns.sequence_playback.slide.type == :outcome
    assert finished.assigns.sequence_playback.canGoBack

    back = event(waiting, "back")
    assert back.assigns.sequence_playback.slide.node_id == first.id
    restarted = event(finished, "restart")
    assert restarted.assigns.sequence_playback.slide.node_id == first.id

    stopped = event(restarted, "stop")
    assert stopped.assigns.sequence_playback_session == nil
    assert stopped.assigns.sequence_playback == nil

    assert Map.drop(stopped.assigns, [:__changed__, :sequence_playback_session, :sequence_playback]) ==
             Map.drop(ctx.socket.assigns, [:__changed__, :sequence_playback_session, :sequence_playback])

    assert stopped.redirected == nil
  end

  test "uses project variable defaults without importing debugger state", ctx do
    sheet = sheet_fixture(ctx.project, %{name: "Hero"})
    block_fixture(sheet, %{type: "number", config: %{"label" => "Health"}, value: %{"content" => "42"}})
    first = dialogue(ctx.flow, "<p>{#{sheet.shortcut}.health}</p>")
    started = event(ctx.socket, "start", %{"id" => first.id})

    assert started.assigns.sequence_playback_session.state.variables["#{sheet.shortcut}.health"].value == 42
    assert started.assigns.sequence_playback.slide.text =~ "42"
    assert started.assigns.debug_state == ctx.socket.assigns.debug_state
  end

  test "rejects nodes outside the current Flow and non-dialogue nodes", ctx do
    foreign = node_fixture(flow_fixture(ctx.project))
    entry = Enum.find(Flows.list_nodes(ctx.flow.id), &(&1.type == "entry"))

    for id <- [foreign.id, entry.id, "invalid", %{}, -1] do
      assert event(ctx.socket, "start", %{"id" => id}).assigns == ctx.socket.assigns
    end

    for action <- ~w(continue choose back restart unknown) do
      assert event(ctx.socket, action).assigns == ctx.socket.assigns
    end
  end

  test "retains inherited visuals and music while voice changes between interventions", ctx do
    image = image_asset_fixture(ctx.project, ctx.user)
    audio = audio_asset_fixture(ctx.project, ctx.user)
    first = dialogue(ctx.flow, "First", [], audio.id)
    second = dialogue(ctx.flow, "Second", [], audio.id)
    connection_fixture(ctx.flow, first, second)
    assert {:ok, _} = Flows.set_composition_source(second.id, first.id)

    assert {:ok, layer} =
             Flows.create_sequence_visual_layer(first.id, %{kind: "character", asset_id: image.id})

    assert {:ok, _} = Flows.upsert_sequence_track(first.id, "music", %{asset_id: audio.id, volume: 0.5})

    started = event(ctx.socket, "start", %{"id" => first.id})
    state = started.assigns.sequence_playback
    assert [%{id: layer_key, url: image_url}] = state.visualLayers
    assert layer_key == layer.layer_key
    assert image_url == "/media/assets/#{image.id}"
    assert [%{volume: 0.5, kind: "music"}] = state.audioTracks
    assert state.voice.url == "/media/assets/#{audio.id}"

    continued = event(started, "continue")
    next = continued.assigns.sequence_playback
    assert next.audioTracks == state.audioTracks
    assert next.voice.url == state.voice.url
    refute next.voice.key == state.voice.key
    assert next.visualLayers == state.visualLayers

    restarted = event(started, "restart")
    refute restarted.assigns.sequence_playback.voice.key == state.voice.key
  end

  test "cross-flow runtime transitions leave the editor Flow and route unchanged", ctx do
    first = dialogue(ctx.flow, "Root")
    child_flow = flow_fixture(ctx.project)
    child = dialogue(child_flow, "Child")
    child_entry = Enum.find(Flows.list_nodes(child_flow.id), &(&1.type == "entry"))
    subflow = node_fixture(ctx.flow, %{type: "subflow", data: %{"referenced_flow_id" => child_flow.id}})
    connection_fixture(ctx.flow, first, subflow)
    connection_fixture(child_flow, child_entry, child)

    started = event(ctx.socket, "start", %{"id" => first.id})
    continued = event(started, "continue")
    assert continued.assigns.sequence_playback.slide.node_id == child.id
    assert continued.assigns.sequence_playback_session.flow.id == child_flow.id
    assert continued.assigns.flow.id == ctx.flow.id
    assert continued.redirected == nil

    restarted = event(continued, "restart")
    assert restarted.assigns.sequence_playback.slide.node_id == first.id
    assert restarted.assigns.sequence_playback_session.flow.id == ctx.flow.id
  end

  test "does not expose a foreign or non-audio asset stored in malformed dialogue data", ctx do
    foreign_audio = audio_asset_fixture(project_fixture(ctx.user), ctx.user)
    image = image_asset_fixture(ctx.project, ctx.user)

    for asset <- [foreign_audio, image] do
      malformed = raw_node_fixture(ctx.flow, %{data: %{"text" => "Voice", "audio_asset_id" => asset.id}})
      started = event(ctx.socket, "start", %{"id" => malformed.id})
      assert started.assigns.sequence_playback.voice == nil
    end
  end

  defp event(socket, action, params \\ %{}) do
    assert {:noreply, result} = SequencePlaybackHandlers.handle_event(Map.put(params, "action", action), socket)
    result
  end

  defp dialogue(flow, text, responses \\ [], audio_id \\ nil) do
    node_fixture(flow, %{
      type: "dialogue",
      data: %{"text" => text, "responses" => responses, "audio_asset_id" => audio_id}
    })
  end

  defp response(id), do: %{"id" => id, "text" => id, "condition" => ""}
end
