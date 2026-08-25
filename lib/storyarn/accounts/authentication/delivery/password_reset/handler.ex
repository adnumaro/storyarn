defmodule Storyarn.Accounts.Authentication.Delivery.PasswordReset.Handler do
  @moduledoc false

  alias Storyarn.Accounts.Authentication.Adapters.Email.Mailer
  alias Storyarn.Accounts.Authentication.Delivery.PasswordReset.Content

  @spec deliver(String.t() | map(), String.t()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver(%{email: email}, url), do: deliver(email, url)

  def deliver(email, url) when is_binary(email) do
    {subject, html, text} = Content.render(email, url)
    Mailer.deliver(email, subject, html, text)
  end
end
