defmodule Storyarn.Projects.ProjectNotifier do
  @moduledoc """
  Handles email notifications for project-related actions.
  """
  import Swoosh.Email
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Mailer
  alias Storyarn.Projects.ProjectInvitation

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    {sender_name, sender_email} = sender()

    email =
      new()
      |> to(recipient)
      |> from({sender_name, sender_email})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp sender do
    Application.get_env(:storyarn, :mailer_sender, {"Storyarn", "noreply@storyarn.com"})
  end

  @doc """
  Delivers a project invitation email.
  """
  def deliver_invitation(%ProjectInvitation{} = invitation, encoded_token) do
    url = invitation_url(encoded_token)
    project_name = invitation.project.name
    inviter_name = invitation.invited_by.display_name || invitation.invited_by.email
    days = ProjectInvitation.validity_in_days()

    subject =
      dgettext("emails", "You've been invited to %{project}", project: project_name)

    body =
      dgettext(
        "emails",
        """

        ==============================

        Hi,

        %{inviter} has invited you to join "%{project}" on Storyarn as %{role}.

        You can accept this invitation by visiting the URL below:

        %{url}

        This invitation will expire in %{days} days.

        If you don't want to join this project, you can ignore this email.

        ==============================
        """,
        inviter: inviter_name,
        project: project_name,
        role: invitation.role,
        url: url,
        days: days
      )

    deliver(invitation.email, subject, body)
  end

  defp invitation_url(token) do
    StoryarnWeb.Endpoint.url() <> "/projects/invitations/#{token}"
  end
end
