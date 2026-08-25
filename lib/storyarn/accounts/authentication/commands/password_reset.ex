defmodule Storyarn.Accounts.Authentication.Commands.PasswordReset do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Authentication.Adapters.Encryption.ResetUrl
  alias Storyarn.Accounts.Authentication.Adapters.Jobs.PasswordResetQueue
  alias Storyarn.Accounts.Authentication.Tokens.Issuer
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @reset_password_context "reset_password"
  @reset_token_placeholder "__STORYARN_RESET_TOKEN__"

  @spec deliver(User.t(), (String.t() -> String.t())) :: {:ok, :queued} | {:error, term()}
  def deliver(%User{} = user, reset_password_url_fun) when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = Issuer.email(user, @reset_password_context)
    encrypted_reset_url = ResetUrl.encrypt!(reset_password_url_fun.(encoded_token))

    Repo.transact(fn ->
      delete_tokens(user)

      with {:ok, _user_token} <- Repo.insert(user_token),
           {:ok, _job} <- PasswordResetQueue.enqueue_delivery(user.email, encrypted_reset_url) do
        {:ok, :queued}
      end
    end)
  end

  @spec request(String.t(), (String.t() -> String.t())) :: {:ok, :queued} | {:error, term()}
  def request(email, reset_password_url_fun) when is_binary(email) and is_function(reset_password_url_fun, 1) do
    reset_url_template = reset_password_url_fun.(@reset_token_placeholder)

    if is_binary(reset_url_template) and String.contains?(reset_url_template, @reset_token_placeholder) do
      email
      |> normalize_email()
      |> PasswordResetQueue.enqueue_request(reset_url_template)
      |> case do
        {:ok, _job} -> {:ok, :queued}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :invalid_reset_password_url_template}
    end
  end

  @spec process(String.t(), String.t()) :: :ok | {:ok, :queued} | {:error, term()}
  def process(email, reset_url_template) when is_binary(email) and is_binary(reset_url_template) do
    case Repo.get_by(User, email: normalize_email(email)) do
      %User{} = user ->
        deliver(user, fn token ->
          String.replace(reset_url_template, @reset_token_placeholder, token)
        end)

      nil ->
        :ok
    end
  end

  defp delete_tokens(%User{id: user_id}) do
    Repo.delete_all(
      from(token in UserToken,
        where: token.user_id == ^user_id and token.context == @reset_password_context
      )
    )
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
