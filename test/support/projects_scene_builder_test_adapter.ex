defmodule StoryarnTest.ProjectsSceneBuilderTestAdapter do
  @moduledoc false

  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Versioning.Builders.SceneBuilder
  alias Storyarn.Repo

  def build_snapshot(scene), do: scene |> scene_record!() |> SceneBuilder.build_snapshot()
  def build_capture_snapshot(scene), do: scene |> scene_record!() |> SceneBuilder.build_capture_snapshot()

  defdelegate validate_portable_snapshot(snapshot), to: SceneBuilder
  defdelegate instantiate_snapshot(project_id, snapshot, opts \\ []), to: SceneBuilder
  defdelegate diff_snapshots(old_snapshot, new_snapshot), to: SceneBuilder

  defp scene_record!(%SceneRecord{} = scene), do: scene
  defp scene_record!(%{id: scene_id}), do: Repo.get!(SceneRecord, scene_id)
end
