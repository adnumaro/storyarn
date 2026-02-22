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

  Draft support fields (`draft_of_id`, `draft_label`, `draft_status`) are
  included from day one but not yet implemented — see FUTURE_FEATURES.md.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Flows.Flow
  alias Storyarn.Projects.Project
  alias Storyarn.Screenplays.ScreenplayElement
  alias Storyarn.Shared.{TimeHelpers, Validations}

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          shortcut: String.t() | nil,
          description: String.t() | nil,
          position: integer() | nil,
          deleted_at: DateTime.t() | nil,
          draft_label: String.t() | nil,
          draft_status: String.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          parent_id: integer() | nil,
          parent: t() | Ecto.Association.NotLoaded.t() | nil,
          children: [t()] | Ecto.Association.NotLoaded.t(),
          linked_flow_id: integer() | nil,
          linked_flow: Flow.t() | Ecto.Association.NotLoaded.t() | nil,
          draft_of_id: integer() | nil,
          draft_of: t() | Ecto.Association.NotLoaded.t() | nil,
          drafts: [t()] | Ecto.Association.NotLoaded.t(),
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

    # Draft support (see FUTURE_FEATURES.md — Copy-Based Drafts)
    field :draft_label, :string
    field :draft_status, :string, default: "active"

    belongs_to :project, Project
    belongs_to :parent, __MODULE__
    belongs_to :linked_flow, Flow
    belongs_to :draft_of, __MODULE__

    has_many :children, __MODULE__, foreign_key: :parent_id
    has_many :drafts, __MODULE__, foreign_key: :draft_of_id
    has_many :elements, ScreenplayElement

    timestamps(type: :utc_datetime)
  end

  @doc """
  Returns true if this screenplay is a draft of another screenplay.
  """
  def draft?(%__MODULE__{draft_of_id: id}), do: not is_nil(id)

  @doc """
  Returns true if the screenplay is soft-deleted.
  """
  def deleted?(%__MODULE__{deleted_at: deleted_at}), do: not is_nil(deleted_at)

  @doc """
  Changeset for creating a new screenplay.
  """
  def create_changeset(screenplay, attrs) do
    screenplay
    |> cast(attrs, [:name, :shortcut, :description, :parent_id, :position])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_shortcut()
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for updating a screenplay.
  """
  def update_changeset(screenplay, attrs) do
    screenplay
    |> cast(attrs, [:name, :shortcut, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_shortcut()
  end

  @doc """
  Changeset for moving a screenplay (changing parent or position).
  """
  def move_changeset(screenplay, attrs) do
    screenplay
    |> cast(attrs, [:parent_id, :position])
    |> foreign_key_constraint(:parent_id)
  end

  @doc """
  Changeset for soft deleting a screenplay.
  """
  def delete_changeset(screenplay) do
    screenplay
    |> change(%{deleted_at: TimeHelpers.now()})
  end

  @doc """
  Changeset for restoring a soft-deleted screenplay.
  """
  def restore_changeset(screenplay) do
    screenplay
    |> change(%{deleted_at: nil})
  end

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
