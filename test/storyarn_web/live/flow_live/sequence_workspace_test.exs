defmodule StoryarnWeb.FlowLive.SequenceWorkspaceTest do
  use StoryarnWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Repo

  setup :register_and_log_in_user

  setup %{user: user} do
    project = user |> project_fixture() |> Repo.preload(:workspace)
    flow = flow_fixture(project)
    first = node_fixture(flow, %{type: "dialogue", data: %{"text" => "First", "responses" => []}})
    second = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Second", "responses" => []}})
    connection_fixture(flow, first, second)
    {:ok, _} = Flows.set_composition_source(second.id, first.id)
    %{project: project, flow: flow, first: first, second: second}
  end

  test "a dialogue edits inherited audio, records undo, removes and restores it", context do
    asset = audio_asset_fixture(context.project, context.user)
    {:ok, track} = Flows.upsert_sequence_track(context.first.id, "music", %{asset_id: asset.id})
    view = open(context)
    render_hook(view, "node_selected", %{id: context.second.id})
    render_hook(view, "set_sequence_workspace", %{open: true})
    assert [%{"trackKey" => key, "inherited" => true}] = data(view)["tracks"]
    assert key == track.track_key
    render_hook(view, "override_sequence_track", %{id: context.second.id, track_key: key, volume: 0.3})
    assert_push_event(view, "sequence_composition_changed", %{previous: previous, current: current})
    assert current["version"] == 2
    assert [%{"volume" => 0.3}] = data(view)["tracks"]

    render_hook(view, "restore_sequence_composition", %{
      id: context.second.id,
      snapshot: previous,
      expected_current: current
    })

    assert [%{"volume" => 1.0}] = data(view)["tracks"]
    render_hook(view, "remove_sequence_track", %{id: context.second.id, track_key: key})
    assert data(view)["tracks"] == []
    assert [%{"trackKey" => ^key}] = data(view)["removed_tracks"]
    render_hook(view, "restore_sequence_track", %{id: context.second.id, track_key: key})
    assert [%{"trackKey" => ^key}] = data(view)["tracks"]
    assert [%{volume: volume}] = Flows.list_sequence_tracks(context.first.id)
    assert Decimal.equal?(volume, 1)
  end

  test "content locale follows inline playback, back and restart without writing source text", context do
    source_language_fixture(context.project, %{locale_code: "en", name: "English"})
    language_fixture(context.project, %{locale_code: "es", name: "Spanish"})

    for {node, translated} <- [{context.first, "Primero"}, {context.second, "Segundo"}] do
      row =
        localized_text_fixture(context.project.id, %{
          project_id: context.project.id,
          source_type: "flow_node",
          source_id: node.id,
          source_field: "text",
          locale_code: "es",
          source_text: node.data["text"],
          translated_text: translated,
          status: "draft"
        })

      assert row.translated_text == translated
    end

    view = open(context)
    render_hook(view, "node_selected", %{id: context.first.id})
    render_hook(view, "set_sequence_workspace", %{open: true})
    render_hook(view, "set_sequence_content_locale", %{locale: "es"})
    assert surface(view)["stage"]["intervention"]["text"] == "Primero"
    render_hook(view, "sequence_playback", %{action: "start", id: context.first.id})
    assert surface(view)["sequencePlayback"]["slide"]["text"] == "Primero"
    render_hook(view, "sequence_playback", %{action: "continue"})
    assert surface(view)["sequencePlayback"]["slide"]["text"] == "Segundo"
    render_hook(view, "sequence_playback", %{action: "back"})
    assert surface(view)["sequencePlayback"]["slide"]["text"] == "Primero"
    render_hook(view, "sequence_playback", %{action: "restart"})
    assert surface(view)["sequencePlayback"]["contentLocale"] == "es"
    render_hook(view, "set_sequence_content_locale", %{locale: "not-a-project-language"})
    assert surface(view)["sequencePlayback"]["contentLocale"] == "es"
    render_hook(view, "set_sequence_content_locale", %{locale: "en"})
    assert surface(view)["sequencePlayback"]["slide"]["text"] == "First"
    assert Flows.get_node!(context.flow.id, context.first.id).data["text"] == "First"
  end

  test "debug displays the executed composition instead of the selected dialogue", context do
    entry = Enum.find(Flows.list_nodes(context.flow.id), &(&1.type == "entry"))
    connection_fixture(context.flow, entry, context.first)
    view = open(context)
    render_hook(view, "node_selected", %{id: context.second.id})
    render_hook(view, "debug_start", %{})
    render_hook(view, "debug_step", %{})
    assert surface(view)["debug"]["composition"]["presentationNodeId"] == context.first.id
    assert surface(view)["stage"]["intervention"]["nodeId"] == context.first.id
    render_hook(view, "debug_tab_change", %{tab: "composition"})
    assert surface(view)["debug"]["controls"]["activeTab"] == "composition"
    render_hook(view, "debug_stop", %{})
    assert surface(view)["stage"]["intervention"]["nodeId"] == context.second.id
  end

  test "remote audio changes refresh Debug even when no composition is selected", context do
    entry = Enum.find(Flows.list_nodes(context.flow.id), &(&1.type == "entry"))
    connection_fixture(context.flow, entry, context.first)
    asset = audio_asset_fixture(context.project, context.user)
    view = open(context)
    render_hook(view, "debug_start", %{})
    render_hook(view, "debug_step", %{})
    assert surface(view)["debug"]["composition"]["audioTracks"] == []
    {:ok, track} = Flows.upsert_sequence_track(context.first.id, "music", %{asset_id: asset.id})
    send(view.pid, {:remote_change, :sequence_track_upserted, %{sequence_id: context.first.id}})
    assert [%{"trackKey" => key}] = surface(view)["debug"]["composition"]["audioTracks"]
    assert key == track.track_key
    render_hook(view, "set_sequence_workspace", %{open: true})
    render_hook(view, "sequence_playback", %{action: "start", id: context.first.id})
    assert surface(view)["sequencePlayback"] == nil
  end

  defp open(context) do
    {:ok, view, _} =
      live(
        context.conn,
        ~p"/workspaces/#{context.project.workspace.slug}/projects/#{context.project.slug}/flows/#{context.flow.id}"
      )

    render_async(view, 5000)
    view
  end

  defp surface(view), do: LiveVue.Test.get_vue(view, name: "live/flow/show/FlowSurface").props["surface"]
  defp data(view), do: surface(view)["sequenceWorkspace"]["data"]
end
