defmodule Storyarn.Flows.AvatarIntegrityTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.AssetsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Repo
  alias Storyarn.Sheets

  setup do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    speaker = sheet_fixture(project, %{name: "Speaker"})
    avatar = avatar_fixture(project, user, speaker)

    %{user: user, project: project, flow: flow, speaker: speaker, avatar: avatar}
  end

  test "create_node accepts a project avatar owned by the selected speaker", %{
    flow: flow,
    speaker: speaker,
    avatar: avatar
  } do
    assert {:ok, node} =
             Flows.create_node(flow, %{
               type: "dialogue",
               data: %{
                 "speaker_sheet_id" => Integer.to_string(speaker.id),
                 "avatar_id" => Integer.to_string(avatar.id),
                 "text" => "Hello"
               }
             })

    assert node.data["speaker_sheet_id"] == speaker.id
    assert node.data["avatar_id"] == avatar.id
  end

  test "create_node rejects a cross-project avatar without inserting a node", %{
    user: user,
    flow: flow,
    speaker: speaker
  } do
    foreign_project = project_fixture(user)
    foreign_speaker = sheet_fixture(foreign_project)
    foreign_avatar = avatar_fixture(foreign_project, user, foreign_speaker)

    count_before =
      Repo.aggregate(from(node in FlowNode, where: node.flow_id == ^flow.id), :count)

    assert {:error, {:avatar_project_mismatch, avatar_id}} =
             Flows.create_node(flow, %{
               type: "dialogue",
               data: %{
                 "speaker_sheet_id" => speaker.id,
                 "avatar_id" => foreign_avatar.id,
                 "text" => "Invalid"
               }
             })

    assert avatar_id == foreign_avatar.id
    assert Repo.aggregate(from(node in FlowNode, where: node.flow_id == ^flow.id), :count) == count_before
  end

  test "create_node rejects an avatar owned by another speaker in the project", %{
    user: user,
    project: project,
    flow: flow,
    speaker: speaker
  } do
    other_speaker = sheet_fixture(project)
    other_avatar = avatar_fixture(project, user, other_speaker)

    assert {:error, {:avatar_speaker_mismatch, avatar_id, avatar_sheet_id, requested_speaker_id}} =
             Flows.create_node(flow, %{
               type: "dialogue",
               data: %{
                 "speaker_sheet_id" => speaker.id,
                 "avatar_id" => other_avatar.id,
                 "text" => "Invalid"
               }
             })

    assert avatar_id == other_avatar.id
    assert avatar_sheet_id == other_speaker.id
    assert requested_speaker_id == speaker.id
  end

  test "update_node_data rejects a cross-project avatar and preserves existing JSONB", %{
    user: user,
    flow: flow,
    speaker: speaker
  } do
    node = node_fixture(flow)
    foreign_project = project_fixture(user)
    foreign_speaker = sheet_fixture(foreign_project)
    foreign_avatar = avatar_fixture(foreign_project, user, foreign_speaker)
    original_data = node.data

    assert {:error, {:avatar_project_mismatch, avatar_id}} =
             Flows.update_node_data(
               node,
               Map.merge(node.data, %{
                 "speaker_sheet_id" => speaker.id,
                 "avatar_id" => foreign_avatar.id
               })
             )

    assert avatar_id == foreign_avatar.id
    assert Repo.get!(FlowNode, node.id).data == original_data
  end

  test "update_node rejects a wrong-speaker avatar and preserves existing JSONB", %{
    user: user,
    project: project,
    flow: flow,
    speaker: speaker
  } do
    node = node_fixture(flow)
    other_speaker = sheet_fixture(project)
    other_avatar = avatar_fixture(project, user, other_speaker)
    original_data = node.data

    assert {:error, {:avatar_speaker_mismatch, avatar_id, avatar_sheet_id, requested_speaker_id}} =
             Flows.update_node(node, %{
               data:
                 Map.merge(node.data, %{
                   "speaker_sheet_id" => speaker.id,
                   "avatar_id" => other_avatar.id
                 })
             })

    assert avatar_id == other_avatar.id
    assert avatar_sheet_id == other_speaker.id
    assert requested_speaker_id == speaker.id
    assert Repo.get!(FlowNode, node.id).data == original_data
  end

  test "update_node_data validates the final speaker and avatar together", %{
    user: user,
    project: project,
    flow: flow,
    speaker: speaker,
    avatar: avatar
  } do
    node =
      node_fixture(flow, %{
        data: %{
          "speaker_sheet_id" => speaker.id,
          "avatar_id" => avatar.id,
          "text" => "Before"
        }
      })

    new_speaker = sheet_fixture(project)
    new_avatar = avatar_fixture(project, user, new_speaker)

    assert {:ok, updated, %{renamed_jumps: 0}} =
             Flows.update_node_data(node, %{
               "speaker_sheet_id" => new_speaker.id,
               "avatar_id" => new_avatar.id,
               "text" => "After"
             })

    assert updated.data["speaker_sheet_id"] == new_speaker.id
    assert updated.data["avatar_id"] == new_avatar.id
  end

  defp avatar_fixture(project, user, sheet) do
    asset = image_asset_fixture(project, user)
    {:ok, avatar} = Sheets.add_avatar(sheet, asset.id)
    avatar
  end
end
