defmodule Storyarn.Emails.Templates do
  @moduledoc """
  MJML email templates for all transactional emails.

  Each function returns `{subject, html_body, text_body}`.

  User-facing templates use Gettext so they render in the caller's locale
  (set by `StoryarnWeb.Plugs.Locale` from the Accept-Language header).
  Admin-only templates (e.g. `admin_waitlist_signup`) stay in English.
  """

  use Gettext, backend: Storyarn.Gettext

  alias Storyarn.Emails.Layout

  @doc "Magic link login for existing users."
  def magic_link(email, url) do
    subject = dgettext("emails", "Log in to Storyarn")

    content = """
    <mj-text>
      #{dgettext("emails", "Hi %{email},", email: escape(email))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Click the button below to log in to your Storyarn account. This link will expire in 10 minutes.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Log in to Storyarn")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "If you didn't request this email, you can safely ignore it.")}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi %{email},", email: email)}

    #{dgettext("emails", "Log in to your Storyarn account by visiting this URL:")}

    #{url}

    #{dgettext("emails", "This link will expire in 10 minutes.")}
    #{dgettext("emails", "If you didn't request this email, you can safely ignore it.")}
    """

    {subject,
     Layout.render(content, preview: dgettext("emails", "Log in to your Storyarn account")), text}
  end

  @doc "Confirmation email for new users."
  def confirmation(email, url) do
    subject = dgettext("emails", "Confirm your Storyarn account")

    content = """
    <mj-text>
      #{dgettext("emails", "Welcome to Storyarn, %{email}!", email: escape(email))}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Click the button below to confirm your account and get started.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Confirm my account")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "If you didn't create an account, you can safely ignore this.")}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Welcome to Storyarn, %{email}!", email: email)}

    #{dgettext("emails", "Confirm your account by visiting this URL:")}

    #{url}

    #{dgettext("emails", "If you didn't create an account, you can safely ignore this.")}
    """

    {subject,
     Layout.render(content, preview: dgettext("emails", "Confirm your Storyarn account")), text}
  end

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

    {subject, Layout.render(content, preview: dgettext("emails", "Confirm your email change")),
     text}
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
      #{dgettext("emails", "Click the button below to accept. You'll be redirected to the login page where you can sign in with this email address.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Accept invitation")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "This invitation expires in %{days} days. If you don't want to join, simply ignore this email.", days: days)}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi,")}

    #{dgettext("emails", "%{inviter} has invited you to join \"%{project}\" on Storyarn as %{role}.", inviter: inviter_name, project: project_name, role: role)}

    #{dgettext("emails", "Click the link below to accept. You'll be redirected to the login page where you can sign in with this email address.")}

    #{dgettext("emails", "Accept by visiting:")} #{url}

    #{dgettext("emails", "This invitation expires in %{days} days.", days: days)}
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
      #{dgettext("emails", "Click the button below to accept. You'll be redirected to the login page where you can sign in with this email address.")}
    </mj-text>
    <mj-button href="#{escape(url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Accept invitation")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "This invitation expires in %{days} days. If you don't want to join, simply ignore this email.", days: days)}
    </mj-text>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Or copy this link: %{url}", url: escape(url))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "Hi,")}

    #{dgettext("emails", "%{inviter} has invited you to join the \"%{workspace}\" workspace on Storyarn as %{role}.", inviter: inviter_name, workspace: workspace_name, role: role)}

    #{dgettext("emails", "Click the link below to accept. You'll be redirected to the login page where you can sign in with this email address.")}

    #{dgettext("emails", "Accept by visiting:")} #{url}

    #{dgettext("emails", "This invitation expires in %{days} days.", days: days)}
    #{dgettext("emails", "If you don't want to join, simply ignore this email.")}
    """

    preview =
      dgettext("emails", "%{inviter} invited you to %{workspace}",
        inviter: inviter_name,
        workspace: workspace_name
      )

    {subject, Layout.render(content, preview: preview), text}
  end

  @doc "Waitlist invitation email — sent when a waitlist user gets access."
  def waitlist_invite(email, login_url) do
    subject = dgettext("emails", "You're in! Welcome to Storyarn")

    content = """
    <mj-text font-size="18px" font-weight="600" color="#f9fafb">
      #{dgettext("emails", "You're in!")}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Great news — your spot on the Storyarn waitlist has been activated. You now have full access to the platform.")}
    </mj-text>
    <mj-text>
      #{dgettext("emails", "Storyarn is a narrative design platform for game developers and interactive storytellers. Create character sheets, design dialogue flows, write screenplays, and build worlds.")}
    </mj-text>
    <mj-button href="#{escape(login_url)}" background-color="#4dd9c0" color="#0a0a0a">
      #{dgettext("emails", "Get started")}
    </mj-button>
    <mj-text font-size="13px" color="#9ca3af">
      #{dgettext("emails", "Just click the button above — you'll be able to log in with this email address (%{email}).", email: escape(email))}
    </mj-text>
    """

    text = """
    #{dgettext("emails", "You're in!")}

    #{dgettext("emails", "Great news — your spot on the Storyarn waitlist has been activated. You now have full access to the platform.")}

    #{dgettext("emails", "Get started:")} #{login_url}

    #{dgettext("emails", "You can log in with this email address (%{email}).", email: email)}
    """

    {subject,
     Layout.render(content, preview: dgettext("emails", "Your Storyarn access is ready")), text}
  end

  # --- Admin-only templates (no Gettext, always English) ---

  @doc "Admin notification when a user requests to invite someone to a project or workspace."
  def admin_invitation_request(request_info) do
    invitee_email = Map.fetch!(request_info, :invitee_email)
    requester_email = Map.fetch!(request_info, :requester_email)
    type = Map.fetch!(request_info, :type)
    entity_name = Map.fetch!(request_info, :entity_name)
    entity_id = Map.fetch!(request_info, :entity_id)
    role = Map.fetch!(request_info, :role)
    locale = Map.get(request_info, :locale, "en")

    type_label = if type == "project", do: "Project", else: "Workspace"

    # Sanitize values for shell command safety — strip anything that could break out of quotes
    safe_email = sanitize_for_shell(invitee_email)
    safe_role = sanitize_for_shell(role)
    safe_locale = sanitize_for_shell(locale)

    safe_requester = sanitize_for_shell(requester_email)

    command =
      ~s|fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_member(\\"#{safe_email}\\", \\"#{type}\\", #{entity_id}, \\"#{safe_role}\\", \\"#{safe_locale}\\", \\"#{safe_requester}\\")"'|

    subject = "Member invitation request: #{invitee_email} → #{entity_name}"

    content = """
    <mj-text font-size="18px" font-weight="600" color="#f9fafb">
      Member Invitation Request
    </mj-text>
    <mj-text>
      A user has requested to invite someone to their #{String.downcase(type_label)}:
    </mj-text>
    <mj-table font-size="13px" color="#d1d5db" cellpadding="4px">
      <tr><td style="color:#9ca3af;width:120px">Invitee</td><td><strong>#{escape(invitee_email)}</strong></td></tr>
      <tr><td style="color:#9ca3af">Requested by</td><td>#{escape(requester_email)}</td></tr>
      <tr><td style="color:#9ca3af">#{type_label}</td><td>#{escape(entity_name)} (ID: #{entity_id})</td></tr>
      <tr><td style="color:#9ca3af">Role</td><td>#{escape(role)}</td></tr>
      <tr><td style="color:#9ca3af">Locale</td><td>#{escape(locale)}</td></tr>
    </mj-table>
    <mj-text font-size="13px" color="#9ca3af" padding-top="16px">
      Accept with:<br/>
      <code>#{escape(command)}</code>
    </mj-text>
    """

    text = """
    Member Invitation Request

    Invitee: #{invitee_email}
    Requested by: #{requester_email}
    #{type_label}: #{entity_name} (ID: #{entity_id})
    Role: #{role}
    Locale: #{locale}

    Accept with:
    #{command}
    """

    {subject, Layout.render(content, preview: "Invitation request: #{invitee_email}"), text}
  end

  @doc "Admin notification when someone joins the waitlist."
  def admin_waitlist_signup(email, signup_info \\ %{}) do
    locale = Map.get(signup_info, :locale, "unknown")
    language = Map.get(signup_info, :accept_language, "unknown")
    ip = Map.get(signup_info, :ip, "unknown")
    country = Map.get(signup_info, :country, "unknown")

    safe_email = sanitize_for_shell(email)
    safe_locale = sanitize_for_shell(locale)

    subject = "New waitlist signup: #{email}"

    content = """
    <mj-text font-size="18px" font-weight="600" color="#f9fafb">
      New Waitlist Signup
    </mj-text>
    <mj-text>
      Someone just signed up for the Storyarn waitlist:
    </mj-text>
    <mj-text font-size="16px" font-weight="500" color="#d4a24c">
      #{escape(email)}
    </mj-text>
    <mj-table font-size="13px" color="#d1d5db" cellpadding="4px">
      <tr><td style="color:#9ca3af;width:100px">Language</td><td>#{escape(locale)} (#{escape(language)})</td></tr>
      <tr><td style="color:#9ca3af">Region</td><td>#{escape(country)}</td></tr>
      <tr><td style="color:#9ca3af">IP</td><td>#{escape(ip)}</td></tr>
    </mj-table>
    <mj-text font-size="13px" color="#9ca3af" padding-top="16px">
      Invite with:<br/>
      <code>fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_waitlist_user(\\"#{escape(safe_email)}\\", \\"#{escape(safe_locale)}\\")"'</code>
    </mj-text>
    """

    text = """
    New Waitlist Signup

    Email: #{email}
    Language: #{locale} (#{language})
    Region: #{country}
    IP: #{ip}

    Invite with:
    fly ssh console -a storyarn-staging -C '/app/bin/storyarn rpc "Storyarn.Release.invite_waitlist_user(\\"#{safe_email}\\", \\"#{safe_locale}\\")"'
    """

    {subject, Layout.render(content, preview: "New waitlist signup: #{email}"), text}
  end

  defp escape(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape(text), do: escape(to_string(text))

  # Strip shell-dangerous characters from values embedded in CLI commands
  defp sanitize_for_shell(text) when is_binary(text) do
    String.replace(text, ~r/[^a-zA-Z0-9@._\-+]/, "")
  end

  defp sanitize_for_shell(text), do: sanitize_for_shell(to_string(text))
end
