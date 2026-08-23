defmodule Storyarn.Projects.Persistence.ScenePinRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Storyarn.Projects.SceneChangesetHelpers

  alias Storyarn.Assets.Asset
  alias Storyarn.Projects.Persistence.FlowRecord
  alias Storyarn.Projects.Persistence.SceneConnectionRecord
  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SheetRecord

  @valid_pin_types ~w(location character event custom)
  @valid_sizes ~w(sm md lg)
  @valid_condition_effects ~w(hide disable)
  @valid_patrol_modes ~w(none loop ping_pong one_way)

  @type t :: %__MODULE__{}

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
    field :is_playable, :boolean, default: false
    field :is_leader, :boolean, default: false
    field :condition, :map
    field :condition_effect, :string, default: "hide"
    field :patrol_mode, :string, default: "none"
    field :patrol_speed, :float, default: 1.0
    field :patrol_pause_ms, :integer, default: 0

    belongs_to :scene, SceneRecord
    belongs_to :layer, SceneLayerRecord
    belongs_to :sheet, SheetRecord
    belongs_to :icon_asset, Asset, where: [deleted_at: nil]
    belongs_to :flow, FlowRecord

    has_many :outgoing_connections, SceneConnectionRecord, foreign_key: :from_pin_id
    has_many :incoming_connections, SceneConnectionRecord, foreign_key: :to_pin_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(pin, attrs), do: shared_changeset(pin, attrs)

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
    |> validate_inclusion(:pin_type, @valid_pin_types)
    |> validate_inclusion(:size, @valid_sizes)
    |> validate_inclusion(:condition_effect, @valid_condition_effects)
    |> validate_number(:opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_inclusion(:patrol_mode, @valid_patrol_modes)
    |> validate_number(:patrol_speed, greater_than: 0, less_than_or_equal_to: 3.0)
    |> validate_number(:patrol_pause_ms, greater_than_or_equal_to: 0, less_than_or_equal_to: 30_000)
    |> validate_shortcut()
    |> unique_constraint(:shortcut, name: :scene_pins_scene_id_shortcut_index)
    |> unique_constraint(:scene_id, name: :scene_pins_single_leader_per_scene_index)
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
end
