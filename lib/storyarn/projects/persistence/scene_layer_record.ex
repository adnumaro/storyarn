defmodule Storyarn.Projects.Persistence.SceneLayerRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Storyarn.Projects.Persistence.ScenePinRecord
  alias Storyarn.Projects.Persistence.SceneRecord
  alias Storyarn.Projects.Persistence.SceneZoneRecord

  schema "scene_layers" do
    field :name, :string
    field :is_default, :boolean, default: false
    field :position, :integer, default: 0
    field :visible, :boolean, default: true
    field :fog_enabled, :boolean, default: false

    belongs_to :scene, SceneRecord
    has_many :zones, SceneZoneRecord, foreign_key: :layer_id
    has_many :pins, ScenePinRecord, foreign_key: :layer_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(layer, attrs) do
    layer
    |> cast(attrs, [:name, :is_default, :position, :visible, :fog_enabled])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
  end
end
