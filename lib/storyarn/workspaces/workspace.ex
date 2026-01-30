defmodule Storyarn.Workspaces.Workspace do
  @moduledoc """
  Schema for workspaces.

  A workspace is a container for projects that can be shared with team members.
  Each user has at least one workspace (created on registration).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project
  alias Storyarn.Workspaces.WorkspaceMembership

  schema "workspaces" do
    field :name, :string
    field :description, :string
    field :slug, :string
    field :banner_url, :string
    field :color, :string

    belongs_to :owner, User
    has_many :memberships, WorkspaceMembership
    has_many :members, through: [:memberships, :user]
    has_many :projects, Project

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new workspace.
  """
  def create_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :slug, :banner_url, :color])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> validate_slug()
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for updating a workspace.
  """
  def update_changeset(workspace, attrs) do
    workspace
    |> cast(attrs, [:name, :description, :banner_url, :color])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
  end

  defp validate_slug(changeset) do
    changeset
    |> validate_length(:slug, min: 1, max: 100)
    |> validate_format(:slug, ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/,
      message: "must be lowercase alphanumeric with hyphens"
    )
  end
end
