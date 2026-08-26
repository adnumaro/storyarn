defmodule Storyarn.Scenes.Editor.Queries.AmbientFlows do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneAmbientFlow

  @doc "Lists ambient flows for a scene, ordered by position then id."
  def list_ambient_flows(scene_id) do
    Repo.all(
      from(ambient_flow in SceneAmbientFlow,
        where: ambient_flow.scene_id == ^scene_id,
        order_by: [asc: ambient_flow.position, desc: ambient_flow.priority, asc: ambient_flow.id],
        preload: [:flow]
      )
    )
  end

  @doc "Gets a single ambient flow scoped to a scene."
  def get_ambient_flow(scene_id, id) do
    Repo.get_by(SceneAmbientFlow, id: id, scene_id: scene_id)
  end
end
