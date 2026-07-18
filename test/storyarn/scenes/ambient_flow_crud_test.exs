defmodule Storyarn.Scenes.AmbientFlowCrudTest do
  use Storyarn.DataCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Scenes.AmbientFlowCrud
  alias Storyarn.Scenes.SceneAmbientFlow

  describe "create_ambient_flow/2" do
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
end
