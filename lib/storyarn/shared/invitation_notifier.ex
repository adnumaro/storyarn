defmodule Storyarn.Shared.InvitationNotifier do
  @moduledoc """
  Generic invitation email delivery shared by Projects and Workspaces.

  Parameterized by the config map from `InvitationOperations`, which must
  additionally include:

    - `parent_assoc` — atom key to fetch parent name (e.g., `:project` or `:workspace`)
    - `template` — function name in `Storyarn.Emails.Templates` (e.g., `:project_invitation`)
    - `invitation_schema` — for `validity_in_days/0`
  """

  import Swoosh.Email
  require Logger

  alias Storyarn.Emails.Templates
  alias Storyarn.Mailer

  @doc """
  Delivers an invitation email using the config's template function.
  """
  def deliver_invitation(config, invitation, url, opts \\ []) do
    entity_name = invitation |> Map.fetch!(config.parent_assoc) |> Map.fetch!(:name)

    inviter_name =
      Keyword.get_lazy(opts, :inviter_name, fn ->
        case invitation.invited_by do
          nil -> "Storyarn"
          user -> user.display_name || user.email
        end
      end)

    days = config.invitation_schema.validity_in_days()

    {subject, html, text} =
      apply(Templates, config.template, [
        invitation.email,
        entity_name,
        inviter_name,
        invitation.role,
        url,
        days
      ])

    deliver(invitation.email, subject, html, text)
  end

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
end
