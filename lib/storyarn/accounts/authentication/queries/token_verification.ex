defmodule Storyarn.Accounts.Authentication.Queries.TokenVerification do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Accounts.UserToken

  @change_email_validity_in_days 7
  @reset_password_validity_in_hours 24
  @session_validity_in_days 14

  def session(token) do
    from token_record in by_token_and_context(token, "session"),
      join: user in assoc(token_record, :user),
      where: token_record.inserted_at > ago(@session_validity_in_days, "day"),
      select: {%{user | authenticated_at: token_record.authenticated_at}, token_record.inserted_at}
  end

  def active_session(token, user_id) do
    from session_token in by_token_and_context(token, "session"),
      where: session_token.user_id == ^user_id,
      where: session_token.inserted_at > ago(@session_validity_in_days, "day")
  end

  def change_email(hashed_token, context) do
    from token_record in by_token_and_context(hashed_token, context),
      where: token_record.inserted_at > ago(@change_email_validity_in_days, "day")
  end

  def reset_password(hashed_token) do
    from token_record in by_token_and_context(hashed_token, "reset_password"),
      join: user in assoc(token_record, :user),
      where: token_record.inserted_at > ago(@reset_password_validity_in_hours, "hour"),
      where: token_record.sent_to == user.email,
      select: user
  end

  defp by_token_and_context(token, context), do: from(UserToken, where: [token: ^token, context: ^context])
end
