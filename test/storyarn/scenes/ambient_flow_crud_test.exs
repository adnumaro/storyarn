defmodule Storyarn.Scenes.AmbientFlowCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures
  import Storyarn.SheetsFixtures

  alias Storyarn.Platform.Collaboration
  alias Storyarn.Projects.References.VariableReference
  alias Storyarn.Scenes.AmbientFlowCrud
  alias Storyarn.Scenes.Persistence.FlowRecord
  alias Storyarn.Scenes.SceneAmbientFlow

  describe "dashboard invalidation" do
    test "create invalidates once after commit while a rejected link emits nothing" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      foreign_flow = flow_fixture(project_fixture())
      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, _ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id
               })

      assert_dashboard_invalidation_once()

      assert {:error, :cross_project} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => foreign_flow.id
               })

      refute_dashboard_invalidation()
    end

    test "update invalidates changed data once while failure and no-op emit nothing" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      foreign_flow = flow_fixture(project_fixture())

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id
               })

      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, updated} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "priority" => 10
               })

      assert_dashboard_invalidation_once()

      assert {:ok, unchanged} =
               AmbientFlowCrud.update_ambient_flow(updated, %{
                 "priority" => 10
               })

      assert unchanged.priority == 10
      refute_dashboard_invalidation()

      assert {:error, :cross_project} =
               AmbientFlowCrud.update_ambient_flow(updated, %{
                 "flow_id" => foreign_flow.id
               })

      refute_dashboard_invalidation()
    end

    test "delete invalidates once while deleting stale input emits nothing" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id
               })

      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, _deleted} =
               AmbientFlowCrud.delete_ambient_flow(ambient_flow)

      assert_dashboard_invalidation_once()

      assert {:error, :ambient_flow_not_found} =
               AmbientFlowCrud.delete_ambient_flow(ambient_flow)

      refute_dashboard_invalidation()
    end

    test "reorder invalidates only when the persisted order changes" do
      project = project_fixture()
      scene = scene_fixture(project)
      first_flow = flow_fixture(project)
      second_flow = flow_fixture(project)

      assert {:ok, first} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => first_flow.id
               })

      assert {:ok, second} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => second_flow.id
               })

      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:ok, reordered} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [
                 second.id,
                 first.id
               ])

      assert Enum.map(reordered, & &1.id) == [second.id, first.id]
      assert_dashboard_invalidation_once()

      assert {:ok, unchanged} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [
                 second.id,
                 first.id
               ])

      assert Enum.map(unchanged, & &1.id) == [second.id, first.id]
      refute_dashboard_invalidation()

      assert {:error, {:invalid_scene_ambient_flow_reorder, _ids}} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [
                 second.id,
                 second.id
               ])

      refute_dashboard_invalidation()
    end
  end

  describe "create_ambient_flow/2" do
    test "preloads the linked flow through the Scenes-owned read model" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project, %{name: "Ambient narrative"})

      assert {:ok, _ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => flow.id})

      assert [%SceneAmbientFlow{flow: %FlowRecord{} = linked_flow}] =
               AmbientFlowCrud.list_ambient_flows(scene.id)

      assert linked_flow.id == flow.id
      assert linked_flow.name == "Ambient narrative"
      assert linked_flow.project_id == project.id
    end

    test "creates a link only when both scene and flow are active in the same project" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id,
                 "trigger_type" => "on_enter"
               })

      assert ambient_flow.scene_id == scene.id
      assert ambient_flow.flow_id == flow.id
    end

    test "keeps on-event variable references synchronized across create, update, and delete" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      sheet = sheet_fixture(project, %{shortcut: "hero.profile"})
      block = block_fixture(sheet, %{type: "number", variable_name: "health"})

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id,
                 "trigger_type" => "on_event",
                 "trigger_config" => %{"variable_ref" => "hero.profile.health"}
               })

      assert ambient_variable_reference?(ambient_flow.id, block.id)

      assert {:ok, timed} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "trigger_type" => "timed",
                 "trigger_config" => %{"interval_ms" => 1_000}
               })

      refute ambient_variable_reference?(ambient_flow.id, block.id)

      assert {:ok, restored_event} =
               AmbientFlowCrud.update_ambient_flow(timed, %{
                 "trigger_type" => "on_event",
                 "trigger_config" => %{"variable_ref" => "hero.profile.health"}
               })

      assert ambient_variable_reference?(ambient_flow.id, block.id)
      assert {:ok, _deleted} = AmbientFlowCrud.delete_ambient_flow(restored_event)
      refute ambient_variable_reference?(ambient_flow.id, block.id)
    end

    test "rejects a soft-deleted scene without inserting a link" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      soft_delete(scene)

      assert {:error, :scene_not_active} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => flow.id})

      refute Repo.exists?(
               from(ambient_flow in SceneAmbientFlow,
                 where: ambient_flow.scene_id == ^scene.id
               )
             )
    end

    test "rejects a soft-deleted flow without inserting a link" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      soft_delete(flow)

      assert {:error, :flow_not_active} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => flow.id})

      refute Repo.exists?(
               from(ambient_flow in SceneAmbientFlow,
                 where: ambient_flow.scene_id == ^scene.id
               )
             )
    end

    test "rejects an active flow from another project" do
      scene = scene_fixture(project_fixture())
      foreign_flow = flow_fixture(project_fixture())

      assert {:error, :cross_project} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => foreign_flow.id
               })
    end
  end

  describe "update_ambient_flow/2" do
    test "returns validation errors even when casting produced no changes" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id,
                 "priority" => 7
               })

      :ok = Collaboration.subscribe_dashboard(project.id)

      assert {:error, %Ecto.Changeset{} = changeset} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "priority" => "not-an-integer"
               })

      refute changeset.valid?
      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).priority == 7
      refute_dashboard_invalidation()
    end

    test "validates a requested flow change under the scene and flow locks" do
      project = project_fixture()
      scene = scene_fixture(project)
      original_flow = flow_fixture(project)
      replacement_flow = flow_fixture(project)
      deleted_flow = flow_fixture(project)
      foreign_flow = flow_fixture(project_fixture())

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => original_flow.id
               })

      assert {:ok, updated_ambient_flow} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "flow_id" => replacement_flow.id
               })

      assert updated_ambient_flow.flow_id == replacement_flow.id

      assert {:error, :cross_project} =
               AmbientFlowCrud.update_ambient_flow(updated_ambient_flow, %{
                 "flow_id" => foreign_flow.id
               })

      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).flow_id ==
               replacement_flow.id

      soft_delete(deleted_flow)

      assert {:error, :flow_not_active} =
               AmbientFlowCrud.update_ambient_flow(updated_ambient_flow, %{
                 "flow_id" => deleted_flow.id
               })

      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).flow_id ==
               replacement_flow.id
    end

    test "rejects updates once the owning scene is soft-deleted" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => flow.id,
                 "priority" => 1
               })

      soft_delete(scene)

      assert {:error, :scene_not_active} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "priority" => 99
               })

      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).priority == 1
    end

    test "reloads stale input under lock before validating the persisted flow" do
      project = project_fixture()
      scene = scene_fixture(project)
      original_flow = flow_fixture(project)
      replacement_flow = flow_fixture(project)

      assert {:ok, ambient_flow} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => original_flow.id
               })

      stale_ambient_flow = ambient_flow

      assert {:ok, _updated_ambient_flow} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "flow_id" => replacement_flow.id
               })

      soft_delete(original_flow)

      assert {:ok, updated_ambient_flow} =
               AmbientFlowCrud.update_ambient_flow(stale_ambient_flow, %{
                 "priority" => 42
               })

      assert updated_ambient_flow.flow_id == replacement_flow.id
      assert updated_ambient_flow.priority == 42
    end
  end

  defp soft_delete(struct) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
    Repo.update!(Ecto.Changeset.change(struct, deleted_at: deleted_at))
  end

  defp ambient_variable_reference?(ambient_flow_id, block_id) do
    Repo.exists?(
      from(reference in VariableReference,
        where:
          reference.source_type == "scene_ambient_flow" and
            reference.source_id == ^ambient_flow_id and
            reference.block_id == ^block_id and
            reference.kind == "read"
      )
    )
  end

  defp assert_dashboard_invalidation_once do
    assert_receive {:dashboard_invalidate, :scenes}
    refute_receive {:dashboard_invalidate, :scenes}, 10
  end

  defp refute_dashboard_invalidation do
    refute_receive {:dashboard_invalidate, :scenes}, 10
  end
end
