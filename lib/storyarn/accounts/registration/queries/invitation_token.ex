defmodule Storyarn.Accounts.Registration.Queries.InvitationToken do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Accounts.UserToken

  @validity_in_days 14

  def by_hash(hashed_token, context) do
    from token in UserToken,
      where: token.token == ^hashed_token,
      where: token.context == ^context,
      join: user in assoc(token, :user),
      where: token.inserted_at > ago(@validity_in_days, "day"),
      where: token.sent_to == user.email,
      select: {user, token}
  end
end
