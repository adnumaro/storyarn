defmodule Storyarn.Flows.SequenceCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Flows
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.SequenceConfig
  alias Storyarn.Flows.SequenceTrack
  alias Storyarn.Repo

  defp setup_flow(_ctx \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{flow: flow, project: project, user: user}
  end

  describe "create_sequence/2" do
    test "creates a sequence flow_node + sequence_config" do
      %{flow: flow} = setup_flow()

      assert {:ok, %FlowNode{type: "sequence"} = seq} =
               Flows.create_sequence(flow.id, %{"name" => "Castle Throne"})

      assert seq.flow_id == flow.id
      assert is_nil(seq.parent_id)
      assert is_nil(seq.deleted_at)
      assert %SequenceConfig{name: "Castle Throne"} = seq.sequence_config
    end

    test "defaults canvas geometry" do
      %{flow: flow} = setup_flow()

      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert seq.position_x == 0.0
      assert seq.position_y == 0.0
      assert seq.sequence_config.width == 300.0
      assert seq.sequence_config.height == 200.0
    end

    test "accepts explicit canvas geometry" do
      %{flow: flow} = setup_flow()

      {:ok, seq} =
        Flows.create_sequence(flow.id, %{
          "name" => "s",
          "position_x" => 120.0,
          "position_y" => 80.0,
          "width" => 500.0,
          "height" => 350.0
        })

      assert seq.position_x == 120.0
      assert seq.position_y == 80.0
      assert seq.sequence_config.width == 500.0
      assert seq.sequence_config.height == 350.0
    end

    test "accepts parent_id for nesting (parent must be a sequence)" do
      %{flow: flow} = setup_flow()

      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "outer"})

      {:ok, inner} =
        Flows.create_sequence(flow.id, %{"name" => "inner", "parent_id" => outer.id})

      assert inner.parent_id == outer.id
    end

    test "rejects missing name" do
      %{flow: flow} = setup_flow()
      assert {:error, cs} = Flows.create_sequence(flow.id, %{})
      assert %{name: ["can't be blank"]} = errors_on(cs)
    end

    test "rejects broken flow_id FK" do
      assert {:error, cs} = Flows.create_sequence(-1, %{"name" => "s"})
      assert %{flow_id: ["does not exist"]} = errors_on(cs)
    end

    test "rejects parent_id pointing to a non-sequence node (DB trigger)" do
      %{flow: flow} = setup_flow()
      non_seq = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})

      assert_raise Postgrex.Error, ~r/only sequence nodes can be parents/, fn ->
        Flows.create_sequence(flow.id, %{"name" => "bad", "parent_id" => non_seq.id})
      end
    end
  end

  describe "get_sequence/2 and list_sequences/1" do
    test "lists active sequences for the flow" do
      %{flow: flow} = setup_flow()
      {:ok, a} = Flows.create_sequence(flow.id, %{"name" => "A"})
      {:ok, b} = Flows.create_sequence(flow.id, %{"name" => "B"})

      ids = flow.id |> Flows.list_sequences() |> Enum.map(& &1.id) |> Enum.sort()
      assert ids == Enum.sort([a.id, b.id])
    end

    test "ignores non-sequence flow_nodes" do
      %{flow: flow} = setup_flow()
      _non_seq = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "S"})

      assert [%FlowNode{id: id}] = Flows.list_sequences(flow.id)
      assert id == seq.id
    end

    test "excludes soft-deleted from list_sequences" do
      %{flow: flow} = setup_flow()
      {:ok, a} = Flows.create_sequence(flow.id, %{"name" => "A"})
      {:ok, _} = Flows.delete_sequence(a)

      assert Flows.list_sequences(flow.id) == []
      assert [%FlowNode{id: id}] = Flows.list_deleted_sequences(flow.id)
      assert id == a.id
    end

    test "get_sequence returns nil for soft-deleted" do
      %{flow: flow} = setup_flow()
      {:ok, s} = Flows.create_sequence(flow.id, %{"name" => "A"})
      {:ok, _} = Flows.delete_sequence(s)

      assert Flows.get_sequence(flow.id, s.id) == nil
    end

    test "get_sequence preloads sequence_config" do
      %{flow: flow} = setup_flow()
      {:ok, s} = Flows.create_sequence(flow.id, %{"name" => "A"})

      refetched = Flows.get_sequence(flow.id, s.id)
      assert %SequenceConfig{name: "A"} = refetched.sequence_config
    end
  end

  describe "update_sequence/2" do
    test "updates name/width/height (on config) and position/parent_id (on node)" do
      %{flow: flow} = setup_flow()
      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "outer"})
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "old"})

      assert {:ok, updated} =
               Flows.update_sequence(seq, %{
                 "name" => "new",
                 "position_x" => 50.0,
                 "width" => 450.0,
                 "parent_id" => outer.id
               })

      assert updated.sequence_config.name == "new"
      assert updated.sequence_config.width == 450.0
      assert updated.position_x == 50.0
      assert updated.parent_id == outer.id
    end

    test "does NOT update flow_id or type (both immutable from the update attr set)" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      {:ok, updated} = Flows.update_sequence(seq, %{"flow_id" => -1, "name" => "s2"})

      assert updated.flow_id == flow.id
      assert updated.type == "sequence"
    end

    test "updates background media fields (asset/position/fit) on config" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      {:ok, updated} =
        Flows.update_sequence(seq, %{
          "name" => "s",
          "background_asset_id" => asset.id,
          "background_position" => "top-right",
          "background_fit" => "contain"
        })

      assert updated.sequence_config.background_asset_id == asset.id
      assert updated.sequence_config.background_position == "top-right"
      assert updated.sequence_config.background_fit == "contain"
    end

    test "rejects background_position outside the 9-value whitelist" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert {:error, changeset} =
               Flows.update_sequence(seq, %{
                 "name" => "s",
                 "background_position" => "diagonal-upward"
               })

      assert %{background_position: ["is invalid"]} = errors_on(changeset)
    end

    test "rejects background_fit outside the cover/contain/fill whitelist" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert {:error, changeset} =
               Flows.update_sequence(seq, %{"name" => "s", "background_fit" => "stretch"})

      assert %{background_fit: ["is invalid"]} = errors_on(changeset)
    end
  end

  describe "sequence tracks (audio)" do
    test "upsert creates a track row for (sequence, kind) when none exists" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      assert {:ok, %SequenceTrack{} = track} =
               Flows.upsert_sequence_track(seq.id, "music", %{
                 "asset_id" => asset.id,
                 "volume" => Decimal.new("0.8")
               })

      assert track.flow_node_id == seq.id
      assert track.kind == "music"
      assert track.asset_id == asset.id
      assert Decimal.equal?(track.volume, Decimal.new("0.8"))
    end

    test "upsert updates the existing row for the same (sequence, kind)" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, original} =
        Flows.upsert_sequence_track(seq.id, "music", %{
          "asset_id" => asset.id,
          "volume" => Decimal.new("1.0")
        })

      {:ok, updated} =
        Flows.upsert_sequence_track(seq.id, "music", %{"volume" => Decimal.new("0.25")})

      # Same row, not duplicated.
      assert updated.id == original.id
      assert Decimal.equal?(updated.volume, Decimal.new("0.25"))
      assert updated.asset_id == asset.id
    end

    test "clear deletes the row for (sequence, kind)" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, _} = Flows.upsert_sequence_track(seq.id, "ambient", %{"asset_id" => asset.id})
      assert Flows.get_sequence_track(seq.id, "ambient") != nil

      assert {:ok, :cleared} = Flows.clear_sequence_track(seq.id, "ambient")
      assert Flows.get_sequence_track(seq.id, "ambient") == nil
    end

    test "clear is a no-op when no row exists" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert {:ok, :cleared} = Flows.clear_sequence_track(seq.id, "music")
    end

    test "rejects invalid kind on both upsert and clear" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert {:error, :invalid_kind} =
               Flows.upsert_sequence_track(seq.id, "narration", %{})

      assert {:error, :invalid_kind} = Flows.clear_sequence_track(seq.id, "narration")
    end

    test "DB trigger rejects tracks pointing to non-sequence flow_nodes" do
      %{flow: flow} = setup_flow()
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "x"}})

      assert_raise Postgrex.Error, ~r/must reference a sequence node/, fn ->
        Flows.upsert_sequence_track(dialogue.id, "music", %{})
      end
    end

    test "UNIQUE (flow_node_id, kind) enforced — independent kinds coexist" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      {:ok, _} = Flows.upsert_sequence_track(seq.id, "background", %{})
      {:ok, _} = Flows.upsert_sequence_track(seq.id, "music", %{})
      {:ok, _} = Flows.upsert_sequence_track(seq.id, "ambient", %{})

      tracks = Flows.list_sequence_tracks(seq.id)
      assert Enum.map(tracks, & &1.kind) |> Enum.sort() ==
               ["ambient", "background", "music"]
    end

    test "rejects volume outside [0, 1]" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert {:error, cs} =
               Flows.upsert_sequence_track(seq.id, "music", %{
                 "volume" => Decimal.new("1.5")
               })

      assert %{volume: ["must be <= 1"]} = errors_on(cs)

      assert {:error, cs2} =
               Flows.upsert_sequence_track(seq.id, "music", %{
                 "volume" => Decimal.new("-0.1")
               })

      assert %{volume: ["must be >= 0"]} = errors_on(cs2)
    end
  end

  describe "delete_sequence/1 and restore_sequence/1" do
    test "soft-delete sets deleted_at; restore clears it" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      {:ok, deleted} = Flows.delete_sequence(seq)
      assert %DateTime{} = deleted.deleted_at

      {:ok, restored} = Flows.restore_sequence(deleted)
      assert is_nil(restored.deleted_at)
      assert Flows.get_sequence(flow.id, restored.id).id == seq.id
    end

    test "soft-delete of a root-level sequence nilifies parent_id on children via DB trigger" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "Act I"})

      child =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "a"}})
        |> Ecto.Changeset.change(%{parent_id: seq.id})
        |> Repo.update!()

      {:ok, _} = Flows.delete_sequence(seq)

      # Root-level sequence has parent_id = NULL, so children reparent to
      # NULL (effectively orphaned to the flow root).
      assert Repo.get!(FlowNode, child.id).parent_id == nil
    end

    test "soft-delete of a nested sequence reparents children to the grandparent" do
      %{flow: flow} = setup_flow()
      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "outer"})

      {:ok, inner} =
        Flows.create_sequence(flow.id, %{"name" => "inner", "parent_id" => outer.id})

      child =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "a"}})
        |> Ecto.Changeset.change(%{parent_id: inner.id})
        |> Repo.update!()

      {:ok, _} = Flows.delete_sequence(inner)

      # Deleting the INNER sequence should leave the outer sequence intact
      # and reparent the child up one level, not orphan it to the flow root.
      assert Repo.get!(FlowNode, child.id).parent_id == outer.id
      assert Repo.get!(FlowNode, outer.id).deleted_at == nil
    end

    test "restore does NOT re-associate children (they stay at the reparented location)" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "Act I"})

      child =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "a"}})
        |> Ecto.Changeset.change(%{parent_id: seq.id})
        |> Repo.update!()

      {:ok, deleted} = Flows.delete_sequence(seq)
      {:ok, _} = Flows.restore_sequence(deleted)

      # Per D-J of the refactor: restore doesn't bring refs back. For a
      # root-level sequence, children stay with parent_id = NULL after the
      # trigger fired on delete.
      assert Repo.get!(FlowNode, child.id).parent_id == nil
    end
  end

  describe "cascade behavior" do
    test "deleting the parent flow hard-deletes its sequence flow_nodes" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      Repo.delete!(flow)

      assert Repo.get(FlowNode, seq.id) == nil
    end

    test "hard-deleting an outer sequence nilifies inner sequence parent_id (FK SET NULL)" do
      %{flow: flow} = setup_flow()
      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "outer"})

      {:ok, inner} =
        Flows.create_sequence(flow.id, %{"name" => "inner", "parent_id" => outer.id})

      Repo.delete!(outer)

      refetched = Repo.get!(FlowNode, inner.id)
      assert is_nil(refetched.parent_id)
    end

    test "hard-deleting a sequence deletes its sequence_config via FK CASCADE" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      assert Repo.get_by(SequenceConfig, flow_node_id: seq.id)

      Repo.delete!(seq)

      assert Repo.get_by(SequenceConfig, flow_node_id: seq.id) == nil
    end
  end

  describe "wrap_selection_in_sequence/3" do
    test "wraps a single node: creates sequence + sets parent_id" do
      %{flow: flow} = setup_flow()
      n1 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})

      assert {:ok, seq} =
               Flows.wrap_selection_in_sequence(flow, [n1.id], %{"name" => "Intro"})

      assert seq.type == "sequence"
      assert seq.sequence_config.name == "Intro"
      assert seq.flow_id == flow.id
      assert is_nil(seq.parent_id)

      assert Repo.get!(FlowNode, n1.id).parent_id == seq.id
    end

    test "wraps multiple nodes at root into a new root-level sequence" do
      %{flow: flow} = setup_flow()
      n1 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})
      n2 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "b"}})

      assert {:ok, seq} = Flows.wrap_selection_in_sequence(flow, [n1.id, n2.id])

      assert is_nil(seq.parent_id)
      assert Repo.get!(FlowNode, n1.id).parent_id == seq.id
      assert Repo.get!(FlowNode, n2.id).parent_id == seq.id
    end

    test "inherits parent_id when wrapped nodes all live inside an existing sequence" do
      %{flow: flow} = setup_flow()
      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "Outer"})

      n1 =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "a"}})
        |> Ecto.Changeset.change(%{parent_id: outer.id})
        |> Repo.update!()

      n2 =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "b"}})
        |> Ecto.Changeset.change(%{parent_id: outer.id})
        |> Repo.update!()

      {:ok, inner} = Flows.wrap_selection_in_sequence(flow, [n1.id, n2.id])

      assert inner.parent_id == outer.id
      assert Repo.get!(FlowNode, n1.id).parent_id == inner.id
      assert Repo.get!(FlowNode, n2.id).parent_id == inner.id
    end

    test "wraps mixed-type selection (node + existing sequence share a parent)" do
      %{flow: flow} = setup_flow()
      {:ok, outer} = Flows.create_sequence(flow.id, %{"name" => "Outer"})

      {:ok, inner_a} =
        Flows.create_sequence(flow.id, %{"name" => "A", "parent_id" => outer.id})

      n1 =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "a"}})
        |> Ecto.Changeset.change(%{parent_id: outer.id})
        |> Repo.update!()

      # Wrapping a flow_node + a sequence that share the same parent_id succeeds.
      {:ok, wrap} = Flows.wrap_selection_in_sequence(flow, [n1.id, inner_a.id])

      assert wrap.parent_id == outer.id
      assert Repo.get!(FlowNode, n1.id).parent_id == wrap.id
      assert Repo.get!(FlowNode, inner_a.id).parent_id == wrap.id
    end

    test "rejects empty selection" do
      %{flow: flow} = setup_flow()

      assert {:error, :empty_selection} = Flows.wrap_selection_in_sequence(flow, [])
    end

    test "rejects mixed parents" do
      %{flow: flow} = setup_flow()
      {:ok, seq_a} = Flows.create_sequence(flow.id, %{"name" => "A"})

      n_root = node_fixture(flow, %{type: "dialogue", data: %{"text" => "root"}})

      n_in_a =
        flow
        |> node_fixture(%{type: "dialogue", data: %{"text" => "in_a"}})
        |> Ecto.Changeset.change(%{parent_id: seq_a.id})
        |> Repo.update!()

      assert {:error, :mixed_parents} =
               Flows.wrap_selection_in_sequence(flow, [n_root.id, n_in_a.id])

      assert Repo.get!(FlowNode, n_root.id).parent_id == nil
      assert Repo.get!(FlowNode, n_in_a.id).parent_id == seq_a.id
    end

    test "rejects node_ids that don't exist" do
      %{flow: flow} = setup_flow()

      assert {:error, :nodes_not_found} =
               Flows.wrap_selection_in_sequence(flow, [-1, -2])
    end

    test "rejects nodes from a different flow" do
      user = user_fixture()
      project = project_fixture(user)
      flow_a = flow_fixture(project)
      flow_b = flow_fixture(project)
      n_b = node_fixture(flow_b, %{type: "dialogue", data: %{"text" => "x"}})

      assert {:error, :nodes_not_found} =
               Flows.wrap_selection_in_sequence(flow_a, [n_b.id])
    end

    test "rejects soft-deleted nodes" do
      %{flow: flow} = setup_flow()
      n1 = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})

      n1
      |> Ecto.Changeset.change(%{deleted_at: DateTime.truncate(DateTime.utc_now(), :second)})
      |> Repo.update!()

      assert {:error, :nodes_not_found} = Flows.wrap_selection_in_sequence(flow, [n1.id])
    end
  end

  describe "DB triggers" do
    test "flow_connections cannot reference a sequence as source" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      target = node_fixture(flow, %{type: "dialogue", data: %{}})

      assert_raise Postgrex.Error,
                   ~r/sequences cannot be connection endpoints/,
                   fn ->
                     %FlowConnection{}
                     |> Ecto.Changeset.cast(
                       %{
                         flow_id: flow.id,
                         source_node_id: seq.id,
                         target_node_id: target.id,
                         source_pin: "output",
                         target_pin: "input"
                       },
                       [:flow_id, :source_node_id, :target_node_id, :source_pin, :target_pin]
                     )
                     |> Repo.insert!()
                   end
    end

    test "cannot change flow_node.type to 'sequence' if it has connections" do
      %{flow: flow} = setup_flow()
      src = node_fixture(flow, %{type: "dialogue", data: %{}})
      tgt = node_fixture(flow, %{type: "dialogue", data: %{}})

      %FlowConnection{}
      |> Ecto.Changeset.cast(
        %{
          flow_id: flow.id,
          source_node_id: src.id,
          target_node_id: tgt.id,
          source_pin: "output",
          target_pin: "input"
        },
        [:flow_id, :source_node_id, :target_node_id, :source_pin, :target_pin]
      )
      |> Repo.insert!()

      assert_raise Postgrex.Error,
                   ~r/has existing connections/,
                   fn ->
                     src
                     |> Ecto.Changeset.change(%{type: "sequence"})
                     |> Repo.update!()
                   end
    end
  end
end
