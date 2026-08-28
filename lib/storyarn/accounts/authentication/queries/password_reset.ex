defmodule Storyarn.Accounts.Authentication.Queries.PasswordReset do
  @moduledoc false

  alias Storyarn.Accounts.Authentication.Tokens.Verifier
  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  @spec get_user(String.t()) :: User.t() | nil
  def get_user(token) do
    case Verifier.reset_password(token) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end
end
