defmodule Storyarn.Scenes.SceneLayer do
  @moduledoc """
  Schema for map layers.

  Layers allow organizing pins and zones into groups that can be toggled
  on/off independently.

  Every map has at least one layer (the default layer created automatically).
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Scenes.Scene
  alias Storyarn.Scenes.ScenePin
  alias Storyarn.Scenes.SceneZone

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          is_default: boolean(),
          position: integer() | nil,
          visible: boolean(),
          fog_enabled: boolean(),
          scene_id: integer() | nil,
          scene: Scene.t() | NotLoaded.t() | nil,
          zones: [SceneZone.t()] | NotLoaded.t(),
          pins: [ScenePin.t()] | NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "scene_layers" do
    field :name, :string
    field :is_default, :boolean, default: false
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :fog_enabled, :boolean, default: false

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
      :fog_enabled
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
      :fog_enabled
    ])
    |> shared_validations()
  end

  defp shared_validations(changeset) do
    changeset
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end
end
