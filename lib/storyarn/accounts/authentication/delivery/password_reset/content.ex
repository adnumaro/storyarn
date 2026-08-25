defmodule Storyarn.Accounts.Authentication.Delivery.PasswordReset.Content do
  @moduledoc """
  Account-owned copy and localization for password-reset instructions.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Platform.Emails.Layout

  @spec render(String.t(), String.t()) :: {String.t(), String.t(), String.t()}
  def render(email, url) do
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
