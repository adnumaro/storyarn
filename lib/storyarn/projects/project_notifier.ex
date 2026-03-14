defmodule Storyarn.Projects.ProjectNotifier do
  @moduledoc """
  Handles email notifications for project-related actions.
  """
  import Swoosh.Email
  require Logger
  use Gettext, backend: Storyarn.Gettext

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
  Delivers a project invitation email.
  """
  def deliver_invitation(%ProjectInvitation{} = invitation, url, opts \\ []) do
    project_name = invitation.project.name

    inviter_name =
      Keyword.get_lazy(opts, :inviter_name, fn ->
        case invitation.invited_by do
          nil -> "Storyarn"
          user -> user.display_name || user.email
        end
      end)

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
end
