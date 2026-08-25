defmodule Storyarn.Accounts.Authentication.Commands.EmailChange do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Accounts.Authentication.Delivery.EmailChange.Handler
  alias Storyarn.Accounts.Authentication.Tokens.Issuer
  alias Storyarn.Accounts.Authentication.Tokens.Verifier
  alias Storyarn.Accounts.User
  alias Storyarn.Accounts.UserToken
  alias Storyarn.Repo

  @spec change(User.t(), map(), keyword()) :: Ecto.Changeset.t()
  def change(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @spec update(User.t(), String.t()) :: {:ok, User.t()} | {:error, :transaction_aborted}
  def update(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- Verifier.change_email(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @spec deliver_instructions(User.t(), String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = Issuer.email(user, "change:#{current_email}")

    Repo.insert!(user_token)
    Handler.deliver(user, update_email_url_fun.(encoded_token))
  end
end
