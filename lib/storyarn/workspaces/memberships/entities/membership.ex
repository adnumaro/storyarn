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

  alias Ecto.Association.NotLoaded
  alias Storyarn.Workspaces.Memberships.Data.UserRecord
  alias Storyarn.Workspaces.Memberships.Rules.Permissions
  alias Storyarn.Workspaces.Workspace

  @type t :: %__MODULE__{
          id: integer() | nil,
          role: String.t() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | NotLoaded.t() | nil,
          user_id: integer() | nil,
          user: UserRecord.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "workspace_memberships" do
    field :role, :string

    belongs_to :workspace, Workspace
    belongs_to :user, UserRecord

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a membership.
  """
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:role, :workspace_id, :user_id])
    |> validate_required([:role, :workspace_id, :user_id])
    |> validate_inclusion(:role, Permissions.roles())
    |> unique_constraint([:workspace_id, :user_id],
      name: :workspace_memberships_workspace_id_user_id_index,
      message: "is already a member of this workspace"
    )
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:user_id)
  end
end
