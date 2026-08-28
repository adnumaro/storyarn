defmodule Storyarn.Accounts.Registration.Commands.PrepareInvitation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Registration.Commands.Register
  alias Storyarn.Accounts.Registration.Tokens.Invitation
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @doc """
  Finds an existing user by email, or registers and auto-confirms a new one.

  Used for invitation acceptance where the user must be able to log in immediately.
  Returns `{:ok, user}` or `{:error, changeset}`.
  """
  def find_or_register_confirmed_user(email) do
    case Repo.get_by(User, email: String.downcase(email)) do
      %User{} = user ->
        {:ok, user}

      nil ->
        with {:ok, user} <- Register.register_user(%{"email" => email}) do
          Repo.update(User.confirm_changeset(user))
        end
    end
  end

  @doc """
  Finds or creates a user for a workspace/project invitation.

  Users with passwords can accept the invitation immediately. New users, and
  existing passwordless users, must complete password setup before the invitation
  is accepted.
  """
  def prepare_invitation_user(email) do
    email = String.downcase(email)

    case Repo.get_by(User, email: email) do
      %User{hashed_password: hashed_password} = user when is_binary(hashed_password) ->
        {:ok, {:ready, user}}

      %User{} = user ->
        create_registration_invite_token(user)

      nil ->
        with {:ok, user} <- Register.register_user(%{"email" => email}) do
          create_registration_invite_token(user)
        end
    end
  end

  defp create_registration_invite_token(%User{} = user) do
    Repo.transact(fn ->
      delete_registration_invite_tokens(user.id)

      {encoded_token, user_token} = Invitation.issue(user)

      with {:ok, _user_token} <- Repo.insert(user_token) do
        {:ok, {:registration_required, encoded_token}}
      end
    end)
  end

  defp delete_registration_invite_tokens(user_id) do
    Repo.delete_all(from(t in UserToken, where: t.user_id == ^user_id and t.context == "invite"))
  end
end
