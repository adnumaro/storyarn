defmodule Storyarn.Workspaces.WorkspaceNotifier do
  @moduledoc """
  Handles email notifications for workspace-related actions.
  """
  import Swoosh.Email
  use Gettext, backend: StoryarnWeb.Gettext

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

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp sender do
    Application.get_env(:storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"})
  end

  @doc """
  Delivers a workspace invitation email.
  """
  def deliver_invitation(%WorkspaceInvitation{} = invitation, encoded_token) do
    url = invitation_url(encoded_token)
    workspace_name = invitation.workspace.name
    inviter_name = invitation.invited_by.display_name || invitation.invited_by.email
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

  defp invitation_url(token) do
    StoryarnWeb.Endpoint.url() <> "/workspaces/invitations/#{token}"
  end
end
