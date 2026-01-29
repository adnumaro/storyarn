defmodule Storyarn.Projects.Project do
  @moduledoc """
  Schema for projects.

  A project is a narrative design workspace that can be shared with team members.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.{ProjectInvitation, ProjectMembership}

  schema "projects" do
    field :name, :string
    field :description, :string
    field :settings, :map, default: %{}

    belongs_to :owner, User
    has_many :memberships, ProjectMembership
    has_many :members, through: [:memberships, :user]
    has_many :invitations, ProjectInvitation

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new project.
  """
  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
  end

  @doc """
  Changeset for updating a project.
  """
  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :settings])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
  end
end
