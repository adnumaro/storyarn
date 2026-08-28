defmodule Storyarn.Scenes.Editor.Queries.Layers do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.SceneLayer

  def list_layers(scene_id) do
    Repo.all(
      from(layer in SceneLayer,
        where: layer.scene_id == ^scene_id,
        order_by: [asc: layer.position]
      )
    )
  end

  def get_layer(scene_id, layer_id) do
    Repo.one(from(layer in SceneLayer, where: layer.scene_id == ^scene_id and layer.id == ^layer_id))
  end

  def get_layer!(scene_id, layer_id) do
    Repo.one!(from(layer in SceneLayer, where: layer.scene_id == ^scene_id and layer.id == ^layer_id))
  end
end
