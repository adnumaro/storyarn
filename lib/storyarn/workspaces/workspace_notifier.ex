defmodule Storyarn.Workspaces.WorkspaceNotifier do
  @moduledoc """
  Handles email notifications for workspace-related actions.
  """
  import Swoosh.Email
  require Logger
  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Emails.Templates
  alias Storyarn.Mailer
  alias Storyarn.Workspaces.WorkspaceInvitation

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

  @doc """
  Delivers a workspace invitation email.
  """
  def deliver_invitation(%WorkspaceInvitation{} = invitation, url, opts \\ []) do
    workspace_name = invitation.workspace.name

    inviter_name =
      Keyword.get_lazy(opts, :inviter_name, fn ->
        case invitation.invited_by do
          nil -> "Storyarn"
          user -> user.display_name || user.email
        end
      end)

    days = WorkspaceInvitation.validity_in_days()

    {subject, html, text} =
      Templates.workspace_invitation(
        invitation.email,
        workspace_name,
        inviter_name,
        invitation.role,
        url,
        days
      )

    deliver(invitation.email, subject, html, text)
  end
end
