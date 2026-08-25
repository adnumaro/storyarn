defmodule Storyarn.Workspaces.Banner.Commands.Change do
  @moduledoc false

  import Ecto.Query

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Banner.Commands.Cleanup
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace
  alias Storyarn.Workspaces.WorkspaceMembership

  @spec persist(map(), pos_integer(), String.t() | nil, String.t() | nil, keyword()) ::
          {:ok, Workspace.t()} | {:error, term()}
  def persist(scope, workspace_id, banner_url, current_key, opts) do
    persist_banner_url(scope, workspace_id, banner_url, current_key, opts)
  rescue
    error -> {:error, {:workspace_banner_update_failed, error}}
  catch
    kind, reason -> {:error, {:workspace_banner_update_failed, {kind, reason}}}
  end

  defp persist_banner_url(scope, workspace_id, banner_url, current_key, opts) do
    Repo.transact(fn ->
      with {:ok, workspace} <- lock_authorized_workspace(scope, workspace_id),
           {:ok, updated_workspace} <- update_banner_url(workspace, banner_url),
           :ok <- Cleanup.schedule_previous(workspace, current_key, opts) do
        {:ok, updated_workspace}
      end
    end)
  end

  defp lock_authorized_workspace(%{user: %{id: user_id}}, workspace_id) do
    query =
      from(workspace in Workspace,
        join: membership in WorkspaceMembership,
        on: membership.workspace_id == workspace.id,
        where: workspace.id == ^workspace_id and membership.user_id == ^user_id,
        select: {workspace, membership},
        lock: "FOR UPDATE"
      )

    case Repo.one(query) do
      {%Workspace{} = workspace, %WorkspaceMembership{role: role}} ->
        if Memberships.can?(role, :manage_workspace),
          do: {:ok, workspace},
          else: {:error, :unauthorized}

      nil ->
        {:error, :unauthorized}
    end
  end

  defp update_banner_url(workspace, banner_url) do
    case workspace |> Workspace.banner_changeset(%{banner_url: banner_url}) |> Repo.update() do
      {:ok, updated_workspace} -> {:ok, updated_workspace}
      {:error, reason} -> {:error, {:workspace_banner_update_failed, reason}}
    end
  end
end
