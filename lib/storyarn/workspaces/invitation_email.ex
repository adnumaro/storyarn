defmodule Storyarn.Workspaces.InvitationEmail do
  @moduledoc """
  Workspace-owned invitation email content.

  Workspaces owns the invitation intent, copy, and localization. Platform only
  supplies the shared technical email layout.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Platform.Emails.Layout

  @doc "Renders a workspace invitation email."
  def render(workspace_name, inviter_name, role, url, days) do
    subject =
      dgettext("emails", "You've been invited to %{workspace}", workspace: workspace_name)

    content = """
    <mj-text>
      #{dgettext("emails", "Hi,")}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "<strong>%{inviter}</strong> has invited you to join the <strong>%{workspace}</strong> workspace on Storyarn as <strong>%{role}</strong>.", inviter: Layout.escape(inviter_name), workspace: Layout.escape(workspace_name), role: Layout.escape(role))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Click the button below to accept. You can then sign in or create a password for this email address.")}
    </mj-text>
    <mj-button href="#{Layout.escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Accept invitation")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{invitation_expiry_notice(days)}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: Layout.escape(url))}
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
end
