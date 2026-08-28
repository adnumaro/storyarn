defmodule Storyarn.Workspaces.Invitations.Delivery.Handler do
  @moduledoc false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Workspaces.Invitations.Adapters.Email.Mailer
  alias Storyarn.Workspaces.Invitations.Commands.Revoke
  alias Storyarn.Workspaces.Invitations.Delivery.Content
  alias Storyarn.Workspaces.Invitations.Queries.ByToken
  alias Storyarn.Workspaces.Invitations.Rules.Policy

  @invitation_path_prefix "/workspaces/invitations"

  def deliver(encoded_token, opts \\ []) do
    case ByToken.get(encoded_token) do
      {:ok, invitation} ->
        url = invitation_url(encoded_token)
        inviter_name = inviter_name(invitation, opts)
        days = Policy.remaining_days(invitation.expires_at, TimeHelpers.now())

        {subject, html, text} =
          Content.render(invitation.workspace.name, inviter_name, invitation.role, url, days)

        Mailer.deliver(invitation.email, subject, html, text)

      {:error, :invalid_token} ->
        {:cancel, :invitation_unavailable}
    end
  end

  def cancel(encoded_token) do
    case ByToken.get(encoded_token) do
      {:ok, invitation} -> Revoke.execute(invitation)
      {:error, :invalid_token} -> :ok
    end
  end

  defp invitation_url(token) do
    Storyarn.Platform.Urls.base_url() <> @invitation_path_prefix <> "/" <> token
  end

  defp inviter_name(invitation, opts) do
    Keyword.get_lazy(opts, :inviter_name, fn ->
      case invitation.invited_by do
        nil -> "Storyarn"
        user -> user.display_name || user.email
      end
    end)
  end
end
