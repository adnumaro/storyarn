defmodule Storyarn.Accounts.Registration.Commands.CompleteInvitation do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Registration.Events.UserSignedUp
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @doc """
  Completes the user's registration by setting their password and consuming the invite token.
  """
  def execute(%User{} = user, token_record, attrs) do
    result =
      Repo.transact(fn ->
        user_changeset =
          user
          |> User.confirm_changeset()
          |> User.password_changeset(attrs, hash_password: true)

        with {1, nil} <- delete_registration_invite_token(token_record, user),
             {:ok, updated_user} <- Repo.update(user_changeset) do
          # Consume all registration tokens for this user immediately.
          delete_registration_invite_tokens(token_record.user_id)
          {:ok, updated_user}
        else
          {0, nil} -> {:error, :stale_invite_token}
          {:error, _reason} = error -> error
        end
      end)

    case result do
      {:ok, updated_user} ->
        UserSignedUp.emit(updated_user, "invite")
        {:ok, updated_user}

      error ->
        error
    end
  end

  defp delete_registration_invite_token(%UserToken{} = token_record, %User{} = user) do
    Repo.delete_all(
      from(t in UserToken,
        where: t.id == ^token_record.id,
        where: t.user_id == ^user.id,
        where: t.context == "invite"
      )
    )
  end

  defp delete_registration_invite_tokens(user_id) do
    Repo.delete_all(from(t in UserToken, where: t.user_id == ^user_id and t.context == "invite"))
  end
end
