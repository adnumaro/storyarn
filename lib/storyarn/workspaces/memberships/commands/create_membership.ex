defmodule Storyarn.Workspaces.Memberships.Commands.CreateMembership do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec create(integer(), integer(), String.t()) ::
          {:ok, WorkspaceMembership.t()} | {:error, Ecto.Changeset.t()}
  def create(workspace_id, user_id, role) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace_id,
      user_id: user_id,
      role: role
    })
    |> Repo.insert()
  end
end
