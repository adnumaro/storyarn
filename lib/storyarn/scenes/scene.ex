defmodule Storyarn.Scenes.Scene do
  @moduledoc """
  Schema for maps.

  A map is a visual world-building canvas with interactive pins and zones
  linked to narrative content (sheets, flows). Each map belongs to a project
  and can contain layers, zones, pins, and connections.

  Scenes are organized in a tree structure for drill-down navigation:
  - `parent_id` - FK to parent map (nil for root level)
  - `position` - Order among siblings
  - `deleted_at` - Soft delete support

  Any map can have children AND content. The UI adapts based on what
  the map contains (e.g., world → region → city → building).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Assets.Asset
  alias Storyarn.Projects.Project
  alias Storyarn.Scenes.{SceneAnnotation, SceneConnection, SceneLayer, ScenePin, SceneZone}
  alias Storyarn.Shared.{HierarchicalSchema, Validations}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          description: String.t() | nil,
          shortcut: String.t() | nil,
          width: integer() | nil,
          height: integer() | nil,
          default_zoom: float(),
          default_center_x: float(),
          default_center_y: float(),
          scale_unit: String.t() | nil,
          scale_value: float() | nil,
          position: integer() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          background_asset_id: integer() | nil,
          background_asset: Asset.t() | Ecto.Association.NotLoaded.t() | nil,
          layers: [SceneLayer.t()] | Ecto.Association.NotLoaded.t(),
          zones: [SceneZone.t()] | Ecto.Association.NotLoaded.t(),
          pins: [ScenePin.t()] | Ecto.Association.NotLoaded.t(),
          connections: [SceneConnection.t()] | Ecto.Association.NotLoaded.t(),
          annotations: [SceneAnnotation.t()] | Ecto.Association.NotLoaded.t(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

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
    field :deleted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :background_asset, Asset
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :layers, SceneLayer, preload_order: [asc: :position, asc: :id]
    has_many :zones, SceneZone
    has_many :pins, ScenePin
    has_many :connections, SceneConnection
    has_many :annotations, SceneAnnotation

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new map.
  """
  def create_changeset(map, attrs), do: shared_changeset(map, attrs)

  @doc """
  Changeset for updating a map.
  """
  def update_changeset(map, attrs), do: shared_changeset(map, attrs)

  defp shared_changeset(map, attrs) do
    map
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
      :scale_value
    ])
    |> HierarchicalSchema.validate_core_fields()
    |> HierarchicalSchema.validate_description()
    |> validate_number(:width, greater_than: 0)
    |> validate_number(:height, greater_than: 0)
    |> validate_number(:default_zoom, greater_than: 0)
    |> validate_number(:default_center_x, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:default_center_y, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:scale_value, greater_than: 0)
    |> validate_length(:scale_unit, max: 50)
    |> validate_shortcut()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:background_asset_id)
  end

  @doc """
  Changeset for moving a map (changing parent or position).
  """
  def move_changeset(map, attrs), do: HierarchicalSchema.move_changeset(map, attrs)

  @doc """
  Changeset for soft deleting a map.
  """
  def delete_changeset(map), do: HierarchicalSchema.delete_changeset(map)

  @doc """
  Changeset for restoring a soft-deleted map.
  """
  def restore_changeset(map), do: HierarchicalSchema.restore_changeset(map)

  @doc """
  Returns true if the map is soft-deleted.
  """
  def deleted?(map), do: HierarchicalSchema.deleted?(map)

  # Private functions

  defp validate_shortcut(changeset) do
    changeset
    |> Validations.validate_shortcut(
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., world-map)"
    )
    |> unique_constraint(:shortcut,
      name: :scenes_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end
end
