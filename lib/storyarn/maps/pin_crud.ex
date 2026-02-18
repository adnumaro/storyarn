defmodule Storyarn.Maps.PinCrud do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Maps.{MapPin, PositionUtils}
  alias Storyarn.Repo

  @doc """
  Lists pins for a map, with optional layer_id filter.
  """
  def list_pins(map_id, opts \\ []) do
    query =
      from(p in MapPin,
        where: p.map_id == ^map_id,
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
    Repo.get(MapPin, pin_id)
  end

  def get_pin!(pin_id) do
    Repo.get!(MapPin, pin_id)
  end

  @doc """
  Gets a pin by ID, scoped to a specific map. Returns `nil` if not found.
  """
  def get_pin(map_id, pin_id) do
    from(p in MapPin,
      where: p.map_id == ^map_id and p.id == ^pin_id,
      preload: [:icon_asset, sheet: :avatar_asset]
    )
    |> Repo.one()
  end

  @doc """
  Gets a pin by ID, scoped to a specific map. Raises if not found.
  """
  def get_pin!(map_id, pin_id) do
    from(p in MapPin,
      where: p.map_id == ^map_id and p.id == ^pin_id,
      preload: [:icon_asset, sheet: :avatar_asset]
    )
    |> Repo.one!()
  end

  def create_pin(map_id, attrs) do
    position = PositionUtils.next_position(MapPin, map_id)
    attrs = Storyarn.Shared.MapUtils.stringify_keys(attrs)

    %MapPin{map_id: map_id}
    |> MapPin.create_changeset(Map.put(attrs, "position", position))
    |> Repo.insert()
  end

  def update_pin(%MapPin{} = pin, attrs) do
    pin
    |> MapPin.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Moves a pin to a new position (position_x/position_y only — drag optimization).
  """
  def move_pin(%MapPin{} = pin, position_x, position_y) do
    pin
    |> MapPin.move_changeset(%{position_x: position_x, position_y: position_y})
    |> Repo.update()
  end

  def delete_pin(%MapPin{} = pin) do
    Repo.delete(pin)
  end

  def change_pin(%MapPin{} = pin, attrs \\ %{}) do
    MapPin.update_changeset(pin, attrs)
  end

end
