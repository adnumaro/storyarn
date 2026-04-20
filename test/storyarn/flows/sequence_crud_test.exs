defmodule Storyarn.Flows.SequenceCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
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

      assert seq.tracks |> Map.keys() |> Enum.sort() == Enum.sort(Sequence.track_keys())
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

      ids = flow.id |> Flows.list_sequences() |> Enum.map(& &1.id) |> Enum.sort()
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

      assert tracks |> Map.keys() |> Enum.sort() ==
               ~w(audio_ambient audio_music audio_sfx video_bg video_overlay)

      assert Enum.all?(tracks, fn {_, v} -> v == [] end)
    end
  end

  describe "create_sequence_from_node/2 atomic" do
    test "creates sequence AND sets node's sequence_directive in one transaction" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()

      assert {:ok, %Sequence{} = seq} =
               Flows.create_sequence_from_node(entry, %{"name" => "Castle Intro"})

      assert seq.name == "Castle Intro"
      assert seq.flow_id == flow.id
      assert seq.start_node_id == entry.id

      refetched = Storyarn.Repo.get!(FlowNode, entry.id)
      assert refetched.data["sequence_directive"] == seq.id
    end

    test "overwrites an existing sequence_directive on the node" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, first} = Flows.create_sequence_from_node(entry, %{"name" => "A"})

      {:ok, second} = Flows.create_sequence_from_node(entry, %{"name" => "B"})

      refetched = Storyarn.Repo.get!(FlowNode, entry.id)
      assert refetched.data["sequence_directive"] == second.id
      refute first.id == second.id
      # Both sequences exist (first is not deleted, just orphaned from this node)
      assert Flows.get_sequence(flow.id, first.id).id == first.id
      assert Flows.get_sequence(flow.id, second.id).id == second.id
    end

    test "rolls back if sequence creation fails (missing name)" do
      %{entry_node: entry} = setup_flow_with_node()

      assert {:error, cs} = Flows.create_sequence_from_node(entry, %{})
      assert %{name: ["can't be blank"]} = errors_on(cs)

      refetched = Storyarn.Repo.get!(FlowNode, entry.id)
      refute refetched.data["sequence_directive"]
    end
  end

  describe "delete_sequence/1 sweeps node sequence_directive pointers" do
    test "nullifies sequence_directive on nodes of the same flow" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, seq} = Flows.create_sequence(flow.id, entry.id, %{"name" => "S"})

      # Point the entry node's sequence_directive at the sequence
      {:ok, entry_with_directive} =
        entry
        |> FlowNode.data_changeset(%{
          data: Map.put(entry.data, "sequence_directive", seq.id)
        })
        |> Storyarn.Repo.update()

      assert entry_with_directive.data["sequence_directive"] == seq.id

      {:ok, _deleted} = Flows.delete_sequence(seq)

      # After delete, the pointer should be nil (key preserved)
      refetched = Storyarn.Repo.get!(FlowNode, entry.id)
      assert Map.has_key?(refetched.data, "sequence_directive")
      assert refetched.data["sequence_directive"] == nil
    end

    test "does not touch pointers to OTHER sequences" do
      %{flow: flow, entry_node: entry} = setup_flow_with_node()
      {:ok, seq_a} = Flows.create_sequence(flow.id, entry.id, %{"name" => "A"})
      {:ok, seq_b} = Flows.create_sequence(flow.id, entry.id, %{"name" => "B"})

      # Entry points at seq_b
      {:ok, _} =
        entry
        |> FlowNode.data_changeset(%{
          data: Map.put(entry.data, "sequence_directive", seq_b.id)
        })
        |> Storyarn.Repo.update()

      # Delete seq_a
      {:ok, _} = Flows.delete_sequence(seq_a)

      # Entry's pointer to seq_b is untouched
      refetched = Storyarn.Repo.get!(FlowNode, entry.id)
      assert refetched.data["sequence_directive"] == seq_b.id
    end

    test "does not touch pointers in OTHER flows" do
      %{flow: flow_a, entry_node: entry_a} = setup_flow_with_node()
      %{entry_node: entry_b} = setup_flow_with_node()

      {:ok, seq_a} = Flows.create_sequence(flow_a.id, entry_a.id, %{"name" => "SA"})

      # An entry node in flow_b somehow has an orphan pointer to seq_a (e.g. import bug)
      {:ok, _} =
        entry_b
        |> FlowNode.data_changeset(%{
          data: Map.put(entry_b.data, "sequence_directive", seq_a.id)
        })
        |> Storyarn.Repo.update()

      {:ok, _} = Flows.delete_sequence(seq_a)

      # Sweep scopes to flow_id — the cross-flow orphan is left alone
      # (it's the export validator's job to flag such orphans).
      refetched = Storyarn.Repo.get!(FlowNode, entry_b.id)
      assert refetched.data["sequence_directive"] == seq_a.id
    end
  end
end
