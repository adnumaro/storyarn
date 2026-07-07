defmodule Storyarn.Accounts.Passwords do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Sessions
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Workers.DeliverResetPasswordInstructionsWorker

  @reset_password_context "reset_password"

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Queues reset password instructions for an existing user.

  Passing `nil` is a no-op so callers can keep the public response generic and
  avoid exposing whether an email address belongs to an account.
  """
  def deliver_user_reset_password_instructions(nil, reset_password_url_fun) when is_function(reset_password_url_fun, 1) do
    {:ok, :queued}
  end

  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, @reset_password_context)
    encrypted_reset_url = encrypt_reset_password_url!(reset_password_url_fun.(encoded_token))

    Repo.transact(fn ->
      delete_user_reset_password_tokens(user)

      with {:ok, _user_token} <- Repo.insert(user_token),
           {:ok, _job} <-
             %{email: user.email, encrypted_reset_url: encrypted_reset_url}
             |> DeliverResetPasswordInstructionsWorker.new()
             |> Oban.insert() do
        {:ok, :queued}
      end
    end)
  end

  @doc false
  def decrypt_reset_password_url(encrypted_reset_url) when is_binary(encrypted_reset_url) do
    with {:ok, encrypted_binary} <- Base.decode64(encrypted_reset_url),
         {:ok, reset_url} <- EncryptedBinary.load(encrypted_binary) do
      {:ok, reset_url}
    else
      _ -> {:error, :invalid_reset_password_url}
    end
  end

  @doc """
  Gets the user for a valid reset password token.
  """
  def get_user_by_reset_password_token(token) do
    case UserToken.verify_reset_password_token_query(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.
  """
  def update_user_password(user, attrs) do
    changeset = User.password_changeset(user, attrs)

    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Sessions.delete_all_user_tokens(user)
        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  @doc """
  Resets the user password and expires all existing tokens.
  """
  def reset_user_password(%User{} = user, attrs) do
    update_user_password(user, attrs)
  end

  defp encrypt_reset_password_url!(reset_url) do
    {:ok, encrypted_binary} = EncryptedBinary.dump(reset_url)
    Base.encode64(encrypted_binary)
  end

  defp delete_user_reset_password_tokens(%User{id: user_id}) do
    Repo.delete_all(
      from(token in UserToken, where: token.user_id == ^user_id and token.context == @reset_password_context)
    )
  end
end
