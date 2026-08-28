defmodule Storyarn.Projects.Persistence.SceneRecord do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset
  import Storyarn.Projects.SceneChangesetHelpers, only: [validate_color: 2]

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Projects.Assets.Asset
  alias Storyarn.Projects.Persistence.SceneAmbientFlowRecord
  alias Storyarn.Projects.Persistence.SceneAnnotationRecord
  alias Storyarn.Projects.Persistence.SceneConnectionRecord
  alias Storyarn.Projects.Persistence.SceneLayerRecord
  alias Storyarn.Projects.Persistence.ScenePinRecord
  alias Storyarn.Projects.Persistence.SceneZoneRecord
  alias Storyarn.Projects.Project
  alias Storyarn.Projects.SceneChangesetHelpers

  @type t :: %__MODULE__{}

  schema "scenes" do
    field :name, :string
    field :description, :string
    field :shortcut, :string
    field :width, :integer
    field :height, :integer
    field :default_zoom, :float, default: 1.0
    field :default_center_x, :float, default: 50.0
    field :default_center_y, :float, default: 50.0
    field :position, :integer, default: 0
    field :scale_unit, :string
    field :scale_value, :float
    field :fog_color, :string, default: "#000000"
    field :fog_opacity, :float, default: 0.85
    field :exploration_display_mode, :string, default: "fit"
    field :deleted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :background_asset, Asset, where: [deleted_at: nil]
    field :current_version_id, :id
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :layers, SceneLayerRecord, foreign_key: :scene_id, preload_order: [asc: :position, asc: :id]
    has_many :zones, SceneZoneRecord, foreign_key: :scene_id
    has_many :pins, ScenePinRecord, foreign_key: :scene_id
    has_many :connections, SceneConnectionRecord, foreign_key: :scene_id
    has_many :annotations, SceneAnnotationRecord, foreign_key: :scene_id
    has_many :ambient_flows, SceneAmbientFlowRecord, foreign_key: :scene_id

    timestamps(type: :utc_datetime)
  end

  def create_changeset(scene, attrs), do: shared_changeset(scene, attrs)

  def delete_changeset(scene, deleted_at \\ TimeHelpers.now()) do
    SceneChangesetHelpers.delete_changeset(scene, deleted_at)
  end

  def restore_changeset(scene), do: SceneChangesetHelpers.restore_changeset(scene)
  def deleted?(scene), do: SceneChangesetHelpers.deleted?(scene)

  defp shared_changeset(scene, attrs) do
    scene
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :width,
      :height,
      :default_zoom,
      :default_center_x,
      :default_center_y,
      :parent_id,
      :background_asset_id,
      :position,
      :scale_unit,
      :scale_value,
      :fog_color,
      :fog_opacity,
      :exploration_display_mode
    ])
    |> SceneChangesetHelpers.validate_core_fields()
    |> SceneChangesetHelpers.validate_description()
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
    |> validate_number(:default_zoom, greater_than: 0)
    |> validate_number(:default_center_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:default_center_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:scale_value, greater_than: 0)
    |> validate_number(:fog_opacity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_length(:scale_unit, max: 50)
    |> validate_length(:fog_color, max: 20)
    |> validate_inclusion(:exploration_display_mode, ~w(fit scaled))
    |> validate_color(:fog_color)
    |> validate_shortcut()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:background_asset_id)
  end

  defp validate_shortcut(changeset) do
    changeset
    |> SceneChangesetHelpers.validate_shortcut(
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., world-map)"
    )
    |> unique_constraint(:shortcut,
      name: :scenes_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end
end
