defmodule Storyarn.Workspaces.Banner.Commands.Change do
  @moduledoc false

  alias Storyarn.Repo
  alias Storyarn.Workspaces.Banner.Commands.Cleanup
  alias Storyarn.Workspaces.Memberships
  alias Storyarn.Workspaces.Workspace

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
    Memberships.transact_as_owner(scope, workspace_id, fn %{workspace: workspace} ->
      with {:ok, updated_workspace} <- update_banner_url(workspace, banner_url),
           :ok <- Cleanup.schedule_previous(workspace, current_key, opts) do
        {:ok, updated_workspace}
      end
    end)
  end

  defp update_banner_url(workspace, banner_url) do
    case workspace |> Workspace.banner_changeset(%{banner_url: banner_url}) |> Repo.update() do
      {:ok, updated_workspace} -> {:ok, updated_workspace}
      {:error, reason} -> {:error, {:workspace_banner_update_failed, reason}}
    end
  end
end
