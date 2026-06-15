defmodule Storyarn.Scenes.SceneConnection do
  @moduledoc """
  Schema for map connections.

  Connections are visual lines between two pins on a map, representing
  routes, relationships, or paths. They can be unidirectional or bidirectional.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Storyarn.Scenes.ChangesetHelpers

  alias Ecto.Association.NotLoaded
  alias Storyarn.Scenes.RoutePoints
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin

  @valid_line_styles ~w(solid dashed dotted)
  @max_waypoints 50

  @type t :: %__MODULE__{
          id: integer() | nil,
          line_style: String.t(),
          color: String.t() | nil,
          label: String.t() | nil,
          bidirectional: boolean(),
          waypoints: [map()] | nil,
          from_stop: boolean(),
          to_stop: boolean(),
          from_pause_ms: integer() | nil,
          to_pause_ms: integer() | nil,
          scene_id: integer() | nil,
          scene: Scene.t() | NotLoaded.t() | nil,
          from_pin_id: integer() | nil,
          from_pin: ScenePin.t() | NotLoaded.t() | nil,
          to_pin_id: integer() | nil,
          to_pin: ScenePin.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "scene_connections" do
    field :line_style, :string, default: "solid"
    field :line_width, :integer, default: 2
    field :color, :string
    field :label, :string
    field :bidirectional, :boolean, default: true
    field :show_label, :boolean, default: true
    field :waypoints, {:array, :map}, default: []
    field :from_stop, :boolean, default: true
    field :to_stop, :boolean, default: true
    field :from_pause_ms, :integer
    field :to_pause_ms, :integer

    belongs_to :scene, Scene
    belongs_to :from_pin, ScenePin
    belongs_to :to_pin, ScenePin

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new connection.
  """
  def create_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :from_pin_id,
      :to_pin_id,
      :line_style,
      :line_width,
      :color,
      :label,
      :bidirectional,
      :show_label,
      :waypoints,
      :from_stop,
      :to_stop,
      :from_pause_ms,
      :to_pause_ms
    ])
    |> validate_inclusion(:line_style, @valid_line_styles)
    |> validate_number(:line_width, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:from_pause_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 30_000)
    |> validate_number(:to_pause_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 30_000)
    |> validate_length(:label, max: 200)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> validate_waypoints()
    |> validate_route_has_two_points()
    |> validate_not_self_connection()
    |> foreign_key_constraint(:from_pin_id)
    |> foreign_key_constraint(:to_pin_id)
  end

  @doc """
  Changeset for updating a connection.
  """
  def update_changeset(connection, attrs) do
    connection
    |> cast(attrs, [
      :line_style,
      :line_width,
      :color,
      :label,
      :bidirectional,
      :show_label,
      :waypoints,
      :from_stop,
      :to_stop,
      :from_pause_ms,
      :to_pause_ms
    ])
    |> validate_inclusion(:line_style, @valid_line_styles)
    |> validate_number(:line_width, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> validate_number(:from_pause_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 30_000)
    |> validate_number(:to_pause_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 30_000)
    |> validate_length(:label, max: 200)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> validate_waypoints()
    |> validate_route_has_two_points()
  end

  @doc """
  Changeset optimized for waypoint drag updates.
  """
  def waypoints_changeset(connection, attrs) do
    connection
    |> cast(attrs, [:waypoints])
    |> validate_waypoints()
    |> validate_route_has_two_points()
  end

  defp validate_waypoints(changeset) do
    case get_change(changeset, :waypoints) do
      nil ->
        changeset

      waypoints when length(waypoints) > @max_waypoints ->
        add_error(changeset, :waypoints, "cannot have more than #{@max_waypoints} waypoints")

      waypoints ->
        if Enum.all?(waypoints, &RoutePoints.valid_waypoint?/1) do
          changeset
        else
          add_error(changeset, :waypoints, "all waypoints must have numeric x and y values")
        end
    end
  end

  defp validate_route_has_two_points(changeset) do
    from_pin_id = get_field(changeset, :from_pin_id)
    to_pin_id = get_field(changeset, :to_pin_id)
    waypoints = get_field(changeset, :waypoints) || []

    if RoutePoints.enough_points?(from_pin_id, to_pin_id, waypoints) do
      changeset
    else
      add_error(changeset, :waypoints, "route must have at least two points")
    end
  end

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
