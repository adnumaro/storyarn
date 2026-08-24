defmodule Storyarn.Workspaces.WorkspaceInvitation do
  @moduledoc """
  Schema for workspace invitations.

  Invitations are token-based and expire after 7 days.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Association.NotLoaded
  alias Storyarn.Shared.TimeHelpers
  alias Storyarn.Shared.TokenGenerator
  alias Storyarn.Workspaces.Persistence.UserRecord
  alias Storyarn.Workspaces.Workspace

  @invitation_validity_in_days 7
  @allowed_roles ~w(admin member viewer)
  @default_role "member"
  @email_format ~r/^[^@,;\s]+@[^@,;\s]+$/

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

  @doc """
  Changeset for creating an invitation.
  """
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :workspace_id, :invited_by_id])
    |> validate_required([:email, :role, :workspace_id])
    |> validate_format(:email, @email_format, message: "must have the @ sign and no spaces")
    |> validate_length(:email, max: 160)
    |> validate_inclusion(:role, @allowed_roles)
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  @doc "Validates the `:email` field with the invitation email format."
  def validate_email_format(changeset) do
    validate_format(changeset, :email, @email_format, message: "must have the @ sign and no spaces")
  end

  @doc """
  Builds an invitation with a generated token.

  Returns `{encoded_token, invitation_struct}` where the encoded_token
  should be sent to the user and the invitation_struct should be inserted
  into the database.
  """
  def build_invitation(parent, invited_by, email, role \\ @default_role) do
    {encoded_token, hashed_token} = TokenGenerator.build_hashed_token()

    expires_at = DateTime.add(TimeHelpers.now(), @invitation_validity_in_days, :day)

    invited_by_id = if invited_by, do: invited_by.id

    invitation = %__MODULE__{
      workspace_id: parent.id,
      invited_by_id: invited_by_id,
      email: String.downcase(email),
      token: hashed_token,
      role: role,
      expires_at: expires_at
    }

    {encoded_token, invitation}
  end

  @doc """
  Verifies a token and returns a query for the invitation if valid.

  Returns `{:ok, query}` if the token is valid, `:error` otherwise.
  """
  def verify_token_query(token) do
    case TokenGenerator.decode_and_hash(token) do
      {:ok, hashed_token} ->
        query =
          from(i in __MODULE__,
            where: i.token == ^hashed_token,
            where: i.expires_at > ^TimeHelpers.now(),
            where: is_nil(i.accepted_at),
            preload: [:workspace, :invited_by]
          )

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc """
  Returns the invitation validity period in days.
  """
  def validity_in_days, do: @invitation_validity_in_days
end
