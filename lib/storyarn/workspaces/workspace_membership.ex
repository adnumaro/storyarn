defmodule Storyarn.Workspaces.WorkspaceMembership do
  @moduledoc """
  Schema for workspace memberships.

  Each user's access to a workspace is represented by a membership record.
  The workspace owner also has a membership record with role "owner".

  Roles:
  - owner: Full control over workspace and all projects
  - admin: Can manage members and projects
  - member: Can create/edit projects
  - viewer: Read-only access
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Storyarn.Accounts.User
  alias Storyarn.Workspaces.Workspace

  @roles ~w(owner admin member viewer)

  schema "workspace_memberships" do
    field :role, :string

    belongs_to :workspace, Workspace
    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :workspace_id, :user_id])
    |> validate_required([:role, :workspace_id, :user_id])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:workspace_id, :user_id],
      name: :workspace_memberships_workspace_id_user_id_index,
      message: "is already a member of this workspace"
    )
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Returns the list of valid roles.
  """
  def roles, do: @roles

  @doc """
  Checks if a role can perform a given action at the workspace level.

  Actions:
  - :manage_workspace - update workspace settings, delete workspace
  - :manage_members - invite/remove members, change roles
  - :create_project - create new projects
  - :view - view workspace and projects

  Permissions:
  - owner: all actions
  - admin: manage_members, create_project, view
  - member: create_project, view
  - viewer: view only
  """
  def can?(role, action)

  def can?("owner", _action), do: true
  def can?("admin", :manage_members), do: true
  def can?("admin", :create_project), do: true
  def can?("admin", :view), do: true
  def can?("member", :create_project), do: true
  def can?("member", :view), do: true
  def can?("viewer", :view), do: true
  def can?(_role, _action), do: false
end
