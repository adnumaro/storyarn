defmodule Storyarn.Scenes.SceneChildWriterIntegrityTest do
  use Storyarn.DataCase, async: true

  import Storyarn.FlowsFixtures
  import Storyarn.ProjectsFixtures
  import Storyarn.ScenesFixtures

  alias Storyarn.Scenes.AmbientFlowCrud
  alias Storyarn.Scenes.AnnotationCrud
  alias Storyarn.Scenes.LayerCrud
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.SceneAmbientFlow
  alias Storyarn.Scenes.SceneAnnotation
  alias Storyarn.Scenes.SceneLayer
  alias Storyarn.Scenes.TreeOperations

  describe "layer source and child integrity" do
    test "all layer writers reject a scene in trash without changing its layers" do
      project = project_fixture()
      scene = scene_fixture(project)
      layer = layer_fixture(scene, %{"name" => "Protected"})
      layer_ids = scene.id |> LayerCrud.list_layers() |> Enum.map(& &1.id)
      soft_delete!(scene)

      assert {:error, :scene_not_active} =
               LayerCrud.create_layer(scene.id, %{"name" => "Forbidden"})

      assert {:error, :scene_not_active} =
               LayerCrud.update_layer(layer, %{"name" => "Forbidden"})

      assert {:error, :scene_not_active} =
               LayerCrud.toggle_layer_visibility(layer)

      assert {:error, :scene_not_active} =
               LayerCrud.delete_layer(layer)

      assert {:error, :scene_not_active} =
               LayerCrud.reorder_layers(scene.id, Enum.reverse(layer_ids))

      persisted = Repo.get!(SceneLayer, layer.id)
      assert persisted.name == "Protected"
      assert persisted.visible
      assert Enum.map(LayerCrud.list_layers(scene.id), & &1.id) == layer_ids
    end

    test "all layer writers reject an active scene whose project is in trash" do
      project = project_fixture()
      scene = scene_fixture(project)
      layer = layer_fixture(scene, %{"name" => "Protected"})
      layer_ids = scene.id |> LayerCrud.list_layers() |> Enum.map(& &1.id)
      soft_delete!(project)

      assert {:error, :project_not_active} =
               LayerCrud.create_layer(scene.id, %{"name" => "Forbidden"})

      assert {:error, :project_not_active} =
               LayerCrud.update_layer(layer, %{"name" => "Forbidden"})

      assert {:error, :project_not_active} =
               LayerCrud.toggle_layer_visibility(layer)

      assert {:error, :project_not_active} =
               LayerCrud.delete_layer(layer)

      assert {:error, :project_not_active} =
               LayerCrud.reorder_layers(scene.id, Enum.reverse(layer_ids))

      persisted = Repo.get!(SceneLayer, layer.id)
      assert persisted.name == "Protected"
      assert persisted.visible
      assert Enum.map(LayerCrud.list_layers(scene.id), & &1.id) == layer_ids
    end

    test "updates and toggles re-read the child and reject a forged scene owner" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      stale_layer = layer_fixture(scene, %{"name" => "Original"})

      Repo.update!(
        Ecto.Changeset.change(stale_layer,
          name: "Persisted latest",
          visible: false
        )
      )

      assert {:ok, updated} =
               LayerCrud.update_layer(stale_layer, %{"fog_enabled" => true})

      assert updated.name == "Persisted latest"
      assert updated.fog_enabled
      refute updated.visible

      assert {:ok, toggled} = LayerCrud.toggle_layer_visibility(stale_layer)
      assert toggled.visible

      forged_layer = %{stale_layer | scene_id: other_scene.id}

      assert {:error, :layer_not_found} =
               LayerCrud.update_layer(forged_layer, %{"name" => "Forbidden"})

      assert Repo.get!(SceneLayer, stale_layer.id).name == "Persisted latest"
    end

    test "reorder rejects duplicate, malformed and foreign layer IDs atomically" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      local_layer = layer_fixture(scene)
      foreign_layer = layer_fixture(other_scene)
      original = positions(SceneLayer, scene_id: scene.id)

      assert {:error, {:invalid_scene_layer_reorder, _ids}} =
               LayerCrud.reorder_layers(scene.id, [local_layer.id, local_layer.id])

      assert positions(SceneLayer, scene_id: scene.id) == original

      assert {:error, {:invalid_scene_layer_reorder, _ids}} =
               LayerCrud.reorder_layers(scene.id, [local_layer.id, "invalid"])

      assert positions(SceneLayer, scene_id: scene.id) == original

      assert {:error, {:invalid_scene_layer_reorder, _ids}} =
               LayerCrud.reorder_layers(scene.id, [local_layer.id, foreign_layer.id])

      assert positions(SceneLayer, scene_id: scene.id) == original
    end
  end

  describe "annotation source, child and effective-layer integrity" do
    test "all annotation writers reject a scene in trash" do
      project = project_fixture()
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene, %{"text" => "Protected"})
      soft_delete!(scene)

      assert {:error, :scene_not_active} =
               AnnotationCrud.create_annotation(scene.id, annotation_attrs("Forbidden"))

      assert {:error, :scene_not_active} =
               AnnotationCrud.update_annotation(annotation, %{"text" => "Forbidden"})

      assert {:error, :scene_not_active} =
               AnnotationCrud.move_annotation(annotation, 1.0, 2.0)

      assert {:error, :scene_not_active} =
               AnnotationCrud.delete_annotation(annotation)

      persisted = Repo.get!(SceneAnnotation, annotation.id)
      assert persisted.text == "Protected"
      assert persisted.position_x == annotation.position_x
      assert persisted.position_y == annotation.position_y
    end

    test "all annotation writers reject an active scene whose project is in trash" do
      project = project_fixture()
      scene = scene_fixture(project)
      annotation = annotation_fixture(scene, %{"text" => "Protected"})
      soft_delete!(project)

      assert {:error, :project_not_active} =
               AnnotationCrud.create_annotation(scene.id, annotation_attrs("Forbidden"))

      assert {:error, :project_not_active} =
               AnnotationCrud.update_annotation(annotation, %{"text" => "Forbidden"})

      assert {:error, :project_not_active} =
               AnnotationCrud.move_annotation(annotation, 1.0, 2.0)

      assert {:error, :project_not_active} =
               AnnotationCrud.delete_annotation(annotation)

      assert Repo.get!(SceneAnnotation, annotation.id).text == "Protected"
    end

    test "unrelated updates re-read the row and validate its persisted effective layer" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      local_layer = layer_fixture(scene)
      foreign_layer = layer_fixture(other_scene)
      stale_annotation = annotation_fixture(scene, %{"layer_id" => local_layer.id})

      Repo.update!(
        Ecto.Changeset.change(stale_annotation,
          text: "Persisted latest",
          color: "#ff0000"
        )
      )

      assert {:ok, updated} =
               AnnotationCrud.update_annotation(stale_annotation, %{
                 "font_size" => "lg"
               })

      assert updated.text == "Persisted latest"
      assert updated.color == "#ff0000"
      assert updated.font_size == "lg"

      Repo.update_all(
        from(annotation in SceneAnnotation,
          where: annotation.id == ^stale_annotation.id
        ),
        set: [layer_id: foreign_layer.id]
      )

      assert {:error, {:scene_layer_ownership_mismatch, foreign_layer_id, scene_id, foreign_scene_id}} =
               AnnotationCrud.update_annotation(stale_annotation, %{
                 "text" => "Forbidden"
               })

      assert foreign_layer_id == foreign_layer.id
      assert scene_id == scene.id
      assert foreign_scene_id == other_scene.id

      assert {:error, {:scene_layer_ownership_mismatch, ^foreign_layer_id, ^scene_id, ^foreign_scene_id}} =
               AnnotationCrud.move_annotation(stale_annotation, 1.0, 2.0)

      persisted = Repo.get!(SceneAnnotation, stale_annotation.id)
      assert persisted.text == "Persisted latest"
      assert persisted.position_x == stale_annotation.position_x
      assert persisted.position_y == stale_annotation.position_y
    end

    test "a forged scene owner cannot update or delete another scene's annotation" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      annotation = annotation_fixture(scene)
      forged_annotation = %{annotation | scene_id: other_scene.id}

      assert {:error, :annotation_not_found} =
               AnnotationCrud.update_annotation(forged_annotation, %{
                 "text" => "Forbidden"
               })

      assert {:error, :annotation_not_found} =
               AnnotationCrud.delete_annotation(forged_annotation)

      assert Repo.get!(SceneAnnotation, annotation.id).text == annotation.text
    end
  end

  describe "ambient flow source, child and reorder integrity" do
    test "delete and reorder reject a scene in trash" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      {:ok, ambient_flow} = AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => flow.id})
      soft_delete!(scene)

      assert {:error, :scene_not_active} =
               AmbientFlowCrud.delete_ambient_flow(ambient_flow)

      assert {:error, :scene_not_active} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [ambient_flow.id])

      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).position == ambient_flow.position
    end

    test "all ambient-flow writers reject an active scene whose project is in trash" do
      project = project_fixture()
      scene = scene_fixture(project)
      flow = flow_fixture(project)
      replacement_flow = flow_fixture(project)
      {:ok, ambient_flow} = AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => flow.id})
      soft_delete!(project)

      assert {:error, :project_not_active} =
               AmbientFlowCrud.create_ambient_flow(scene.id, %{
                 "flow_id" => replacement_flow.id
               })

      assert {:error, :project_not_active} =
               AmbientFlowCrud.update_ambient_flow(ambient_flow, %{
                 "flow_id" => replacement_flow.id
               })

      assert {:error, :project_not_active} =
               AmbientFlowCrud.delete_ambient_flow(ambient_flow)

      assert {:error, :project_not_active} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [ambient_flow.id])

      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).flow_id == flow.id
    end

    test "reorder rejects duplicate, malformed and foreign IDs atomically" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      first_flow = flow_fixture(project)
      second_flow = flow_fixture(project)
      foreign_flow = flow_fixture(project)

      {:ok, first} =
        AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => first_flow.id})

      {:ok, second} =
        AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => second_flow.id})

      {:ok, foreign} =
        AmbientFlowCrud.create_ambient_flow(other_scene.id, %{
          "flow_id" => foreign_flow.id
        })

      original = positions(SceneAmbientFlow, scene_id: scene.id)

      assert {:error, {:invalid_scene_ambient_flow_reorder, _ids}} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [second.id, second.id])

      assert positions(SceneAmbientFlow, scene_id: scene.id) == original

      assert {:error, {:invalid_scene_ambient_flow_reorder, _ids}} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [second.id, "invalid"])

      assert positions(SceneAmbientFlow, scene_id: scene.id) == original

      assert {:error, {:invalid_scene_ambient_flow_reorder, _ids}} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [second.id])

      assert positions(SceneAmbientFlow, scene_id: scene.id) == original

      assert {:error, {:invalid_scene_ambient_flow_reorder, []}} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [])

      assert positions(SceneAmbientFlow, scene_id: scene.id) == original

      assert {:error, {:invalid_scene_ambient_flow_reorder, _ids}} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [second.id, foreign.id])

      assert positions(SceneAmbientFlow, scene_id: scene.id) == original

      assert {:ok, reordered} =
               AmbientFlowCrud.reorder_ambient_flows(scene.id, [
                 Integer.to_string(second.id),
                 Integer.to_string(first.id)
               ])

      assert Enum.map(reordered, & &1.id) == [second.id, first.id]
    end

    test "delete re-reads the child and rejects a forged scene owner" do
      project = project_fixture()
      scene = scene_fixture(project)
      other_scene = scene_fixture(project)
      flow = flow_fixture(project)
      {:ok, ambient_flow} = AmbientFlowCrud.create_ambient_flow(scene.id, %{"flow_id" => flow.id})
      forged_ambient_flow = %{ambient_flow | scene_id: other_scene.id}

      assert {:error, :ambient_flow_not_found} =
               AmbientFlowCrud.delete_ambient_flow(forged_ambient_flow)

      assert Repo.get!(SceneAmbientFlow, ambient_flow.id).flow_id == flow.id
    end
  end

  describe "scene tree reorder integrity" do
    test "rejects a project in trash without changing positions" do
      project = project_fixture()
      first = scene_fixture(project)
      second = scene_fixture(project)
      original = positions(Scene, project_id: project.id, parent_id: nil)
      soft_delete!(project)

      assert {:error, :project_not_active} =
               TreeOperations.reorder_scenes(project.id, nil, [second.id, first.id])

      assert positions(Scene,
               project_id: project.id,
               parent_id: nil
             ) == original
    end

    test "rejects foreign and deleted parents" do
      project = project_fixture()
      scene = scene_fixture(project)
      foreign_parent = scene_fixture(project_fixture())
      deleted_parent = scene_fixture(project)
      soft_delete!(deleted_parent)
      original = Repo.get!(Scene, scene.id).position

      assert {:error, {:invalid_project_reference, _context, foreign_parent_id}} =
               TreeOperations.reorder_scenes(project.id, foreign_parent.id, [scene.id])

      assert foreign_parent_id == foreign_parent.id

      assert {:error, {:invalid_project_reference, _context, deleted_parent_id}} =
               TreeOperations.reorder_scenes(project.id, deleted_parent.id, [scene.id])

      assert deleted_parent_id == deleted_parent.id
      assert Repo.get!(Scene, scene.id).position == original
    end

    test "rejects duplicate, malformed, foreign-container and trashed scene IDs atomically" do
      project = project_fixture()
      parent = scene_fixture(project)
      first = scene_fixture(project, %{parent_id: parent.id})
      second = scene_fixture(project, %{parent_id: parent.id})
      root_scene = scene_fixture(project)
      trashed = scene_fixture(project, %{parent_id: parent.id})
      soft_delete!(trashed)
      original = positions(Scene, project_id: project.id, parent_id: parent.id)

      assert {:error, {:invalid_scene_reorder, _ids}} =
               TreeOperations.reorder_scenes(project.id, parent.id, [first.id, first.id])

      assert positions(Scene,
               project_id: project.id,
               parent_id: parent.id
             ) == original

      assert {:error, {:invalid_scene_reorder, _ids}} =
               TreeOperations.reorder_scenes(project.id, parent.id, [first.id, "invalid"])

      assert {:error, {:invalid_scene_reorder, _ids}} =
               TreeOperations.reorder_scenes(project.id, parent.id, [first.id, root_scene.id])

      assert {:error, {:invalid_scene_reorder, _ids}} =
               TreeOperations.reorder_scenes(project.id, parent.id, [first.id, trashed.id])

      assert positions(Scene,
               project_id: project.id,
               parent_id: parent.id
             ) == original

      assert {:ok, reordered} =
               TreeOperations.reorder_scenes(project.id, Integer.to_string(parent.id), [
                 Integer.to_string(second.id),
                 Integer.to_string(first.id)
               ])

      assert Enum.map(reordered, & &1.id) == [second.id, first.id]
    end
  end

  defp annotation_attrs(text) do
    %{"text" => text, "position_x" => 10.0, "position_y" => 20.0}
  end

  defp positions(schema, filters) do
    query =
      Enum.reduce(filters, schema, fn
        {:parent_id, nil}, query ->
          where(query, [row], is_nil(row.parent_id))

        {field, value}, query ->
          where(query, [row], field(row, ^field) == ^value)
      end)

    Repo.all(from(row in query, order_by: [asc: row.id], select: {row.id, row.position}))
  end

  defp soft_delete!(struct) do
    deleted_at = DateTime.truncate(DateTime.utc_now(), :second)
    Repo.update!(Ecto.Changeset.change(struct, deleted_at: deleted_at))
  end
end
