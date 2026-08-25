defmodule Storyarn.Workspaces.Memberships.Queries.Authorize do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Memberships.Queries.Members
  alias Storyarn.Workspaces.Memberships.Rules.Permissions
  alias Storyarn.Workspaces.Workspace

  @spec call(%{user: %{id: integer()}}, integer(), atom()) ::
          {:ok, Workspace.t(), map()} | {:error, :not_found | :unauthorized}
  def call(%{user: user}, workspace_id, action) do
    with %Workspace{} = workspace <- Repo.get(Workspace, workspace_id),
         %{role: role} = membership <- Members.get(workspace_id, user.id),
         true <- Permissions.allowed?(role, action) do
      {:ok, workspace, membership}
    else
      nil -> {:error, :not_found}
      false -> {:error, :unauthorized}
    end
  end
end
