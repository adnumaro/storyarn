defmodule Storyarn.Maps.MapPin do
  @moduledoc """
  Schema for map pins.

  Pins are point markers placed on a map. They can link to sheets, flows,
  maps, or external URLs. Position is stored as percentage pairs (0-100)
  relative to the map dimensions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Storyarn.Maps.ChangesetHelpers

  alias Storyarn.Assets.Asset
  alias Storyarn.Maps.{Map, MapConnection, MapLayer}
  alias Storyarn.Sheets.Sheet

  @valid_pin_types ~w(location character event custom)
  @valid_sizes ~w(sm md lg)
  @valid_target_types ~w(sheet flow map url)

  @type t :: %__MODULE__{
          id: integer() | nil,
          position_x: float() | nil,
          position_y: float() | nil,
          pin_type: String.t(),
          icon: String.t() | nil,
          color: String.t() | nil,
          label: String.t() | nil,
          target_type: String.t() | nil,
          target_id: integer() | nil,
          tooltip: String.t() | nil,
          size: String.t(),
          position: integer() | nil,
          locked: boolean(),
          map_id: integer() | nil,
          map: Map.t() | Ecto.Association.NotLoaded.t() | nil,
          layer_id: integer() | nil,
          layer: MapLayer.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "map_pins" do
    field :position_x, :float
    field :position_y, :float
    field :pin_type, :string, default: "location"
    field :icon, :string
    field :color, :string
    field :opacity, :float, default: 1.0
    field :label, :string
    field :target_type, :string
    field :target_id, :integer
    field :tooltip, :string
    field :size, :string, default: "md"
    field :position, :integer, default: 0
    field :locked, :boolean, default: false

    belongs_to :map, Map
    belongs_to :layer, MapLayer
    belongs_to :sheet, Sheet
    belongs_to :icon_asset, Asset

    has_many :outgoing_connections, MapConnection, foreign_key: :from_pin_id
    has_many :incoming_connections, MapConnection, foreign_key: :to_pin_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new pin.
  """
  def create_changeset(pin, attrs), do: shared_changeset(pin, attrs)

  @doc """
  Changeset for updating a pin.
  """
  def update_changeset(pin, attrs), do: shared_changeset(pin, attrs)

  defp shared_changeset(pin, attrs) do
    pin
    |> cast(attrs, [
      :position_x,
      :position_y,
      :pin_type,
      :icon,
      :color,
      :opacity,
      :label,
      :target_type,
      :target_id,
      :tooltip,
      :size,
      :layer_id,
      :sheet_id,
      :icon_asset_id,
      :position,
      :locked
    ])
    |> validate_required([:position_x, :position_y])
    |> validate_number(:position_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:position_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:pin_type, @valid_pin_types)
    |> validate_inclusion(:size, @valid_sizes)
    |> validate_number(:opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_target_pair(@valid_target_types)
    |> validate_length(:label, max: 200)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> validate_length(:tooltip, max: 500)
    |> validate_length(:icon, max: 100)
    |> foreign_key_constraint(:layer_id)
    |> foreign_key_constraint(:sheet_id)
    |> foreign_key_constraint(:icon_asset_id)
  end

  @doc """
  Changeset for moving a pin (position_x/position_y only — drag optimization).
  """
  def move_changeset(pin, attrs) do
    pin
    |> cast(attrs, [:position_x, :position_y])
    |> validate_required([:position_x, :position_y])
    |> validate_number(:position_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:position_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end

end
