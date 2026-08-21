defmodule StoryarnWeb.FlowLive.Handlers.PreviewHandlersTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias StoryarnWeb.FlowLive.Handlers.PreviewHandlers

  describe "handle_start_preview/2" do
    test "resolves integer and string speaker references through the Flows boundary" do
      project = project_fixture(user_fixture())
      flow = flow_fixture(project)
      speaker = sheet_fixture(project, %{name: "Ada Lovelace"})

      for speaker_id <- [speaker.id, to_string(speaker.id)] do
        dialogue = dialogue_fixture(flow, speaker_id)
        socket = build_socket(flow, project)

        assert {:noreply, result} =
                 PreviewHandlers.handle_start_preview(%{"id" => dialogue.id}, socket)

        state = PreviewHandlers.serialize_preview_state(result)
        assert state.open
        assert state.currentNode.speaker == "Ada Lovelace"
        assert state.currentNode.speakerInitials == "AL"
      end
    end

    test "does not resolve a speaker owned by another project" do
      user = user_fixture()
      project = project_fixture(user)
      other_project = project_fixture(user)
      flow = flow_fixture(project)
      foreign_speaker = sheet_fixture(other_project, %{name: "Foreign speaker"})
      dialogue = dialogue_fixture(flow, nil)

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue.id),
        set: [data: Map.put(dialogue.data, "speaker_sheet_id", foreign_speaker.id)]
      )

      assert {:noreply, result} =
               PreviewHandlers.handle_start_preview(%{"id" => dialogue.id}, build_socket(flow, project))

      state = PreviewHandlers.serialize_preview_state(result)
      assert state.currentNode.speaker == nil
      assert state.currentNode.speakerInitials == "?"
    end
  end

  defp dialogue_fixture(flow, speaker_id) do
    node_fixture(flow, %{
      type: "dialogue",
      data: %{
        "text" => "<p>Hello</p>",
        "speaker_sheet_id" => speaker_id,
        "responses" => []
      }
    })
  end

  defp build_socket(flow, project) do
    %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        flow: flow,
        project: project,
        preview_show: false,
        preview_current_node: nil,
        preview_speaker: nil,
        preview_responses: [],
        preview_has_next: false,
        preview_history: []
      }
    }
  end
end
