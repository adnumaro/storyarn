defmodule Storyarn.References.EntityTrackerTest do
  use Storyarn.DataCase, async: false

  import Ecto.Query
  import Storyarn.AccountsFixtures
  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.References
  alias Storyarn.References.EntityReference
  alias Storyarn.Repo

  test "propagates a later source error and rolls back earlier replacements" do
    user = user_fixture()
    project = project_fixture(user)
    original_target = sheet_fixture(project, %{name: "Original target"})
    replacement_target = sheet_fixture(project, %{name: "Replacement target"})
    flow = flow_fixture(project, %{name: "Reference rebuild"})

    first_node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"speaker_sheet_id" => original_target.id, "text" => "First"}
      })

    second_node =
      node_fixture(flow, %{
        type: "dialogue",
        data: %{"text" => "Second"}
      })

    assert reference_count(first_node.id, original_target.id) == 1
    assert reference_count(first_node.id, replacement_target.id) == 0

    first_node =
      Repo.update!(
        Ecto.Changeset.change(first_node,
          data: %{
            "speaker_sheet_id" => replacement_target.id,
            "text" => "First changed"
          }
        )
      )

    install_second_source_failure_trigger(first_node.id, second_node.id)

    assert {:error, {:flow_node_project_mismatch, node_id, project_id}} =
             References.rebuild_project_entity_references(project.id)

    assert node_id == second_node.id
    assert project_id == project.id
    assert Repo.reload!(second_node).deleted_at == nil
    assert reference_count(first_node.id, original_target.id) == 1
    assert reference_count(first_node.id, replacement_target.id) == 0
  end

  defp reference_count(source_id, target_id) do
    Repo.aggregate(
      from(reference in EntityReference,
        where:
          reference.source_type == "flow_node" and
            reference.source_id == ^source_id and
            reference.target_type == "sheet" and
            reference.target_id == ^target_id
      ),
      :count
    )
  end

  defp install_second_source_failure_trigger(first_node_id, second_node_id) do
    Repo.query!(
      "SELECT set_config('storyarn.test_first_reference_node_id', $1, true)",
      [to_string(first_node_id)]
    )

    Repo.query!(
      "SELECT set_config('storyarn.test_second_reference_node_id', $1, true)",
      [to_string(second_node_id)]
    )

    Repo.query!("""
    CREATE FUNCTION storyarn_test_fail_second_reference_rebuild()
    RETURNS trigger AS $$
    BEGIN
      IF OLD.source_type = 'flow_node'
         AND OLD.source_id =
           current_setting('storyarn.test_first_reference_node_id')::bigint THEN
        UPDATE flow_nodes
        SET deleted_at = NOW()
        WHERE id =
          current_setting('storyarn.test_second_reference_node_id')::bigint;
      END IF;

      RETURN OLD;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER storyarn_test_fail_second_reference_rebuild
    BEFORE DELETE ON entity_references
    FOR EACH ROW
    EXECUTE FUNCTION storyarn_test_fail_second_reference_rebuild()
    """)
  end
end
