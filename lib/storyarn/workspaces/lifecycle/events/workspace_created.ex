defmodule Storyarn.Workspaces.Lifecycle.Events.WorkspaceCreated do
  @moduledoc false

  alias Storyarn.Platform
  alias Storyarn.Workspaces.Workspace

  @spec publish(term(), Workspace.t()) :: :ok
  def publish(scope_or_user, %Workspace{id: workspace_id}) when is_integer(workspace_id) and workspace_id > 0 do
    Platform.react_to_event(scope_or_user, :workspaces, :workspace_created, %{
      workspace_id: workspace_id
    })
  end

  def publish(_scope_or_user, _workspace), do: :ok
end
