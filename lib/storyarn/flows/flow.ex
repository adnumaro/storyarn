defmodule Storyarn.Flows.Flow do
  @moduledoc """
  Schema for flows.

  A flow is a visual graph representing narrative structure, dialogue trees,
  or game logic. Each flow belongs to a project and contains nodes and connections.

  Flows are organized in a tree structure (like Sheets) with:
  - `parent_id` - FK to parent flow (nil for root level)
  - `position` - Order among siblings
  - `description` - Rich text for annotations
  - `deleted_at` - Soft delete support

  Any flow can have children AND content (nodes). The UI adapts based on what
  the flow contains. This matches the Sheets model for consistency.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.{FlowConnection, FlowNode}
  alias Storyarn.Projects.Project
  alias Storyarn.Scenes
  alias Storyarn.Shared.{HierarchicalSchema, Validations}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          description: String.t() | nil,
          position: integer() | nil,
          is_main: boolean(),
          settings: map(),
          scene_id: integer() | nil,
          scene: Scenes.Scene.t() | Ecto.Association.NotLoaded.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          nodes: [FlowNode.t()] | Ecto.Association.NotLoaded.t(),
          connections: [FlowConnection.t()] | Ecto.Association.NotLoaded.t(),
          deleted_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "flows" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :position, :integer, default: 0
    field :is_main, :boolean, default: false
    field :settings, :map, default: %{}
    field :deleted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :scene, Scenes.Scene
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :nodes, FlowNode
    has_many :connections, FlowConnection

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new flow.
  """
  def create_changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :is_main,
      :settings,
      :parent_id,
      :position,
      :scene_id
    ])
    |> HierarchicalSchema.validate_core_fields()
    |> HierarchicalSchema.validate_description()
    |> validate_shortcut()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:scene_id)
  end

  @doc """
  Changeset for updating a flow.
  """
  def update_changeset(flow, attrs) do
    flow
    |> cast(attrs, [
      :name,
      :shortcut,
      :description,
      :is_main,
      :settings,
      :parent_id,
      :position,
      :scene_id
    ])
    |> HierarchicalSchema.validate_core_fields()
    |> HierarchicalSchema.validate_description()
    |> validate_shortcut()
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:scene_id)
  end

  @doc """
  Changeset for updating the scene association.
  """
  def scene_changeset(flow, attrs) do
    flow
    |> cast(attrs, [:scene_id])
    |> foreign_key_constraint(:scene_id)
  end

  @doc """
  Changeset for moving a flow (changing parent or position).
  """
  def move_changeset(flow, attrs), do: HierarchicalSchema.move_changeset(flow, attrs)

  @doc """
  Changeset for soft deleting a flow.
  """
  def delete_changeset(flow), do: HierarchicalSchema.delete_changeset(flow)

  @doc """
  Changeset for restoring a soft-deleted flow.
  """
  def restore_changeset(flow), do: HierarchicalSchema.restore_changeset(flow)

  @doc """
  Returns true if the flow is soft-deleted.
  """
  def deleted?(flow), do: HierarchicalSchema.deleted?(flow)

  # Private functions

  defp validate_shortcut(changeset) do
    changeset
    |> Validations.validate_shortcut(
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., chapter-1)"
    )
    |> unique_constraint(:shortcut,
      name: :flows_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end
end
