defmodule Storyarn.Workspaces.Memberships.Queries.Members do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec list(integer()) :: [WorkspaceMembership.t()]
  def list(workspace_id) do
    WorkspaceMembership
    |> where([membership], membership.workspace_id == ^workspace_id)
    |> preload(:user)
    |> order_by([membership], asc: membership.inserted_at)
    |> Repo.all()
  end

  @spec get(Workspace.t() | integer(), %{id: integer()} | integer()) ::
          WorkspaceMembership.t() | nil
  def get(%Workspace{id: workspace_id}, %{id: user_id}) do
    get(workspace_id, user_id)
  end

  def get(workspace_id, user_id) when is_integer(workspace_id) and is_integer(user_id) do
    Repo.get_by(WorkspaceMembership, workspace_id: workspace_id, user_id: user_id)
  end
end
