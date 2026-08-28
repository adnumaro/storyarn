defmodule Storyarn.Workspaces.WorkspaceInvitation do
  @moduledoc """
  Workspace invitation entity backed by the `workspace_invitations` table.

  Invitation lifecycle behavior lives in the `Storyarn.Workspaces.Invitations`
  capability. The module identity remains stable for Ecto associations and
  encoded workspace data; consumers perform operations through
  `Storyarn.Workspaces`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Storyarn.Workspaces.Invitations.Projections.UserRecord
  alias Storyarn.Workspaces.Invitations.Rules.Email
  alias Storyarn.Workspaces.Invitations.Rules.Policy
  alias Storyarn.Workspaces.Workspace

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          token: binary() | nil,
          role: String.t() | nil,
          expires_at: DateTime.t() | nil,
          accepted_at: DateTime.t() | nil,
          workspace_id: integer() | nil,
          workspace: Workspace.t() | NotLoaded.t() | nil,
          invited_by_id: integer() | nil,
          invited_by: UserRecord.t() | NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "workspace_invitations" do
    field :email, :string
    field :token, :binary
    field :role, :string, default: "member"
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :invited_by, UserRecord

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset for creating an invitation."
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :workspace_id, :invited_by_id])
    |> validate_required([:email, :role, :workspace_id])
    |> Email.validate_changeset()
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, Policy.allowed_roles())
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  @doc "Validates the `:email` field with the invitation email format."
  def validate_email_format(changeset), do: Email.validate_changeset(changeset)
end
