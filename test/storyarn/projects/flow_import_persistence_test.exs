defmodule Storyarn.Projects.FlowImportPersistenceTest do
  use Storyarn.DataCase, async: true

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.ProjectsFixtures

  alias Storyarn.Projects.FlowImportPersistence
  alias Storyarn.Projects.Persistence.FlowConnectionRecord
  alias Storyarn.Projects.Persistence.FlowNodeRecord
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SequenceConfigRecord
  alias Storyarn.Repo
  alias Storyarn.Shared.TimeHelpers

  setup do
    project = project_fixture(user_fixture())
    %{project: project}
  end

  describe "shortcut conflict persistence" do
    test "lists active shortcuts and detects only existing conflicts", %{project: project} do
      active = import_flow!(project, %{name: "Active", shortcut: "active"})
      deleted = import_flow!(project, %{name: "Deleted", shortcut: "deleted"})

      assert {1, nil} = FlowImportPersistence.soft_delete_by_shortcut(project.id, deleted.shortcut)

      assert FlowImportPersistence.list_shortcuts(project.id) == MapSet.new([active.shortcut])

      assert FlowImportPersistence.detect_shortcut_conflicts(project.id, ["active", "deleted", "missing"]) ==
               ["active"]

      assert FlowImportPersistence.detect_shortcut_conflicts(project.id, []) == []
    end

    test "returns an empty update result for a missing shortcut", %{project: project} do
      assert {0, nil} = FlowImportPersistence.soft_delete_by_shortcut(project.id, "missing")
    end
  end

  describe "import_flow/2" do
    test "inserts a Flow without editor side effects", %{project: project} do
      flow = import_flow!(project, %{name: "Imported Flow", shortcut: "imported"})

      assert flow.name == "Imported Flow"

      assert Repo.aggregate(
               from(node in FlowNodeRecord, where: node.flow_id == ^flow.id),
               :count
             ) == 0
    end

    test "returns a changeset for invalid input", %{project: project} do
      assert {:error, changeset} = FlowImportPersistence.import_flow(project.id, %{})
      assert errors_on(changeset).name
    end
  end

  describe "import_node/2" do
    test "inserts a node and derives its word count", %{project: project} do
      flow = import_flow!(project)

      assert {:ok, node} =
               FlowImportPersistence.import_node(flow.id, %{
                 type: "dialogue",
                 position_x: 200.0,
                 position_y: 300.0,
                 data: %{"text" => "Imported dialogue"}
               })

      assert node.flow_id == flow.id
      assert node.word_count == 2
      assert is_binary(node.data["localization_id"])
    end

    test "preserves flow-wide hub and entry invariants", %{project: project} do
      flow = import_flow!(project)

      assert {:error, :hub_id_required} =
               FlowImportPersistence.import_node(flow.id, %{
                 type: "hub",
                 data: %{"hub_id" => "   "}
               })

      assert {:ok, _hub} =
               FlowImportPersistence.import_node(flow.id, %{
                 type: "hub",
                 data: %{"hub_id" => "shared-hub"}
               })

      assert {:error, :hub_id_not_unique} =
               FlowImportPersistence.import_node(flow.id, %{
                 type: "hub",
                 data: %{"hub_id" => "shared-hub"}
               })

      assert {:ok, _entry} = FlowImportPersistence.import_node(flow.id, %{type: "entry", data: %{}})
      assert {:error, :entry_node_exists} = FlowImportPersistence.import_node(flow.id, %{type: "entry", data: %{}})
    end

    test "persists a sequence and its required config atomically", %{project: project} do
      flow = import_flow!(project)

      assert {:ok, sequence} =
               FlowImportPersistence.import_node(flow.id, %{
                 type: "sequence",
                 data: %{},
                 sequence_config: %{name: "Act I", width: 640.0, height: 360.0}
               })

      assert %SequenceConfigRecord{name: "Act I", width: 640.0, height: 360.0} =
               sequence.sequence_config

      assert Repo.get!(SequenceConfigRecord, sequence.id).name == "Act I"
    end
  end

  describe "deferred linking" do
    test "links Flow and node parents after IDs have been remapped", %{project: project} do
      parent_flow = import_flow!(project, %{name: "Parent", shortcut: "parent"})
      child_flow = import_flow!(project, %{name: "Child", shortcut: "child"})

      assert %FlowRecord{parent_id: parent_id} =
               FlowImportPersistence.link_flow_parent(child_flow, parent_flow.id)

      assert parent_id == parent_flow.id

      sequence = import_sequence!(parent_flow, "Act I")
      assert {:ok, node} = FlowImportPersistence.import_node(parent_flow.id, %{type: "annotation", data: %{}})

      assert {:ok, %FlowNodeRecord{parent_id: sequence_id}} =
               FlowImportPersistence.link_node_parent(node, sequence.id)

      assert sequence_id == sequence.id
    end

    test "rejects a cyclic imported node hierarchy", %{project: project} do
      flow = import_flow!(project)
      parent = import_sequence!(flow, "Parent")
      child = import_sequence!(flow, "Child")

      assert {:ok, child} = FlowImportPersistence.link_node_parent(child, parent.id)
      assert {:error, :cyclic_parent} = FlowImportPersistence.link_node_parent(parent, child.id)
    end

    test "updates deferred node data", %{project: project} do
      flow = import_flow!(project)
      assert {:ok, node} = FlowImportPersistence.import_node(flow.id, %{type: "subflow", data: %{}})

      assert {1, nil} =
               FlowImportPersistence.link_node_data(node.id, %{"referenced_flow_id" => flow.id})

      assert Repo.get!(FlowNodeRecord, node.id).data["referenced_flow_id"] == flow.id
    end
  end

  describe "bulk_insert_connections/2" do
    test "inserts connections in chunks and handles an empty batch", %{project: project} do
      flow = import_flow!(project)
      assert {:ok, entry} = FlowImportPersistence.import_node(flow.id, %{type: "entry", data: %{}})
      assert {:ok, exit} = FlowImportPersistence.import_node(flow.id, %{type: "exit", data: %{}})
      now = TimeHelpers.now()

      attrs = [
        %{
          flow_id: flow.id,
          source_node_id: entry.id,
          target_node_id: exit.id,
          source_pin: "output",
          target_pin: "input",
          inserted_at: now,
          updated_at: now
        }
      ]

      assert [%{id: id}] = FlowImportPersistence.bulk_insert_connections(attrs, 1)
      assert %FlowConnectionRecord{} = Repo.get!(FlowConnectionRecord, id)
      assert FlowImportPersistence.bulk_insert_connections([]) == []
    end
  end

  defp import_flow!(project, attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        name: "Imported Flow #{unique}",
        shortcut: "imported-flow-#{unique}"
      })

    {:ok, flow} = FlowImportPersistence.import_flow(project.id, attrs)
    flow
  end

  defp import_sequence!(flow, name) do
    {:ok, sequence} =
      FlowImportPersistence.import_node(flow.id, %{
        type: "sequence",
        data: %{},
        sequence_config: %{name: name}
      })

    sequence
  end
end
