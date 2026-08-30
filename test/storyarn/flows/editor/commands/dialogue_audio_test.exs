defmodule Storyarn.Flows.DialogueAudioTest do
  use Storyarn.DataCase, async: false

  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.NodeUpdate
  alias Storyarn.Platform.Collaboration

  setup do
    user = user_fixture()
    scope = user_scope_fixture(user)
    project = project_fixture(user)
    sheet = sheet_fixture(project, %{name: "Speaker"})
    flow = flow_fixture(project, %{name: "Dialogue"})

    node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => sheet.id,
          "text" => "Keep this line",
          "stage_directions" => "Keep this direction"
        }
      })

    %{flow: flow, node: node, project: project, scope: scope, sheet: sheet, user: user}
  end

  describe "assign_dialogue_audio/4" do
    test "assigns a same-project audio asset and preserves every unrelated field", context do
      audio = audio_asset_fixture(context.project, context.user)

      assert {:ok, updated} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 audio.id
               )

      persisted = Flows.get_node!(context.flow.id, context.node.id)

      assert %{
               node_id: returned_node_id,
               audio_asset_id: returned_audio_id,
               node_snapshot: committed_snapshot
             } = updated

      assert returned_node_id == context.node.id
      assert returned_audio_id == audio.id
      assert committed_snapshot.id == context.node.id
      assert committed_snapshot.data["audio_asset_id"] == audio.id
      assert persisted.data["audio_asset_id"] == audio.id
      assert persisted.data["text"] == "Keep this line"
      assert persisted.data["stage_directions"] == "Keep this direction"

      assert persisted.derivatives_fingerprint ==
               NodeUpdate.derivatives_fingerprint(persisted.type, persisted.data)
    end

    test "returns the state committed by this command, not a later assignment", context do
      first_audio = audio_asset_fixture(context.project, context.user)
      second_audio = audio_asset_fixture(context.project, context.user)

      assert {:ok, first_receipt} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 first_audio.id
               )

      assert {:ok, second_receipt} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 second_audio.id
               )

      assert first_receipt.audio_asset_id == first_audio.id
      assert first_receipt.node_snapshot.data["audio_asset_id"] == first_audio.id
      assert second_receipt.audio_asset_id == second_audio.id
      assert second_receipt.node_snapshot.data["audio_asset_id"] == second_audio.id
      assert Flows.get_node!(context.flow.id, context.node.id).data["audio_asset_id"] == second_audio.id
    end

    test "clears audio without removing or rewriting unrelated node data", context do
      audio = audio_asset_fixture(context.project, context.user)

      assert {:ok, _node} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 audio.id
               )

      assert {:ok, _node} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 nil
               )

      persisted = Flows.get_node!(context.flow.id, context.node.id)
      assert persisted.data["audio_asset_id"] == nil
      assert persisted.data["text"] == "Keep this line"
      assert persisted.data["stage_directions"] == "Keep this direction"
    end

    test "rejects missing, foreign, deleted and non-audio assets", context do
      foreign_project = project_fixture(context.user)
      foreign_audio = audio_asset_fixture(foreign_project, context.user)
      image = image_asset_fixture(context.project, context.user)
      deleted_audio = audio_asset_fixture(context.project, context.user)
      {:ok, _deleted} = Storyarn.Projects.Assets.delete_asset(deleted_audio)

      for asset_id <- [-1, 9_999_999, foreign_audio.id, deleted_audio.id, image.id] do
        assert {:error, {:invalid_project_reference, :audio_asset_id, ^asset_id}} =
                 Flows.assign_dialogue_audio(
                   context.project.id,
                   context.sheet.id,
                   context.node.id,
                   asset_id
                 )
      end

      persisted = Flows.get_node!(context.flow.id, context.node.id)
      refute Map.has_key?(persisted.data, "audio_asset_id")
    end

    test "rejects identifiers outside PostgreSQL bigint range without querying or crashing", context do
      too_large = 9_223_372_036_854_775_808

      assert {:error, :not_found} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 too_large,
                 nil
               )

      assert {:error, {:invalid_project_reference, :audio_asset_id, ^too_large}} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 too_large
               )
    end

    test "does not reveal nodes from another project, speaker, type or deleted Flow", context do
      other_sheet = sheet_fixture(context.project, %{name: "Other speaker"})
      annotation = node_fixture(context.flow, %{type: "annotation", data: %{"text" => "Note"}})

      assert {:error, :not_found} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 other_sheet.id,
                 context.node.id,
                 nil
               )

      assert {:error, :not_found} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 annotation.id,
                 nil
               )

      foreign_project = project_fixture(context.user)

      assert {:error, :not_found} =
               Flows.assign_dialogue_audio(
                 foreign_project.id,
                 context.sheet.id,
                 context.node.id,
                 nil
               )

      assert {:ok, _deleted_flow} = Flows.delete_flow(context.scope, context.flow)

      assert {:error, :not_found} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 nil
               )
    end

    test "broadcasts the existing dashboard invalidation only after success", context do
      audio = audio_asset_fixture(context.project, context.user)
      :ok = Collaboration.subscribe_dashboard(context.project.id)

      assert {:error, {:invalid_project_reference, :audio_asset_id, -1}} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 -1
               )

      refute_receive {:dashboard_invalidate, :flows}, 50

      assert {:ok, _node} =
               Flows.assign_dialogue_audio(
                 context.project.id,
                 context.sheet.id,
                 context.node.id,
                 audio.id
               )

      assert_receive {:dashboard_invalidate, :flows}
    end
  end
end
