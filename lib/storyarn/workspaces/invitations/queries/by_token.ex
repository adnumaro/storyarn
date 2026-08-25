defmodule Storyarn.Workspaces.Invitations.Queries.ByToken do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Invitations.Tokens.Issuer
  alias Storyarn.Workspaces.WorkspaceInvitation

  def get(token) do
    case Issuer.decode_and_hash(token) do
      {:ok, hashed_token} ->
        query =
          from(invitation in WorkspaceInvitation,
            where: invitation.token == ^hashed_token,
            where: invitation.expires_at > ^TimeHelpers.now(),
            where: is_nil(invitation.accepted_at),
            preload: [:workspace, :invited_by]
          )

        case Repo.one(query) do
          nil -> {:error, :invalid_token}
          invitation -> {:ok, invitation}
        end

      :error ->
        {:error, :invalid_token}
    end
  end
end
