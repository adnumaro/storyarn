defmodule Storyarn.Maps.MapAnnotation do
  @moduledoc """
  Schema for map annotations.

  Annotations are text labels placed directly on a map canvas.
  Position is stored as percentage pairs (0-100) relative to the map dimensions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Storyarn.Maps.ChangesetHelpers

  alias Storyarn.Maps.{Map, MapLayer}

  @valid_font_sizes ~w(sm md lg)

  @type t :: %__MODULE__{
          id: integer() | nil,
          text: String.t() | nil,
          position_x: float() | nil,
          position_y: float() | nil,
          font_size: String.t(),
          color: String.t() | nil,
          position: integer() | nil,
          locked: boolean(),
          map_id: integer() | nil,
          map: Map.t() | Ecto.Association.NotLoaded.t() | nil,
          layer_id: integer() | nil,
          layer: MapLayer.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "map_annotations" do
    field :text, :string
    field :position_x, :float
    field :position_y, :float
    field :font_size, :string, default: "md"
    field :color, :string
    field :position, :integer, default: 0
    field :locked, :boolean, default: false

    belongs_to :map, Map
    belongs_to :layer, MapLayer

    timestamps(type: :utc_datetime)
  end

  def create_changeset(annotation, attrs), do: shared_changeset(annotation, attrs)

  def update_changeset(annotation, attrs), do: shared_changeset(annotation, attrs)

  defp shared_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [
      :text,
      :position_x,
      :position_y,
      :font_size,
      :color,
      :layer_id,
      :position,
      :locked
    ])
    |> validate_required([:text, :position_x, :position_y])
    |> validate_length(:text, min: 1, max: 500)
    |> validate_number(:position_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:position_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:font_size, @valid_font_sizes)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> foreign_key_constraint(:layer_id)
  end

  def move_changeset(annotation, attrs) do
    annotation
    |> cast(attrs, [:position_x, :position_y])
    |> validate_required([:position_x, :position_y])
    |> validate_number(:position_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:position_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
