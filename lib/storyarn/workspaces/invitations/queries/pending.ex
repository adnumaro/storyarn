defmodule Storyarn.Workspaces.Invitations.Queries.Pending do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.WorkspaceInvitation

  def list(workspace_id) do
    WorkspaceInvitation
    |> where([invitation], invitation.workspace_id == ^workspace_id)
    |> where([invitation], is_nil(invitation.accepted_at))
    |> where([invitation], invitation.expires_at > ^TimeHelpers.now())
    |> preload(:invited_by)
    |> order_by([invitation], desc: invitation.updated_at)
    |> Repo.all()
  end

  def get(id) do
    WorkspaceInvitation
    |> where([invitation], invitation.id == ^id)
    |> where([invitation], is_nil(invitation.accepted_at))
    |> where([invitation], invitation.expires_at > ^TimeHelpers.now())
    |> Repo.one()
  end

  def exists?(workspace_id, email) do
    Repo.exists?(
      from(invitation in WorkspaceInvitation,
        where: invitation.workspace_id == ^workspace_id,
        where: fragment("lower(?)", invitation.email) == ^email,
        where: is_nil(invitation.accepted_at),
        where: invitation.expires_at > ^TimeHelpers.now()
      )
    )
  end
end
