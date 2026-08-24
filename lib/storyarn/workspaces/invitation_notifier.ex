defmodule Storyarn.Workspaces.InvitationNotifier do
  @moduledoc """
  Workspace invitation email delivery.

  Workspace-owned copy of the retired shared notifier, specialized to the
  workspace invitation template.
  """

  import Swoosh.Email

  alias Storyarn.Emails.Templates
  alias Storyarn.Mailer
  alias Storyarn.Shared.TimeHelpers

  require Logger

  @seconds_per_day 86_400

  @doc """
  Delivers a workspace invitation email.
  """
  def deliver_invitation(invitation, url, opts \\ []) do
    entity_name = invitation.workspace.name

    inviter_name =
      Keyword.get_lazy(opts, :inviter_name, fn ->
        case invitation.invited_by do
          nil -> "Storyarn"
          user -> user.display_name || user.email
        end
      end)

    days = remaining_days(invitation.expires_at)

    {subject, html, text} =
      Templates.workspace_invitation(
        invitation.email,
        entity_name,
        inviter_name,
        invitation.role,
        url,
        days
      )

    deliver(invitation.email, subject, html, text)
  end

  defp remaining_days(expires_at) do
    remaining_seconds = DateTime.diff(expires_at, TimeHelpers.now(), :second)
    div(max(remaining_seconds, 1) + @seconds_per_day - 1, @seconds_per_day)
  end

  defp deliver(recipient, subject, html_body, text_body) do
    {sender_name, sender_email} = sender()

    email =
      new()
      |> to(recipient)
      |> from({sender_name, sender_email})
      |> subject(subject)
      |> html_body(html_body)
      |> text_body(text_body)

    case Mailer.deliver(email) do
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
