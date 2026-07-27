defmodule Storyarn.Screenplays.FlowSyncTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.LocalizationFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScreenplaysFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Collaboration
  alias Storyarn.Flows
  alias Storyarn.Flows.FlowNode
  alias Storyarn.Flows.VariableReference
  alias Storyarn.Localization
  alias Storyarn.Localization.LocalizedText
  alias Storyarn.Repo
  alias Storyarn.Screenplays
  alias Storyarn.Shared.WordCount

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

    test "keeps an unchanged twenty-node resync within its query budget" do
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

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert {:ok, resynced_flow} = Screenplays.sync_to_flow(screenplay)
      assert resynced_flow.id == flow.id

      queries = drain_queries(marker)

      assert length(queries) <= 120
      refute Enum.any?(queries, &String.contains?(&1, ~s(UPDATE "flow_nodes")))
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

  defp drain_queries(marker, queries \\ []) do
    receive do
      {^marker, query} -> drain_queries(marker, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end
end
