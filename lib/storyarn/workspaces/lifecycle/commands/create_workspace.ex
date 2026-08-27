defmodule Storyarn.Workspaces.Lifecycle.Commands.CreateWorkspace do
  @moduledoc false

  import Ecto.Query, warn: false

  alias Storyarn.Platform
  alias Storyarn.Repo
  alias Storyarn.Workspaces.Lifecycle.Events.WorkspaceCreated
  alias Storyarn.Workspaces.Lifecycle.Projections.UserRecord
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec create(%{user: %{id: integer()}}, map()) ::
          {:ok, Workspace.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_reached, map()}
  def create(%{user: user}, attrs), do: create_with_owner(user, attrs)

  @spec create_with_owner(%{id: integer()}, map()) ::
          {:ok, Workspace.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :limit_reached, map()}
  def create_with_owner(%{id: _} = user, attrs) do
    result =
      Repo.transact(fn ->
        locked_user =
          Repo.one!(from(candidate in UserRecord, where: candidate.id == ^user.id, lock: "FOR UPDATE"))

        with :ok <- normalize_workspace_capacity(Platform.can_create_workspace?(locked_user)),
             {:ok, workspace} <- insert_workspace(user, attrs),
             {:ok, _membership} <- create_owner_membership(workspace, user),
             {:ok, _subscription} <- Platform.create_subscription(workspace) do
          {:ok, workspace}
        end
      end)

    case result do
      {:ok, workspace} ->
        WorkspaceCreated.publish(user, workspace)
        {:ok, workspace}

      {:error, {:limit_reached, details}} ->
        {:error, :limit_reached, details}

      error ->
        error
    end
  end

  defp normalize_workspace_capacity(:ok), do: :ok

  defp normalize_workspace_capacity({:error, :limit_reached, details}) do
    {:error, {:limit_reached, details}}
  end

  defp insert_workspace(user, attrs) do
    %Workspace{owner_id: user.id}
    |> Workspace.create_changeset(attrs)
    |> Repo.insert()
  end

  defp create_owner_membership(workspace, user) do
    %WorkspaceMembership{}
    |> WorkspaceMembership.changeset(%{
      workspace_id: workspace.id,
      user_id: user.id,
      role: "owner"
    })
    |> Repo.insert()
  end
end
