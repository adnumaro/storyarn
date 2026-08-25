defmodule Storyarn.Accounts.UserEmail do
  @moduledoc """
  Account-owned content for transactional user emails.

  Platform supplies the shared visual layout; Accounts owns the intent, copy,
  and localization of account recovery and email-change messages.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Platform.Emails.Layout

  @doc "Renders email-change instructions."
  def update_email(email, url) do
    subject = dgettext("emails", "Update your email address")

    content = """
    <mj-text>
      #{dgettext("emails", "Hi %{email},", email: Layout.escape(email))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "You requested to change your email address. Click below to confirm the change.")}
    </mj-text>
    <mj-button href="#{Layout.escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Confirm email change")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "If you didn't request this change, please ignore this email.")}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: Layout.escape(url))}
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

  @doc "Renders password-reset instructions."
  def reset_password(email, url) do
    subject = dgettext("emails", "Reset your Storyarn password")

    content = """
    <mj-text>
      #{dgettext("emails", "Hi %{email},", email: Layout.escape(email))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "We received a request to reset your Storyarn password. Click below to choose a new one.")}
    </mj-text>
    <mj-button href="#{Layout.escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Reset password")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "This link expires in 24 hours. If you didn't request this, you can ignore this email.")}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: Layout.escape(url))}
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
end
