defmodule Storyarn.Maps.MapZone do
  @moduledoc """
  Schema for map zones.

  Zones are polygonal areas drawn on a map. They can link to sheets, flows,
  or other maps (for drill-down navigation). Vertices are stored as a list
  of `%{"x" => float, "y" => float}` percentage pairs (0-100).
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Storyarn.Maps.ChangesetHelpers

  alias Storyarn.Maps.{Map, MapLayer}

  @valid_border_styles ~w(solid dashed dotted)
  @valid_target_types ~w(sheet flow map)
  @valid_action_types ~w(none instruction display)

  @valid_condition_effects ~w(hide disable)

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          vertices: [map()] | nil,
          fill_color: String.t() | nil,
          border_color: String.t() | nil,
          border_width: integer(),
          border_style: String.t(),
          opacity: float(),
          target_type: String.t() | nil,
          target_id: integer() | nil,
          tooltip: String.t() | nil,
          position: integer() | nil,
          locked: boolean(),
          action_type: String.t(),
          action_data: map(),
          condition: map() | nil,
          condition_effect: String.t(),
          map_id: integer() | nil,
          map: Map.t() | Ecto.Association.NotLoaded.t() | nil,
          layer_id: integer() | nil,
          layer: MapLayer.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "map_zones" do
    field :name, :string
    field :vertices, {:array, :map}
    field :fill_color, :string
    field :border_color, :string
    field :border_width, :integer, default: 2
    field :border_style, :string, default: "solid"
    field :opacity, :float, default: 0.3
    field :target_type, :string
    field :target_id, :integer
    field :tooltip, :string
    field :position, :integer, default: 0
    field :locked, :boolean, default: false
    field :action_type, :string, default: "none"
    field :action_data, :map, default: %{}
    field :condition, :map
    field :condition_effect, :string, default: "hide"

    belongs_to :map, Map
    belongs_to :layer, MapLayer

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new zone.
  """
  def create_changeset(zone, attrs), do: shared_changeset(zone, attrs)

  @doc """
  Changeset for updating a zone.
  """
  def update_changeset(zone, attrs), do: shared_changeset(zone, attrs)

  defp shared_changeset(zone, attrs) do
    zone
    |> cast(attrs, [
      :name,
      :vertices,
      :fill_color,
      :border_color,
      :border_width,
      :border_style,
      :opacity,
      :target_type,
      :target_id,
      :tooltip,
      :layer_id,
      :position,
      :locked,
      :action_type,
      :action_data,
      :condition,
      :condition_effect
    ])
    |> validate_required([:name, :vertices])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_inclusion(:border_style, @valid_border_styles)
    |> validate_inclusion(:action_type, @valid_action_types)
    |> validate_inclusion(:condition_effect, @valid_condition_effects)
    |> validate_target_pair(@valid_target_types)
    |> validate_action_data()
    |> validate_number(:opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:border_width, greater_than_or_equal_to: 0)
    |> validate_length(:fill_color, max: 20)
    |> validate_color(:fill_color)
    |> validate_length(:border_color, max: 20)
    |> validate_color(:border_color)
    |> validate_length(:tooltip, max: 500)
    |> validate_vertices()
    |> foreign_key_constraint(:layer_id)
  end

  @doc """
  Changeset for updating only vertices (optimized for drag operations).
  """
  def update_vertices_changeset(zone, attrs) do
    zone
    |> cast(attrs, [:vertices])
    |> validate_required([:vertices])
    |> validate_vertices()
  end

  # Validates vertices: minimum 3 points, all x/y in 0-100 range
  defp validate_vertices(changeset) do
    case get_field(changeset, :vertices) do
      nil ->
        changeset

      vertices when is_list(vertices) ->
        cond do
          length(vertices) < 3 ->
            add_error(changeset, :vertices, "must have at least 3 points")

          not all_valid_coordinates?(vertices) ->
            add_error(changeset, :vertices, "all coordinates must have x and y between 0 and 100")

          true ->
            changeset
        end

      _ ->
        add_error(changeset, :vertices, "must be a list of coordinate points")
    end
  end

  # Validates action_data shape based on action_type
  defp validate_action_data(changeset) do
    action_type = get_field(changeset, :action_type)
    action_data = get_field(changeset, :action_data) || %{}
    do_validate_action_data(changeset, action_type, action_data)
  end

  defp do_validate_action_data(changeset, "instruction", %{"assignments" => list})
       when is_list(list),
       do: changeset

  defp do_validate_action_data(changeset, "instruction", _),
    do: add_error(changeset, :action_data, "must include \"assignments\" as a list")

  defp do_validate_action_data(changeset, "display", %{"variable_ref" => ref})
       when is_binary(ref),
       do: changeset

  defp do_validate_action_data(changeset, "display", _),
    do: add_error(changeset, :action_data, "must include \"variable_ref\"")

  defp do_validate_action_data(changeset, _, _), do: changeset

  defp all_valid_coordinates?(vertices) do
    Enum.all?(vertices, fn point ->
      is_map(point) && valid_point?(point)
    end)
  end

  defp valid_point?(point) do
    x = point["x"] || point[:x]
    y = point["y"] || point[:y]

    is_number(x) && x >= 0 && x <= 100 &&
      is_number(y) && y >= 0 && y <= 100
  end
end
