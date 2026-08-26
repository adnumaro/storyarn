defmodule Storyarn.Scenes.Editor.Queries.Pins do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Scenes.ScenePin

  def list_pins(scene_id, opts \\ []) do
    query =
      from(pin in ScenePin,
        where: pin.scene_id == ^scene_id,
        order_by: [asc: pin.position]
      )

    query =
      case Keyword.get(opts, :layer_id) do
        nil -> query
        layer_id -> where(query, [pin], pin.layer_id == ^layer_id)
      end

    Repo.all(query)
  end

  def get_pin(pin_id), do: Repo.get(ScenePin, pin_id)
  def get_pin!(pin_id), do: Repo.get!(ScenePin, pin_id)

  def get_pin(scene_id, pin_id) do
    Repo.one(
      from(pin in ScenePin,
        where: pin.scene_id == ^scene_id and pin.id == ^pin_id,
        preload: [:icon_asset, sheet: [avatars: :asset]]
      )
    )
  end

  def get_pin!(scene_id, pin_id) do
    Repo.one!(
      from(pin in ScenePin,
        where: pin.scene_id == ^scene_id and pin.id == ^pin_id,
        preload: [:icon_asset, sheet: [avatars: :asset]]
      )
    )
  end
end
