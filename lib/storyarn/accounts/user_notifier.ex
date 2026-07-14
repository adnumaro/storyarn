defmodule Storyarn.Accounts.UserNotifier do
  @moduledoc """
  Handles email notifications for user account actions.
  """
  import Swoosh.Email

  alias Storyarn.Emails.Templates
  alias Storyarn.Mailer

  require Logger

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
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    {subject, html, text} = Templates.update_email(user.email, url)
    deliver(user.email, subject, html, text)
  end

  @doc """
  Deliver instructions to reset a user password.
  """
  def deliver_reset_password_instructions(%{email: email}, url) do
    deliver_reset_password_instructions(email, url)
  end

  def deliver_reset_password_instructions(email, url) when is_binary(email) do
    {subject, html, text} = Templates.reset_password(email, url)
    deliver(email, subject, html, text)
  end

  @doc """
  Deliver admin notification about a member invitation request.
  """
  def deliver_admin_invitation_request(request_info) do
    admin_email = Application.get_env(:storyarn, :admin_email, "adan@storyarn.com")
    {subject, html, text} = Templates.admin_invitation_request(request_info)
    deliver(admin_email, subject, html, text)
  end

  @doc """
  Deliver project/workspace invitation email.
  """
  def deliver_invitation(email, type, entity_name, role, url, days) do
    {subject, html, text} =
      if type == "project",
        do: Templates.project_invitation(email, entity_name, "Storyarn", role, url, days),
        else: Templates.workspace_invitation(email, entity_name, "Storyarn", role, url, days)

    deliver(email, subject, html, text)
  end
end
