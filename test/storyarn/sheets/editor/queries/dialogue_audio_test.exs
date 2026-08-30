defmodule Storyarn.Sheets.DialogueAudioQueryTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Sheets
  alias Storyarn.Sheets.Editor.Projections.FlowNodeRecord

  test "returns only active dialogue lines for the requested project and speaker in Flow-name order" do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = project_fixture(user)
    speaker = sheet_fixture(project, %{name: "Speaker"})
    other_speaker = sheet_fixture(project, %{name: "Other"})
    alpha_flow = flow_fixture(project, %{name: "Alpha"})
    beta_flow = flow_fixture(project, %{name: "Beta"})

    beta_dialogue = dialogue_fixture(beta_flow, speaker, "Beta line")
    alpha_dialogue = dialogue_fixture(alpha_flow, speaker, "Alpha line")
    _other_speaker_dialogue = dialogue_fixture(alpha_flow, other_speaker, "Other line")
    _annotation = node_fixture(alpha_flow, %{type: "annotation", data: %{"text" => "Note"}})

    deleted_node = dialogue_fixture(alpha_flow, speaker, "Deleted line")
    assert {:ok, _deleted_node, _meta} = Flows.delete_node(deleted_node)

    deleted_flow = flow_fixture(project, %{name: "Deleted"})
    _deleted_flow_dialogue = dialogue_fixture(deleted_flow, speaker, "Deleted Flow line")
    assert {:ok, _deleted_flow} = Flows.delete_flow(scope, deleted_flow)

    foreign_project = project_fixture(user)
    foreign_speaker = sheet_fixture(foreign_project, %{name: "Foreign speaker"})
    foreign_flow = flow_fixture(foreign_project, %{name: "Foreign Flow"})
    _foreign_dialogue = dialogue_fixture(foreign_flow, foreign_speaker, "Foreign line")

    lines = Sheets.list_dialogue_audio_lines(project.id, speaker.id)

    assert Enum.map(lines, & &1.id) == [alpha_dialogue.id, beta_dialogue.id]

    assert Enum.map(lines, & &1.flow) == [
             %{id: alpha_flow.id, name: "Alpha", shortcut: alpha_flow.shortcut},
             %{id: beta_flow.id, name: "Beta", shortcut: beta_flow.shortcut}
           ]
  end

  test "preserves the established Sheet facade result after delegating the write to Flows" do
    user = user_fixture()
    project = project_fixture(user)
    speaker = sheet_fixture(project, %{name: "Speaker"})
    flow = flow_fixture(project, %{name: "Dialogue"})
    dialogue = dialogue_fixture(flow, speaker, "Line")
    audio = audio_asset_fixture(project, user)

    assert {:ok, %FlowNodeRecord{} = updated} =
             Sheets.update_dialogue_audio(project.id, speaker.id, dialogue.id, audio.id)

    assert updated.id == dialogue.id
    assert updated.data["audio_asset_id"] == audio.id
  end

  defp dialogue_fixture(flow, speaker, text) do
    node_fixture(flow, %{
      type: "dialogue",
      data: %{"speaker_sheet_id" => speaker.id, "text" => text}
    })
  end
end
