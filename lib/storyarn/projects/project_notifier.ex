defmodule Storyarn.Projects.ProjectNotifier do
  @moduledoc """
  Handles email notifications for project-related actions.
  """
  import Swoosh.Email
  require Logger
  use Gettext, backend: StoryarnWeb.Gettext

  alias Storyarn.Emails.Templates
  alias Storyarn.Mailer
  alias Storyarn.Projects.ProjectInvitation

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
        Logger.info("Email sent to #{recipient}: #{subject}")
        {:ok, email}

      {:error, reason} ->
        Logger.error("Failed to send email to #{recipient}: #{inspect(reason)}")
        {:error, reason}
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

    {subject, html, text} =
      Templates.project_invitation(
        invitation.email,
        project_name,
        inviter_name,
        invitation.role,
        url,
        days
      )

    deliver(invitation.email, subject, html, text)
  end

  defp invitation_url(token) do
    StoryarnWeb.Endpoint.url() <> "/projects/invitations/#{token}"
  end
end
