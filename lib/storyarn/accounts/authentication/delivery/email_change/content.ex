defmodule Storyarn.Accounts.Authentication.Delivery.EmailChange.Content do
  @moduledoc """
  Account-owned copy and localization for email-change instructions.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Platform.Emails.Layout

  @spec render(String.t(), String.t()) :: {String.t(), String.t(), String.t()}
  def render(email, url) do
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
end
