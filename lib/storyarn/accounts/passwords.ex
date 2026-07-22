defmodule Storyarn.Accounts.Passwords do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Sessions
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo
  alias Storyarn.Shared.EncryptedBinary
  alias Storyarn.Workers.DeliverResetPasswordInstructionsWorker
  alias Storyarn.Workers.RequestResetPasswordInstructionsWorker

  @reset_password_context "reset_password"
  @reset_token_placeholder "__STORYARN_RESET_TOKEN__"

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Queues reset password instructions for an existing user.

  This lower-level function is used after an asynchronous reset request has
  resolved the account. Public callers should use
  `request_user_reset_password_instructions/2` so existing and missing emails
  take the same synchronous path.
  """
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

  @doc """
  Queues a password reset request without resolving the account synchronously.

  The worker performs the account lookup and only creates a reset token when
  the normalized email exists, keeping the public request path uniform.
  """
  def request_user_reset_password_instructions(email, reset_password_url_fun)
      when is_binary(email) and is_function(reset_password_url_fun, 1) do
    reset_url_template = reset_password_url_fun.(@reset_token_placeholder)

    if is_binary(reset_url_template) and String.contains?(reset_url_template, @reset_token_placeholder) do
      %{
        email: normalize_email(email),
        reset_url_template: reset_url_template
      }
      |> RequestResetPasswordInstructionsWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} -> {:ok, :queued}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_reset_password_url_template}
    end
  end

  @doc false
  def process_user_reset_password_request(email, reset_url_template)
      when is_binary(email) and is_binary(reset_url_template) do
    case Repo.get_by(User, email: normalize_email(email)) do
      %User{} = user ->
        deliver_user_reset_password_instructions(user, fn token ->
          String.replace(reset_url_template, @reset_token_placeholder, token)
        end)

      nil ->
        :ok
    end
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

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
