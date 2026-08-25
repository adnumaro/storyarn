defmodule Storyarn.Workspaces.Invitations.Adapters.Email.Mailer do
  @moduledoc """
  Technical email adapter for Workspace invitation messages.

  It receives already-rendered, Workspace-owned content and translates it into
  a `Swoosh.Email`. It does not choose recipients, copy, roles, expiry wording,
  or delivery policy.
  """

  import Swoosh.Email

  alias Storyarn.Platform.Mailer, as: PlatformMailer

  require Logger

  @spec deliver(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver(recipient, subject, html_body, text_body) do
    {sender_name, sender_email} = sender()

    email =
      new()
      |> to(recipient)
      |> from({sender_name, sender_email})
      |> subject(subject)
      |> html_body(html_body)
      |> text_body(text_body)

    case PlatformMailer.deliver(email) do
      {:ok, _metadata} ->
        Logger.info("Email delivered successfully")
        {:ok, email}

      {:error, reason} ->
        Logger.error("Email delivery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp sender do
    Application.get_env(:storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"})
  end
end
