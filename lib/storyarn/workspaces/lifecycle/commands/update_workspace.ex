defmodule Storyarn.Workspaces.Lifecycle.Commands.UpdateWorkspace do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec update(map(), pos_integer(), map()) ::
          {:ok, Workspace.t()}
          | {:error, Ecto.Changeset.t() | :ownership_invariant_violation | :unauthorized}
  def update(%{user: %{id: user_id}}, workspace_id, attrs)
      when is_integer(user_id) and user_id > 0 and is_integer(workspace_id) and workspace_id > 0 and is_map(attrs) do
    Repo.transact(fn ->
      with {:ok, workspace} <- lock_workspace(workspace_id),
           :ok <- lock_and_authorize_owner(workspace, user_id) do
        workspace
        |> Workspace.update_changeset(attrs)
        |> Repo.update()
      end
    end)
  end

  def update(_scope, _workspace_id, _attrs), do: {:error, :unauthorized}

  defp lock_workspace(workspace_id) do
    query =
      from(workspace in Workspace,
        where: workspace.id == ^workspace_id,
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      %Workspace{} = workspace -> {:ok, workspace}
      nil -> {:error, :unauthorized}
    end
  end

  defp lock_and_authorize_owner(%Workspace{} = workspace, user_id) do
    query =
      from(membership in WorkspaceMembership,
        where: membership.workspace_id == ^workspace.id and membership.role == "owner",
        order_by: [asc: membership.user_id, asc: membership.id],
        lock: "FOR UPDATE"
      )

    case Repo.all(query) do
      [%WorkspaceMembership{user_id: owner_id}] when owner_id == workspace.owner_id ->
        if owner_id == user_id, do: :ok, else: {:error, :unauthorized}

      _missing_or_ambiguous_owner ->
        {:error, :ownership_invariant_violation}
    end
  end
end
