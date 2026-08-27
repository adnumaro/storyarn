defmodule Storyarn.Projects.Persistence.SceneConnectionRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Storyarn.Projects.SceneChangesetHelpers

  alias Storyarn.Projects.Persistence.ScenePinRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.SceneRoutePoints

  @valid_line_styles ~w(solid dashed dotted)
  @max_waypoints 50

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

    belongs_to :scene, SceneRecord
    belongs_to :from_pin, ScenePinRecord
    belongs_to :to_pin, ScenePinRecord

    timestamps(type: :utc_datetime)
  end

  def create_changeset(connection, attrs) do
    connection
    |> cast_shared(attrs, [:from_pin_id, :to_pin_id])
    |> validate_not_self_connection()
    |> foreign_key_constraint(:from_pin_id)
    |> foreign_key_constraint(:to_pin_id)
  end

  defp cast_shared(connection, attrs, endpoint_fields) do
    connection
    |> cast(
      attrs,
      endpoint_fields ++
        [
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
        ]
    )
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

  defp validate_waypoints(changeset) do
    case get_change(changeset, :waypoints) do
      nil ->
        changeset

      waypoints when length(waypoints) > @max_waypoints ->
        add_error(changeset, :waypoints, "cannot have more than #{@max_waypoints} waypoints")

      waypoints ->
        if Enum.all?(waypoints, &SceneRoutePoints.valid_waypoint?/1),
          do: changeset,
          else: add_error(changeset, :waypoints, "all waypoints must have numeric x and y values")
    end
  end

  defp validate_route_has_two_points(changeset) do
    if SceneRoutePoints.enough_points?(
         get_field(changeset, :from_pin_id),
         get_field(changeset, :to_pin_id),
         get_field(changeset, :waypoints) || []
       ) do
      changeset
    else
      add_error(changeset, :waypoints, "route must have at least two points")
    end
  end

  defp validate_not_self_connection(changeset) do
    from_pin_id = get_field(changeset, :from_pin_id)
    to_pin_id = get_field(changeset, :to_pin_id)

    if from_pin_id && to_pin_id && from_pin_id == to_pin_id,
      do: add_error(changeset, :to_pin_id, "cannot connect a pin to itself"),
      else: changeset
  end
end
