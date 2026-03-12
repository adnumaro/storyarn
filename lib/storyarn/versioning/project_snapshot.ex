defmodule Storyarn.Versioning.ProjectSnapshot do
  @moduledoc """
  Schema for project-level snapshots.

  Each snapshot stores a reference to a compressed JSON file in object storage
  containing the full state of all project entities (sheets, flows, scenes).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          project_id: integer(),
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          storage_key: String.t(),
          snapshot_size_bytes: integer(),
          entity_counts: map(),
          created_by_id: integer() | nil,
          created_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "project_snapshots" do
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :storage_key, :string
    field :snapshot_size_bytes, :integer
    field :entity_counts, :map, default: %{}

    belongs_to :project, Project
    belongs_to :created_by, User

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new project snapshot.
  """
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [
      :project_id,
      :version_number,
      :title,
      :description,
      :storage_key,
      :snapshot_size_bytes,
      :entity_counts,
      :created_by_id
    ])
    |> validate_required([
      :project_id,
      :version_number,
      :storage_key,
      :snapshot_size_bytes
    ])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
    |> validate_number(:snapshot_size_bytes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint([:project_id, :version_number],
      name: :project_snapshots_project_id_version_number_index
    )
  end

  @doc """
  Changeset for updating title and description on an existing snapshot.
  """
  def update_changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:title, :description])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 500)
  end
end
