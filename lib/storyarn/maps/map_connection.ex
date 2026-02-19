defmodule Storyarn.Maps.MapConnection do
  @moduledoc """
  Schema for map connections.

  Connections are visual lines between two pins on a map, representing
  routes, relationships, or paths. They can be unidirectional or bidirectional.
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Storyarn.Maps.ChangesetHelpers

  alias Storyarn.Maps.{Map, MapPin}

  @valid_line_styles ~w(solid dashed dotted)
  @max_waypoints 50

  @type t :: %__MODULE__{
          id: integer() | nil,
          line_style: String.t(),
          color: String.t() | nil,
          label: String.t() | nil,
          bidirectional: boolean(),
          waypoints: [map()] | nil,
          map_id: integer() | nil,
          map: Map.t() | Ecto.Association.NotLoaded.t() | nil,
          from_pin_id: integer() | nil,
          from_pin: MapPin.t() | Ecto.Association.NotLoaded.t() | nil,
          to_pin_id: integer() | nil,
          to_pin: MapPin.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "map_connections" do
    field :line_style, :string, default: "solid"
    field :line_width, :integer, default: 2
    field :color, :string
    field :label, :string
    field :bidirectional, :boolean, default: true
    field :show_label, :boolean, default: true
    field :waypoints, {:array, :map}, default: []

    belongs_to :map, Map
    belongs_to :from_pin, MapPin
    belongs_to :to_pin, MapPin

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new connection.
  """
  def create_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:from_pin_id, :to_pin_id, :line_style, :line_width, :color, :label, :bidirectional, :waypoints])
    |> validate_required([:from_pin_id, :to_pin_id])
    |> validate_inclusion(:line_style, @valid_line_styles)
    |> validate_number(:line_width, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_length(:label, max: 200)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> validate_waypoints()
    |> validate_not_self_connection()
    |> foreign_key_constraint(:from_pin_id)
    |> foreign_key_constraint(:to_pin_id)
  end

  @doc """
  Changeset for updating a connection.
  """
  def update_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:line_style, :line_width, :color, :label, :bidirectional, :show_label, :waypoints])
    |> validate_inclusion(:line_style, @valid_line_styles)
    |> validate_number(:line_width, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_length(:label, max: 200)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> validate_waypoints()
  end

  @doc """
  Changeset optimized for waypoint drag updates.
  """
  def waypoints_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:waypoints])
    |> validate_waypoints()
  end

  defp validate_waypoints(changeset) do
    case get_change(changeset, :waypoints) do
      nil ->
        changeset

      waypoints when length(waypoints) > @max_waypoints ->
        add_error(changeset, :waypoints, "cannot have more than #{@max_waypoints} waypoints")

      waypoints ->
        if Enum.all?(waypoints, &valid_waypoint?/1) do
          changeset
        else
          add_error(changeset, :waypoints, "all waypoints must have x and y between 0 and 100")
        end
    end
  end

  defp valid_waypoint?(%{"x" => x, "y" => y})
       when is_number(x) and is_number(y) and x >= 0 and x <= 100 and y >= 0 and y <= 100,
       do: true

  defp valid_waypoint?(_), do: false

  # Validates that from_pin_id and to_pin_id are different
  defp validate_not_self_connection(changeset) do
    from_pin_id = get_field(changeset, :from_pin_id)
    to_pin_id = get_field(changeset, :to_pin_id)

    if from_pin_id && to_pin_id && from_pin_id == to_pin_id do
      add_error(changeset, :to_pin_id, "cannot connect a pin to itself")
    else
      changeset
    end
  end
end
