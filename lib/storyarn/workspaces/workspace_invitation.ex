defmodule Storyarn.Workspaces.WorkspaceInvitation do
  @moduledoc """
  Schema for workspace invitations.

  Invitations are token-based and expire after 7 days.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Storyarn.Accounts.User
  alias Storyarn.Workspaces.Workspace

  @hash_algorithm :sha256
  @rand_size 32
  @invitation_validity_in_days 7

  schema "workspace_invitations" do
    field :email, :string
    field :token, :binary
    field :role, :string, default: "member"
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :workspace, Workspace
    belongs_to :invited_by, User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating an invitation.
  """
  def changeset(invitation, attrs) do
    invitation
    |> cast(attrs, [:email, :role, :workspace_id, :invited_by_id])
    |> validate_required([:email, :role, :workspace_id, :invited_by_id])
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_inclusion(:role, ~w(admin member viewer))
    |> foreign_key_constraint(:workspace_id)
    |> foreign_key_constraint(:invited_by_id)
  end

  @doc """
  Builds an invitation with a generated token.

  Returns `{encoded_token, invitation_struct}` where the encoded_token
  should be sent to the user and the invitation_struct should be inserted
  into the database.
  """
  def build_invitation(workspace, invited_by, email, role \\ "member") do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    expires_at =
      DateTime.utc_now()
      |> DateTime.add(@invitation_validity_in_days, :day)
      |> DateTime.truncate(:second)

    invitation = %__MODULE__{
      workspace_id: workspace.id,
      invited_by_id: invited_by.id,
      email: String.downcase(email),
      token: hashed_token,
      role: role,
      expires_at: expires_at
    }

    {Base.url_encode64(token, padding: false), invitation}
  end

  @doc """
  Verifies a token and returns a query for the invitation if valid.

  Returns `{:ok, query}` if the token is valid, `:error` otherwise.
  """
  def verify_token_query(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from(i in __MODULE__,
            where: i.token == ^hashed_token,
            where: i.expires_at > ^DateTime.utc_now(),
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
