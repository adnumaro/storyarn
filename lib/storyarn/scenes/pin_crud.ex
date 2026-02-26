defmodule Storyarn.Scenes.PinCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Flows
  alias Storyarn.Repo
  alias Storyarn.Scenes
  alias Storyarn.Scenes.{PositionUtils, ScenePin}
  alias Storyarn.Sheets

  @doc """
  Lists pins for a map, with optional layer_id filter.
  """
  def list_pins(scene_id, opts \\ []) do
    query =
      from(p in ScenePin,
        where: p.scene_id == ^scene_id,
        order_by: [asc: p.position]
      )

    query =
      case Keyword.get(opts, :layer_id) do
        nil -> query
        layer_id -> where(query, [p], p.layer_id == ^layer_id)
      end

    Repo.all(query)
  end

  def get_pin(pin_id) do
    Repo.get(ScenePin, pin_id)
  end

  def get_pin!(pin_id) do
    Repo.get!(ScenePin, pin_id)
  end

  @doc """
  Gets a pin by ID, scoped to a specific map. Returns `nil` if not found.
  """
  def get_pin(scene_id, pin_id) do
    from(p in ScenePin,
      where: p.scene_id == ^scene_id and p.id == ^pin_id,
      preload: [:icon_asset, sheet: :avatar_asset]
    )
    |> Repo.one()
  end

  @doc """
  Gets a pin by ID, scoped to a specific map. Raises if not found.
  """
  def get_pin!(scene_id, pin_id) do
    from(p in ScenePin,
      where: p.scene_id == ^scene_id and p.id == ^pin_id,
      preload: [:icon_asset, sheet: :avatar_asset]
    )
    |> Repo.one!()
  end

  def create_pin(scene_id, attrs) do
    position = PositionUtils.next_position(ScenePin, scene_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    result =
      %ScenePin{scene_id: scene_id}
      |> ScenePin.create_changeset(Map.put(attrs, "position", position))
      |> Repo.insert()

    case result do
      {:ok, pin} ->
        project_id = Scenes.get_scene_project_id(scene_id)
        Sheets.update_scene_pin_references(pin)
        Flows.update_scene_pin_references(pin, project_id: project_id)

      _ ->
        :ok
    end

    result
  end

  def update_pin(%ScenePin{} = pin, attrs) do
    result =
      pin
      |> ScenePin.update_changeset(attrs)
      |> Repo.update()

    case result do
      {:ok, updated_pin} ->
        project_id = Scenes.get_scene_project_id(pin.scene_id)
        Sheets.update_scene_pin_references(updated_pin)
        Flows.update_scene_pin_references(updated_pin, project_id: project_id)

      _ ->
        :ok
    end

    result
  end

  @doc """
  Moves a pin to a new position (position_x/position_y only — drag optimization).
  """
  def move_pin(%ScenePin{} = pin, position_x, position_y) do
    pin
    |> ScenePin.move_changeset(%{position_x: position_x, position_y: position_y})
    |> Repo.update()
  end

  def delete_pin(%ScenePin{} = pin) do
    Sheets.delete_map_pin_references(pin.id)
    Flows.delete_map_pin_references(pin.id)
    Repo.delete(pin)
  end

  def change_pin(%ScenePin{} = pin, attrs \\ %{}) do
    ScenePin.update_changeset(pin, attrs)
  end
end
