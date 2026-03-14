defmodule Storyarn.Versioning.EntityVersion do
  @moduledoc """
  Schema for generalized entity version history.

  Each version stores a reference to a compressed JSON snapshot in object storage,
  supporting sheets, flows, and scenes.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          entity_type: String.t(),
          entity_id: integer(),
          project_id: integer(),
          version_number: integer(),
          title: String.t() | nil,
          description: String.t() | nil,
          change_summary: String.t() | nil,
          change_details: map() | nil,
          storage_key: String.t(),
          snapshot_size_bytes: integer(),
          is_auto: boolean(),
          created_by_id: integer() | nil,
          created_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @valid_entity_types ~w(sheet flow scene)

  schema "entity_versions" do
    field :entity_type, :string
    field :entity_id, :integer
    field :version_number, :integer
    field :title, :string
    field :description, :string
    field :change_summary, :string
    field :change_details, :map
    field :storage_key, :string
    field :snapshot_size_bytes, :integer
    field :is_auto, :boolean, default: false

    belongs_to :project, Project
    belongs_to :created_by, User

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new entity version.
  """
  def changeset(version, attrs) do
    version
    |> cast(attrs, [
      :entity_type,
      :entity_id,
      :project_id,
      :version_number,
      :title,
      :description,
      :change_summary,
      :change_details,
      :storage_key,
      :snapshot_size_bytes,
      :is_auto,
      :created_by_id
    ])
    |> validate_required([
      :entity_type,
      :entity_id,
      :project_id,
      :version_number,
      :storage_key,
      :snapshot_size_bytes
    ])
    |> validate_inclusion(:entity_type, @valid_entity_types)
    |> validate_length(:title, max: 255)
    |> validate_number(:snapshot_size_bytes, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint([:entity_type, :entity_id, :version_number],
      name: :entity_versions_type_id_number_unique
    )
  end

  @doc """
  Changeset for updating title and description on an existing version (promotion).
  Title is required — you cannot un-name a version.
  Automatically sets `is_auto: false` so promoted versions count against the named quota.
  """
  def update_changeset(version, attrs) do
    version
    |> cast(attrs, [:title, :description])
    |> put_change(:is_auto, false)
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 255)
    |> validate_length(:description, max: 500)
  end

  @doc """
  Returns the list of valid entity types.
  """
  def valid_entity_types, do: @valid_entity_types
end
