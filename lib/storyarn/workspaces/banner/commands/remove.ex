defmodule Storyarn.Workspaces.Banner.Commands.Remove do
  @moduledoc false

  alias Storyarn.Workspaces.Banner.Commands.Change
  alias Storyarn.Workspaces.Memberships

  @spec execute(map(), pos_integer(), keyword()) :: {:ok, map()} | {:error, term()}
  def execute(scope, workspace_id, opts \\ [])

  def execute(%{user: %{id: user_id}} = scope, workspace_id, opts)
      when is_integer(user_id) and is_integer(workspace_id) and workspace_id > 0 and is_list(opts) do
    with {:ok, _workspace, _membership} <- Memberships.authorize(scope, workspace_id, :manage_workspace) do
      Change.persist(scope, workspace_id, nil, nil, opts)
    end
  end

  def execute(_scope, _workspace_id, _opts), do: {:error, :unauthorized}
end
