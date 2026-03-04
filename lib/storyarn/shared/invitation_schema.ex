defmodule Storyarn.Shared.InvitationSchema do
  @moduledoc """
  Shared invitation schema logic for Projects and Workspaces.

  ## Usage

      use Storyarn.Shared.InvitationSchema,
        parent_key: :project_id,
        parent_schema: Storyarn.Projects.Project,
        allowed_roles: ~w(editor viewer),
        default_role: "editor",
        verify_preloads: [[project: :workspace], :invited_by]
  """

  defmacro __using__(opts) do
    parent_key = Keyword.fetch!(opts, :parent_key)
    allowed_roles = Keyword.fetch!(opts, :allowed_roles)
    default_role = Keyword.fetch!(opts, :default_role)
    verify_preloads = Keyword.fetch!(opts, :verify_preloads)

    quote do
      use Ecto.Schema
      import Ecto.Changeset
      import Ecto.Query

      alias Storyarn.Accounts.User
      alias Storyarn.Shared.{TokenGenerator, Validations}

      @invitation_validity_in_days 7
      @__parent_key unquote(parent_key)

      @doc """
      Changeset for creating an invitation.
      """
      def changeset(invitation, attrs) do
        invitation
        |> cast(attrs, [:email, :role, @__parent_key, :invited_by_id])
        |> validate_required([:email, :role, @__parent_key, :invited_by_id])
        |> Validations.validate_email_format()
        |> validate_inclusion(:role, unquote(allowed_roles))
        |> foreign_key_constraint(@__parent_key)
        |> foreign_key_constraint(:invited_by_id)
      end

      @doc """
      Builds an invitation with a generated token.

      Returns `{encoded_token, invitation_struct}` where the encoded_token
      should be sent to the user and the invitation_struct should be inserted
      into the database.
      """
      def build_invitation(parent, invited_by, email, role \\ unquote(default_role)) do
        {encoded_token, hashed_token} = TokenGenerator.build_hashed_token()

        expires_at =
          DateTime.utc_now()
          |> DateTime.add(@invitation_validity_in_days, :day)
          |> DateTime.truncate(:second)

        invitation =
          struct!(
            __MODULE__,
            [{@__parent_key, parent.id}] ++
              [
                invited_by_id: invited_by.id,
                email: String.downcase(email),
                token: hashed_token,
                role: role,
                expires_at: expires_at
              ]
          )

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
                where: i.expires_at > ^DateTime.utc_now(),
                where: is_nil(i.accepted_at),
                preload: unquote(verify_preloads)
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
  end
end
