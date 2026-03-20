defmodule Storyarn.Scenes.ScenePin do
  @moduledoc """
  Schema for scene pins.

  Pins are point markers placed on a scene. They can display a sheet's avatar
  and optionally launch a flow when clicked in exploration mode (`flow_id`).
  Position is stored as percentage pairs (0-100) relative to the scene dimensions.
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Storyarn.Scenes.ChangesetHelpers

  alias Storyarn.Assets.Asset
  alias Storyarn.Flows.Flow
  alias Storyarn.Scenes.{Scene, SceneConnection, SceneLayer}
  alias Storyarn.Shared.Validations
  alias Storyarn.Sheets.Sheet

  @valid_pin_types ~w(location character event custom)
  @valid_sizes ~w(sm md lg)
  @valid_condition_effects ~w(hide disable)
  @valid_patrol_modes ~w(none loop ping_pong one_way)

  @type t :: %__MODULE__{
          id: integer() | nil,
          position_x: float() | nil,
          position_y: float() | nil,
          pin_type: String.t(),
          icon: String.t() | nil,
          color: String.t() | nil,
          label: String.t() | nil,
          shortcut: String.t() | nil,
          hidden: boolean(),
          tooltip: String.t() | nil,
          size: String.t(),
          position: integer() | nil,
          locked: boolean(),
          condition: map() | nil,
          condition_effect: String.t(),
          is_playable: boolean(),
          is_leader: boolean(),
          patrol_mode: String.t(),
          patrol_speed: float(),
          patrol_pause_ms: integer(),
          scene_id: integer() | nil,
          scene: Scene.t() | Ecto.Association.NotLoaded.t() | nil,
          layer_id: integer() | nil,
          layer: SceneLayer.t() | Ecto.Association.NotLoaded.t() | nil,
          flow_id: integer() | nil,
          flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "scene_pins" do
    field :position_x, :float
    field :position_y, :float
    field :pin_type, :string, default: "location"
    field :icon, :string
    field :color, :string
    field :opacity, :float, default: 1.0
    field :label, :string
    field :shortcut, :string
    field :hidden, :boolean, default: false
    field :tooltip, :string
    field :size, :string, default: "md"
    field :position, :integer, default: 0
    field :locked, :boolean, default: false
    field :condition, :map
    field :condition_effect, :string, default: "hide"
    field :is_playable, :boolean, default: false
    field :is_leader, :boolean, default: false
    field :patrol_mode, :string, default: "none"
    field :patrol_speed, :float, default: 1.0
    field :patrol_pause_ms, :integer, default: 0

    belongs_to :scene, Scene
    belongs_to :layer, SceneLayer
    belongs_to :sheet, Sheet
    belongs_to :icon_asset, Asset
    belongs_to :flow, Flow

    has_many :outgoing_connections, SceneConnection, foreign_key: :from_pin_id
    has_many :incoming_connections, SceneConnection, foreign_key: :to_pin_id

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
      :shortcut,
      :hidden,
      :flow_id,
      :tooltip,
      :size,
      :layer_id,
      :sheet_id,
      :icon_asset_id,
      :position,
      :locked,
      :condition,
      :condition_effect,
      :is_playable,
      :is_leader,
      :patrol_mode,
      :patrol_speed,
      :patrol_pause_ms
    ])
    |> validate_required([:position_x, :position_y])
    |> validate_number(:position_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:position_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_inclusion(:pin_type, @valid_pin_types)
    |> validate_inclusion(:size, @valid_sizes)
    |> validate_inclusion(:condition_effect, @valid_condition_effects)
    |> validate_number(:opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_inclusion(:patrol_mode, @valid_patrol_modes)
    |> validate_number(:patrol_speed, greater_than: 0, less_than_or_equal_to: 3.0)
    |> validate_number(:patrol_pause_ms,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 30_000
    )
    |> Validations.validate_shortcut()
    |> unique_constraint(:shortcut, name: :scene_pins_scene_id_shortcut_index)
    |> validate_length(:label, max: 200)
    |> validate_length(:color, max: 20)
    |> validate_color(:color)
    |> validate_length(:tooltip, max: 500)
    |> validate_length(:icon, max: 100)
    |> foreign_key_constraint(:layer_id)
    |> foreign_key_constraint(:sheet_id)
    |> foreign_key_constraint(:icon_asset_id)
    |> foreign_key_constraint(:flow_id)
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
