defmodule Storyarn.Accounts.Authentication.Delivery.EmailChange.Handler do
  @moduledoc false

  alias Storyarn.Accounts.Authentication.Adapters.Email.Mailer
  alias Storyarn.Accounts.Authentication.Delivery.EmailChange.Content

  @spec deliver(map(), String.t()) :: {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver(%{email: email}, url) do
    {subject, html, text} = Content.render(email, url)
    Mailer.deliver(email, subject, html, text)
  end
end
