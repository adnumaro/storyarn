defmodule Storyarn.Projects.ProjectMembership do
  @moduledoc """
  Schema for project memberships.

  Each user's access to a project is represented by a membership record.
  The project owner also has a membership record with role "owner".
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Projects.Project

  @roles ~w(owner editor viewer)

  schema "project_memberships" do
    field :role, :string

    belongs_to :project, Project
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :project_id, :user_id])
    |> validate_required([:role, :project_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:project_id, :user_id],
      name: :project_memberships_project_id_user_id_index,
      message: "is already a member of this project"
    )
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid roles.
  """
  def roles, do: @roles

  @doc """
  Checks if a role can perform a given action.

  Actions:
  - :manage_project - update project settings, delete project
  - :manage_members - invite/remove members, change roles
  - :edit_content - edit flows, entities
  - :view - view project content

  Permissions:
  - owner: all actions
  - editor: edit_content, view
  - viewer: view only
  """
  def can?(role, action)

  def can?("owner", _action), do: true
  def can?("editor", :edit_content), do: true
  def can?("editor", :view), do: true
  def can?("viewer", :view), do: true
  def can?(_role, _action), do: false
end
