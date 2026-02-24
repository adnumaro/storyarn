defmodule Storyarn.Scenes.SceneLayer do
  @moduledoc """
  Schema for map layers.

  Layers allow organizing pins and zones into groups that can be toggled
  on/off independently.

  Every map has at least one layer (the default layer created automatically).
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Storyarn.Scenes.ChangesetHelpers

  alias Storyarn.Scenes.{Scene, ScenePin, SceneZone}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          is_default: boolean(),
          position: integer() | nil,
          visible: boolean(),
          fog_enabled: boolean(),
          fog_color: String.t() | nil,
          fog_opacity: float(),
          scene_id: integer() | nil,
          scene: Scene.t() | Ecto.Association.NotLoaded.t() | nil,
          zones: [SceneZone.t()] | Ecto.Association.NotLoaded.t(),
          pins: [ScenePin.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "scene_layers" do
    field :name, :string
    field :is_default, :boolean, default: false
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :fog_enabled, :boolean, default: false
    field :fog_color, :string, default: "#000000"
    field :fog_opacity, :float, default: 0.85

    belongs_to :scene, Scene
    has_many :zones, SceneZone, foreign_key: :layer_id
    has_many :pins, ScenePin, foreign_key: :layer_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new layer.
  """
  def create_changeset(layer, attrs) do
    layer
    |> cast(attrs, [
      :name,
      :is_default,
      :position,
      :visible,
      :fog_enabled,
      :fog_color,
      :fog_opacity
    ])
    |> shared_validations()
  end

  @doc """
  Changeset for updating a layer.
  """
  def update_changeset(layer, attrs) do
    layer
    |> cast(attrs, [
      :name,
      :is_default,
      :visible,
      :fog_enabled,
      :fog_color,
      :fog_opacity
    ])
    |> shared_validations()
  end

  defp shared_validations(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_number(:fog_opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_length(:fog_color, max: 20)
    |> validate_color(:fog_color)
  end
end
