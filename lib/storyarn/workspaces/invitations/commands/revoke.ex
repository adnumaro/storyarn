defmodule Storyarn.Workspaces.Invitations.Commands.Revoke do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform.Shared.TimeHelpers
  alias Storyarn.Repo
  alias Storyarn.Workspaces.WorkspaceInvitation

  def execute(%WorkspaceInvitation{} = invitation) do
    {deleted_count, _} =
      WorkspaceInvitation
      |> where([current], current.id == ^invitation.id)
      |> where([current], is_nil(current.accepted_at))
      |> where([current], current.expires_at > ^TimeHelpers.now())
      |> Repo.delete_all()

    if deleted_count == 1 do
      {:ok, invitation}
    else
      changeset =
        invitation
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:id, "is no longer pending")

      {:error, changeset}
    end
  end
end
