defmodule Storyarn.Screenplays.FlowSyncTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.FlowsFixtures
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowConnection
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.References.EntityReference
  alias Storyarn.Repo
  alias Storyarn.Screenplays
  alias Storyarn.Screenplays.LinkedPageCrud
  alias Storyarn.Screenplays.Screenplay
  alias Storyarn.Screenplays.ScreenplayElement
  alias Storyarn.Shared.WordCount

  describe "flow link management" do
    test "unlinks the persisted association even when the caller struct is stale" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Stale unlink"})
      child = screenplay_fixture(project, %{name: "Child page", parent_id: screenplay.id})

      assert {:ok, action} =
               Screenplays.create_element(screenplay, %{
                 type: "action",
                 content: "Opening"
               })

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, _dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      assert {:ok, _response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{
                   "choices" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue",
                       "linked_screenplay_id" => child.id
                     }
                   ]
                 }
               })

      assert {:ok, child_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Child action"
               })

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)
      assert screenplay.linked_flow_id == nil
      assert Repo.reload!(action).linked_node_id
      assert Repo.reload!(child_action).linked_node_id

      assert {:ok, unlinked_screenplay} = Screenplays.unlink_flow(screenplay)
      assert unlinked_screenplay.linked_flow_id == nil
      assert Repo.reload!(screenplay).linked_flow_id == nil
      assert Repo.reload!(action).linked_node_id == nil
      assert Repo.reload!(child_action).linked_node_id == nil
      assert Flows.get_flow(project.id, flow.id)
    end

    test "an idempotent unlink clears residual element links on the root screenplay" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Residual unlink"})

      assert {:ok, action} =
               Screenplays.create_element(screenplay, %{
                 type: "action",
                 content: "Opening"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      assert Repo.reload!(action).linked_node_id

      screenplay
      |> Repo.reload!()
      |> Ecto.Changeset.change(linked_flow_id: nil)
      |> Repo.update!()

      assert {:ok, unlinked_screenplay} = Screenplays.unlink_flow(screenplay)
      assert unlinked_screenplay.linked_flow_id == nil
      assert Repo.reload!(action).linked_node_id == nil
    end

    test "unlinking a root preserves descendant links owned by another flow" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Root flow"})
      child = screenplay_fixture(project, %{name: "Independent child", parent_id: screenplay.id})

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      assert {:ok, _response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{
                   "choices" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue",
                       "linked_screenplay_id" => child.id
                     }
                   ]
                 }
               })

      assert {:ok, child_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Independent action"
               })

      assert {:ok, root_flow} = Screenplays.sync_to_flow(screenplay)
      assert linked_node(child_action).flow_id == root_flow.id

      assert {:ok, child_flow} = Screenplays.sync_to_flow(child)
      child_node_id = linked_node_id(child_action)
      assert child_flow.id != root_flow.id
      assert Repo.reload!(child).linked_flow_id == child_flow.id

      assert {:ok, %{linked_flow_id: nil}} = Screenplays.unlink_flow(screenplay)

      assert Repo.reload!(dialogue).linked_node_id == nil
      assert Repo.reload!(child).linked_flow_id == child_flow.id
      assert linked_node_id(child_action) == child_node_id
      assert Repo.get!(FlowNode, child_node_id).flow_id == child_flow.id
    end

    test "resyncing a root preserves descendant links owned by another flow" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Root resync"})
      child = screenplay_fixture(project, %{name: "Independent child", parent_id: screenplay.id})

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, _dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      assert {:ok, _response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{
                   "choices" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue",
                       "linked_screenplay_id" => child.id
                     }
                   ]
                 }
               })

      assert {:ok, child_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Independent action"
               })

      assert {:ok, root_flow} = Screenplays.sync_to_flow(screenplay)
      assert linked_node(child_action).flow_id == root_flow.id

      assert {:ok, child_flow} = Screenplays.sync_to_flow(child)
      child_node_id = linked_node_id(child_action)
      assert child_flow.id != root_flow.id
      assert Repo.reload!(child).linked_flow_id == child_flow.id

      assert {:ok, resynced_root_flow} = Screenplays.sync_to_flow(screenplay)

      assert resynced_root_flow.id == root_flow.id
      assert Repo.reload!(child).linked_flow_id == child_flow.id
      assert linked_node_id(child_action) == child_node_id
      assert Repo.get!(FlowNode, child_node_id).flow_id == child_flow.id
    end

    test "syncing and unlinking a root never mutates a descendant from another project" do
      project = project_fixture()
      foreign_project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Project-scoped root"})

      # The public create path currently accepts a parent from another project.
      # FlowSync must still preserve the tenant boundary when it encounters that
      # malformed hierarchy.
      assert {:ok, foreign_child} =
               Screenplays.create_screenplay(foreign_project, %{
                 name: "Foreign child",
                 parent_id: screenplay.id
               })

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      assert {:ok, _response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{
                   "choices" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue",
                       "linked_screenplay_id" => foreign_child.id
                     }
                   ]
                 }
               })

      assert {:ok, foreign_action} =
               Screenplays.create_element(foreign_child, %{
                 type: "action",
                 content: "Foreign action"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      foreign_node_id_after_sync = linked_node_id(foreign_action)
      root_node_id = linked_node_id(dialogue)

      foreign_action
      |> Repo.reload!()
      |> Ecto.Changeset.change(linked_node_id: root_node_id)
      |> Repo.update!()

      assert {:ok, %{linked_flow_id: nil}} = Screenplays.unlink_flow(screenplay)

      assert foreign_node_id_after_sync == nil
      assert linked_node_id(foreign_action) == root_node_id
    end

    test "unlinking also clears links from soft-deleted descendants after they are restored" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Restorable root"})
      child = screenplay_fixture(project, %{name: "Restorable child", parent_id: screenplay.id})

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, _dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      assert {:ok, _response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{
                   "choices" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue",
                       "linked_screenplay_id" => child.id
                     }
                   ]
                 }
               })

      assert {:ok, child_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Restorable action"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      assert linked_node_id(child_action)

      assert {:ok, deleted_child} = Screenplays.delete_screenplay(child)
      assert {:ok, %{linked_flow_id: nil}} = Screenplays.unlink_flow(screenplay)
      assert {:ok, _restored_child} = Screenplays.restore_screenplay(deleted_child)

      assert linked_node_id(child_action) == nil
    end

    test "unlinking terminates and clears links when an imported hierarchy contains a cycle" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Cyclic root"})
      child = screenplay_fixture(project, %{name: "Cyclic child", parent_id: screenplay.id})

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, _dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      assert {:ok, _response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{
                   "choices" => [
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue",
                       "linked_screenplay_id" => child.id
                     }
                   ]
                 }
               })

      assert {:ok, child_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Child action"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      assert linked_node_id(child_action)

      # The Storyarn JSON importer links parent IDs in a raw second pass, so an
      # imported A -> B -> A cycle can reach FlowSync even though UI moves reject it.
      screenplay
      |> Repo.reload!()
      |> Ecto.Changeset.change(parent_id: child.id)
      |> Repo.update!()

      Repo.query!("SET LOCAL statement_timeout = 500")

      assert {:ok, %{linked_flow_id: nil}} = Screenplays.unlink_flow(screenplay)
      assert linked_node_id(child_action) == nil
    end

    test "clears stale element links when switching to another flow" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Switch linked flow"})

      assert {:ok, action} =
               Screenplays.create_element(screenplay, %{
                 type: "action",
                 content: "Opening"
               })

      assert {:ok, original_flow} = Screenplays.sync_to_flow(screenplay)
      assert Repo.reload!(action).linked_node_id

      target_flow = flow_fixture(project, %{name: "Replacement flow"})

      assert {:ok, switched_screenplay} =
               screenplay
               |> Repo.reload!()
               |> Screenplays.link_to_flow(target_flow.id)

      assert switched_screenplay.linked_flow_id == target_flow.id
      assert Repo.reload!(action).linked_node_id == nil
      assert Flows.get_flow(project.id, original_flow.id)
    end
  end

  describe "sync_from_flow/1 branch ownership" do
    test "does not mutate a linked child from another project" do
      project = project_fixture()
      foreign_project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Reverse tenant root"})

      assert {:ok, foreign_child} =
               Screenplays.create_screenplay(foreign_project, %{
                 name: "Foreign branch",
                 parent_id: screenplay.id
               })

      assert {:ok, foreign_action} =
               Screenplays.create_element(foreign_child, %{
                 type: "action",
                 content: "Foreign content"
               })

      {_flow, choice_id} =
        reverse_branch_flow(project, screenplay, foreign_child, "Foreign branch content")

      assert {:ok, _screenplay} = Screenplays.sync_from_flow(screenplay)

      assert Repo.get(ScreenplayElement, foreign_action.id)

      assert replacement_child =
               Repo.one(
                 from(child in Screenplay,
                   where:
                     child.parent_id == ^screenplay.id and
                       child.project_id == ^project.id and
                       is_nil(child.deleted_at)
                 )
               )

      assert replacement_child.id != foreign_child.id

      assert root_choice_link(screenplay.id, choice_id) ==
               replacement_child.id
    end

    test "does not mutate a child owned by a different flow" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Reverse ownership root"})
      child = screenplay_fixture(project, %{name: "Independent branch", parent_id: screenplay.id})

      assert {:ok, child_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Independent content"
               })

      assert {:ok, child_flow} = Screenplays.sync_to_flow(child)
      assert Repo.reload!(child).linked_flow_id == child_flow.id

      {root_flow, choice_id} =
        reverse_branch_flow(project, screenplay, child, "Root branch content")

      assert root_flow.id != child_flow.id
      assert {:ok, _screenplay} = Screenplays.sync_from_flow(screenplay)

      assert Repo.get(ScreenplayElement, child_action.id)
      assert Repo.reload!(child).linked_flow_id == child_flow.id

      assert replacement_child =
               Repo.one(
                 from(candidate in Screenplay,
                   where:
                     candidate.parent_id == ^screenplay.id and
                       candidate.project_id == ^project.id and
                       candidate.id != ^child.id and
                       is_nil(candidate.deleted_at) and
                       is_nil(candidate.linked_flow_id)
                 )
               )

      assert root_choice_link(screenplay.id, choice_id) ==
               replacement_child.id
    end

    test "rejects two reverse-sync branches that reuse the same screenplay child" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Reverse reused child root"})
      child = screenplay_fixture(project, %{name: "Shared child", parent_id: screenplay.id})

      assert {:ok, original_action} =
               Screenplays.create_element(child, %{
                 type: "action",
                 content: "Original child content"
               })

      {flow, _first_choice_id} =
        reverse_branch_flow(project, screenplay, child, "First branch")

      nodes = Flows.list_nodes(flow.id)
      dialogue = Enum.find(nodes, &(&1.type == "dialogue" and &1.data["responses"] != []))
      exit_node = Enum.find(nodes, &(&1.type == "exit"))
      second_choice_id = Ecto.UUID.generate()

      second_response = %{
        "id" => second_choice_id,
        "text" => "Reuse child",
        "condition" => nil,
        "instruction" => nil,
        "linked_screenplay_id" => child.id
      }

      assert {:ok, dialogue, _meta} =
               Flows.update_node_data(
                 dialogue,
                 Map.update!(dialogue.data, "responses", &(&1 ++ [second_response]))
               )

      second_branch =
        node_fixture(flow, %{
          type: "dialogue",
          data: %{
            "speaker_sheet_id" => nil,
            "text" => "",
            "stage_directions" => "Second branch",
            "menu_text" => "",
            "audio_asset_id" => nil,
            "technical_id" => "",
            "localization_id" => "",
            "responses" => []
          }
        })

      assert {:ok, _connection} =
               Flows.create_connection(flow, dialogue, second_branch, %{
                 source_pin: second_choice_id,
                 target_pin: "input"
               })

      assert {:ok, _connection} =
               Flows.create_connection(flow, second_branch, exit_node, %{
                 source_pin: "output",
                 target_pin: "input"
               })

      assert {:error, {:reused_screenplay_branch, child_id}} =
               Screenplays.sync_from_flow(screenplay)

      assert child_id == child.id
      assert Repo.get(ScreenplayElement, original_action.id)
    end
  end

  describe "sync_to_flow/1" do
    test "resyncs canonical node derivatives and emits one post-commit dashboard event" do
      project = project_fixture()
      language_fixture(project)

      first_sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      first_variable =
        block_fixture(first_sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      second_sheet = sheet_fixture(project, %{name: "World", shortcut: "world"})

      second_variable =
        block_fixture(second_sheet, %{
          type: "number",
          config: %{"label" => "Danger", "placeholder" => "0"}
        })

      screenplay = screenplay_fixture(project, %{name: "Opening"})

      {:ok, _scene_heading} =
        Screenplays.create_element(screenplay, %{
          type: "scene_heading",
          content: "INT. OBSERVATORY - NIGHT"
        })

      {:ok, _character} =
        Screenplays.create_element(screenplay, %{
          type: "character",
          content: "Narrator"
        })

      {:ok, dialogue_element} =
        Screenplays.create_element(screenplay, %{
          type: "dialogue",
          content: "One two"
        })

      {:ok, instruction_element} =
        Screenplays.create_element(screenplay, %{
          type: "instruction",
          data: %{"assignments" => [assignment(first_sheet.shortcut, first_variable.variable_name)]}
        })

      {:ok, removable_element} =
        Screenplays.create_element(screenplay, %{
          type: "action",
          content: "This node will be removed"
        })

      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)
      assert_receive {:dashboard_invalidate, :flows}
      refute_receive {:dashboard_invalidate, :flows}, 10

      entry_node = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      assert entry_node.source == "screenplay_sync"

      dialogue_node = linked_node(dialogue_element)
      instruction_node = linked_node(instruction_element)

      assert dialogue_node.word_count ==
               WordCount.for_node_data(dialogue_node.type, dialogue_node.data)

      assert variable_reference_block_ids(instruction_node.id) == [first_variable.id]

      assert initial_text =
               Localization.get_text_by_source(
                 "flow_node",
                 dialogue_node.id,
                 "text",
                 "es"
               )

      assert initial_text.source_text == "One two"

      removable_node_id = linked_node_id(removable_element)

      {:ok, dialogue_element} =
        Screenplays.update_element(dialogue_element, %{
          content: "One two three four five"
        })

      {:ok, instruction_element} =
        Screenplays.update_element(instruction_element, %{
          data: %{
            "assignments" => [
              assignment(second_sheet.shortcut, second_variable.variable_name)
            ]
          }
        })

      assert {:ok, _deleted_element} = Screenplays.delete_element(removable_element)

      assert {:ok, resynced_flow} = Screenplays.sync_to_flow(screenplay)
      assert resynced_flow.id == flow.id
      assert_receive {:dashboard_invalidate, :flows}
      refute_receive {:dashboard_invalidate, :flows}, 10

      entry_node = flow.id |> Flows.list_nodes() |> Enum.find(&(&1.type == "entry"))
      assert entry_node.source == "screenplay_sync"

      updated_dialogue = linked_node(dialogue_element)
      updated_instruction = linked_node(instruction_element)

      assert updated_dialogue.id == dialogue_node.id
      assert updated_instruction.id == instruction_node.id

      assert updated_dialogue.word_count ==
               WordCount.for_node_data(updated_dialogue.type, updated_dialogue.data)

      assert updated_dialogue.word_count > dialogue_node.word_count
      assert Flows.flow_word_counts(project.id)[flow.id] == updated_dialogue.word_count
      assert variable_reference_block_ids(updated_instruction.id) == [second_variable.id]

      assert updated_text =
               Localization.get_text_by_source(
                 "flow_node",
                 updated_dialogue.id,
                 "text",
                 "es"
               )

      assert updated_text.id == initial_text.id
      assert updated_text.source_text == "One two three four five"

      assert Repo.get!(FlowNode, removable_node_id).deleted_at
    end

    test "rolls back every mutation and emits no event when sync fails" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Invalid hubs"})

      for label <- ["First", "Second"] do
        assert {:ok, _element} =
                 Screenplays.create_element(screenplay, %{
                   type: "hub_marker",
                   content: label,
                   data: %{"hub_node_id" => "duplicate-hub"}
                 })
      end

      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:error, _reason} = Screenplays.sync_to_flow(screenplay)
      refute_receive {:dashboard_invalidate, :flows}, 10

      assert Repo.reload!(screenplay).linked_flow_id == nil
      assert Flows.list_flows(project.id) == []
    end

    test "does not certify a jump against a hub that is renamed in the same sync" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Hub rename snapshot"})

      assert {:ok, hub_marker} =
               Screenplays.create_element(screenplay, %{
                 type: "hub_marker",
                 content: "Checkpoint",
                 data: %{"hub_node_id" => "checkpoint-a"}
               })

      assert {:ok, jump_marker} =
               Screenplays.create_element(screenplay, %{
                 type: "jump_marker",
                 data: %{"target_hub_id" => "checkpoint-a"}
               })

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      hub_node = linked_node(hub_marker)
      jump_node = linked_node(jump_marker)

      assert hub_node.data["hub_id"] == "checkpoint-a"
      assert jump_node.data["target_hub_id"] == "checkpoint-a"

      assert {:ok, _updated_hub_marker} =
               Screenplays.update_element(hub_marker, %{
                 data: %{"hub_node_id" => "checkpoint-b"}
               })

      assert {:error, {:invalid_jump_target, "checkpoint-a"}} =
               Screenplays.sync_to_flow(screenplay)

      assert Repo.reload!(hub_node).data["hub_id"] == "checkpoint-a"
      assert Repo.reload!(jump_node).data["target_hub_id"] == "checkpoint-a"
      assert Repo.reload!(screenplay).linked_flow_id == flow.id

      assert {:ok, _updated_jump_marker} =
               Screenplays.update_element(jump_marker, %{
                 data: %{"target_hub_id" => "checkpoint-b"}
               })

      assert {:ok, resynced_flow} = Screenplays.sync_to_flow(screenplay)
      assert resynced_flow.id == flow.id
      assert Repo.reload!(hub_node).data["hub_id"] == "checkpoint-b"
      assert Repo.reload!(jump_node).data["target_hub_id"] == "checkpoint-b"
    end

    test "rolls back when deleting an orphaned hub invalidates a retained jump" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Orphaned hub snapshot"})

      assert {:ok, hub_marker} =
               Screenplays.create_element(screenplay, %{
                 type: "hub_marker",
                 content: "Checkpoint",
                 data: %{"hub_node_id" => "checkpoint"}
               })

      assert {:ok, jump_marker} =
               Screenplays.create_element(screenplay, %{
                 type: "jump_marker",
                 data: %{"target_hub_id" => "checkpoint"}
               })

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      hub_node = linked_node(hub_marker)
      jump_node = linked_node(jump_marker)

      assert {:ok, _deleted_hub_marker} = Screenplays.delete_element(hub_marker)

      assert {:error, {:invalid_jump_target, "checkpoint"}} =
               Screenplays.sync_to_flow(screenplay)

      assert Repo.reload!(hub_node).deleted_at == nil
      assert Repo.reload!(jump_node).data["target_hub_id"] == "checkpoint"
      assert Repo.reload!(screenplay).linked_flow_id == flow.id
    end

    test "repairs legacy node derivatives before certifying the no-op path" do
      project = project_fixture()
      language_fixture(project)

      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      variable =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      screenplay = screenplay_fixture(project, %{name: "Legacy derivatives"})

      {:ok, _character} =
        Screenplays.create_element(screenplay, %{
          type: "character",
          content: "Narrator"
        })

      {:ok, dialogue_element} =
        Screenplays.create_element(screenplay, %{
          type: "dialogue",
          content: "One two three"
        })

      {:ok, instruction_element} =
        Screenplays.create_element(screenplay, %{
          type: "instruction",
          data: %{"assignments" => [assignment(sheet.shortcut, variable.variable_name)]}
        })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      dialogue_node = linked_node(dialogue_element)
      instruction_node = linked_node(instruction_element)
      node_ids = [dialogue_node.id, instruction_node.id]

      Repo.update_all(
        from(node in FlowNode, where: node.id in ^node_ids),
        set: [derivatives_fingerprint: nil]
      )

      Repo.update_all(
        from(node in FlowNode, where: node.id == ^dialogue_node.id),
        set: [word_count: -1]
      )

      Repo.delete_all(
        from(reference in VariableReference,
          where:
            reference.source_type == "flow_node" and
              reference.source_id == ^instruction_node.id
        )
      )

      Repo.delete_all(
        from(text in LocalizedText,
          where:
            text.source_type == "flow_node" and
              text.source_id == ^dialogue_node.id
        )
      )

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      repaired_dialogue = Repo.get!(FlowNode, dialogue_node.id)
      repaired_instruction = Repo.get!(FlowNode, instruction_node.id)

      assert repaired_dialogue.word_count ==
               WordCount.for_node_data(repaired_dialogue.type, repaired_dialogue.data)

      assert variable_reference_block_ids(repaired_instruction.id) == [variable.id]

      assert Localization.get_text_by_source(
               "flow_node",
               repaired_dialogue.id,
               "text",
               "es"
             )

      assert is_binary(repaired_dialogue.derivatives_fingerprint)
      assert is_binary(repaired_instruction.derivatives_fingerprint)
    end

    test "repairs missing batch-verified derivatives with an intact fingerprint" do
      project = project_fixture()
      language_fixture(project)
      speaker = sheet_fixture(project, %{name: "Narrator"})
      screenplay = screenplay_fixture(project, %{name: "Batch derivative repair"})

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator",
                 data: %{"sheet_id" => speaker.id}
               })

      assert {:ok, dialogue_element} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "A line with derivatives"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      dialogue_node = linked_node(dialogue_element)
      fingerprint = dialogue_node.derivatives_fingerprint

      assert %LocalizedText{} =
               localized_text =
               Localization.get_text_by_source(
                 "flow_node",
                 dialogue_node.id,
                 "text",
                 "es"
               )

      assert %EntityReference{} =
               entity_reference =
               Repo.get_by(EntityReference,
                 source_type: "flow_node",
                 source_id: dialogue_node.id,
                 target_type: "sheet",
                 target_id: speaker.id,
                 context: "speaker"
               )

      Repo.delete!(localized_text)
      Repo.delete!(entity_reference)
      assert Repo.reload!(dialogue_node).derivatives_fingerprint == fingerprint

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      assert %LocalizedText{} =
               Localization.get_text_by_source(
                 "flow_node",
                 dialogue_node.id,
                 "text",
                 "es"
               )

      assert %EntityReference{} =
               Repo.get_by(EntityReference,
                 source_type: "flow_node",
                 source_id: dialogue_node.id,
                 target_type: "sheet",
                 target_id: speaker.id,
                 context: "speaker"
               )
    end

    test "repairs a missing condition variable reference with an intact fingerprint" do
      project = project_fixture()
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      variable =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      screenplay = screenplay_fixture(project, %{name: "Condition derivative repair"})

      assert {:ok, conditional_element} =
               Screenplays.create_element(screenplay, %{
                 type: "conditional",
                 data: %{
                   "condition" =>
                     variable_condition(
                       sheet.shortcut,
                       variable.variable_name
                     )
                 }
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      condition_node = linked_node(conditional_element)
      fingerprint = condition_node.derivatives_fingerprint

      assert %VariableReference{} =
               reference =
               Repo.get_by(VariableReference,
                 source_type: "flow_node",
                 source_id: condition_node.id,
                 block_id: variable.id,
                 kind: "read"
               )

      Repo.delete!(reference)
      assert Repo.reload!(condition_node).derivatives_fingerprint == fingerprint

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      assert %VariableReference{} =
               Repo.get_by(VariableReference,
                 source_type: "flow_node",
                 source_id: condition_node.id,
                 block_id: variable.id,
                 kind: "read"
               )
    end

    test "repairs stale instruction variable reference metadata with an intact fingerprint" do
      project = project_fixture()
      sheet = sheet_fixture(project, %{name: "Hero", shortcut: "hero"})

      variable =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Health", "placeholder" => "0"}
        })

      screenplay = screenplay_fixture(project, %{name: "Instruction derivative repair"})

      assert {:ok, instruction_element} =
               Screenplays.create_element(screenplay, %{
                 type: "instruction",
                 data: %{
                   "assignments" => [
                     assignment(sheet.shortcut, variable.variable_name)
                   ]
                 }
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      instruction_node = linked_node(instruction_element)
      fingerprint = instruction_node.derivatives_fingerprint

      reference =
        Repo.get_by!(VariableReference,
          source_type: "flow_node",
          source_id: instruction_node.id,
          block_id: variable.id,
          kind: "write"
        )

      reference
      |> Ecto.Changeset.change(source_sheet: "stale")
      |> Repo.update!()

      assert Repo.reload!(instruction_node).derivatives_fingerprint ==
               fingerprint

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      assert %VariableReference{
               source_sheet: "hero",
               source_variable: source_variable,
               flow_node_id: flow_node_id
             } =
               Repo.get_by!(VariableReference,
                 source_type: "flow_node",
                 source_id: instruction_node.id,
                 block_id: variable.id,
                 kind: "write"
               )

      assert source_variable == variable.variable_name
      assert flow_node_id == instruction_node.id
    end

    test "updates the linked node type when an element changes mapping" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Type change"})

      {:ok, action} =
        Screenplays.create_element(screenplay, %{
          type: "action",
          content: "The door opens"
        })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      dialogue_node = linked_node(action)
      assert dialogue_node.type == "dialogue"

      assert {:ok, transition} =
               Screenplays.update_element(action, %{
                 type: "transition",
                 content: "CUT TO BLACK"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      exit_node = linked_node(transition)
      assert exit_node.id == dialogue_node.id
      assert exit_node.type == "exit"
      assert exit_node.data["label"] == "CUT TO BLACK"
      assert is_binary(exit_node.derivatives_fingerprint)
    end

    test "preserves unchanged connections and only replaces a changed segment" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Stable connections"})

      assert {:ok, scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      [first_action, second_action] =
        for index <- 1..2 do
          assert {:ok, action} =
                   Screenplays.create_element(screenplay, %{
                     type: "action",
                     content: "Action #{index}"
                   })

          action
        end

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      original_connections = connection_identity_map(flow.id)
      entry_node = linked_node(scene_heading)
      first_node = linked_node(first_action)
      second_node = linked_node(second_action)
      stable_key = {entry_node.id, "output", first_node.id, "input"}
      replaced_key = {first_node.id, "output", second_node.id, "input"}

      assert Map.has_key?(original_connections, stable_key)
      assert Map.has_key?(original_connections, replaced_key)

      stable_connection = Flows.get_connection_by_id!(original_connections[stable_key])
      assert {:ok, _connection} = Flows.update_connection(stable_connection, %{label: "Keep me"})

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      assert connection_identity_map(flow.id) == original_connections
      assert Flows.get_connection_by_id!(original_connections[stable_key]).label == "Keep me"

      assert {:ok, inserted_action} =
               Screenplays.insert_element_at(screenplay, 2, %{
                 type: "action",
                 content: "Inserted action"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      inserted_node = linked_node(inserted_action)
      changed_connections = connection_identity_map(flow.id)

      assert changed_connections[stable_key] == original_connections[stable_key]
      refute Map.has_key?(changed_connections, replaced_key)

      assert Map.has_key?(
               changed_connections,
               {first_node.id, "output", inserted_node.id, "input"}
             )

      assert Map.has_key?(
               changed_connections,
               {inserted_node.id, "output", second_node.id, "input"}
             )
    end

    test "preserves labelled connections between synced and manual nodes" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Cross-boundary connections"})

      assert {:ok, _scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      [first_action, second_action] =
        for index <- 1..2 do
          assert {:ok, action} =
                   Screenplays.create_element(screenplay, %{
                     type: "action",
                     content: "Action #{index}"
                   })

          action
        end

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)
      first_node = linked_node(first_action)
      second_node = linked_node(second_action)

      manual_exit =
        flow.id
        |> Flows.list_nodes()
        |> Enum.find(&(&1.type == "exit" and &1.source == "manual"))

      assert {:ok, boundary_connection} =
               Flows.create_connection(flow, first_node, manual_exit, %{
                 source_pin: "output",
                 target_pin: "input",
                 label: "Manual boundary"
               })

      assert {:ok, _inserted_action} =
               Screenplays.insert_element_at(screenplay, 2, %{
                 type: "action",
                 content: "Inserted action"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      preserved_connection = Flows.get_connection_by_id!(boundary_connection.id)
      assert preserved_connection.label == "Manual boundary"
      assert preserved_connection.source_node_id == first_node.id
      assert preserved_connection.target_node_id == manual_exit.id
      assert linked_node(second_action).id == second_node.id
    end

    test "orphan cleanup does not clear element links from another project" do
      project = project_fixture()
      foreign_project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Scoped orphan cleanup"})
      foreign_screenplay = screenplay_fixture(foreign_project, %{name: "Foreign screenplay"})

      assert {:ok, action} =
               Screenplays.create_element(screenplay, %{
                 type: "action",
                 content: "Owned action"
               })

      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)
      node_id = linked_node_id(action)

      assert {:ok, foreign_element} =
               Screenplays.import_element(
                 foreign_screenplay.id,
                 %{
                   type: "action",
                   position: 0,
                   content: "Foreign imported action"
                 },
                 %{linked_node_id: node_id}
               )

      assert {:ok, _deleted_action} = Screenplays.delete_element(action)
      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      assert Repo.reload!(foreign_element).linked_node_id == node_id
    end

    test "removes connections incident to synced nodes that become orphaned" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Orphan connection cleanup"})

      actions =
        for index <- 1..3 do
          assert {:ok, action} =
                   Screenplays.create_element(screenplay, %{
                     type: "action",
                     content: "Action #{index}"
                   })

          action
        end

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)
      orphaned_node = actions |> Enum.at(1) |> linked_node()

      assert Repo.exists?(
               from(connection in FlowConnection,
                 where:
                   connection.source_node_id == ^orphaned_node.id or
                     connection.target_node_id == ^orphaned_node.id
               )
             )

      assert {:ok, _deleted_action} = actions |> Enum.at(1) |> Screenplays.delete_element()
      assert {:ok, _flow} = Screenplays.sync_to_flow(screenplay)

      refute Repo.exists?(
               from(connection in FlowConnection,
                 where:
                   connection.source_node_id == ^orphaned_node.id or
                     connection.target_node_id == ^orphaned_node.id
               )
             )

      assert {:ok, _restored_node} = Flows.restore_node(flow.id, orphaned_node.id)

      refute Enum.any?(Flows.list_connections(flow.id), fn connection ->
               connection.source_node_id == orphaned_node.id or
                 connection.target_node_id == orphaned_node.id
             end)
    end

    test "rejects duplicate desired connections from a reused child page and rolls back" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Duplicate choices"})
      child = screenplay_fixture(project, %{name: "Branch", parent_id: screenplay.id})
      choice_id = Ecto.UUID.generate()

      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: "Narrator"
               })

      assert {:ok, _dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Choose"
               })

      choice = %{
        "id" => choice_id,
        "text" => "Continue",
        "linked_screenplay_id" => child.id
      }

      assert {:ok, response} =
               Screenplays.create_element(screenplay, %{
                 type: "response",
                 data: %{"choices" => [choice]}
               })

      for index <- 1..2 do
        assert {:ok, _child_action} =
                 Screenplays.create_element(child, %{
                   type: "action",
                   content: "Branch action #{index}"
                 })
      end

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      original_connections = connection_identity_map(flow.id)
      original_nodes = flow_node_identity_map(flow.id)

      assert {:ok, _response} =
               Screenplays.update_element(response, %{
                 data: %{
                   "choices" => [
                     choice,
                     %{
                       "id" => Ecto.UUID.generate(),
                       "text" => "Continue another way",
                       "linked_screenplay_id" => child.id
                     }
                   ]
                 }
               })

      assert {:error, {:duplicate_connection_spec, _key}} =
               Screenplays.sync_to_flow(screenplay)

      assert connection_identity_map(flow.id) == original_connections
      assert flow_node_identity_map(flow.id) == original_nodes
    end

    test "restores stale connections when creating their replacements fails" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Connection rollback"})

      assert {:ok, scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      [first_action, second_action, third_action] =
        for index <- 1..3 do
          assert {:ok, action} =
                   Screenplays.create_element(screenplay, %{
                     type: "action",
                     content: "Action #{index}"
                   })

          action
        end

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)
      entry_node = linked_node(scene_heading)
      first_node = linked_node(first_action)
      second_node = linked_node(second_action)
      third_node = linked_node(third_action)

      assert {:ok, stale_connection} =
               Flows.create_connection(flow, entry_node, second_node, %{
                 source_pin: "output",
                 target_pin: "input",
                 label: "Keep after rollback"
               })

      original_connections = connection_identity_map(flow.id)
      original_nodes = flow_node_identity_map(flow.id)

      assert {:ok, _third_action} =
               third_action
               |> Repo.reload!()
               |> Ecto.Changeset.change(linked_node_id: second_node.id)
               |> Repo.update()

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Screenplays.sync_to_flow(screenplay)

      assert Keyword.has_key?(errors, :target_node_id)
      assert connection_identity_map(flow.id) == original_connections
      assert Flows.get_connection_by_id!(stale_connection.id).label == "Keep after rollback"
      assert flow_node_identity_map(flow.id) == original_nodes
      assert Repo.get!(FlowNode, third_node.id).deleted_at == nil
      assert linked_node(first_action).id == first_node.id
    end

    test "batches derivative verification instead of adding queries per synced node" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Query budget"})

      assert {:ok, _scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      for index <- 1..19 do
        assert {:ok, _action} =
                 Screenplays.create_element(screenplay, %{
                   type: "action",
                   content: "Action #{index}"
                 })
      end

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      assert flow.id
             |> Flows.list_nodes()
             |> Enum.filter(&(&1.source == "screenplay_sync"))
             |> Enum.all?(&is_binary(&1.derivatives_fingerprint))

      {{:ok, small_flow}, small_queries} =
        capture_queries(fn -> Screenplays.sync_to_flow(screenplay) end)

      assert small_flow.id == flow.id

      for index <- 20..99 do
        assert {:ok, _action} =
                 Screenplays.create_element(screenplay, %{
                   type: "action",
                   content: "Action #{index}"
                 })
      end

      assert {:ok, _expanded_flow} = Screenplays.sync_to_flow(screenplay)

      {{:ok, large_flow}, large_queries} =
        capture_queries(fn -> Screenplays.sync_to_flow(screenplay) end)

      assert large_flow.id == flow.id
      assert length(large_queries) <= length(small_queries) + 10

      for queries <- [small_queries, large_queries] do
        refute Enum.any?(queries, &String.contains?(&1, ~s(UPDATE "flow_nodes")))
        refute Enum.any?(queries, &String.contains?(&1, ~s(DELETE FROM "flow_connections")))
        refute Enum.any?(queries, &String.contains?(&1, ~s(INSERT INTO "flow_connections")))
      end
    end

    test "batches unchanged speaker reference validation instead of adding queries per dialogue" do
      project = project_fixture()
      speaker = sheet_fixture(project, %{name: "Query Speaker"})
      screenplay = screenplay_fixture(project, %{name: "Speaker query budget"})

      assert {:ok, _scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      create_speaker_dialogues(screenplay, speaker, 1..19)
      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      assert 19 ==
               flow.id
               |> Flows.list_nodes()
               |> Enum.count(&(&1.data["speaker_sheet_id"] == speaker.id))

      {{:ok, small_flow}, small_queries} =
        capture_queries(fn -> Screenplays.sync_to_flow(screenplay) end)

      assert small_flow.id == flow.id

      create_speaker_dialogues(screenplay, speaker, 20..99)
      assert {:ok, _expanded_flow} = Screenplays.sync_to_flow(screenplay)

      assert 99 ==
               flow.id
               |> Flows.list_nodes()
               |> Enum.count(&(&1.data["speaker_sheet_id"] == speaker.id))

      {{:ok, large_flow}, large_queries} =
        capture_queries(fn -> Screenplays.sync_to_flow(screenplay) end)

      assert large_flow.id == flow.id
      assert length(large_queries) <= length(small_queries) + 10
    end

    test "keeps derivative verification query-bounded for condition nodes" do
      project = project_fixture()
      sheet = sheet_fixture(project, %{name: "Query variables", shortcut: "query.vars"})

      variable =
        block_fixture(sheet, %{
          type: "number",
          config: %{"label" => "Counter", "placeholder" => "0"}
        })

      screenplay = screenplay_fixture(project, %{name: "Condition query budget"})

      assert {:ok, _scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      create_condition_elements(
        screenplay,
        1..19,
        sheet.shortcut,
        variable.variable_name
      )

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      {{:ok, small_flow}, small_queries} =
        capture_queries(fn -> Screenplays.sync_to_flow(screenplay) end)

      assert small_flow.id == flow.id

      create_condition_elements(
        screenplay,
        20..99,
        sheet.shortcut,
        variable.variable_name
      )

      assert {:ok, _expanded_flow} = Screenplays.sync_to_flow(screenplay)

      {{:ok, large_flow}, large_queries} =
        capture_queries(fn -> Screenplays.sync_to_flow(screenplay) end)

      assert large_flow.id == flow.id
      assert length(large_queries) <= length(small_queries) + 10
    end

    test "keeps the protected entry when its source scene heading is removed" do
      project = project_fixture()
      screenplay = screenplay_fixture(project, %{name: "Protected entry"})

      assert {:ok, scene_heading} =
               Screenplays.create_element(screenplay, %{
                 type: "scene_heading",
                 content: "INT. ARCHIVE - NIGHT"
               })

      assert {:ok, flow} = Screenplays.sync_to_flow(screenplay)

      entry =
        flow.id
        |> Flows.list_nodes()
        |> Enum.find(&(&1.type == "entry"))

      assert entry.source == "screenplay_sync"
      assert {:ok, _deleted_element} = Screenplays.delete_element(scene_heading)

      assert {:ok, resynced_flow} = Screenplays.sync_to_flow(screenplay)
      assert resynced_flow.id == flow.id

      assert reloaded_entry = Repo.get!(FlowNode, entry.id)
      assert reloaded_entry.deleted_at == nil
    end
  end

  defp assignment(sheet_shortcut, variable_name) do
    %{
      "id" => Ecto.UUID.generate(),
      "sheet" => sheet_shortcut,
      "variable" => variable_name,
      "operator" => "set",
      "value" => "100",
      "value_type" => "literal"
    }
  end

  defp reverse_branch_flow(project, screenplay, linked_child, branch_content) do
    flow = flow_fixture(project, %{name: "Reverse branch flow"})

    assert {:ok, %{linked_flow_id: linked_flow_id}} =
             Screenplays.link_to_flow(screenplay, flow.id)

    assert linked_flow_id == flow.id

    nodes = Flows.list_nodes(flow.id)
    entry = Enum.find(nodes, &(&1.type == "entry"))
    exit_node = Enum.find(nodes, &(&1.type == "exit"))
    choice_id = Ecto.UUID.generate()

    dialogue_data = %{
      "speaker_sheet_id" => nil,
      "text" => "Choose a branch",
      "stage_directions" => "",
      "menu_text" => "Narrator",
      "audio_asset_id" => nil,
      "technical_id" => "",
      "localization_id" => "",
      "responses" => [
        %{
          "id" => choice_id,
          "text" => "Continue",
          "condition" => nil,
          "instruction" => nil,
          "linked_screenplay_id" => linked_child.id
        }
      ]
    }

    dialogue = node_fixture(flow, %{type: "dialogue", data: dialogue_data})

    branch =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{
          "speaker_sheet_id" => nil,
          "text" => "",
          "stage_directions" => branch_content,
          "menu_text" => "",
          "audio_asset_id" => nil,
          "technical_id" => "",
          "localization_id" => "",
          "responses" => []
        }
      })

    assert {:ok, _connection} =
             Flows.create_connection(flow, entry, dialogue, %{
               source_pin: "output",
               target_pin: "input"
             })

    assert {:ok, _connection} =
             Flows.create_connection(flow, dialogue, branch, %{
               source_pin: choice_id,
               target_pin: "input"
             })

    assert {:ok, _connection} =
             Flows.create_connection(flow, branch, exit_node, %{
               source_pin: "output",
               target_pin: "input"
             })

    {flow, choice_id}
  end

  defp root_choice_link(screenplay_id, choice_id) do
    screenplay_id
    |> Screenplays.list_elements()
    |> Enum.find(&(&1.type == "response"))
    |> LinkedPageCrud.find_choice(choice_id)
    |> Map.fetch!("linked_screenplay_id")
  end

  defp variable_condition(sheet_shortcut, variable_name) do
    %{
      "logic" => "all",
      "blocks" => [
        %{
          "id" => Ecto.UUID.generate(),
          "type" => "block",
          "logic" => "all",
          "rules" => [
            %{
              "id" => Ecto.UUID.generate(),
              "sheet" => sheet_shortcut,
              "variable" => variable_name,
              "operator" => "greater_than",
              "value" => "0"
            }
          ]
        }
      ]
    }
  end

  defp create_speaker_dialogues(screenplay, speaker, range) do
    for index <- range do
      assert {:ok, _character} =
               Screenplays.create_element(screenplay, %{
                 type: "character",
                 content: speaker.name,
                 data: %{"sheet_id" => speaker.id}
               })

      assert {:ok, _dialogue} =
               Screenplays.create_element(screenplay, %{
                 type: "dialogue",
                 content: "Dialogue #{index}"
               })
    end
  end

  defp create_condition_elements(screenplay, range, sheet_shortcut, variable_name) do
    for index <- range do
      assert {:ok, _conditional} =
               Screenplays.create_element(screenplay, %{
                 type: "conditional",
                 content: "Condition #{index}",
                 data: %{"condition" => variable_condition(sheet_shortcut, variable_name)}
               })
    end
  end

  defp linked_node(element) do
    node_id = linked_node_id(element)
    Repo.get!(FlowNode, node_id)
  end

  defp linked_node_id(element) do
    element
    |> Repo.reload!()
    |> Map.fetch!(:linked_node_id)
  end

  defp variable_reference_block_ids(node_id) do
    VariableReference
    |> where([reference], reference.source_type == "flow_node" and reference.source_id == ^node_id)
    |> order_by([reference], asc: reference.block_id)
    |> select([reference], reference.block_id)
    |> Repo.all()
  end

  defp connection_identity_map(flow_id) do
    flow_id
    |> Flows.list_connections()
    |> Map.new(fn connection ->
      key =
        {
          connection.source_node_id,
          connection.source_pin,
          connection.target_node_id,
          connection.target_pin
        }

      {key, connection.id}
    end)
  end

  defp flow_node_identity_map(flow_id) do
    flow_id
    |> Flows.list_nodes()
    |> Map.new(&{&1.id, {&1.type, &1.data, &1.deleted_at}})
  end

  defp drain_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp capture_queries(fun) when is_function(fun, 0) do
    handler_id = "flow-sync-query-budget-#{System.unique_integer([:positive])}"
    marker = make_ref()
    test_pid = self()

    :ok =
      :telemetry.attach(
        handler_id,
        [:storyarn, :repo, :query],
        fn _event, _measurements, %{query: query}, {pid, ref} ->
          if self() == pid, do: send(pid, {ref, query})
        end,
        {test_pid, marker}
      )

    try do
      {fun.(), drain_queries(marker)}
    after
      :telemetry.detach(handler_id)
    end
  end
end
