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
  alias Storyarn.Flows.SequenceVisualLayer
  alias Storyarn.Platform.Collaboration
  alias Storyarn.Repo

  defp setup_flow(_ctx \\ %{}) do
    user = user_fixture()
    project = project_fixture(user)
    flow = flow_fixture(project)
    %{flow: flow, project: project, user: user}
  end

  describe "create_sequence/2" do
    test "invalidates the flows dashboard once after commit and not on error" do
      %{flow: flow, project: project} = setup_flow()
      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, %FlowNode{type: "sequence"}} =
               Flows.create_sequence(flow.id, %{"name" => "Opening"})

      assert_receive {:dashboard_invalidate, :flows}
      refute_receive {:dashboard_invalidate, :flows}, 10

      assert {:error, %Ecto.Changeset{}} = Flows.create_sequence(flow.id, %{})
      refute_receive {:dashboard_invalidate, :flows}, 10
    end

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
      assert {:error, :flow_not_found} =
               Flows.create_sequence(-1, %{"name" => "s"})
    end

    test "rejects parent_id pointing to a non-sequence node before writing" do
      %{flow: flow} = setup_flow()
      non_seq = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})

      assert {:error, {:invalid_node_parent, parent_id}} =
               Flows.create_sequence(flow.id, %{
                 "name" => "bad",
                 "parent_id" => non_seq.id
               })

      assert parent_id == non_seq.id
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

    test "ignores non-metadata attrs on sequence config updates" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      {:ok, updated} =
        Flows.update_sequence(seq, %{
          "name" => "s",
          "kind" => "backdrop"
        })

      assert updated.sequence_config.name == "s"
    end
  end

  describe "sequence visual layers" do
    test "creates a backdrop layer with stage defaults" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      assert {:ok, %SequenceVisualLayer{} = layer} =
               Flows.create_sequence_visual_layer(seq.id, %{
                 "kind" => "backdrop",
                 "asset_id" => asset.id
               })

      assert layer.flow_node_id == seq.id
      assert layer.asset_id == asset.id
      assert layer.kind == "backdrop"
      assert layer.slot == "full"
      assert layer.fit == "cover"
      assert layer.x == 0.0
      assert layer.y == 0.0
      assert layer.width == 1.0
      assert layer.height == 1.0
    end

    test "public creation ignores persisted identity and override-state attrs" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      assert {:ok, layer} =
               Flows.create_sequence_visual_layer(seq.id, %{
                 "asset_id" => asset.id,
                 "kind" => "prop",
                 "flow_node_id" => -1,
                 "layer_key" => "caller-controlled",
                 "overridden_fields" => [],
                 "removed" => true
               })

      assert layer.flow_node_id == seq.id
      assert layer.layer_key != "caller-controlled"

      assert MapSet.new(layer.overridden_fields) ==
               MapSet.new(SequenceVisualLayer.property_fields())

      refute layer.removed
    end

    test "creates a character layer with legacy right-slot defaults" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      assert {:ok, layer} =
               Flows.create_sequence_visual_layer(seq.id, %{
                 "kind" => "character",
                 "slot" => "right",
                 "asset_id" => asset.id
               })

      assert layer.kind == "character"
      assert layer.slot == "bottom-right"
      assert layer.fit == "contain"
      assert layer.x == 0.75
      assert layer.y == 1.0
      assert layer.width == 0.38
      assert layer.height == 0.9
      assert layer.anchor_x == 0.5
      assert layer.anchor_y == 1.0
    end

    test "creates a character layer with top-right slot defaults" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      assert {:ok, layer} =
               Flows.create_sequence_visual_layer(seq.id, %{
                 "kind" => "character",
                 "slot" => "top-right",
                 "asset_id" => asset.id
               })

      assert layer.kind == "character"
      assert layer.slot == "top-right"
      assert layer.fit == "contain"
      assert layer.x == 0.75
      assert layer.y == 0.0
      assert layer.width == 0.38
      assert layer.height == 0.9
      assert layer.anchor_x == 0.5
      assert layer.anchor_y == 0.0
    end

    test "lists visual layers ordered by z-index then id" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      backdrop = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      character = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      {:ok, character_layer} =
        Flows.create_sequence_visual_layer(seq.id, %{
          "kind" => "character",
          "asset_id" => character.id
        })

      {:ok, backdrop_layer} =
        Flows.create_sequence_visual_layer(seq.id, %{
          "kind" => "backdrop",
          "asset_id" => backdrop.id
        })

      assert seq.id |> Flows.list_sequence_visual_layers() |> Enum.map(& &1.id) == [
               backdrop_layer.id,
               character_layer.id
             ]
    end

    test "updates and deletes a visual layer" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      {:ok, layer} =
        Flows.create_sequence_visual_layer(seq.id, %{
          "kind" => "prop",
          "asset_id" => asset.id
        })

      assert {:ok, updated} =
               Flows.update_sequence_visual_layer(layer, %{"opacity" => 0.5, "slot" => "center"})

      assert updated.opacity == 0.5
      assert updated.slot == "middle-center"

      assert {:ok, _deleted} = Flows.delete_sequence_visual_layer(updated)
      assert Flows.get_sequence_visual_layer(seq.id, layer.id) == nil
    end

    test "dialogue nodes can own visual layers" do
      %{flow: flow, project: project, user: user} = setup_flow()
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "x"}})

      assert {:ok, %SequenceVisualLayer{flow_node_id: dialogue_id}} =
               Flows.create_sequence_visual_layer(dialogue.id, %{
                 "kind" => "backdrop",
                 "asset_id" => asset.id
               })

      assert dialogue_id == dialogue.id
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

    test "public upsert creation ignores persisted identity and override-state attrs" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})
      asset = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      assert {:ok, track} =
               Flows.upsert_sequence_track(seq.id, "music", %{
                 "asset_id" => asset.id,
                 "flow_node_id" => -1,
                 "kind" => "sfx",
                 "track_key" => "caller-controlled",
                 "is_override" => true,
                 "overridden_fields" => [],
                 "removed" => true
               })

      assert track.flow_node_id == seq.id
      assert track.kind == "music"
      assert track.track_key != "caller-controlled"
      assert MapSet.new(track.overridden_fields) == MapSet.new(SequenceTrack.property_fields())
      refute track.is_override
      refute track.removed
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

      {:ok, _} = Flows.upsert_sequence_track(seq.id, "ambience", %{"asset_id" => asset.id})
      assert Flows.get_sequence_track(seq.id, "ambience")

      assert {:ok, :cleared} = Flows.clear_sequence_track(seq.id, "ambience")
      assert Flows.get_sequence_track(seq.id, "ambience") == nil
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

    test "dialogue nodes can own audio tracks" do
      %{flow: flow} = setup_flow()
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "x"}})

      assert {:ok, %SequenceTrack{flow_node_id: dialogue_id}} =
               Flows.upsert_sequence_track(dialogue.id, "music", %{})

      assert dialogue_id == dialogue.id
    end

    test "UNIQUE (flow_node_id, kind) enforced — independent kinds coexist" do
      %{flow: flow} = setup_flow()
      {:ok, seq} = Flows.create_sequence(flow.id, %{"name" => "s"})

      {:ok, _} = Flows.upsert_sequence_track(seq.id, "music", %{})
      {:ok, _} = Flows.upsert_sequence_track(seq.id, "ambience", %{})
      {:ok, _} = Flows.upsert_sequence_track(seq.id, "sfx", %{})

      tracks = Flows.list_sequence_tracks(seq.id)

      assert tracks |> Enum.map(& &1.kind) |> Enum.sort() ==
               ["ambience", "music", "sfx"]
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
    test "each committed transition invalidates once while repeated transitions emit nothing" do
      %{flow: flow, project: project} = setup_flow()
      {:ok, sequence} = Flows.create_sequence(flow.id, %{"name" => "Act I"})
      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, deleted} = Flows.delete_sequence(sequence)
      assert_dashboard_invalidation_once()

      assert {:error, :node_not_found} = Flows.delete_sequence(sequence)
      refute_dashboard_invalidation()

      assert {:ok, restored} = Flows.restore_sequence(deleted)
      assert is_nil(restored.deleted_at)
      assert_dashboard_invalidation_once()

      assert {:error, :sequence_not_deleted} = Flows.restore_sequence(deleted)
      refute_dashboard_invalidation()
    end

    test "reloads the persisted node so a forged type cannot delete a dialogue" do
      %{flow: flow} = setup_flow()
      dialogue = node_fixture(flow, %{type: "dialogue", data: %{"text" => "Keep me"}})

      assert {:error, :sequence_not_found} =
               Flows.delete_sequence(%{dialogue | type: "sequence"})

      assert Repo.get!(FlowNode, dialogue.id).deleted_at == nil
      assert Repo.get!(FlowNode, dialogue.id).type == "dialogue"
    end

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
    test "invalidates once for the whole committed wrap, not for its nested sequence insert" do
      %{flow: flow, project: project} = setup_flow()
      node = node_fixture(flow, %{type: "dialogue", data: %{"text" => "a"}})
      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, %FlowNode{type: "sequence"}} =
               Flows.wrap_selection_in_sequence(flow, [node.id], %{"name" => "Opening"})

      assert_receive {:dashboard_invalidate, :flows}
      refute_receive {:dashboard_invalidate, :flows}, 10
    end

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

  describe "explicit composition inheritance" do
    test "sets a same-flow source, accepts explicit empty, and rejects cycles and foreign flows" do
      %{flow: flow, project: project} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
      first = node_fixture(flow, %{parent_id: base.id, data: %{"text" => "first"}})
      second = node_fixture(flow, %{data: %{"text" => "second"}})

      assert Repo.reload(first).composition_source_id == base.id
      assert {:ok, second} = Flows.set_composition_source(second.id, first.id)
      assert second.composition_source_id == first.id

      assert {:error, :composition_cycle} = Flows.set_composition_source(first.id, second.id)
      assert Repo.reload(first).composition_source_id == base.id

      other_flow = flow_fixture(project)
      foreign = node_fixture(other_flow)

      assert {:error, {:invalid_composition_source, foreign_id}} =
               Flows.set_composition_source(first.id, foreign.id)

      assert foreign_id == foreign.id
      assert {:ok, detached} = Flows.set_composition_source(first.id, nil)
      assert is_nil(detached.composition_source_id)
    end

    test "inherits visual properties, reverts them, and persists a removable tombstone" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
      dialogue = node_fixture(flow, %{parent_id: base.id, data: %{"text" => "line"}})
      asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "character",
          "asset_id" => asset.id,
          "x" => 0.2,
          "opacity" => 0.9
        })

      assert {:ok, patch} =
               Flows.override_sequence_visual_layer(dialogue.id, base_layer.layer_key, %{
                 "opacity" => 0.4
               })

      assert patch.overridden_fields == ["opacity"]

      {:ok, _base_layer} =
        Flows.update_sequence_visual_layer(base_layer, %{"x" => 0.7, "opacity" => 0.8})

      resolved = dialogue |> composition_for(flow.id) |> visual_layer!(base_layer.layer_key)
      assert resolved.item.x == 0.7
      assert resolved.item.opacity == 0.4
      assert resolved.property_sources["x"] == base.id
      assert resolved.property_sources["opacity"] == dialogue.id

      assert {:ok, :inherited} =
               Flows.revert_sequence_visual_layer_fields(
                 dialogue.id,
                 base_layer.layer_key,
                 ["opacity"]
               )

      assert dialogue
             |> composition_for(flow.id)
             |> visual_layer!(base_layer.layer_key)
             |> Map.fetch!(:item)
             |> Map.fetch!(:opacity) == 0.8

      assert {:ok, tombstone} =
               Flows.remove_sequence_visual_layer(dialogue.id, base_layer.layer_key)

      assert tombstone.removed

      refute Enum.any?(
               composition_for(dialogue, flow.id).visual_layers,
               &(&1.layer_key == base_layer.layer_key)
             )

      assert {:ok, :inherited} =
               Flows.restore_sequence_visual_layer(dialogue.id, base_layer.layer_key)

      assert visual_layer!(composition_for(dialogue, flow.id), base_layer.layer_key)
    end

    test "overrides inherited track properties without replacing local same-kind definitions" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
      dialogue = node_fixture(flow, %{parent_id: base.id, data: %{"text" => "line"}})
      inherited_asset = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)
      local_asset = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, inherited_track} =
        Flows.upsert_sequence_track(base.id, "music", %{
          "asset_id" => inherited_asset.id,
          "volume" => Decimal.new("0.8")
        })

      assert {:ok, patch} =
               Flows.override_sequence_track(dialogue.id, inherited_track.track_key, %{
                 "volume" => Decimal.new("0.25")
               })

      assert patch.is_override
      assert patch.overridden_fields == ["volume"]

      assert {:ok, local_track} =
               Flows.upsert_sequence_track(dialogue.id, "music", %{
                 "asset_id" => local_asset.id
               })

      assert local_track.track_key != inherited_track.track_key
      assert length(Flows.list_sequence_tracks(dialogue.id)) == 2

      inherited_result =
        dialogue
        |> composition_for(flow.id)
        |> audio_track!(inherited_track.track_key)

      assert inherited_result.item.asset_id == inherited_asset.id
      assert Decimal.equal?(inherited_result.item.volume, Decimal.new("0.25"))
      assert inherited_result.asset_source_row_id == inherited_track.id

      assert {:ok, :cleared} = Flows.clear_sequence_track(dialogue.id, "music")
      assert Flows.get_sequence_track_by_key(dialogue.id, patch.track_key)

      assert {:ok, :inherited} =
               Flows.revert_sequence_track_fields(
                 dialogue.id,
                 inherited_track.track_key,
                 ["volume"]
               )

      inherited_result =
        dialogue
        |> composition_for(flow.id)
        |> audio_track!(inherited_track.track_key)

      assert Decimal.equal?(inherited_result.item.volume, Decimal.new("0.8"))

      assert {:ok, tombstone} =
               Flows.remove_sequence_track(dialogue.id, inherited_track.track_key)

      assert tombstone.removed

      refute Enum.any?(
               composition_for(dialogue, flow.id).audio_tracks,
               &(&1.track_key == inherited_track.track_key)
             )

      assert {:ok, :inherited} =
               Flows.restore_sequence_track(dialogue.id, inherited_track.track_key)

      assert audio_track!(composition_for(dialogue, flow.id), inherited_track.track_key)
    end

    test "removing definitions introduced by the current owner deletes their local rows" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, owner} = Flows.create_sequence(flow.id, %{"name" => "Local stage"})
      image = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      audio = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, layer} =
        Flows.create_sequence_visual_layer(owner.id, %{
          "kind" => "backdrop",
          "asset_id" => image.id
        })

      {:ok, track} =
        Flows.upsert_sequence_track(owner.id, "music", %{
          "asset_id" => audio.id
        })

      assert {:ok, removed_layer} =
               Flows.remove_sequence_visual_layer(owner.id, layer.layer_key)

      refute removed_layer.removed
      assert is_nil(Flows.get_sequence_visual_layer_by_key(owner.id, layer.layer_key))

      assert {:ok, removed_track} =
               Flows.remove_sequence_track(owner.id, track.track_key)

      refute removed_track.removed
      assert is_nil(Flows.get_sequence_track_by_key(owner.id, track.track_key))
    end

    test "a descendant restores ancestor tombstones as complete local overrides" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})

      middle =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "middle"}
        })

      descendant =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: middle.id,
          data: %{"text" => "descendant"}
        })

      image = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      audio = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "character",
          "asset_id" => image.id,
          "x" => 0.25,
          "opacity" => 0.75
        })

      {:ok, base_track} =
        Flows.upsert_sequence_track(base.id, "ambience", %{
          "asset_id" => audio.id,
          "volume" => Decimal.new("0.6")
        })

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_visual_layer(middle.id, base_layer.layer_key)

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_track(middle.id, base_track.track_key)

      assert {:ok, restored_layer} =
               Flows.restore_sequence_visual_layer(descendant.id, base_layer.layer_key)

      assert restored_layer.layer_key == base_layer.layer_key
      refute restored_layer.removed

      assert MapSet.new(restored_layer.overridden_fields) ==
               MapSet.new(SequenceVisualLayer.property_fields())

      assert {:ok, restored_track} =
               Flows.restore_sequence_track(descendant.id, base_track.track_key)

      assert restored_track.track_key == base_track.track_key
      assert restored_track.is_override
      refute restored_track.removed

      assert MapSet.new(restored_track.overridden_fields) ==
               MapSet.new(SequenceTrack.property_fields())

      assert {:ok, edited_track} =
               Flows.override_sequence_track(descendant.id, base_track.track_key, %{
                 "volume" => Decimal.new("0.4")
               })

      assert edited_track.id == restored_track.id

      restored_composition = composition_for(descendant, flow.id)
      restored_visual = visual_layer!(restored_composition, base_layer.layer_key)
      restored_audio = audio_track!(restored_composition, base_track.track_key)

      assert restored_visual.sequence_id == descendant.id
      assert restored_visual.item.asset_id == image.id
      assert restored_visual.item.x == 0.25
      assert restored_visual.property_sources["x"] == descendant.id
      assert restored_audio.sequence_id == descendant.id
      assert restored_audio.item.asset_id == audio.id
      assert Decimal.equal?(restored_audio.item.volume, Decimal.new("0.4"))
      assert restored_audio.property_sources["volume"] == descendant.id

      assert {:ok, _removed_layer} =
               Flows.remove_sequence_visual_layer(descendant.id, base_layer.layer_key)

      assert {:ok, _removed_track} =
               Flows.remove_sequence_track(descendant.id, base_track.track_key)

      assert is_nil(Flows.get_sequence_visual_layer_by_key(descendant.id, base_layer.layer_key))

      assert is_nil(Flows.get_sequence_track_by_key(descendant.id, base_track.track_key))
      assert composition_for(descendant, flow.id).visual_layers == []
      assert composition_for(descendant, flow.id).audio_tracks == []
    end

    test "restoring orphan tombstones clears them after the ancestor deletes the identity" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})

      descendant =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "descendant"}
        })

      image = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      audio = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "prop",
          "asset_id" => image.id
        })

      {:ok, base_track} =
        Flows.upsert_sequence_track(base.id, "ambience", %{
          "asset_id" => audio.id
        })

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_visual_layer(descendant.id, base_layer.layer_key)

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_track(descendant.id, base_track.track_key)

      Repo.delete!(base_layer)
      Repo.delete!(base_track)

      assert {:ok, :cleared} =
               Flows.restore_sequence_visual_layer(descendant.id, base_layer.layer_key)

      assert {:ok, :cleared} =
               Flows.restore_sequence_track(descendant.id, base_track.track_key)

      assert is_nil(Flows.get_sequence_visual_layer_by_key(descendant.id, base_layer.layer_key))

      assert is_nil(Flows.get_sequence_track_by_key(descendant.id, base_track.track_key))
      assert composition_for(descendant, flow.id).visual_layers == []
      assert composition_for(descendant, flow.id).audio_tracks == []
    end

    test "changing a source rolls back when local changes would lose their inherited identities" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
      {:ok, alternate} = Flows.create_sequence(flow.id, %{"name" => "Alternate"})

      descendant =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "descendant"}
        })

      image = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      audio = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "character",
          "asset_id" => image.id
        })

      {:ok, base_track} =
        Flows.upsert_sequence_track(base.id, "music", %{"asset_id" => audio.id})

      assert {:ok, _patch} =
               Flows.override_sequence_visual_layer(descendant.id, base_layer.layer_key, %{
                 "opacity" => 0.5
               })

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_track(descendant.id, base_track.track_key)

      assert {:error, :composition_dependency_conflict} =
               Flows.set_composition_source(descendant.id, alternate.id)

      assert Repo.reload(descendant).composition_source_id == base.id
      assert visual_layer!(composition_for(descendant, flow.id), base_layer.layer_key)
      assert composition_for(descendant, flow.id).audio_tracks == []
    end

    test "definition deletion and clear roll back while descendants still patch or remove them" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})

      patched =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "patched"}
        })

      removed =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "removed"}
        })

      image = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      audio = Storyarn.AssetsFixtures.audio_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "character",
          "asset_id" => image.id
        })

      {:ok, base_track} =
        Flows.upsert_sequence_track(base.id, "ambience", %{"asset_id" => audio.id})

      assert {:ok, _patch} =
               Flows.override_sequence_visual_layer(patched.id, base_layer.layer_key, %{
                 "visible" => false
               })

      assert {:ok, _patch} =
               Flows.override_sequence_track(patched.id, base_track.track_key, %{
                 "volume" => Decimal.new("0.5")
               })

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_visual_layer(removed.id, base_layer.layer_key)

      assert {:ok, %{removed: true}} =
               Flows.remove_sequence_track(removed.id, base_track.track_key)

      assert {:error, :composition_dependency_conflict} =
               Flows.delete_sequence_visual_layer(base_layer)

      assert {:error, :composition_dependency_conflict} =
               Flows.remove_sequence_visual_layer(base.id, base_layer.layer_key)

      assert Flows.get_sequence_visual_layer(base.id, base_layer.id)

      assert {:error, :composition_dependency_conflict} =
               Flows.clear_sequence_track(base.id, "ambience")

      assert {:error, :composition_dependency_conflict} =
               Flows.remove_sequence_track(base.id, base_track.track_key)

      assert Flows.get_sequence_track(base.id, "ambience")
    end

    test "definition deletion validates dependent composition owners in the trash" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})

      descendant =
        node_fixture(flow, %{
          type: "dialogue",
          composition_source_id: base.id,
          data: %{"text" => "archived patch"}
        })

      image = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "prop",
          "asset_id" => image.id
        })

      assert {:ok, _patch} =
               Flows.override_sequence_visual_layer(descendant.id, base_layer.layer_key, %{
                 "opacity" => 0.4
               })

      assert {:ok, _deleted_descendant, _meta} = Flows.delete_node(descendant)

      assert {:error, :composition_dependency_conflict} =
               Flows.delete_sequence_visual_layer(base_layer)

      assert Flows.get_sequence_visual_layer(base.id, base_layer.id)
    end

    test "returns a domain error when deleting an active sequence composition source" do
      %{flow: flow} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
      _dialogue = node_fixture(flow, %{parent_id: base.id})

      assert {:error, :composition_source_in_use} = Flows.delete_sequence(base)
      assert is_nil(Repo.reload(base).deleted_at)
    end

    test "returns a domain error when deleting an active dialogue composition source" do
      %{flow: flow} = setup_flow()
      source = node_fixture(flow, %{type: "dialogue", data: %{"text" => "source"}})
      _dependent = node_fixture(flow, %{type: "dialogue", composition_source_id: source.id})

      assert {:error, :composition_source_in_use} = Flows.delete_node(source)
      assert is_nil(Repo.reload(source).deleted_at)
    end

    test "returns a domain error when restoring a node whose composition source is deleted" do
      %{flow: flow} = setup_flow()
      source = node_fixture(flow, %{type: "dialogue", data: %{"text" => "source"}})
      dependent = node_fixture(flow, %{type: "dialogue", composition_source_id: source.id})

      assert {:ok, deleted_dependent, _meta} = Flows.delete_node(dependent)
      assert {:ok, _deleted_source, _meta} = Flows.delete_node(source)

      assert {:error, :inactive_composition_source} =
               Flows.restore_node(flow.id, deleted_dependent.id)

      assert Repo.reload(deleted_dependent).deleted_at
    end

    test "returns a domain error when restoring a sequence whose composition source is deleted" do
      %{flow: flow} = setup_flow()
      {:ok, source} = Flows.create_sequence(flow.id, %{"name" => "Source"})
      {:ok, dependent} = Flows.create_sequence(flow.id, %{"name" => "Dependent"})
      assert {:ok, dependent} = Flows.set_composition_source(dependent.id, source.id)

      assert {:ok, deleted_dependent} = Flows.delete_sequence(dependent)
      assert {:ok, _deleted_source} = Flows.delete_sequence(source)

      assert {:error, :inactive_composition_source} =
               Flows.restore_sequence(deleted_dependent)

      assert Repo.reload(deleted_dependent).deleted_at
    end

    test "hard-deleting an overridden visual asset preserves the patch and does not reactivate inheritance" do
      %{flow: flow, project: project, user: user} = setup_flow()
      {:ok, base} = Flows.create_sequence(flow.id, %{"name" => "Base"})
      dialogue = node_fixture(flow, %{parent_id: base.id, data: %{"text" => "line"}})
      inherited_asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)
      overridden_asset = Storyarn.AssetsFixtures.image_asset_fixture(project, user)

      {:ok, base_layer} =
        Flows.create_sequence_visual_layer(base.id, %{
          "kind" => "character",
          "asset_id" => inherited_asset.id
        })

      {:ok, patch} =
        Flows.override_sequence_visual_layer(dialogue.id, base_layer.layer_key, %{
          "asset_id" => overridden_asset.id
        })

      Repo.delete!(overridden_asset)

      persisted = Flows.get_sequence_visual_layer_by_key(dialogue.id, patch.layer_key)
      assert persisted.asset_id == nil
      assert persisted.asset == nil
      assert persisted.overridden_fields == ["asset_id"]

      resolved = visual_layer!(composition_for(dialogue, flow.id), base_layer.layer_key)
      assert resolved.item.asset_id == nil
      assert resolved.item.asset == nil
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

  defp assert_dashboard_invalidation_once do
    assert_receive {:dashboard_invalidate, :flows}
    refute_receive {:dashboard_invalidate, :flows}, 10
  end

  defp refute_dashboard_invalidation do
    refute_receive {:dashboard_invalidate, :flows}, 10
  end

  defp composition_for(node, flow_id) do
    nodes =
      FlowNode
      |> Repo.all()
      |> Enum.filter(&(&1.flow_id == flow_id and is_nil(&1.deleted_at)))
      |> Repo.preload(sequence_tracks: [:asset], sequence_visual_layers: [:asset])
      |> Map.new(&{&1.id, &1})

    Flows.compose_node_sequences(node.id, nodes)
  end

  defp visual_layer!(composition, layer_key),
    do: Enum.find(composition.visual_layers, &(&1.layer_key == layer_key)) || flunk("missing visual layer")

  defp audio_track!(composition, track_key),
    do: Enum.find(composition.audio_tracks, &(&1.track_key == track_key)) || flunk("missing audio track")
end
