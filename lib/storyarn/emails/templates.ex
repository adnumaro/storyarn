defmodule Storyarn.Emails.Templates do
  @moduledoc """
  MJML email templates for all transactional emails.

  Each function returns `{subject, html_body, text_body}`.

  User-facing templates use Gettext so they render in the caller's locale
  (set by `StoryarnWeb.Plugs.Locale` from the Accept-Language header).
  Admin-only templates stay in English.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Emails.Layout

  @doc "Email change instructions."
  def update_email(email, url) do
    subject = dgettext("emails", "Update your email address")

    content = """
    <mj-text>
      #{dgettext("emails", "Hi %{email},", email: escape(email))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "You requested to change your email address. Click below to confirm the change.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Confirm email change")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "If you didn't request this change, please ignore this email.")}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi %{email},", email: email)}

    #{dgettext("emails", "You requested to change your email address. Confirm by visiting:")}

    #{url}

    #{dgettext("emails", "If you didn't request this change, please ignore this email.")}
    """

    {subject, Layout.render(content, preview: dgettext("emails", "Confirm your email change")), text}
  end

  @doc "Password reset instructions."
  def reset_password(email, url) do
    subject = dgettext("emails", "Reset your Storyarn password")

    content = """
    <mj-text>
      #{dgettext("emails", "Hi %{email},", email: escape(email))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "We received a request to reset your Storyarn password. Click below to choose a new one.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Reset password")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "This link expires in 24 hours. If you didn't request this, you can ignore this email.")}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi %{email},", email: email)}

    #{dgettext("emails", "We received a request to reset your Storyarn password. Choose a new password by visiting:")}

    #{url}

    #{dgettext("emails", "This link expires in 24 hours. If you didn't request this, you can ignore this email.")}
    """

    {subject, Layout.render(content, preview: dgettext("emails", "Choose a new Storyarn password")), text}
  end

  @doc "Project invitation email."
  def project_invitation(_email, project_name, inviter_name, role, url, days) do
    subject =
      dgettext("emails", "You've been invited to %{project}", project: project_name)

    content = """
    <mj-text>
      #{dgettext("emails", "Hi,")}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "<strong>%{inviter}</strong> has invited you to join <strong>%{project}</strong> on Storyarn as <strong>%{role}</strong>.", inviter: escape(inviter_name), project: escape(project_name), role: escape(role))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Click the button below to accept. You can then sign in or create a password for this email address.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Accept invitation")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{invitation_expiry_notice(days)}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi,")}

    #{dgettext("emails", "%{inviter} has invited you to join \"%{project}\" on Storyarn as %{role}.", inviter: inviter_name, project: project_name, role: role)}

    #{dgettext("emails", "Click the link below to accept. You can then sign in or create a password for this email address.")}

    #{dgettext("emails", "Accept by visiting:")} #{url}

    #{invitation_expiry_short(days)}
    #{dgettext("emails", "If you don't want to join, simply ignore this email.")}
    """

    preview =
      dgettext("emails", "%{inviter} invited you to %{project}",
        inviter: inviter_name,
        project: project_name
      )

    {subject, Layout.render(content, preview: preview), text}
  end

  @doc "Workspace invitation email."
  def workspace_invitation(_email, workspace_name, inviter_name, role, url, days) do
    subject =
      dgettext("emails", "You've been invited to %{workspace}", workspace: workspace_name)

    content = """
    <mj-text>
      #{dgettext("emails", "Hi,")}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "<strong>%{inviter}</strong> has invited you to join the <strong>%{workspace}</strong> workspace on Storyarn as <strong>%{role}</strong>.", inviter: escape(inviter_name), workspace: escape(workspace_name), role: escape(role))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Click the button below to accept. You can then sign in or create a password for this email address.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Accept invitation")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{invitation_expiry_notice(days)}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi,")}

    #{dgettext("emails", "%{inviter} has invited you to join the \"%{workspace}\" workspace on Storyarn as %{role}.", inviter: inviter_name, workspace: workspace_name, role: role)}

    #{dgettext("emails", "Click the link below to accept. You can then sign in or create a password for this email address.")}

    #{dgettext("emails", "Accept by visiting:")} #{url}

    #{invitation_expiry_short(days)}
    #{dgettext("emails", "If you don't want to join, simply ignore this email.")}
    """

    preview =
      dgettext("emails", "%{inviter} invited you to %{workspace}",
        inviter: inviter_name,
        workspace: workspace_name
      )

    {subject, Layout.render(content, preview: preview), text}
  end

  defp invitation_expiry_notice(days) do
    dngettext(
      "emails",
      "This invitation expires in %{count} day. If you don't want to join, simply ignore this email.",
      "This invitation expires in %{count} days. If you don't want to join, simply ignore this email.",
      days,
      count: days
    )
  end

  defp invitation_expiry_short(days) do
    dngettext(
      "emails",
      "This invitation expires in %{count} day.",
      "This invitation expires in %{count} days.",
      days,
      count: days
    )
  end

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape(text), do: escape(to_string(text))
end
