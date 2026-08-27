defmodule Storyarn.Accounts.Authentication.Tokens.Verifier do
  @moduledoc false

  alias Storyarn.Accounts.Authentication.Queries.TokenVerification
  alias Storyarn.Platform.Shared.TokenGenerator

  @spec session(binary()) :: {:ok, Ecto.Query.t()}
  def session(token), do: {:ok, TokenVerification.session(token)}

  @spec active_session(binary(), integer()) :: Ecto.Query.t()
  def active_session(token, user_id), do: TokenVerification.active_session(token, user_id)

  @spec change_email(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def change_email(token, "change:" <> _ = context) do
    case TokenGenerator.decode_and_hash(token) do
      {:ok, hashed_token} ->
        {:ok, TokenVerification.change_email(hashed_token, context)}

      :error ->
        :error
    end
  end

  @spec reset_password(String.t()) :: {:ok, Ecto.Query.t()} | :error
  def reset_password(token) do
    case TokenGenerator.decode_and_hash(token) do
      {:ok, hashed_token} ->
        {:ok, TokenVerification.reset_password(hashed_token)}

      :error ->
        :error
    end
  end
end
