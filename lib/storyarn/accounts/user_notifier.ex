defmodule Storyarn.Accounts.UserNotifier do
  @moduledoc """
  Handles email notifications for user account actions.
  """
  import Swoosh.Email
  require Logger

  alias Storyarn.Accounts.User
  alias Storyarn.Emails.Templates
  alias Storyarn.Mailer

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
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    {subject, html, text} = Templates.update_email(user.email, url)
    deliver(user.email, subject, html, text)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} ->
        {subject, html, text} = Templates.confirmation(user.email, url)
        deliver(user.email, subject, html, text)

      _ ->
        {subject, html, text} = Templates.magic_link(user.email, url)
        deliver(user.email, subject, html, text)
    end
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
  Deliver waitlist invite email.
  """
  def deliver_waitlist_invite(email, login_url) do
    {subject, html, text} = Templates.waitlist_invite(email, login_url)
    deliver(email, subject, html, text)
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

  @doc """
  Deliver admin notification about a new waitlist signup.
  """
  def deliver_admin_waitlist_notification(email, signup_info \\ %{}) do
    admin_email = Application.get_env(:storyarn, :admin_email, "adan@storyarn.com")
    {subject, html, text} = Templates.admin_waitlist_signup(email, signup_info)
    deliver(admin_email, subject, html, text)
  end
end
