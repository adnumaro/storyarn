defmodule Storyarn.Accounts.Authentication.Tokens.Verifier do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Accounts.UserToken
  alias Storyarn.Platform.Shared.TokenGenerator

  @change_email_validity_in_days 7
  @reset_password_validity_in_hours 24
  @session_validity_in_days 14

  @spec session(binary()) :: {:ok, Ecto.Query.t()}
  def session(token) do
    query =
      from token_record in by_token_and_context(token, "session"),
        join: user in assoc(token_record, :user),
        where: token_record.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token_record.authenticated_at}, token_record.inserted_at}

    {:ok, query}
  end

  @spec active_session(binary(), integer()) :: Ecto.Query.t()
  def active_session(token, user_id) do
    from session_token in by_token_and_context(token, "session"),
      where: session_token.user_id == ^user_id,
      where: session_token.inserted_at > ago(@session_validity_in_days, "day")
  end

  @spec change_email(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def change_email(token, "change:" <> _ = context) do
    case TokenGenerator.decode_and_hash(token) do
      {:ok, hashed_token} ->
        query =
          from token_record in by_token_and_context(hashed_token, context),
            where: token_record.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  @spec reset_password(String.t()) :: {:ok, Ecto.Query.t()} | :error
  def reset_password(token) do
    case TokenGenerator.decode_and_hash(token) do
      {:ok, hashed_token} ->
        query =
          from token_record in by_token_and_context(hashed_token, "reset_password"),
            join: user in assoc(token_record, :user),
            where: token_record.inserted_at > ago(@reset_password_validity_in_hours, "hour"),
            where: token_record.sent_to == user.email,
            select: user

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
