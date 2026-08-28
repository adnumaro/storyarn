defmodule Storyarn.Workspaces.Invitations.Rules.Acceptance do
  @moduledoc false

  alias Storyarn.Platform.Shared.TimeHelpers

  def validate(invitation, user) do
    cond do
      not is_nil(invitation.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(invitation.expires_at, TimeHelpers.now()) != :gt ->
        {:error, :expired}

      String.downcase(user.email) != String.downcase(invitation.email) ->
        {:error, :email_mismatch}

      true ->
        :ok
    end
  end

  def ensure_not_member(nil), do: :ok
  def ensure_not_member(_membership), do: {:error, :already_member}
end
