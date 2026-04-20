defmodule Storyarn.Flows.SequenceCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.Sequence

  defp setup_flow_with_node(_ctx \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    entry = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
    %{flow: flow, entry_node: entry}
  end

  describe "create_sequence/3" do
    test "creates a sequence with name, flow_id, and start_node_id" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()

      assert {:ok, %Sequence{} = seq} =
               Flows.create_sequence(flow.id, entry.id, %{"name" => "Castle Throne"})

      assert seq.name == "Castle Throne"
      assert seq.flow_id == flow.id
      assert seq.start_node_id == entry.id
      assert is_nil(seq.deleted_at)
    end

    test "defaults tracks to the 5 empty fixed track keys" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()

      {:ok, seq} = Flows.create_sequence(flow.id, entry.id, %{"name" => "s"})

      assert Map.keys(seq.tracks) |> Enum.sort() == Enum.sort(Sequence.track_keys())
      assert Enum.all?(seq.tracks, fn {_k, v} -> v == [] end)
    end

    test "accepts explicit tracks map" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()

      custom = %{"video_bg" => [%{"asset_id" => 1}]}

      {:ok, seq} =
        Flows.create_sequence(flow.id, entry.id, %{"name" => "s", "tracks" => custom})

      assert seq.tracks == custom
    end

    test "rejects missing name" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      assert {:error, cs} = Flows.create_sequence(flow.id, entry.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(cs)
    end

    test "rejects broken flow_id FK" do
      %{entry_node: entry} = setup_flow_with_node()

      assert {:error, cs} = Flows.create_sequence(-1, entry.id, %{"name" => "s"})
      assert %{flow_id: ["does not exist"]} = errors_on(cs)
    end
  end

  describe "get_sequence/2 and list_sequences/1" do
    test "lists active sequences for the flow" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, a} = Flows.create_sequence(flow.id, entry.id, %{"name" => "A"})
      {:ok, b} = Flows.create_sequence(flow.id, entry.id, %{"name" => "B"})

      ids = Flows.list_sequences(flow.id) |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([a.id, b.id])
    end

    test "excludes soft-deleted from list_sequences" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, a} = Flows.create_sequence(flow.id, entry.id, %{"name" => "A"})
      {:ok, _} = Flows.delete_sequence(a)

      assert Flows.list_sequences(flow.id) == []
      assert [%Sequence{id: id}] = Flows.list_deleted_sequences(flow.id)
      assert id == a.id
    end

    test "get_sequence returns nil for soft-deleted" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, s} = Flows.create_sequence(flow.id, entry.id, %{"name" => "A"})
      {:ok, _} = Flows.delete_sequence(s)

      assert Flows.get_sequence(flow.id, s.id) == nil
    end
  end

  describe "update_sequence/2" do
    test "updates name and tracks" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, seq} = Flows.create_sequence(flow.id, entry.id, %{"name" => "old"})

      new_tracks = %{"audio_music" => [%{"asset_id" => 5}]}
      assert {:ok, updated} = Flows.update_sequence(seq, %{"name" => "new", "tracks" => new_tracks})

      assert updated.name == "new"
      assert updated.tracks == new_tracks
    end

    test "does NOT update flow_id or start_node_id (immutable)" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, seq} = Flows.create_sequence(flow.id, entry.id, %{"name" => "s"})

      {:ok, updated} =
        Flows.update_sequence(seq, %{
          "flow_id" => -1,
          "start_node_id" => -1,
          "name" => "s2"
        })

      assert updated.flow_id == flow.id
      assert updated.start_node_id == entry.id
    end
  end

  describe "delete_sequence/1 and restore_sequence/1" do
    test "soft-delete sets deleted_at; restore clears it" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, seq} = Flows.create_sequence(flow.id, entry.id, %{"name" => "s"})

      {:ok, deleted} = Flows.delete_sequence(seq)
      assert %DateTime{} = deleted.deleted_at

      {:ok, restored} = Flows.restore_sequence(deleted)
      assert is_nil(restored.deleted_at)
      assert Flows.get_sequence(flow.id, restored.id).id == seq.id
    end
  end

  describe "cascade behavior" do
    test "deleting the parent flow hard-deletes its sequences" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, seq} = Flows.create_sequence(flow.id, entry.id, %{"name" => "s"})

      # Hard delete the flow (bypassing soft delete) to verify ON DELETE CASCADE
      Storyarn.Repo.delete!(flow)

      assert Storyarn.Repo.get(Sequence, seq.id) == nil
    end
  end

  describe "Sequence.empty_tracks/0" do
    test "returns all 5 fixed keys with empty lists" do
      tracks = Sequence.empty_tracks()
      assert Map.keys(tracks) |> Enum.sort() ==
               ~w(audio_ambient audio_music audio_sfx video_bg video_overlay)
      assert Enum.all?(tracks, fn {_, v} -> v == [] end)
    end
  end
end
