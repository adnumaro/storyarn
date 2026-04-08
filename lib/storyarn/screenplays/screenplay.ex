defmodule Storyarn.Screenplays.Screenplay do
  @moduledoc """
  Schema for screenplays.

  A screenplay is a block-based script editor for narrative design. Each
  screenplay belongs to a project and contains ordered elements (blocks).

  Screenplays are organized in a tree structure with:
  - `parent_id` - FK to parent screenplay (nil for root level)
  - `position` - Order among siblings
  - `linked_flow_id` - Optional link to a flow for bidirectional sync
  - `deleted_at` - Soft delete support

  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Screenplays.ScreenplayElement
  alias Storyarn.Shared.{HierarchicalSchema, Validations}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          description: String.t() | nil,
          position: integer() | nil,
          deleted_at: DateTime.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          linked_flow_id: integer() | nil,
          linked_flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          elements: [ScreenplayElement.t()] | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "screenplays" do
    field :name, :string
    field :shortcut, :string
    field :description, :string
    field :position, :integer, default: 0
    field :deleted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :linked_flow, Flow
    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :elements, ScreenplayElement

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns true if the screenplay is soft-deleted.
  """
  def deleted?(screenplay), do: HierarchicalSchema.deleted?(screenplay)

  @doc """
  Changeset for creating a new screenplay.
  """
  def create_changeset(screenplay, attrs) do
    screenplay
    |> cast(attrs, [:name, :shortcut, :description, :parent_id, :position])
    |> HierarchicalSchema.validate_core_fields()
    |> HierarchicalSchema.validate_description()
    |> validate_shortcut()
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating a screenplay.
  """
  def update_changeset(screenplay, attrs) do
    screenplay
    |> cast(attrs, [:name, :shortcut, :description])
    |> HierarchicalSchema.validate_core_fields()
    |> HierarchicalSchema.validate_description()
    |> validate_shortcut()
  end

  @doc """
  Changeset for moving a screenplay (changing parent or position).
  """
  def move_changeset(screenplay, attrs), do: HierarchicalSchema.move_changeset(screenplay, attrs)

  @doc """
  Changeset for soft deleting a screenplay.
  """
  def delete_changeset(screenplay), do: HierarchicalSchema.delete_changeset(screenplay)

  @doc """
  Changeset for restoring a soft-deleted screenplay.
  """
  def restore_changeset(screenplay), do: HierarchicalSchema.restore_changeset(screenplay)

  @doc """
  Changeset for linking/unlinking a flow.
  """
  def link_flow_changeset(screenplay, attrs) do
    screenplay
    |> cast(attrs, [:linked_flow_id])
    |> foreign_key_constraint(:linked_flow_id)
    |> unique_constraint(:linked_flow_id,
      name: :screenplays_linked_flow_unique,
      message: "is already linked to another screenplay"
    )
  end

  # Private functions

  defp validate_shortcut(changeset) do
    changeset
    |> Validations.validate_shortcut(
      message: "must be lowercase, alphanumeric, with dots or hyphens (e.g., chapter-1)"
    )
    |> unique_constraint(:shortcut,
      name: :screenplays_project_shortcut_unique,
      message: "is already taken in this project"
    )
  end
end
