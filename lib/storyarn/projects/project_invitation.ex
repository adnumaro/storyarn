defmodule Storyarn.Projects.ProjectInvitation do
  @moduledoc """
  Schema for project invitations.

  Invitations are token-based and expire after 7 days.
  """

  use Storyarn.Shared.InvitationSchema,
    parent_key: :project_id,
    parent_schema: Storyarn.Projects.Project,
    allowed_roles: ~w(editor viewer),
    default_role: "editor",
    verify_preloads: [[project: :workspace], :invited_by]

  alias Storyarn.Projects.Project

  @type t :: %__MODULE__{
          id: integer() | nil,
          email: String.t() | nil,
          token: binary() | nil,
          role: String.t() | nil,
          expires_at: DateTime.t() | nil,
          accepted_at: DateTime.t() | nil,
          project_id: integer() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil,
          invited_by_id: integer() | nil,
          invited_by: User.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "project_invitations" do
    field :email, :string
    field :token, :binary
    field :role, :string, default: "editor"
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :invited_by, User

    timestamps(type: :utc_datetime)
  end
end
