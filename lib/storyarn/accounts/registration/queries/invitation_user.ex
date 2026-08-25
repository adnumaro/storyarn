defmodule Storyarn.Accounts.Registration.Queries.InvitationUser do
  @moduledoc false

  alias Storyarn.Accounts.Registration.Tokens.Invitation
  alias Storyarn.Accounts.User
  alias Storyarn.Repo

  @doc """
  Gets the passwordless user with the given invite token.

  Used for gating registration. The token is consumed only after password setup
  succeeds.
  """
  def get(token) do
    with {:ok, query} <- Invitation.verify_query(token),
         {%User{hashed_password: nil} = user, found_token} <- Repo.one(query) do
      {user, found_token}
    else
      _ -> nil
    end
  end
end
